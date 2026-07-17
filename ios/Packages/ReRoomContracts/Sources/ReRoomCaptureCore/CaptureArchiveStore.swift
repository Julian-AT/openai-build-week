import Foundation
import ReRoomContracts

public enum CaptureArchiveError: String, Error, Equatable, Sendable {
    case invalidLifecycleTransition = "invalid_lifecycle_transition"
    case invalidConfiguration = "invalid_configuration"
    case sessionMismatch = "session_mismatch"
    case sessionNotStarted = "session_not_started"
    case sessionAlreadyStarted = "session_already_started"
    case sessionFinalized = "session_finalized"
    case archiveInterrupted = "archive_interrupted"
    case identityCollision = "identity_collision"
    case idempotencyCollision = "idempotency_collision"
    case acknowledgementMismatch = "acknowledgement_mismatch"
    case duplicateAcknowledgement = "duplicate_acknowledgement"
    case invalidFrameLayout = "invalid_frame_layout"
    case contractRejected = "contract_rejected"
}

public enum CaptureFrameState: String, Codable, CaseIterable, Sendable {
    case selected
    case imageAndMetadataDurable = "image_and_metadata_durable"
    case journaled
    case networkEligible = "network_eligible"
    case serverAcknowledged = "server_acknowledged"

    public func advanced(to next: CaptureFrameState) throws -> CaptureFrameState {
        let allowed: CaptureFrameState? = switch self {
        case .selected: .imageAndMetadataDurable
        case .imageAndMetadataDurable: .journaled
        case .journaled: .networkEligible
        case .networkEligible: .serverAcknowledged
        case .serverAcknowledged: nil
        }
        guard next == allowed else {
            throw CaptureArchiveError.invalidLifecycleTransition
        }
        return next
    }
}

public struct CaptureArchiveSource: Codable, Equatable, Sendable {
    public let deviceModel: String
    public let osVersion: String
    public let appVersion: String
    public let buildID: String
    public let recordedAtUTC: String

    public init(
        deviceModel: String,
        osVersion: String,
        appVersion: String,
        buildID: String,
        recordedAtUTC: String
    ) {
        self.deviceModel = deviceModel
        self.osVersion = osVersion
        self.appVersion = appVersion
        self.buildID = buildID
        self.recordedAtUTC = recordedAtUTC
    }

    enum CodingKeys: String, CodingKey {
        case deviceModel = "device_model"
        case osVersion = "os_version"
        case appVersion = "app_version"
        case buildID = "build_id"
        case recordedAtUTC = "recorded_at_utc"
    }
}

public struct CaptureJournalEntry: Codable, Equatable, Sendable {
    public let journalSequence: UInt64
    public let monotonicTimestampNanoseconds: String
    public let entryType: String
    public let referenceID: String
    public let contentSHA256: String

    enum CodingKeys: String, CodingKey {
        case journalSequence = "journal_sequence"
        case monotonicTimestampNanoseconds = "monotonic_timestamp_ns"
        case entryType = "entry_type"
        case referenceID = "reference_id"
        case contentSHA256 = "content_sha256"
    }
}

public struct CaptureEventRecord: Codable, Equatable, Sendable {
    public let eventID: String
    public let eventSequence: UInt64
    public let durableJournalSequence: UInt64
    public let monotonicTimestampNanoseconds: String
    public let type: String
    public let payloadSHA256: String
    public let payloadPath: String
    public let recordSHA256Algorithm: String
    public let recordSHA256Scope: String
    public let recordSHA256: String

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case eventSequence = "event_sequence"
        case durableJournalSequence = "durable_journal_sequence"
        case monotonicTimestampNanoseconds = "monotonic_timestamp_ns"
        case type
        case payloadSHA256 = "payload_sha256"
        case payloadPath = "payload_path"
        case recordSHA256Algorithm = "record_sha256_algorithm"
        case recordSHA256Scope = "record_sha256_scope"
        case recordSHA256 = "record_sha256"
    }
}

public struct CaptureAcceptedFrame: Codable, Equatable, Sendable {
    public let sequence: UInt64
    public let frameID: String
    public let packetPath: String
    public let packetSHA256: String
    public let durableJournalSequence: UInt64
    public var serverAcknowledged: Bool

    enum CodingKeys: String, CodingKey {
        case sequence
        case frameID = "frame_id"
        case packetPath = "packet_path"
        case packetSHA256 = "packet_sha256"
        case durableJournalSequence = "durable_journal_sequence"
        case serverAcknowledged = "server_acknowledged"
    }
}

