---
phase: 05-curated-replacement-vertical
plan: "03"
subsystem: native-replacement-ui
tags: [swiftui, realitykit, accessibility, replacement, simulator]
requires:
  - phase: 05-curated-replacement-vertical
    provides: durable exactly-once replace authority and versioned controlled target from Plan 02
  - phase: 04-target-grounding-and-compositor-gate
    provides: retained AR session and bounded manual target presentation
provides:
  - Safe supported-view Replace preview, explicit confirmation, idempotent retry, restart, and Restore UI
  - One-time retained RealityKit loading of the exact bundled six-cube USDA outside updateUIView
  - Fail-closed replacement asset state with separate target coverage and replacement render identities
  - Stable accessible controls and simulator automation for the replacement journey
affects: [05-04-evidence, phase-07-replay, physical-device-uat]
tech-stack:
  added: []
  patterns: [closed asset readiness state, retained RealityKit template, immutable render snapshot, explicit accessible transaction controls]
key-files:
  created: []
  modified:
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/RoomEditModel.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/RoomEditView.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/Resources/Phase3Proxy/PROVENANCE.md
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/Resources/Phase3Proxy/asset-manifest.json
    - ios/ReRoomDeviceProof/ReRoomDeviceProofTests/RoomEditModelTests.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProofUITests/RoomEditJourneyTests.swift
key-decisions:
  - "Replacement is available only when the deterministic supported view and exact local proxy asset are both ready; every other state retains the safe target and explains the blocker."
  - "RealityKit synchronously loads proxy-chair.usda once in Coordinator initialization and retains a template; updateUIView performs only in-memory snapshot application."
  - "The generated translucent box remains target coverage only and is never a replacement success fallback."
patterns-established:
  - "SwiftUI consumes narrow immutable snapshots while the retained renderer owns expensive asset setup."
  - "Preview, confirmation, retry, and restore remain explicit native controls with stable accessibility identifiers."
requirements-implemented: [FR-REPLACE-001]
coverage:
  - id: D1
    description: Safe supported-view replacement state, rollback, retry, tracking revocation, and restore behavior
    requirement: FR-REPLACE-001
    verification:
      - kind: integration
        ref: "xcodebuild test -project ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj -scheme ReRoomDeviceProof -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:ReRoomDeviceProofTests/RoomEditModelTests"
        status: pass
    human_judgment: false
  - id: D2
    description: Exact bundled six-cube asset loading and one complete Replace/retry/restart/Restore simulator journey
    requirement: FR-REPLACE-001
    verification:
      - kind: automated_ui
        ref: "ReRoomDeviceProofUITests/RoomEditJourneyTests#testBundledReplacementLoadsAndFullJourneyIsExactlyOnce"
        status: pass
    human_judgment: false
  - id: D3
    description: Five deterministic fixture iterations and injected asset-loader failure behavior
    requirement: FR-REPLACE-001
    verification:
      - kind: automated_ui
        ref: "ReRoomDeviceProofUITests/RoomEditJourneyTests#testFiveDeterministicReplacementFixtureIterations and #testReplacementLoaderFailureRetainsSafeTarget"
        status: unknown
    human_judgment: true
    rationale: "The tests are implemented, but three focused simulator attempts ended in UI-runner Busy/preflight termination before assertions executed."
  - id: D4
    description: Physical-device replacement loading and formal visual/parity gate acceptance
    requirement: FR-REPLACE-001
    verification: []
    human_judgment: true
    rationale: "Simulator wiring cannot prove device loading, compositing quality, native/web parity, or the pending formal gates."
duration: 20min
completed: 2026-07-18
status: complete
---

# Phase 5 Plan 03: Supported Replacement Journey Summary

**The native app now presents one bounded, accessible Replace journey using the exact retained local USDA while failing closed to the safe target whenever view or asset readiness is unavailable.**

## Performance

- **Duration:** 20 min
- **Started:** 2026-07-18T20:24:06+02:00
- **Completed:** 2026-07-18T20:44:01+02:00
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments

- Added closed replacement asset and supported-view readiness to immutable model/render snapshots, including cancel, retry, tracking reset, commit-failure rollback, restart, and captured-exact Restore behavior.
- Loaded `proxy-chair.usda` exactly once during retained RealityKit coordinator setup, verified its six model entities, cloned the retained template for presentation, and kept all file/network/loading work out of `updateUIView`.
- Exposed separate target-coverage and replacement states plus stable accessible Replace, Confirm, Cancel, Retry, and Restore controls with honest local-demo and pending-gate copy.
- Added one full journey, five-iteration fixture, and loader-failure UI automation without creating a second AR session or adding dependencies.

