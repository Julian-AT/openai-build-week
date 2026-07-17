---
phase: 01-contract-and-device-proof
plan: "12"
subsystem: ios-capture-durability
tags: [swift, swift-testing, arkit, rr-jcs-sha256-1, framepacket, rrcap, crash-recovery]

requires:
  - phase: 01-contract-and-device-proof
    provides: Plan 01-11 portrait candidate, ARSession ownership, and verified ReRoomContracts coordinate and contract boundaries
provides:
  - Explicit portrait-attempt and single world-epoch correction-or-quarantine authority
  - Bounded schema-valid CON-001 FramePacket construction and atomic image/metadata staging
  - Exact CON-002 journal lifecycle, journal-gated visibility, crash-prefix recovery, projections, and digests
affects: [01-13, 01-14, mode-a-capture, gate-001, gate-002]

tech-stack:
  added: []
  patterns: [single epoch owner, directed correction or quarantine, staged directory rename, journal-gated visibility, recovered-prefix validation]

key-files:
  created:
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/OrientationGate.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/WorldEpochController.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/CaptureAttemptMachine.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/FramePacketBuilder.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/DiagnosticJournal.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProofTests/CaptureAttemptTests.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProofTests/WorldEpochTests.swift
  modified:
    - ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj/project.pbxproj

key-decisions:
  - "A world-frame reset or relocalization always advances the sole epoch owner; only one finite rigid correction with matching directed base and target versions can release affected quarantine."
  - "CON-001 image and packet bytes become internally durable through one staging-directory rename, but remain non-visible and non-network-eligible until the exact CON-002 journal lifecycle is synced."
  - "The simulator test target embeds the existing frozen contract schema resources so full ContractValidator checks do not depend on inaccessible host-repository paths; canonical schemas are not copied or altered."

patterns-established:
  - "Correction-or-quarantine: unknown, absent, ambiguous, non-finite, non-rigid, stale, or reverse-directed alignment fails capture closed."
  - "Two durability boundaries: directory rename establishes internal bytes; contiguous authoritative journal sync establishes replay visibility and network eligibility."
  - "Bounded recovery: file size, path count, record digest, sequence, projection, final sequence, and replay tuple digest are all validated before exposure."

requirements-completed: [OPS-DEVICE-001, NFR-COORD-001, NFR-CONTRACT-001]

coverage:
  - id: D1
    description: "Portrait and epoch snapshots govern each attempt; landscape rejects in flight without stopping ARSession, and reset/relocalization data remains quarantined unless one matching forward rigid correction validates through RRCoordinateMath."
    requirement: NFR-COORD-001
    verification:
      - kind: unit
        ref: "ReRoomDeviceProofTests/CaptureAttemptTests and WorldEpochTests on the named iPhone 17 simulator"
        status: pass
      - kind: integration
        ref: "scripts/verify-phase-01-contracts quick"
        status: pass
    human_judgment: false
  - id: D2
    description: "Bounded CON-001 bytes and exact CON-002 journal/event records use RR-JCS-SHA256-1 digests, a single rename for internal durability, journal-sync-gated visibility, and fail-closed recovery from every injected crash seam and semantic mutation."
    requirement: NFR-CONTRACT-001
    verification:
      - kind: unit
        ref: "ReRoomDeviceProofTests/CaptureAttemptTests, including 20 parameterized recovery and manifest validation runs"
        status: pass
      - kind: integration
        ref: "Full ReRoomDeviceProof test target on the named iPhone 17 simulator"
        status: pass
    human_judgment: false
  - id: D3
    description: "The atomic capture candidate remains unpromoted until signed base-device installation, camera/ARKit behavior, capture durability, and the applicable GATE-013/GATE-002 procedure are exercised with real evidence."
    requirement: OPS-DEVICE-001
    verification:
      - kind: manual_procedural
        ref: "Plan 01-14 signed physical-device and evidence checklist"
        status: unknown
    human_judgment: true
    rationale: "Simulator unit and filesystem tests cannot prove signing, installation, sensor-backed ARKit behavior, or physical-device durability."

duration: 33min
completed: 2026-07-17
status: complete
---

# Phase 01 Plan 12: Atomic Frame Capture and Recovery Summary

**Portrait and world-epoch attempts now fail closed through directed correction or quarantine, while bounded CON-001 capture bytes become visible only after an exact, synced CON-002 journal lifecycle that survives crash-prefix recovery.**

