---
phase: 04-target-grounding-and-compositor-gate
plan: "03"
subsystem: native-compositor
tags: [swiftui, realitykit, arkit, compositor, accessibility, ui-testing]

requires:
  - phase: 04-target-grounding-and-compositor-gate
    plan: "01"
    provides: Deterministic manual target lifecycle, readiness, and recovery reducer
  - phase: 04-target-grounding-and-compositor-gate
    plan: "02"
    provides: One shared RealityKit ARView/session, bounded raycast adapter, and ordered safety observers
provides:
  - Retained live and deterministic fixture object graphs that publish immutable render snapshots
  - Exact six-layer compositor contract with reveal and occluder explicitly unavailable
  - Accessible native camera/proxy/readiness/reseed surface with complete transaction regression coverage
affects: [04-04-compositor-evidence, native-room-edit, target-grounding, release-demo]

tech-stack:
  added: []
  patterns:
    - One retained ARView/session graph with immutable snapshot-only SwiftUI consumption
    - Closed compositor descriptor validated before presentation
    - Launch-argument fixtures that never request simulator AR tracking

key-files:
  created: []
  modified:
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/RoomEditModel.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/RoomEditView.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProofTests/RoomEditModelTests.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProofUITests/RoomEditJourneyTests.swift

key-decisions:
  - "Retain exactly one live ARView/session/controller/device-proof/model object graph; deterministic UI fixtures use no AR tracking."
  - "Represent the compositor as exactly camera, reveal, occluder, asset/proxy, debug, SwiftUI, with reveal and occluder present but unavailable."
  - "Let SwiftUI and RealityKit consume immutable render snapshots only; no canonical authority or transaction actor crosses into the render update boundary."
  - "Keep simulator controls behind UI-test launch arguments and expose no production debug button."

patterns-established:
  - "Shared-session boundary: AR events are coarsened into target safety state before observation-driven UI updates."
  - "Snapshot-diff rendering: the representable synchronizes local entities only when immutable proxy state changes."

requirements-completed: [FR-TARGET-001, NFR-RENDER-001]

coverage:
  - id: D1
    description: "One live shared-session graph and deterministic no-AR fixtures ground, reseed, revoke, and render one stable target without changing transaction revision."
    requirement: FR-TARGET-001
    verification:
      - kind: unit
        ref: "ios/ReRoomDeviceProof/ReRoomDeviceProofTests/RoomEditModelTests.swift#targetSessionWiringIsCoarsenedAndRevisionNeutral/targetFixturesAreDeterministic"
        status: pass
      - kind: integration
        ref: "xcodebuild test -project ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj -scheme ReRoomDeviceProof -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -only-testing:ReRoomDeviceProofTests/RoomEditModelTests -only-testing:ReRoomDeviceProofTests/ReleaseSmokeTests"
        status: pass
    human_judgment: false
  - id: D2
    description: "The native surface presents local proxy, target epoch, five readiness states, recovery, fallbacks, pending gates, and all four transaction operations accessibly."
    requirement: NFR-RENDER-001
    verification:
      - kind: automated_ui
        ref: "ios/ReRoomDeviceProof/ReRoomDeviceProofUITests/RoomEditJourneyTests.swift#testManualTargetSeedReseedReadinessAndTrackingRevocation/testTargetMissAndAmbiguityAreExplicit/testPlaceCancelConfirmRelaunchAndOfflineRestore"
        status: pass
      - kind: integration
        ref: "Debug and Release iPhone Simulator builds"
        status: pass
    human_judgment: false
  - id: D3
    description: "The release surface uses the physical device camera behind the conservative local proxy through the retained shared AR session."
    requirement: NFR-RENDER-001
    verification: []
    human_judgment: true
    rationale: "Simulator automation cannot prove physical-camera compositing, device thermal behavior, or formal GATE-003/004/005/007/012 evidence; those gates remain PENDING."

duration: 22min
completed: 2026-07-18
status: complete
---

# Phase 4 Plan 3: Native Target Compositor Integration Summary

**The native room-edit surface now retains one shared AR session, renders a conservative local target proxy behind accessible SwiftUI controls, and exposes exact readiness and recovery without fabricating deferred capabilities.**

## Performance

- **Duration:** 22 min
- **Started:** 2026-07-18T16:55:02Z
- **Completed:** 2026-07-18T17:17:18Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Wired one retained live ARView/session/controller/device-proof/model graph and deterministic healthy, miss, ambiguity, and tracking-loss fixture graphs.
- Enforced the exact camera → reveal → occluder → asset/proxy → debug → SwiftUI descriptor, with reveal and occluder honestly unavailable.
- Added a local snapshot-diffed RealityKit proxy surface, explicit reseed/recovery UI, stable readiness reasons, accessibility identifiers, and full Phase 3 place/restore regression coverage.

## Task Commits

Each TDD task was committed in test-to-implementation order:

