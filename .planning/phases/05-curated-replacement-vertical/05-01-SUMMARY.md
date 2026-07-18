---
phase: 05-curated-replacement-vertical
plan: "01"
subsystem: deterministic-transactions
tags: [swift, swift-testing, replace, edit-projection, captured-exact-inverse]

requires:
  - phase: 03-typed-place-commit-and-offline-restore
    provides: typed transaction models, exact edit projection engine, preview/confirm lifecycle, and captured-exact restore semantics
  - phase: 04-target-grounding-and-compositor-gate
    provides: stable selected target identity, exact world epoch, and degraded manual-proxy fallback policy
provides:
  - pure no-reveal replace preview/cancel/confirm reducer
  - exact set_object_visibility then create_asset_instance operation sequence
  - fail-closed target, view, support, asset, authority, world, revision, and integrity validation
  - one captured-exact RR-EDIT-PROJECTION-1 inverse for each confirmed replace
affects: [05-02, 05-03, 05-04, native-branch-authority, replace-restore]

tech-stack:
  added: []
  patterns:
    - deterministic candidate values own target, readiness, view, transform, support, and asset-policy verdicts
    - preview replay before cancellation or confirmation
    - projection diff verification before publishing a provisional result

key-files:
  created:
    - ios/Packages/ReRoomContracts/Sources/ReRoomTransactionCore/ReplaceReducer.swift
    - ios/Packages/ReRoomContracts/Tests/ReRoomTransactionCoreTests/ReplaceReducerTests.swift
  modified: []

key-decisions:
  - "Use only the canonical no-reveal replace order: hide the selected visible object first, then create its replacement asset and support relation atomically."
  - "Accept the sprint fallback only as explicit degraded manual_proxy_fallback readiness bound to one deterministic supported-view fixture."
  - "Permit intent bytes to select only the allowlisted asset ID; all mutation-authorizing target, spatial, readiness, and policy values come from deterministic candidate state."
  - "Construct one captured-exact projection inverse from committed content back to the exact prior edit projection without claiming GATE-011 completion."

patterns-established:
  - "Replace validation: target, capability, view fixture, support, asset policy, world, and revision must all be current before any provisional projection exists."
  - "Replace confirmation: replay the immutable preview against current state, then construct pending r+1 content and its exact inverse without mutating the input scene."

requirements-completed: [FR-REPLACE-001]

coverage:
  - id: D1
    description: "A valid bounded local replacement preview is byte-stable, revision-neutral, and emits exactly visibility then asset creation with no reveal operation."
    requirement: FR-REPLACE-001
    verification:
      - kind: unit
        ref: "ios/Packages/ReRoomContracts/Tests/ReRoomTransactionCoreTests/ReplaceReducerTests.swift#previewIsOrderedStableAndNonmutating"
        status: pass
      - kind: unit
        ref: "swift test --package-path ios/Packages/ReRoomContracts --filter ReplaceReducerTests"
        status: pass
    human_judgment: false
  - id: D2
    description: "Replace rejects every stale or unauthorized target/view/support/asset boundary without mutation, and explicit confirmation produces one pending revision with one captured-exact inverse."
    requirement: FR-REPLACE-001
    verification:
      - kind: unit
        ref: "ios/Packages/ReRoomContracts/Tests/ReRoomTransactionCoreTests/ReplaceReducerTests.swift#failuresAreNonDestructive,cancelAndConfirm,confirmationFailsClosed"
        status: pass
      - kind: integration
        ref: "swift test --package-path ios/Packages/ReRoomContracts"
        status: pass
    human_judgment: false

duration: 7min
completed: 2026-07-18
status: complete
---

# Phase 5 Plan 1: Exact No-Reveal Replace Reduction Summary

**A pure Swift reducer now validates the bounded local replacement fallback, emits the exact visibility-to-asset delta order, and produces a revision-neutral preview plus captured-exact compensating inverse.**

## Performance

- **Duration:** 7 min
- **Started:** 2026-07-18T17:54:47Z
- **Completed:** 2026-07-18T18:01:18Z
- **Tasks:** 1 TDD feature
- **Files modified:** 2

