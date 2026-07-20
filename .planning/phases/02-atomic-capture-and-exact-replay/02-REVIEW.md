---
phase: 02-atomic-capture-and-exact-replay
reviewed: 2026-07-19T10:01:26Z
depth: deep
files_reviewed: 47
files_reviewed_list:
  - evidence/capture/phase-02/automated-preflight.json
  - evidence/compatibility/replay-agreement.json
  - evidence/templates/gate-001-operator-procedure.md
  - evidence/templates/gate-001-physical-observations.schema.json
  - fixtures/capture/1.0.0/rev-001/archives/
  - fixtures/capture/1.0.0/rev-001/manifest.json
  - fixtures/replay-report.schema.json
  - ios/Packages/ReRoomContracts/Package.swift
  - ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/BoundedLatestQueue.swift
  - ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/CaptureAdmission.swift
  - ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/CaptureArchiveStore.swift
  - ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/CaptureFileSystem.swift
  - ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/CaptureRecovery.swift
  - ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/CaptureSession.swift
  - ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/CaptureTransport.swift
  - ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/FramePacketEncoder.swift
  - ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/FrameSelectionPolicy.swift
  - ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/ReplayCore.swift
  - ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/ReplayReport.swift
  - ios/Packages/ReRoomContracts/Sources/ReRoomContracts/FrozenSchemaValidator.swift
  - ios/Packages/ReRoomContracts/Sources/ReRoomReplayRunner/main.swift
  - ios/Packages/ReRoomContracts/Tests/ReRoomCaptureCoreTests/BoundedQueueTests.swift
  - ios/Packages/ReRoomContracts/Tests/ReRoomCaptureCoreTests/CaptureAdmissionTests.swift
  - ios/Packages/ReRoomContracts/Tests/ReRoomCaptureCoreTests/CaptureCoreContractTests.swift
  - ios/Packages/ReRoomContracts/Tests/ReRoomCaptureCoreTests/CaptureCrashMatrixTests.swift
  - ios/Packages/ReRoomContracts/Tests/ReRoomCaptureCoreTests/CaptureLifecycleTests.swift
  - ios/Packages/ReRoomContracts/Tests/ReRoomCaptureCoreTests/CaptureRecoveryTests.swift
  - ios/Packages/ReRoomContracts/Tests/ReRoomCaptureCoreTests/FrameSelectionTests.swift
  - ios/Packages/ReRoomContracts/Tests/ReRoomCaptureCoreTests/ReplayCoreTests.swift
  - ios/Packages/ReRoomContracts/Tests/ReRoomReplayRunnerTests/ReplayRunnerTests.swift
  - ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj/project.pbxproj
  - ios/ReRoomDeviceProof/ReRoomDeviceProof/App.swift
  - ios/ReRoomDeviceProof/ReRoomDeviceProof/CaptureSessionAdapter.swift
  - ios/ReRoomDeviceProof/ReRoomDeviceProof/DeviceProofModel.swift
  - ios/ReRoomDeviceProof/ReRoomDeviceProof/DiagnosticChecklistView.swift
  - ios/ReRoomDeviceProof/ReRoomDeviceProofTests/CaptureSessionAdapterTests.swift
  - ios/ReRoomDeviceProof/ReRoomDeviceProofUITests/DiagnosticSurfaceTests.swift
  - scripts/run-phase-02-replay-agreement
  - scripts/verify-reroom-release-surface
  - tools/javascript/src/replay.ts
  - tools/javascript/test/replay.test.mjs
  - tools/python/reroom_verify/replay.py
  - tools/python/tests/test_replay.py
  - tools/verify/compare_replay_reports.py
  - tools/verify/tests/test_phase_02_fixtures.py
  - tools/verify/tests/test_replay_agreement.py
  - tools/verify/verify_phase_02_gate.py
findings:
  critical: 12
  warning: 8
  info: 0
  total: 20
status: issues_found
---

# Phase 02 Code Review Report

**Reviewed:** 2026-07-19T10:01:26Z
**Depth:** deep
**Files Reviewed:** 47
**Status:** issues_found

## Summary