## Performance

- **Duration:** 33 min
- **Started:** 2026-07-17T00:32:40Z
- **Completed:** 2026-07-17T01:05:19Z
- **Tasks:** 2
- **Files modified:** 8

## Accomplishments

- Added an explicit portrait attempt gate and single private-set world epoch owner. Landscape rotation rejects an in-flight attempt with retry coaching while preserving the healthy ARSession; reset and relocalization always advance coordinate meaning.
- Added direction-sensitive correction validation through `RRCoordinateMath.validateRigidTransform`. Only one finite, rigid, matching base-to-target correction releases affected quarantine; stale, absent, ambiguous, invalid, non-finite, and reverse corrections keep capture unavailable.
- Added a bounded CON-001 builder with synchronized image orientation/crop, encoded intrinsics, column-vector transforms, world epoch, image digest, exact wire constants, full schema validation, and schema-owned final lifecycle state.
- Added one contiguous CON-002 journal authority, exact event records and self-omitting digests, fsynced image/metadata directory staging, atomic rename, journal-gated visibility, four injected crash seams, and bounded prefix recovery with exact projections and replay digest.
- Added mutation and filesystem round-trip coverage for gaps, reorderings, prohibited event types, extra fields, record/replay digests, projection mismatch, final sequence mismatch, invalid recovered-prefix state, and pre-journal invisibility.

## Task Commits

Each behavior-bearing task followed an explicit RED then GREEN commit:

1. **Task 1 RED: Capture orientation and epoch invariants** - `a30a32b` (test)
2. **Task 1 GREEN: Capture epoch quarantine authority** - `75e3bcf` (feat)
3. **Task 2 RED: Atomic capture and recovery contract** - `e6420f4` (test)
4. **Task 2 GREEN: Atomic FramePacket journal durability** - `1b3b0d7` (feat)

**Plan metadata:** recorded by the closeout commit containing this summary.

## Files Created/Modified

- `ios/ReRoomDeviceProof/ReRoomDeviceProof/OrientationGate.swift` - Portrait attempt snapshot and exact landscape retry coaching.
- `ios/ReRoomDeviceProof/ReRoomDeviceProof/WorldEpochController.swift` - Sole monotonic world-frame version owner and directed correction/quarantine validation.
- `ios/ReRoomDeviceProof/ReRoomDeviceProof/CaptureAttemptMachine.swift` - Capture attempt lifecycle integrating orientation, epoch, and quarantine eligibility.
- `ios/ReRoomDeviceProof/ReRoomDeviceProof/FramePacketBuilder.swift` - Bounded CON-001 packet construction, canonical digesting, and full schema validation.
- `ios/ReRoomDeviceProof/ReRoomDeviceProof/DiagnosticJournal.swift` - Atomic staging, exact CON-002 records, synced visibility, recovery validation, and bounded Foundation filesystem boundary.
- `ios/ReRoomDeviceProof/ReRoomDeviceProofTests/CaptureAttemptTests.swift` - Attempt, packet, exact-field, crash-seam, semantic mutation, and production-filesystem integration tests.
- `ios/ReRoomDeviceProof/ReRoomDeviceProofTests/WorldEpochTests.swift` - Epoch advancement and correction direction/rigidity/quarantine tests.
- `ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj/project.pbxproj` - New source/test membership and existing canonical schema resources for simulator validation.

## Decisions Made

- Kept epoch mutation in one controller and made its version setter private so downstream code cannot silently relabel observations after coordinate meaning changes.
- Required a singular matching forward correction and reused locked coordinate math for finite-rigid validation; ambiguity is not resolved heuristically and reverse corrections are not inverted implicitly.
- Kept internal durability and authoritative visibility separate: the image and metadata move together in one directory rename, while exact frame and lifecycle journal records must append and sync before any packet is enumerated as network eligible.
- Used synchronous, bounded Foundation filesystem operations behind a non-Sendable journal owner, making the deterministic persistence boundary explicit without introducing an actor, network call, model call, or server acknowledgement.
- Bundled the repository's existing frozen schema files as test resources because iOS simulator processes cannot reliably load source-tree paths through `#filePath`; tests still validate against the canonical bytes and no duplicate schema source was created.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added Xcode source, test, and frozen-schema resource membership**

