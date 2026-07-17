---
phase: 02-atomic-capture-and-exact-replay
plan: "01"
subsystem: capture-replay-foundation
tags: [swift, rrcap, replay, fixtures, durability, sendable]

requires:
  - phase: 01-contract-and-device-proof
    provides: Frozen CON-001/CON-002, RR-JCS-SHA256-1, RR-COORD-1, RRFP-WIRE-1, ArchivePath, and locked package dependencies
provides:
  - Immutable synthetic finalized-empty, finalized-one-frame, and recovered-prefix capture oracle with externally pinned byte identities
  - Closed replay evidence schema with archive/finalization identity, exact digests, stable rejection data, metrics, and self-omitting report digest
  - ReRoomCaptureCore product with immutable Sendable capture/replay/policy values
  - Synchronous bounded Foundation filesystem seam with validated archive paths, operation tracing, and pre-mutation fault injection
affects: [02-02-capture-writer, 02-03-recovery-replay, 02-04-admission-queues, 02-05-cross-runtime-replay, 02-06-native-adapter]

tech-stack:
  added: []
  patterns: [externally-pinned-fixture-oracle, immutable-sendable-boundaries, synchronous-actor-owned-io-seam, pre-mutation-fault-observation]

key-files:
  created:
    - fixtures/capture/1.0.0/rev-001/manifest.json
    - fixtures/capture/1.0.0/rev-001/archives/finalized-empty.rrcap
    - fixtures/capture/1.0.0/rev-001/archives/finalized-one-frame.rrcap
    - fixtures/capture/1.0.0/rev-001/archives/recovered-prefix.rrcap
    - fixtures/replay-report.schema.json
    - ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/CaptureSession.swift
    - ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/CaptureFileSystem.swift
    - ios/Packages/ReRoomContracts/Tests/ReRoomCaptureCoreTests/CaptureCoreContractTests.swift
    - tools/verify/tests/test_phase_02_fixtures.py
  modified:
    - ios/Packages/ReRoomContracts/Package.swift

key-decisions:
  - "Pin the complete capture fixture manifest digest in verifier source outside the generated corpus, so regenerated expected output cannot redefine the oracle."
  - "Keep replay reports evidence-only rather than minting CON-006, while binding the exact archive/finalization identity and omitting only report_sha256 from its own digest."
  - "Make consented authorization unrepresentable for a denied decision and require every network-eligible receipt to bind stable session/frame/idempotency identity plus packet and image digests."
  - "Expose synchronous filesystem operations through one immutable Sendable implementation whose observer runs before each valid operation, leaving transaction ordering to the future sole writer actor."

patterns-established:
  - "Fixture authority: bind every accepted file and directory by exact byte length/SHA-256, then pin the root manifest hash outside the fixture."
  - "Capture boundaries: validate stable prefixed IDs, archive-relative paths, digests, decimal timestamps, policy classifications, and byte limits at immutable value construction."
  - "Filesystem faults: validate and resolve first, emit one typed operation to the injected observer, then mutate synchronously without suspension."

requirements-completed: [FR-CAPTURE-001, FR-B0-001, NFR-REPLAY-001, SEC-CONSENT-001]

coverage:
  - id: D1
    description: "Three non-room capture archives encode finalized-empty, exact five-state one-frame, and hash-valid recovered-prefix behavior with complete byte and digest bindings."
    requirement: FR-CAPTURE-001
    verification:
      - kind: integration
        ref: "tools/verify/tests/test_phase_02_fixtures.py#Phase02FixtureTests"
        status: pass
    human_judgment: false
  - id: D2
    description: "The closed replay evidence schema and fixture oracle bind archive/finalization identity, journal/projection/revision digests, stable rejection outcomes, and a self-omitting report digest."
    requirement: FR-B0-001
    verification:
      - kind: unit
        ref: "tools/verify/tests/test_phase_02_fixtures.py#test_report_schema_is_closed_and_self_hash_omission_is_exact"
        status: pass
      - kind: unit
        ref: "tools/verify/tests/test_phase_02_fixtures.py#test_one_byte_drift_is_fatal"
        status: pass
    human_judgment: false
  - id: D3
    description: "The NFR replay target remains explicitly HYPOTHESIS evidence in the twelve-case edge probe set rather than being reported as a fabricated measurement."
    requirement: NFR-REPLAY-001
    verification:
      - kind: unit
        ref: "fixtures/capture/1.0.0/rev-001/manifest.json#nfr-replay.assumption verified by test_phase_02_fixtures"
        status: pass
    human_judgment: false
  - id: D4
    description: "Denied consent cannot construct CaptureSessionAuthorization, and the denied fixture case creates no archive while concurrent session identity mismatch has a stable rejection."
    requirement: SEC-CONSENT-001
    verification:
      - kind: unit
        ref: "ios/Packages/ReRoomContracts/Tests/ReRoomCaptureCoreTests/CaptureCoreContractTests.swift#captureValueRejections"
        status: pass
      - kind: unit
        ref: "tools/verify/tests/test_phase_02_fixtures.py#test_capture_corpus_is_complete_and_semantically_exact"
        status: pass
    human_judgment: false
  - id: D5
    description: "ReRoomCaptureCore exposes immutable Sendable capture/replay/policy values and one bounded synchronous filesystem seam with max/max+1, containment, fault, and isolation coverage."
    requirement: FR-CAPTURE-001
    verification:
      - kind: integration
        ref: "swift test --package-path ios/Packages/ReRoomContracts --filter CaptureCoreContractTests"
        status: pass
      - kind: integration
        ref: "swift test --package-path ios/Packages/ReRoomContracts (40 tests in 6 suites)"
        status: pass
    human_judgment: false

