import Foundation
import ReRoomContracts

public enum CaptureValueError: String, Error, Equatable, Sendable {
    case invalidIdentity = "invalid_identity"
    case invalidPath = "invalid_path"
    case invalidDigest = "digest_mismatch"
    case invalidTimestamp = "invalid_timestamp"
    case invalidSequence = "invalid_sequence"
    case invalidPolicy = "invalid_policy"
    case invalidMetrics = "invalid_metrics"
    case invalidReplayReport = "invalid_replay_report"
    case emptyBytes = "empty_bytes"
    case byteLimitExceeded = "byte_limit_exceeded"
    case consentDenied = "consent_denied"
}

public enum CaptureRetentionPolicy: String, Codable, CaseIterable, Sendable {
    case localOnlyUntilShare = "local_only_until_share"
}

public struct CaptureSessionAuthorization: Codable, Equatable, Sendable {
    public let sessionID: String
    public let consentGranted: Bool
    public let retentionPolicy: CaptureRetentionPolicy

    public init(
        sessionID: String,
        consentGranted: Bool,
        retentionPolicy: CaptureRetentionPolicy = .localOnlyUntilShare
    ) throws {
        try CaptureValueValidation.requireID(sessionID, prefix: "session_")
        guard consentGranted else { throw CaptureValueError.consentDenied }
        self.sessionID = sessionID
        self.consentGranted = consentGranted
        self.retentionPolicy = retentionPolicy
    }
}

public struct CaptureSessionDescriptor: Codable, Equatable, Sendable {
    public let sessionID: String
    public let archivePath: String
    public let worldFrameID: String
    public let startedAtMonotonicNanoseconds: String

    public init(
        sessionID: String,
        archivePath: String,
        worldFrameID: String,
        startedAtMonotonicNanoseconds: String
    ) throws {
        try CaptureValueValidation.requireID(sessionID, prefix: "session_")
        try CaptureValueValidation.requireArchivePath(archivePath)
        try CaptureValueValidation.requireID(worldFrameID, prefix: "world_")
        try CaptureValueValidation.requireTimestamp(startedAtMonotonicNanoseconds)
        self.sessionID = sessionID
        self.archivePath = archivePath
        self.worldFrameID = worldFrameID
        self.startedAtMonotonicNanoseconds = startedAtMonotonicNanoseconds
    }
}

public enum SelectedFrameReason: String, Codable, CaseIterable, Sendable {
    case cadence
    case viewNovelty = "view_novelty"
    case keyframe
    case userEvent = "user_event"
    case recovery
}

public enum CaptureFrameLifecycleEvent: String, Codable, CaseIterable, Sendable {
    case selected = "frame_selected"
    case imageAndMetadataDurable = "frame_image_and_metadata_durable"
    case journaled = "frame_journaled"
    case networkEligible = "frame_network_eligible"
    case serverAcknowledged = "frame_server_acknowledged"
}

public struct SelectedFrameCandidate: Codable, Equatable, Sendable {
    public static let maximumImageBytes = 16_777_216

    public let sessionID: String
    public let frameID: String
    public let submapID: String
    public let worldFrameID: String
    public let worldFrameVersion: UInt64
    public let captureSequence: UInt64
    public let monotonicTimestampNanoseconds: String
    public let imageRelativePath: String
    public let packetRelativePath: String
    public let imageBytes: Data
    public let selectedReason: SelectedFrameReason
    public let idempotencyKey: String

