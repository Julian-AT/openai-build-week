---
phase: 01-contract-and-device-proof
plan: "08"
subsystem: contract-tooling
tags: [swift, json-schema, draft-2020-12, compatibility, fail-closed, tdd]

requires:
  - phase: 01-contract-and-device-proof
    provides: Human-approved exact Swift dependency and reproducible SwiftPM lock from Plan 01-04
  - phase: 01-contract-and-device-proof
    provides: Immutable contract oracle and fresh JavaScript/Python parity from Plans 01-01 and 01-07
provides:
  - Swift agreement with every frozen CON-001 through CON-005 reference verdict
  - Measured and documented 35-keyword Draft 2020-12 frozen validation profile
  - Typed fail-closed Swift contract boundary with exact schema selection and bounded input
affects: [01-09, 01-10, swift-runtime, mode-a-capture, three-runtime-agreement]

tech-stack:
  added: []
  patterns: [frozen schema keyword profile, exact schema registry, typed rejection verdicts, bounded pre-parse validation]

key-files:
  created:
    - ios/Packages/ReRoomContracts/Sources/ReRoomContracts/FrozenSchemaValidator.swift
    - ios/Packages/ReRoomContracts/Sources/ReRoomContracts/ContractValidation.swift
    - ios/Packages/ReRoomContracts/Tests/ReRoomContractsTests/ContractValidationTests.swift
    - evidence/compatibility/swift-schema-validation.json
  modified:
    - ios/Packages/ReRoomContracts/Package.swift
    - docs/canonical/RESEARCH_LEDGER.md

key-decisions:
  - "The Swift validator accepts only the exact 35-keyword surface used by the five frozen 1.0 schemas; unknown keywords and remote/dynamic resolution fail before compilation."
  - "swift-json-schema remains pinned at approved 0.13.1/f299eb1, while a bounded RFC 3339 date-time checker replaces its fractional-seconds-only helper for reference parity."
  - "Public validation requests keep schema ID, version, and hash as untrusted strings, while construction requires all five canonical schemas at exact registered hashes."
  - "Consumers may lower the 32 MiB/64-depth limits but cannot raise them, and the API returns verdicts without coercing, defaulting, or returning transformed documents."

requirements-completed: [NFR-CONTRACT-001]

coverage:
  - id: D1
    description: "Swift supports the entire frozen five-schema keyword surface, rejects unsupported schema behavior, and agrees with every JavaScript/Python reference verdict and rejection class."
    requirement: NFR-CONTRACT-001
    verification:
      - kind: integration
        ref: "swift test --package-path ios/Packages/ReRoomContracts --filter ContractValidationTests#frozen oracle, keyword surface, unsafe schema probes, benchmark"
        status: pass
      - kind: integration
        ref: "scripts/run-reference-parity#FX-CONTRACT-001 fresh JavaScript/Python reference agreement"
        status: pass
    human_judgment: false
  - id: D2
    description: "Swift consumers receive one bounded typed API that requires an allowlisted ID/version/hash and rejects spoofing, tamper, oversized/deep input, coercion candidates, and extra properties."
    requirement: NFR-CONTRACT-001
    verification:
      - kind: integration
        ref: "ios/Packages/ReRoomContracts/Tests/ReRoomContractsTests/ContractValidationTests.swift#typed boundary and tamper/limit tests"
        status: pass
    human_judgment: false

duration: 21min
completed: 2026-07-16
status: complete
---

# Phase 01 Plan 08: Swift Frozen-Schema Validation Summary

**Swift now validates the exact five closed 1.0 schemas with full frozen-oracle agreement and exposes a hash-bound, size/depth-bounded, noncoercing contract API.**

## Performance

- **Duration:** 21 min
- **Started:** 2026-07-16T22:24:51Z
- **Completed:** 2026-07-16T22:46:08Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments

- Bound the already approved `swift-json-schema` `0.13.1` package to revision `f299eb1cce78b2dd736d9a390ec0779d28678416`, enumerated all 35 keywords used by CON-001 through CON-005, and proved exact agreement across all 18 frozen cases and 12 rejection classes.
- Added fail-closed schema preflight for unknown keywords, nested identifiers, nonlocal references, and dynamic resolution, plus explicit `date-time` and `uri` assertions and the existing semantic/path/numeric/digest boundaries required by the oracle.
- Added a public five-schema registry and typed validation request/verdict API that requires exact ID, version, and SHA-256; enforces configurable-but-never-wider 32 MiB and depth-64 limits; and returns no coerced/defaulted document.
- Recorded exact package/license/artifact provenance, schema hashes, environment, raw benchmark digest, metric calculation, evaluator, fallback, and a MEASURED 2.507663833-second 20-repetition corpus result against the 10-second plan-local timebox.

## Task Commits

Each task was committed as a failing specification followed by its passing implementation:

