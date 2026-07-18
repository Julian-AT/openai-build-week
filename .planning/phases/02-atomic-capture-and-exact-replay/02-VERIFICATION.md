---
phase: 02-atomic-capture-and-exact-replay
verified: 2026-07-18T12:53:58Z
status: human_needed
score: 48/48 must-haves verified
behavior_unverified: 0
overrides_applied: 0
deferred:
  - truth: "The new-revision full GATE-001 physical consent, pressure, five-state termination, recovery, and two-replay matrix has human attestation."
    addressed_in: "Phase 8"
    evidence: ".planning/SPRINT-CUT-36H.md explicitly defers the full matrix while keeping GATE-001 PENDING."
human_verification:
  - test: "Run the signed-device pressure/recovery smoke for the sprint, then the complete new-revision GATE-001 10-second/60-second five-state matrix and human attestation before a release claim."
    expected: "The smoke is recorded honestly; the full gate remains PENDING until the closed physical observation document passes and a human-bound GREEN report is supplied."
    why_human: "Camera, signing, abrupt termination, physical storage/queue behavior, and human attestation cannot be established by simulator or host automation."
  - test: "Review the prohibition that server acknowledgement, queue completion, or network availability must not become local durability/replay authority."
    expected: "Human accepts the implementation and evidence as preserving journal-first local authority."
    why_human: "The plan marks this descriptor-less prohibition unresolved; the verifier's code review is non-authoritative."
  - test: "Review the prohibition that provider/network output must not enter the deterministic replay oracle."
    expected: "Human accepts the replay oracle as provider- and network-independent."
    why_human: "The plan marks this descriptor-less prohibition unresolved; the verifier's code review is non-authoritative."
  - test: "Review the prohibition against exposing, enqueueing, or acknowledging a frame before durable image/metadata and journal binding."
    expected: "Human accepts the record-first lifecycle enforcement."
    why_human: "The plan marks this descriptor-less prohibition unresolved; the verifier's code review is non-authoritative."
  - test: "Review the prohibition against pre-consent capture bytes or consent reuse across session IDs."
    expected: "Human accepts the per-session consent boundary."
    why_human: "The plan marks this product-specific prohibition unresolved; device UX remains a human check."
  - test: "Review the prohibition against exposing replay records beyond the last hash-valid contiguous prefix."
    expected: "Human accepts the verified-only timeline boundary."
    why_human: "The plan marks this descriptor-less prohibition unresolved; the verifier's code review is non-authoritative."
  - test: "Review the prohibition against repairing journal gaps/reordering with timestamps, arrays, directory order, or provider output."
    expected: "Human accepts global journal sequence as sole order."
    why_human: "The plan marks this descriptor-less prohibition unresolved; the verifier's code review is non-authoritative."
  - test: "Review the prohibition against live drop/cancel/pause/completion order deleting durable packets or redefining replay order."
    expected: "Human accepts durable order as independent of live queues."
    why_human: "The plan marks this descriptor-less prohibition unresolved; the verifier's code review is non-authoritative."
  - test: "Review the prohibition against cross-runtime agreement by copied expected output, mismatch normalization, or another runtime's authority."
    expected: "Human accepts the three runners as independent computations."
    why_human: "The plan marks this descriptor-less prohibition unresolved; independence includes an architectural judgment."
  - test: "Review the prohibition against presenting local durability as upload/share completion or hiding paused/offline/recovered states."
    expected: "Human accepts the on-device wording and state separation."
    why_human: "Truthfulness and comprehension of UI copy require human judgment."
  - test: "Review the prohibition against the inspector decoding or exposing records ReplayCore did not verify."
    expected: "Human accepts the verified replay snapshot boundary."
    why_human: "The plan marks this descriptor-less prohibition unresolved; the verifier's code review is non-authoritative."
  - test: "Review the prohibition against labeling synthetic, simulator, fixture, or inferred results as physical MEASURED GATE-001 evidence."
    expected: "Human confirms that only real physical evidence may be promoted to MEASURED/GREEN."
    why_human: "Only the human decision actor can authorize physical gate evidence."
  - test: "Review the prohibition against committing raw room imagery, private traces, device identifiers, signing material, or account data."
    expected: "Human confirms the retained external artifacts and checked-in sanitized facts respect the privacy boundary."
    why_human: "The allowlist and secret scan are automated support; classification of retained physical artifacts is a human responsibility."
