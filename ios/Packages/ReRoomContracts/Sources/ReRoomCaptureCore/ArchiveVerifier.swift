import Foundation
import ReRoomContracts

public enum ArchiveVerificationError: String, Error, Equatable, Sendable {
    case invalidRoot = "invalid_root"
    case missingManifest = "missing_manifest"
    case invalidJSON = "invalid_json"
    case nonCanonicalJSON = "non_canonical_json"
    case schemaValidation = "schema_validation"
    case unsupportedContractVersion = "unsupported_contract_version"
    case unknownProperty = "unknown_property"
    case invalidIdentity = "invalid_identity"
    case invalidPath = "invalid_path"
    case numericOutOfRange = "numeric_out_of_range"
    case byteLimitExceeded = "byte_limit_exceeded"
    case digestMismatch = "digest_mismatch"
    case semanticInvariant = "semantic_invariant"
    case projectionMismatch = "projection_mismatch"
    case nonContiguousJournal = "non_contiguous_journal"
    case archiveOpen = "archive_open"
    case ioFailure = "io_failure"
}

public struct VerifiedArchiveSourceIdentity: Equatable, Sendable {
    public let sessionID: String
    public let manifestSHA256: String
    public let sha256: String
}

public struct VerifiedArchiveGeneration: Equatable, Sendable {
    public let sha256: String
}

public struct VerifiedArchiveManifestDescriptor: Equatable, Sendable {
    public let byteLength: Int
    public let sha256: String
    public let finalizationState: CaptureFinalizationState
    public let lastDurableJournalSequence: UInt64
    public let journalRecordCount: Int
    public let acceptedFrameCount: Int
    public let eventCount: Int
}

public struct VerifiedArchiveInventoryDescriptor: Equatable, Sendable {
    public let memberCount: Int
    public let sha256: String
}

public struct VerifiedArchiveMemberDescriptor: Equatable, Sendable {
    public let relativePath: String
    public let mediaType: String
    public let codec: String
    public let byteLength: Int
    public let sha256: String
    public let role: String
}

/// Replay authority for exactly one eagerly verified archive generation.
///
/// Construction is file-private so only `ArchiveVerifier` can mint the capability.
/// The root URL and consumption records remain private to the capability.
public struct VerifiedArchive: Sendable {
    public let sourceIdentity: VerifiedArchiveSourceIdentity
    public let generation: VerifiedArchiveGeneration
    public let manifest: VerifiedArchiveManifestDescriptor
    public let inventory: VerifiedArchiveInventoryDescriptor
    public let members: [VerifiedArchiveMemberDescriptor]

    fileprivate let storage: VerifiedArchiveStorage

    fileprivate init(storage: VerifiedArchiveStorage) {
        sourceIdentity = storage.sourceIdentity
        generation = storage.generation
        manifest = storage.manifest
        inventory = storage.inventory
        members = storage.members
        self.storage = storage
    }

    /// Re-establishes exact-byte identity immediately before replay consumes records.
    /// The returned records were derived from the same bytes admitted by the verifier;
    /// raw paths and untrusted JSON never cross this boundary.
    func consumeVerifiedContents() throws -> VerifiedArchiveContents {
        try storage.consumeVerifiedContents()
    }
}

struct VerifiedRecoverySource: Sendable {
    let sourceIdentity: VerifiedArchiveSourceIdentity
    let generation: VerifiedArchiveGeneration
    let manifest: VerifiedArchiveManifestDescriptor
    let inventory: VerifiedArchiveInventoryDescriptor
    let members: [VerifiedArchiveMemberDescriptor]

    fileprivate let storage: VerifiedArchiveStorage

    fileprivate init(storage: VerifiedArchiveStorage) {
        sourceIdentity = storage.sourceIdentity
        generation = storage.generation
        manifest = storage.manifest
        inventory = storage.inventory
        members = storage.members
        self.storage = storage
    }
}

public struct ArchiveVerifier: Sendable {
    public static let maximumManifestBytes = 33_554_432
    public static let maximumMemberBytes = 33_554_432
    public static let maximumInventoryMembers = 2_048
    public static let maximumJournalRecords = 2_048
    public static let maximumAggregateMemberBytes = 268_435_456

    private static let manifestSchemaSHA256 =
        "c97349820ed66fb1a1fdf60ea9afee312f532811602851d01d1e233641730b87"
    private static let framePacketSchemaSHA256 =
        "d50b19bfb29c6c62c494e3a47deb3c51a933609698f4ff2f9cbfba6ec4252b43"

    private let validator: ContractValidator

    public init(validator: ContractValidator) {
        self.validator = validator
    }

    public func verify(root: URL) throws -> VerifiedArchive {
        let storage = try verifyStorage(root: root)
        guard storage.manifest.finalizationState != .open else {
            throw ArchiveVerificationError.archiveOpen
        }
        return VerifiedArchive(storage: storage)
    }

    func verifyRecoverySource(root: URL) throws -> VerifiedRecoverySource {
        let storage = try verifyStorage(root: root)
        guard storage.manifest.finalizationState == .open else {
            throw ArchiveVerificationError.semanticInvariant
        }
        return VerifiedRecoverySource(storage: storage)
    }

