---
phase: 01-contract-and-device-proof
reviewed: 2026-07-17T13:49:56Z
depth: standard
files_reviewed: 79
files_reviewed_list:
  - docs/canonical/RESEARCH_LEDGER.md
  - evidence/compatibility/contract-agreement.json
  - evidence/compatibility/coordinate-agreement.json
  - evidence/compatibility/jcs-agreement.json
  - evidence/compatibility/swift-schema-validation.json
  - evidence/dependencies/phase-01-package-audit.json
  - evidence/device/phase-01/automated-preflight.json
  - evidence/device/phase-01/gate-002-operator-checklist.json
  - evidence/device/phase-01/gate-002-report.json
  - evidence/device/phase-01/gate-013-operator-checklist.json
  - evidence/device/phase-01/gate-013-report.json
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
  critical: 1
  warning: 0
  info: 0
  total: 1
status: issues_found
---

# Phase 01: Code Review Report

**Reviewed:** 2026-07-17T13:49:56Z
**Depth:** standard
**Files Reviewed:** 79
**Status:** issues_found

## Summary

The previous CR-01, WR-01, and WR-02 findings are fixed: the final V2 report decision, unsigned checklist, external operator-attestation digest, and exact checklist bytes form an acyclic verified chain; shared compiled-schema access is serialized; and a rejected capture re-selection clears the prior selection. Both final physical report/checklist pairs verify as GREEN, and the Swift package plus repeated simulator capture tests passed.

One new blocker remains. The breaking GateReportV2 migration was not synchronized to the diagnostic app's machine-readable evidence exporter. The app still emits and self-validates GateReportV1, which the current canonical evidence schema explicitly rejects.

## Critical Issues

### CR-01 — BLOCKER: the on-device evidence exporter still emits rejected GateReportV1

**File:** `ios/ReRoomDeviceProof/ReRoomDeviceProof/EvidenceExporter.swift:199`

`evidence/templates/README.md` declares GateReportV2 the checked-in boundary and explicitly says V1 reports are rejected. The current Swift exporter nevertheless serializes `schema_version: "1.0.0"`, omits the V2-required `artifact_role` from every external artifact, and validates the result with a private `GateReportV1Validator`. `EvidenceExporterTests` pass because they exercise only that stale local validator and never validate emitted bytes against the checked-in canonical schema. A representative V1 automated preflight produces two validation errors against the current schema, beginning with `2.0.0 was expected`; therefore a diagnostic export produced by the promoted device-proof seed cannot be consumed by the current evidence verifier.

This breaks the D-07 machine-readable evidence-export deliverable and violates the repository's rule that a contract change synchronize its schema, producers, fixtures, and tests. It is especially load-bearing here because the V2 change is the evidence-integrity correction used to close the physical gates, while the candidate revision named by those reports still contains this V1 producer.

**Fix:** Migrate `EvidenceExporter` and its independent validator to GateReportV2 for the automation-owned UNRUN/RUNNING/RED states, emitting `artifact_role: supporting_evidence` and rejecting operator-attestation roles. Update `EvidenceExporterTests` to assert the V2 version/role fields and cross-validate actual Swift-emitted bytes against `evidence/templates/gate-report.schema.json` so another local-schema drift cannot pass. Preserve the existing signed physical evidence as evidence for its named revision; do not rewrite its implementation revision without a newly bound candidate/evidence decision.

## Warnings

None.

## Informational

None.

## Verification

- `scripts/verify-phase-01-contracts gate` — passed; both V2 evidence pairs verified and reported `GATE-013=GREEN,GATE-002=GREEN`.
- `.venv/bin/python -m unittest tools.verify.tests.test_evidence_templates -v` — passed, 22 tests including report/checklist mutation rejection.
- `swift test --package-path ios/Packages/ReRoomContracts` — passed, 33 tests across 5 suites; the shared-validator concurrency stress test completed 1,024 accepted validations.
- Full Debug simulator `xcodebuild test ... -only-testing:ReRoomDeviceProofTests` on iPhone 17 / iOS 26.4 — passed, including the complete capture, evidence-export, AR policy, world-epoch, and release-smoke unit target.
- A second focused simulator `CaptureAttemptTests` run passed, including repeated manifest mutations and `rejectedReselectionClearsStaleAttempt`.
- Historical V1 automated-preflight bytes validated against the current V2 schema — rejected with two errors, proving the same version/role mismatch present in `EvidenceExporter.swift`.
- Frozen review scope validation — exactly 79 declared, unique, existing files; no files were added or removed from the scope.
- `git diff --check` — passed before writing this report and was rerun after writing.
- The GATE-002 and GATE-013 physical observations were treated only as human-attested evidence. This review did not inspect private external raw artifacts under `/tmp` or fabricate physical evidence.

---

_Reviewed: 2026-07-17T13:49:56Z_
_Reviewer: Codex (generic-agent fallback following gsd-code-reviewer contract)_
_Depth: standard_
