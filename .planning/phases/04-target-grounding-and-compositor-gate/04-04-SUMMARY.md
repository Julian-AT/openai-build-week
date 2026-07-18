---
phase: 04-target-grounding-and-compositor-gate
plan: "04"
subsystem: verification
tags: [python, xcodebuild, swift-testing, xcuitest, evidence, fail-closed]

requires:
  - phase: 04-target-grounding-and-compositor-gate
    plan: "03"
    provides: Native manual target, shared-session raycast, exact compositor descriptor, and recovery UI
provides:
  - One quick/full fail-closed verifier for the Phase 4 sprint fallback slice
  - Mutation coverage for all checks, exact six-layer order, unavailable layers, dependency boundaries, claims, privacy, and atomic publication
  - Sanitized revision-bound automated evidence with five formal gates explicitly PENDING
affects: [phase-05-replace, phase-06-remove, native-compositor, sprint-evidence]

tech-stack:
  added: []
  patterns:
    - Atomic evidence publication only after a closed ordered check manifest passes
    - Stable semantic outcome digests separated from raw nondeterministic Xcode logs
    - Unique simulator reboot with serialized Xcode jobs and explicit CoreSimulator Busy failure

key-files:
  created:
    - scripts/verify-phase-04-targeting
    - tools/verify/tests/test_phase_04_targeting.py
    - evidence/targeting/phase-04/automated-preflight.json
  modified: []

key-decisions:
  - "Bind Phase 4 evidence to product implementation commit 4d268ba and a closed digest set; verifier/evidence commits do not redefine product behavior."
  - "Record only automated sprint fallback behavior; GATE-003/004/005/007/012 remain exactly PENDING."
  - "Represent camera, reveal, occluder, asset/proxy, debug, and SwiftUI as an exact closed descriptor with reveal and occluder unavailable."
  - "Hash stable PASS semantics rather than private and nondeterministic raw Xcode logs."

patterns-established:
  - "Evidence boundary: quick mode never publishes and full mode atomically replaces only after all twelve checks pass."
  - "Claim boundary: HYPOTHESIS fallback evidence cannot contain MEASURED performance/provider claims, physical observations, paths, identifiers, room data, or credentials."

requirements-completed: [FR-TARGET-001, NFR-RENDER-001]

coverage:
  - id: D1
    description: "One command proves deterministic target reducers, AR raycast policy, exact compositor ordering, local render independence, UI recovery, Debug/Release builds, and release-surface compatibility."
    requirement: NFR-RENDER-001
    verification:
      - kind: integration
        ref: "scripts/verify-phase-04-targeting full"
        status: pass
      - kind: unit
        ref: "tools/verify/tests/test_phase_04_targeting.py"
        status: pass
    human_judgment: false
  - id: D2
    description: "The published report is source-bound, sanitized, selects manual/no-dense/local fallbacks, and keeps all five formal gates PENDING."
    requirement: FR-TARGET-001
    verification:
      - kind: integration
        ref: "evidence/targeting/phase-04/automated-preflight.json"
        status: pass
      - kind: unit
        ref: "tools/verify/tests/test_phase_04_targeting.py#test_closed_evidence_accepts_only_pending_fallback_report"
        status: pass
    human_judgment: false
  - id: D3
    description: "Physical camera compositing, signed-device visual/runtime campaigns, provider bake-off, and runtime-tier soak complete the formal Phase 4 gates."
    requirement: NFR-RENDER-001
    verification: []
    human_judgment: true
    rationale: "Simulator and static automation cannot fabricate the physical, provider, measurement, or human evidence required by GATE-003/004/005/007/012."

duration: 18min
completed: 2026-07-18
status: complete
---

# Phase 4 Plan 4: Targeting Fallback Preflight Summary

**A serialized fail-closed verifier now proves the automated target/compositor fallback slice and publishes only sanitized evidence with every formal Phase 4 gate still pending.**

## Performance

- **Duration:** 18 min
- **Started:** 2026-07-18T17:18:00Z
- **Completed:** 2026-07-18T17:36:00Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- Added quick/full verification covering 30 focused Swift tests, three native UI journeys, Debug and Release builds, the release surface, production dependency boundaries, tracked secrets, and whitespace.
- Added eight Python mutation tests that kill missing/reordered checks, every six-layer descriptor mutation family, unavailable-layer promotion, external production dependencies, evidence overclaims, private values, and partial publication.
- Published `automated-preflight.json` bound to `git:4d268ba88c1a8e10181bbd88faf306df1bd1d3d6`; its file SHA-256 is `7ed6fba8fe728849f92961700a8d2ebc930177df2ad336514d141b2f72cdc19a` and all five formal gates are `PENDING`.

