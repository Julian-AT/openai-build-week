import Darwin
import Foundation
import ReRoomContracts

enum CaptureStorageLimits {
    static let maximumFileBytes = 33_554_432
    static let maximumFiles = 2_048
}

enum CaptureCrashPoint: String, CaseIterable, Sendable {
    case beforeRename
    case afterRenameBeforeJournal
    case duringJournalAppendOrSync
    case afterJournalSync
}

struct InjectedCaptureCrash: Error, Equatable, Sendable {
    let point: CaptureCrashPoint
}

struct CaptureCrashInjector {
    let point: CaptureCrashPoint?

    init(point: CaptureCrashPoint? = nil) {
        self.point = point
    }

    func check(_ candidate: CaptureCrashPoint) throws {
        if point == candidate {
            throw InjectedCaptureCrash(point: candidate)
        }
    }
}

protocol CaptureFileSystem: AnyObject {
    func write(_ data: Data, to path: String) throws
    func replaceAtomically(_ data: Data, at path: String) throws
    func append(_ data: Data, to path: String) throws
    func synchronizeFile(at path: String) throws
    func renameDirectory(from sourcePath: String, to destinationPath: String) throws
    func synchronizeDirectory(containing path: String) throws
    func read(at path: String) throws -> Data
    func fileExists(at path: String) -> Bool
    func allPaths() -> [String]
}

final class FoundationCaptureFileSystem: CaptureFileSystem {
    let root: URL

    init(root: URL) {
        self.root = root
    }

    func write(_ data: Data, to path: String) throws {
        guard data.count <= CaptureStorageLimits.maximumFileBytes else {
            throw DiagnosticJournalRejection.invalidJournal
        }
        let url = try resolved(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .withoutOverwriting)
    }

    func append(_ data: Data, to path: String) throws {
        let url = try resolved(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: url.path) == false {
            _ = FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        let existingBytes = try handle.seekToEnd()
        guard existingBytes <= UInt64(CaptureStorageLimits.maximumFileBytes - data.count) else {
            throw DiagnosticJournalRejection.invalidJournal
        }
        try handle.write(contentsOf: data)
    }

    func replaceAtomically(_ data: Data, at path: String) throws {
        guard data.count <= CaptureStorageLimits.maximumFileBytes else {
            throw DiagnosticJournalRejection.invalidJournal
        }
        let destination = try resolved(path)
        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(
            ".\(destination.lastPathComponent).\(UUID().uuidString.lowercased()).repair"
        )
        do {
            try data.write(to: temporary, options: .withoutOverwriting)
            let handle = try FileHandle(forWritingTo: temporary)
            try handle.synchronize()
            try handle.close()
            let result = temporary.path.withCString { source in
                destination.path.withCString { target in
                    Darwin.rename(source, target)
                }
            }
            guard result == 0 else {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }
            try synchronizeDirectory(containing: path)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    func synchronizeFile(at path: String) throws {
        let handle = try FileHandle(forWritingTo: resolved(path))
        defer { try? handle.close() }
        try handle.synchronize()
    }

    func renameDirectory(from sourcePath: String, to destinationPath: String) throws {
        let source = try resolved(sourcePath)
        let destination = try resolved(destinationPath)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: source, to: destination)
    }

    func synchronizeDirectory(containing path: String) throws {
        let directory = try resolved(path).deletingLastPathComponent()
        let descriptor = Darwin.open(directory.path, O_RDONLY)
        guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        defer { Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
    }

    func read(at path: String) throws -> Data {
        let handle = try FileHandle(forReadingFrom: resolved(path))
        defer { try? handle.close() }
        let data = try handle.read(upToCount: CaptureStorageLimits.maximumFileBytes + 1) ?? Data()
        guard data.count <= CaptureStorageLimits.maximumFileBytes else {
            throw DiagnosticJournalRejection.invalidJournal
        }
        return data
    }

    func fileExists(at path: String) -> Bool {
        guard let url = try? resolved(path) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    func allPaths() -> [String] {
        guard FileManager.default.fileExists(atPath: root.path),
              let enumerator = FileManager.default.enumerator(
                  at: root,
                  includingPropertiesForKeys: [.isRegularFileKey]
              )
        else {
            return []
        }
        var paths: [String] = []
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            else {
                continue
            }
            paths.append(String(url.path.dropFirst(root.path.count + 1)))
            if paths.count > CaptureStorageLimits.maximumFiles { break }
        }
        return paths.sorted()
    }

    private func resolved(_ path: String) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return try ArchivePath.resolve(path, under: root)
    }
}

enum FrameCaptureLifecycle: String, Equatable, Sendable {
    case selected
    case imageAndMetadataDurable = "image_and_metadata_durable"
    case journaled
    case networkEligible = "network_eligible"
}

struct DurableJournalEntry: Codable, Equatable, Sendable {
    let journalSequence: Int
    let monotonicTimestampNS: String
    let entryType: String
    let referenceID: String
    let contentSHA256: String

    enum CodingKeys: String, CodingKey {
        case journalSequence = "journal_sequence"
        case monotonicTimestampNS = "monotonic_timestamp_ns"
        case entryType = "entry_type"
        case referenceID = "reference_id"
        case contentSHA256 = "content_sha256"
    }
}

struct LifecycleEventRecord: Codable, Equatable, Sendable {
    let eventID: String
    let eventSequence: Int
    let durableJournalSequence: Int
    let monotonicTimestampNS: String
    let type: String
    let payloadSHA256: String
    let payloadPath: String
    let recordSHA256Algorithm: String
    let recordSHA256Scope: String
    let recordSHA256: String

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case eventSequence = "event_sequence"
        case durableJournalSequence = "durable_journal_sequence"
        case monotonicTimestampNS = "monotonic_timestamp_ns"
        case type
        case payloadSHA256 = "payload_sha256"
        case payloadPath = "payload_path"
        case recordSHA256Algorithm = "record_sha256_algorithm"
        case recordSHA256Scope = "record_sha256_scope"
        case recordSHA256 = "record_sha256"
    }
}

struct AcceptedFrameProjection: Codable, Equatable, Sendable {
    let sequence: Int
    let frameID: String
    let packetPath: String
    let packetSHA256: String
    let durableJournalSequence: Int

