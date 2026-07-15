# Synthesized Requirements

The PRD already owns stable requirement IDs, so no derived `REQ-*` aliases are introduced. All entries have the same source and precedence; acceptance text is condensed without changing thresholds or gate semantics.

## FR-CAPTURE-001 — Atomic record-first capture

- source: docs/canonical/PRD.md
- priority: P0
- scope: Mode A frame capture, durability, transport eligibility, deterministic replay
- description: Bind each selected upright image to RR-COORD-1 metadata and advance it through the exact five-state record-first lifecycle before network eligibility.
- acceptance criteria: RRFP-WIRE-1 and exact image SHA validate; crash injection leaves no frame or one hash-valid journaled frame; the global journal is contiguous; event and projection digests verify; two replays match; no upload references a non-journaled frame.

## FR-TARGET-001 — Explicit target and capability readiness

- source: docs/canonical/PRD.md
- priority: P0
- scope: target grounding, ambiguity handling, per-operation readiness
- description: Ground one chair/table target by reticle, tap, or utterance-time context and expose independent readiness for all five capabilities (`select` plus the four product operations).
- acceptance criteria: Ambiguous selection never silently commits; tracking loss updates readiness within one UI update; replace and remove may differ; re-seed restores selection or reports a clear failure.

## FR-PLACE-001 — Place

- source: docs/canonical/PRD.md
- priority: P0
- scope: curated asset placement, support/collision proxy validation, preview and commit
- description: Place one validated curated asset on an estimated support surface and preview it before commit.
- acceptance criteria: The hero fixture yields a stable preview, deterministic support/collision proxy checks, one explicit-confirmation revision increment, interruption survival, and replay persistence; missing support rejects commit.

## FR-REPLACE-001 — Replace

- source: docs/canonical/PRD.md
- priority: P0
- scope: selected target replacement, conservative cover, support alignment, retry safety
- description: Replace the selected hero target with a curated asset while masking the original only within supported observations.
- acceptance criteria: A ready target produces stable identity, conservative mask/occlusion, support alignment, no duplicate retry revision, and 5/5 successful golden-path runs; unsupported views coach or restore instead of exposing invalid content.

## FR-REMOVE-001 — Empty removal

- source: docs/canonical/PRD.md
- priority: P0
- scope: multi-surface reveal, foreground occlusion, supported view envelope, controlled release gate
- description: Remove the controlled target only when reveal and foreground-occlusion evidence is ready for the current view envelope.
- acceptance criteria: GATE-006 requires coverage P10 at least 0.95, median at least 0.98, largest uncovered component at most 1%, correct multi-surface order, no severe foreground overwrite, and at least 4/5 of exactly five visual votes. Failure blocks release unless a human explicitly changes the locked scope.

## FR-RESTORE-001 — Restore/undo

- source: docs/canonical/PRD.md
- priority: P0
- scope: compensating transaction, local inverse, offline restore, immutable history
- description: Restore the latest eligible committed edit with a new compensating transaction on the native-authoritative branch, including offline.
- acceptance criteria: Restore verifies the persisted captured-exact RR-EDIT-PROJECTION-1 inverse, derives current-complete output through RR-RESTORE-REBASE-1, increments once, preserves new/unaffected state and live evidence, keeps original history immutable, renders offline, and reconciles without duplicate mutation or whole-document rewind.

## FR-TRANSACTION-001 — Deterministic edit authority

- source: docs/canonical/PRD.md
- priority: P0
- scope: validate/preview/commit, branch authority, idempotency, durability, reconciliation
- description: Every edit uses one declared branch authority, CAS revision control, RR-JCS request fingerprinting, exactly-once idempotency, local durability, inverse operations, and explicit reconciliation.
- acceptance criteria: Preview changes no revision; explicit confirmation and exact operation-specific reducer/check order are required; canonical edit state and support relations materialize atomically; commit changes `r` to `r+1`; same key/fingerprint returns the prior result, changed content conflicts; stale/wrong authority rejects; offline replication is idempotent; divergence is quarantined without automatic merge.

## FR-AGENT-001 — Typed/tap semantic intent

- source: docs/canonical/PRD.md
- priority: P0
- scope: nonmodel operation proposals, allowlisted design attributes, deterministic validation
- description: Typed/tap controls propose any of the four operations without model or network and cannot themselves authorize or mutate canonical state.
- acceptance criteria: All golden edits complete with network and learned providers disabled; malformed, stale, oversized, or injected arguments cannot change target/session, supply transforms, authorize, confirm, or commit.

## FR-B0-001 — Guaranteed `.rrcap` replay

