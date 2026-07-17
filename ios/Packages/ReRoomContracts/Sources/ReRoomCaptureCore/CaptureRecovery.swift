import Foundation
import ReRoomContracts

public enum CaptureRecoveryError: String, Error, Equatable, Sendable {
    case missingManifest = "missing_manifest"
    case missingJournal = "missing_journal"
    case emptyJournal = "empty_journal"
    case invalidRoot = "invalid_root"
    case invalidJSON = "invalid_json"
    case invalidManifest = "invalid_manifest"
    case invalidPath = "invalid_path"
    case byteLimitExceeded = "byte_limit_exceeded"
    case digestMismatch = "digest_mismatch"
    case projectionMismatch = "projection_mismatch"
    case unsupportedContractVersion = "unsupported_contract_version"
    case unsupportedCodec = "unsupported_codec"
    case unsupportedDigest = "unsupported_digest"
    case nonContiguousJournal = "non_contiguous_journal"
    case interiorCorruption = "interior_corruption"
    case noRecoverablePrefix = "no_recoverable_prefix"
    case publicationConflict = "publication_conflict"
    case ioFailure = "io_failure"
}

public enum CaptureRecoveryPublicationStage: String, Equatable, Sendable {
    case beforePublish = "before_publish"
}

public typealias CaptureRecoveryPublicationObserver = @Sendable (
    CaptureRecoveryPublicationStage
) throws -> Void

public enum CaptureRecovery {
    static let maximumDocumentBytes = 33_554_432
    static let maximumJournalBytes = 33_554_432
    static let maximumInventoryMembers = 2_048

    public static func inspect(root: URL) throws -> RecoveredArchive {
        try inspect(root: root, publicationObserver: { _ in })
    }

    public static func inspect(
        root: URL,
        publicationObserver: CaptureRecoveryPublicationObserver
    ) throws -> RecoveredArchive {
        let archive = try RecoveryArchiveReader(root: root).read()
        if archive.state != .open {
            return try archive.recoveredArchive()
        }
        return try recover(
            archive,
            publicationObserver: publicationObserver
        )
    }

    static func verifiedArchive(root: URL) throws -> RecoveryValidatedArchive {
        let archive = try RecoveryArchiveReader(root: root).read()
        guard archive.state != .open else { throw CaptureRecoveryError.invalidManifest }
        return archive
    }

    private static func recover(
        _ source: RecoveryValidatedArchive,
        publicationObserver: CaptureRecoveryPublicationObserver
    ) throws -> RecoveredArchive {
        let destination = recoveredURL(for: source.root)
        let quarantine = quarantineURL(for: source.root)
        if FileManager.default.fileExists(atPath: destination.path) {
            return try existingRecovery(at: destination, quarantine: quarantine)
        }

        let journalURL: URL
        do {
            journalURL = try ArchivePath.resolve("journal/global.jsonl", under: source.root)
        } catch {
            throw CaptureRecoveryError.invalidPath
        }
        guard FileManager.default.fileExists(atPath: journalURL.path) else {
            throw CaptureRecoveryError.missingJournal
        }
        let journalData = try boundedRead(journalURL, maximum: maximumJournalBytes)
        guard journalData.isEmpty == false else { throw CaptureRecoveryError.emptyJournal }

        let scan = try scanJournal(journalData, expected: source.journal)
        guard scan.acceptedCount > 0 else { throw CaptureRecoveryError.noRecoverablePrefix }
        let recoveredManifest = try source.recoveredManifest(acceptedCount: scan.acceptedCount)
        let recoveredManifestData = try canonicalData(recoveredManifest)

        let parent = source.root.deletingLastPathComponent()
        let nonce = UUID().uuidString.lowercased()
        let archiveStage = parent.appendingPathComponent(".recovery-staging-\(nonce).rrcap")
        let quarantineStage = parent.appendingPathComponent(".recovery-staging-\(nonce).quarantine")
        var publishedQuarantine = false
        var publishedArchive = false
        defer {
            if FileManager.default.fileExists(atPath: archiveStage.path) {
                try? FileManager.default.removeItem(at: archiveStage)
            }
            if FileManager.default.fileExists(atPath: quarantineStage.path) {
                try? FileManager.default.removeItem(at: quarantineStage)
            }
            if publishedArchive == false, FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.removeItem(at: destination)
            }
            if publishedQuarantine, publishedArchive == false,
               FileManager.default.fileExists(atPath: quarantine.path) {
                try? FileManager.default.removeItem(at: quarantine)
            }
        }

