# ReRoom Versioned Contracts

These JSON Schemas are the field and lifecycle authority at every external boundary. They are not generated bindings. Shipping/demo code must validate the applicable schema and its additional semantic invariants before data can influence native deterministic behavior.

| Contract | Versioned `$id` | Purpose |
|---|---|---|
| `frame-packet.schema.json` | `urn:reroom:schema:frame-packet:1` | Atomic captured frame and transport metadata. |
| `rrcap-manifest.schema.json` | `urn:reroom:schema:rrcap-manifest:1` | Record-first capture inventory and replay ordering. |
| `scene-state.schema.json` | `urn:reroom:schema:scene-state:1` | Stable semantic scene identity and readiness. |
| `edit-artifacts.schema.json` | `urn:reroom:schema:edit-artifacts:1` | Typed geometry, reveal, asset, and correction artifacts. |
| `transaction.schema.json` | `urn:reroom:schema:transaction:1` | Validate/preview/commit/restore and reconciliation. |
| `semantic-proposal.schema.json` | `urn:reroom:schema:semantic-proposal:1` | Optional model-produced, gateway-bound semantic/design proposal (`CON-006`); never mutation authority. |

## Contract invariants

- The checked-in `1.0.0` schemas are closed and exact: a 1.0 reader rejects every unknown property and every version other than `1.0.0`, including a future `1.1.0`. Minor-version forward compatibility is never inferred from SemVer.
- RR-COORD-1 and RR-FLOAT-1 from the canonical glossary apply everywhere: meters, right-handed ARKit world, column-vector math, row-major serialization, physically upright images, top-left pixel origin, half-pixel centers, encoded-pixel intrinsics, and exact cross-language numeric/rigid-transform tolerances.
- `world_frame_id` plus `world_frame_version` names a coordinate epoch. Corrections are explicit artifacts.
- Runtime identity uses stable prefixed UUIDs, never renderer indices.
- Capture uses exactly `selected → image_and_metadata_durable → journaled → network_eligible → server_acknowledged`; CON-002 event names prefix those states with `frame_`.
- RRFP-WIRE-1 is the only live FramePacket envelope: a 24-byte big-endian fixed header followed by bounded JCS header bytes and exact image bytes, with duplicate length/sequence and payload SHA checks defined in CON-001.
- The CON-002 global journal is the sole replay order. Its sequence is unique and contiguous from zero; accepted frames and events are exact projections of it, including reference ID, durable journal sequence, packet/event-record digest, and contiguous per-type sequence. Event `record_sha256` hashes the complete event with only itself omitted. `last_durable_journal_sequence` equals the final journal sequence, and replay input digest is recomputed from the exact journal tuple array. Array order, wall-clock time, and per-type counters never break ties.
- RR-JCS-SHA256-1 means RFC 8785 JSON Canonicalization Scheme, UTF-8 encoding, then SHA-256. Raw-file inventory hashes are SHA-256 over exact file bytes. Digest scopes in the schemas are closed and normative.
- One revision branch has one authority. Mode A uses the native device; a distinct B0 replay branch may use the gateway. Preview does not mutate `scene_revision`; a successful compare-and-swap commit by that branch authority increments it exactly once.
- A commit requires a preview-bound explicit user confirmation record. Models and services cannot be confirmation actors. The four product operations reduce to the exact ordered CON-005/Master Spec delta lists and every committed inverse is one inline, content-addressed RR-EDIT-PROJECTION-1 restoration.
- Restore/undo is a compensating transaction. Canonical transaction state and local `sync_state` are separate.
- RR-EDIT-PROJECTION-1 contains only edit-managed object visibility/reveal state, placed assets with full typed manifest references, and asset-subject support relations plus scene/branch/world identity. RR-RESTORE-REBASE-1 applies a persisted inverse only to its verified touched stable IDs atop the current complete projection, preserving newly tracked/unaffected objects. Restore then emits a fresh monotonic SceneState envelope and appends history; it never rewinds `scene_revision`, tracking evidence, or the whole-document digest.
- Artifact records bind immutable origin branch, activation branch, producing authority, scene/world epoch, and RR-JCS content scope. Two branches at the same numeric revision never alias.
- CON-006 is a closed nonmutating envelope. The gateway binds the exact trusted request-context snapshot, model identity, and one allowlisted catalog intent. It cannot carry transforms, URLs, confirmation, authorization, commit state, idempotency keys, artifact activation, or revision changes. Native code rejects stale context and re-enters CON-005 only through the existing deterministic intent, preview, and explicit-confirmation boundary. `vision` is CON-006 ingress metadata; it maps to CON-005 `typed` plus model provenance because frozen CON-005 is unchanged.
- CON-006 `1.0.0` is a new sideband contract, not a migration of CON-001 through CON-005. Those five frozen schemas and their compatibility behavior remain byte-for-byte and semantically unchanged. Its immutable accept/reject vectors live at `fixtures/semantic-proposals/1.0.0/rev-001/cases.json` and bind the exact schema digest.
- CON-004 has no implicit spatial decoding: mesh vertices are meter-valued RR-COORD-1 world coordinates; a sparse NPY voxel mask declares its world transform, XYZ voxel size/dimensions, ZYX/C layout, `uint8` occupancy values, and center rule; each P0 reveal layer declares a closed convex planar polygon whose vertices pair surface XY meters with normalized top-left texture UVs. Generic mesh-atlas reveal mapping requires a future contract version.
- CON-002 ordinary-video import is a distinct uncalibrated variant with no ARKit/world fields or fabricated geometry.
- Archive-relative paths use forward slashes and cannot be absolute, drive/UNC based, contain backslashes, `.`/`..` segments, resolve outside their root, or traverse a symlink outside it.
- The closed codec registry is `json_jcs_1`, `jsonl_utf8_1`, `jpeg`, `png`, `hevc_intra`, `hevc_video`, `h264_video`, `glb2`, `usdz`, `ply_binary_little_endian_1_0`, `npy_1_0`, and `ktx2_2_0`. Each contract exposes only its applicable subset; opaque or undocumented codecs are invalid.

Schemas use JSON Schema Draft 2020-12. Relative cross-contract references are descriptive until an implementation chooses a resolver; fields carrying external IDs use the registry in `docs/canonical/GLOSSARY_AND_ID_REGISTRY.md`.

## Executable evolution policy

- A compatible additive publication creates a new schema file/fixture set, changes the document version constant to (for example) `1.1.0`, and changes `$id` to an exact minor identifier such as `urn:reroom:schema:transaction:1.1`; it does not loosen or edit the frozen 1.0 schema in place.
- A 1.1 consumer may accept 1.0 only through a named, tested `1.0 → 1.1` migration. A producer may down-convert `1.1 → 1.0` only when every added value is provably optional/representable; otherwise it reports `unsupported_contract_version`. There is no best-effort field dropping.
- A breaking change uses a new major `$id`, a new versioned schema, and an explicit migration or quarantine path. Unknown major, coordinate convention, codec, digest algorithm/scope, or tagged variant rejects before mutation.
- Compatibility fixtures have fixed verdicts: exact 1.0 valid = accept; 1.0 plus unknown property = reject; version `1.1.0` presented to a 1.0 reader = reject; migrated 1.0 presented to a declared 1.1 reader = accept only after the named migration; unrepresentable down-conversion = reject; unknown major/codec/convention/digest = reject or read-only quarantine with zero mutation.
