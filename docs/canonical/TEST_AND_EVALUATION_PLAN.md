# ReRoom Test and Evaluation Plan

Status: canonical quality authority
Version: 1.0.0  
Date: 2026-07-13

## 1. Purpose and result language

This plan defines the evidence needed to decide whether ReRoom's controlled P0 is ready. Requirement behavior is owned by [PRD.md](PRD.md), terminology by [GLOSSARY_AND_ID_REGISTRY.md](GLOSSARY_AND_ID_REGISTRY.md), contract fields by `docs/contracts/`, and final kill decisions by [RISK_AND_KILL_GATES.md](RISK_AND_KILL_GATES.md).

All numeric acceptance values in this plan are explicitly labeled **TARGET**. They are not measured performance. A result may be called `MEASURED` only when it links the immutable fixture, implementation revision, environment, raw evidence, and metric calculation. Product copy may not convert a TARGET or HYPOTHESIS into a claim.

## 2. Test classes and evidence ownership

| Class | Purpose | Typical execution | Required evidence |
|---|---|---|---|
| **Automated contract/unit** | Pure schema, transform, identity, lifecycle, transaction, security, and persistence invariants | Local deterministic runner; no network/model required | Machine-readable report, inputs/expected outputs, command, revision, dependency lock |
| **Replay-based** | Repeatable provider, queue, geometry, tracking, transaction, and failure comparison over `.rrcap` | Pinned fixture and provider/runtime; live timing may be simulated only when labeled | Fixture/provider digests, traces, metric arrays/distributions, output artifact hashes |
| **Device/manual** | Camera, orientation, ARKit, compositor, performance, thermal, signing, permissions, and tracking-loss behavior | Physical base iPhone 17; simulator results are supplemental only | Device/OS/build, run video, Instruments/MetricKit or equivalent logs, screenshots, operator checklist |
| **Human visual** | Reveal credibility, surface ordering, foreground overwrite, replacement plausibility, readiness comprehension, and demo coherence | Blinded prescribed poses/order; no developer coaching during score | Ballot, randomized variant labels, evaluator count, source video, severe-artifact annotations |

No provider-specific output becomes canonical identity. Neural reproducibility means pinned input/provider/runtime plus metric tolerances; it is not assumed bitwise unless a provider separately proves that property.

## 3. Canonical fixtures

| Fixture ID | Contents and purpose | Freeze evidence |
|---|---|---|
| `FX-CONTRACT-001` | Valid and invalid instances for CON-001 through CON-005, including unknown/exact minor/major versions, illegal lifecycle and extra fields, missing confirmation/reference, malformed prefixed IDs, unsafe integer timestamp, binary32 overflow, path traversal, branch/authority mismatch, missing/wrong artifact spatial encoding, ready reveal/asset violations, and hash/digest mismatch | Schema `$id`, fixture SHA-256, expected verdict/error code |
| `FX-JCS-001` | Frozen RFC 8785 inputs and exact UTF-8/hex outputs for packet, global journal tuple array, manifest self-member omission, artifact, RR-EDIT-PROJECTION-1, transaction fingerprint, validation input, and commit-result scopes | Source JSON bytes, canonical bytes hex, SHA-256, scope/version, independent Swift/JavaScript/Python outputs |
| `FX-COORD-001` | Known camera matrices/rays, half-pixel cases, crop/scale/rotation cases, RRFP-WIRE-1 duplicated transport fields, OpenCV conversion, and directed world-reset/relocalization corrections | Generator revision, expected projected pixels/transforms, tolerance |
| `FX-RRCAP-010S` | `TARGET: 10-second` physical capture for crash/durability tests | Device/build, manifest and file digests, accepted order |
| `FX-RRCAP-060S` | `TARGET: 60-second` golden replay with occlusion, re-entry, lighting change, fast motion, planes, target seed, typed events, and one world-reset variant | Same as above plus annotation revision and event/revision oracle |
| `FX-HERO-ROOM-001` | Controlled armchair or small table with visible floor, taped floor and `TARGET: 3 taped distances`, multi-surface reveal, foreground occluder, curated assets, and prescribed trajectory | Room/target photos, taped measurements, trajectory/pose list, asset digests |
| `FX-SEM-020` | `TARGET: 20` hand-annotated hero frames sampled from the golden replay | Annotation tool/reviewer, masks, target ID, boundary policy |
| `FX-TX-001` | Exact place/replace/remove/restore reducer traces with preview/explicit confirmation/cancel, duplicate same-fingerprint retry, changed-fingerprint conflict, wrong authority/branch, stale base, crash, offline device commit/restore, idempotent journal replication, and divergent-branch quarantine | Expected states, branches/revisions, ordered operation/inverse/snapshot digests, confirmation IDs, conflict codes |
| `FX-AGENT-001` | `TARGET: 5` hero utterances plus ambiguity, malformed arguments, stale context, duplicate, prompt/tool injection, secret and URL/transform injection | Expected nonmutating proposal/rejection/clarification and target snapshot |
| `FX-WEB-001` | Golden capture/video plus camera denial, unsupported codec, quota exhaustion, corrupted suffix, and network-loss scenarios | Browser/OS matrix, expected degraded state and preserved data |

