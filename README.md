<!-- (C) 2026 Rodrigo Rodrigues da Silva <rodrigo@flowlexi.com> -->
<!-- SPDX-License-Identifier: Apache-2.0 -->

# PaveDB Elixir Client

Elixir client package for PaveDB.

## Planned Shape

- Connect to a running PaveDB HTTP server.
- Keep the PaveDB server repository as the OpenAPI contract source.
- Keep local embedded PaveDB runtime concerns out of this client.

## Development

```bash
mix deps.get
mix compile --warnings-as-errors
mix test
```