    enum CodingKeys: String, CodingKey {
        case sequence
        case frameID = "frame_id"
        case packetPath = "packet_path"
        case packetSHA256 = "packet_sha256"
        case durableJournalSequence = "durable_journal_sequence"
    }
}

enum CaptureRetentionPolicy: String, Equatable, Sendable {
    case localOnlyUntilShare = "local_only_until_share"
    case sessionTTL = "session_ttl"
    case explicitUserRetention = "explicit_user_retention"
}

struct CaptureConsentRecord: Equatable, Sendable {
    let sessionID: String
    let recordedAtUTC: String
    let retentionPolicy: CaptureRetentionPolicy
    let retentionExpiresAtUTC: String?
    let recordSHA256: String

    init(
        sessionID: String,
        recordedAtUTC: String,
        retentionPolicy: CaptureRetentionPolicy,
        retentionExpiresAtUTC: String?,
        recordSHA256: String
    ) {
        self.sessionID = sessionID
        self.recordedAtUTC = recordedAtUTC
        self.retentionPolicy = retentionPolicy
        self.retentionExpiresAtUTC = retentionExpiresAtUTC
        self.recordSHA256 = recordSHA256
    }

    static func granting(
        sessionID: String,
        recordedAtUTC: String,
        retentionPolicy: CaptureRetentionPolicy,
        retentionExpiresAtUTC: String?
    ) throws -> CaptureConsentRecord {
        let digest = try digest(
            sessionID: sessionID,
            recordedAtUTC: recordedAtUTC,
            retentionPolicy: retentionPolicy,
            retentionExpiresAtUTC: retentionExpiresAtUTC
        )
        return CaptureConsentRecord(
            sessionID: sessionID,
            recordedAtUTC: recordedAtUTC,
            retentionPolicy: retentionPolicy,
            retentionExpiresAtUTC: retentionExpiresAtUTC,
            recordSHA256: digest
        )
    }

    func isValid(for expectedSessionID: String) -> Bool {
        guard sessionID == expectedSessionID,
              Self.isUTCDate(recordedAtUTC),
              retentionPolicy == .sessionTTL
                ? retentionExpiresAtUTC.map(Self.isUTCDate) == true
                : retentionExpiresAtUTC == nil,
              let expectedDigest = try? Self.digest(
                sessionID: sessionID,
                recordedAtUTC: recordedAtUTC,
                retentionPolicy: retentionPolicy,
                retentionExpiresAtUTC: retentionExpiresAtUTC
              )
        else {
            return false
        }
        return recordSHA256 == expectedDigest
    }

    private static func digest(
        sessionID: String,
        recordedAtUTC: String,
        retentionPolicy: CaptureRetentionPolicy,
        retentionExpiresAtUTC: String?
    ) throws -> String {
        var record: [String: Any] = [
            "capture_consent_granted": true,
            "session_id": sessionID,
            "recorded_at_utc": recordedAtUTC,
            "retention_policy": retentionPolicy.rawValue,
        ]
        if let retentionExpiresAtUTC {
            record["retention_expires_at"] = retentionExpiresAtUTC
        }
        let encoded = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        let canonical = try CanonicalJSON.canonicalize(jsonData: encoded)
        return CanonicalJSON.sha256Hex(canonical)
    }