Fixture changes require a new fixture revision and digest. A failing implementation may not edit a fixture or threshold in place to obtain a pass.

## 4. Automated contract and state tests

| Test ID | Requirements / ADRs | Procedure and evidence | Acceptance |
|---|---|---|---|
| `TST-CONTRACT-001` Schema syntax and IDs | `NFR-CONTRACT-001`; [ADR-003](../adr/ADR-003-arkit-authority-and-coordinates.md), [ADR-008](../adr/ADR-008-scene-identity-and-readiness.md), [ADR-012](../adr/ADR-012-transaction-and-offline-restore.md) | Parse all JSON/JSON Schemas; validate `FX-CONTRACT-001`; check unique `$id`, local references, closed enums/objects, required fields, binary32 bounds, and every registry prefix. Include nil, uppercase, wrong-version/variant, missing-hyphen, all-hyphen, renderer-index, wrong-prefix, `1e300`, NaN/Infinity, durability state/eligible disagreement, illegal tracking state/reason pairs, P10>median, vote pass>total, bounds min≥max, missing/wrong mesh coordinate space, voxel transform/shape/layout/dtype/value/center mismatch, absent or malformed reveal planar/UV mapping, wrong variant codec, world correction target≤source/base mismatch, unknown/empty/ready-with-blocker readiness reasons, and cross-branch artifact negatives. | **TARGET:** `100%` golden-valid fixtures pass and golden-invalid fixtures fail with the expected class; `TARGET: zero` duplicate `$id`, missing reference, malformed/stale identity, non-finite/out-of-range numeric, spatially undecodable payload, or impossible cross-field evidence accepted. |
| `TST-CONTRACT-002` Compatibility | `NFR-CONTRACT-001`; CON-001–CON-005 | Execute the contracts README verdict matrix: exact 1.0, 1.0+unknown field, 1.1 sent to 1.0 reader, named 1.0→1.1 migration, representable/unrepresentable 1.1→1.0 down-conversion, and unknown major/codec/coordinate/digest scope. | **TARGET:** exact documented verdict for every fixture; old readers never infer minor compatibility or drop fields; unknown/breaking input rejects or enters read-only quarantine with zero mutation. |
| `TST-CONTRACT-003` Archive-relative path safety | `NFR-CONTRACT-001`, `SEC-RETENTION-001`; CON-001, CON-002, CON-004 | Validate allowed normalized paths and malicious absolute, drive-letter, UNC/backslash, dot, dot-dot, empty-segment, and traversal cases for every packet/manifest/artifact path field; repeat after transport decoding and before filesystem resolution. | **TARGET:** `100%` malicious paths reject before any filesystem read/write; valid normalized forward-slash paths resolve inside the intended capture/artifact root. |
| `TST-COORD-001` Projection and transforms | `NFR-COORD-001`, `FR-CAPTURE-001`; [ADR-003](../adr/ADR-003-arkit-authority-and-coordinates.md) | Run `FX-COORD-001` in Swift, JavaScript, and Python; compare pixel centers, `world_from_camera`, row-major serialization/column-vector math, inverse, OpenCV conversion, and `p_to=T_to_from_from·p_from` reset/relocalization vectors. Include nonfinite, binary32 overflow, nonorthonormal, reflection, invalid homogeneous row, reversed/equal versions, base-target mismatch, and unknown-transform-as-artifact negatives. | **TARGET:** maximum reprojection error `1 encoded pixel`; every numeric/transform round trip satisfies RR-FLOAT-1; every correction direction/version/inversion oracle matches; language outputs agree under the same named policy. |
| `TST-COORD-002` Orientation, crop, intrinsics | `NFR-COORD-001`, `FR-CAPTURE-001`; [ADR-003](../adr/ADR-003-arkit-authority-and-coordinates.md), [ADR-004](../adr/ADR-004-atomic-capture-and-record-first-replay.md) | Apply every supported orientation/crop/scale; verify physically upright bytes, `encoded_from_sensor`, encoded-pixel intrinsics, image dimensions, and duplicated binary-header/JSON fields. | **TARGET:** `zero` orientation/crop swaps; `TARGET: zero` duplicated-field mismatch; checkerboard corners remain within `TARGET: 1 encoded pixel`. |
| `TST-WIRE-001` RRFP-WIRE-1 framing | `FR-CAPTURE-001`, `NFR-CONTRACT-001`; CON-001 | Independently encode/decode magic/version/flags, big-endian lengths and capture sequence, JCS header, and exact image bytes in Swift/JavaScript/Python. Inject truncation, trailing bytes, nonzero flags, bad magic/version, over-limit header/payload, duplicate length/sequence mismatch, inline/file SHA mismatch, and one-bit image tamper. | **TARGET:** valid bytes round-trip identically; `100%` malformed/tampered envelopes reject atomically before journal/network acceptance. |
| `TST-SCENE-001` Identity/readiness | `FR-TARGET-001`, `NFR-CONTRACT-001`; [ADR-008](../adr/ADR-008-scene-identity-and-readiness.md) | Reject renderer/provider indices, dangling IDs, unknown readiness-reason capability/code, any non-ready capability without a reason, ready capability with a blocker reason, missing canonical object edit state, active reveal while visible, illegal lifecycle/readiness transitions, wrong authority/branch, stale/cross-world or unactivated artifacts, and world-frame overwrite. Exercise direct `unsupported_target_category`, `provider_unavailable`, `no_eligible_restore`, and `world_frame_mismatch` reasons. | **TARGET:** `100%` invalid fixtures reject without mutation; activation changes only the intended capability/readiness/edit state; stable IDs survive renderer/provider replacement; two revision-7 branches never alias. |
| `TST-TX-001` Revision, authority, and idempotency | `FR-TRANSACTION-001`, `FR-PLACE-001`, `FR-REPLACE-001`, `FR-REMOVE-001`; [ADR-012](../adr/ADR-012-transaction-and-offline-restore.md) | Execute preview, explicit confirmation, commit, same-key/same-fingerprint retry, same-key/different-fingerprint conflict, stale base, wrong authority/branch, cancel, offline native commit, reconnect replication, and an injected gateway/device divergent same-branch revision. | **TARGET:** preview/cancel cause `zero` increments; each authority-accepted commit increments exactly once; offline journal replicates idempotently; divergence stops mutation and is quarantined under a new branch with no automatic merge; expected trace matches exactly. |
| `TST-TX-002` Ordered reducer, inverse, and restore | `FR-RESTORE-001`, `FR-TRANSACTION-001`; [ADR-012](../adr/ADR-012-transaction-and-offline-restore.md) | Execute the exact MTS reducer lists for place, both replace variants, remove, and restore in native/JavaScript/Python reducers. Verify canonical object `edit_state`, reveal-before-hide, asset/support creation last and atomic, full manifest/reveal reference identity/revision/digest binding, one captured-exact RR-EDIT-PROJECTION-1 inverse, lexicographic/unique projection IDs, asset/support referential integrity, exact after-projection artifact-reference union, latest-eligible compensation, RR-RESTORE-REBASE-1 touched-ID derivation/source-operation identity/source hashes/current-before equality, and preservation of excluded tracking/readiness/surface fields. Insert a newly tracked object plus readiness update after the source edit but before restore; it must survive unchanged. Separately mutate one touched value before restore; the rebase must reject as unexpected touched-entity drift. | **TARGET:** all reducers yield the same SceneState digest/revision; restore reverts exactly the verified touched edit content inside a current-complete fresh `r+1` envelope, preserves the new/unaffected object, appends history, and has a new whole-document digest; original history/evidence are immutable; wrong order/current projection/hash/derivation/source/touched drift/branch/world/reference union/dangling support/later-edit compensation rejects; `zero` offline network reads. |
| `TST-TX-003` Lifecycle/intent/confirmation-invalid transactions | `FR-TRANSACTION-001`, `FR-RESTORE-001`, `SEC-AGENT-001`; CON-005 | Attempt committed records with failed/empty/failed-member validation, no preview/confirmation, mismatched confirmation preview, model/service actor, wrong authority/branch, empty/non-snapshot inverse, null undo token, or missing commit. Put commit/inverse extras on draft/validated/rejected/cancelled; make failed validation contain no failed check; omit operation-specific check IDs; inject forbidden model arguments and wrong delta lists/orders. | **TARGET:** `100%` invalid fixtures fail schema/reducer validation without mutation; committed records require passed nonempty operation-specific checks, preview-bound explicit user confirmation, matching authority/branch, one snapshot inverse, and nonnull undo token. |
| `TST-ARTIFACT-001` Artifact readiness/provenance | `FR-REMOVE-001`, `OPS-LICENSE-001`, `NFR-CONTRACT-001`; CON-004 | Validate branch origin/activation, authority, JCS content scope, world epoch, ready reveal thresholds/cross-relations, and ready asset source/license/attribution/bounds/delivery. Include P10>median, 100% foreground overwrite/severe flag, vote 4/100 or pass>total, nonredistributable ready asset, empty required attribution, min≥max bounds, and silent cross-fork reuse. | **TARGET:** `100%` invalid readiness/provenance fixtures reject; cross-fork reuse requires a new activation record with preserved origin/content hash and compatible world epoch. |
| `TST-PERSIST-001` Atomic local commit | `FR-TRANSACTION-001`, `FR-RESTORE-001`, `NFR-RESILIENCE-001` | Inject termination before and after transaction, inverse, artifact, hash, and activated-revision writes; restart with no network. | **TARGET:** visible acknowledgement occurs only for a fully hash-valid activated bundle; `TARGET: zero` acknowledged edit loss; partial data remains nonactive and diagnosable. |
| `TST-QUEUE-001` Bounded work | `NFR-REPLAY-001`, `NFR-RENDER-001`; [ADR-004](../adr/ADR-004-atomic-capture-and-record-first-replay.md), [ADR-014](../adr/ADR-014-service-topology-and-hardware-tiers.md) | Submit above-rate inputs; make provider completion reorder; blackhole network/model; compare durable order with live completion. | Queue never exceeds configured capacity; stale-drop counter increases; `TARGET: zero` render-thread waits; replay preserves accepted order regardless of live completion. |

