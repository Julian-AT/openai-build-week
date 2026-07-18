---
phase: 03-typed-place-commit-and-offline-restore
plan: "02"
subsystem: transaction-reducers
tags: [swift, swift-testing, intent-boundary, rr-jcs-sha256-1, place-reducer]

requires:
  - phase: 03-typed-place-commit-and-offline-restore
    plan: "01"
    provides: frozen transaction types, schema adapter, and immutable transaction oracle
  - phase: 03-typed-place-commit-and-offline-restore
    plan: "03"
    provides: shared RR-EDIT-PROJECTION-1 build, diff, digest, and artifact-union engine
provides:
  - strict byte/depth-bounded typed/tap intent parsing with trusted context binding and local voice rejection
  - dedicated seven-member RR-JCS-SHA256-1 transaction request fingerprint
  - pure projection-backed place preview, cancellation, explicit confirmation, pending scene, receipt candidate, and captured-exact inverse
  - typed nonmutating readiness blockers for replace, remove, and restore proposals
affects: [03-04, 03-05, 03-06, 03-07, mode-a]

tech-stack:
  added: []
  patterns:
    - canonical JSON before exact typed DTO decoding
    - trusted context attachment only after untrusted semantic parsing
    - dedicated Codable fingerprint scope with canonical typed round-trip
    - immutable preview replay before cancellation or confirmation
    - projection-engine-only committed and inverse snapshot construction

key-files:
  created:
    - ios/Packages/ReRoomContracts/Sources/ReRoomTransactionCore/IntentBoundary.swift
    - ios/Packages/ReRoomContracts/Sources/ReRoomTransactionCore/TransactionFingerprint.swift
    - ios/Packages/ReRoomContracts/Sources/ReRoomTransactionCore/PlaceReducer.swift
    - ios/Packages/ReRoomContracts/Tests/ReRoomTransactionCoreTests/IntentBoundaryTests.swift
    - ios/Packages/ReRoomContracts/Tests/ReRoomTransactionCoreTests/PlaceReducerTests.swift
  modified: []

key-decisions:
  - "Parse only operation, arguments, and ordered typed constraints from untrusted bytes; attach session, authority, branch, revision, target, and world values exclusively from trusted native context."
  - "Represent the request fingerprint as a dedicated seven-member Codable value, never a generic dictionary or complete transaction encoding."
  - "Replay the immutable preview from its trusted deterministic candidate before cancellation or confirmation, and return pending r+1 content without persistence or canonical revision allocation."

patterns-established:
  - "Intent authority boundary: typed and tap share one value path, voice is locally unavailable, and transform/URL/confirmation/tool/authority fields have no decodable representation."
  - "Place authority boundary: deterministic asset/support candidates own spatial and policy facts; explicit native user confirmation is preview-bound and still yields only pending content."

requirements-completed: [FR-PLACE-001, FR-TRANSACTION-001, FR-AGENT-001]

