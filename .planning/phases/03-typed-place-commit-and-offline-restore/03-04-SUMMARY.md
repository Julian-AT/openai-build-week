---
phase: 03-typed-place-commit-and-offline-restore
plan: "04"
subsystem: transaction-authority
tags: [swift, swift-testing, actors, cas, idempotency, crash-safety, offline-restore]

requires:
  - phase: 03-typed-place-commit-and-offline-restore
    plan: "02"
    provides: trusted typed/tap proposal binding, exact request fingerprinting, and pure place preview/confirmation reduction
  - phase: 03-typed-place-commit-and-offline-restore
    plan: "03"
    provides: exact edit projection, captured inverse verification, and pure offline restore rebase
provides:
  - immutable content-addressed transaction generations with synchronized active-pointer-last publication and fail-closed recovery
  - sole native branch-authority actor with synchronous CAS, persistent idempotency, durable activation, and divergence freeze
  - exact concurrent retry, restart, offline place/restore, fault-matrix, and quarantine evidence
affects: [03-05, 03-06, 03-07, native-mode-a, mode-b0]

tech-stack:
  added: []
  patterns:
    - immutable canonical multi-file generations selected only by one synchronized active pointer
    - synchronous no-suspension actor critical sections for CAS through durable activation
    - persistent fingerprint-keyed idempotency receipts and explicit same-branch quarantine

key-files:
  created:
    - ios/Packages/ReRoomContracts/Sources/ReRoomTransactionCore/TransactionFileSystemAdapter.swift
    - ios/Packages/ReRoomContracts/Sources/ReRoomTransactionCore/TransactionStore.swift
    - ios/Packages/ReRoomContracts/Sources/ReRoomTransactionCore/TransactionAuthority.swift
    - ios/Packages/ReRoomContracts/Tests/ReRoomTransactionCoreTests/TransactionStoreCrashTests.swift
    - ios/Packages/ReRoomContracts/Tests/ReRoomTransactionCoreTests/TransactionAuthorityTests.swift
  modified: []

key-decisions:
  - "Publish every canonical generation member and inventory durably before atomically replacing and synchronizing the sole active-generation pointer."
  - "Keep CAS, fingerprint/idempotency decisions, pure reduction, store activation, and actor state publication in synchronous actor-isolated critical functions with no suspension point."
  - "Return an existing durable receipt before current-revision validation for an exact same-key/same-fingerprint retry, while changed fingerprints conflict without writes."
  - "Represent unexpected same-branch divergence as two preserved typed snapshots plus an explicit manual quarantine that freezes new mutation and never permits automatic merge."

requirements-completed: [FR-PLACE-001, FR-RESTORE-001, FR-TRANSACTION-001]

coverage:
  - id: D1
    description: "Immutable transaction generations validate exact schemas, hashes, semantic links, inverse/artifact inventory, receipts, and idempotency before pointer-last publication or recovery."
    requirement: FR-TRANSACTION-001
    verification:
      - kind: integration
        ref: "ios/Packages/ReRoomContracts/Tests/ReRoomTransactionCoreTests/TransactionStoreCrashTests.swift#every generation write sync and pointer edge recovers the exact old or new generation"
        status: pass
      - kind: integration
        ref: "swift test --package-path ios/Packages/ReRoomContracts --filter TransactionStoreCrashTests"
        status: pass
    human_judgment: false
  - id: D2
    description: "One native actor enforces exact CAS, persistent idempotency, authority/branch identity, monotonic revision allocation, and durable acknowledgement under concurrency and restart."
    requirement: FR-TRANSACTION-001
    verification:
      - kind: integration
        ref: "ios/Packages/ReRoomContracts/Tests/ReRoomTransactionCoreTests/TransactionAuthorityTests.swift#concurrent identical confirms serialize to one durable revision and one receipt"
        status: pass
      - kind: integration
        ref: "ios/Packages/ReRoomContracts/Tests/ReRoomTransactionCoreTests/TransactionAuthorityTests.swift#changed fingerprint stale base and wrong authority reject without filesystem writes"
        status: pass
      - kind: other
        ref: "TransactionAuthority.swift critical-function no-await and module import scans"
        status: pass
    human_judgment: false
  - id: D3
    description: "Confirmed place and compensating restore remain exact and offline across two restarts; divergence preserves both histories, quarantines, freezes, and performs no automatic merge."
    requirement: FR-RESTORE-001
    verification:
      - kind: integration
        ref: "ios/Packages/ReRoomContracts/Tests/ReRoomTransactionCoreTests/TransactionAuthorityTests.swift#place then explicit offline restore survives restart with exact immutable trace"
        status: pass
      - kind: integration
        ref: "ios/Packages/ReRoomContracts/Tests/ReRoomTransactionCoreTests/TransactionAuthorityTests.swift#same-branch divergence preserves both snapshots quarantines and freezes mutation"
        status: pass
      - kind: integration
        ref: "swift test --package-path ios/Packages/ReRoomContracts"
        status: pass
    human_judgment: false

duration: 17min
completed: 2026-07-18
status: complete
---

# Phase 3 Plan 4: Crash-Safe Native Branch Authority Summary

**Native place and restore now commit through one non-reentrant actor into immutable, content-addressed generations whose synchronized active pointer is the only visibility boundary.**

## Performance

- **Duration:** 17 min
- **Started:** 2026-07-18T14:29:00Z
- **Completed:** 2026-07-18T14:45:49Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments

- Added a transaction-named synchronous adapter and immutable generation store that binds canonical scene, history, inverse inventory, artifacts, receipts, idempotency, inventory, and active-pointer identity through exact hashes and frozen-contract validation.
- Added the sole `NativeBranchAuthority` actor, keeping exact retry lookup, CAS, place/restore reduction, generation activation, and active-state update in synchronous actor-isolated critical sections.
- Proved 40 before/after filesystem crash edges, Foundation/in-memory parity, 16-way concurrent place and restore retries, persistent retry equality across restart, exact `r8 → r9 → r10` offline history, and fail-closed divergence quarantine.