## 5. Capture and deterministic replay tests

| Test ID | Requirements / gate | Procedure and evidence | Acceptance |
|---|---|---|---|
| `TST-CAPTURE-001` Record-first crash matrix | `FR-CAPTURE-001`, `SEC-CONSENT-001`; `GATE-001` | Use `FX-RRCAP-010S` and `FX-RRCAP-060S`; deny consent, then with consent terminate after `selected`, `image_and_metadata_durable`, `journaled`, `network_eligible`, and `server_acknowledged`; verify exact event names, packet/image hash binding, and recovered global-journal prefix. | **TARGET:** denied consent creates no `.rrcap`; `zero` upload references to non-journaled frames; `zero` earlier-record corruption; recovered prefix stops at the last hash-valid contiguous journal record. |
| `TST-DIGEST-001` RR-JCS-SHA256-1 vectors | `NFR-CONTRACT-001`, `NFR-REPLAY-001`, `FR-TRANSACTION-001`; CON-001–CON-005 | Run `FX-JCS-001` in Swift/JavaScript/Python. Verify raw-file bytes, JSON number/string/key canonicalization, global journal tuple construction, manifest/artifact/commit self-member omission, exact transaction fingerprint member inclusion/exclusion, validation input, and complete RR-EDIT-PROJECTION-1 member. Toggle each included/excluded member and one byte; prove snapshot revision/origin/derivation metadata is outside the projection digest while branch/world/edit content is inside, and that a restore proposal's transaction fingerprint still binds the derivation metadata. | **TARGET:** canonical UTF-8 hex and lowercase SHA-256 match exactly in all languages; included changes alter digest, excluded changes do not, and wrong algorithm/scope rejects. |
| `TST-REPLAY-001` Input/event determinism | `FR-B0-001`, `NFR-REPLAY-001`; `GATE-001`, `GATE-008` | Replay each frozen fixture independently **TARGET: at least 2 times** with learned providers disabled; recompute every event record digest, project accepted frames/events solely from the contiguous global journal, require exact membership/order/reference/durable sequence/content hash and contiguous per-type sequence, verify final sequence, recompute the ordered journal-tuple input digest, and compare revision trace. | **TARGET:** `2 of 2` runs produce identical RR-JCS input digest/projections/revision trace; every event, raw file, final sequence, and manifest hash validates. |
| `TST-REPLAY-002` Corrupt/truncated capture | `FR-B0-001`, `NFR-CONTRACT-001` | Remove/corrupt tail files; duplicate/gap/reorder global sequence; omit/add/reorder a projected event/frame; mismatch journal reference/durable sequence/packet or event-record hash; mismatch per-type sequence, final sequence, or recomputed input digest; change manifest self-hash; introduce unsafe path or unsupported version/codec/digest. | **TARGET:** `100%` corrupt cases fail closed or recover only the documented prefix; raw evidence remains quarantined; no array order/timestamp tie-break or fabricated/missing frame/event enters replay. |
| `TST-REPLAY-003` Neural tolerance policy | `NFR-REPLAY-001`, `NFR-LATENCY-001`; [ADR-007](../adr/ADR-007-segmentation-and-depth-providers.md) | Pin provider code/checkpoint/runtime/hardware class; run repeated inference; store raw outputs and distribution metrics. | The report distinguishes deterministic input digest from tolerance-evaluated neural output; any provider without a pin/license/tolerance policy is ineligible. |

