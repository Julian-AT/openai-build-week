---
phase: 01-contract-and-device-proof
plan: "03"
subsystem: verification
tags: [fixtures, comparator, oracle-integrity, preflight, physical-gates]

requires:
  - phase: 01-contract-and-device-proof
    provides: Immutable fixture manifests and evidence schemas from Plans 01-01 and 01-02
  - phase: 01-contract-and-device-proof
    provides: Approved exact dependency closure from Plan 01-04
provides:
  - Fail-closed bounded fixture and normalized runner-result comparator
  - Stable fixture-integrity, evidence, contracts, coords, references, quick, full, and gate modes
  - Automated-preflight boundary independent from physical gate evidence
  - Physical completion rule requiring bound signed GREEN GATE-013 and GATE-002 reports
affects: [01-05, 01-06, 01-07, 01-08, 01-09, 01-10, 01-13, 01-14, contract-runners, device-proof]

tech-stack:
  added: []
  patterns: [bounded fail-closed reads, immutable oracle verification, exact normalized result comparison, automation-physical gate separation]

key-files:
  created:
    - tools/verify/compare_results.py
    - tools/verify/tests/test_compare_results.py
    - scripts/verify-phase-01-contracts
  modified: []

key-decisions:
  - "Fixture manifests, registered contract schemas, case inputs, and expected artifacts are all hash-checked before a runner result can be accepted."
  - "Runner results must contain exactly the manifest case set in order and agree byte-for-byte through declared artifact lengths and digests."
  - "Full automation emits only a RUNNING automated preflight and never reads physical reports; gate is the sole consumer of physical reports and succeeds only for two bound signed GREEN decisions."

patterns-established:
  - "Comparator diagnostics expose deterministic mismatch classes and case IDs without echoing untrusted payload bytes."
  - "Unavailable future verification surfaces fail closed in full/references while quick runs every deterministic check currently present."

requirements-completed: [NFR-CONTRACT-001, NFR-COORD-001, OPS-DEVICE-001]

coverage:
  - id: D1
    description: "Immutable fixtures and normalized runtime outputs reject changed, malformed, missing, extra, duplicate, reordered, or disagreeing data."
    requirement: NFR-CONTRACT-001
    verification:
      - kind: unit
        ref: "python3 -m unittest tools.verify.tests.test_compare_results -v"
        status: pass
      - kind: integration
        ref: "scripts/verify-phase-01-contracts fixture-integrity"
        status: pass
    human_judgment: false
  - id: D2
    description: "Coordinate fixtures use the same exact integrity and cross-runner comparison boundary as contract and JCS fixtures."
    requirement: NFR-COORD-001
    verification:
      - kind: integration
        ref: "scripts/verify-phase-01-contracts coords"
        status: pass
    human_judgment: false
  - id: D3
    description: "Automated preflight is physically independent and phase gate success requires bound signed GREEN GATE-013 and GATE-002 evidence."
    requirement: OPS-DEVICE-001
    verification:
      - kind: unit
        ref: "VerificationModeTests in tools/verify/tests/test_compare_results.py"
        status: pass
    human_judgment: false

duration: 10min
completed: 2026-07-16
status: complete
---

# Phase 01 Plan 03: Comparator and Verification Modes Summary

**Immutable fixture bytes and exact normalized results now form a fail-closed oracle boundary, while automated preflight and signed physical completion have separate, explicit modes.**

## Performance

- **Duration:** 10 min
- **Started:** 2026-07-16T11:56:48Z
- **Completed:** 2026-07-16T12:06:05Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- Added bounded JSON/file reads, duplicate-name and depth rejection, schema tuple/hash validation, immutable input/artifact verification, and exact RunnerResultV1 comparison across case order, verdicts, rejection classes, artifacts, summaries, fixture identity, and result digest.
- Added mutation-focused tests for changed oracle bytes, missing/extra/duplicate/reordered cases, every artifact field, manifest/result digest drift, duplicate runtimes, absent runtimes, and cross-runner disagreement.
- Added eight stable modes. `quick` runs all available deterministic checks; `full` requires the complete automated surface and atomically emits a sanitized candidate-bound preflight only after success; `gate` alone validates physical evidence and only accepts two bound signed GREEN reports.
- Proved schema-valid RED evidence remains valid input but can never become successful completion, and unknown or incomplete modes fail closed.

## Task Commits

Each task was committed atomically:

1. **Task 1 RED: Define fail-closed result comparison** - `8b147b8` (test)
2. **Task 1 GREEN: Add fail-closed fixture comparator** - `928e4e8` (feat)
3. **Task 2: Add bounded phase verification modes** - `48d9704` (feat)

**Plan metadata:** recorded by the closeout commit containing this summary and tracking updates.

## Files Created/Modified

- `tools/verify/compare_results.py` - Bounded fixture-integrity oracle and exact normalized multi-runtime result comparator.
- `tools/verify/tests/test_compare_results.py` - Mutation, disagreement, mode-boundary, RED, and signed-GREEN coverage.
- `scripts/verify-phase-01-contracts` - Stable deterministic, automated-preflight, and physical-gate mode dispatcher.

## Decisions Made

- Compared runner artifact metadata directly to manifest-owned exact byte length and digest fields; runners never supply paths or rewrite oracle files.
- Kept quick checks capability-aware, but made `references` and `full` require their future plan-owned components instead of silently skipping them.
- Represented successful automated preflight as schema-valid automation-owned `RUNNING` evidence bound to a real candidate artifact digest. This cannot self-approve either physical gate.
- Required GREEN checklists and reports to bind to the exact preflight and checklist bytes; RED, UNRUN, RUNNING, WAIVED_BY_HUMAN, missing, malformed, or unbound evidence exits nonzero.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## Verification Evidence

- Comparator/mode suite: 11 tests pass.
- `fixture-integrity`, `evidence`, `contracts`, `coords`, and `quick` pass against the current repository; quick includes the six-decision dependency verifier.
- Synthetic schema-valid signed GREEN pairs pass `gate`; a schema-valid GREEN/RED pair is retained but exits nonzero.
- Unknown mode, missing-component `full`, and absent physical evidence all reject safely as expected.
- The complete `full` surface and default physical `gate` inputs remain intentionally unavailable until later Phase 1 plans; their negative probes create no preflight or physical evidence.
- Secret-pattern scan and `git diff --check` pass.

## User Setup Required

None. Later plans must create the explicitly required runtime, native, release, evidence-verifier, candidate-build, and physical evidence inputs before `full` or the default `gate` can pass.

## Next Phase Readiness

- Independent JavaScript, Python, and Swift runners can target one exact normalized comparison boundary.
- Later CI/device-proof work can call stable mode names without granting automation authority over physical decisions.
- Physical GATE-013 and GATE-002 remain honestly pending; no evidence was fabricated.

## Self-Check: PASSED

- All three declared implementation/test files exist.
- Task commits `8b147b8`, `928e4e8`, and `48d9704` exist in history.
- Relevant tests, current modes, bounded negative probes, secret scan, and diff check pass.

---
*Phase: 01-contract-and-device-proof*
*Completed: 2026-07-16*
