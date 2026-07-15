# ReRoom Risk and Kill Gates

Status: canonical PRE-GSD gate authority  
Version: 1.0.0  
Date: 2026-07-13

## 1. Use of this register

This file is the authoritative `GATE-NNN` mapping. Terms and requirement IDs come from [GLOSSARY_AND_ID_REGISTRY.md](GLOSSARY_AND_ID_REGISTRY.md) and [PRD.md](PRD.md). Evidence procedures and formats are identified by the canonical `TEST-NNN` and `EVAL-NNN` registries. ADRs own the architectural decision; this register owns the operational trigger and final kill rule.

Every numeric value below is a **TARGET**, not a measured result. A gate becomes green only when an evidence record identifies the fixture version, implementation revision, device/runtime tier, provider and checkpoint revisions, run count, raw output location, metric code revision, and evaluator. Missing evidence is a failed gate, not an assumed pass.

Gate states are `UNRUN`, `RUNNING`, `GREEN`, `RED`, or `WAIVED_BY_HUMAN`. A human waiver must name the changed locked promise and update the PRD and affected ADR; a timebox overrun alone cannot silently waive a gate.

## 2. Gate map

| Gate | Risk controlled | P0 requirement trace | Decision trace |
|---|---|---|---|
| `GATE-001` | Capture durability and deterministic replay | `FR-CAPTURE-001`, `FR-B0-001`, `NFR-REPLAY-001` | [ADR-004](../adr/ADR-004-atomic-capture-and-record-first-replay.md), [ADR-013](../adr/ADR-013-mode-b0-guarantee.md) |
| `GATE-002` | Coordinate, projection, orientation, and intrinsics correctness | `FR-CAPTURE-001`, `NFR-COORD-001` | [ADR-003](../adr/ADR-003-arkit-authority-and-coordinates.md), [ADR-004](../adr/ADR-004-atomic-capture-and-record-first-replay.md) |
| `GATE-003` | Native compositor correctness and physical-device viability | `FR-REPLACE-001`, `FR-REMOVE-001`, `NFR-RENDER-001` | [ADR-002](../adr/ADR-002-native-iphone-and-web-split.md), [ADR-005](../adr/ADR-005-realitykit-first-compositor.md) |
| `GATE-004` | Semantic provider, target mask, and tracking quality | `FR-TARGET-001`, `FR-REPLACE-001` | [ADR-007](../adr/ADR-007-segmentation-and-depth-providers.md), [ADR-008](../adr/ADR-008-scene-identity-and-readiness.md) |
| `GATE-005` | Fast mask volume, OBB, support, and view-envelope quality | `FR-TARGET-001`, `FR-REPLACE-001`, `FR-REMOVE-001` | [ADR-006](../adr/ADR-006-fast-and-dense-geometry-tracks.md), [ADR-008](../adr/ADR-008-scene-identity-and-readiness.md) |
| `GATE-006` | Multi-surface reveal and empty-removal credibility | `FR-REMOVE-001`, `FR-REPLACE-001`, `NFR-RENDER-001` | [ADR-001](../adr/ADR-001-product-modes-and-p0-scope.md), [ADR-005](../adr/ADR-005-realitykit-first-compositor.md), [ADR-009](../adr/ADR-009-multi-surface-reveal.md) |
| `GATE-007` | Learned depth and dense geometry viability | `FR-REPLACE-001`, `FR-REMOVE-001`, `NFR-COORD-001`, `NFR-LATENCY-001` | [ADR-006](../adr/ADR-006-fast-and-dense-geometry-tracks.md), [ADR-007](../adr/ADR-007-segmentation-and-depth-providers.md) |
| `GATE-008` | Provider-independent Mode B0 and web fallback | `FR-B0-001`, `FR-WEB-001`, `NFR-REPLAY-001` | [ADR-002](../adr/ADR-002-native-iphone-and-web-split.md), [ADR-013](../adr/ADR-013-mode-b0-guarantee.md) |
| `GATE-009` | Scene revisions, idempotency, local commit durability, reconnect, and restore | `FR-PLACE-001`, `FR-REPLACE-001`, `FR-REMOVE-001`, `FR-RESTORE-001`, `FR-TRANSACTION-001`, `NFR-RESILIENCE-001` | [ADR-008](../adr/ADR-008-scene-identity-and-readiness.md), [ADR-012](../adr/ADR-012-transaction-and-offline-restore.md) |
| `GATE-010` | P0 typed/agent safety and optional voice reliability | `FR-AGENT-001`, `STR-VOICE-001`, `SEC-AGENT-001`, `SEC-CREDENTIAL-001` | [ADR-011](../adr/ADR-011-agent-and-deterministic-boundary.md) |
| `GATE-011` | Asset normalization, integrity, delivery, and licensing | `FR-PLACE-001`, `FR-REPLACE-001`, `NFR-CONTRACT-001`, `OPS-LICENSE-001` | [ADR-010](../adr/ADR-010-asset-contract.md) |
| `GATE-012` | Selected runtime tier, network/service latency, VRAM, and bounded queues | `NFR-LATENCY-001`, `NFR-REPLAY-001`, `NFR-RESILIENCE-001` | [ADR-014](../adr/ADR-014-service-topology-and-hardware-tiers.md) |
| `GATE-013` | Signing, permissions, and base-iPhone build readiness | `OPS-DEVICE-001`, `FR-CAPTURE-001` | [ADR-002](../adr/ADR-002-native-iphone-and-web-split.md), [ADR-003](../adr/ADR-003-arkit-authority-and-coordinates.md), [ADR-005](../adr/ADR-005-realitykit-first-compositor.md) |
| `GATE-014` | Mode B1 scope/resource temptation | `STR-B1-001` and every P0 requirement | [ADR-001](../adr/ADR-001-product-modes-and-p0-scope.md), [ADR-013](../adr/ADR-013-mode-b0-guarantee.md), [ADR-014](../adr/ADR-014-service-topology-and-hardware-tiers.md) |

