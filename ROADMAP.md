<!-- (C) 2026 Rodrigo Rodrigues da Silva <rodrigo@flowlexi.com> -->
<!-- SPDX-License-Identifier: Apache-2.0 -->

# PaveDB Elixir Client — Roadmap

Early-stage HTTP client targeting PaveDB's `/v1` REST contract, which freezes
at PaveDB 1.0 and is additive afterward. Keep this roadmap lightweight and
honest: list only what's planned, mark dependencies, and do not invent module
or function names ahead of implementation.

## PaveDB 1.0

- **P1-67 — Public API parity.** Track the current user-facing `/v1` surface
  plus a basic `/health` connection check. `/admin`, `/metrics`, and
  `/embedders` stay out of scope. Prove parity against a real PaveDB without a
  generated client or new dependency.