1. **Task 1 RED: Define target compositor integration contract** - `8b07aae`
2. **Task 1 GREEN: Integrate target session and render snapshots** - `17fdf95`
3. **Task 2 RED: Define target recovery UI journey** - `e4a8136`
4. **Task 2 GREEN: Present local target compositor and recovery** - `73dbf2e`
5. **Task 2 fixture automation fix** - `9af04b0`
6. **Task 2 transaction visibility fix** - `89b75d2`
7. **Final compatibility regression fix** - `a8f4435`

## Files Created/Modified

- `ios/ReRoomDeviceProof/ReRoomDeviceProof/RoomEditModel.swift` - Retained runtime graphs, target-session reduction, closed compositor descriptor, and immutable render snapshots.
- `ios/ReRoomDeviceProof/ReRoomDeviceProof/RoomEditView.swift` - Shared AR surface, local proxy synchronization, target/readiness/recovery overlay, and accessible operation controls.
- `ios/ReRoomDeviceProof/ReRoomDeviceProofTests/RoomEditModelTests.swift` - Exact layer, deterministic fixture, revision-neutral, and existing transaction assertions.
- `ios/ReRoomDeviceProof/ReRoomDeviceProofUITests/RoomEditJourneyTests.swift` - Seed/reseed/revocation, miss/ambiguity, and complete place/restore journeys.

## Decisions Made

- One runtime owner retains all live AR components so the camera, raycast authority, target model, and device proof cannot drift onto separate sessions.
- Reveal and occluder keep stable descriptor positions but remain unavailable until their later evidence gates pass.
- Fixture-only launch arguments provide deterministic automation without adding production debug controls or invoking simulator AR tracking.
- Transaction-only model harnesses may omit a target session; fail-closed tracking enforcement applies whenever a live or fixture target session is integrated.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Source provenance check required committed source**
- **Found during:** Task 1 and Task 2 GREEN verification
- **Issue:** The repository provenance script intentionally rejects dirty product source, so pre-commit builds reached and compiled the changed source but stopped at the provenance phase.
- **Fix:** Preserved atomic TDD commits, then ran the focused tests and builds against committed source.
- **Files modified:** None beyond the planned task files.
- **Verification:** Focused model/UI suites plus Debug and Release builds passed after each source commit.

**2. [Rule 1 - Bug] Added the concrete matrix module import**
- **Found during:** Task 2 compilation
- **Issue:** The RealityKit proxy transform used `Matrix4` across a module boundary without importing its defining package.
- **Fix:** Added the required import in the planned UI file.
- **Files modified:** `ios/ReRoomDeviceProof/ReRoomDeviceProof/RoomEditView.swift`
- **Verification:** Debug and Release builds compile the current RealityKit path.
- **Committed in:** `73dbf2e`

**3. [Rule 1 - Bug] Made fixture target activation and transaction actions automation-safe**
- **Found during:** Task 2 UI verification
- **Issue:** XCTest could not reliably synthesize taps through the fixture representable, and the new target detail placed existing transaction controls below the visible scroll region.
- **Fix:** Added a transparent fixture-only native target button, explicit test scrolling, and reordered transaction state/actions ahead of detailed target diagnostics.
- **Files modified:** `ios/ReRoomDeviceProof/ReRoomDeviceProof/RoomEditView.swift`, `ios/ReRoomDeviceProof/ReRoomDeviceProofUITests/RoomEditJourneyTests.swift`
- **Verification:** All three focused UI journeys pass together.
- **Committed in:** `9af04b0`, `89b75d2`

**4. [Rule 1 - Bug] Preserved the transaction-only model harness contract**
- **Found during:** Final focused `RoomEditModelTests` plus `ReleaseSmokeTests` rerun
- **Issue:** The new tracking guard treated an intentionally absent target session in two legacy Phase 3 transaction tests as unhealthy live tracking.
- **Fix:** Applied tracking enforcement whenever an integrated live/fixture target session exists, while preserving the transaction-only compatibility seam.
- **Files modified:** `ios/ReRoomDeviceProof/ReRoomDeviceProof/RoomEditModel.swift`
- **Verification:** The final 14-test focused model/release run passed, including the two previously exposed tests.
- **Committed in:** `a8f4435`

---

**Total deviations:** 4 auto-fixed (3 correctness, 1 blocking workflow constraint)
**Impact on plan:** All fixes were necessary to compile, preserve existing transaction semantics, and make the planned UI evidence deterministic. No product scope or deferred gate was expanded.

## Issues Encountered

- CoreSimulator intermittently denied a test-runner launch while cloning or reported the app busy. Successful serialized reruns separate these simulator-infrastructure events from product test results.
- Formal physical-device compositor, thermal, and quality gates were not fabricated; `GATE-003`, `GATE-004`, `GATE-005`, `GATE-007`, and `GATE-012` remain explicitly PENDING.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Plan 04-04 can collect evidence against a stable, exact compositor descriptor and deterministic recovery surface.
- Physical-device camera/proxy judgment and all named formal gates remain pending until real evidence is captured.

---
*Phase: 04-target-grounding-and-compositor-gate*
*Completed: 2026-07-18*
