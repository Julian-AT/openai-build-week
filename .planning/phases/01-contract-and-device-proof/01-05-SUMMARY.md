---
phase: 01-contract-and-device-proof
plan: "05"
subsystem: contract-tooling
tags: [javascript, json-schema-2020-12, rfc-8785, sha256, rrfp, coordinates, fixtures]

requires:
  - phase: 01-contract-and-device-proof
    provides: Frozen contract/JCS/coordinate fixture corpus and RunnerResultV1 from Plans 01-01 and 01-03
  - phase: 01-contract-and-device-proof
    provides: Exact approved Ajv, ajv-formats, and canonicalize lock closure from Plan 01-04
provides:
  - Independent JavaScript consumer for every frozen contract, JCS, wire, path, and coordinate case
  - Strict bounded JSON and fixture loader with immutable schema/input/artifact verification
  - Trailer-less CON-001 RRFP encoder/decoder and RR-COORD-1 pure math functions
  - Closed normalized RunnerResultV1 API and CLI output
affects: [01-06, 01-07, 01-10, javascript-runtime, contract-parity, coordinate-parity]

tech-stack:
  added: []
  patterns: [bounded fail-closed fixture loading, strict duplicate-aware JSON parsing, independent oracle execution, normalized result envelopes]

key-files:
  created:
    - tools/javascript/src/loader.mjs
    - tools/javascript/src/schema-validator.mjs
    - tools/javascript/src/canonical-json.mjs
    - tools/javascript/src/wire-frame.mjs
    - tools/javascript/src/coordinate.mjs
    - tools/javascript/src/runner.mjs
    - tools/javascript/test/runner.test.mjs
  modified: []

key-decisions:
  - "Parse untrusted JSON with a bounded duplicate-aware recursive parser so duplicate names and invalid Unicode reject before native object materialization."
  - "Use only the approved Ajv 2020-12 and canonicalize packages, while independently checking immutable schema, input, expected-artifact, and manifest bytes."
  - "RRFP-WIRE-1 is exactly one 24-byte big-endian fixed header, JCS header, and payload; no trailer, padding, or unchecked duplicate field is accepted."
  - "Runner output is canonical and self-digested, but checked-in expected bytes remain read-only oracle data and are never regenerated."

patterns-established:
  - "Fixture executors return only case_id, verdict, stable rejection_class, and content-derived output artifact metadata."
  - "Known validation failures normalize to RunnerFailure; unexpected programming/runtime errors escape instead of being misreported as fixture rejections."

requirements-completed: [NFR-CONTRACT-001, NFR-COORD-001]

coverage:
  - id: D1
    description: "JavaScript independently validates frozen closed schemas, strict JSON/JCS bytes and digests, safe paths, and exact trailer-less RRFP framing."
    requirement: NFR-CONTRACT-001
    verification:
      - kind: unit
        ref: "node --test tools/javascript/test/runner.test.mjs#contract, JCS, wire, and path policies match the immutable oracle"
        status: pass
      - kind: integration
        ref: "tools/verify/compare_results.py compare for FX-CONTRACT-001 and FX-JCS-001"
        status: pass
    human_judgment: false
  - id: D2
    description: "RR-COORD-1 pure functions and the JavaScript runner consume every frozen case and emit complete ordered RunnerResultV1 envelopes."
    requirement: NFR-COORD-001
    verification:
      - kind: unit
        ref: "node --test tools/javascript/test/runner.test.mjs#RR-COORD-1 and RunnerResultV1 tests"
        status: pass
      - kind: integration
        ref: "tools/verify/compare_results.py compare for FX-COORD-001"
        status: pass
    human_judgment: false

duration: 16min
completed: 2026-07-16
status: complete
---

# Phase 01 Plan 05: Independent JavaScript Contract and Coordinate Runner Summary

**A bounded JavaScript reference independently executes all 51 frozen contract, RFC 8785, RRFP, path, and RR-COORD-1 cases and emits comparator-accepted RunnerResultV1 envelopes.**

## Performance

- **Duration:** 16 min
- **Started:** 2026-07-16T12:11:32Z
- **Completed:** 2026-07-16T12:27:23Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments

- Added bounded immutable fixture loading with strict UTF-8/JSON parsing, duplicate-name and lone-surrogate rejection, safe resolved paths, exact byte/digest checks, schema registry enforcement, and Draft 2020-12 validation.
- Implemented RFC 8785 canonical bytes/SHA-256 plus the exact 24-byte big-endian RRFP-WIRE-1 frame with magic/version/zero flags, length/sequence agreement, payload digest, truncation, and one-byte trailing rejection.
- Implemented binary32 bounds/tolerances, rigid transforms, encoded intrinsics/orientation, camera projection, OpenCV conversion, explicit forward world corrections, and normalized ordered execution across all three fixture families.

## Task Commits

Each TDD task was committed as a failing specification followed by its passing implementation:

