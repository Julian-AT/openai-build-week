---
phase: 03-typed-place-commit-and-offline-restore
plan: "03"
subsystem: transaction-reducers
tags: [swift, swift-testing, rr-edit-projection-1, rr-restore-rebase-1, offline-restore]

requires:
  - phase: 03-typed-place-commit-and-offline-restore
    plan: "01"
    provides: exact SceneState/transaction values, frozen schema adapter, and immutable transaction oracle
provides:
  - complete RR-EDIT-PROJECTION-1 builder, validator, digest, diff, artifact-union, and touched-value application
  - pure latest-eligible RR-RESTORE-REBASE-1 reduction with immutable captured-exact inverse verification
  - fresh pending compensating transaction/inverse and preservation/failure regression coverage
affects: [03-02, 03-04, 03-05, 03-06, 03-07, mode-b0]

tech-stack:
  added: []
  patterns:
    - closed stable-ID maps with lexicographic projection arrays
    - projection-member-only canonical JCS SHA-256
    - touched-value equality before current-complete inverse rebase
    - pure pending compensation values with zero provider or network access

key-files:
  created:
    - ios/Packages/ReRoomContracts/Sources/ReRoomTransactionCore/EditProjection.swift
    - ios/Packages/ReRoomContracts/Sources/ReRoomTransactionCore/RestoreReducer.swift
    - ios/Packages/ReRoomContracts/Tests/ReRoomTransactionCoreTests/EditProjectionTests.swift
    - ios/Packages/ReRoomContracts/Tests/ReRoomTransactionCoreTests/RestoreReducerTests.swift
  modified: []

key-decisions:
  - "Projection construction sorts complete object edit state, placed assets, and asset-subject support relations while rejecting duplicate, dangling, or semantically invalid values."
  - "Restore selects the latest uncompensated branch edit, validates its captured-exact inverse and ordered operations, then applies only operation-verified touched IDs to the current projection."
  - "A restore reduction emits a fresh pending r+1 compensation and fresh inverse; durable activation and lifecycle publication remain owned by Plan 03-04."

patterns-established:
  - "Projection boundary: semantic/tracking/readiness/surface/history/timestamp envelopes never enter RR-EDIT-PROJECTION-1 or its digest."
  - "Restore boundary: source and input values are immutable; every mismatch rejects before a pending scene or transaction value exists."

requirements-completed: [FR-RESTORE-001, FR-TRANSACTION-001]

coverage:
  - id: D1
    description: "RR-EDIT-PROJECTION-1 is complete, sorted, unique, referentially valid, hash-exact, and exposes exact touched-ID and artifact-union helpers."
    requirement: FR-TRANSACTION-001
    verification:
      - kind: unit
        ref: "ios/Packages/ReRoomContracts/Tests/ReRoomTransactionCoreTests/EditProjectionTests.swift#construction is complete, sorted, and hashes only the projection member"
        status: pass
      - kind: unit
        ref: "ios/Packages/ReRoomContracts/Tests/ReRoomTransactionCoreTests/EditProjectionTests.swift#semantic projection corruption rejects before output"
        status: pass
      - kind: unit
        ref: "ios/Packages/ReRoomContracts/Tests/ReRoomTransactionCoreTests/EditProjectionTests.swift#diff, ordered operations, artifact union, and touched application are exact"
        status: pass
    human_judgment: false
  - id: D2
    description: "RR-RESTORE-REBASE-1 verifies the latest eligible captured inverse and creates a fresh offline compensation and inverse at pending r+1."
    requirement: FR-RESTORE-001
    verification:
      - kind: unit
        ref: "ios/Packages/ReRoomContracts/Tests/ReRoomTransactionCoreTests/RestoreReducerTests.swift#latest eligible restore rebases only touched IDs and creates fresh immutable compensation"
        status: pass
      - kind: integration
        ref: "swift test --package-path ios/Packages/ReRoomContracts --filter RestoreReducerTests"
        status: pass
    human_judgment: false
  - id: D3
    description: "New/unaffected edit state and excluded live semantic evidence survive; drift, corruption, eligibility, identity, and artifact failures reject non-destructively."
    requirement: FR-RESTORE-001
    verification:
      - kind: unit
        ref: "ios/Packages/ReRoomContracts/Tests/ReRoomTransactionCoreTests/RestoreReducerTests.swift#corruption, drift, eligibility, identity, and artifact failures are non-destructive"
        status: pass
      - kind: integration
        ref: "swift test --package-path ios/Packages/ReRoomContracts"
        status: pass
    human_judgment: false

duration: 11min
completed: 2026-07-18
status: complete
---

# Phase 3 Plan 3: Exact Edit Projection and Offline Restore Rebase Summary

**RR-EDIT-PROJECTION-1 and RR-RESTORE-REBASE-1 now form a pure, offline, fail-closed reducer that compensates only verified touched edit content while preserving the current complete scene.**

## Performance

