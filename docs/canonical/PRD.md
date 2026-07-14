# ReRoom Product Requirements Document

Status: canonical PRE-GSD product authority  
Version: 1.0.0  
Date: 2026-07-13

## 1. Product intent

ReRoom helps a person preview a controlled room edit on a physical iPhone: point at a freestanding armchair or small side table with visible floor, select it, and **place, replace, remove, or restore** an edit. The live camera remains the photoreal scene. ReRoom composites only virtual assets, masks/occlusion, reveal geometry, shadows, and UI.

The honest P0 promise is a constraint-checked preview against estimated spatial proxies in a controlled hero scene. It is not a survey-grade digital twin, general interior reconstruction, guaranteed unseen-background synthesis, or proof of real-world physical safety.

### Target user and problem

The target user wants a fast, believable answer to “what would this controlled room change look like?” Existing catalog AR can place a model, but does not reliably ground a replace/remove request in the observed object, preserve an auditable edit transaction, or replay the evidence when the live path fails.

### Success thesis

The signature path is replacement. Empty removal is available only when its multi-surface reveal bundle passes the hero quality gate. Recorded Mode B0 makes the result recoverable and demonstrable even when live inference is degraded.

## 2. Modes and scope

- **Mode A (P0):** native SwiftUI iPhone live editing with ARKit authority and camera-feed compositing.
- **Mode B0 (P0):** `.rrcap` capture/replay, timeline/session inspection, browser fallback, typed transactions, and a degraded point/plane/artifact viewer. Ordinary video upload and timeline replay are P0; learned geometry from arbitrary video is capability-gated.
- **Mode B1 (stretch):** offline photoreal refinement behind a preserved-identity render-skin interface. It starts only after all P0 gates are green and explicit human approval is recorded.

P0 has exactly four user-visible operations: **place**, **replace**, **remove**, and **restore**. “Undo” is UI wording that invokes `restore`; it is not a fifth operation. Internal visibility/asset/reveal deltas are not user operations.

## 3. Hero journey

1. The user gives capture consent, starts a Mode A session, and is coached to move around the controlled chair/table while keeping floor visible.
2. The client durably records selected atomic frames before upload and shows tracking plus per-capability readiness.
3. The user taps or speaks to ground a target. If confidence is ambiguous, ReRoom requests a tap/re-seed rather than guessing.
4. The user chooses one of the four operations. Typed/tap control always remains available.
5. ReRoom validates the proposal against the current scene revision and estimated support/collision/view proxies, previews locally, then commits by explicit confirmation.
6. A committed edit and inverse artifacts are locally durable before visible acknowledgement. Restore works offline.
7. The same `.rrcap` can be opened in Mode B0 to replay accepted inputs/events and inspect the transaction.

## 4. P0 requirements

The stable ID convention is defined in `GLOSSARY_AND_ID_REGISTRY.md`: `FR-*`, `NFR-*`, `SEC-*`, and `OPS-*`. All requirements in this section are P0.

### FR-CAPTURE-001 — Atomic record-first capture

- **Priority:** P0
- **Statement:** The Mode A client shall move each selected frame through exactly `selected → image_and_metadata_durable → journaled → network_eligible → server_acknowledged`, binding physically upright image bytes to RR-COORD-1 metadata before network eligibility.
- **Rationale:** Exact replay and coordinate correctness require image, intrinsics, pose, crop/orientation, tracking, timestamp, and identity to remain inseparable.
- **Acceptance criteria:** RRFP-WIRE-1 and exact image SHA validate; crash injection after every lifecycle boundary leaves either no frame or one hash-valid journaled frame; the global journal is contiguous, final sequence matches finalization, each event record digest verifies, and exact frame/event projections plus the recomputed journal-tuple RR-JCS input digest match in two replays; no upload references a non-journaled frame.
- **Dependencies:** ARKit session; local storage; CON-001 and CON-002.
- **Fallback:** Drop stale non-durable work; continue local camera/rendering; finalize and later upload the valid `.rrcap` prefix.
- **Relevant ADRs:** ADR-003, ADR-004.
- **Contract/spec references:** CON-001, CON-002; Master Spec §§4–5.
- **Recommended slice:** S1 Capture/replay foundation.