## Task Commits

1. **Task 1 RED:** `b6b8622` — safe replacement presentation tests.
2. **Task 1 GREEN:** `5ff3066` — supported-view model, closed asset state, and honest qualification metadata.
3. **Task 2 RED:** `d9ffcca` — retained replacement journey and failure-seam UI tests.
4. **Task 2 GREEN:** `fa97e51` — one-time exact USDA loading and accessible replacement UI.
5. **Task 2 fix:** `f519ef9` — one unambiguous accessible asset-load status element.

## Verification

- Focused `RoomEditModelTests`: **passed**.
- `testBundledReplacementLoadsAndFullJourneyIsExactlyOnce`: **passed** with one commit at revision 1, idempotent retry at revision 1, restart at revision 1, and Restore at revision 2.
- Debug iPhone 17 simulator build: **passed**.
- Release iPhone 17 simulator build: **passed**.
- Static scan: `Entity.load` occurs in retained coordinator initialization; `updateUIView` only applies an in-memory snapshot. No `URLSession` or file read exists in that callback.
- Asset manifest JSON parsing, `git diff --check`, and focused credential-pattern scan: **passed**.
- Five-iteration and injected-loader-failure UI tests: **implemented but not executed successfully** after three focused attempts were stopped by the simulator UI-runner (`FBSOpenApplicationErrorDomain` Busy/preflight termination and one runner termination before test execution). No product assertion failed.

## Decisions Made

- Used a closed asset readiness state instead of an optional success flag so missing, mismatched, or unloadable resources cannot accidentally enable Replace.
- Kept the target coverage proxy and opaque local replacement as distinct render entities; load failure never swaps in generated geometry as a replacement.
- Followed the SwiftUI skill by keeping expensive retained renderer setup outside view updates, driving UI from narrow immutable state, and using native Buttons with explicit accessibility labels and identifiers.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking compile fix] Completed the new blocker switch during Task 1 GREEN**

- **Found during:** Task 1 model implementation.
- **Issue:** Adding closed blocker cases made the existing SwiftUI switch non-exhaustive before the full Task 2 presentation existed.
- **Fix:** Added minimal exhaustive descriptions in the same GREEN cycle; Task 2 then replaced them with the full bounded presentation.
- **Verification:** Focused model tests and both simulator builds passed.
- **Committed in:** `5ff3066`.

**2. [Rule 1 - Accessibility defect] Removed duplicate asset-status matches**

- **Found during:** Task 2 focused UI journey.
- **Issue:** A SwiftUI `Label` propagated one accessibility identifier to both its image and text, producing an ambiguous UI-test match.
- **Fix:** Used a hidden decorative image and one identified text element.
- **Verification:** The complete focused replacement journey passed afterward.
- **Committed in:** `f519ef9`.

**Total deviations:** 2 auto-fixed (1 blocking compile fix, 1 accessibility defect).
**Impact on plan:** Both were narrow correctness fixes inside the planned files; no dependency, schema, PBX, session, or product-scope expansion occurred.

## Issues Encountered

- The iOS simulator UI runner repeatedly failed to launch the two remaining focused tests. Their evidence stays explicitly unknown rather than being inferred from source or the passing full journey.
- Concurrent phase work added unrelated commits while this plan ran. Only the five Plan 03 task commits and this summary describe this plan's scope.

## User Setup Required

None.

## Next Phase Readiness

- Plan 05-04 can collect replacement evidence from the passing model suite, passing full simulator journey, and Debug/Release builds.
- Before formal phase acceptance, rerun the five-iteration and load-failure UI tests on a healthy simulator and complete physical-device evidence.
- `GATE-003`, `GATE-005`, `GATE-009`, `GATE-011`, and `OPS-GOLDEN-001` remain `PENDING`; this plan makes no physical-device or native/web parity claim.

## Self-Check: PASSED WITH DECLARED PENDING EVIDENCE

- All six planned source/test/metadata files exist.
- TDD commits `b6b8622`, `5ff3066`, `d9ffcca`, `fa97e51`, and `f519ef9` exist.
- Model tests, the full focused UI journey, Debug build, Release build, JSON validation, static callback scan, and diff check passed.
- Repeated-fixture/load-failure UI execution and all formal/physical gates remain explicitly pending above.

---
*Phase: 05-curated-replacement-vertical*
*Completed: 2026-07-18*