## Task Commits

1. **Task 1 RED: Define fail-closed targeting preflight** - `f0e2eed`
2. **Task 1 GREEN: Enforce targeting evidence boundaries** - `9cae425`
3. **Task 2 RED: Require authoritative targeting evidence** - `4adaf31`
4. **Task 2 GREEN: Publish targeting fallback preflight** - `e32f149`

## Files Created/Modified

- `scripts/verify-phase-04-targeting` - Quick/full orchestration, source binding, simulator isolation, production audits, evidence validation, and atomic publication.
- `tools/verify/tests/test_phase_04_targeting.py` - Mutation and closed-report tests for checks, compositor layers, dependencies, privacy, claims, and publication.
- `evidence/targeting/phase-04/automated-preflight.json` - Sanitized automated fallback result with exact source digests and pending gates.

## Decisions Made

- Reused the Phase 3 evidence shape while narrowing source and claims to Phase 4 target/render boundaries.
- Stored stable semantic check outcomes instead of raw command output, preventing machine paths and nondeterministic simulator logs from entering evidence.
- Audited only production AR/raycast/representable paths for learned, network, web, and scripting dependencies; test fixtures remain allowed.
- Quick mode performs no publication, and post-commit quick verification proved the full evidence file remained byte-identical.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Reclaimed exact rebuildable ReRoom DerivedData**
- **Found during:** Task 1 preparation
- **Issue:** Less than 1 GB of disk remained, which could not safely support serialized Debug/Release and UI builds.
- **Fix:** Deleted only the rebuildable Xcode DerivedData entry `ReRoomDeviceProof-dxaqfvpdmentxkcpvaxawrgtxpkr`; Xcode rebuilt it during verification. No repository or user project files were removed.
- **Files modified:** None.
- **Verification:** Focused tests, UI tests, Debug build, and Release build all passed from the rebuilt cache.

**2. [Rule 1 - Test Bug] Made compositor mutations operate on a mutable descriptor copy**
- **Found during:** Task 1 GREEN
- **Issue:** Three mutation cases attempted to edit the canonical tuple directly and errored before exercising the validator.
- **Fix:** Converted the copied descriptor to a list before reorder, duplicate, and omission mutations.
- **Files modified:** `tools/verify/tests/test_phase_04_targeting.py`
- **Verification:** All six descriptor mutation families are rejected and all eight mutation tests pass.
- **Committed in:** `9cae425`

**3. [Rule 1 - Test Design] Avoided a circular first-publication requirement**
- **Found during:** Task 2 GREEN
- **Issue:** The RED test initially required the evidence file inside the mutation suite, but the full verifier must run that suite before atomically publishing its first evidence file.
- **Fix:** The pre-publication test now locks schema revision, exact twelve-check threshold, source revision, privacy, and pending gates through a valid in-memory report; the post-full command independently validates the published file.
- **Files modified:** `scripts/verify-phase-04-targeting`, `tools/verify/tests/test_phase_04_targeting.py`
- **Verification:** Full first publication passed; independent artifact validation and post-commit quick/mutation reruns passed without changing its SHA-256.
- **Committed in:** `e32f149`

---

**Total deviations:** 3 auto-fixed (2 correctness, 1 blocking environment constraint)
**Impact on plan:** No product scope or claim changed. The fixes preserved TDD, atomic publication, and the pending-gate boundary.

## Issues Encountered

- The first quick invocation failed closed during simulator startup and published nothing. An explicit serialized diagnostic run passed all 30 tests, and the subsequent authoritative quick and full invocations passed. No retry logic was added that could hide CoreSimulator Busy failures.
- Xcode rebuilt the exact removed cache and reduced free space again; future Xcode work may need the same narrowly scoped rebuildable-cache cleanup.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 5 may consume a verified stable target identity, shared-session raycast boundary, closed local compositor descriptor, and automated fallback evidence.
- `GATE-003`, `GATE-004`, `GATE-005`, `GATE-007`, and `GATE-012` remain pending real physical/provider/runtime evidence and cannot support measured or full-P0 claims.

## Self-Check: PASSED

- All three plan artifacts exist and all four TDD commits are present.
- Full, post-commit quick, mutation, source-binding, privacy, secret, release-surface, and whitespace checks passed.
- Evidence SHA-256 remained `7ed6fba8fe728849f92961700a8d2ebc930177df2ad336514d141b2f72cdc19a` after quick rerun.

---
*Phase: 04-target-grounding-and-compositor-gate*
*Completed: 2026-07-18*