---

# Phase 2: Atomic Capture and Exact Replay Verification Report

**Phase Goal:** Consented selected frames become crash-safe, journal-authoritative replay inputs before they can be uploaded or coupled to live providers.
**Verified:** 2026-07-18T12:53:58Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Verdict

The automated/local Phase 2 implementation is achieved: all 48 merged roadmap
and plan truths have executable evidence, all 22 declared artifacts exist and
are substantive, all 20 declared key links are wired, and the verifier's own
read-only run passed all eight full preflight checks.

This is not a GATE-001 GREEN verdict. The checked-in gate report is `RUNNING`,
the checklist is `UNRUN`, its environment says signing/camera/ARKit are
`not_tested`, and the gate command correctly exits `2` with
`physical observations and human attestation are required`. The approved
36-hour sprint overlay permits sequencing past the automated/local slice but
explicitly leaves the new-revision physical matrix `PENDING`; it does not
override canonical release authority.

## Goal Achievement

### Roadmap Success Criteria

| # | Truth | Status | Evidence |
|---|---|---|---|
| R1 | Consent precedes selected room imagery; recording/upload state is distinct and denial remains non-capturing. | ✓ VERIFIED | `CaptureSessionAdapter.acceptDisclosure` creates a fresh authorization/session before `startSession`; denial writes no archive in `CaptureLifecycleTests`/`CaptureSessionAdapterTests`; `DiagnosticSurfaceTests` exercises disclosure plus visible local/upload states. Physical comprehension remains in the human section. |
| R2 | Accepted frames follow the exact five-state durable lifecycle, validate RRFP/image hashes, survive every declared fault edge as no frame or one valid journaled frame, and never upload before journal authority. | ✓ VERIFIED | `CaptureArchiveStore` advances the closed state machine synchronously inside one actor; `FramePacketEncoder` binds payload bytes; the full `lifecycle_crash_matrix` check passed `CaptureLifecycleTests` and `CaptureCrashMatrixTests`. |
| R3 | Finalized and recovered-prefix archives replay identically; corrupt suffix stops at the valid prefix without provider/network authority. | ✓ VERIFIED | `CaptureRecovery` validates inventory/journal/projections and publishes a verified sibling; `ReplayCore` derives only from the contiguous journal; `recovery_exact_replay` and `three_runtime_agreement` passed with 16 cases, three runtimes, zero semantic/digest/integrity disagreements. |
| R4 | Queue depth is bounded, stale/capacity drops are measured, durable sequences remain monotonic, and replay ignores live completion order. | ✓ VERIFIED | `CaptureAdmissionGate` and `BoundedLatestQueue` include in-flight work in capacity and expose metrics; `queue_stress_reordering` passed. Numeric defaults remain HYPOTHESIS/TARGET, and physical pressure remains pending. |

### Plan Truths

Every plan truth was checked against code and the named behavioral suites. The
short evidence references below are to checks the verifier ran, not to SUMMARY
claims.