## Accomplishments

- Added a dedicated replace reducer rather than routing replacement through place or presentation-only state.
- Bound replacement to one visible tracked stable target, current revision/world, explicit degraded fallback readiness, deterministic supported-view fixture, current support, and allowlisted local asset policy.
- Emitted exactly `set_object_visibility` followed by `create_asset_instance`; no reveal operation or measured geometry claim is introduced.
- Kept preview and cancel revision-neutral, replayed preview on confirmation, and created one pending `r+1` scene with one exact `restore_snapshot` inverse.
- Proved 20 parameterized failure variants leave the input scene and edit history unchanged.

## Task Commits

The behavior-bearing task followed RED then GREEN:

1. **RED: define exact replace reducer contract** - `8631a4a` (test)
2. **GREEN: implement deterministic no-reveal replace reduction** - `300931f` (feat)

## Files Created/Modified

- `ios/Packages/ReRoomContracts/Sources/ReRoomTransactionCore/ReplaceReducer.swift` - Pure candidate validation, exact ordered operations, replayable cancel/confirm, pending scene construction, receipt candidate, and captured-exact inverse.
- `ios/Packages/ReRoomContracts/Tests/ReRoomTransactionCoreTests/ReplaceReducerTests.swift` - Exact order/nonmutation, 20 fail-closed policy cases, confirmation binding, pending revision, and inverse projection coverage.

## Decisions Made

- Reused the established `ProxyAssetCandidate`, `DeterministicSupportCandidate`, `PlacePreviewSeed`, and `PlaceConfirmationRequest` values where their semantics are identical; replace-specific target/readiness/view state remains a dedicated type.
- Restricted this sprint reducer to `capabilityReadiness=degraded` with `readinessSource=manual_proxy_fallback`; provider-ready or reveal-backed variants require their own validated evidence rather than implicit promotion.
- Included `view_envelope` in the validation report for the deterministic demo fixture even though the no-reveal contract variant does not require a reveal artifact.
- Left persistence, idempotency lookup, CAS activation, restart recovery, and UI integration to the dependent Phase 5 plans.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- SwiftPM recreated the exact generated `ios/Packages/ReRoomContracts/.build/` directory during verification. It was removed after the passing runs to preserve disk space; source and test files were unaffected and the output is fully rebuildable.

## TDD Gate Compliance

- RED failed on the intentionally absent `ReplaceReducer`, `ReplaceRejection`, `DeterministicReplaceCandidate`, and reduction result types.
- GREEN added only the planned reducer source and made the focused tests pass.
- No refactor commit was necessary; the implementation reuses the existing projection, fingerprint, asset, support, preview, confirmation, and receipt interfaces.

## Verification

- `swift test --package-path ios/Packages/ReRoomContracts --filter ReplaceReducerTests` — passed: 4 Swift Testing functions, including 20 parameterized fail-closed cases.
- `swift test --package-path ios/Packages/ReRoomContracts` — passed with direct exit code 0; all package suites remained green.
- Scoped placeholder/stub scan — passed; no TODO, FIXME, placeholder, unimplemented trap, network, provider, or cloud path was introduced.
- `git diff --check` — passed for both planned files.
- Phase 5 plan recheck — passed with no 05-01 blockers.

## User Setup Required

None. This slice adds pure local Swift behavior and tests only; it requires no provider, account, dependency, network, cloud, schema, or Xcode project change.

## Next Phase Readiness

- Ready for Plan 05-02 to route replace through the sole native branch authority, durable generation store, idempotent retry, restart replay, and compensating restore.
- Formal asset parity/licensing/device evidence under `GATE-011`, physical compositor evidence, and signed-device golden journeys remain `PENDING`; this reducer does not promote any gate.

---
*Phase: 05-curated-replacement-vertical*
*Completed: 2026-07-18*

## Self-Check: PASSED

- Both planned files exist and commits `8631a4a` and `300931f` are present.
- Focused and full Swift package test commands passed from the committed GREEN source.
- Only the two planned source/test files and this summary belong to Plan 05-01; user configuration, Xcode project/scheme, package workspace state, and Xcode user/workspace data remain unstaged.