## 3. Gate records

### GATE-001 — Capture durability and replay determinism

- **Trigger:** A selected frame can become network-eligible before durable image/metadata/journal completion; a crash corrupts a prior record; or repeated replay changes accepted input/event order.
- **Measurement:** Run the versioned synthetic fixture plus physical-device captures of `TARGET: 10 seconds` and `TARGET: 60 seconds`; inject termination after every one of the five named lifecycle states. Validate exact image/packet hashes, RRFP framing, contiguous global journal, frame/event projections, RR-JCS digest vectors, manifest self-hash, recovered-prefix boundary, and two replays.
- **Deadline:** Exit of S1 capture/replay foundation, before any live provider integration.
- **Maximum recovery budget:** `TARGET: 4 engineering hours` inside S1.
- **Pass threshold:** `TARGET: 2 of 2` independent replays have identical RR-JCS global-journal digest/projections and expected order; `TARGET: zero` network references to non-journaled frames; `TARGET: zero` corruption of earlier records; recovery ends exactly at the last hash-valid contiguous journal record.
- **Fallback:** Reduce selected-frame cadence/resolution, pause upload first, preserve the valid local prefix, and continue provider work only against replay fixtures.
- **Effect on P0:** Blocking for Mode A capture and guaranteed Mode B0.
- **Final decision rule:** Any missed invariant or timebox leaves the gate `RED` and blocks live integration. No network-first variant may proceed.

### GATE-002 — RR-COORD-1, projection, orientation, and intrinsics