| ID | Plan truth | Status | Evidence |
|---|---|---|---|
| 01.1 | Capture/replay interfaces are Sendable and provider/network/UI independent. | ✓ VERIFIED | `ReRoomCaptureCore` has no ARKit/SwiftUI/network client import; Swift 6 package tests pass. |
| 01.2 | Frozen finalized-empty, one-frame, and recovered-prefix corpus is manifest/hash bound. | ✓ VERIFIED | Immutable fixture manifest validation passed `contract_package` and three-runtime agreement. |
| 01.3 | CON-001/CON-002 and filesystem adjacent boundary cases reject without repair/partial output. | ✓ VERIFIED | Fixture tests and Swift package boundary/mutation suites pass. |
| 01.4 | Binary32-first coordinates, RRFP bytes, image/packet hashes, and JCS scopes remain exact. | ✓ VERIFIED | Package contract vectors and three-runtime `fr-capture.precision` case pass. |
| 02.1 | Each concurrent session requires its own explicit authorization. | ✓ VERIFIED | Session-ID authorization guards plus consent/concurrency tests pass. |
| 02.2 | Lifecycle adjacency is exact and duplicate/skipped/inverted/out-of-session acknowledgements reject. | ✓ VERIFIED | Closed `CaptureFrameState.advanced(to:)` and lifecycle tests pass. |
| 02.3 | One actor owns sequence allocation and synchronous filesystem transitions without an actor reentrancy seam. | ✓ VERIFIED | `CaptureArchiveStore` is an actor; mutation methods contain no `await`; crash/concurrency tests pass. |
| 02.4 | Consented zero-frame finalization is valid; denied/malformed consent writes no capture. | ✓ VERIFIED | Empty archive and consent-denial tests pass. |
| 02.5 | Fault injection at declared durability edges preserves no frame or the last complete valid prefix. | ✓ VERIFIED | Full crash matrix passes, including JPEG live profile recovery. |
| 02.6 | Explicit stop is finalized; interruption preserves a recoverable prefix and is not mislabeled. | ✓ VERIFIED | Adapter/background and recovery tests pass. |
| 03.1 | Launch recovery accepts one contiguous prefix, excludes suffix bytes, and never resumes the source. | ✓ VERIFIED | `CaptureRecovery.inspect/recover` and recovery immutability tests pass. |
| 03.2 | Corrupt suffix stops adjacent; gap/reorder/interior corruption fails closed. | ✓ VERIFIED | `CaptureRecoveryTests.journalAdjacency` and corrupt-suffix/interior tests pass. |
| 03.3 | Valid zero-frame finalization differs from missing/empty journal rejection. | ✓ VERIFIED | Complete archive and missing/empty launch tests pass. |
| 03.4 | Replay order comes only from global journal tuples. | ✓ VERIFIED | `ReplayCore` enumerates journal order; mutation and ordering cases pass. |
| 03.5 | Replays over identical input emit byte-identical reports and verified timelines. | ✓ VERIFIED | Replay concurrency tests and two-run cross-runtime publisher pass. |
| 03.6 | Unsupported/tampered/projection-invalid input rejects before timeline exposure. | ✓ VERIFIED | Recovery/replay mutation suites and 16-case corpus pass. |
| 03.7 | The Swift runner consumes the frozen manifest and emits the complete sorted report set. | ✓ VERIFIED | Named `ReRoomReplayRunner` product is invoked by the passing agreement script. |
| 04.1 | Selection is deterministic and admission precedes selected lifecycle. | ✓ VERIFIED | `FrameSelectionPolicy` plus selection/admission tests pass. |
| 04.2 | Synchronous pre-durability admission is nonblocking and bounded by ordinary capacity plus one reserved event. | ✓ VERIFIED | Lock-backed `offer` has no task/await/user callback; stress tests pass. |
| 04.3 | Reserved user-event lane is single-flight and cannot be replaced by ordinary work. | ✓ VERIFIED | `CaptureAdmissionGate.State.admit/takeNext` and admission tests pass. |
| 04.4 | Only immutable durable receipts enter transport/optional queues. | ✓ VERIFIED | `CaptureTransport` input type is `NetworkEligibleReceipt`; wiring query and package tests pass. |
| 04.5 | Queues have positive bounded capacity and stable depth/drop/pause/completion metrics. | ✓ VERIFIED | Initializers reject invalid capacity; queue stress tests pass. |
| 04.6 | Optional compute drops, upload pause, then cadence/quality reduction do not rewrite durable records. | ✓ VERIFIED | Pressure policy tests pass; archive authority is a separate actor. |
| 04.7 | Reordered/duplicate/delayed/cancelled/blackholed completion changes only live metrics. | ✓ VERIFIED | Queue reordering tests and replay agreement pass. |
| 04.8 | Capacity/cadence/quality/pressure numbers remain HYPOTHESIS/TARGET until physical measurement. | ✓ VERIFIED | Preflight validator requires HYPOTHESIS/TARGET and rejects physical fixture identity/MEASURED automation; evidence limitation remains explicit. |
| 05.1 | Swift, exact Node 22.22.3, and Python independently compute closed reports. | ✓ VERIFIED | Three independent runners produced 16 reports each. |
| 05.2 | All runtimes verify inventory, event/packet digests, projections, final sequence, manifest hash, and input digest. | ✓ VERIFIED | Agreement has zero integrity, semantic, runtime, or report-digest disagreement. |
| 05.3 | Two runs and publication are byte-identical, complete, sorted, and revision/source/fixture bound. | ✓ VERIFIED | Agreement script and `--verify-evidence` pass; evidence names exact revision and source digest. |
| 05.4 | Boundary/empty/order/precision/concurrency/corruption/completion cases agree. | ✓ VERIFIED | All 16 manifest cases have shared verdict/rejection and artifact digest. |
| 05.5 | Mutation gates reject omissions, stale/mixed identity, drift, wrong digest, and semantic/oracle corruption. | ✓ VERIFIED | Replay-agreement mutation tests pass inside `contract_package`/agreement checks. |
| 06.1 | Ready-camera flow requests disclosure; accept makes a fresh session; denial creates no archive. | ✓ VERIFIED | Adapter/UI tests pass and code creates authorization only after acceptance. |
| 06.2 | Local recording, upload/offline, and share state are independently visible. | ✓ VERIFIED | Snapshot labels and `DiagnosticSurfaceTests` verify the distinct surfaces. |
| 06.3 | Stop finalizes; background expiry preserves prefix and ends its assertion. | ✓ VERIFIED | Adapter background tests pass; `defer endBackgroundAssertion()` is wired. |
| 06.4 | Next launch verifies interrupted archives and exposes recovered/inspect/new-capture paths without resuming. | ✓ VERIFIED | Recovery driver feeds verified snapshots; simulator UI flow passes. |
| 06.5 | Inspector renders only verified report snapshots in journal order. | ✓ VERIFIED | `VerifiedReplayInspector` checks accept verdict, digest/finalization counts, and contiguous sequence before the view receives data. |
| 06.6 | High-rate callback performs one synchronous offer; one off-main consumer serializes writes within capacity. | ✓ VERIFIED | `offerARFrame`/`offerCapturedFrame` are synchronous; one `Task { @concurrent }` leases `runConsumer`; adapter tests pass. |
| 06.7 | Capacity rejection creates no selected write; repeated explicit action is disabled/rejected with exact copy. | ✓ VERIFIED | Payload is removed on rejection, busy state/copy is tested, and UI button is disabled. |
| 06.8 | Native frame work remains on MainActor; archive/replay work is off-main; 60 Hz path never awaits it. | ✓ VERIFIED | Swift isolation annotations and no-await callback path compile under Swift 6; simulator/release tests pass. |
| 07.1 | One preflight covers the declared synthetic matrices without consuming physical fixture identities. | ✓ VERIFIED | Verifier's read-only full run passed all eight check IDs; validator rejects `FX-RRCAP-*` in automation. |
| 07.2 | Only human-bound real-device evidence can make GATE-001 GREEN. | ✓ VERIFIED | `verify_gate_paths` requires GREEN + human actor + physical observation path and currently exits pending. |
| 07.3 | GREEN requires exactly the five canonical termination-state observations. | ✓ VERIFIED | Closed schema requires five; semantic validator requires exact ordered state tuple. |
| 07.4 | Physical records must bind zero invalid upload/corruption, exact prefix, two matching replays, bounded queue, and visible states—or fail. | ✓ VERIFIED | `validate_physical_observations` enforces each relation; no physical record is currently claimed. |
| 07.5 | Checked-in evidence is allowlisted/sanitized and excludes raw/private/machine facts. | ✓ VERIFIED | Preflight reconstruction uses closed fields, privacy validation, digests, and opaque artifact IDs. |
| 07.6 | Missing/incomplete physical evidence leaves GATE-001 pending/RED and blocks live integration. | ✓ VERIFIED | Gate command exits `2`; report remains `RUNNING`, checklist `UNRUN`, physical state `pending`. |

