---
phase: 04-target-grounding-and-compositor-gate
verified: 2026-07-18T17:40:28Z
status: gaps_found
score: 15/18 must-haves verified
behavior_unverified: 0
overrides_applied: 0
gaps:
  - truth: "The published Phase 4 preflight is an exact source-bound account of the six-layer compositor descriptor."
    status: failed
    reason: "The product descriptor marks the debug layer unavailable with debug_overlay_disabled, but the verifier constant and published evidence mark it available as a local debug overlay. The existing mutation tests compare evidence to the same incorrect verifier constant, not to product source, so they pass despite the contradiction."
    artifacts:
      - path: scripts/verify-phase-04-targeting
        issue: "COMPOSITOR_DESCRIPTOR records debug as available and _verify_compositor_source_contract does not compare all source-layer availability/reason values."
      - path: evidence/targeting/phase-04/automated-preflight.json
        issue: "The source-bound report records debug available although RoomEditCompositorDescriptor.canonical records it unavailable."
    missing:
      - "Make the verifier derive or assert every layer's exact ID, availability, and reason against RoomEditCompositorDescriptor.canonical."
      - "Regenerate and validate automated-preflight.json after the verifier/test correction."
human_verification:
  - test: "Run GATE-003 on the signed base iPhone 17: eight prescribed poses, four-minute runtime capture, and five blinded ballots."
    expected: "No severe ordering artifact; TARGET median >=45 FPS and p95 frame time <=33 ms; no crash/jetsam or sustained serious/critical thermal state; at least 4/5 pass votes."
    why_human: "Simulator/source automation cannot establish physical camera composition, thermal/runtime distributions, or visual judgment."
  - test: "Run the GATE-004 semantic/manual recovery campaign and GATE-005 fast-geometry campaign."
    expected: "Identity, quality, access/license/tier, support, OBB, view-envelope, and explicit reseed results are recorded against canonical TARGET thresholds."
    why_human: "The sprint intentionally selected the manual/frozen fallback and published no provider or geometry measurements."
  - test: "Run the GATE-007 dense bake-off and GATE-012 declared-tier soak, or record the canonical measured fallback decisions."
    expected: "Dense output never rewrites ARKit/stable IDs/history; optional providers remain bounded; formal gate records include real runtime/provider evidence."
    why_human: "The automated report records no-dense/local selections but cannot substitute for the prescribed provider/runtime campaigns."
---

# Phase 4: Target Grounding and Compositor Gate Verification

**Phase Goal:** A user can ground and recover one explicit target while the base-device renderer and target-first provider path meet their measured gates or activate bounded canonical fallbacks.

**Status:** `gaps_found` — the implemented sprint fallback behavior is substantively present, but the published compositor evidence contradicts its bound product source. All physical/provider/runtime gates remain `PENDING`.

## Goal Achievement

| Area | Status | Independent evidence |
| --- | --- | --- |
| Explicit target, ambiguity, tracking revocation, and same-ID reseed | VERIFIED | `TargetGroundingReducer`, `RoomEditModel`, model tests, and three UI journeys exercise success, miss, ambiguity, loss, reset, and reseed without revision mutation. |
| Five independent readiness states/reasons | VERIFIED | The model publishes select/place/replace/remove/restore independently using the canonical values; tests cover healthy and tracking-loss transitions. |
| One AR session and bounded nonsemantic raycast boundary | VERIFIED | `SharedRealityKitSession` injects `ARView.session` into the sole driver; observer/raycast tests prove ordered delivery, removal, detected-plane preference, estimated fallback, finite filtering, and a four-candidate cap. |
| Local immutable-snapshot renderer boundary | VERIFIED | `updateUIView` only applies a coarsened snapshot; no network/model/web/filesystem/transaction wait exists in the representable callback. |
| Six-layer product descriptor | VERIFIED | Product source and Swift tests close the order as camera, reveal, occluder, asset/proxy, debug, SwiftUI; reveal, occluder, and debug are explicitly unavailable in source. |
| Published automated preflight | FAILED | The report says debug is available while the source-bound product descriptor says unavailable. This is a verifier/evidence integrity gap, not a renderer implementation gap. |
| Formal GATE-003/004/005/007/012 campaigns | HUMAN/PENDING | The repository honestly contains no signed-device, provider, geometry, tier, or blinded-vote evidence. |