    public init(
        sessionID: String,
        frameID: String,
        submapID: String,
        worldFrameID: String,
        worldFrameVersion: UInt64,
        captureSequence: UInt64,
        monotonicTimestampNanoseconds: String,
        imageRelativePath: String,
        packetRelativePath: String,
        imageBytes: Data,
        selectedReason: SelectedFrameReason,
        idempotencyKey: String
    ) throws {
        try CaptureValueValidation.requireID(sessionID, prefix: "session_")
        try CaptureValueValidation.requireID(frameID, prefix: "frame_")
        try CaptureValueValidation.requireID(submapID, prefix: "submap_")
        try CaptureValueValidation.requireID(worldFrameID, prefix: "world_")
        try CaptureValueValidation.requireID(idempotencyKey, prefix: "frameidem_")
        guard worldFrameVersion > 0 else { throw CaptureValueError.invalidSequence }
        try CaptureValueValidation.requireTimestamp(monotonicTimestampNanoseconds)
        try CaptureValueValidation.requireArchivePath(imageRelativePath)
        try CaptureValueValidation.requireArchivePath(packetRelativePath)
        guard imageBytes.isEmpty == false else { throw CaptureValueError.emptyBytes }
        guard imageBytes.count <= Self.maximumImageBytes else {
            throw CaptureValueError.byteLimitExceeded
        }
        self.sessionID = sessionID
        self.frameID = frameID
        self.submapID = submapID
        self.worldFrameID = worldFrameID
        self.worldFrameVersion = worldFrameVersion
        self.captureSequence = captureSequence
        self.monotonicTimestampNanoseconds = monotonicTimestampNanoseconds
        self.imageRelativePath = imageRelativePath
        self.packetRelativePath = packetRelativePath
        self.imageBytes = imageBytes
        self.selectedReason = selectedReason
        self.idempotencyKey = idempotencyKey
    }
}

public struct NetworkEligibleReceipt: Codable, Equatable, Sendable {
    public let sessionID: String
    public let frameID: String
    public let idempotencyKey: String
    public let packetRelativePath: String
    public let packetSHA256: String
    public let imageSHA256: String
    public let acceptedSequence: UInt64
    public let durableJournalSequence: UInt64

    public init(
        sessionID: String,
        frameID: String,
        idempotencyKey: String,
        packetRelativePath: String,
        packetSHA256: String,
        imageSHA256: String,
        acceptedSequence: UInt64,
        durableJournalSequence: UInt64
    ) throws {
        try CaptureValueValidation.requireID(sessionID, prefix: "session_")
        try CaptureValueValidation.requireID(frameID, prefix: "frame_")
        try CaptureValueValidation.requireID(idempotencyKey, prefix: "frameidem_")
        try CaptureValueValidation.requireArchivePath(packetRelativePath)
        try CaptureValueValidation.requireDigest(packetSHA256)
        try CaptureValueValidation.requireDigest(imageSHA256)
        self.sessionID = sessionID
        self.frameID = frameID
        self.idempotencyKey = idempotencyKey
        self.packetRelativePath = packetRelativePath
        self.packetSHA256 = packetSHA256
        self.imageSHA256 = imageSHA256
        self.acceptedSequence = acceptedSequence
        self.durableJournalSequence = durableJournalSequence
    }
}

public struct GatewayAcknowledgement: Codable, Equatable, Sendable {
    public let gatewayID: String
    public let sessionID: String
    public let frameID: String
    public let idempotencyKey: String
    public let packetSHA256: String
    public let acceptedSequence: UInt64

    public init(
        gatewayID: String,
        sessionID: String,
        frameID: String,
        idempotencyKey: String,
        packetSHA256: String,
        acceptedSequence: UInt64
    ) throws {
        try CaptureValueValidation.requireID(gatewayID, prefix: "gateway_")
        try CaptureValueValidation.requireID(sessionID, prefix: "session_")
        try CaptureValueValidation.requireID(frameID, prefix: "frame_")
        try CaptureValueValidation.requireID(idempotencyKey, prefix: "frameidem_")
        try CaptureValueValidation.requireDigest(packetSHA256)
        self.gatewayID = gatewayID
        self.sessionID = sessionID
        self.frameID = frameID
        self.idempotencyKey = idempotencyKey
        self.packetSHA256 = packetSHA256
        self.acceptedSequence = acceptedSequence
    }
}

public enum CaptureFinalizationState: String, Codable, CaseIterable, Sendable {
    case open
    case finalized
    case recoveredPrefix = "recovered_prefix"
}

public struct CaptureFinalization: Codable, Equatable, Sendable {
    public let sessionID: String
    public let archivePath: String
    public let state: CaptureFinalizationState
    public let manifestSHA256: String
    public let lastDurableJournalSequence: UInt64
    public let acceptedFrameCount: UInt64
    public let eventCount: UInt64

