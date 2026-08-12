# (C) 2026 Rodrigo Rodrigues da Silva <rodrigo@flowlexi.com>
# SPDX-License-Identifier: Apache-2.0

defmodule PaveDBClient.Client do
  @moduledoc """
  HTTP transport for PaveDB.
  """

  alias PaveDBClient.Error

  @default_timeout 30_000
  @default_connect_timeout 5_000

  defstruct base_url: nil,
            tenant: "default",
            token: nil,
            headers: [],
            transport: nil,
            timeout: @default_timeout,
            connect_timeout: @default_connect_timeout

  @type t :: %__MODULE__{
          base_url: String.t(),
          tenant: String.t(),
          token: String.t() | nil,
          headers: [{String.t(), String.t()}],
          transport: transport() | nil,
          timeout: timeout(),
          connect_timeout: timeout()
        }

  @typedoc """
  Replacement HTTP sender, called as `transport.(method, path, headers, body)`.
  """
  @type transport ::
          (atom(), String.t(), [{String.t(), String.t()}], binary() ->
             {:ok, non_neg_integer(), list(), binary()} | {:error, term()})

  @doc """
  Builds a client struct. Prefer `PaveDBClient.connect/2`, which fills the
  base URL in from `PAVEDB_URL`.

  Takes `:tenant`, `:token` (or `:api_key`), `:headers`, `:timeout`,
  `:connect_timeout`, and `:transport`. A base URL already ending in `/v1` is
  used as-is.
  """
  @spec new(String.t(), keyword()) :: t()
  def new(base_url, opts \\ []) do
    token =
      Keyword.get(opts, :token) ||
        Keyword.get(opts, :api_key) ||
        System.get_env("PAVEDB_TOKEN")

    %__MODULE__{
      base_url: String.trim_trailing(base_url, "/"),
      tenant: Keyword.get(opts, :tenant, "default"),
      token: blank_to_nil(token),
      headers: Keyword.get(opts, :headers, []),
      transport: Keyword.get(opts, :transport),
      timeout: Keyword.get(opts, :timeout, @default_timeout),
      connect_timeout: Keyword.get(opts, :connect_timeout, @default_connect_timeout)
    }
  end

  @doc """
  Sends `body` as JSON and decodes the response envelope.
  """
  @spec request_json(t(), atom(), String.t(), map()) ::
          {:ok, map()} | {:error, Error.t()}
  def request_json(%__MODULE__{} = client, method, path, body) do
    case PaveDBClient.JSON.encode(body) do
      {:ok, encoded} ->
        request(client, method, path, encoded, content_type: "application/json")

      {:error, _reason} ->
        {:error,
         %Error{
           code: "invalid_body",
           message: "request body cannot be encoded as JSON",
           body: body
         }}
    end
  end

  @doc """
  Sends a request with an empty body and decodes the response envelope.

  Pass `root: true` for endpoints outside the `/v1` API, such as `/health`.
  """
  @spec request(t(), atom(), String.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def request(%__MODULE__{} = client, method, path, opts \\ []) do
    request(client, method, path, "", opts)
  end

  @doc """
  Sends a request with `body` and decodes the response envelope.

  Takes `:content_type` and `:root`.
  """
  @spec request(t(), atom(), String.t(), iodata(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def request(%__MODULE__{} = client, method, path, body, opts) do
    headers = headers(client)
    content_type = Keyword.get(opts, :content_type)
    root = Keyword.get(opts, :root, false)

    with {:ok, status, _headers, response_body} <-
           send_request(client, method, root, path, headers, content_type, body) do
      decode(status, response_body)
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, reason} -> {:error, transport_error(reason)}
    end
  end

  @doc """
  Sends a request and returns the undecoded response body on success.

  Used for endpoints that answer with a raw body (for example chunk content)
  instead of the usual JSON envelope. Non-2xx responses still decode into a
  structured `Error`.
  """
  @spec request_raw(t(), atom(), String.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def request_raw(%__MODULE__{} = client, method, path, opts \\ []) do
    headers = headers(client)
    root = Keyword.get(opts, :root, false)

    with {:ok, status, response_headers, response_body} <-
           send_request(client, method, root, path, headers, nil, "") do
      if status in 200..299 do
        {:ok, %{status: status, headers: response_headers, body: response_body}}
      else
        decode(status, response_body)
      end
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, reason} -> {:error, transport_error(reason)}
    end
  end

  defp send_request(
         %{transport: transport} = client,
         method,
         root,
         path,
         headers,
         _type,
         body
       )
       when is_function(transport, 4) do
    transport.(method, path_prefix(client, root) <> path, headers, IO.iodata_to_binary(body))
  end

  defp send_request(client, method, root, path, headers, content_type, body) do
    # :ssl is not a dependency of :inets, so https URLs fail with
    # :ssl_not_started unless it is running before the first request.
    {:ok, _apps} = Application.ensure_all_started([:inets, :ssl])

    url = String.to_charlist(target_url(client, root, path))

    http_headers =
      Enum.map(headers, fn {key, value} ->
        {to_charlist(key), to_charlist(value)}
      end)

    request =
      case {method, content_type} do
        {:get, _type} ->
          {url, http_headers}

        {:delete, _type} ->
          {url, http_headers}

        {_method, nil} ->
          {url, http_headers, ~c"application/octet-stream", body}

        {_method, type} ->
          {url, http_headers, to_charlist(type), body}
      end

    http_options = [
      timeout: client.timeout,
      connect_timeout: client.connect_timeout
    ]

    case :httpc.request(method, request, http_options, body_format: :binary) do
      {:ok, {{_version, status, _reason}, response_headers, response_body}} ->
        {:ok, status, response_headers, response_body}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode(status, body) when status in 200..299 do
    decode_success(body)
  end

  # PaveDB answers every failure with {ok, code, error, details?} plus the
  # trace fields. Bodies that miss it (proxies, non-JSON) keep the status.
  defp decode(status, body) do
    payload =
      case PaveDBClient.JSON.decode(body) do
        {:ok, %{"code" => _code} = data} -> data
        _other -> %{"code" => "http_#{status}", "error" => body}
      end

    {:error,
     %Error{
       code: to_string(payload["code"]),
       message: to_string(payload["error"] || "PaveDB error"),
       status: status,
       details: payload["details"],
       body: payload
     }}
  end

  defp decode_success(""), do: {:ok, %{}}

  defp decode_success(body) do
    case PaveDBClient.JSON.decode(body) do
      # The HTTP status decides success, so `ok` carries nothing extra. On
      # `/health` it can be false on a 200 while `status` says "degraded".
      {:ok, %{} = data} ->
        {:ok, Map.delete(data, "ok")}

      {:ok, _other} ->
        {:error,
         %Error{
           code: "invalid_response",
           message: "server returned non-object JSON",
           body: body
         }}

      {:error, message} ->
        {:error,
         %Error{
           code: "invalid_response",
           message: "server returned invalid JSON: #{message}",
           body: body
         }}
    end
  end

  defp transport_error(reason) do
    %Error{
      code: "request_failed",
      message: "PaveDB request failed: #{inspect(reason)}",
      body: reason
    }
  end

  defp headers(client) do
    client.headers ++ auth_headers(client.token)
  end

  defp auth_headers(nil), do: []
  defp auth_headers(token), do: [{"authorization", "Bearer #{token}"}]

  defp prefix(%{base_url: base_url}) do
    if String.ends_with?(base_url, "/v1"), do: "", else: "/v1"
  end

  @doc false
  @spec target_url(t(), boolean(), String.t()) :: String.t()
  def target_url(%__MODULE__{} = client, root, path) do
    base_url(client, root) <> path_prefix(client, root) <> path
  end

  # Root-scoped requests (for example `/health`) target the server origin,
  # so any `/v1` carried in the configured base URL is dropped as well.
  defp base_url(%{base_url: base_url}, true), do: String.replace_suffix(base_url, "/v1", "")
  defp base_url(%{base_url: base_url}, false), do: base_url

  defp path_prefix(_client, true), do: ""
  defp path_prefix(client, false), do: prefix(client)

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
