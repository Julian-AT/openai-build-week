# Phase 2: Atomic Capture and Exact Replay - Research

**Researched:** 2026-07-17
**Domain:** Native Swift record-first capture, crash-safe `.rrcap` durability, bounded transport, and exact offline replay
**Confidence:** HIGH for project semantics and existing code; MEDIUM for platform lifecycle/storage API guidance

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

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

### Deferred Ideas (OUT OF SCOPE)
- Full Next.js Mode B0 sessions, sharing controls, ordinary-video replay/import, typed proposals, and polished degraded visualization remain Phase 7.
- Learned reconstruction and neural-output comparison remain unavailable unless a later phase activates a separately pinned provider and tolerance policy under its own gate.
</user_constraints>

## Summary

Phase 2 should deepen the Phase 1 diagnostic seed into one deterministic capture/replay core instead of replacing it. The existing code already proves upright `ARFrame` snapshots, closed CON-001 validation, generation/rename publication, a contiguous JSONL journal, consent-bound writes, event and packet digests, recovered-prefix truncation, and in-memory/real-filesystem fault tests. It does not yet provide a whole capture session: `server_acknowledged` is absent, finalization always synthesizes `recovered_prefix`, the manifest is returned rather than durably published, there is no bounded send queue or replay report, and mutable archive state is a synchronous app-target class. [VERIFIED: `FramePacketBuilder.swift`, `DiagnosticJournal.swift`, `CaptureAttemptTests.swift`]

The safest planning boundary is a new `ReRoomCaptureCore` product/target inside the existing `ios/Packages/ReRoomContracts` package, depending on `ReRoomContracts` but adding no package. Keep `ARFrame`, image encoding, UIKit background assertions, and SwiftUI presentation in the app target. Move archive state, synchronous filesystem transactions, prefix recovery, deterministic replay/reporting, and bounded queue logic into Sendable value types plus one storage actor. This makes the exact replay core runnable on iOS and macOS test hosts while leaving the later Next.js product boundary intact. [VERIFIED: `AGENTS.md`; `02-CONTEXT.md`; existing `Package.swift`; Swift Concurrency project skill]

The planner should build this as contract-first vertical slices: freeze synthetic `.rrcap` fixtures and a closed evidence-report schema; establish session start/finalization and the complete five-state lifecycle; add recovered-prefix replay and byte-identical Swift/TypeScript/Python reports; place bounded transmission/optional-work queues strictly after durability; then connect the internal SwiftUI inspector and run GATE-001 automation before requesting fresh physical evidence. [VERIFIED: `AGENTS.md`; ADR-004; `TEST_AND_EVALUATION_PLAN.md` TST-CAPTURE-001/TST-REPLAY-001/TST-QUEUE-001; `RISK_AND_KILL_GATES.md` GATE-001]

**Primary recommendation:** Make the journal-writing capture actor the sole archive mutation authority, make replay a pure read/verify/report pipeline over finalized or recovered-prefix bytes, and let every network/optional queue consume immutable journal-eligible receipts only. [VERIFIED: ADR-004; CON-001/CON-002; Master Spec §5]

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| `FR-CAPTURE-001` | Bind each selected upright image to RR-COORD-1 metadata and advance it through the exact five-state lifecycle before network eligibility. | Extend the existing builder/journal into session-scoped writer APIs, add `server_acknowledged`, durable finalized manifests, and operation-level crash injection. [VERIFIED: REQUIREMENTS.md; code inspection] |
| `FR-B0-001` | Replay accepted FramePackets and events from finalized or recovered-prefix `.rrcap` input without a learned reconstruction provider or live network. | Add a pure replay verifier that derives both projections only from the journal and emits a closed JCS report; no provider/network imports in the core. [VERIFIED: REQUIREMENTS.md; CON-002; ADR-004] |
| `NFR-REPLAY-001` | Keep live work bounded and newest-useful while durable accepted order remains replay-authoritative. | Add bounded transmission/optional queues after journal eligibility, with deterministic admission/drop metrics and completion-order independence tests. [VERIFIED: REQUIREMENTS.md; TST-QUEUE-001] |
| `SEC-CONSENT-001` | Require explicit consent and visible recording/upload/share state while minimizing selected frames. | Model consent as session-bound authorization before any capture directory/event/manifest write; derive UI state separately from archive/network state. [VERIFIED: REQUIREMENTS.md; CON-002 privacy; accepted context] |
</phase_requirements>

## Project Constraints (from AGENTS.md)

