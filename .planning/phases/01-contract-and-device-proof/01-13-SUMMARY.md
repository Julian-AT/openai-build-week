---
phase: 01-contract-and-device-proof
plan: "13"
subsystem: ios-diagnostics-and-release-safety
tags: [swiftui, swift-testing, xcuitest, evidence, privacy, release-surface]

requires:
  - phase: 01-contract-and-device-proof
    provides: Plans 01-02, 01-11, and 01-12 contract schemas, candidate app root, device state, and durable capture diagnostics
provides:
  - Compact Debug-only independent diagnostic checklist with stable accessibility identifiers
  - Closed allowlist, schema-validated, atomic sanitized gate-evidence export plus an independent host verifier
  - One-target Debug/Release UI proof and built-product inspection that excludes diagnostics and exporter code from Release
affects: [01-14, gate-013, gate-002, device-evidence, release-candidate]

tech-stack:
  added: []
  patterns: [sanitize-serialize-validate-publish, automation-never-self-approves, compile-time-debug-root, release-source-exclusion, same-product-binary-inspection]

key-files:
  created:
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/DiagnosticChecklistView.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/EvidenceExporter.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProofTests/EvidenceExporterTests.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProofUITests/DiagnosticSurfaceTests.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj/xcshareddata/xcschemes/ReRoomDeviceProof.xcscheme
    - tools/verify/verify_evidence.py
    - scripts/verify-reroom-release-surface
  modified:
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/App.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj/project.pbxproj

key-decisions:
  - "Automation may emit only UNRUN, RUNNING, or RED; GREEN and WAIVED_BY_HUMAN remain external signed human decisions."
  - "Evidence input is reconstructed from a closed allowlist, independently validated, and durably published only after validation; opaque artifact IDs and SHA-256 digests replace raw private evidence."
  - "The same app target selects its root at compile time, and Release additionally excludes diagnostic/exporter source files so identifiers, types, controls, and resources are absent from the built product."
  - "The Release inspector locates the same DerivedData product built by the shared scheme and never rebuilds or substitutes another app."

patterns-established:
  - "Sanitized evidence pipeline: reject unknown/private fields, reconstruct the exact GateReportV1 shape, canonicalize, independently validate, fsync a temporary file, rename, then fsync the directory."
  - "Independent facts: permission, orientation, tracking, planes, epoch/quarantine, packet, journal, signing/capability, and gate state retain separate rows and stable identifiers."
  - "Shipping-surface proof: XCUITest asserts configuration-specific roots while a separate binary/resource scanner rejects Debug/exporter markers in the same Release app."

requirements-completed: [OPS-DEVICE-001, NFR-CONTRACT-001, NFR-COORD-001]

coverage:
  - id: D1
    description: "The Debug diagnostic surface presents independent device/capture/gate facts and can export only deterministic, sanitized, schema-valid UNRUN, RUNNING, or RED evidence through an atomic validated write."
    requirement: NFR-CONTRACT-001
    verification:
      - kind: unit
        ref: "ReRoomDeviceProofTests/EvidenceExporterTests on the named iPhone 17 simulator"
        status: pass
      - kind: integration
        ref: "scripts/verify-phase-01-contracts evidence and quick"
        status: pass
    human_judgment: false
  - id: D2
    description: "The one application target launches the diagnostic root in Debug and the narrow CandidateSeedView in Release; diagnostic controls, exporter identifiers, types, and resources are absent from the inspected Release product."
    requirement: OPS-DEVICE-001
    verification:
      - kind: automated_ui
        ref: "ReRoomDeviceProofUITests/DiagnosticSurfaceTests in Debug and Release on the named iPhone 17 simulator"
        status: pass
      - kind: integration
        ref: "scripts/verify-reroom-release-surface against the Release XCUITest product"
        status: pass
    human_judgment: false
  - id: D3
    description: "D-05 promotion remains pending real signed base-iPhone installation, camera/ARKit behavior, capability, and operator evidence for GATE-013 and GATE-002."
    requirement: OPS-DEVICE-001
    verification:
      - kind: manual_procedural
        ref: "Plan 01-14 physical-device evidence and signed operator checklists"
        status: unknown
    human_judgment: true
    rationale: "Simulator UI tests and binary inspection cannot prove signing, installation, real camera/ARKit sensors, physical device capability, or a human gate decision."

duration: 27min
completed: 2026-07-17
status: complete
---

