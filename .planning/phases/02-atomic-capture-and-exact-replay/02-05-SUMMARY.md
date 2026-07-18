---
phase: 02-atomic-capture-and-exact-replay
plan: "05"
subsystem: cross-runtime-replay-evidence
tags: [swift, node, python, replay, jcs, evidence, atomic-publication]

requires:
  - phase: 02-atomic-capture-and-exact-replay
    plan: "01"
    provides: Immutable capture corpus, closed ReplayReport schema, and frozen expected outcomes
  - phase: 02-atomic-capture-and-exact-replay
    plan: "03"
    provides: Verified Swift replay core and named ReRoomReplayRunner executable
  - phase: 02-atomic-capture-and-exact-replay
    plan: "04"
    provides: Queue-order, boundedness, pressure, and completion-order invariants represented by the edge probes
provides:
  - Independent exact-Node v22.22.3 replay over the complete immutable capture corpus
  - Independent Python 3.13.12 replay with dependency-free strict parsing and canonical report encoding
  - Closed three-runtime comparator and recoverable atomic revision-bound agreement evidence
affects: [02-06-native-capture-adapter, 02-07-capture-evidence, mode-b0-replay]

tech-stack:
  added: []
  patterns:
    - Independent replay before immutable-oracle equality
    - Runtime-provenance stripping only after schema, oracle, and self-digest validation
    - Exact runner-revision binding plus separate evaluator and publisher hashes
    - Recoverable prepared/committed evidence replacement

key-files:
  created:
    - tools/javascript/src/replay.ts
    - tools/javascript/test/replay.test.mjs
    - tools/python/reroom_verify/replay.py
    - tools/python/tests/test_replay.py
    - tools/verify/compare_replay_reports.py
    - tools/verify/tests/test_replay_agreement.py
    - scripts/run-phase-02-replay-agreement
    - evidence/compatibility/replay-agreement.json
  modified: []

key-decisions:
  - "Bind all three replay implementations to exact runner revision 0d371bc1de9a057cbf61b70142729f6cbe620eec, close and hash that source tree, and record the comparator and publisher as separate exact provenance hashes."
  - "Validate each runtime report against the frozen fixture, closed schema, exact identity, canonical bytes, and self-digest before removing runtime-only provenance for semantic artifact comparison."
  - "Keep the Python replay entry point standard-library-only so the plan's exact bare-python test command is deterministic without importing another runtime or weakening the locked shipping dependency policy."
  - "Publish the single evidence generation through a durable prepared/committed transaction that restores the prior generation after a failed replacement or interrupted restart."

patterns-established:
  - "Independent-first comparison: no runtime output is an authority for another runtime; expected values are consulted only after replay computations and integrity checks complete."
  - "Closed result roots: every invocation writes exactly 16 sorted case-named reports into a fresh exclusive directory, and missing, extra, stale, or non-regular members fail closed."
  - "Sanitized reproducibility: evidence records only stable identities, hashes, counts, outcomes, and toolchain facts, never temporary paths, room bytes, device IDs, or private traces."

requirements-completed: [FR-B0-001, NFR-REPLAY-001, FR-CAPTURE-001]

coverage:
  - id: D1
    description: "Exact Node v22.22.3 independently verifies raw inventory, archive self-hashes, event/frame/packet bindings, contiguous journal projections, finalization, and all 16 replay outcomes before publishing closed canonical ReplayReport bytes."
    requirement: FR-B0-001
    verification:
      - kind: integration
        ref: "node --test tools/javascript/test/replay.test.mjs"
        status: pass
    human_judgment: false
  - id: D2
    description: "Python 3.13.12 independently reproduces the same complete corpus with strict duplicate/Unicode/path handling, canonical self-digests, byte-identical repeated and concurrent runs, and no overwrite or cross-runtime authority."
    requirement: FR-CAPTURE-001
    verification:
      - kind: integration
        ref: "python3 -m unittest tools.python.tests.test_replay -v"
        status: pass
    human_judgment: false
  - id: D3
    description: "The publisher executes the actual Swift, Node, and Python entry points, rejects integrity/provenance/semantic/publication mutations, and atomically emits one 16-case zero-disagreement evidence generation with stable bytes."
    requirement: NFR-REPLAY-001
    verification:
      - kind: integration
        ref: "python3 -m unittest tools.verify.tests.test_replay_agreement -v"
        status: pass
      - kind: other
        ref: "scripts/run-phase-02-replay-agreement twice plus --verify-evidence"
        status: pass
    human_judgment: false

