---
phase: 01-contract-and-device-proof
plan: "10"
subsystem: three-runtime-contract-agreement
tags: [swift, javascript, python, contracts, jcs, coordinates, evidence]

requires:
  - phase: 01-contract-and-device-proof
    provides: Immutable contract, JCS, wire, and coordinate fixtures plus independent JavaScript/Python runners from Plans 01-01 through 01-07
  - phase: 01-contract-and-device-proof
    provides: Bounded Swift contract validation and serialization/coordinate policies from Plans 01-08 and 01-09
provides:
  - Normalized bounded Swift runner for all three immutable fixture families
  - Fresh isolated three-runtime agreement gate requiring exact oracle and cross-runtime parity
  - Reproducible MEASURED contract, JCS, and coordinate reports bound to raw-result, schema, source-tree, evaluator, and implementation digests
affects: [01-11, 01-14, mode-a-capture, release-preflight, physical-device-gates]

tech-stack:
  added: []
  patterns: [digest-bound immutable manifests, normalized runner envelopes, exclusive fresh outputs, atomic evidence publication, revision-bound reproducibility]

key-files:
  created:
    - ios/Packages/ReRoomContracts/Sources/ReRoomContractRunner/main.swift
    - ios/Packages/ReRoomContracts/Tests/ReRoomContractsTests/RunnerTests.swift
    - scripts/run-three-runtime-agreement
    - evidence/compatibility/contract-agreement.json
    - evidence/compatibility/jcs-agreement.json
    - evidence/compatibility/coordinate-agreement.json
  modified:
    - ios/Packages/ReRoomContracts/Package.swift

key-decisions:
  - "The Swift runner accepts only the exact checked-in manifest digests for FX-CONTRACT-001, FX-JCS-001, and FX-COORD-001, so an omitted or altered corpus cannot redefine its own oracle."
  - "All runtime outputs are labeled with the common git revision 3e3adda8d11a871fe721d03ec78e2706bcbf44c5 and the harness fails if any bound implementation or oracle source differs from that revision."
  - "Agreement reports are atomically replaced only after every fresh Swift, JavaScript, and Python result passes the closed comparator with all three runtimes required."
  - "Raw outputs remain ephemeral; their exact byte digests and normalized result digests provide durable, reproducible evidence without retaining path-bearing temporary artifacts."

requirements-completed: [NFR-CONTRACT-001, NFR-COORD-001]

coverage:
  - id: D1
    description: "The Swift runner emits complete stable RunnerResultV1 envelopes for every immutable contract, JCS, wire, and coordinate case and rejects omitted, duplicate, or unknown manifests."
    requirement: NFR-CONTRACT-001
    verification:
      - kind: integration
        ref: "swift build --package-path ios/Packages/ReRoomContracts --product ReRoomContractRunner && swift test --package-path ios/Packages/ReRoomContracts --filter RunnerTests"
        status: pass
      - kind: regression
        ref: "swift test --package-path ios/Packages/ReRoomContracts#31 tests in 5 suites"
        status: pass
    human_judgment: false
  - id: D2
    description: "Swift, JavaScript, and Python agree on all 51 frozen cases with zero missing, extra, verdict, rejection-class, artifact, or oracle mismatches and revision-bound MEASURED evidence."
    requirement: NFR-COORD-001
    verification:
      - kind: integration
        ref: "scripts/run-three-runtime-agreement && scripts/verify-phase-01-contracts references"
        status: pass
      - kind: mutation
        ref: "node --test tools/javascript/test/parity-mutations.test.mjs && .venv/bin/python -m unittest tools.python.tests.test_parity_mutations tools.verify.tests.test_reference_parity -v"
        status: pass
    human_judgment: false

duration: 18min
completed: 2026-07-16
status: complete
---

# Phase 01 Plan 10: Three-Runtime Contract Agreement Summary

**Swift, JavaScript, and Python now agree exactly on all 51 immutable contract, JCS, RRFP, and coordinate cases, with reproducible revision-bound MEASURED reports and fail-closed mutation coverage.**

## Performance

- **Duration:** 18 min
- **Started:** 2026-07-16T23:15:06Z
- **Completed:** 2026-07-16T23:33:00Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments

- Added the `ReRoomContractRunner` SwiftPM executable product/target, which reuses the pure frozen contract, canonical JSON, coordinate, archive-path, and RRFP policy modules.
- Added bounded manifest/schema/file loading, exact immutable-manifest digest authorization, safe containment, normalized stable rejections, lexicographic complete case output, exclusive result creation, and exact RunnerResultV1 digest scope.
- Added Swift Testing coverage for byte-stable complete JCS output and fail-closed omitted, duplicate, and unknown manifest mutations.
- Added a three-runtime harness that builds the Swift runner, creates fresh exclusive Swift/JavaScript/Python outputs, validates every result with the shared comparator, protects oracle bytes before/after execution, and writes reports only after all fixtures pass.
- Recorded sanitized MEASURED reports for 18 contract, 12 JCS, and 21 coordinate/wire cases with common implementation revision, source-tree/schema/evaluator hashes, raw-result digests, commands, environment, metric calculation, and zero mismatch counts.

