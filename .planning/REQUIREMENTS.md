# Requirements: ReRoom

**Defined:** 2026-07-15

**Core Value:** Trustworthy camera-grounded room editing where users can place, replace, remove, and restore one controlled freestanding chair or small table while deterministic application code retains spatial, persistence, transaction, and replay authority.

Canonical IDs are preserved exactly. Acceptance summaries retain the canonical thresholds and gate semantics; the PRD and versioned schemas remain the behavior and field authorities.

## v1 Requirements (P0)

### Capture and Edit Workflows

- [ ] **FR-CAPTURE-001 - Atomic record-first capture:** Bind each selected upright image to RR-COORD-1 metadata and advance it through the exact five-state lifecycle before network eligibility.
  - Acceptance: RRFP-WIRE-1 and exact image SHA validate; crash injection leaves no frame or one hash-valid journaled frame; the global journal is contiguous; event and projection digests verify; two replays match; no upload references a non-journaled frame.
- [ ] **FR-TARGET-001 - Explicit target and capability readiness:** Ground one chair/table target by reticle, tap, or utterance-time context and expose independent readiness for `select`, `place`, `replace`, `remove`, and `restore`.
  - Acceptance: Ambiguous selection never silently commits; tracking loss updates readiness within one UI update; replace and remove may differ; reseeding restores selection or reports a clear failure.
- [ ] **FR-PLACE-001 - Place:** Place one validated curated asset on an estimated support surface and preview it before commit.
  - Acceptance: The hero fixture yields a stable preview, deterministic support/collision proxy checks, one explicit-confirmation revision increment, interruption survival, and replay persistence; missing support rejects commit.
- [ ] **FR-REPLACE-001 - Replace:** Replace the selected hero target with a curated asset while masking the original only within supported observations.
  - Acceptance: A ready target produces stable identity, conservative mask/occlusion, support alignment, no duplicate retry revision, and 5/5 successful golden-path runs; unsupported views coach or restore instead of exposing invalid content.
- [ ] **FR-REMOVE-001 - Empty removal:** Remove the controlled target only when reveal and foreground-occlusion evidence is ready for the current supported view envelope.
  - Acceptance: `GATE-006` requires coverage p10 at least 0.95, median at least 0.98, largest uncovered component at most 1%, correct multi-surface order, no severe foreground overwrite, and at least 4/5 of exactly five visual votes. Failure blocks release unless a human explicitly changes the locked scope.
- [ ] **FR-RESTORE-001 - Restore/undo:** Restore the latest eligible committed edit with a new compensating transaction on the native-authoritative branch, including offline.
  - Acceptance: Restore verifies the persisted captured-exact RR-EDIT-PROJECTION-1 inverse, derives current-complete output through RR-RESTORE-REBASE-1, increments once, preserves new/unaffected state and live evidence, keeps original history immutable, renders offline, and reconciles without duplicate mutation or whole-document rewind.
- [ ] **FR-TRANSACTION-001 - Deterministic edit authority:** Every edit uses one declared branch authority, CAS revision control, RR-JCS request fingerprinting, exactly-once idempotency, local durability, inverse operations, and explicit reconciliation.
  - Acceptance: Preview changes no revision; explicit confirmation and the exact operation-specific reducer/check order are required; canonical edit state and support relations materialize atomically; commit changes `r` to `r+1`; same key/fingerprint returns the prior result while changed content conflicts; stale/wrong authority rejects; offline replication is idempotent; divergence is quarantined without automatic merge.
- [ ] **FR-AGENT-001 - Typed/tap semantic intent:** Typed/tap controls propose any of the four operations without model or network and cannot authorize or mutate canonical state.
  - Acceptance: All golden edits complete with network and learned providers disabled; malformed, stale, oversized, or injected arguments cannot change target/session, supply transforms, authorize, confirm, or commit.
- [ ] **FR-B0-001 - Guaranteed `.rrcap` replay:** Replay accepted FramePackets and events from finalized or recovered-prefix `.rrcap` input without a learned reconstruction provider or live network.
  - Acceptance: Two runs match global-journal digests, exact frame/event projections, and the expected revision trace; all hashes validate; corrupt-suffix recovery stops at the valid prefix; neural comparison is allowed only under a pinned tolerance policy.
- [ ] **FR-WEB-001 - Separate web replay and fallback:** Provide a separate Next.js client for sessions, timeline inspection, `.rrcap`/ordinary-video replay, sharing, typed proposals, and degraded visualization without claiming Mode A parity.
  - Acceptance: Supported browsers open and verify the golden capture, scrub events, inspect canonical state, and render available sparse/artifact data; camera, codec, quota, and network failures degrade without acknowledged-commit loss. Ordinary video never fabricates ARKit calibration, scale, pose, or planes.