- source: docs/canonical/PRD.md
- priority: P0
- scope: finalized/recovered capture replay, exact ordering, provider-independent fallback
- description: Replay accepted FramePackets and events from finalized or recovered-prefix `.rrcap` input without a learned reconstruction provider or live network.
- acceptance criteria: Two runs match global-journal digests, exact frame/event projections, and the expected revision trace; all hashes validate; corrupt suffix recovery stops at the valid prefix; neural comparison is allowed only under a pinned tolerance policy.

## FR-WEB-001 — Separate web replay and fallback

- source: docs/canonical/PRD.md
- priority: P0
- scope: Next.js B0 client, upload/replay, inspection, sharing, typed proposals, degradation
- description: Provide a separate web client for sessions, timeline inspection, `.rrcap`/ordinary-video replay, sharing, typed proposals, and degraded visualization without claiming Mode A parity.
- acceptance criteria: Supported browsers open and verify the golden capture, scrub events, inspect canonical state, and render available sparse/artifact data; camera, codec, quota, and network failures degrade without acknowledged-commit loss. Ordinary video never fabricates ARKit calibration, scale, pose, or planes.

## NFR-COORD-001 — Coordinate correctness

- source: docs/canonical/PRD.md
- priority: P0
- scope: RR-COORD-1, RR-FLOAT-1, projection, orientation, world epochs
- description: Every producer and consumer implements RR-COORD-1 and explicit world-frame versioning exactly.
- acceptance criteria: Cross-language projection fixtures stay within one encoded pixel; duplicated transport/body fields agree; transform and intrinsics comparisons satisfy RR-FLOAT-1; device checks show no crop/orientation swap; reset creates a new epoch and correction rather than silent reinterpretation.

## NFR-REPLAY-001 — Bounded deterministic processing

- source: docs/canonical/PRD.md
- priority: P0
- scope: queue bounds, stale work, durable order, replay independence
- description: Live processing remains bounded and favors newest useful work while accepted durable order stays replay-authoritative.
- acceptance criteria: Stress never exceeds configured capacity; stale drops are measured; durable sequences remain monotonic; replay reproduces accepted order independently of live completion order.

## NFR-RENDER-001 — Local render independence

- source: docs/canonical/PRD.md
- priority: P0
- scope: 60 Hz native loop, local rendering, physical-device budget
- description: The native camera/render loop never waits synchronously for network, worker, web client, or LLM, and high-rate buffers never cross a scripting bridge.
- acceptance criteria: Fault injection creates no render-thread wait. The four-minute base-device gate targets median at least 45 FPS and p95 frame time at most 33 ms with no crash or thermal shutdown; these remain TARGET until measured.

## NFR-LATENCY-001 — Measured latency distributions

- source: docs/canonical/PRD.md
- priority: P0
- scope: monotonic spans, per-stage distributions, provider/tier evidence
- description: Record device-to-preview and stage latency distributions without unsupported real-time claims.
- acceptance criteria: Reports include p50/p95/max for capture, durability, queues, upload, inference, artifact acceptance, preview, commit, and mask age. Target mask age p95 is at most 250 ms on an advertised tier or the capability degrades.

## NFR-RESILIENCE-001 — Tracking/network/offline resilience

- source: docs/canonical/PRD.md
- priority: P0
- scope: local camera, commits, restore, capture integrity, reconnect
- description: Tracking loss, network loss, reconnect, and worker failure preserve local operation, acknowledged edits, restore, and record integrity.
- acceptance criteria: The fault matrix has zero lost acknowledged commits, no cross-session state, no duplicate mutation, a valid recovered capture prefix, and explicit degraded/recovery UI.

## NFR-CONTRACT-001 — Versioned interoperability

- source: docs/canonical/PRD.md
- priority: P0
- scope: CON-001 through CON-005, closed codecs, RRFP, RR-FLOAT, RR-JCS, migrations
- description: All capture, scene, artifact, and transaction boundaries use exact versioned schemas and named compatibility migrations.
- acceptance criteria: Golden cross-language schema/digest/wire vectors pass; schema IDs are unique; 1.0 readers reject unknown fields and unknown versions without a named migration; malformed framing, path, digest, branch, or identity input rejects before mutation.

## SEC-CONSENT-001 — Capture consent and minimization

- source: docs/canonical/PRD.md
- priority: P0
- scope: consent, visible recording/upload/share state, selected-frame minimization
- description: Room imagery capture, upload, and sharing require explicit consent and visible state while minimizing selected frames.
- acceptance criteria: No capture occurs before consent; recording/upload/share states are visible; the manifest records consent and retention; denial leaves only non-capture explanation available.

