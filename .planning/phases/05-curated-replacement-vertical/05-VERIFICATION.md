---
phase: 05-curated-replacement-vertical
verified: 2026-07-18T19:17:54Z
status: human_needed
score: 16/19 must-haves verified
behavior_unverified: 0
overrides_applied: 0
gaps: []
deferred:
  - truth: "Physical conservative masking/occlusion, support plausibility, and absence of a severe seam"
    addressed_in: "Phase 8 and canonical GATE-003/GATE-005 campaigns"
    evidence: "Phase 8 goal requires the journey to be repeatable, measured, and honestly documented; SPRINT-CUT-36H explicitly leaves GATE-003 and GATE-005 PENDING."
  - truth: "Five complete signed-device golden runs with exact replay and no severe artifact"
    addressed_in: "Phase 8"
    evidence: "Phase 8 owns complete hardening/evidence, and OPS-GOLDEN-001 remains PENDING until five complete native plus B0 runs after all gates are green."
  - truth: "Validated native/web asset derivatives, parity, collision/cover evidence, and approved license/attribution records"
    addressed_in: "Phase 8 and canonical GATE-011 campaign"
    evidence: "The approved sprint cut permits one provenance-recorded local demo asset while deferring derivative parity and redistribution/attribution approval."
---

# Phase 5: Curated Replacement Vertical Verification Report

**Phase Goal:** Users can replace the controlled target with a validated curated asset reliably inside supported observations.
**Verified:** 2026-07-18T19:17:54Z
**Status:** `human_needed`
**Re-verification:** Yes — supported-view implementation gap closed

## Goal Achievement

The deterministic reducer, sole-writer authority, restart/restore path, exact local asset loader, simulator journeys, supported-view policy, and honest evidence publication are substantive and tested. Production now fails closed by default and derives the fixture/live verdict from the current revision, world epoch, frozen target, and camera pose at preview and confirmation. The roadmap's physical visual, derivative/license, and complete golden criteria remain intentionally pending under the approved sprint cut and require human/canonical evidence.

### Observable Truths