        do {
            try FileManager.default.createDirectory(at: archiveStage, withIntermediateDirectories: false)
            try copyAcceptedFiles(
                manifest: recoveredManifest,
                from: source.root,
                to: archiveStage
            )
            try recoveredManifestData.write(
                to: archiveStage.appendingPathComponent("manifest.json"),
                options: .atomic
            )

            let staged = try RecoveryArchiveReader(root: archiveStage).read()
            guard staged.state == .recoveredPrefix else {
                throw CaptureRecoveryError.invalidManifest
            }

            try FileManager.default.createDirectory(at: quarantineStage, withIntermediateDirectories: false)
            try scan.suffix.write(
                to: quarantineStage.appendingPathComponent("invalid-suffix.bin"),
                options: .atomic
            )
            let metadata: [String: Any] = [
                "accepted_inventory_member": false,
                "first_invalid_journal_sequence": scan.acceptedCount,
                "suffix_byte_length": scan.suffix.count,
                "suffix_sha256": scan.suffixSHA256,
            ]
            try canonicalData(metadata).write(
                to: quarantineStage.appendingPathComponent("metadata.json"),
                options: .atomic
            )

            try publicationObserver(.beforePublish)
            guard FileManager.default.fileExists(atPath: destination.path) == false,
                  FileManager.default.fileExists(atPath: quarantine.path) == false
            else { throw CaptureRecoveryError.publicationConflict }
            try FileManager.default.moveItem(at: quarantineStage, to: quarantine)
            publishedQuarantine = true
            try FileManager.default.moveItem(at: archiveStage, to: destination)
            publishedArchive = true
        } catch let error as CaptureRecoveryError {
            throw error
        } catch {
            throw error
        }

        let published = try RecoveryArchiveReader(root: destination).read()
        return try published.recoveredArchive(
            firstInvalidSequence: UInt64(scan.acceptedCount),
            quarantineSHA256: scan.suffixSHA256
        )
    }

    private static func existingRecovery(at root: URL, quarantine: URL) throws -> RecoveredArchive {
        let archive = try RecoveryArchiveReader(root: root).read()
        guard archive.state == .recoveredPrefix else {
            throw CaptureRecoveryError.publicationConflict
        }
        let metadataURL = quarantine.appendingPathComponent("metadata.json")
        let metadata = try object(try boundedRead(metadataURL, maximum: 4_096))
        guard let sequence = uint(metadata["first_invalid_journal_sequence"]),
              let digest = metadata["suffix_sha256"] as? String
        else { throw CaptureRecoveryError.publicationConflict }
        return try archive.recoveredArchive(
            firstInvalidSequence: sequence,
            quarantineSHA256: digest
        )
    }

    private static func scanJournal(
        _ data: Data,
        expected: [[String: Any]]
    ) throws -> RecoveryJournalScan {
        let chunks = journalChunks(data)
        guard chunks.isEmpty == false else { throw CaptureRecoveryError.emptyJournal }
        var accepted = 0
        var invalidOffset: Int?

        for (index, chunk) in chunks.enumerated() {
            let record = data.subdata(in: chunk.contentRange)
            let parsed: [String: Any]
            do {
                parsed = try object(record)
            } catch {
                if index == 0 { throw CaptureRecoveryError.noRecoverablePrefix }
                if index < chunks.count - 1 { throw CaptureRecoveryError.interiorCorruption }
                invalidOffset = chunk.rawRange.lowerBound
                break
            }

            guard let sequence = uint(parsed["journal_sequence"]) else {
                if index == 0 { throw CaptureRecoveryError.noRecoverablePrefix }
                if index < chunks.count - 1 { throw CaptureRecoveryError.interiorCorruption }
                invalidOffset = chunk.rawRange.lowerBound
                break
            }
            guard sequence == UInt64(index) else {
                throw CaptureRecoveryError.nonContiguousJournal
            }
            guard index < expected.count else {
                invalidOffset = chunk.rawRange.lowerBound
                break
            }
            if try canonicalData(parsed) != canonicalData(expected[index]) {
                if index == 0 { throw CaptureRecoveryError.noRecoverablePrefix }
                if index < chunks.count - 1 { throw CaptureRecoveryError.interiorCorruption }
                invalidOffset = chunk.rawRange.lowerBound
                break
            }
            accepted += 1
        }

        if invalidOffset == nil, accepted < expected.count {
            invalidOffset = data.count
        }
        guard let offset = invalidOffset else {
            throw CaptureRecoveryError.invalidManifest
        }
        let suffix = data.subdata(in: offset..<data.count)
        return RecoveryJournalScan(
            acceptedCount: accepted,
            suffix: suffix,
            suffixSHA256: CanonicalJSON.sha256Hex(suffix)
        )
    }

    private static func journalChunks(_ data: Data) -> [RecoveryJournalChunk] {
        var result = [RecoveryJournalChunk]()
        var start = 0
        for index in data.indices where data[index] == 0x0a {
            if index > start {
                result.append(
                    RecoveryJournalChunk(
                        contentRange: start..<index,
                        rawRange: start..<(index + 1)
                    )
                )
            }
            start = index + 1
        }
        if start < data.count {
            result.append(
                RecoveryJournalChunk(
                    contentRange: start..<data.count,
                    rawRange: start..<data.count
                )
            )
        }
        return result
    }

    private static func copyAcceptedFiles(
        manifest: [String: Any],
        from source: URL,
        to destination: URL
    ) throws {
        guard let files = manifest["files"] as? [[String: Any]] else {
            throw CaptureRecoveryError.invalidManifest
        }
        for file in files {
            guard let path = file["relative_path"] as? String else {
                throw CaptureRecoveryError.invalidManifest
            }
            let sourceURL = try safeURL(path, root: source)
            let destinationURL = try safeURL(path, root: destination)
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        }
    }

    private static func recoveredURL(for root: URL) -> URL {
        root.deletingPathExtension().appendingPathExtension("recovered-prefix.rrcap")
    }

    private static func quarantineURL(for root: URL) -> URL {
        root.deletingPathExtension().appendingPathExtension("quarantine")
    }
}

