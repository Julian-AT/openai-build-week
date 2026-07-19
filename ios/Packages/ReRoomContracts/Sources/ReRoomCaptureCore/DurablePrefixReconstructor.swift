import Foundation
import ReRoomContracts

struct RecoveryCandidateMember: Equatable, Sendable {
    let descriptor: VerifiedArchiveMemberDescriptor
    let data: Data
}

struct RecoveryInvalidSuffix: Equatable, Sendable {
    let firstInvalidJournalSequence: UInt64
    let bytes: Data
    let sha256: String
    let metadataData: Data
}

/// One immutable, exact-byte recovery result. It is evidence only until the
/// pointer-last publisher introduced by the next plan makes it visible.
struct RecoveryGenerationCandidate: Equatable, Sendable {
    let sourceIdentity: VerifiedArchiveSourceIdentity
    let manifestData: Data
    let members: [RecoveryCandidateMember]
    let journalData: Data
    let invalidSuffix: RecoveryInvalidSuffix?
    let acceptedPrefixJournalSHA256: String
    let finalizationState: CaptureFinalizationState
    let manifestSHA256: String
    let lastDurableJournalSequence: UInt64
    let acceptedFrameCount: UInt64
    let eventCount: UInt64

    var acceptedJournalRecordCount: UInt64 {
        lastDurableJournalSequence + 1
    }

    func recoveredArchive(archivePath: String) throws -> RecoveredArchive {
        let finalization = try CaptureFinalization(
            sessionID: sourceIdentity.sessionID,
            archivePath: archivePath,
            state: finalizationState,
            manifestSHA256: manifestSHA256,
            lastDurableJournalSequence: lastDurableJournalSequence,
            acceptedFrameCount: acceptedFrameCount,
            eventCount: eventCount
        )
        return try RecoveredArchive(
            finalization: finalization,
            acceptedJournalRecordCount: acceptedJournalRecordCount,
            firstInvalidJournalSequence: invalidSuffix?.firstInvalidJournalSequence,
            quarantineSHA256: invalidSuffix?.sha256
        )
    }

    /// Test/staging support only. Visibility publication is deliberately not
    /// performed here; Plan 03 owns the generation pointer commit.
    func materialize(at root: URL) throws {
        guard root.isFileURL,
              FileManager.default.fileExists(atPath: root.path) == false
        else { throw CaptureRecoveryError.publicationConflict }

        var ownsRoot = false
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            ownsRoot = true
            try write(journalData, relativePath: "journal/global.jsonl", under: root)
            for member in members {
                try write(member.data, relativePath: member.descriptor.relativePath, under: root)
            }
            try write(manifestData, relativePath: "manifest.json", under: root)
        } catch let error as CaptureRecoveryError {
            if ownsRoot { try? FileManager.default.removeItem(at: root) }
            throw error
        } catch {
            if ownsRoot { try? FileManager.default.removeItem(at: root) }
            throw CaptureRecoveryError.ioFailure
        }
    }

    private func write(_ data: Data, relativePath: String, under root: URL) throws {
        let destination: URL
        do {
            destination = try ArchivePath.resolve(relativePath, under: root)
        } catch {
            throw CaptureRecoveryError.invalidPath
        }
        let parent = destination.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: parent,
                withIntermediateDirectories: true
            )
            try data.write(to: destination, options: .withoutOverwriting)
        } catch {
            throw CaptureRecoveryError.ioFailure
        }
    }
}

struct DurablePrefixReconstructor: Sendable {
    private static let recordDigestScope =
        "entire_event_record_with_record_sha256_member_omitted"
    private static let manifestDigestScope =
        "entire_manifest_with_finalization_manifest_sha256_member_omitted"

    let verifier: ArchiveVerifier

