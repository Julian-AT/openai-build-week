---
phase: 06-controlled-multi-surface-removal
plan: "03"
subsystem: native-removal-demo
tags: [swiftui, realitykit, removal, demo-fixture, accessibility]
requires:
  - phase: 06-controlled-multi-surface-removal
    provides: deterministic degraded remove reducer and durable sole branch authority from Plans 01 and 02
  - phase: 05-curated-replacement-vertical
    provides: retained one-session RealityKit/SwiftUI presentation and exact retry/restart/restore patterns
provides:
  - DEBUG-only degraded removal fixture with exact compiled bytes and fail-closed normal/Release isolation
  - Deterministic HYPOTHESIS pose envelope with two retained local reveal-proxy surfaces
  - Accessible preview, cancel, confirm, retry, relaunch, and compensating Restore journey
affects: [06-04-evidence, phase-08-hardening, physical-device-uat]
tech-stack:
  added: []
  patterns: [compiled exact-byte fixture, immutable reveal snapshot, retained proxy surfaces, debug-only launch authorization]
key-files:
  created:
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/Resources/Phase6Reveal/demo-reveal-fixture.json
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/Resources/Phase6Reveal/PROVENANCE.md
  modified:
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/RoomEditModel.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/RoomEditView.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProofTests/RoomEditModelTests.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProofUITests/RoomEditJourneyTests.swift
key-decisions:
  - "Only a DEBUG-only explicit launch argument can select degraded_demo_fixture; normal and Release paths remain remove-unavailable with reveal_quality_failed."
  - "The audit JSON is byte-identical to a compiled Swift constant and is never loaded from Bundle or added to PBX resources."
  - "Two retained local floor/wall proxies are presentation fixtures only; they are not observed surfaces, occluders, provider output, or quality evidence."
patterns-established:
  - "Unsafe pose, tracking, world epoch, or fixture state cancels preview and restores the safe original display without revision mutation."
  - "SwiftUI consumes immutable snapshots while the coordinator retains generated RealityKit entities and performs no I/O in updateUIView."
trace-requirements: [FR-REMOVE-001]
requirements-completed: []
formal-acceptance: pending
coverage:
  - id: D1
    description: Closed normal/demo launch isolation, exact fixture decoding, bounded pose, safe invalidation, and exact remove authority journey
    requirement: FR-REMOVE-001
    verification:
      - kind: integration
        ref: "ReRoomDeviceProofTests/RoomEditModelTests"
        status: pass
      - kind: automated_ui
        ref: "RoomEditJourneyTests#testNormalLaunchKeepsRemoveUnavailableWithoutDemoEnablement, #testDemoRevealCompleteJourneyIsExactlyOnceAndRestorable, #testDemoRevealInvalidStatesRetainOriginal"
        status: pass
    human_judgment: false
  - id: D2
    description: Physical reveal quality, coverage, seams, foreground overwrite, performance, and human visual vote
    requirement: FR-REMOVE-001
    verification: []
    human_judgment: true
    rationale: "The implementation and simulator fixture cannot establish GATE-006 or any physical/human quality claim."
duration: 17min
completed: 2026-07-18
status: plan-implementation-complete
---

# Phase 6 Plan 03: Bounded Native Removal Demo Summary

**The native app now exposes removal only through an unmistakable DEBUG fixture with two retained proxy surfaces and an exact authority-backed journey, while normal and Release builds stay fail-closed.**

## Performance

- **Duration:** 17 min
- **Started:** 2026-07-18T21:19:00+02:00
- **Completed:** 2026-07-18T21:36:00+02:00
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments

- Added strict exact-byte fixture decoding with target, branch, world epoch, revision, frozen seed pose, named finite HYPOTHESIS bounds, stable envelope ID, and two local proxy descriptors.
- Routed preview, confirmation, idempotent retry, restart recovery, and captured-exact Restore through `NativeBranchAuthority`; tracking/world/pose/fixture failures retain the original without mutation.
- Added a persistent `DEMO REVEAL FIXTURE - GATE-006 PENDING` surface, accessible native controls, and two retained RealityKit/fixture entities without Bundle/PBX resource changes or per-update I/O.