- **Found during:** Task 1 and Task 2 GREEN integration
- **Issue:** The plan created seven Swift files but did not list the project file needed to compile them. Full simulator-side `ContractValidator` checks also blocked when a test attempted to load host-repository schema paths that are unavailable from the simulator process.
- **Fix:** Added only the required source/test membership and embedded references to the five existing canonical contract schemas in the test bundle; no schema bytes or product dependency were copied or changed.
- **Files modified:** `ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj/project.pbxproj`
- **Verification:** Targeted and full `xcodebuild test` runs pass on the named iPhone 17 simulator.
- **Committed in:** Task GREEN commits.

**2. [Rule 1 - Correctness] Bounded all persistence input and recovery enumeration**

- **Found during:** Task 2 implementation self-review
- **Issue:** A recovery boundary that reads complete files or enumerates unbounded paths would not satisfy the plan's bounded untrusted-input requirement even if happy-path tests passed.
- **Fix:** Enforced a 32 MiB per-file maximum, 2,048-path maximum, max-plus-one `FileHandle` reads, bounded writes/appends, and fail-closed recovery errors.
- **Files modified:** `ios/ReRoomDeviceProof/ReRoomDeviceProof/DiagnosticJournal.swift`
- **Verification:** Production Foundation filesystem round-trip, crash-prefix, mutation, targeted, and full test runs pass.
- **Committed in:** `1b3b0d7`

---

**Total deviations:** 2 auto-fixed (1 blocking, 1 correctness)
**Impact on plan:** Both changes were required for executable simulator validation and the specified bounded durability semantics. They introduced no new product scope, dependency, or canonical contract change.

## Issues Encountered

- An early simulator run appeared to hang while loading schemas from a host `#filePath`; process sampling identified the blocked host-path read. Test resources resolved the boundary without weakening validation.
- A parallel CoreSimulator clone briefly failed to launch during the intentional RED run. The unchanged named-simulator scope subsequently executed successfully; no product workaround or assertion relaxation was made.
- GSD health remains degraded only by the pre-existing non-repairable `model_profile: adaptive` configuration warning. Consistency passes with only expected notices for roadmap phases whose directories are not created yet.

## Verification Evidence

- The targeted Task 1 `CaptureAttemptTests` and `WorldEpochTests` command passes on the named iPhone 17 simulator with code signing disabled.
- The targeted Task 2 `CaptureAttemptTests` command passes, including 20 parameterized semantic mutation and recovery cases.
- The full `ReRoomDeviceProof` test target passes `ARSessionPolicyTests`, `CaptureAttemptTests`, and `WorldEpochTests` on the named simulator.
- `scripts/verify-phase-01-contracts quick` passes dependency audit, immutable fixture integrity, evidence schemas, JavaScript/Python runners, and Swift contract/coordinate suites.
- Product-source unfinished-marker and network/server-ack boundary scans, tracked high-confidence secret scanning, project plist lint, GSD consistency, and `git diff --check` pass.
- Generated SwiftPM build and Xcode workspace state was removed; no generated project workspace or package build directory is retained.
- No signed physical-device, real camera/ARKit sensor, signing, installation, launch, thermal, human, GATE-013 GREEN, or GATE-002 GREEN evidence is claimed.

## User Setup Required

None - this plan uses Apple platform frameworks and the existing locked local contracts package; it adds no dependency, credential, or service configuration.

## Next Phase Readiness

- Plan 01-13 can harden the candidate release surface against the now-tested attempt, epoch, packet, journal, and recovery boundaries.
- Plan 01-14 must still produce real signed base-device evidence before D-05 promotion or physical acceptance; GATE-013 and GATE-002 remain pending.
- The persisted Phase 1 lifecycle deliberately stops at `frame_network_eligible`; server acknowledgement remains absent.

## Self-Check: PASSED

- All seven declared Swift files and the required project membership exist, all four TDD commits are present, and targeted plus full simulator tests pass.
- Schema field sets, journal/event sequences, self and replay digests, exact projections, crash seams, quarantine boundaries, bounded file operations, and real Foundation filesystem behavior are covered.
- Required quick contract checks, metadata/boundary scans, tracked secret scanning, GSD consistency, plist lint, and `git diff --check` pass.
- No partial packet exposure, silent epoch relabeling, reverse-correction inference, network/server-ack product path, physical evidence fabrication, LiDAR requirement, or generated local workspace/build artifact remains.

---
*Phase: 01-contract-and-device-proof*
*Completed: 2026-07-17*
