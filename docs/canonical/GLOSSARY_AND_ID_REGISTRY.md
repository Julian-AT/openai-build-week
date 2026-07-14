# Glossary and ID Registry

Status: canonical naming authority  
Version: 1.0.0  
Date: 2026-07-13

## Product modes

| Term | Canonical meaning |
|---|---|
| **Mode A** | Live, native iPhone AR editing. ARKit owns pose/world state; the camera feed is the photoreal background and virtual edit artifacts are composited over it. |
| **Mode B0** | Guaranteed P0 recorded/replay path: local `.rrcap` capture, exact ordered replay, web inspection/fallback, sessions, typed transactions, and degraded visualization. Ordinary recorded video may be ingested, but learned RGB-to-geometry quality is capability-gated rather than guaranteed. |
| **Mode B1** | Stretch-only offline photoreal refinement/reconstruction. It cannot block, rewrite, or become a hidden dependency of Mode A or B0. |

## Capture and coordinates

| Term | Canonical meaning |
|---|---|
| **FramePacket** | Versioned, atomic association of one encoded image with its IDs, monotonic timestamp, encoded-pixel intrinsics, orientation/crop transform, `world_from_camera` pose, tracking/quality evidence, ordering, and idempotency metadata. |
| **`.rrcap`** | Record-first directory/archive format whose manifest inventories content-addressed files, one global journal, accepted frame/event projections, keyframes, coordinate convention, replay policy, and privacy metadata. The contiguous `journal_sequence` is the sole replay order. |
| **ordinary-video import** | CON-002 `capture_kind=ordinary_video_import`: exact MP4/MOV bytes plus media timeline/events with `uncalibrated_no_world_authority`. It has no RR-COORD-1/ARKit world frame, capture settings, accepted ARKit frames, or keyframes; geometry is unavailable unless an optional provider later supplies explicitly gated evidence. |
| **world frame** | One ARKit world-coordinate epoch named by `world_frame_id` and `world_frame_version`. A relocalization/reset that changes its meaning creates a new version and an explicit correction artifact; it is never silently overwritten. |
| **RR-COORD-1** | Coordinate convention: right-handed ARKit world meters; camera looks along local `-Z`; `world_from_camera` transforms camera coordinates into world coordinates; matrices serialize row-major but math uses column vectors; image origin is top-left and pixel centers are `(x+0.5,y+0.5)`; transmitted image bytes are physically upright; intrinsics are in transmitted encoded-pixel coordinates. |
| **RR-FLOAT-1** | Cross-language numeric policy for RR-COORD-1. Producers quantize matrix/intrinsic/scalar contract values to finite IEEE-754 binary32, reject magnitude above `3.4028234663852886e38`, and serialize a decimal that round-trips to that binary32; NaN and infinities are invalid JSON. Scalar/matrix equality uses `abs(a-b) ≤ 1e-5 + 1e-6×max(abs(a),abs(b))`; translation components also require absolute error ≤`1e-4 m`; transformed intrinsics require absolute error ≤`1e-3 encoded pixel`. A rigid transform requires `||RᵀR-I||F ≤1e-4`, `abs(det(R)-1) ≤1e-4`, and homogeneous last-row absolute error ≤`1e-6` from `[0,0,0,1]`. The separate end-to-end projection gate remains ≤`1 encoded pixel`. |
| **RR-JCS-SHA256-1** | Deterministic structured digest: serialize the named JSON value with RFC 8785 JCS, encode UTF-8 without BOM, then SHA-256 and lowercase hexadecimal. Raw-file inventory SHA-256 is over exact bytes. An event record digest hashes the complete CON-002 event with only `record_sha256` omitted. `.rrcap` input digest hashes the JCS array `[[journal_sequence,entry_type,reference_id,content_sha256], ...]` in contiguous ascending journal order. Manifest digest hashes the entire manifest with only `finalization.manifest_sha256` omitted. Transaction request fingerprint hashes an object containing exactly `schema_version`, `session_id`, `revision_authority`, `base_scene_revision`, `target_context`, `intent`, and `proposed_operations`; IDs, idempotency key, timestamps, states, validation/results, preview, commit, inverse, sync, failures, and reconciliation are excluded. Commit result digest hashes the commit object with only `result_sha256` omitted. RR-EDIT-PROJECTION-1 digest hashes exactly the transaction snapshot's `projection` member; captured revision, origin, derivation, and digest metadata are outside that projection digest, while a restore proposal's request fingerprint still binds all proposed-operation metadata. |
| **RR-EDIT-PROJECTION-1** | Closed edit-managed SceneState projection: scene/branch/world identity, all object `edit_state` values, placed assets with full typed asset-manifest revision/digest references, and asset-subject support relations, with arrays in lexicographic stable-ID order. It excludes monotonic/document envelopes, tracking/readiness evidence, surfaces, non-asset support, edit history, and timestamps. Restore applies a verified complete derived projection into a fresh higher-revision SceneState; it never restores an old full document. |
| **RR-RESTORE-REBASE-1** | Restore derivation rule: diff the compensated transaction's persisted captured-exact inverse projections to obtain touched stable IDs, verify them against its ordered operations, then apply only the inverse after-values for those IDs to the current complete RR-EDIT-PROJECTION-1. Preserve current new/unaffected IDs. Record source transaction and both inverse hashes; mismatch, unexpected drift, branch/world change, or a non-latest compensation rejects. |
| **readiness reason** | Typed blocker attached to one of `select`, `place`, `replace`, `remove`, or `restore`. The closed CON-003 registry includes direct codes for unsupported target category, unavailable provider, missing artifact/support, failed reveal/license/integrity, no eligible restore, world-frame mismatch, tracking/authority/durability failures, and view/proxy blockers; a non-ready capability never relies on an uncoded free-text cause. |
| **sensor-to-encoded transform** | `encoded_from_sensor`, a 3x3 homogeneous pixel transform mapping sensor pixel coordinates to physically encoded/transmitted image pixel coordinates, after orientation/crop/scale. Metadata orientation is always `up` in RR-COORD-1. |
| **world-frame correction** | Directed validated transform between versions of one `world_frame_id`: `p_to = T_to_from_from · p_from`. `to_world_frame_version` equals the artifact base `world_frame_version` and is greater than `from_world_frame_version`. If the transform is unknown, no correction artifact is emitted; the new epoch is quarantined until validated alignment or explicit reseed. |

