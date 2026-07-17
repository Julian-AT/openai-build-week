---
phase: 01-contract-and-device-proof
reviewed: 2026-07-17T02:10:31Z
depth: standard
files_reviewed: 75
files_reviewed_list:
  - docs/canonical/RESEARCH_LEDGER.md
  - evidence/compatibility/contract-agreement.json
  - evidence/compatibility/coordinate-agreement.json
  - evidence/compatibility/jcs-agreement.json
  - evidence/compatibility/swift-schema-validation.json
  - evidence/dependencies/phase-01-package-audit.json
  - evidence/fixtures/invalid/gate-report.invalid.automation-waiver.json
  - evidence/fixtures/valid/gate-report.green.json
  - evidence/templates/README.md
  - evidence/templates/gate-report.schema.json
  - evidence/templates/operator-checklist.schema.json
  - fixtures/contracts/1.0.0/rev-001/manifest.json
  - fixtures/manifest.schema.json
  - fixtures/policies/RR-COORD-1/rev-001/manifest.json
  - fixtures/policies/RR-JCS-SHA256-1/rev-001/manifest.json
  - fixtures/runner-result.schema.json
  - ios/Packages/ReRoomContracts/Package.resolved
  - ios/Packages/ReRoomContracts/Package.swift
  - ios/Packages/ReRoomContracts/Sources/ReRoomContractRunner/main.swift
  - ios/Packages/ReRoomContracts/Sources/ReRoomContracts/ArchivePath.swift
  - ios/Packages/ReRoomContracts/Sources/ReRoomContracts/CanonicalJSON.swift
  - ios/Packages/ReRoomContracts/Sources/ReRoomContracts/ContractValidation.swift
  - ios/Packages/ReRoomContracts/Sources/ReRoomContracts/CoordinateMath.swift
  - ios/Packages/ReRoomContracts/Sources/ReRoomContracts/FrozenSchemaValidator.swift
  - ios/Packages/ReRoomContracts/Sources/ReRoomContracts/WireFrame.swift
  - ios/Packages/ReRoomContracts/Tests/ReRoomContractsTests/CanonicalJSONTests.swift
  - ios/Packages/ReRoomContracts/Tests/ReRoomContractsTests/ContractValidationTests.swift
  - ios/Packages/ReRoomContracts/Tests/ReRoomContractsTests/CoordinateMathTests.swift
  - ios/Packages/ReRoomContracts/Tests/ReRoomContractsTests/RunnerTests.swift
  - ios/Packages/ReRoomContracts/Tests/ReRoomContractsTests/WireFrameTests.swift
  - ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj/project.pbxproj
  - ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj/xcshareddata/xcschemes/ReRoomDeviceProof.xcscheme
  - ios/ReRoomDeviceProof/ReRoomDeviceProof/ARSessionController.swift
  - ios/ReRoomDeviceProof/ReRoomDeviceProof/App.swift
  - ios/ReRoomDeviceProof/ReRoomDeviceProof/CaptureAttemptMachine.swift
  - ios/ReRoomDeviceProof/ReRoomDeviceProof/DeviceProofModel.swift
  - ios/ReRoomDeviceProof/ReRoomDeviceProof/DiagnosticChecklistView.swift
  - ios/ReRoomDeviceProof/ReRoomDeviceProof/DiagnosticJournal.swift
  - ios/ReRoomDeviceProof/ReRoomDeviceProof/EvidenceExporter.swift
  - ios/ReRoomDeviceProof/ReRoomDeviceProof/FramePacketBuilder.swift
  - ios/ReRoomDeviceProof/ReRoomDeviceProof/Info.plist
  - ios/ReRoomDeviceProof/ReRoomDeviceProof/OrientationGate.swift
  - ios/ReRoomDeviceProof/ReRoomDeviceProof/PermissionController.swift
  - ios/ReRoomDeviceProof/ReRoomDeviceProof/WorldEpochController.swift
  - ios/ReRoomDeviceProof/ReRoomDeviceProofTests/ARSessionPolicyTests.swift
  - ios/ReRoomDeviceProof/ReRoomDeviceProofTests/CaptureAttemptTests.swift
  - ios/ReRoomDeviceProof/ReRoomDeviceProofTests/EvidenceExporterTests.swift
  - ios/ReRoomDeviceProof/ReRoomDeviceProofTests/WorldEpochTests.swift
  - ios/ReRoomDeviceProof/ReRoomDeviceProofUITests/DiagnosticSurfaceTests.swift
  - tools/javascript/package-lock.json
  - tools/javascript/src/canonical-json.mjs
  - tools/javascript/src/coordinate.mjs
  - tools/javascript/src/loader.mjs
  - tools/javascript/src/runner.mjs
  - tools/javascript/src/schema-validator.mjs
  - tools/javascript/src/wire-frame.mjs
  - tools/javascript/test/parity-mutations.test.mjs
  - tools/javascript/test/runner.test.mjs
  - tools/python/requirements.in
  - tools/python/requirements.lock
  - tools/python/reroom_verify/__init__.py
  - tools/python/reroom_verify/canonical_json.py
  - tools/python/reroom_verify/coordinate.py
  - tools/python/reroom_verify/loader.py
  - tools/python/reroom_verify/runner.py
  - tools/python/reroom_verify/schema_validator.py
  - tools/python/reroom_verify/wire_frame.py
  - tools/python/tests/test_parity_mutations.py
  - tools/python/tests/test_runner.py
  - tools/verify/compare_results.py
  - tools/verify/tests/test_compare_results.py
  - tools/verify/tests/test_evidence_templates.py
  - tools/verify/tests/test_reference_parity.py
  - tools/verify/verify_evidence.py
  - tools/verify/verify_phase_01_dependencies.py