## SEC-CREDENTIAL-001 — Secret isolation

- source: docs/canonical/PRD.md
- priority: P0
- scope: provider credentials, client secrets, logs, source and captures
- description: Standard provider/storage credentials never enter source, logs, captures, browser bundles, or the phone; clients receive scoped short-lived credentials only when supported.
- acceptance criteria: Secret scan passes; Realtime uses a server-created scoped ephemeral secret/session; authorization headers are redacted; invalid or expired credentials fail closed.

## SEC-RETENTION-001 — Retention, deletion, and sharing

- source: docs/canonical/PRD.md
- priority: P0
- scope: captures, derived data, transactions, share links, TTL and deletion
- description: Source and derived scene data have explicit retention scope, deletion behavior, and share access state.
- acceptance criteria: Local-only is the default; server sessions have a documented TTL; deletion invalidates shares and queues source/derived deletion; the manifest records state; audit logs contain stable IDs rather than room imagery.

## SEC-AGENT-001 — Prompt/tool injection containment

- source: docs/canonical/PRD.md
- priority: P0
- scope: untrusted external/model data, allowlisted tools, deterministic authorization
- description: External text, metadata, crawled content, and model output are untrusted; only typed allowlisted tools may propose actions and deterministic code authorizes transitions.
- acceptance criteria: The injection corpus cannot expand the tool set, change target/session, bypass confirmation/revision/license checks, reveal secrets, deploy, delete, or mutate; invalid arguments reject with non-sensitive logs.

## OPS-DEVICE-001 — Device/build readiness

- source: docs/canonical/PRD.md
- priority: P0
- scope: base iPhone 17, Xcode/signing, physical install, ARKit without LiDAR
- description: Validate the physical device and toolchain before architecture-sensitive mobile work.
- acceptance criteria: A signed minimal build installs and launches; camera permission, ARKit tracking, and planes work without LiDAR semantics; a repeatable build record is retained. Simulator-only evidence is insufficient.

## OPS-LICENSE-001 — Shipping license evidence

- source: docs/canonical/PRD.md
- priority: P0
- scope: models, weights, assets, fonts, libraries, exact provenance and terms
- description: Every shipped artifact has an exact version/digest, source, applicable terms, attribution, and explicit use/redistribution decision.
- acceptance criteria: The shipping bill of materials contains no unknown or noncommercial dependency and retains separate code/weight/asset evidence; missing evidence removes the component or activates a permitted fallback.

## OPS-GOLDEN-001 — Repeatable hero acceptance

- source: docs/canonical/PRD.md
- priority: P0
- scope: end-to-end hero journey, B0 replay, repeated evidence
- description: Run the complete place/replace/remove/restore journey plus B0 replay five consecutive times on the declared device/tier.
- acceptance criteria: 5/5 runs complete without crash, lost commit, duplicate revision, wrong target, severe visual artifact, or replay mismatch; removal separately passes GATE-006 and evidence is retained.

## OPS-SUBMISSION-001 — Build Week evidence package

- source: docs/canonical/PRD.md
- priority: P0
- scope: project description, repository, demo video, Codex evidence, honest claims
- description: Assemble the required submission evidence and tie product claims to recorded proof.
- acceptance criteria: The official rules checklist is signed before the deadline; the public demo with audio remains under the official limit, shows the four operations and B0 honestly, includes a representative Codex Session ID, and contains no unsupported performance/novelty claim.

## STR-VOICE-001 — Optional Realtime/GPT semantic ingress

- source: docs/canonical/PRD.md
- priority: P1, nonblocking stretch
- scope: optional voice proposals through the same typed boundary
- description: Realtime voice and GPT may translate utterances into the same nonmutating proposal contract used by typed/tap input.
- acceptance criteria: At least 4/5 fixed hero utterances yield the expected proposal, every ambiguity/injection case rejects or clarifies, and disabling the model/network leaves the full typed journey available. Failure ends voice work without changing P0.

## STR-B1-001 — Isolated offline refinement

- source: docs/canonical/PRD.md
- priority: stretch, explicitly outside P0
- scope: post-P0 render-skin refinement, identity preservation, resource isolation
- description: Only after all P0 gates are green and a human approves, an offline provider may create a higher-fidelity render skin without changing canonical IDs, transforms, edits, or history.
- acceptance criteria: No B1 dependency, worker, package, or task is scheduled while a P0 gate is red; every result maps to stable scene/artifact IDs and remains discardable without canonical-state change.
