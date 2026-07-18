---
phase: 03-typed-place-commit-and-offline-restore
plan: "07"
subsystem: transaction-preflight
tags: [swift, typescript, python, exact-agreement, xctest, evidence, pending-gates]

requires:
  - phase: 03-typed-place-commit-and-offline-restore
    plan: "06"
    provides: independent provenance-bound Swift, TypeScript, and Python transaction traces
provides:
  - closed bounded normalized transaction result schema and independent immutable-oracle comparator
  - one quick/full fail-closed Phase 3 verification entry point with two isolated runs per runtime
  - sanitized revision-bound automated sprint-slice evidence with all deferred gates explicitly pending
affects: [phase-04, phase-08, transaction-evidence, demo-sprint]

tech-stack:
  added: []
  patterns:
    - validate every raw result against a pinned closed schema before normalization
    - require independent fixture-derived and pinned semantic oracles even when all runtimes agree
    - publish evidence atomically only after one complete full verification inventory passes

key-files:
  created:
    - tools/verify/transaction-trace-result.schema.json
    - tools/verify/compare_transaction_traces.py
    - tools/verify/tests/test_phase_03_transactions.py
    - scripts/verify-phase-03-transactions
    - evidence/transactions/phase-03/automated-preflight.json
  modified: []

key-decisions:
  - "Treat exact cross-runtime equality as necessary but insufficient: every semantic family must also match the independent immutable fixture or pinned deterministic oracle."
  - "Bind producer source to one recorded commit and require exact Node v22.22.3, Python 3.13.12, runtime identities, fixture digests, result schema, and source-tree digests."
  - "Describe only an automated sprint slice as passed; GATE-009, GATE-010, GATE-011, physical, reconnect, proxy/license, and full-P0 evidence remain PENDING."

requirements-completed: [FR-PLACE-001, FR-RESTORE-001, FR-TRANSACTION-001, FR-AGENT-001]

duration: 22min
completed: 2026-07-18
status: complete
---

# Phase 3 Plan 7: Exact Transaction Agreement and Honest Preflight Summary

**A single quick/full command now proves byte-repeatable Swift/TypeScript/Python transaction agreement, native model/UI and Release integrity, and publishes only a sanitized automated sprint-slice result with every deferred gate still `PENDING`.**

## Performance

- **Duration:** 22 min
- **Started:** 2026-07-18T17:43:02+02:00
- **Completed:** 2026-07-18T18:04:26+02:00
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments

- Added a Draft 2020-12 closed, bounded result schema and comparator that validates canonical raw bytes before normalization, requires exactly Swift/TypeScript/Python, and checks one complete ordered 24-case corpus against independent fixture and pinned semantic oracles.
- Killed schema, provenance, source, runtime, case, proposal, blocker, operation-order, injection, projection, fingerprint, revision, receipt, retry, restore, divergence, and trace mutations—including the equal-wrong-output case across all three runtimes.
- Added `scripts/verify-phase-03-transactions quick|full`: exact Node v22.22.3, focused Swift/Node/Python tests, two isolated publications per runtime, byte identity, exact parity, native model/UI, Debug/Release, release-surface, tracked-secret, and whitespace checks.
- Published a self-digested, source-bound 13-check report after the full run passed. It contains hashes, counts, stable command/check IDs, revisions, and outcomes only; no raw room/user text, machine paths, device IDs, credentials, or fabricated observations.
- Preserved the approved sprint-cut truth: deterministic automation passed, while complete resilience/adversarial campaigns and physical, reconnect, proxy/license, human, and full-P0 evidence remain pending.

## Task Commits

Each behavior-bearing task began with failing tests before implementation:

1. **Task 1 RED: closed schema and independent-oracle mutation gates** - `85b54b3` (test)
2. **Task 1 GREEN: strict exact transaction comparator** - `b778a84` (feat)
3. **Task 2 RED: orchestration, evidence, privacy, and atomic-publication gates** - `53551f8` (test)
4. **Task 2 GREEN: quick/full transaction preflight** - `b00c393` (feat)
5. **Task 2 hardening: clean sequential XCUITest simulator boundary** - `8b21f89`, `d0d0358` (fix)
6. **Task 2 evidence: passing automated sprint preflight** - `2600d64` (evidence)