final class RecoveryValidatedArchive {
    let root: URL
    let manifest: [String: Any]
    let manifestData: Data
    let state: CaptureFinalizationState
    let sessionID: String
    let manifestSHA256: String
    let files: [[String: Any]]
    let journal: [[String: Any]]
    let frames: [[String: Any]]
    let events: [[String: Any]]

    init(
        root: URL,
        manifest: [String: Any],
        manifestData: Data,
        state: CaptureFinalizationState,
        sessionID: String,
        manifestSHA256: String,
        files: [[String: Any]],
        journal: [[String: Any]],
        frames: [[String: Any]],
        events: [[String: Any]]
    ) {
        self.root = root
        self.manifest = manifest
        self.manifestData = manifestData
        self.state = state
        self.sessionID = sessionID
        self.manifestSHA256 = manifestSHA256
        self.files = files
        self.journal = journal
        self.frames = frames
        self.events = events
    }

    func recoveredArchive(
        firstInvalidSequence: UInt64? = nil,
        quarantineSHA256: String? = nil
    ) throws -> RecoveredArchive {
        let finalizationObject = try requiredObject(manifest, "finalization")
        guard let last = uint(finalizationObject["last_durable_journal_sequence"]) else {
            throw CaptureRecoveryError.invalidManifest
        }
        let finalization = try CaptureFinalization(
            sessionID: sessionID,
            archivePath: root.lastPathComponent,
            state: state,
            manifestSHA256: manifestSHA256,
            lastDurableJournalSequence: last,
            acceptedFrameCount: UInt64(frames.count),
            eventCount: UInt64(events.count)
        )
        return try RecoveredArchive(
            finalization: finalization,
            acceptedJournalRecordCount: UInt64(journal.count),
            firstInvalidJournalSequence: firstInvalidSequence,
            quarantineSHA256: quarantineSHA256
        )
    }