1. **Task 1 RED: Contract/JCS/wire/path oracle test** - `6de283b` (test)
2. **Task 1 GREEN: Schema, serialization, path, and RRFP policies** - `c9996e1` (feat)
3. **Task 2 RED: Coordinate and normalized-runner tests** - `7ce08e6` (test)
4. **Task 2 GREEN: RR-COORD-1 and RunnerResultV1 runner** - `044e2ce` (feat)

**Plan metadata:** recorded by the closeout commit containing this summary.

## Files Created/Modified

- `tools/javascript/src/loader.mjs` - Bounded strict JSON parser, safe path resolution, immutable fixture/schema verification, and mutation helpers.
- `tools/javascript/src/schema-validator.mjs` - Frozen Ajv 2020-12 contract validation, stable error classification, named compatibility case, and semantic checks.
- `tools/javascript/src/canonical-json.mjs` - RFC 8785 UTF-8 bytes, SHA-256, I-JSON Unicode checks, and JCS case execution.
- `tools/javascript/src/wire-frame.mjs` - Exact CON-001 RRFP encode/decode and wire mutation execution without a trailer.
- `tools/javascript/src/coordinate.mjs` - RR-FLOAT-1, rigid matrix, projection, transformed intrinsics, OpenCV, and world-correction functions.
- `tools/javascript/src/runner.mjs` - Three-family dispatch, RunnerResultV1 schema/semantic validation, result digest, and bounded CLI output.
- `tools/javascript/test/runner.test.mjs` - Immutable oracle, coordinate, ordering, summary, digest, and closed-envelope tests.

## Decisions Made

- Kept parser-differential raw inputs as exact bytes and rejected duplicate names/invalid Unicode before canonicalization.
- Classified rejection causes from the earliest authoritative boundary, including semantic authority mismatch before a misleading identity-pattern error.
- Generated output artifact metadata only from independently computed bytes; expected artifacts are read and hash-verified but never copied into computed results.
- Required explicit `git:<40 lowercase hex>` implementation identity, resolving current Git HEAD only when the caller omits it.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Made default CLI fixture resolution repository-aware**
- **Found during:** Task 2 CLI verification
- **Issue:** Library tests passed with an explicit repository root, but direct CLI use initially derived the wrong root from a nested fixture path.
- **Fix:** Anchored the default repository root to the checked-in JavaScript module location while preserving an explicit override for isolated tests.
- **Files modified:** `tools/javascript/src/loader.mjs`
- **Verification:** Direct CLI output for all three manifests passed the independent comparator.
- **Committed in:** `044e2ce`

**2. [Rule 1 - Bug] Corrected asynchronous result-schema assertion**
- **Found during:** Task 2 GREEN review
- **Issue:** `assert.doesNotThrow` cannot observe a rejected promise returned by the async result validator.
- **Fix:** Awaited `assert.doesNotReject` so RunnerResultV1 validation failures fail the test.
- **Files modified:** `tools/javascript/test/runner.test.mjs`
- **Verification:** All three Node test subtests pass with the awaited validation assertion.
- **Committed in:** `044e2ce`

---

**Total deviations:** 2 auto-fixed (1 Rule 1, 1 Rule 3)
**Impact on plan:** Both fixes were necessary for correct CLI/test behavior; no package, schema, fixture, native, Python, or later-plan scope changed.

## Issues Encountered

- The approved npm lock was consumed with scripts/audit/funding disabled; the offline dependency-closure verifier continued to pass with exactly three approved npm roots and four audited npm transitives.
- GSD consistency passes; GSD health remains degraded only by the pre-existing non-repairable `adaptive` model-profile warning already present before this plan.

## Evidence

- Node test suite: 3/3 subtests pass across 51 cases (23 accepts, 28 expected rejections).
- Independent comparator accepts fresh JavaScript results for `FX-CONTRACT-001`, `FX-JCS-001`, and `FX-COORD-001`.
- Exact approved dependency closure verifier passes: 6 decisions, direct npm/Python/Swift roots `3/2/1`, 10 audited reachable transitives.
- JavaScript syntax checks and `git diff --check` pass.
- Stub scan found no incomplete implementation; empty arrays/objects are intentional bounded accumulators or canonical fixture values.
- No unplanned network, authentication, endpoint, or schema surface was introduced; bounded file access is the declared T-01-08 trust boundary.

## User Setup Required

None - the JavaScript runner consumes the already approved exact npm lock.

## Next Phase Readiness

- Plan 01-06 can implement the independent Python runner against the same immutable corpus.
- Plan 01-07 can execute JavaScript/Python fresh-output parity and mutation gates using the runner CLI and common comparator.
- Physical-device, Swift, and human evidence remain correctly outside this plan.

## Self-Check: PASSED

- All seven declared JavaScript source/test files exist.
- Task commits `6de283b`, `c9996e1`, `7ce08e6`, and `044e2ce` exist in history.
- All 51 frozen cases are represented exactly once in lexicographic order by their family runner.

---
*Phase: 01-contract-and-device-proof*
*Completed: 2026-07-16*