    public init(
        sessionID: String,
        archivePath: String,
        state: CaptureFinalizationState,
        manifestSHA256: String,
        lastDurableJournalSequence: UInt64,
        acceptedFrameCount: UInt64,
        eventCount: UInt64
    ) throws {
        try CaptureValueValidation.requireID(sessionID, prefix: "session_")
        try CaptureValueValidation.requireArchivePath(archivePath)
        try CaptureValueValidation.requireDigest(manifestSHA256)
        self.sessionID = sessionID
        self.archivePath = archivePath
        self.state = state
        self.manifestSHA256 = manifestSHA256
        self.lastDurableJournalSequence = lastDurableJournalSequence
        self.acceptedFrameCount = acceptedFrameCount
        self.eventCount = eventCount
    }
}

public struct RecoveredArchive: Codable, Equatable, Sendable {
    public let finalization: CaptureFinalization
    public let acceptedJournalRecordCount: UInt64
    public let firstInvalidJournalSequence: UInt64?
    public let quarantineSHA256: String?

    public init(
        finalization: CaptureFinalization,
        acceptedJournalRecordCount: UInt64,
        firstInvalidJournalSequence: UInt64?,
        quarantineSHA256: String?
    ) throws {
        guard acceptedJournalRecordCount > 0 else { throw CaptureValueError.invalidSequence }
        switch finalization.state {
        case .open:
            throw CaptureValueError.invalidReplayReport
        case .finalized:
            guard firstInvalidJournalSequence == nil, quarantineSHA256 == nil else {
                throw CaptureValueError.invalidReplayReport
            }
        case .recoveredPrefix:
            guard let firstInvalidJournalSequence,
                  let quarantineSHA256,
                  firstInvalidJournalSequence == acceptedJournalRecordCount
            else {
                throw CaptureValueError.invalidReplayReport
            }
            try CaptureValueValidation.requireDigest(quarantineSHA256)
        }
        self.finalization = finalization
        self.acceptedJournalRecordCount = acceptedJournalRecordCount
        self.firstInvalidJournalSequence = firstInvalidJournalSequence
        self.quarantineSHA256 = quarantineSHA256
    }
}

public enum ReplayVerdict: String, Codable, CaseIterable, Sendable {
    case accept
    case reject
}

public enum ReplayTimelineEntryType: String, Codable, CaseIterable, Sendable {
    case event
    case frame
}

public struct ReplayTimelineEntry: Codable, Equatable, Sendable {
    public let journalSequence: UInt64
    public let entryType: ReplayTimelineEntryType
    public let referenceID: String
    public let contentSHA256: String
    public let monotonicTimestampNanoseconds: String

    public init(
        journalSequence: UInt64,
        entryType: ReplayTimelineEntryType,
        referenceID: String,
        contentSHA256: String,
        monotonicTimestampNanoseconds: String
    ) throws {
        try CaptureValueValidation.requireID(
            referenceID,
            prefix: entryType == .event ? "event_" : "frame_"
        )
        try CaptureValueValidation.requireDigest(contentSHA256)
        try CaptureValueValidation.requireTimestamp(monotonicTimestampNanoseconds)
        self.journalSequence = journalSequence
        self.entryType = entryType
        self.referenceID = referenceID
        self.contentSHA256 = contentSHA256
        self.monotonicTimestampNanoseconds = monotonicTimestampNanoseconds
    }
}

public struct ReplayEvaluator: Codable, Equatable, Sendable {
    public let name: String
    public let version: String
    public let platform: String

    public init(name: String, version: String, platform: String) {
        self.name = name
        self.version = version
        self.platform = platform
    }
}

public struct ReplayFixtureIdentity: Codable, Equatable, Sendable {
    public let fixtureID: String
    public let fixtureRevision: String
    public let manifestSHA256: String

    public init(
        fixtureID: String,
        fixtureRevision: String,
        manifestSHA256: String
    ) throws {
        guard fixtureID.hasPrefix("FX-"), fixtureID.count > 3,
              fixtureRevision.hasPrefix("rev-"), fixtureRevision.count > 4
        else { throw CaptureValueError.invalidIdentity }
        try CaptureValueValidation.requireDigest(manifestSHA256)
        self.fixtureID = fixtureID
        self.fixtureRevision = fixtureRevision
        self.manifestSHA256 = manifestSHA256
    }
}