    fileprivate static func isUTCDate(_ value: String) -> Bool {
        value.range(
            of: #"^[0-9]{4}-(?:0[1-9]|1[0-2])-(?:0[1-9]|[12][0-9]|3[01])T(?:[01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]Z$"#,
            options: .regularExpression
        ) != nil
    }
}

struct CaptureConsentDenial: Equatable, Sendable {
    let sessionID: String
    let recordedAtUTC: String
    let explanation: String
}

enum DiagnosticCaptureConsent: Equatable, Sendable {
    case granted(CaptureConsentRecord)
    case denied(CaptureConsentDenial)
}

struct DiagnosticCaptureConfiguration: Equatable, Sendable {
    let sessionID: String
    let deviceModel: String
    let osVersion: String
    let appVersion: String
    let buildID: String
    let recordedAtUTC: String
    let worldFrameID: String
    let initialWorldFrameVersion: Int
    let consent: DiagnosticCaptureConsent
}

struct CaptureCommitReceipt: Equatable, Sendable {
    let packet: BuiltFramePacket
    let lifecycle: FrameCaptureLifecycle
    let isVisible: Bool
}

struct RecoveredCapture: Equatable, Sendable {
    let manifestData: Data
    let journal: [DurableJournalEntry]
    let acceptedFrames: [AcceptedFrameProjection]
    let events: [LifecycleEventRecord]
    let internalDurableFrameIDs: [String]
    let networkEligibleFrameIDs: [String]
}

enum DiagnosticJournalRejection: Error, Equatable, Sendable {
    case invalidAttempt
    case invalidConsent
    case consentDenied(String)
    case invalidJournal
    case invalidManifest
    case noDurablePrefix
}

enum RecoveredManifestVerdict: Equatable, Sendable {
    case accepted
    case rejected(DiagnosticJournalRejection)
}

final class DiagnosticJournal {
    private static let journalPath = "journal/global.jsonl"
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
    let fileSystem: any CaptureFileSystem
    let framePacketBuilder: FramePacketBuilder
    let configuration: DiagnosticCaptureConfiguration
    let crashInjector: CaptureCrashInjector
    private(set) var visibleFrameIDs: [String] = []
    private(set) var lifecycleByFrameID: [String: FrameCaptureLifecycle] = [:]

    var captureDenialExplanation: String? {
        guard case let .denied(denial) = configuration.consent,
              denial.sessionID == configuration.sessionID
        else {
            return nil
        }
        return denial.explanation
    }

    init(
        fileSystem: any CaptureFileSystem,
        framePacketBuilder: FramePacketBuilder,
        configuration: DiagnosticCaptureConfiguration,
        crashInjector: CaptureCrashInjector = CaptureCrashInjector()
    ) {
        self.fileSystem = fileSystem
        self.framePacketBuilder = framePacketBuilder
        self.configuration = configuration
        self.crashInjector = crashInjector
    }

    func capture(
        input: FramePacketCaptureInput,
        attempt: CaptureAttemptResolution
    ) throws -> CaptureCommitReceipt {
        _ = try validatedGrantedConsent()
        guard case .ready = attempt else { throw DiagnosticJournalRejection.invalidAttempt }
        guard input.lifecycleEventIDs.count == Self.phaseOneEventTypes.count,
              Set(input.lifecycleEventIDs).count == input.lifecycleEventIDs.count,
              input.lifecycleEventIDs.allSatisfy(isValidEventID),
              input.sessionID == configuration.sessionID
        else {
            throw DiagnosticJournalRejection.invalidJournal
        }

        let existing = try repairedDurablePrefixIfNeeded(try durablePrefix())
        try validateUnusedIdentities(for: input, durablePrefix: existing)
        let firstJournalSequence = (existing.entries.last?.journalSequence ?? -1) + 1
        let firstEventSequence = existing.events.count
        let frameJournalSequence = firstJournalSequence + 2
        let packet: BuiltFramePacket
        do {
            packet = try framePacketBuilder.build(
                input: input,
                attempt: attempt,
                durableJournalSequence: frameJournalSequence
            )
        } catch FramePacketBuildRejection.invalidAttempt {
            throw DiagnosticJournalRejection.invalidAttempt
        }

        lifecycleByFrameID[input.frameID] = .selected
        try appendEvent(
            id: input.lifecycleEventIDs[0],
            type: Self.phaseOneEventTypes[0],
            eventSequence: firstEventSequence,
            journalSequence: firstJournalSequence,
            monotonicTimestampNS: input.monotonicTimestampNS,
            packet: packet
        )

        let stagingDirectory = "staging/\(input.frameID).tmp"
        let stagingImagePath = "\(stagingDirectory)/image.\(packet.imagePath.split(separator: ".").last!)"
        let stagingPacketPath = "\(stagingDirectory)/packet.json"
        try fileSystem.write(packet.imageData, to: stagingImagePath)
        try fileSystem.write(packet.packetData, to: stagingPacketPath)
        try fileSystem.synchronizeFile(at: stagingImagePath)
        try fileSystem.synchronizeFile(at: stagingPacketPath)
        try fileSystem.synchronizeDirectory(containing: stagingImagePath)
        try crashInjector.check(.beforeRename)

        let finalDirectory = "frames/\(input.frameID)"
        try fileSystem.renameDirectory(from: stagingDirectory, to: finalDirectory)
        try fileSystem.synchronizeDirectory(containing: finalDirectory)
        lifecycleByFrameID[input.frameID] = .imageAndMetadataDurable
        try crashInjector.check(.afterRenameBeforeJournal)

        if crashInjector.point == .duringJournalAppendOrSync {
            let event = try persistEventRecord(
                id: input.lifecycleEventIDs[1],
                type: Self.phaseOneEventTypes[1],
                eventSequence: firstEventSequence + 1,
                journalSequence: firstJournalSequence + 1,
                monotonicTimestampNS: input.monotonicTimestampNS,
                packet: packet
            )
            _ = event
            try fileSystem.append(Data("{".utf8), to: Self.journalPath)
            try crashInjector.check(.duringJournalAppendOrSync)
        }

        try appendEvent(
            id: input.lifecycleEventIDs[1],
            type: Self.phaseOneEventTypes[1],
            eventSequence: firstEventSequence + 1,
            journalSequence: firstJournalSequence + 1,
            monotonicTimestampNS: input.monotonicTimestampNS,
            packet: packet
        )
        try appendEntry(
            DurableJournalEntry(
                journalSequence: frameJournalSequence,
                monotonicTimestampNS: input.monotonicTimestampNS,
                entryType: "frame",
                referenceID: input.frameID,
                contentSHA256: packet.packetSHA256
            )
        )
        try appendEvent(
            id: input.lifecycleEventIDs[2],
            type: Self.phaseOneEventTypes[2],
            eventSequence: firstEventSequence + 2,
            journalSequence: firstJournalSequence + 3,
            monotonicTimestampNS: input.monotonicTimestampNS,
            packet: packet
        )
        lifecycleByFrameID[input.frameID] = .journaled
        try appendEvent(
            id: input.lifecycleEventIDs[3],
            type: Self.phaseOneEventTypes[3],
            eventSequence: firstEventSequence + 3,
            journalSequence: firstJournalSequence + 4,
            monotonicTimestampNS: input.monotonicTimestampNS,
            packet: packet
        )
        lifecycleByFrameID[input.frameID] = .networkEligible
        try crashInjector.check(.afterJournalSync)

        visibleFrameIDs.append(input.frameID)
        return CaptureCommitReceipt(
            packet: packet,
            lifecycle: .networkEligible,
            isVisible: true
        )
    }

