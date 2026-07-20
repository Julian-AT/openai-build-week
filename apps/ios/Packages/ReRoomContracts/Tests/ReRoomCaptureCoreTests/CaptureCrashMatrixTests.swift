import Foundation
import ReRoomContracts
import Testing

@testable import ReRoomCaptureCore

@Suite("CaptureCrashMatrixTests")
struct CaptureCrashMatrixTests {
    @Test(
        "every explicit operation fault leaves a hash-valid contiguous prefix",
        arguments: CaptureFaultCase.cases
    )
    private func operationFaultMatrix(testCase: CaptureFaultCase) async throws {
        let fixture = try CrashMatrixFixture(sessionOrdinal: testCase.sessionOrdinal)
        defer { fixture.remove() }

        var immutablePrefix: ImmutablePrefix?
        switch testCase.workflow {
        case .start:
            fixture.faults.arm(testCase.target)
            await #expect(throws: InjectedCaptureOperationFault.self) {
                _ = try await fixture.store.startSession(authorization: fixture.authorization)
            }
        case .firstFrame:
            _ = try await fixture.store.startSession(authorization: fixture.authorization)
            fixture.faults.arm(testCase.target)
            await #expect(throws: InjectedCaptureOperationFault.self) {
                _ = try await fixture.store.publishSelectedFrame(fixture.candidate(ordinal: 1))
            }
        case .laterFrame:
            _ = try await fixture.store.startSession(authorization: fixture.authorization)
            _ = try await fixture.store.publishSelectedFrame(fixture.candidate(ordinal: 1))
            immutablePrefix = try fixture.immutableFirstFramePrefix()
            fixture.faults.arm(testCase.target)
            await #expect(throws: InjectedCaptureOperationFault.self) {
                _ = try await fixture.store.publishSelectedFrame(fixture.candidate(ordinal: 2))
            }
        case .acknowledgement:
            _ = try await fixture.store.startSession(authorization: fixture.authorization)
            let receipt = try await fixture.store.publishSelectedFrame(fixture.candidate(ordinal: 1))
            fixture.faults.arm(testCase.target)
            await #expect(throws: InjectedCaptureOperationFault.self) {
                try await fixture.store.recordAcknowledgement(
                    fixture.acknowledgement(for: receipt)
                )
            }
        case .emptyFinalization:
            _ = try await fixture.store.startSession(authorization: fixture.authorization)
            fixture.faults.arm(testCase.target)
            await #expect(throws: InjectedCaptureOperationFault.self) {
                _ = try await fixture.store.finalizeExplicitly()
            }
        case .frameFinalization:
            _ = try await fixture.store.startSession(authorization: fixture.authorization)
            _ = try await fixture.store.publishSelectedFrame(fixture.candidate(ordinal: 1))
            fixture.faults.arm(testCase.target)
            await #expect(throws: InjectedCaptureOperationFault.self) {
                _ = try await fixture.store.finalizeExplicitly()
            }
        }

        #expect(fixture.faults.didFire)
        try fixture.assertProductionRecovery(testCase)

        if let immutablePrefix {
            try fixture.assertFirstFramePrefixUnchanged(immutablePrefix)
        }
    }

    @Test(
        "each exact lifecycle boundary publishes a replayable open manifest",
        arguments: LifecycleRecoveryCase.cases
    )
    private func exactLifecycleRecovery(testCase: LifecycleRecoveryCase) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("reroom-lifecycle-recovery-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root
            .appendingPathComponent("archives", isDirectory: true)
            .appendingPathComponent("\(CrashIDs.session(testCase.sessionOrdinal)).rrcap")
        let probe = LifecycleRecoveryProbe(
            target: testCase.state,
            sourceURL: sourceURL,
            recovery: CaptureRecovery(
                verifier: ArchiveVerifier(validator: try CrashSchemas.validator())
            )
        )
        let faults = CaptureOperationFaultController()
        let fileSystem = try FoundationCaptureFileSystem(
            root: root,
            observe: faults.observeBefore,
            afterOperation: faults.observeAfter
        )
        let fixture = try CrashMatrixFixture(
            sessionOrdinal: testCase.sessionOrdinal,
            fileSystem: fileSystem,
            faults: faults,
            root: root,
            lifecycleObserver: probe.observe
        )
        defer { fixture.remove() }

        _ = try await fixture.store.startSession(authorization: fixture.authorization)
        let receipt = try await fixture.store.publishSelectedFrame(fixture.candidate(ordinal: 1))
        if testCase.state == .serverAcknowledged {
            try await fixture.store.recordAcknowledgement(fixture.acknowledgement(for: receipt))
        }

        let result = probe.snapshot()
        #expect(result.didObserve)
        #expect(result.failure == nil)
        #expect(result.recovered?.finalization.state == .recoveredPrefix)
        #expect(result.recovered?.acceptedJournalRecordCount == testCase.journalCount)
        #expect(result.recovered?.finalization.acceptedFrameCount == testCase.frameCount)
        #expect(result.recovered?.finalization.eventCount == testCase.eventCount)
    }

    @Test("journaled recovery accepts the live JPEG capture profile")
    private func journaledRecoveryAcceptsJPEG() async throws {
        let sessionOrdinal = 206
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("reroom-lifecycle-recovery-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root
            .appendingPathComponent("archives", isDirectory: true)
            .appendingPathComponent("\(CrashIDs.session(sessionOrdinal)).rrcap")
        let probe = LifecycleRecoveryProbe(
            target: .journaled,
            sourceURL: sourceURL,
            recovery: CaptureRecovery(
                verifier: ArchiveVerifier(validator: try CrashSchemas.validator())
            )
        )
        let faults = CaptureOperationFaultController()
        let fileSystem = try FoundationCaptureFileSystem(
            root: root,
            observe: faults.observeBefore,
            afterOperation: faults.observeAfter
        )
        let jpegProfile = try FramePacketEncodingProfile(
            codec: "jpeg",
            width: 1,
            height: 1,
            colorSpace: "srgb",
            imageRange: "full",
            cropInSensorPixels: [0, 0, 1, 1],
            intrinsicsEncodedPixels: [1, 1, 0.5, 0.5],
            encodedFromSensor: [1, 0, 0, 0, 1, 0, 0, 0, 1],
            worldFromCamera: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
            trackingState: "normal",
            trackingReason: "none",
            motionScore: 0,
            blurScore: 1,
            exposureScore: 1
        )
        let fixture = try CrashMatrixFixture(
            sessionOrdinal: sessionOrdinal,
            fileSystem: fileSystem,
            faults: faults,
            root: root,
            lifecycleObserver: probe.observe,
            encodingProfile: jpegProfile,
            imageFileExtension: "jpg",
            imageBytes: Data([0xff, 0xd8, 0xff, 0xd9])
        )
        defer { fixture.remove() }

        _ = try await fixture.store.startSession(authorization: fixture.authorization)
        _ = try await fixture.store.publishSelectedFrame(fixture.candidate(ordinal: 1))

        let result = probe.snapshot()
        #expect(result.didObserve)
        #expect(result.failure == nil)
        #expect(result.recovered?.finalization.state == .recoveredPrefix)
        #expect(result.recovered?.acceptedJournalRecordCount == 5)
        #expect(result.recovered?.finalization.acceptedFrameCount == 1)
        #expect(result.recovered?.finalization.eventCount == 4)
    }

    @Test("concurrent publishers receive unique monotonic actor-owned sequences")
    func concurrentPublishersAreSerializedByTheWriter() async throws {
        let fixture = try CrashMatrixFixture(sessionOrdinal: 80)
        defer { fixture.remove() }
        _ = try await fixture.store.startSession(authorization: fixture.authorization)

        let receipts = try await withThrowingTaskGroup(
            of: NetworkEligibleReceipt.self,
            returning: [NetworkEligibleReceipt].self
        ) { group in
            for ordinal in 1...8 {
                group.addTask {
                    try await fixture.store.publishSelectedFrame(
                        fixture.candidate(ordinal: ordinal)
                    )
                }
            }
            var values = [NetworkEligibleReceipt]()
            for try await value in group { values.append(value) }
            return values
        }

        let ordered = receipts.sorted { $0.acceptedSequence < $1.acceptedSequence }
        let snapshot = await fixture.store.snapshot()
        #expect(ordered.map(\.acceptedSequence) == Array(0..<8))
        #expect(Set(ordered.map(\.frameID)).count == 8)
        #expect(snapshot.acceptedFrames.map(\.sequence) == Array(0..<8))
        #expect(snapshot.events.map(\.eventSequence) == Array(0..<33))
        #expect(snapshot.journalEntries.map(\.journalSequence) == Array(0..<41))
        #expect(snapshot.journalEntries.filter { $0.entryType == "frame" }.count == 8)
        let physical = try fixture.physicalJournalSnapshot()
        #expect(physical.timeline.count == 41)
        #expect(physical.timeline.filter { $0.entryType == .frame }.count == 8)
        #expect(physical.events.filter { $0.type == "frame_network_eligible" }.count == 8)
    }

    @Test("identity and idempotency collisions perform no filesystem mutation")
    func collisionsArePreflightOnly() async throws {
        let fixture = try CrashMatrixFixture(sessionOrdinal: 81)
        defer { fixture.remove() }
        _ = try await fixture.store.startSession(authorization: fixture.authorization)
        let first = try fixture.candidate(ordinal: 1)
        _ = try await fixture.store.publishSelectedFrame(first)
        let before = try fixture.allFileBytes()

        await #expect(throws: CaptureArchiveError.identityCollision) {
            _ = try await fixture.store.publishSelectedFrame(first)
        }
        await #expect(throws: CaptureArchiveError.idempotencyCollision) {
            _ = try await fixture.store.publishSelectedFrame(
                fixture.candidate(ordinal: 2, idempotencyKey: first.idempotencyKey)
            )
        }
        #expect(try fixture.allFileBytes() == before)
    }

    @Test("production and memory filesystems expose the same operation contract")
    func productionAndMemoryParity() async throws {
        let production = try CrashMatrixFixture(sessionOrdinal: 82)
        defer { production.remove() }
        let memoryRecorder = CaptureOperationFaultController()
        let memoryFileSystem = MemoryCaptureFileSystem(
            observe: memoryRecorder.observeBefore,
            afterOperation: memoryRecorder.observeAfter
        )
        let memory = try CrashMatrixFixture(
            sessionOrdinal: 82,
            fileSystem: memoryFileSystem,
            faults: memoryRecorder
        )

        let productionReceipt = try await production.completeAcknowledgedArchive()
        let memoryReceipt = try await memory.completeAcknowledgedArchive()

        #expect(productionReceipt == memoryReceipt)
        let productionFiles = try production.allFileBytes()
        let memoryFiles = memoryFileSystem.snapshotFiles()
        #expect(Set(productionFiles.keys) == Set(memoryFiles.keys))
        #expect(
            productionFiles.mapValues(CanonicalJSON.sha256Hex)
                == memoryFiles.mapValues(CanonicalJSON.sha256Hex)
        )
        #expect(production.faults.observations == memoryRecorder.observations)
    }

    @Test(
        "interior physical corruption never produces a candidate, capability, or replay",
        arguments: PhysicalCorruptionCase.allCases
    )
    private func interiorCorruptionFailsBeforeReplay(
        _ mutation: PhysicalCorruptionCase
    ) async throws {
        let fixture = try CrashMatrixFixture(sessionOrdinal: 300 + mutation.rawValue)
        defer { fixture.remove() }
        _ = try await fixture.store.startSession(authorization: fixture.authorization)
        _ = try await fixture.store.publishSelectedFrame(fixture.candidate(ordinal: 1))
        try fixture.applyPhysicalCorruption(mutation)
        let sourceBefore = try #require(fixture.sourceURL).appendingPathComponent("manifest.json")
        let manifestDigest = CanonicalJSON.sha256Hex(try Data(contentsOf: sourceBefore))
        let recovery = CaptureRecovery(
            verifier: ArchiveVerifier(validator: fixture.validator)
        )

        #expect(throws: mutation.expectedError) {
            _ = try recovery.recoveryCandidate(root: try #require(fixture.sourceURL))
        }
        #expect(CanonicalJSON.sha256Hex(try Data(contentsOf: sourceBefore)) == manifestDigest)
        #expect(fixture.materializedGenerationPaths.isEmpty)
    }
}

