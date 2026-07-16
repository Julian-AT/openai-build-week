---
phase: 01-contract-and-device-proof
plan: "06"
subsystem: contract-tooling
tags: [python, json-schema-2020-12, rfc-8785, sha256, rrfp, coordinates, fixtures]

requires:
  - phase: 01-contract-and-device-proof
    provides: Frozen contract/JCS/coordinate fixture corpus and RunnerResultV1 from Plans 01-01 and 01-03
  - phase: 01-contract-and-device-proof
    provides: Exact approved jsonschema and rfc8785 lock closure from Plan 01-04
provides:
  - Independent Python consumer for every frozen contract, JCS, wire, path, and coordinate case
  - Strict bounded JSON and fixture loader with immutable schema/input/artifact verification
  - Trailer-less CON-001 RRFP encoder/decoder and RR-COORD-1 pure math functions
  - Closed normalized RunnerResultV1 library and fresh-output CLI
affects: [01-07, 01-10, python-runtime, contract-parity, coordinate-parity]

tech-stack:
  added: []
  patterns: [bounded fail-closed fixture loading, strict duplicate-aware JSON parsing, independent oracle execution, normalized result envelopes]

key-files:
  created:
    - tools/python/reroom_verify/__init__.py
    - tools/python/reroom_verify/loader.py
    - tools/python/reroom_verify/schema_validator.py
    - tools/python/reroom_verify/canonical_json.py
    - tools/python/reroom_verify/wire_frame.py
    - tools/python/reroom_verify/coordinate.py
    - tools/python/reroom_verify/runner.py
    - tools/python/tests/test_runner.py
  modified: []

key-decisions:
  - "Parse untrusted JSON as bounded strict UTF-8 with duplicate-name and lone-surrogate rejection before validation or canonicalization."
  - "Use only the previously approved exact jsonschema and rfc8785 lock closure while independently verifying every immutable manifest, schema, input, and expected-artifact hash."
  - "Decode RRFP-WIRE-1 in authoritative boundary order so length duplicates, sequence duplicates, payload SHA, truncation, and trailing bytes retain stable rejection classes."
  - "Serialize computed coordinate artifacts in their frozen field order while using RFC 8785 bytes for every JCS and RunnerResultV1 digest scope."

patterns-established:
  - "Known fixture rejection boundaries raise VerificationFailure with one stable RunnerResultV1 rejection class; unexpected programming errors escape."
  - "Fixture execution reads expected bytes only for oracle integrity and derives all reported output-artifact metadata from independently computed bytes."

requirements-completed: [NFR-CONTRACT-001, NFR-COORD-001]

coverage:
  - id: D1
    description: "Python independently validates all frozen closed schemas, strict JSON/JCS bytes and digests, safe paths, and exact trailer-less RRFP framing."
    requirement: NFR-CONTRACT-001
    verification:
      - kind: unit
        ref: ".venv/bin/python -m unittest tools.python.tests.test_runner -v#contract, JCS, wire, and path boundaries"
        status: pass
      - kind: integration
        ref: "tools/verify/compare_results.py compare for FX-CONTRACT-001 and FX-JCS-001"
        status: pass
    human_judgment: false
  - id: D2
    description: "RR-COORD-1 pure functions and the Python runner consume every frozen case and emit complete ordered RunnerResultV1 envelopes."
    requirement: NFR-COORD-001
    verification:
      - kind: unit
        ref: ".venv/bin/python -m unittest tools.python.tests.test_runner -v#coordinate vectors and all-family runner"
        status: pass
      - kind: integration
        ref: "tools/verify/compare_results.py compare for FX-COORD-001"
        status: pass
    human_judgment: false

duration: 16min
completed: 2026-07-16
status: complete
---

# Phase 01 Plan 06: Independent Python Contract and Coordinate Runner Summary

**A bounded Python reference independently executes all 51 frozen contract, RFC 8785, RRFP, path, and RR-COORD-1 cases and emits comparator-accepted RunnerResultV1 envelopes.**

## Performance

- **Duration:** 16 min
- **Started:** 2026-07-16T21:47:55Z
- **Completed:** 2026-07-16T22:04:19Z
- **Tasks:** 2
- **Files modified:** 8

## Accomplishments