**Score:** 48/48 truths verified (0 present-but-behavior-unverified)

## Required Artifacts

| Plan | Artifacts | Status | Details |
|---|---:|---|---|
| 02-01 | 3 | ✓ VERIFIED | Contracts, frozen corpus manifest, and report schema exist, are substantive, and are exercised. |
| 02-02 | 2 | ✓ VERIFIED | Archive actor and crash matrix exist and pass behavioral tests. |
| 02-03 | 4 | ✓ VERIFIED | Recovery, replay, report, and Swift runner are wired through the package executable. |
| 02-04 | 4 | ✓ VERIFIED | Selector, admission, bounded queue, and transport are concrete and tested. |
| 02-05 | 3 | ✓ VERIFIED | Independent Node/Python runners and published agreement evidence are verified. |
| 02-06 | 2 | ✓ VERIFIED | Native adapter and SwiftUI diagnostic/inspector are wired to the app and tests. |
| 02-07 | 4 | ✓ VERIFIED | Verification entry point, gate verifier, operator procedure, and closed physical schema are substantive. |

## Key Link Verification

| Plan | Links | Status | Details |
|---|---:|---|---|
| 02-01 | 2 | ✓ WIRED | Capture types use canonical digest/wire types; fixture schema identity matches CON-002. |
| 02-02 | 2 | ✓ WIRED | Archive actor calls the filesystem boundary; encoder uses exact wire/payload validation. |
| 02-03 | 3 | ✓ WIRED | Replay validates manifest projections, report self-digest, and runner-to-core execution. |
| 02-04 | 4 | ✓ WIRED | Selector→admission→session and durable receipt→transport links are concrete. |
| 02-05 | 3 | ✓ WIRED | Publisher invokes Swift/Node/Python outputs and the closed comparator. |
| 02-06 | 3 | ✓ WIRED | AR callback→admission→archive and verified report→inspector links are live. |
| 02-07 | 3 | ✓ WIRED | Preflight publication, checklist binding, and five-state schema validation are live. |