## Scene and geometry

| Term | Canonical meaning |
|---|---|
| **scene state** | Versioned semantic state keyed by stable surface, object, asset, and artifact IDs. It never uses renderer array indices as identity. |
| **scene revision** | Monotonic integer changed exactly once by a successful canonical commit; previews and local sync-state changes do not increment it. |
| **canonical geometry** | Persistent world-space surfaces and conservative object/support representations used by deterministic validation. Renderer meshes and neural outputs are derived evidence, not identity. |
| **proxy/occluder geometry** | Disposable render-oriented geometry used for depth/occlusion. It references canonical IDs and may be regenerated without changing scene identity. |
| **object mask volume** | Conservative world-space visual occupancy derived from multi-view masks; used for cutout/occlusion. It is not a collision-quality surface. |
| **object surface mesh** | Object surface estimate used only for capabilities whose quality gate it passes; distinct from mask volume and OBB. |
| **OBB** | Oriented bounding box proxy used for selection, coarse collision, footprint, and support checks. |
| **reveal bundle** | Multi-surface collection for empty removal, containing one or more reveal layers plus view-envelope and quality evidence. |
| **reveal layer** | Observed or deterministic-fill texture/geometry for one background surface, with provenance and confidence. |
| **artifact branch provenance** | Every artifact record names immutable payload origin branch, activation branch, producing authority, scene/world revision, and RR-JCS digest. Cross-fork reuse never aliases records: it creates a new activation record preserving origin/content hash and only after world-epoch compatibility validation. |

## Lifecycle and readiness

Object lifecycle values are `candidate`, `tracked`, `lost`, `retired`. Capability readiness is independent and uses `unavailable`, `warming`, `ready`, `degraded`, `failed` for each of `select`, `place`, `replace`, `remove`, and `restore`. An object may be replace-ready while remove-unavailable. P0 release still requires the removal gate to pass on the controlled hero fixture.

Tracking state values are `normal`, `limited`, and `not_available`. Transaction state values are defined below. Artifact readiness uses the same five readiness values.