## 6. Provider and geometry bake-offs

### TST-SEM-001 — Semantic provider and target resolution

- **Requirements/decisions:** `FR-TARGET-001`, `FR-REPLACE-001`, `NFR-LATENCY-001`; [ADR-007](../adr/ADR-007-segmentation-and-depth-providers.md), [ADR-008](../adr/ADR-008-scene-identity-and-readiness.md); `GATE-004`.
- **Fixture/variants:** `FX-SEM-020` plus `FX-RRCAP-060S`; pinned SAM 2.1 Hiera Small versus an accessible, license-approved SAM 3.1 checkpoint. Frozen/manual masks are the fallback reference, not an automatic-provider competitor.
- **Metrics:** IoU distribution, boundary leakage/foreground precision, hero identity switches, seed-to-first-mask p50/p95, queue depth, cold/warm startup, VRAM, access, artifact license/digest.
- **Acceptance:** **TARGET:** median IoU `at least 0.80`; **TARGET:** P10 IoU `at least 0.65`; **TARGET:** `zero` hero-target identity switches; **TARGET:** seed-to-first-mask p95 `at most 1.5 seconds`; **TARGET:** `zero` sustained queue growth; selected-tier fit and license/access evidence are mandatory.
- **Timebox/deadline/fallback:** **TARGET:** `4 hours`, before semantic integration. A tie/timebox selects SAM 2.1 Hiera Small; threshold failure uses frozen/manual masks and explicit re-seed/readiness failure.

