---
phase: 02-atomic-capture-and-exact-replay
plan: "06"
subsystem: native-capture-boundary
tags: [swiftui, arkit, swift-concurrency, bounded-admission, replay]

requires:
  - phase: 02-atomic-capture-and-exact-replay
    plan: "02"
    provides: Consent-bound atomic capture archive durability and recovery
  - phase: 02-atomic-capture-and-exact-replay
    plan: "03"
    provides: Verified replay reports, recovery discovery, and stable-ID timelines
  - phase: 02-atomic-capture-and-exact-replay
    plan: "04"
    provides: Synchronous bounded admission, pressure policy, and reserved user-event lane
provides:
  - Native ARFrame and lifecycle adapter with exact per-frame image, calibration, and pose plus one bounded consumer
  - Explicit consent and truthful independent local, upload, share, recovery, and failure presentation state
  - Hash-verified replay inspector exposing only accepted stable-ID journal timelines
affects: [02-07-capture-evidence, native-mode-a, mode-b0-replay]

tech-stack:
  added: []
  patterns:
    - Synchronous callback admission plus one session-owned sequential consumer
    - Immutable verified presentation snapshots at the MainActor boundary
    - Fail-closed embedded dependency resource resolution on iOS

key-files:
  created:
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/CaptureSessionAdapter.swift
  modified:
    - ios/Packages/ReRoomContracts/Package.swift
    - ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/CaptureArchiveStore.swift
    - ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/FramePacketEncoder.swift
    - ios/Packages/ReRoomContracts/Sources/ReRoomContracts/FrozenSchemaValidator.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj/project.pbxproj
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/DeviceProofModel.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/DiagnosticChecklistView.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProofTests/CaptureSessionAdapterTests.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProofUITests/DiagnosticSurfaceTests.swift
    - scripts/verify-reroom-release-surface

key-decisions:
  - "Accept a per-frame encoding profile so each durable packet's image, intrinsics, projection, and pose originate from the same ARFrame callback."
  - "Expose recovery candidates only as either immutable verified snapshots or sanitized failure snapshots; rejected records never enter the inspector."
  - "When iOS static linking prevents the dependency's public bundle lookup, locate its embedded pinned resource bundle and run the same draft-2020-12 meta-schema validation fail closed."

patterns-established:
  - "Native callback boundary: convert one ARFrame coherently, select purely, offer synchronously, and perform no callback-created task or await."
  - "Verified presentation boundary: views receive accepted report and timeline snapshots rather than archive bytes or partially validated records."
  - "Truthful state separation: local durability, upload, sharing, recovery, close reason, and admission pressure remain independent user-visible facts."

requirements-completed: [SEC-CONSENT-001, FR-CAPTURE-001, FR-B0-001, NFR-REPLAY-001]

coverage:
  - id: D1
    description: "Explicit disclosure acceptance alone creates a fresh local-only capture session; denial creates no archive writer or bytes."
    requirement: SEC-CONSENT-001
    verification:
      - kind: integration
        ref: "xcodebuild focused CaptureSessionAdapterTests on iPhone 17 simulator"
        status: pass
      - kind: e2e
        ref: "xcodebuild DiagnosticSurfaceTests on iPhone 17 simulator"
        status: pass
    human_judgment: false
  - id: D2
    description: "ARFrame callbacks preserve one-frame calibration and pose, perform exactly one synchronous bounded offer, and feed one sequential archive consumer with explicit stop, expiration, cancellation, and storage-failure cleanup."
    requirement: FR-CAPTURE-001
    verification:
      - kind: integration
        ref: "xcodebuild focused CaptureSessionAdapterTests on iPhone 17 simulator"
        status: pass
      - kind: other
        ref: "AR callback/task/network source scans"
        status: pass
    human_judgment: false
  - id: D3
    description: "The diagnostic surface independently presents Recording locally, upload/offline, sharing, busy pressure, stop, recovery, and sanitized failure state with stable accessibility identifiers."
    requirement: SEC-CONSENT-001
    verification:
      - kind: e2e
        ref: "xcodebuild DiagnosticSurfaceTests on iPhone 17 simulator"
        status: pass
      - kind: other
        ref: "scripts/verify-reroom-release-surface against the tested Release app"
        status: pass
    human_judgment: false
  - id: D4
    description: "Recovery discovery and the replay inspector expose only accepted ReplayReportV1 snapshots with verified archive identity, finalization status, digests, and stable-ID authoritative journal order."
    requirement: FR-B0-001
    verification:
      - kind: integration
        ref: "xcodebuild focused CaptureSessionAdapterTests on iPhone 17 simulator"
        status: pass
      - kind: unit
        ref: "swift test --package-path ios/Packages/ReRoomContracts"
        status: pass
    human_judgment: false
  - id: D5
    description: "The complete Debug app suite and independently scanned Release product preserve exact replay behavior while excluding internal capture diagnostics from the protected release surface."
    requirement: NFR-REPLAY-001
    verification:
      - kind: integration
        ref: "xcodebuild complete ReRoomDeviceProof Debug test suite on iPhone 17 simulator"
        status: pass
      - kind: integration
        ref: "xcodebuild Release DiagnosticSurfaceTests plus release-surface scan"
        status: pass
    human_judgment: false

