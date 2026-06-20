# (C) 2026 Rodrigo Rodrigues da Silva <rodrigo@flowlexi.com>
# SPDX-License-Identifier: Apache-2.0

defmodule PaveDBClient.Client do
  @moduledoc """
  HTTP transport for PaveDB.
  """

  alias PaveDBClient.Error

  defstruct base_url: nil,
            tenant: "default",
            token: nil,
            headers: [],
            transport: nil

  @type t :: %__MODULE__{
          base_url: String.t(),
          tenant: String.t(),
          token: String.t() | nil,
          headers: [{String.t(), String.t()}],
          transport: function() | nil
        }

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
      transport: Keyword.get(opts, :transport)
    }
  end

  @spec request_json(t(), atom(), String.t(), map()) ::
          {:ok, map()} | {:error, Error.t()}
  def request_json(%__MODULE__{} = client, method, path, body) do
    request(
      client,
      method,
      path,
      PaveDBClient.JSON.encode!(body),
      content_type: "application/json"
    )
  end

  @spec request(t(), atom(), String.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def request(%__MODULE__{} = client, method, path, opts \\ []) do
    request(client, method, path, "", opts)
  end

  @spec request(t(), atom(), String.t(), iodata(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def request(%__MODULE__{} = client, method, path, body, opts) do
    headers = headers(client)
    content_type = Keyword.get(opts, :content_type)

    with {:ok, status, _headers, response_body} <-
           send_request(client, method, path, headers, content_type, body) do
      decode(status, response_body)
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, reason} -> {:error, transport_error(reason)}
    end
  end

  defp send_request(
         %{transport: transport} = client,
         method,
         path,
         headers,
         _type,
         body
       )
       when is_function(transport, 4) do
    transport.(method, prefix(client) <> path, headers, IO.iodata_to_binary(body))
  end

  defp send_request(client, method, path, headers, content_type, body) do
    {:ok, _apps} = Application.ensure_all_started(:inets)

    url = String.to_charlist(client.base_url <> prefix(client) <> path)

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

    case :httpc.request(method, request, [], body_format: :binary) do
      {:ok, {{_version, status, _reason}, response_headers, response_body}} ->
        {:ok, status, response_headers, response_body}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode(status, body) when status in 200..299 do
    decode_success(body)
  end

  defp decode(status, body) do
    payload =
      case PaveDBClient.JSON.decode(body) do
        {:ok, %{} = data} -> normalize_error_payload(data)
        _other -> %{"code" => "http_#{status}", "error" => body}
      end

    {:error,
     %Error{
       code: to_string(payload["code"] || "pavedb_error"),
       message: to_string(payload["error"] || payload["message"] || "PaveDB error"),
       status: status,
       type: payload["error_type"],
       body: payload
     }}
  end

  defp decode_success(""), do: {:ok, %{}}

  defp decode_success(body) do
    case PaveDBClient.JSON.decode(body) do
      {:ok, %{} = data} ->
        if data["ok"] == false do
          decode(500, body)
        else
          {:ok, Map.delete(data, "ok")}
        end

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

  defp normalize_error_payload(%{"detail" => %{} = detail}), do: detail
  defp normalize_error_payload(payload), do: payload

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

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
