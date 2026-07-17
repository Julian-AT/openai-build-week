---
phase: 02-atomic-capture-and-exact-replay
plan: "03"
subsystem: recovery-and-exact-replay
tags: [swift, rrcap, recovery, replay, jcs, executable]

requires:
  - phase: 02-01
    provides: Frozen capture contracts, fixtures, and digest vectors
  - phase: 02-02
    provides: Atomic capture writer and authoritative global journal
provides:
  - Verified contiguous-prefix recovery that never mutates or resumes the interrupted archive
  - Exact provider-independent replay from the verified authoritative journal
  - Deterministic 16-case Swift replay evidence runner with atomic report publication
affects: [02-05, 02-06, 02-07]

tech-stack:
  added: []
  patterns:
    - Immutable sibling publication for recovered prefixes
    - Fail-closed bounded validation before replay
    - JCS self-omitting evidence digests
    - Stage-then-exclusive-rename report publication

key-files:
  created:
    - ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/CaptureRecovery.swift
    - ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/ReplayCore.swift
    - ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/ReplayReport.swift
    - ios/Packages/ReRoomContracts/Sources/ReRoomReplayRunner/main.swift
    - ios/Packages/ReRoomContracts/Tests/ReRoomCaptureCoreTests/CaptureRecoveryTests.swift
    - ios/Packages/ReRoomContracts/Tests/ReRoomCaptureCoreTests/ReplayCoreTests.swift
    - ios/Packages/ReRoomContracts/Tests/ReRoomReplayRunnerTests/ReplayRunnerTests.swift
  modified:
    - ios/Packages/ReRoomContracts/Package.swift
    - ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/CaptureSession.swift

key-decisions:
  - "Accept only the longest physically present contiguous global-journal prefix; gaps, reordering, invalid records, and mismatched bindings fail closed."
  - "Keep the interrupted archive immutable and publish recovery only as a new recovered-prefix sibling; quarantined suffix diagnostics remain outside accepted inventory."
  - "Derive replay timelines exclusively from the verified global journal and freeze journal, frame, event, and revision digests in the replay report."
  - "Run the complete 16-case evidence set locally with no provider, model, network, Node, or Python dependency in the shipping Swift runner."

requirements-completed: [FR-B0-001, FR-CAPTURE-001]

coverage:
  - id: D1
    description: "Only a fully verified contiguous global-journal prefix is accepted and published as an immutable recovered-prefix sibling; gaps, reordering, tampering, over-bound inputs, and publication failure do not mutate the interrupted archive."
    requirement: FR-CAPTURE-001
    verification:
      - kind: integration
        ref: "swift test --package-path ios/Packages/ReRoomContracts --filter CaptureRecoveryTests"
        status: pass
    human_judgment: false
  - id: D2
    description: "Verified finalized and recovered-prefix archives replay exactly from authoritative journal order with frozen journal, frame, event, and revision digests independent of provider, renderer, model, and network availability."
    requirement: FR-B0-001
    verification:
      - kind: integration
        ref: "swift test --package-path ios/Packages/ReRoomContracts --filter ReplayCoreTests"
        status: pass
    human_judgment: false
  - id: D3
    description: "The standalone Swift runner executes the complete three archive, twelve edge-probe, and consent-denied case set and publishes 16 byte-identical, closed, self-digested reports that validate against the pinned evidence schema."
    requirement: FR-B0-001
    verification:
      - kind: integration
        ref: "swift test --package-path ios/Packages/ReRoomContracts --filter ReplayRunnerTests"
        status: pass
      - kind: other
        ref: "Two standalone ReRoomReplayRunner invocations plus pinned replay-evidence.schema.json validation"
        status: pass
    human_judgment: false

duration: 32min
completed: 2026-07-18
status: complete
---

# Phase 02 Plan 03: Recovered Prefix and Exact Replay Summary

Interrupted captures now recover only a fully verified contiguous prefix into a new immutable archive, while exact replay and the evidence runner deterministically reconstruct and report every accepted case from the authoritative journal.

## Performance

- **Duration:** 32min
- **Started:** 2026-07-17T23:06:32Z
- **Completed:** 2026-07-17T23:38:21Z
- **Tasks:** 3
- **Files modified:** 9

## Accomplishments

- Added bounded, fail-closed recovery validation across manifest closure, inventory paths and counts, raw hashes, manifest self-hash, journal records, event self-digests, frame/packet/image bindings, sequence continuity, projections, and tuple digest.
- Made interrupted capture handling immutable and idempotent: the accepted prefix is staged and atomically published as a recovered-prefix sibling, the original remains byte-identical, and the invalid suffix is excluded from accepted inventory.
- Added exact replay from the verified global journal with frozen journal, frame, event, and revision digests and no renderer/provider dependency.
- Added a complete Swift replay runner for three synthesized archive cases, twelve named edge probes, and consent denial, with strict CLI validation and atomic no-overwrite evidence publication.

## Task Commits

Each behavior-bearing task was implemented through a RED/GREEN pair:

1. **Task 1: Recover only the longest valid contiguous prefix**
   - `8d41b2b` — `test(02-03): define recovery prefix behavior` (RED)
   - `597fd1e` — `feat(02-03): publish verified recovery prefixes` (GREEN)