# Phase 01 Plan 13: Privacy-Safe Diagnostics and Release Surface Summary

**Debug now exposes an independent device/evidence checklist with fail-closed sanitized export, while the same app target's Release product contains only the narrow candidate root and no diagnostic or exporter surface.**

## Performance

- **Duration:** 27 min
- **Started:** 2026-07-17T01:11:26Z
- **Completed:** 2026-07-17T01:37:48Z
- **Tasks:** 2
- **Files modified:** 9

## Accomplishments

- Added the approved compact internal checklist with separate camera, optional microphone, physical orientation, ARKit tracking, horizontal/vertical plane, epoch/quarantine, packet durability, journal visibility, build/signing/capability, and canonical gate-state rows. Stable accessibility identifiers cover the root, each fact, microphone action, and evidence export.
- Added a closed evidence request boundary that rejects private/unknown fields, unknown capability values, LiDAR requirements, human-only gate states, and unbound evidence before serialization or filesystem mutation. Valid automation evidence is deterministic, independently shape-validated, bounded, and atomically published.
- Added a bounded host-side Draft 2020-12 verifier with duplicate-key and privacy scanning across valid/invalid fixtures plus explicit report/checklist binding checks.
- Added a real UI-test target and shared scheme. Debug and Release XCUITests launch the actual configuration products, and a separate scanner verifies the same Release app contains required candidate markers but no diagnostic/exporter identifiers, types, controls, schemas, or resources.
- Kept one application target and made exclusion structural: `App.swift` selects the configuration root at compile time, while Release source settings omit `DiagnosticChecklistView.swift` and `EvidenceExporter.swift` entirely.

## Task Commits

Each behavior-bearing task followed an explicit RED then GREEN commit:

1. **Task 1 RED: Sanitized evidence boundaries** - `edb88ba` (test)
2. **Task 1 GREEN: Diagnostic checklist and sanitized evidence export** - `8628087` (feat)
3. **Task 2 RED: Debug/Release built-product UI boundary** - `c6ff089` (test)
4. **Task 2 GREEN: Compile-time root and Release exclusion proof** - `b2bf175` (feat)

**Plan metadata:** recorded by the closeout commit containing this summary.

## Files Created/Modified

- `ios/ReRoomDeviceProof/ReRoomDeviceProof/DiagnosticChecklistView.swift` - Approved internal checklist, independent facts, exact failure/recovery copy, stable identifiers, and disabled-until-valid export action.
- `ios/ReRoomDeviceProof/ReRoomDeviceProof/EvidenceExporter.swift` - Allowlisted evidence types, automation-state and binding rules, deterministic canonical data, independent GateReportV1 validation, and atomic durable export.
- `ios/ReRoomDeviceProof/ReRoomDeviceProofTests/EvidenceExporterTests.swift` - Private-field, state, capability, binding, schema, deterministic serialization, atomic publication, and checklist-order tests.
- `tools/verify/verify_evidence.py` - Independent bounded schema, duplicate-key, privacy, fixture, automation-state, and report/checklist binding verification.
- `ios/ReRoomDeviceProof/ReRoomDeviceProofUITests/DiagnosticSurfaceTests.swift` - Configuration-specific actual-product root and identifier assertions.
- `ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj/xcshareddata/xcschemes/ReRoomDeviceProof.xcscheme` - Shared app, unit-test, and UI-test membership for command-line Debug/Release execution.
- `ios/ReRoomDeviceProof/ReRoomDeviceProof/App.swift` - Explicit compile-time Debug diagnostic root and Release-local CandidateSeedView root.
- `ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj/project.pbxproj` - UI-test target/dependency/configuration plus Release source exclusion.
- `scripts/verify-reroom-release-surface` - Same-product one-target, binary-string, accessibility-marker, and resource inspection.

## Decisions Made

- Preserved the canonical gate authority split: automation may prepare only UNRUN, RUNNING, or RED reports and cannot sign, approve GREEN, or author a waiver.
- Reconstructed the exact export object from a closed typed allowlist instead of filtering an arbitrary payload. This makes unknown and private inputs fail before serialization and keeps raw room bytes, logs, identifiers, account/team data, paths, and signing material outside the report.
- Kept the Python verifier independent of the Swift exporter architecture. It validates checked-in schemas, duplicate keys, privacy patterns, automation states, and cross-file digest binding rather than trusting exporter implementation details.
- Used both conditional root selection and Release source exclusion. Conditional UI alone would hide controls while retaining diagnostic/exporter code and strings; exclusion makes their absence testable in the shipping product.
- Followed the approved UI specification's compact system typography, color roles, 44-point controls, scrolling layout, independent status rows, reason/recovery copy, and accessibility identifiers.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Prevented unrelated unit-test sources from invalidating Release-only XCUITest execution**

