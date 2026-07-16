---
phase: 01-contract-and-device-proof
plan: "02"
subsystem: testing
tags: [json-schema, evidence, privacy, gate-lifecycle, human-approval]

requires: []
provides:
  - Closed GateReportV1 and OperatorChecklistV1 evidence envelopes
  - Human-only GREEN and WAIVED_BY_HUMAN approval constraints
  - Sanitized valid/invalid gate evidence fixture corpus
affects: [01-03, 01-04, 01-14, device-proof, release-gates]

tech-stack:
  added: []
  patterns: [sanitize-first serialize-second, opaque external evidence references, report-bound signed checklists]

key-files:
  created:
    - evidence/templates/gate-report.schema.json
    - evidence/templates/operator-checklist.schema.json
    - evidence/templates/README.md
    - evidence/fixtures/valid/gate-report.green.json
    - evidence/fixtures/invalid/gate-report.invalid.automation-waiver.json
  modified:
    - tools/verify/tests/test_evidence_templates.py

key-decisions:
  - "Ordinary automation can emit only UNRUN, RUNNING, or RED; GREEN and WAIVED_BY_HUMAN require a human decision actor and signed checklist digest."
  - "Checked-in evidence stores sanitized facts plus opaque external artifact IDs and digests; paths, raw room content, accounts, device UUIDs, and signing material are unrepresentable."
  - "A waiver validates only after an explicit lock-change ID, updated PRD digest, nonempty affected ADR digest list, and signed human waiver checklist are present."

patterns-established:
  - "GREEN binds a passing automated report digest to a signed human checklist; cross-document digest equality is verified outside JSON Schema."
  - "RED preserves exact failure evidence and follows D-16 routing without turning a failed physical gate into a pass."

requirements-completed: [NFR-CONTRACT-001, OPS-DEVICE-001]

coverage:
  - id: D1
    description: "Closed canonical gate and operator-checklist schemas enforce all five states, approval digests, and human-only waiver authority."
    requirement: NFR-CONTRACT-001
    verification:
      - kind: unit
        ref: "python3 -m unittest tools.verify.tests.test_evidence_templates -v"
        status: pass
    human_judgment: false
  - id: D2
    description: "Sanitized fixtures and handling guidance reject private fields, raw content, malformed evidence, and automation approval or waiver."
    requirement: OPS-DEVICE-001
    verification:
      - kind: unit
        ref: "tools/verify/tests/test_evidence_templates.py#CheckedInEvidenceFixtureTests"
        status: pass
    human_judgment: false

duration: 10min
completed: 2026-07-16
status: complete
---

# Phase 01 Plan 02: Sanitized Gate Evidence Summary

**Closed JSON Schema evidence records with opaque external-artifact references, report-bound human approval, and explicit lock/PRD/ADR waiver escalation**

## Performance

- **Duration:** 10 min
- **Started:** 2026-07-16T11:15:17Z
- **Completed:** 2026-07-16T11:25:12Z
- **Tasks:** 2
- **Files modified:** 24

## Accomplishments

- Defined `GateReportV1` across `UNRUN`, `RUNNING`, `GREEN`, `RED`, and `WAIVED_BY_HUMAN`, with automation restricted to the three non-approval states.
- Defined a report-bound signed `OperatorChecklistV1` for GREEN approval and explicit human waiver escalation.
- Added seven valid and thirteen invalid checked-in fixtures covering canonical lifecycle, private-data rejection, missing approval evidence, and automation waiver rejection.
- Documented sanitize-first/serialize-second handling, external raw-evidence retention, TARGET versus MEASURED labels, D-16 RED routing, and human waiver updates.

## Task Commits

Each task was committed atomically; Task 1 followed the required TDD RED/GREEN sequence:

1. **Task 1 RED: Pin fail-closed gate evidence rules** - `3a32179` (test)
2. **Task 1 GREEN: Define canonical gate evidence schemas** - `b598936` (feat)
3. **Task 2: Add redaction fixtures and evidence handling contract** - `84a1b3f` (feat)

## Files Created/Modified

- `evidence/templates/gate-report.schema.json` - Closed sanitized gate report with state-specific approval and waiver constraints.
- `evidence/templates/operator-checklist.schema.json` - Human-only signed checklist bound to a reviewed report digest.
- `evidence/templates/README.md` - Evidence sanitization, retention, GREEN, RED, and waiver handling contract.
- `evidence/fixtures/valid/` - Canonical state and signed-checklist examples.
- `evidence/fixtures/invalid/` - Private-field, malformed-approval, and automation-waiver rejection examples.
- `tools/verify/tests/test_evidence_templates.py` - Schema behavior and checked-in fixture validation.

## Decisions Made

- The automated report digest is the checklist's `report_sha256`; the final gate record stores that digest plus the signed checklist digest, avoiding a circular full-document digest.
- Human identity and signing material are not recorded. Only the digest of the externally signed checklist crosses the repository boundary.
- Physical evidence was not run or fabricated in this plan; the schemas and fixtures only define how later real evidence must be represented.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Accepted the complete canonical fixture-ID family**
- **Found during:** Task 2 (valid fixture validation)
- **Issue:** The initial fixture-ID pattern accepted `FX-COORD-001` but rejected canonical multi-segment IDs such as `FX-RRCAP-010S` and `FX-HERO-ROOM-001`.
- **Fix:** Expanded the closed `FX-` pattern to accept one or more uppercase alphanumeric segments while retaining the registered prefix and rejecting paths or arbitrary characters.
- **Files modified:** `evidence/templates/gate-report.schema.json`
- **Verification:** All seven valid fixtures pass and all thirteen invalid fixtures fail under the unit suite.
- **Committed in:** `84a1b3f`

---

**Total deviations:** 1 auto-fixed (1 Rule 1 bug).
**Impact on plan:** The correction was necessary to represent canonical fixture IDs and did not expand product scope.

## Issues Encountered

None beyond the auto-fixed canonical fixture-ID pattern above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- The fail-closed comparator and later physical gate workflows can consume the closed evidence templates and fixtures.
- Physical-device, signing, and human approval evidence remains pending until the real Plan 01-14 procedures run.
- GSD consistency passes; health retains the pre-existing non-repairable `adaptive` model-profile warning and expected notices for not-yet-executed plans.

## Self-Check: PASSED

- All declared key files exist.
- Task commits `3a32179`, `b598936`, and `84a1b3f` exist in history.
- The 15-test evidence suite passes and GSD summary verification reports no errors.

---
*Phase: 01-contract-and-device-proof*
*Completed: 2026-07-16*
