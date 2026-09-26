<!-- (C) 2026 Rodrigo Rodrigues da Silva <rodrigo@flowlexi.com> -->
<!-- SPDX-License-Identifier: Apache-2.0 -->

# PaveDB Elixir Client

Elixir client package for PaveDB.

## Scope

- Connects to a running PaveDB HTTP server.
- The PaveDB core repository defines the OpenAPI contract.
- Embedded PaveDB runtime support is outside this client's scope.

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

Requests time out after 30 seconds, with 5 seconds to connect. Both are
per-client options:

```elixir
PaveDBClient.connect(timeout: 120_000, connect_timeout: 2_000)
```

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

## Raw vectors

Collections also take precomputed embeddings. PaveDB accepts either text or a
raw vector on a given document or query, never both:

```elixir
{:ok, _} = PaveDBClient.Collection.add_vector(books, [0.12, 0.98], docid: "vec-1")
{:ok, response} = PaveDBClient.Collection.search_vector(books, [0.12, 0.98], k: 3)
```

Batch items carry vectors too: `%{vector: [0.1, 0.2], docid: "vec-2"}`.

## Shared scope

A server can designate one collection as shared across tenants. Searching it
needs no tenant or collection, and answers with an empty match list when the
server has no shared scope enabled:

```elixir
{:ok, %{"matches" => matches}} = PaveDBClient.search_shared(client, "captain", k: 3)
```

Text only — PaveDB's shared endpoint rejects raw query vectors.

## PaveDB 0.9.7 collection options

The client sends PaveDB's collection creation settings, including an embedder
selector, default search mode, chunking, and priority field:

```elixir
{:ok, books} =
  PaveDBClient.create_collection(client, "books",
    embedder: "native",
    search_mode: "boost",
    chunking: %{strategy: "fixed", size: 800, overlap: 100},
    priority_key: "rank"
  )

{:ok, %{"matches" => matches, "mode" => "hybrid"}} =
  PaveDBClient.Collection.search(books, "captain nemo",
    mode: "hybrid",
    content_filter: %{op: "phrase", value: "captain nemo"}
  )
```

`search_shared/3` takes the same `:mode` and `:content_filter` options.
`"native"` is the default configured instance used in PaveDB's core examples.
Collection creation accepts another `:embedder` selector if the server has it
configured. PaveDB chooses the instance for each operation; the client has no
per-operation embedder option.

Tenant keys can inspect their available embedder instances:

```elixir
{:ok, %{"embedders" => embedders, "default" => default}} =
  PaveDBClient.list_embedders(client)
```

## Collection portability

Collection archives are binary zip files and restore only on a PaveDB server
of the same version. `restore_archive/3` creates a new collection by default;
`replace: true` replaces an existing one.

```elixir
{:ok, archive} = PaveDBClient.Collection.export_archive(books)
copy = PaveDBClient.collection(client, "books-copy")
{:ok, _} = PaveDBClient.Collection.restore_archive(copy, archive)

{:ok, %{"job_id" => job_id}} =
  PaveDBClient.Collection.start_reindex(copy,
    embedder_type: "sbert",
    embed_model: "all-MiniLM-L6-v2"
  )
{:ok, job} = PaveDBClient.Collection.get_reindex(copy, job_id)
```

The target reindex model must be configured on the server. Use
`PaveDBClient.Collection.cancel_reindex(copy, job_id)` to cancel a job.

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

`/admin` and `/metrics` are intentionally out of scope.

## Development

Needs Elixir 1.17 or later on OTP 27 or later: the client encodes and decodes
with OTP's built-in `:json` and takes no runtime dependency of its own.

```bash
mix deps.get
mix compile --warnings-as-errors
mix test
```
