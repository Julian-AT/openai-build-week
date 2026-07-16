# Sanitized gate evidence

`GateReportV1` and `OperatorChecklistV1` are the checked-in boundary for gate evidence. They represent the canonical states `UNRUN`, `RUNNING`, `GREEN`, `RED`, and `WAIVED_BY_HUMAN` without placing private raw evidence in Git.

## Processing order

Evidence producers must **sanitize first, then serialize**:

1. Collect raw logs, traces, screenshots, video, metrics, and ballots outside the repository under the approved retention controls.
2. Remove private identifiers and raw content before constructing either schema instance.
3. Replace each external artifact with an `opaque_artifact_id`, artifact kind, lowercase SHA-256, and `external_retention: true`.
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

## GREEN binding

The automated runner first emits its sanitized pass report and digest. A human reviews that report and the externally retained artifacts, then signs an `OperatorChecklistV1` whose `report_sha256` equals the automated report digest. The final `GateReportV1` records the same value in `automated_report_sha256` and the digest of the signed checklist in `operator_checklist_sha256`.

A verifier must recompute both digests and confirm the report/checklist gate IDs agree before accepting `GREEN`. Schema validation alone cannot compare two separate documents.

## Human waiver escalation

A timebox overrun, failed test, missing device, or automation request cannot create a waiver. Before `WAIVED_BY_HUMAN` validates:

1. A human explicitly changes the affected locked promise through the canonical escalation process in `docs/audit/OPEN_DECISIONS.md`.
2. `docs/canonical/PRD.md` is updated and its exact digest is recorded as `prd_sha256`.
3. Every affected ADR is updated; `affected_adr_sha256` is nonempty and binds each ADR ID to its updated digest.
4. A human completes the waiver checklist, including lock-change, PRD-update, ADR-update, and privacy-redaction checks, and signs it.
5. The gate report records the lock-change ID and signed checklist digest with `decision_actor: human`.

The waiver record documents a human authority change; it does not convert failed physical evidence into a pass. Canonical PRD and ADR updates must already exist before the evidence record is accepted.

## Fixtures

- `../fixtures/valid/` covers all five gate states plus signed GREEN and waiver checklists.
- `../fixtures/invalid/` covers automation approval/waiver, missing approval and escalation digests, private fields, embedded raw content, signing material, and private artifact paths.

Run:

```text
python3 -m unittest tools.verify.tests.test_evidence_templates -v
```
