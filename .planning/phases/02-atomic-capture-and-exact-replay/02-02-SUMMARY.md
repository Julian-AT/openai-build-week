---
phase: 02-atomic-capture-and-exact-replay
plan: "02"
subsystem: atomic-capture-writer
tags: [swift, actor, rrcap, durability, crash-injection, consent]

requires:
  - phase: 02-atomic-capture-and-exact-replay
    plan: "01"
    provides: Immutable capture values, CON-001/CON-002 validators, synchronous filesystem seam, and frozen replay oracle
provides:
  - Sole actor-owned consent-bound archive writer with the exact five-state frame lifecycle
  - Byte-valid CON-001 packet/image generation and journal-authoritative immutable network receipts
  - Exact gateway acknowledgement binding and acknowledgement-independent local finalization
  - Atomic self-digested CON-002 manifest publication for empty and framed sessions
  - Pre/post operation fault injection with a 77-case crash matrix and immutable earlier-prefix proof
affects: [02-03-recovery-replay, 02-04-admission-queues, 02-05-cross-runtime-replay, 02-06-native-adapter]

tech-stack:
  added: []
  patterns: [synchronous-actor-transaction, record-first-publication, pre-post-durability-observation, fresh-root-parameterized-faults]

key-files:
  created:
    - ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/CaptureArchiveStore.swift
    - ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/FramePacketEncoder.swift
    - ios/Packages/ReRoomContracts/Tests/ReRoomCaptureCoreTests/CaptureLifecycleTests.swift
    - ios/Packages/ReRoomContracts/Tests/ReRoomCaptureCoreTests/CaptureCrashMatrixTests.swift
  modified:
    - ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/CaptureFileSystem.swift

key-decisions:
  - "Keep all sequence allocation, lifecycle inspection, and filesystem mutation inside one synchronous actor-isolated transaction with no suspension point."
  - "Return NetworkEligibleReceipt only after image, packet, lifecycle payloads, frame reference, and authoritative journal bytes cross their sync boundaries."
  - "Treat gateway acknowledgement as an exact receipt-bound fifth event that never controls local durability, visibility, replay, or finalization."
  - "Preserve the existing pre-operation filesystem observer and add a backward-compatible post-operation observer so both sides of every durability edge are injectable."

patterns-established:
  - "Record-first visibility: internal generation rename may leave orphan bytes, but only a complete hash-valid frame record plus exact lifecycle prefix can become replay/network eligible."
  - "Crash proof: each parameterized case owns a fresh archive root, literal fault boundary, and literal durable frame/eligibility/ack/finalization expectation."
  - "Finalization: append session_finalized, verify the complete in-memory/disk projection, atomically replace manifest.json, then sync the file and archive directory."

requirements-completed: [FR-CAPTURE-001, SEC-CONSENT-001]

coverage:
  - id: D1
    description: "A current-session authorization is required before archive creation, concurrent starts cannot transfer consent, and each frame follows only the exact five-state lifecycle."
    requirement: SEC-CONSENT-001
    verification:
      - kind: integration
        ref: "swift test --package-path ios/Packages/ReRoomContracts --filter CaptureLifecycleTests"
        status: pass
    human_judgment: false
  - id: D2
    description: "Network-eligible receipts bind byte-valid CON-001 packet/image digests and authoritative journal sequence, while explicit empty or framed stop publishes a self-digested CON-002 manifest independently of acknowledgement."
    requirement: FR-CAPTURE-001
    verification:
      - kind: integration
        ref: "ios/Packages/ReRoomContracts/Tests/ReRoomCaptureCoreTests/CaptureLifecycleTests.swift#frameTransactionIsExactAndByteValid"
        status: pass
      - kind: integration
        ref: "ios/Packages/ReRoomContracts/Tests/ReRoomCaptureCoreTests/CaptureLifecycleTests.swift#emptySessionFinalization"
        status: pass
      - kind: integration
        ref: "ios/Packages/ReRoomContracts/Tests/ReRoomCaptureCoreTests/CaptureLifecycleTests.swift#localFinalizationWithoutAcknowledgement"
        status: pass
    human_judgment: false
  - id: D3
    description: "Seventy-seven pre/post operation terminations across start, first/later frame, acknowledgement, and finalization recover only hash-valid contiguous prefixes without mutating an earlier frame or exposing an unjournaled network reference."
    requirement: FR-CAPTURE-001
    verification:
      - kind: integration
        ref: "swift test --package-path ios/Packages/ReRoomContracts --filter CaptureCrashMatrixTests"
        status: pass
    human_judgment: false
  - id: D4
    description: "Concurrent publishers receive unique monotonic actor-owned sequences, collisions mutate no bytes, and production Foundation I/O matches the memory fault fake byte-for-byte and operation-for-operation."
    requirement: FR-CAPTURE-001
    verification:
      - kind: integration
        ref: "ios/Packages/ReRoomContracts/Tests/ReRoomCaptureCoreTests/CaptureCrashMatrixTests.swift#concurrentPublishersAreSerializedByTheWriter"
        status: pass
      - kind: integration
        ref: "ios/Packages/ReRoomContracts/Tests/ReRoomCaptureCoreTests/CaptureCrashMatrixTests.swift#productionAndMemoryParity"
        status: pass
    human_judgment: false

duration: 28min
completed: 2026-07-17
status: complete
---

# Phase 02 Plan 02: Consent-Bound Atomic Capture Writer Summary

**A sole synchronous Swift actor now turns session-bound consent into byte-valid record-first FramePackets, exact five-state journal authority, acknowledgement-independent local replay, and atomic finalized manifests proven across 77 operation-level crash cases.**

## Performance