| # | Truth | Status | Evidence |
|---|---|---|---|
| 1 | A ready target is replaced with stable identity, conservative masking/occlusion, support alignment, and one revision after retry. | ? HUMAN/DEFERRED | Stable identity, support fields, and exactly-once retry are automated; physical masking/contact/seam quality still requires GATE-003/GATE-005 evidence. |
| 2 | Five consecutive runs have no wrong target, duplicate revision, severe seam, lost edit, or replay failure. | ? HUMAN/DEFERRED | Five simulator fixture iterations passed and local restart/restore is exact; severe-seam judgment, signed-device runs, and complete B0 golden replay remain OPS-GOLDEN-001 work. |
| 3 | Outside validated observations, the UI coaches or restores safe content. | ✓ VERIFIED | The default policy is `.denyAll`; fixture/live factories explicitly inject named policies derived from current scene/world/frozen-target/camera evidence. Preview and confirmation revalidate, and omitted, stale, and out-of-view regressions retain the original at r0. |
| 4 | One manifest binds native/web derivatives, dimensions, origin, collision, hashes, delivery, and license before hero use. | ? HUMAN/DEFERRED | The local USDA digest/provenance/HYPOTHESIS metadata is honest, but the manifest deliberately lacks validated web derivative parity and shipping license approval; GATE-011 is PENDING. |
| 5 | Valid preview emits exactly visibility then asset creation without changing revision. | ✓ VERIFIED | Direct source trace shows `setObjectVisibility` then `createAssetInstance`; independent `ReplaceReducerTests.cancelAndConfirm` passed. |
| 6 | Target/readiness/view/support/asset/world/revision/integrity failures reject before mutation. | ✓ VERIFIED | `ReplaceReducer.validateContext` and candidate guards are covered by the parameterized non-destructive reducer tests; mutation verifier passed. |
| 7 | Confirmation replays current state, commits r+1, and captures one exact inverse. | ✓ VERIFIED | `ReplaceReducer.confirm` replays `preview`, creates captured-exact before/after projections, and the independent named reducer test passed. |
| 8 | NativeBranchAuthority is sole owner; identical retry returns one receipt/revision. | ✓ VERIFIED | `RoomEditModel` calls `authority.commitReplace`; `commitReplaceCritical` resolves idempotency before reduction/activation. Independent concurrent retry/restart test passed. |
| 9 | Conflicts, invalid confirmation, divergence, or durability faults publish no replacement. | ✓ VERIFIED | Authority tests cover changed fingerprint, confirmation and activation faults; `active` publishes only after `store.activate`. |
| 10 | Replace survives recovery and Restore preserves unrelated state/history. | ✓ VERIFIED | Independent `replaceRestorePreservesUnrelatedState` test passed, including restart and immutable source transaction. |
| 11 | App bootstrap and manual target share one stable object; incompatible old state fails closed. | ✓ VERIFIED | Stable `RoomEditIdentity.targetObjectID` is used by target/candidate/bootstrap; model regressions cover recovered empty generations. |
| 12 | Native target → preview → Confirm → retry → restart → Restore journey works. | ✓ VERIFIED | Full source-bound UI preflight records PASS; test source asserts r0 → r1, retry r1, restart r1, Restore r2. |
| 13 | Target coverage and replacement are distinct; load/commit failure retains safe display. | ✓ VERIFIED | Separate `targetAnchor`/`replacementAnchor` and snapshot fields; UI loader-failure test requires target coverage and no replacement at r0. |
| 14 | Bundled USDA is exact, provenance-bound, local-demo labeled, and GATE-011 remains pending. | ✓ VERIFIED | Asset digest `afdd38…32379`, six-cube manifest, provenance, product copy, and evidence agree; no parity/license completion claim exists. |
| 15 | RealityKit loads the exact USDA once outside `updateUIView`, retains/clones it, and fails closed. | ✓ VERIFIED | One `Entity.load(named: "proxy-chair.usda")` occurs in coordinator init; six entities required; retained template clones on render; failure publishes unavailable. |
| 16 | One fail-closed verifier covers reducer/authority/model/UI/build/asset/render/security checks. | ✓ VERIFIED | Closed 16-check manifest exists; independent 10-test mutation suite passed and report self-validation succeeded. |
| 17 | Evidence claims only the automated sprint slice and leaves all named gates pending. | ✓ VERIFIED | Claim is exactly `automated sprint replacement slice passed`; GATE-003/005/009/011 and OPS-GOLDEN-001 are exactly `PENDING`. |
| 18 | Evidence contains no private data, credentials, machine paths, fabricated measurements, or P0 claim. | ✓ VERIFIED | Closed privacy map is false, limitation text is explicit, and focused scan found no affirmative forbidden claim. |
| 19 | Verification binds all core sources and exact retained loader, rejecting implicit supported-view authorization, substitution, and load-failure readiness. | ✓ VERIFIED | Current reducer, authority, app, tests, and asset bytes match `f53ba72`; mutation tests reject default-true/omitted policy wiring, exact-asset drift, generated-box substitution, and failed-load promotion. |

**Score:** 16/19 truths verified; 0 failed; 3 require deferred human/canonical evidence.

## Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `ReplaceReducer.swift` | Pure ordered replace reducer | ✓ VERIFIED | Substantive validation, projection diff, preview/cancel/confirm, and exact inverse logic. |
| `ReplaceReducerTests.swift` | Order/rejection/inverse/nonmutation tests | ✓ VERIFIED | Direct named reducer test passed independently. |
| `TransactionAuthority.swift` | Sole durable replace authority | ✓ VERIFIED | Fingerprint/idempotency, confirmation, store activation, restore, and post-activation publication wired. |
| `TransactionAuthorityTests.swift` | Retry/recovery/fault/restore coverage | ✓ VERIFIED | Independent concurrent retry/restart and restore-preservation tests passed. |
| `RoomEditModel.swift` | App state/bootstrap/authority bridge and supported-view policy | ✓ VERIFIED | Fail-closed default plus explicit fixture/live policies evaluate current scene/world/frozen target/camera evidence at preview and confirmation. |
| `RoomEditView.swift` | Accessible bounded replacement UI | ✓ VERIFIED | Native controls, retained coordinator, exact loader, distinct anchors, and honest copy are wired. |
| `RoomEditJourneyTests.swift` | Full/five-run/failure UI paths | ✓ VERIFIED | All three named cases are present and the full source-bound report records PASS. |
| `asset-manifest.json` / `PROVENANCE.md` / `proxy-chair.usda` | Honest exact local demo asset | ✓ VERIFIED | Closed digest and HYPOTHESIS metadata; explicitly not CON-004 parity evidence. |
| `verify-phase-05-replacement` | Quick/full verifier | ✓ VERIFIED | Executable, closed checks, source/asset contracts, atomic publication. |
| `test_phase_05_replacement.py` | Mutation enforcement | ✓ VERIFIED | Ten tests passed independently. |
| `automated-preflight.json` | Sanitized revision-bound evidence | ✓ VERIFIED | Canonical self-digest and source/asset checks validate; all fixed product bytes match `f53ba72`. |

## Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| `ReplaceReducer.swift` | `EditProjection.swift` | projection build/diff/verify and captured-exact inverse | ✓ WIRED | `EditProjectionEngine.build`, `diff`, `verify`, `snapshot`, and required-artifact union are invoked directly. |
| `TransactionAuthority.swift` | `TransactionStore.swift` | durable activation before visible publication | ✓ WIRED | Candidate/receipt/idempotency inventory is assembled, `store.activate(candidate)` completes, then `active` updates and receipt returns. |
| `RoomEditModel.swift` | `NativeBranchAuthority` | preview/confirm/retry/restore | ✓ WIRED | Model owns one injected authority and invokes typed preview/commit/restore entry points. |
| `RoomEditView.swift` | exact local USDA | coordinator initialization and retained clone | ✓ WIRED | Loader count is one, template is retained, `updateUIView` only applies snapshots. |
| verifier | evidence report | atomic publish after closed full manifest | ✓ WIRED | `_publish_atomic` validates the sealed report, fsyncs a temporary file, and replaces only after all full checks pass. |

## Data-Flow Trace

| Artifact | Data | Source | Produces real bounded state | Status |
|---|---|---|---|---|
| Replace UI | immutable render snapshot | authority snapshot → `RoomEditModel.publish` → SwiftUI/RealityKit coordinator | Yes | ✓ FLOWING |
| Replacement entity | retained `replacementTemplate` | exact bundled USDA → six-entity validation → model availability → clone | Yes | ✓ FLOWING |
| Supported-view blocker | `RoomEditSupportedViewPolicy` | current scene/world + frozen target + support camera pose | Yes; fail-closed at preview and revalidated before commit | ✓ FLOWING |
| Preflight evidence | checks/source digests/counts | quick/full commands and static contracts → sealed report → atomic replace | Yes | ✓ FLOWING |

## Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| Mutation enforcement | `python3 -m unittest tools.verify.tests.test_phase_05_replacement` | 10 tests passed | ✓ PASS |
| Current model policy suite | `xcodebuild … -only-testing:ReRoomDeviceProofTests/RoomEditModelTests` | 22 tests passed | ✓ PASS |
| Exact confirm/inverse | `swift test … --filter ReplaceReducerTests.cancelAndConfirm` | 1 Swift Testing test passed | ✓ PASS |
| Concurrent retry/restart | `swift test … --filter TransactionAuthorityTests.concurrentReplaceIsExactlyOnceAndRestartSafe` | 1 Swift Testing test passed | ✓ PASS |
| Restore/restart/unrelated state | `swift test … --filter TransactionAuthorityTests.replaceRestorePreservesUnrelatedState` | 1 Swift Testing test passed | ✓ PASS |
| Evidence/source/asset validation | Import verifier; call `_validate_report`, `_require_bound_sources`, source and asset contracts | PASS | ✓ PASS |