    func recover() throws -> RecoveredCapture {
        let prefix = try repairedDurablePrefixIfNeeded(try durablePrefix())
        guard prefix.entries.isEmpty == false else {
            throw DiagnosticJournalRejection.noDurablePrefix
        }

        let acceptedFrames = try acceptedFrameProjection(from: prefix.entries)
        let internalFrameIDs = try internallyDurableFrameIDs()
        let networkFrameIDs = networkEligibleFrameIDs(
            acceptedFrames: acceptedFrames,
            journal: prefix.entries,
            events: prefix.events
        )
        let manifest = try buildManifest(
            journal: prefix.entries,
            acceptedFrames: acceptedFrames,
            events: prefix.events
        )
        guard validateRecoveredManifest(manifest) == .accepted else {
            throw DiagnosticJournalRejection.invalidManifest
        }

        visibleFrameIDs = networkFrameIDs
        for frameID in internalFrameIDs {
            lifecycleByFrameID[frameID] = networkFrameIDs.contains(frameID)
                ? .networkEligible
                : .imageAndMetadataDurable
        }
        return RecoveredCapture(
            manifestData: manifest,
            journal: prefix.entries,
            acceptedFrames: acceptedFrames,
            events: prefix.events,
            internalDurableFrameIDs: internalFrameIDs,
            networkEligibleFrameIDs: networkFrameIDs
        )
    }

    func validateRecoveredManifest(_ manifestData: Data) -> RecoveredManifestVerdict {
        do {
            try validateManifest(manifestData)
            return .accepted
        } catch let rejection as DiagnosticJournalRejection {
            return .rejected(rejection)
        } catch {
            return .rejected(.invalidManifest)
        }
    }

    private func appendEvent(
        id: String,
        type: String,
        eventSequence: Int,
        journalSequence: Int,
        monotonicTimestampNS: String,
        packet: BuiltFramePacket
    ) throws {
        let event = try persistEventRecord(
            id: id,
            type: type,
            eventSequence: eventSequence,
            journalSequence: journalSequence,
            monotonicTimestampNS: monotonicTimestampNS,
            packet: packet
        )
        try appendEntry(
            DurableJournalEntry(
                journalSequence: journalSequence,
                monotonicTimestampNS: monotonicTimestampNS,
                entryType: "event",
                referenceID: id,
                contentSHA256: event.recordSHA256
            )
        )
    }

    private func persistEventRecord(
        id: String,
        type: String,
        eventSequence: Int,
        journalSequence: Int,
        monotonicTimestampNS: String,
        packet: BuiltFramePacket
    ) throws -> LifecycleEventRecord {
        let partial: [String: Any] = [
            "event_id": id,
            "event_sequence": eventSequence,
            "durable_journal_sequence": journalSequence,
            "monotonic_timestamp_ns": monotonicTimestampNS,
            "type": type,
            "payload_sha256": packet.packetSHA256,
            "payload_path": packet.packetPath,
            "record_sha256_algorithm": "RR-JCS-SHA256-1",
            "record_sha256_scope": "entire_event_record_with_record_sha256_member_omitted",
        ]
        let partialData = try canonicalData(partial)
        let digest = CanonicalJSON.sha256Hex(partialData)
        var complete = partial
        complete["record_sha256"] = digest
        let completeData = try canonicalData(complete)
        let event = try JSONDecoder().decode(LifecycleEventRecord.self, from: completeData)
        let path = eventPath(id)
        try fileSystem.write(completeData, to: path)
        try fileSystem.synchronizeFile(at: path)
        try fileSystem.synchronizeDirectory(containing: path)
        return event
    }