- **Duration:** 28 min
- **Started:** 2026-07-17T22:01:35Z
- **Completed:** 2026-07-17T22:29:36Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments

- Implemented `CaptureArchiveStore` as the only mutable archive authority: it validates per-session consent, allocates every frame/event/global-journal sequence, and performs each lifecycle transition and filesystem operation without an actor reentrancy seam.
- Encoded and validated exact CON-001 metadata/image bytes and RRFP-WIRE-1 envelopes, returning an immutable network receipt only after image, packet, event payload, frame journal reference, and network-eligibility event are durably ordered.
- Enforced exact receipt-bound gateway acknowledgements as the fifth lifecycle event while retaining complete local replay/finalization without a gateway or network.
- Published schema-valid zero-frame and framed CON-002 manifests through a self-digested explicit-finalization transaction.
- Proved pre/post write, file-sync, directory-sync, rename, append, and replace faults across start, first frame, every later-frame operation, acknowledgement, and finalization; earlier durable files remain byte-identical and orphan generations remain non-visible.

## Task Commits

Each task was developed RED then GREEN and committed atomically:

1. **Task 1: Drive consented frames through the exact five-state transaction** - `38d52fc` (RED test), `8d676c5` (GREEN implementation)
2. **Task 2: Prove every durability edge and earlier-record invariant** - `71be3b0` (RED test), `3ad69cb` (GREEN implementation)

**Plan metadata:** recorded by the closeout commit containing this summary.

## Files Created/Modified

- `ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/CaptureArchiveStore.swift` - Sole actor writer, exact lifecycle/acknowledgement authority, journal projections, and explicit manifest transaction.
- `ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/FramePacketEncoder.swift` - CON-001/JCS/RRFP adapter with immutable encoding profile and payload binding.
- `ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/CaptureFileSystem.swift` - Adds post-operation observation while preserving the existing pre-operation fault contract.
- `ios/Packages/ReRoomContracts/Tests/ReRoomCaptureCoreTests/CaptureLifecycleTests.swift` - Consent, adjacency, collision, acknowledgement, packet, and empty/framed finalization coverage.
- `ios/Packages/ReRoomContracts/Tests/ReRoomCaptureCoreTests/CaptureCrashMatrixTests.swift` - Fresh-root operation fault matrix, durable-prefix scanner, earlier-byte oracle, concurrency checks, and production/memory parity proof.

## Decisions Made

- Kept archive storage synchronous inside the actor. External callers use `await` only to enter actor isolation; the transaction bodies contain no `async` adapter or suspension point.
- Made authoritative journal order the only route to eligibility. Staging or renamed frame bytes can survive a fault but cannot create a receipt, upload reference, acknowledgement, or replay-visible frame without the exact hash-valid lifecycle prefix.
- Required acknowledgement to match session, frame, idempotency key, packet digest, and accepted sequence exactly before appending `frame_server_acknowledged`; acknowledgement does not change local receipt or finalization eligibility.
- Added an optional post-operation observer to `FoundationCaptureFileSystem` rather than changing the established pre-operation callback, keeping existing integrations source-compatible while allowing faults after mutation/durability calls.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- The first matrix GREEN run exposed two test-oracle mistakes: eight frames produce 33 events but 41 global-journal records, and an acknowledged lifecycle is the four-event eligible prefix plus the fifth acknowledgement. Both expectations were corrected before acceptance.
- Foundation temporary URLs enumerate through the resolved `/private/var` path while the original root may use `/var`; the production/memory byte-parity helper now normalizes at the archive-relative `archives/` boundary. Product archive path resolution was already symlink-aware and unchanged.

## Verification Evidence

- `swift test --package-path ios/Packages/ReRoomContracts --filter CaptureLifecycleTests` passed all 12 tests, including 21 invalid-transition arguments and five acknowledgement-mismatch arguments.
- `swift test --package-path ios/Packages/ReRoomContracts --filter CaptureCrashMatrixTests` passed four tests, including all 77 explicit fault cases.
- `swift test --package-path ios/Packages/ReRoomContracts` exited successfully across the complete eight-suite package.
- Source inspection found zero `async` or `await` tokens in `CaptureArchiveStore`; all filesystem transitions remain synchronous actor-isolated calls.
- `Package.resolved` remains unchanged at SHA-256 `d6a939867cb3f1eb438da2b7806d9d128ba715312ea10449092a98d532309501`.
- GSD roadmap consistency has zero warnings. GSD health has zero errors and only the pre-existing non-repairable `W004` warning for `model_profile: adaptive`; pending future-plan summaries remain informational.
- Targeted secret scanning and `git diff --check` passed.

## User Setup Required

None - no external service, credential, dependency, endpoint, deployment, or cloud resource was added.

## Next Phase Readiness

- Plan 02-03 can recover and replay the exact durable journal/file prefix using the actor's stable record shapes and crash matrix as its recovery oracle.
- Plan 02-04 can consume immutable `NetworkEligibleReceipt` values without observing actor internals or coupling durable order to live completion order.
- Plans 02-05 and 02-06 can consume byte-valid CON-001/CON-002 output and truthful local acknowledgement/finalization state.
- Ready for Plan 02-03 or the independent Wave 2 Plan 02-04 with no product or planning blocker.

## Self-Check: PASSED

- All four TDD commits exist in repository history and every declared artifact exists at its planned path.
- Both task verifiers and the complete Swift package passed after the final source/test change.
- No actor transaction contains a suspension point, no dependency lock changed, and no unresolved prohibited receipt/consent path remains in the tested writer boundary.
- Pre-existing config, Xcode scheme, `.swiftpm`, workspace, and user-data changes were preserved outside plan commits.

---
*Phase: 02-atomic-capture-and-exact-replay*
*Completed: 2026-07-17*
