# Best-Supported-Solution Decision Matrix

Status: final comparison audit  
Date: 2026-07-14

Common constraints are two developers, one week, a controlled hero scene, a base non-LiDAR iPhone 17, deterministic replay before live integration, guaranteed B0, isolated B1, no hidden hardware SKU, and honest measured-versus-target claims. “Best” below means best supported under those constraints, not globally optimal.

## D-001 — Product modes and exact P0 scope

1. **Problem:** Define what must ship without allowing gates to rewrite the promise.
2. **Project constraints:** Human-locked four operations, B0 P0, B1 stretch.
3. **Existing proposed choice:** Four operations, but failed removal could be omitted/demoted.
4. **Alternatives:** Replacement-only; broad room editor; four operations with fixture/readiness gate.
5. **Criteria:** Scope honesty, independent testability, demo value, fallback cost, GSD phase complexity.
6. **Evidence:** Governing human locks; archived removal risk; ADR-001.
7. **Verdict:** `REPLACE` the demotion rule with exact four-operation P0 and hard fixture gate.
8. **Confidence:** High.
9. **Required benchmark:** GATE-006 validates removal quality; scope itself is not benchmark-selected.
10. **Fallback/kill:** Unsupported sessions keep remove unavailable; hero failure blocks P0 or requires explicit human escalation. GATE-014 kills B1 while P0 is red.
11. **Impact:** Mode A and B0 share four operations; B1 has no P0 phase; narrows the week to a controlled fixture.

## D-002 — Native iPhone and separate web client

1. **Problem:** Assign live AR and replay/web responsibilities.
2. **Project constraints:** Direct ARKit/camera access, native thermal behavior, cross-device replay.
3. **Existing proposed choice:** SwiftUI native app plus Next.js web app.
4. **Alternatives:** PWA-only; cross-platform wrapper; native/web split.
5. **Criteria:** AR capability, hot-path latency, debugging, portability, implementation effort.
6. **Evidence:** Apple AR session APIs; pinned Next.js WebSocket source; ADR-002.
7. **Verdict:** `ACCEPT` the split; gateway owns sockets/state.
8. **Confidence:** High.
9. **Required benchmark:** GATE-003 native; GATE-008 web replay.
10. **Fallback/kill:** B0 survives native failure; native-only capability is never claimed on web.
11. **Impact:** Mode A remains native; B0 is web; B1 web-only later; two clear vertical slices.

## D-003 — ARKit authority and coordinates

1. **Problem:** Preserve one metric world and exact cross-language projection.
2. **Project constraints:** No LiDAR; Swift/JS/Python consumers; reset/replay correctness.
3. **Existing proposed choice:** ARKit pose plus partial ARKit/OpenCV transform examples.
4. **Alternatives:** Per-service conventions; learned native pose; RR-COORD-1.
5. **Criteria:** Metric correctness, determinism, debuggability, provider independence.
6. **Evidence:** Apple transform/display/raw-feature/depth documentation; ADR-003.
7. **Verdict:** `ACCEPT` ARKit authority and `REPLACE` partial conventions with RR-COORD-1.
8. **Confidence:** High architecture, medium implementation.
9. **Required benchmark:** GATE-002 known-ray and device orientation/checkerboard projection.
10. **Fallback/kill:** Reject inconsistent packets and start a new explicit world-frame version; never guess alignment.
11. **Impact:** Load-bearing for A and `.rrcap` B0; B1 consumes snapshots only; must finish in the first contract slice.

## D-004 — Atomic capture and replay