    func reconstruct(
        source: VerifiedRecoverySource,
        root: URL
    ) throws -> RecoveryGenerationCandidate {
        let boundary = try RecoveryReadBoundary(root: root)
        let manifestData = try boundary.read(
            relativePath: "manifest.json",
            maximumBytes: ArchiveVerifier.maximumManifestBytes
        )
        guard manifestData.count == source.manifest.byteLength,
              CanonicalJSON.sha256Hex(manifestData) == source.manifest.sha256
        else { throw CaptureRecoveryError.digestMismatch }
        let sourceManifest = try recoveryObject(manifestData)
        guard sourceManifest["session_id"] as? String == source.sourceIdentity.sessionID else {
            throw CaptureRecoveryError.invalidManifest
        }

        let journalData: Data
        do {
            journalData = try boundary.read(
                relativePath: "journal/global.jsonl",
                maximumBytes: CaptureRecovery.maximumJournalBytes
            )
        } catch CaptureRecoveryError.ioFailure {
            throw CaptureRecoveryError.missingJournal
        }
        guard journalData.isEmpty == false else { throw CaptureRecoveryError.emptyJournal }

        let scan = try scan(
            journalData: journalData,
            sourceIdentity: source.sourceIdentity,
            boundary: boundary
        )
        guard scan.journal.isEmpty == false else {
            throw CaptureRecoveryError.noRecoverablePrefix
        }
        let state: CaptureFinalizationState = scan.containsFinalization
            ? .finalized
            : .recoveredPrefix
        if state == .finalized, scan.invalidSuffix != nil {
            throw CaptureRecoveryError.interiorCorruption
        }

        let manifest = try buildManifest(
            source: sourceManifest,
            state: state,
            journal: scan.journal,
            events: scan.events,
            frames: scan.frames,
            members: scan.members
        )
        let candidate = RecoveryGenerationCandidate(
            sourceIdentity: source.sourceIdentity,
            manifestData: manifest.data,
            members: scan.members,
            journalData: scan.acceptedJournalData,
            invalidSuffix: scan.invalidSuffix,
            acceptedPrefixJournalSHA256: CanonicalJSON.sha256Hex(scan.acceptedJournalData),
            finalizationState: state,
            manifestSHA256: manifest.sha256,
            lastDurableJournalSequence: UInt64(scan.journal.count - 1),
            acceptedFrameCount: UInt64(scan.frames.count),
            eventCount: UInt64(scan.events.count)
        )
        try independentlyVerify(candidate)
        return candidate
    }