    func recoveredManifest(acceptedCount: Int) throws -> [String: Any] {
        guard (1...journal.count).contains(acceptedCount) else {
            throw CaptureRecoveryError.noRecoverablePrefix
        }
        var result = manifest
        let acceptedJournal = Array(journal.prefix(acceptedCount))
        let acceptedEvents = events.filter {
            guard let sequence = uint($0["durable_journal_sequence"]) else { return false }
            return sequence < UInt64(acceptedCount)
        }
        let acceptedFrames = frames.filter {
            guard let sequence = uint($0["durable_journal_sequence"]) else { return false }
            return sequence < UInt64(acceptedCount)
        }

        var acceptedPaths = Set<String>()
        for event in acceptedEvents {
            if let path = event["payload_path"] as? String { acceptedPaths.insert(path) }
        }
        for frame in acceptedFrames {
            guard let path = frame["packet_path"] as? String else { continue }
            acceptedPaths.insert(path)
            let packetURL = try safeURL(path, root: root)
            let packet = try object(try boundedRead(packetURL, maximum: CaptureRecovery.maximumDocumentBytes))
            if let image = packet["image"] as? [String: Any],
               let payload = image["payload"] as? [String: Any],
               let imagePath = payload["relative_path"] as? String {
                acceptedPaths.insert(imagePath)
            }
        }
        let acceptedFiles = files.filter {
            guard let path = $0["relative_path"] as? String else { return false }
            return acceptedPaths.contains(path)
        }
        guard acceptedFiles.count == acceptedPaths.count else {
            throw CaptureRecoveryError.projectionMismatch
        }

        result["journal"] = acceptedJournal
        result["events"] = acceptedEvents
        result["accepted_frame_order"] = acceptedFrames
        result["files"] = acceptedFiles

        var replay = try requiredObject(result, "replay")
        replay["input_digest"] = try journalInputDigest(acceptedJournal)
        result["replay"] = replay

        var finalization = try requiredObject(result, "finalization")
        finalization["state"] = CaptureFinalizationState.recoveredPrefix.rawValue
        finalization["last_durable_journal_sequence"] = acceptedCount - 1
        finalization.removeValue(forKey: "manifest_sha256")
        result["finalization"] = finalization
        let digest = CanonicalJSON.sha256Hex(try canonicalData(result))
        finalization["manifest_sha256"] = digest
        result["finalization"] = finalization
        return result
    }
}

private struct RecoveryArchiveReader {
    let root: URL

    func read() throws -> RecoveryValidatedArchive {
        try validateRoot()
        let manifestURL = root.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw CaptureRecoveryError.missingManifest
        }
        let data = try boundedRead(manifestURL, maximum: CaptureRecovery.maximumDocumentBytes)
        let manifest = try object(data)
        try requireKeys(
            manifest,
            ["accepted_frame_order", "capture_kind", "capture_settings", "coordinate_convention",
             "events", "files", "finalization", "format_version", "journal", "keyframes",
             "privacy", "replay", "session_id", "source"]
        )
        guard manifest["format_version"] as? String == "1.0.0" else {
            throw CaptureRecoveryError.unsupportedContractVersion
        }
        guard manifest["capture_kind"] as? String == "native_arkit" else {
            throw CaptureRecoveryError.unsupportedContractVersion
        }
        guard let sessionID = manifest["session_id"] as? String else {
            throw CaptureRecoveryError.invalidManifest
        }
        let finalization = try requiredObject(manifest, "finalization")
        try requireKeys(
            finalization,
            ["last_durable_journal_sequence", "manifest_sha256", "manifest_sha256_algorithm",
             "manifest_sha256_scope", "state"]
        )
        guard finalization["manifest_sha256_algorithm"] as? String == "RR-JCS-SHA256-1",
              finalization["manifest_sha256_scope"] as? String ==
                "entire_manifest_with_finalization_manifest_sha256_member_omitted"
        else { throw CaptureRecoveryError.unsupportedDigest }
        guard let stateText = finalization["state"] as? String,
              let state = CaptureFinalizationState(rawValue: stateText),
              let expectedManifestDigest = finalization["manifest_sha256"] as? String
        else { throw CaptureRecoveryError.invalidManifest }

        var digestRoot = manifest
        var digestFinalization = finalization
        digestFinalization.removeValue(forKey: "manifest_sha256")
        digestRoot["finalization"] = digestFinalization
        guard CanonicalJSON.sha256Hex(try canonicalData(digestRoot)) == expectedManifestDigest else {
            throw CaptureRecoveryError.digestMismatch
        }

        guard let files = manifest["files"] as? [[String: Any]],
              files.count <= CaptureRecovery.maximumInventoryMembers,
              let journal = manifest["journal"] as? [[String: Any]],
              journal.count <= CaptureRecovery.maximumInventoryMembers,
              let frames = manifest["accepted_frame_order"] as? [[String: Any]],
              let events = manifest["events"] as? [[String: Any]],
              let keyframes = manifest["keyframes"] as? [Any], keyframes.isEmpty
        else { throw CaptureRecoveryError.invalidManifest }
        guard journal.isEmpty == false else { throw CaptureRecoveryError.emptyJournal }

