---
phase: 03-typed-place-commit-and-offline-restore
plan: "01"
subsystem: transaction-contracts
tags: [swift, swift-testing, con-003, con-005, canonical-json, immutable-fixtures]

requires:
  - phase: 02-capture-replay-and-device-proof
    provides: strict contract validation, canonical JSON, and local capture-core package seams
provides:
  - ReRoomTransactionCore static SwiftPM product with exact transaction and SceneState values
  - strict canonicalize-validate-decode-round-trip adapter for frozen CON-003 and CON-005
  - immutable FX-TRANSACTION-001 oracle for identity, ordering, lifecycle, revision, retry, restore, and rejection traces
affects: [03-02, 03-03, 03-04, 03-05, 03-06, 03-07, mode-b0]

tech-stack:
  added: []
  patterns:
    - canonical JSON before frozen schema validation and typed decode
    - exact typed re-encoding must reproduce the same canonical bytes
    - immutable external fixture bytes pin expected normalized traces

key-files:
  created:
    - ios/Packages/ReRoomContracts/Sources/ReRoomTransactionCore/TransactionModels.swift
    - ios/Packages/ReRoomContracts/Sources/ReRoomTransactionCore/TransactionContractAdapter.swift
    - ios/Packages/ReRoomContracts/Tests/ReRoomTransactionCoreTests/TransactionContractTests.swift
    - fixtures/transactions/1.0.0/rev-001/manifest.json
    - fixtures/transactions/1.0.0/rev-001/cases.json
    - fixtures/transactions/1.0.0/rev-001/expected-traces.json
  modified:
    - ios/Packages/ReRoomContracts/Package.swift

key-decisions:
  - "Keep CON-003/CON-005 schema bytes untouched and bind the implementation through their existing validator registrations."
  - "Expose exactly place, replace, remove, restore in stable allowlist order; transaction and idempotency identity remain distinct from branch authority."
  - "Use one strict adapter pipeline: canonicalize, frozen-schema validate, typed decode, canonical typed round-trip equality."

patterns-established:
  - "Contract adapter: hostile bytes cannot reach typed semantic use until JCS parsing and the frozen schema verdict both accept."
  - "Fixture closure: manifest byte lengths and SHA-256 values bind cases and expected traces; tests never regenerate expected output."

requirements-completed: [FR-PLACE-001, FR-RESTORE-001, FR-TRANSACTION-001, FR-AGENT-001]

coverage:
  - id: D1
    description: "ReRoomTransactionCore provides closed Swift values for scene, authority, intent, operations, validation, preview, confirmation, commit, projection/inverse, reconciliation, and receipts."
    requirement: FR-TRANSACTION-001
    verification:
      - kind: unit
        ref: "ios/Packages/ReRoomContracts/Tests/ReRoomTransactionCoreTests/TransactionContractTests.swift#operation and lifecycle inventories remain closed and stable"
        status: pass
      - kind: integration
        ref: "swift package --package-path ios/Packages/ReRoomContracts describe"
        status: pass
    human_judgment: false
  - id: D2
    description: "Strict CON-003/CON-005 ingress rejects empty, malformed, duplicate, missing, unknown, wrong-version, and wrong-ID-family input before typed use."
    requirement: FR-AGENT-001
    verification:
      - kind: unit
        ref: "ios/Packages/ReRoomContracts/Tests/ReRoomTransactionCoreTests/TransactionContractTests.swift#malformed and hostile contract bytes reject before typed use"
        status: pass
      - kind: integration
        ref: "ios/Packages/ReRoomContracts/Tests/ReRoomTransactionCoreTests/TransactionContractTests.swift#frozen schemas and exact typed adapters accept canonical minimal records"
        status: pass
    human_judgment: false
  - id: D3
    description: "FX-TRANSACTION-001 pins exact place commit/retry/replay, offline restore, identity, operation-order, and fail-closed conflict traces."
    requirement: FR-RESTORE-001
    verification:
      - kind: unit
        ref: "ios/Packages/ReRoomContracts/Tests/ReRoomTransactionCoreTests/TransactionContractTests.swift#fixture manifest is closed, hash-bound, and lexicographically ordered"
        status: pass
      - kind: unit
        ref: "ios/Packages/ReRoomContracts/Tests/ReRoomTransactionCoreTests/TransactionContractTests.swift#oracle traces pin preview no-op, exactly-once commit, retry, restore, and fail-closed conflicts"
        status: pass
    human_judgment: false

duration: 15min
completed: 2026-07-18
status: complete
---

# Phase 3 Plan 1: Exact Transaction Contract and Oracle Summary