public struct CaptureArchiveSnapshot: Equatable, Sendable {
    public let sessionID: String
    public let journalEntries: [CaptureJournalEntry]
    public let events: [CaptureEventRecord]
    public let acceptedFrames: [CaptureAcceptedFrame]
    public let networkEligibleReceipts: [NetworkEligibleReceipt]
    public let finalization: CaptureFinalization?
    public let manifestData: Data?

    public var eventTypes: [String] { events.map(\.type) }
}

public actor CaptureArchiveStore {
    private static let manifestSchemaSHA256 =
        "c97349820ed66fb1a1fdf60ea9afee312f532811602851d01d1e233641730b87"
    private static let recordDigestScope =
        "entire_event_record_with_record_sha256_member_omitted"
    private static let manifestDigestScope =
        "entire_manifest_with_finalization_manifest_sha256_member_omitted"

    private enum SessionState {
        case notStarted
        case active
        case finalized
        case interrupted
    }

    private let fileSystem: any CaptureFileSystem
    private let encoder: FramePacketEncoder
    private let descriptor: CaptureSessionDescriptor
    private let source: CaptureArchiveSource
    private let makeEventID: @Sendable (UInt64) -> String

    private var sessionState = SessionState.notStarted
    private var journalEntries = [CaptureJournalEntry]()
    private var events = [CaptureEventRecord]()
    private var acceptedFrames = [CaptureAcceptedFrame]()
    private var receipts = [NetworkEligibleReceipt]()
    private var lifecycleByFrameID = [String: CaptureFrameState]()
    private var finalization: CaptureFinalization?
    private var manifestData: Data?
    private var lastMonotonicTimestampNanoseconds: String

    public init(
        fileSystem: any CaptureFileSystem,
        encoder: FramePacketEncoder,
        descriptor: CaptureSessionDescriptor,
        source: CaptureArchiveSource,
        eventID: @escaping @Sendable (UInt64) -> String = { _ in
            "event_\(UUID().uuidString.lowercased())"
        }
    ) {
        self.fileSystem = fileSystem
        self.encoder = encoder
        self.descriptor = descriptor
        self.source = source
        self.makeEventID = eventID
        self.lastMonotonicTimestampNanoseconds = descriptor.startedAtMonotonicNanoseconds
    }

    @discardableResult
    public func startSession(
        authorization: CaptureSessionAuthorization
    ) throws -> CaptureSessionDescriptor {
        guard sessionState == .notStarted else {
            throw sessionState == .finalized
                ? CaptureArchiveError.sessionFinalized
                : CaptureArchiveError.sessionAlreadyStarted
        }
        guard authorization.sessionID == descriptor.sessionID else {
            throw CaptureArchiveError.sessionMismatch
        }
        try validateConfiguration()

        do {
            try createArchiveDirectories()
            _ = try persistEvent(
                type: "session_started",
                timestamp: descriptor.startedAtMonotonicNanoseconds,
                details: ["consent_granted": true]
            )
            sessionState = .active
            return descriptor
        } catch {
            sessionState = .interrupted
            throw error
        }
    }

    public func publishSelectedFrame(
        _ candidate: SelectedFrameCandidate
    ) throws -> NetworkEligibleReceipt {
        try requireActiveSession()
        guard candidate.sessionID == descriptor.sessionID,
              candidate.worldFrameID == descriptor.worldFrameID
        else {
            throw CaptureArchiveError.sessionMismatch
        }
        guard lifecycleByFrameID[candidate.frameID] == nil,
              acceptedFrames.contains(where: { $0.frameID == candidate.frameID }) == false
        else {
            throw CaptureArchiveError.identityCollision
        }
        guard receipts.contains(where: { $0.idempotencyKey == candidate.idempotencyKey }) == false
        else {
            throw CaptureArchiveError.idempotencyCollision
        }
        let frameDirectory = try validatedFrameDirectory(for: candidate)
        guard try fileSystem.fileExists(at: archivePath(frameDirectory)) == false else {
            throw CaptureArchiveError.identityCollision
        }

        let frameJournalSequence = UInt64(journalEntries.count + 2)
        let encoded = try encoder.encode(
            candidate,
            durableJournalSequence: frameJournalSequence
        )

        do {
            _ = try persistEvent(
                type: CaptureFrameLifecycleEvent.selected.rawValue,
                timestamp: candidate.monotonicTimestampNanoseconds,
                details: frameDetails(candidate)
            )
            lifecycleByFrameID[candidate.frameID] = .selected

            try publishFrameGeneration(
                candidate: candidate,
                encoded: encoded,
                frameDirectory: frameDirectory
            )
            lifecycleByFrameID[candidate.frameID] = try lifecycleByFrameID[candidate.frameID]!
                .advanced(to: .imageAndMetadataDurable)
            _ = try persistEvent(
                type: CaptureFrameLifecycleEvent.imageAndMetadataDurable.rawValue,
                timestamp: candidate.monotonicTimestampNanoseconds,
                details: frameDetails(candidate)
            )

            try appendJournalEntry(
                CaptureJournalEntry(
                    journalSequence: UInt64(journalEntries.count),
                    monotonicTimestampNanoseconds: candidate.monotonicTimestampNanoseconds,
                    entryType: "frame",
                    referenceID: candidate.frameID,
                    contentSHA256: encoded.packetSHA256
                )
            )
            lifecycleByFrameID[candidate.frameID] = try lifecycleByFrameID[candidate.frameID]!
                .advanced(to: .journaled)
            _ = try persistEvent(
                type: CaptureFrameLifecycleEvent.journaled.rawValue,
                timestamp: candidate.monotonicTimestampNanoseconds,
                details: frameDetails(candidate)
            )
            lifecycleByFrameID[candidate.frameID] = try lifecycleByFrameID[candidate.frameID]!
                .advanced(to: .networkEligible)
            _ = try persistEvent(
                type: CaptureFrameLifecycleEvent.networkEligible.rawValue,
                timestamp: candidate.monotonicTimestampNanoseconds,
                details: frameDetails(candidate)
            )

            let acceptedSequence = UInt64(acceptedFrames.count)
            let receipt = try NetworkEligibleReceipt(
                sessionID: descriptor.sessionID,
                frameID: candidate.frameID,
                idempotencyKey: candidate.idempotencyKey,
                packetRelativePath: candidate.packetRelativePath,
                packetSHA256: encoded.packetSHA256,
                imageSHA256: encoded.imageSHA256,
                acceptedSequence: acceptedSequence,
                durableJournalSequence: frameJournalSequence
            )
            acceptedFrames.append(
                CaptureAcceptedFrame(
                    sequence: acceptedSequence,
                    frameID: candidate.frameID,
                    packetPath: candidate.packetRelativePath,
                    packetSHA256: encoded.packetSHA256,
                    durableJournalSequence: frameJournalSequence,
                    serverAcknowledged: false
                )
            )
            receipts.append(receipt)
            lastMonotonicTimestampNanoseconds = candidate.monotonicTimestampNanoseconds
            return receipt
        } catch {
            sessionState = .interrupted
            throw error
        }
    }

    public func recordAcknowledgement(_ acknowledgement: GatewayAcknowledgement) throws {
        try requireActiveSession()
        guard let receiptIndex = receipts.firstIndex(where: {
            $0.acceptedSequence == acknowledgement.acceptedSequence
        }) else {
            throw CaptureArchiveError.acknowledgementMismatch
        }
        let receipt = receipts[receiptIndex]
        guard acknowledgement.sessionID == receipt.sessionID,
              acknowledgement.frameID == receipt.frameID,
              acknowledgement.idempotencyKey == receipt.idempotencyKey,
              acknowledgement.packetSHA256 == receipt.packetSHA256,
              acknowledgement.acceptedSequence == receipt.acceptedSequence
        else {
            throw CaptureArchiveError.acknowledgementMismatch
        }
        guard lifecycleByFrameID[receipt.frameID] == .networkEligible,
              acceptedFrames[receiptIndex].serverAcknowledged == false
        else {
            throw CaptureArchiveError.duplicateAcknowledgement
        }

        do {
            _ = try persistEvent(
                type: CaptureFrameLifecycleEvent.serverAcknowledged.rawValue,
                timestamp: lastMonotonicTimestampNanoseconds,
                details: [
                    "accepted_sequence": receipt.acceptedSequence,
                    "frame_id": receipt.frameID,
                    "gateway_id": acknowledgement.gatewayID,
                    "idempotency_key": receipt.idempotencyKey,
                    "packet_sha256": receipt.packetSHA256,
                ]
            )
            lifecycleByFrameID[receipt.frameID] = try lifecycleByFrameID[receipt.frameID]!
                .advanced(to: .serverAcknowledged)
            acceptedFrames[receiptIndex].serverAcknowledged = true
        } catch {
            sessionState = .interrupted
            throw error
        }
    }

    public func finalizeExplicitly() throws -> CaptureFinalization {
        try requireActiveSession()
        do {
            _ = try persistEvent(
                type: "session_finalized",
                timestamp: lastMonotonicTimestampNanoseconds,
                details: [
                    "accepted_frame_count": acceptedFrames.count,
                    "finalization_state": CaptureFinalizationState.finalized.rawValue,
                ]
            )
            let completeManifest = try buildFinalizedManifest()
            guard encoder.validator.validate(
                ContractValidationRequest(
                    schemaID: ContractSchemaIdentifier.rrcapManifest.rawValue,
                    schemaVersion: "1.0.0",
                    schemaSHA256: Self.manifestSchemaSHA256,
                    documentData: completeManifest.data
                )
            ) == .accepted else {
                throw CaptureArchiveError.contractRejected
            }

            let manifestPath = archivePath("manifest.json")
            try fileSystem.replace(completeManifest.data, at: manifestPath)
            try fileSystem.synchronizeFile(at: manifestPath)
            try fileSystem.synchronizeDirectory(at: descriptor.archivePath)

            let result = try CaptureFinalization(
                sessionID: descriptor.sessionID,
                archivePath: descriptor.archivePath,
                state: .finalized,
                manifestSHA256: completeManifest.sha256,
                lastDurableJournalSequence: UInt64(journalEntries.count - 1),
                acceptedFrameCount: UInt64(acceptedFrames.count),
                eventCount: UInt64(events.count)
            )
            finalization = result
            manifestData = completeManifest.data
            sessionState = .finalized
            return result
        } catch {
            sessionState = .interrupted
            throw error
        }
    }

    public func snapshot() -> CaptureArchiveSnapshot {
        CaptureArchiveSnapshot(
            sessionID: descriptor.sessionID,
            journalEntries: journalEntries,
            events: events,
            acceptedFrames: acceptedFrames,
            networkEligibleReceipts: receipts,
            finalization: finalization,
            manifestData: manifestData
        )
    }
}

