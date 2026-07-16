# Synthesized Decisions

Mode: `new`. Precedence uses each classification's manifest override; lower integers are stronger. Human-locked authority from `docs/canonical/README.md` at precedence `-10` remains above Accepted ADRs at `0`. Every decision below is preserved independently.

This file is an ingest index, not a new source of authority. `locked` entries summarize Accepted ADRs and must be verified against their live source before a material change. `proposed` entries are benchmark-bounded candidates, not mandatory technology selections. Research may introduce a better eligible variant when it preserves the governing contracts and acceptance gates; adopting a load-bearing change requires the appropriate ADR update and any required human escalation.

## ADR-001 — Product modes, exact P0 scope, and B1 isolation

- source: docs/adr/ADR-001-product-modes-and-p0-scope.md
- status: locked
- precedence: 0
- scope: product operations; Mode B0/B1; XR; controlled P0 release
- decision: P0 has exactly `place`, `replace`, `remove`, and `restore`; undo invokes restore. Mode B0 is guaranteed, while B1 and XR stay outside the P0 critical path. Removal may be unavailable in unsupported sessions, but controlled-fixture removal remains a release gate.

## ADR-002 — Native iPhone hero and separate web client

- source: docs/adr/ADR-002-native-iphone-and-web-split.md
- status: locked
- precedence: 0
- scope: Mode A; Mode B0; native/web split; gateway ownership
- decision: SwiftUI plus a native AR session/rendering boundary owns Mode A. A separate Next.js client owns B0 upload, replay, inspection, sharing, sessions, and typed proposals. The gateway, not a Next.js route handler, owns stateful processing and production WebSockets.

## ADR-003 — ARKit world authority and RR-COORD-1

- source: docs/adr/ADR-003-arkit-authority-and-coordinates.md
- status: locked
- precedence: 0
- scope: ARKit authority; coordinates; transforms; timestamps; world resets
- decision: ARKit is the healthy native world/pose authority. FramePacket data follows RR-COORD-1, including upright encoded bytes, encoded-pixel intrinsics, explicit sensor-to-encoded transforms, row-major serialization with column-vector math, decimal-string monotonic nanoseconds, and explicit validated world-epoch corrections. Unknown alignment is quarantined, never guessed.

## ADR-004 — Record-first capture, transport, and replay

- source: docs/adr/ADR-004-atomic-capture-and-record-first-replay.md
- status: locked
- precedence: 0
- scope: atomic capture; durability; transport; replay; queues; digests
- decision: A selected frame progresses through the exact durability lifecycle before becoming network-eligible. One contiguous global journal is the sole replay order; frame/event arrays are exact projections, events are self-digested, and the replay input digest uses RR-JCS-SHA256-1 over ordered journal tuples. Live queues stay bounded while durable capture is retained.

## ADR-005 — RealityKit-first camera-feed compositor

- source: docs/adr/ADR-005-realitykit-first-compositor.md
- status: proposed
- precedence: 10
- scope: Mode A renderer; compositing order; RealityKit; bounded Metal fallback; GATE-003
- decision: Start with RealityKit behind a renderer boundary, drawing camera background, occluders, reveal layers, assets, conservative shadows, and UI in deterministic order. A minimal Metal spike is only a bounded escape hatch. The physical-device benchmark decides which variant survives.

## ADR-006 — Separate fast and dense geometry tracks

- source: docs/adr/ADR-006-fast-and-dense-geometry-tracks.md
- status: locked
- precedence: 0
- scope: fast interaction proxies; dense enhancement; stable identity; readiness
- decision: The fast path owns calibrated masks, conservative mask volume, OBB, support, and reveal/view-envelope evidence. Dense processing may add surface, collision, occlusion, and B0 evidence, but cannot rewrite stable IDs or committed transactions. A mask volume is not collision-quality geometry.

## ADR-007 — Versioned segmentation and depth providers

- source: docs/adr/ADR-007-segmentation-and-depth-providers.md
- status: proposed
- precedence: 10
- scope: semantic/depth providers; licensing; benchmarks; fallbacks
- decision: Use versioned provider interfaces. SAM 2.1 Hiera Small is the initial semantic default, SAM 3.1 is an optional measured upgrade, native depth is chosen among eligible DA3 variants or no-dense, and LingBot is optional offline processing rather than part of guaranteed B0. Code, checkpoint, license, and runtime must be pinned before use.