Phase 02 has a substantial working base: all 149 Swift package tests passed, the focused Python and Node suites passed, fixture archives are small sanitized images rather than room data, and the checked-in gate remains pending rather than falsely claiming current physical GREEN evidence. The earlier Xcode “Missing package product” failure is also not reproducible in the present workspace: both local package products resolve.

It is not yet an enterprise-quality capture/replay trust boundary. Twelve BLOCKER-class issues remain. The most consequential are that recovery does not validate the frozen contracts, a crash can cause recovery to discard a physically fsynced journal record, concurrent recovery publishers can delete a successful archive, the app fabricates canonical server acknowledgements from a no-network fixture, its AR world epoch is disconnected from capture, and its interruption finalizer is not connected to app lifecycle. The evidence side also overstates runtime independence, records synthetic pressure facts as observations, and can accept a self-consistent but untrusted GREEN evidence bundle without a trusted build/operator/artifact root.

The committed test suite therefore proves important local properties, but it does not prove the current source tree or the canonical GATE-001 claims. `scripts/run-phase-02-replay-agreement --verify-evidence` currently fails because the recorded source binding is stale.

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-01: Checked-in replay and preflight evidence do not describe the current implementation

**Severity:** BLOCKER
**File:** `evidence/compatibility/replay-agreement.json:124-164`; `evidence/capture/phase-02/automated-preflight.json:1`

**Issue:** The replay agreement binds revision `git:25fc361...` and a `Package.swift` digest of `19652e...`; the current HEAD is `a2fc773...`, and the current package manifest digest is `309990...`. The minified automated preflight binds a different older revision, `git:47f4816...`, while embedding the stale replay agreement. The normal evidence verifier rejects this state with `bound implementation sources differ from their recorded revision`. This means neither artifact can support a quality claim about the code now in the repository.

**Fix:** Close the implementation scope only after the candidate is frozen, regenerate the 16-case agreement from that exact revision, run the full preflight on the same exact signed candidate, and publish both artifacts as one immutable generation. Verification must fail before reading verdicts whenever HEAD, the selected SwiftPM manifest, any bound source, or the build artifact differs. Never repair these bindings by editing hashes manually.

### CR-02: The advertised 16-case three-runtime agreement is not three independent evaluations

**Severity:** BLOCKER
**File:** `ios/Packages/ReRoomContracts/Sources/ReRoomReplayRunner/main.swift:255-325`; `tools/javascript/src/replay.ts:492-588,696-718`; `tools/python/reroom_verify/replay.py:689-744,865-882`; `tools/verify/compare_replay_reports.py:291-340`; `fixtures/replay-report.schema.json:1`

**Issue:** Swift genuinely replays the three archive cases, but for all twelve edge probes it ignores each probe input, selects one of two baseline archive snapshots, and copies `expected.verdict`/`expected.rejection_class` directly into the report. Its consent case is also copied from the expected fixture. Node and Python evaluate the twelve probe inputs, but both hard-code the consent outcome. The comparator then maps every non-archive case back to a baseline archive and checks only the expected verdict/rejection plus that unrelated baseline snapshot. The report schema has no case-specific computed result capable of proving, for example, the two-frame adjacency input. Thus “16 reports from each runtime” is true as a file count, while only three archive cases are independently executed in all three runtimes and the consent denial is independently executed in none.

**Fix:** Implement an independent Swift probe evaluator; execute consent admission through real capture logic in all three runtimes; add a closed, case-specific result object to the report schema; and compare every computed output, not just verdict labels. Add mutated-input tests that keep the expected oracle unchanged and require each runtime to disagree/fail. Retain actual archive mutations for schema, digest, ordering, consent, and lifecycle cases instead of attaching a baseline archive to an abstract probe.

### CR-03: Recovery and replay accept self-consistent archives that violate CON-001/CON-002

**Severity:** BLOCKER
**File:** `ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/CaptureRecovery.swift:56-59,415-495,531-637`; `ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/ReplayCore.swift:30-39`

**Issue:** `CaptureRecovery.verifiedArchive` routes untrusted archives through `RecoveryArchiveReader`, a hand-written partial validator. It validates selected keys and digests but never invokes the pinned `ContractValidator` for either the manifest or each FramePacket. It does not validate the manifest privacy object (including `consent_granted == true`), the full event type/payload semantics, ID patterns, the complete packet shape, capture/world/session bindings, or all numeric/transform constraints. Because `ReplayCore` trusts this result, an attacker can change a contract-constrained value such as manifest consent, recompute the self-digests, and expose an archive that the frozen schema rejects.