**Score:** 15/18 observable truths verified. The three unscored roadmap truths are the deliberately pending physical compositor, semantic/fast-geometry, and dense/runtime campaigns; no automated behavior truth is merely presence-only.

## Artifact and Wiring Audit

All 10 declared plan artifacts exist and are substantive. Manual wiring inspection confirms:

- `RoomEditModel` binds a stable `object_*` target to exact world ID/version and captured revision; renderer handles never enter `TargetContext`.
- `ARSessionController` uses one injected `ARSession`, synchronous bounded observers, and value-only raycast candidates.
- `RoomEditView` retains the shared `ARView`, routes tap/reseed into the model, and consumes immutable render snapshots.
- `scripts/verify-phase-04-targeting` publishes atomically only after its declared full manifest, but its compositor source-contract check is incomplete as described above.

The generic key-link query could not resolve descriptive Swift targets such as `ARKit/RealityKit`; direct source tracing verifies those links. The evidence publication link was also verified by the query.

## Independent Checks

| Check | Result |
| --- | --- |
| Focused `RoomEditModelTests` + `ARSessionPolicyTests` | PASS — latest `.xcresult` reports 30 tests, 0 failures. |
| Phase 4 Python mutation suite | PASS — 8 tests. |
| Source binding | PASS — all eight recorded SHA-256 bindings match current files and product files are unchanged from `4d268ba88c1a8e10181bbd88faf306df1bd1d3d6`. |
| Evidence file SHA-256 | PASS — `7ed6fba8fe728849f92961700a8d2ebc930177df2ad336514d141b2f72cdc19a`, matching the summary. |
| `git diff --check` and debt-marker scan | PASS. |
| `scripts/verify-phase-04-targeting quick` | Initial invocation failed closed at the focused Xcode step under a nearly full disk/simulator environment; the exact focused Xcode command then passed. |
| Full verifier rerun | NOT RERUN — only about 1 GiB was free and a fresh Debug/Release/UI cycle was not proportionate after the focused pass and immutable source/evidence binding checks. Existing full evidence is not accepted as exact until the descriptor mismatch is corrected. |

## Requirements Coverage

| Requirement | Status | Evidence |
| --- | --- | --- |
| `FR-TARGET-001` | SATISFIED for the approved automated fallback slice; formal campaigns pending | Explicit manual target/reseed, stable identity/epoch, ambiguity/loss handling, and independent readiness are implemented and exercised. |
| `NFR-RENDER-001` | SATISFIED for local code boundaries; physical performance pending | The AR/render callback has no external wait and the local compositor builds/tests are source-bound; GATE-003/012 measurements remain pending. |

## Anti-Patterns and Disconfirmation Pass

- No unreferenced `TBD`, `FIXME`, or `XXX` markers were found in Phase 4 source/test/verifier files.
- Partial requirement found: formal gate criteria remain pending by approved sprint cut and cannot support Mode A/P0 or measured-performance claims.
- Misleading passing test found: the descriptor mutation suite locks the verifier's own constant but does not compare its debug availability/reason to product source.
- Uncovered evidence error path: product-layer availability drift can still publish a PASS when order and only reveal/occluder checks remain present.

## Gaps Summary

Correct the debug-layer mismatch in the verifier/evidence path and regenerate the preflight. No product behavior change is required unless the team intentionally wants a visible debug overlay, in which case the product descriptor and UI must be changed consistently. Keep `GATE-003`, `GATE-004`, `GATE-005`, `GATE-007`, and `GATE-012` pending until their canonical real-world campaigns are performed.

---

_Verified: 2026-07-18T17:40:28Z_
_Verifier: generic-agent workaround following gsd-verifier_