private enum PhysicalCorruptionCase: Int, CaseIterable, Sendable {
    case gap
    case duplicate
    case reorder
    case laterValidAfterFault
    case referencedByteContradiction
    case invalidLifecycle

    var expectedError: CaptureRecoveryError {
        switch self {
        case .gap, .duplicate, .reorder:
            .nonContiguousJournal
        case .laterValidAfterFault:
            .interiorCorruption
        case .referencedByteContradiction:
            .digestMismatch
        case .invalidLifecycle:
            .invalidManifest
        }
    }
}

private struct CaptureFaultCase: Sendable, CustomTestStringConvertible {
    let name: String
    let workflow: FaultWorkflow
    let target: CaptureFaultTarget
    let expectedFrameCount: Int
    let expectedEligibleCount: Int
    let expectedAcknowledgedCount: Int
    let expectsFinalizedManifest: Bool

    var sessionOrdinal: Int {
        100 + Self.cases.firstIndex(where: { $0.name == name })!
    }

    var testDescription: String { name }

    static let cases: [CaptureFaultCase] = [
        fault("start/event payload write/after", .start, .write, .after, "events/event_0000.json"),
        fault("start/event file sync/after", .start, .synchronizeFile, .after, "events/event_0000.json"),
        fault("start/journal write/before", .start, .write, .before, "journal/global.jsonl"),
        fault("start/journal write/after", .start, .write, .after, "journal/global.jsonl"),
        fault("start/journal file sync/after", .start, .synchronizeFile, .after, "journal/global.jsonl"),
        fault("start/journal directory sync/after", .start, .synchronizeDirectory, .after, "journal"),

        fault("first/selected payload write/before", .firstFrame, .write, .before, "events/event_0001.json"),
        fault("first/selected payload write/after", .firstFrame, .write, .after, "events/event_0001.json"),
        fault("first/selected payload sync/after", .firstFrame, .synchronizeFile, .after, "events/event_0001.json"),
        fault("first/selected event directory sync/after", .firstFrame, .synchronizeDirectory, .after, "events"),
        fault("first/selected journal append/before", .firstFrame, .append, .before, "journal/global.jsonl"),
        fault("first/selected journal append/after", .firstFrame, .append, .after, "journal/global.jsonl"),
        fault("first/staging image write/after", .firstFrame, .write, .after, "frame_00000001-0000-4000-8000-000000000001.tmp/image.png"),
        fault("first/staging packet write/after", .firstFrame, .write, .after, "frame_00000001-0000-4000-8000-000000000001.tmp/packet.json"),
        fault("first/staging image sync/after", .firstFrame, .synchronizeFile, .after, "frame_00000001-0000-4000-8000-000000000001.tmp/image.png"),
        fault("first/staging packet sync/after", .firstFrame, .synchronizeFile, .after, "frame_00000001-0000-4000-8000-000000000001.tmp/packet.json"),
        fault("first/staging directory sync/after", .firstFrame, .synchronizeDirectory, .after, "frame_00000001-0000-4000-8000-000000000001.tmp"),
        fault("first/frame generation rename/before", .firstFrame, .rename, .before, "frame_00000001-0000-4000-8000-000000000001.tmp"),
        fault("first/frame generation rename/after", .firstFrame, .rename, .after, "frame_00000001-0000-4000-8000-000000000001.tmp"),
        fault("first/frame parent sync/after", .firstFrame, .synchronizeDirectory, .after, "frames"),
        fault("first/durable event write/after", .firstFrame, .write, .after, "events/event_0002.json"),
        fault("first/frame journal append/before", .firstFrame, .append, .before, "journal/global.jsonl", occurrence: 3),
        fault("first/frame journal append/after", .firstFrame, .append, .after, "journal/global.jsonl", occurrence: 3, frames: 1),
        fault("first/journaled event write/after", .firstFrame, .write, .after, "events/event_0003.json", frames: 1),
        fault("first/journaled event append/after", .firstFrame, .append, .after, "journal/global.jsonl", occurrence: 4, frames: 1),
        fault("first/network event write/after", .firstFrame, .write, .after, "events/event_0004.json", frames: 1),
        fault("first/network event append/before", .firstFrame, .append, .before, "journal/global.jsonl", occurrence: 5, frames: 1),
        fault("first/network event append/after", .firstFrame, .append, .after, "journal/global.jsonl", occurrence: 5, frames: 1, eligible: 1),
        fault("first/network journal sync/after", .firstFrame, .synchronizeFile, .after, "journal/global.jsonl", occurrence: 5, frames: 1, eligible: 1),
        fault("first/network journal directory sync/after", .firstFrame, .synchronizeDirectory, .after, "journal", occurrence: 5, frames: 1, eligible: 1),

        fault("later/selected payload write/before", .laterFrame, .write, .before, "events/event_0005.json", frames: 1, eligible: 1),
        fault("later/selected payload write/after", .laterFrame, .write, .after, "events/event_0005.json", frames: 1, eligible: 1),
        fault("later/selected payload sync/after", .laterFrame, .synchronizeFile, .after, "events/event_0005.json", frames: 1, eligible: 1),
        fault("later/selected event directory sync/after", .laterFrame, .synchronizeDirectory, .after, "events", frames: 1, eligible: 1),
        fault("later/selected journal append/before", .laterFrame, .append, .before, "journal/global.jsonl", frames: 1, eligible: 1),
        fault("later/selected journal append/after", .laterFrame, .append, .after, "journal/global.jsonl", frames: 1, eligible: 1),
        fault("later/staging image write/after", .laterFrame, .write, .after, "frame_00000002-0000-4000-8000-000000000001.tmp/image.png", frames: 1, eligible: 1),
        fault("later/staging packet write/after", .laterFrame, .write, .after, "frame_00000002-0000-4000-8000-000000000001.tmp/packet.json", frames: 1, eligible: 1),
        fault("later/staging image sync/after", .laterFrame, .synchronizeFile, .after, "frame_00000002-0000-4000-8000-000000000001.tmp/image.png", frames: 1, eligible: 1),
        fault("later/staging packet sync/after", .laterFrame, .synchronizeFile, .after, "frame_00000002-0000-4000-8000-000000000001.tmp/packet.json", frames: 1, eligible: 1),
        fault("later/staging directory sync/after", .laterFrame, .synchronizeDirectory, .after, "frame_00000002-0000-4000-8000-000000000001.tmp", frames: 1, eligible: 1),
        fault("later/frame generation rename/before", .laterFrame, .rename, .before, "frame_00000002-0000-4000-8000-000000000001.tmp", frames: 1, eligible: 1),
        fault("later/frame generation rename/after", .laterFrame, .rename, .after, "frame_00000002-0000-4000-8000-000000000001.tmp", frames: 1, eligible: 1),
        fault("later/frame parent sync/after", .laterFrame, .synchronizeDirectory, .after, "frames", frames: 1, eligible: 1),
        fault("later/durable event write/after", .laterFrame, .write, .after, "events/event_0006.json", frames: 1, eligible: 1),
        fault("later/frame journal append/before", .laterFrame, .append, .before, "journal/global.jsonl", occurrence: 3, frames: 1, eligible: 1),
        fault("later/frame journal append/after", .laterFrame, .append, .after, "journal/global.jsonl", occurrence: 3, frames: 2, eligible: 1),
        fault("later/journaled event write/after", .laterFrame, .write, .after, "events/event_0007.json", frames: 2, eligible: 1),
        fault("later/journaled event append/after", .laterFrame, .append, .after, "journal/global.jsonl", occurrence: 4, frames: 2, eligible: 1),
        fault("later/network event write/after", .laterFrame, .write, .after, "events/event_0008.json", frames: 2, eligible: 1),
        fault("later/network event append/before", .laterFrame, .append, .before, "journal/global.jsonl", occurrence: 5, frames: 2, eligible: 1),
        fault("later/network event append/after", .laterFrame, .append, .after, "journal/global.jsonl", occurrence: 5, frames: 2, eligible: 2),
        fault("later/network journal sync/after", .laterFrame, .synchronizeFile, .after, "journal/global.jsonl", occurrence: 5, frames: 2, eligible: 2),
        fault("later/network journal directory sync/after", .laterFrame, .synchronizeDirectory, .after, "journal", occurrence: 5, frames: 2, eligible: 2),

        fault("ack/payload write/after", .acknowledgement, .write, .after, "events/event_0005.json", frames: 1, eligible: 1),
        fault("ack/payload sync/after", .acknowledgement, .synchronizeFile, .after, "events/event_0005.json", frames: 1, eligible: 1),
        fault("ack/event directory sync/after", .acknowledgement, .synchronizeDirectory, .after, "events", frames: 1, eligible: 1),
        fault("ack/journal append/before", .acknowledgement, .append, .before, "journal/global.jsonl", frames: 1, eligible: 1),
        fault("ack/journal append/after", .acknowledgement, .append, .after, "journal/global.jsonl", frames: 1, eligible: 1, acknowledged: 1),
        fault("ack/journal file sync/after", .acknowledgement, .synchronizeFile, .after, "journal/global.jsonl", frames: 1, eligible: 1, acknowledged: 1),
        fault("ack/journal directory sync/after", .acknowledgement, .synchronizeDirectory, .after, "journal", frames: 1, eligible: 1, acknowledged: 1),

        fault("empty final/event write/before", .emptyFinalization, .write, .before, "events/event_0001.json"),
        fault("empty final/event write/after", .emptyFinalization, .write, .after, "events/event_0001.json"),
        fault("empty final/event file sync/after", .emptyFinalization, .synchronizeFile, .after, "events/event_0001.json"),
        fault("empty final/event directory sync/after", .emptyFinalization, .synchronizeDirectory, .after, "events"),
        fault("empty final/journal append/before", .emptyFinalization, .append, .before, "journal/global.jsonl"),
        fault("empty final/journal append/after", .emptyFinalization, .append, .after, "journal/global.jsonl"),
        fault("empty final/journal file sync/after", .emptyFinalization, .synchronizeFile, .after, "journal/global.jsonl"),
        fault("empty final/journal directory sync/after", .emptyFinalization, .synchronizeDirectory, .after, "journal"),
        fault("empty final/manifest replace/before", .emptyFinalization, .replace, .before, "manifest.json"),
        fault("empty final/manifest replace/after", .emptyFinalization, .replace, .after, "manifest.json", finalized: true),
        fault("empty final/manifest file sync/after", .emptyFinalization, .synchronizeFile, .after, "manifest.json", finalized: true),
        fault("empty final/archive directory sync/after", .emptyFinalization, .synchronizeDirectory, .after, ".rrcap", finalized: true),

        fault("frame final/manifest replace/before", .frameFinalization, .replace, .before, "manifest.json", frames: 1, eligible: 1),
        fault("frame final/manifest replace/after", .frameFinalization, .replace, .after, "manifest.json", frames: 1, eligible: 1, finalized: true),
        fault("frame final/manifest file sync/after", .frameFinalization, .synchronizeFile, .after, "manifest.json", frames: 1, eligible: 1, finalized: true),
        fault("frame final/archive directory sync/after", .frameFinalization, .synchronizeDirectory, .after, ".rrcap", frames: 1, eligible: 1, finalized: true),
    ]

