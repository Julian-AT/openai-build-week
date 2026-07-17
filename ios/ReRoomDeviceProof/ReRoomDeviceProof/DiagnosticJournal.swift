import Foundation

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
        _ = data
        _ = path
        throw DiagnosticJournalRejection.notImplemented
    }

    func append(_ data: Data, to path: String) throws {
        _ = data
        _ = path
        throw DiagnosticJournalRejection.notImplemented
    }

    func synchronizeFile(at path: String) throws {
        _ = path
        throw DiagnosticJournalRejection.notImplemented
    }

    func renameDirectory(from sourcePath: String, to destinationPath: String) throws {
        _ = sourcePath
        _ = destinationPath
        throw DiagnosticJournalRejection.notImplemented
    }

    func synchronizeDirectory(containing path: String) throws {
        _ = path
        throw DiagnosticJournalRejection.notImplemented
    }

    func read(at path: String) throws -> Data {
        _ = path
        throw DiagnosticJournalRejection.notImplemented
    }

    func fileExists(at path: String) -> Bool {
        _ = path
        return false
    }

    func allPaths() -> [String] { [] }
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

struct DiagnosticCaptureConfiguration: Equatable, Sendable {
    let deviceModel: String
    let osVersion: String
    let appVersion: String
    let buildID: String
    let recordedAtUTC: String
    let worldFrameID: String
    let initialWorldFrameVersion: Int
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
    case invalidJournal
    case invalidManifest
    case noDurablePrefix
    case notImplemented
}

enum RecoveredManifestVerdict: Equatable, Sendable {
    case accepted
    case rejected(DiagnosticJournalRejection)
}

final class DiagnosticJournal {
    let fileSystem: any CaptureFileSystem
    let framePacketBuilder: FramePacketBuilder
    let configuration: DiagnosticCaptureConfiguration
    let crashInjector: CaptureCrashInjector
    private(set) var visibleFrameIDs: [String] = []
    private(set) var lifecycleByFrameID: [String: FrameCaptureLifecycle] = [:]

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
        _ = input
        _ = attempt
        throw DiagnosticJournalRejection.notImplemented
    }

    func recover() throws -> RecoveredCapture {
        throw DiagnosticJournalRejection.notImplemented
    }

    func validateRecoveredManifest(_ manifestData: Data) -> RecoveredManifestVerdict {
        _ = manifestData
        return .rejected(.notImplemented)
    }
}
