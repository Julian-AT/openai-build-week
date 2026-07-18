---
phase: 06-controlled-multi-surface-removal
plan: "02"
subsystem: native-transaction-authority
tags: [swift, actor, remove, idempotency, durability, crash-recovery, restore]
requires:
  - phase: 06-controlled-multi-surface-removal
    provides: exact degraded-fixture remove reduction and captured-exact inverse
  - phase: 03-deterministic-native-transaction-core
    provides: sole branch authority, pointer-last transaction store, and restore rebase
provides:
  - Sole-authority preview and commit path for deterministic remove
  - Exactly-once remove retry across concurrency and restart
  - Pointer-last remove recovery coverage at all 40 injected store boundaries
  - Remove-to-restore proof with immutable source history and unrelated-state retention
affects: [06-03-demo-fixture-ui, 06-04-removal-evidence, native-replay, restore]
tech-stack:
  added: []
  patterns: [synchronous actor critical section, retry-before-CAS, pointer-last generation activation]
key-files:
  created: []
  modified:
    - ios/Packages/ReRoomContracts/Sources/ReRoomTransactionCore/TransactionAuthority.swift
    - ios/Packages/ReRoomContracts/Tests/ReRoomTransactionCoreTests/TransactionAuthorityTests.swift
    - ios/Packages/ReRoomContracts/Tests/ReRoomTransactionCoreTests/TransactionStoreCrashTests.swift
key-decisions:
  - "Remove uses the same suspension-free actor-isolated fingerprint, retry, reduction, activation, and publication path as place and replace."
  - "Same-key/same-fingerprint retry is resolved before confirmation, undo-token, CAS, or current-state validation, including after restart."
  - "The remove crash matrix reuses the generic TransactionStore boundaries with a contract-valid deterministic reveal generation."
trace-requirements: [FR-REMOVE-001]
formal-acceptance: pending
coverage:
  - id: D1
    description: Sole-writer remove commit is exactly once, fail closed, durable, and restart safe
    requirement: FR-REMOVE-001
    verification:
      - kind: integration
        ref: "swift test --package-path ios/Packages/ReRoomContracts --filter TransactionAuthorityTests"
        status: pass
    human_judgment: false
  - id: D2
    description: Every injected persistence boundary recovers the complete old or remove generation, and restore preserves unrelated state
    requirement: FR-REMOVE-001
    verification:
      - kind: integration
        ref: "swift test --package-path ios/Packages/ReRoomContracts --filter 'TransactionAuthorityTests|TransactionStoreCrashTests|RestoreReducerTests'"
        status: pass
    human_judgment: false
duration: 10min
completed: 2026-07-18
status: plan-implementation-complete
---

# Phase 6 Plan 02: Durable Sole-Authority Remove Summary

**The native branch authority now publishes one durable degraded-fixture remove, returns the original receipt on exact retry, recovers atomically after every injected store fault, and restores through a new immutable compensation.**

## Performance

- **Duration:** 10 min
- **Started:** 2026-07-18T18:28:25Z
- **Completed:** 2026-07-18T18:38:19Z
- **Feature cycles:** 2 RED/GREEN cycles
- **Files modified:** 3

## Accomplishments

- Added `previewRemove` and `commitRemove` to `NativeBranchAuthority` without a suspension point between fingerprinting, retry lookup, validation, reduction, generation activation, and in-memory publication.
- Proved 16 concurrent identical confirms produce one r13 remove transaction and receipt; restarted exact retry returns that receipt before revalidating confirmation, undo token, or current revision.
- Proved changed fingerprint, stale preview, invalid confirmation or undo token, missing local reveal, divergence quarantine, and pointer activation fault publish no hidden object or partial durable state.
- Proved restart/replay preserves the ordered remove record and projection inverse, while later restore creates r14, clears the reveal, restores visibility, retains newly tracked unrelated state, and leaves source transaction bytes unchanged.
- Added a 40-case remove persistence matrix covering every existing generation create/write/sync and active-pointer boundary.