    private static func fault(
        _ name: String,
        _ workflow: FaultWorkflow,
        _ kind: CaptureFileOperationKind,
        _ phase: CaptureOperationPhase,
        _ pathSuffix: String,
        occurrence: Int = 1,
        frames: Int = 0,
        eligible: Int = 0,
        acknowledged: Int = 0,
        finalized: Bool = false
    ) -> CaptureFaultCase {
        CaptureFaultCase(
            name: name,
            workflow: workflow,
            target: CaptureFaultTarget(
                kind: kind,
                phase: phase,
                pathSuffix: pathSuffix,
                occurrence: occurrence
            ),
            expectedFrameCount: frames,
            expectedEligibleCount: eligible,
            expectedAcknowledgedCount: acknowledged,
            expectsFinalizedManifest: finalized
        )
    }
}

private struct LifecycleRecoveryCase: Sendable, CustomTestStringConvertible {
    let state: CaptureFrameState
    let journalCount: UInt64
    let frameCount: UInt64
    let eventCount: UInt64
    let sessionOrdinal: Int

    var testDescription: String { state.rawValue }

    static let cases = [
        LifecycleRecoveryCase(
            state: .selected,
            journalCount: 2,
            frameCount: 0,
            eventCount: 2,
            sessionOrdinal: 201
        ),
        LifecycleRecoveryCase(
            state: .imageAndMetadataDurable,
            journalCount: 3,
            frameCount: 0,
            eventCount: 3,
            sessionOrdinal: 202
        ),
        LifecycleRecoveryCase(
            state: .journaled,
            journalCount: 5,
            frameCount: 1,
            eventCount: 4,
            sessionOrdinal: 203
        ),
        LifecycleRecoveryCase(
            state: .networkEligible,
            journalCount: 6,
            frameCount: 1,
            eventCount: 5,
            sessionOrdinal: 204
        ),
        LifecycleRecoveryCase(
            state: .serverAcknowledged,
            journalCount: 7,
            frameCount: 1,
            eventCount: 6,
            sessionOrdinal: 205
        ),
    ]
}