1. **Problem:** Make network loss and crash recovery compatible with deterministic replay.
2. **Project constraints:** Render-loop independence, bounded queues, no lost durable prefix.
3. **Existing proposed choice:** Enqueue local write before network; replay logical packets.
4. **Alternatives:** Network-first; simultaneous best-effort; durable record-first then send.
5. **Criteria:** Durability, ordering, latency isolation, storage load, replay fidelity.
6. **Evidence:** Governing record/replay invariants; ADR-004.
7. **Verdict:** `REPLACE` enqueue semantics with atomic durable-before-network eligibility.
8. **Confidence:** High.
9. **Required benchmark:** GATE-001 crash/network injection on 10 s and 60 s fixtures.
10. **Fallback/kill:** Reduce rate/resolution or pause upload; preserve the valid local journal prefix. Failure blocks integration.
11. **Impact:** A records locally; B0 gains exact inputs; B1 may consume immutable captures; first critical slice.

## D-005 — Camera-feed compositor

1. **Problem:** Cover real target pixels with spatial reveals/assets at device frame budget.
2. **Project constraints:** Camera remains background, no LiDAR mesh, two developers, four-minute session.
3. **Existing proposed choice:** RealityKit first, Metal fallback.
4. **Alternatives:** RealityKit entities; custom Metal from start; screen-space punch-out.
5. **Criteria:** Ordering, quality, FPS/thermal, implementation effort, fallback cost.
6. **Evidence:** RealityKit occlusion/postprocess APIs establish capability but not ReRoom quality; ADR-005.
7. **Verdict:** `REQUIRES_BENCHMARK` for RealityKit; `REJECT` screen-space canonical path; Metal is a bounded contingency.
8. **Confidence:** Medium-low until device evidence.
9. **Required benchmark:** GATE-003 eight poses and four-minute device run, at least 45 FPS and 4/5 visual pass.
10. **Fallback/kill:** Use simplest validated RealityKit replacement composite; Metal only if its spike passes within four hours. Neither passing blocks Mode A completion.
11. **Impact:** Critical to A; B0 unaffected; B1 irrelevant; must be front-loaded.

## D-006 — Fast and dense geometry tracks

1. **Problem:** Obtain edit-ready proxies without waiting for experimental dense reconstruction.
2. **Project constraints:** Imperfect masks/depth, no LiDAR, quick replacement, optional dense quality.
3. **Existing proposed choice:** Fast mask volume/planes plus dense DA3/Open3D.
4. **Alternatives:** Dense-only; 2D-only; split fast/dense.
5. **Criteria:** Time-to-first-edit, metric correctness, temporal stability, failure isolation, implementation effort.
6. **Evidence:** ARKit plane/raycast capability; archived failure-chain analysis; ADR-006.
7. **Verdict:** `ACCEPT` the split, with stricter evidence boundaries.
8. **Confidence:** High on split, medium on fast-volume quality.
9. **Required benchmark:** GATE-005 fast volume; GATE-007 dense provider.
10. **Fallback/kill:** Additional views or unavailable capability; dense failure selects no-dense.
11. **Impact:** A fast path stays independent; B0 may degrade; B1 cannot rewrite identities; reduces week risk materially.

## D-007 — Segmentation and depth providers

1. **Problem:** Select adequate models without freezing novelty or hidden access/runtime risk.
2. **Project constraints:** One target, bounded GPU, current licenses, deterministic fixture, no provider criticality for replay.
3. **Existing proposed choice:** SAM 3.1 default, DA3Metric initial, LingBot universal fallback.
4. **Alternatives:** SAM 2.1 Small/SAM 3.1/frozen masks; DA3Metric/pose-conditioned/no-dense; LingBot/replay-only video.
5. **Criteria:** Quality, identity stability, latency, VRAM, startup, license/access, maturity, fallback cost.
6. **Evidence:** Official SAM 2/3, DA3, and LingBot repositories/licenses; ADR-007.
7. **Verdict:** `REPLACE` frozen defaults with versioned providers; provisional default SAM 2.1 Small; LingBot deferred.
8. **Confidence:** Medium.
9. **Required benchmark:** GATE-004 semantic and GATE-007 depth shared fixtures.
10. **Fallback/kill:** Frozen/reseeded masks, no-dense path, and ordinary-video replay without geometry. Missed timebox selects fallback.
11. **Impact:** A semantics stays swappable; B0 provider-independent; B1 may choose later models; prevents model work from owning the week.