- **Duration:** 11 min
- **Started:** 2026-07-18T14:00:00Z
- **Completed:** 2026-07-18T14:10:00Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Built complete lexicographically ordered edit projections with strict identity, reference, digest, touched-set, operation-order, and exact artifact-union validation.
- Built latest-eligible restore reduction that validates captured-exact source hashes/operations, rejects touched drift, and rebases only verified touched values over the current projection.
- Proved new objects, readiness, surfaces, non-asset support, unaffected assets, immutable source bytes, and every excluded live field survive while a fresh pending compensation and inverse are created with zero network reads.

## Task Commits

Each behavior-bearing task used a distinct RED then GREEN commit:

1. **Task 1 RED: failing edit projection semantics** - `4e958b6` (test)
2. **Task 1 GREEN: exact edit projection engine** - `9d053b1` (feat)
3. **Task 2 RED: failing restore rebase semantics** - `8a0164c` (test)
4. **Task 2 GREEN: offline restore rebase reducer** - `2ef2281` (feat)

## Files Created/Modified

- `ios/Packages/ReRoomContracts/Sources/ReRoomTransactionCore/EditProjection.swift` - Complete projection build/validation/digest/diff/artifact/touched application engine.
- `ios/Packages/ReRoomContracts/Sources/ReRoomTransactionCore/RestoreReducer.swift` - Latest-eligible captured-inverse validation and pure fresh compensation reduction.
- `ios/Packages/ReRoomContracts/Tests/ReRoomTransactionCoreTests/EditProjectionTests.swift` - Exact digest-scope, ordering, reference, artifact, touched, and corruption tests.
- `ios/Packages/ReRoomContracts/Tests/ReRoomTransactionCoreTests/RestoreReducerTests.swift` - Offline preservation and eight-case non-destructive rejection matrix.

## Decisions Made

- Kept the reducer synchronous and value-only. It accepts local typed values and artifact inventory, performs no provider/network access, and returns a pending result for the later sole-writer durability plan.
- Validated source forward operations by replaying their exact typed values from the inverse's pre-edit projection and requiring the result to equal the persisted committed projection.
- Required local artifacts for both the derived restore result and its fresh inverse, so a successful restore remains compensable offline.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Required artifacts for the fresh inverse as well as the restore result**
- **Found during:** Task 2 GREEN implementation
- **Issue:** The initial success fixture listed only the artifact needed after restore. The fresh compensating inverse must also retain every artifact required to render the prior current projection.
- **Fix:** The reducer validates local availability for the union needed by both forward and fresh-inverse snapshots; the success fixture now supplies both manifest revisions.
- **Files modified:** `RestoreReducer.swift`, `RestoreReducerTests.swift`
- **Verification:** The exact restore suite passes and the missing-artifact case still rejects non-destructively.
- **Committed in:** `2ef2281`

---

**Total deviations:** 1 auto-fixed bug
**Impact on plan:** Strengthened the specified offline restore/inverse durability guarantee without changing schema, dependency, provider, or network scope.

## TDD Gate Compliance

- Task 1 RED failed because `EditProjectionEngine`/`EditProjectionRejection` did not exist; GREEN passes 3 tests, including 5 parameterized corruptions.
- Task 2 RED failed because `RestoreReducer`/`RestoreRequest`/`RestoreRejection` did not exist; GREEN passes 2 tests, including 8 parameterized failure cases.
- The complete package regression passes 110 tests across 17 suites.

## Verification

- `swift test --package-path ios/Packages/ReRoomContracts --filter EditProjectionTests` — 3 tests in 1 suite passed.
- `swift test --package-path ios/Packages/ReRoomContracts --filter RestoreReducerTests` — 2 tests in 1 suite passed.
- `swift test --package-path ios/Packages/ReRoomContracts` — 110 tests in 17 suites passed.
- CON-003 and CON-005 schema SHA-256 values remain exactly unchanged.
- No dependency, network/provider surface, schema, credential, or implementation stub was added.
- Scoped secret scan and `git diff --check` pass.

## User Setup Required

None - this plan is deterministic local Swift code and adds no dependency or service configuration.

## Next Phase Readiness

- Ready for `03-02-PLAN.md` to consume the shared projection engine for typed/tap intent, exact fingerprinting, and place reduction.
- Ready for `03-04-PLAN.md` after Plan 03-02 to persist/activate the pending compensation through the sole native authority.
- GATE-009, GATE-010, physical-device, reconnect, and human evidence remain pending; this plan does not promote them.

---
*Phase: 03-typed-place-commit-and-offline-restore*
*Completed: 2026-07-18*

## Self-Check: PASSED

- All four plan files exist and both RED/GREEN commit pairs are present.
- Both filtered suites and the 110-test full package regression pass.
- Frozen CON-003/CON-005 schema digests are unchanged.
- Unrelated `.planning/config.json`, Xcode project/scheme, workspace, user data, and local Swift build artifacts remain unstaged.
