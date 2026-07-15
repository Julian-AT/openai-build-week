# ReRoom

## What This Is

ReRoom is a camera-grounded room-editing product for placing, replacing, removing, and restoring one controlled freestanding chair or small table. Mode A is a native SwiftUI iPhone experience with ARKit world authority; a separate Next.js Mode B0 client provides guaranteed capture replay, inspection, fallback, sessions, sharing, and typed proposals without claiming native Mode A parity.

This is a planning draft. It records product authority and delivery boundaries but does not authorize product implementation, package installation, deployment, or publication.

## Core Value

Trustworthy camera-grounded room editing where users can place, replace, remove, and restore one controlled freestanding chair or small table while deterministic application code retains spatial, persistence, transaction, and replay authority.

## P0 Success Metric

OPS-GOLDEN-001 reaches 5/5 on the signed base-iPhone path, all blocking GATE-NNN records are green, exact replay/revision traces pass, controlled removal is not demoted, B0 replay works without learned providers, and secrets/license checks pass.

All numeric thresholds are TARGET values until an evidence record identifies the immutable fixture, implementation revision, environment, raw evidence, metric calculation, and evaluator.

## Requirements

### Validated

(None yet - implementation and physical/human validation have not begun.)

### Active P0

The 24 canonical P0 requirement IDs are preserved in `.planning/REQUIREMENTS.md` and each maps to exactly one roadmap phase:

- Capture and edit workflows: `FR-CAPTURE-001`, `FR-TARGET-001`, `FR-PLACE-001`, `FR-REPLACE-001`, `FR-REMOVE-001`, `FR-RESTORE-001`, `FR-TRANSACTION-001`, `FR-AGENT-001`, `FR-B0-001`, `FR-WEB-001`
- Correctness and quality: `NFR-COORD-001`, `NFR-REPLAY-001`, `NFR-RENDER-001`, `NFR-LATENCY-001`, `NFR-RESILIENCE-001`, `NFR-CONTRACT-001`
- Security and privacy: `SEC-CONSENT-001`, `SEC-CREDENTIAL-001`, `SEC-RETENTION-001`, `SEC-AGENT-001`
- Operational evidence: `OPS-DEVICE-001`, `OPS-LICENSE-001`, `OPS-GOLDEN-001`, `OPS-SUBMISSION-001`

### Future / Stretch

- `STR-VOICE-001` - Optional Realtime/GPT semantic ingress through the same nonmutating typed-proposal boundary. It is nonblocking and failure leaves the complete typed/tap P0 path unchanged.
- `STR-B1-001` - Isolated offline render-skin refinement only after every P0 gate is green and a human approves. It cannot be scheduled while a P0 gate is red and cannot change canonical identity, transforms, edits, or history.

### Out of Scope for P0

- XR glasses - explicitly future work.
- Mode B1 photoreal refinement - tracked as `STR-B1-001`, never a P0 dependency or fallback.
- Voice/model dependence - `STR-VOICE-001` is optional; all four operations remain complete through typed/tap input without a model or network.
- General furniture or whole-room editing - the controlled hero target is one freestanding chair or small table with visible floor.
- Rear-LiDAR dependence on the base iPhone 17 path - prohibited by the human lock.
- Model-owned mutation, hidden automatic merge, or renderer/provider index identity - deterministic application code and stable prefixed IDs remain authoritative.

## Runtime and Delivery Context

- Mode A is native SwiftUI on iPhone. ARKit owns healthy-session pose/world authority, and the live camera remains the photoreal background.
- The native renderer draws only edit, reveal, occlusion, conservative shadow, and UI overlays. The 60 Hz path never waits synchronously for a network, worker, web client, or model.
- Mode B0 is a separate Next.js client backed by the shared gateway/service contracts. It guarantees `.rrcap` replay, inspection, sessions, sharing, typed proposals, and honest degraded visualization without learned providers.
- The gateway owns durable replication and explicit B0 forks; a Next.js route handler does not own stateful processing or production WebSockets.
- Delivery assumes two developers using Codex and Sol, but work is divided only by dependency and risk slices. At most two implementation-critical streams may be active, with joins through versioned contracts and replay fixtures rather than person assignments.
- SQLite WAL plus content-addressed filesystem storage is the P0 baseline. GPU work is bounded and priority-based, and compute is declared by measured capability tier rather than hidden mandatory hardware.

## Constraints