private final class LifecycleRecoveryProbe: @unchecked Sendable {
    struct Snapshot {
        let didObserve: Bool
        let recovered: RecoveredArchive?
        let failure: String?
    }

    let target: CaptureFrameState
    let sourceURL: URL
    let recovery: CaptureRecovery

    private let lock = NSLock()
    private var didObserve = false
    private var recovered: RecoveredArchive?
    private var failure: String?

    init(target: CaptureFrameState, sourceURL: URL, recovery: CaptureRecovery) {
        self.target = target
        self.sourceURL = sourceURL
        self.recovery = recovery
    }

    func observe(_ observation: CaptureLifecycleObservation) {
        lock.lock()
        guard didObserve == false, observation.state == target else {
            lock.unlock()
            return
        }
        didObserve = true
        lock.unlock()

        do {
            let value = try recovery.inspect(root: sourceURL)
            lock.lock()
            recovered = value
            lock.unlock()
        } catch {
            lock.lock()
            failure = String(describing: error)
            lock.unlock()
        }
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(didObserve: didObserve, recovered: recovered, failure: failure)
    }
}

private enum FaultWorkflow: Equatable, Sendable {
    case start
    case firstFrame
    case laterFrame
    case acknowledgement
    case emptyFinalization
    case frameFinalization
}

private enum CaptureOperationPhase: String, Equatable, Sendable {
    case before
    case after
}

private struct CaptureOperationObservation: Equatable, Sendable {
    let phase: CaptureOperationPhase
    let operation: CaptureFileOperation
}

private struct CaptureFaultTarget: Sendable {
    let kind: CaptureFileOperationKind
    let phase: CaptureOperationPhase
    let pathSuffix: String
    let occurrence: Int
}

private struct InjectedCaptureOperationFault: Error, Equatable {
    let kind: CaptureFileOperationKind
    let phase: CaptureOperationPhase
    let path: String
}

private final class CaptureOperationFaultController: @unchecked Sendable {
    private let lock = NSLock()
    private var target: CaptureFaultTarget?
    private var matchingCount = 0
    private var fired = false
    private var recorded = [CaptureOperationObservation]()

    var didFire: Bool { withLock { fired } }
    var observations: [CaptureOperationObservation] { withLock { recorded } }

    func arm(_ target: CaptureFaultTarget) {
        withLock {
            self.target = target
            matchingCount = 0
            fired = false
        }
    }

    func observeBefore(_ operation: CaptureFileOperation) throws {
        try observe(operation, phase: .before)
    }

    func observeAfter(_ operation: CaptureFileOperation) throws {
        try observe(operation, phase: .after)
    }