### FR-TARGET-001 — Explicit target and capability readiness

- **Priority:** P0
- **Statement:** The user shall ground a single chair/table target by reticle/tap or utterance-time context, and UI shall expose independent readiness for select, place, replace, remove, and restore.
- **Rationale:** One-week feasibility and honest UX require target-first processing and no false “scene ready” state.
- **Acceptance criteria:** On annotated hero fixtures, an ambiguous selection never commits silently; tracking loss changes readiness within one UI update; replace may show ready while remove is unavailable; manual re-seed restores selection or returns a clear failure.
- **Dependencies:** FR-CAPTURE-001; semantic provider; scene state.
- **Fallback:** Tap/box re-seed and replacement-first coaching; no whole-room discovery.
- **Relevant ADRs:** ADR-007, ADR-008.
- **Contract/spec references:** CON-003; Master Spec §§7–8.
- **Recommended slice:** S3 Target and fast geometry.

### FR-PLACE-001 — Place

- **Priority:** P0
- **Statement:** The user shall place one curated validated asset on an estimated support surface and preview it before commit.
- **Rationale:** Placement proves AR grounding and the asset/transaction path without requiring object removal.
- **Acceptance criteria:** On the hero fixture, tap or typed intent creates a stable preview, deterministic support/collision proxy checks run, explicit confirmation commits exactly one scene revision, and the edit survives app interruption and replay.
- **Dependencies:** FR-CAPTURE-001; asset manifest; support surface; FR-TRANSACTION-001.
- **Fallback:** Snap to a user-confirmed ARKit plane; refuse commit when support is unavailable.
- **Relevant ADRs:** ADR-006, ADR-010, ADR-012.
- **Contract/spec references:** CON-003, CON-004, CON-005; Master Spec §§9–11.
- **Recommended slice:** S2 Deterministic place transaction.

### FR-REPLACE-001 — Replace

- **Priority:** P0
- **Statement:** The user shall replace the selected hero object with a curated asset while masking the original only within supported observations.
- **Rationale:** Replacement is the signature path and tolerates less background completion than empty removal.
- **Acceptance criteria:** A ready target yields a preview with stable target identity, conservative mask/occlusion, support-aligned asset, no duplicate revision on retry, and 5/5 successful golden-path runs; outside supported views the UI coaches or restores instead of exposing invalid pixels.
- **Dependencies:** FR-TARGET-001; mask volume/OBB; asset manifest; FR-TRANSACTION-001.
- **Fallback:** Place the replacement in front of the original without claiming empty removal, or ask for more views/re-seed.
- **Relevant ADRs:** ADR-005, ADR-006, ADR-007, ADR-009, ADR-010, ADR-012.
- **Contract/spec references:** CON-003–CON-005; Master Spec §§6–11.
- **Recommended slice:** S4 Signature replacement.

### FR-REMOVE-001 — Empty removal

- **Priority:** P0
- **Statement:** The user shall remove the controlled hero object only when its multi-surface reveal bundle and foreground occlusion coverage are ready for the current supported view envelope.
- **Rationale:** Removal is human-locked P0 but must not hallucinate unseen room geometry or advertise readiness prematurely.
- **Acceptance criteria:** The hero fixture passes GATE-006: target coverage P10 ≥0.95, median ≥0.98, largest uncovered component ≤1%, correct multi-surface order, and at least 4/5 human visual pass votes over the prescribed views. A failed gate blocks P0 release or triggers explicit human escalation; it cannot be silently demoted.
- **Dependencies:** FR-TARGET-001; FR-REPLACE-001; reveal bundle; compositor; FR-TRANSACTION-001.
- **Fallback:** Within a session keep remove `unavailable` and coach for views; replacement remains usable. Release still remains blocked until the controlled removal gate passes or a human changes P0.
- **Relevant ADRs:** ADR-005, ADR-008, ADR-009, ADR-012.
- **Contract/spec references:** CON-003–CON-005; Master Spec §§8–10.
- **Recommended slice:** S5 Quality-gated removal.