## Data-Flow Trace (Level 4)

| Artifact | Data | Source | Produces real data | Status |
|---|---|---|---|---|
| `DiagnosticChecklistView.swift` | `CapturePresentationSnapshot` | AR callback → selector → admission snapshot → `DeviceProofModel` → SwiftUI owner | Yes; simulator tests drive the flow and release wiring is verified | ✓ FLOWING |
| `DiagnosticChecklistView.swift` | `VerifiedReplayInspector.timeline` | filesystem discovery → `CaptureRecovery` → `ReplayCore` → verified report/timeline | Yes; invalid archives become failure snapshots and expose no records | ✓ FLOWING |
| `App.swift` release pressure surface | pressure measurement/status | real camera offer → stalled ordinary writer → bounded admission snapshot → durable local observation | Yes in code/tests; physical execution remains human-needed | ✓ FLOWING |

## Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| Full deterministic Phase 2 matrix | `python3 -c '... run_deterministic_checks("full") ...'` | `PASS 8 checks`: contract/package, lifecycle/crash, recovery/replay, queue/reorder, consent denial, simulator flow, release surface, three-runtime agreement | ✓ PASS |
| Physical gate refuses automation-only evidence | `scripts/verify-phase-02-capture-replay gate` | Exit `2`: `GATE-001 pending: physical observations and human attestation are required` | ✓ PASS (expected pending) |

## Probe Execution

No `scripts/**/tests/probe-*.sh` files are declared. The phase's explicit
verification entry point was exercised through its read-only full-check API to
avoid rewriting checked-in evidence, and the gate mode was executed directly.

## Requirements Coverage

| Requirement | Source Plans | Status | Evidence |
|---|---|---|---|
| FR-CAPTURE-001 | 01, 02, 03, 04, 05, 06, 07 | ✓ SATISFIED (implementation) | Exact lifecycle, wire/image binding, crash matrix, journal projections, recovery, and replay checks pass. Release authorization still depends on GATE-001. |
| FR-B0-001 | 01, 03, 05, 06, 07 | ✓ SATISFIED (Phase 2 core) | Provider-independent exact replay and verified inspector pass; separate web product remains Phase 7. |
| NFR-REPLAY-001 | 01, 04, 05, 06, 07 | ✓ SATISFIED (automated/local) | Queue capacity/drop/order tests and three-runtime agreement pass; physical timing/pressure remains unmeasured. |
| SEC-CONSENT-001 | 01, 02, 06, 07 | ✓ SATISFIED (automated/local) | Per-session authorization, denial no-write behavior, and visible state tests pass; device UX remains in human verification. |