    private func verifyStorage(root: URL) throws -> VerifiedArchiveStorage {
        let boundary = try ArchiveReadBoundary(root: root)
        let manifestData: Data
        do {
            manifestData = try boundary.read(
                relativePath: "manifest.json",
                maximumBytes: Self.maximumManifestBytes
            )
        } catch ArchiveVerificationError.ioFailure {
            throw ArchiveVerificationError.missingManifest
        }
        let canonicalManifest = try requireCanonicalJSON(manifestData)
        guard canonicalManifest == manifestData else {
            throw ArchiveVerificationError.nonCanonicalJSON
        }
        try requireAcceptedContract(
            validator.validate(
                ContractValidationRequest(
                    schemaID: ContractSchemaIdentifier.rrcapManifest.rawValue,
                    schemaVersion: ContractSchemaIdentifier.rrcapManifest.version,
                    schemaSHA256: Self.manifestSchemaSHA256,
                    documentData: manifestData
                )
            )
        )

        let manifestObject = try archiveJSONObject(manifestData)
        let manifestSelfSHA256 = try verifyManifestSelfDigest(manifestObject)
        guard let sessionID = manifestObject["session_id"] as? String,
              let finalization = manifestObject["finalization"] as? [String: Any],
              let stateValue = finalization["state"] as? String,
              let state = CaptureFinalizationState(rawValue: stateValue),
              let lastSequence = archiveUInt(finalization["last_durable_journal_sequence"])
        else { throw ArchiveVerificationError.semanticInvariant }

        let loadedMembers = try loadInventory(
            manifestObject: manifestObject,
            boundary: boundary
        )
        let events = try validateEvents(
            manifestObject: manifestObject,
            sessionID: sessionID,
            members: loadedMembers
        )
        let frames = try validateFrames(
            manifestObject: manifestObject,
            sessionID: sessionID,
            members: loadedMembers
        )
        let journal = try validateJournalAndProjections(
            manifestObject: manifestObject,
            finalizationState: state,
            lastSequence: lastSequence,
            events: events,
            frames: frames
        )
        try validateWorldEpochs(
            manifestObject: manifestObject,
            events: events,
            frames: frames,
            journal: journal
        )
        try validateLifecycle(
            finalizationState: state,
            events: events,
            frames: frames,
            journal: journal
        )
        try validateExactInventory(
            manifestObject: manifestObject,
            members: loadedMembers,
            events: events,
            frames: frames
        )

        let members = loadedMembers.values.map(\.descriptor).sorted {
            $0.relativePath < $1.relativePath
        }
        let inventorySHA256 = try digestInventory(members)
        let manifestSHA256 = CanonicalJSON.sha256Hex(manifestData)
        let sourceIdentitySHA256 = try digestObject([
            "manifest_sha256": manifestSelfSHA256,
            "session_id": sessionID,
        ])
        let sourceIdentity = VerifiedArchiveSourceIdentity(
            sessionID: sessionID,
            manifestSHA256: manifestSelfSHA256,
            sha256: sourceIdentitySHA256
        )
        let generationSHA256 = try digestObject([
            "finalization_state": state.rawValue,
            "inventory_sha256": inventorySHA256,
            "manifest_bytes_sha256": manifestSHA256,
            "source_identity_sha256": sourceIdentitySHA256,
        ])
        let descriptor = VerifiedArchiveManifestDescriptor(
            byteLength: manifestData.count,
            sha256: manifestSHA256,
            finalizationState: state,
            lastDurableJournalSequence: lastSequence,
            journalRecordCount: journal.count,
            acceptedFrameCount: frames.count,
            eventCount: events.count
        )
        let inventory = VerifiedArchiveInventoryDescriptor(
            memberCount: members.count,
            sha256: inventorySHA256
        )

        return VerifiedArchiveStorage(
            root: boundary.root,
            sourceIdentity: sourceIdentity,
            generation: VerifiedArchiveGeneration(sha256: generationSHA256),
            manifest: descriptor,
            inventory: inventory,
            members: members,
            journal: journal,
            frames: frames.map(\.record),
            events: events.map(\.record)
        )
    }

    private func loadInventory(
        manifestObject: [String: Any],
        boundary: ArchiveReadBoundary
    ) throws -> [String: LoadedArchiveMember] {
        guard let fileObjects = manifestObject["files"] as? [[String: Any]],
              fileObjects.count <= Self.maximumInventoryMembers
        else { throw ArchiveVerificationError.byteLimitExceeded }

        var result = [String: LoadedArchiveMember]()
        var aggregateBytes = 0
        for file in fileObjects {
            guard let path = file["relative_path"] as? String,
                  let mediaType = file["media_type"] as? String,
                  let codec = file["codec"] as? String,
                  let byteLengthValue = archiveUInt(file["byte_length"]),
                  byteLengthValue <= UInt64(Int.max),
                  let sha256 = file["sha256"] as? String,
                  let role = file["role"] as? String
            else { throw ArchiveVerificationError.semanticInvariant }
            guard result[path] == nil else {
                throw ArchiveVerificationError.projectionMismatch
            }
            let byteLength = Int(byteLengthValue)
            guard byteLength <= Self.maximumMemberBytes,
                  aggregateBytes <= Self.maximumAggregateMemberBytes - byteLength
            else { throw ArchiveVerificationError.byteLimitExceeded }
            aggregateBytes += byteLength

            let data = try boundary.read(
                relativePath: path,
                maximumBytes: Self.maximumMemberBytes
            )
            guard data.count == byteLength,
                  CanonicalJSON.sha256Hex(data) == sha256
            else { throw ArchiveVerificationError.digestMismatch }
            let descriptor = VerifiedArchiveMemberDescriptor(
                relativePath: path,
                mediaType: mediaType,
                codec: codec,
                byteLength: byteLength,
                sha256: sha256,
                role: role
            )
            result[path] = LoadedArchiveMember(descriptor: descriptor, data: data)
        }
        return result
    }

