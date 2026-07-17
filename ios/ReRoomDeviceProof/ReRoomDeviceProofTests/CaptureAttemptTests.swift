import Foundation
import ReRoomContracts
import Testing
@testable import ReRoomDeviceProof

@Suite("Capture attempts")
struct CaptureAttemptTests {
    private let readyEpoch = WorldEpochSnapshot(
        worldFrameID: "world_00000000-0000-4000-8000-000000000001",
        worldFrameVersion: 1,
        isQuarantined: false
    )

    @Test("Landscape during an attempt rejects capture, preserves ARSession, and coaches retry")
    func landscapeMidAttemptRejectsWithoutStoppingSession() {
        var machine = CaptureAttemptMachine()
        let selection = machine.select(
            orientation: .portrait,
            sessionIsRunning: true,
            worldEpoch: readyEpoch
        )
        #expect(selection == .selected(machine.selectedAttempt!))

        let result = machine.finish(
            currentOrientation: .landscape,
            sessionIsRunning: true,
            worldEpoch: readyEpoch
        )

        #expect(result == .rejected(.orientation(.returnToPortrait)))
        #expect(CaptureRetryCoaching.returnToPortrait.title == "Capture stopped")
        #expect(
            CaptureRetryCoaching.returnToPortrait.message
                == "The phone turned sideways. Return to portrait and try again."
        )
        #expect(CaptureRetryCoaching.returnToPortrait.retryAvailable)
        #expect(CaptureRetryCoaching.returnToPortrait.preservesARSession)
    }

    @Test("A changed epoch rejects stale selected work")
    func changedEpochRejectsAttempt() {
        var machine = CaptureAttemptMachine()
        _ = machine.select(
            orientation: .portrait,
            sessionIsRunning: true,
            worldEpoch: readyEpoch
        )
        let advanced = WorldEpochSnapshot(
            worldFrameID: readyEpoch.worldFrameID,
            worldFrameVersion: 2,
            isQuarantined: false
        )

        #expect(
            machine.finish(
                currentOrientation: .portrait,
                sessionIsRunning: true,
                worldEpoch: advanced
            ) == .rejected(.worldFrameChanged)
        )
    }

    @Test("Quarantine disables selection and completion")
    func quarantineRejectsCapture() {
        let quarantined = WorldEpochSnapshot(
            worldFrameID: readyEpoch.worldFrameID,
            worldFrameVersion: readyEpoch.worldFrameVersion,
            isQuarantined: true
        )
        var selectionMachine = CaptureAttemptMachine()
        #expect(
            selectionMachine.select(
                orientation: .portrait,
                sessionIsRunning: true,
                worldEpoch: quarantined
            ) == .rejected(.worldFrameQuarantined)
        )

        var completionMachine = CaptureAttemptMachine()
        _ = completionMachine.select(
            orientation: .portrait,
            sessionIsRunning: true,
            worldEpoch: readyEpoch
        )
        #expect(
            completionMachine.finish(
                currentOrientation: .portrait,
                sessionIsRunning: true,
                worldEpoch: quarantined
            ) == .rejected(.worldFrameQuarantined)
        )
    }

    @Test("Portrait with a stable healthy epoch produces a bounded capture authorization")
    func stablePortraitAttemptIsReady() {
        var machine = CaptureAttemptMachine()
        _ = machine.select(
            orientation: .portrait,
            sessionIsRunning: true,
            worldEpoch: readyEpoch
        )

        #expect(
            machine.finish(
                currentOrientation: .portrait,
                sessionIsRunning: true,
                worldEpoch: readyEpoch
            ) == .ready(
                ValidatedCaptureAttempt(
                    worldFrameID: readyEpoch.worldFrameID,
                    worldFrameVersion: readyEpoch.worldFrameVersion
                )
            )
        )
    }

    @Test("A completed capture is CON-001 valid and visible only after journal sync")
    func schemaValidAtomicCapture() throws {
        let fileSystem = MemoryCaptureFileSystem()
        let journal = makeJournal(fileSystem: fileSystem)

        let receipt = try journal.capture(input: captureInput, attempt: readyAttempt)

        #expect(receipt.lifecycle == .networkEligible)
        #expect(receipt.isVisible)
        #expect(journal.visibleFrameIDs == [captureInput.frameID])
        #expect(receipt.packet.packetData.count <= FramePacketBuilder.maximumPacketBytes)
        #expect(
            Self.validator.validate(
                ContractValidationRequest(
                    schemaID: ContractSchemaIdentifier.framePacket.rawValue,
                    schemaVersion: "1.0.0",
                    schemaSHA256: Self.schemaHashes[.framePacket]!,
                    documentData: receipt.packet.packetData,
                    payloadData: receipt.packet.imageData
                )
            ) == .accepted
        )
        #expect(receipt.packet.packetSHA256 == CanonicalJSON.sha256Hex(receipt.packet.packetData))

        let recovered = try journal.recover()
        #expect(recovered.acceptedFrames.count == 1)
        #expect(recovered.events.map(\.type) == Self.phaseOneEventTypes)
        #expect(recovered.networkEligibleFrameIDs == [captureInput.frameID])
        #expect(journal.validateRecoveredManifest(recovered.manifestData) == .accepted)
        #expect(
            recovered.journal.allSatisfy { entry in
                Set(Self.jsonObject(entry).keys) == Self.journalKeys
            }
        )
        #expect(
            recovered.events.allSatisfy { event in
                Set(Self.jsonObject(event).keys) == Self.eventKeys
            }
        )
        #expect(recovered.events.contains { $0.type == "frame_server_acknowledged" } == false)
    }

    @Test("Rejected and quarantined attempts cannot reach the packet builder")
    func invalidAttemptRejectsBeforeDurability() {
        let fileSystem = MemoryCaptureFileSystem()
        let journal = makeJournal(fileSystem: fileSystem)

        #expect(throws: DiagnosticJournalRejection.invalidAttempt) {
            try journal.capture(
                input: captureInput,
                attempt: .rejected(.worldFrameQuarantined)
            )
        }
        #expect(fileSystem.allPaths().isEmpty)
        #expect(journal.visibleFrameIDs.isEmpty)
    }

    @Test(
        "Injected crashes preserve only the internal and visible states allowed at each boundary",
        arguments: CaptureCrashPoint.allCases
    )
    func crashMatrix(point: CaptureCrashPoint) throws {
        let fileSystem = MemoryCaptureFileSystem()
        let crashing = makeJournal(fileSystem: fileSystem, crashPoint: point)

        #expect(throws: InjectedCaptureCrash(point: point)) {
            try crashing.capture(input: captureInput, attempt: readyAttempt)
        }

        let recoveredJournal = makeJournal(fileSystem: fileSystem)
        let recovered = try? recoveredJournal.recover()
        let expectedInternal = point == .beforeRename ? [] : [captureInput.frameID]
        let expectedVisible = point == .afterJournalSync ? [captureInput.frameID] : []
        #expect(recovered?.internalDurableFrameIDs ?? [] == expectedInternal)
        #expect(recovered?.networkEligibleFrameIDs ?? [] == expectedVisible)
        #expect(recoveredJournal.visibleFrameIDs == expectedVisible)
    }

    @Test(
        "CON-002 recovery rejects ordering, lifecycle, digest, projection, final sequence, and prefix mutations",
        arguments: JournalManifestMutation.allCases
    )
    func manifestMutationsReject(mutation: JournalManifestMutation) throws {
        let fileSystem = MemoryCaptureFileSystem()
        let journal = makeJournal(fileSystem: fileSystem)
        _ = try journal.capture(input: captureInput, attempt: readyAttempt)
        let valid = try journal.recover().manifestData
        let mutated = try mutation.apply(to: valid)

        if case .accepted = journal.validateRecoveredManifest(mutated) {
            Issue.record("accepted mutation: \(mutation.rawValue)")
        }
    }

    private var readyAttempt: CaptureAttemptResolution {
        .ready(
            ValidatedCaptureAttempt(
                worldFrameID: readyEpoch.worldFrameID,
                worldFrameVersion: readyEpoch.worldFrameVersion
            )
        )
    }

    private var captureInput: FramePacketCaptureInput {
        FramePacketCaptureInput(
            sessionID: "session_00000000-0000-4000-8000-000000000001",
            submapID: "submap_00000000-0000-4000-8000-000000000001",
            frameID: "frame_00000000-0000-4000-8000-000000000001",
            captureSequence: 0,
            monotonicTimestampNS: "9007199254740993",
            imageData: Data("test".utf8),
            imageCodec: "jpeg",
            imageWidth: 480,
            imageHeight: 640,
            colorSpace: "srgb",
            imageRange: "full",
            cropInSensorPixels: FrameCrop(x: 0, y: 0, width: 480, height: 640),
            intrinsicsEncodedPixels: FrameIntrinsics(
                fx: 500,
                fy: 500,
                cx: 239.5,
                cy: 319.5,
                width: 480,
                height: 640
            ),
            encodedFromSensor: [1, 0, 0, 0, 1, 0, 0, 0, 1],
            worldFromCamera: [
                1, 0, 0, 0,
                0, 1, 0, 0,
                0, 0, 1, 0,
                0, 0, 0, 1,
            ],
            trackingState: "normal",
            trackingReason: "none",
            quality: FrameQuality(
                motionScore: 0,
                blurScore: 1,
                exposureScore: 1,
                selectedReason: "cadence"
            ),
            idempotencyKey: "frameidem_00000000-0000-4000-8000-000000000001",
            previousDurableFrameID: nil,
            lifecycleEventIDs: [
                "event_00000000-0000-4000-8000-000000000001",
                "event_00000000-0000-4000-8000-000000000002",
                "event_00000000-0000-4000-8000-000000000003",
                "event_00000000-0000-4000-8000-000000000004",
            ]
        )
    }

    private func makeJournal(
        fileSystem: MemoryCaptureFileSystem,
        crashPoint: CaptureCrashPoint? = nil
    ) -> DiagnosticJournal {
        DiagnosticJournal(
            fileSystem: fileSystem,
            framePacketBuilder: FramePacketBuilder(validator: Self.validator),
            configuration: DiagnosticCaptureConfiguration(
                deviceModel: "fixture",
                osVersion: "26.4",
                appVersion: "0.1.0",
                buildID: "fixture",
                recordedAtUTC: "2026-07-17T00:00:00Z",
                worldFrameID: readyEpoch.worldFrameID,
                initialWorldFrameVersion: readyEpoch.worldFrameVersion
            ),
            crashInjector: CaptureCrashInjector(point: crashPoint)
        )
    }

    private static let phaseOneEventTypes = [
        "frame_selected",
        "frame_image_and_metadata_durable",
        "frame_journaled",
        "frame_network_eligible",
    ]

    private static let journalKeys: Set<String> = [
        "journal_sequence", "monotonic_timestamp_ns", "entry_type", "reference_id",
        "content_sha256",
    ]

    private static let eventKeys: Set<String> = [
        "event_id", "event_sequence", "durable_journal_sequence", "monotonic_timestamp_ns",
        "type", "payload_sha256", "payload_path", "record_sha256_algorithm",
        "record_sha256_scope", "record_sha256",
    ]

    private static let schemaHashes: [ContractSchemaIdentifier: String] = [
        .framePacket: "d50b19bfb29c6c62c494e3a47deb3c51a933609698f4ff2f9cbfba6ec4252b43",
        .rrcapManifest: "c97349820ed66fb1a1fdf60ea9afee312f532811602851d01d1e233641730b87",
        .sceneState: "9c77d27762e20ff5fad24c438e8817a03c770b55be3fc82ea72097c4c273e440",
        .editArtifacts: "58dbfc8f152881cbdc31be22f6ab7631ac474bb78537ac2a9254f5ef16bd598f",
        .transaction: "2a4f6728978db0879b5dfb10f052f6d5280e5cf83ad5600f0cf959626c2399a2",
    ]

    private static let validator: ContractValidator = {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let paths: [ContractSchemaIdentifier: String] = [
            .framePacket: "docs/contracts/frame-packet.schema.json",
            .rrcapManifest: "docs/contracts/rrcap-manifest.schema.json",
            .sceneState: "docs/contracts/scene-state.schema.json",
            .editArtifacts: "docs/contracts/edit-artifacts.schema.json",
            .transaction: "docs/contracts/transaction.schema.json",
        ]
        let registrations = ContractSchemaIdentifier.allCases.map { identifier in
            ContractSchemaRegistration(
                identifier: identifier,
                version: "1.0.0",
                sha256: schemaHashes[identifier]!,
                schemaData: try! Data(contentsOf: root.appendingPathComponent(paths[identifier]!))
            )
        }
        return try! ContractValidator(registrations: registrations)
    }()

    private static func jsonObject<T: Encodable>(_ value: T) -> [String: Any] {
        let data = try! JSONEncoder().encode(value)
        return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    }
}