- **Trigger:** Any producer/consumer disagrees on pose direction, matrix layout, timestamp representation, pixel center, orientation, crop, scale, intrinsics, or world-frame version.
- **Measurement:** Cross-run the same synthetic rays and golden FramePackets in Swift, JavaScript, and Python; round-trip transforms; compare duplicated transport/JSON header fields; then use a physical checkerboard/orientation fixture in every supported device orientation and `TARGET: one` explicit world reset.
- **Deadline:** S0 contract lock and S1 device capture, before lifting masks or integrating depth.
- **Maximum recovery budget:** `TARGET: 4 engineering hours` before dependent geometry work stops.
- **Pass threshold:** `TARGET: maximum 1 encoded pixel` projection/reprojection error; `TARGET: zero` header/body mismatches; `TARGET: zero` orientation/crop swaps; every transform/intrinsics round trip and rigid-matrix validity check satisfies RR-FLOAT-1 exactly; reset creates a new world-frame version/correction rather than overwriting an epoch.
- **Fallback:** Reject/quarantine the packet or artifact, retain it in `.rrcap`, and restart/coaching the session; never guess a conversion.
- **Effect on P0:** Blocking for every spatial capability.
- **Final decision rule:** The allowed unexplained mismatch count is `TARGET: zero`; any mismatch is `RED`, and semantic lifting, fusion, reveal, and commits remain disabled until corrected and rerun.

### GATE-003 — Native compositor and device viability

- **Trigger:** RealityKit ordering, mask/reveal edges, depth writes, foreground occlusion, contact, frame time, memory, or thermal state fails on the base iPhone 17.
- **Measurement:** Compare RealityKit-first and the already-bounded minimal Metal spike using the canned multi-surface reveal/occluder/asset fixture plus the physical hero room. Inspect `TARGET: 8 poses`, run a `TARGET: 4-minute` session, capture FPS/frame-time/thermal/memory distributions, and conduct a blinded visual review.
- **Deadline:** First physical-device risk slice, before full replacement/removal integration.
- **Maximum recovery budget:** `TARGET: 4 engineering hours` for the bake-off; a Metal rewrite beyond the bounded spike is outside this budget.
- **Pass threshold:** `TARGET: zero` severe ordering/coverage artifacts at prescribed poses; `TARGET: median at least 45 FPS`; `TARGET: p95 frame time at most 33 ms`; `TARGET: zero` crash/jetsam; `TARGET: zero` sustained serious/critical thermal state; `TARGET: at least 4 of 5` blinded pass votes.
- **Fallback:** Reduce reveal/occluder complexity, preserve last-known-good artifacts, prefer the validated replacement composite, and activate provider-independent B0. Use Metal only if the bounded spike already passed.
- **Effect on P0:** Blocking for Mode A and empty removal; B0 remains viable but is not a substitute for the locked Mode A promise.
- **Final decision rule:** Kill any renderer variant that misses the threshold or timebox. If no variant passes, Mode A remains incomplete and requires explicit human scope action.

### GATE-004 — Semantic provider and target tracking

- **Trigger:** The chosen segmentation/tracking provider loses identity, leaks materially outside the target, cannot recover from occlusion/re-entry, exceeds the selected tier, or lacks usable license/access evidence.
- **Measurement:** Use `TARGET: 20 annotated hero frames` plus one `TARGET: 60-second` `.rrcap` containing occlusion, re-entry, lighting change, and fast motion. Compare pinned SAM 2.1 Hiera Small and an accessible, license-approved SAM 3.1 checkpoint on IoU, boundary leakage, identity switches, seed-to-first-mask p50/p95, sustained queue growth, VRAM, cold/warm startup, access, and license. Frozen/manual masks remain the fallback reference.
- **Deadline:** S3 target/fast-geometry slice before semantic live integration.
- **Maximum recovery budget:** `TARGET: 4 engineering hours`.
- **Pass threshold:** `TARGET: median IoU at least 0.80`; `TARGET: P10 IoU at least 0.65`; `TARGET: zero` hero-target identity switches; `TARGET: seed-to-first-mask p95 at most 1.5 seconds`; `TARGET: zero` sustained queue growth; the provider fits the selected tier and has recorded artifact access/license evidence.
- **Fallback:** SAM 2.1 Hiera Small wins a tie/timebox; otherwise use versioned frozen masks/manual box re-seed for the controlled fixture and keep unsupported capability unavailable.
- **Effect on P0:** Blocking for target-ready replace/remove; capture, place, transactions, and B0 replay can continue.
- **Final decision rule:** Select the smallest accessible licensed provider that passes. If none passes, kill live automatic tracking for the fixture and use the explicit manual/frozen fallback; do not silently guess identity.