duration: 1h35m
completed: 2026-07-18
status: complete
---

# Phase 02 Plan 06: Native Capture Boundary Summary

**The native seed now converts coherent ARFrames into bounded consent-authorized durable capture, reports lifecycle and pressure truthfully, discovers interrupted archives without resuming them, and exposes only hash-verified replay timelines.**

## Performance

- **Duration:** 1h35m
- **Started:** 2026-07-18T00:21:21Z
- **Completed:** 2026-07-18T01:56:21Z
- **Tasks:** 2
- **Files modified:** 11

## Accomplishments

- Added a MainActor native capture adapter that creates no storage before disclosure acceptance, converts each ARFrame coherently, performs one synchronous bounded admission offer, and owns exactly one session consumer that serializes durable writes.
- Implemented explicit stop, background drain, expiration/cancellation abort, storage-failure recovery, and next-launch discovery so only the verified durable prefix survives and no prior archive is ever resumed.
- Added immutable presentation snapshots and an accessible internal SwiftUI surface that keeps local recording, upload/offline, sharing, busy pressure, close reason, recovery, and integrity states visibly independent.
- Added a verified replay inspector whose archive verdict, finalization status, digest summary, selection, and stable-ID timeline derive only from accepted authoritative journal records.
- Preserved the protected Release root and strengthened its scanner so capture diagnostic identifiers and source remain structurally excluded from the tested Release application.

## Task Commits

Each planned behavior task was implemented through a RED/GREEN pair, followed by two verification-driven Release isolation fixes:

1. **Task 1: Bridge ARFrame, app lifecycle, pressure, and recovery to the capture actor**
   - c429f7c — test(02-06): define native capture adapter behavior (RED)
   - 20ced35 — feat(02-06): bridge bounded native capture sessions (GREEN)
2. **Task 2: Present explicit consent, local/upload state, recovery, and verified replay**
   - bbf9e9d — test(02-06): define truthful capture diagnostics (RED)
   - 3d7a1d2 — feat(02-06): present truthful capture and replay state (GREEN)
   - e32caca — fix(02-06): exclude capture diagnostics from release
   - 4556f15 — fix(02-06): preserve release test isolation

**Plan summary:** recorded by the following documentation-only commit.

## Files Created/Modified