enum JournalManifestMutation: String, CaseIterable, Sendable {
    case gap
    case reorder
    case wrongEventName
    case extraEventField
    case badRecordDigest
    case badReplayDigest
    case projectionMismatch
    case wrongLastSequence
    case invalidRecoveredPrefix

    func apply(to data: Data) throws -> Data {
        var root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        switch self {
        case .gap:
            var journal = root["journal"] as! [[String: Any]]
            journal[1]["journal_sequence"] = 2
            root["journal"] = journal
        case .reorder:
            var journal = root["journal"] as! [[String: Any]]
            journal.swapAt(0, 1)
            root["journal"] = journal
        case .wrongEventName:
            var events = root["events"] as! [[String: Any]]
            events[3]["type"] = "frame_server_acknowledged"
            root["events"] = events
        case .extraEventField:
            var events = root["events"] as! [[String: Any]]
            events[0]["server_acknowledged"] = false
            root["events"] = events
        case .badRecordDigest:
            var events = root["events"] as! [[String: Any]]
            events[0]["record_sha256"] = String(repeating: "0", count: 64)
            root["events"] = events
        case .badReplayDigest:
            var replay = root["replay"] as! [String: Any]
            replay["input_digest"] = String(repeating: "0", count: 64)
            root["replay"] = replay
        case .projectionMismatch:
            root["accepted_frame_order"] = []
        case .wrongLastSequence:
            var finalization = root["finalization"] as! [String: Any]
            finalization["last_durable_journal_sequence"] = 0
            root["finalization"] = finalization
        case .invalidRecoveredPrefix:
            var finalization = root["finalization"] as! [String: Any]
            finalization["state"] = "finalized"
            root["finalization"] = finalization
        }
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }
}

private final class MemoryCaptureFileSystem: CaptureFileSystem {
    private var files: [String: Data] = [:]

    func write(_ data: Data, to path: String) throws {
        files[path] = data
    }

    func append(_ data: Data, to path: String) throws {
        files[path, default: Data()].append(data)
    }

    func synchronizeFile(at path: String) throws {
        guard files[path] != nil else { throw DiagnosticJournalRejection.invalidJournal }
    }

    func renameDirectory(from sourcePath: String, to destinationPath: String) throws {
        let prefix = sourcePath + "/"
        let matches = files.filter { $0.key.hasPrefix(prefix) }
        guard matches.isEmpty == false else { throw DiagnosticJournalRejection.invalidJournal }
        for (path, data) in matches {
            files.removeValue(forKey: path)
            files[destinationPath + path.dropFirst(sourcePath.count)] = data
        }
    }

    func synchronizeDirectory(containing path: String) throws {
        _ = path
    }

    func read(at path: String) throws -> Data {
        guard let data = files[path] else { throw DiagnosticJournalRejection.invalidJournal }
        return data
    }

    func fileExists(at path: String) -> Bool { files[path] != nil }

    func allPaths() -> [String] { files.keys.sorted() }
}