## D-008 — Scene identity and readiness

1. **Problem:** Keep identity stable while providers/artifacts improve independently.
2. **Project constraints:** Cross-mode history, client activation, retries, disposable renderer/provider indices.
3. **Existing proposed choice:** Stable IDs with mostly linear readiness examples.
4. **Alternatives:** Transient indices; one editable flag; canonical IDs plus independent lifecycle/readiness.
5. **Criteria:** Determinism, upgrade safety, debugging, contract clarity, failure communication.
6. **Evidence:** Replay/provider invariants; ADR-008.
7. **Verdict:** `ACCEPT` canonical IDs; `REPLACE` linear readiness with independent capability states.
8. **Confidence:** High.
9. **Required benchmark:** Contract transition/activation fixtures in GATE-009.
10. **Fallback/kill:** Retain previous activated revision; unknown/stale artifacts never become ready.
11. **Impact:** Shared by A/B0; B1 is a skin; early contract work reduces all later integration drift.

## D-009 — Multi-surface reveal

1. **Problem:** Produce credible empty removal across movement with incomplete background evidence.
2. **Project constraints:** Controlled target, imperfect masks, foreground objects, no undisclosed calibration plate, exact remove P0.
3. **Existing proposed choice:** Multi-surface atlases, deterministic fill, optional LaMa, sampled coverage.
4. **Alternatives:** Screen-space inpaint; single plane; view-bounded multi-surface bundle.
5. **Criteria:** Coverage, seams, foreground correctness, provenance, temporal stability, implementation/license risk.
6. **Evidence:** Geometry of floor/wall exposure; RealityKit capability; ADR-009.
7. **Verdict:** `REQUIRES_BENCHMARK`; multi-surface bundle is the best provisional representation.
8. **Confidence:** Medium-low.
9. **Required benchmark:** GATE-006 eight-view coverage/foreground/visual gate.
10. **Fallback/kill:** Request views, shrink envelope, choose easier fixture, or keep remove unavailable; hero failure blocks P0.
11. **Impact:** A removal only; B0 can inspect evidence; B1 irrelevant; highest one-week visual risk.

## D-010 — Asset contract

1. **Problem:** Deliver fitting, licensed assets consistently to native and web clients.
2. **Project constraints:** Tiny catalog, offline hero availability, no runtime conversion.
3. **Existing proposed choice:** Five-to-ten USDZ/GLB derivatives with metadata.
4. **Alternatives:** Marketplace/runtime conversion; one format; canonical manifest with prevalidated derivatives.
5. **Criteria:** Fit/cover correctness, load time, parity, license, preparation effort.
6. **Evidence:** Client format requirements and deterministic validation needs; ADR-010.
7. **Verdict:** `ACCEPT` manifest authority and prevalidated pairs; remove fixed catalog-count pressure.
8. **Confidence:** High after gate.
9. **Required benchmark:** GATE-011 derivative parity, collision, local load, hash, and license.
10. **Fallback/kill:** Exclude failed assets; use smallest catalog that demonstrates choice/rejection.
11. **Impact:** A and B0 share IDs; B1 reuses assets later; finite early preparation task.

## D-011 — Agent/deterministic boundary

1. **Problem:** Make voice/GPT useful without granting spatial or mutation authority.
2. **Project constraints:** Server-side secrets, strict validation, typed fallback, injection resistance.
3. **Existing proposed choice:** Realtime transcript ingress, gateway, Sol strict output, deterministic validation.
4. **Alternatives:** Realtime mutations; gateway-only audio; direct WebRTC narrow ingress.
5. **Criteria:** Security, latency, structure, testability, graceful failure, implementation effort.
6. **Evidence:** Official Realtime WebRTC and model capability pages; ADR-011.
7. **Verdict:** `ACCEPT` and harden the existing split.
8. **Confidence:** High boundary, medium voice reliability.
9. **Required benchmark:** GATE-010 five hero turns plus ambiguity/injection fixtures.
10. **Fallback/kill:** Typed path; malformed/stale calls rejected; voice work ends on failed timebox.
11. **Impact:** A/B0 can share typed service; B1 none; voice occurs after deterministic transactions.