## Task Commits

Task 1 used a failing specification followed by its passing implementation; Task 2 recorded the verified integration evidence:

1. **Task 1 RED: Swift runner behavior specification** - `7f9abd4` (test)
2. **Task 1 GREEN: Normalized Swift contract runner** - `3e3adda` (feat)
3. **Task 2: Three-runtime agreement harness and reports** - `aef8ffe` (feat)

**Plan metadata:** recorded by the closeout commit containing this summary.

## Files Created/Modified

- `ios/Packages/ReRoomContracts/Package.swift` - Registers the `ReRoomContractRunner` executable product/target with a `ReRoomContracts` dependency.
- `ios/Packages/ReRoomContracts/Sources/ReRoomContractRunner/main.swift` - Bounded immutable-fixture loader, family dispatcher, normalized result builder, CLI, and exclusive writer.
- `ios/Packages/ReRoomContracts/Tests/ReRoomContractsTests/RunnerTests.swift` - Stable complete-output and omitted/duplicate/unknown manifest coverage using parameterized Swift Testing cases.
- `scripts/run-three-runtime-agreement` - Revision-bound fresh-output executor, three-runtime comparator, oracle guard, report builder, and atomic publisher.
- `evidence/compatibility/contract-agreement.json` - MEASURED 18-case contract agreement and raw-result bindings.
- `evidence/compatibility/jcs-agreement.json` - MEASURED 12-case canonicalization/digest agreement and raw-result bindings.
- `evidence/compatibility/coordinate-agreement.json` - MEASURED 21-case RR-COORD-1/RRFP agreement and raw-result bindings.

## Decisions Made

- Bound accepted manifests to exact known fixture IDs, revisions, subjects, and byte digests, which is stronger than trusting a self-described altered manifest and makes omission a loader failure.
- Reused the public pure Swift policy boundaries and kept fixture orchestration in the executable, leaving validation, JCS, coordinate, wire, and path meaning in their existing deterministic modules.
- Bound all three runners to the Swift implementation commit and recorded a deterministic digest of every tracked source in the declared revision scope; later bound-source drift fails before runner execution.
- Kept raw output files in an exclusive temporary directory while retaining both their exact file SHA-256 and their self-authenticating RunnerResultV1 digest in durable reports.

## Deviations from Plan

None - the plan was executed as written.

## Issues Encountered

- GSD health remains degraded only by the pre-existing non-repairable `adaptive` model-profile warning. Consistency passes; health notices only the future Plan 01-11 through 01-14 summaries as pending.

## Verification Evidence

- The exact Task 1 command builds `ReRoomContractRunner` and passes 2 runner tests, including all 3 parameterized invalid-manifest variants.
- The exact Task 2 command and repository `references` gate pass twice from fresh isolated output sets; all three generated report files reproduce byte-for-byte.
- Three runtimes agree on 51 cases: 23 accepts and 28 stable rejects, with zero missing, extra, verdict, rejection-class, artifact, or oracle mismatches.
- The complete Swift package passes 31 tests in 5 suites, including the prior bounded contract validation, JCS, wire, path, and coordinate suites.
- The JavaScript mutation suite passes its complete contract/JCS/RRFP/path/coordinate matrix; all 4 Python runtime/comparator integration and mutation tests pass.
- Tracked secret scanning, `git diff --check`, GSD consistency, and report sanity checks pass. GSD health has no errors or repairable warnings.
- No physical-device, signing, ARKit, camera, thermal, human, cloud, deployment, or publication evidence is claimed.

## User Setup Required

None - the harness uses the existing locked Swift, Node.js, and Python environments and adds no dependency.

## Next Phase Readiness

- Contract and coordinate compatibility evidence is ready for the later automated release preflight and device-proof slices.
- Plan 01-11 can proceed with the typed semantic planner boundary; physical-device and human gates remain pending until their named plans collect real evidence.

## Self-Check: PASSED

- All seven declared source/test/script/report files exist, the executable script is tracked with mode `100755`, and all three task commits are present in history.
- Both exact task commands, the complete Swift package, fresh three-runtime reports, mutation gates, secret scan, GSD consistency, and `git diff --check` pass.
- SwiftPM build artifacts were removed with `swift package reset`; the worktree was clean before this summary was written.

---
*Phase: 01-contract-and-device-proof*
*Completed: 2026-07-16*