**Fix:** Inject the pinned frozen-schema validator into recovery. Validate the complete manifest bytes and every exact packet byte sequence before exposing any record, then enforce cross-record session, world epoch/version, sequence, lifecycle, image, journal, and idempotency bindings. Add rehashed adversarial fixtures for false consent, invalid IDs/event types, unknown packet properties, session/world mismatch, sequence inversion, and invalid RR-FLOAT/transform values.

### CR-04: Recovery can discard a physically fsynced, hash-valid journal record

**Severity:** BLOCKER
**File:** `ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/CaptureArchiveStore.swift:247-352,571-660`; `ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/CaptureRecovery.swift:181-233`; `ios/Packages/ReRoomContracts/Tests/ReRoomCaptureCoreTests/CaptureCrashMatrixTests.swift:275-350,687-815`

**Issue:** The writer appends and fsyncs each journal record before a later open-manifest replacement. A crash after the frame journal append at lines 304-312 but before the projection/manifest update leaves a physically durable, contiguous, hash-valid frame reference that is absent from the stale manifest projection. Recovery compares the physical journal only to the manifest's `expected` array and treats the first record beyond `expected.count` as an invalid suffix. It therefore truncates a journaled frame even though the journal is the canonical replay authority. The crash matrix expects that record to survive, but verifies it with its own `scanDurablePrefix` implementation rather than the production `CaptureRecovery` path, so the mismatch is not caught.

**Fix:** Make the journal records self-sufficient enough to reconstruct projections, and recover from the last physical hash-valid contiguous prefix rather than from a stale manifest copy. An alternative is a generation/pointer protocol that atomically publishes the journal and projection as one recoverable generation. Run every existing fault boundary through production `CaptureRecovery` and assert the recovered prefix equals the crash matrix's physically durable prefix.

### CR-05: A no-network fixture is persisted as canonical `server_acknowledged`

**Severity:** BLOCKER for product/enterprise promotion
**File:** `ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/CaptureTransport.swift:22-49`; `ios/ReRoomDeviceProof/ReRoomDeviceProof/CaptureSessionAdapter.swift:345-364,535-553`; `ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/CaptureArchiveStore.swift:362-408`; `ios/ReRoomDeviceProof/ReRoomDeviceProof/App.swift:523-526,567-572`; `evidence/templates/gate-001-operator-procedure.md:20-40`

**Issue:** `CaptureTransport` explicitly performs no network operation. The live adapter nevertheless creates that fixture, immediately generates a local acknowledgement after publication, and records the canonical `frame_server_acknowledged` event with `serverAcknowledged=true`. The UI simultaneously and correctly says no upload is configured. Phase 02 intentionally called for an echo/blackhole/reorder fixture, so the fixture itself is not the defect; the defect is that synthetic provenance is indistinguishable in the canonical archive from a server-originated acknowledgement. The physical procedure then asks the operator to terminate at canonical `server_acknowledged` while acknowledging that the “server” event is only internal.

**Fix:** Keep the fixture path test-only or encode it in a separate synthetic state/event namespace that cannot satisfy canonical server acknowledgement or GATE-001. Product code must append `server_acknowledged` only after a bounded post-durability uploader receives and validates an authenticated gateway response bound to session, frame, idempotency key, packet digest, and accepted sequence. If a real server is intentionally out of scope, the human authority must change the gate requirement rather than relabel the fixture.

### CR-06: Capture does not use the app's ARKit world-epoch authority

**Severity:** BLOCKER
**File:** `ios/ReRoomDeviceProof/ReRoomDeviceProof/DiagnosticChecklistView.swift:335-372,498-509,738-745`; `ios/ReRoomDeviceProof/ReRoomDeviceProof/CaptureSessionAdapter.swift:486-500,852-880`; `ios/ReRoomDeviceProof/ReRoomDeviceProof/DeviceProofModel.swift:268-287`