public struct ReplayImplementationIdentity: Codable, Equatable, Sendable {
    public let repositoryRevision: String
    public let runtime: String
    public let buildID: String

    public init(repositoryRevision: String, runtime: String, buildID: String) {
        self.repositoryRevision = repositoryRevision
        self.runtime = runtime
        self.buildID = buildID
    }
}

public struct ReplayArchiveIdentity: Codable, Equatable, Sendable {
    public let caseID: String
    public let archiveName: String
    public let finalizationState: CaptureFinalizationState
    public let manifestSHA256: String
    public let acceptedFrameCount: UInt64
    public let eventCount: UInt64
    public let journalRecordCount: UInt64

    public init(
        caseID: String,
        archiveName: String,
        finalizationState: CaptureFinalizationState,
        manifestSHA256: String,
        acceptedFrameCount: UInt64,
        eventCount: UInt64,
        journalRecordCount: UInt64
    ) throws {
        guard caseID.isEmpty == false,
              archiveName.hasSuffix(".rrcap"),
              archiveName.contains("/") == false,
              finalizationState != .open,
              journalRecordCount > 0
        else { throw CaptureValueError.invalidReplayReport }
        try CaptureValueValidation.requireArchivePath(archiveName)
        try CaptureValueValidation.requireDigest(manifestSHA256)
        self.caseID = caseID
        self.archiveName = archiveName
        self.finalizationState = finalizationState
        self.manifestSHA256 = manifestSHA256
        self.acceptedFrameCount = acceptedFrameCount
        self.eventCount = eventCount
        self.journalRecordCount = journalRecordCount
    }
}

public struct ReplayDigestSet: Codable, Equatable, Sendable {
    public let journalTupleSHA256: String
    public let frameProjectionSHA256: String
    public let eventProjectionSHA256: String
    public let revisionTraceSHA256: String

    public init(
        journalTupleSHA256: String,
        frameProjectionSHA256: String,
        eventProjectionSHA256: String,
        revisionTraceSHA256: String
    ) throws {
        try [
            journalTupleSHA256,
            frameProjectionSHA256,
            eventProjectionSHA256,
            revisionTraceSHA256,
        ].forEach(CaptureValueValidation.requireDigest)
        self.journalTupleSHA256 = journalTupleSHA256
        self.frameProjectionSHA256 = frameProjectionSHA256
        self.eventProjectionSHA256 = eventProjectionSHA256
        self.revisionTraceSHA256 = revisionTraceSHA256
    }
}

public enum ReplayRejectionClass: String, Codable, CaseIterable, Sendable {
    case digestMismatch = "digest_mismatch"
    case invalidIdentity = "invalid_identity"
    case invalidPath = "invalid_path"
    case invalidUnicode = "invalid_unicode"
    case nonContiguousJournal = "non_contiguous_journal"
    case numericOutOfRange = "numeric_out_of_range"
    case schemaValidation = "schema_validation"
    case semanticInvariant = "semantic_invariant"
    case unknownProperty = "unknown_property"
    case unsupportedContractVersion = "unsupported_contract_version"
    case wireLengthMismatch = "wire_length_mismatch"
}

public struct ReplayRejection: Codable, Equatable, Sendable {
    public let rejectionClass: ReplayRejectionClass
    public let detail: String

    public init(rejectionClass: ReplayRejectionClass, detail: String) {
        self.rejectionClass = rejectionClass
        self.detail = detail
    }
}

public struct ReplayMetrics: Codable, Equatable, Sendable {
    public let maximumQueueDepth: UInt64
    public let droppedStaleCandidates: UInt64
    public let recoveredPrefixRecords: UInt64
    public let quarantinedSuffixRecords: UInt64

    public init(
        maximumQueueDepth: UInt64,
        droppedStaleCandidates: UInt64,
        recoveredPrefixRecords: UInt64,
        quarantinedSuffixRecords: UInt64
    ) {
        self.maximumQueueDepth = maximumQueueDepth
        self.droppedStaleCandidates = droppedStaleCandidates
        self.recoveredPrefixRecords = recoveredPrefixRecords
        self.quarantinedSuffixRecords = quarantinedSuffixRecords
    }
}