findings:
  critical: 2
  warning: 6
  info: 0
  total: 8
status: issues_found
---

# Phase 01: Code Review Report

**Reviewed:** 2026-07-17T02:10:31Z
**Depth:** standard
**Files Reviewed:** 75
**Status:** issues_found

## Summary

The reviewed contract kernels and checked-in test suites pass, but the phase is not safe to promote. The capture journal can destroy an already-durable prefix, room capture has no consent authority while its manifest asserts consent, and several recovery, device-proof, and cross-runtime validation paths are either disconnected or fail open.

## Critical Issues

### CR-01: Reused stable IDs overwrite immutable journal history

**File:** `ios/ReRoomDeviceProof/ReRoomDeviceProof/DiagnosticJournal.swift:290-306,482-510`

**Issue:** `capture` checks that the four event IDs are unique only within the incoming frame. It never rejects an event ID or frame ID already present in the durable prefix. `persistEventRecord` then writes with overwrite semantics to `events/<event_id>.json` before appending the new journal entry. Reusing an earlier event ID replaces the bytes bound by an existing journal digest; the next recovery reads the replacement for the old entry, rejects at sequence zero, and loses the entire otherwise-durable prefix. On the concrete filesystem, reusing a frame ID is also destructive: the selected event is overwritten and journaled before the later directory rename fails because the destination frame already exists.

**Fix:** Before any write, reject frame, event, and idempotency collisions against the validated durable prefix and existing filesystem. Create immutable event/packet files without overwrite semantics, and add two-capture regression tests that reuse each ID family and verify the first recovered prefix remains byte-for-byte valid.

### CR-02: Capture bypasses consent and fabricates a positive consent record

**File:** `ios/ReRoomDeviceProof/ReRoomDeviceProof/DiagnosticJournal.swift:216-225,290-321,757-763`

**Issue:** `DiagnosticCaptureConfiguration` and `capture` have no explicit consent input or authorization check, yet every recovered manifest hard-codes `capture_consent_recorded` to `true`. Any caller can persist room imagery without recording a consent decision, and the resulting evidence falsely claims the SEC-CONSENT-001 prerequisite was satisfied. Camera permission is not capture consent.

**Fix:** Make a validated, session-bound consent record mandatory before `capture` accepts bytes; bind its identity/digest and retention decision into configuration/manifest generation. Represent denial explicitly, keep non-capture explanation usable, and add tests proving capture rejects before consent and the manifest value is derived rather than defaulted.

## Warnings

### WR-01: Torn-tail recovery leaves the archive permanently unwritable

**File:** `ios/ReRoomDeviceProof/ReRoomDeviceProof/DiagnosticJournal.swift:303-306,347-359,406-428,530-568`

**Issue:** The injected journal crash deliberately leaves a partial line. `recover` correctly projects the contiguous valid prefix, but it neither truncates nor atomically replaces the invalid tail. Every later `capture` sees `hasInvalidTail` and rejects forever, so the advertised crash recovery cannot resume capture in the same archive.

**Fix:** After validating a recovered prefix, durably truncate/replace the journal at the final valid byte boundary (or write each entry through an atomic append protocol), fsync it, and test `crash -> recover -> capture -> recover`.

### WR-02: The shipped Debug diagnostics show synthetic facts and can never export

**File:** `ios/ReRoomDeviceProof/ReRoomDeviceProof/App.swift:11-17`; `ios/ReRoomDeviceProof/ReRoomDeviceProof/DiagnosticChecklistView.swift:55-64,216-219,251-255,287-319`