    private func validateEvents(
        manifestObject: [String: Any],
        sessionID: String,
        members: [String: LoadedArchiveMember]
    ) throws -> [VerifiedEventBinding] {
        guard let eventObjects = manifestObject["events"] as? [[String: Any]],
              eventObjects.count <= Self.maximumJournalRecords
        else { throw ArchiveVerificationError.byteLimitExceeded }

        var result = [VerifiedEventBinding]()
        var eventIDs = Set<String>()
        for (index, event) in eventObjects.enumerated() {
            guard archiveUInt(event["event_sequence"]) == UInt64(index),
                  let durableSequence = archiveUInt(event["durable_journal_sequence"]),
                  let eventID = event["event_id"] as? String,
                  eventIDs.insert(eventID).inserted,
                  let timestamp = event["monotonic_timestamp_ns"] as? String,
                  let type = event["type"] as? String,
                  let payloadPath = event["payload_path"] as? String,
                  let payloadSHA256 = event["payload_sha256"] as? String,
                  let recordSHA256 = event["record_sha256"] as? String,
                  let member = members[payloadPath],
                  member.descriptor.role == "event_log",
                  member.descriptor.codec == "json_jcs_1",
                  member.descriptor.sha256 == payloadSHA256
            else { throw ArchiveVerificationError.projectionMismatch }

            var digestEvent = event
            digestEvent.removeValue(forKey: "record_sha256")
            guard CanonicalJSON.sha256Hex(try archiveCanonicalData(digestEvent)) == recordSHA256 else {
                throw ArchiveVerificationError.digestMismatch
            }
            guard try requireCanonicalJSON(member.data) == member.data else {
                throw ArchiveVerificationError.nonCanonicalJSON
            }
            let payload = try archiveJSONObject(member.data)
            guard Set(payload.keys) == Set(["details", "event_version", "session_id", "type"]),
                  payload["event_version"] as? String == "1.0.0",
                  payload["session_id"] as? String == sessionID,
                  payload["type"] as? String == type,
                  let details = payload["details"] as? [String: Any]
            else { throw ArchiveVerificationError.semanticInvariant }

            let semanticDetails = EventSemanticDetails(
                frameID: details["frame_id"] as? String,
                idempotencyKey: details["idempotency_key"] as? String,
                packetPath: details["packet_path"] as? String,
                acceptedSequence: archiveUInt(details["accepted_sequence"]),
                packetSHA256: details["packet_sha256"] as? String,
                consentGranted: details["consent_granted"] as? Bool,
                acceptedFrameCount: archiveUInt(details["accepted_frame_count"]),
                finalizationState: details["finalization_state"] as? String,
                worldFrameID: (details["new_world_frame_id"] ?? details["world_frame_id"]) as? String,
                worldFrameVersion: archiveUInt(
                    details["new_world_frame_version"] ?? details["world_frame_version"]
                ),
                previousWorldFrameID: details["previous_world_frame_id"] as? String,
                previousWorldFrameVersion: archiveUInt(details["previous_world_frame_version"])
            )
            result.append(
                VerifiedEventBinding(
                    record: VerifiedEventRecord(
                        durableJournalSequence: durableSequence,
                        eventID: eventID,
                        timestamp: timestamp,
                        type: type,
                        recordSHA256: recordSHA256,
                        payload: member.descriptor,
                        canonicalProjectionData: try archiveCanonicalData(event)
                    ),
                    details: semanticDetails
                )
            )
        }
        return result
    }