### Correctness, Performance, and Resilience

- [x] **NFR-COORD-001 - Coordinate correctness:** Every producer and consumer implements RR-COORD-1 and explicit world-frame versioning exactly.
  - Acceptance: Cross-language projection fixtures stay within one encoded pixel; duplicated transport/body fields agree; transform and intrinsics comparisons satisfy RR-FLOAT-1; device checks show no crop/orientation swap; reset creates a new epoch and correction rather than silent reinterpretation.
- [ ] **NFR-REPLAY-001 - Bounded deterministic processing:** Live processing remains bounded and favors newest useful work while accepted durable order stays replay-authoritative.
  - Acceptance: Stress never exceeds configured capacity; stale drops are measured; durable sequences remain monotonic; replay reproduces accepted order independently of live completion order.
- [ ] **NFR-RENDER-001 - Local render independence:** The native camera/render loop never waits synchronously for network, worker, web client, or LLM, and high-rate buffers never cross a scripting bridge.
  - Acceptance: Fault injection creates no render-thread wait. The four-minute base-device gate targets median at least 45 FPS and p95 frame time at most 33 ms with no crash or thermal shutdown; these remain TARGET until measured.
- [ ] **NFR-LATENCY-001 - Measured latency distributions:** Record device-to-preview and per-stage latency distributions without unsupported real-time claims.
  - Acceptance: Reports include p50/p95/max for capture, durability, queues, upload, inference, artifact acceptance, preview, commit, and mask age. Target mask-age p95 is at most 250 ms on an advertised tier or the capability degrades.
- [ ] **NFR-RESILIENCE-001 - Tracking/network/offline resilience:** Tracking loss, network loss, reconnect, and worker failure preserve local operation, acknowledged edits, restore, and record integrity.
  - Acceptance: The fault matrix has zero lost acknowledged commits, no cross-session state, no duplicate mutation, a valid recovered capture prefix, and explicit degraded/recovery UI.
- [x] **NFR-CONTRACT-001 - Versioned interoperability:** All capture, scene, artifact, and transaction boundaries use exact versioned schemas and named compatibility migrations.
  - Acceptance: Golden cross-language schema/digest/wire vectors pass; schema IDs are unique; 1.0 readers reject unknown fields and unknown versions without a named migration; malformed framing, path, digest, branch, or identity input rejects before mutation.

### Security and Privacy

- [ ] **SEC-CONSENT-001 - Capture consent and minimization:** Room imagery capture, upload, and sharing require explicit consent and visible state while minimizing selected frames.
  - Acceptance: No capture occurs before consent; recording/upload/share states are visible; the manifest records consent and retention; denial leaves only non-capture explanation available.
- [ ] **SEC-CREDENTIAL-001 - Secret isolation:** Standard provider/storage credentials never enter source, logs, captures, browser bundles, or the phone; clients receive scoped short-lived credentials only when supported.
  - Acceptance: Secret scan passes; Realtime uses a server-created scoped ephemeral secret/session if that stretch path is enabled; authorization headers are redacted; invalid or expired credentials fail closed.
- [ ] **SEC-RETENTION-001 - Retention, deletion, and sharing:** Source and derived scene data have explicit retention scope, deletion behavior, and share access state.
  - Acceptance: Local-only is the default; server sessions have a documented TTL; deletion invalidates shares and queues source/derived deletion; the manifest records state; audit logs contain stable IDs rather than room imagery.
- [ ] **SEC-AGENT-001 - Prompt/tool injection containment:** External text, metadata, crawled content, and model output are untrusted; only typed allowlisted tools may propose actions and deterministic code authorizes transitions.
  - Acceptance: The injection corpus cannot expand the tool set, change target/session, bypass confirmation/revision/license checks, reveal secrets, deploy, delete, or mutate; invalid arguments reject with non-sensitive logs.

### Operational Readiness and Evidence

- [x] **OPS-DEVICE-001 - Device/build readiness:** Validate the physical device and toolchain before architecture-sensitive mobile work.
  - Acceptance: A signed minimal build installs and launches; camera permission, ARKit tracking, and planes work without LiDAR semantics; a repeatable build record is retained. Simulator-only evidence is insufficient.