### FR-RESTORE-001 — Restore/undo

- **Priority:** P0
- **Statement:** The user shall restore the latest eligible committed edit through a new compensating transaction on the native device-authoritative Mode A revision branch, including while offline.
- **Rationale:** Immutable history plus deterministic compensation makes retries, replay, and reconciliation safe.
- **Acceptance criteria:** For place/replace/remove fixtures, restore references the original transaction, verifies its locally durable captured-exact RR-EDIT-PROJECTION-1 inverse, derives the current-complete `after` projection with RR-RESTORE-REBASE-1, increments the scene revision exactly once, appends immutable history, preserves new/unaffected objects plus current tracking/readiness evidence, leaves the original committed record unchanged, renders offline, and reconciles without a duplicate mutation or historical whole-document rewind.
- **Dependencies:** FR-TRANSACTION-001; local inverse/artifact persistence.
- **Fallback:** If required local artifacts fail integrity checks, preserve the committed view and present a clear non-destructive restore failure.
- **Relevant ADRs:** ADR-012.
- **Contract/spec references:** CON-003, CON-005; Master Spec §11.
- **Recommended slice:** S2 Deterministic place transaction, then exercised in S4–S5.

### FR-TRANSACTION-001 — Deterministic edit authority

- **Priority:** P0
- **Statement:** Every edit shall follow validate/preview/commit semantics on one explicitly identified single-authority revision branch, with compare-and-swap scene revision, RR-JCS-SHA256-1 request fingerprinting, exactly-once idempotency, local durability, inverse operations, and explicit reconciliation.
- **Canonical lifecycle:** CON-005 state is exactly `draft`, `validated`, `previewed`, `committed`, `rejected`, or `cancelled`. Local replication state is separate and exactly `local_only`, `pending_sync`, `synced`, `sync_failed`, or `conflict`; it never rewrites canonical transaction state. Undo is the `restore` operation implemented as a new immutable compensating transaction with one `restore_snapshot` inverse.
- **Rationale:** Conversational inference and unreliable networks cannot own canonical mutations.
- **Acceptance criteria:** Preview changes no revision; commit requires a preview-bound explicit user confirmation event and the exact operation-specific validation checks/reducer order; visibility/reveal deltas materialize in canonical object `edit_state`, asset creation atomically materializes its support relation, and every inverse contains the complete RR-EDIT-PROJECTION-1; the declared branch authority changes `r` to `r+1`; same idempotency key/fingerprint returns the prior result; same key/different fingerprint reports `idempotency_conflict`; stale base or wrong authority/branch is rejected; an offline device commit later replicates idempotently; unexpected divergence is quarantined without automatic merge; disconnect/retry/restore tests match the expected branch/revision trace exactly.
- **Dependencies:** Versioned scene and transaction contracts; persistent commit journal.
- **Fallback:** Typed local proposal and pending synchronization; never speculative server overwrite.
- **Relevant ADRs:** ADR-011, ADR-012.
- **Contract/spec references:** CON-003, CON-005; Master Spec §11.
- **Recommended slice:** S2 Deterministic place transaction.

### FR-AGENT-001 — Typed/tap semantic intent

- **Priority:** P0
- **Statement:** Typed/tap input shall propose any of the four operations and allowlisted design attributes without a model or network; deterministic application code shall capture target context, authorize, validate, preview, and commit.
- **Rationale:** GPT is useful for semantic/design choices, not transforms, collisions, revision control, or physical validity.
- **Acceptance criteria:** Typed/tap controls complete every golden edit with learned providers and network disabled; malformed, stale, oversized, or injected arguments cannot mutate state, select another target/session, provide transforms, authorize, or commit.
- **Dependencies:** FR-TARGET-001; FR-TRANSACTION-001.
- **Fallback:** Curated asset picker plus explicit operation controls through the same validated proposal boundary.
- **Relevant ADRs:** ADR-011.
- **Contract/spec references:** CON-005; Master Spec §12.
- **Recommended slice:** S6 Agent ingress after typed edits pass.

