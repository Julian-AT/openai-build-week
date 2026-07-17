---
phase: 01-contract-and-device-proof
review: 01-REVIEW.md
fixed_at: 2026-07-17T14:22:57Z
iteration: 2
status: all_fixed
findings_in_scope: 4
fixed: 4
skipped: 0
resolved_findings:
  - id: CR-01
    severity: critical
    title: bind human approval to the final gate decision
    commits: [e87d81c, 26cb685]
  - id: WR-01
    severity: warning
    title: serialize shared compiled-schema validation
    commits: [69764a4]
  - id: WR-02
    severity: warning
    title: clear stale capture selection before every reselection
    commits: [2ada97c]
  - id: CR-01-ITERATION-2
    severity: critical
    title: migrate the on-device evidence exporter to the canonical V2 boundary
    commits: [2a02253, a5bff68]
verification:
  evidence_suite:
    result: pass
    tests: 22
  evidence_pairs: pass
  phase_gate: pass
  swift_package:
    result: pass
    tests: 33
    suites: 5
  ios_capture_attempt_suite: pass
  ios_complete_unit_target: pass
  ios_evidence_exporter_suite:
    result: pass
    tests: 14
  swift_output_against_canonical_gate_report_v2: pass
  diff_check: pass
final_convergence:
  iteration: 2
  status: clean
  reviewed_at: 2026-07-17T14:28:49Z
  reviewed_files: 79
  findings:
    critical: 0
    warning: 0
    info: 0
    total: 0
---

# Phase 01 Code Review Fix Report

All four findings found across two standard-depth reviews of the frozen 79-file scope were fixed and verified. No finding was skipped.

## CR-01 — Final gate decision binding

`GateReportV2` and `OperatorChecklistV2` now form a non-circular approval chain:

1. The checklist binds the exact automated preflight digest.
2. `report_decision_sha256` binds every load-bearing final report field except the post-decision checklist digest and operator-attestation attachment.
3. `unsigned_checklist_sha256` binds the canonical checklist payload before its own digest and external ballot digest are attached.
4. The externally retained human ballot digest must match exactly one report artifact with role `operator_attestation`.
5. The final report binds the exact checked-in checklist bytes.

Mutation tests require changes to the implementation revision, fixture, environment, supporting artifact, checklist payload, or ballot digest to fail verification. The previous general physical attestation remains supporting evidence only. A fresh human response approved the four frozen GATE-013/GATE-002 report and checklist digests; its normalized external ballot is retained outside Git and referenced only by opaque ID and SHA-256. Both final report/checklist pairs independently verify and `scripts/verify-phase-01-contracts gate` reports both gates GREEN.

## WR-01 — Shared validator concurrency

Each compiled `FrozenSchemaValidator` is now owned by a `SerializedSchemaValidator` that locks every top-level validation. The wrapped validator does not escape the boundary. A concurrent shared-validator stress test passes, as do all 33 Swift package tests across five suites.

## WR-02 — Rejected reselection

`CaptureAttemptMachine.select` clears its prior selection before evaluating every new selection. The regression covers valid selection → rejected landscape reselection → finish and requires `.noSelection`. The focused iPhone 17 simulator `CaptureAttemptTests` run passes, including this regression and the journal/capture matrix.

## CR-01, Iteration 2 — Canonical V2 producer migration

The fresh re-review found that the diagnostic app still emitted and locally validated GateReportV1 after the repository boundary moved to V2. The exporter now emits only automation-owned V2 `UNRUN`, `RUNNING`, and `RED` reports; every emitted external artifact has role `supporting_evidence`, and automation rejects `operator_attestation` before serialization.

The frozen schema engine now supports the standard Draft 2020-12 `maxContains` keyword and exposes a narrow `JSONSchemaDocumentValidator` façade for independent document-schema checks. Simulator tests load the checked-in `gate-report.schema.json` and verify actual Swift-emitted bytes for all three automation states. Missing-role and operator-attestation mutations fail closed, preventing the app's local validator from silently drifting from the canonical schema again. The signed physical reports remain unchanged and continue to identify the installed candidate revision they actually measured.

## Fix Commits

- `e87d81c` — V2 evidence schemas, semantic verifier, fixtures, and mutation coverage.
- `69764a4` — serialized production schema-validation boundary and concurrency coverage.
- `2ada97c` — stale-selection state-machine fix and regression test.
- `26cb685` — fresh digest-scoped human ballot bindings and final GREEN evidence.
- `2a02253` — RED assertions proving the stale V1 exporter mismatch.
- `a5bff68` — GateReportV2 exporter, canonical-schema façade, and cross-validation coverage.

## Verification Evidence

- `python3 -m unittest tools.verify.tests.test_evidence_templates` — 22 passed.
- `./scripts/verify-phase-01-contracts evidence` — evidence corpus and semantic checks passed.
- Independent `verify_evidence.py` runs for GATE-013 and GATE-002 — passed.
- `./scripts/verify-phase-01-contracts gate` — `GATE-013=GREEN,GATE-002=GREEN`.
- `swift test --package-path ios/Packages/ReRoomContracts` — 33 tests passed across five suites, including shared-validator concurrency.
- Focused Debug iPhone 17 simulator `CaptureAttemptTests` — succeeded, including the rejected-reselection regression.
- Complete Debug iPhone 17 simulator unit target — succeeded after the V2 exporter migration.
- `EvidenceExporterTests` — 14 tests passed, including actual Swift bytes against the checked-in GateReportV2 schema, missing-role rejection, and operator-attestation rejection.
- `git diff --check` — passed.

The final independent re-review of the unchanged 79-file scope is clean with zero findings; its full result is recorded separately in `01-REVIEW.md`.