    private func scan(
        journalData: Data,
        sourceIdentity: VerifiedArchiveSourceIdentity,
        boundary: RecoveryReadBoundary
    ) throws -> RecoveryScan {
        let chunks = recoveryJournalChunks(journalData)
        guard chunks.isEmpty == false else { throw CaptureRecoveryError.emptyJournal }
        guard chunks.count <= ArchiveVerifier.maximumJournalRecords + 1 else {
            throw CaptureRecoveryError.byteLimitExceeded
        }

        var journal = [[String: Any]]()
        var events = [[String: Any]]()
        var frames = [[String: Any]]()
        var eventMembers = [RecoveryCandidateMember]()
        var frameMembers = [[RecoveryCandidateMember]]()
        var references = Set<String>()
        var acknowledgedFrames = Set<String>()
        var acceptedEnd = 0
        var suffixStart: Int?
        var containsFinalization = false

        for (index, chunk) in chunks.enumerated() {
            let recordData = journalData.subdata(in: chunk.contentRange)
            let parsed: [String: Any]
            do {
                parsed = try parseJournalRecord(recordData)
            } catch {
                suffixStart = try classifyTerminalFault(
                    at: index,
                    chunks: chunks,
                    journalData: journalData,
                    acceptedCount: journal.count
                )
                break
            }

            guard let sequence = recoveryUInt(parsed["journal_sequence"]) else {
                suffixStart = try classifyTerminalFault(
                    at: index,
                    chunks: chunks,
                    journalData: journalData,
                    acceptedCount: journal.count
                )
                break
            }
            guard sequence == UInt64(journal.count) else {
                throw CaptureRecoveryError.nonContiguousJournal
            }
            guard chunk.isNewlineTerminated else {
                suffixStart = try classifyTerminalFault(
                    at: index,
                    chunks: chunks,
                    journalData: journalData,
                    acceptedCount: journal.count
                )
                break
            }
            guard let entryType = parsed["entry_type"] as? String,
                  let referenceID = parsed["reference_id"] as? String,
                  let timestamp = parsed["monotonic_timestamp_ns"] as? String,
                  let contentSHA256 = parsed["content_sha256"] as? String,
                  recoveryIsTimestamp(timestamp),
                  recoveryIsDigest(contentSHA256),
                  references.insert(referenceID).inserted
            else { throw CaptureRecoveryError.interiorCorruption }
            if containsFinalization {
                throw CaptureRecoveryError.interiorCorruption
            }

            do {
                switch entryType {
                case "event":
                    guard recoveryIsStableID(referenceID, prefix: "event_") else {
                        throw RecoveryRecordFault.referenceContradiction
                    }
                    let result = try reconstructEvent(
                        eventSequence: UInt64(events.count),
                        journalSequence: sequence,
                        eventID: referenceID,
                        timestamp: timestamp,
                        contentSHA256: contentSHA256,
                        sessionID: sourceIdentity.sessionID,
                        boundary: boundary
                    )
                    events.append(result.projection)
                    eventMembers.append(result.member)
                    if result.type == "frame_server_acknowledged",
                       let frameID = result.details["frame_id"] as? String {
                        acknowledgedFrames.insert(frameID)
                    }
                    containsFinalization = result.type == "session_finalized"
                case "frame":
                    guard recoveryIsStableID(referenceID, prefix: "frame_") else {
                        throw RecoveryRecordFault.referenceContradiction
                    }
                    let result = try reconstructFrame(
                        acceptedSequence: UInt64(frames.count),
                        journalSequence: sequence,
                        frameID: referenceID,
                        contentSHA256: contentSHA256,
                        sessionID: sourceIdentity.sessionID,
                        boundary: boundary
                    )
                    frames.append(result.projection)
                    frameMembers.append([result.packet, result.image])
                default:
                    throw RecoveryRecordFault.referenceContradiction
                }
            } catch RecoveryRecordFault.contentDigestMismatch {
                suffixStart = try classifyTerminalFault(
                    at: index,
                    chunks: chunks,
                    journalData: journalData,
                    acceptedCount: journal.count
                )
                break
            } catch RecoveryRecordFault.referenceContradiction {
                throw CaptureRecoveryError.interiorCorruption
            }

            journal.append(parsed)
            acceptedEnd = chunk.rawRange.upperBound
        }

        guard journal.isEmpty == false else { throw CaptureRecoveryError.noRecoverablePrefix }
        for index in frames.indices {
            let frameID = frames[index]["frame_id"] as! String
            frames[index]["server_acknowledged"] = acknowledgedFrames.contains(frameID)
        }
        let acceptedJournalData = journalData.subdata(in: 0..<acceptedEnd)
        let members = eventMembers + frameMembers.flatMap { $0 }
        guard journal.count <= ArchiveVerifier.maximumJournalRecords,
              members.count <= ArchiveVerifier.maximumInventoryMembers
        else { throw CaptureRecoveryError.byteLimitExceeded }
        var aggregateMemberBytes = 0
        for member in members {
            guard aggregateMemberBytes
                    <= ArchiveVerifier.maximumAggregateMemberBytes - member.data.count
            else { throw CaptureRecoveryError.byteLimitExceeded }
            aggregateMemberBytes += member.data.count
        }
        let invalidSuffix: RecoveryInvalidSuffix?
        if let suffixStart {
            let bytes = journalData.subdata(in: suffixStart..<journalData.count)
            let digest = CanonicalJSON.sha256Hex(bytes)
            let metadata: [String: Any] = [
                "accepted_inventory_member": false,
                "first_invalid_journal_sequence": journal.count,
                "suffix_byte_length": bytes.count,
                "suffix_sha256": digest,
            ]
            invalidSuffix = RecoveryInvalidSuffix(
                firstInvalidJournalSequence: UInt64(journal.count),
                bytes: bytes,
                sha256: digest,
                metadataData: try recoveryCanonicalData(metadata)
            )
        } else {
            invalidSuffix = nil
        }
        return RecoveryScan(
            journal: journal,
            events: events,
            frames: frames,
            members: members,
            acceptedJournalData: acceptedJournalData,
            invalidSuffix: invalidSuffix,
            containsFinalization: containsFinalization
        )
    }

