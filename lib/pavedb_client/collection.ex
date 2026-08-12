# (C) 2026 Rodrigo Rodrigues da Silva <rodrigo@flowlexi.com>
# SPDX-License-Identifier: Apache-2.0

defmodule PaveDBClient.Collection do
  @moduledoc """
  Tenant-scoped collection handle.

  Every function here forwards to its `PaveDBClient` counterpart with the
  tenant and collection the handle already carries. Build one with
  `PaveDBClient.collection/3` or `PaveDBClient.create_collection/3`.
  """

  alias PaveDBClient.Client
  alias PaveDBClient.Error

  defstruct [:client, :tenant, :name]

  @type t :: %__MODULE__{
          client: Client.t(),
          tenant: String.t(),
          name: String.t()
        }

  @doc """
  Adds one raw text document. Takes `:docid` and `:metadata`.
  """
  @spec add(t(), String.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def add(%__MODULE__{} = collection, text, opts \\ []) do
    PaveDBClient.add_text(
      collection.client,
      collection.tenant,
      collection.name,
      text,
      opts
    )
  end

  @doc """
  Adds one precomputed embedding. Takes `:docid` and `:metadata`.
  """
  @spec add_vector(t(), list(number()), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def add_vector(%__MODULE__{} = collection, vector, opts \\ []) do
    PaveDBClient.add_vector(
      collection.client,
      collection.tenant,
      collection.name,
      vector,
      opts
    )
  end

  @doc """
  Adds several documents in one request.

  The response reports per-document results, so a `{:ok, _}` can still carry
  individual failures under `"documents"`.
  """
  @spec add_many(t(), list()) :: {:ok, map()} | {:error, Error.t()}
  def add_many(%__MODULE__{} = collection, documents) do
    PaveDBClient.add_many(
      collection.client,
      collection.tenant,
      collection.name,
      documents
    )
  end

  @doc """
  Uploads a local file. Takes `:docid`, `:metadata`, `:content_type`, and
  `:csv_options`.
  """
  @spec ingest(t(), Path.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def ingest(%__MODULE__{} = collection, path, opts \\ []) do
    PaveDBClient.ingest_file(
      collection.client,
      collection.tenant,
      collection.name,
      path,
      opts
    )
  end

  @doc """
  Searches by text and returns the full response envelope.

  Takes `:k`, `:filters`, and `:include_common`. Use `matches/3` for the hits
  alone.
  """
  @spec search(t(), String.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def search(%__MODULE__{} = collection, q, opts \\ []) do
    PaveDBClient.search(
      collection.client,
      collection.tenant,
      collection.name,
      q,
      opts
    )
  end

  @doc """
  Searches with a precomputed query vector. Takes the same options as
  `search/3`.
  """
  @spec search_vector(t(), list(number()), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def search_vector(%__MODULE__{} = collection, vector, opts \\ []) do
    PaveDBClient.search_vector(
      collection.client,
      collection.tenant,
      collection.name,
      vector,
      opts
    )
  end

  @doc """
  Lists logged searches, newest first. Takes `:limit` and `:offset`.
  """
  @spec list_queries(t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def list_queries(%__MODULE__{} = collection, opts \\ []) do
    PaveDBClient.list_queries(
      collection.client,
      collection.tenant,
      collection.name,
      opts
    )
  end

  @doc """
  Fetches one logged search, including the result ids it returned.
  """
  @spec get_query(t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_query(%__MODULE__{} = collection, query_id) do
    PaveDBClient.get_query(
      collection.client,
      collection.tenant,
      collection.name,
      query_id
    )
  end

  @doc """
  Replays one logged search against the collection's current data.

  Compare the replayed ids with the stored ones to detect drift.
  """
  @spec replay_query(t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def replay_query(%__MODULE__{} = collection, query_id) do
    PaveDBClient.replay_query(
      collection.client,
      collection.tenant,
      collection.name,
      query_id
    )
  end

  @doc """
  Searches and returns just the matches, skipping the response envelope.
  """
  @spec matches(t(), String.t(), keyword()) ::
          {:ok, list(map())} | {:error, Error.t()}
  def matches(%__MODULE__{} = collection, q, opts \\ []) do
    case search(collection, q, opts) do
      {:ok, %{"matches" => matches}} when is_list(matches) ->
        {:ok, matches}

      {:ok, _response} ->
        {:error,
         %Error{
           code: "invalid_response",
           message: "server response is missing matches"
         }}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Lists the collection's documents.
  """
  @spec list_documents(t()) :: {:ok, list(map())} | {:error, Error.t()}
  def list_documents(%__MODULE__{} = collection) do
    PaveDBClient.list_documents(
      collection.client,
      collection.tenant,
      collection.name
    )
  end

  @doc """
  Fetches one document by id, with its metadata and chunk ids.
  """
  @spec get(t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get(%__MODULE__{} = collection, docid) do
    PaveDBClient.get_document(
      collection.client,
      collection.tenant,
      collection.name,
      docid
    )
  end

  @doc """
  Deletes one document by id, along with its chunks.
  """
  @spec delete(t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def delete(%__MODULE__{} = collection, docid) do
    PaveDBClient.delete_document(
      collection.client,
      collection.tenant,
      collection.name,
      docid
    )
  end

  @doc """
  Fetches the collection's settings plus document and chunk counts.
  """
  @spec detail(t()) :: {:ok, map()} | {:error, Error.t()}
  def detail(%__MODULE__{} = collection) do
    PaveDBClient.collection_detail(
      collection.client,
      collection.tenant,
      collection.name
    )
  end

  @doc """
  Updates editable metadata. Takes `:display_name`.
  """
  @spec update(t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def update(%__MODULE__{} = collection, opts \\ []) do
    PaveDBClient.update_collection(
      collection.client,
      collection.tenant,
      collection.name,
      opts
    )
  end

  @doc """
  Renames the collection and returns a handle pointing at the new slug.

  The original handle still carries the old name, so keep the returned one.
  """
  @spec rename(t(), String.t()) :: {:ok, t()} | {:error, Error.t()}
  def rename(%__MODULE__{} = collection, new_name) do
    case PaveDBClient.move_collection(
           collection.client,
           collection.tenant,
           collection.name,
           new_name
         ) do
      {:ok, _response} -> {:ok, %{collection | name: new_name}}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Lists the chunks a document was split into. Listings carry no chunk text.
  """
  @spec list_chunks(t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def list_chunks(%__MODULE__{} = collection, docid) do
    PaveDBClient.list_chunks(
      collection.client,
      collection.tenant,
      collection.name,
      docid
    )
  end

  @doc """
  Fetches one chunk's record by its rid.
  """
  @spec get_chunk(t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_chunk(%__MODULE__{} = collection, rid) do
    PaveDBClient.get_chunk(
      collection.client,
      collection.tenant,
      collection.name,
      rid
    )
  end

  @doc """
  Fetches one chunk's raw text as `%{"content" => text, "content_type" => type}`.
  """
  @spec get_chunk_content(t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_chunk_content(%__MODULE__{} = collection, rid) do
    PaveDBClient.get_chunk_content(
      collection.client,
      collection.tenant,
      collection.name,
      rid
    )
  end
end