## Task Commits

1. **Task 1 RED:** `e493db2` — failing launch isolation, fixture, authority, and invalidation tests.
2. **Task 1 GREEN:** `fb98394` — compiled fixture, bounded model, and exact remove authority wiring.
3. **Task 1 test fix:** `2b45708` — corrected the existing mutable support-probe seam.
4. **Task 2 RED:** `3ff3de6` — failing normal/demo/invalid-state UI journeys.
5. **Task 2 GREEN:** `99a2a67` — DEBUG launch gate, persistent demo UI, retained proxy rendering, and accessible actions.
6. **Final honesty regression:** `a79433c` — byte-identical audit mirror/PBX exclusion and world-reset invalidation.

## Verification

- Focused `RoomEditModelTests`: **passed**.
- Focused exact demo journey: **passed** at preview r0, confirm r1, identical retry r1, relaunch r1, and Restore r2.
- Focused normal-launch and invalid-state UI cases: **passed** for no demo enablement plus out-of-view, corrupt fixture, and tracking-loss retention.
- Debug and Release iPhone 17 simulator builds: **passed**.
- Audit JSON parse and SHA-256 (`5a7cb9ef...c63783`), exact compiled-byte equality, PBX/Bundle exclusion, scoped secret scan, static retained-surface/update callback scan, and `git diff --check`: **passed**.

## Decisions Made

- Used compile-time `#if DEBUG` launch authorization so Release cannot select the demo reducer path even if the argument is supplied.
- Kept the normal target readiness matrix unchanged at `unavailable / reveal_quality_failed`; the demo classification exists only in a separate immutable presentation snapshot.
- Applied the SwiftUI expert guidance by using native Buttons and stable accessibility identifiers, retaining RealityKit entities in the coordinator, and restricting `updateUIView` to in-memory snapshot application.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking compile fix] Completed new blocker presentation during model GREEN**

- **Issue:** Adding closed remove blocker cases made the existing SwiftUI switch non-exhaustive before Task 2.
- **Fix:** Added minimal exhaustive copy, then completed the full presentation in Task 2.
- **Verification:** Focused model tests and both builds passed.
- **Committed in:** `fb98394`.

**2. [Rule 1 - Test fixture fix] Used the existing mutable support-probe API**

- **Issue:** The first RED helper assumed actor-style `value()`/`set()` methods that the existing main-actor probe does not expose.
- **Fix:** Read and assigned its existing `value` property directly.
- **Verification:** Focused model suite passed.
- **Committed in:** `2b45708`.

**Total deviations:** 2 narrow fixes (1 compile integration, 1 test seam).
**Impact on plan:** No product scope, dependency, PBX, signing, canonical schema, or formal-gate status changed.

## Issues Encountered

- The provenance build phase intentionally rejected dirty product source during pre-commit checks. Each scoped source commit was made before the authoritative focused run, matching the repository's source-binding workflow.

## User Setup Required

None.

## Next Phase Readiness

- Plan 06-04 can bind automated evidence to this exact implementation without promoting the fixture into production readiness.
- `GATE-006`, `GATE-003`, `GATE-005`, `GATE-009`, and `OPS-GOLDEN-001` remain `PENDING`. No observed/provider/occluder/coverage/seam/foreground/vote or physical-device claim was made.

## Self-Check: PASSED WITH FORMAL ACCEPTANCE PENDING

- All six planned source/test/audit files exist and the audit files are absent from PBX resources.
- TDD and correction commits listed above exist.
- Focused model/UI tests, Debug/Release builds, JSON/hash/static/secret/whitespace checks passed.
- `FR-REMOVE-001` is trace-only here; formal physical/human acceptance remains pending.

---
*Phase: 06-controlled-multi-surface-removal*
*Completed: 2026-07-18*