public struct ReplayReportV1: Codable, Equatable, Sendable {
    public let reportVersion: String
    public let evaluator: ReplayEvaluator
    public let fixture: ReplayFixtureIdentity
    public let archive: ReplayArchiveIdentity
    public let implementation: ReplayImplementationIdentity
    public let verdict: ReplayVerdict
    public let digests: ReplayDigestSet
    public let rejection: ReplayRejection?
    public let metrics: ReplayMetrics
    public let reportSHA256: String

    public init(
        evaluator: ReplayEvaluator,
        fixture: ReplayFixtureIdentity,
        archive: ReplayArchiveIdentity,
        implementation: ReplayImplementationIdentity,
        verdict: ReplayVerdict,
        digests: ReplayDigestSet,
        rejection: ReplayRejection?,
        metrics: ReplayMetrics,
        reportSHA256: String
    ) throws {
        guard evaluator.name.isEmpty == false,
              evaluator.version.isEmpty == false,
              evaluator.platform.isEmpty == false,
              implementation.repositoryRevision.isEmpty == false,
              implementation.runtime.isEmpty == false,
              implementation.buildID.isEmpty == false,
              (verdict == .accept) == (rejection == nil),
              rejection?.detail.isEmpty != true
        else { throw CaptureValueError.invalidReplayReport }
        try CaptureValueValidation.requireDigest(reportSHA256)
        self.reportVersion = "1.0.0"
        self.evaluator = evaluator
        self.fixture = fixture
        self.archive = archive
        self.implementation = implementation
        self.verdict = verdict
        self.digests = digests
        self.rejection = rejection
        self.metrics = metrics
        self.reportSHA256 = reportSHA256
    }
}

public enum EvidenceClassification: String, Codable, CaseIterable, Sendable {
    case target = "TARGET"
    case hypothesis = "HYPOTHESIS"
    case measured = "MEASURED"
}

public struct FrameSelectionPolicy: Codable, Equatable, Sendable {
    public let policyID: String
    public let classification: EvidenceClassification
    public let minimumCadenceNanoseconds: UInt64
    public let minimumViewNovelty: Float
    public let maximumMotionScore: Float
    public let minimumBlurScore: Float
    public let minimumExposureScore: Float

    public init(
        policyID: String,
        classification: EvidenceClassification,
        minimumCadenceNanoseconds: UInt64,
        minimumViewNovelty: Float,
        maximumMotionScore: Float,
        minimumBlurScore: Float,
        minimumExposureScore: Float
    ) throws {
        guard CaptureValueValidation.isPolicyID(policyID),
              minimumCadenceNanoseconds > 0,
              [minimumViewNovelty, maximumMotionScore, minimumBlurScore, minimumExposureScore]
              .allSatisfy({ $0.isFinite && (0...1).contains($0) })
        else { throw CaptureValueError.invalidPolicy }
        self.policyID = policyID
        self.classification = classification
        self.minimumCadenceNanoseconds = minimumCadenceNanoseconds
        self.minimumViewNovelty = minimumViewNovelty
        self.maximumMotionScore = maximumMotionScore
        self.minimumBlurScore = minimumBlurScore
        self.minimumExposureScore = minimumExposureScore
    }
}

public struct CapturePressurePolicy: Codable, Equatable, Sendable {
    public let policyID: String
    public let classification: EvidenceClassification
    public let ordinaryCapacity: Int
    public let optionalComputeDropDepth: Int
    public let uploadPauseDepth: Int
    public let cadenceReductionDepth: Int

    public init(
        policyID: String,
        classification: EvidenceClassification,
        ordinaryCapacity: Int,
        optionalComputeDropDepth: Int,
        uploadPauseDepth: Int,
        cadenceReductionDepth: Int
    ) throws {
        guard CaptureValueValidation.isPolicyID(policyID),
              ordinaryCapacity > 0,
              (0...ordinaryCapacity).contains(optionalComputeDropDepth),
              (optionalComputeDropDepth...ordinaryCapacity).contains(uploadPauseDepth),
              (uploadPauseDepth...ordinaryCapacity).contains(cadenceReductionDepth)
        else { throw CaptureValueError.invalidPolicy }
        self.policyID = policyID
        self.classification = classification
        self.ordinaryCapacity = ordinaryCapacity
        self.optionalComputeDropDepth = optionalComputeDropDepth
        self.uploadPauseDepth = uploadPauseDepth
        self.cadenceReductionDepth = cadenceReductionDepth
    }
}