duration: 32min
completed: 2026-07-18
status: complete
---

# Phase 02 Plan 05: Exact Three-Runtime Replay Agreement Summary

**Swift, exact Node, and exact Python now independently replay the immutable capture corpus and publish one source-bound, byte-stable, recoverable zero-disagreement evidence artifact.**

## Performance

- **Duration:** 32 min
- **Started:** 2026-07-17T23:43:39Z
- **Completed:** 2026-07-18T00:15:31Z
- **Tasks:** 3
- **Files modified:** 8

## Accomplishments

- Added an erasable TypeScript runner under exact Node v22.22.3 that independently validates the complete raw archive, journal, event, frame, packet, image, projection, final-sequence, and manifest-digest chain before emitting the 16-case report set.
- Added a standard-library Python 3.13.12 runner with its own strict duplicate-aware Unicode parser, safe-path and inventory validation, replay calculations, edge-probe evaluation, canonical report encoding, and exclusive atomic output publication.
- Added a fail-closed comparator that validates each report against the immutable fixture and closed schema before comparing the runtime-independent semantic artifact; omission, extra, stale, wrong-runtime, wrong-digest, semantic, and fixture-integrity mutations all have stable kills.
- Added a hardened publisher that closes the execution-eligible source set, builds and invokes the exact `ReRoomReplayRunner` product, binds all runtimes and provenance hashes, and replaces evidence through a recoverable prepared/committed transaction.
- Published `replay-agreement.json` with 16 sorted cases, three raw output-set digests, and zero missing, extra, semantic, runtime-identity, report-digest, or fixture-integrity disagreements.

## Task Commits

Each behavior-bearing task was implemented through a RED/GREEN pair:

1. **Task 1: Implement independent exact replay under pinned Node**
   - `31849f4` — `test(02-05): define exact Node replay behavior` (RED)
   - `3ac74e1` — `feat(02-05): implement independent exact Node replay` (GREEN)
2. **Task 2: Implement independent exact replay in Python**
   - `b4699f8` — `test(02-05): define independent Python replay behavior` (RED)
   - `0d371bc` — `feat(02-05): implement independent Python replay` (GREEN)
3. **Task 3: Publish complete three-runtime replay agreement atomically**
   - `e15f8d9` — `test(02-05): define replay agreement proof gates` (RED)
   - `d8280b3` — `feat(02-05): publish exact three-runtime replay agreement` (GREEN)

**Plan summary:** recorded by the following documentation-only commit.

## Files Created/Modified

- `tools/javascript/src/replay.ts` - Exact-Node fixture loader, archive verifier, independent edge evaluator, ReplayReport encoder, and exclusive staged publisher.
- `tools/javascript/test/replay.test.mjs` - Complete corpus, repeated/concurrent identity, runtime/output rejection, and archive-corruption coverage.
- `tools/python/reroom_verify/replay.py` - Standard-library strict parser, canonical encoder, archive replay implementation, edge evaluator, and durable report publisher.
- `tools/python/tests/test_replay.py` - Complete corpus, repeated/concurrent identity, runtime/output rejection, and archive-corruption coverage.
- `tools/verify/compare_replay_reports.py` - Immutable fixture integrity verifier, closed schema/self-digest validator, runtime identity gate, and normalized semantic comparator.
- `tools/verify/tests/test_replay_agreement.py` - Actual-runtime agreement, source/runtime/semantic/integrity mutations, failure isolation, and transaction rollback/restart coverage.
- `scripts/run-phase-02-replay-agreement` - Exact runtime orchestration, source closure, selected Swift manifest binding, deterministic evidence construction, and atomic publication/verification.
- `evidence/compatibility/replay-agreement.json` - Sanitized measured three-runtime agreement evidence.

## Decisions Made

- The exact runner revision is `git:0d371bc1de9a057cbf61b70142729f6cbe620eec`. Its closed source-tree digest covers all runtime inputs; the later comparator and publisher are bound separately by their content hashes so evidence remains reproducible without a dynamic-HEAD or self-reference loop.
- Runtime provenance is never normalized before validation. Each report must first match its exact runtime/evaluator/build identity, implementation revision, immutable fixture oracle, closed schema, canonical bytes, and self-digest; only then are `evaluator`, `implementation`, and `report_sha256` removed to compute the shared semantic artifact digest.
- Python replay uses a dependency-free closed-domain canonical encoder because the required `python3 -m unittest ...` environment does not expose the verification venv's `rfc8785` package. This preserves the exact command and changes no dependency manifest or lock.
- Evidence publication uses a recoverable single-target generation transaction. A prepared interruption restores the prior evidence, while a committed marker requires the complete new digest before cleanup.

