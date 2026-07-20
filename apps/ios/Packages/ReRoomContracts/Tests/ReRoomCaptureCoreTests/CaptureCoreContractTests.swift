import Foundation
import Testing

@testable import ReRoomCaptureCore

@Suite("CaptureCoreContractTests")
struct CaptureCoreContractTests {
    @Test("public capture values are immutable Sendable snapshots with stable identities")
    func captureValueContracts() throws {
        requireSendable(CaptureSessionAuthorization.self)
        requireSendable(CaptureSessionDescriptor.self)
        requireSendable(SelectedFrameCandidate.self)
        requireSendable(NetworkEligibleReceipt.self)
        requireSendable(GatewayAcknowledgement.self)
        requireSendable(CaptureFinalization.self)
        requireSendable(RecoveredArchive.self)

        let authorization = try CaptureSessionAuthorization(
            sessionID: IDs.session,
            consentGranted: true
        )
        let descriptor = try CaptureSessionDescriptor(
            sessionID: IDs.session,
            archivePath: "sessions/session_0001.rrcap",
            worldFrameID: IDs.world,
            startedAtMonotonicNanoseconds: "1000000000"
        )
        let candidate = try SelectedFrameCandidate(
            sessionID: IDs.session,
            frameID: IDs.frame,
            submapID: IDs.submap,
            worldFrameID: IDs.world,
            worldFrameVersion: 1,
            captureSequence: 0,
            monotonicTimestampNanoseconds: "1000000001",
            imageRelativePath: "image/frame_0001.png",
            packetRelativePath: "frames/frame_0001.json",
            imageBytes: Data("synthetic".utf8),
            selectedReason: .cadence,
            idempotencyKey: IDs.idempotency
        )
        let receipt = try NetworkEligibleReceipt(
            sessionID: IDs.session,
            frameID: IDs.frame,
            idempotencyKey: IDs.idempotency,
            packetRelativePath: "frames/frame_0001.json",
            packetSHA256: IDs.digestA,
            imageSHA256: IDs.digestB,
            acceptedSequence: 0,
            durableJournalSequence: 3
        )
        let acknowledgement = try GatewayAcknowledgement(
            gatewayID: IDs.gateway,
            sessionID: IDs.session,
            frameID: IDs.frame,
            idempotencyKey: IDs.idempotency,
            packetSHA256: IDs.digestA,
            acceptedSequence: 0
        )
        let finalization = try CaptureFinalization(
            sessionID: IDs.session,
            archivePath: "sessions/session_0001.rrcap",
            state: .finalized,
            manifestSHA256: IDs.digestB,
            lastDurableJournalSequence: 7,
            acceptedFrameCount: 1,
            eventCount: 7
        )
        let recoveredFinalization = try CaptureFinalization(
            sessionID: IDs.session,
            archivePath: "sessions/session_0001.rrcap",
            state: .recoveredPrefix,
            manifestSHA256: IDs.digestB,
            lastDurableJournalSequence: 7,
            acceptedFrameCount: 1,
            eventCount: 6
        )
        let recovered = try RecoveredArchive(
            finalization: recoveredFinalization,
            acceptedJournalRecordCount: 8,
            firstInvalidJournalSequence: 8,
            quarantineSHA256: IDs.digestC
        )

        #expect(authorization.retentionPolicy.rawValue == "local_only_until_share")
        #expect(descriptor.sessionID == candidate.sessionID)
        #expect(candidate.selectedReason.rawValue == "cadence")
        #expect(
            CaptureFrameLifecycleEvent.allCases.map(\.rawValue) == [
                "frame_selected",
                "frame_image_and_metadata_durable",
                "frame_journaled",
                "frame_network_eligible",
                "frame_server_acknowledged",
            ]
        )
        #expect(receipt.durableJournalSequence == 3)
        #expect(acknowledgement.packetSHA256 == receipt.packetSHA256)
        #expect(finalization.state.rawValue == "finalized")
        #expect(CaptureFinalizationState.allCases.map(\.rawValue) == ["open", "finalized", "recovered_prefix"])
        #expect(recovered.firstInvalidJournalSequence == 8)
    }

    @Test("capture identities paths digests and empty bytes fail closed")
    func captureValueRejections() {
        #expect(throws: CaptureValueError.consentDenied) {
            try CaptureSessionAuthorization(
                sessionID: IDs.session,
                consentGranted: false
            )
        }
        #expect(throws: CaptureValueError.invalidIdentity) {
            try CaptureSessionAuthorization(
                sessionID: "session_1",
                consentGranted: true,
                retentionPolicy: .localOnlyUntilShare
            )
        }
        #expect(throws: CaptureValueError.invalidPath) {
            try CaptureSessionDescriptor(
                sessionID: IDs.session,
                archivePath: "../escape.rrcap",
                worldFrameID: IDs.world,
                startedAtMonotonicNanoseconds: "1"
            )
        }
        #expect(throws: CaptureValueError.emptyBytes) {
            try SelectedFrameCandidate(
                sessionID: IDs.session,
                frameID: IDs.frame,
                submapID: IDs.submap,
                worldFrameID: IDs.world,
                worldFrameVersion: 1,
                captureSequence: 0,
                monotonicTimestampNanoseconds: "1",
                imageRelativePath: "image/frame.png",
                packetRelativePath: "frames/frame.json",
                imageBytes: Data(),
                selectedReason: .cadence,
                idempotencyKey: IDs.idempotency
            )
        }
        #expect(throws: CaptureValueError.invalidDigest) {
            try NetworkEligibleReceipt(
                sessionID: IDs.session,
                frameID: IDs.frame,
                idempotencyKey: IDs.idempotency,
                packetRelativePath: "frames/frame.json",
                packetSHA256: "abc",
                imageSHA256: IDs.digestB,
                acceptedSequence: 0,
                durableJournalSequence: 3
            )
        }
    }

    @Test("replay values expose only verified journal-order evidence")
    func replayValueContracts() throws {
        requireSendable(ReplayVerdict.self)
        requireSendable(ReplayTimelineEntry.self)
        requireSendable(ReplayReportV1.self)

        let entry = try ReplayTimelineEntry(
            journalSequence: 0,
            entryType: .event,
            referenceID: IDs.event,
            contentSHA256: IDs.digestA,
            monotonicTimestampNanoseconds: "1000000000"
        )
        let report = try ReplayReportV1(
            evaluator: ReplayEvaluator(name: "swift", version: "6.1", platform: "macos"),
            fixture: try ReplayFixtureIdentity(
                fixtureID: "FX-CAPTURE-001",
                fixtureRevision: "rev-001",
                manifestSHA256: IDs.digestA
            ),
            archive: try ReplayArchiveIdentity(
                caseID: "finalized-one-frame",
                archiveName: "finalized-one-frame.rrcap",
                finalizationState: .finalized,
                manifestSHA256: IDs.digestB,
                acceptedFrameCount: 1,
                eventCount: 7,
                journalRecordCount: 8
            ),
            implementation: ReplayImplementationIdentity(
                repositoryRevision: "git:0000000000000000000000000000000000000000",
                runtime: "swift-6.1",
                buildID: "build_fixture_0001"
            ),
            verdict: .accept,
            digests: try ReplayDigestSet(
                journalTupleSHA256: IDs.digestA,
                frameProjectionSHA256: IDs.digestB,
                eventProjectionSHA256: IDs.digestC,
                revisionTraceSHA256: IDs.digestD
            ),
            rejection: nil,
            metrics: ReplayMetrics(
                maximumQueueDepth: 1,
                droppedStaleCandidates: 0,
                recoveredPrefixRecords: 0,
                quarantinedSuffixRecords: 0
            ),
            reportSHA256: IDs.digestD
        )

        #expect(ReplayVerdict.allCases.map(\.rawValue) == ["accept", "reject"])
        #expect(ReplayTimelineEntryType.allCases.map(\.rawValue) == ["event", "frame"])
        #expect(report.reportVersion == "1.0.0")
        #expect(entry.referenceID == IDs.event)
        #expect(report.rejection == nil)
    }

    @Test("selection pressure and queue metrics preserve explicit policy identity")
    func policyValueContracts() throws {
        requireSendable(FrameSelectionPolicy.self)
        requireSendable(CapturePressurePolicy.self)
        requireSendable(QueueMetricsSnapshot.self)

        let selection = try FrameSelectionPolicy(
            policyID: "policy_capture_balanced_1",
            classification: .hypothesis,
            minimumCadenceNanoseconds: 250_000_000,
            minimumViewNovelty: 0.25,
            maximumMotionScore: 0.5,
            minimumBlurScore: 0.25,
            minimumExposureScore: 0.25
        )
        let pressure = try CapturePressurePolicy(
            policyID: "policy_capture_pressure_1",
            classification: .target,
            ordinaryCapacity: 3,
            optionalComputeDropDepth: 1,
            uploadPauseDepth: 2,
            cadenceReductionDepth: 3
        )
        let metrics = try QueueMetricsSnapshot(
            offered: 5,
            accepted: 4,
            replaced: 1,
            dropped: 1,
            completed: 3,
            cancelled: 0,
            currentDepth: 1,
            maximumDepth: 2,
            uploadPaused: true,
            pressureReason: .uploadPaused
        )

        #expect(selection.classification.rawValue == "HYPOTHESIS")
        #expect(pressure.classification.rawValue == "TARGET")
        #expect(metrics.pressureReason.rawValue == "upload_paused")
        #expect(throws: CaptureValueError.invalidPolicy) {
            try FrameSelectionPolicy(
                policyID: "policy_bad",
                classification: .hypothesis,
                minimumCadenceNanoseconds: 0,
                minimumViewNovelty: .nan,
                maximumMotionScore: 2,
                minimumBlurScore: 0,
                minimumExposureScore: 0
            )
        }
    }

    @Test("Foundation filesystem performs only bounded traced archive-path operations")
    func filesystemRoundTrip() throws {
        requireSendable(FoundationCaptureFileSystem.self)
        let temporary = try TemporaryRoot()
        defer { temporary.remove() }
        let recorder = OperationRecorder()
        let fileSystem = try FoundationCaptureFileSystem(
            root: temporary.url,
            limits: CaptureFileSystemLimits(
                maximumFileBytes: 64,
                maximumAppendBytes: 16,
                maximumReadBytes: 64
            ),
            observe: recorder.observe
        )

        try fileSystem.createDirectory(at: "journal")
        try fileSystem.write(Data("a".utf8), to: "journal/current.jsonl")
        try fileSystem.synchronizeFile(at: "journal/current.jsonl")
        try fileSystem.append(Data("b".utf8), to: "journal/current.jsonl")
        try fileSystem.replace(Data("final".utf8), at: "journal/current.jsonl")
        try fileSystem.write(Data("next".utf8), to: "journal/next.jsonl")
        try fileSystem.rename(from: "journal/next.jsonl", to: "journal/published.jsonl")
        try fileSystem.synchronizeDirectory(at: "journal")

        #expect(try fileSystem.read(at: "journal/current.jsonl") == Data("final".utf8))
        #expect(try fileSystem.fileExists(at: "journal/published.jsonl"))
        #expect(
            recorder.snapshot().map(\.kind) == [
                .createDirectory,
                .write,
                .synchronizeFile,
                .append,
                .replace,
                .write,
                .rename,
                .synchronizeDirectory,
                .read,
                .fileExists,
            ]
        )
    }

    @Test("filesystem rejects traversal oversize writes and injected faults before mutation")
    func filesystemFailureBoundaries() throws {
        let temporary = try TemporaryRoot()
        defer { temporary.remove() }
        let fileSystem = try FoundationCaptureFileSystem(
            root: temporary.url,
            limits: CaptureFileSystemLimits(
                maximumFileBytes: 4,
                maximumAppendBytes: 2,
                maximumReadBytes: 4
            )
        )

        #expect(throws: CaptureFileSystemError.invalidPath) {
            try fileSystem.write(Data("x".utf8), to: "../escape")
        }
        try fileSystem.createDirectory(at: "frames")
        try fileSystem.write(Data("1234".utf8), to: "frames/max")
        #expect(try fileSystem.read(at: "frames/max") == Data("1234".utf8))
        #expect(throws: CaptureFileSystemError.byteLimitExceeded) {
            try fileSystem.write(Data("12345".utf8), to: "frames/large")
        }
        try fileSystem.write(Data("1".utf8), to: "frames/append")
        try fileSystem.append(Data("23".utf8), to: "frames/append")
        #expect(throws: CaptureFileSystemError.byteLimitExceeded) {
            try fileSystem.append(Data("456".utf8), to: "frames/append")
        }

        let faulting = try FoundationCaptureFileSystem(
            root: temporary.url,
            limits: CaptureFileSystemLimits(
                maximumFileBytes: 4,
                maximumAppendBytes: 2,
                maximumReadBytes: 4
            )
        ) { operation in
            if operation.kind == .write { throw InjectedFault.planned }
        }
        #expect(throws: InjectedFault.planned) {
            try faulting.write(Data("ok".utf8), to: "frames/faulted")
        }
        #expect(FileManager.default.fileExists(atPath: temporary.url.appendingPathComponent("frames/faulted").path) == false)
    }

    @Test("filesystem instances isolate identical archive-relative names")
    func filesystemInstanceIsolation() throws {
        let firstRoot = try TemporaryRoot()
        let secondRoot = try TemporaryRoot()
        defer {
            firstRoot.remove()
            secondRoot.remove()
        }
        let first = try FoundationCaptureFileSystem(root: firstRoot.url)
        let second = try FoundationCaptureFileSystem(root: secondRoot.url)
        try first.createDirectory(at: "frames")
        try second.createDirectory(at: "frames")
        try first.write(Data("first".utf8), to: "frames/frame.json")
        try second.write(Data("second".utf8), to: "frames/frame.json")

        #expect(try first.read(at: "frames/frame.json") == Data("first".utf8))
        #expect(try second.read(at: "frames/frame.json") == Data("second".utf8))
    }
}

private func requireSendable<T: Sendable>(_: T.Type) {}

private enum IDs {
    static let session = "session_00000000-0000-4000-8000-000000000001"
    static let frame = "frame_00000000-0000-4000-8000-000000000001"
    static let submap = "submap_00000000-0000-4000-8000-000000000001"
    static let world = "world_00000000-0000-4000-8000-000000000001"
    static let event = "event_00000000-0000-4000-8000-000000000001"
    static let gateway = "gateway_00000000-0000-4000-8000-000000000001"
    static let idempotency = "frameidem_00000000-0000-4000-8000-000000000001"
    static let digestA = String(repeating: "a", count: 64)
    static let digestB = String(repeating: "b", count: 64)
    static let digestC = String(repeating: "c", count: 64)
    static let digestD = String(repeating: "d", count: 64)
}

private final class OperationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var operations = [CaptureFileOperation]()

    func observe(_ operation: CaptureFileOperation) {
        lock.lock()
        operations.append(operation)
        lock.unlock()
    }

    func snapshot() -> [CaptureFileOperation] {
        lock.lock()
        defer { lock.unlock() }
        return operations
    }
}

private struct TemporaryRoot {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("reroom-capture-core-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

private enum InjectedFault: Error {
    case planned
}
