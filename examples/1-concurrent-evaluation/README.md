# Concurrent evaluation

Runs the chapter 11-style evaluation queries concurrently, retrying only PaveDB
backpressure responses. It creates or refreshes its own `book-evaluation`
collection.

Start a real PaveDB server, then run this from the client checkout:

```sh
PAVEDB_URL=http://127.0.0.1:8086 PAVEDB_TENANT=book \
  mix run examples/1-concurrent-evaluation/run.exs
```

Set `PAVEDB_TOKEN` when the server requires authentication. The result reports
per-query failures and mean recall for the two seeded curriculum records.