**Issue:** The diagnostic surface owns a `WorldEpochController` and advances/quarantines it on reset, but capture independently creates a different random world-frame ID at session start and hard-codes `worldFrameVersion: 1` for every FramePacket. The ARFrame offer path has no epoch descriptor or quarantine gate, and capture remains enabled across the diagnostic reset. A reset or relocalization can therefore place pre- and post-reset poses in one apparently stable capture world, violating RR-COORD-1 and making replayed geometry semantically unsafe even when all hashes match.

**Fix:** Establish one ARKit world-epoch authority. Each offered ARFrame must carry its immutable `(world_frame_id, world_frame_version)` descriptor; reset/relocalization must close admission, abort or drain queued old-epoch work, and only reopen after a validated reseed/correction. Add tests for reset with queued and in-flight frames, stale-epoch rejection, and epoch transition evidence.

### CR-07: GATE-001 queue/network observations are synthesized rather than measured

**Severity:** BLOCKER
**File:** `ios/ReRoomDeviceProof/ReRoomDeviceProof/App.swift:77-95,99-177,318-367,584-591`; `evidence/templates/gate-001-physical-observations.schema.json:164-175,225-232`; `tools/verify/verify_phase_02_gate.py:205-239`

**Issue:** `Gate001PressureMeasurement` derives only capacity counters from the admission snapshot, then hard-codes `staleDropCount = 0`, `networkBlackholed = true`, and `uploadPausedFirst = true`. No production `BoundedLatestQueue` or network transport is connected, and the active transport actually echoes a local acknowledgement. The physical schema permits zero depth/zero stale drops and requires only assertion booleans; the semantic verifier checks depth does not exceed capacity and that those booleans are true. A final snapshot can therefore be recorded as proof of a chronological pressure/blackhole/pause sequence that was never observed.

**Fix:** Emit a timestamped, append-only trace from the real post-durability queue and transport. Derive capacity, maximum depth, drops, pause transition, blackhole interval, and resumed state from that trace; bind its digest to the run. Represent “transport not configured” separately from “network blackholed.” Require a meaningful pressure exercise (offers, positive occupancy/capacity interaction, and ordered pause evidence), and verify two replay executions by input/output artifact digests rather than by two opaque IDs alone.

### CR-08: The GREEN gate has no trusted build, operator, or raw-artifact root

**Severity:** BLOCKER
**File:** `tools/verify/verify_phase_02_gate.py:279-379,715-761`; `evidence/templates/gate-001-physical-observations.schema.json:109-131,144-175`; `evidence/templates/gate-001-operator-procedure.md:55-73`

**Issue:** Gate mode validates shapes, literal PASS/true values, revision/hash syntax, cross-document equality, and self-digests. It does not rerun the preflight, recompute the declared source tree, verify the signed app artifact/CDHash, validate a cryptographic operator signature against a pinned authority, or retrieve and hash the externally retained raw artifacts. Consequently a locally constructed, internally consistent JSON bundle can satisfy the same checks as physical evidence. Self-digests prove only that the JSON was not changed after its creator computed the digest; they do not prove who created it, what binary ran, or that the referenced phone artifacts exist.

**Fix:** Make GREEN consume trusted attestations: a CI-signed preflight tied to an immutable source/build artifact, an XCArchive/IPA identity and CDHash, cryptographic operator/evaluator signatures against pinned public keys or an authenticated evidence service, and verifiable raw-artifact object identities/digests. Gate mode should either rerun applicable checks on the exact candidate or verify a signed attestation that did so. Keep the current schema validation as defense in depth, not as the trust root.

### CR-09: Reentrant adapter operations can duplicate sessions/finalization and wedge failed captures

**Severity:** BLOCKER
**File:** `ios/ReRoomDeviceProof/ReRoomDeviceProof/CaptureSessionAdapter.swift:486-575,684-749,786-840`; `ios/ReRoomDeviceProof/ReRoomDeviceProofTests/CaptureSessionAdapterTests.swift:326-375`

**Issue:** `acceptDisclosure` checks idle ownership, then awaits archive creation and session start before publishing a `.starting` state or claiming ownership. Because it is `@MainActor`, another task can reenter during either await and start a second archive; the later completion overwrites the first task/resources. `stop` and `finalizeForBackground` likewise have independent guards and no one-shot terminal task, so concurrent calls can both consume/finalize the same writer and overwrite the terminal presentation. On asynchronous writer failure, `recordConsumerOutcome` changes the UI to failed/recovered but leaves `consumerTask`, gate, archive, and queued payload storage owned; a subsequent start is silently rejected. The test masks this by explicitly calling `stop()` after the failure.