private extension CaptureArchiveStore {
    func requireActiveSession() throws {
        switch sessionState {
        case .active:
            return
        case .notStarted:
            throw CaptureArchiveError.sessionNotStarted
        case .finalized:
            throw CaptureArchiveError.sessionFinalized
        case .interrupted:
            throw CaptureArchiveError.archiveInterrupted
        }
    }

    func validateConfiguration() throws {
        guard source.deviceModel.isEmpty == false,
              source.osVersion.isEmpty == false,
              source.appVersion.isEmpty == false,
              source.buildID.isEmpty == false,
              source.recordedAtUTC.range(
                of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"#,
                options: .regularExpression
              ) != nil,
              isValidEventID(makeEventID(0))
        else {
            throw CaptureArchiveError.invalidConfiguration
        }
    }

    func createArchiveDirectories() throws {
        let components = descriptor.archivePath.split(separator: "/").map(String.init)
        var path = ""
        for component in components {
            path = path.isEmpty ? component : "\(path)/\(component)"
            if try fileSystem.fileExists(at: path) == false {
                try fileSystem.createDirectory(at: path)
            }
        }
        for child in ["events", "frames", "journal", "staging"] {
            try fileSystem.createDirectory(at: archivePath(child))
        }
        try fileSystem.synchronizeDirectory(at: descriptor.archivePath)
    }