    private func reconstructEvent(
        eventSequence: UInt64,
        journalSequence: UInt64,
        eventID: String,
        timestamp: String,
        contentSHA256: String,
        sessionID: String,
        boundary: RecoveryReadBoundary
    ) throws -> RecoveryEventResult {
        let path = "events/event_\(String(format: "%04llu", eventSequence)).json"
        let data: Data
        do {
            data = try boundary.read(
                relativePath: path,
                maximumBytes: ArchiveVerifier.maximumMemberBytes
            )
        } catch {
            throw RecoveryRecordFault.referenceContradiction
        }
        let canonical: Data
        let payload: [String: Any]
        do {
            canonical = try CanonicalJSON.canonicalize(jsonData: data)
            payload = try recoveryObject(data)
        } catch {
            throw RecoveryRecordFault.referenceContradiction
        }
        guard canonical == data,
              Set(payload.keys) == Set(["details", "event_version", "session_id", "type"]),
              payload["event_version"] as? String == "1.0.0",
              payload["session_id"] as? String == sessionID,
              let type = payload["type"] as? String,
              let details = payload["details"] as? [String: Any]
        else { throw RecoveryRecordFault.referenceContradiction }

        let payloadSHA256 = CanonicalJSON.sha256Hex(data)
        var projection: [String: Any] = [
            "event_id": eventID,
            "event_sequence": eventSequence,
            "durable_journal_sequence": journalSequence,
            "monotonic_timestamp_ns": timestamp,
            "type": type,
            "payload_sha256": payloadSHA256,
            "payload_path": path,
            "record_sha256_algorithm": "RR-JCS-SHA256-1",
            "record_sha256_scope": Self.recordDigestScope,
        ]
        let recordSHA256 = CanonicalJSON.sha256Hex(try recoveryCanonicalData(projection))
        guard recordSHA256 == contentSHA256 else {
            throw RecoveryRecordFault.contentDigestMismatch
        }
        projection["record_sha256"] = recordSHA256
        return RecoveryEventResult(
            projection: projection,
            member: recoveryMember(
                path: path,
                mediaType: "application/json",
                codec: "json_jcs_1",
                role: "event_log",
                data: data
            ),
            type: type,
            details: details
        )
    }

