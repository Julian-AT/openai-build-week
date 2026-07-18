---
phase: 05-curated-replacement-vertical
plan: "01"
subsystem: deterministic-replace-reducer
tags: [swift, tdd, transaction, replace, restore]
requires:
  - phase: 03-deterministic-native-transaction-core
    provides: projections, place lifecycle, captured-exact restore
  - phase: 04-target-grounding-and-compositor-gate
    provides: stable manual target identity and fallback readiness
provides:
  - Exact no-reveal replace preview/cancel/confirm reducer
  - Visibility-before-asset operation order and exact projection inverse
  - Fail-closed target/view/support/asset/world/revision validation
affects: [05-02-native-authority, 05-03-native-replace-ui, phase-06-remove]
completed: 2026-07-18
---

# Phase 5 Plan 01 Summary

**A dedicated pure reducer now implements the canonical sprint replace sequence: hide the validated selected target, create the replacement asset/support last, and capture one exact compensating snapshot.**

## Delivered

- `ReplaceReducer` with preview, cancel, and explicit-confirmation reduction.
- Exact no-reveal order: `set_object_visibility` then `create_asset_instance`.
- Validation for stable selected target, visible/tracked lifecycle, capability fallback, supported-view fixture, current support/world/revision, allowlist, collision, provenance/license, and artifact integrity.
- Atomic pending scene construction plus RR-EDIT-PROJECTION-1 diff verification.
- One captured-exact `restore_snapshot` inverse with exact artifact references.
- Typed failures leave the input scene and revision unchanged.

## TDD and verification

- RED commit: `8631a4a` — failing reducer contract and failure matrix.
- GREEN commit: `300931f` — production reducer.
- Focused result: 4 replace tests passed, including 20 parameterized fail-closed cases.
- Full Swift package regression: 137 tests across 23 suites passed.

## Honest boundary

This plan proves deterministic transaction semantics only. It does not prove physical replacement quality, device asset loading, native/web derivative parity, or any green gate. `GATE-003`, `GATE-005`, `GATE-009`, `GATE-011`, and `OPS-GOLDEN-001` remain `PENDING`.

## Next

Plan 05-02 can add `NativeBranchAuthority` replace entry points, versioned canonical target bootstrap, durable idempotency/recovery, replay, and restore coverage.