## Deviations from Plan

### Auto-fixed Environment Compatibility

**1. Bare Python verification did not expose the locked helper dependency**

- **Found during:** Task 2 GREEN
- **Issue:** The plan's exact bare-`python3` verification environment did not provide `rfc8785`, so importing the existing canonical helper would fail before replay.
- **Fix:** Implemented strict JSON parsing and canonical encoding for the closed ReplayReport/capture fixture domain inside the independent runner using only the standard library; no dependency or lock changed.
- **Files modified:** `tools/python/reroom_verify/replay.py`
- **Verification:** The exact focused Python command and all repeat/concurrency/mutation gates pass.
- **Committed in:** `0d371bc`

### Auto-fixed Direct Entrypoint Bootstrap

**2. Executing the publisher by path did not place the repository package root on `sys.path`**

- **Found during:** Task 3 evidence generation
- **Issue:** `scripts/run-phase-02-replay-agreement` could be imported by tests but direct execution could not resolve `tools.verify.compare_replay_reports`.
- **Fix:** Added a deterministic repository-root bootstrap before the comparator import.
- **Files modified:** `scripts/run-phase-02-replay-agreement`
- **Verification:** Two direct publisher invocations and direct `--verify-evidence` pass.
- **Committed in:** `d8280b3`

---

**Total deviations:** 2 auto-fixed (1 environment compatibility, 1 direct entrypoint bootstrap)
**Impact on plan:** Both fixes preserve the planned exact commands and dependency-free evidence path; neither expands product scope.

## Issues Encountered

- macOS exposes `/tmp` as a symlink, and the runners correctly reject symlink output parents. Manual isolated checks used `/private/tmp`; automated tests use regular temporary subdirectories and require no product relaxation.
- GSD health remains degraded only by the pre-existing, non-repairable `W004` warning for the user-modified `model_profile: adaptive`; no health error or repairable finding exists, and that unrelated configuration was preserved.

## Verification Evidence

- `node --test tools/javascript/test/replay.test.mjs` passed 4 tests, including complete output, sequential/concurrent byte identity, exact runtime/no-overwrite gates, and one-byte archive corruption.
- `python3 -m unittest tools.python.tests.test_replay -v` passed 4 tests covering the equivalent independent Python corpus and mutations.
- `python3 -m unittest tools.verify.tests.test_replay_agreement -v` passed 10 tests, including actual Swift/Node/Python execution, complete normalized agreement, every planned mutation family, publication rollback, and restart recovery.
- The committed publisher ran twice after all implementation commits and preserved evidence SHA-256 `c30286ae23015a140a09504d375aefb34185096104a9e4be56e5418d244c4e1d`; `--verify-evidence` passed.
- Evidence records 16 cases, three exact runtime identities and raw output-set digests, the selected Swift `Package.swift`, exact fixture/report/rrcap schema hashes, evaluator/publisher hashes, and zero disagreement metrics without temporary paths or private data.
- Dependency manifests and locks are byte-unchanged from the plan baseline; strict Python compilation, changed-file secret scanning, source/fixture closure, and `git diff --check` passed.

## User Setup Required

None - no dependency, credential, endpoint, deployment, live network, cloud resource, or private evidence is required.

## Next Phase Readiness

- Plans 02-06 and 02-07 can consume the closed 16-case agreement artifact and exact source/runtime bindings as their host replay proof.
- The deterministic typed/tap Mode B0 replay input path is now proven across all three host runtimes without a model, renderer, provider, or network defining replay authority.
- Physical-device, human, signing, ARKit, compositor, thermal, and the three-minute `NFR-REPLAY-001` timing gate remain pending until their real measured evidence exists.

## Self-Check: PASSED

- All six RED/GREEN task commits exist and all eight declared plan artifacts exist at their planned paths.
- All three focused task commands, two committed-tree publisher runs, evidence provenance verification, source/fixture integrity, lock-diff, secret, syntax, and whitespace checks passed after the final implementation.
- The checked-in evidence is complete, sorted, sanitized, revision-bound, and byte-stable with zero three-runtime disagreements.
- Pre-existing config, Xcode scheme, `.swiftpm`, workspace, and user-data changes remain outside plan commits; the generated Swift build cache was moved out of the workspace after verification.

---
*Phase: 02-atomic-capture-and-exact-replay*
*Completed: 2026-07-18*
