---
phase: 05-curated-replacement-vertical
plan: "04"
subsystem: replacement-evidence
tags: [python, mutation-testing, realitykit, evidence, atomic-publication]
requires:
  - phase: 05-curated-replacement-vertical
    provides: supported native replacement journey and retained exact local USDA from Plan 03
  - phase: 04-target-grounding-and-compositor-gate
    provides: fail-closed quick/full evidence publication pattern
provides:
  - Mutation-tested quick/full Phase 5 replacement verifier
  - Closed source binding to Phase 5 implementation revision ba04382
  - Atomic sanitized automated replacement preflight evidence
  - Explicitly pending physical, parity, license, transaction-campaign, and golden gates
affects: [phase-06-remove, phase-08-hardening, physical-device-uat, release-evidence]
tech-stack:
  added: []
  patterns: [closed check manifest, immutable product digest binding, atomic evidence replacement, mutation-tested honesty boundary]
key-files:
  created:
    - scripts/verify-phase-05-replacement
    - tools/verify/tests/test_phase_05_replacement.py
    - evidence/replacement/phase-05/automated-preflight.json
  modified: []
key-decisions:
  - "Phase 5 evidence binds product sources and exact asset metadata to ba04382 even when unrelated later commits advance repository HEAD."
  - "The full report publishes only after every ordered check passes; simulator or publication failure preserves the prior report and returns failure."
  - "The only accepted claim is automated sprint replacement slice passed; every formal physical, license/parity, transaction, and golden gate remains PENDING."
patterns-established:
  - "Retained RealityKit loading is source-bound by exact asset name, single load count, coordinator setup location, clone reuse, six-entity count, and fail-closed injection seam."
  - "Generated box geometry may satisfy target coverage only and is mutation-rejected as a replacement success substitute."
requirements-implemented: [FR-REPLACE-001]
coverage:
  - id: D1
    description: Mutation-tested fail-closed Phase 5 quick/full verifier
    requirement: FR-REPLACE-001
    verification:
      - kind: unit
        ref: "python3 -m unittest tools.verify.tests.test_phase_05_replacement"
        status: pass
    human_judgment: false
  - id: D2
    description: Source-bound reducer, authority, model, asset, retained-loader, and render-independence quick checks
    requirement: FR-REPLACE-001
    verification:
      - kind: integration
        ref: "scripts/verify-phase-05-replacement quick"
        status: pass
    human_judgment: false
  - id: D3
    description: Atomic sanitized evidence after three replacement UI cases, Debug/Release builds, release surface, secret scan, and whitespace check
    requirement: FR-REPLACE-001
    verification:
      - kind: e2e
        ref: "scripts/verify-phase-05-replacement full"
        status: pass
    human_judgment: false
  - id: D4
    description: Physical-device loading, compositor quality, license approval, native/web parity, formal transaction campaign, and complete golden acceptance
    requirement: FR-REPLACE-001
    verification: []
    human_judgment: true
    rationale: "The automated simulator preflight is deliberately insufficient for GATE-011, GATE-003, GATE-005, GATE-009, or OPS-GOLDEN-001 acceptance."
duration: 11min
completed: 2026-07-18
status: complete
---

# Phase 5 Plan 04: Replacement Evidence Summary

**A mutation-tested fail-closed verifier now binds the complete automated replacement slice to `ba04382`, publishes one canonical report atomically, and prevents simulator success from promoting deferred physical or formal gates.**

## Performance

- **Duration:** 11 min
- **Started:** 2026-07-18T20:46:55+02:00
- **Completed:** 2026-07-18T20:57:23+02:00
- **Tasks:** 2
- **Files created:** 3

## Accomplishments

- Added quick verification for the replace reducer, sole branch authority/restore, native model, exact source contract, asset contract, production dependency boundary, render independence, and mutation suite.
- Added full verification for the exact bundled replacement journey, five deterministic fixture iterations, injected loader failure, Debug/Release simulator builds, release surface, tracked secrets, and whitespace.
- Bound the local proxy and Phase 5 app source set to `ba04382fbc03e0065ff9e943bc9b007b04318692`, including exact digest/provenance metadata and the six-entity retained RealityKit load contract.
- Published a sanitized canonical JSON report only after all 16 ordered checks passed, with a self-digest and atomic replacement protocol.

## Task Commits

1. **Task 1 RED:** `2587d1c` — failing mutation contract for replacement evidence.
2. **Task 1 GREEN:** `6f6bbed` — quick/full source-bound fail-closed verifier.
3. **Task 2:** `2830318` — atomically published full automated preflight evidence.

## Verification