    private func appendEntry(_ entry: DurableJournalEntry) throws {
        let data = try JSONEncoder().encode(entry)
        let canonical = try CanonicalJSON.canonicalize(jsonData: data)
        try fileSystem.append(canonical + Data([0x0a]), to: Self.journalPath)
        try fileSystem.synchronizeFile(at: Self.journalPath)
        try fileSystem.synchronizeDirectory(containing: Self.journalPath)
    }
}

private struct DurablePrefix {
    let entries: [DurableJournalEntry]
    let events: [LifecycleEventRecord]
    let hasInvalidTail: Bool
}

private extension DiagnosticJournal {
    func repairedDurablePrefixIfNeeded(_ prefix: DurablePrefix) throws -> DurablePrefix {
        guard prefix.hasInvalidTail else { return prefix }
        guard prefix.entries.isEmpty == false else {
            throw DiagnosticJournalRejection.invalidJournal
        }
        var repaired = Data()
        for entry in prefix.entries {
            let encoded = try JSONEncoder().encode(entry)
            let canonical = try CanonicalJSON.canonicalize(jsonData: encoded)
            repaired.append(canonical)
            repaired.append(0x0a)
        }
        try fileSystem.replaceAtomically(repaired, at: Self.journalPath)
        let verified = try durablePrefix()
        guard verified.hasInvalidTail == false,
              verified.entries == prefix.entries,
              verified.events == prefix.events
        else {
            throw DiagnosticJournalRejection.invalidJournal
        }
        return verified
    }

    func validateUnusedIdentities(
        for input: FramePacketCaptureInput,
        durablePrefix: DurablePrefix
    ) throws {
        let durableFrameIDs = Set(
            durablePrefix.entries.lazy
                .filter { $0.entryType == "frame" }
                .map(\.referenceID)
        )
        let durableEventIDs = Set(durablePrefix.events.map(\.eventID))
        guard durableFrameIDs.contains(input.frameID) == false,
              durableEventIDs.isDisjoint(with: input.lifecycleEventIDs)
        else {
            throw DiagnosticJournalRejection.invalidJournal
        }

        let paths = fileSystem.allPaths()
        guard paths.count <= CaptureStorageLimits.maximumFiles,
              paths.contains(where: { $0.hasPrefix("frames/\(input.frameID)/") }) == false,
              paths.contains(where: { $0.hasPrefix("staging/\(input.frameID).tmp/") }) == false,
              input.lifecycleEventIDs.allSatisfy({ fileSystem.fileExists(at: eventPath($0)) == false })
        else {
            throw DiagnosticJournalRejection.invalidJournal
        }

        for path in paths where path.hasPrefix("frames/") && path.hasSuffix("/packet.json") {
            let packetData = try fileSystem.read(at: path)
            let canonical = try CanonicalJSON.canonicalize(
                jsonData: packetData,
                maximumBytes: FramePacketBuilder.maximumPacketBytes
            )
            guard canonical == packetData,
                  let object = try JSONSerialization.jsonObject(with: canonical) as? [String: Any],
                  let existingKey = object["idempotency_key"] as? String
            else {
                throw DiagnosticJournalRejection.invalidJournal
            }
            guard existingKey != input.idempotencyKey else {
                throw DiagnosticJournalRejection.invalidJournal
            }
        }
    }

    func durablePrefix() throws -> DurablePrefix {
        guard fileSystem.fileExists(at: Self.journalPath) else {
            return DurablePrefix(entries: [], events: [], hasInvalidTail: false)
        }
        let bytes = try fileSystem.read(at: Self.journalPath)
        let lines = bytes.split(separator: 0x0a, omittingEmptySubsequences: false)
        var entries: [DurableJournalEntry] = []
        var events: [LifecycleEventRecord] = []
        var invalidTail = false

        for rawLine in lines where rawLine.isEmpty == false {
            let line = Data(rawLine)
            guard let entry = try? decodeExact(
                DurableJournalEntry.self,
                from: line,
                keys: Self.journalKeys
            ), entry.journalSequence == entries.count else {
                invalidTail = true
                break
            }
            if entry.entryType == "event" {
                guard let event = try? validatedEvent(for: entry, expectedSequence: events.count) else {
                    invalidTail = true
                    break
                }
                events.append(event)
            } else if entry.entryType == "frame" {
                guard (try? validatedPacket(for: entry)) != nil else {
                    invalidTail = true
                    break
                }
            } else {
                invalidTail = true
                break
            }
            entries.append(entry)
        }
        return DurablePrefix(entries: entries, events: events, hasInvalidTail: invalidTail)
    }