- **Authority**: Human locks and Accepted ADRs outrank provisional ADRs, specifications/contracts, the PRD, and supporting strategy documents. Conflicts require explicit human escalation; they are not resolved inside a phase plan.
- **Contracts**: CON-001 through CON-005 are closed exact `1.0.0` schemas. RR-COORD-1, RR-FLOAT-1, RR-JCS-SHA256-1, closed codecs, path safety, and stable prefixed IDs apply at every boundary; unknown fields or versions reject without a named migration.
- **Capture**: Selected image bytes and matching metadata become locally durable and globally journaled before network eligibility. The contiguous journal is authoritative replay order.
- **Transactions**: One branch authority performs compare-and-swap commits. Preview changes no revision; explicit confirmation increments exactly once; idempotency binds key and request fingerprint; restore is a new compensating transaction over a verified captured-exact inverse.
- **Geometry and identity**: Fast interaction proxies and optional dense enhancement remain distinct. Dense outputs cannot rewrite ARKit trajectory, stable IDs, committed transactions, or the no-dense path.
- **Removal**: Controlled-fixture removal remains a P0 release gate. Per-session unavailability is allowed, but failure of the controlled gate blocks P0 unless a human explicitly changes the lock.
- **Security and privacy**: Imagery, geometry, metadata, prompts, and model output are sensitive and untrusted. Credentials remain server-controlled; capture/upload/share require consent and visible state; retention/deletion/share access are explicit.
- **Evidence**: Physical device, Xcode/signing, compositor, thermal, visual-vote, license, and human confirmation gates require real evidence and cannot be replaced by simulator or model assertions.
- **Planning boundary**: These drafts initialize planning only. Every phase still requires an approved detailed plan before any implementation action.

## Key Decisions

<decisions>

### Locked Decisions

Each block below is an Accepted ADR decision and is locked for planning. Changing one requires the explicit human escalation defined by canonical authority.

#### ADR-001 - Product modes, exact P0 scope, and B1 isolation

**Status:** Locked (Accepted)

**Decision:** P0 exposes exactly `place`, `replace`, `remove`, and `restore`; undo invokes restore. Mode B0 is guaranteed. B1 and XR remain outside the P0 critical path. Removal may be unavailable in unsupported sessions, but controlled-fixture removal remains a release gate.

#### ADR-002 - Native iPhone hero and separate web client

**Status:** Locked (Accepted)

**Decision:** SwiftUI plus a native AR session/rendering boundary owns Mode A. A separate Next.js client owns B0 upload, replay, inspection, sessions, sharing, and typed proposals. The gateway, not a Next.js route handler, owns stateful processing and production WebSockets.

#### ADR-003 - ARKit world authority and RR-COORD-1

**Status:** Locked (Accepted)

**Decision:** ARKit is healthy native world/pose authority. FramePackets use upright encoded bytes, encoded-pixel intrinsics, explicit sensor-to-encoded transforms, row-major serialization with column-vector math, decimal-string monotonic nanoseconds, and explicit validated world-epoch corrections. Unknown alignment is quarantined rather than guessed.

#### ADR-004 - Record-first capture, transport, and replay

**Status:** Locked (Accepted)

**Decision:** A selected frame follows the exact durability lifecycle before network eligibility. One contiguous global journal is sole replay order; frame/event arrays are exact projections; events are self-digested; replay input uses RR-JCS-SHA256-1 over ordered journal tuples. Live queues are bounded while durable capture is retained.

#### ADR-006 - Separate fast and dense geometry tracks

**Status:** Locked (Accepted)

**Decision:** The fast path owns calibrated masks, conservative mask volume, OBB, support, and reveal/view-envelope evidence. Dense processing may add surface, collision, occlusion, and B0 evidence but cannot rewrite stable IDs or committed transactions. A mask volume is not collision-quality geometry.

#### ADR-008 - Canonical scene identity and capability readiness

**Status:** Locked (Accepted)

**Decision:** Stable prefixed UUIDs, never renderer/provider indices, carry scene identity. Object lifecycle is separate from independent `select`, `place`, `replace`, `remove`, and `restore` readiness. Client-side artifact verification and activation precede use.

#### ADR-010 - Curated asset contract and derivatives

**Status:** Locked (Accepted)

**Decision:** Stable `asset_id` manifests bind normalized dimensions/origin/axis, visual and collision bounds, paired USDZ/GLB derivatives, budgets, hashes, delivery, provenance, license, and attribution. Hero assets are bundled or pre-cached and hash-verified; runtime conversion is excluded from the hero path.

#### ADR-011 - Agent intent and deterministic system boundary

**Status:** Locked (Accepted)

**Decision:** Typed/tap input completes all four operations through a schema-validated nonmutating proposal boundary without model or network. Optional Realtime/GPT interprets semantic/design intent only. Deterministic code retains target, transform, spatial, revision, persistence, confirmation, commit, and restore authority; credentials and allowlists stay server-controlled.

#### ADR-012 - Revisioned transactions and offline restore

**Status:** Locked (Accepted)

**Decision:** Each revision branch has one writer. Preview does not increment; confirmed CAS commit increments once. Idempotency binds key plus RR-JCS request fingerprint. History is immutable. Restore is a new compensating transaction applying a verified persisted inverse through RR-RESTORE-REBASE-1 while preserving new/unaffected state; sync state is separate.

#### ADR-013 - Guaranteed Mode B0 minimum

**Status:** Locked (Accepted)