        let inventory = try validateFiles(files)
        try validateJournal(journal)
        try validateEvents(events, journal: journal, inventory: inventory)
        try validateFrames(frames, journal: journal, inventory: inventory)
        try validateReplay(manifest, journal: journal)
        guard uint(finalization["last_durable_journal_sequence"]) == UInt64(journal.count - 1) else {
            throw CaptureRecoveryError.projectionMismatch
        }
        let referenced = try referencedPaths(events: events, frames: frames)
        guard referenced == Set(inventory.keys) else {
            throw CaptureRecoveryError.projectionMismatch
        }

        return RecoveryValidatedArchive(
            root: root,
            manifest: manifest,
            manifestData: data,
            state: state,
            sessionID: sessionID,
            manifestSHA256: expectedManifestDigest,
            files: files,
            journal: journal,
            frames: frames,
            events: events
        )
    }

    private func validateRoot() throws {
        guard root.isFileURL else { throw CaptureRecoveryError.invalidRoot }
        let values = try? root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values?.isDirectory == true, values?.isSymbolicLink != true else {
            throw CaptureRecoveryError.invalidRoot
        }
    }

    private func validateFiles(_ files: [[String: Any]]) throws -> [String: [String: Any]] {
        let codecs = Set([
            "json_jcs_1", "jsonl_utf8_1", "jpeg", "png", "hevc_intra", "hevc_video",
            "h264_video", "glb2", "usdz", "ply_binary_little_endian_1_0", "npy_1_0", "ktx2_2_0",
        ])
        var inventory = [String: [String: Any]]()
        for file in files {
            try requireKeys(file, ["byte_length", "codec", "media_type", "relative_path", "role", "sha256"])
            guard let path = file["relative_path"] as? String,
                  let codec = file["codec"] as? String,
                  let byteLength = uint(file["byte_length"]),
                  let digest = file["sha256"] as? String,
                  inventory[path] == nil
            else { throw CaptureRecoveryError.invalidManifest }
            guard codecs.contains(codec) else { throw CaptureRecoveryError.unsupportedCodec }
            let url = try safeURL(path, root: root)
            let raw = try boundedRead(url, maximum: CaptureRecovery.maximumDocumentBytes)
            guard UInt64(raw.count) == byteLength,
                  CanonicalJSON.sha256Hex(raw) == digest
            else { throw CaptureRecoveryError.digestMismatch }
            inventory[path] = file
        }
        return inventory
    }

    private func validateJournal(_ journal: [[String: Any]]) throws {
        for (index, entry) in journal.enumerated() {
            try requireKeys(
                entry,
                ["content_sha256", "entry_type", "journal_sequence", "monotonic_timestamp_ns", "reference_id"]
            )
            guard uint(entry["journal_sequence"]) == UInt64(index),
                  ["event", "frame"].contains(entry["entry_type"] as? String),
                  (entry["content_sha256"] as? String)?.count == 64,
                  entry["reference_id"] is String,
                  entry["monotonic_timestamp_ns"] is String
            else { throw CaptureRecoveryError.nonContiguousJournal }
        }
    }

    private func validateEvents(
        _ events: [[String: Any]],
        journal: [[String: Any]],
        inventory: [String: [String: Any]]
    ) throws {
        let journalEvents = journal.filter { $0["entry_type"] as? String == "event" }
        guard journalEvents.count == events.count else { throw CaptureRecoveryError.projectionMismatch }
        for (index, event) in events.enumerated() {
            try requireKeys(
                event,
                ["durable_journal_sequence", "event_id", "event_sequence", "monotonic_timestamp_ns",
                 "payload_path", "payload_sha256", "record_sha256", "record_sha256_algorithm",
                 "record_sha256_scope", "type"]
            )
            guard uint(event["event_sequence"]) == UInt64(index),
                  let durable = uint(event["durable_journal_sequence"]),
                  durable < UInt64(journal.count),
                  let eventID = event["event_id"] as? String,
                  let payloadPath = event["payload_path"] as? String,
                  let payloadDigest = event["payload_sha256"] as? String,
                  let recordDigest = event["record_sha256"] as? String,
                  event["record_sha256_algorithm"] as? String == "RR-JCS-SHA256-1",
                  event["record_sha256_scope"] as? String ==
                    "entire_event_record_with_record_sha256_member_omitted",
                  inventory[payloadPath]?["sha256"] as? String == payloadDigest
            else { throw CaptureRecoveryError.projectionMismatch }
            var digestEvent = event
            digestEvent.removeValue(forKey: "record_sha256")
            guard CanonicalJSON.sha256Hex(try canonicalData(digestEvent)) == recordDigest else {
                throw CaptureRecoveryError.digestMismatch
            }
            let journalEntry = journal[Int(durable)]
            guard journalEntry["entry_type"] as? String == "event",
                  journalEntry["reference_id"] as? String == eventID,
                  journalEntry["content_sha256"] as? String == recordDigest,
                  journalEntry["monotonic_timestamp_ns"] as? String == event["monotonic_timestamp_ns"] as? String,
                  try canonicalData(journalEntry) == canonicalData(journalEvents[index])
            else { throw CaptureRecoveryError.projectionMismatch }
        }
    }

    private func validateFrames(
        _ frames: [[String: Any]],
        journal: [[String: Any]],
        inventory: [String: [String: Any]]
    ) throws {
        let journalFrames = journal.filter { $0["entry_type"] as? String == "frame" }
        guard journalFrames.count == frames.count else { throw CaptureRecoveryError.projectionMismatch }
        for (index, frame) in frames.enumerated() {
            let allowed = Set([
                "durable_journal_sequence", "frame_id", "packet_path", "packet_sha256", "sequence",
                "server_acknowledged",
            ])
            guard Set(frame.keys).isSubset(of: allowed),
                  Set(["durable_journal_sequence", "frame_id", "packet_path", "packet_sha256", "sequence"])
                    .isSubset(of: Set(frame.keys)),
                  uint(frame["sequence"]) == UInt64(index),
                  let durable = uint(frame["durable_journal_sequence"]),
                  durable < UInt64(journal.count),
                  let frameID = frame["frame_id"] as? String,
                  let packetPath = frame["packet_path"] as? String,
                  let packetDigest = frame["packet_sha256"] as? String,
                  inventory[packetPath] != nil
            else { throw CaptureRecoveryError.projectionMismatch }
            guard inventory[packetPath]?["sha256"] as? String == packetDigest else {
                throw CaptureRecoveryError.digestMismatch
            }
            let journalEntry = journal[Int(durable)]
            guard journalEntry["entry_type"] as? String == "frame",
                  journalEntry["reference_id"] as? String == frameID,
                  journalEntry["content_sha256"] as? String == packetDigest,
                  try canonicalData(journalEntry) == canonicalData(journalFrames[index])
            else { throw CaptureRecoveryError.projectionMismatch }

            let packetURL = try safeURL(packetPath, root: root)
            let packet = try object(try boundedRead(packetURL, maximum: CaptureRecovery.maximumDocumentBytes))
            guard packet["protocol_version"] as? String == "1.0.0",
                  packet["coordinate_convention"] as? String == "RR-COORD-1",
                  packet["frame_id"] as? String == frameID,
                  let image = packet["image"] as? [String: Any],
                  image["codec"] as? String == "png",
                  let payload = image["payload"] as? [String: Any],
                  payload["kind"] as? String == "rrcap_file",
                  let imagePath = payload["relative_path"] as? String,
                  let imageDigest = payload["sha256"] as? String,
                  let imageBytes = uint(payload["byte_length"]),
                  inventory[imagePath]?["sha256"] as? String == imageDigest,
                  uint(inventory[imagePath]?["byte_length"]) == imageBytes
            else { throw CaptureRecoveryError.projectionMismatch }
        }
    }

    private func validateReplay(_ manifest: [String: Any], journal: [[String: Any]]) throws {
        let replay = try requiredObject(manifest, "replay")
        try requireKeys(
            replay,
            ["input_digest", "input_digest_algorithm", "input_digest_scope", "neural_determinism",
             "ordering_authority", "provider_lock"]
        )
        guard replay["input_digest_algorithm"] as? String == "RR-JCS-SHA256-1",
              replay["input_digest_scope"] as? String ==
                "jcs_array_of_journal_sequence_entry_type_reference_id_content_sha256"
        else { throw CaptureRecoveryError.unsupportedDigest }
        let expectedDigest = try journalInputDigest(journal)
        guard replay["ordering_authority"] as? String == "global_journal_sequence",
              let providerLock = replay["provider_lock"] as? [Any], providerLock.isEmpty,
              replay["input_digest"] as? String == expectedDigest
        else { throw CaptureRecoveryError.projectionMismatch }
    }

    private func referencedPaths(
        events: [[String: Any]],
        frames: [[String: Any]]
    ) throws -> Set<String> {
        var paths = Set<String>()
        for event in events {
            guard let path = event["payload_path"] as? String else {
                throw CaptureRecoveryError.projectionMismatch
            }
            paths.insert(path)
        }
        for frame in frames {
            guard let packetPath = frame["packet_path"] as? String else {
                throw CaptureRecoveryError.projectionMismatch
            }
            paths.insert(packetPath)
            let packet = try object(
                try boundedRead(try safeURL(packetPath, root: root), maximum: CaptureRecovery.maximumDocumentBytes)
            )
            guard let image = packet["image"] as? [String: Any],
                  let payload = image["payload"] as? [String: Any],
                  let imagePath = payload["relative_path"] as? String
            else { throw CaptureRecoveryError.projectionMismatch }
            paths.insert(imagePath)
        }
        return paths
    }
}

