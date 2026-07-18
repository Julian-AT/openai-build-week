---
phase: 06-controlled-multi-surface-removal
verified: 2026-07-18T19:59:45Z
status: human_needed
score: 20/21 must-haves verified
behavior_unverified: 0
overrides_applied: 0
human_verification:
  - test: "Run canonical GATE-006 on the controlled hero capture"
    expected: "Across at least eight physical trajectory poses, coverage p10 is at least 0.95, median at least 0.98, the largest uncovered component is at most 1%, there is no severe foreground overwrite or surface-order artifact, and exactly five blinded votes produce at least four passes."
    why_human: "The implemented DEBUG fixture proves bounded transaction/render wiring only; it contains no observed reveal, physical coverage, foreground/seam measurements, or human ballot."
---

# Phase 6: Controlled Multi-Surface Removal Verification Report

**Phase Goal:** Users can remove and restore the controlled target only inside a measured supported-view envelope, satisfying the locked P0 removal gate.

**Verified:** 2026-07-18T19:59:45Z

**Status:** `human_needed`

**Re-verification:** No — initial verification

## Goal Achievement

The automated sprint slice is substantive, wired, source-bound, and fail-closed. The exact remove reducer emits reveal then visibility, the sole native authority owns idempotent durable activation and captured-exact compensation, normal launch remains remove-unavailable, and only a compile-time DEBUG argument opens an exact-byte two-surface `degraded_demo_fixture`. The retained evidence cannot promote this fixture into ready, measured, observed, provider-backed, physical, or P0 evidence.

The canonical Phase 6 goal is not complete: `FR-REMOVE-001` and `GATE-006` remain PENDING until the real measured supported-view campaign and exactly five blinded votes pass. This report verifies implementation/demo wiring only.

### Observable Truths

| # | Truth | Status | Evidence |
|---|---|---|---|
| 1 | The controlled hero capture passes all GATE-006 coverage, ordering, foreground, and five-vote thresholds. | ? UNCERTAIN / HUMAN PENDING | No physical reveal, measurements, evaluator identities, or ballot exists; evidence correctly keeps GATE-006 PENDING. |
| 2 | A remove commit pins the reveal revision, survives replay, and restores through a new compensating transaction without rewriting the source. | ✓ VERIFIED | Reducer/authority source and retained source-bound tests cover exact reveal identity, restart/replay, immutable history, and restore r+1. |
| 3 | Outside the bounded fixture view, removal coaches or stays unavailable and never exposes undisclosed synthesis. | ✓ VERIFIED | Normal readiness is always `unavailable/reveal_quality_failed`; pose/tracking/world/load failures clear preview and retain the original; demo copy remains persistent and explicit. |
| 4 | Missing GATE-006 proof remains a P0 blocker rather than a silent demotion. | ✓ VERIFIED | Canonical requirement, UI banner, fixture, evidence, and claims all say PENDING; mutation tests reject green/promoted wording. |
| 5 | Preview emits exactly `set_reveal_bundle` then `set_object_visibility` without changing revision. | ✓ VERIFIED | `RemoveReducer.preview` constructs only those two ordered operations; source-bound reducer tests are retained. |
| 6 | Target/world/revision/classification/view/artifact failures reject without mutation. | ✓ VERIFIED | Closed reducer guards and parameterized test tokens are source-bound; mutation enforcement passed. |
| 7 | Confirmation creates one atomic r+1 scene and one captured-exact inverse. | ✓ VERIFIED | `confirm` replays preview, applies one pending revision, and constructs exactly one `restoreSnapshot` from committed to prior projection. |
| 8 | The validator is only `degraded_demo_fixture`, never ready/measured/observed/gate-passing. | ✓ VERIFIED | Exact classification/validator/policy constants and claim validator reject promotion. |
| 9 | NativeBranchAuthority is sole remove owner; exact retry returns the original receipt. | ✓ VERIFIED | `commitRemoveCritical` fingerprints and resolves idempotency before divergence, undo, reducer replay, activation, or publication. |
| 10 | Conflict, stale state, invalid confirmation, missing reveal, divergence, or activation fault publishes no hidden target. | ✓ VERIFIED | Authority/store tests are bound in the closed evidence; activation occurs only after complete candidate construction. |
| 11 | Committed remove survives recovery/replay and Restore reactivates exact prior reveal/visibility state. | ✓ VERIFIED | Retained authority/crash/restore checks are source-bound and recorded PASS. |
| 12 | Source remove history is immutable and unrelated/new state survives compensation. | ✓ VERIFIED | Captured-exact projection/rebase tests are required by the verifier and bound to the evidence revision. |
| 13 | Normal app launch never enters the demo reducer and stays `reveal_quality_failed`. | ✓ VERIFIED | Runtime defaults to `.normal`; live construction forces `.normal`; model returns before `previewRemove`. |
| 14 | Only DEBUG/demo launch shows the persistent `DEMO REVEAL FIXTURE - GATE-006 PENDING` experience. | ✓ VERIFIED | `removeLaunchMode` is guarded by `#if DEBUG`; Release returns `.normal`; UI banner/classification are explicit. |
| 15 | Fixture bytes bind target, branch/world/revision, seed pose, envelope, and fail closed on invalidation. | ✓ VERIFIED | Exact compiled bytes/digest and strict decoder bind all fields; model rechecks branch/world/target/revision/pose before preview and confirmation. |
| 16 | Renderer retains two distinct local reveal proxies in canonical order with occluder unavailable. | ✓ VERIFIED | Two retained anchors are created once; snapshot toggles them; compositor remains camera → reveal → unavailable occluder → asset → debug → SwiftUI. |
| 17 | Preview/confirm/retry/relaunch/restore are accessible without physical/provider/quality claims. | ✓ VERIFIED | Native buttons/IDs and retained UI evidence cover r0 → r1, retry r1, relaunch r1, restore r2; banner and limitations remain visible. |
| 18 | One fail-closed verifier covers reducer, authority, model, fixture, render, UI, builds, release surface, privacy, and whitespace. | ✓ VERIFIED | Closed 15-check manifest is retained; current report/source binding validation passed independently. |
| 19 | Evidence claims only the automated sprint slice and keeps all named gates pending. | ✓ VERIFIED | Claim is exact; FR-REMOVE-001 plus GATE-006/003/005/009 and OPS-GOLDEN-001 remain PENDING. |
| 20 | Verification rejects ready/measured/observed/provider/coverage/ballot/foreground/seam/physical/thermal/P0 promotion. | ✓ VERIFIED | Independent ten-test mutation suite exercised forbidden-claim and green-gate rejection. |
| 21 | Evidence contains no imagery, poses, identifiers, credentials, machine paths, raw traces, or fabricated evaluators. | ✓ VERIFIED | Closed privacy map is all false; report shape/value scanning and source-bound validation passed. |