### FR-B0-001 — Guaranteed `.rrcap` replay

- **Priority:** P0
- **Statement:** A finalized or recovered-prefix `.rrcap` shall replay accepted FramePackets and events in authoritative order without any learned reconstruction provider or live network.
- **Rationale:** Deterministic replay is the debugging, recovery, testing, and demo foundation.
- **Acceptance criteria:** Two runs over the golden capture produce identical RR-JCS global-journal input/event digests, exact frame/event projections, and expected revision trace; all raw file and manifest hashes validate; corrupted suffix recovery stops at the last valid contiguous journal record; neural outputs are compared only under a pinned provider/tolerance policy.
- **Dependencies:** FR-CAPTURE-001; CON-001–CON-005.
- **Fallback:** Degraded point/plane/artifact viewer and transaction timeline; learned geometry may remain unavailable.
- **Relevant ADRs:** ADR-004, ADR-013.
- **Contract/spec references:** CON-001, CON-002; Master Spec §§5 and 14.
- **Recommended slice:** S1 Capture/replay foundation.

### FR-WEB-001 — Separate web replay and fallback

- **Priority:** P0
- **Statement:** A separate Next.js web client shall provide session/timeline inspection, `.rrcap`/ordinary-video upload and replay, sharing controls, typed edit proposals, and degraded visualization without claiming Mode A spatial parity.
- **Rationale:** Browser constraints cannot replace ARKit authority, but a real web path preserves B0 access and demo resilience.
- **Acceptance criteria:** Current supported browsers can open the golden `.rrcap`, verify inventory, scrub events, inspect scene/transactions, render available plane/point/artifact data, and degrade clearly on camera denial, codec failure, quota exhaustion, or network loss without losing acknowledged commits. MP4/MOV ordinary-video import decodes and scrubs without fabricating ARKit calibration/world/scale/planes; learned geometry remains capability-unavailable unless a separately pinned provider produces it.
- **Dependencies:** FR-B0-001; gateway HTTP APIs; browser capability checks.
- **Fallback:** File upload plus timeline/metadata view; no calibrated AR interaction claim.
- **Relevant ADRs:** ADR-002, ADR-013, ADR-014.
- **Contract/spec references:** CON-001–CON-005; Master Spec §§2 and 14.
- **Recommended slice:** S7 Web/B0 resilience.

### NFR-COORD-001 — Coordinate correctness

- **Priority:** P0
- **Statement:** All producers/consumers shall implement RR-COORD-1 and explicit world-frame version changes exactly.
- **Rationale:** A one-axis, crop, layout, or timestamp mismatch invalidates all geometry and overlays.
- **Acceptance criteria:** Synthetic projection/reprojection fixtures are ≤1 encoded pixel; duplicated transport header/JSON fields match; known transforms and intrinsics satisfy RR-FLOAT-1; device checkerboard tests show no orientation/crop swap; reset creates a new world-frame version/correction.
- **Dependencies:** CON-001–CON-005.
- **Fallback:** Reject incompatible packets/artifacts and coach session restart; never guess transforms.
- **Relevant ADRs:** ADR-003, ADR-004.
- **Contract/spec references:** Glossary RR-COORD-1; Master Spec §4.
- **Recommended slice:** S1 Capture/replay foundation.

### NFR-REPLAY-001 — Bounded deterministic processing