### TST-GEOMETRY-001 — Fast mask volume, OBB, support, and floor stability

- **Requirements/decisions:** `FR-TARGET-001`, `FR-REPLACE-001`, `FR-REMOVE-001`, `NFR-COORD-001`; [ADR-006](../adr/ADR-006-fast-and-dense-geometry-tracks.md); `GATE-005`.
- **Fixture/variants:** `FX-HERO-ROOM-001`, using **TARGET:** `3 to 5` calibrated views; compare configured conservative dilation/view envelope variants without changing identity.
- **Metrics:** target projection recall, foreground spill, OBB dimension variation, floor/support ID stability, supported-view violations, taped-dimension error.
- **Acceptance:** **TARGET:** projection recall `at least 0.95` at every prescribed in-envelope view; **TARGET:** foreground spill `at most 0.05` of target area; **TARGET:** OBB dimension variation `at most 10%`; **TARGET:** `zero` identity/support changes; out-of-envelope commit is unavailable/coached.
- **Timebox/deadline/fallback:** **TARGET:** `4 hours` in S3 including one extra-view retry; failure shrinks the envelope or keeps replace/remove unavailable.

### TST-DEPTH-001 — Learned depth/dense provider

- **Requirements/decisions:** `NFR-COORD-001`, `NFR-LATENCY-001`, `FR-B0-001`; [ADR-006](../adr/ADR-006-fast-and-dense-geometry-tracks.md), [ADR-007](../adr/ADR-007-segmentation-and-depth-providers.md); `GATE-007`.
- **Fixture/variants:** One shared `FX-HERO-ROOM-001` `.rrcap` with taped floor and **TARGET:** `3 taped distances`; DA3Metric-Large, pose-conditioned Apache-licensed DA3 Small/Base, and no-dense.
- **Metrics:** floor RMSE, each taped-distance relative error, static-region temporal flicker, accepted-update p50/p95, rejection rate, queue depth, VRAM/OOM; Open3D `0.19.0` output is evaluated only if selected.
- **Acceptance for live enhancement:** **TARGET:** floor RMSE `at most 0.025 m`; **TARGET:** every taped distance within `plus or minus 4%`; **TARGET:** accepted-update p95 `at most 450 ms`; **TARGET:** `zero` queue growth over a `2-minute` replay; **TARGET:** `zero` OOM; no ARKit pose or stable-ID rewrite.
- **Timebox/deadline/fallback:** **TARGET:** `4 hours` before dense integration; any failure selects no-dense live. A provider may remain offline research only and cannot redefine guaranteed B0.

### TST-REVEAL-001 — Reveal quality and foreground safety

- **Requirements/decisions:** `FR-REMOVE-001`, `FR-REPLACE-001`, `NFR-RENDER-001`; [ADR-005](../adr/ADR-005-realitykit-first-compositor.md), [ADR-009](../adr/ADR-009-multi-surface-reveal.md); `GATE-006`.
- **Fixture/variants:** `FX-HERO-ROOM-001` with at least **TARGET:** `8 trajectory poses`; observed-only atlas, deterministic local fill, and the simplest already license-approved fallback.
- **Metrics:** P10/median target coverage, largest uncovered component, synthesized fraction/provenance, foreground overwrite, seam/surface-order severity, temporal stability, blinded walk-around vote.
- **Acceptance:** **TARGET:** P10 coverage `at least 0.95` and never above the median; **TARGET:** median coverage `at least 0.98`; **TARGET:** largest uncovered component `at most 1%`; **TARGET:** `zero` severe foreground overwrite or surface-order artifact; exactly `5` blinded votes with `4–5` pass votes. The versioned rubric records both overwrite fraction and the categorical severe flag.
- **Timebox/deadline/fallback:** **TARGET:** one reveal slice, completed before voice integration or release rehearsal; failure requests views/shrinks envelope and blocks empty-removal P0 rather than silently demoting it.

## 7. Physical-device and manual tests

