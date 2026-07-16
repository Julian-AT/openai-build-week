---
phase: 01-contract-and-device-proof
plan: "01"
subsystem: testing
tags: [json-schema, fixtures, jcs, sha256, coordinates, rrfp]

requires: []
provides:
  - Closed FixtureManifestV1 and RunnerResultV1 envelopes
  - Immutable CON-001 through CON-005 contract oracle revision
  - Immutable RR-JCS-SHA256-1 and RR-COORD-1 oracle revisions
affects: [01-02, 01-03, swift-runtime, typescript-runtime, python-runtime]

tech-stack:
  added: []
  patterns: [closed JSON Schema envelopes, immutable hash-bound oracle revisions, lexicographic stable case ordering]

key-files:
  created:
    - fixtures/runner-result.schema.json
    - fixtures/contracts/1.0.0/rev-001/manifest.json
    - fixtures/policies/RR-JCS-SHA256-1/rev-001/manifest.json
    - fixtures/policies/RR-COORD-1/rev-001/manifest.json
  modified:
    - fixtures/manifest.schema.json

key-decisions:
  - "Checked-in declarative inputs, expected bytes, digests, and rejection classes are the oracle; verification cannot regenerate them."
  - "Every case and canonical schema reference is byte-length and SHA-256 bound with lexicographic stable case ordering."

patterns-established:
  - "Fixture revisions are closed, immutable, and language-neutral."
  - "RRFP-WIRE-1 vectors encode one exact 24-byte header followed by JCS header bytes and payload bytes, with no trailer."

requirements-completed: [NFR-CONTRACT-001, NFR-COORD-001]

coverage:
  - id: D1
    description: "Closed, bounded fixture-manifest and runner-result schemas for all runtime consumers."
    requirement: NFR-CONTRACT-001
    verification:
      - kind: unit
        ref: "python3 -m unittest tests.test_fixture_meta_schemas -v"
        status: pass
    human_judgment: false
  - id: D2
    description: "Three immutable rev-001 corpora containing 51 hash-bound contract, JCS, coordinate, and RRFP cases."
    requirement: NFR-COORD-001
    verification:
      - kind: other
        ref: "manifest/schema/hash/JCS/RRFP integrity audit documented in 01-01-SUMMARY.md"
        status: pass
    human_judgment: false

duration: 10min
completed: 2026-07-16
status: complete
---

# Phase 1 Plan 01: Immutable Contract Oracle Summary

**Closed test envelopes and 51 immutable, hash-bound vectors now freeze the language-neutral contract, canonical JSON, coordinate, and RRFP behavior.**

## Performance

- **Duration:** 10 min
- **Started:** 2026-07-16T11:03:06Z
- **Completed:** 2026-07-16T11:13:06Z
- **Tasks:** 2
- **Files modified:** 84

## Accomplishments

- Defined closed Draft 2020-12 schemas for immutable fixture manifests and normalized three-runtime results, including explicit bounds and mutation case kinds.
- Added positive and negative CON-001 through CON-005 vectors, named compatibility migration cases, raw parser-differential inputs, and all five canonical schema hashes.
- Added exact JCS bytes and lowercase digests plus coordinate, RR-FLOAT-1, and complete RRFP-WIRE-1 framing/rejection vectors.

## Task Commits

Each task was committed atomically:

1. **Task 1: Define closed fixture and runner-result manifests** - `7637be0` (test), `b0a01da` (feat)
2. **Task 2: Author immutable rev-001 oracle cases** - `59e2e05` (test)

**Plan metadata:** recorded by the closeout commit containing this summary.

## Files Created/Modified

- `fixtures/manifest.schema.json` - Closed FixtureManifestV1/FixtureCaseV1 envelope and expected-artifact validation.
- `fixtures/runner-result.schema.json` - Closed normalized RunnerResultV1 envelope.
- `fixtures/contracts/1.0.0/rev-001/` - FX-CONTRACT-001 instances, mutation vectors, and manifest.
- `fixtures/policies/RR-JCS-SHA256-1/rev-001/` - FX-JCS-001 raw inputs, authoritative JCS bytes, and digests.
- `fixtures/policies/RR-COORD-1/rev-001/` - FX-COORD-001 coordinate/RR-FLOAT vectors and exact RRFP wire oracle.

## Decisions Made

- Followed D-09 through D-12: one language-neutral corpus, checked-in expectations as authority, stable invalid-case rejection classes, and immutable revisions.
- Represented bounded-length and other malformed RRFP cases as declarative mutations over the exact valid frame, preserving a single authoritative wire byte vector.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Corrected closed expected-artifact schema composition**

- **Found during:** Task 2 (Author immutable rev-001 oracle cases)
- **Issue:** Combining a closed file-reference schema with another closed artifact schema via `allOf` made every concrete artifact invalid under Draft 2020-12.
- **Fix:** Defined the expected-artifact fields directly in one closed object and added explicit JSON/wire mutation case kinds required by the corpus.
- **Files modified:** `fixtures/manifest.schema.json`
- **Verification:** Seven meta-schema tests pass and all three concrete manifests validate.
- **Committed in:** `59e2e05`

---

**Total deviations:** 1 auto-fixed (1 blocking correctness issue)
**Impact on plan:** The fix was limited to making the planned closed schema validate its planned concrete oracle cases; no product or canonical contract scope changed.

## Issues Encountered

- Recovered a legal partial execution after Task 1 had committed and Task 2 files were uncommitted. The existing Task 1 commits were preserved, Task 2 was independently audited, and tracking metadata was kept out of the fixture commit.

## Verification Evidence

- `python3 -m unittest tests.test_fixture_meta_schemas -v`: 7 tests passed.
- Both meta-schemas parse as JSON and the manifest schema validates under Draft 2020-12.
- Three manifests contain 51 unique lexicographically ordered cases; every referenced file, byte length, SHA-256, and canonical schema hash matches.
- Five positive contract instances validate against CON-001 through CON-005.
- Every accepted JCS vector hashes to its checked-in lowercase digest.
- RRFP valid bytes decode to exactly 1,851 bytes with the 24-byte big-endian fixed header, 1,823-byte JCS header, 4-byte payload, duplicate sequence/length agreement, and exact payload digest.
- Fixture secret-pattern scan and `git diff --check` passed.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Plan 01-02 can consume the frozen oracle without runtime-specific expectations.
- No canonical mismatch or unresolved blocker remains for this plan.

---
*Phase: 01-contract-and-device-proof*
*Completed: 2026-07-16*