- [ ] **OPS-LICENSE-001 - Shipping license evidence:** Every shipped artifact has an exact version/digest, source, applicable terms, attribution, and explicit use/redistribution decision.
  - Acceptance: The shipping bill of materials contains no unknown or noncommercial dependency and retains separate code/weight/asset evidence; missing evidence removes the component or activates a permitted fallback.
- [ ] **OPS-GOLDEN-001 - Repeatable hero acceptance:** Run the complete place/replace/remove/restore journey plus B0 replay five consecutive times on the declared device/tier.
  - Acceptance: 5/5 runs complete without crash, lost commit, duplicate revision, wrong target, severe visual artifact, or replay mismatch; removal separately passes `GATE-006` and evidence is retained.
- [ ] **OPS-SUBMISSION-001 - Build Week evidence package:** Assemble the required submission evidence and tie product claims to recorded proof.
  - Acceptance: The official rules checklist is signed before the deadline; the public demo with audio remains under the official limit, shows the four operations and B0 honestly, includes a representative Codex Session ID, and contains no unsupported performance or novelty claim.

## Future / Stretch Requirements

These IDs are preserved but are not P0, do not map to P0 phases, and cannot block P0.

- **STR-VOICE-001 - Optional Realtime/GPT semantic ingress:** Realtime voice and GPT may translate utterances into the same nonmutating proposal contract used by typed/tap input.
  - Acceptance: At least 4/5 fixed hero utterances yield the expected proposal; every ambiguity/injection case rejects or clarifies; disabling model/network leaves the full typed journey available. Failure ends voice work without changing P0.
- **STR-B1-001 - Isolated offline refinement:** Only after all P0 gates are green and a human approves, an offline provider may create a higher-fidelity render skin without changing canonical IDs, transforms, edits, or history.
  - Acceptance: No B1 dependency, worker, package, or task is scheduled while a P0 gate is red; every result maps to stable scene/artifact IDs and remains discardable without canonical-state change.

## Out of Scope

| Feature | Reason |
|---------|--------|
| XR glasses | Human-locked future work, not P0. |
| General furniture and unconstrained rooms | P0 is one controlled freestanding chair or small table with visible floor. |
| Rear-LiDAR-only base-device behavior | The base iPhone 17 path cannot require rear LiDAR. |
| Unbounded or undisclosed background synthesis | Removal is spatial, provenance-explicit, and limited to a measured supported-view envelope. |
| Model-authorized edits | Models may propose semantic/design intent only; deterministic code authorizes every mutation. |
| Mode A parity claims for B0 | B0 is a guaranteed replay/inspection/fallback surface with honest degradation. |

## Traceability

Each P0 requirement maps to exactly one phase. Future/stretch requirements intentionally have no P0 phase.

| Requirement | Phase | Status |
|-------------|-------|--------|
| NFR-COORD-001 | Phase 1 | Complete |
| NFR-CONTRACT-001 | Phase 1 | Complete |
| OPS-DEVICE-001 | Phase 1 | Complete |
| FR-CAPTURE-001 | Phase 2 | Pending |
| FR-B0-001 | Phase 2 | Pending |
| NFR-REPLAY-001 | Phase 2 | Pending |
| SEC-CONSENT-001 | Phase 2 | Pending |
| FR-PLACE-001 | Phase 3 | Pending |
| FR-RESTORE-001 | Phase 3 | Pending |
| FR-TRANSACTION-001 | Phase 3 | Pending |
| FR-AGENT-001 | Phase 3 | Pending |
| FR-TARGET-001 | Phase 4 | Pending |
| NFR-RENDER-001 | Phase 4 | Pending |
| FR-REPLACE-001 | Phase 5 | Pending |
| FR-REMOVE-001 | Phase 6 | Pending |
| FR-WEB-001 | Phase 7 | Pending |
| SEC-RETENTION-001 | Phase 7 | Pending |
| NFR-LATENCY-001 | Phase 8 | Pending |
| NFR-RESILIENCE-001 | Phase 8 | Pending |
| SEC-CREDENTIAL-001 | Phase 8 | Pending |
| SEC-AGENT-001 | Phase 8 | Pending |
| OPS-LICENSE-001 | Phase 8 | Pending |
| OPS-GOLDEN-001 | Phase 8 | Pending |
| OPS-SUBMISSION-001 | Phase 8 | Pending |

**Coverage:**

- P0 requirements: 24 total
- Mapped to exactly one phase: 24
- Unmapped P0 requirements: 0
- Duplicate P0 mappings: 0
- Future/stretch requirements: 2, intentionally outside P0 phase mapping

---
*Requirements defined: 2026-07-15*

*Last updated: 2026-07-15 for the portable GSD 1.7 handoff.*
