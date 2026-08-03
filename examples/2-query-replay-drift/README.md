# Query replay drift

Lists stored searches, fetches their original result ids, and replays them in
parallel against the current collection. A row is drifted when replayed ids no
longer match the logged ids. The script creates or refreshes its own
`book-query-replay` collection, then records one seed search.

Query logging must be enabled on the real PaveDB server. Run from the client
checkout:

```sh
PAVEDB_URL=http://127.0.0.1:8086 PAVEDB_TENANT=book \
  mix run examples/2-query-replay-drift/run.exs
```

Set `PAVEDB_TOKEN` when the server requires authentication.
