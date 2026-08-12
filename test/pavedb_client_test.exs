# (C) 2026 Rodrigo Rodrigues da Silva <rodrigo@flowlexi.com>
# SPDX-License-Identifier: Apache-2.0

defmodule PaveDBClientTest do
  use ExUnit.Case, async: true

  test "exposes the version the package was built with" do
    assert PaveDBClient.version() ==
             :pavedb_client |> Application.spec(:vsn) |> to_string()
  end

  test "values PaveDB cannot receive fail as errors, not exceptions" do
    client =
      PaveDBClient.new("http://pave.test",
        transport: fn _method, _path, _headers, _body ->
          flunk("unencodable values must never reach the transport")
        end
      )

    assert {:error, %{code: "invalid_body"}} =
             PaveDBClient.Collection.add(PaveDBClient.collection(client, "books"), "hi",
               metadata: %{"at" => ~U[2026-01-01 00:00:00Z]}
             )

    assert {:error, %{code: "invalid_body"}} =
             PaveDBClient.search(client, "default", "books", "q", filters: %{"a" => {1, 2}})
  end

  test "an unencodable ingest metadata fails before the file is uploaded" do
    path = Path.join(System.tmp_dir!(), "pavedb-client-#{unique_id()}.txt")
    File.write!(path, "hello")
    on_exit(fn -> File.rm(path) end)

    client =
      PaveDBClient.new("http://pave.test",
        transport: fn _method, _path, _headers, _body ->
          flunk("unencodable metadata must never reach the transport")
        end
      )

    assert {:error, %{code: "invalid_metadata"}} =
             PaveDBClient.ingest_file(client, "default", "books", path,
               metadata: %{"at" => ~U[2026-01-01 00:00:00Z]}
             )
  end

  test "a missing ingest file fails without a request" do
    client =
      PaveDBClient.new("http://pave.test",
        transport: fn _m, _p, _h, _b -> flunk("must not request") end
      )

    assert {:error, %{code: "file_read_failed"}} =
             PaveDBClient.ingest_file(client, "default", "books", "/nope/missing.csv")
  end

  test "collection surface maps to PaveDB HTTP requests" do
    parent = self()

    client =
      PaveDBClient.new(
        "http://pave.test",
        api_key: "secret",
        transport: fn method, path, headers, body ->
          send(parent, {:request, method, path, headers, body})

          cond do
            method == :post and path == "/v1/collections/default/books" ->
              {:ok, 201, [], ~s({"ok":true,"collection":"books"})}

            method == :post and String.ends_with?(path, "/documents") ->
              {:ok, 201, [], ~s({"ok":true,"docid":"note-1","chunks":1})}

            method == :post and String.ends_with?(path, "/documents:batch") ->
              {:ok, 201, [], ~s({"ok":true,"succeeded":2,"failed":0})}

            method == :post and String.ends_with?(path, "/search") ->
              {:ok, 200, [], ~s({"ok":true,"matches":[{"id":"r1"}]})}

            method == :get and String.ends_with?(path, "/queries?limit=10") ->
              {:ok, 200, [], ~s({"ok":true,"queries":[{"query_id":"q1"}]})}

            method == :get and String.ends_with?(path, "/queries/q1") ->
              {:ok, 200, [], ~s({"ok":true,"query":{"query_id":"q1"}})}

            method == :post and String.ends_with?(path, "/queries/q1/replay") ->
              {:ok, 200, [], ~s({"ok":true,"original_query_id":"q1","matches":[]})}

            method == :get and String.ends_with?(path, "/documents") ->
              {:ok, 200, [], ~s({"ok":true,"documents":[{"docid":"note-1"}]})}

            method == :get and String.ends_with?(path, "/documents/note-1") ->
              {:ok, 200, [], ~s({"ok":true,"docid":"note-1"})}

            method == :delete and String.ends_with?(path, "/documents/note-1") ->
              {:ok, 200, [], ~s({"ok":true,"deleted":true})}

            true ->
              {:ok, 500, [], ~s({"code":"unexpected","error":"unexpected"})}
          end
        end
      )

    assert {:ok, books} =
             PaveDBClient.create_collection(client, "books", display_name: "Books")

    assert {:ok, %{"docid" => "note-1"}} =
             PaveDBClient.Collection.add(books, "Captain Nemo", docid: "note-1")

    assert {:ok, %{"succeeded" => 2}} =
             PaveDBClient.Collection.add_many(books, [
               "A",
               {"B", "note-2", %{"kind" => "note"}}
             ])

    assert {:ok, %{"matches" => [%{"id" => "r1"}]}} =
             PaveDBClient.Collection.search(books, "captain",
               k: 3,
               filters: %{"kind" => "note"},
               include_common: true
             )

    assert {:ok, %{"queries" => [%{"query_id" => "q1"}]}} =
             PaveDBClient.Collection.list_queries(books, limit: 10)

    assert {:ok, %{"query" => %{"query_id" => "q1"}}} =
             PaveDBClient.Collection.get_query(books, "q1")

    assert {:ok, %{"original_query_id" => "q1"}} =
             PaveDBClient.Collection.replay_query(books, "q1")

    assert {:ok, [%{"id" => "r1"}]} =
             PaveDBClient.Collection.matches(books, "captain")

    assert {:ok, [%{"docid" => "note-1"}]} =
             PaveDBClient.Collection.list_documents(books)

    assert {:ok, %{"docid" => "note-1"}} =
             PaveDBClient.Collection.get(books, "note-1")

    assert {:ok, %{"deleted" => true}} =
             PaveDBClient.Collection.delete(books, "note-1")

    assert_received {:request, :post, "/v1/collections/default/books", headers, body}

    assert {"authorization", "Bearer secret"} in headers
    assert {:ok, %{"display_name" => "Books"}} = PaveDBClient.JSON.decode(body)

    assert_received {:request, :post, path, _headers, body}
    assert path == "/v1/collections/default/books/documents"

    assert {:ok, %{"text" => "Captain Nemo", "docid" => "note-1"}} =
             PaveDBClient.JSON.decode(body)
  end

  test "connect accepts tenant option for the collection surface" do
    parent = self()

    client =
      PaveDBClient.connect(
        tenant: "acme",
        transport: fn method, path, headers, body ->
          send(parent, {:request, method, path, headers, body})
          {:ok, 201, [], ~s({"ok":true,"collection":"books"})}
        end
      )

    assert {:ok, books} =
             PaveDBClient.create_collection(client, "books", display_name: "Books")

    assert books.tenant == "acme"

    assert_received {:request, :post, "/v1/collections/acme/books", _headers, _body}
  end

  test "ingest uploads a multipart file with csv query parameters" do
    parent = self()
    tmp_dir = Path.join(System.tmp_dir!(), "pavedb-client-#{unique_id()}")
    path = Path.join(tmp_dir, "items.csv")

    File.mkdir_p!(tmp_dir)
    File.write!(path, "id,kind\n1,fruit\n")

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    client =
      PaveDBClient.new(
        "http://pave.test/v1",
        transport: fn method, request_path, headers, body ->
          send(parent, {:request, method, request_path, headers, body})
          {:ok, 201, [], ~s({"ok":true,"docid":"items","chunks":1})}
        end
      )

    books = PaveDBClient.collection(client, "books")

    assert {:ok, %{"chunks" => 1}} =
             PaveDBClient.Collection.ingest(books, path,
               docid: "items",
               metadata: %{"lang" => "en"},
               content_type: "text/csv",
               csv_options: [
                 has_header: "yes",
                 meta_cols: ["id", "kind"],
                 include_cols: "name,description"
               ]
             )

    assert_received {:request, :post, request_path, headers, body}

    assert request_path =~ "/collections/default/books/documents?"
    assert request_path =~ "csv_has_header=yes"
    assert request_path =~ "csv_meta_cols=id%2Ckind"
    assert request_path =~ "csv_include_cols=name%2Cdescription"

    refute Enum.any?(headers, fn {key, _value} -> key == "authorization" end)
    assert body =~ ~s(name="docid")
    assert body =~ "items"
    assert body =~ ~s(name="metadata")
    assert body =~ ~s({"lang":"en"})
    assert body =~ "Content-Type: text/csv"
    assert body =~ "id,kind"
  end

  test "maps PaveDB error envelopes to structured errors" do
    body =
      ~s({"ok":false,"code":"collection_not_found",) <>
        ~s("error":"collection 'missing' not found",) <>
        ~s("details":{"tenant":"default","collection":"missing"},) <>
        ~s("request_id":"r-1","latency_ms":1.5})

    client =
      PaveDBClient.new(
        "http://pave.test",
        transport: fn _method, _path, _headers, _body -> {:ok, 404, [], body} end
      )

    assert {:error, error} =
             PaveDBClient.get_document(client, "default", "missing", "doc")

    assert error.code == "collection_not_found"
    assert error.message == "collection 'missing' not found"
    assert error.status == 404
    assert error.details == %{"tenant" => "default", "collection" => "missing"}

    assert PaveDBClient.format_error(error) ==
             "PaveDB HTTP 404: collection 'missing' not found"
  end

  test "keeps the status when a failure carries no PaveDB envelope" do
    client =
      PaveDBClient.new(
        "http://pave.test",
        transport: fn _method, _path, _headers, _body ->
          {:ok, 502, [], "<html>bad gateway</html>"}
        end
      )

    assert {:error, error} = PaveDBClient.health(client)
    assert error.code == "http_502"
    assert error.message == "<html>bad gateway</html>"
    assert error.status == 502
    assert error.details == nil
  end

  test "reports transport failures without a status" do
    client =
      PaveDBClient.new(
        "http://pave.test",
        transport: fn _method, _path, _headers, _body -> {:error, :timeout} end
      )

    assert {:error, error} = PaveDBClient.health(client)
    assert error.code == "request_failed"
    assert error.status == nil
    assert error.message =~ ":timeout"
    assert PaveDBClient.format_error(error) == error.message
  end

  test "a degraded /health stays a successful response" do
    client =
      PaveDBClient.new(
        "http://pave.test",
        transport: fn _method, _path, _headers, _body ->
          {:ok, 200, [], ~s({"ok":false,"status":"degraded","version":"0.9.3"})}
        end
      )

    assert {:ok, %{"status" => "degraded"}} = PaveDBClient.health(client)
  end

  test "raw vectors ride PaveDB's vector and v fields" do
    parent = self()

    client =
      PaveDBClient.new(
        "http://pave.test",
        transport: fn method, path, _headers, body ->
          send(parent, {:request, method, path, body})
          {:ok, 200, [], ~s({"ok":true,"matches":[]})}
        end
      )

    books = PaveDBClient.collection(client, "books")

    assert {:ok, _} =
             PaveDBClient.Collection.add_vector(books, [0.1, 0.2], docid: "vec-1")

    assert_received {:request, :post, "/v1/collections/default/books/documents", body}
    assert {:ok, added} = PaveDBClient.JSON.decode(body)
    assert added == %{"vector" => [0.1, 0.2], "docid" => "vec-1"}
    refute Map.has_key?(added, "text")

    assert {:ok, _} = PaveDBClient.Collection.search_vector(books, [0.1, 0.2], k: 3)

    assert_received {:request, :post, "/v1/collections/default/books/search", body}
    assert {:ok, searched} = PaveDBClient.JSON.decode(body)
    assert searched == %{"v" => [0.1, 0.2], "k" => 3}
    refute Map.has_key?(searched, "q")

    assert {:ok, _} =
             PaveDBClient.Collection.add_many(books, [%{vector: [0.3], docid: "vec-2"}])

    assert_received {:request, :post, _path, body}
    assert {:ok, %{"documents" => [item]}} = PaveDBClient.JSON.decode(body)
    assert item == %{"vector" => [0.3], "docid" => "vec-2"}
  end

  test "shared search hits /v1/search without a tenant or collection" do
    parent = self()

    client =
      PaveDBClient.new(
        "http://pave.test",
        transport: fn method, path, _headers, body ->
          send(parent, {:request, method, path, body})
          {:ok, 200, [], ~s({"ok":true,"matches":[{"id":"s1"}],"query_id":null})}
        end
      )

    assert {:ok, %{"matches" => [%{"id" => "s1"}]}} =
             PaveDBClient.search_shared(client, "captain", k: 3, filters: %{"kind" => "note"})

    assert_received {:request, :post, "/v1/search", body}

    assert {:ok, %{"q" => "captain", "k" => 3, "filters" => %{"kind" => "note"}}} =
             PaveDBClient.JSON.decode(body)

  end

  test "requests are bounded by a default timeout that callers can override" do
    assert %{timeout: 30_000, connect_timeout: 5_000} = PaveDBClient.connect()

    assert %{timeout: 1_000, connect_timeout: 250} =
             PaveDBClient.connect(timeout: 1_000, connect_timeout: 250)
  end

  test "target_url routes the /v1 API but sends /health to the server root" do
    plain = PaveDBClient.new("http://pave.test")
    versioned = PaveDBClient.new("http://pave.test/v1")

    for client <- [plain, versioned] do
      assert PaveDBClient.Client.target_url(client, false, "/collections/default") ==
               "http://pave.test/v1/collections/default"

      assert PaveDBClient.Client.target_url(client, true, "/health") ==
               "http://pave.test/health"
    end
  end

  test "health check hits the root endpoint outside /v1" do
    parent = self()

    transport = fn method, path, _headers, _body ->
      send(parent, {:request, method, path})
      {:ok, 200, [], ~s({"ok":true,"status":"ready","version":"0.9.3"})}
    end

    for base_url <- ["http://pave.test", "http://pave.test/v1"] do
      client = PaveDBClient.new(base_url, transport: transport)

      assert {:ok, %{"status" => "ready", "version" => "0.9.3"}} =
               PaveDBClient.health(client)

      assert_received {:request, :get, "/health"}
    end
  end

  test "collection catalog and chunk surface maps to PaveDB HTTP requests" do
    parent = self()

    client =
      PaveDBClient.new(
        "http://pave.test",
        transport: fn method, path, _headers, body ->
          send(parent, {:request, method, path, body})

          cond do
            method == :get and path == "/v1/collections/default" ->
              {:ok, 200, [], ~s({"ok":true,"collections":[{"name":"books"}]})}

            method == :get and String.ends_with?(path, "/books/detail") ->
              {:ok, 200, [], ~s({"ok":true,"documents":2,"chunks":5})}

            method == :patch and path == "/v1/collections/default/books" ->
              {:ok, 200, [], ~s({"ok":true,"display_name":"Great Books"})}

            method == :post and String.ends_with?(path, "/books/move") ->
              {:ok, 200, [], ~s({"ok":true,"new_name":"tomes"})}

            method == :delete and path == "/v1/collections/default/books" ->
              {:ok, 200, [], ~s({"ok":true,"deleted":true})}

            method == :get and String.ends_with?(path, "/documents/note-1/chunks") ->
              {:ok, 200, [], ~s({"ok":true,"chunks":[{"rid":"c0"}]})}

            method == :get and String.ends_with?(path, "/chunks/c0/content") ->
              {:ok, 200, [{"content-type", "text/markdown"}], "raw chunk text"}

            method == :get and String.ends_with?(path, "/chunks/c0") ->
              {:ok, 200, [], ~s({"ok":true,"rid":"c0","text":"hello"})}

            true ->
              {:ok, 500, [], ~s({"code":"unexpected","error":"unexpected"})}
          end
        end
      )

    books = PaveDBClient.collection(client, "books")

    assert {:ok, %{"collections" => [%{"name" => "books"}]}} =
             PaveDBClient.list_collections(client)

    assert {:ok, %{"documents" => 2, "chunks" => 5}} =
             PaveDBClient.Collection.detail(books)

    assert {:ok, %{"display_name" => "Great Books"}} =
             PaveDBClient.Collection.update(books, display_name: "Great Books")

    assert_received {:request, :patch, "/v1/collections/default/books", body}
    assert {:ok, %{"display_name" => "Great Books"}} = PaveDBClient.JSON.decode(body)

    assert {:ok, %PaveDBClient.Collection{name: "tomes"}} =
             PaveDBClient.Collection.rename(books, "tomes")

    assert_received {:request, :post, "/v1/collections/default/books/move", body}
    assert {:ok, %{"new_name" => "tomes"}} = PaveDBClient.JSON.decode(body)

    assert {:ok, %{"deleted" => true}} =
             PaveDBClient.delete_collection(client, "default", "books")

    assert {:ok, %{"chunks" => [%{"rid" => "c0"}]}} =
             PaveDBClient.Collection.list_chunks(books, "note-1")

    assert {:ok, %{"rid" => "c0", "text" => "hello"}} =
             PaveDBClient.Collection.get_chunk(books, "c0")

    assert {:ok, %{"content" => "raw chunk text", "content_type" => "text/markdown"}} =
             PaveDBClient.Collection.get_chunk_content(books, "c0")
  end

  defp unique_id do
    System.unique_integer([:positive, :monotonic])
  end
end
