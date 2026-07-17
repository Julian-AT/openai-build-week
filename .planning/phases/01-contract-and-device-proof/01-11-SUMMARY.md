---
phase: 01-contract-and-device-proof
plan: "11"
subsystem: ios-device-proof
tags: [swiftui, arkit, avfoundation, swift-testing, permissions]

requires:
  - phase: 01-contract-and-device-proof
    provides: Verified ReRoomContracts package, immutable coordinate policy, and approved Phase 1 UI contract from Plans 01-01 through 01-10
provides:
  - Portrait-only iOS 26 candidate app and unit-test targets linked to ReRoomContracts
  - Independent camera and optional-microphone authorization policy with fail-closed visual readiness
  - Injected AR world-tracking controller with horizontal/vertical plane events and no LiDAR requirement
  - Swift Testing coverage for permission, capture-eligibility, orientation, and session boundaries
affects: [01-12, 01-13, 01-14, mode-a-capture, gate-013]

tech-stack:
  added: []
  patterns: [main-actor observable view model, injected permission and AR session drivers, pure deterministic capability state, independent capability readiness]

key-files:
  created:
    - ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj/project.pbxproj
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/App.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/DeviceProofModel.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/PermissionController.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/ARSessionController.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/Info.plist
    - ios/ReRoomDeviceProof/ReRoomDeviceProofTests/ARSessionPolicyTests.swift
  modified: []

key-decisions:
  - "The iOS 26.0 deployment target remains only the ASSUMED Xcode 26.4/base-iPhone-17 Phase 1 proof baseline pending Plan 01-14 physical evidence; it is not a broader product minimum-OS decision."
  - "Microphone readiness uses AVFoundation authorization only and never creates audio capture; it cannot gate camera, ARKit, visual FramePacket, or typed/tap availability."
  - "Physical landscape changes capture eligibility only; it does not pause or restart the AR session."
  - "ARKit uses world tracking with horizontal and vertical plane detection only; scene reconstruction, scene depth, and rear-LiDAR gates remain absent."

patterns-established:
  - "Capability separation: required camera consent and optional microphone readiness are represented and tested independently."
  - "Injected Apple-framework boundary: deterministic policy is tested through permission and AR-session drivers without requiring physical sensors."
  - "Truthful candidate state: simulator success never promotes the build or substitutes for signed physical-device evidence."

requirements-completed: [OPS-DEVICE-001, NFR-COORD-001, NFR-CONTRACT-001]

coverage:
  - id: D1
    description: "A portrait-only iPhone candidate target links the verified contracts package, declares explicit camera/microphone usage metadata, and builds on the declared iOS 26 simulator baseline without edit, provider, compositor, audio-capture, or LiDAR surfaces."
    requirement: NFR-CONTRACT-001
    verification:
      - kind: integration
        ref: "xcodebuild -project ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj -scheme ReRoomDeviceProof -sdk iphonesimulator -configuration Debug build CODE_SIGNING_ALLOWED=NO"
        status: pass
      - kind: other
        ref: "plutil -lint ios/ReRoomDeviceProof/ReRoomDeviceProof/Info.plist and source/project boundary scans"
        status: pass
    human_judgment: false
  - id: D2
    description: "Camera and optional-microphone states are independent; camera denial fails visual work closed, microphone denial leaves otherwise-ready camera, AR, planes, minimal visual FramePacket, and typed/tap policies available, and landscape preserves the running AR session."
    requirement: OPS-DEVICE-001
    verification:
      - kind: unit
        ref: "ReRoomDeviceProofTests/ARSessionPolicyTests via the exact Plan 01-11 targeted xcodebuild test command"
        status: pass
      - kind: integration
        ref: "scripts/verify-phase-01-contracts quick"
        status: pass
    human_judgment: false
  - id: D3
    description: "The candidate remains explicitly unpromoted until a signed build installs and launches on the declared base iPhone and real camera, ARKit tracking, and plane behavior pass GATE-013."
    requirement: OPS-DEVICE-001
    verification:
      - kind: manual_procedural
        ref: "Plan 01-14 GATE-013 signed physical-device checklist"
        status: unknown
    human_judgment: true
    rationale: "Simulator policy tests cannot prove signing, installation, launch, camera behavior, or sensor-backed ARKit tracking on the physical base device."

duration: 23min
completed: 2026-07-17
status: complete
---

# Phase 01 Plan 11: Candidate iOS Device-Proof Seed Summary

**A portrait-only SwiftUI candidate now builds against ReRoomContracts and deterministically separates camera, optional microphone, orientation, AR tracking, and plane readiness without adding audio capture, LiDAR semantics, or physical-promotion claims.**

## Performance

- **Duration:** 23 min
- **Started:** 2026-07-17T00:03:11Z
- **Completed:** 2026-07-17T00:26:05Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments

- Created a narrow iPhone-only iOS 26 SwiftUI app and unit-test target, linked the local verified `ReRoomContracts` package, enabled Debug diagnostics, and declared portrait-only camera/microphone permission metadata without a rear-LiDAR capability requirement.
- Added four-state camera and microphone authorization behind an injected main-actor boundary; camera denial fails visual work closed while optional microphone denial never gates otherwise-ready camera, AR, plane, minimal visual FramePacket, or typed/tap policy.
- Added an injected ARKit controller that runs world tracking with horizontal and vertical plane detection, reports tracking/plane events, leaves orientation out of session lifecycle control, and performs no high-rate network, model, file, provider, compositor, or audio work.
- Added parameterized Swift Testing coverage for all authorization states, fail-closed camera behavior, microphone independence, portrait/landscape eligibility, no-LiDAR policy, request injection, and session preservation.

