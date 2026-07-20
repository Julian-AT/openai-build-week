---
phase: 05
slug: curated-replacement-vertical
status: retroactive-executed
nyquist_compliant: true
automated_coverage: complete
manual_gates: pending
created: 2026-07-19
---

# Phase 05 — Validation Strategy

This retroactive map records existing replacement coverage. The phase remains
`human_needed` until device/parity/license/golden evidence closes its gates.

## Test infrastructure

| Scope | Command |
|---|---|
| Pure replacement reducer | `swift test --package-path ios/Packages/ReRoomContracts --filter ReplaceReducerTests` |
| Authority/store/restart | `swift test --package-path ios/Packages/ReRoomContracts --filter TransactionAuthorityTests` |
| Native model/UI | Xcode `RoomEditModelTests` and serialized `RoomEditJourneyTests` |
| Phase verifier | `scripts/verify-phase-05-replacement` |

## Requirement coverage

| Requirement | Automated behavior |
|---|---|
| `FR-REPLACE-001` | Exact visibility→asset order, stable target, support/readiness blockers, one revision, idempotent retry, restart/replay/restore. |
| `OPS-LICENSE-001` | Source/provenance/digest fields are fail-closed and pending status is retained rather than promoted. |

## Continuous strategy

Run reducer first, authority/store second, native tests third, then the
source-bound phase verifier and secret/whitespace checks.

## Manual-only gates

Device load/compositor judgment, USDZ/GLB parity, redistribution/attribution
approval, and five signed-device journeys remain GATE-003/GATE-005/GATE-011
and OPS-GOLDEN-001 evidence.