    func validatedEvent(
        for entry: DurableJournalEntry,
        expectedSequence: Int
    ) throws -> LifecycleEventRecord {
        let data = try fileSystem.read(at: eventPath(entry.referenceID))
        let canonical = try CanonicalJSON.canonicalize(jsonData: data)
        guard canonical == data else { throw DiagnosticJournalRejection.invalidJournal }
        let event = try decodeExact(
            LifecycleEventRecord.self,
            from: canonical,
            keys: Self.eventKeys
        )
        guard event.eventID == entry.referenceID,
              event.eventSequence == expectedSequence,
              event.durableJournalSequence == entry.journalSequence,
              event.monotonicTimestampNS == entry.monotonicTimestampNS,
              Self.phaseOneEventTypes.contains(event.type),
              event.recordSHA256Algorithm == "RR-JCS-SHA256-1",
              event.recordSHA256Scope
                == "entire_event_record_with_record_sha256_member_omitted",
              try eventRecordDigest(event) == event.recordSHA256,
              entry.contentSHA256 == event.recordSHA256
        else {
            throw DiagnosticJournalRejection.invalidJournal
        }
        return event
    }

    @discardableResult
    func validatedPacket(for entry: DurableJournalEntry) throws -> BuiltFramePacket {
        let packetPath = self.packetPath(entry.referenceID)
        let data = try fileSystem.read(at: packetPath)
        let canonical = try CanonicalJSON.canonicalize(
            jsonData: data,
            maximumBytes: FramePacketBuilder.maximumPacketBytes
        )
        guard canonical == data,
              CanonicalJSON.sha256Hex(canonical) == entry.contentSHA256,
              let object = try JSONSerialization.jsonObject(with: canonical) as? [String: Any],
              object["frame_id"] as? String == entry.referenceID,
              let durability = object["durability"] as? [String: Any],
              durability["journal_sequence"] as? Int == entry.journalSequence,
              let image = object["image"] as? [String: Any],
              let payload = image["payload"] as? [String: Any],
              let imagePath = payload["relative_path"] as? String,
              let imageData = try? fileSystem.read(at: imagePath)
        else {
            throw DiagnosticJournalRejection.invalidJournal
        }
        guard framePacketBuilder.validator.validate(
            ContractValidationRequest(
                schemaID: ContractSchemaIdentifier.framePacket.rawValue,
                schemaVersion: "1.0.0",
                schemaSHA256: "d50b19bfb29c6c62c494e3a47deb3c51a933609698f4ff2f9cbfba6ec4252b43",
                documentData: canonical,
                payloadData: imageData
            )
        ) == .accepted else {
            throw DiagnosticJournalRejection.invalidJournal
        }
        return BuiltFramePacket(
            frameID: entry.referenceID,
            imagePath: imagePath,
            packetPath: packetPath,
            imageData: imageData,
            packetData: canonical,
            payloadSHA256: CanonicalJSON.sha256Hex(imageData),
            packetSHA256: entry.contentSHA256,
            durableJournalSequence: entry.journalSequence
        )
    }

    func acceptedFrameProjection(
        from journal: [DurableJournalEntry]
    ) throws -> [AcceptedFrameProjection] {
        var result: [AcceptedFrameProjection] = []
        for entry in journal where entry.entryType == "frame" {
            let packet = try validatedPacket(for: entry)
            result.append(
                AcceptedFrameProjection(
                    sequence: result.count,
                    frameID: entry.referenceID,
                    packetPath: packet.packetPath,
                    packetSHA256: entry.contentSHA256,
                    durableJournalSequence: entry.journalSequence
                )
            )
        }
        return result
    }

    func internallyDurableFrameIDs() throws -> [String] {
        let paths = fileSystem.allPaths()
        guard paths.count <= CaptureStorageLimits.maximumFiles else {
            throw DiagnosticJournalRejection.invalidJournal
        }
        return paths.compactMap { path in
            let components = path.split(separator: "/")
            guard components.count == 3,
                  components[0] == "frames",
                  components[1].hasPrefix("frame_"),
                  components[2] == "packet.json"
            else {
                return nil
            }
            return String(components[1])
        }.sorted()
    }

    func networkEligibleFrameIDs(
        acceptedFrames: [AcceptedFrameProjection],
        journal: [DurableJournalEntry],
        events: [LifecycleEventRecord]
    ) -> [String] {
        acceptedFrames.compactMap { frame in
            let related = events.filter {
                $0.payloadPath == frame.packetPath && $0.payloadSHA256 == frame.packetSHA256
            }
            let lifecycle = Self.phaseOneEventTypes.compactMap { type in
                related.first { $0.type == type }
            }
            guard lifecycle.count == Self.phaseOneEventTypes.count,
                  related.count == Self.phaseOneEventTypes.count,
                  lifecycle[0].durableJournalSequence < lifecycle[1].durableJournalSequence,
                  lifecycle[1].durableJournalSequence < frame.durableJournalSequence,
                  frame.durableJournalSequence < lifecycle[2].durableJournalSequence,
                  lifecycle[2].durableJournalSequence < lifecycle[3].durableJournalSequence,
                  journal.indices.contains(lifecycle[3].durableJournalSequence)
            else {
                return nil
            }
            return frame.frameID
        }
    }