- ios/ReRoomDeviceProof/ReRoomDeviceProof/CaptureSessionAdapter.swift - Consent/session owner, coherent ARFrame conversion, synchronous bounded admission, one consumer/writer, lifecycle close, recovery discovery, and verified inspector snapshots.
- ios/ReRoomDeviceProof/ReRoomDeviceProof/DeviceProofModel.swift - MainActor immutable capture/recovery/replay presentation state and diagnostic actions.
- ios/ReRoomDeviceProof/ReRoomDeviceProof/DiagnosticChecklistView.swift - Explicit disclosure, truthful state rows, bounded busy coaching, recovery cards, and verified stable-ID replay inspector.
- ios/ReRoomDeviceProof/ReRoomDeviceProofTests/CaptureSessionAdapterTests.swift - Consent, callback, capacity, reserved lane, lifecycle, failure, recovery, inspector, and presentation regression coverage.
- ios/ReRoomDeviceProof/ReRoomDeviceProofUITests/DiagnosticSurfaceTests.swift - Accessible disclosure, capture state, busy, stop, recovery, and inspector journey coverage.
- ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/FramePacketEncoder.swift - Per-call encoding profile for exact same-frame pose/calibration authority.
- ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/CaptureArchiveStore.swift - Per-frame profile propagation into the atomic archive writer.
- ios/Packages/ReRoomContracts/Sources/ReRoomContracts/FrozenSchemaValidator.swift - Fail-closed lookup of the embedded pinned draft meta-schema bundle under iOS static linking.
- ios/Packages/ReRoomContracts/Package.swift - Explicit ReRoomCaptureCore library product for the native Xcode target.
- ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj/project.pbxproj - Native product/source/test integration and Release structural diagnostic exclusions.
- scripts/verify-reroom-release-surface - Capture-diagnostic release identifier rejection.

## Decisions Made

- FramePacket encoding accepts a per-call profile because the image, timestamp, intrinsics, projection, and camera pose are an inseparable same-ARFrame authority unit. A session-static profile could silently pair fresh imagery with stale pose.
- Capture recovery discovery has a closed presentation boundary: accepted candidates become immutable verified report snapshots, while rejected candidates become sanitized failures that expose no archive record or timeline item.
- The iOS fallback does not bypass schema integrity or meta-schema validation. It finds the dependency's embedded, pinned swift-json-schema resource bundle and feeds those official draft 2020-12 resources through the same public JSONSchema validation APIs.

## Deviations from Plan

### Auto-fixed Correctness Gaps

**1. The existing encoder profile was session-static rather than frame-coherent**

- **Found during:** Task 1 GREEN
- **Issue:** The native callback could supply current image/calibration data while the encoder retained a stale initialization-time camera pose, violating the exact per-ARFrame authority invariant.
- **Fix:** Added a per-call FramePacketEncodingProfile seam through the encoder and archive store; all packet inputs now originate from the admitted ARFrame snapshot.
- **Files modified:** FramePacketEncoder.swift, CaptureArchiveStore.swift
- **Verification:** Same-frame pose/calibration adapter tests and the full package/app suites pass.
- **Committed in:** 20ced35

**2. Recovery discovery silently discarded rejected candidates**

- **Found during:** Task 2 GREEN
- **Issue:** The plan requires launch discovery to return failure snapshots, but the initial core result exposed only accepted archives.
- **Fix:** Added a typed discovery snapshot containing immutable verified archives and sanitized failures, while retaining the accepted-only convenience API for compatibility.
- **Files modified:** CaptureSessionAdapter.swift, DeviceProofModel.swift, CaptureSessionAdapterTests.swift
- **Verification:** Invalid candidates surface a precise failure without exposing records or enabling inspection.
- **Committed in:** 3d7a1d2

**3. Pinned meta-schema resources were invisible through the dependency's public bundle accessor in the iOS static-link host**

- **Found during:** Task 2 focused iOS verification
- **Issue:** Clean simulator builds contained the official resource bundle, but swift-json-schema's macOS-oriented public lookup returned MetaSchemaError.missingResource under the iOS host and caused every live archive validation to fail closed.
- **Fix:** Locate the embedded pinned swift-json-schema_JSONSchema bundle from host/app bundles and perform the same full draft 2020-12 meta-schema and vocabulary validation with the dependency's public APIs.
- **Files modified:** FrozenSchemaValidator.swift
- **Verification:** Clean iOS focused/full suites and macOS package Debug/Release schema corpus pass; canonical schema resource hashes remain exact.
- **Committed in:** 3d7a1d2

### Auto-fixed Build and Release Integration

