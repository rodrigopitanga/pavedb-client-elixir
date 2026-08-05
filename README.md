<!-- (C) 2026 Rodrigo Rodrigues da Silva <rodrigo@flowlexi.com> -->
<!-- SPDX-License-Identifier: Apache-2.0 -->

# PaveDB Elixir Client

Elixir client package for PaveDB.

## Shape

- Connect to a running PaveDB HTTP server.
- Keep the PaveDB server repository as the OpenAPI contract source.
- Keep local embedded PaveDB runtime concerns out of this client.

## Basic Usage

```elixir
client =
  PaveDBClient.connect("http://localhost:8086",
    tenant: "tenant",
    api_key: "secret"
  )

{:ok, books} =
  PaveDBClient.create_collection(client, "books", display_name: "Books")

{:ok, _doc} =
  PaveDBClient.Collection.add(books, "Captain Nemo commands the Nautilus.",
    docid: "note-1",
    metadata: %{"kind" => "note"}
  )

{:ok, response} =
  PaveDBClient.Collection.search(books, "captain", k: 3)

matches = response["matches"]
```

The collection handle uses the tenant stored on the client. When `tenant:` is
omitted, the client uses PaveDB's `default` tenant.

Lower-level helpers are also available when a provider already has tenant and
collection values:

```elixir
client = PaveDBClient.connect()

PaveDBClient.create_collection(client, "tenant", "collection", %{
  display_name: "Demo"
})

PaveDBClient.add_text(client, "tenant", "collection", "hello world")

PaveDBClient.ingest_file(client, "tenant", "collection", "items.csv",
  docid: "items",
  metadata: %{"source" => "csv"},
  csv_options: [has_header: "yes", meta_cols: ["id"]]
)

PaveDBClient.search(client, "tenant", "collection", "hello",
  k: 5,
  filters: %{"source" => "csv"}
)
```

All request functions return `{:ok, value}` or
`{:error, %PaveDBClient.Error{}}`. `PaveDBClient.format_error/1` formats
errors for logs and operator messages.

## Query replay

Collection handles also expose PaveDB's query log:

```elixir
{:ok, %{"queries" => queries}} =
  PaveDBClient.Collection.list_queries(books, limit: 20)

query_id = hd(queries)["query_id"]
{:ok, %{"query" => original}} = PaveDBClient.Collection.get_query(books, query_id)
{:ok, replay} = PaveDBClient.Collection.replay_query(books, query_id)
```

See the runnable [concurrent evaluation](examples/1-concurrent-evaluation/)
and [query replay drift](examples/2-query-replay-drift/) examples.

## Managing collections

The client mirrors PaveDB's user-facing `/v1` catalog and chunk surface, plus a
root `/health` connection check:

```elixir
{:ok, %{"status" => "ready"}} = PaveDBClient.health(client)

{:ok, %{"collections" => collections}} = PaveDBClient.list_collections(client)

{:ok, detail} = PaveDBClient.Collection.detail(books)
{:ok, _} = PaveDBClient.Collection.update(books, display_name: "Great Books")
{:ok, tomes} = PaveDBClient.Collection.rename(books, "tomes")

{:ok, %{"chunks" => chunks}} = PaveDBClient.Collection.list_chunks(tomes, "note-1")
{:ok, chunk} = PaveDBClient.Collection.get_chunk(tomes, hd(chunks)["rid"])
{:ok, %{"content" => text}} = PaveDBClient.Collection.get_chunk_content(tomes, chunk["rid"])

{:ok, _} = PaveDBClient.delete_collection(client, "tenant", "tomes")
```

`/admin`, `/metrics`, and `/embedders` are intentionally out of scope.

## Development

```bash
mix deps.get
mix compile --warnings-as-errors
mix test
```