## Task Commits

Task 2 followed a failing-policy specification with its passing implementation:

1. **Task 1: Portrait-only candidate device-proof app** - `d483c0e` (feat)
2. **Task 2 RED: Permission and AR session policy specification** - `20ab960` (test)
3. **Task 2 GREEN: Permission, orientation, and AR session policies** - `b14caaf` (feat)

**Plan metadata:** recorded by the closeout commit containing this summary.

## Files Created/Modified

- `ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj/project.pbxproj` - App/test targets, iPhone/iOS 26 settings, local contracts product, Debug condition, and new source membership.
- `ios/ReRoomDeviceProof/ReRoomDeviceProof/App.swift` - Accessible portrait candidate shell with truthful permission, coaching, tracking, and pending-verification states.
- `ios/ReRoomDeviceProof/ReRoomDeviceProof/DeviceProofModel.swift` - Deterministic permission/orientation/session capability state and main-actor observable orchestration.
- `ios/ReRoomDeviceProof/ReRoomDeviceProof/PermissionController.swift` - Injected AVFoundation camera/microphone authorization boundary with four explicit fail-closed states.
- `ios/ReRoomDeviceProof/ReRoomDeviceProof/ARSessionController.swift` - Injected ARKit world-tracking driver, bounded plane/tracking callbacks, and orientation-independent lifecycle.
- `ios/ReRoomDeviceProof/ReRoomDeviceProof/Info.plist` - Portrait-only orientation and explicit camera/optional-microphone usage descriptions.
- `ios/ReRoomDeviceProof/ReRoomDeviceProofTests/ARSessionPolicyTests.swift` - Parameterized permission, independence, capture-eligibility, no-LiDAR, and session-driver tests.

## Decisions Made

- Kept iOS 26.0 as the plan's explicit ASSUMED proof baseline and labeled the UI as a candidate with physical verification pending; simulator success does not promote D-05 or establish a product-wide minimum OS.
- Used `AVCaptureDevice` authorization for the optional microphone readiness check but created no audio session, engine, recorder, capture output, file, or payload.
- Represented camera, microphone, AR tracking, plane observation, and capture eligibility as separate deterministic properties so one capability cannot silently stand in for another.
- Kept ARKit callbacks limited to session/tracking/plane evidence and exposed the current frame only for the next capture slice; no per-frame callback, network request, model call, or persistence work was introduced.

## Deviations from Plan

None - the plan was executed as written.

## Issues Encountered

- The first GREEN simulator test attempt could not clone the named simulator because CoreSimulator reported it busy. Booting and validating the named iPhone 17 simulator, then resetting its lifecycle, allowed the exact unchanged command to pass; no product workaround or test relaxation was made.
- GSD health remains degraded only by the pre-existing non-repairable `model_profile: adaptive` configuration warning. It reports no errors or repairable issues; pending-summary notices correctly identify future Plans 01-12 through 01-14.

## Verification Evidence

- The exact Task 1 simulator Debug build passes after the implementation commits with code signing disabled.
- The exact Task 2 targeted `xcodebuild test` command passes every `ARSessionPolicyTests` case on the named iPhone 17 simulator.
- `scripts/verify-phase-01-contracts quick` passes dependency audit, immutable fixture integrity, evidence schemas, JavaScript/Python parity surfaces, and the filtered Swift contract/coordinate suites.
- Plist lint, project/permission/orientation scans, unfinished-marker scans, audio/scene-reconstruction/network boundary scans, tracked high-confidence secret scanning, and `git diff --check` pass.
- SwiftPM and Xcode-generated local workspace/build state was removed; no generated project workspace or package build directory is retained.
- No signed physical-device, camera-sensor, ARKit-sensor, signing, installation, launch, thermal, human, GATE-013 GREEN, or GATE-002 GREEN evidence is claimed.

## User Setup Required

None - this plan uses Apple platform frameworks and the existing locked local contracts package; it adds no external dependency or service configuration.

## Next Phase Readiness

- Plan 01-12 can consume the injected AR session and `currentFrame` boundary for deterministic attempt/epoch and minimal FramePacket capture work.
- Plan 01-13 can harden the candidate release surface after the capture slice exists.
- Plan 01-14 must still produce real signed base-device evidence before D-05 promotion or OPS-DEVICE-001 physical acceptance; GATE-013 and GATE-002 remain pending.

## Self-Check: PASSED

- All seven declared project/source/test files exist, all three task commits are present, and the exact build/test commands passed without changing their specified scope.
- Required quick contract checks, metadata/boundary scans, tracked secret scanning, GSD consistency, and `git diff --check` pass.
- No source stub, physical evidence fabrication, audio capture path, LiDAR requirement, or generated local build/workspace artifact remains in the worktree.

---
*Phase: 01-contract-and-device-proof*
*Completed: 2026-07-17*
