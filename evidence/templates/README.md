# Sanitized gate evidence

`GateReportV2` and `OperatorChecklistV2` are the checked-in boundary for gate evidence. They represent the canonical states `UNRUN`, `RUNNING`, `GREEN`, `RED`, and `WAIVED_BY_HUMAN` without placing private raw evidence in Git.

Version 2 is a breaking evidence-binding correction. A V1 checklist does not bind the final human gate-decision payload and must not be upgraded by copying its old signature digest. V1 reports/checklists are rejected; a human decision needs a fresh V2 attestation after the V2 report and unsigned-checklist payload digests are frozen.

## Processing order

Evidence producers must **sanitize first, then serialize**:

1. Collect raw logs, traces, screenshots, video, metrics, and ballots outside the repository under the approved retention controls.
2. Remove private identifiers and raw content before constructing either schema instance.
3. Replace each external artifact with an `opaque_artifact_id`, artifact kind, artifact role, lowercase SHA-256, and `external_retention: true`. Ordinary evidence uses `supporting_evidence`; exactly one human signature/attestation ballot uses `operator_attestation`.
4. Validate the closed schema before serialization. Unknown fields, states, actors, malformed digests, or missing state-specific evidence fail closed.
5. Serialize the validated sanitized record and compute any binding digest over the exact declared artifact bytes.

Raw room bytes, raw logs, screenshots, video, traces, ballots, signing material, device UUIDs, team IDs, accounts, user names, and filesystem paths must never be copied into these records or committed. Git retains only sanitized facts and opaque external references. The external evidence store owns access, retention, and deletion; an opaque ID is not a path, URL, account identifier, or embedded payload.

## Gate state and actor rules

- Automation may emit only `UNRUN`, `RUNNING`, or `RED`.
- `UNRUN` contains no artifact or approval digest. It is never green by assumption.
- `RUNNING` may accumulate opaque references but is not an approval.
- `RED` preserves exact failure evidence through at least one opaque artifact and an `automated_report_sha256`. Under D-16, dependent mobile work stops; only independent contract or B0 work may continue.
- `GREEN` requires a human decision actor, a `MEASURED` record, the passing automated report digest, and the signed operator-checklist digest.
- `WAIVED_BY_HUMAN` is represented for canonical completeness but cannot be emitted by ordinary automation.

`TARGET` labels a planned threshold, never an observed result. `MEASURED` is allowed only when the immutable fixture, implementation revision, environment, raw external evidence, metric calculation, and evaluator are bound by the record. Producers must not relabel a target as measured merely because a run completed.

## Human-decision binding

Human approval uses two acyclic payload scopes and two final attachments:

1. `RR-GATE-DECISION-SHA256-1` is lowercase SHA-256 over compact, UTF-8, key-sorted JSON for the final `GateReportV2` after omitting `operator_checklist_sha256` and every artifact whose `artifact_role` is `operator_attestation`. All gate-decision content—including state, actor, implementation revision, tests, requirements, ADRs, fixtures, environment, value classification, supporting evidence, automated report digest, and waiver fields—remains in scope.
2. The checklist records that value in `report_decision_sha256` and independently records the automated runner digest in `automated_report_sha256`.
3. `RR-GATE-CHECKLIST-SHA256-1` is lowercase SHA-256 over the same compact, UTF-8, key-sorted JSON encoding of `OperatorChecklistV2` after omitting `unsigned_checklist_sha256` and `signature_sha256`. The checklist records the result in `unsigned_checklist_sha256` and declares `signature_scope: RR-GATE-CHECKLIST-SHA256-1`.
4. The human externally signs or attests to that exact unsigned-checklist digest. `signature_sha256` is the lowercase SHA-256 of the externally retained signature/attestation bytes. The report must reference exactly one `ballot` with `artifact_role: operator_attestation` and the same artifact digest. The attestation artifact is omitted from step 1 to avoid a signature/report cycle.
5. After attaching the signature fields, `operator_checklist_sha256` is lowercase SHA-256 over the exact checked-in checklist file bytes, including formatting and trailing newline.

The verifier recomputes every local payload digest, confirms both gate identities and decisions agree, matches the external attestation digest to the report ballot, and finally checks the exact checklist-file digest. Changing a fixture, implementation revision, environment fact, supporting artifact, checklist item, or timestamp after attestation fails verification.

## Human waiver escalation

A timebox overrun, failed test, missing device, or automation request cannot create a waiver. Before `WAIVED_BY_HUMAN` validates:

1. A human explicitly changes the affected locked promise through the canonical escalation process in `docs/audit/OPEN_DECISIONS.md`.
2. `docs/canonical/PRD.md` is updated and its exact digest is recorded as `prd_sha256`.
3. Every affected ADR is updated; `affected_adr_sha256` is nonempty and binds each ADR ID to its updated digest.
4. A human completes the V2 waiver checklist, including lock-change, PRD-update, ADR-update, and privacy-redaction checks, and signs its `RR-GATE-CHECKLIST-SHA256-1` payload.
5. The gate report records the lock-change ID and signed checklist digest with `decision_actor: human`.

The waiver record documents a human authority change; it does not convert failed physical evidence into a pass. Canonical PRD and ADR updates must already exist before the evidence record is accepted.

## Fixtures

- `../fixtures/valid/` covers all five gate states plus signed GREEN and waiver checklists.
- `../fixtures/invalid/` covers automation approval/waiver, missing approval and escalation digests, private fields, embedded raw content, signing material, and private artifact paths.

Run:

```text
python3 -m unittest tools.verify.tests.test_evidence_templates -v
```