**Fix:** Replace the loose optionals with an explicit state machine (`idle`, `starting`, `recording`, `finalizing`, `terminal`) and claim each transition before the first await. Own finalization through one shared task/token so duplicate stop/background/interruption calls await the same result. On writer failure, close the gate, remove every queued image payload, release ownership, preserve only durable archive state, and permit a fresh start. Add concurrent start/stop/background tests and a writer-failure-then-restart test.

### CR-10: App background/interruption finalization is implemented but never connected

**Severity:** BLOCKER
**File:** `ios/ReRoomDeviceProof/ReRoomDeviceProof/App.swift:201-233`; `ios/ReRoomDeviceProof/ReRoomDeviceProof/DeviceProofModel.swift:290-303`; `ios/ReRoomDeviceProof/ReRoomDeviceProof/CaptureSessionAdapter.swift:709-749`; `ios/ReRoomDeviceProof/ReRoomDeviceProofTests/CaptureSessionAdapterTests.swift:294-324`

**Issue:** The adapter has background/interruption finalization and the model forwards it, but no production caller invokes it. `ReRoomDeviceProofApp` does not observe `scenePhase`, and no AR session interruption/failure notification routes to the method. The unit test succeeds only because it invokes the adapter directly. In the actual app, backgrounding can leave an open capture without the required immediate finalize/drain/abort sequence.

**Fix:** Connect app `scenePhase`, ARSession interruption, tracking failure, and background-expiration events to the single serialized terminal operation from CR-09. Add an integration/UI lifecycle test that backgrounds while a write is queued/in flight and proves either finalized output or exactly the last durable prefix after expiration.

### CR-11: Arbitrary live recoveries are mislabeled as the frozen replay fixture

**Severity:** BLOCKER
**File:** `ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/ReplayReport.swift:26-63`; `ios/ReRoomDeviceProof/ReRoomDeviceProof/CaptureSessionAdapter.swift:368-424`; `ios/ReRoomDeviceProof/ReRoomDeviceProof/App.swift:656-665`

**Issue:** `ReplayReport.make` hard-codes fixture ID `FX-CAPTURE-001`, revision `rev-001`, zero queue metrics, and a synthetic suffix count. The app recursively discovers arbitrary user-created `.rrcap` archives, verifies one, and passes the frozen fixture manifest digest into this report factory. The UI then displays “Verified replay.” The hash verification may be real, but its claimed fixture provenance and metrics are false; a live capture was never a member of the frozen fixture set.

**Fix:** Separate a generic live `VerifiedArchiveResult` from the evidence-only `ReplayReport`. A fixture report may be issued only after exact membership in the pinned fixture manifest is proven. A live result must bind the actual archive/session/build identity and measured recovery metrics, and the UI must distinguish “archive integrity verified” from “frozen cross-runtime fixture agreement verified.”

### CR-12: Recovery publication can delete a concurrent winner and is not crash-atomic

**Severity:** BLOCKER
**File:** `ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/CaptureRecovery.swift:66-109,135-178`

**Issue:** Recovery publishes quarantine and archive via two sequential renames. A process death after the quarantine rename leaves a permanent half-publication that the next run treats as a conflict. More severely, two concurrent recoveries can both stage, one publish successfully, and the loser fail the existence guard; the loser's unconditional deferred cleanup then sees `publishedArchive == false` and removes the winner's destination. The rename/copy sequence also lacks a durable parent-generation commit point.

**Fix:** Publish one immutable generation directory and atomically replace a pointer/manifest last, with directory fsyncs at each durability boundary. Cleanup must remove only staging paths owned by the current operation and never a pre-existing destination. Add process-death fault injection before/after each rename/fsync and a two-publisher race proving one winner remains readable and repeat recovery is idempotent.

## Warnings

### WR-01: `offerARFrame` materializes image bytes before checking capture-session consent/state

**File:** `ios/ReRoomDeviceProof/ReRoomDeviceProof/CaptureSessionAdapter.swift:579-623`; `ios/ReRoomDeviceProof/ReRoomDeviceProofTests/CaptureSessionAdapterTests.swift:164-197`

