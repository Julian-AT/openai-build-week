---
phase: 05-curated-replacement-vertical
plan: "02"
subsystem: native-transaction-authority
tags: [swift, actor, idempotency, durability, restore, bootstrap]
requires:
  - phase: 05-curated-replacement-vertical
    provides: exact pure no-reveal replace reducer from Plan 01
  - phase: 03-deterministic-native-transaction-core
    provides: pointer-last generation store and captured-exact restore
provides:
  - Replace preview and commit through the sole NativeBranchAuthority
  - Restart-safe exactly-once replace receipts and compensating restore
  - Versioned Phase 5 bootstrap with one exact controlled target
  - Fail-closed handling for recovered empty pre-Phase-5 generations
affects: [05-03-native-replace-ui, 05-04-evidence, phase-06-remove]
tech-stack:
  added: []
  patterns: [synchronous actor-isolated CAS, pointer-last activation, additive semantic object recovery]
key-files:
  created: []
  modified:
    - ios/Packages/ReRoomContracts/Sources/ReRoomTransactionCore/TransactionAuthority.swift
    - ios/Packages/ReRoomContracts/Sources/ReRoomTransactionCore/TransactionStore.swift
    - ios/Packages/ReRoomContracts/Tests/ReRoomTransactionCoreTests/TransactionAuthorityTests.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/RoomEditModel.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProofTests/RoomEditModelTests.swift
key-decisions:
  - "Replace uses the existing sole actor authority and pointer-last store; no second writer or acknowledgement path was added."
  - "A versioned Phase 5 app store starts with the exact stable controlled object; recovered empty generations remain readable but cannot authorize replace."
  - "Newly tracked objects may add to the current edit projection only when every prior committed object and all asset/support state remain exact."
patterns-established:
  - "Same idempotency key and fingerprint resolves before CAS; changed content conflicts without filesystem mutation."
  - "Semantic tracking may extend object identity additively, while transaction-owned assets and supports remain exact."
requirements-implemented: [FR-REPLACE-001]
coverage:
  - id: D1
    description: Durable, idempotent, restart-safe replace through NativeBranchAuthority
    requirement: FR-REPLACE-001
    verification:
      - kind: integration
        ref: "swift test --package-path ios/Packages/ReRoomContracts --filter 'TransactionAuthorityTests|TransactionStoreCrashTests|RestoreReducerTests'"
        status: pass
    human_judgment: false
  - id: D2
    description: Phase 5 bootstrap and recovered-empty-generation compatibility behavior
    requirement: FR-REPLACE-001
    verification:
      - kind: integration
        ref: "xcodebuild test -project ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj -scheme ReRoomDeviceProof -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:ReRoomDeviceProofTests/RoomEditModelTests"
        status: pass
    human_judgment: false
duration: 11min
completed: 2026-07-18
status: plan-implementation-complete
---

# Phase 5 Plan 02: Durable Replace Authority Summary

**Replacement now commits exactly once through the native branch actor, survives pointer-last recovery, restores without deleting newly tracked objects, and starts from one versioned canonical target.**

## Performance

- **Duration:** 11 min
- **Started:** 2026-07-18T18:07:16Z
- **Completed:** 2026-07-18T18:18:18Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments

- Added `previewReplace`/`commitReplace` to `NativeBranchAuthority` with the existing fingerprint, idempotency, CAS, divergence, confirmation, inverse, and durable activation invariants.
- Proved concurrent retry, changed-fingerprint conflict, pointer activation fault recovery, immutable replay, and replace-to-restore preservation of newly tracked unrelated state.
- Versioned the app-local store and seeded one visible tracked object whose ID exactly matches the manual target; old empty generations expose an explicit fresh-room message and unavailable replace readiness.
- Added deterministic tap proposal and local candidate factories for the next native UI plan without enabling presentation prematurely.

## Task Commits

1. **Task 1 RED:** `e56d374` — failing durable replace authority tests.
2. **Task 1 GREEN:** `65f79c5` — actor authority, durable activation, restart/restore behavior.
3. **Task 2 RED:** `8838775` — failing bootstrap, binding, and old-generation tests.
4. **Task 2 GREEN:** `eb51c79` — versioned target bootstrap and fail-closed compatibility.

## Verification

- Package authority/store/restore selection: **13 tests passed**, including the parameterized **40-case** generation fault matrix.
- `RoomEditModelTests`: **16 distinct tests passed** on the iPhone 17 simulator, retaining place, target, restart, and restore regressions.
- `git diff --check`: passed.
- Focused tracked-source credential scan: no findings.

## Decisions Made

- Kept replacement on the same synchronous actor-isolated critical path as place, so reducer replay, generation activation, and visible publication cannot interleave.
- Used a new `phase5-room-edit-v1` local-store namespace rather than mutating legacy Phase 3 data. Injected old empty generations still fail closed in tests.
- Allowed only additive newly tracked object states beyond the latest committed inverse. Existing object states, placed assets, and asset support relations must remain byte-semantically exact.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Permitted additive semantic object discovery in durable generations**

- **Found during:** Task 1 restore-preservation regression.
- **Issue:** Store validation required the latest inverse projection to equal the entire current projection, contradicting canonical restore preservation when tracking discovers a new unrelated object.
- **Fix:** Added a narrow compatibility check: every committed object must remain exact; only additional object edit states are permitted; assets and asset supports still require exact equality.
- **Files modified:** `TransactionStore.swift`, `TransactionAuthorityTests.swift`.
- **Verification:** The new replace/track/restart/restore test and the existing store/restore fault suites pass.
- **Committed in:** `65f79c5`.

**Total deviations:** 1 auto-fixed (1 missing critical correctness issue).
**Impact on plan:** Required to satisfy the plan's explicit unrelated-state preservation truth; no new dependency, schema, network, or writer was introduced.

## Issues Encountered

- One simulator clone was denied launch while another clone completed the same focused suite; the complete distinct test inventory passed and Xcode returned success.
- The provenance build phase intentionally rejected uncommitted product source during the GREEN cycle. After the atomic GREEN commit, the same focused Xcode test command passed.

## User Setup Required

None.

## Next Phase Readiness

- Plan 05-03 can wire the prepared proposal/candidate factories to preview, explicit confirmation, retry, render state, and Restore.
- Formal `FR-REPLACE-001` acceptance, physical compositing quality, device asset loading, native/web derivative parity, and `GATE-003`, `GATE-005`, `GATE-009`, `GATE-011`, and `OPS-GOLDEN-001` evidence remain `PENDING`; this summary records Plan 05-02 implementation only, not phase acceptance.

## Self-Check: PASSED

- All five modified source/test files exist.
- RED/GREEN commits `e56d374`, `65f79c5`, `8838775`, and `eb51c79` exist.
- Both focused verification commands passed.

---
*Phase: 05-curated-replacement-vertical*
*Completed: 2026-07-18*
