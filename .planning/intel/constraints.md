# Synthesized Constraints

These entries consolidate seven SPEC-classified sources into non-overlapping technical constraints. Field and lifecycle detail remains authoritative in the cited JSON Schema.

## System architecture and authority boundary

- source: docs/canonical/MASTER_TECHNICAL_SPEC.md
- type: nfr
- content: Mode A is native SwiftUI/ARKit with the live camera as background and one native writer for the active branch. Mode B0 is a separate Next.js replay/inspection surface. The 60 Hz loop stays local and never synchronously waits for network, GPU workers, the web client, or an LLM. Gateway, provider, renderer, and model outputs remain subordinate to canonical IDs, branch authority, deterministic validation, and local rendering.

## Fast path, renderer, and dense-enhancement separation

- source: docs/canonical/MASTER_TECHNICAL_SPEC.md
- type: nfr
- content: The P0 fast path uses ARKit planes/raycasts, target-first masks, conservative mask volume/OBB/support proxies, curated assets, and observed reveal evidence. RealityKit-first compositing is provisional and benchmark-gated. Dense depth/fusion may upgrade evidence but cannot block capture, replay, place, replace, restore, or local rendering; it cannot rewrite ARKit trajectory, stable IDs, or committed history.

## Service, security, and model proposal boundary

- source: docs/canonical/MASTER_TECHNICAL_SPEC.md
- type: nfr
- content: Use the minimal service topology and only gate-selected provider profiles. GPU queues and admission are bounded, incompatible profiles need not coexist, and hardware is expressed as measured tiers. Typed/tap input is the complete P0 proposal path. Optional Realtime/GPT may return only typed semantic proposals; deterministic code owns target authorization, transforms, spatial checks, readiness, revision, confirmation, commit, restore, and reconciliation. Treat imagery, derived geometry, prompts, metadata, and model output as sensitive/untrusted data.

## Frozen contracts and explicit evolution

- source: docs/contracts/README.md
- type: protocol
- content: CON-001 through CON-005 are closed exact `1.0.0` schemas using Draft 2020-12. A 1.0 reader rejects extra fields and every other version. Compatibility requires a named, tested migration; additive changes publish a new schema file and exact `$id`, breaking changes publish a new major, and unrepresentable down-conversion rejects without dropping fields. RR-COORD-1, RR-FLOAT-1, RR-JCS-SHA256-1, closed codecs, prefixed IDs, and archive-relative path safety apply across contracts.

## CON-001 atomic FramePacket and RRFP-WIRE-1

- source: docs/contracts/frame-packet.schema.json
- type: protocol
- content: A FramePacket is a closed `1.0.0` object binding session/submap/frame/world IDs, world version, capture sequence, decimal-string monotonic time, upright encoded image, encoded-pixel intrinsics, `encoded_from_sensor`, `world_from_camera`, tracking, quality, durability, idempotency, payload SHA, and wire framing. Durability exposed to transport is exactly `network_eligible` with image/metadata durable and a journal sequence. RRFP-WIRE-1 uses a 24-byte big-endian fixed header, bounded JCS header (64 KiB), bounded image payload (16 MiB), no trailer, and exact duplicate sequence/length/SHA checks; any mismatch or tamper rejects atomically.

## CON-002 capture manifest and replay authority

- source: docs/contracts/rrcap-manifest.schema.json
- type: protocol
- content: A `.rrcap` manifest inventories files and one unique contiguous journal from sequence zero. Accepted frames and events are exact journal projections; event `record_sha256` omits only itself, the replay input digest hashes the ordered tuple array, finalization names the last durable journal sequence, and corrupt recovery stops at the valid prefix. Native ARKit capture requires RR-COORD-1 and capture settings with `lidar_required=false`. Ordinary-video import is a separate uncalibrated variant with empty ARKit frame/keyframe arrays, decode/timeline-only guarantee, and no fabricated world authority.

## CON-003 scene identity, readiness, and edit-managed state

