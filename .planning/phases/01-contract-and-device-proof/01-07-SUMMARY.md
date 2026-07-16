---
phase: 01-contract-and-device-proof
plan: "07"
subsystem: contract-tooling
tags: [javascript, python, parity, mutation-testing, fixtures, sha256, rrfp, coordinates]

requires:
  - phase: 01-contract-and-device-proof
    provides: Frozen contract/JCS/coordinate corpus and fail-closed comparator from Plans 01-01 and 01-03
  - phase: 01-contract-and-device-proof
    provides: Independent JavaScript and Python reference runners from Plans 01-05 and 01-06
provides:
  - Fresh isolated two-runtime parity command for every frozen fixture family
  - Exact runner identity, implementation revision, completeness, oracle, and result comparison gates
  - Independent JavaScript and Python mutation suites covering contract, JCS, RRFP, path, coordinate, and fixture-integrity faults
  - Comparator tamper tests over fresh actual runtime outputs
affects: [01-10, swift-runtime, three-runtime-agreement, contract-parity, coordinate-parity]

tech-stack:
  added: []
  patterns: [exclusive fresh outputs, immutable-oracle hash controls, copy-only mutation gates, exact normalized-result comparison]

key-files:
  created:
    - scripts/run-reference-parity
    - tools/javascript/test/parity-mutations.test.mjs
    - tools/python/tests/test_parity_mutations.py
  modified:
    - tools/verify/tests/test_reference_parity.py

key-decisions:
  - "Run each actual reference executable into a newly created isolated directory, bind both results to one exact Git revision, and reject stale or pre-existing output paths."
  - "Hash the complete checked-in fixture and contract-schema oracle before and after parity execution and every mutation suite."
  - "Mutate only temporary copies, retaining stable case IDs and expected rejection classes so each runtime must independently kill the intended fault."
  - "Recompute a tampered result envelope's digest before comparison so comparator mutation tests exercise oracle fields and completeness rather than failing only at the outer digest."

patterns-established:
  - "Cross-runtime acceptance requires fresh JavaScript and Python outputs, exact expected runner identities, one shared implementation revision, complete ordered rows, and independent comparator success."
  - "Mutation tests separate semantic faults from fixture-integrity faults by updating copied input references only for semantic mutations and deliberately retaining stale references for integrity mutations."

requirements-completed: [NFR-CONTRACT-001, NFR-COORD-001]

coverage:
  - id: D1
    description: "Fresh JavaScript and Python reference executions agree exactly for the frozen contract and JCS families without modifying the oracle."
    requirement: NFR-CONTRACT-001
    verification:
      - kind: integration
        ref: "scripts/run-reference-parity#FX-CONTRACT-001 and FX-JCS-001 fresh two-runtime parity"
        status: pass
      - kind: integration
        ref: "python3 -m unittest tools.verify.tests.test_reference_parity -v#fresh runtimes and fail-closed comparator tampering"
        status: pass
    human_judgment: false
  - id: D2
    description: "Fresh JavaScript and Python reference executions agree exactly for RR-COORD-1 and trailer-less RRFP vectors."
    requirement: NFR-COORD-001
    verification:
      - kind: integration
        ref: "scripts/run-reference-parity#FX-COORD-001 fresh two-runtime parity"
        status: pass
      - kind: unit
        ref: "node --test tools/javascript/test/parity-mutations.test.mjs#RRFP and coordinate mutations"
        status: pass
      - kind: unit
        ref: ".venv/bin/python -m unittest tools.python.tests.test_parity_mutations -v#RRFP and coordinate mutations"
        status: pass
    human_judgment: false
  - id: D3
    description: "Runtime and comparator mutation gates reject contract, digest, coordinate, omission, archive-path, and oracle-integrity faults with stable diagnostics."
    requirement: NFR-CONTRACT-001
    verification:
      - kind: integration
        ref: "node --test tools/javascript/test/parity-mutations.test.mjs && .venv/bin/python -m unittest tools.python.tests.test_parity_mutations tools.verify.tests.test_reference_parity -v"
        status: pass
    human_judgment: false

duration: 12min
completed: 2026-07-16
status: complete
---

# Phase 01 Plan 07: Cross-Runtime Parity and Mutation Gates Summary

**Fresh isolated JavaScript and Python executions agree exactly across all frozen contract, JCS, RRFP, path, and coordinate cases, with mutation gates proving both runtimes and the comparator fail closed.**

## Performance