2. **Task 2: Replay verified archives exactly**
   - `a29b316` — `test(02-03): define exact replay behavior` (RED)
   - `5359999` — `feat(02-03): replay verified archives exactly` (GREEN)
3. **Task 3: Publish the complete deterministic replay evidence set**
   - `8238ca9` — `test(02-03): define replay runner contract` (RED)
   - `5c584f6` — `feat(02-03): add complete Swift replay runner` (GREEN)

## Files Created/Modified

- `ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/CaptureRecovery.swift` — Bounded archive verification, contiguous-prefix selection, quarantine, and atomic recovered-sibling publication.
- `ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/CaptureSession.swift` — Recovered archive metadata supports complete immutable recovered archives without fabricated suffix metadata.
- `ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/ReplayCore.swift` — Exact replay timeline construction and frozen replay digest projection.
- `ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/ReplayReport.swift` — Closed ReplayReportV1 encoding, self-omitting JCS digest, and public runner integrity facade.
- `ios/Packages/ReRoomContracts/Sources/ReRoomReplayRunner/main.swift` — Strict executable CLI, pinned input verification, complete case execution, and atomic report publication.
- `ios/Packages/ReRoomContracts/Package.swift` — Replay runner executable and focused test target, both depending only on ReRoomCaptureCore.
- `ios/Packages/ReRoomContracts/Tests/ReRoomCaptureCoreTests/CaptureRecoveryTests.swift` — Recovery success, immutability, idempotency, rollback, reorder, gap, mutation, and bound coverage.
- `ios/Packages/ReRoomContracts/Tests/ReRoomCaptureCoreTests/ReplayCoreTests.swift` — Exact fixture replay, recovered-prefix replay, tamper rejection, independence, and report digest coverage.
- `ios/Packages/ReRoomContracts/Tests/ReRoomReplayRunnerTests/ReplayRunnerTests.swift` — Complete set, repeatability, schema shape, CLI rejection, drift, symlink, and no-overwrite coverage.

## Decisions Made

- Recovery authority is the longest physically present, valid, contiguous global-journal prefix. There is no tie-break, repair, or inferred record.
- An interrupted archive is never resumed or mutated. Recovery publishes a new immutable sibling and keeps quarantine diagnostics outside the accepted archive inventory.
- Replay reads only the verified authoritative journal; filenames, directory ordering, renderer/provider indices, and network/model availability cannot alter the timeline.
- The evidence runner always executes the full 16-case contract and publishes only a complete, internally consistent report directory.

## Deviations from Plan

### Auto-fixed Interface Mismatch

**1. Recovered archive inspection needed an absent-suffix state**

- **Found during:** Task 1 GREEN
- **Issue:** The pre-existing `RecoveredArchive` initializer required suffix-invalid and quarantine metadata for every recovered-prefix archive, preventing later read-only inspection of a complete recovered archive where those publication-time diagnostics are intentionally absent.
- **Fix:** Allowed both fields to be absent together while preserving the invariant that active recovery results provide both or neither.
- **Files modified:** `CaptureSession.swift`
- **Verification:** Complete recovered-prefix inspection and repeated recovery are covered by `CaptureRecoveryTests`.
- **Committed in:** `597fd1e`

---

**Total deviations:** 1 auto-fixed interface mismatch
**Impact on plan:** Required for idempotent inspection of the plan's immutable recovered-prefix artifact; no product-scope expansion.

## Issues Encountered

- The package's Swift JSON Schema validator does not compile the replay evidence schema because that schema is evidence tooling rather than a product contract. Swift tests enforce closed keys and digest semantics; the standalone verification additionally validated every emitted report with the pinned Python `jsonschema` implementation.
- A nested `swift package dump-package` process inside the Swift test process contended on SwiftPM's package lock. The test uses a static package-shape assertion, and `swift package dump-package` was run separately to verify executable and test dependencies.
- macOS canonicalizes temporary paths from `/var` to `/private/var`; the journal-exclusion test normalizes this by matching the controlled relative suffix.
- The local Python user-site initialization hung, so standalone schema verification ran with `PYTHONNOUSERSITE=1`. Python is verification-only and is not a runner dependency.

## Verification Evidence

- Focused recovery tests passed: 8 tests and parameter cases.
- Focused exact replay tests passed: 6 tests and parameter cases.
- Focused replay runner tests passed: 4 tests and mutation cases.
- `swift build --product ReRoomReplayRunner` passed.
- `swift package dump-package` confirmed the executable and focused runner tests depend only on local `ReRoomCaptureCore`.
- Full package suite passed: **96 tests in 14 suites**.
- Two independent standalone runner invocations produced **16 byte-identical, schema-valid reports**.
- Source and lockfile scans found no provider, model, network, ARKit, SwiftUI, Node, or Python runtime dependency and no package lock drift.

## User Setup Required

None.

## Next Phase Readiness

- Plan 02-05 can consume recovered-prefix and replay reports for cross-language conformance vectors.
- Plan 02-06 can consume the atomic report directory and frozen digests for CI evidence gates.
- Physical-device and human gates remain pending until their real evidence exists; this plan does not fabricate either.

## Self-Check: PASSED

- All nine claimed source and test files exist.
- All six RED/GREEN task commits are present in git history.
- The summary records the verified test, build, repeatability, and schema evidence used for completion.