    private func validateFrames(
        manifestObject: [String: Any],
        sessionID: String,
        members: [String: LoadedArchiveMember]
    ) throws -> [VerifiedFrameBinding] {
        guard let frameObjects = manifestObject["accepted_frame_order"] as? [[String: Any]],
              frameObjects.count <= Self.maximumJournalRecords
        else { throw ArchiveVerificationError.byteLimitExceeded }

        var result = [VerifiedFrameBinding]()
        var frameIDs = Set<String>()
        var idempotencyKeys = Set<String>()
        var previousCaptureSequence: UInt64?
        var previousFrameID: String?

        for (index, frame) in frameObjects.enumerated() {
            guard archiveUInt(frame["sequence"]) == UInt64(index),
                  let durableSequence = archiveUInt(frame["durable_journal_sequence"]),
                  let frameID = frame["frame_id"] as? String,
                  frameIDs.insert(frameID).inserted,
                  let packetPath = frame["packet_path"] as? String,
                  let packetSHA256 = frame["packet_sha256"] as? String,
                  let packetMember = members[packetPath],
                  packetMember.descriptor.role == "frame_metadata",
                  packetMember.descriptor.codec == "json_jcs_1",
                  packetMember.descriptor.sha256 == packetSHA256
            else { throw ArchiveVerificationError.projectionMismatch }
            guard try requireCanonicalJSON(packetMember.data) == packetMember.data else {
                throw ArchiveVerificationError.nonCanonicalJSON
            }
            let packet = try archiveJSONObject(packetMember.data)
            guard let image = packet["image"] as? [String: Any],
                  let payload = image["payload"] as? [String: Any],
                  payload["kind"] as? String == "rrcap_file",
                  let imagePath = payload["relative_path"] as? String,
                  let imageSHA256 = payload["sha256"] as? String,
                  let imageByteLength = archiveUInt(payload["byte_length"]),
                  let imageMember = members[imagePath],
                  imageMember.descriptor.role == "frame_image",
                  imageMember.descriptor.sha256 == imageSHA256,
                  UInt64(imageMember.descriptor.byteLength) == imageByteLength,
                  imageMember.descriptor.codec == image["codec"] as? String
            else { throw ArchiveVerificationError.projectionMismatch }

            try requireAcceptedContract(
                validator.validate(
                    ContractValidationRequest(
                        schemaID: ContractSchemaIdentifier.framePacket.rawValue,
                        schemaVersion: ContractSchemaIdentifier.framePacket.version,
                        schemaSHA256: Self.framePacketSchemaSHA256,
                        documentData: packetMember.data,
                        payloadData: imageMember.data
                    )
                )
            )
            guard CanonicalJSON.sha256Hex(packetMember.data) == packetSHA256 else {
                throw ArchiveVerificationError.digestMismatch
            }

            guard packet["session_id"] as? String == sessionID,
                  packet["frame_id"] as? String == frameID,
                  packet["coordinate_convention"] as? String == "RR-COORD-1",
                  let submapID = packet["submap_id"] as? String,
                  submapID.hasPrefix("submap_"),
                  let worldFrameID = packet["world_frame_id"] as? String,
                  let worldFrameVersion = archiveUInt(packet["world_frame_version"]),
                  let captureSequence = archiveUInt(packet["capture_sequence"]),
                  let timestamp = packet["monotonic_timestamp_ns"] as? String,
                  let idempotencyKey = packet["idempotency_key"] as? String,
                  idempotencyKeys.insert(idempotencyKey).inserted,
                  packet["payload_sha256"] as? String == imageSHA256,
                  let durability = packet["durability"] as? [String: Any],
                  durability["image_and_metadata_durable"] as? Bool == true,
                  durability["network_eligible"] as? Bool == true,
                  durability["state"] as? String == "network_eligible",
                  archiveUInt(durability["journal_sequence"]) == durableSequence
            else { throw ArchiveVerificationError.semanticInvariant }
            if let previousCaptureSequence {
                guard captureSequence > previousCaptureSequence else {
                    throw ArchiveVerificationError.semanticInvariant
                }
            }
            if let previousFrameID {
                guard packet["previous_durable_frame_id"] as? String == previousFrameID else {
                    throw ArchiveVerificationError.semanticInvariant
                }
            } else {
                guard packet["previous_durable_frame_id"] is NSNull else {
                    throw ArchiveVerificationError.semanticInvariant
                }
            }
            try validatePacketNumbers(packet)

            previousCaptureSequence = captureSequence
            previousFrameID = frameID
            result.append(
                VerifiedFrameBinding(
                    record: VerifiedFrameRecord(
                        acceptedSequence: UInt64(index),
                        durableJournalSequence: durableSequence,
                        captureSequence: captureSequence,
                        frameID: frameID,
                        timestamp: timestamp,
                        packetSHA256: packetSHA256,
                        idempotencyKey: idempotencyKey,
                        worldFrameID: worldFrameID,
                        worldFrameVersion: worldFrameVersion,
                        serverAcknowledged: frame["server_acknowledged"] as? Bool ?? false,
                        packet: packetMember.descriptor,
                        image: imageMember.descriptor,
                        canonicalProjectionData: try archiveCanonicalData(frame)
                    )
                )
            )
        }
        return result
    }

    private func validatePacketNumbers(_ packet: [String: Any]) throws {
        guard let transform = packet["world_from_camera"] as? [String: Any],
              let transformValues = archiveDoubleArray(transform["values"]),
              let encoded = packet["encoded_from_sensor"] as? [String: Any],
              let encodedValues = archiveDoubleArray(encoded["values"]),
              encodedValues.count == 9,
              let intrinsics = packet["intrinsics_encoded_pixels"] as? [String: Any],
              let fx = archiveDouble(intrinsics["fx"]),
              let fy = archiveDouble(intrinsics["fy"]),
              let cx = archiveDouble(intrinsics["cx"]),
              let cy = archiveDouble(intrinsics["cy"]),
              let width = archiveUInt(intrinsics["width"]),
              let height = archiveUInt(intrinsics["height"]),
              let image = packet["image"] as? [String: Any],
              archiveUInt(image["width"]) == width,
              archiveUInt(image["height"]) == height
        else { throw ArchiveVerificationError.semanticInvariant }
        do {
            _ = try RRCoordinateMath.validateRigidTransform(transformValues)
            for value in encodedValues + [fx, fy, cx, cy] {
                _ = try RRCoordinateMath.quantize(value)
            }
            guard fx > 0, fy > 0,
                  abs(encodedValues[6]) <= RRCoordinateMath.homogeneousRowTolerance,
                  abs(encodedValues[7]) <= RRCoordinateMath.homogeneousRowTolerance,
                  abs(encodedValues[8] - 1) <= RRCoordinateMath.homogeneousRowTolerance
            else { throw ArchiveVerificationError.semanticInvariant }
        } catch let error as ArchiveVerificationError {
            throw error
        } catch CoordinateMathRejection.numericOutOfRange {
            throw ArchiveVerificationError.numericOutOfRange
        } catch {
            throw ArchiveVerificationError.semanticInvariant
        }
    }