No Phase 2 requirement is orphaned: all four roadmap-mapped IDs appear in plan
frontmatter. The requirement tracking table already labels their implementation
`Complete`; this report does not reinterpret that as gate GREEN.

## Anti-Patterns and Adversarial Review

| File | Pattern | Severity | Assessment |
|---|---|---|---|
| `ReplayReport.swift:64` | Local variable named `placeholder` | ℹ️ Info | Not a stub: it is the required zero-self-digest instance immediately hashed and replaced by the final report. |
| `CaptureRecovery.swift:148-151` | Quarantine and recovered sibling publish in two filesystem moves; the only injected rollback test fires before either move. | ⚠️ Warning | The original interrupted archive stays immutable and no partial recovered archive is accepted, so current roadmap truths remain true. A process crash between the two moves could leave an orphan quarantine that makes retry fail with `publicationConflict`; add a mid-publication recovery test in hardening. |

No `TBD`, `FIXME`, `XXX`, `TODO`, `HACK`, user-visible placeholder, empty
implementation, or console-only implementation was found in the Phase 2
production surfaces.

### Disconfirmation Pass

- **Partially met release evidence:** software and simulator evidence are
  complete, but the new-revision signed-device pressure/recovery matrix is not.
- **Potentially misleading green test:** the passing simulator/release-surface
  tests prove UI wiring and fail-closed labels, not physical camera, signing,
  termination, storage, or thermal behavior.
- **Uncovered error path:** recovery publication is tested before the first
  publish move but not for a process crash between quarantine and recovered
  sibling renames. This is a hardening warning, not evidence of accepted-record
  corruption.

## Human Verification Required

### 1. Signed-device GATE-001 evidence

**Test:** On the bound new revision, perform the sprint smoke and retain its
external evidence; before a full P0 claim, run consent denial and both physical
durations after each of the five canonical states, with queue pressure/network
blackhole, exact recovery, two replays, and human attestation.

**Expected:** The sprint may claim device-smoke verification only after the
smoke is recorded. GATE-001 becomes GREEN only when the closed physical record
and human-bound report pass; otherwise it remains PENDING or RED and live
providers stay blocked.

**Why human:** Host and simulator automation cannot supply physical camera,
signing, SIGKILL timing, storage/queue observation, or attestation.

### 2. Twelve unresolved prohibitions

Each plan prohibition is intentionally descriptor-less/unresolved. A
non-authoritative LLM review found no contrary code or evidence, but none is
silently green:

| # | Prohibition (condensed) | Non-authoritative review | Disposition |
|---|---|---|---|
| 1 | No network/ack/queue authority for local durability/replay. | No violation found. | Human review required |
| 2 | No provider/network output in deterministic replay oracle. | No violation found. | Human review required |
| 3 | No pre-journal frame exposure/enqueue/ack. | No violation found. | Human review required |
| 4 | No pre-consent bytes or cross-session consent reuse. | No violation found. | Human review required |
| 5 | No replay exposure beyond valid contiguous prefix. | No violation found. | Human review required |
| 6 | No timestamp/array/directory/provider repair of journal order. | No violation found. | Human review required |
| 7 | No live drop/cancel/pause/completion mutation of durable order. | No violation found. | Human review required |
| 8 | No copied/normalized/cross-fed runtime agreement. | No violation found. | Human review required |
| 9 | No upload/share success conflation or hidden paused/offline/recovered state. | No violation found. | Human review required |
| 10 | No inspector exposure of unverified archive records. | No violation found. | Human review required |
| 11 | No synthetic/simulator/inferred result labeled physical MEASURED. | No violation found. | Human review required |
| 12 | No raw/private/device/signing/account material committed as gate evidence. | No violation found. | Human review required |

## Gaps Summary

No automated/local software gap blocks the approved demo-sprint sequencing.
The status is `human_needed` because physical GATE-001 evidence and the 12
judgment-tier prohibitions are deliberately unresolved. The sprint overlay is
therefore honored exactly: implementation and automation may be called complete
for this slice; GATE-001 and full P0 remain pending.

---

_Verified: 2026-07-18T12:53:58Z_
_Verifier: the agent (gsd-verifier generic-agent workaround)_
