import Foundation
import ReRoomContracts

public enum ReplayCoreError: String, Error, Equatable, Sendable {
    case digestMismatch = "digest_mismatch"
    case invalidIdentity = "invalid_identity"
    case invalidPath = "invalid_path"
    case nonContiguousJournal = "non_contiguous_journal"
    case semanticInvariant = "semantic_invariant"
    case unsupportedContractVersion = "unsupported_contract_version"
}

public struct ReplaySnapshot: Equatable, Sendable {
    public let finalization: CaptureFinalization
    public let timeline: [ReplayTimelineEntry]
    public let digests: ReplayDigestSet

    public init(
        finalization: CaptureFinalization,
        timeline: [ReplayTimelineEntry],
        digests: ReplayDigestSet
    ) {
        self.finalization = finalization
        self.timeline = timeline
        self.digests = digests
    }
}

public enum ReplayCore {
    public static func replay(_ archive: VerifiedArchive) throws -> ReplaySnapshot {
        do {
            let contents = try archive.consumeVerifiedContents()
            let timeline = try contents.journal.map { entry -> ReplayTimelineEntry in
                guard let type = ReplayTimelineEntryType(rawValue: entry.entryType) else {
                    throw ReplayCoreError.semanticInvariant
                }
                return try ReplayTimelineEntry(
                    journalSequence: entry.journalSequence,
                    entryType: type,
                    referenceID: entry.referenceID,
                    contentSHA256: entry.contentSHA256,
                    monotonicTimestampNanoseconds: entry.timestamp
                )
            }
            guard timeline.indices.allSatisfy({ timeline[$0].journalSequence == UInt64($0) }) else {
                throw ReplayCoreError.nonContiguousJournal
            }

            let revisionTrace: [[String: Any]] = [[
                "journal_sequence": 0,
                "revision_id": contents.sourceIdentity.sessionID.replacingOccurrences(
                    of: "session_",
                    with: "revision_",
                    options: [.anchored]
                ),
                "source": "capture_baseline",
            ]]
            let digests = try ReplayDigestSet(
                journalTupleSHA256: try replayJournalDigest(contents.journal),
                frameProjectionSHA256: CanonicalJSON.sha256Hex(
                    replayCanonicalArray(contents.frames.map(\.canonicalProjectionData))
                ),
                eventProjectionSHA256: CanonicalJSON.sha256Hex(
                    replayCanonicalArray(contents.events.map(\.canonicalProjectionData))
                ),
                revisionTraceSHA256: CanonicalJSON.sha256Hex(
                    try replayCanonicalData(revisionTrace)
                )
            )
            let finalization = try CaptureFinalization(
                sessionID: contents.sourceIdentity.sessionID,
                archivePath: contents.archiveName,
                state: contents.manifest.finalizationState,
                manifestSHA256: contents.sourceIdentity.manifestSHA256,
                lastDurableJournalSequence: contents.manifest.lastDurableJournalSequence,
                acceptedFrameCount: UInt64(contents.frames.count),
                eventCount: UInt64(contents.events.count)
            )
            return ReplaySnapshot(
                finalization: finalization,
                timeline: timeline,
                digests: digests
            )
        } catch let error as ArchiveVerificationError {
            throw ReplayCoreError(error)
        } catch let error as ReplayCoreError {
            throw error
        } catch {
            throw ReplayCoreError.semanticInvariant
        }
    }
}

public enum ReplayInputIntegrity {
    public static let maximumDocumentBytes = 33_554_432

    public static func canonicalizeJSON(_ data: Data) throws -> Data {
        try CanonicalJSON.canonicalize(jsonData: data)
    }

    public static func sha256Hex(_ data: Data) -> String {
        CanonicalJSON.sha256Hex(data)
    }

    public static func resolveArchivePath(_ path: String, under root: URL) throws -> URL {
        try ArchivePath.resolve(path, under: root)
    }
}

private extension ReplayCoreError {
    init(_ error: ArchiveVerificationError) {
        switch error {
        case .digestMismatch:
            self = .digestMismatch
        case .invalidIdentity:
            self = .invalidIdentity
        case .invalidPath:
            self = .invalidPath
        case .nonContiguousJournal:
            self = .nonContiguousJournal
        case .unsupportedContractVersion:
            self = .unsupportedContractVersion
        case .invalidRoot, .missingManifest, .invalidJSON, .nonCanonicalJSON,
             .schemaValidation, .unknownProperty, .numericOutOfRange, .byteLimitExceeded,
             .semanticInvariant, .projectionMismatch, .archiveOpen, .ioFailure:
            self = .semanticInvariant
        }
    }
}

func replayCanonicalData(_ value: Any) throws -> Data {
    let encoded = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    return try CanonicalJSON.canonicalize(jsonData: encoded)
}

private func replayJournalDigest(_ journal: [VerifiedJournalRecord]) throws -> String {
    let tuples: [[Any]] = journal.map { entry in
        [
            entry.journalSequence,
            entry.entryType,
            entry.referenceID,
            entry.contentSHA256,
        ]
    }
    return CanonicalJSON.sha256Hex(try replayCanonicalData(tuples))
}

private func replayCanonicalArray(_ values: [Data]) -> Data {
    var result = Data([0x5b])
    for (index, value) in values.enumerated() {
        if index > 0 { result.append(0x2c) }
        result.append(value)
    }
    result.append(0x5d)
    return result
}