    private func validateJournalAndProjections(
        manifestObject: [String: Any],
        finalizationState: CaptureFinalizationState,
        lastSequence: UInt64,
        events: [VerifiedEventBinding],
        frames: [VerifiedFrameBinding]
    ) throws -> [VerifiedJournalRecord] {
        guard let journalObjects = manifestObject["journal"] as? [[String: Any]],
              journalObjects.isEmpty == false,
              journalObjects.count <= Self.maximumJournalRecords,
              lastSequence == UInt64(journalObjects.count - 1)
        else { throw ArchiveVerificationError.nonContiguousJournal }

        let eventsByID = Dictionary(uniqueKeysWithValues: events.map { ($0.record.eventID, $0) })
        let framesByID = Dictionary(uniqueKeysWithValues: frames.map { ($0.record.frameID, $0) })
        var result = [VerifiedJournalRecord]()
        var priorTimestamp: String?
        var journalEventIDs = [String]()
        var journalFrameIDs = [String]()

        for (index, entry) in journalObjects.enumerated() {
            guard archiveUInt(entry["journal_sequence"]) == UInt64(index),
                  let type = entry["entry_type"] as? String,
                  let referenceID = entry["reference_id"] as? String,
                  let contentSHA256 = entry["content_sha256"] as? String,
                  let timestamp = entry["monotonic_timestamp_ns"] as? String
            else { throw ArchiveVerificationError.nonContiguousJournal }
            if let priorTimestamp, compareDecimalTimestamp(timestamp, priorTimestamp) == .orderedAscending {
                throw ArchiveVerificationError.nonContiguousJournal
            }
            priorTimestamp = timestamp

            switch type {
            case "event":
                guard let event = eventsByID[referenceID],
                      event.record.durableJournalSequence == UInt64(index),
                      event.record.recordSHA256 == contentSHA256,
                      event.record.timestamp == timestamp
                else { throw ArchiveVerificationError.projectionMismatch }
                journalEventIDs.append(referenceID)
            case "frame":
                guard let frame = framesByID[referenceID],
                      frame.record.durableJournalSequence == UInt64(index),
                      frame.record.packetSHA256 == contentSHA256,
                      frame.record.timestamp == timestamp
                else { throw ArchiveVerificationError.projectionMismatch }
                journalFrameIDs.append(referenceID)
            default:
                throw ArchiveVerificationError.semanticInvariant
            }
            result.append(
                VerifiedJournalRecord(
                    journalSequence: UInt64(index),
                    entryType: type,
                    referenceID: referenceID,
                    contentSHA256: contentSHA256,
                    timestamp: timestamp,
                    canonicalData: try archiveCanonicalData(entry)
                )
            )
        }
        guard journalEventIDs == events.map(\.record.eventID),
              journalFrameIDs == frames.map(\.record.frameID)
        else { throw ArchiveVerificationError.projectionMismatch }

        let tuples: [[Any]] = result.map {
            [$0.journalSequence, $0.entryType, $0.referenceID, $0.contentSHA256]
        }
        guard let replay = manifestObject["replay"] as? [String: Any],
              replay["ordering_authority"] as? String == "global_journal_sequence",
              (replay["provider_lock"] as? [Any])?.isEmpty == true,
              replay["input_digest"] as? String ==
                CanonicalJSON.sha256Hex(try archiveCanonicalData(tuples))
        else { throw ArchiveVerificationError.projectionMismatch }

        if finalizationState == .finalized {
            guard events.last?.record.type == "session_finalized" else {
                throw ArchiveVerificationError.semanticInvariant
            }
        }
        return result
    }

    private func validateWorldEpochs(
        manifestObject: [String: Any],
        events: [VerifiedEventBinding],
        frames: [VerifiedFrameBinding],
        journal: [VerifiedJournalRecord]
    ) throws {
        guard let captureKind = manifestObject["capture_kind"] as? String else {
            throw ArchiveVerificationError.semanticInvariant
        }
        if captureKind == "ordinary_video_import" {
            guard frames.isEmpty else { throw ArchiveVerificationError.semanticInvariant }
            return
        }
        guard captureKind == "native_arkit",
              let coordinates = manifestObject["coordinate_convention"] as? [String: Any],
              coordinates["convention"] as? String == "RR-COORD-1",
              let initialWorldID = coordinates["world_frame_id"] as? String,
              let initialWorldVersion = archiveUInt(coordinates["initial_world_frame_version"])
        else { throw ArchiveVerificationError.semanticInvariant }

        let eventsByID = Dictionary(uniqueKeysWithValues: events.map { ($0.record.eventID, $0) })
        let framesByID = Dictionary(uniqueKeysWithValues: frames.map { ($0.record.frameID, $0) })
        var worldID = initialWorldID
        var worldVersion = initialWorldVersion
        for entry in journal {
            if entry.entryType == "event", let event = eventsByID[entry.referenceID],
               event.record.type == "world_frame_changed" {
                let details = event.details
                guard let nextID = details.worldFrameID,
                      isStableID(nextID, prefix: "world_"),
                      let nextVersion = details.worldFrameVersion,
                      nextVersion > worldVersion,
                      details.previousWorldFrameID.map({ $0 == worldID }) ?? true,
                      details.previousWorldFrameVersion.map({ $0 == worldVersion }) ?? true
                else { throw ArchiveVerificationError.semanticInvariant }
                worldID = nextID
                worldVersion = nextVersion
            } else if entry.entryType == "frame", let frame = framesByID[entry.referenceID] {
                guard frame.record.worldFrameID == worldID,
                      frame.record.worldFrameVersion == worldVersion
                else { throw ArchiveVerificationError.semanticInvariant }
            }
        }
    }