## D-012 — Transactions and offline restore

1. **Problem:** Guarantee idempotent preview/commit/restore across disconnect and retry.
2. **Project constraints:** One P0 editor, immutable replay, active-session offline restoration.
3. **Existing proposed choice:** Revisioned deltas and local inverse ops, with undo mixed into lifecycle wording.
4. **Alternatives:** Direct commands; mutate original to undone; compensating restore transaction.
5. **Criteria:** Determinism, crash safety, reconciliation, testability, user latency.
6. **Evidence:** Record/offline invariants and transaction design; ADR-012.
7. **Verdict:** `ACCEPT` revisioned transactions; `REPLACE` mutable/full-document undo with a compensating restore, RR-EDIT-PROJECTION-1 plus touched-ID RR-RESTORE-REBASE-1, fresh monotonic envelope, and separate sync state.
8. **Confidence:** High.
9. **Required benchmark:** GATE-009 duplicate/stale/offline/crash/reconnect fixture.
10. **Fallback/kill:** Do not acknowledge an unpersisted commit; stop mutations and reconcile explicitly on conflict.
11. **Impact:** Same contract for A/B0; newly tracked/unaffected objects and live evidence survive restore; B1 reads immutable history; typed transaction slice precedes voice/models.

## D-013 — Guaranteed B0 minimum

1. **Problem:** Make the locked replay product survive provider/GPU failure.
2. **Project constraints:** Exact `.rrcap` replay, web inspection, ordinary-video support, no hidden learned dependency.
3. **Existing proposed choice:** TSDF/LingBot mesh or point twin plus replay and controls.
4. **Alternatives:** Model-dependent B0; developer utility; provider-independent baseline with optional geometry.
5. **Criteria:** Guarantee strength, deterministic replay, deployment risk, user value, fallback cost.
6. **Evidence:** Human lock, LingBot current maturity/runtime, ADR-013.
7. **Verdict:** `REPLACE` model-dependent B0 with provider-independent baseline.
8. **Confidence:** High.
9. **Required benchmark:** GATE-008 with every learned provider disabled.
10. **Fallback/kill:** Replay/timeline/errors/sparse artifacts remain; LingBot failure never fails B0.
11. **Impact:** B0 is real P0; A records for it; B1 optional; substantially lowers week/deployment risk.

## D-014 — Service topology and hardware tiers

1. **Problem:** Fit stateful live processing and experiments into two-developer/hardware limits.
2. **Project constraints:** No deployment in preparation, no mandatory GPU SKU, bounded work, incompatible runtimes.
3. **Existing proposed choice:** Many always-on containers on one warm cloud GPU.
4. **Alternatives:** Full microservices; one dependency monolith; minimal logical gateway/web/selected-worker profiles.
5. **Criteria:** Integration effort, dependency isolation, VRAM, observability, portability, failure recovery.
6. **Evidence:** Official provider runtime requirements, Next.js boundary, ADR-014.
7. **Verdict:** `REPLACE` always-resident topology with minimal selected profiles and hardware tiers.
8. **Confidence:** Medium-high.
9. **Required benchmark:** GATE-012 four-minute selected-profile runtime; GATE-013 device/signing preflight.
10. **Fallback/kill:** Unload/serialize optional providers, reduce rate/resolution, no-dense; no new datastore/orchestrator without measured failure and ADR.
11. **Impact:** A live lane stays small; B0 baseline can run without GPU; B1 disabled; matches two-developer debugging capacity.