### GATE-005 — Fast mask volume, OBB, support, and view envelope

- **Trigger:** Multi-view lifting changes target identity/support, leaves target pixels uncovered in supported views, overpaints foreground, produces unstable OBB dimensions, or claims collision-quality geometry.
- **Measurement:** Lift calibrated masks from `TARGET: 3 to 5` hero views into the conservative mask volume, OBB, and support relation; replay prescribed in-envelope and out-of-envelope poses; compare projections with annotations and taped dimensions.
- **Deadline:** End of S3, before signature replacement readiness.
- **Maximum recovery budget:** `TARGET: 4 engineering hours` including one request-for-more-views retry.
- **Pass threshold:** `TARGET: projection recall at least 0.95` at every prescribed in-envelope view; `TARGET: foreground spill at most 0.05` of projected target area; `TARGET: OBB dimension variation at most 10%` across fixture replays; `TARGET: zero` identity/support changes; out-of-envelope poses must coach or disable commit.
- **Fallback:** Request additional calibrated views, shrink the supported envelope, enlarge only the conservative visual proxy, and keep dense/collision claims unavailable.
- **Effect on P0:** Blocking for replace/remove readiness; place on a confirmed ARKit plane and B0 remain available.
- **Final decision rule:** If the retry misses the threshold or budget, kill automatic replace/remove readiness for that capture and keep the UI explicit; dense geometry cannot override this gate.

### GATE-006 — Multi-surface reveal and empty removal

- **Trigger:** The reveal bundle lacks supported observed background, exposes seams/uncovered target pixels, overpaints foreground, or changes implausibly during the prescribed walk-around.
- **Measurement:** On the controlled hero capture with at least `TARGET: 8 trajectory poses`, compare observed-only atlas, deterministic local fill, and the simplest already license-approved fallback. Record P10/median target coverage, largest uncovered component, synthesized fraction/provenance, foreground overwrite, surface ordering/seams, and blinded walk-around votes.
- **Deadline:** Exit of S5 quality-gated removal, before P0 release declaration.
- **Maximum recovery budget:** `TARGET: 1 implementation slice`, with no general diffusion or general 3D-inpainting expansion.
- **Pass threshold:** `TARGET: P10 coverage at least 0.95`, not above median; `TARGET: median coverage at least 0.98`; `TARGET: largest uncovered component at most 1%` of target area; `TARGET: zero` severe foreground overwrite or surface-order artifacts; exactly `5` blinded votes with `4–5` passes.
- **Fallback:** Request another view, shrink the supported envelope, choose the easier locked target, and keep session removal unavailable while replacement remains independently available.
- **Effect on P0:** Blocking for the human-locked empty-removal release promise.
- **Final decision rule:** Failure keeps P0 incomplete. It cannot be silently relabeled experimental; only an explicit human change to the locked promise can waive the gate.

### GATE-007 — Learned depth and dense geometry

- **Trigger:** Learned depth is metrically wrong, temporally unstable, too slow/heavy, unavailable under a permissible license, or causes dense fusion to accumulate unsupported geometry.
- **Measurement:** Replay the same versioned `.rrcap` with a taped floor and `TARGET: 3 taped distances` through DA3Metric-Large, pose-conditioned Apache-licensed DA3 Small/Base, and no-dense. Evaluate floor RMSE, every taped-distance relative error, static-region flicker, accepted-update p50/p95, rejection rate, VRAM/OOM, bounded queue behavior, and Open3D `0.19.0` output when enabled.
- **Deadline:** Provider selection in S3/S4, before any dense result enters readiness or demo claims.
- **Maximum recovery budget:** `TARGET: 4 engineering hours`.
- **Pass threshold for live enhancement:** `TARGET: floor RMSE at most 0.025 m`; `TARGET: every taped-distance error within plus or minus 4%`; `TARGET: accepted-update p95 at most 450 ms`; `TARGET: zero` sustained queue growth during a `TARGET: 2-minute` replay; `TARGET: zero` OOM; dense output never rewrites ARKit trajectory or stable IDs.
- **Fallback:** Disable learned dense geometry; use ARKit planes/raycasts/feature points, mask volume, OBB, and degraded point/plane B0.
- **Effect on P0:** Nonblocking when the no-dense fallback satisfies the fast path; blocks only claims/capabilities that explicitly require dense evidence.
- **Final decision rule:** Select a passing provider only if its incremental capability justifies the runtime. A tie, timebox miss, license/access gap, or threshold miss selects no-dense.