    private func validateLifecycle(
        finalizationState: CaptureFinalizationState,
        events: [VerifiedEventBinding],
        frames: [VerifiedFrameBinding],
        journal: [VerifiedJournalRecord]
    ) throws {
        guard events.first?.record.type == "session_started",
              events.first?.details.consentGranted == true,
              events.filter({ $0.record.type == "session_started" }).count == 1
        else { throw ArchiveVerificationError.semanticInvariant }

        let frameStages = [
            "frame_selected",
            "frame_image_and_metadata_durable",
            "frame_journaled",
            "frame_network_eligible",
            "frame_server_acknowledged",
        ]
        let stageRank = Dictionary(uniqueKeysWithValues: frameStages.enumerated().map { ($1, $0) })
        var stagesByFrame = [String: [VerifiedEventBinding]]()
        for event in events where stageRank[event.record.type] != nil {
            guard let frameID = event.details.frameID,
                  isStableID(frameID, prefix: "frame_")
            else { throw ArchiveVerificationError.semanticInvariant }
            stagesByFrame[frameID, default: []].append(event)
        }

        let framesByID = Dictionary(uniqueKeysWithValues: frames.map { ($0.record.frameID, $0) })
        for (frameID, stageEvents) in stagesByFrame {
            let ranks = try stageEvents.map { event -> Int in
                guard let rank = stageRank[event.record.type] else {
                    throw ArchiveVerificationError.semanticInvariant
                }
                return rank
            }
            guard ranks == ranks.sorted(), Set(ranks).count == ranks.count else {
                throw ArchiveVerificationError.semanticInvariant
            }
            if let frame = framesByID[frameID] {
                let requiredLastRank = finalizationState == .open ? 2 : 3
                guard ranks.count > requiredLastRank,
                      Array(ranks.prefix(requiredLastRank + 1)) == Array(0...requiredLastRank),
                      stageEvents[1].record.durableJournalSequence < frame.record.durableJournalSequence,
                      frame.record.durableJournalSequence < stageEvents[2].record.durableJournalSequence,
                      (ranks.contains(4) == frame.record.serverAcknowledged)
                else { throw ArchiveVerificationError.semanticInvariant }
                for event in stageEvents {
                    guard event.details.idempotencyKey.map({ $0 == frame.record.idempotencyKey }) ?? true,
                          event.details.packetPath.map({ $0 == frame.record.packet.relativePath }) ?? true,
                          event.details.acceptedSequence.map({ $0 == frame.record.acceptedSequence }) ?? true,
                          event.details.packetSHA256.map({ $0 == frame.record.packetSHA256 }) ?? true
                    else { throw ArchiveVerificationError.semanticInvariant }
                }
            } else {
                guard finalizationState == .open,
                      ranks.allSatisfy({ $0 <= 1 })
                else { throw ArchiveVerificationError.semanticInvariant }
            }
        }
        for frame in frames {
            guard stagesByFrame[frame.record.frameID] != nil else {
                throw ArchiveVerificationError.semanticInvariant
            }
        }

        if finalizationState == .finalized {
            guard events.filter({ $0.record.type == "session_finalized" }).count == 1,
                  let finalized = events.last,
                  finalized.details.acceptedFrameCount.map({ $0 == UInt64(frames.count) }) ?? true,
                  finalized.details.finalizationState.map({ $0 == "finalized" }) ?? true
            else { throw ArchiveVerificationError.semanticInvariant }
        } else {
            guard events.contains(where: { $0.record.type == "session_finalized" }) == false else {
                throw ArchiveVerificationError.semanticInvariant
            }
        }

        guard journal.map(\.journalSequence) == Array(0..<UInt64(journal.count)) else {
            throw ArchiveVerificationError.nonContiguousJournal
        }
    }

    private func validateExactInventory(
        manifestObject: [String: Any],
        members: [String: LoadedArchiveMember],
        events: [VerifiedEventBinding],
        frames: [VerifiedFrameBinding]
    ) throws {
        var referenced = Set(events.map(\.record.payload.relativePath))
        for frame in frames {
            referenced.insert(frame.record.packet.relativePath)
            referenced.insert(frame.record.image.relativePath)
        }

        guard let keyframes = manifestObject["keyframes"] as? [[String: Any]] else {
            throw ArchiveVerificationError.semanticInvariant
        }
        let frameIDs = Set(frames.map(\.record.frameID))
        for keyframe in keyframes {
            guard let frameID = keyframe["frame_id"] as? String,
                  frameIDs.contains(frameID),
                  let path = keyframe["file_path"] as? String,
                  let sha256 = keyframe["sha256"] as? String,
                  let member = members[path],
                  member.descriptor.role == "keyframe",
                  member.descriptor.sha256 == sha256
            else { throw ArchiveVerificationError.projectionMismatch }
            referenced.insert(path)
        }

        if let ordinaryVideo = manifestObject["ordinary_video"] as? [String: Any] {
            guard let path = ordinaryVideo["file_path"] as? String,
                  let sha256 = ordinaryVideo["sha256"] as? String,
                  let member = members[path],
                  member.descriptor.role == "ordinary_video",
                  member.descriptor.sha256 == sha256
            else { throw ArchiveVerificationError.projectionMismatch }
            referenced.insert(path)
        }
        guard referenced == Set(members.keys) else {
            throw ArchiveVerificationError.projectionMismatch
        }
    }

    private func verifyManifestSelfDigest(_ manifest: [String: Any]) throws -> String {
        guard var finalization = manifest["finalization"] as? [String: Any],
              let expected = finalization["manifest_sha256"] as? String
        else { throw ArchiveVerificationError.semanticInvariant }
        finalization.removeValue(forKey: "manifest_sha256")
        var digestRoot = manifest
        digestRoot["finalization"] = finalization
        guard CanonicalJSON.sha256Hex(try archiveCanonicalData(digestRoot)) == expected else {
            throw ArchiveVerificationError.digestMismatch
        }
        return expected
    }

