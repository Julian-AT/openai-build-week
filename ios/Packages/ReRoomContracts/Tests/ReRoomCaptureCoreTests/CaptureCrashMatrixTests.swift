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
        let recovered = try fixture.scanDurablePrefix()
        #expect(recovered.journalSequences == Array(0..<UInt64(recovered.journalSequences.count)))
        #expect(recovered.frameIDs.count == testCase.expectedFrameCount)
        #expect(recovered.networkEligibleFrameIDs.count == testCase.expectedEligibleCount)
        #expect(recovered.acknowledgedFrameIDs.count == testCase.expectedAcknowledgedCount)
        #expect(recovered.hasFinalizedManifest == testCase.expectsFinalizedManifest)
        #expect(Set(recovered.networkEligibleFrameIDs).isSubset(of: Set(recovered.frameIDs)))
        #expect(Set(recovered.acknowledgedFrameIDs).isSubset(of: Set(recovered.networkEligibleFrameIDs)))

        if let immutablePrefix {
            try fixture.assertFirstFramePrefixUnchanged(immutablePrefix)
        }
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
        #expect(try fixture.scanDurablePrefix().networkEligibleFrameIDs.count == 8)
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

private enum FaultWorkflow: Sendable {
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
        root: URL? = nil
    ) throws {
        self.root = root
        self.fileSystem = fileSystem
        self.faults = faults
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
            profile: .syntheticOnePixelPNG
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
            eventID: { sequence in CrashIDs.event(sessionOrdinal * 100 + Int(sequence) + 1) }
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
            imageRelativePath: "frames/\(frameID)/image.png",
            packetRelativePath: "frames/\(frameID)/packet.json",
            imageBytes: CrashImages.onePixelPNG,
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

    func scanDurablePrefix() throws -> DurablePrefixScan {
        let journalPath = archivePath("journal/global.jsonl")
        guard try fileSystem.fileExists(at: journalPath) else {
            return DurablePrefixScan.empty
        }
        let journalData = try fileSystem.read(at: journalPath)
        let lines = journalData.split(separator: 0x0a, omittingEmptySubsequences: true)
        var entries = [CaptureJournalEntry]()
        var eventTypes = [String]()
        var frameIDs = [String]()
        var lifecycleByFrame = [String: [String]]()
        var eventOrdinal = 0

        for line in lines {
            let entry = try JSONDecoder().decode(CaptureJournalEntry.self, from: Data(line))
            guard entry.journalSequence == UInt64(entries.count) else {
                throw CrashFixtureError.invalidJournal
            }
            switch entry.entryType {
            case "event":
                let payloadPath = "events/event_\(String(format: "%04d", eventOrdinal)).json"
                let payloadData = try fileSystem.read(at: archivePath(payloadPath))
                guard let payload = try JSONSerialization.jsonObject(with: payloadData)
                        as? [String: Any],
                      let type = payload["type"] as? String
                else { throw CrashFixtureError.invalidJournal }
                var record: [String: Any] = [
                    "event_id": entry.referenceID,
                    "event_sequence": eventOrdinal,
                    "durable_journal_sequence": entry.journalSequence,
                    "monotonic_timestamp_ns": entry.monotonicTimestampNanoseconds,
                    "type": type,
                    "payload_sha256": CanonicalJSON.sha256Hex(payloadData),
                    "payload_path": payloadPath,
                    "record_sha256_algorithm": "RR-JCS-SHA256-1",
                    "record_sha256_scope":
                        "entire_event_record_with_record_sha256_member_omitted",
                ]
                let recordDigest = CanonicalJSON.sha256Hex(try canonicalData(record))
                guard recordDigest == entry.contentSHA256 else {
                    throw CrashFixtureError.invalidJournal
                }
                record["record_sha256"] = recordDigest
                _ = record
                eventTypes.append(type)
                if let details = payload["details"] as? [String: Any],
                   let frameID = details["frame_id"] as? String {
                    lifecycleByFrame[frameID, default: []].append(type)
                }
                eventOrdinal += 1
            case "frame":
                let packetPath = "frames/\(entry.referenceID)/packet.json"
                let packetData = try fileSystem.read(at: archivePath(packetPath))
                guard CanonicalJSON.sha256Hex(packetData) == entry.contentSHA256,
                      let packet = try JSONSerialization.jsonObject(with: packetData)
                        as? [String: Any],
                      let image = packet["image"] as? [String: Any],
                      let payload = image["payload"] as? [String: Any],
                      let imagePath = payload["relative_path"] as? String,
                      let imageDigest = payload["sha256"] as? String
                else { throw CrashFixtureError.invalidJournal }
                let imageData = try fileSystem.read(at: archivePath(imagePath))
                guard CanonicalJSON.sha256Hex(imageData) == imageDigest,
                      validator.validate(
                        ContractValidationRequest(
                            schemaID: ContractSchemaIdentifier.framePacket.rawValue,
                            schemaVersion: "1.0.0",
                            schemaSHA256: CrashSchemas.framePacketDigest,
                            documentData: packetData,
                            payloadData: imageData
                        )
                      ) == .accepted
                else { throw CrashFixtureError.invalidJournal }
                frameIDs.append(entry.referenceID)
            default:
                throw CrashFixtureError.invalidJournal
            }
            entries.append(entry)
        }

        let eligible = lifecycleByFrame.compactMap { frameID, lifecycle in
            lifecycle.contains("frame_network_eligible") ? frameID : nil
        }.sorted()
        let acknowledged = lifecycleByFrame.compactMap { frameID, lifecycle in
            lifecycle.contains("frame_server_acknowledged") ? frameID : nil
        }.sorted()
        for frameID in eligible {
            guard lifecycleByFrame[frameID]?.prefix(4) == [
                "frame_selected",
                "frame_image_and_metadata_durable",
                "frame_journaled",
                "frame_network_eligible",
            ], frameIDs.contains(frameID)
            else { throw CrashFixtureError.invalidLifecycle }
        }
        for frameID in acknowledged {
            guard lifecycleByFrame[frameID]?.suffix(2) == [
                "frame_network_eligible", "frame_server_acknowledged",
            ] else { throw CrashFixtureError.invalidLifecycle }
        }

        var hasFinalizedManifest = false
        let manifestPath = archivePath("manifest.json")
        if try fileSystem.fileExists(at: manifestPath) {
            let manifest = try fileSystem.read(at: manifestPath)
            guard validator.validate(
                ContractValidationRequest(
                    schemaID: ContractSchemaIdentifier.rrcapManifest.rawValue,
                    schemaVersion: "1.0.0",
                    schemaSHA256: CrashSchemas.manifestDigest,
                    documentData: manifest
                )
            ) == .accepted else { throw CrashFixtureError.invalidManifest }
            try verifyManifestDigest(manifest)
            hasFinalizedManifest = true
        }

        return DurablePrefixScan(
            journalSequences: entries.map(\.journalSequence),
            eventTypes: eventTypes,
            frameIDs: frameIDs,
            networkEligibleFrameIDs: eligible,
            acknowledgedFrameIDs: acknowledged,
            hasFinalizedManifest: hasFinalizedManifest
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

private struct DurablePrefixScan {
    let journalSequences: [UInt64]
    let eventTypes: [String]
    let frameIDs: [String]
    let networkEligibleFrameIDs: [String]
    let acknowledgedFrameIDs: [String]
    let hasFinalizedManifest: Bool

    static let empty = DurablePrefixScan(
        journalSequences: [],
        eventTypes: [],
        frameIDs: [],
        networkEligibleFrameIDs: [],
        acknowledgedFrameIDs: [],
        hasFinalizedManifest: false
    )
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