## Decisions Made

- Keep the checked-in expected trace immutable and require fixture-file hashes before any runtime comparison; no producer output defines another producer's expected semantics.
- Require one caller-supplied lowercase `git:<40-hex>` producer revision bound to the unchanged producer source scopes at `10de1b6bde8e447143f61cb2833618b86486a6a9`.
- Keep quick mode publication-free. Only a complete full check inventory may create or atomically replace `automated-preflight.json`.
- Record user worktree state as counts only and never stage, clean, or name user signing/configuration/build artifacts in evidence.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Isolated sequential Xcode test sessions from CoreSimulator Busy state**
- **Found during:** Task 2 full verification
- **Issue:** The model test passed, but the immediately following UI runner was denied by CoreSimulator preflight as Busy. The same UI journey passed independently after a clean simulator boot.
- **Fix:** Resolve exactly one available iPhone 17 target, accept only Booted or Shutdown state, establish a clean boot boundary, and wait for terminal boot readiness before the UI session.
- **Verification:** The unchanged UI journey and subsequent complete full verifier passed.
- **Committed in:** `8b21f89`, `d0d0358`

---

**Total deviations:** 1 auto-fixed verification-infrastructure blocker
**Impact on plan:** No product behavior, assertion, retry policy, gate status, fixture, oracle, or evidence claim changed. The boundary removes confirmed simulator-host state between two required test sessions.

## TDD Gate Compliance

- Task 1 RED failed because the comparator did not exist; GREEN passes all independent-oracle and exact-agreement mutations.
- Task 2 RED failed because the preflight entry point did not exist; GREEN passes closed evidence, overclaim, binding, privacy, atomic replacement, and required-surface tests.
- A failed full run never published partial evidence. Publication occurred only after all 13 checks completed successfully.

## Verification

- `python3 -m unittest tools.verify.tests.test_phase_03_transactions` — 11 tests passed.
- `scripts/verify-phase-03-transactions quick` — passed; three runtimes, two byte-identical isolated runs each, no evidence publication.
- Targeted `RoomEditJourneyTests` diagnostic — 1 test passed in 23.003 seconds with zero failures after the simulator host was clean.
- `scripts/verify-phase-03-transactions full` — passed all 13 declared checks and atomically published evidence.
- Evidence validation — passed with 24 cases, three runtimes, two runs per runtime, zero semantic/provenance disagreements, and every declared deferred gate `PENDING`.
- Evidence file SHA-256: `cfadb799fe8a22899aaf953c1cb5f73528fc527ed908b13616df8b1d08e9b3`; internal preflight SHA-256: `5003c352f8a869b0af0b2261aad68a891f893b5d7bd5c50438e131ee27806baf`.
- `git diff --check` and the full tracked-file secret scan passed.

## User Setup Required

None. The verifier uses the local checked-in fixture and sources plus the uniquely available iPhone 17 simulator. No account, cloud service, learned provider, network, or physical-device claim is required.

## Next Phase Readiness

- Phase 3's seven approved implementation plans are complete and the automated sprint slice passes.
- Ready for the next sprint-critical roadmap slice; formal GATE-009/GATE-010 campaigns and GATE-011/physical/reconnect/proxy/license/human/full-P0 evidence remain explicitly deferred to the recorded resume path.

---
*Phase: 03-typed-place-commit-and-offline-restore*
*Completed: 2026-07-18*

## Self-Check: PASSED

- All five planned artifacts exist and the two RED/GREEN chains are present.
- Exact quick/full verification and independent evidence validation pass.
- No deferred gate is represented as green or complete.
- Pre-existing `.planning/config.json`, Xcode project/scheme changes, workspace/user data, and local Swift build artifacts remain unstaged.