private struct RecoveryJournalScan {
    let acceptedCount: Int
    let suffix: Data
    let suffixSHA256: String
}

private struct RecoveryJournalChunk {
    let contentRange: Range<Int>
    let rawRange: Range<Int>
}

private func safeURL(_ path: String, root: URL) throws -> URL {
    do {
        try ArchivePath.validate(path)
        let lexical = root.appendingPathComponent(path)
        let values = try? lexical.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values?.isSymbolicLink != true else { throw CaptureRecoveryError.invalidPath }
        return try ArchivePath.resolve(path, under: root)
    } catch let error as CaptureRecoveryError {
        throw error
    } catch {
        throw CaptureRecoveryError.invalidPath
    }
}

private func boundedRead(_ url: URL, maximum: Int) throws -> Data {
    guard maximum > 0 else { throw CaptureRecoveryError.byteLimitExceeded }
    let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
    guard values?.isRegularFile == true, values?.isSymbolicLink != true else {
        throw CaptureRecoveryError.ioFailure
    }
    guard let size = values?.fileSize, size <= maximum else {
        throw CaptureRecoveryError.byteLimitExceeded
    }
    do {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= maximum else { throw CaptureRecoveryError.byteLimitExceeded }
        return data
    } catch let error as CaptureRecoveryError {
        throw error
    } catch {
        throw CaptureRecoveryError.ioFailure
    }
}