### GATE-008 — Guaranteed Mode B0 and web fallback

- **Trigger:** B0 needs a live GPU/learned provider, cannot validate/import/replay the golden capture, loses the canonical transaction timeline, or represents ordinary video geometry as guaranteed.
- **Measurement:** Disable learned providers and live GPU/network. Import the golden `.rrcap`, validate inventory/hashes, replay `TARGET: 2 times`, inspect canonical scene/artifacts/transactions, execute a typed fixture transaction, and upload/replay ordinary video with geometry explicitly unavailable. Exercise camera denial, unsupported codec, quota exhaustion, and network loss in the web client.
- **Deadline:** S7 web/B0 resilience, with the replay core green in S1.
- **Maximum recovery budget:** `TARGET: 1 implementation slice` after the S1 replay core.
- **Pass threshold:** `TARGET: 2 of 2` replays produce the same accepted event digest and revision trace; `TARGET: zero` learned-provider calls; all corrupt/missing data degrades explicitly; acknowledged commits remain present; ordinary video media/timeline works without claiming metric geometry.
- **Fallback:** File upload plus timeline/metadata and point/plane/cached-artifact view; preserve provider-unavailable status.
- **Effect on P0:** Blocking for the guaranteed B0 promise.
- **Final decision rule:** B0 failure blocks P0. LingBot, dense reconstruction, WebCodecs, and live GPU failure do not fail this gate when the minimum path passes.

### GATE-009 — Transactions, idempotency, offline restore, and reconnect

- **Trigger:** Preview mutates state; retry duplicates an edit; stale revision commits; idempotency-key collision is accepted; artifact activation is partial; offline restore needs the server; or reconnect loses/merges state silently.
- **Measurement:** Execute exact ordered reducer traces covering preview/cancel, preview-bound explicit confirmation, commit, same-key/fingerprint retry, changed-fingerprint conflict, stale base, wrong authority/branch, crash after activation, offline device commit/restore, idempotent journal replication, injected divergent same-branch history, quarantine, and snapshot reconciliation.
- **Deadline:** S2 deterministic place transaction; rerun for S4/S5 edits and S8 resilience.
- **Maximum recovery budget:** `TARGET: 1 implementation slice` in S2; later failures return to S2 rather than adding compensating hacks.
- **Pass threshold:** `TARGET: zero` preview revision increments; each branch-authority commit/restore increments exactly once; `TARGET: zero` duplicate/unauthorized mutations or automatic merges; divergence stops mutation and is quarantined under another branch; `TARGET: zero` lost acknowledged edits; restore uses only hash-valid local artifacts/snapshots while offline; expected and actual branch/revision traces match exactly.
- **Fallback:** Do not acknowledge or allow further commits; preserve local evidence, render the last activated revision, fetch canonical snapshot after reconnect, and require deterministic reconciliation.
- **Effect on P0:** Blocking for all four operations.
- **Final decision rule:** Any mismatch is `RED` and blocks edit commits. No model/provider result can waive transaction invariants.

### GATE-010 — Typed/agent safety and optional voice boundary

