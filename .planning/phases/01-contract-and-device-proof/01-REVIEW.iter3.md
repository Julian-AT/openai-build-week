---
phase: 01-contract-and-device-proof
reviewed: 2026-07-17T03:19:49Z
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
  critical: 0
  warning: 3
  info: 0
  total: 3
status: issues_found
---

# Phase 01: Code Review Report

**Reviewed:** 2026-07-17T03:19:49Z
**Depth:** standard
**Files Reviewed:** 75
**Status:** issues_found

## Summary

Five of the eight findings from the previous review are fully fixed: stable-ID collision handling, capture consent authority, physically upright FramePacket construction, AR interruption/failure recovery, and Python compatibility-migration validation. The checked-in Swift, JavaScript, Python, verifier, and simulator unit suites pass. Three warning-level edge cases remain in journal repair, live Debug evidence facts, and cross-runtime coordinate validation; the existing tests do not cover them.

## Critical Issues

None.

## Warnings

### WR-01: Torn-tail repair still fails at both journal boundaries

**File:** `ios/ReRoomDeviceProof/ReRoomDeviceProof/DiagnosticJournal.swift:661-697,743-780`

**Issue:** The new repair path handles an invalid tail only when at least one entry survives. If the first append tears (for example, the journal contains only `{`), `durablePrefix` reports an invalid tail with zero entries and `repairedDurablePrefixIfNeeded` throws instead of atomically replacing the journal with the valid empty prefix. The scanner also treats a complete JSON record without its required trailing newline as healthy. A later append then concatenates the next JSON object onto it, and recovery loses the prefix. A direct scanner reproduction returned `(1, false)` for a complete record without newline, then `(0, true)` after the next append; a partial first record returned `(0, true)`. The existing regression injects a torn tail only after a valid selected event, so neither boundary is covered.

**Fix:** Track whether the durable bytes end in `0x0A`; canonically rewrite a complete-but-undelimited record, and atomically replace any invalid tail with its valid prefix even when that prefix is empty. Add concrete- and memory-filesystem regressions for a torn first append and for a complete record missing only the final newline.

### WR-02: Normal Debug launches still cannot produce schema-valid live evidence facts

**File:** `ios/ReRoomDeviceProof/ReRoomDeviceProof/DiagnosticChecklistView.swift:222-235,623-629`; `ios/ReRoomDeviceProof/ReRoomDeviceProofUITests/DiagnosticSurfaceTests.swift:8-10`; `ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj/xcshareddata/xcschemes/ReRoomDeviceProof.xcscheme:53-72`

**Issue:** `DiagnosticRuntimeFacts.live()` falls back to empty strings for the implementation revision and fixture digest when process environment variables are absent, while the gate schema requires a `git:`-prefixed 40-hex revision and the frozen fixture reference requires 64 hex characters. It also supplies `UIDevice.current.model` as the device model; on an iPhone that value is `iPhone`, which does not satisfy the evidence schema's `^iPhone .+` constraint. Validation therefore disables export on a normal shared-scheme Debug launch. The UI test injects the two environment values, masking the production launch path; neither the shared scheme nor the Debug build settings supplies them.

**Fix:** Embed a build-provenanced Git revision and frozen fixture digest through build settings/Info.plist (or another deterministic bundle source), and either obtain a schema-valid hardware model or omit the optional value. Add coverage for `live(environment: [:])` and the unmodified shared LaunchAction.

### WR-03: Coordinate preconditions still disagree across Swift, JavaScript, and Python

**File:** `tools/javascript/src/coordinate.mjs:97-124`; `tools/python/reroom_verify/coordinate.py:181-194`; `ios/Packages/ReRoomContracts/Sources/ReRoomContracts/CoordinateMath.swift:91-97,119-131`

**Issue:** JavaScript `transformIntrinsics` does not reject nonpositive sensor focal lengths and checks the homogeneous row after multiplying the transform by the intrinsic matrix, whereas Swift and Python validate the input transform itself. Consequently a transform whose homogeneous component is `5e-7` is accepted under Swift/Python's `1e-6` tolerance but rejected by JavaScript after multiplication by focal length 1000. Separately, Python `project` accepts negative focal lengths that Swift and JavaScript reject. Direct reproductions confirmed both disagreements, and the new frozen boundary vector does not exercise these operations.

**Fix:** Validate positive focal lengths in every operation, make JavaScript validate the homogeneous row on the input transform, and make Python `project` reject nonpositive focal lengths. Freeze both cases in the shared runtime-boundary fixture and assert identical outcomes in all three runtimes.

## Verification

- `swift test --package-path ios/Packages/ReRoomContracts` — passed, 32 tests across 5 suites.
- `node --test tools/javascript/test/runner.test.mjs tools/javascript/test/parity-mutations.test.mjs` — passed, 5 tests.
- `.venv/bin/python -m unittest tools.python.tests.test_runner tools.python.tests.test_parity_mutations tools.verify.tests.test_compare_results tools.verify.tests.test_evidence_templates tools.verify.tests.test_reference_parity` — passed, 33 tests.
- `xcodebuild test -project ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj -scheme ReRoomDeviceProof -configuration Debug -destination 'platform=iOS Simulator,id=77FC48DD-7DD0-4AC9-85D3-C3231BC8176F' -only-testing:ReRoomDeviceProofTests CODE_SIGNING_ALLOWED=NO` — passed.
- Physical-device, human-observation, and room-evidence gates remain pending; this review does not fabricate or promote them.

---

_Reviewed: 2026-07-17T03:19:49Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