**Issue:** The app constructs `DiagnosticChecklistView` without an `EvidenceExportRequest`, so export readiness is always `.notReady` and the only export button is permanently disabled. The checklist also defaults the world epoch to `Version 1 — usable` and supplies fixed packet/journal/build facts rather than reading `WorldEpochController`, `DiagnosticJournal`, or capture recovery. No production source constructs an evidence request or either capture authority. The UI test checks only that the disabled control exists, so it passes while the feature is unusable and the epoch row can assert readiness that was never measured.

**Fix:** Introduce one app-level diagnostic owner that supplies live epoch/capture/journal facts and a validated evidence request, subscribe the Debug view to orientation changes, and extend UI tests to require real readiness transitions plus a successful sanitized export.

### WR-03: FramePacket metadata can label arbitrary bytes as physically upright

**File:** `ios/ReRoomDeviceProof/ReRoomDeviceProof/FramePacketBuilder.swift:35-56,76-109,149-183,206-245`

**Issue:** The builder accepts caller-provided bytes, dimensions, crop, transform, and encoded intrinsics independently, then unconditionally emits `orientation: "up"`. It never derives them from one `ARFrame`, applies `displayTransform`, rotates/encodes the bytes, or verifies that the supplied intrinsics and `encoded_from_sensor` describe those exact bytes. The only scoped test payload is the non-image string `test`, so schema validity is being mistaken for the normative physically-upright atomic binding.

**Fix:** Build the input from one captured `ARFrame`/orientation/viewport snapshot, physically encode upright bytes, derive `encoded_from_sensor` and encoded intrinsics from that snapshot, and add checkerboard/image-dimension tests plus a negative mismatched-transform case.

### WR-04: AR interruption/failure does not revoke the running session or capture authorization

**File:** `ios/ReRoomDeviceProof/ReRoomDeviceProof/ARSessionController.swift:69-82,127-134`; `ios/ReRoomDeviceProof/ReRoomDeviceProof/OrientationGate.swift:39-53`; `ios/ReRoomDeviceProof/ReRoomDeviceProof/CaptureAttemptMachine.swift:55-84`

**Issue:** AR failure and interruption emit only `tracking(.unavailable)` and leave `ARSessionController.isRunning` true, so `synchronize` refuses to restart. Independently, `OrientationGate.evaluate` explicitly discards `sessionIsRunning`, allowing `finish` to return `.ready` after the session stopped during an attempt. The result is a stale session owner and a capture authorization that does not guarantee a healthy current frame.

**Fix:** Transition running state to false on terminal failure/interruption, expose an explicit recovery/restart action, and require a running session plus the same healthy atomic frame snapshot at attempt completion. Add failure/interruption and mid-attempt-stop tests.

### WR-05: RR-COORD-1 validation differs across the three runtimes outside the happy-path oracle

**File:** `tools/python/reroom_verify/coordinate.py:14-15,62-76,163-168`; `tools/javascript/src/coordinate.mjs:51-67,132-147`; `ios/Packages/ReRoomContracts/Sources/ReRoomContracts/CoordinateMath.swift:152-183,202-211`

**Issue:** Python applies `1e-6` to rotation orthogonality and determinant even though RR-FLOAT-1 requires Frobenius/determinant tolerance `1e-4`; a transform with a `1.00002` axis is within the canonical bounds but Python rejects it. For ARKit-to-OpenCV conversion, Swift validates a rigid 3x3 matrix, Python checks only determinant, and JavaScript performs no matrix validation, so both reference runners accept a determinant-one shear that Swift rejects. The frozen corpus has no tolerance-neighbor or malformed-conversion cases, allowing agreement reports to remain green despite policy divergence.

**Fix:** Implement the exact RR-FLOAT-1 Frobenius, determinant, and homogeneous-row rules in Python; apply the same rigid 3x3 validation to OpenCV conversion in all runtimes; freeze boundary-neighbor, shear, reflection, and nonorthonormal cases and add them to each mutation gate.

### WR-06: Python accepts compatibility migrations with wrong versions and no source document

**File:** `tools/python/reroom_verify/schema_validator.py:133-155`

**Issue:** The Python runner accepts any descriptor whose migration name and `representable` flag match, without checking `reader_version`, `source_version`, `source`, or validating the source contract. A mutated descriptor with reader `9.9.9`, source version `9.8.7`, and no source file is reported as accepted, while Swift and JavaScript reject it. This is a fail-open compatibility boundary hidden by the single valid oracle case.

**Fix:** Match the closed Swift/JavaScript predicate exactly, require and bounded-read the source path, validate it as CON-001, and add mutations for every missing/wrong descriptor field and an invalid source instance.

---

_Reviewed: 2026-07-17T02:10:31Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