    func buildManifest(
        journal: [DurableJournalEntry],
        acceptedFrames: [AcceptedFrameProjection],
        events: [LifecycleEventRecord]
    ) throws -> Data {
        let tupleArray: [[Any]] = journal.map {
            [$0.journalSequence, $0.entryType, $0.referenceID, $0.contentSHA256]
        }
        let replayDigest = CanonicalJSON.sha256Hex(try canonicalData(tupleArray))
        let files = try manifestFiles(events: events, frames: acceptedFrames)
        let lastSequence = try requiredLastSequence(journal)
        let consent = try validatedGrantedConsent()
        var privacy: [String: Any] = [
            "capture_consent_recorded": true,
            "contains_room_imagery": true,
            "retention_policy": consent.retentionPolicy.rawValue,
            "deletion_state": "none",
            "share_access_state": "not_shared",
        ]
        if let retentionExpiresAtUTC = consent.retentionExpiresAtUTC {
            privacy["retention_expires_at"] = retentionExpiresAtUTC
        }
        var root: [String: Any] = [
            "format_version": "1.0.0",
            "capture_kind": "native_arkit",
            "session_id": configuration.sessionID,
            "source": [
                "device_model": configuration.deviceModel,
                "os_version": configuration.osVersion,
                "app_version": configuration.appVersion,
                "build_id": configuration.buildID,
                "recorded_at_utc": configuration.recordedAtUTC,
            ],
            "coordinate_convention": [
                "convention": "RR-COORD-1",
                "world_frame_id": configuration.worldFrameID,
                "initial_world_frame_version": configuration.initialWorldFrameVersion,
            ],
            "capture_settings": [
                "camera_format": "encoded_upright",
                "frame_selection_policy": "diagnostic_single_frame",
                "queue_capacity": 1,
                "high_resolution_keyframe_policy": "disabled_phase_1",
                "arkit_configuration": [
                    "world_tracking": true,
                    "plane_detection": ["horizontal", "vertical"],
                    "lidar_required": false,
                ],
            ],
            "files": files,
            "journal": try jsonArray(journal),
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
            "privacy": privacy,
            "finalization": [
                "state": "recovered_prefix",
                "manifest_sha256_algorithm": "RR-JCS-SHA256-1",
                "manifest_sha256_scope":
                    "entire_manifest_with_finalization_manifest_sha256_member_omitted",
                "last_durable_journal_sequence": lastSequence,
            ],
        ]
        let digest = CanonicalJSON.sha256Hex(try canonicalData(root))
        var finalization = root["finalization"] as! [String: Any]
        finalization["manifest_sha256"] = digest
        root["finalization"] = finalization
        return try canonicalData(root)
    }

    func manifestFiles(
        events: [LifecycleEventRecord],
        frames: [AcceptedFrameProjection]
    ) throws -> [[String: Any]] {
        var result: [[String: Any]] = []
        for event in events {
            let path = eventPath(event.eventID)
            let data = try fileSystem.read(at: path)
            result.append(fileRecord(
                path: path,
                mediaType: "application/json",
                codec: "json_jcs_1",
                data: data,
                role: "event_log"
            ))
        }
        for frame in frames {
            let entry = DurableJournalEntry(
                journalSequence: frame.durableJournalSequence,
                monotonicTimestampNS: "0",
                entryType: "frame",
                referenceID: frame.frameID,
                contentSHA256: frame.packetSHA256
            )
            let packet = try validatedPacket(for: entry)
            result.append(fileRecord(
                path: packet.packetPath,
                mediaType: "application/json",
                codec: "json_jcs_1",
                data: packet.packetData,
                role: "frame_metadata"
            ))
            let packetObject = try JSONSerialization.jsonObject(with: packet.packetData) as! [String: Any]
            let imageObject = packetObject["image"] as! [String: Any]
            let codec = imageObject["codec"] as! String
            result.append(fileRecord(
                path: packet.imagePath,
                mediaType: mediaType(for: codec),
                codec: codec,
                data: packet.imageData,
                role: "frame_image"
            ))
        }
        return result
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

    func validateManifest(_ manifestData: Data) throws {
        guard framePacketBuilder.validator.validate(
            ContractValidationRequest(
                schemaID: ContractSchemaIdentifier.rrcapManifest.rawValue,
                schemaVersion: "1.0.0",
                schemaSHA256: "c97349820ed66fb1a1fdf60ea9afee312f532811602851d01d1e233641730b87",
                documentData: manifestData
            )
        ) == .accepted,
              var root = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              var finalization = root["finalization"] as? [String: Any],
              finalization["state"] as? String == "recovered_prefix",
              finalization["manifest_sha256_algorithm"] as? String == "RR-JCS-SHA256-1",
              finalization["manifest_sha256_scope"] as? String
                == "entire_manifest_with_finalization_manifest_sha256_member_omitted",
              let recordedManifestDigest = finalization.removeValue(forKey: "manifest_sha256")
                as? String
        else {
            throw DiagnosticJournalRejection.invalidManifest
        }
        root["finalization"] = finalization
        guard CanonicalJSON.sha256Hex(try canonicalData(root)) == recordedManifestDigest else {
            throw DiagnosticJournalRejection.invalidManifest
        }

        let original = try JSONSerialization.jsonObject(with: manifestData) as! [String: Any]
        let journal = try decodeExactArray(
            DurableJournalEntry.self,
            from: original["journal"],
            keys: Self.journalKeys
        )
        guard journal.isEmpty == false,
              journal.enumerated().allSatisfy({ $0.offset == $0.element.journalSequence }),
              finalization["last_durable_journal_sequence"] as? Int == journal.count - 1
        else {
            throw DiagnosticJournalRejection.invalidManifest
        }

        let events = try decodeExactArray(
            LifecycleEventRecord.self,
            from: original["events"],
            keys: Self.eventKeys
        )
        let eventEntries = journal.filter { $0.entryType == "event" }
        guard events.count == eventEntries.count else {
            throw DiagnosticJournalRejection.invalidManifest
        }
        for (index, pair) in zip(events, eventEntries).enumerated() {
            let event = pair.0
            let entry = pair.1
            guard event.eventSequence == index,
                  event.eventID == entry.referenceID,
                  event.durableJournalSequence == entry.journalSequence,
                  event.monotonicTimestampNS == entry.monotonicTimestampNS,
                  Self.phaseOneEventTypes.contains(event.type),
                  event.recordSHA256Algorithm == "RR-JCS-SHA256-1",
                  event.recordSHA256Scope
                    == "entire_event_record_with_record_sha256_member_omitted",
                  try eventRecordDigest(event) == event.recordSHA256,
                  entry.contentSHA256 == event.recordSHA256
            else {
                throw DiagnosticJournalRejection.invalidManifest
            }
        }

        let accepted = try decodeArray(AcceptedFrameProjection.self, from: original["accepted_frame_order"])
        let expectedAccepted = try acceptedFrameProjection(from: journal)
        guard accepted == expectedAccepted else {
            throw DiagnosticJournalRejection.invalidManifest
        }
        let tuples: [[Any]] = journal.map {
            [$0.journalSequence, $0.entryType, $0.referenceID, $0.contentSHA256]
        }
        let replay = original["replay"] as! [String: Any]
        guard replay["input_digest"] as? String
            == CanonicalJSON.sha256Hex(try canonicalData(tuples))
        else {
            throw DiagnosticJournalRejection.invalidManifest
        }

        let files = original["files"] as! [[String: Any]]
        for file in files {
            guard let path = file["relative_path"] as? String,
                  let expectedLength = file["byte_length"] as? Int,
                  let expectedDigest = file["sha256"] as? String,
                  let data = try? fileSystem.read(at: path),
                  data.count == expectedLength,
                  CanonicalJSON.sha256Hex(data) == expectedDigest
            else {
                throw DiagnosticJournalRejection.invalidManifest
            }
        }
    }

    func decodeExact<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        keys: Set<String>
    ) throws -> T {
        let canonical = try CanonicalJSON.canonicalize(jsonData: data)
        guard let object = try JSONSerialization.jsonObject(with: canonical) as? [String: Any],
              Set(object.keys) == keys
        else {
            throw DiagnosticJournalRejection.invalidJournal
        }
        return try JSONDecoder().decode(type, from: canonical)
    }