    private func reconstructFrame(
        acceptedSequence: UInt64,
        journalSequence: UInt64,
        frameID: String,
        contentSHA256: String,
        sessionID: String,
        boundary: RecoveryReadBoundary
    ) throws -> RecoveryFrameResult {
        let packetPath = "frames/\(frameID)/packet.json"
        let packetData: Data
        do {
            packetData = try boundary.read(
                relativePath: packetPath,
                maximumBytes: ArchiveVerifier.maximumMemberBytes
            )
        } catch {
            throw RecoveryRecordFault.referenceContradiction
        }
        let packet: [String: Any]
        do {
            guard try CanonicalJSON.canonicalize(jsonData: packetData) == packetData else {
                throw RecoveryRecordFault.referenceContradiction
            }
            packet = try recoveryObject(packetData)
        } catch let fault as RecoveryRecordFault {
            throw fault
        } catch {
            throw RecoveryRecordFault.referenceContradiction
        }
        guard CanonicalJSON.sha256Hex(packetData) == contentSHA256 else {
            throw RecoveryRecordFault.contentDigestMismatch
        }
        guard packet["session_id"] as? String == sessionID,
              packet["frame_id"] as? String == frameID,
              let image = packet["image"] as? [String: Any],
              let codec = image["codec"] as? String,
              let payload = image["payload"] as? [String: Any],
              payload["kind"] as? String == "rrcap_file",
              let imagePath = payload["relative_path"] as? String,
              imagePath.hasPrefix("frames/\(frameID)/image."),
              let imageSHA256 = payload["sha256"] as? String,
              let imageByteLength = recoveryUInt(payload["byte_length"])
        else { throw RecoveryRecordFault.referenceContradiction }
        let imageData: Data
        do {
            imageData = try boundary.read(
                relativePath: imagePath,
                maximumBytes: ArchiveVerifier.maximumMemberBytes
            )
        } catch {
            throw RecoveryRecordFault.referenceContradiction
        }
        guard UInt64(imageData.count) == imageByteLength,
              CanonicalJSON.sha256Hex(imageData) == imageSHA256,
              packet["payload_sha256"] as? String == imageSHA256
        else { throw RecoveryRecordFault.referenceContradiction }

        return RecoveryFrameResult(
            projection: [
                "sequence": acceptedSequence,
                "frame_id": frameID,
                "packet_path": packetPath,
                "packet_sha256": contentSHA256,
                "durable_journal_sequence": journalSequence,
                "server_acknowledged": false,
            ],
            packet: recoveryMember(
                path: packetPath,
                mediaType: "application/json",
                codec: "json_jcs_1",
                role: "frame_metadata",
                data: packetData
            ),
            image: recoveryMember(
                path: imagePath,
                mediaType: recoveryMediaType(codec),
                codec: codec,
                role: "frame_image",
                data: imageData
            )
        )
    }

    private func classifyTerminalFault(
        at index: Int,
        chunks: [RecoveryJournalChunk],
        journalData: Data,
        acceptedCount: Int
    ) throws -> Int {
        guard acceptedCount > 0 else { throw CaptureRecoveryError.noRecoverablePrefix }
        if index + 1 < chunks.count {
            for later in chunks[(index + 1)...] {
                let data = journalData.subdata(in: later.contentRange)
                if (try? parseJournalRecord(data)) != nil {
                    throw CaptureRecoveryError.interiorCorruption
                }
            }
        }
        return chunks[index].rawRange.lowerBound
    }

    private func parseJournalRecord(_ data: Data) throws -> [String: Any] {
        guard data.isEmpty == false,
              try CanonicalJSON.canonicalize(jsonData: data) == data
        else { throw CaptureRecoveryError.invalidJSON }
        let value = try recoveryObject(data)
        guard Set(value.keys) == Set([
            "journal_sequence", "monotonic_timestamp_ns", "entry_type", "reference_id",
            "content_sha256",
        ]) else { throw CaptureRecoveryError.invalidJSON }
        return value
    }