coverage:
  - id: D1
    description: "Typed and tap ingress produce one trusted context-bound proposal while malformed, duplicate, oversized, stale, mismatched, or authority-injecting bytes reject without scene mutation."
    requirement: FR-AGENT-001
    verification:
      - kind: unit
        ref: "ios/Packages/ReRoomContracts/Tests/ReRoomTransactionCoreTests/IntentBoundaryTests.swift#tap and typed ingress share one trusted context-bound proposal type"
        status: pass
      - kind: unit
        ref: "ios/Packages/ReRoomContracts/Tests/ReRoomTransactionCoreTests/IntentBoundaryTests.swift#forbidden malformed empty oversized and injected input rejects without mutation"
        status: pass
    human_judgment: false
  - id: D2
    description: "The request fingerprint canonicalizes exactly the seven frozen members, changes for every included member, excludes lifecycle metadata, and remains deterministic under concurrent submissions."
    requirement: FR-TRANSACTION-001
    verification:
      - kind: unit
        ref: "ios/Packages/ReRoomContracts/Tests/ReRoomTransactionCoreTests/IntentBoundaryTests.swift#fingerprint scope has exactly seven members and excludes transaction lifecycle metadata"
        status: pass
      - kind: unit
        ref: "ios/Packages/ReRoomContracts/Tests/ReRoomTransactionCoreTests/IntentBoundaryTests.swift#each of the seven included members changes the request fingerprint"
        status: pass
    human_judgment: false
  - id: D3
    description: "Allowlisted local assets and current support yield a stable revision-neutral preview; failures and cancellation do not mutate, while exact user confirmation yields one pending place delta and complete captured-exact inverse."
    requirement: FR-PLACE-001
    verification:
      - kind: unit
        ref: "ios/Packages/ReRoomContracts/Tests/ReRoomTransactionCoreTests/PlaceReducerTests.swift#valid support and allowlisted proxy produce a byte-stable noncanonical preview"
        status: pass
      - kind: unit
        ref: "ios/Packages/ReRoomContracts/Tests/ReRoomTransactionCoreTests/PlaceReducerTests.swift#cancel is revision-neutral and exact confirmation yields one pending place plus complete inverse"
        status: pass
      - kind: integration
        ref: "swift test --package-path ios/Packages/ReRoomContracts"
        status: pass
    human_judgment: false
  - id: D4
    description: "Replace and remove return typed capability blockers and restore requires source selection, with no canonical delta or pre-authorized compensation."
    requirement: FR-PLACE-001
    verification:
      - kind: unit
        ref: "ios/Packages/ReRoomContracts/Tests/ReRoomTransactionCoreTests/PlaceReducerTests.swift#replace and remove remain typed context-bound proposals with readiness blockers"
        status: pass
    human_judgment: false

duration: 9min
completed: 2026-07-18
status: complete
---

# Phase 3 Plan 2: Strict Intent, Exact Fingerprint, and Pure Place Reducer Summary

**Typed/tap intent is now fail-closed and context-bound, and an allowlisted offline place can advance only from stable preview to explicit-confirmation pending content through RR-EDIT-PROJECTION-1.**

## Performance

- **Duration:** 9 min
- **Started:** 2026-07-18T16:12:00+02:00
- **Completed:** 2026-07-18T16:21:00+02:00
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments

- Added one strict typed/tap intent seam with canonical duplicate detection, exact field allowlists, ordered typed constraints, trusted native context binding, and 16-class adversarial rejection coverage.
- Added a dedicated canonical seven-member request fingerprint with included/excluded-member and 32-way concurrent determinism tests.
- Added a pure place reducer with five exact validation checks, stable preview replay, revision-neutral cancellation, explicit preview-bound native confirmation, one create operation, pending r+1 scene/receipt content, and a complete captured-exact inverse.
- Preserved the four-operation surface with typed no-delta blockers for replace/remove and restore source selection.

## Task Commits

Each behavior-bearing task used a distinct RED then GREEN commit:

1. **Task 1 RED: failing strict intent and fingerprint semantics** - `98d8249` (test)
2. **Task 1 GREEN: context-bound ingress and seven-member fingerprint** - `89612f8` (feat)
3. **Task 2 RED: failing pure place reducer semantics** - `56f4c99` (test)
4. **Task 2 GREEN: projection-backed place preview and confirmation** - `4a2f819` (feat)

## Files Created/Modified

- `ios/Packages/ReRoomContracts/Sources/ReRoomTransactionCore/IntentBoundary.swift` - Bounded exact semantic decoder and trusted context attachment.
- `ios/Packages/ReRoomContracts/Sources/ReRoomTransactionCore/TransactionFingerprint.swift` - Frozen seven-member canonical fingerprint value and digest.
- `ios/Packages/ReRoomContracts/Sources/ReRoomTransactionCore/PlaceReducer.swift` - Pure preview/cancel/confirm/defer reduction over immutable deterministic candidates.
- `ios/Packages/ReRoomContracts/Tests/ReRoomTransactionCoreTests/IntentBoundaryTests.swift` - Ingress attacks, context staleness, concurrency, and fingerprint scope tests.
- `ios/Packages/ReRoomContracts/Tests/ReRoomTransactionCoreTests/PlaceReducerTests.swift` - Preview stability, ten-case failure matrix, confirmation/inverse, cancellation, and blocker tests.