## Task Commits

1. **Task 1 RED:** `2c641e4` — failing durable remove authority coverage.
2. **Task 1 GREEN:** `5809664` — sole-authority remove publication and contract-valid durable fixture.
3. **Task 2 RED:** `bbaf6d7` — failing remove crash-recovery matrix.
4. **Task 2 GREEN:** `f52491e` — generic candidate-specific fault cases and complete remove generation fixture.

## TDD Gate Compliance

- Task 1 RED failed only because `NativeBranchAuthority` lacked `previewRemove` and `commitRemove`.
- Task 1 GREEN passed all ten authority tests after routing remove through the existing actor-isolated critical path.
- Task 2 RED failed only because the remove generation fixture and candidate-specific fault-case factory did not exist.
- Task 2 GREEN passed all 40 remove persistence fault cases.

## Verification

- `TransactionAuthorityTests`: **10 tests passed**.
- `TransactionStoreCrashTests`, `TransactionAuthorityTests`, and `RestoreReducerTests`: **17 tests across three suites passed**, including 80 total old/new generation fault cases.
- `git show --check 5809664` and `git show --check f52491e`: passed.
- No dependency, schema, network, provider, app UI, resource, or Xcode project change was introduced by this plan.

## Decisions Made

- Reused `PlaceConfirmationRequest` because the frozen confirmation request carries operation-neutral transaction, idempotency, and update-time values; no contract or model alias was added.
- Required the reveal reference in `locallyAvailableArtifacts` and delegated exact required-artifact ordering and deduplication to `TransactionIntegrity.requiredArtifactUnion`.
- Generalized only the test fault-case constructor, keeping one production `TransactionStore` and one pointer-last activation algorithm for place and remove.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Made the durable remove bootstrap fixture satisfy frozen readiness-reason invariants**

- **Found during:** Task 1 GREEN contract validation.
- **Issue:** The reducer-only demo scene represented unavailable readiness values with empty reason arrays. That is sufficient for pure reducer tests but frozen `scene-state.schema.json` requires a non-empty reason for every non-ready capability.
- **Fix:** The authority/store fixture now preserves the exact unavailable readiness states while supplying the allowlisted controlled-fixture reason.
- **Files modified:** `TransactionAuthorityTests.swift`.
- **Verification:** All authority and crash/recovery suites decode the bootstrap and committed scenes through frozen contracts.
- **Committed in:** `5809664`.

---

**Total deviations:** 1 auto-fixed bug.

**Impact on plan:** The fix was test-fixture-only, preserved the closed degraded-remove policy, and did not change product contracts or runtime semantics.

## Issues Encountered

The first GREEN run reported `TransactionStoreError.contractRejected`. Isolating the frozen decoder showed the rejection was the reducer-only bootstrap fixture rather than the remove transaction. Adding required readiness reasons resolved it without broadening remove authorization.

## User Setup Required

None.

## Next Phase Readiness

- Plan 06-03 can bind the app demo fixture to this one durable remove authority path; renderer/UI code must not allocate revisions or bypass local reveal inventory.
- Formal `FR-REMOVE-001` acceptance and `GATE-006` remain **PENDING**. This plan produced deterministic transaction evidence only, not physical reveal coverage, foreground/seam measurements, or five-person blinded voting.
- `GATE-003`, `GATE-005`, `GATE-009`, and `OPS-GOLDEN-001` also remain **PENDING**.
- This summary records Plan 06-02 implementation only; it is not a Phase 6, release, device-quality, or human-gate completion claim.

## Self-Check: PASSED

- All three declared implementation/test artifacts exist.
- Both RED/GREEN commit pairs exist.
- Focused verification passed with exact restart, replay, idempotency, crash, and restore assertions.
- No physical or human evidence was fabricated and no formal gate state was changed.

---
*Phase: 06-controlled-multi-surface-removal*
*Plan implementation completed: 2026-07-18*