    private func buildManifest(
        source: [String: Any],
        state: CaptureFinalizationState,
        journal: [[String: Any]],
        events: [[String: Any]],
        frames: [[String: Any]],
        members: [RecoveryCandidateMember]
    ) throws -> (data: Data, sha256: String) {
        guard let formatVersion = source["format_version"],
              let captureKind = source["capture_kind"],
              let sessionID = source["session_id"],
              let archiveSource = source["source"],
              let coordinates = source["coordinate_convention"],
              let settings = source["capture_settings"],
              let privacy = source["privacy"],
              let keyframes = source["keyframes"] as? [Any],
              keyframes.isEmpty
        else { throw CaptureRecoveryError.invalidManifest }

        let tuples: [[Any]] = try journal.map { entry in
            guard let sequence = recoveryUInt(entry["journal_sequence"]),
                  let entryType = entry["entry_type"] as? String,
                  let referenceID = entry["reference_id"] as? String,
                  let contentSHA256 = entry["content_sha256"] as? String
            else { throw CaptureRecoveryError.invalidManifest }
            return [sequence, entryType, referenceID, contentSHA256]
        }
        let files: [[String: Any]] = members.map { member in
            [
                "relative_path": member.descriptor.relativePath,
                "media_type": member.descriptor.mediaType,
                "codec": member.descriptor.codec,
                "byte_length": member.descriptor.byteLength,
                "sha256": member.descriptor.sha256,
                "role": member.descriptor.role,
            ]
        }
        var root: [String: Any] = [
            "format_version": formatVersion,
            "capture_kind": captureKind,
            "session_id": sessionID,
            "source": archiveSource,
            "coordinate_convention": coordinates,
            "capture_settings": settings,
            "files": files,
            "journal": journal,
            "accepted_frame_order": frames,
            "keyframes": [],
            "events": events,
            "replay": [
                "ordering_authority": "global_journal_sequence",
                "input_digest_algorithm": "RR-JCS-SHA256-1",
                "input_digest_scope":
                    "jcs_array_of_journal_sequence_entry_type_reference_id_content_sha256",
                "input_digest": CanonicalJSON.sha256Hex(try recoveryCanonicalData(tuples)),
                "neural_determinism": "tolerance_based_when_provider_pinned",
                "provider_lock": [],
            ],
            "privacy": privacy,
            "finalization": [
                "state": state.rawValue,
                "manifest_sha256_algorithm": "RR-JCS-SHA256-1",
                "manifest_sha256_scope": Self.manifestDigestScope,
                "last_durable_journal_sequence": journal.count - 1,
            ],
        ]
        let digest = CanonicalJSON.sha256Hex(try recoveryCanonicalData(root))
        var finalization = root["finalization"] as! [String: Any]
        finalization["manifest_sha256"] = digest
        root["finalization"] = finalization
        return (try recoveryCanonicalData(root), digest)
    }

    private func independentlyVerify(_ candidate: RecoveryGenerationCandidate) throws {
        let validationRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("reroom-recovery-validation-\(UUID().uuidString.lowercased()).rrcap")
        defer { try? FileManager.default.removeItem(at: validationRoot) }
        do {
            try candidate.materialize(at: validationRoot)
            let verified = try verifier.verify(root: validationRoot)
            guard verified.manifest.sha256 == CanonicalJSON.sha256Hex(candidate.manifestData),
                  verified.manifest.journalRecordCount == Int(candidate.acceptedJournalRecordCount),
                  verified.manifest.acceptedFrameCount == Int(candidate.acceptedFrameCount),
                  verified.manifest.eventCount == Int(candidate.eventCount),
                  verified.members == candidate.members.map(\.descriptor).sorted(by: {
                      $0.relativePath < $1.relativePath
                  })
            else { throw CaptureRecoveryError.projectionMismatch }
        } catch let error as CaptureRecoveryError {
            throw error
        } catch let error as ArchiveVerificationError {
            throw CaptureRecoveryError(error)
        } catch {
            throw CaptureRecoveryError.invalidManifest
        }
    }
}

private struct RecoveryScan {
    let journal: [[String: Any]]
    let events: [[String: Any]]
    let frames: [[String: Any]]
    let members: [RecoveryCandidateMember]
    let acceptedJournalData: Data
    let invalidSuffix: RecoveryInvalidSuffix?
    let containsFinalization: Bool
}

private struct RecoveryEventResult {
    let projection: [String: Any]
    let member: RecoveryCandidateMember
    let type: String
    let details: [String: Any]
}

private struct RecoveryFrameResult {
    let projection: [String: Any]
    let packet: RecoveryCandidateMember
    let image: RecoveryCandidateMember
}

private enum RecoveryRecordFault: Error {
    case contentDigestMismatch
    case referenceContradiction
}

private struct RecoveryJournalChunk {
    let contentRange: Range<Int>
    let rawRange: Range<Int>
    let isNewlineTerminated: Bool
}

private struct RecoveryReadBoundary {
    let root: URL

    init(root: URL) throws {
        guard root.isFileURL else { throw CaptureRecoveryError.invalidRoot }
        let values = try? root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values?.isDirectory == true, values?.isSymbolicLink != true else {
            throw CaptureRecoveryError.invalidRoot
        }
        self.root = root.standardizedFileURL
    }

