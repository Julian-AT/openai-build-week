---
phase: 02-atomic-capture-and-exact-replay
plan: "04"
subsystem: bounded-capture-admission
tags: [swift, concurrency, bounded-queue, replay, backpressure, offline-transport]

requires:
  - phase: 02-atomic-capture-and-exact-replay
    plan: "01"
    provides: Immutable capture values, classified selection/pressure policies, bounded filesystem seam, and frozen replay oracle
provides:
  - Pure deterministic selector with exact binary32 boundaries and metadata-only pre-lifecycle admission candidates
  - Synchronous ordinary-capacity plus one reserved user-event admission gate with one leased consumer
  - Bounded newest-useful post-durability queue with priority, cancellation, pressure, and exact metrics
  - Typed provider-independent echo, delayed, reordered, duplicated, and blackholed acknowledgement fixture
affects: [02-05-cross-runtime-replay, 02-06-native-capture-adapter, 02-07-capture-evidence]

tech-stack:
  added: []
  patterns: [synchronous-lock-admission, wake-only-bounded-stream, reserved-single-flight-lane, bounded-newest-useful-queue, receipt-bound-offline-transport]

key-files:
  created:
    - ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/FrameSelectionPolicy.swift
    - ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/CaptureAdmission.swift
    - ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/BoundedLatestQueue.swift
    - ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/CaptureTransport.swift
    - ios/Packages/ReRoomContracts/Tests/ReRoomCaptureCoreTests/FrameSelectionTests.swift
    - ios/Packages/ReRoomContracts/Tests/ReRoomCaptureCoreTests/CaptureAdmissionTests.swift
    - ios/Packages/ReRoomContracts/Tests/ReRoomCaptureCoreTests/BoundedQueueTests.swift
  modified: []

key-decisions:
  - "Treat the admission sequence as the sole merge order for ordinary and reserved lanes; reserved capacity changes eligibility, not replay order."
  - "Count queued plus the single writer lease as outstanding and release lane occupancy only at terminal writer completion."
  - "Use one shared CapturePressurePolicy observation for admission and live queues so degradation remains optional-compute drop, upload pause, then cadence/quality reduction."
  - "Keep acknowledgement scheduling as a pure receipt-bound offline fixture; completion order and duplication never mutate receipt or journal order."

patterns-established:
  - "Pre-lifecycle admission: the selector may create only metadata until synchronous admission succeeds; SelectedFrameCandidate construction and frame_selected publication remain downstream writer responsibilities."
  - "Wake-only handoff: AsyncStream<Void>.bufferingNewest(1) signals one consumer, while fixed-capacity lock state retains all admitted work."
  - "Live-order isolation: bounded receipt queues may replace stale optional work or prioritize explicit/keyframe work without deleting or reordering durable journal records."

requirements-completed: [NFR-REPLAY-001, FR-CAPTURE-001]

coverage:
  - id: D1
    description: "Equal cadence, view, quality, keyframe, and explicit-user inputs produce equal eligibility and schema-owned reasons at exact binary32 threshold and adjacent values without provider or model input."
    requirement: NFR-REPLAY-001
    verification:
      - kind: unit
        ref: "swift test --package-path ios/Packages/ReRoomContracts --filter FrameSelectionTests"
        status: pass
    human_judgment: false
  - id: D2
    description: "Synchronous admission never exceeds ordinaryCapacity plus one reserved explicit candidate across queued and writer-in-flight work; rejected offers never reach the writer and close modes report every bounded pre-selection termination."
    requirement: FR-CAPTURE-001
    verification:
      - kind: concurrency
        ref: "ios/Packages/ReRoomContracts/Tests/ReRoomCaptureCoreTests/CaptureAdmissionTests.swift#stalledWriterStressIsBounded"
        status: pass
      - kind: unit
        ref: "swift test --package-path ios/Packages/ReRoomContracts --filter CaptureAdmissionTests"
        status: pass
    human_judgment: false
  - id: D3
    description: "Post-durability work never exceeds injected capacity, preserves user-event/keyframe priority, replaces only stale lower-or-equal-priority queued work, and drains cancellation with exact metrics."
    requirement: NFR-REPLAY-001
    verification:
      - kind: concurrency
        ref: "swift test --package-path ios/Packages/ReRoomContracts --filter BoundedQueueTests"
        status: pass
    human_judgment: false
  - id: D4
    description: "Blackholed, delayed, reversed, and duplicated candidate completions create no acknowledgement without an immutable receipt and leave authoritative durable sequence order unchanged."
    requirement: NFR-REPLAY-001
    verification:
      - kind: unit
        ref: "ios/Packages/ReRoomContracts/Tests/ReRoomCaptureCoreTests/BoundedQueueTests.swift#transportCompletionOrderIsNonAuthoritative"
        status: pass
      - kind: concurrency
        ref: "ios/Packages/ReRoomContracts/Tests/ReRoomCaptureCoreTests/BoundedQueueTests.swift#blackholeRemainsBounded"
        status: pass
    human_judgment: false

duration: 16min
completed: 2026-07-18
status: complete
---

# Phase 02 Plan 04: Bounded Capture Admission and Live Work Summary

**A deterministic selector, synchronous bounded pre-durability gate, bounded receipt queue, shared pressure policy, and offline typed transport now prevent callback rate or completion order from creating replay authority.**

## Performance

- **Duration:** 16 min
- **Started:** 2026-07-17T22:40:57Z
- **Completed:** 2026-07-17T22:57:23Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments

