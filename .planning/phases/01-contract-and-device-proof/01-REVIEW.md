---
phase: 01-contract-and-device-proof
reviewed: 2026-07-17T12:41:07Z
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
  warning: 2
  info: 0
  total: 3
status: issues_found
---

# Phase 01: Code Review Report

**Reviewed:** 2026-07-17T12:41:07Z
**Depth:** standard
**Files Reviewed:** 79
**Status:** issues_found

## Summary

One critical evidence-integrity defect and two warnings were proved at standard depth. The explicit world-reset path correctly resets the AR session, advances the epoch, clears tracked state, quarantines incompatible versions, updates the diagnostic surface, and disables capture; the checked-in physical evidence also contains no observed private room media or user identifiers. However, the signed operator decision does not cryptographically bind the final physical gate report, so the current verifier can accept post-approval changes to load-bearing report metadata. The capture test suite also exhibited a reproducible intermittent concurrency failure, and the capture state machine can retain a stale selection after a rejected re-selection.

## Critical Issues

### CR-01 — BLOCKER: signed operator decision does not bind the final physical gate report

**File:** `tools/verify/verify_evidence.py:156`

The verifier checks that `operator_checklist.report_sha256` equals the report's `automated_report_sha256`, then checks that `report.operator_checklist_sha256` equals the digest of the checklist bytes. In both checked-in physical checklists, `report_sha256` is therefore the digest of `automated-preflight.json`, not a digest of the GATE-002 or GATE-013 physical report. This creates only a final-report-to-checklist link: the signed/checklisted decision does not bind the final report bytes. After approval, an actor can change schema-valid, load-bearing fields such as `implementation_revision`, fixture or device metadata, or artifact IDs and digests while retaining the signed checklist and GREEN decision; the current verifier still accepts the evidence. That defeats the report-bound evidence requirement and leaves critical spoofing/repudiation threat T-01-19 unresolved.

**Fix:** Define a non-circular digest for the final GateReport payload—for example, canonicalize the report with `operator_checklist_sha256` omitted—and include that digest in the signed checklist or human attestation. Recompute and verify it in `verify_evidence.py`, then continue to bind the exact checklist bytes from the report. Also verify that the external attestation/signature artifact is scoped to those exact checklist bytes and matches the artifact referenced by the report. Add mutation tests that change final-report fixture, environment, implementation revision, and artifact digest fields after signing and require verification to fail.

## Warnings

### WR-01 — shared schema validator makes the capture suite intermittently fail under concurrent execution

**File:** `ios/ReRoomDeviceProof/ReRoomDeviceProofTests/CaptureAttemptTests.swift:8`

`CaptureAttemptTests` is not serialized, while all parameterized cases share the static `ContractValidator` declared at line 747. A full Debug simulator run failed the `.gap` case in `manifestMutationsReject(mutation:)`: `journal.recover()` unexpectedly threw `.invalidManifest` before the mutation under test. The same complete unit target passed immediately on rerun. The package-level contract validation suite is explicitly serialized, which further indicates that concurrent use of the compiled validator is not established as safe. This makes verification nondeterministic and may expose an unjustified `Sendable` assumption in production validation.

**Fix:** Make `CaptureAttemptTests` serialized or instantiate an isolated validator per test. Separately, either serialize access within the production `ContractValidator` or establish the wrapped compiled schema validator's concurrency safety with a stress test before relying on its `Sendable` conformance.

### WR-02 — a rejected orientation re-selection leaves the prior capture selected

**File:** `ios/ReRoomDeviceProof/ReRoomDeviceProof/CaptureAttemptMachine.swift:55`

`select` returns an orientation rejection without clearing `selectedAttempt`; the quarantine and unhealthy-state branches do clear it. A caller can select a valid portrait attempt, attempt a second landscape selection that is rejected, then call `finish` with values matching the first attempt and receive `.ready`. The current UI constructs a fresh machine for each capture flow, which limits present exposure, but the state machine itself violates re-selection semantics and can authorize a stale attempt if it is reused.

**Fix:** Clear `selectedAttempt` at the start of every `select` operation, or at minimum before returning the orientation rejection. Add a regression test for valid selection → rejected re-selection → finish, requiring `.noSelection`.

## Informational

None.

## Verification

- `scripts/verify-phase-01-contracts gate` — passed; both evidence verification passes completed and GATE-013/GATE-002 were reported GREEN.
- `.venv/bin/python -m unittest tools.verify.tests.test_compare_results tools.verify.tests.test_evidence_templates tools.verify.tests.test_reference_parity tools.python.tests.test_parity_mutations tools.python.tests.test_runner -v` — passed, 33 tests.
- `node --test tools/javascript/test/runner.test.mjs tools/javascript/test/parity-mutations.test.mjs` — passed, 5 tests.
- `swift test --package-path ios/Packages/ReRoomContracts` — passed, 32 tests across 5 suites.
- Full Debug simulator `xcodebuild test` — the UI target passed, but the unit target failed once in the `.gap` capture mutation case with unexpected `.invalidManifest`; the complete unit target passed on immediate rerun. This is the evidence for WR-01, not a clean full-suite result.
- `git diff --check` — passed before writing this report; the report itself was checked again after writing.
- The GATE-002 and GATE-013 physical outcomes were treated as human-attested evidence supplied by the operator. This review did not fabricate physical observations or inspect private external room artifacts.

---

_Reviewed: 2026-07-17T12:41:07Z_
_Reviewer: Codex (generic-agent fallback following gsd-code-reviewer contract)_
_Depth: standard_