    func read(relativePath: String, maximumBytes: Int) throws -> Data {
        guard maximumBytes > 0 else { throw CaptureRecoveryError.byteLimitExceeded }
        let url: URL
        do {
            url = try ArchivePath.resolve(relativePath, under: root)
        } catch {
            throw CaptureRecoveryError.invalidPath
        }
        try rejectSymbolicLinks(relativePath: relativePath)
        let values = try? url.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        )
        guard values?.isRegularFile == true, values?.isSymbolicLink != true else {
            throw CaptureRecoveryError.ioFailure
        }
        guard let size = values?.fileSize, size <= maximumBytes else {
            throw CaptureRecoveryError.byteLimitExceeded
        }
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard data.count <= maximumBytes else {
                throw CaptureRecoveryError.byteLimitExceeded
            }
            return data
        } catch let error as CaptureRecoveryError {
            throw error
        } catch {
            throw CaptureRecoveryError.ioFailure
        }
    }

    private func rejectSymbolicLinks(relativePath: String) throws {
        var cursor = root
        for component in relativePath.split(separator: "/") {
            cursor.appendPathComponent(String(component))
            let values = try? cursor.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values?.isSymbolicLink != true else {
                throw CaptureRecoveryError.invalidPath
            }
        }
    }
}

private func recoveryJournalChunks(_ data: Data) -> [RecoveryJournalChunk] {
    var chunks = [RecoveryJournalChunk]()
    var start = 0
    for index in data.indices where data[index] == 0x0a {
        chunks.append(
            RecoveryJournalChunk(
                contentRange: start..<index,
                rawRange: start..<(index + 1),
                isNewlineTerminated: true
            )
        )
        start = index + 1
    }
    if start < data.count {
        chunks.append(
            RecoveryJournalChunk(
                contentRange: start..<data.count,
                rawRange: start..<data.count,
                isNewlineTerminated: false
            )
        )
    }
    return chunks
}

private func recoveryMember(
    path: String,
    mediaType: String,
    codec: String,
    role: String,
    data: Data
) -> RecoveryCandidateMember {
    RecoveryCandidateMember(
        descriptor: VerifiedArchiveMemberDescriptor(
            relativePath: path,
            mediaType: mediaType,
            codec: codec,
            byteLength: data.count,
            sha256: CanonicalJSON.sha256Hex(data),
            role: role
        ),
        data: data
    )
}

private func recoveryMediaType(_ codec: String) -> String {
    switch codec {
    case "jpeg": "image/jpeg"
    case "png": "image/png"
    default: "image/heic"
    }
}

private func recoveryCanonicalData(_ value: Any) throws -> Data {
    let encoded: Data
    do {
        encoded = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    } catch {
        throw CaptureRecoveryError.invalidJSON
    }
    do {
        return try CanonicalJSON.canonicalize(jsonData: encoded)
    } catch {
        throw CaptureRecoveryError.invalidJSON
    }
}

private func recoveryObject(_ data: Data) throws -> [String: Any] {
    do {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CaptureRecoveryError.invalidJSON
        }
        return value
    } catch let error as CaptureRecoveryError {
        throw error
    } catch {
        throw CaptureRecoveryError.invalidJSON
    }
}

private func recoveryUInt(_ value: Any?) -> UInt64? {
    guard let number = value as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID()
    else { return nil }
    let decimal = number.stringValue
    guard decimal.range(of: #"^(0|[1-9][0-9]*)$"#, options: .regularExpression) != nil else {
        return nil
    }
    return UInt64(decimal)
}

private func recoveryIsStableID(_ value: String, prefix: String) -> Bool {
    value.range(
        of: "^\(prefix)[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
        options: .regularExpression
    ) != nil
}

private func recoveryIsDigest(_ value: String) -> Bool {
    value.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil
}

private func recoveryIsTimestamp(_ value: String) -> Bool {
    value.range(of: #"^(0|[1-9][0-9]*)$"#, options: .regularExpression) != nil
}
