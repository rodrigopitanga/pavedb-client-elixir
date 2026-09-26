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
  @version Mix.Project.config()[:version]

  @doc """
  Returns the package version.
  """
  @spec version() :: String.t()
  def version, do: @version

  @doc """
  Builds a client for a running PaveDB HTTP server.

  The base URL falls back to `PAVEDB_URL`, then to `#{@default_url}`. See
  `PaveDBClient.Client.new/2` for the options.
  """
  @spec connect(String.t() | nil, keyword()) :: Client.t()
  def connect(base_url \\ nil, opts \\ [])

  def connect(opts, []) when is_list(opts) do
    connect(nil, opts)
  end

  def connect(base_url, opts) when is_binary(base_url) or is_nil(base_url) do
    base_url = base_url || System.get_env("PAVEDB_URL", @default_url)
    Client.new(base_url, opts)
  end

  @doc """
  Alias for `connect/2`.
  """
  @spec new(String.t() | nil, keyword()) :: Client.t()
  def new(base_url \\ nil, opts \\ []), do: connect(base_url, opts)

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

  Options include `:display_name`, `:embedder`, `:embedder_type`,
  `:embed_model`, `:embedder_config`, `:search_mode`, `:chunking`, and
  `:priority_key`.
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
  Creates or configures a tenant collection with the same settings as
  `create_collection/3`.
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
    add_document(client, tenant, collection, %{"text" => text}, opts)
  end

  @doc """
  Adds one precomputed embedding to a collection.

  PaveDB takes either text or a raw vector, never both.
  """
  @spec add_vector(Client.t(), String.t(), String.t(), list(number()), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def add_vector(%Client{} = client, tenant, collection, vector, opts \\ []) do
    add_document(client, tenant, collection, %{"vector" => vector}, opts)
  end

  defp add_document(client, tenant, collection, content, opts) do
    body =
      content
      |> Map.merge(%{
        "docid" => Keyword.get(opts, :docid),
        "metadata" => Keyword.get(opts, :metadata)
      })
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

  Each item may be a string, a map with `text` or `vector` plus `docid` and
  `metadata`, or `{text, docid, metadata}`.
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
    with {:ok, file} <- read_file(path),
         {:ok, metadata} <- encode_metadata(Keyword.get(opts, :metadata)) do
      boundary = boundary()
      endpoint = "/collections/#{segment(tenant)}/#{segment(collection)}/documents"

      Client.request(
        client,
        :post,
        endpoint <> ingest_query(opts),
        multipart_body(boundary, multipart_parts(path, file, metadata, opts)),
        content_type: "multipart/form-data; boundary=#{boundary}"
      )
    end
  end

  defp read_file(path) do
    case File.read(path) do
      {:ok, file} ->
        {:ok, file}

      {:error, reason} ->
        {:error,
         %Error{
           code: "file_read_failed",
           message: "could not read #{path}: #{:file.format_error(reason)}"
         }}
    end
  end

  defp encode_metadata(nil), do: {:ok, nil}
  defp encode_metadata(metadata) when is_binary(metadata), do: {:ok, metadata}

  defp encode_metadata(metadata) do
    case PaveDBClient.JSON.encode(metadata) do
      {:ok, json} ->
        {:ok, json}

      {:error, _reason} ->
        {:error,
         %Error{
           code: "invalid_metadata",
           message: "metadata cannot be encoded as JSON"
         }}
    end
  end

  # Random, so a file that happens to contain the boundary cannot split the
  # body early.
  defp boundary do
    "pavedb-client-" <> Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
  end

  @doc """
  Searches a collection and returns the full PaveDB response envelope.
  """
  @spec search(Client.t(), String.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def search(%Client{} = client, tenant, collection, q, opts \\ []) do
    run_search(client, tenant, collection, %{"q" => q}, opts)
  end

  @doc """
  Searches a collection with a precomputed query vector.

  PaveDB takes either a text query or a raw vector, never both.
  """
  @spec search_vector(Client.t(), String.t(), String.t(), list(number()), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def search_vector(%Client{} = client, tenant, collection, vector, opts \\ []) do
    run_search(client, tenant, collection, %{"v" => vector}, opts)
  end

  @doc """
  Searches the one collection PaveDB is configured to share across tenants.

  Takes `:k`, `:filters`, `:content_filter`, and `:mode`. The endpoint needs no
  tenant or collection, and answers with an empty match list when the server
  has no shared scope enabled. It accepts only text queries.
  """
  @spec search_shared(Client.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def search_shared(%Client{} = client, q, opts \\ []) do
    body =
      %{
        "q" => q,
        "k" => Keyword.get(opts, :k, 5),
        "filters" => Keyword.get(opts, :filters),
        "content_filter" => Keyword.get(opts, :content_filter),
        "mode" => Keyword.get(opts, :mode)
      }
      |> strip_nil()

    Client.request_json(client, :post, "/search", body)
  end

  defp run_search(client, tenant, collection, query, opts) do
    body =
      query
      |> Map.merge(%{
        "k" => Keyword.get(opts, :k, 5),
        "filters" => Keyword.get(opts, :filters),
        "include_common" => Keyword.get(opts, :include_common),
        "content_filter" => Keyword.get(opts, :content_filter),
        "mode" => Keyword.get(opts, :mode)
      })
      |> strip_nil()

    Client.request_json(
      client,
      :post,
      "/collections/#{segment(tenant)}/#{segment(collection)}/search",
      body
    )
  end

  @doc """
  Lists logged searches for a collection, newest first.
  """
  @spec list_queries(Client.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def list_queries(%Client{} = client, tenant, collection, opts \\ []) do
    query =
      opts
      |> Keyword.take([:limit, :offset])
      |> URI.encode_query()
      |> case do
        "" -> ""
        value -> "?" <> value
      end

    Client.request(
      client,
      :get,
      "/collections/#{segment(tenant)}/#{segment(collection)}/queries" <>
        query
    )
  end

  @doc """
  Fetches one logged search, including its original result ids.
  """
  @spec get_query(Client.t(), String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def get_query(%Client{} = client, tenant, collection, query_id) do
    Client.request(
      client,
      :get,
      "/collections/#{segment(tenant)}/#{segment(collection)}/queries/" <>
        segment(query_id)
    )
  end

  @doc """
  Replays one logged search against the collection's current data.
  """
  @spec replay_query(Client.t(), String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def replay_query(%Client{} = client, tenant, collection, query_id) do
    Client.request(
      client,
      :post,
      "/collections/#{segment(tenant)}/#{segment(collection)}/queries/" <>
        segment(query_id) <> "/replay"
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
  Checks server health through the root `/health` endpoint.

  `/health` lives outside the `/v1` API and needs no auth, so it doubles as a
  basic connection check. Returns the readiness envelope (`status`, `version`).
  """
  @spec health(Client.t()) :: {:ok, map()} | {:error, Error.t()}
  def health(%Client{} = client) do
    Client.request(client, :get, "/health", root: true)
  end

  @doc """
  Lists a tenant's collections.
  """
  @spec list_collections(Client.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def list_collections(%Client{} = client, opts \\ []) do
    tenant = Keyword.get(opts, :tenant, client.tenant)
    Client.request(client, :get, "/collections/#{segment(tenant)}")
  end

  @doc """
  Lists configured embedder instances available to a tenant.

  Uses the client's tenant unless `:tenant` is supplied. This is the
  tenant-visible inventory, so it works with a tenant key.
  """
  @spec list_embedders(Client.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def list_embedders(%Client{} = client, opts \\ []) do
    tenant = Keyword.get(opts, :tenant, client.tenant)
    Client.request(client, :get, "/embedders/#{segment(tenant)}")
  end

  @doc """
  Fetches a collection's settings plus document and chunk counts.
  """
  @spec collection_detail(Client.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def collection_detail(%Client{} = client, tenant, name) do
    Client.request(
      client,
      :get,
      "/collections/#{segment(tenant)}/#{segment(name)}/detail"
    )
  end

  @doc """
  Updates a collection's editable metadata (currently `display_name`).
  """
  @spec update_collection(Client.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def update_collection(%Client{} = client, tenant, name, opts \\ []) do
    case Keyword.get(opts, :display_name) do
      nil ->
        {:error,
         %Error{
           code: "invalid_update",
           message: "update_collection needs a display_name"
         }}

      display_name ->
        Client.request_json(
          client,
          :patch,
          "/collections/#{segment(tenant)}/#{segment(name)}",
          %{"display_name" => display_name}
        )
    end
  end

  @doc """
  Renames a collection, changing its slug and URL.
  """
  @spec move_collection(Client.t(), String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def move_collection(%Client{} = client, tenant, name, new_name) do
    Client.request_json(
      client,
      :post,
      "/collections/#{segment(tenant)}/#{segment(name)}/move",
      %{"new_name" => new_name}
    )
  end

  @doc """
  Deletes a collection and every document in it.
  """
  @spec delete_collection(Client.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def delete_collection(%Client{} = client, tenant, name) do
    Client.request(
      client,
      :delete,
      "/collections/#{segment(tenant)}/#{segment(name)}"
    )
  end

  @doc """
  Downloads a collection archive as a binary zip.

  PaveDB restores collection archives only on the same server version.
  """
  @spec export_collection_archive(Client.t(), String.t(), String.t()) ::
          {:ok, binary()} | {:error, Error.t()}
  def export_collection_archive(%Client{} = client, tenant, name) do
    case Client.request_raw(
           client,
           :get,
           "/collections/#{segment(tenant)}/#{segment(name)}/archive"
         ) do
      {:ok, %{body: archive}} -> {:ok, archive}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Restores a binary collection archive. Creates a new collection by default;
  pass `replace: true` to replace an existing collection.
  """
  @spec restore_collection_archive(Client.t(), String.t(), String.t(), binary(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def restore_collection_archive(%Client{} = client, tenant, name, archive, opts \\ [])
      when is_binary(archive) do
    boundary = boundary()
    method = if Keyword.get(opts, :replace, false), do: :put, else: :post

    part = %{
      name: "file",
      filename: "collection.zip",
      content_type: "application/zip",
      body: archive
    }

    Client.request(
      client,
      method,
      "/collections/#{segment(tenant)}/#{segment(name)}/archive",
      multipart_body(boundary, [part]),
      content_type: "multipart/form-data; boundary=#{boundary}"
    )
  end

  @doc """
  Starts a resumable reindex into a new vector space.

  Takes `:embedder_type`, `:embed_model`, and `:embedder_config`. The server
  chooses the embedder instance for this operation.
  """
  @spec start_reindex(Client.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def start_reindex(%Client{} = client, tenant, name, opts \\ []) do
    body = opts |> Keyword.take([:embedder_type, :embed_model, :embedder_config])

    Client.request_json(
      client,
      :post,
      "/collections/#{segment(tenant)}/#{segment(name)}/reindex",
      Enum.into(body, %{})
    )
  end

  @doc """
  Fetches a collection reindex job's status.
  """
  @spec get_reindex(Client.t(), String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def get_reindex(%Client{} = client, tenant, name, job_id) do
    Client.request(
      client,
      :get,
      "/collections/#{segment(tenant)}/#{segment(name)}/reindex/#{segment(job_id)}"
    )
  end

  @doc """
  Cancels a collection reindex job.
  """
  @spec cancel_reindex(Client.t(), String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def cancel_reindex(%Client{} = client, tenant, name, job_id) do
    Client.request(
      client,
      :delete,
      "/collections/#{segment(tenant)}/#{segment(name)}/reindex/#{segment(job_id)}"
    )
  end

  @doc """
  Lists the chunks a document was split into.
  """
  @spec list_chunks(Client.t(), String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def list_chunks(%Client{} = client, tenant, collection, docid) do
    Client.request(
      client,
      :get,
      "/collections/#{segment(tenant)}/#{segment(collection)}/documents/" <>
        segment(docid) <> "/chunks"
    )
  end

  @doc """
  Fetches one chunk by its record id.
  """
  @spec get_chunk(Client.t(), String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def get_chunk(%Client{} = client, tenant, collection, rid) do
    Client.request(
      client,
      :get,
      "/collections/#{segment(tenant)}/#{segment(collection)}/chunks/" <>
        segment(rid)
    )
  end

  @doc """
  Fetches one chunk's raw text content.

  Returns `%{"content" => body, "content_type" => type}`; the endpoint answers
  with the raw body rather than a JSON envelope.
  """
  @spec get_chunk_content(Client.t(), String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def get_chunk_content(%Client{} = client, tenant, collection, rid) do
    case Client.request_raw(
           client,
           :get,
           "/collections/#{segment(tenant)}/#{segment(collection)}/chunks/" <>
             segment(rid) <> "/content"
         ) do
      {:ok, %{body: body, headers: headers}} ->
        {:ok,
         %{
           "content" => body,
           "content_type" => response_content_type(headers)
         }}

      {:error, error} ->
        {:error, error}
    end
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

  defp response_content_type(headers) do
    Enum.find_value(headers, "text/plain", fn {key, value} ->
      if String.downcase(to_string(key)) == "content-type", do: to_string(value)
    end)
  end

  defp collection_attr_keys do
    [
      :display_name,
      :embedder,
      :embedder_type,
      :embed_model,
      :embedder_config,
      :search_mode,
      :chunking,
      :priority_key,
      "display_name",
      "embedder",
      "embedder_type",
      "embed_model",
      "embedder_config",
      "search_mode",
      "chunking",
      "priority_key"
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
       "vector" => Map.get(item, "vector") || Map.get(item, :vector),
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

  defp multipart_parts(path, file, metadata, opts) do
    []
    |> maybe_part("metadata", metadata)
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
      "filename=\"#{header_safe(filename)}\"\r\n"
  end

  defp disposition(%{name: name}) do
    "Content-Disposition: form-data; name=\"#{name}\"\r\n"
  end

  # Quotes and newlines in a filename would end the header early.
  defp header_safe(value), do: String.replace(value, ~r/["\r\n]/, "")

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