**Score:** 20/21 truths verified; the one unresolved truth is the real physical/human GATE-006 campaign.

## Artifacts and Wiring

All 12 declared plan artifacts exist and are substantive. The generic plan query reported four false negatives because Swift consumers reference symbols rather than target filenames; manual traces establish the links:

| From | To | Status | Evidence |
|---|---|---|---|
| `RemoveReducer.swift` | `EditProjection.swift` | ✓ WIRED | Calls `build`, `diff`, `verify`, `apply`, `snapshot`, and required-artifact helpers. |
| `TransactionAuthority.swift` | `TransactionStore.swift` | ✓ WIRED | The authority owns the store and publishes only through complete generation activation. |
| `RoomEditModel.swift` | `NativeBranchAuthority` | ✓ WIRED | Preview, confirm, retry, refresh, and restore all call the one authority. |
| `RoomEditView.swift` | `RoomEditModel.swift` | ✓ WIRED | SwiftUI actions call model entry points; renderer consumes immutable snapshot diffs. |
| verifier | preflight evidence | ✓ WIRED | Full mode seals/validates then atomically replaces the report; quick/failure paths publish nothing. |

Data flows from exact compiled fixture bytes → strict decoder → launch/pose/epoch policy → exact reducer → sole authority/store → immutable snapshot → retained reveal anchors. Normal launch exits before that path. No Phase 6 fixture is loaded from `Bundle` or listed in PBX resources, and `updateUIView` performs only in-memory snapshot application.

## Independent Checks

| Check | Result |
|---|---|
| `python3 -m unittest tools.verify.tests.test_phase_06_removal -v` | 10/10 PASS |
| Standalone `_require_bound_sources` + sealed `_validate_report` + current digest comparison | PASS |
| Forbidden dependency, Bundle/PBX, debt-marker, and external-call scans | No Phase 6 finding |
| Xcode/Swift suites | Not rerun by instruction; retained 15-check evidence remains byte-bound to every product/test source and independently validates now |

No phase-specific probe scripts are declared.

## Requirements Coverage

| Requirement / gate | Status | Evidence |
|---|---|---|
| `FR-REMOVE-001` | ? PARTIAL / PENDING | Exact transaction, bounded demo, normal fallback, and honesty controls are implemented; physical reveal/foreground readiness is not established. |
| `GATE-006` | ? HUMAN PENDING | No eight-pose measurements or exactly-five-vote record exists. Failure remains release-blocking. |

`REQUIREMENTS.md` correctly leaves FR-REMOVE-001 pending. ROADMAP still shows Plans 06-03/06-04 unchecked and “2/4” despite their committed summaries/artifacts; this is stale planning metadata, not an implementation pass or gate claim.

## Anti-Patterns and Disconfirmation

No unresolved TBD/FIXME/XXX/TODO/HACK marker, provider/network path, Phase 6 Bundle load, PBX resource dependency, per-update I/O/wait, normal-path readiness promotion, synthetic occluder, or evidence promotion was found.

1. **Partially met requirement:** FR-REMOVE-001 has deterministic transaction/demo wiring but lacks the physical GATE-006 acceptance evidence.
2. **Limited passing test:** The simulator journey proves retained surfaces and revision behavior; it cannot prove observed-background coverage, seams, foreground safety, or a believable walk-around.
3. **Uncovered campaign path:** Tracking/world invalidation before commit is automated, while post-commit physical tracking/relocalization quality remains part of the pending device/resilience campaigns. Source preserves the last activated durable edit rather than inventing a new mutation.

## Human Verification Required

### Canonical GATE-006 campaign

**Test:** Run `TST-REVEAL-001` on `FX-HERO-ROOM-001` at at least eight prescribed physical poses and conduct exactly five blinded walk-around votes.

**Expected:** P10 ≥ 0.95, median ≥ 0.98, largest uncovered component ≤ 1%, zero severe foreground overwrite/surface-order artifact, and 4–5 of exactly five pass votes.

**Why human:** The DEBUG two-surface proxy is explicitly a HYPOTHESIS wiring fixture and cannot supply observed pixels, physical quality measurements, or human judgment.

## Pending Summary

No implementation defect was found in the authorized automated Phase 6 sprint slice. Exact reduction/authority, normal/DEBUG isolation, compiled fixture/audit separation, two retained surfaces, safe pre-commit invalidation, source binding, privacy, and honest pending claims verify cleanly. Phase 6 remains `human_needed` because the locked removal promise cannot complete without the real GATE-006 campaign.

---

_Verified: 2026-07-18T19:59:45Z_

_Verifier: the agent (gsd-verifier)_