- Read canonical authority before changing meaning; precedence is human locks, Accepted ADRs, gated Provisional ADRs, Master Spec/contracts, PRD, then supporting documents. Stop on conflicts rather than silently choosing. [VERIFIED: `AGENTS.md`]
- Preserve requirement, contract, ADR, gate, test, claim, and glossary IDs. JSON Schemas own fields/lifecycle and the glossary owns terms/ID families. [VERIFIED: `AGENTS.md`]
- Extend the native SwiftUI/ARKit Mode A path; do not require rear LiDAR, introduce a web owner for capture, or make network/model/worker work block the 60 Hz path. [VERIFIED: `AGENTS.md`]
- Implement RR-COORD-1, RR-FLOAT-1, RR-JCS-SHA256-1, atomic FramePacket durability, and journal-authoritative replay exactly. [VERIFIED: `AGENTS.md`]
- Validate untrusted input at every boundary and fail closed without corrupting durable state. Keep queues bounded with explicit cancellation/backpressure. [VERIFIED: `AGENTS.md`]
- Use TDD for behavior-bearing logic and regression tests for fixed bugs; maintain cross-runtime golden vectors for capture ordering and replay. [VERIFIED: `AGENTS.md`]
- Treat thresholds as `TARGET`/`HYPOTHESIS` until reproducible evidence records fixture, implementation revision, environment, raw evidence, calculation, and evaluator. [VERIFIED: `AGENTS.md`]
- Add no dependency without a concrete phase need, exact compatible version, license/artifact/current-doc evidence, and tested fallback. [VERIFIED: `AGENTS.md`]
- Never commit credentials, raw room data, private traces, signing material, user identifiers, or machine-local `.codex` state. Keep `.planning/` committed. [VERIFIED: `AGENTS.md`]
- Preserve unrelated worktree changes, use `rg` and `apply_patch`, run relevant contract/GSD/secret/diff checks, and leave new physical/human gates pending until real evidence exists. [VERIFIED: `AGENTS.md`]

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Explicit session start, disclosure, visible local/upload/recovery state | Native SwiftUI (`@MainActor`) | Capture core snapshots | Presentation is UI-derived and noncanonical; it must observe, not own, durability authority. [VERIFIED: Glossary session presentation state; accepted context] |
| ARFrame selection and upright image snapshot | Native ARKit/CoreImage adapter | Pure selection policy | One ARFrame binds image/camera/time evidence; non-Sendable/high-rate ARKit objects stay on the native side. [VERIFIED: CLM-004; existing `ARFrameCaptureAdapter`] |
| FramePacket validation and exact bytes | `ReRoomContracts` | Capture core | CON-001 and the frozen validators/JCS/wire/path policies already own this boundary. [VERIFIED: contracts README; code inspection] |
| Journal append, lifecycle transition, finalization, recovery mutation | `ReRoomCaptureCore` storage actor | Synchronous filesystem adapter | One serialized writer must own sequence allocation and all archive mutations; transitions should contain no suspension point. [VERIFIED: ADR-004; Swift actor guidance] |
| Transmission/optional-work queues | Capture core actors/adapters | Network gateway later | Queues consume journal-eligible receipts and may drop stale work; they never mutate or reorder accepted durable records. [VERIFIED: ADR-004; Master Spec §5] |
| Gateway acknowledgement | Capture core writer via typed ack adapter | Fake echo harness in Phase 2 | Ack appends the fifth event after server acceptance and is never durability authority. [VERIFIED: ADR-004; CON-002 event registry] |
| `.rrcap` verification, recovered prefix, deterministic report | Pure `ReRoomCaptureCore` reader/replayer | Existing cross-runtime tools | Replay is provider/network independent and derives all order/projections from verified journal bytes. [VERIFIED: FR-B0-001; CON-002] |
| Minimal replay inspector | Internal SwiftUI diagnostic surface | Replay report | The inspector renders already-verified report/timeline data and must not interpret raw unverified archive entries. [VERIFIED: accepted context; SwiftUI project skill] |
| Gate fixtures, fault matrix, byte comparison, evidence | Test/tooling tier | Physical operator later | GATE-001 needs synthetic and real-device evidence with explicit TARGET/MEASURED separation. [VERIFIED: GATE-001; test plan] |

## Standard Stack

### Core

