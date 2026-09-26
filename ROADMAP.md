<!-- (C) 2026 Rodrigo Rodrigues da Silva <rodrigo@flowlexi.com> -->
<!-- SPDX-License-Identifier: Apache-2.0 -->

# PaveDB Elixir Client — Roadmap

Early-stage HTTP client targeting PaveDB's `/v1` REST contract, which freezes
at PaveDB 1.0 and is additive afterward. Keep this roadmap lightweight and
honest: list only what's planned, mark dependencies, and do not invent module
or function names ahead of implementation.

## PaveDB 1.0

- ~~P1-54 dependency — binary collection archive export/import~~: demonstrate
  a same-version round trip against a real PaveDB while preserving unrelated
  collections.
- ~~P1-77/P1-78/P2-11 dependency — collection creation settings~~.
- ~~P1-77/P1-70 dependency — search mode and content filters~~.
- ~~P1-55 dependency — self-service reindex start, status, and cancel~~.

- ~~P1-69 — Publish generated Elixir API docs for pavedb-site from a versioned
  Hex tarball~~: CI generates one `docs/reference/api.md`, verifies the package
  copy byte-for-byte, and publishes final tags with protected `HEX_API_KEY`.
- Guard the `/v1` contract against drift. Nothing here checks the client's
  routes and payload fields against the server's `openapi.json`, which is how
  the error decoder came to target an envelope PaveDB never sends.

## PaveDB 1.1

- P1-66 — Run the numbered examples against a real PaveDB in CI. The examples
  live under `examples/<n>-<slug>/` and run by hand, but the test only checks
  that each documented command appears in its README, so a renamed client
  function still passes.