The normative capture lifecycle is exactly `selected → image_and_metadata_durable → journaled → network_eligible → server_acknowledged`. CON-002 event types use `frame_selected`, `frame_image_and_metadata_durable`, `frame_journaled`, `frame_network_eligible`, and `frame_server_acknowledged`; event names are evidence of transitions, not a second lifecycle.

Session presentation state is UI-derived and noncanonical: `initializing`, `coaching`, `tracking`, `degraded`, `offline`, `recovering`, or `ready_for_edit`. It may be logged as an event payload but is never revision authority, capability readiness, or persisted SceneState identity.

## Transactions and offline state

| Term | Canonical meaning |
|---|---|
| **transaction** | Versioned intent plus captured target context, proposed deterministic operations, validation result, preview, commit, inverse operations, and reconciliation metadata. |
| **transaction lifecycle** | `draft` → `validated` → `previewed` → `committed`, or `rejected`/`cancelled`. Undo is a new committed compensating transaction referencing the original; original history is immutable. |
| **sync state** | Local transport state independent of canonical transaction state: `local_only`, `pending_sync`, `synced`, `conflict`, or `sync_failed`. A locally committed edit remains renderable offline. |
| **idempotency rule** | Reuse of an idempotency key with the same request fingerprint returns the prior result; reuse with a different fingerprint is a protocol conflict. |
| **revision authority** | Exactly one writer for one `revision_branch_id`. A live Mode A branch is owned by its native `device_…`; the gateway validates and durably replicates its ordered journal. A B0 replay fork may be owned by `gateway_…`. Web input against an active phone branch is proposal-only. Unexpected divergence is quarantined on another branch and requires snapshot reconciliation; there is no automatic merge. |

## Edit artifact variants

The closed artifact type set is `mask_volume`, `surface_mesh`, `obb`, `occluder_chunk`, `reveal_bundle`, `asset_manifest`, and `world_frame_correction`. Detailed fields and variants live in `docs/contracts/edit-artifacts.schema.json`.

## Stable ID families

| Family | Pattern | Purpose |
|---|---|---|
| Requirement | `FR-*`, `NFR-*`, `SEC-*`, `OPS-*`, `STR-*` | Functional, nonfunctional, security/privacy, operational/demo, and stretch requirements. |
| ADR | `ADR-NNN` | Load-bearing architecture decision. |
| Claim | `CLM-NNN` | Research-ledger evidence claim. |
| Risk/gate | `GATE-NNN` | Timeboxed risk and kill gate. |
| Assumption | `ASM-NNN` | Explicit unresolved assumption. |
| Contract | `CON-NNN` | Contract family reference. |
| Runtime entity | prefixed lowercase RFC 9562 UUID v4/v7 strings: `session_`, `submap_`, `frame_`, `event_`, `world_`, `scene_`, `surface_`, `object_`, `support_`, `artifact_`, catalog `asset_`, placed instance `assetinst_`, `layer_`, `envelope_`, `preview_`, `undo_`, session-pseudonymous `user_`, `device_`, `gateway_`, `branch_`, and `tx_` | Stable identity across capture, scene, artifact, transaction, and replay records. Catalog and placed-instance identity are distinct. Prefix plus canonical `8-4-4-4-12` form is required; renderer indices, nil IDs, uppercase aliases, or malformed hyphen strings are invalid. |
| Idempotency key | `frameidem_` or `txidem_` plus lowercase RFC 9562 UUID v4/v7 | Opaque protocol key with equality semantics only. It is not an ordered entity identity, timestamp, secret, authorization token, or request fingerprint. |
| Local renderer handle | implementation-local opaque value with no canonical prefix | Disposable binding only. It never crosses a contract boundary or participates in identity, hashes, replay, or reconciliation. |

IDs are immutable once published. Removed requirements remain reserved and marked superseded; they are not renumbered.

## Contract registry

| ID | Schema | `$id` |
|---|---|---|
| CON-001 | `frame-packet.schema.json` | `urn:reroom:schema:frame-packet:1` |
| CON-002 | `rrcap-manifest.schema.json` | `urn:reroom:schema:rrcap-manifest:1` |
| CON-003 | `scene-state.schema.json` | `urn:reroom:schema:scene-state:1` |
| CON-004 | `edit-artifacts.schema.json` | `urn:reroom:schema:edit-artifacts:1` |
| CON-005 | `transaction.schema.json` | `urn:reroom:schema:transaction:1` |