## Task Commits

Each behavior-bearing task used a distinct RED then GREEN commit:

1. **Task 1 RED: failing transaction generation crash matrix** - `0b3486f` (test)
2. **Task 1 GREEN: atomic content-addressed transaction store** - `9661965` (feat)
3. **Task 2 RED: failing native branch-authority scenarios** - `9b3e5d1` (test)
4. **Task 2 GREEN: serialized durable native branch authority** - `4c51b3c` (feat)

## Files Created/Modified

- `ios/Packages/ReRoomContracts/Sources/ReRoomTransactionCore/TransactionFileSystemAdapter.swift` - Bounded synchronous transaction durability operations over `any CaptureFileSystem`.
- `ios/Packages/ReRoomContracts/Sources/ReRoomTransactionCore/TransactionStore.swift` - Canonical generation creation, preflight validation, active-pointer-last activation, and pointer-only recovery.
- `ios/Packages/ReRoomContracts/Sources/ReRoomTransactionCore/TransactionAuthority.swift` - Sole native actor for preview, CAS, idempotency, place, restore, restart, and divergence freeze.
- `ios/Packages/ReRoomContracts/Tests/ReRoomTransactionCoreTests/TransactionStoreCrashTests.swift` - Forty-case fault matrix, filesystem parity, corruption, and zero-mutation preflight coverage.
- `ios/Packages/ReRoomContracts/Tests/ReRoomTransactionCoreTests/TransactionAuthorityTests.swift` - Concurrency, conflict, branch identity, restart, retry, offline restore, and quarantine coverage.

## Decisions Made

- Follow only a schema-valid active pointer during recovery. Incomplete or newer-looking directories are never selected by time, name, or scan order.
- Treat the final root-directory synchronization as the durable publication edge; root preparation synchronizes only when it actually creates directories.
- Perform durable idempotency lookup before new-mutation CAS so an exact retry remains stable even after its original base revision is no longer current.
- Keep canonical transaction lifecycle independent from `local_only` synchronization state and preserve all source transaction bytes when creating restore compensation.
- Freeze the actor on unexpected same-branch divergence while retaining both typed snapshots and explicit manual quarantine metadata; no automatic merge or storage overwrite occurs.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Removed a redundant root-directory sync before every activation**
- **Found during:** Task 1 fault-matrix GREEN cycle
- **Issue:** Re-synchronizing an already-prepared root introduced an earlier operation indistinguishable from the required final active-pointer directory sync in deterministic crash injection.
- **Fix:** Root preparation synchronizes only when creating the root or generations directory; the final root sync is now the unambiguous publication boundary.
- **Files modified:** `TransactionFileSystemAdapter.swift`, `TransactionStoreCrashTests.swift`
- **Verification:** All 40 pre/post operation fault cases recover the exact prior or exact new generation.
- **Committed in:** `9661965`

**2. [Rule 1 - Bug] Normalized Foundation temporary paths independently of `/var` symlink spelling**
- **Found during:** Task 1 Foundation/in-memory parity
- **Issue:** macOS enumerated `/private/var/...` while the temporary root was supplied as `/var/...`, producing false relative-path mismatches despite identical bytes.
- **Fix:** The parity helper derives transaction-relative paths from path components and compares every member byte-for-byte.
- **Files modified:** `TransactionStoreCrashTests.swift`
- **Verification:** Foundation and in-memory generation bytes plus operation order match exactly.
- **Committed in:** `9661965`

---

**Total deviations:** 2 auto-fixed bugs
**Impact on plan:** Both fixes strengthen deterministic durability evidence without changing schemas, dependencies, authority, or product scope.

## TDD Gate Compliance

- Task 1 RED failed because the transaction store and adapter APIs did not exist; GREEN passes 4 tests including all 40 injected pre/post filesystem edges.
- Task 2 RED failed because `NativeBranchAuthority`, restore preview, quarantine, and typed authority errors did not exist; GREEN passes 4 end-to-end actor tests.
- The complete package regression passes 129 tests across 21 suites.

## Verification

- `swift test --package-path ios/Packages/ReRoomContracts --filter TransactionStoreCrashTests` — 4 tests in 1 suite passed, including 40 parameterized fault cases.
- `swift test --package-path ios/Packages/ReRoomContracts --filter TransactionAuthorityTests` — 4 tests in 1 suite passed.
- `swift test --package-path ios/Packages/ReRoomContracts` — 129 tests in 21 suites passed.
- Critical-function scan finds no `await` token from CAS through activation and state update.
- `ReRoomTransactionCore` imports contain no network, model, UI, or provider module.
- Scoped secret scan and `git diff --check` pass.

## User Setup Required

None - this plan adds deterministic local Swift code and no dependency, service, account, or environment configuration.

## Next Phase Readiness

- Ready for `03-05-PLAN.md` to add native operation coordination and UI-facing transaction flow over this sole authority.
- Physical-device, reconnect, gateway, and human evidence remain pending under the approved sprint cut; this plan does not promote any gate.

---
*Phase: 03-typed-place-commit-and-offline-restore*
*Completed: 2026-07-18*

## Self-Check: PASSED

- All five planned files exist and both RED/GREEN commit pairs are present.
- Both filtered suites and the 129-test full package regression pass.
- No suspension occurs inside either mutation critical section and no network/model/UI import entered the module.
- Unrelated `.planning/config.json`, Xcode project/scheme, workspace, user data, and local Swift build artifacts remain unstaged.