- Added bounded immutable fixture loading with strict UTF-8/JSON parsing, duplicate-name and lone-surrogate rejection, repository-contained paths, exact byte/digest checks, schema identity checks, and closed Draft 2020-12 validation.
- Implemented RFC 8785 canonical bytes/SHA-256 plus the exact 24-byte big-endian RRFP-WIRE-1 frame with magic/version/zero flags, duplicate length/sequence agreement, payload digest, truncation, and trailing-byte rejection.
- Implemented finite binary32 validation, proper rigid transforms, encoded intrinsics/orientation, projection, OpenCV conversion, forward-only world correction, and normalized ordered execution across all three fixture families.

## Task Commits

Each TDD task was committed as a failing specification followed by its passing implementation:

1. **Task 1 RED: Contract/JCS/wire/path boundary test** - `c1623e7` (test)
2. **Task 1 GREEN: Schema, serialization, path, and RRFP policies** - `c2be5fb` (feat)
3. **Task 2 RED: Coordinate and all-family runner tests** - `3d9fba5` (test)
4. **Task 2 GREEN: RR-COORD-1 and normalized Python runner** - `31431a7` (feat)

**Plan metadata:** recorded by the closeout commit containing this summary.

## Files Created/Modified

- `tools/python/reroom_verify/__init__.py` - Minimal package boundary exposing the normalized verification failure type.
- `tools/python/reroom_verify/loader.py` - Bounded strict parser, safe repository path resolution, manifest/schema/hash verification, and immutable fixture access.
- `tools/python/reroom_verify/schema_validator.py` - Draft 2020-12 contract validation, compatibility handling, JSON mutation execution, and stable semantic classification.
- `tools/python/reroom_verify/canonical_json.py` - RFC 8785 canonical bytes, SHA-256 scopes, and computed artifact metadata.
- `tools/python/reroom_verify/wire_frame.py` - Exact CON-001 RRFP encode/decode and bounded wire mutation execution without a trailer.
- `tools/python/reroom_verify/coordinate.py` - RR-FLOAT-1, rigid matrix, projection, transformed intrinsics, OpenCV, orientation, and world-correction helpers.
- `tools/python/reroom_verify/runner.py` - Explicit case-kind dispatch, closed RunnerResultV1 validation/digest, library API, and exclusive fresh-output CLI.
- `tools/python/tests/test_runner.py` - TDD coverage for immutable oracle execution, all three families, ordering, result digests, unknown kinds, and oracle non-mutation.

## Decisions Made

- Checked manifest, contract schema, case input, and expected artifact integrity before executing any case, but never copied oracle metadata into computed case results.
- Classified semantic authority mismatch before schema-pattern errors and validated unsafe archive-relative paths before contract schema evaluation, preserving the authoritative rejection boundary.
- Required canonical RRFP JSON header bytes and checked each duplicated header field before the payload hash and final trailing-byte boundary.
- Kept coordinate helpers pure and serialized their computed result objects with explicit frozen field order and compact UTF-8 plus newline; RFC 8785 remains authoritative for JCS and result digests.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- The repository-local virtual environment was absent, so the already human-approved exact hash-locked Python dependency closure from Plan 01-04 was installed before executing the required `.venv/bin/python` tests. The offline dependency verifier and `pip check` both pass.
- GSD consistency passes. GSD health remains degraded only by the pre-existing non-repairable `adaptive` model-profile warning; the missing 01-06 summary informational item is resolved by this closeout.

## Evidence

- Python runner tests pass for all 51 frozen cases: 23 expected accepts and 28 expected rejections.
- The independent comparator accepts fresh Python results for `FX-CONTRACT-001`, `FX-JCS-001`, and `FX-COORD-001`; fixture integrity passes for all three manifests.
- The comparator regression suite and Python runner suite pass together: 13 tests.
- Exact approved dependency closure verification passes: 6 decisions, direct npm/Python/Swift roots `3/2/1`, and 10 audited reachable transitives; `pip check` reports no broken requirements.
- Python compilation, targeted secret scan, `git diff --check`, and clean-worktree checks pass.
- No physical-device, human, cloud, deployment, or fabricated evidence was introduced by this plan.

## User Setup Required

None - the Python runner consumes the already approved exact hash-locked dependency closure.

## Next Phase Readiness

- Plan 01-07 can execute the independent JavaScript and Python runners into fresh isolated outputs and prove exact cross-runtime parity with mutation gates.
- Physical-device, Swift, and human evidence remain correctly pending for their later risk slices.

## Self-Check: PASSED

- All eight declared Python source/test files exist.
- Task commits `c1623e7`, `c2be5fb`, `3d9fba5`, and `31431a7` exist in history.
- All 51 frozen cases are represented exactly once in strict lexicographic order by their family runner.

---
*Phase: 01-contract-and-device-proof*
*Completed: 2026-07-16*
