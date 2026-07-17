# Phase 2: Atomic Capture and Exact Replay - Context

**Gathered:** 2026-07-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver the consented capture/replay foundation required by `FR-CAPTURE-001`, `FR-B0-001`, `NFR-REPLAY-001`, and `SEC-CONSENT-001`. Selected FramePackets become crash-safe, journal-authoritative `.rrcap` inputs before upload or provider use; finalized and recovered-prefix archives replay deterministically without a learned provider or live network; bounded live work cannot change durable replay order. Phase 2 includes only the minimal capture and replay inspection surfaces needed to prove those behaviors. The full Next.js Mode B0 sessions, sharing, ordinary-video import, typed proposals, and polished fallback experience remain Phase 7 work.

</domain>

<decisions>
## Implementation Decisions

### Consent and session start
- Begin through an explicit **Start room capture** action from the ready camera, followed by the capture disclosure; do not surprise the user with capture consent on app entry.
- Confirm consent for every newly created capture session and never silently carry consent into a different session ID.
- Default the primary P0 flow to `local_only_until_share`; keep TTL and extended-retention controls out of the foreground capture flow.
- Keep a persistent **Recording locally** indicator during capture and display upload/offline as a separate state so local durability is never mistaken for upload completion.

### Frame selection and pressure behavior
- Use deterministic selection: always retain explicit user-event frames; otherwise select using measured cadence plus view-change and quality signals. A model never controls selection eligibility.
- Preserve every selected durable packet. Only transmission and optional-compute queues may replace stale work with the newest useful item.
- Under pressure, drop optional compute first, pause upload second, then reduce capture cadence or quality using thresholds measured under `GATE-001`.
- Show a non-blocking **Capture continues locally — upload paused** warning. If storage can no longer accept atomic writes, stop cleanly and finalize the valid durable prefix.

### Finalization and crash recovery
- Explicit stop finalizes the session. Backgrounding or an unrecoverable interruption also attempts immediate finalization from the current durable prefix.
- On next launch, automatically discover and verify interrupted sessions, but never silently resume recording into the same archive.
- Discard or quarantine an incomplete tail and expose only the verified contiguous prefix as replayable.
- Label the result **Recovered — capture may be incomplete**, show an integrity summary, and offer **Inspect replay** or **Start new capture**. Recovery never rewrites immutable history to make an interrupted session appear complete.

### Exact replay boundary and inspection
- Build a provider-independent replay core plus a minimal fixture/developer inspector. Do not pull Phase 7 sessions, sharing, ordinary-video import, or polished web UX into this phase.
- The inspector shows the archive verdict, finalized/recovered status, digest summary, and authoritative frame/event timeline in global-journal order.
- Scrubbing exposes only hash-verified accepted records. Unknown versions, invalid hashes, and non-prefix corruption fail closed with a precise diagnostic.
- Every replay emits a canonical machine-comparable report, and two runs over the same input must be byte-identical. Learned outputs remain excluded unless a separately pinned tolerance policy is active.

### the agent's Discretion
- Choose internal module names, replay-core packaging, minimal inspector presentation, and fault-injection harness structure within the canonical native/web boundary.
- Treat queue capacities, cadence, quality cutoffs, storage warnings, and pressure thresholds as `HYPOTHESIS` or `TARGET` values until `GATE-001` records reproducible measurements; do not present them as measured facts.
- Choose the recoverable quarantine representation and diagnostic wording details as long as valid-prefix replay, immutable history, clear status, and fail-closed behavior remain exact.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- The Phase 1 native seed already contains `CaptureAttemptMachine`, `FramePacketBuilder`, `DiagnosticJournal`, `ARFrameCaptureAdapter`, canonical JSON/digest validation, stable-ID checks, a filesystem abstraction, crash injection, and memory-backed durability tests.
- `DiagnosticJournal` already enforces session-bound consent before writes, atomically publishes image and packet bytes, appends a sole global journal, validates recovered manifests, and distinguishes internally durable from network-eligible frames.
- The frozen CON-001/CON-002 schemas, cross-runtime validators, RRFP-WIRE-1 framing, canonical fixture publisher, and exact Node/Swift/Python toolchain evidence from Phase 1 are reusable replay inputs and oracles.
- `DiagnosticChecklistView` provides an internal-only SwiftUI surface that can host the minimal capture/recovery proof without defining the later shipping UX.

### Established Patterns
- Closed versioned contracts reject unknown fields and versions; RR-JCS-SHA256 digests and stable prefixed IDs carry authority across runtimes.
- Behavior-bearing Swift logic is deterministic and covered with Swift Testing, in-memory fault injection, golden vectors, and byte comparisons before physical evidence is claimed.
- Durable publication is generation/rename based, raw room evidence stays out of Git, and reports distinguish `TARGET`, `HYPOTHESIS`, and `MEASURED` evidence.
- The current journal seed covers `selected` through `network_eligible`; Phase 2 must complete and verify the canonical five-state lifecycle, including `server_acknowledged`, without allowing network state to become durability authority.

### Integration Points
- Native capture extends the Phase 1 device-proof seed rather than creating a speculative mobile stack.
- `.rrcap` manifest and global-journal processing connect the native writer to a provider-independent replay core and canonical replay report that the separate Phase 7 Next.js client can consume later.
- Queue and upload adapters sit after journal eligibility; neither may block ARKit capture/render work or reorder durable accepted records.
- Planning and implementation must re-read `docs/canonical/README.md`, ADR-004, CON-001/CON-002, Master Spec capture/replay sections, the Phase 2 PRD requirements, `GATE-001`, and the corresponding test-plan fixtures before changing lifecycle or archive meaning.

</code_context>

<specifics>
## Specific Ideas

- Keep local durability, upload, recovery, and archive-integrity states visibly distinct; preferred labels include **Recording locally**, **Capture continues locally — upload paused**, and **Recovered — capture may be incomplete**.
- The minimal replay inspector is evidence-oriented: verdict and integrity first, then the authoritative timeline. It is not an early imitation of the Phase 7 web product.

</specifics>

<deferred>
## Deferred Ideas

- Full Next.js Mode B0 sessions, sharing controls, ordinary-video replay/import, typed proposals, and polished degraded visualization remain Phase 7.
- Learned reconstruction and neural-output comparison remain unavailable unless a later phase activates a separately pinned provider and tolerance policy under its own gate.

</deferred>

---

*Phase: 02-atomic-capture-and-exact-replay*
*Context gathered: 2026-07-17*