- **Priority:** P0
- **Statement:** Live queues shall be bounded and favor newest useful work, while durable accepted order remains replay-authoritative.
- **Rationale:** Latency must not grow without bound and dropped work must remain auditable.
- **Acceptance criteria:** Stress input never exceeds configured queue capacity; stale inference work is dropped with a metric; durable frames/events retain monotonic sequence; replay reproduces accepted order independent of live completion order.
- **Dependencies:** FR-CAPTURE-001; telemetry.
- **Fallback:** Reduce upload cadence/quality and preserve keyframes/local recording.
- **Relevant ADRs:** ADR-004, ADR-014.
- **Contract/spec references:** CON-001, CON-002; Master Spec §§5 and 13.
- **Recommended slice:** S1, then S8 hardening.

### NFR-RENDER-001 — Local render independence

- **Priority:** P0
- **Statement:** The 60 Hz camera/render loop shall never wait synchronously for network, GPU worker, web client, or LLM; native high-rate image buffers shall not cross a scripting bridge.
- **Rationale:** Mobile responsiveness and safety require local ownership and last-known-good artifacts.
- **Acceptance criteria:** Network/LLM fault injection causes no render-thread wait; four-minute base-iPhone device gate achieves TARGET median ≥45 FPS and p95 frame time ≤33 ms without crash/thermal shutdown; values remain TARGET until measured.
- **Dependencies:** Compositor spike; local artifact cache.
- **Fallback:** Reduce overlay cadence/quality, disable nonessential occluders, replacement-first render; gate removal when invalid.
- **Relevant ADRs:** ADR-002, ADR-005.
- **Contract/spec references:** Master Spec §§3 and 10.
- **Recommended slice:** S3/S4 physical-device gate.

### NFR-LATENCY-001 — Measured latency distributions

- **Priority:** P0
- **Statement:** The system shall record device-to-preview and stage latency distributions with synchronized monotonic spans and no unsupported “real-time” claim.
- **Rationale:** Provider and deployment choices require comparable evidence.
- **Acceptance criteria:** Replay/device reports contain p50/p95/max for capture, durability, queue, upload, inference, artifact acceptance, preview, commit, and mask age; **TARGET:** target mask age p95 ≤250 ms on the declared benchmark tier or the capability degrades.
- **Dependencies:** Observability envelope; selected worker profile.
- **Fallback:** Lower cadence, narrower provider set, cached artifacts, typed/local path.
- **Relevant ADRs:** ADR-007, ADR-014.
- **Contract/spec references:** Master Spec §15; Test Plan.
- **Recommended slice:** S3 onward, finalized S8.

### NFR-RESILIENCE-001 — Tracking/network/offline resilience

- **Priority:** P0
- **Statement:** Tracking loss, network loss, reconnect, and worker failure shall preserve local camera operation, committed edits, restore capability, and record integrity.
- **Rationale:** The live service is not reliable enough to own continued rendering or history.
- **Acceptance criteria:** Fault matrix passes with zero lost acknowledged commits, no cross-session state, no duplicate mutations, valid recovered capture prefix, and a clear degraded/recovery UI state.
- **Dependencies:** FR-CAPTURE-001; FR-TRANSACTION-001; local persistence.
- **Fallback:** Local last-known-good edit/replay and delayed synchronization.
- **Relevant ADRs:** ADR-004, ADR-012, ADR-014.
- **Contract/spec references:** CON-002, CON-005; Master Spec §§5, 11, 16.
- **Recommended slice:** S8 Hardening/demo evidence.

### NFR-CONTRACT-001 — Versioned interoperability

- **Priority:** P0
- **Statement:** All external capture, scene, artifact, and transaction boundaries shall use the exact versioned schemas, RRFP-WIRE-1 framing, closed codecs, RR-FLOAT-1, and RR-JCS-SHA256-1 scopes in `docs/contracts/`; compatibility requires an explicit versioned migration.
- **Rationale:** Independent native/web/service work needs one executable vocabulary.
- **Acceptance criteria:** All golden instances and cross-language digest/wire vectors validate; schema IDs are unique; a 1.0 reader rejects unknown fields and 1.1/unknown major unless a named migration runs; malformed path/framing/digest/branch input rejects before mutation; no identity uses renderer indices or opaque unversioned codecs.
- **Dependencies:** CON-001–CON-005.
- **Fallback:** Quarantine incompatible data and retain raw `.rrcap` evidence for migration.
- **Relevant ADRs:** ADR-003, ADR-004, ADR-008, ADR-012.
- **Contract/spec references:** Contracts README; Master Spec §17.
- **Recommended slice:** S0 Contract lock.

