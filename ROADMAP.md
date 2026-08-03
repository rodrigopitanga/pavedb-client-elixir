<!-- (C) 2026 Rodrigo Rodrigues da Silva <rodrigo@flowlexi.com> -->
<!-- SPDX-License-Identifier: Apache-2.0 -->

# PaveDB Elixir Client — Roadmap

Early-stage HTTP client targeting PaveDB's `/v1` REST contract, which freezes
at PaveDB 1.0 and is additive afterward. Keep this roadmap lightweight and
honest: list only what's planned, mark dependencies, and do not invent module
or function names ahead of implementation.

## Completed

- **P1-66 — Numbered `examples/` tree.** Runnable concurrent-evaluation and
  query-replay-drift examples live under `examples/<n>-<slug>/` and are tested
  against a real PaveDB.
- **Query log + replay support.** The client and collection surfaces list,
  fetch, and replay stored queries.