    private func digestInventory(_ members: [VerifiedArchiveMemberDescriptor]) throws -> String {
        let values: [[String: Any]] = members.map {
            [
                "byte_length": $0.byteLength,
                "codec": $0.codec,
                "media_type": $0.mediaType,
                "relative_path": $0.relativePath,
                "role": $0.role,
                "sha256": $0.sha256,
            ]
        }
        return CanonicalJSON.sha256Hex(try archiveCanonicalData(values))
    }

    private func digestObject(_ object: [String: Any]) throws -> String {
        CanonicalJSON.sha256Hex(try archiveCanonicalData(object))
    }

    private func requireAcceptedContract(_ verdict: ContractValidationVerdict) throws {
        switch verdict {
        case .accepted:
            return
        case .rejected(let rejection):
            throw ArchiveVerificationError(rejection)
        }
    }
}

struct VerifiedArchiveContents: Sendable {
    let sourceIdentity: VerifiedArchiveSourceIdentity
    let generation: VerifiedArchiveGeneration
    let manifest: VerifiedArchiveManifestDescriptor
    let journal: [VerifiedJournalRecord]
    let frames: [VerifiedFrameRecord]
    let events: [VerifiedEventRecord]
    let archiveName: String
}

struct VerifiedJournalRecord: Sendable {
    let journalSequence: UInt64
    let entryType: String
    let referenceID: String
    let contentSHA256: String
    let timestamp: String
    let canonicalData: Data
}

struct VerifiedFrameRecord: Sendable {
    let acceptedSequence: UInt64
    let durableJournalSequence: UInt64
    let captureSequence: UInt64
    let frameID: String
    let timestamp: String
    let packetSHA256: String
    let idempotencyKey: String
    let worldFrameID: String
    let worldFrameVersion: UInt64
    let serverAcknowledged: Bool
    let packet: VerifiedArchiveMemberDescriptor
    let image: VerifiedArchiveMemberDescriptor
    let canonicalProjectionData: Data
}

struct VerifiedEventRecord: Sendable {
    let durableJournalSequence: UInt64
    let eventID: String
    let timestamp: String
    let type: String
    let recordSHA256: String
    let payload: VerifiedArchiveMemberDescriptor
    let canonicalProjectionData: Data
}

private struct VerifiedArchiveStorage: Sendable {
    let root: URL
    let sourceIdentity: VerifiedArchiveSourceIdentity
    let generation: VerifiedArchiveGeneration
    let manifest: VerifiedArchiveManifestDescriptor
    let inventory: VerifiedArchiveInventoryDescriptor
    let members: [VerifiedArchiveMemberDescriptor]
    let journal: [VerifiedJournalRecord]
    let frames: [VerifiedFrameRecord]
    let events: [VerifiedEventRecord]

    func consumeVerifiedContents() throws -> VerifiedArchiveContents {
        let boundary = try ArchiveReadBoundary(root: root)
        let manifestData = try boundary.read(
            relativePath: "manifest.json",
            maximumBytes: ArchiveVerifier.maximumManifestBytes
        )
        guard manifestData.count == manifest.byteLength,
              CanonicalJSON.sha256Hex(manifestData) == manifest.sha256,
              try requireCanonicalJSON(manifestData) == manifestData
        else { throw ArchiveVerificationError.digestMismatch }

        let object = try archiveJSONObject(manifestData)
        try requireProjectionBytes(object["journal"], expected: journal.map(\.canonicalData))
        try requireProjectionBytes(
            object["accepted_frame_order"],
            expected: frames.map(\.canonicalProjectionData)
        )
        try requireProjectionBytes(object["events"], expected: events.map(\.canonicalProjectionData))

        for member in members {
            let data = try boundary.read(
                relativePath: member.relativePath,
                maximumBytes: ArchiveVerifier.maximumMemberBytes
            )
            guard data.count == member.byteLength,
                  CanonicalJSON.sha256Hex(data) == member.sha256
            else { throw ArchiveVerificationError.digestMismatch }
            if member.codec == "json_jcs_1" {
                guard try requireCanonicalJSON(data) == data else {
                    throw ArchiveVerificationError.nonCanonicalJSON
                }
            }
        }
        return VerifiedArchiveContents(
            sourceIdentity: sourceIdentity,
            generation: generation,
            manifest: manifest,
            journal: journal,
            frames: frames,
            events: events,
            archiveName: root.lastPathComponent
        )
    }

    private func requireProjectionBytes(_ value: Any?, expected: [Data]) throws {
        guard let objects = value as? [Any], objects.count == expected.count else {
            throw ArchiveVerificationError.projectionMismatch
        }
        for (object, expectedData) in zip(objects, expected) {
            guard try archiveCanonicalData(object) == expectedData else {
                throw ArchiveVerificationError.digestMismatch
            }
        }
    }
}

private struct LoadedArchiveMember {
    let descriptor: VerifiedArchiveMemberDescriptor
    let data: Data
}

private struct VerifiedEventBinding {
    let record: VerifiedEventRecord
    let details: EventSemanticDetails
}

private struct VerifiedFrameBinding {
    let record: VerifiedFrameRecord
}

private struct EventSemanticDetails {
    let frameID: String?
    let idempotencyKey: String?
    let packetPath: String?
    let acceptedSequence: UInt64?
    let packetSHA256: String?
    let consentGranted: Bool?
    let acceptedFrameCount: UInt64?
    let finalizationState: String?
    let worldFrameID: String?
    let worldFrameVersion: UInt64?
    let previousWorldFrameID: String?
    let previousWorldFrameVersion: UInt64?
}