| Test ID | Requirements / gate | Procedure and distributions | Acceptance |
|---|---|---|---|
| `TST-DEVICE-001` Build/signing/permissions | `OPS-DEVICE-001`, `FR-CAPTURE-001`; `GATE-013` | Clean signed install/launch on base iPhone 17; camera/microphone grant and denial; ARKit world tracking/planes with LiDAR-only semantics disabled; short capture/recovery. | **TARGET:** `1` repeatable clean install/launch and hash-valid short capture; permissions fail closed; no LiDAR-only API is required. |
| `TST-DEVICE-002` Orientation/intrinsics checkerboard | `NFR-COORD-001`; `GATE-002` | Prescribed orientations/crops/aspect ratios at physical-device poses; overlay known checkerboard rays. | **TARGET:** maximum corner/reprojection error `1 encoded pixel`; `TARGET: zero` mirrored/rotated/cropped mismatch. |
| `TST-COMPOSITOR-001` Ordering and coverage | `FR-REPLACE-001`, `FR-REMOVE-001`; `GATE-003` | RealityKit-first versus already-bounded minimal Metal spike; camera, occluder, reveal, asset, shadow, UI at **TARGET:** `8 poses`. | **TARGET:** `zero` severe ordering/coverage artifact and **TARGET:** `at least 4 of 5` blinded visual pass votes. |
| `TST-PERF-001` FPS/memory/thermal/latency | `NFR-RENDER-001`, `NFR-LATENCY-001`; `GATE-003`, `GATE-012` | **TARGET:** `4-minute` hero session; capture frame-time, FPS, CPU/GPU/memory/thermal, mask age, capture-to-preview stages, drops and queue depth. | **TARGET:** median `at least 45 FPS`; **TARGET:** p95 frame time `at most 33 ms`; **TARGET:** p95 mask age `at most 250 ms` for advertised live tracking; **TARGET:** `zero` crash/jetsam or sustained serious/critical thermal state; all named stages report p50/p95/max. |
| `TST-TRACKING-001` Tracking loss/reset | `FR-TARGET-001`, `NFR-RESILIENCE-001`; [ADR-003](../adr/ADR-003-arkit-authority-and-coordinates.md), [ADR-008](../adr/ADR-008-scene-identity-and-readiness.md) | Occlude camera, fast motion, low texture, app interruption, relocalization, and explicit session reset while an edit is active. | Unsafe commit becomes unavailable within the next UI update; last activated edit remains renderable; reset creates a new world-frame version; manual re-seed succeeds or reports clear failure within **TARGET:** `2 seconds`. |
| `TST-OFFLINE-001` Committed-edit persistence | `FR-RESTORE-001`, `NFR-RESILIENCE-001`; `GATE-009` | Commit each operation, blackhole network/kill worker/restart app, render and restore from local data, then reconcile. | **TARGET:** `zero` acknowledged edit loss; **TARGET:** `zero` duplicate mutation; restore needs `zero` network reads; conflict preserves evidence and stops mutation. |

## 8. Network, service, and web fallback tests

| Test ID | Requirements / gate | Procedure | Acceptance |
|---|---|---|---|
| `TST-NET-001` Loss/reconnect/idempotency | `NFR-RESILIENCE-001`, `FR-TRANSACTION-001`; `GATE-009`, `GATE-012` | **TARGET:** `20` forced disconnect/reconnect cycles during capture, preview, commit acknowledgement, and artifact activation; duplicate/reorder messages; restart worker. | **TARGET:** `zero` acknowledged edit loss, duplicate mutation, or cross-session leakage; **TARGET:** canonical snapshot recovery `at most 2 seconds`; stale/duplicate traffic is deterministic. |
| `TST-RUNTIME-001` Tier/queue soak | `NFR-LATENCY-001`, `NFR-REPLAY-001`; `GATE-012` | Run selected live profile for **TARGET:** `4 minutes` on each declared tier; record VRAM, p50/p95/max latency, queue depth/drops and process status. | **TARGET:** `zero` OOM/crash; **TARGET:** `zero` unbounded queue growth; all published stage distributions and drop counts are present. |
| `TST-B0-001` Provider-independent B0 | `FR-B0-001`, `FR-WEB-001`; `GATE-008` | Disable GPU/learned providers/network; replay native capture **TARGET: 2 times**, inspect scene/artifacts/transactions, execute typed fixture proposal on a distinct gateway-authoritative fork; import MP4/MOV as `ordinary_video_import` with only exact media timeline metadata, one journal-linked `ordinary_video_imported` event, and no ARKit coordinate/capture settings. | **TARGET:** `2 of 2` identical event digests/revision traces; `TARGET: zero` provider calls; ordinary video event record/projection/input digest validates, media decodes/scrubs with `uncalibrated_no_world_authority`, ARKit frame/keyframe arrays remain empty, and no scale/pose/planes are fabricated; all unavailable capabilities are explicit. |
| `TST-WEB-001` Browser degradation | `FR-WEB-001`, `NFR-RESILIENCE-001`; [ADR-002](../adr/ADR-002-native-iphone-and-web-split.md), [ADR-013](../adr/ADR-013-mode-b0-guarantee.md) | Run `FX-WEB-001` on the declared browser matrix; deny camera, remove codec, exhaust/quota-fail local storage, corrupt upload, and lose network. | Each case reaches the documented upload/timeline/degraded path without a Mode A parity claim; `TARGET: zero` acknowledged commit loss; failures are visible and actionable. |
| `TST-RETENTION-001` Consent/retention/deletion/share | `SEC-CONSENT-001`, `SEC-RETENTION-001` | Attempt pre-consent capture/manifest, `session_ttl` without concrete expiry, upload/share without action, TTL expiry, every deletion state, delete source/derived data, follow invalidated share, and inspect logs. | `TARGET: zero` pre-consent capture/manifest or implicit upload/share; TTL always has an expiry; requested deletion records time and revokes/not-shares access; logs contain IDs rather than raw imagery/secrets. |

## 9. Agent, voice, and adversarial tests