## ADR-008 — Canonical scene identity and capability readiness

- source: docs/adr/ADR-008-scene-identity-and-readiness.md
- status: locked
- precedence: 0
- scope: stable IDs; lifecycle; per-capability readiness; artifact activation
- decision: Canonical scene identity uses stable prefixed UUIDs and never renderer/provider indices. Object lifecycle remains separate from readiness. `select`, `place`, `replace`, `remove`, and `restore` each use independent readiness values and require client-side artifact verification/activation before use.

## ADR-009 — Multi-surface reveal and supported view envelope

- source: docs/adr/ADR-009-multi-surface-reveal.md
- status: proposed
- precedence: 10
- scope: reveal bundles; surface mapping; provenance; view envelope; GATE-006
- decision: Empty removal uses a versioned, view-bounded multi-surface reveal bundle with explicit planar polygon/UV mapping, provenance, foreground proxies, and quality evidence. Exactly five human votes plus objective coverage/order thresholds gate readiness. A commit pins its reveal revision; later improvements require a new validated, previewed, explicitly confirmed transaction.

## ADR-010 — Curated asset contract and derivatives

- source: docs/adr/ADR-010-asset-contract.md
- status: locked
- precedence: 0
- scope: curated catalog; manifests; USDZ/GLB; collision; licenses; local delivery
- decision: A stable `asset_id` identifies a canonical manifest containing normalized dimensions/origin/axis, visual and collision bounds, paired native/web derivatives, budgets, hashes, delivery state, provenance, license, and attribution. Hero assets are bundled or pre-cached and hash-verified; runtime conversion is excluded from the hero path.

## ADR-011 — Agent intent and deterministic system boundary

- source: docs/adr/ADR-011-agent-and-deterministic-boundary.md
- status: locked
- precedence: 0
- scope: typed/tap intent; optional voice; GPT proposals; deterministic mutation; credentials
- decision: Typed/tap input completes all four operations through a schema-validated nonmutating proposal boundary without a model or network. Optional Realtime and GPT may interpret semantic/design intent only. Deterministic application code retains target, transform, spatial, revision, persistence, confirmation, commit, and restore authority; credentials and allowlists remain server-controlled.

## ADR-012 — Revisioned transactions and offline restore

- source: docs/adr/ADR-012-transaction-and-offline-restore.md
- status: locked
- precedence: 0
- scope: branch authority; CAS revisions; idempotency; inverses; offline restore; reconciliation
- decision: Each revision branch has one writer. Preview does not increment revisions; a confirmed CAS commit increments exactly once. Idempotency binds key plus RR-JCS request fingerprint. Commit history is immutable, and restore is a new compensating transaction that applies a verified persisted inverse through RR-RESTORE-REBASE-1 while preserving new/unaffected state. Sync state is separate from canonical lifecycle.

## ADR-013 — Guaranteed Mode B0 minimum

- source: docs/adr/ADR-013-mode-b0-guarantee.md
- status: locked
- precedence: 0
- scope: `.rrcap` import; deterministic replay; inspection; typed transactions; degraded visualization
- decision: Guaranteed B0 is provider-independent: capture import, manifest/hash validation, exact packet/event replay, timeline and processing state, canonical inspection, typed transactions on the shared service, and degraded visualization. Ordinary-video replay is supported, while estimated trajectory/geometry remains explicitly optional and capability-gated.

## ADR-014 — Minimal service topology and hardware tiers

- source: docs/adr/ADR-014-service-topology-and-hardware-tiers.md
- status: locked
- precedence: 0
- scope: gateway; branch authority; CV profiles; persistence; GPU scheduling; hardware tiers
- decision: Use a minimal logical topology: native/web clients, a gateway that validates and durably replicates active phone branches and can own distinct B0 forks, and only gate-selected CV worker profiles. SQLite WAL plus content-addressed filesystem storage is the P0 baseline. GPU work is bounded and priority-based; hardware is declared by measured capability tier, not mandatory SKU.