    func validatedFrameDirectory(for candidate: SelectedFrameCandidate) throws -> String {
        let packet = candidate.packetRelativePath.split(separator: "/").map(String.init)
        let image = candidate.imageRelativePath.split(separator: "/").map(String.init)
        guard packet.count == 3,
              image.count == 3,
              packet[0] == "frames",
              image[0] == "frames",
              packet[1] == candidate.frameID,
              image[1] == candidate.frameID,
              packet[2] == "packet.json",
              image[2].hasPrefix("image.")
        else {
            throw CaptureArchiveError.invalidFrameLayout
        }
        return "frames/\(candidate.frameID)"
    }

    func publishFrameGeneration(
        candidate: SelectedFrameCandidate,
        encoded: EncodedFramePacket,
        frameDirectory: String
    ) throws {
        let stagingDirectory = "staging/\(candidate.frameID).tmp"
        let stagingImage = "\(stagingDirectory)/\(candidate.imageRelativePath.split(separator: "/").last!)"
        let stagingPacket = "\(stagingDirectory)/packet.json"
        try fileSystem.createDirectory(at: archivePath(stagingDirectory))
        try fileSystem.write(encoded.imageData, to: archivePath(stagingImage))
        try fileSystem.write(encoded.packetData, to: archivePath(stagingPacket))
        try fileSystem.synchronizeFile(at: archivePath(stagingImage))
        try fileSystem.synchronizeFile(at: archivePath(stagingPacket))
        try fileSystem.synchronizeDirectory(at: archivePath(stagingDirectory))
        try fileSystem.rename(
            from: archivePath(stagingDirectory),
            to: archivePath(frameDirectory)
        )
        try fileSystem.synchronizeDirectory(at: archivePath("frames"))
    }