    private func observe(
        _ operation: CaptureFileOperation,
        phase: CaptureOperationPhase
    ) throws {
        let injected: InjectedCaptureOperationFault? = withLock {
            recorded.append(CaptureOperationObservation(phase: phase, operation: operation))
            guard let target,
                  fired == false,
                  target.kind == operation.kind,
                  target.phase == phase,
                  operation.path.hasSuffix(target.pathSuffix)
            else { return nil }
            matchingCount += 1
            guard matchingCount == target.occurrence else { return nil }
            fired = true
            return InjectedCaptureOperationFault(
                kind: operation.kind,
                phase: phase,
                path: operation.path
            )
        }
        if let injected { throw injected }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private struct CrashMatrixFixture: Sendable {
    let root: URL?
    let fileSystem: any CaptureFileSystem
    let faults: CaptureOperationFaultController
    let validator: ContractValidator
    let descriptor: CaptureSessionDescriptor
    let authorization: CaptureSessionAuthorization
    let store: CaptureArchiveStore
    let imageFileExtension: String
    let imageBytes: Data

    init(sessionOrdinal: Int) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("reroom-capture-crash-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let faults = CaptureOperationFaultController()
        let fileSystem = try FoundationCaptureFileSystem(
            root: root,
            observe: faults.observeBefore,
            afterOperation: faults.observeAfter
        )
        try self.init(
            sessionOrdinal: sessionOrdinal,
            fileSystem: fileSystem,
            faults: faults,
            root: root
        )
    }

    init(
        sessionOrdinal: Int,
        fileSystem: any CaptureFileSystem,
        faults: CaptureOperationFaultController,
        root: URL? = nil,
        lifecycleObserver: @escaping CaptureLifecycleObserver = { _ in },
        encodingProfile: FramePacketEncodingProfile = .syntheticOnePixelPNG,
        imageFileExtension: String = "png",
        imageBytes: Data = CrashImages.onePixelPNG
    ) throws {
        self.root = root
        self.fileSystem = fileSystem
        self.faults = faults
        self.imageFileExtension = imageFileExtension
        self.imageBytes = imageBytes
        validator = try CrashSchemas.validator()
        descriptor = try CaptureSessionDescriptor(
            sessionID: CrashIDs.session(sessionOrdinal),
            archivePath: "archives/\(CrashIDs.session(sessionOrdinal)).rrcap",
            worldFrameID: CrashIDs.world(sessionOrdinal),
            startedAtMonotonicNanoseconds: String(3_000_000_000 + sessionOrdinal)
        )
        authorization = try CaptureSessionAuthorization(
            sessionID: descriptor.sessionID,
            consentGranted: true
        )
        let encoder = FramePacketEncoder(
            validator: validator,
            profile: encodingProfile
        )
        store = CaptureArchiveStore(
            fileSystem: fileSystem,
            encoder: encoder,
            descriptor: descriptor,
            source: CaptureArchiveSource(
                deviceModel: "Synthetic iPhone Fixture",
                osVersion: "fixture-1.0.0",
                appVersion: "fixture-1.0.0",
                buildID: "build_fixture_0002",
                recordedAtUTC: "2026-07-17T00:00:00Z"
            ),
            eventID: { sequence in CrashIDs.event(sessionOrdinal * 100 + Int(sequence) + 1) },
            lifecycleObserver: lifecycleObserver
        )
    }

    func candidate(ordinal: Int, idempotencyKey: String? = nil) throws -> SelectedFrameCandidate {
        let frameID = CrashIDs.frame(ordinal)
        return try SelectedFrameCandidate(
            sessionID: descriptor.sessionID,
            frameID: frameID,
            submapID: CrashIDs.submap(1),
            worldFrameID: descriptor.worldFrameID,
            worldFrameVersion: 1,
            captureSequence: UInt64(ordinal - 1),
            monotonicTimestampNanoseconds: String(4_000_000_000 + ordinal),
            imageRelativePath: "frames/\(frameID)/image.\(imageFileExtension)",
            packetRelativePath: "frames/\(frameID)/packet.json",
            imageBytes: imageBytes,
            selectedReason: .userEvent,
            idempotencyKey: idempotencyKey ?? CrashIDs.idempotency(ordinal)
        )
    }

    func acknowledgement(for receipt: NetworkEligibleReceipt) throws -> GatewayAcknowledgement {
        try GatewayAcknowledgement(
            gatewayID: CrashIDs.gateway(1),
            sessionID: receipt.sessionID,
            frameID: receipt.frameID,
            idempotencyKey: receipt.idempotencyKey,
            packetSHA256: receipt.packetSHA256,
            acceptedSequence: receipt.acceptedSequence
        )
    }

    func completeAcknowledgedArchive() async throws -> NetworkEligibleReceipt {
        _ = try await store.startSession(authorization: authorization)
        let receipt = try await store.publishSelectedFrame(candidate(ordinal: 1))
        try await store.recordAcknowledgement(acknowledgement(for: receipt))
        _ = try await store.finalizeExplicitly()
        return receipt
    }

    func assertProductionRecovery(_ testCase: CaptureFaultCase) throws {
        guard let sourceURL else { throw CrashFixtureError.invalidFileSystem }
        let sourceBefore = try recursiveArchiveFiles(at: sourceURL)
        let manifestExists = FileManager.default.fileExists(
            atPath: sourceURL.appendingPathComponent("manifest.json").path
        )

        if manifestExists == false {
            #expect(testCase.workflow == .start)
            #expect(throws: CaptureRecoveryError.missingManifest) {
                try CaptureRecovery(verifier: ArchiveVerifier(validator: validator))
                    .inspect(root: sourceURL)
            }
            #expect(try recursiveArchiveFiles(at: sourceURL) == sourceBefore)
            return
        }

        let recovered = try productionRecovery()
        let physical = recovered.physical
        let frameIDs = physical.entries
            .filter { $0.entryType == "frame" }
            .map(\.referenceID)
        let eligibleFrameIDs = physical.events.compactMap { event in
            event.type == "frame_network_eligible" ? event.frameID : nil
        }
        let acknowledgedFrameIDs = physical.events.compactMap { event in
            event.type == "frame_server_acknowledged" ? event.frameID : nil
        }

        #expect(physical.entries.map(\.journalSequence) == Array(0..<UInt64(physical.entries.count)))
        #expect(frameIDs.count == testCase.expectedFrameCount)
        #expect(eligibleFrameIDs.count == testCase.expectedEligibleCount)
        #expect(acknowledgedFrameIDs.count == testCase.expectedAcknowledgedCount)
        #expect(Set(eligibleFrameIDs).isSubset(of: Set(frameIDs)))
        #expect(Set(acknowledgedFrameIDs).isSubset(of: Set(eligibleFrameIDs)))
        #expect(recovered.replay.timeline == physical.timeline)
        #expect(recovered.replay.finalization.acceptedFrameCount == UInt64(frameIDs.count))
        #expect(recovered.replay.finalization.eventCount == UInt64(physical.events.count))
        #expect(recovered.inspected.acceptedJournalRecordCount == UInt64(physical.entries.count))

        let sourceManifest = try JSONSerialization.jsonObject(
            with: Data(contentsOf: sourceURL.appendingPathComponent("manifest.json"))
        ) as! [String: Any]
        let sourceFinalization = sourceManifest["finalization"] as! [String: Any]
        #expect(
            (sourceFinalization["state"] as? String == "finalized")
                == testCase.expectsFinalizedManifest
        )

        let manifest = recovered.manifest
        let projectedJournal = manifest["journal"] as! [[String: Any]]
        let projectedFrames = manifest["accepted_frame_order"] as! [[String: Any]]
        let projectedEvents = manifest["events"] as! [[String: Any]]
        let projectedFiles = manifest["files"] as! [[String: Any]]
        let finalization = manifest["finalization"] as! [String: Any]
        let replay = manifest["replay"] as! [String: Any]
        let expectedState = physical.events.contains(where: { $0.type == "session_finalized" })
            ? CaptureFinalizationState.finalized
            : .recoveredPrefix

        #expect(projectedJournal.count == physical.entries.count)
        #expect(projectedFrames.map { $0["frame_id"] as! String } == frameIDs)
        #expect(projectedEvents.map { $0["event_id"] as! String }
            == physical.entries.filter { $0.entryType == "event" }.map(\.referenceID))
        #expect(Set(projectedFiles.map { $0["relative_path"] as! String }) == physical.memberPaths)
        #expect(projectedFrames.filter { $0["server_acknowledged"] as? Bool == true }.count
            == testCase.expectedAcknowledgedCount)
        #expect(finalization["state"] as? String == expectedState.rawValue)
        #expect(recovered.inspected.finalization.state == expectedState)
        #expect(finalization["last_durable_journal_sequence"] as? Int
            == physical.entries.count - 1)

        let tuples: [[Any]] = physical.entries.map {
            [$0.journalSequence, $0.entryType, $0.referenceID, $0.contentSHA256]
        }
        let expectedJournalDigest = CanonicalJSON.sha256Hex(try canonicalData(tuples))
        #expect(replay["input_digest"] as? String == expectedJournalDigest)
        #expect(recovered.replay.digests.journalTupleSHA256 == expectedJournalDigest)
        #expect(recovered.replay.digests.frameProjectionSHA256
            == CanonicalJSON.sha256Hex(try canonicalData(projectedFrames)))
        #expect(recovered.replay.digests.eventProjectionSHA256
            == CanonicalJSON.sha256Hex(try canonicalData(projectedEvents)))

        if let candidate = recovered.candidate {
            #expect(candidate.journalData == physical.journalData)
            #expect(candidate.acceptedPrefixJournalSHA256
                == CanonicalJSON.sha256Hex(physical.journalData))
            #expect(candidate.members.map(\.descriptor).sorted { $0.relativePath < $1.relativePath }
                == recovered.verified.members)
            for member in candidate.members {
                let sourceData = try fileSystem.read(
                    at: archivePath(member.descriptor.relativePath)
                )
                #expect(member.data == sourceData)
                #expect(member.descriptor.sha256 == CanonicalJSON.sha256Hex(member.data))
            }
        } else {
            #expect(testCase.expectsFinalizedManifest)
        }
        #expect(try recursiveArchiveFiles(at: sourceURL) == sourceBefore)
    }

    func productionRecovery() throws -> ProductionRecoverySnapshot {
        guard let root, let sourceURL else { throw CrashFixtureError.invalidFileSystem }
        let recovery = CaptureRecovery(verifier: ArchiveVerifier(validator: validator))
        let inspected = try recovery.inspect(root: sourceURL)
        let candidate: RecoveryGenerationCandidate?
        let verified: VerifiedArchive
        do {
            verified = try validatorBackedVerifier().verify(root: sourceURL)
            candidate = nil
        } catch ArchiveVerificationError.archiveOpen {
            let value = try recovery.recoveryCandidate(root: sourceURL)
            let generation = root.appendingPathComponent(
                "matrix-generation-\(UUID().uuidString.lowercased()).rrcap"
            )
            try value.materialize(at: generation)
            verified = try validatorBackedVerifier().verify(root: generation)
            candidate = value
        }
        let replay = try ReplayCore.replay(verified)
        let manifestData: Data
        if let candidate {
            manifestData = candidate.manifestData
        } else {
            manifestData = try Data(
                contentsOf: sourceURL.appendingPathComponent("manifest.json")
            )
        }
        let manifest = try JSONSerialization.jsonObject(with: manifestData) as! [String: Any]
        return ProductionRecoverySnapshot(
            inspected: inspected,
            candidate: candidate,
            verified: verified,
            replay: replay,
            manifest: manifest,
            physical: try physicalJournalSnapshot()
        )
    }

    var sourceURL: URL? {
        root?.appendingPathComponent(descriptor.archivePath)
    }

    var materializedGenerationPaths: [URL] {
        guard let root else { return [] }
        return ((try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        )) ?? []).filter { $0.lastPathComponent.hasPrefix("matrix-generation-") }
    }

    func applyPhysicalCorruption(_ mutation: PhysicalCorruptionCase) throws {
        let journalPath = archivePath("journal/global.jsonl")
        var objects = try fileSystem.read(at: journalPath)
            .split(separator: 0x0a)
            .map { try JSONSerialization.jsonObject(with: Data($0)) as! [String: Any] }
        switch mutation {
        case .gap:
            objects[2]["journal_sequence"] = 3
            try replacePhysicalJournal(objects)
        case .duplicate:
            objects[2]["journal_sequence"] = 1
            try replacePhysicalJournal(objects)
        case .reorder:
            objects.swapAt(2, 3)
            try replacePhysicalJournal(objects)
        case .laterValidAfterFault:
            var data = Data()
            for (index, object) in objects.enumerated() {
                data.append(index == 2 ? Data("{".utf8) : try canonicalData(object))
                data.append(0x0a)
            }
            try data.write(to: try #require(sourceURL).appendingPathComponent("journal/global.jsonl"))
        case .referencedByteContradiction:
            try Data("contradictory-packet".utf8).write(
                to: try #require(sourceURL)
                    .appendingPathComponent("frames/\(CrashIDs.frame(1))/packet.json")
            )
        case .invalidLifecycle:
            try installOpenManifestPrefix(recordCount: 2, journalObjects: objects)
            let payloadPath = try #require(sourceURL)
                .appendingPathComponent("events/event_0002.json")
            var payload = try JSONSerialization.jsonObject(
                with: Data(contentsOf: payloadPath)
            ) as! [String: Any]
            payload["type"] = "frame_selected"
            let payloadData = try canonicalData(payload)
            try payloadData.write(to: payloadPath)
            let entry = objects[2]
            var record: [String: Any] = [
                "event_id": entry["reference_id"]!,
                "event_sequence": 2,
                "durable_journal_sequence": 2,
                "monotonic_timestamp_ns": entry["monotonic_timestamp_ns"]!,
                "type": "frame_selected",
                "payload_sha256": CanonicalJSON.sha256Hex(payloadData),
                "payload_path": "events/event_0002.json",
                "record_sha256_algorithm": "RR-JCS-SHA256-1",
                "record_sha256_scope":
                    "entire_event_record_with_record_sha256_member_omitted",
            ]
            record["record_sha256"] = CanonicalJSON.sha256Hex(try canonicalData(record))
            objects[2]["content_sha256"] = record["record_sha256"]
            try replacePhysicalJournal(objects)
        }
    }

    private func replacePhysicalJournal(_ objects: [[String: Any]]) throws {
        var data = Data()
        for object in objects {
            data.append(try canonicalData(object))
            data.append(0x0a)
        }
        try data.write(to: try #require(sourceURL).appendingPathComponent("journal/global.jsonl"))
    }

    private func installOpenManifestPrefix(
        recordCount: Int,
        journalObjects: [[String: Any]]
    ) throws {
        let sourceURL = try #require(sourceURL)
        try replacePhysicalJournal(Array(journalObjects.prefix(recordCount)))
        let recovery = CaptureRecovery(verifier: validatorBackedVerifier())
        let prefix = try recovery.recoveryCandidate(root: sourceURL)
        var manifest = try JSONSerialization.jsonObject(with: prefix.manifestData) as! [String: Any]
        var finalization = manifest["finalization"] as! [String: Any]
        finalization["state"] = CaptureFinalizationState.open.rawValue
        finalization.removeValue(forKey: "manifest_sha256")
        manifest["finalization"] = finalization
        finalization["manifest_sha256"] = CanonicalJSON.sha256Hex(try canonicalData(manifest))
        manifest["finalization"] = finalization
        try canonicalData(manifest).write(to: sourceURL.appendingPathComponent("manifest.json"))
        try replacePhysicalJournal(journalObjects)
    }

    private func validatorBackedVerifier() -> ArchiveVerifier {
        ArchiveVerifier(validator: validator)
    }

    func physicalJournalSnapshot() throws -> PhysicalJournalSnapshot {
        let journalData = try fileSystem.read(at: archivePath("journal/global.jsonl"))
        let entries = try journalData.split(separator: 0x0a).map {
            try JSONDecoder().decode(CaptureJournalEntry.self, from: Data($0))
        }
        var eventOrdinal = 0
        var events = [PhysicalEventSnapshot]()
        var memberPaths = Set<String>()
        for entry in entries {
            if entry.entryType == "event" {
                let path = "events/event_\(String(format: "%04d", eventOrdinal)).json"
                let payloadData = try fileSystem.read(at: archivePath(path))
                let payload = try JSONSerialization.jsonObject(with: payloadData) as! [String: Any]
                let details = payload["details"] as! [String: Any]
                events.append(
                    PhysicalEventSnapshot(
                        type: payload["type"] as! String,
                        frameID: details["frame_id"] as? String
                    )
                )
                memberPaths.insert(path)
                eventOrdinal += 1
            } else if entry.entryType == "frame" {
                let packetPath = "frames/\(entry.referenceID)/packet.json"
                let packetData = try fileSystem.read(at: archivePath(packetPath))
                let packet = try JSONSerialization.jsonObject(with: packetData) as! [String: Any]
                let image = packet["image"] as! [String: Any]
                let payload = image["payload"] as! [String: Any]
                memberPaths.insert(packetPath)
                memberPaths.insert(payload["relative_path"] as! String)
            }
        }
        let timeline = try entries.map {
            try ReplayTimelineEntry(
                journalSequence: $0.journalSequence,
                entryType: ReplayTimelineEntryType(rawValue: $0.entryType)!,
                referenceID: $0.referenceID,
                contentSHA256: $0.contentSHA256,
                monotonicTimestampNanoseconds: $0.monotonicTimestampNanoseconds
            )
        }
        return PhysicalJournalSnapshot(
            journalData: journalData,
            entries: entries,
            timeline: timeline,
            events: events,
            memberPaths: memberPaths
        )
    }

    func immutableFirstFramePrefix() throws -> ImmutablePrefix {
        let journal = try fileSystem.read(at: archivePath("journal/global.jsonl"))
        let paths = [
            "events/event_0000.json",
            "events/event_0001.json",
            "events/event_0002.json",
            "events/event_0003.json",
            "events/event_0004.json",
            "frames/\(CrashIDs.frame(1))/image.png",
            "frames/\(CrashIDs.frame(1))/packet.json",
        ]
        return ImmutablePrefix(
            journalBytes: journal,
            files: try Dictionary(uniqueKeysWithValues: paths.map {
                ($0, try fileSystem.read(at: archivePath($0)))
            })
        )
    }

    func assertFirstFramePrefixUnchanged(_ prefix: ImmutablePrefix) throws {
        let journal = try fileSystem.read(at: archivePath("journal/global.jsonl"))
        #expect(journal.starts(with: prefix.journalBytes))
        for (path, bytes) in prefix.files {
            #expect(try fileSystem.read(at: archivePath(path)) == bytes)
        }
    }

    func allFileBytes() throws -> [String: Data] {
        if let root {
            return try recursiveFiles(at: root)
        }
        if let memory = fileSystem as? MemoryCaptureFileSystem {
            return memory.snapshotFiles()
        }
        throw CrashFixtureError.invalidFileSystem
    }

    func archivePath(_ relativePath: String) -> String {
        "\(descriptor.archivePath)/\(relativePath)"
    }

    func remove() {
        if let root { try? FileManager.default.removeItem(at: root) }
    }
}

private struct ProductionRecoverySnapshot {
    let inspected: RecoveredArchive
    let candidate: RecoveryGenerationCandidate?
    let verified: VerifiedArchive
    let replay: ReplaySnapshot
    let manifest: [String: Any]
    let physical: PhysicalJournalSnapshot

    var eventTypes: [String] { physical.events.map(\.type) }
}

private struct PhysicalJournalSnapshot {
    let journalData: Data
    let entries: [CaptureJournalEntry]
    let timeline: [ReplayTimelineEntry]
    let events: [PhysicalEventSnapshot]
    let memberPaths: Set<String>
}

private struct PhysicalEventSnapshot {
    let type: String
    let frameID: String?
}

private struct ImmutablePrefix {
    let journalBytes: Data
    let files: [String: Data]
}

private final class MemoryCaptureFileSystem: CaptureFileSystem, @unchecked Sendable {
    let limits = CaptureFileSystemLimits.production
    private let lock = NSLock()
    private var directories: Set<String> = []
    private var files: [String: Data] = [:]
    private let observe: CaptureFileOperationObserver
    private let afterOperation: CaptureFileOperationObserver

    init(
        observe: @escaping CaptureFileOperationObserver = { _ in },
        afterOperation: @escaping CaptureFileOperationObserver = { _ in }
    ) {
        self.observe = observe
        self.afterOperation = afterOperation
    }

    func createDirectory(at path: String) throws {
        let operation = CaptureFileOperation(kind: .createDirectory, path: path)
        try observe(operation)
        _ = withLock { directories.insert(path) }
        try afterOperation(operation)
    }

    func write(_ data: Data, to path: String) throws {
        let operation = CaptureFileOperation(kind: .write, path: path, byteCount: data.count)
        try observe(operation)
        try withLock {
            guard files[path] == nil else { throw CaptureFileSystemError.destinationExists }
            files[path] = data
        }
        try afterOperation(operation)
    }

    func synchronizeFile(at path: String) throws {
        let operation = CaptureFileOperation(kind: .synchronizeFile, path: path)
        try observe(operation)
        try withLock {
            guard files[path] != nil else { throw CaptureFileSystemError.missingFile }
        }
        try afterOperation(operation)
    }

    func synchronizeDirectory(at path: String) throws {
        let operation = CaptureFileOperation(kind: .synchronizeDirectory, path: path)
        try observe(operation)
        try withLock {
            guard directories.contains(path) else { throw CaptureFileSystemError.missingFile }
        }
        try afterOperation(operation)
    }

    func append(_ data: Data, to path: String) throws {
        let operation = CaptureFileOperation(kind: .append, path: path, byteCount: data.count)
        try observe(operation)
        try withLock {
            guard files[path] != nil else { throw CaptureFileSystemError.missingFile }
            files[path]!.append(data)
        }
        try afterOperation(operation)
    }

    func replace(_ data: Data, at path: String) throws {
        let operation = CaptureFileOperation(kind: .replace, path: path, byteCount: data.count)
        try observe(operation)
        withLock { files[path] = data }
        try afterOperation(operation)
    }

    func rename(from sourcePath: String, to destinationPath: String) throws {
        let operation = CaptureFileOperation(
            kind: .rename,
            path: sourcePath,
            destinationPath: destinationPath
        )
        try observe(operation)
        try withLock {
            guard directories.contains(sourcePath), directories.contains(destinationPath) == false
            else { throw CaptureFileSystemError.missingFile }
            let descendants = files.filter { $0.key.hasPrefix(sourcePath + "/") }
            directories.remove(sourcePath)
            directories.insert(destinationPath)
            for (path, data) in descendants {
                files.removeValue(forKey: path)
                files[destinationPath + path.dropFirst(sourcePath.count)] = data
            }
        }
        try afterOperation(operation)
    }

    func read(at path: String, maximumBytes: Int?) throws -> Data {
        let operation = CaptureFileOperation(
            kind: .read,
            path: path,
            byteCount: maximumBytes ?? limits.maximumReadBytes
        )
        try observe(operation)
        let data = try withLock {
            guard let data = files[path] else { throw CaptureFileSystemError.missingFile }
            return data
        }
        try afterOperation(operation)
        return data
    }

    func fileExists(at path: String) throws -> Bool {
        let operation = CaptureFileOperation(kind: .fileExists, path: path)
        try observe(operation)
        let exists = withLock { files[path] != nil || directories.contains(path) }
        try afterOperation(operation)
        return exists
    }

    func snapshotFiles() -> [String: Data] { withLock { files } }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

private enum CrashIDs {
    static func session(_ ordinal: Int) -> String { id("session", ordinal) }
    static func frame(_ ordinal: Int) -> String { id("frame", ordinal) }
    static func submap(_ ordinal: Int) -> String { id("submap", ordinal) }
    static func world(_ ordinal: Int) -> String { id("world", ordinal) }
    static func event(_ ordinal: Int) -> String { id("event", ordinal) }
    static func gateway(_ ordinal: Int) -> String { id("gateway", ordinal) }
    static func idempotency(_ ordinal: Int) -> String { id("frameidem", ordinal) }

    private static func id(_ prefix: String, _ ordinal: Int) -> String {
        "\(prefix)_\(String(format: "%08x", ordinal))-0000-4000-8000-000000000001"
    }
}

private enum CrashImages {
    static let onePixelPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!
}

private enum CrashSchemas {
    static let framePacketDigest = "d50b19bfb29c6c62c494e3a47deb3c51a933609698f4ff2f9cbfba6ec4252b43"
    static let manifestDigest = "c97349820ed66fb1a1fdf60ea9afee312f532811602851d01d1e233641730b87"

    static func validator() throws -> ContractValidator {
        let root = try repositoryRoot()
        let registrations: [(ContractSchemaIdentifier, String, String)] = [
            (.framePacket, "frame-packet.schema.json", framePacketDigest),
            (.rrcapManifest, "rrcap-manifest.schema.json", manifestDigest),
            (.sceneState, "scene-state.schema.json", "9c77d27762e20ff5fad24c438e8817a03c770b55be3fc82ea72097c4c273e440"),
            (.editArtifacts, "edit-artifacts.schema.json", "58dbfc8f152881cbdc31be22f6ab7631ac474bb78537ac2a9254f5ef16bd598f"),
            (.transaction, "transaction.schema.json", "2a4f6728978db0879b5dfb10f052f6d5280e5cf83ad5600f0cf959626c2399a2"),
        ]
        return try ContractValidator(registrations: registrations.map { identifier, name, digest in
            ContractSchemaRegistration(
                identifier: identifier,
                version: "1.0.0",
                sha256: digest,
                schemaData: try Data(
                    contentsOf: root.appendingPathComponent("docs/contracts/\(name)")
                )
            )
        })
    }

    private static func repositoryRoot() throws -> URL {
        var cursor = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<12 {
            if FileManager.default.fileExists(
                atPath: cursor.appendingPathComponent("docs/contracts/frame-packet.schema.json").path
            ) { return cursor }
            cursor.deleteLastPathComponent()
        }
        throw CrashFixtureError.repositoryRootNotFound
    }
}

private enum CrashFixtureError: Error {
    case repositoryRootNotFound
    case invalidJournal
    case invalidLifecycle
    case invalidManifest
    case invalidFileSystem
}

private func canonicalData(_ value: Any) throws -> Data {
    let encoded = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    return try CanonicalJSON.canonicalize(jsonData: encoded)
}

private func verifyManifestDigest(_ data: Data) throws {
    guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          var finalization = root["finalization"] as? [String: Any],
          let expected = finalization.removeValue(forKey: "manifest_sha256") as? String
    else { throw CrashFixtureError.invalidManifest }
    root["finalization"] = finalization
    guard CanonicalJSON.sha256Hex(try canonicalData(root)) == expected else {
        throw CrashFixtureError.invalidManifest
    }
}

private func recursiveFiles(at root: URL) throws -> [String: Data] {
    let resolvedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
    guard let enumerator = FileManager.default.enumerator(
        at: resolvedRoot,
        includingPropertiesForKeys: [.isRegularFileKey]
    ) else { return [:] }
    var files = [String: Data]()
    for case let url as URL in enumerator {
        if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
            guard let archiveStart = url.path.range(of: "/archives/") else {
                throw CrashFixtureError.invalidFileSystem
            }
            let relative = String(url.path[archiveStart.lowerBound...].dropFirst())
            files[relative] = try Data(contentsOf: url)
        }
    }
    return files
}

private func recursiveArchiveFiles(at root: URL) throws -> [String: Data] {
    guard let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey]
    ) else { return [:] }
    var files = [String: Data]()
    for case let url as URL in enumerator {
        guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            continue
        }
        let relative = String(url.path.dropFirst(root.path.count + 1))
        files[relative] = try Data(contentsOf: url)
    }
    return files
}