    func decodeExactArray<T: Decodable>(
        _ type: T.Type,
        from value: Any?,
        keys: Set<String>
    ) throws -> [T] {
        guard let objects = value as? [[String: Any]],
              objects.allSatisfy({ Set($0.keys) == keys })
        else {
            throw DiagnosticJournalRejection.invalidManifest
        }
        return try objects.map { object in
            try JSONDecoder().decode(type, from: canonicalData(object))
        }
    }

    func decodeArray<T: Decodable>(_ type: T.Type, from value: Any?) throws -> [T] {
        guard let value else { throw DiagnosticJournalRejection.invalidManifest }
        return try JSONDecoder().decode([T].self, from: canonicalData(value))
    }

    func eventRecordDigest(_ event: LifecycleEventRecord) throws -> String {
        var object = try jsonObject(event)
        object.removeValue(forKey: "record_sha256")
        return CanonicalJSON.sha256Hex(try canonicalData(object))
    }

    func requiredLastSequence(_ journal: [DurableJournalEntry]) throws -> Int {
        guard let value = journal.last?.journalSequence else {
            throw DiagnosticJournalRejection.noDurablePrefix
        }
        return value
    }

    func packetPath(_ frameID: String) -> String { "frames/\(frameID)/packet.json" }
    func eventPath(_ eventID: String) -> String { "events/\(eventID).json" }

    func isValidEventID(_ value: String) -> Bool {
        value.range(
            of: #"^event_[0-9a-f]{8}-[0-9a-f]{4}-[47][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"#,
            options: .regularExpression
        ) != nil
    }

    func validatedGrantedConsent() throws -> CaptureConsentRecord {
        switch configuration.consent {
        case let .granted(record):
            guard record.isValid(for: configuration.sessionID) else {
                throw DiagnosticJournalRejection.invalidConsent
            }
            return record
        case let .denied(denial):
            guard denial.sessionID == configuration.sessionID,
                  CaptureConsentRecord.isUTCDate(denial.recordedAtUTC),
                  denial.explanation.isEmpty == false,
                  denial.explanation.utf8.count <= 256
            else {
                throw DiagnosticJournalRejection.invalidConsent
            }
            throw DiagnosticJournalRejection.consentDenied(denial.explanation)
        }
    }

    func mediaType(for codec: String) -> String {
        switch codec {
        case "jpeg": "image/jpeg"
        case "png": "image/png"
        default: "image/heic"
        }
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
}
