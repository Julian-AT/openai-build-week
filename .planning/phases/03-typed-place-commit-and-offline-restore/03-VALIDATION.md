---
phase: 03
slug: typed-place-commit-and-offline-restore
status: retroactive-executed
nyquist_compliant: true
automated_coverage: complete
manual_gates: pending
created: 2026-07-19
---

# Phase 03 — Validation Strategy

This retroactive artifact restores the validation architecture omitted when
Nyquist generation was disabled. It records existing executable coverage; it
does not promote the `human_needed` phase verdict or any gate.

## Test infrastructure

| Scope | Command |
|---|---|
| Transaction/intent unit tests | `swift test --package-path ios/Packages/ReRoomContracts --filter ReRoomTransactionCoreTests` |
| Phase quick/full | `scripts/verify-phase-03-transactions quick` / `scripts/verify-phase-03-transactions full` |
| Native model/UI | Xcode `RoomEditModelTests` and `RoomEditJourneyTests` on the declared simulator/device |

## Requirement coverage

| Requirement | Automated behavior |
|---|---|
| `FR-PLACE-001` | Preview stays at `r`; support failures reject; explicit confirmation commits one `r+1`; restart/replay retains it. |
| `FR-RESTORE-001` | Captured-exact inverse, latest eligibility, touched-ID rebase, offline fresh revision, and immutable history. |
| `FR-TRANSACTION-001` | CAS, idempotency/fingerprint conflict, wrong/stale authority, crash activation, and divergence quarantine. |
| `FR-AGENT-001` | Closed typed/tap proposal boundary and forbidden field/transform/session/confirmation rejection without mutation. |

## Continuous strategy

- Run the narrow reducer/authority test after behavior changes.
- Run `quick` before every phase-local commit and `full` before evidence handoff.
- Preserve exact input/source revision in evidence; a dirty candidate is not
  revision-bound proof.

## Manual-only gates

GATE-009 resilience and GATE-010 external/adversarial campaign remain pending
where the verification report says `human_needed`. Automation cannot replace
network/device/operator evidence.