- **Found during:** Task 2 GREEN Release verification
- **Issue:** Xcode prepares every scheme testable even with `-only-testing` scoped to the UI target. Existing unit sources use `@testable import`, while the true Release app intentionally remains built without `-enable-testing`; this blocked the required Release UI invocation before its selected test could run.
- **Fix:** Kept unit and UI targets in the shared scheme for selectable execution, kept the app Release module non-testable, removed redundant test targets from `BuildActionEntries`, and excluded all unit-test source files only in the unit target's Release configuration. Debug unit tests remain present and pass; the Release UI test builds and launches the genuine Release app.
- **Files modified:** `ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj/project.pbxproj`, `ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj/xcshareddata/xcschemes/ReRoomDeviceProof.xcscheme`
- **Verification:** The exact targeted exporter command passes in Debug; the exact targeted UI command passes in both Debug and Release.
- **Committed in:** `b2bf175`

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** The adjustment preserves the intended Release compilation and exact scheme membership without runtime branching, assertion weakening, dependency changes, or product scope expansion.

## Issues Encountered

- The first UI-test RED attempt hit a transient CoreSimulator preflight `Busy` launch failure. Rebooting the named simulator allowed the unchanged test to run and fail on the intended root/identifier assertions; no product workaround or weaker assertion was introduced.
- The first Release attempt exposed the expected `@testable`/non-testable module conflict from unrelated scheme testables. Configuration-specific test-source exclusion resolved the build graph while preserving an ordinary non-testable Release app.

## Verification Evidence

- The final targeted `EvidenceExporterTests` command passes 18 Swift Testing cases on the named iPhone 17 simulator, followed by `evidence verification: PASS` for all checked-in fixtures.
- `scripts/verify-phase-01-contracts evidence` passes 15 positive/negative gate-report and operator-checklist schema tests plus the independent verifier.
- `scripts/verify-phase-01-contracts quick` passes dependency audit, immutable fixture integrity, evidence schemas, JavaScript/Python runners, and Swift contract/coordinate suites.
- The exact combined Debug XCUITest, Release XCUITest, and `scripts/verify-reroom-release-surface` command passes. The inspector resolves the same Release DerivedData app, confirms one app target and candidate markers, and rejects every diagnostic/exporter marker or resource.
- The deterministic UI safety gate finds the approved `01-UI-SPEC.md` and reports `block: false`; project plist lint, scheme XML lint, tracked high-confidence secret scanning, and `git diff --check` pass.
- Generated SwiftPM `.build` and Xcode `project.xcworkspace` state was removed; the worktree is clean before summary creation.
- No signed physical-device, camera/ARKit sensor, signing, installation, thermal, human, GATE-013 GREEN, or GATE-002 GREEN evidence is claimed.

## User Setup Required

None - no dependency, credential, external service, or cloud configuration was added.

## Next Phase Readiness

- Plan 01-14 can run the full automated preflight against the now-inspectable Release product and use the evidence verifier to bind automated output to external signed operator reports.
- Real base-iPhone signing, installation, camera/ARKit behavior, capability capture, and human checklists remain mandatory before D-05 promotion; GATE-013 and GATE-002 remain pending.
- Release contains only the narrow candidate device-proof surface; guaranteed B0 work and broader product implementation remain outside this plan.

## Self-Check: PASSED

- All declared files exist, all four RED/GREEN commits are present, and each targeted acceptance command passes under the final shared scheme.
- Evidence serialization rejects private fields, unknown capabilities/states, self-approval, and unbound RED reports; invalid data cannot create or replace the destination.
- The Release app retains required candidate markers while diagnostic/exporter types, controls, accessibility IDs, schema names, and resources are absent.
- Required evidence/quick checks, UI safety gate, project/scheme syntax checks, secret scan, and `git diff --check` pass; no generated local workspace/build artifact remains.
- Physical gate evidence remains explicitly pending and unclaimed.

---
*Phase: 01-contract-and-device-proof*
*Completed: 2026-07-17*