### SEC-CONSENT-001 — Capture consent and minimization

- **Priority:** P0
- **Statement:** Room imagery capture/upload/share shall require clear consent, a visible recording state, and minimal selected-frame collection.
- **Rationale:** Room imagery is sensitive and unnecessary raw capture increases exposure.
- **Acceptance criteria:** No capture before consent; recording/upload/share states are visible; manifest records consent and retention mode; denial leaves the app usable only for non-capture explanation.
- **Dependencies:** Session UX; CON-002.
- **Fallback:** Local-only session or cancellation.
- **Relevant ADRs:** ADR-004, ADR-014.
- **Contract/spec references:** CON-002; Master Spec §16.
- **Recommended slice:** S1.

### SEC-CREDENTIAL-001 — Secret isolation

- **Priority:** P0
- **Statement:** Standard OpenAI, Firecrawl, storage, and provider credentials shall never enter source, logs, `.rrcap`, browser bundles, or the iPhone app; clients receive only scoped short-lived credentials where supported.
- **Rationale:** Client or repository secrets create immediate compromise.
- **Acceptance criteria:** Secret scan passes; Realtime uses a server-created ephemeral client secret/session; logs redact authorization headers; invalid/expired credentials fail closed.
- **Dependencies:** Gateway bootstrap; environment management.
- **Fallback:** Disable the external feature and retain typed/local/replay behavior.
- **Relevant ADRs:** ADR-011, ADR-014.
- **Contract/spec references:** Master Spec §§12 and 16.
- **Recommended slice:** S6 and every integration slice.

### SEC-RETENTION-001 — Retention, deletion, and sharing

- **Priority:** P0
- **Statement:** Captures, derived geometry, transactions, and share links shall have explicit retention scope and deletion behavior.
- **Rationale:** Derived scene data is as sensitive as source imagery.
- **Acceptance criteria:** Default is local-only until share/upload; server sessions have documented TTL; delete invalidates share access and queues source/derived deletion; manifest records retention/delete state; audit logs contain IDs, not raw imagery.
- **Dependencies:** Session store; CON-002.
- **Fallback:** Local-only capture and manual file deletion guidance.
- **Relevant ADRs:** ADR-013, ADR-014.
- **Contract/spec references:** CON-002; Master Spec §16.
- **Recommended slice:** S7/S8.

### SEC-AGENT-001 — Prompt/tool injection containment

- **Priority:** P0
- **Statement:** External text, model output, asset metadata, and crawled content shall be untrusted data; only allowlisted typed tools may produce proposals and deterministic code shall authorize every state transition.
- **Rationale:** Natural-language instructions cannot expand permissions or mutate canonical state.
- **Acceptance criteria:** Injection corpus cannot invoke an unlisted tool, change target/session, bypass confirmation/revision/license checks, expose secrets, deploy, or delete data; invalid arguments are rejected and logged without sensitive content.
- **Dependencies:** FR-AGENT-001; strict gateway schemas.
- **Fallback:** Disable model tools and use typed deterministic controls.
- **Relevant ADRs:** ADR-011.
- **Contract/spec references:** CON-005; Master Spec §§12 and 16.
- **Recommended slice:** S6, regression S8.

### OPS-DEVICE-001 — Device/build readiness