- **Trigger:** Typed/agent input mutates directly, selects the wrong target/operation, bypasses confirmation/revision/license checks, exposes a credential, or optional voice becomes the only usable path.
- **Measurement:** First disable network/models and run every golden edit plus ambiguity, malformed-schema, stale-context, duplicate, prompt/tool injection, model-URL, and transform injection through typed/tap ingress. Only after that passes, run `TARGET: 5 fixed hero utterances` through optional voice.
- **Deadline:** P0 typed/injection boundary in S2/S4; optional voice in S6 only after `GATE-009` is green.
- **Maximum recovery budget:** Typed/injection defects return to the blocking transaction slice; optional voice gets `TARGET: 1 voice slice`.
- **Pass threshold:** P0 typed/tap completes `100%` of golden edits and rejects `100%` malformed/adversarial cases with `zero` unconfirmed mutation/credential exposure. Optional voice yields at least `4 of 5` expected nonmutating proposals and rejects all adversarial cases.
- **Fallback:** Disable Realtime/model tools and use typed/tap through the same deterministic proposal/transaction boundary.
- **Effect on P0:** Typed/injection failure is blocking. Optional voice failure falls back to typed/tap and does not change P0 status.
- **Final decision rule:** A voice threshold/timebox miss ends voice work for the week. Any unsafe mutation is an immediate kill independent of aggregate intent accuracy.

### GATE-011 — Asset contract, parity, and licensing

- **Trigger:** A hero asset lacks exact source/license/attribution/digest, is not redistributable, loads only over the network at command time, or its USDZ/GLB derivatives disagree materially in units/origin/axis/dimensions/collision/cover.
- **Measurement:** Review the shipping bill of materials and each canonical asset manifest; verify hashes, metres, floor-contact origin, forward axis, bounds, collision proxy, texture/LOD budgets, local availability, device/web loading, and USDZ/GLB dimension/visual parity.
- **Deadline:** S0/S2 before an asset enters place/replace; repeat at S8 shipping freeze.
- **Maximum recovery budget:** `TARGET: 2 engineering hours per candidate asset`, with a `TARGET: 1-day` catalog freeze before final evidence capture.
- **Pass threshold:** `TARGET: 100%` of shipped assets/models/fonts/libraries have exact artifact/version/digest, source, applicable terms, attribution, and approved redistribution/use; `TARGET: zero` noncommercial or unknown shipping dependencies; `TARGET: dimension parity within 1%` between validated derivatives; `TARGET: zero` command-time network fetches for hero assets.
- **Fallback:** Exclude the asset/component and use the smallest already validated permissive catalog or observed deterministic method.
- **Effect on P0:** A single asset can be removed without blocking P0 if a valid hero alternative remains; no valid place/replace asset blocks those operations.
- **Final decision rule:** No exception is allowed on demo/submission day. Unknown, gated-without-acceptance, or noncommercial evidence excludes the artifact.

### GATE-012 — Runtime tier, network/service latency, and queues

- **Trigger:** The selected live profile exceeds tier VRAM, crashes/OOMs, grows a queue, loses session isolation/state on reconnect, or fails to publish usable latency distributions.
- **Measurement:** On each declared capability tier, load only gate-selected providers and run a `TARGET: 4-minute` live-equivalent/replay soak plus `TARGET: 20` forced disconnect/reconnect cycles. Record p50/p95/max capture-to-preview spans, transport/queue/provider stages, mask age, VRAM, process restarts, queue depth/drops, session-state recovery, and cross-session leakage checks.
- **Deadline:** S8 hardening before the tier is named in a demo claim.
- **Maximum recovery budget:** `TARGET: 1 implementation slice`; no new cloud/database/orchestration platform may be added within this recovery.
- **Pass threshold:** `TARGET: zero` OOM/crash; `TARGET: zero` unbounded queue growth; `TARGET: zero` lost acknowledged edits or cross-session state; `TARGET: reconnect snapshot recovery at most 2 seconds`; `TARGET: p95 mask age at most 250 ms` for a capability advertised live; every named stage reports p50/p95/max and drop counts.
- **Fallback:** Unload mutually exclusive providers, serialize GPU lanes, reduce cadence/resolution, use cached artifacts, select no-dense, and preserve capture/B0. A later deployment may use one warm Pod plus external commit persistence, but cloud deployment is outside PRE-GSD preparation.
- **Effect on P0:** Blocks only the declared live tier/capability; provider-independent local capture/transactions/B0 remain the safety ladder.
- **Final decision rule:** Drop any optional provider or tier that misses stability/bounds. Do not hide a mandatory GPU SKU or add infrastructure to rescue a failed optional path.