public enum CapturePressureReason: String, Codable, CaseIterable, Sendable {
    case none
    case optionalComputeDropped = "optional_compute_dropped"
    case uploadPaused = "upload_paused"
    case cadenceQualityReduced = "cadence_quality_reduced"
    case storageUnavailable = "storage_unavailable"
}

public struct QueueMetricsSnapshot: Codable, Equatable, Sendable {
    public let offered: UInt64
    public let accepted: UInt64
    public let replaced: UInt64
    public let dropped: UInt64
    public let completed: UInt64
    public let cancelled: UInt64
    public let currentDepth: Int
    public let maximumDepth: Int
    public let uploadPaused: Bool
    public let pressureReason: CapturePressureReason

    public init(
        offered: UInt64,
        accepted: UInt64,
        replaced: UInt64,
        dropped: UInt64,
        completed: UInt64,
        cancelled: UInt64,
        currentDepth: Int,
        maximumDepth: Int,
        uploadPaused: Bool,
        pressureReason: CapturePressureReason
    ) throws {
        let pressureRequiresUploadPause = [
            CapturePressureReason.uploadPaused,
            .cadenceQualityReduced,
            .storageUnavailable,
        ].contains(pressureReason)
        guard accepted <= offered,
              dropped <= offered,
              replaced <= accepted,
              completed <= accepted,
              cancelled <= accepted,
              currentDepth >= 0,
              maximumDepth >= currentDepth,
              uploadPaused == pressureRequiresUploadPause
        else { throw CaptureValueError.invalidMetrics }
        self.offered = offered
        self.accepted = accepted
        self.replaced = replaced
        self.dropped = dropped
        self.completed = completed
        self.cancelled = cancelled
        self.currentDepth = currentDepth
        self.maximumDepth = maximumDepth
        self.uploadPaused = uploadPaused
        self.pressureReason = pressureReason
    }
}

private enum CaptureValueValidation {
    static func requireID(_ value: String, prefix: String) throws {
        guard value.hasPrefix(prefix) else { throw CaptureValueError.invalidIdentity }
        let suffix = String(value.dropFirst(prefix.count))
        let characters = Array(suffix.utf8)
        let hyphenOffsets = Set([8, 13, 18, 23])
        guard characters.count == 36,
              characters.enumerated().allSatisfy({ offset, byte in
                  hyphenOffsets.contains(offset) ? byte == 0x2d : byte.isLowerHexadecimal
              }),
              characters[14] == 0x34,
              [0x38, 0x39, 0x61, 0x62].contains(characters[19])
        else { throw CaptureValueError.invalidIdentity }
    }

    static func requireArchivePath(_ value: String) throws {
        do {
            try ArchivePath.validate(value)
        } catch {
            throw CaptureValueError.invalidPath
        }
    }

    static func requireDigest(_ value: String) throws {
        guard value.utf8.count == 64, value.utf8.allSatisfy(\.isLowerHexadecimal) else {
            throw CaptureValueError.invalidDigest
        }
    }

    static func requireTimestamp(_ value: String) throws {
        guard value == "0"
                || (value.first.map({ ("1"..."9").contains($0) }) == true
                    && value.allSatisfy({ ("0"..."9").contains($0) }))
        else { throw CaptureValueError.invalidTimestamp }
    }

    static func isPolicyID(_ value: String) -> Bool {
        value.hasPrefix("policy_")
            && value.utf8.count > 7
            && value.utf8.allSatisfy { byte in
                byte.isLowerHexadecimal
                    || (0x67...0x7a).contains(byte)
                    || byte == 0x5f
                    || byte == 0x2d
            }
    }
}

private extension UInt8 {
    var isLowerHexadecimal: Bool {
        (0x30...0x39).contains(self) || (0x61...0x66).contains(self)
    }
}