- **Priority:** P0
- **Statement:** The base iPhone 17, current Xcode, signing, Developer Mode, and physical installation path shall be validated before architecture-sensitive implementation.
- **Rationale:** The physical compositor and thermal behavior cannot be inferred from simulator/docs.
- **Acceptance criteria:** A signed minimal device build installs/launches, ARKit world tracking and planes run without LiDAR semantics, camera permission works, and a repeatable build record is saved.
- **Dependencies:** Confirmed human hardware/tooling.
- **Fallback:** Resolve signing/toolchain before continuing mobile critical path; B0 work may proceed independently.
- **Relevant ADRs:** ADR-002, ADR-003, ADR-005.
- **Contract/spec references:** Development Strategy S0/S1; GATE-013.
- **Recommended slice:** S0 Preflight.

### OPS-LICENSE-001 — Shipping license evidence

- **Priority:** P0
- **Statement:** Every shipped model weight, asset, font, library, and checkpoint shall have exact version/digest, source, applicable terms, attribution, and redistribution/use approval recorded.
- **Rationale:** Code licenses do not automatically cover weights/checkpoints/assets.
- **Acceptance criteria:** The shipping bill of materials has no unknown or noncommercial dependency; SAM gated terms and all model/asset artifacts have retained evidence; missing evidence activates the fallback or removes the component.
- **Dependencies:** Research ledger; selected providers/assets.
- **Fallback:** Apache/MIT/permissive alternative, observed deterministic method, or omit optional component.
- **Relevant ADRs:** ADR-007, ADR-009, ADR-010.
- **Contract/spec references:** CON-004; GATE-011.
- **Recommended slice:** S0 and repeated at S8.

### OPS-GOLDEN-001 — Repeatable hero acceptance

- **Priority:** P0
- **Statement:** The complete place/replace/remove/restore hero journey and B0 replay shall pass five consecutive golden runs on the declared device/backend tier.
- **Rationale:** One successful demo run is not release evidence.
- **Acceptance criteria:** 5/5 runs complete without crash, lost committed edit, duplicate revision, wrong target, severe compositor artifact, or replay digest mismatch; removal separately satisfies GATE-006; logs/video/metrics are retained.
- **Dependencies:** All P0 functional and quality gates.
- **Fallback:** Fix or invoke documented subsystem fallback; no false completion claim.
- **Relevant ADRs:** ADR-001 and all P0-path ADRs.
- **Contract/spec references:** Test Plan §11 (`TST-GOLDEN-001`); Risk Plan.
- **Recommended slice:** S8 Hardening/demo evidence.

### OPS-SUBMISSION-001 — Build Week evidence package

- **Priority:** P0
- **Statement:** The submission shall include the required project description, repository/README, public demo video under the official limit with audio, and a representative Codex Session ID, with claims tied to recorded evidence.
- **Rationale:** Technical work is insufficient if required proof is missing.
- **Acceptance criteria:** A rules checklist against the official rules page is signed off before the official deadline; video demonstrates the four operations and B0 fallback honestly; no unmeasured superlative or unsupported novelty claim remains.
- **Dependencies:** OPS-GOLDEN-001; demo capture; Codex development trace.
- **Fallback:** Pre-recorded golden `.rrcap`/device demo with transparent degraded-state narration.
- **Relevant ADRs:** ADR-001, ADR-013.
- **Contract/spec references:** Development Strategy; Research claims CLM-026 and CLM-027.
- **Recommended slice:** Evidence capture begins S2; final assembly S8.

## 5. UX/readiness states

The session UI uses the glossary's presentation-only enum: `initializing`, `coaching`, `tracking`, `degraded`, `offline`, `recovering`, and `ready_for_edit`. These values are derived from—and never replace—the canonical tracking and per-capability readiness values; they are not persisted in CON-003. Each operation button explains its own missing evidence. Target ambiguity requires tap/re-seed. Network loss preserves recording and committed overlays. Tracking loss freezes last-known-good edit artifacts, disables unsafe commit, and coaches relocalization/session restart.

Remove is shown only when `remove=ready` and the current camera pose lies inside the reveal bundle's supported view envelope. Outside it the client coaches back to coverage or restores the original view. “Constraint-checked” copy must name estimated proxies; “physically validated” is prohibited until a measured dense-geometry gate explicitly supports it.

