---
phase: 01-contract-and-device-proof
plan: "15"
subsystem: three-runtime-contract-agreement
tags: [swift, javascript, python, contracts, provenance, reproducibility]

requires:
  - phase: 01-contract-and-device-proof
    provides: Finalized post-review contract source tree and signed GREEN physical gate chain through Plan 01-14
provides:
  - Ordinary three-runtime publisher bound to the finalized post-review contract source revision
  - Current deterministic MEASURED contract, JCS, and coordinate agreement reports
  - Byte-stability and physical-evidence non-interference proof for the refreshed reports
affects: [02-atomic-capture-and-exact-replay, release-preflight, contract-compatibility-evidence]

tech-stack:
  added: []
  patterns: [non-self-referential-source-binding, deterministic-evidence-revisions, atomic-byte-stable-publication]

key-files:
  created: []
  modified:
    - scripts/run-three-runtime-agreement
    - evidence/compatibility/contract-agreement.json
    - evidence/compatibility/jcs-agreement.json
    - evidence/compatibility/coordinate-agreement.json

key-decisions:
  - "Bind the compatibility publisher to a5bff6896188dcac9397c48ce1a6820a7196011a because it is the last commit that changed any declared bound source path and those bytes remain identical at closeout."
  - "Advance the deterministic compatibility evidence run identities from _001 to _002 while leaving fixture revisions, source scopes, runtime identities, comparator policy, and metric meaning unchanged."
  - "Keep the signed candidate, automated preflight, GATE-013/GATE-002 reports and checklists, and external physical attestations byte-identical; this host-only provenance repair does not reinterpret physical observations."

requirements-completed: [NFR-CONTRACT-001, NFR-COORD-001]

coverage:
  - id: D1
    description: "The ordinary checked-in publisher accepts the exact finalized bound source tree and emits fresh three-runtime reports without overrides or bypasses."
    requirement: NFR-CONTRACT-001
    verification:
      - kind: integration
        ref: "scripts/run-three-runtime-agreement"
        status: pass
      - kind: integrity
        ref: "git log/diff over BOUND_SOURCE_SCOPES resolves to a5bff6896188dcac9397c48ce1a6820a7196011a with identical current bytes"
        status: pass
    human_judgment: false
  - id: D2
    description: "Contract, JCS, and coordinate reports share one nonempty source-tree digest, bind all three runtimes to the finalized revision, record zero disagreements, and reproduce byte-for-byte."
    requirement: NFR-COORD-001
    verification:
      - kind: integration
        ref: "scripts/verify-phase-01-contracts references && scripts/run-reference-parity"
        status: pass
      - kind: reproducibility
        ref: "second ordinary publication preserved all three report SHA-256 values"
        status: pass
      - kind: mutation
        ref: "JavaScript and Python parity mutation suites plus complete Swift package tests"
        status: pass
    human_judgment: false
  - id: D3
    description: "The complete tracked Phase 01 device-evidence chain and immutable fixture manifests remain byte-identical to the protected baseline."
    requirement: NFR-COORD-001
    verification:
      - kind: integrity
        ref: "git diff --quiet a5bff6896188dcac9397c48ce1a6820a7196011a HEAD -- evidence/device/phase-01"
        status: pass
      - kind: integrity
        ref: "fixture manifest SHA-256 and worktree comparisons"
        status: pass
    human_judgment: false

duration: 9min
completed: 2026-07-17
status: complete
---

# Phase 01 Plan 15: Finalized Three-Runtime Provenance Summary

**The ordinary Swift/JavaScript/Python publisher now binds the finalized post-review contract source tree and reproduces current zero-disagreement MEASURED reports byte-for-byte without changing any signed physical evidence.**

## Performance

- **Duration:** 9 min
- **Started:** 2026-07-17T15:48:55Z
- **Completed:** 2026-07-17T15:57:44Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Proved `a5bff6896188dcac9397c48ce1a6820a7196011a` is the latest commit that changed any existing `BOUND_SOURCE_SCOPES` path and that the complete scoped source tree is byte-identical between that commit and closeout HEAD.
- Rebound the ordinary publisher to that exact non-self-referential source revision and advanced the three deterministic evidence run identities to `_002` without changing source scope, fixtures, schema hashes, runtime policy, rejection meaning, or comparator rules.
- Published current reports for 18 contract, 12 JCS, and 21 coordinate/wire cases. All share source-tree digest `7186a0a61c57d2073cdd475b8c8dc877647c1ce88b2e8bec5f87a73395d83ce7`, bind Swift/JavaScript/Python raw results to the same implementation revision, and record zero missing, extra, verdict, rejection-class, artifact, or oracle disagreements.
- Re-ran the ordinary publisher and reproduced all three report files byte-for-byte.
- Passed the focused reference, fixture-integrity, cross-runtime mutation, complete Swift package/concurrency, dependency, roadmap, planning-health, tracked-secret, and diff gates while preserving the complete signed physical-evidence directory.