## Probe Execution

No phase-specific probe scripts were declared. The executable preflight is a verifier, not a `probe-*.sh`; its full mode had already passed and was not rerun.

## Requirements Coverage

| Requirement | Source Plans | Description | Status | Evidence |
|---|---|---|---|---|
| FR-REPLACE-001 | 05-01 through 05-04 | Replace the selected hero object with a curated asset only within supported observations. | ? HUMAN NEEDED | Automated mechanics and production supported-view enforcement pass; physical composite quality, derivative/license evidence, and formal golden acceptance remain pending. |

No additional requirement is mapped to Phase 5 in `REQUIREMENTS.md`, so there is no orphaned Phase 5 requirement.

## Anti-Patterns and Disconfirmation Findings

| File | Line | Finding | Severity | Impact |
|---|---|---|---|---|
| `RoomEditModel.swift` | supported-view policy/runtime wiring | Bounded values are explicitly `HYPOTHESIS`, not measured thresholds. | ℹ️ DECLARED | Safe for the bounded sprint demo only; physical validation may tighten or replace them. |
| `verify-phase-05-replacement` | product digest/source contract | Core reducer, authority, app, test, and asset paths are immutable-bound. | ✓ CLOSED | Core-only drift and default-true/omitted runtime injection are mutation-rejected. |

No unreferenced `TBD`, `FIXME`, `XXX`, TODO placeholder, empty user-visible implementation, credential, private room data, or machine path was found in the Phase 5 files/report.

### Disconfirmation pass

1. **Remaining human boundary:** FR-REPLACE-001 has deterministic transaction/UI mechanics and production supported-view enforcement, but formal visual/asset acceptance remains pending.
2. **Policy honesty:** The local pose envelope is labeled `HYPOTHESIS`; no measurement or formal gate acceptance is inferred from model/simulator tests.
3. **Uncovered error path:** Missing/corrupt asset states have model tests and startup fail-closed behavior, but only RealityKit load failure has an end-to-end UI injection. This is non-blocking because startup failure prevents mutation, but it is not equivalent UI-path coverage.

## Human Verification Required

### 1. Physical replacement composite and support

**Test:** Run the prescribed base-iPhone poses and sustained session under GATE-003/GATE-005.
**Expected:** Original coverage is conservative, replacement contact/support is plausible, foreground ordering is safe, and no severe seam occurs.
**Why human:** Simulator state assertions and source inspection cannot establish camera-pixel quality, depth/occlusion ordering, contact, performance, or thermal behavior.

### 2. Asset derivative and license acceptance

**Test:** Complete TST-ASSET-001/TST-LICENSE-001 for native/web derivatives, dimensions/origin, collision/cover, device/web load, parity, redistribution, and attribution.
**Expected:** GATE-011 passes with approved evidence or the asset is excluded.
**Why human:** The current repository-owned USDA is deliberately a local demo proxy, not a validated shipping manifest or derivative pair.

### 3. Complete golden journey

**Test:** After all gates are green, run five complete signed-device place/replace/remove/restore plus B0 journeys with retained traces/video.
**Expected:** 5/5 with no wrong target, duplicate revision, lost edit, severe artifact, or replay mismatch.
**Why human:** Five automated replacement fixture loops do not constitute OPS-GOLDEN-001.

## Gaps Summary

No automated implementation gap remains. The supported-view verdict is now production-wired and fail-closed, its regression and mutation suites pass, and the evidence is rebound to `f53ba72`. Phase status is `human_needed` solely because canonical physical composite, derivative/license, and complete golden evidence remain PENDING rather than failed or fabricated.

---

_Verified: 2026-07-18T19:17:54Z_
_Verifier: the agent (gsd-verifier)_