## Decisions Made

- Kept all identity, revision, target, world, confirmation, and spatial authority outside user bytes; only semantic operation, asset/query, and schema-frozen constraints are decoded.
- Made preview values replay-complete by retaining their bound proposal, deterministic local candidate, and coordinator seed; cancel/confirm recompute and require exact equality before returning output.
- Used the shared projection engine for pre/committed projections, touched-operation verification, pending scene application, complete snapshots, artifact union, and result digest.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Corrected a throwing Swift Testing collection expression**
- **Found during:** Task 1 GREEN compilation
- **Issue:** A throwing digest call nested directly inside `#expect` macro expansion was not propagated by the generated macro code.
- **Fix:** Evaluated the throwing digest array before the assertion and asserted its unique-count separately.
- **Files modified:** `IntentBoundaryTests.swift`
- **Verification:** Filtered intent suite and full package regression pass.
- **Committed in:** `89612f8`

**2. [Rule 1 - Bug] Matched every typed constraint variant to the frozen transaction schema**
- **Found during:** Task 2 pre-commit authority review
- **Issue:** The first decoder draft covered the test constraints but not all frozen schema variants.
- **Fix:** Added `style_tag`, `preserve_walkway`, and `max_footprint_m2` with the schema's exact types and bounds.
- **Files modified:** `IntentBoundary.swift`
- **Verification:** Filtered intent suite and full package regression pass.
- **Committed in:** `4a2f819`

---

**Total deviations:** 2 auto-fixed bugs
**Impact on plan:** Both fixes strengthened exact test/compiler and frozen-contract compliance without schema, dependency, network, model, persistence, or cloud changes.

## TDD Gate Compliance

- Task 1 RED failed only because `IntentBoundary`, `BoundProposal`, and `TransactionFingerprintScope` did not exist; GREEN passes 6 tests including 16 attack cases and 7 fingerprint-member cases.
- Task 2 RED failed only because the place reducer/value APIs did not exist; GREEN passes 5 tests including 10 parameterized context/policy failures.
- The complete package regression passes 121 tests across 19 suites.

## Verification

- `swift test --package-path ios/Packages/ReRoomContracts --filter IntentBoundaryTests` — 6 tests in 1 suite passed.
- `swift test --package-path ios/Packages/ReRoomContracts --filter PlaceReducerTests` — 5 tests in 1 suite passed.
- `swift test --package-path ios/Packages/ReRoomContracts` — 121 tests in 19 suites passed.
- Pure-source scan found no network/model imports or filesystem writes in `IntentBoundary.swift`, `TransactionFingerprint.swift`, or `PlaceReducer.swift`.
- Scoped secret scan and `git diff --check` pass.

## User Setup Required

None - this plan is deterministic local Swift code and adds no dependency or service configuration.

## Next Phase Readiness

- Ready for `03-04-PLAN.md` to make the sole native authority durably activate pending place/restore content through explicit CAS commit.
- GATE-009, GATE-010, physical-device, reconnect, and human evidence remain pending; this plan does not promote them.

---
*Phase: 03-typed-place-commit-and-offline-restore*
*Completed: 2026-07-18*

## Self-Check: PASSED

- All five plan files exist and both RED/GREEN commit pairs are present.
- Both filtered suites and the 121-test full package regression pass.
- The three pure source files contain no network/model import or filesystem write surface.
- Unrelated `.planning/config.json`, Xcode project/scheme, workspace, user data, and local Swift build artifacts remain unstaged.