- source: docs/contracts/scene-state.schema.json
- type: schema
- content: SceneState is a closed `1.0.0` object with explicit revision authority/branch, monotonic scene revision, one ARKit world epoch, stable surfaces/objects/support/assets/history, and timestamps. Native-device and replay-gateway authorities are distinct variants. Object lifecycle is `candidate|tracked|lost|retired`; readiness is independent for `select|place|replace|remove|restore` using the five closed readiness values. Every non-ready capability needs a typed reason and every ready capability has none. Canonical object edit state is `visible` plus nullable typed reveal reference; an active reveal requires `visible=false`. Renderer bindings are disposable and never identity.

## CON-004 artifact provenance and typed payload registry

- source: docs/contracts/edit-artifacts.schema.json
- type: schema
- content: The closed artifact union is `mask_volume`, `surface_mesh`, `obb`, `occluder_chunk`, `reveal_bundle`, `asset_manifest`, and `world_frame_correction`. Every artifact binds stable ID/revision, immutable origin branch, activation branch, producing authority, scene/world epoch, provider provenance, readiness, exact payload references, and an RR-JCS content digest. Cross-fork reuse requires a new activation record with preserved origin/content hash and validated compatible world epoch.

## CON-004 explicit spatial encodings

- source: docs/contracts/edit-artifacts.schema.json
- type: api-contract
- content: Mesh vertices are already meter-valued RR-COORD-1 artifact-world coordinates. Sparse voxel masks declare `world_from_volume`, XYZ voxel size/dimensions, NPY `z_y_x` shape, C-contiguous `uint8` occupancy values 0/1, and the index-plus-half center rule. P0 reveal layers use a closed convex CCW local-XY planar polygon whose vertices pair meter coordinates with normalized top-left UVs and deterministic fan triangulation. No consumer may infer transforms, scale, array layout, or generic mesh-atlas mapping from file type.

## CON-004 reveal readiness gate

- source: docs/contracts/edit-artifacts.schema.json
- type: api-contract
- content: A reveal bundle binds one target, one or more surface-specific layers with explicit provenance/mapping, a supported view envelope, foreground occluder artifacts, and GATE-006 evidence. `ready` requires coverage P10 at least 0.95, median at least 0.98, largest uncovered component at most 0.01, no severe foreground overwrite, no severe seam/order result, and at least four passes from exactly five votes. Observed and synthesized provenance remain explicit.

## CON-004 curated asset manifest readiness

- source: docs/contracts/edit-artifacts.schema.json
- type: schema
- content: An asset manifest binds stable catalog identity, canonical meter dimensions/bounds, floor-center Y-up origin, minus-Z forward axis, exact source/digest/author, license terms and approval evidence, texture budgets, local delivery, native USDZ, web GLB, collision proxy, LODs, and validation evidence. Ready assets require approved use and redistribution, verified native/web delivery, no network at edit time, and required attribution when applicable.

## CON-005 transaction lifecycle, fingerprint, and commit

- source: docs/contracts/transaction.schema.json
- type: protocol
- content: A transaction binds stable ID/idempotency key, RR-JCS request fingerprint over the exact named proposal members, session/branch authority, base revision, captured target context, typed intent, ordered operations, validation, canonical state, and separate sync state. Committed records require passed operation-specific checks, a preview at the unchanged base revision, explicit user confirmation bound to that preview, matching authority/branch CAS from `r` to `r+1`, local durability before visible acknowledgement, one captured-exact snapshot inverse, and a local undo token. Same key/different fingerprint is a protocol conflict.

## CON-005 exact reducers and compensating restore

- source: docs/contracts/transaction.schema.json
- type: protocol
- content: P0 forward operations have exact orders: place creates one asset/support atomically; replace hides then creates, optionally activating reveal first; remove activates reveal then hides; restore applies one snapshot. RR-EDIT-PROJECTION-1 contains only complete edit-managed object state, placed assets with full manifest references, asset-subject support relations, and scene/branch/world identity, with stable-ID sorting. RR-RESTORE-REBASE-1 verifies the source inverse and touched IDs, applies only those inverse after-values atop the current complete projection, preserves new/unaffected IDs, rejects touched drift or branch/world mismatch, and emits a fresh higher-revision SceneState without rewriting history.