- Implemented exact deterministic selection across explicit user events, keyframes, view novelty, cadence, motion, blur, and exposure, including non-finite rejection and exact binary32 boundary/adjacent behavior.
- Added a synchronous `OSAllocatedUnfairLock` gate with a fixed ordinary ring, exactly one nonreplaceable reserved user-event slot, monotonic admission sequence, one consumer lease, and a wake-only `bufferingNewest(1)` stream.
- Proved above-rate offers finish synchronously while a controlled writer is stalled, never exceed `ordinaryCapacity + 1`, never invoke the writer for rejected candidates, and preserve one sequential writer invocation.
- Added graceful drain and cancellation/expiration/storage abort semantics with explicit before-selection terminal results and exact close/depth/counter snapshots.
- Added a bounded newest-useful actor queue over immutable receipts, shared ordered pressure observations, explicit priority protection, deterministic cancellation, and typed echo/blackhole/delay/reorder/duplicate acknowledgement fixtures.

## Task Commits

Each task was developed RED then GREEN and committed atomically:

1. **Task 1: Select deterministically and bound admission before durability** - `1d70a6f` (RED test), `b4ccf31` (GREEN implementation)
2. **Task 2: Bound live work and prove completion-order independence** - `9d71978` (RED test), `22af576` (GREEN implementation)

**Plan summary:** recorded by the following documentation-only commit.

## Files Created/Modified

- `ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/FrameSelectionPolicy.swift` - Pure selection facts, rejection reasons, exact policy evaluation, and pre-lifecycle candidate conversion.
- `ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/CaptureAdmission.swift` - Fixed-capacity synchronous gate, reserved lane, single consumer, close semantics, and snapshots.
- `ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/BoundedLatestQueue.swift` - Capacity-bounded newest-useful receipt queue, priority leases, cancellation, metrics, and shared pressure observation.
- `ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/CaptureTransport.swift` - Provider-independent receipt-bound acknowledgement and deterministic completion schedules.
- `ios/Packages/ReRoomContracts/Tests/ReRoomCaptureCoreTests/FrameSelectionTests.swift` - Exact/adjacent threshold, reason, invalid-input, explicit, keyframe, and repeatability coverage.
- `ios/Packages/ReRoomContracts/Tests/ReRoomCaptureCoreTests/CaptureAdmissionTests.swift` - Reserved lane, stalled writer, capacity, close, terminal, and one-consumer concurrency coverage.
- `ios/Packages/ReRoomContracts/Tests/ReRoomCaptureCoreTests/BoundedQueueTests.swift` - Concurrent producer, replacement, priority, pressure, cancellation, blackhole, and completion-order coverage.

## Decisions Made

- Kept `offer` fully synchronous. It performs only a short lock-protected state transition followed by a nonblocking wake yield; it contains no task creation, actor call, suspension, archive bytes, lifecycle event, or user callback.
- Reserved one explicit-user slot without creating a priority replay order. Ordinary and explicit candidates merge only by monotonic admission sequence, and both remain outstanding through the writer lease until terminal completion.
- Used one pressure observation implementation for both pre-durability and post-durability snapshots. All capacities and thresholds remain injected `HYPOTHESIS` or `TARGET` policy values; none is claimed `MEASURED` before GATE-001.
- Allowed live queues to prefer newest useful work only after durability. Queue drops, cancellation, transport blackholes, and acknowledgement completion order never mutate the immutable receipt set or authoritative journal sequence.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- Swift 6 strict concurrency required the lock state and fixed ring to declare `Sendable` explicitly before `OSAllocatedUnfairLock` accepted the generic state. The declarations were added without weakening isolation or using unchecked conformance.

## Verification Evidence

- Both task-focused commands passed 21 tests across the selector, admission, and bounded-queue suites after the final source change.
- `swift test --package-path ios/Packages/ReRoomContracts` passed 78 tests in 11 suites.
- The controlled stalled-writer test passed ten consecutive runs; each run retained one writer and the exact `ordinaryCapacity + 1` maximum.
- Source inspection confirms `CaptureAdmissionGate.offer` has no `Task`, `await`, actor call, or user callback and the sole wake stream is `AsyncStream<Void>.bufferingNewest(1)`.
- Source scans found no live network/provider framework import and no unbounded stream policy. Every mutable live collection is fixed-capacity or bounded by the injected queue/admission capacity.
- The five Phase 2 fixture/schema oracle tests passed in the locked Python environment; `Package.resolved` remains unchanged at SHA-256 `d6a939867cb3f1eb438da2b7806d9d128ba715312ea10449092a98d532309501`.
- GSD consistency passed with only expected future-phase-directory warnings. GSD health had no errors or repairable findings and retained the pre-existing non-repairable `W004` warning for `model_profile: adaptive`.
- Targeted tracked-secret scanning, dependency-lock diff, and `git diff --check` passed.

## User Setup Required

None - no external service, credential, dependency, endpoint, deployment, live network, or cloud resource was added.

## Next Phase Readiness

- Plan 02-06 can bind the one consumer writer closure to `publishSelectedFrame` while preserving the proven pre-lifecycle admission boundary.
- Plan 02-05 and Plan 02-07 can use immutable receipts and journal sequence as their only replay/evidence authority; transport scheduling remains non-authoritative.
- GATE-001 physical measurements remain pending. Injected numeric policies stay `HYPOTHESIS`/`TARGET`, and no physical or human evidence was fabricated.

## Self-Check: PASSED

- All four TDD commits exist in repository history and all seven declared source/test artifacts exist at their planned paths.
- Focused tests, ten repeated deterministic stress runs, the complete Swift package, and Phase 2 fixture/schema tests passed after the final implementation.
- No dependency lock changed; no live provider/network import, unbounded wake payload, or production numeric default was introduced.
- Pre-existing config, Xcode scheme, `.swiftpm`, workspace, and user-data changes were preserved outside plan commits; generated Swift build products were reset after verification.

---
*Phase: 02-atomic-capture-and-exact-replay*
*Completed: 2026-07-18*