- `python3 -m unittest tools.verify.tests.test_phase_05_replacement`: **9 tests passed**.
- `scripts/verify-phase-05-replacement quick`: **passed**.
- `scripts/verify-phase-05-replacement full`: **passed and published**.
- Full functional inventory: **16 checks**, **1** full replacement journey, **5** deterministic fixture runs, **1** injected load-failure run, **2** build configurations, **1** exact retained asset load per coordinator, **6** asset model entities, and **0** command-time network requests.
- Final evidence schema/self-digest validation, JSON parse, focused evidence secret/machine-path scan, and `git diff --check`: **passed**.

## Mutation Coverage

The suite rejects:

- every missing or reordered check;
- visibility/asset operation removal, duplication, or reordering;
- missing captured-exact inverse, idempotency, restart, restore, revocation, or loader-failure tests;
- wrong, repeated, or per-update USDA loading;
- generated-box replacement substitution;
- load-failure readiness promotion;
- asset digest, closed metadata, provenance, license/parity, or gate drift;
- green formal gates, physical/parity overclaims, private/raw fields, source drift, incomplete reports, and self-digest tampering;
- partial publication when atomic replacement fails.

## Decisions Made

- Kept the Phase 5 product revision immutable at `ba04382` and stored closed product digests in the verifier. Concurrent unrelated Phase 7/8 commits may advance repository HEAD but cannot redefine Phase 5 evidence.
- Recorded both the fixed implementation revision and the exact repository parent observed at publication. The latter is provenance only; all acceptance semantics come from the fixed source bindings.
- Treated simulator asset loading as local wiring evidence only. The report does not claim physical-device loading, visual quality, performance, thermal behavior, approved redistribution, or derivative parity.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Test contract bug] Corrected source tokens to the implemented Swift test and launch-seam names**

- **Found during:** Task 1 GREEN mutation run.
- **Issue:** Initial mutation expectations used descriptive names rather than the existing Swift identifiers and assumed a direct `CommandLine` launch check.
- **Fix:** Bound the verifier to the actual reducer/authority test identifiers, captured-exact assertion, `ProcessInfo` launch configuration, and replacement render structure.
- **Verification:** All nine mutation tests passed, followed by quick and full verifier passes.
- **Committed in:** `6f6bbed`.

**2. [Rule 1 - Honesty scanner bug] Narrowed the full-P0 overclaim pattern**

- **Found during:** Task 1 GREEN report validation.
- **Issue:** The scanner rejected the required limitation sentence saying the report does not establish full P0 completion.
- **Fix:** Restricted rejection to affirmative `full P0 passed/complete` claims while preserving the negative limitation.
- **Verification:** Valid reports pass; affirmative physical/parity overclaim mutations still fail.
- **Committed in:** `6f6bbed`.

**Total deviations:** 2 auto-fixed test/verifier correctness issues.
**Impact on plan:** Both changes strengthened exact binding and prevented a false rejection; no product source, dependency, PBX, or gate status changed.

## Issues Encountered

- Repository HEAD advanced through unrelated concurrent Phase 7/8 commits during the full run. The report's implementation revision and seven product/asset digests remain fixed to `ba04382`; the separately recorded verification parent preserves the actual publication context without changing Phase 5 authority.
- CoreSimulator completed all three isolated Phase 5 UI cases on this full attempt. No simulator result was converted into physical-device evidence.

## Known Stubs

None. Empty dictionaries/lists in the verifier are local accumulators populated within the same execution path, not shipped placeholder data.

## Threat Flags

None. The verifier reads repository-owned sources, invokes local build/test tools, scans tracked files, and atomically writes one sanitized evidence file; it adds no network, authentication, cloud, or user-data boundary.

## User Setup Required

None.

## Next Phase Readiness

- Phase 6 app work can proceed without modifying or reinterpreting this revision-bound Phase 5 result.
- `GATE-011`, `GATE-003`, `GATE-005`, `GATE-009`, and `OPS-GOLDEN-001` remain exactly `PENDING` and require their canonical future evidence.
- `FR-REPLACE-001` has an automated sprint-slice pass but is not a full P0/release acceptance claim while those gates remain pending.

## Self-Check: PASSED

- Verifier, mutation suite, and evidence file exist.
- RED/GREEN/evidence commits `2587d1c`, `6f6bbed`, and `2830318` exist.
- Evidence validates against its closed schema, fixed product digests, exact pending gates, and canonical self-digest.
- Quick, full, mutation, JSON, secret/machine-path, and whitespace checks passed.

---
*Phase: 05-curated-replacement-vertical*
*Completed: 2026-07-18*