## Task Commits

1. **Task 1: Rebind and regenerate the three compatibility reports** - `9c89123` (fix)
2. **Task 2: Prove byte stability, focused regressions, and physical-evidence non-interference** - `93288db` (test)

**Plan metadata:** recorded by the closeout commit containing this summary.

## Files Created/Modified

- `scripts/run-three-runtime-agreement` - Pins the finalized source revision and deterministic `_002` evidence run identity.
- `evidence/compatibility/contract-agreement.json` - Current 18-case CON-001 through CON-005 three-runtime agreement report; SHA-256 `4fd1379adf2f3c95789ebb7fc487735929fff622dfa3e51cf4abe3a35f18140c`.
- `evidence/compatibility/jcs-agreement.json` - Current 12-case RR-JCS-SHA256-1 three-runtime agreement report; SHA-256 `465fdaaf9a0a44d179268fced7ac8173f3d478613224b7e2e557ecf434f29748`.
- `evidence/compatibility/coordinate-agreement.json` - Current 21-case RR-COORD-1/RRFP-WIRE-1 three-runtime agreement report; SHA-256 `5111ce0c2efe70fef8772593eaaf41d8add47fa6f54dd08b246e07825ca3037f`.

## Decisions Made

- Selected the last source-changing commit rather than repository HEAD. The harness and its generated reports remain outside `BOUND_SOURCE_SCOPES`, so publishing evidence cannot invalidate the source identity it records.
- Created new `_002` evidence identities because the implementation binding changed; retained every frozen oracle, fixture revision, comparator rule, source-scope member, runtime identity, and threshold exactly.
- Treated the prior human-approved GATE-013/GATE-002 chain as immutable input. This plan checked its tracked bytes against the protected baseline but did not regenerate, re-sign, reinstall, access raw room evidence, or repeat human observations.

## Deviations from Plan

None - the plan was executed as written.

## Issues Encountered

- GSD health remains degraded only by the pre-existing non-repairable `W004` warning for `model_profile "adaptive"`. Roadmap consistency has no warnings, health has no errors, and the in-progress `I001` informational notice resolves when this summary is committed.

## Verification Evidence

- `scripts/run-three-runtime-agreement` passed normally for `FX-CONTRACT-001`, `FX-JCS-001`, and `FX-COORD-001`; `scripts/verify-phase-01-contracts references` passed the same checked-in path.
- Two consecutive ordinary publications produced identical report hashes: contract `4fd1379a…`, JCS `465fdaaf…`, and coordinate `5111ce0c…`.
- Fixture-integrity comparison and independent JavaScript/Python reference parity passed all three manifests.
- The JavaScript mutation suite passed 2 tests; the Python mutation/reference suite passed 5 tests.
- `swift test --package-path ios/Packages/ReRoomContracts` passed 33 tests in 5 suites, including the serialized 1,024-request shared-validator concurrency regression.
- The exact offline dependency audit passed 6 decisions with direct npm/Python/Swift counts `3/2/1` and 10 audited reachable transitives.
- The five tracked preflight/GATE-013/GATE-002 report/checklist files and three immutable fixture manifests match the protected `a5bff689…` baseline and have no worktree diff.
- GSD roadmap validation returned no warnings. GSD health returned no errors and only the allowlisted non-repairable `W004`; tracked-secret scanning and `git diff --check` passed.

## User Setup Required

None - this provenance repair uses the existing locked host environments and preserves the already approved physical evidence.

## Next Phase Readiness

- Phase 01 contract/device proof is complete with current reproducible acceptance evidence.
- Phase 02 may consume the frozen contracts, RR-JCS-SHA256-1, RR-COORD-1/RRFP-WIRE-1, and signed base-device gate chain without a stale three-runtime provenance gap.
- Later compositor, removal, provider, web, security, performance, and final-release gates remain governed by their own phases; this plan makes no claim for them.

## Self-Check: PASSED

- The harness and all three reports contain the exact finalized revision and `_002` evidence identities; the reports share one source-tree digest and record zero disagreements.
- Both task commits exist in repository history, and all four declared modified files are tracked.
- A second ordinary publisher run preserved every report byte; focused regressions, dependency audit, roadmap/health, secret, and diff checks passed.
- The generated Swift `.build` directory was removed, and all protected Xcode/user paths remain unstaged and unedited by this plan.
- The complete tracked physical evidence directory remains byte-identical to the protected baseline.

---
*Phase: 01-contract-and-device-proof*
*Completed: 2026-07-17*