| Test ID | Requirements / gate | Procedure | Acceptance |
|---|---|---|---|
| `TST-AGENT-001` Typed intent/tool correctness | `FR-AGENT-001`, `SEC-AGENT-001`; `GATE-010` | With network/models disabled, run every golden typed/tap edit and malformed/injection fixture through the local nonmutating proposal boundary. | **TARGET:** `100%` golden typed/tap edits reach a valid preview and every adversarial input rejects; no proposal can confirm or mutate. Typed failure blocks P0. |
| `TST-AGENT-002` CON-006 Sol/vision proposal boundary | `STR-VOICE-001`, `SEC-AGENT-001`, `SEC-CREDENTIAL-001`; `GATE-010` | Validate gateway and native copies of CON-006 against ready/clarification fixtures; inject stale/native context, unknown catalog asset, unordered/duplicate constraints, transform, URL, confirmation, commit, restore-execution, revision, oversized image/prompt, and unknown fields. Repeat with one explicitly consented current JPEG and with no image. | **TARGET / P1:** every valid fixture binds exact context and can create only a revision-neutral preview; `100%` forbidden fixtures reject before deterministic mutation; no frame is captured/sent without the explicit one-frame action and consent; gateway/model failure leaves local catalog and typed/tap journey complete. |
| `TST-VOICE-001` Optional voice proposal | `STR-VOICE-001`, `SEC-AGENT-001`; `GATE-010` | Only after `TST-AGENT-001` passes, run five fixed hero utterances through Realtime with the same captured context and compare the nonmutating proposal. | **TARGET / P1:** at least `4 of 5` expected proposals and `100%` injection rejection; failure disables voice and leaves P0 status unchanged. |
| `TST-INJECTION-001` Prompt/tool injection | `SEC-AGENT-001`, `SEC-CREDENTIAL-001`; [ADR-011](../adr/ADR-011-agent-and-deterministic-boundary.md) | Put hostile instructions in utterances, asset metadata, labels, tool outputs, retrieved content, URLs and model arguments; attempt unlisted tool, target/session switch, transform injection, license bypass, deploy/delete, and secret extraction. | **TARGET:** `100%` adversarial cases reject or safely clarify; **TARGET:** `zero` state mutation, authority expansion, deployment, deletion, or credential disclosure; redacted audit event retained. |
| `TST-CREDENTIAL-001` Ephemeral/standard keys | `SEC-CREDENTIAL-001`; [ADR-011](../adr/ADR-011-agent-and-deterministic-boundary.md) | Scan repository/bundles/logs/captures; expire/revoke client secret; inspect bootstrap and authorization-header redaction. | **TARGET:** `zero` standard keys in source/client/log/`.rrcap`; expired/invalid scoped credential fails closed while typed/local/replay remains usable. |

## 10. Asset and shipping evidence tests

| Test ID | Requirements / gate | Procedure | Acceptance |
|---|---|---|---|
| `TST-ASSET-001` Manifest/integrity/parity | `FR-PLACE-001`, `FR-REPLACE-001`, `NFR-CONTRACT-001`, `OPS-LICENSE-001`; `GATE-011` | Validate canonical manifest, artifact/branch digest, exact source revision/hash/author, use+redistribution approval, explicit attribution-required evidence, metres/origin/axis and axis-wise min<max bounds, texture budget, local delivery, USDZ/GLB hashes/device/web loads and parity. | **TARGET:** `100%` ready hero assets are approved redistributable and hash/load; derivative dimension difference `at most 1%`; `zero` empty required attribution or command-time network fetches. |
| `TST-LICENSE-001` Shipping bill of materials | `OPS-LICENSE-001`; [ADR-007](../adr/ADR-007-segmentation-and-depth-providers.md), [ADR-009](../adr/ADR-009-multi-surface-reveal.md), [ADR-010](../adr/ADR-010-asset-contract.md) | Review exact code and weight/checkpoint/asset/font revisions separately; retain terms/attribution/acceptance evidence and redistribution/use decision. | **TARGET:** `100%` shipped artifacts have exact source/version/digest and approved applicable terms; **TARGET:** `zero` noncommercial, unknown, or unaccepted gated shipping artifact. |

## 11. Golden path, human acceptance, and demo

### TST-GOLDEN-001 — Repeated end-to-end journey

Run consent/capture, target/re-seed if prescribed, place, restore, replace, restore, remove, restore, network-loss persistence, and provider-independent B0 replay on the declared physical device/runtime tier. Preserve screen/device video, synchronized traces, capture digest, transaction/revision oracle, gate states, and operator checklist.

Acceptance is **TARGET: 5 of 5 consecutive complete runs** with **TARGET: zero** crash, lost acknowledged edit, duplicate revision, wrong target, severe compositor/reveal artifact, unsafe commit, or replay-digest mismatch. Removal must separately satisfy `GATE-006`; B0 must separately satisfy `GATE-008`.

### TST-HUMAN-001 — Visual and readiness comprehension

Use randomized variant labels and prescribed poses. Evaluators answer whether the original target is credibly covered, empty reveal remains spatially coherent, foreground is preserved, asset contact/support looks plausible for a preview, and degraded/unavailable readiness is understood. Record per-question ballots and severe-artifact locations; do not discard dissent.