**Issue:** The AR callback calls the frame snapshotter/JPEG encoder before `offerCapturedFrame` checks that the adapter is recording with a consented session. Denied/idle calls do not persist an archive, but they still create a room-image copy in memory. The consent test proves no archive factory/start call; it does not prove that the snapshotter was never invoked.

**Fix:** Check active consent/session/epoch admission before snapshotting, then recheck the session token before enqueueing. Add a spy snapshotter and assert zero invocations while denied, idle, starting, finalizing, interrupted, or failed.

### WR-02: The ID validator rejects schema-permitted UUIDv7 identifiers

**File:** `ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/CaptureSession.swift:678-690`

**Issue:** `requireID` hard-codes UUID version nibble `4`, while the frozen ID schemas permit version 4 or 7. A contract-valid v7 session/frame/world/submap/etc. ID is therefore rejected by core capture logic.

**Fix:** Accept the exact schema-owned `[47]` version set and add v4/v7 positive vectors plus invalid-version/variant negatives for every capture ID family.

### WR-03: The writer does not enforce strictly increasing packet `capture_sequence`

**File:** `ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/CaptureArchiveStore.swift:247-276`; `ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/FramePacketEncoder.swift:216-224`; `ios/Packages/ReRoomContracts/Tests/ReRoomCaptureCoreTests/CaptureCrashMatrixTests.swift:177-207`

**Issue:** The contract says `capture_sequence` is strictly increasing, but the store accepts the caller's value without comparing it to the last durable packet. Concurrent-writer tests verify actor-owned accepted/journal sequences, not the embedded packet sequence, so reversed or duplicate caller values remain possible. The encoder also always emits a null `previous_durable_frame_id`, preventing that optional integrity link from being useful.

**Fix:** Allocate capture sequence in the sole writer, or reject any value not greater than the previous durable value. Pass the prior durable frame identity when applicable, validate both during recovery, and add reversed/duplicate/concurrent input tests.

### WR-04: Existing quarantine metadata is trusted without verifying the suffix artifact

**File:** `ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/CaptureRecovery.swift:165-178`; `ios/Packages/ReRoomContracts/Tests/ReRoomCaptureCoreTests/CaptureRecoveryTests.swift:136-151`

**Issue:** Repeat recovery reads `metadata.json` and returns its stated suffix digest/sequence without bounded-reading `invalid-suffix.bin`, checking its byte length/digest, or binding it to the source archive/session. Missing or modified quarantine bytes can therefore retain a “verified” metadata result. The repeated-recovery test only checks unchanged snapshots.

**Fix:** Require a bounded regular non-symlink suffix file, recompute length/SHA-256, and bind metadata to source archive/session/manifest. Add missing, tampered, swapped, symlink, and oversized suffix tests.

### WR-05: Recovery discovery can double-count one session and chooses “latest” nondeterministically

**File:** `ios/ReRoomDeviceProof/ReRoomDeviceProof/CaptureSessionAdapter.swift:368-424,751-763`

**Issue:** Recursive discovery scans both an original open archive and its generated `.recovered-prefix.rrcap`; inspecting the original redirects to the recovered sibling, then the sibling is verified again. Results are sorted only by `lastPathComponent`, so duplicate names in different directories have no contract-owned ordering, yet `.last` is presented as the latest.

**Fix:** Canonicalize each final recovered URL, deduplicate by stable `(session_id, manifest_sha256)`, and sort by a contract-owned creation/finalization sequence or timestamp with a deterministic tiebreaker. Test discovery on a second launch after recovery publication.

### WR-06: Raw cross-runtime reports are discarded, weakening later auditability

**File:** `scripts/run-phase-02-replay-agreement:650-735`; `evidence/compatibility/replay-agreement.json:174-189`

**Issue:** Published evidence retains only runtime report counts, byte totals, and directory digests; the 48 individual reports are temporary. A later reviewer cannot independently inspect or revalidate the exact bytes behind the summary, and Node/Python tests share expected values from the same fixture, increasing common-mode oracle risk.

**Fix:** Retain the closed-schema raw report generation as an immutable CI/evidence artifact, bind every file hash in a signed generation manifest, and add separately authored negative/mutation or property tests that do not consume the same expected verdict fields as the runners.

