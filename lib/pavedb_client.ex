# (C) 2026 Rodrigo Rodrigues da Silva <rodrigo@flowlexi.com>
# SPDX-License-Identifier: Apache-2.0

defmodule PaveDBClient do
  @moduledoc """
  Elixir client for PaveDB's HTTP API.
  """

  alias PaveDBClient.Client
  alias PaveDBClient.Collection
  alias PaveDBClient.Error

  @default_url "http://localhost:8086"

  @doc """
  Returns the package version.
  """
  def version do
    "0.1.0"
  end

  @doc """
  Builds a client for a running PaveDB HTTP server.
  """
  @spec connect(String.t() | nil, keyword()) :: Client.t()
  def connect(base_url \\ nil, opts \\ [])

  def connect(opts, []) when is_list(opts) do
    connect(nil, opts)
  end

  def connect(base_url, opts) do
    base_url = base_url || System.get_env("PAVEDB_URL", @default_url)
    Client.new(base_url, opts)
  end

  @doc """
  Alias for `connect/2`.
  """
  @spec new(String.t() | nil, keyword()) :: Client.t()
  def new(base_url \\ nil, opts \\ [])

  def new(opts, []) when is_list(opts) do
    connect(nil, opts)
  end

  def new(base_url, opts), do: connect(base_url, opts)

  @doc """
  Builds a tenant-scoped collection handle without making a request.
  """
  @spec collection(Client.t(), String.t(), keyword()) :: Collection.t()
  def collection(%Client{} = client, name, opts \\ []) do
    tenant = Keyword.get(opts, :tenant, client.tenant)
    %Collection{client: client, tenant: tenant, name: name}
  end

  @doc """
  Creates a collection and returns a collection handle.
  """
  @spec create_collection(Client.t(), String.t(), keyword()) ::
          {:ok, Collection.t()} | {:error, Error.t()}
  def create_collection(%Client{} = client, name, opts \\ []) do
    tenant = Keyword.get(opts, :tenant, client.tenant)
    attrs = Keyword.take(opts, collection_attr_keys())

    case create_collection(client, tenant, name, attrs) do
      {:ok, _response} -> {:ok, collection(client, name, tenant: tenant)}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Creates or configures a tenant collection.
  """
  @spec create_collection(Client.t(), String.t(), String.t(), map() | keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def create_collection(%Client{} = client, tenant, name, attrs) do
    body =
      attrs
      |> Enum.into(%{})
      |> Map.take(collection_attr_keys())
      |> strip_nil()

    Client.request_json(
      client,
      :post,
      "/collections/#{segment(tenant)}/#{segment(name)}",
      body
    )
  end

  @doc """
  Adds one raw text document to a collection.
  """
  @spec add_text(Client.t(), String.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def add_text(%Client{} = client, tenant, collection, text, opts \\ []) do
    body =
      %{
        "text" => text,
        "docid" => Keyword.get(opts, :docid),
        "metadata" => Keyword.get(opts, :metadata)
      }
      |> strip_nil()

    Client.request_json(
      client,
      :post,
      "/collections/#{segment(tenant)}/#{segment(collection)}/documents",
      body
    )
  end

  @doc """
  Adds several raw text documents to a collection.

  Each item may be a string, a map with `text`, `docid`, and `metadata`, or
  `{text, docid, metadata}`.
  """
  @spec add_many(Client.t(), String.t(), String.t(), list()) ::
          {:ok, map()} | {:error, Error.t()}
  def add_many(%Client{} = client, tenant, collection, documents) do
    with {:ok, items} <- batch_items(documents) do
      Client.request_json(
        client,
        :post,
        "/collections/#{segment(tenant)}/#{segment(collection)}/documents:batch",
        %{"documents" => items}
      )
    end
  end

  @doc """
  Uploads a local file to a collection.
  """
  @spec ingest_file(Client.t(), String.t(), String.t(), Path.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def ingest_file(%Client{} = client, tenant, collection, path, opts \\ []) do
    with {:ok, file} <- File.read(path) do
      query = ingest_query(opts)
      boundary = "pavedb-client-#{System.unique_integer([:positive])}"
      endpoint = "/collections/#{segment(tenant)}/#{segment(collection)}/documents"
      content_type = "multipart/form-data; boundary=#{boundary}"

      Client.request(
        client,
        :post,
        endpoint <> query,
        multipart_body(boundary, multipart_parts(path, file, opts)),
        content_type: content_type
      )
    else
      {:error, reason} ->
        {:error,
         %Error{
           code: "file_read_failed",
           message: "could not read #{path}: #{:file.format_error(reason)}"
         }}
    end
  end

  @doc """
  Searches a collection and returns the full PaveDB response envelope.
  """
  @spec search(Client.t(), String.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def search(%Client{} = client, tenant, collection, q, opts \\ []) do
    body =
      %{
        "q" => q,
        "k" => Keyword.get(opts, :k, 5),
        "filters" => Keyword.get(opts, :filters),
        "include_common" => Keyword.get(opts, :include_common)
      }
      |> strip_nil()

    Client.request_json(
      client,
      :post,
      "/collections/#{segment(tenant)}/#{segment(collection)}/search",
      body
    )
  end

  @doc """
  Lists documents in a collection.
  """
  @spec list_documents(Client.t(), String.t(), String.t()) ::
          {:ok, list(map())} | {:error, Error.t()}
  def list_documents(%Client{} = client, tenant, collection) do
    case Client.request(
           client,
           :get,
           "/collections/#{segment(tenant)}/#{segment(collection)}/documents"
         ) do
      {:ok, %{"documents" => documents}} when is_list(documents) ->
        {:ok, documents}

      {:ok, _response} ->
        {:error,
         %Error{
           code: "invalid_response",
           message: "server response is missing documents"
         }}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Fetches one document by id.
  """
  @spec get_document(Client.t(), String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def get_document(%Client{} = client, tenant, collection, docid) do
    Client.request(
      client,
      :get,
      "/collections/#{segment(tenant)}/#{segment(collection)}/documents/" <>
        segment(docid)
    )
  end

  @doc """
  Deletes one document by id.
  """
  @spec delete_document(Client.t(), String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def delete_document(%Client{} = client, tenant, collection, docid) do
    Client.request(
      client,
      :delete,
      "/collections/#{segment(tenant)}/#{segment(collection)}/documents/" <>
        segment(docid)
    )
  end

  @doc """
  Formats a structured client error for logs or operator messages.
  """
  @spec format_error(Error.t() | term()) :: String.t()
  def format_error(%Error{status: status, message: message}) when is_integer(status),
    do: "PaveDB HTTP #{status}: #{message}"

  def format_error(%Error{message: message}), do: message
  def format_error(other), do: inspect(other)

  @doc false
  def segment(value), do: value |> to_string() |> URI.encode(&URI.char_unreserved?/1)

  @doc false
  def strip_nil(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) end)
  end

  defp collection_attr_keys do
    [
      :display_name,
      :embedder_type,
      :embed_model,
      :embedder_config,
      "display_name",
      "embedder_type",
      "embed_model",
      "embedder_config"
    ]
  end

  defp batch_items(documents) when is_list(documents) do
    documents
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case batch_item(item) do
        {:ok, mapped} -> {:cont, {:ok, [mapped | acc]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      {:error, error} -> {:error, error}
    end
  end

  defp batch_items(_documents) do
    {:error,
     %Error{
       code: "invalid_batch",
       message: "documents must be a list"
     }}
  end

  defp batch_item(text) when is_binary(text), do: {:ok, %{"text" => text}}

  defp batch_item(%{} = item) do
    {:ok,
     %{
       "text" => Map.get(item, "text") || Map.get(item, :text),
       "docid" => Map.get(item, "docid") || Map.get(item, :docid),
       "metadata" => Map.get(item, "metadata") || Map.get(item, :metadata)
     }
     |> strip_nil()}
  end

  defp batch_item({text, docid, metadata}) do
    {:ok, %{"text" => text, "docid" => docid, "metadata" => metadata} |> strip_nil()}
  end

  defp batch_item({text, docid}) do
    {:ok, %{"text" => text, "docid" => docid} |> strip_nil()}
  end

  defp batch_item({text}), do: {:ok, %{"text" => text}}

  defp batch_item(_item) do
    {:error,
     %Error{
       code: "invalid_batch_item",
       message: "batch items must be text, {text, docid, metadata}, or a map"
     }}
  end

  defp ingest_query(opts) do
    opts
    |> Keyword.get(:csv_options, %{})
    |> Kernel.||(%{})
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      query_key = csv_query_key(key)

      if query_key && present?(value) do
        Map.put(acc, query_key, query_value(value))
      else
        acc
      end
    end)
    |> URI.encode_query()
    |> case do
      "" -> ""
      query -> "?" <> query
    end
  end

  defp csv_query_key(:has_header), do: "csv_has_header"
  defp csv_query_key("has_header"), do: "csv_has_header"
  defp csv_query_key(:meta_cols), do: "csv_meta_cols"
  defp csv_query_key("meta_cols"), do: "csv_meta_cols"
  defp csv_query_key(:include_cols), do: "csv_include_cols"
  defp csv_query_key("include_cols"), do: "csv_include_cols"
  defp csv_query_key(:csv_has_header), do: "csv_has_header"
  defp csv_query_key("csv_has_header"), do: "csv_has_header"
  defp csv_query_key(:csv_meta_cols), do: "csv_meta_cols"
  defp csv_query_key("csv_meta_cols"), do: "csv_meta_cols"
  defp csv_query_key(:csv_include_cols), do: "csv_include_cols"
  defp csv_query_key("csv_include_cols"), do: "csv_include_cols"
  defp csv_query_key(_key), do: nil

  defp query_value(value) when is_list(value), do: Enum.join(value, ",")
  defp query_value(value), do: to_string(value)

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(_value), do: true

  defp multipart_parts(path, file, opts) do
    []
    |> maybe_part("metadata", metadata_json(Keyword.get(opts, :metadata)))
    |> maybe_part("docid", Keyword.get(opts, :docid))
    |> Kernel.++([
      %{
        name: "file",
        filename: Path.basename(path),
        content_type: Keyword.get(opts, :content_type, content_type(path)),
        body: file
      }
    ])
  end

  defp maybe_part(parts, _name, nil), do: parts
  defp maybe_part(parts, _name, ""), do: parts
  defp maybe_part(parts, name, body), do: parts ++ [%{name: name, body: body}]

  defp metadata_json(nil), do: nil
  defp metadata_json(metadata) when is_binary(metadata), do: metadata
  defp metadata_json(metadata), do: PaveDBClient.JSON.encode!(metadata)

  defp multipart_body(boundary, parts) do
    body =
      Enum.map(parts, fn part ->
        [
          "--#{boundary}\r\n",
          disposition(part),
          content_type_header(part),
          "\r\n",
          part.body,
          "\r\n"
        ]
      end)

    IO.iodata_to_binary([body, "--#{boundary}--\r\n"])
  end

  defp disposition(%{filename: filename, name: name}) do
    "Content-Disposition: form-data; name=\"#{name}\"; " <>
      "filename=\"#{filename}\"\r\n"
  end

  defp disposition(%{name: name}) do
    "Content-Disposition: form-data; name=\"#{name}\"\r\n"
  end

  defp content_type_header(%{content_type: content_type}) do
    "Content-Type: #{content_type}\r\n"
  end

  defp content_type_header(_part), do: ""

  defp content_type(path) do
    case Path.extname(path) do
      ".csv" -> "text/csv"
      ".json" -> "application/json"
      ".txt" -> "text/plain"
      _ -> "application/octet-stream"
    end
  end
end