## 6. Dependencies and boundaries

P0 depends on a signed base-iPhone build, ARKit world tracking/planes, local durable storage, curated dual-runtime assets, one selected semantic provider, optional swappable depth enhancement, native-device authority for the active Mode A branch, a gateway for validation/durable replication/reconciliation, and a Next.js B0 client. Standard OpenAI credentials are required only if optional voice/GPT is enabled. P0 does not depend on voice, LiDAR, B1, arbitrary-room reconstruction, LingBot, neural inpainting, a specific GPU SKU, or Next.js-owned WebSockets.

## 7. Explicitly out of scope

- XR glasses or headset delivery.
- General arbitrary rooms, whole-room semantic inventory, structural modification, safety certification, or survey-grade measurement.
- Photoreal Mode B1 implementation is not permitted on the P0 critical path.
- General 3D inpainting or unbounded hallucination of unseen background.
- LiDAR-only scene depth/mesh semantics.
- Large catalogs, commerce, multi-user live editing, production billing, or cloud autoscaling.
- A guarantee that arbitrary ordinary video produces metric learned geometry.
- Product implementation during this PRE-GSD preparation.

## 8. Release criteria and success metrics

P0 releases only when all P0 requirements above pass, all blocking gates in `RISK_AND_KILL_GATES.md` are green, the four-operation inventory is present, controlled removal passes rather than being demoted, the B0 replay works without learned providers, secrets/license checks pass, and OPS-GOLDEN-001 is 5/5. Benchmark values are TARGET until results are attached to the test evidence record.

Primary success metrics are golden-run completion, exact replay/revision traces, removal reveal quality, target mask stability, mobile frame-time/thermal distributions, edit latency distributions, typed intent correctness, recovery with zero acknowledged edit loss, and clear user understanding of readiness/degradation. Optional voice accuracy is tracked separately and cannot compensate for a typed-path failure.

## 9. Stretch requirement

### STR-VOICE-001 — Optional Realtime/GPT semantic ingress

- **Priority:** P1/nonblocking stretch
- **Statement:** Realtime voice and GPT may translate utterances into the same nonmutating typed proposal accepted by FR-AGENT-001.
- **Acceptance criteria:** At least 4/5 fixed hero utterances produce the expected proposal; every ambiguity/injection fixture rejects or clarifies; disabling model/network leaves the complete typed/tap journey available.
- **Dependencies:** FR-AGENT-001 and SEC-AGENT-001; server-minted ephemeral Realtime credential.
- **Fallback:** End voice work and use typed/tap controls; P0 status is unchanged.
- **Relevant ADRs:** ADR-011.
- **Contract/spec references:** CON-005; Master Spec §12.
- **Recommended slice:** S6 only after typed transactions and injection tests pass.

### STR-B1-001 — Isolated offline refinement

- **Priority:** Stretch; explicitly not P0.
- **Statement:** After P0 completion and human approval, an offline provider may generate a higher-fidelity render skin while preserving Mode A IDs, transforms, edits, and transaction history.
- **Acceptance criteria:** No B1 package, worker, task, or dependency is scheduled while any P0 gate is red; any result maps to stable scene/artifact IDs and can be discarded without changing canonical state.
- **Dependencies:** All P0 gates; explicit human start decision.
- **Fallback:** Do not implement B1.
- **Relevant ADRs:** ADR-001, ADR-013.
- **Contract/spec references:** Master Spec §14.
- **Recommended slice:** Post-P0 only; excluded from the one-week critical path.

## 10. Changelog

- **1.0.0 (2026-07-13):** Canonical PRE-GSD rewrite. Locked four-operation scope; made removal a real release gate; narrowed guaranteed B0 to deterministic replay/web behavior; separated semantic intent from deterministic mutation; added stable testable IDs and explicit fallbacks; isolated B1.