### WR-07: Live frame selection feeds fabricated perfect quality/novelty scores

**File:** `ios/ReRoomDeviceProof/ReRoomDeviceProof/DeviceProofModel.swift:268-285`; `ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/FrameSelectionPolicy.swift:67-80`

**Issue:** Every live ARFrame is offered with `motionScore=0`, `blurScore=1`, `exposureScore=1`, and `viewNovelty=1`. The selection policy treats these as real signals, so the device path cannot demonstrate its intended quality/novelty behavior and may select redundant or poor frames under a false “perfect” score.

**Fix:** Compute and label measured signals with calibrated ranges, or omit quality-based admission until those measurements exist and use only explicit/interval selection. Preserve raw metric provenance in diagnostics and add device-vector tests around each threshold.

### WR-08: Diagnostic capture setup failure silently falls back to an inert idle model

**File:** `ios/ReRoomDeviceProof/ReRoomDeviceProof/DiagnosticChecklistView.swift:536-589`; `ios/ReRoomDeviceProof/ReRoomDeviceProof/DeviceProofModel.swift:147-165,258-312`

**Issue:** If live model/schema setup throws, the diagnostic factory returns a default `DeviceProofModel` with no capture adapter. Optional calls then no-op and the UI can appear idle rather than explicitly unavailable. This can waste a physical run or hide a missing/corrupt frozen-schema resource. The release owner has a more explicit error path; this warning applies to the diagnostic surface.

**Fix:** Represent initialization as a typed unavailable/failed state with the failing dependency class, disable capture controls, and require a UI test for a missing or digest-mismatched schema resource.

## Worktree and Xcode Scope Note

The audited Swift/package implementation is committed at HEAD. The current uncommitted `project.pbxproj`/scheme changes are separate user-generated Xcode repair/signing changes, not Phase 02 source behavior. They resolve the local package-product graph in this workspace, but `project.pbxproj` also contains personal development team `ZP2PFF43D2` in six build configurations (`451,476,505,528,592,614`). Do not commit that team value as shared project authority; move developer signing to local/CI configuration. The other observed project delta is Xcode quoting/comment normalization, and the scheme delta is formatting plus removal of an explicit UI-test `parallelizable="NO"` attribute.

The earlier missing-product error is disconfirmed in the current workspace: `Package.swift` declares both products, the project carries the local package reference, `plutil -lint` passes, and `xcodebuild -list` resolves and lists the package schemes.

## Verification

- `swift test --package-path ios/Packages/ReRoomContracts` — 149 tests in 24 suites passed. The run generated untracked `.build/`; it was left in place because the workspace is shared.
- Phase 02 Python fixture/gate checks — 33 tests passed. `python3 -m unittest tools.verify.tests.test_replay_agreement` separately produced 9 passes and 1 error because its actual-publication case correctly encountered the stale current-source binding in CR-01.
- Node replay tests — 4/4 passed.
- `scripts/run-phase-02-replay-agreement --verify-evidence` — failed: bound implementation sources differ from their recorded revision (CR-01).
- The current GATE-001 command remains pending/nonzero because physical observations and human attestation are not checked in; no current GREEN claim was found.
- Fixture inspection found only sanitized tiny PNG payloads, not raw room imagery.
- No product source/evidence file was edited by this review. Only this review artifact was added; pre-existing planning, user Xcode, workspace, SwiftPM, and generated-build state was preserved.

## Recommended Closure Order

1. Repair the trust boundary first: CR-03, CR-04, and CR-12.
2. Make the app lifecycle and spatial authority correct: CR-06, CR-09, and CR-10.
3. Separate all synthetic fixture provenance from product/server/physical claims: CR-05, CR-07, CR-08, and CR-11.
4. Make the three-runtime cases genuinely independent (CR-02), then regenerate evidence only after every behavior-bearing source is frozen (CR-01).
5. Close the warnings and rerun the full automated suite, adversarial mutation suite, simulator UI suite, signed-device matrix, and two independently retained replays before considering GATE-001 GREEN.

---

_Reviewed: 2026-07-19T10:01:26Z_
_Reviewer: Codex (generic-agent workaround following gsd-code-reviewer contract)_
_Depth: deep_
