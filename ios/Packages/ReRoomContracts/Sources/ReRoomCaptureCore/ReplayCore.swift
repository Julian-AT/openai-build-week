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
    public static func replay(root: URL) throws -> ReplaySnapshot {
        let archive: RecoveryValidatedArchive
        do {
            archive = try CaptureRecovery.verifiedArchive(root: root)
        } catch let error as CaptureRecoveryError {
            throw ReplayCoreError(error)
        } catch {
            throw ReplayCoreError.semanticInvariant
        }

        do {
            let timeline = try archive.journal.map { entry -> ReplayTimelineEntry in
                guard let sequence = replayUInt(entry["journal_sequence"]),
                      let typeText = entry["entry_type"] as? String,
                      let type = ReplayTimelineEntryType(rawValue: typeText),
                      let referenceID = entry["reference_id"] as? String,
                      let digest = entry["content_sha256"] as? String,
                      let timestamp = entry["monotonic_timestamp_ns"] as? String
                else { throw ReplayCoreError.semanticInvariant }
                return try ReplayTimelineEntry(
                    journalSequence: sequence,
                    entryType: type,
                    referenceID: referenceID,
                    contentSHA256: digest,
                    monotonicTimestampNanoseconds: timestamp
                )
            }
            guard timeline.indices.allSatisfy({ timeline[$0].journalSequence == UInt64($0) }) else {
                throw ReplayCoreError.nonContiguousJournal
            }

            let revisionTrace: [[String: Any]] = [[
                "journal_sequence": 0,
                "revision_id": archive.sessionID.replacingOccurrences(
                    of: "session_",
                    with: "revision_",
                    options: [.anchored]
                ),
                "source": "capture_baseline",
            ]]
            let digests = try ReplayDigestSet(
                journalTupleSHA256: try replayJournalDigest(archive.journal),
                frameProjectionSHA256: CanonicalJSON.sha256Hex(
                    try replayCanonicalData(archive.frames)
                ),
                eventProjectionSHA256: CanonicalJSON.sha256Hex(
                    try replayCanonicalData(archive.events)
                ),
                revisionTraceSHA256: CanonicalJSON.sha256Hex(
                    try replayCanonicalData(revisionTrace)
                )
            )
            let lastSequence = UInt64(archive.journal.count - 1)
            let finalization = try CaptureFinalization(
                sessionID: archive.sessionID,
                archivePath: root.lastPathComponent,
                state: archive.state,
                manifestSHA256: archive.manifestSHA256,
                lastDurableJournalSequence: lastSequence,
                acceptedFrameCount: UInt64(archive.frames.count),
                eventCount: UInt64(archive.events.count)
            )
            return ReplaySnapshot(
                finalization: finalization,
                timeline: timeline,
                digests: digests
            )
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
    init(_ error: CaptureRecoveryError) {
        switch error {
        case .digestMismatch:
            self = .digestMismatch
        case .invalidPath:
            self = .invalidPath
        case .nonContiguousJournal:
            self = .nonContiguousJournal
        case .unsupportedContractVersion, .unsupportedCodec, .unsupportedDigest:
            self = .unsupportedContractVersion
        case .interiorCorruption:
            self = .nonContiguousJournal
        case .missingManifest, .missingJournal, .emptyJournal, .invalidRoot, .invalidJSON,
             .invalidManifest, .byteLimitExceeded, .projectionMismatch, .noRecoverablePrefix,
             .publicationConflict, .ioFailure:
            self = .semanticInvariant
        }
    }
}

func replayCanonicalData(_ value: Any) throws -> Data {
    let encoded = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    return try CanonicalJSON.canonicalize(jsonData: encoded)
}

private func replayJournalDigest(_ journal: [[String: Any]]) throws -> String {
    let tuples = try journal.map { entry -> [Any] in
        guard let sequence = replayUInt(entry["journal_sequence"]),
              let type = entry["entry_type"] as? String,
              let referenceID = entry["reference_id"] as? String,
              let digest = entry["content_sha256"] as? String
        else { throw ReplayCoreError.semanticInvariant }
        return [sequence, type, referenceID, digest]
    }
    return CanonicalJSON.sha256Hex(try replayCanonicalData(tuples))
}

private func replayUInt(_ value: Any?) -> UInt64? {
    guard let number = value as? NSNumber,
          number.objCType.pointee != 0x63,
          number.doubleValue >= 0,
          number.doubleValue.rounded(.towardZero) == number.doubleValue,
          number.doubleValue <= 9_007_199_254_740_991
    else { return nil }
    return number.uint64Value
}