    @discardableResult
    func persistEvent(
        type: String,
        timestamp: String,
        details: [String: Any]
    ) throws -> CaptureEventRecord {
        let eventSequence = UInt64(events.count)
        let journalSequence = UInt64(journalEntries.count)
        let eventID = makeEventID(eventSequence)
        guard isValidEventID(eventID) else {
            throw CaptureArchiveError.invalidConfiguration
        }
        let payloadPath = "events/event_\(String(format: "%04llu", eventSequence)).json"
        let payload: [String: Any] = [
            "details": details,
            "event_version": "1.0.0",
            "session_id": descriptor.sessionID,
            "type": type,
        ]
        let payloadData = try canonicalData(payload)
        let payloadSHA256 = CanonicalJSON.sha256Hex(payloadData)
        var record: [String: Any] = [
            "event_id": eventID,
            "event_sequence": eventSequence,
            "durable_journal_sequence": journalSequence,
            "monotonic_timestamp_ns": timestamp,
            "type": type,
            "payload_sha256": payloadSHA256,
            "payload_path": payloadPath,
            "record_sha256_algorithm": "RR-JCS-SHA256-1",
            "record_sha256_scope": Self.recordDigestScope,
        ]
        let recordSHA256 = CanonicalJSON.sha256Hex(try canonicalData(record))
        record["record_sha256"] = recordSHA256
        let event = try JSONDecoder().decode(
            CaptureEventRecord.self,
            from: canonicalData(record)
        )

        let persistedPayloadPath = archivePath(payloadPath)
        try fileSystem.write(payloadData, to: persistedPayloadPath)
        try fileSystem.synchronizeFile(at: persistedPayloadPath)
        try fileSystem.synchronizeDirectory(at: archivePath("events"))
        try appendJournalEntry(
            CaptureJournalEntry(
                journalSequence: journalSequence,
                monotonicTimestampNanoseconds: timestamp,
                entryType: "event",
                referenceID: eventID,
                contentSHA256: recordSHA256
            )
        )
        events.append(event)
        return event
    }

    func appendJournalEntry(_ entry: CaptureJournalEntry) throws {
        guard entry.journalSequence == UInt64(journalEntries.count) else {
            throw CaptureArchiveError.invalidLifecycleTransition
        }
        let encoded = try JSONEncoder().encode(entry)
        let line = try CanonicalJSON.canonicalize(jsonData: encoded) + Data([0x0a])
        let journalPath = archivePath("journal/global.jsonl")
        if journalEntries.isEmpty {
            try fileSystem.write(line, to: journalPath)
        } else {
            try fileSystem.append(line, to: journalPath)
        }
        try fileSystem.synchronizeFile(at: journalPath)
        try fileSystem.synchronizeDirectory(at: archivePath("journal"))
        journalEntries.append(entry)
    }