**A strict ReRoomTransactionCore vocabulary now binds frozen CON-003/CON-005 bytes to immutable place, retry, restore, identity, ordering, and rejection traces without changing schema authority.**

## Performance

- **Duration:** 15 min
- **Started:** 2026-07-18T13:42:00Z
- **Completed:** 2026-07-18T13:57:00Z
- **Tasks:** 1
- **Files modified:** 7

## Accomplishments

- Added the static `ReRoomTransactionCore` product with closed Sendable/Codable values for the entire transaction and SceneState vocabulary.
- Added strict canonical JSON plus frozen schema validation before typed decode, followed by canonical round-trip equality to prevent silent field loss.
- Added a closed immutable fixture revision covering four-operation order, lifecycle, native authority/branch identity, preview/commit/retry/restore traces, and fail-closed inputs.

## Task Commits

The TDD task was committed atomically as separate gates:

1. **RED: failing transaction contract oracle** - `52b6be7` (test)
2. **GREEN: exact transaction contract** - `4612370` (feat)

## Files Created/Modified

- `ios/Packages/ReRoomContracts/Package.swift` - Registers the static transaction product and focused test target without a new dependency.
- `ios/Packages/ReRoomContracts/Sources/ReRoomTransactionCore/TransactionModels.swift` - Exact closed values for CON-003/CON-005 and shared receipts.
- `ios/Packages/ReRoomContracts/Sources/ReRoomTransactionCore/TransactionContractAdapter.swift` - JCS, frozen-schema, typed-decode, and canonical round-trip boundary.
- `ios/Packages/ReRoomContracts/Tests/ReRoomTransactionCoreTests/TransactionContractTests.swift` - Parallel-safe Swift Testing coverage with parameterized hostile cases.
- `fixtures/transactions/1.0.0/rev-001/manifest.json` - Closed schema/file inventory with exact bytes and SHA-256 bindings.
- `fixtures/transactions/1.0.0/rev-001/cases.json` - Stable identities, four-operation inventory, lifecycle, retry, injection, and rejection cases.
- `fixtures/transactions/1.0.0/rev-001/expected-traces.json` - Independent normalized revision/mutation traces for place, retry, restore, and conflicts.

## Decisions Made

- Reused `CanonicalJSON` and `ContractValidator` directly; no canonicalization, schema engine, or ID registry was forked.
- Kept schema-owned optional semantic-model metadata representable as contract data while adding no model, provider, voice, network, or cloud integration.
- Kept GATE-009 and GATE-010 formal campaigns pending; this plan establishes only their deterministic contract/oracle foundation.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Preserved nonzero RED discovery without an invalid SwiftPM manifest**
- **Found during:** Task 1 RED gate
- **Issue:** A SwiftPM test target cannot both depend on a nonexistent product and run a discovered test; package resolution fails before test discovery.
- **Fix:** Registered the focused test target against the existing contracts module, loaded the immutable fixture, and recorded an explicit failing issue because the production transaction module was absent. The run discovered one test and failed for that exact missing implementation reason.
- **Files modified:** `Package.swift`, `TransactionContractTests.swift`
- **Verification:** RED output reported `Test run with 1 test in 1 suite failed` before the production target existed.
- **Committed in:** `52b6be7`

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** The mandated RED evidence became executable and nonzero while preserving the same missing-production-contract signal; no product scope or architecture changed.

## Issues Encountered

- The plan's `fixtures/contracts/1.0.0/rev-001/cases.json` read-first path does not exist because the established contract corpus uses `cases/*.json`; the existing manifest and relevant CON-003/CON-005 instance/mutation files were read instead. No authority conflict resulted.

## TDD Gate Compliance

- RED commit exists before GREEN: `52b6be7`.
- GREEN commit exists after RED: `4612370`.
- Exact filtered run passes with six discovered tests; the hostile parameterized test contributes seven independently reported cases.

## User Setup Required

None - no external service configuration or new dependency is required.

## Next Phase Readiness

- Ready for `03-03-PLAN.md` to build RR-EDIT-PROJECTION-1 and restore rebase semantics on the shared types.
- Formal physical, reconnect, human, and full GATE-009/GATE-010 evidence remains pending under the approved sprint cut.

---
*Phase: 03-typed-place-commit-and-offline-restore*
*Completed: 2026-07-18*

## Self-Check: PASSED

- All seven implementation and fixture files are present.
- RED commit `52b6be7` and GREEN commit `4612370` are present in repository history.
- The filtered transaction suite and the complete `ReRoomContracts` package suite pass.
- Frozen CON-003 and CON-005 schema digests are unchanged.
- Scoped secret scan and `git diff --check` pass.
