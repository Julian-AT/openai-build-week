---
phase: 04-target-grounding-and-compositor-gate
plan: "02"
subsystem: native-ar-session
tags: [swift, arkit, realitykit, raycast, main-actor, swift-testing]

requires:
  - phase: 02-capture-replay-and-world-authority
    provides: Single native ARKit session authority and world-epoch safety events
  - phase: 03-typed-place-commit-and-offline-restore
    provides: RR-COORD-1 Matrix4 value boundary and captured scene revision
provides:
  - Ordered removable observers sharing one synchronous AR session event stream
  - Bounded explicit-tap raycast conversion into finite current-world value candidates
  - RealityKit ARView/session object graph with automatic session configuration disabled
affects: [04-03-native-compositor, target-grounding, device-proof, room-edit]

tech-stack:
  added: []
  patterns:
    - Main-actor synchronous observer registry with opaque monotonic tokens
    - Detected-horizontal-first raycast with explicit estimated-plane fallback
    - One ARView-created ARSession injected into the sole AR session driver

key-files:
  created: []
  modified:
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/ARSessionController.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProofTests/ARSessionPolicyTests.swift

key-decisions:
  - "Keep the existing onEvent callback as a compatibility seam while independent ordered observers prevent one consumer from monopolizing safety events."
  - "Inspect at most four raycast transforms per source, reject nonfinite values, and use estimated horizontal planes only when detected geometry yields no valid candidate."
  - "Construct one RealityKit ARView with automatic configuration disabled and inject that view's session into SystemARSessionDriver."

patterns-established:
  - "AR callbacks publish only coarsened safety transitions synchronously; no frame buffers or asynchronous queues enter the observer registry."
  - "Raycast results lose ARKit/RealityKit object identity at the boundary and retain only finite RR-COORD-1 values plus caller-supplied epoch/revision."

requirements-completed: [FR-TARGET-001, NFR-RENDER-001]

coverage:
  - id: D1
    description: "Multiple native consumers observe one ordered AR session safety stream with removal, reset, recovery, and duplicate-state coalescing."
    requirement: FR-TARGET-001
    verification:
      - kind: unit
        ref: "ios/ReRoomDeviceProof/ReRoomDeviceProofTests/ARSessionPolicyTests.swift#controllerDeliversToMultipleObserversInRegistrationOrder/controllerCoalescesDuplicateNoOpState/controllerRequiresExplicitRecovery"
        status: pass
    human_judgment: false
  - id: D2
    description: "Explicit taps resolve through detected geometry then bounded estimated fallback into finite current-world Matrix4 candidates on the shared RealityKit session."
    requirement: NFR-RENDER-001
    verification:
      - kind: unit
        ref: "ios/ReRoomDeviceProof/ReRoomDeviceProofTests/ARSessionPolicyTests.swift#targetRaycastPrefersDetectedGeometry/targetRaycastUsesBoundedEstimatedFallback/targetRaycastMissIsEmpty/systemDriverUsesInjectedSession"
        status: pass
      - kind: integration
        ref: "xcodebuild test -project ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj -scheme ReRoomDeviceProof -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:ReRoomDeviceProofTests/ARSessionPolicyTests"
        status: pass
    human_judgment: false

duration: 9min
completed: 2026-07-18
status: complete
---

# Phase 4 Plan 2: Shared AR Session and Bounded Raycast Summary

**One main-actor ARKit event stream now serves multiple native consumers while explicit taps become finite, capped RR-COORD-1 candidates through a compiler-checked single-session RealityKit adapter.**

## Performance

- **Duration:** 9 min
- **Started:** 2026-07-18T16:42:10Z
- **Completed:** 2026-07-18T16:50:39Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Replaced the single-consumer limitation with ordered removable observers while preserving the existing device-proof callback and synchronous interruption/failure revocation.
- Added explicit-tap raycast selection that prefers detected horizontal geometry, falls back visibly to an estimated horizontal plane, rejects nonfinite transforms, and returns at most four nonsemantic candidates.
- Compiler-checked the installed RealityKit API by building a shared object graph whose `ARView` is created once with automatic configuration disabled and whose session is injected into `SystemARSessionDriver`.

## Task Commits

Each task was committed atomically:

1. **Task 1 RED: shared AR observer contract** - `c9341a9` (test)
2. **Task 1 GREEN: ordered bounded event stream** - `27fe694` (feat)
3. **Task 2 RED: bounded raycast contract** - `cae73e2` (test)
4. **Task 2 GREEN: shared-session RealityKit raycast adapter** - `70c3487` (feat)
5. **Task 2 compile fix: explicit finite-value closure** - `1d17254` (fix)

## Files Created/Modified

- `ios/ReRoomDeviceProof/ReRoomDeviceProof/ARSessionController.swift` - Adds the observer registry, bounded raycast value boundary, RealityKit adapter, and shared ARView/session container.
- `ios/ReRoomDeviceProof/ReRoomDeviceProofTests/ARSessionPolicyTests.swift` - Proves event ordering/removal/coalescing, recovery safety, raycast preference/fallback/bounds, finite row-major conversion, empty misses, and injected session identity.

## Decisions Made

- Kept `onEvent` source-compatible for `DeviceProofModel`; registered observers are additive and cannot replace that consumer.
- Kept all observer and raycast work on the main actor with synchronous delivery and no buffered frame stream.
- Returned no semantic or renderer identity from raycasts; the later reducer receives only source, current world epoch, captured revision, and a finite matrix.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Replaced a Swift Testing key-path predicate that expanded as throwing**
- **Found during:** Task 2 focused GREEN build
- **Issue:** `allSatisfy(\.isFinite)` expanded through the Swift Testing macro as a throwing closure and stopped test compilation.
- **Fix:** Used an explicit nonthrowing closure without weakening the finite-value assertion.
- **Files modified:** `ios/ReRoomDeviceProof/ReRoomDeviceProofTests/ARSessionPolicyTests.swift`
- **Verification:** The complete focused suite passed after the fix.
- **Committed in:** `1d17254`

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** The fix was limited to test expression syntax and preserved the exact assertion.

## Issues Encountered

- Xcode initially exhausted local disk space while writing a generated test log. A sibling executor removed only the exact rebuildable ReRoom DerivedData cache; no repository or evidence file was removed.
- Simultaneous fresh SwiftPM resolution briefly collided after that cache reset. The overlapping build was stopped, the suites were serialized, and the solo 04-02 rerun passed.

## User Setup Required

None - no external service, provider, credential, package, or device-only configuration was added.

## Next Phase Readiness

- The compositor/UI plan can reuse `SharedRealityKitSession.view` and `controller` without creating a second session.
- The model-integration plan can map `TargetRaycastCandidate` values into its manual target reducer while assigning stable semantic identity outside ARKit/RealityKit.
- Formal `GATE-003`, `GATE-004`, `GATE-005`, `GATE-007`, and `GATE-012` evidence remains `PENDING`; this plan makes no physical-device or measured-performance claim.

## Self-Check: PASSED

- Both modified source/test files exist.
- All five task commits exist in repository history.
- Focused tests and prohibited-dependency scan passed.

---
*Phase: 04-target-grounding-and-compositor-gate*
*Completed: 2026-07-18*