    func buildFinalizedManifest() throws -> (data: Data, sha256: String) {
        let tuples: [[Any]] = journalEntries.map {
            [$0.journalSequence, $0.entryType, $0.referenceID, $0.contentSHA256]
        }
        let replayDigest = CanonicalJSON.sha256Hex(try canonicalData(tuples))
        var root: [String: Any] = [
            "format_version": "1.0.0",
            "capture_kind": "native_arkit",
            "session_id": descriptor.sessionID,
            "source": try jsonObject(source),
            "coordinate_convention": [
                "convention": "RR-COORD-1",
                "world_frame_id": descriptor.worldFrameID,
                "initial_world_frame_version": 1,
            ],
            "capture_settings": [
                "camera_format": "encoded_upright",
                "frame_selection_policy": "explicit_selected_candidate",
                "queue_capacity": 1,
                "high_resolution_keyframe_policy": "disabled_phase_2_writer",
                "arkit_configuration": [
                    "world_tracking": true,
                    "plane_detection": ["horizontal", "vertical"],
                    "lidar_required": false,
                    "feature_flags": [],
                ],
            ],
            "files": try manifestFiles(),
            "journal": try jsonArray(journalEntries),
            "accepted_frame_order": try jsonArray(acceptedFrames),
            "keyframes": [],
            "events": try jsonArray(events),
            "replay": [
                "ordering_authority": "global_journal_sequence",
                "input_digest_algorithm": "RR-JCS-SHA256-1",
                "input_digest_scope":
                    "jcs_array_of_journal_sequence_entry_type_reference_id_content_sha256",
                "input_digest": replayDigest,
                "neural_determinism": "tolerance_based_when_provider_pinned",
                "provider_lock": [],
            ],
            "privacy": [
                "capture_consent_recorded": true,
                "contains_room_imagery": true,
                "retention_policy": CaptureRetentionPolicy.localOnlyUntilShare.rawValue,
                "deletion_state": "none",
                "share_access_state": "not_shared",
            ],
            "finalization": [
                "state": CaptureFinalizationState.finalized.rawValue,
                "manifest_sha256_algorithm": "RR-JCS-SHA256-1",
                "manifest_sha256_scope": Self.manifestDigestScope,
                "last_durable_journal_sequence": journalEntries.count - 1,
            ],
        ]
        let sha256 = CanonicalJSON.sha256Hex(try canonicalData(root))
        var finalization = root["finalization"] as! [String: Any]
        finalization["manifest_sha256"] = sha256
        root["finalization"] = finalization
        return (try canonicalData(root), sha256)
    }

    func manifestFiles() throws -> [[String: Any]] {
        var files = [[String: Any]]()
        for event in events {
            let data = try fileSystem.read(at: archivePath(event.payloadPath))
            files.append(fileRecord(
                path: event.payloadPath,
                mediaType: "application/json",
                codec: "json_jcs_1",
                data: data,
                role: "event_log"
            ))
        }
        for frame in acceptedFrames {
            let packet = try fileSystem.read(at: archivePath(frame.packetPath))
            files.append(fileRecord(
                path: frame.packetPath,
                mediaType: "application/json",
                codec: "json_jcs_1",
                data: packet,
                role: "frame_metadata"
            ))
            guard let packetObject = try JSONSerialization.jsonObject(with: packet) as? [String: Any],
                  let image = packetObject["image"] as? [String: Any],
                  let codec = image["codec"] as? String,
                  let payload = image["payload"] as? [String: Any],
                  let path = payload["relative_path"] as? String
            else {
                throw CaptureArchiveError.contractRejected
            }
            let imageData = try fileSystem.read(at: archivePath(path))
            files.append(fileRecord(
                path: path,
                mediaType: mediaType(for: codec),
                codec: codec,
                data: imageData,
                role: "frame_image"
            ))
        }
        return files
    }

    func fileRecord(
        path: String,
        mediaType: String,
        codec: String,
        data: Data,
        role: String
    ) -> [String: Any] {
        [
            "relative_path": path,
            "media_type": mediaType,
            "codec": codec,
            "byte_length": data.count,
            "sha256": CanonicalJSON.sha256Hex(data),
            "role": role,
        ]
    }

    func frameDetails(_ candidate: SelectedFrameCandidate) -> [String: Any] {
        [
            "frame_id": candidate.frameID,
            "idempotency_key": candidate.idempotencyKey,
            "packet_path": candidate.packetRelativePath,
        ]
    }

    func mediaType(for codec: String) -> String {
        switch codec {
        case "jpeg": "image/jpeg"
        case "png": "image/png"
        default: "image/heic"
        }
    }

    func archivePath(_ relativePath: String) -> String {
        "\(descriptor.archivePath)/\(relativePath)"
    }

    func canonicalData(_ value: Any) throws -> Data {
        let encoded = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return try CanonicalJSON.canonicalize(jsonData: encoded)
    }

    func jsonObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
    }

    func jsonArray<T: Encodable>(_ values: [T]) throws -> [Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(values)) as! [Any]
    }

    func isValidEventID(_ value: String) -> Bool {
        value.range(
            of: #"^event_[0-9a-f]{8}-[0-9a-f]{4}-[47][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"#,
            options: .regularExpression
        ) != nil
    }
}