private struct ArchiveReadBoundary: Sendable {
    let root: URL

    init(root: URL) throws {
        guard root.isFileURL else { throw ArchiveVerificationError.invalidRoot }
        let standardized = root.standardizedFileURL
        let values: URLResourceValues
        do {
            values = try standardized.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        } catch {
            throw ArchiveVerificationError.invalidRoot
        }
        guard values.isDirectory == true, values.isSymbolicLink != true,
              standardized.resolvingSymlinksInPath().path == standardized.path
        else { throw ArchiveVerificationError.invalidRoot }
        self.root = standardized
    }

    func read(relativePath: String, maximumBytes: Int) throws -> Data {
        guard maximumBytes >= 0 else { throw ArchiveVerificationError.byteLimitExceeded }
        let url = try resolveRegularFile(relativePath)
        let before: URLResourceValues
        do {
            before = try url.resourceValues(
                forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
            )
        } catch {
            throw ArchiveVerificationError.ioFailure
        }
        guard before.isRegularFile == true, before.isSymbolicLink != true,
              let fileSize = before.fileSize, fileSize <= maximumBytes
        else {
            if before.fileSize.map({ $0 > maximumBytes }) == true {
                throw ArchiveVerificationError.byteLimitExceeded
            }
            throw ArchiveVerificationError.invalidPath
        }
        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw ArchiveVerificationError.ioFailure
        }
        guard data.count <= maximumBytes else {
            throw ArchiveVerificationError.byteLimitExceeded
        }
        let after = try? url.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
        guard after?.isSymbolicLink != true, after?.fileSize == data.count else {
            throw ArchiveVerificationError.ioFailure
        }
        return data
    }

    private func resolveRegularFile(_ relativePath: String) throws -> URL {
        do {
            try ArchivePath.validate(relativePath)
        } catch {
            throw ArchiveVerificationError.invalidPath
        }
        var lexical = root
        let segments = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        for (index, segment) in segments.enumerated() {
            lexical = lexical.appendingPathComponent(String(segment), isDirectory: index < segments.count - 1)
            let values = try? lexical.resourceValues(
                forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
            )
            guard values?.isSymbolicLink != true else {
                throw ArchiveVerificationError.invalidPath
            }
            if index < segments.count - 1, values?.isDirectory != true {
                throw ArchiveVerificationError.ioFailure
            }
        }
        let resolved: URL
        do {
            resolved = try ArchivePath.resolve(relativePath, under: root)
        } catch {
            throw ArchiveVerificationError.invalidPath
        }
        guard resolved.path == lexical.standardizedFileURL.path,
              resolved.path.hasPrefix(root.path + "/")
        else { throw ArchiveVerificationError.invalidPath }
        return resolved
    }
}

private func requireCanonicalJSON(_ data: Data) throws -> Data {
    do {
        return try CanonicalJSON.canonicalize(jsonData: data)
    } catch {
        throw ArchiveVerificationError.invalidJSON
    }
}

private func archiveJSONObject(_ data: Data) throws -> [String: Any] {
    do {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ArchiveVerificationError.invalidJSON
        }
        return object
    } catch let error as ArchiveVerificationError {
        throw error
    } catch {
        throw ArchiveVerificationError.invalidJSON
    }
}

private func archiveCanonicalData(_ value: Any) throws -> Data {
    do {
        let encoded = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return try CanonicalJSON.canonicalize(jsonData: encoded)
    } catch let error as ArchiveVerificationError {
        throw error
    } catch {
        throw ArchiveVerificationError.invalidJSON
    }
}

private func archiveUInt(_ value: Any?) -> UInt64? {
    guard let number = value as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID(),
          number.doubleValue >= 0,
          number.doubleValue.rounded(.towardZero) == number.doubleValue,
          number.doubleValue <= 9_007_199_254_740_991
    else { return nil }
    return number.uint64Value
}

private func archiveDouble(_ value: Any?) -> Double? {
    guard let number = value as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID()
    else { return nil }
    return number.doubleValue
}

private func archiveDoubleArray(_ value: Any?) -> [Double]? {
    guard let values = value as? [Any] else { return nil }
    let doubles = values.compactMap(archiveDouble)
    return doubles.count == values.count ? doubles : nil
}

private func compareDecimalTimestamp(_ left: String, _ right: String) -> ComparisonResult {
    if left.count != right.count {
        return left.count < right.count ? .orderedAscending : .orderedDescending
    }
    if left == right { return .orderedSame }
    return left < right ? .orderedAscending : .orderedDescending
}

private func isStableID(_ value: String, prefix: String) -> Bool {
    value.range(
        of: "^\(NSRegularExpression.escapedPattern(for: prefix))[0-9a-f]{8}-[0-9a-f]{4}-[47][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
        options: .regularExpression
    ) != nil
}

private extension ArchiveVerificationError {
    init(_ rejection: ContractValidationRejection) {
        self = switch rejection {
        case .jsonParse: .invalidJSON
        case .schemaValidation: .schemaValidation
        case .unsupportedContractVersion: .unsupportedContractVersion
        case .unknownProperty: .unknownProperty
        case .invalidIdentity: .invalidIdentity
        case .invalidPath: .invalidPath
        case .numericOutOfRange: .numericOutOfRange
        case .semanticInvariant: .semanticInvariant
        case .digestMismatch: .digestMismatch
        }
    }
}