**Decision:** Provider-independent B0 includes capture import, manifest/hash validation, exact packet/event replay, timeline and processing state, canonical inspection, typed shared-service transactions, and degraded visualization. Ordinary-video replay is supported without fabricating optional trajectory or geometry.

#### ADR-014 - Minimal service topology and hardware tiers

**Status:** Locked (Accepted)

**Decision:** Use native/web clients, a gateway that validates and durably replicates active phone branches and may own distinct B0 forks, and only gate-selected CV worker profiles. SQLite WAL plus content-addressed filesystem storage is the P0 baseline. GPU work is bounded and hardware is a measured capability tier, not a mandatory SKU.

### Provisional Decisions

These ADRs are usable only behind their named boundaries. Their thresholds remain TARGET values until measured. Missing evidence or a missed timebox activates the documented fallback; it does not expand or demote P0.

#### ADR-005 - RealityKit-first camera-feed compositor

**Status:** Provisional

**Decision:** Start with RealityKit behind a renderer boundary; keep only a bounded minimal Metal spike as an escape hatch.

**Benchmark / kill gate:** `GATE-003`; canned multi-surface reveal/occluder/normalized-asset fixture plus the hero room; RealityKit primary versus minimal Metal prototype; correct ordering at eight poses, severe-artifact count, four-minute FPS/thermal/memory, and 4/5 visual vote. Passing requires no severe ordering artifact, at least 45 FPS, no crash/jetsam or sustained serious/critical thermal state, and 4/5 vote.

**Timebox / deadline:** Four hours in the first device-risk slice. A missed threshold or timebox kills that renderer variant.

**Fallback:** Reduce reveal complexity and use validated replacement compositing first; use Metal only if the bounded spike already proves ordering and frame budget. If neither passes, `GATE-003` blocks Mode A completion and B0 supplies resilience without a Mode A-complete claim.

#### ADR-007 - Versioned segmentation and depth providers

**Status:** Provisional

**Decision:** Use versioned provider interfaces. SAM 2.1 Hiera Small is the initial semantic default; an accessible, license-approved SAM 3.1 checkpoint is an optional measured upgrade. Native depth chooses among DA3Metric-Large, pose-conditioned Apache-licensed DA3 Small/Base, or no-dense. LingBot is optional offline ordinary-video processing and is not in guaranteed B0.

**Semantic benchmark / kill gate:** `GATE-004`; 20 annotated hero frames plus one 60-second replay; median IoU at least 0.80, p10 IoU at least 0.65, zero hero-target identity switches, seed-to-first-mask p95 at most 1.5 seconds, zero sustained queue growth, fit within the selected tier, and recorded access/license.

**Semantic timebox / deadline:** Four hours, completed before semantic integration. A tie or missed timebox selects SAM 2.1 Small.

**Depth benchmark / kill gate:** `GATE-007`; one shared `.rrcap` with a taped floor and three taped distances; live enhancement requires floor RMSE at most 0.025 m, every taped error within +/-4%, accepted-update p95 at most 450 ms, no two-minute queue growth, and no OOM.

**Depth timebox / deadline:** Four hours before any dense integration. Failure selects no-dense live and may retain the provider for offline research only. LingBot receives no P0 time unless `GATE-008` is already green.

**Fallback:** Freeze the best validated masks with explicit reseeding; use the no-dense fast path and plane/point B0; ordinary video retains deterministic media replay and processing status without learned geometry.

#### ADR-009 - Multi-surface reveal and supported view envelope

**Status:** Provisional

**Decision:** Use a versioned, view-bounded multi-surface reveal bundle with explicit planar polygon/UV mapping, provenance, foreground proxies, and quality evidence. A commit pins its reveal revision; improvements require a new validated, previewed, explicitly confirmed transaction.

**Benchmark / kill gate:** `GATE-006`; controlled hero capture with at least eight trajectory poses; observed-only atlas, deterministic local fill, and the simplest license-approved fallback if already available. Pass requires p10 target coverage at least 0.95, median coverage at least 0.98, no uncovered component over 1%, no severe foreground overwrite, correct seam/surface order, and at least 4/5 of exactly five blinded visual votes.

**Timebox / deadline:** One reveal slice, completed before voice integration or release rehearsal. Failure kills remove readiness for the fixture and blocks P0 completion.

**Fallback:** Request another view, shrink the supported envelope, select the easier controlled target, or keep remove unavailable for the session while replacement remains usable. Controlled-fixture failure still blocks P0 under ADR-001.

</decisions>

## Evolution

- Requirement IDs, locked decisions, contract terms, and gate thresholds are not redefined inside planning artifacts.
- After a phase completes, update requirement status only when implementation and required evidence both pass.
- Provisional benchmark results must synchronize the ADR, research ledger, risk gate, and any affected requirement/schema before a decision becomes measured.
- Future/stretch work may enter a later roadmap only through explicit human approval and may never weaken P0 acceptance.

---
*Last updated: 2026-07-15 after staged documentation ingest and initial roadmap drafting.*