- **Duration:** 12 min
- **Started:** 2026-07-16T22:09:07Z
- **Completed:** 2026-07-16T22:20:49Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Added one executable command that produces fresh actual JavaScript and Python RunnerResultV1 outputs, checks expected runner identities and a shared exact Git revision, and requires complete comparator agreement for `FX-CONTRACT-001`, `FX-JCS-001`, and `FX-COORD-001`.
- Added independent copy-only mutation suites that kill closed-schema, unsafe-path, payload/JCS digest, all authoritative RRFP header and boundary, coordinate matrix/orientation/correction, and fixture-hash faults with stable rejection classes.
- Added integrated comparator mutations over retained fresh actual outputs, including verdict, artifact digest, result omission, manifest digest, and copied-oracle integrity faults, while proving checked-in oracle hashes remain unchanged.

## Task Commits

Each TDD task was committed as a failing specification followed by its passing implementation:

1. **Task 1 RED: Fresh reference parity harness specification** - `16bcaa4` (test)
2. **Task 1 GREEN: Isolated two-runtime parity command** - `4d3063e` (feat)
3. **Task 2 RED: Cross-runtime mutation-gate specification** - `551f92c` (test)
4. **Task 2 GREEN: Runtime and comparator mutation gates** - `5e428ee` (feat)

**Plan metadata:** recorded by the closeout commit containing this summary.

## Files Created/Modified

- `scripts/run-reference-parity` - Executable fresh-output orchestrator with runner identity/revision checks, exact common comparison, and pre/post immutable-oracle hashes.
- `tools/verify/tests/test_reference_parity.py` - Integration coverage for stale paths, missing runtimes, identity/revision/case faults, actual-result tampering, and copied-oracle integrity.
- `tools/javascript/test/parity-mutations.test.mjs` - Independent JavaScript mutation matrix over temporary fixture/schema copies.
- `tools/python/tests/test_parity_mutations.py` - Independent Python mutation matrix over temporary fixture/schema copies.

## Decisions Made

- Used one Git revision value for both executions and validated the exact expected name/version/runtime tuple before invoking the common comparator, preventing unrelated or stale programs from satisfying parity.
- Created output directories exclusively and rejected all existing output paths so a green result cannot reuse a prior runner artifact.
- Reused frozen negative case bytes only inside copied manifests for stable boundary mutations, while coordinate mutations recompute copied input references so the runtime reaches the intended semantic boundary.
- Kept RRFP mutation coverage on the authoritative exact 24-byte-header wire format, including trailing-byte rejection, without adding or testing a wire trailer.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Preserve virtual-environment interpreter semantics**
- **Found during:** Task 1 GREEN (isolated two-runtime parity command)
- **Issue:** Resolving `.venv/bin/python` through its physical symlink selected the base interpreter and lost the virtual environment's approved packages.
- **Fix:** Normalized the executable to an absolute path without dereferencing the virtual-environment symlink.
- **Files modified:** `scripts/run-reference-parity`
- **Verification:** Direct parity and both required task commands pass using `.venv/bin/python`; `pip check` reports no broken requirements.
- **Committed in:** `4d3063e` (part of Task 1 GREEN)

---

**Total deviations:** 1 auto-fixed bug.
**Impact on plan:** The correction preserves the already approved environment and changes no contract, fixture, dependency, or product scope.

## Issues Encountered

- GSD consistency passes with expected notices for future phase directories. GSD health remains degraded only by the pre-existing non-repairable `adaptive` model-profile warning; this summary resolves the in-progress 01-07 informational item.

## Evidence

- `python3 -m unittest tools.verify.tests.test_reference_parity -v` passes all 3 integration tests.
- The exact combined mutation command passes the JavaScript suite and all 4 Python/integration tests; every planned copied mutation is killed and repository oracle hashes match before and after.
- `scripts/run-reference-parity` reports fresh exact JavaScript/Python parity for all three frozen fixture families.
- Phase quick verification passes the exact dependency closure, all fixture/evidence/meta-schema/comparator tests, both reference-runner suites, and coordinate integrity checks.
- The 11-test comparator regression suite, Python compilation, JavaScript syntax check, `pip check`, targeted secret/stub scans, executable-mode check, `git diff --check`, and clean-worktree checks pass.
- This plan proves only the independent JavaScript/Python pair; Swift agreement, physical-device evidence, human gates, cloud actions, deployment, and D-12's final three-runtime acceptance remain correctly pending.

## User Setup Required

None - the parity harness uses the already approved exact local runtime closure.

## Next Phase Readiness

- The shared immutable oracle and demonstrably effective two-runtime parity gate are ready for the Swift consumer and final three-runtime agreement slice.
- No fixture revision is declared accepted by this plan alone; D-12 still requires Swift agreement in Plan 01-10, and physical/human gates remain pending.

## Self-Check: PASSED

- All four declared implementation/test files exist, and `scripts/run-reference-parity` is tracked executable.
- Task commits `16bcaa4`, `4d3063e`, `551f92c`, and `5e428ee` exist in history.
- The required commands pass from committed HEAD with an unchanged checked-in oracle and clean worktree.

---
*Phase: 01-contract-and-device-proof*
*Completed: 2026-07-16*