Acceptance for compositor/reveal gates is **TARGET: at least 4 of 5 pass votes** plus the objective coverage/ordering thresholds. A majority vote cannot override a severe foreground overwrite, unsupported-view claim, transaction failure, or license/security failure.

### TST-DEMO-001 — Submission acceptance

Verify the official rules snapshot tied to `CLM-026` and `CLM-027`; check description, category, repository/README/setup/sample-data/testing guidance, public demo video with audio under the **VERIFIED RULE: 3-minute maximum**, Codex/GPT-5.6 explanation, representative Codex `/feedback` Session ID, licensing/access instructions, and honest TARGET/MEASURED language. The demo must show the four operations and provider-independent B0 or transparently narrate a documented degraded fallback. Begin evidence capture in S2; final assembly occurs in S8.

## 12. Exact Day 1 evidence

Day 1 must end with the following immutable evidence, even if a test fails:

1. governing prompt path and SHA-256; source-document/archive hashes; Git status/branch and no `.planning/` assertion;
2. toolchain inventory: base iPhone 17 identifier, iOS, Xcode/Swift, signing team readiness without secrets, Developer Mode, Node/npm, Python, CUDA/driver if present, browser versions, and available hardware-tier description;
3. **TARGET: one** clean signed install/launch log plus camera permission grant/denial and ARKit world-tracking/plane screenshot/video;
4. `FX-COORD-001` generator/oracle and first Swift/JavaScript/Python projection report;
5. **TARGET: one** short atomic capture with FramePacket and `.rrcap` schema-validation report, file/manifest SHA-256, authoritative order, and recovered-prefix result;
6. first `FX-RRCAP-010S` replay run and input/event digest, even before a second run exists;
7. first transaction fixture showing preview no-op and exactly-one revision commit plus inverse artifact digest;
8. base-device baseline distributions with camera/recording only: FPS, frame time, memory, thermal state, capture durability latency, queue depth/drop count;
9. hero-room freeze: target, surfaces, taped measurements, prescribed trajectory/poses, lighting notes, foreground occluder, asset candidates, and consent/privacy classification;
10. provider/access/license matrix with exact code/checkpoint revisions for every candidate and explicit `not yet downloaded/accepted` state;
11. Build Week rules snapshot/digest, deadline in UTC/PT, submission checklist, and retained Codex session-evidence plan;
12. failure log and gate state for `GATE-001`, `GATE-002`, and `GATE-013`; unrun items remain `UNRUN`, never green-by-assumption.

## 13. Evidence record format

Every test result records:

- test ID, requirement IDs, ADR links, gate ID, class, and result `PASS`/`FAIL`/`BLOCKED`;
- UTC time, implementation/build commit, dirty-state note, schema/contract versions;
- fixture IDs/revisions/SHA-256 and expected oracle revision;
- physical device/OS or browser/runtime/hardware tier;
- provider code/checkpoint/container/package revisions and applicable license evidence;
- exact command or manual procedure revision;
- raw logs/traces/screenshots/video/ballots and metric-script revision;
- every TARGET beside its MEASURED result and distribution sample count;
- failure signature, recovery time consumed, selected fallback, and final gate state.

## 14. Governing-prompt coverage

| Required category | Test coverage |
|---|---|
| Schema/contract validation | `TST-CONTRACT-001`, `TST-CONTRACT-002` |
| Coordinate transform/projection | `TST-COORD-001`, `TST-DEVICE-002` |
| Image orientation/intrinsics | `TST-COORD-002`, `TST-DEVICE-002` |
| `.rrcap` deterministic replay | `TST-CAPTURE-001`, `TST-REPLAY-001`–`003` |
| Scene revision/idempotency | `TST-TX-001`, `TST-NET-001` |
| Transaction inverse/undo | `TST-TX-002`, `TST-OFFLINE-001` |
| Model provider bake-offs | `TST-SEM-001`, `TST-DEPTH-001` |
| Geometry accuracy/floor stability | `TST-GEOMETRY-001`, `TST-DEPTH-001` |
| Semantic mask/target resolution | `TST-SEM-001`, `TST-TRACKING-001` |
| Reveal quality | `TST-REVEAL-001`, `TST-HUMAN-001` |
| Compositor device tests | `TST-COMPOSITOR-001`, `TST-PERF-001` |
| FPS/memory/thermal/latency distributions | `TST-PERF-001`, `TST-RUNTIME-001` |
| Offline committed-edit persistence | `TST-PERSIST-001`, `TST-OFFLINE-001` |
| Network loss/reconnect | `TST-NET-001`, `TST-OFFLINE-001` |
| Tracking loss | `TST-TRACKING-001`, `TST-SEM-001` |
| Web fallback | `TST-B0-001`, `TST-WEB-001` |
| Agent intent/tools | `TST-AGENT-001`, `TST-AGENT-002`, `TST-VOICE-001` |
| Prompt/tool injection | `TST-INJECTION-001`, `TST-CREDENTIAL-001` |
| Golden-path repeated runs | `TST-GOLDEN-001` |
| Demo acceptance | `TST-DEMO-001` |
| Exact Day 1 evidence | Section 12 |
