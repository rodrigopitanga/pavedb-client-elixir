# (C) 2026 Rodrigo Rodrigues da Silva <rodrigo@flowlexi.com>
# SPDX-License-Identifier: Apache-2.0

defmodule PaveDBClientTest do
  use ExUnit.Case, async: true

  test "exposes a version" do
    assert PaveDBClient.version() == "0.1.0"
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

  test "maps HTTP error payloads to structured errors" do
    client =
      PaveDBClient.new(
        "http://pave.test",
        transport: fn _method, _path, _headers, _body ->
          body =
            ~s({"detail":{"code":"collection_not_found",) <>
              ~s("error":"missing","error_type":"not_found"}})

          {:ok, 404, [], body}
        end
      )

    assert {:error, error} =
             PaveDBClient.get_document(client, "default", "missing", "doc")

    assert error.code == "collection_not_found"
    assert error.message == "missing"
    assert error.status == 404
    assert error.type == "not_found"
    assert PaveDBClient.format_error(error) == "PaveDB HTTP 404: missing"
  end

  defp unique_id do
    System.unique_integer([:positive, :monotonic])
  end
end