duration: 33min
completed: 2026-07-17
status: complete
---

# Phase 02 Plan 01: Capture/Replay Oracle and Core Contracts Summary

**An externally pinned synthetic `.rrcap` oracle, closed replay evidence schema, immutable Sendable capture values, and bounded synchronous filesystem seam now define the contract every later Phase 2 writer, recovery, replay, queue, and native adapter consumes.**

## Performance

- **Duration:** 33 min
- **Started:** 2026-07-17T21:22:27Z
- **Completed:** 2026-07-17T21:56:02Z
- **Tasks:** 2
- **Files modified:** 29

## Accomplishments

- Froze three deterministic non-room capture archives: a valid finalized zero-frame session, a finalized one-frame session with the exact five schema-owned lifecycle events and a real 1×1 PNG, and a recovered archive whose invalid suffix remains quarantined outside accepted inventory.
- Bound every fixture file/directory, CON-001 packet/image pair, CON-002 manifest, journal tuple, accepted-frame/event projection, revision trace, finalization state, verdict, and rejection class to exact byte lengths and SHA-256 values; the verifier pins the root manifest digest externally and kills one-byte or omission mutations.
- Added a closed evidence-only replay report schema with evaluator, fixture, archive/finalization, implementation, verdict, digest, rejection, metric, and exact self-hash omission fields without changing frozen product contracts.
- Added the dependency-local `ReRoomCaptureCore` product/test target and immutable Sendable authorization, lifecycle, receipt, acknowledgement, finalization, recovery, replay, policy, and metrics values with stable-ID/digest/path/boundary validation.
- Added a synchronous Foundation filesystem implementation over `ArchivePath` with explicit read/write/append limits, file/directory sync, rename/replace, typed operation tracing, deterministic pre-mutation fault injection, and isolated-root tests.

## Task Commits

Each task was developed RED then GREEN and committed atomically:

1. **Task 1: Freeze the synthetic archive and replay-report oracle** - `07ad25f` (RED test), `c8cb9db` (GREEN fixture), `a427661` (byte-valid PNG hardening)
2. **Task 2: Establish ReRoomCaptureCore contracts and bounded filesystem boundary** - `79993fe` (RED test), `acb1d66` (GREEN implementation), `8364392` (closed-boundary hardening)

**Plan metadata:** recorded by the closeout commit containing this summary.

## Files Created/Modified

- `fixtures/capture/1.0.0/rev-001/manifest.json` - Lexical root oracle with archive expectations, file/directory bindings, denied-consent case, and twelve fallback edge probes.
- `fixtures/capture/1.0.0/rev-001/archives/` - Synthetic finalized-empty, finalized-one-frame, and recovered-prefix archive directories.
- `fixtures/replay-report.schema.json` - Closed replay evidence schema; not a product contract.
- `tools/verify/tests/test_phase_02_fixtures.py` - Schema, semantic, hash, projection, omission, and drift verifier with externally pinned fixture identity.
- `ios/Packages/ReRoomContracts/Package.swift` - Adds the local-only `ReRoomCaptureCore` product/target and its test target.
- `ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/CaptureSession.swift` - Stable immutable Sendable capture, replay, policy, and metric value boundary.
- `ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/CaptureFileSystem.swift` - Bounded synchronous filesystem protocol, operation model, and Foundation implementation.
- `ios/Packages/ReRoomContracts/Tests/ReRoomCaptureCoreTests/CaptureCoreContractTests.swift` - Parallel-safe value, max/max+1, path, fault, trace, and root-isolation coverage.

## Decisions Made