**4. The native Xcode target needed an explicit package product**

- **Found during:** Task 1 RED integration
- **Issue:** ReRoomCaptureCore was a package target only and could not be linked as a named Xcode package product.
- **Fix:** Declared the existing target as a library product without changing dependencies or versions.
- **Files modified:** Package.swift, project.pbxproj
- **Verification:** The focused and complete native app suites link and pass.
- **Committed in:** c429f7c, 20ced35

**5. New diagnostics needed both identifier isolation and Release test-source isolation**

- **Found during:** Release verification
- **Issue:** A capture diagnostic identifier initially lived in an app source compiled for Release, and the new unit source was not yet in the Release unit target's structural exclusion list.
- **Fix:** Moved the identifier into the diagnostic-only source, strengthened the release scanner, and added the new test source to Release exclusions.
- **Files modified:** CaptureSessionAdapter.swift, DiagnosticChecklistView.swift, project.pbxproj, verify-reroom-release-surface
- **Verification:** Release UI test and scan pass against the same built app; diagnostic.capture.* is absent.
- **Committed in:** e32caca, 4556f15

---

**Total deviations:** 5 auto-fixed (3 correctness, 2 build/release integration)
**Impact on plan:** All changes close required native-boundary or verification gaps without expanding product scope, changing dependencies, or weakening fail-closed validation.

## Issues Encountered

- Simulator diagnostics and Xcode crash-report writes exhausted local disk space during repeated clean verification. Only generated DerivedData, module, package build, and test-log caches were removed; simulators were cleanly shut down, and no source, user data, signing state, or canonical evidence was removed.
- A destructive-role button in a popover confirmation surface did not render the disclosure's non-capture choice on the simulator. The disclosure uses an explicit roleless Keep Capture Off action plus a separate Cancel action so denial remains visible and testable without changing meaning.
- GSD health remains degraded only by the pre-existing non-repairable W004 warning for the user-modified model_profile: adaptive; planning consistency passes and the unrelated configuration was preserved.

## Verification Evidence

- Focused Task 1 and Task 2 simulator commands pass with 9 CaptureSessionAdapter tests and 1 DiagnosticSurface UI test on iPhone 17.
- The complete Debug ReRoomDeviceProof suite passes 60 logical tests and 98 parameterized cases with zero failures, including the UI journey.
- Existing CaptureAttemptTests pass 21 logical tests and 36 parameterized cases, preserving prior native boundary behavior.
- The Release DiagnosticSurface test passes against the same app inspected by scripts/verify-reroom-release-surface; diagnostic capture identifiers are absent from the protected root.
- swift test --package-path ios/Packages/ReRoomContracts passes 96 tests across 14 suites.
- Source scans confirm no Task or await in the AR callback, exactly one stored Task creation in the adapter, no Task.detached, no live provider/network wait, no raw/private diagnostic output, and no deprecated/custom interaction patterns in the new SwiftUI surface.
- Canonical schema resource hashes, tracked-file secret scan, git diff --check, GSD consistency, and planning health diagnostics pass except for the preserved W004 configuration warning.

## User Setup Required

None - no dependency, credential, endpoint, signing, deployment, cloud resource, or private evidence is required.

## Next Phase Readiness

- Plan 02-07 can run fail-closed Phase 2 verification against the now-complete host replay, native capture, recovery, truthful UI, and protected Release boundaries.
- Simulator and contract automation are green. Physical-device, human, signing, ARKit/compositor, thermal, and the three-minute NFR-REPLAY-001 measurement remain pending until real evidence is collected; this plan makes no claim that those gates passed.

## Self-Check: PASSED

- All six task/fix commits exist, the native adapter exists, and all eleven declared production/test artifacts are present.
- Focused, full Debug, Release isolation, package, source-scan, secret, consistency, and whitespace checks passed after the final implementation.
- Pre-existing config, Xcode scheme, .swiftpm, workspace, and user-data changes remain outside plan commits; regenerated package build output was removed after verification.

---
*Phase: 02-atomic-capture-and-exact-replay*
*Completed: 2026-07-18*