### GATE-013 — Signing and base-iPhone preflight

- **Trigger:** The current Xcode/signing/Developer Mode path cannot install and launch a minimal build on the physical base iPhone 17, or permissions/ARKit world tracking/planes fail without LiDAR semantics.
- **Measurement:** Record tool/device versions, perform a clean signed build, install/launch, grant/deny camera and microphone permissions, start ARKit world tracking and plane detection, record a short FramePacket fixture, and save logs/screenshots/checksum.
- **Deadline:** S0, before architecture-sensitive mobile implementation.
- **Maximum recovery budget:** `TARGET: 4 engineering hours`; B0/contract work may continue independently.
- **Pass threshold:** `TARGET: 1` repeatable clean signed install/launch on the base device; camera consent behaves correctly; ARKit pose/planes work with LiDAR-only semantics disabled; a hash-valid short capture is recovered; the build record is reproducible.
- **Fallback:** Stop the mobile critical path and resolve account/signing/toolchain/device access while continuing contracts and provider-independent B0.
- **Effect on P0:** Blocking for Mode A, compositor, and physical-device evidence.
- **Final decision rule:** No simulator-only substitute. A failed preflight keeps Mode A gates `UNRUN/RED` and prevents readiness claims.

### GATE-014 — Mode B1 isolation

- **Trigger:** A B1 package, provider, worker, task, schema requirement, or resource becomes a dependency of any P0 slice; B1 work starts while a P0 gate is red; or B1 rewrites Mode A identity/history.
- **Measurement:** Inspect dependency graph, manifests, worker profiles, plans, schemas, and resource schedule at every slice exit; attempt deletion/disablement of all B1 components and rerun P0 contract tests.
- **Deadline:** Continuous from S0 through P0 completion; explicit review before any post-P0 B1 start.
- **Maximum recovery budget:** `TARGET: zero scheduled P0 engineering hours` for B1 while any P0 gate is red.
- **Pass threshold:** `TARGET: zero` P0 dependencies on B1; `TARGET: zero` B1 workers/tasks while a P0 gate is red; P0 tests pass with all B1 components absent; any B1 result maps to stable IDs and is discardable without canonical-state change.
- **Fallback:** Do not implement B1; remove its package/profile/task and preserve only the provider boundary/documentation.
- **Effect on P0:** Protects the entire critical path; B1 has no P0 entitlement.
- **Final decision rule:** Any violation immediately kills B1 work. It may start only after every blocking P0 gate is green and a human explicitly authorizes the stretch.

## 4. Cross-cutting release blockers

The following are not additional gate IDs; they are mandatory checks attached to the mapped gate:

- `SEC-AGENT-001` prompt/tool injection and `SEC-CREDENTIAL-001` secret isolation are blocking subchecks of `GATE-010`.
- Consent, retention, deletion, and share-link behavior under `SEC-CONSENT-001` and `SEC-RETENTION-001` are blocking subchecks of `GATE-001`, `GATE-008`, and `GATE-009` where applicable.
- Shipping bill-of-materials completeness under `OPS-LICENSE-001` is a blocking subcheck of `GATE-011`.
- `OPS-GOLDEN-001` requires `TARGET: 5 of 5` complete place/replace/remove/restore plus B0 runs after all gates are green.
- `OPS-SUBMISSION-001` additionally requires the independently verified Build Week evidence checklist in research claims `CLM-026` and `CLM-027`.

## 5. Gate evidence record

For every execution, store or link a compact record with:

1. gate ID and state;
2. UTC start/end and deadline slice;
3. requirement and ADR links;
4. fixture IDs and SHA-256 digests;
5. source/build commit, schema versions, device/OS, runtime tier, provider code/checkpoint/license revisions;
6. exact commands or test harness revision;
7. raw logs, traces, screenshots/video, metric output, and visual ballots;
8. TARGET threshold beside the measured result, without relabeling the target;
9. failure classification and recovery time consumed;
10. selected fallback and final decision.

Measured results belong in evidence artifacts and audit reports. This canonical file changes only when the governing requirement, decision, or TARGET changes.