- Kept the fixture root manifest outside its own hash inventory and pinned its exact raw-file digest in verifier source. A corpus rewrite therefore needs an explicit test-oracle change and cannot self-authorize.
- Kept `ReplayReportV1` evidence-only. It binds the concrete archive/finalization identity and all exact replay digests, but does not mint CON-006 or modify frozen CON-001/CON-002.
- Restricted `CaptureSessionAuthorization` to granted consent with default `local_only_until_share`; a denied decision is an explicit constructor rejection and cannot cross the storage boundary as authorization.
- Required a `NetworkEligibleReceipt` to carry the durable journal sequence plus both packet and image SHA-256 values before any later transport queue can accept it.
- Kept filesystem operations synchronous and stateless. The injected observer runs after validation but before mutation, enabling the later actor-owned crash matrix without putting an `await` inside an archive transaction.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Correctness] Closed authorization, durable-receipt, and report-archive boundaries**
- **Found during:** Final Task 2 acceptance review.
- **Issue:** The first GREEN shape could represent denied consent, bound only the packet digest on a durable receipt, and lacked explicit archive/finalization identity in `ReplayReportV1`.
- **Fix:** Rejected denied authorization construction, required packet and image digests, added the exact five lifecycle values/open-finalized-recovered states, and added closed replay archive identity to both Swift and schema values.
- **Files modified:** `CaptureSession.swift`, `CaptureCoreContractTests.swift`, `fixtures/replay-report.schema.json`, capture fixture manifest, fixture verifier.
- **Verification:** Both focused suites and the complete 40-test Swift package passed.
- **Committed in:** `8364392`

**2. [Rule 1 - Correctness] Made synthetic PNG payloads codec-valid**
- **Found during:** Final fixture semantic review.
- **Issue:** The initial non-room image marker was hash-valid but did not contain PNG bytes despite declaring the `png` codec.
- **Fix:** Replaced both markers with the same deterministic valid 1×1 gray+alpha PNG and mechanically re-derived packet, inventory, journal, replay, archive, directory, and root oracle digests.
- **Files modified:** Both one-frame image/packet/manifests, root fixture manifest, fixture verifier.
- **Verification:** `file` recognizes both payloads as 1×1 PNG; all five fixture tests pass with the new externally pinned root digest.
- **Committed in:** `a427661`

---

**Total deviations:** 2 auto-fixed correctness issues.
**Impact on plan:** Both fixes tighten declared boundaries and byte truth without adding dependencies, changing product contracts, or expanding beyond the planned oracle/interface surfaces.

## Issues Encountered

- The host's global Miniconda `site` initialization blocks in `stat(2)` on two stale editable `.pth` paths outside this repository. The exact bare Python command therefore could not reach unittest discovery. The same locked Python 3.13 interpreter and installed `jsonschema` package passed all five tests when invoked with `-S` and an explicit Miniconda site-packages path; no global environment or dependency file was changed.
- GSD consistency passes with expected warnings for future Phase 3-8 directories. GSD health has no errors or repairable findings and retains only the pre-existing non-repairable `W004` warning for `model_profile: adaptive`; pending Phase 2 summary notices are expected during execution.

## Verification Evidence

- The isolated Python fixture command passed 5 tests, including complete semantic validation, one-byte drift, bound-artifact omission, external-oracle mutation, and closed report schema checks.
- `swift test --package-path ios/Packages/ReRoomContracts --filter CaptureCoreContractTests` passed 7 parallel-safe tests.
- `swift test --package-path ios/Packages/ReRoomContracts` passed 40 tests in 6 suites after the last Swift boundary change.
- `swift package dump-package` lists `ReRoomCaptureCore` with only local `ReRoomContracts` dependency and its test target with only local `ReRoomCaptureCore` dependency.
- `Package.resolved` remains byte-identical at SHA-256 `d6a939867cb3f1eb438da2b7806d9d128ba715312ea10449092a98d532309501`; no JavaScript/Python/Swift lock changed.
- Targeted secret scanning found no credential-shaped values. `git diff --check` passed.

## User Setup Required

None - the plan adds no service, credential, product dependency, endpoint, or cloud resource.

## Next Phase Readiness

- Plan 02-02 can consume exact consent/session/candidate/receipt/acknowledgement/finalization values and inject operation-level faults into the sole future archive writer.
- Plan 02-03 can consume the immutable finalized/recovered fixture oracle, replay identities, timeline values, and closed report shape.
- The twelve edge probes remain oracle inputs; NFR-REPLAY-001 is explicitly HYPOTHESIS rather than fabricated MEASURED evidence.
- Ready for Plan 02-02 with no product or planning blocker.

## Self-Check: PASSED

- All six implementation commits exist in repository history; every declared plan artifact is tracked and no temporary generator remains.
- Both task verifiers and the complete Swift package suite pass; package topology and lock invariants are unchanged.
- The generated Swift `.build` directory was moved to Trash, while pre-existing `.swiftpm`, Xcode workspace/userdata, scheme, STATE, and config changes were preserved until the required metadata update.
- No archive/source file includes room data, raw evidence, credentials, model output, provider call, or network dependency.

---
*Phase: 02-atomic-capture-and-exact-replay*
*Completed: 2026-07-17*