| Library / API | Version | Purpose | Why Standard |
|---------------|---------|---------|--------------|
| Swift | Language mode 6.0 in Xcode target; Swift 6 in package | Sendable models, actors, deterministic core | Already selected and build-verified; do not introduce another runtime into native capture. [VERIFIED: `project.pbxproj`, `Package.swift`, local `swift --version`] |
| Foundation | Apple SDK in Xcode 26.4 | `Data`, bounded file I/O, URL/path scanning, JSON plumbing, filesystem adapters | Existing capture and contract code use it; atomic writes use sibling temporary files plus sync/rename internally, but archive ordering remains ReRoom-owned. [VERIFIED: code inspection; CITED: https://github.com/swiftlang/swift-foundation/blob/main/Sources/FoundationEssentials/Data/Data%2BWriting.swift] |
| CryptoKit | Apple SDK in Xcode 26.4 | SHA-256 through `CanonicalJSON.sha256Hex` | Existing RR-JCS/raw-byte digest implementation; no custom hash code. [VERIFIED: `CanonicalJSON.swift`] |
| `ReRoomContracts` | Repository target; CON-001/CON-002 1.0.0 | Closed schema, JCS, RRFP, coordinates, safe paths | Frozen contract authority and existing independent test oracle. [VERIFIED: contracts README; `Package.swift`] |
| ARKit + CoreImage + ImageIO | Apple SDK in Xcode 26.4 | One-frame native snapshot and physically upright encoding | Existing adapter already binds ARFrame image/camera facts and validates encoded bytes. [VERIFIED: `FramePacketBuilder.swift`; CLM-003/CLM-004] |
| Swift Testing | Bundled with toolchain | Parameterized lifecycle, corruption, queue, and replay tests | Existing suites use `Testing`; it supports isolated, parallel parameter cases with rich diagnostics. [VERIFIED: `CaptureAttemptTests.swift`; Swift Testing project skill] |
| SwiftUI + Observation | Apple SDK in Xcode 26.4 | Internal consent/capture/recovery/replay inspector | Existing diagnostic surface uses `@Observable`, `@Bindable`, native `Button`, and `confirmationDialog`. [VERIFIED: `DiagnosticChecklistView.swift`; SwiftUI project skill] |

### Supporting

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| Xcode / `xcodebuild` | 26.4 (17E192) | iOS simulator and physical build/test | App adapter, lifecycle UI, real-filesystem integration, and later physical GATE-001 evidence. [VERIFIED: local environment probe] |
| Node.js | 22.22.3 exact | Existing JavaScript oracle plus dependency-free erasable TypeScript replay runner | Run Phase 2 `.ts` fixture code directly under the pinned Node runtime, using erasable syntax only; Node does not type-check or honor general `tsconfig` transforms. [VERIFIED: local smoke test; CITED: https://nodejs.org/docs/latest-v22.x/api/typescript.html] |
| Python | 3.13.12 | Existing independent Python contract/JCS oracle and evidence tooling | Validate fixture manifests, reports, mutations, and cross-runtime consensus. [VERIFIED: local environment; Phase 1 tools] |

### External Packages

No new external package is needed or recommended. Keep the existing exact `swift-json-schema` 0.13.1 dependency and the already-audited JavaScript/Python locks unchanged. [VERIFIED: `Package.swift`; Phase 1 dependency audit]

**Installation:** none. The planner should include a guard that dependency lockfiles remain byte-unchanged unless a separately authorized dependency plan proves necessity, license, exact version, and fallback. [VERIFIED: `AGENTS.md`]

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| New target in the existing local package | Leave all logic in the Xcode app target | Faster first edit, but weak macOS/CLI replay reuse and poor separation between deterministic archive logic and AR/UI adapters. The existing package target is the preferred deep module. [VERIFIED: codebase structure; accepted packaging discretion] |
| CON-002 global journal | SQLite or a second state database | SQLite could provide transactions, but any competing order authority violates CON-002; adding it here creates reconciliation work with no phase need. [VERIFIED: CON-002; ADR-004] |
| Native internal inspector | Early Next.js client | The full web client is human-locked to Phase 7; pulling it forward expands scope and dependency surface. [VERIFIED: canonical README; accepted context] |
| Directory-form `.rrcap` | ZIP library/archive container | CON-002 defines a directory/archive meaning, not a required compression container; a ZIP dependency adds atomicity/path/streaming risks without satisfying a missing requirement. [VERIFIED: CON-002; contracts README] |

## Package Legitimacy Audit

Not applicable: Phase 2 should install no external package. Existing exact dependencies were audited and approved in Phase 1; this research does not broaden that approval. [VERIFIED: Phase 1 package audit; `AGENTS.md`]

## Architecture Patterns

### System Architecture Diagram

```text
Ready camera
    │ explicit Start room capture
    ▼
@MainActor session UI ── consent denied ──> explanation only; no archive bytes
    │ consent record bound to new session_id
    ▼
ARFrame adapter ──> deterministic selector ──> immutable selected snapshot
                                               │
                                               ▼
                                   CaptureArchiveStore actor
                                   ├─ event: frame_selected
                                   ├─ stage image + packet
                                   ├─ sync + rename generation
                                   ├─ event: durable
                                   ├─ journal frame reference
                                   ├─ event: journaled
                                   └─ event: network_eligible
                                               │ immutable eligible receipt
                         ┌─────────────────────┴────────────────────┐
                         ▼                                          ▼
              bounded upload queue                      finalized/recovered `.rrcap`
              (drop/pause metrics)                                  │
                         │ gateway echo/ack                          ▼
                         └──────────────> actor appends      ReplayCore verifies
                                          server_ack event   inventory → journal →
                                                             records → projections →
                                                             digest → report
                                                                       │
                                                                       ▼
                                                             minimal inspector
```

The primary path has one mutation authority and two one-way consumers. Network completion can arrive in any order, but only the writer actor may append acknowledgement events; replay never consults queue completion order. [VERIFIED: ADR-004; CON-002]

### Recommended Project Structure

```text
ios/Packages/ReRoomContracts/
├── Sources/ReRoomContracts/          # frozen CON validation/JCS/RRFP/path policy
├── Sources/ReRoomCaptureCore/         # deterministic archive writer/reader/replay/queue
│   ├── CaptureSession.swift           # consent/session/finalization types
│   ├── CaptureArchiveStore.swift      # sole actor mutation authority
│   ├── FramePacketEncoder.swift       # pure CON-001 packet construction from value snapshots
│   ├── CaptureFileSystem.swift        # bounded sync filesystem interface + production impl
│   ├── CaptureRecovery.swift          # contiguous-prefix verification/quarantine
│   ├── ReplayCore.swift               # pure archive verification and projection
│   ├── ReplayReport.swift             # closed JCS machine report
│   └── BoundedLatestQueue.swift       # transport/optional work, metrics only
└── Tests/ReRoomCaptureCoreTests/
    ├── CaptureLifecycleTests.swift
    ├── CaptureCrashMatrixTests.swift
    ├── ReplayMutationTests.swift
    └── BoundedQueueTests.swift

ios/ReRoomDeviceProof/ReRoomDeviceProof/
├── ARFrameCaptureAdapter.swift        # ARKit/CoreImage snapshot into Sendable values
├── CaptureSessionAdapter.swift        # scene/background/storage-pressure integration
└── DiagnosticChecklistView.swift      # internal consent/status/replay inspector only

fixtures/capture/1.0.0/rev-001/        # synthetic, non-room `.rrcap` fixtures and mutations
fixtures/replay-report.schema.json      # test/evidence schema, not a new product contract
tools/javascript/replay/*.ts           # independent erasable TypeScript fixture/report runner
tools/python/                           # independent Python fixture/report verification
```

This is a target-level deepening of the current package, not a speculative monorepo or new product client. Keep ARKit/UIKit/SwiftUI out of `ReRoomCaptureCore` so its replay path stays provider- and UI-independent. [VERIFIED: `AGENTS.md`; existing code imports; accepted context]

### Pattern 1: Non-reentrant archive transaction

**What:** Allocate journal/event sequences and complete one filesystem transition inside a synchronous actor-isolated method. Do not `await` between checking the current prefix and syncing the resulting journal entry. [VERIFIED: Swift actor reentrancy guidance; ADR-004]

**When to use:** session start, every frame lifecycle transition, acknowledgement append, explicit finalization, and recovered-prefix publication. [VERIFIED: CON-002 event/finalization fields]

```swift
// Source: project Swift Concurrency actor rules + ADR-004 ordering
actor CaptureArchiveStore {
    private var nextJournalSequence = 0
    private let files: any CaptureFileSystem

    func publishSelectedFrame(_ candidate: SelectedFrame) throws -> NetworkEligibleReceipt {
        // Synchronous actor-isolated transaction: no await/reentrancy seam.
        let allocation = allocateSequences(for: candidate)
        try writeAndSynchronizeGeneration(candidate, allocation: allocation)
        try appendAndSynchronizeLifecycle(candidate, allocation: allocation)
        nextJournalSequence = allocation.nextJournalSequence
        return try verifiedEligibleReceipt(candidate.frameID)
    }
}
```

The input must be a Sendable value snapshot, not `ARFrame`; convert ARKit/CoreImage data before crossing into the actor. [VERIFIED: existing `ARFrameCaptureAdapter`; Swift 6 project settings]

### Pattern 2: Journal-derived replay, never directory-derived replay

**What:** Validate the manifest and raw-file inventory, then walk journal sequence `0...n` exactly once. Stop at the first invalid/missing record. Derive frame and event projections from that accepted prefix and compare them byte-semantically with the manifest projections. [VERIFIED: CON-002; TST-REPLAY-001/002]

**When to use:** finalized replay, launch-time recovery, scrub authorization, corruption diagnostics, and canonical report generation. [VERIFIED: FR-B0-001; accepted context]

```swift
// Source: CON-002 global-journal and projection invariants
func verifyPrefix(_ archive: ArchiveBytes) throws -> VerifiedReplay {
    let manifest = try verifyClosedManifestAndSelfDigest(archive.manifest)
    let prefix = try verifyContiguousJournalPrefix(archive.journal, files: archive.files)
    let frames = try projectFrames(prefix)
    let events = try projectEvents(prefix)
    try requireExactProjection(frames, manifest.acceptedFrameOrder)
    try requireExactProjection(events, manifest.events)
    return try VerifiedReplay(prefix: prefix, frames: frames, events: events)
}
```

No timestamp sort, directory enumeration order, or array order may repair a journal gap. [VERIFIED: contracts README]

### Pattern 3: Durable receipt before bounded queue admission

**What:** Queue elements contain stable IDs, packet path/digest, and durable journal sequence from a verified `network_eligible` receipt. Enqueue/drop decisions update metrics only; they never delete or alter archive records. [VERIFIED: ADR-004; accepted context]

**When to use:** live send, optional compute, and test gateway echo. [VERIFIED: Master Spec §5]

```swift
// Source: ADR-004 bounded-newest-useful rule
struct UploadCandidate: Sendable, Equatable {
    let frameID: String
    let durableJournalSequence: Int
    let packetSHA256: String
    let priority: Priority // userEvent/keyframe outranks ordinary cadence
}

actor BoundedUploadQueue {
    func offer(_ candidate: UploadCandidate) -> QueueDisposition {
        // Capacity and policy are injected HYPOTHESIS values.
        // A dropped candidate remains durable in `.rrcap` for later finalized upload.
    }
}
```

### Pattern 4: Finalized and recovered-prefix are different immutable outcomes

**What:** Explicit stop appends `session_finalized`, verifies the complete journal, builds `finalization.state=finalized`, computes the self-omitting manifest digest, and atomically publishes the manifest. Launch recovery verifies/quarantines the invalid suffix, publishes a new `recovered_prefix` manifest over only the valid prefix, and never relabels it finalized. [VERIFIED: CON-002 finalization; accepted context]

**When to use:** stop/background finalization and next-launch discovery. [VERIFIED: accepted context]

Background execution is best effort and bounded: request the UIKit background assertion before critical finalization work, finish quickly, handle expiration by ending at the already-durable prefix, and always end the assertion. Do not treat background time as a durability guarantee. [CITED: https://developer.apple.com/documentation/uikit/uiapplication/beginbackgroundtask(expirationhandler:); https://developer.apple.com/documentation/uikit/uiapplicationdelegate/applicationdidenterbackground(_:)]

### Pattern 5: Canonical replay report as evidence, not a sixth product contract

**What:** Emit a closed, versioned, JCS-canonical test/evidence report containing verdict, `finalized`/`recovered_prefix`, manifest digest, journal input digest, exact accepted frame/event projection digests, revision trace digest, rejection class, and implementation/fixture identity. The report self-digest omits only its own digest member. [VERIFIED: accepted context; RR-JCS-SHA256-1 pattern; Phase 1 RunnerResultV1 precedent]

**When to use:** two-run byte comparison, cross-runtime fixture agreement, inspector input, and GATE-001 evidence. [VERIFIED: TST-REPLAY-001; GATE-001]

Keep this schema under `fixtures/` as an evidence format. If a later product client consumes it as a public boundary, Phase 7 must deliberately promote/version it through the contract-change synchronization rule. [VERIFIED: `AGENTS.md` contract discipline]

### Pattern 6: UI observes snapshots, never filesystem internals

**What:** Keep capture/replay core off `@MainActor`; expose immutable status/report snapshots to the existing `@MainActor @Observable` owner. Use native `Button` controls, dedicated accessibility labels/values, Dynamic Type styles, and stable timeline identity. [VERIFIED: SwiftUI project skill; existing diagnostic view]

**When to use:** Start/Stop, consent disclosure, local/upload state, recovery card, integrity summary, and verified timeline scrub. [VERIFIED: accepted context]

### Anti-Patterns to Avoid

- **A second ordering authority:** Never sort by timestamp, capture sequence, ack sequence, directory order, or queue completion to repair/replay a capture. [VERIFIED: CON-002]
- **Exposing a staged packet:** The CON-001 packet snapshot may contain `durability.state=network_eligible` only as staged bytes; do not return/send it until the journal and `frame_network_eligible` event are synced and revalidated. [VERIFIED: CON-001 durability; current builder design]
- **Await inside sequence allocation/publication:** Actor reentrancy can admit another operation between validation and append. Keep the filesystem transaction synchronous inside the actor. [VERIFIED: Swift actor guidance]
- **Resuming an interrupted archive:** A recovered capture is immutable `recovered_prefix`; a new recording creates a new session ID/archive. [VERIFIED: accepted context]
- **In-place manifest digest recursion:** Remove only `finalization.manifest_sha256`, canonicalize, hash, then insert it; no other field is excluded. [VERIFIED: CON-002]
- **Background-task optimism:** The OS may deny/expire extra time; successful finalization must not depend on a guaranteed duration. [CITED: https://developer.apple.com/documentation/uikit/uiapplication/beginbackgroundtask(expirationhandler:)]
- **Storage estimate as permission to lose selected data:** Available-capacity values are advisory; write failure must stop/finalize the valid prefix rather than delete a selected durable packet. [CITED: https://github.com/swiftlang/swift-foundation/blob/main/Sources/FoundationEssentials/URL/URL.swift]
- **Unverified scrub:** The inspector must never decode/display a frame beyond the hash-valid accepted prefix. [VERIFIED: accepted context]
- **A polished web detour:** Do not initialize Next.js, ordinary-video support, sessions/sharing, or typed replay forks in Phase 2. [VERIFIED: accepted context]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Canonical JSON | Another key sorter/number formatter | Existing `CanonicalJSON` + frozen FX-JCS vectors | RFC 8785 strings/numbers/duplicates/Unicode are already independently proven. [VERIFIED: CLM-036; Phase 1 tests] |
| SHA-256 | Custom digest implementation | `CanonicalJSON.sha256Hex` / CryptoKit | One existing lowercase implementation covers structured and raw bytes. [VERIFIED: `CanonicalJSON.swift`] |
| Closed contract validation | Ad hoc Codable-only checks | Existing `ContractValidator` plus semantic validators | JSON Schema owns fields, while exact semantic checks own projections/digests/order. [VERIFIED: contracts README; code inspection] |
| Archive path safety | String concatenation/prefix checks | Existing `ArchivePath.resolve` | It already enforces normalized paths and symlink-aware root containment. [VERIFIED: Phase 1 decisions; `ArchivePath.swift`] |
| RRFP framing | Another envelope | Existing `WireFrame`/RRFP-WIRE-1 | The wire bytes and limits are closed and cross-runtime tested. [VERIFIED: CON-001; Phase 1 tests] |
| Concurrent journal mutation | Locks, dispatch queues, or multiple writers | One Swift actor with synchronous transitions | Compiler-enforced ownership matches the sole-authority invariant. [VERIFIED: Swift actor guidance; ADR-004] |
| Test timing | Sleeps and real network | Deterministic fake clock, fault filesystem, echo adapter, parameterized Swift Testing cases | Tests must prove ordering independent of timing and remain parallel-safe. [VERIFIED: Swift Testing project skill; TST-QUEUE-001] |
| Consent/inspector controls | Tap gestures or custom controls | Native SwiftUI `Button`, `confirmationDialog`, accessibility modifiers | Native controls supply semantics/focus and match the existing diagnostic surface. [VERIFIED: SwiftUI project skill] |
| Queue library | New reactive/async package | Small bounded actor over immutable receipts | The required policy is narrow and domain-specific; no dependency need is established. [VERIFIED: accepted context; dependency rule] |

**Key insight:** The custom work is not cryptography, JSON, schema, or a generic queue. It is the ReRoom-specific transaction that binds those proven primitives into one crash-tested journal authority. [VERIFIED: ADR-004; existing Phase 1 primitives]

## Common Pitfalls

### Pitfall 1: Completing only four lifecycle states

**What goes wrong:** A capture passes Phase 1 tests but cannot prove the exact canonical lifecycle or acknowledged upload state. [VERIFIED: current `FrameCaptureLifecycle` and Phase 1 test assertion]

**How to avoid:** Add `serverAcknowledged`; before append, a typed adapter must match the ack to the outstanding session/frame/idempotency key/packet digest and server-accepted sequence. Record only fields already permitted by CON-002 unless a deliberate contract change is approved. Validate it as the fifth per-frame event without making it a prerequisite for local replay. [VERIFIED: ADR-004; Master Spec §5; CON-002]

**Warning sign:** `frame_server_acknowledged` appears in no positive fixture, or `server_acknowledged` changes whether the frame is durable/visible locally. [VERIFIED: CON-002]

### Pitfall 2: Conflating open, finalized, and recovered archives

**What goes wrong:** Every recovery is labeled `recovered_prefix`, explicit stop never creates `finalized`, or recovery rewrites status to look complete. [VERIFIED: current `buildManifest`; accepted context]

**How to avoid:** Make finalization state an explicit input/output of distinct writer/recovery paths and test both byte identities separately. [VERIFIED: CON-002 finalization enum]

**Warning sign:** Manifest generation has a hard-coded state or an interrupted archive is recordable again. [VERIFIED: current code; accepted context]

### Pitfall 3: Trusting a schema-valid but semantically inconsistent manifest

**What goes wrong:** JSON Schema accepts individually well-shaped arrays even if they disagree with the journal, event record hashes, packet/image hashes, or final sequence. [VERIFIED: contracts README states deterministic semantic validation requirements]

**How to avoid:** Replay validation must independently recompute every digest and exact projection, then compare complete arrays. [VERIFIED: TST-REPLAY-001/002]

**Warning sign:** Tests mutate only schema fields, not gaps/reorders/references/digests/projections/paths/versions. [VERIFIED: TST-REPLAY-002]

### Pitfall 4: Weak crash injection

**What goes wrong:** Tests throw at high-level lifecycle labels but miss write, sync, rename, append, manifest, and ack edges, so earlier records can still be corrupted. [VERIFIED: GATE-001 requires termination after states and zero earlier-record corruption]

**How to avoid:** Use a scripted filesystem operation log/fault plan for every write/sync/rename/append/replace boundary, plus production-filesystem integration tests. Keep the existing memory fake but make its sync/rename failures observable. [VERIFIED: current crash injector/fakes; GATE-001]

**Warning sign:** The only crash enum remains four cases or the fake `synchronizeDirectory` is a no-op with no injectable failure. [VERIFIED: current code]

### Pitfall 5: Queue behavior changes replay meaning

**What goes wrong:** Dropped or out-of-order live completions remove durable frames, rewrite sequence, or determine replay order. [VERIFIED: NFR-REPLAY-001]

**How to avoid:** Queue only eligible receipts; keep drop/queue/completion metrics separate; compare replay output after deliberately reversed completion. [VERIFIED: TST-QUEUE-001]

**Warning sign:** Queue capacity is unbounded, a queue owns FramePacket persistence, or a test expects completion order to equal journal order. [VERIFIED: ADR-004]

### Pitfall 6: Main-actor file and replay work

**What goes wrong:** Capture finalization or replay hashing stalls the UI/render path. [VERIFIED: root invariant that render never waits for worker/network; SwiftUI owner currently calls synchronous journal methods]

**How to avoid:** Snapshot ARFrame/UI inputs on the native owner, call the capture actor asynchronously, and return immutable status/report snapshots to `@MainActor`. [VERIFIED: Swift Concurrency project skill]

**Warning sign:** `Data(contentsOf:)`, directory scans, JCS, or full replay loops execute directly in a SwiftUI button action. [VERIFIED: architecture recommendation]

### Pitfall 7: Fabricated evidence labels

**What goes wrong:** Simulator/fault-harness results are reported as physical `MEASURED` GATE-001 results. [VERIFIED: `AGENTS.md` evidence discipline]

**How to avoid:** Keep synthetic results automated and label capacities/cadence/pressure values `HYPOTHESIS`/`TARGET`; leave physical 10s/60s captures pending until recorded on the named build/device with raw evidence. [VERIFIED: GATE-001]

**Warning sign:** A committed report claims physical throughput/thermal/storage thresholds without fixture, revision, environment, raw trace, calculation, and evaluator. [VERIFIED: `AGENTS.md`]

## Code Examples

### Self-omitting report digest

```swift
// Source: RR-JCS-SHA256-1 manifest/report pattern
func canonicalReplayReport(_ fields: [String: Any]) throws -> Data {
    var digestInput = fields
    digestInput.removeValue(forKey: "report_sha256")
    let inputBytes = try canonicalData(digestInput)
    var complete = digestInput
    complete["report_sha256"] = CanonicalJSON.sha256Hex(inputBytes)
    return try canonicalData(complete)
}
```

The new evidence schema must name this exact omission scope and reject all unknown fields/versions. [VERIFIED: Phase 1 RunnerResultV1 pattern; contract discipline]

### Contiguous-prefix fold

```swift
// Source: CON-002 recovery rule
func acceptedPrefix(_ lines: [Data], files: ArchiveFiles) -> PrefixResult {
    var accepted: [JournalEntry] = []
    for (expected, bytes) in lines.enumerated() {
        guard let entry = try? verifyJournalEntry(bytes, files: files),
              entry.journalSequence == expected else {
            return .recovered(accepted: accepted, firstInvalidSequence: expected)
        }
        accepted.append(entry)
    }
    return .complete(accepted)
}
```

Never skip an invalid entry and continue; later valid-looking bytes are suffix quarantine, not replay input. [VERIFIED: TST-REPLAY-002]

### Parallel-safe fault test

```swift
// Source: Swift Testing project skill + GATE-001
@Test("Each durability edge preserves only a valid prefix", arguments: FaultEdge.allCases)
func crashMatrix(edge: FaultEdge) throws {
    let fixture = IsolatedCaptureFixture(failingAt: edge)
    #expect(throws: InjectedFault.self) { try fixture.run() }
    let recovered = try fixture.reopenAndRecover()
    #expect(recovered.journalSequences == Array(recovered.journalSequences.indices))
    #expect(recovered.allReferencedBytesVerify)
}
```

Each parameter needs its own temp root/fake instance; do not serialize the whole suite to hide shared state. [VERIFIED: Swift Testing parallelization guidance]

## Privacy and Trust Boundaries

- Consent authorization is a session-bound input to archive creation; a denial path may retain only the non-capture explanation and must produce no directory, journal, manifest, or image bytes. [VERIFIED: SEC-CONSENT-001; TST-CAPTURE-001; accepted context]
- `local_only_until_share` is the foreground default; upload state is separate and no share action exists in Phase 2. [VERIFIED: accepted context]
- Archive paths, manifests, journal lines, event payloads, packet bytes, and reports are untrusted on read. Apply bounds, path containment, closed version checks, raw/JCS digests, and exact projection validation before exposure. [VERIFIED: contracts README; `AGENTS.md`]
- Quarantined corrupt suffix bytes must remain outside the accepted manifest/replay set and must not be shown by the inspector. Do not commit raw room bytes or private traces. [VERIFIED: accepted context; `AGENTS.md`]
- The replay core imports no network/model/provider module; a fake gateway echo is a typed test adapter, not a hidden live dependency. [VERIFIED: FR-B0-001; accepted context]

## State of the Codebase

| Current Phase 1 State | Required Phase 2 State | Planning Impact |
|-----------------------|------------------------|-----------------|
| `DiagnosticJournal` is an app-target `final class` with mutable arrays. | One capture-core actor owns sequence allocation and archive mutation. | Extract behavior with characterization tests before changing semantics. [VERIFIED: code inspection] |
| Four lifecycle events through `network_eligible`; positive tests explicitly exclude ack. | Exact five-state lifecycle with typed gateway ack and independent local replay. | Add ack after base writer tests; do not make ack durability authority. [VERIFIED: code inspection; ADR-004] |
| Manifest is generated in memory and hard-coded `recovered_prefix`. | Atomically published `finalized` or `recovered_prefix` manifest with exact self-digest. | Separate explicit stop and recovery plans. [VERIFIED: code inspection; CON-002] |
| One diagnostic frame selected by user event; queue capacity hard-coded to 1 in manifest. | Deterministic session selector plus injected TARGET/HYPOTHESIS policy and measured bounded queues. | Freeze policy names/inputs; do not claim measured thresholds. [VERIFIED: code inspection; accepted context] |
| Recovery truncates a torn JSONL tail and validates accepted projections. | Quarantine/repair suffix, validate full inventory, emit deterministic report, never resume same archive. | Retain valid code as seed but broaden mutations and outcomes. [VERIFIED: code inspection; accepted context] |
| SwiftUI button asks consent for one test frame and synchronously captures/replays. | Explicit Start flow, persistent local/upload state, Stop, recovered card, verified inspector. | Keep internal diagnostic scope and move heavy work off MainActor. [VERIFIED: code inspection; accepted context] |
| Existing cross-runtime result schema knows only Phase 1 fixture families. | New closed Phase 2 replay-report evidence schema/fixture family. | Do not silently loosen or repurpose RunnerResultV1 enums. [VERIFIED: `runner-result.schema.json`; contract discipline] |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| — | None. Recommendations are grounded in locked context, canonical repository authority, inspected code, installed project skills, or cited platform documentation. | — | — |

## Open Questions (RESOLVED)

1. **RESOLVED — What queue capacities, cadence, quality cutoffs, storage warning thresholds, and pressure thresholds ship initially?**
   - What we know: all must be bounded; user-event frames are retained; optional compute drops first, upload pauses second, then cadence/quality degrades. [VERIFIED: accepted context]
   - What's unclear: numeric values have no `MEASURED` evidence. [VERIFIED: GATE-001]
   - **Resolution selected by Plan 02-04:** inject explicit named `HYPOTHESIS`/`TARGET` values into fixtures and make GATE-001 output the observed depths/drops/latencies; promotion to `MEASURED` requires real evidence. [VERIFIED: `AGENTS.md`]

2. **RESOLVED — When can GATE-001 become GREEN?**
   - What we know: synthetic/fault/replay automation can be completed in this phase, but the gate also specifies physical 10-second and 60-second captures. [VERIFIED: GATE-001]
   - What's unclear: fresh Phase 2 physical capture evidence does not exist yet. [VERIFIED: repository inspection]
   - **Resolution selected by Plan 02-07:** only the explicit human/device checkpoint after green automation may authorize GREEN; leave the phase/gate pending or RED if real physical evidence is unavailable, incomplete, or misses a threshold. Synthetic/simulator evidence has no GREEN authority. [VERIFIED: `AGENTS.md`; GATE-001]

3. **RESOLVED — How should an invalid suffix be retained?**
   - What we know: it may be discarded or quarantined, but accepted replay must stop at the valid prefix and immutable history must not be rewritten as complete. [VERIFIED: accepted context]
   - What's unclear: the exact out-of-band representation is discretionary. [VERIFIED: accepted context]
   - **Resolution selected by Plan 02-03:** copy the raw invalid suffix plus its SHA-256 and first-invalid sequence into a bounded diagnostic quarantine outside the accepted `.rrcap` inventory, then atomically replace the live journal with the verified prefix. Never expose or commit room bytes. [VERIFIED: accepted context; existing repair pattern; `AGENTS.md`]

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| Swift toolchain | Capture core and package tests | ✓ | Apple Swift 6.3; package language mode Swift 6 | Xcode-bundled compiler only; do not change language mode in this phase. [VERIFIED: local probe; `Package.swift`] |
| Xcode / iOS Simulator | App adapter and internal UI tests | ✓ | Xcode 26.4 (17E192) | Swift package host tests cover pure core; simulator remains required for app/UI integration. [VERIFIED: local probe] |
| Node.js | Existing JavaScript oracle and Phase 2 TypeScript golden runner | ✓ | 22.22.3 exact | Built-in erasable type stripping; no `tsx`/compiler install. Keep syntax erasable and add a direct runtime smoke test. [VERIFIED: local probe/smoke test; CITED: https://nodejs.org/docs/latest-v22.x/api/typescript.html] |
| Python | Fixture/report/evidence tooling | ✓ | 3.13.12 | Standard-library tooling where possible; existing locked environment for current validators. [VERIFIED: local probe] |
| Physical base iPhone/signing | Fresh GATE-001 10s/60s evidence | Not re-run in this research | Phase 1 has separate signed readiness evidence | Keep physical subgate pending until a human runs the Phase 2 fixture; simulator evidence cannot substitute. [VERIFIED: STATE.md; `AGENTS.md`; GATE-001] |

**Missing dependencies with no fallback:** fresh physical GATE-001 evidence is required before a true GREEN claim, but it does not block planning or host/simulator implementation. [VERIFIED: GATE-001]

**Missing dependencies with fallback:** none; no new software dependency is required. [VERIFIED: environment audit]

## Sources

### Primary (HIGH confidence)

- `docs/canonical/README.md` — human locks and authority order. [VERIFIED: repository canonical authority]
- `docs/adr/ADR-004-atomic-capture-and-record-first-replay.md` — exact lifecycle, journal authority, bounded queue, fallback, and GATE-001. [VERIFIED: Accepted ADR]
- `docs/contracts/frame-packet.schema.json` and `docs/contracts/rrcap-manifest.schema.json` — CON-001/CON-002 field and lifecycle authority. [VERIFIED: repository schema authority]
- `docs/contracts/README.md` — closed-reader, replay-order, digest, projection, path, and compatibility invariants. [VERIFIED: repository contract authority]
- `docs/canonical/MASTER_TECHNICAL_SPEC.md` §§4–5, 14, 18–19 — record-first system flow and ownership. [VERIFIED: repository canonical authority]
- `docs/canonical/PRD.md` — FR-CAPTURE-001, FR-B0-001, NFR-REPLAY-001, SEC-CONSENT-001. [VERIFIED: repository canonical authority]
- `docs/canonical/TEST_AND_EVALUATION_PLAN.md` — TST-CAPTURE-001, TST-DIGEST-001, TST-REPLAY-001/002, TST-QUEUE-001. [VERIFIED: repository quality authority]
- `docs/canonical/RISK_AND_KILL_GATES.md` — GATE-001 measurement, threshold, fallback, and blocking effect. [VERIFIED: repository gate authority]
- `docs/canonical/GLOSSARY_AND_ID_REGISTRY.md` — FramePacket, `.rrcap`, RR-JCS-SHA256-1, lifecycle, and ID families. [VERIFIED: repository naming authority]
- `docs/canonical/RESEARCH_LEDGER.md` CLM-003, CLM-004, CLM-036 — ARFrame/ARKit and RFC 8785 evidence. [VERIFIED: repository research ledger]
- Phase 1 Swift implementation/tests named above — current reusable behavior and concrete gaps. [VERIFIED: codebase inspection]

### Secondary (MEDIUM confidence)

- [Swift Foundation `Data+Writing.swift`](https://github.com/swiftlang/swift-foundation/blob/main/Sources/FoundationEssentials/Data/Data%2BWriting.swift) — temp-file, `fsync`, and rename implementation pattern. [CITED: official Swift Foundation source]
- [UIKit `applicationDidEnterBackground`](https://developer.apple.com/documentation/uikit/uiapplicationdelegate/applicationdidenterbackground(_:)) — prompt state saving and scene caveat. [CITED: Apple Developer documentation]
- [UIKit `beginBackgroundTask`](https://developer.apple.com/documentation/uikit/uiapplication/beginbackgroundtask(expirationhandler:)) — bounded critical file completion and expiration handling. [CITED: Apple Developer documentation]
- [Swift Foundation URL capacity API source](https://github.com/swiftlang/swift-foundation/blob/main/Sources/FoundationEssentials/URL/URL.swift) — advisory important-usage capacity semantics. [CITED: official Swift Foundation source]
- [Node.js v22 TypeScript documentation](https://nodejs.org/docs/latest-v22.x/api/typescript.html) — built-in lightweight type stripping, erasable syntax, and lack of full `tsconfig`/type-checking behavior. [CITED: official Node.js documentation]
- Project Swift Concurrency, Swift Testing, and SwiftUI skills — actor reentrancy, parallel-safe tests, and native accessible UI conventions. [VERIFIED: checked-in project skills]

### Tertiary (LOW confidence)

- None. No training-only or non-authoritative claim is used as a planning premise.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — existing exact repository/toolchain stack; no new dependency. [VERIFIED: codebase and local environment]
- Architecture: HIGH — constrained by Accepted ADR-004, CON-001/CON-002, and locked context. [VERIFIED: canonical authority]
- Platform lifecycle/storage details: MEDIUM — current official Apple/Swift sources retrieved through Context7; still require fault tests on the actual target filesystem and device. [CITED: Apple/Swift sources]
- Pitfalls: HIGH — most are explicit canonical rejection cases or observable gaps in the Phase 1 seed. [VERIFIED: tests/contracts/code inspection]

**Research date:** 2026-07-17
**Valid until:** 2026-08-16 for planning; re-check Apple SDK behavior and live repository evidence before implementation if the toolchain or canonical sources change.