private func object(_ data: Data) throws -> [String: Any] {
    do {
        _ = try CanonicalJSON.canonicalize(jsonData: data)
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

private func canonicalData(_ value: Any) throws -> Data {
    do {
        let encoded = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return try CanonicalJSON.canonicalize(jsonData: encoded)
    } catch let error as CaptureRecoveryError {
        throw error
    } catch {
        throw CaptureRecoveryError.invalidJSON
    }
}

private func requiredObject(_ root: [String: Any], _ key: String) throws -> [String: Any] {
    guard let object = root[key] as? [String: Any] else {
        throw CaptureRecoveryError.invalidManifest
    }
    return object
}

private func requireKeys(_ object: [String: Any], _ keys: Set<String>) throws {
    guard Set(object.keys) == keys else { throw CaptureRecoveryError.invalidManifest }
}

private func uint(_ value: Any?) -> UInt64? {
    guard let number = value as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID(),
          number.doubleValue >= 0,
          number.doubleValue.rounded(.towardZero) == number.doubleValue,
          number.doubleValue <= 9_007_199_254_740_991
    else { return nil }
    return number.uint64Value
}

private func journalInputDigest(_ journal: [[String: Any]]) throws -> String {
    let tuples = try journal.map { entry -> [Any] in
        guard let sequence = uint(entry["journal_sequence"]),
              let type = entry["entry_type"] as? String,
              let referenceID = entry["reference_id"] as? String,
              let digest = entry["content_sha256"] as? String
        else { throw CaptureRecoveryError.invalidManifest }
        return [sequence, type, referenceID, digest]
    }
    return CanonicalJSON.sha256Hex(try canonicalData(tuples))
}
