---
phase: 06-controlled-multi-surface-removal
plan: "01"
subsystem: native-transaction-reducer
tags: [swift, reducer, remove, reveal, restore, degraded-fixture]
requires:
  - phase: 03-deterministic-native-transaction-core
    provides: RR-EDIT-PROJECTION-1, explicit confirmation, and captured-exact restore
  - phase: 05-curated-replacement-vertical
    provides: current pure preview/replay lifecycle pattern
provides:
  - Exact reveal_bundle then visibility remove reduction
  - Closed degraded_demo_fixture authorization boundary
  - Revision-neutral preview/cancel and atomic r+1 confirmation
  - Captured-exact remove inverse for later compensation
affects: [06-02-native-remove-authority, 06-03-demo-fixture-ui, 06-04-removal-evidence]
tech-stack:
  added: []
  patterns: [pure reducer replay, closed degraded fixture policy, projection-scoped inverse]
key-files:
  created:
    - ios/Packages/ReRoomContracts/Sources/ReRoomTransactionCore/RemoveReducer.swift
    - ios/Packages/ReRoomContracts/Tests/ReRoomTransactionCoreTests/RemoveReducerTests.swift
  modified: []
key-decisions:
  - "The reducer accepts only degraded_demo_fixture with RR-DEMO-REMOVE-VALIDATOR-1 and deterministic_demo_pose_bound while normal remove readiness remains unavailable."
  - "Reveal activation precedes visibility in the operation list, while both fields become visible canonically only through one atomic projection application."
  - "The degraded validator records only the five contract-required checks and emits no physical coverage, vote, seam, provider, foreground, or gate evidence."
trace-requirements: [FR-REMOVE-001]
formal-acceptance: pending
coverage:
  - id: D1
    description: Exact deterministic degraded-fixture remove preview, cancel, confirmation, and inverse
    requirement: FR-REMOVE-001
    verification:
      - kind: unit
        ref: "swift test --package-path ios/Packages/ReRoomContracts --filter RemoveReducerTests"
        status: pass
    human_judgment: false
  - id: D2
    description: Adjacent projection, replace, and restore behavior remains unchanged
    requirement: FR-REMOVE-001
    verification:
      - kind: regression
        ref: "swift test --package-path ios/Packages/ReRoomContracts --filter 'RemoveReducerTests|ReplaceReducerTests|RestoreReducerTests|EditProjectionTests'"
        status: pass
    human_judgment: false
duration: 5min
completed: 2026-07-18
status: plan-implementation-complete
---

# Phase 6 Plan 01: Exact Degraded-Fixture Remove Reducer Summary

**A pure Swift reducer now authorizes only the closed degraded demo fixture, emits reveal-before-visibility operations, and produces an atomic pending scene with a captured-exact inverse.**

## Performance

- **Duration:** 5 min
- **Started:** 2026-07-18T18:21:09Z
- **Completed:** 2026-07-18T18:26:33Z
- **Feature cycles:** 1 RED/GREEN cycle
- **Files created:** 2

## Accomplishments

- Added remove-specific candidate, seed, reduction, cancellation, confirmation, and typed rejection values without changing frozen contracts.
- Bound acceptance to one selected tracked visible target, current native branch/world/revision, one `envelope_*`, one local valid `reveal_bundle`, and the exact degraded policy identifiers.
- Emitted exactly `set_reveal_bundle` followed by `set_object_visibility`; preview and cancel retain revision `r`, while explicit confirmation constructs one pending `r+1` scene.
- Captured the complete committed and prior RR-EDIT-PROJECTION-1 snapshots in one `restore_snapshot` inverse.
- Rejected normal-ready state, unsupported/stale views, injected intent artifacts, invalid reveal references, unavailable local artifacts, tampered order/before-state/unions, and authority mismatches without mutating input state.

## Task Commits

1. **RED:** `70a103d` — failing exact remove reducer coverage.
2. **GREEN:** `de488aa` — closed degraded-fixture remove reducer and remove-specific seed.

## TDD Gate Compliance

- RED failed for the intended missing `RemoveReducer`, `RemoveRejection`, candidate, seed, and reduction types.
- GREEN passed after the minimum two-file implementation.
- The focused suite contains five Swift Testing declarations, including 25 parameterized boundary cases and seven parameterized preview-tampering cases.

## Verification

- `RemoveReducerTests`: **5 tests passed**, including all parameterized boundary and tamper arguments.
- Adjacent `RemoveReducer`, `ReplaceReducer`, `RestoreReducer`, and `EditProjection` selection: **14 tests across four suites passed**.
- `git show --check de488aa`: passed.
- Focused source/test credential scan: no findings.
- No package, schema, app, UI, resource, project-file, network, filesystem, provider, or cloud change was made.

## Decisions Made

- Required ordinary target remove readiness to remain exactly `unavailable`; a ready normal path cannot invoke this sprint-only reducer.
- Required `degraded_demo_fixture`, `RR-DEMO-REMOVE-VALIDATOR-1`, and `deterministic_demo_pose_bound` together so changing cosmetic copy cannot promote the fixture.
- Required proposal arguments, constraints, and target-context artifact references to be empty. Deterministic native policy supplies target, view, reveal reference, integrity, availability, and world bindings.
- Applied both target edit-state fields together in the provisional projection because an active reveal on a still-visible object is contract-invalid, while retaining the required reveal-first operation journal order.

## Deviations from Plan

None - the plan was executed exactly within its two-file contract-core scope.

## Issues Encountered

None.

## User Setup Required

None.

## Next Phase Readiness

- Plan 06-02 can route preview and commit through the sole native branch authority using these immutable reduction values.
- App launch gating, bounded proxy rendering, resource integrity, UI coaching, durable authority/restart behavior, and automated preflight remain for later Phase 6 plans.
- Formal `FR-REMOVE-001` acceptance and `GATE-006` remain **PENDING** because no physical reveal coverage, foreground result, seam/order measurement, or five-person blinded vote was produced. `GATE-003`, `GATE-005`, `GATE-009`, and `OPS-GOLDEN-001` also remain **PENDING**.
- This summary records Plan 06-01 implementation only; it is not a Phase 6, release, physical-quality, or gate-completion claim.

## Self-Check: PASSED

- Both declared source/test artifacts exist.
- RED commit `70a103d` and GREEN commit `de488aa` exist.
- Both focused verification commands passed.
- No physical/human evidence or formal gate state was changed.

---
*Phase: 06-controlled-multi-surface-removal*
*Plan implementation completed: 2026-07-18*