1. **Task 1 RED: Frozen Swift schema decision specification** - `7bae7fc` (test)
2. **Task 1 GREEN: Frozen schema validator and compatibility evidence** - `050fbc7` (feat)
3. **Task 2 RED: Bounded typed validation API specification** - `57b8e6a` (test)
4. **Task 2 GREEN: Exact registry and typed validation boundary** - `774bd96` (feat)

**Plan metadata:** recorded by the closeout commit containing this summary.

## Files Created/Modified

- `ios/Packages/ReRoomContracts/Package.swift` - Added the Swift Testing target while preserving the exact approved package requirement.
- `ios/Packages/ReRoomContracts/Sources/ReRoomContracts/FrozenSchemaValidator.swift` - Compiles the frozen Draft 2020-12 profile, rejects unsupported resolution/keywords, and matches the reference semantic/rejection boundary.
- `ios/Packages/ReRoomContracts/Sources/ReRoomContracts/ContractValidation.swift` - Public exact-registry request/verdict API with hash, byte, and nesting controls.
- `ios/Packages/ReRoomContracts/Tests/ReRoomContractsTests/ContractValidationTests.swift` - Parameterized Swift Testing coverage for the full oracle, schema surface, benchmark, selection spoofing, tamper, bounds, coercion, and closed objects.
- `evidence/compatibility/swift-schema-validation.json` - Reproducible dependency, profile, agreement, environment, benchmark, evaluator, raw-evidence digest, and fallback record.
- `docs/canonical/RESEARCH_LEDGER.md` - Added `CLM-040` for the exact pinned Swift validation result and its limits.

## Decisions Made

- Limited the eligible schema language to what the immutable 1.0 corpus actually uses instead of treating the package's broader support as implicit approval.
- Required every `$ref` to be `#` or a local JSON Pointer fragment and rejected dynamic keywords before the dependency can resolve anything.
- Kept untrusted selection fields as strings at the public request boundary so unknown IDs and versions produce explicit stable rejection verdicts rather than becoming unrepresentable inputs.
- Required validator construction to receive the complete five-schema set at the manifest's exact SHA-256 values; duplicate, incomplete, stale-version, tampered, or invalid registries fail construction.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Replace the package's fractional-seconds-only date-time helper**
- **Found during:** Task 1 GREEN (frozen valid-instance agreement)
- **Issue:** The pinned package's built-in `date-time` helper rejected canonical whole-second RFC 3339 values such as `2026-07-16T00:00:00Z`, while both approved reference runtimes accepted them.
- **Fix:** Supplied a bounded local `date-time` validator accepting both whole and fractional internet timestamps; retained the package for all schema semantics and kept the profile limited to canonical formats.
- **Files modified:** `FrozenSchemaValidator.swift`, compatibility evidence, research ledger.
- **Verification:** Five of five valid instances and all 18 frozen verdicts/12 rejection classes agree.
- **Committed in:** `050fbc7`

---

**Total deviations:** 1 auto-fixed bug.
**Impact on plan:** The correction restores canonical/reference parity without changing a schema, fixture, version, dependency, compatibility policy, or product boundary.

## Issues Encountered

- Context7 had no entry for this exact package, so current-library review used the official source and documentation from the audited immutable `v0.13.1` checkout instead.
- GSD health remains degraded only by the pre-existing non-repairable `adaptive` model-profile warning. Consistency passes with expected notices for future phase directories.

## Verification Evidence

- The exact filtered Swift test command passes twice: 9 tests, including 3 parameterized unsafe-schema cases and 3 parameterized selection-spoofing cases.
- Fresh reference parity passes for `FX-CONTRACT-001`, `FX-JCS-001`, and `FX-COORD-001` across the JavaScript and Python runners with unchanged oracle hashes.
- Exact dependency closure verification passes for all 6 approved roots and 10 audited transitives; SwiftPM remains locked to `swift-json-schema` `0.13.1` at `f299eb1`.
- `evidence/compatibility/swift-schema-validation.json` parses, contains 35 unique keywords, and its embedded compact raw benchmark reproduces SHA-256 `a7220bfa2ce37a25b76554acd2559f57c73eadf52033fe8d31d3ca68c4da05a4`.
- No physical-device, signing, ARKit, compositor, thermal, human, cloud, deployment, or publication evidence is claimed.

## User Setup Required

None - consumers supply the five canonical schema bytes already frozen in the repository, and package resolution uses the committed exact lock.

## Next Phase Readiness

- Ready for Plan 01-09 to implement Swift JCS, RRFP, path, and RR-COORD-1 policies over the same immutable corpus.
- Plan 01-10 can later consume this typed boundary for final three-runtime agreement; D-12 and all physical/human gates remain pending until their named plans produce real evidence.

## Self-Check: PASSED

- All six declared implementation/evidence files exist, and Package.resolved remains at the audited exact revision.
- Task commits `7bae7fc`, `050fbc7`, `57b8e6a`, and `774bd96` exist in history.
- Required Swift tests, reference parity, dependency verification, evidence-digest check, GSD consistency, and `git diff --check` pass.

---
*Phase: 01-contract-and-device-proof*
*Completed: 2026-07-16*
