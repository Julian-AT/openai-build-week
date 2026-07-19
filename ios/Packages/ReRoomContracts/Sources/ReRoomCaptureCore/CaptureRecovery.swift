import Foundation

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

/// Recovery admission is dependency-injected with the same pinned verifier
/// that alone mints replay authority. It never publishes recovery output.
public struct CaptureRecovery: Sendable {
    static let maximumDocumentBytes = ArchiveVerifier.maximumMemberBytes
    static let maximumJournalBytes = 33_554_432
    static let maximumInventoryMembers = ArchiveVerifier.maximumInventoryMembers

    private let verifier: ArchiveVerifier
    private let reconstructor: DurablePrefixReconstructor

    public init(verifier: ArchiveVerifier) {
        self.verifier = verifier
        reconstructor = DurablePrefixReconstructor(verifier: verifier)
    }

    public func inspect(root: URL) throws -> RecoveredArchive {
        do {
            let archive = try verifier.verify(root: root)
            return try recoveredArchive(from: archive, root: root)
        } catch ArchiveVerificationError.archiveOpen {
            let candidate = try recoveryCandidate(root: root)
            return try candidate.recoveredArchive(archivePath: root.lastPathComponent)
        } catch let error as ArchiveVerificationError {
            throw CaptureRecoveryError(error)
        }
    }

    public func verifiedArchive(root: URL) throws -> VerifiedArchive {
        do {
            return try verifier.verify(root: root)
        } catch let error as ArchiveVerificationError {
            throw CaptureRecoveryError(error)
        }
    }

    func recoveryCandidate(root: URL) throws -> RecoveryGenerationCandidate {
        do {
            let source = try verifier.verifyRecoverySource(root: root)
            return try reconstructor.reconstruct(source: source, root: root)
        } catch let error as CaptureRecoveryError {
            throw error
        } catch let error as ArchiveVerificationError {
            throw CaptureRecoveryError(error)
        } catch {
            throw CaptureRecoveryError.invalidManifest
        }
    }

    private func recoveredArchive(from archive: VerifiedArchive, root: URL) throws -> RecoveredArchive {
        let finalization = try CaptureFinalization(
            sessionID: archive.sourceIdentity.sessionID,
            archivePath: root.lastPathComponent,
            state: archive.manifest.finalizationState,
            manifestSHA256: archive.sourceIdentity.manifestSHA256,
            lastDurableJournalSequence: archive.manifest.lastDurableJournalSequence,
            acceptedFrameCount: UInt64(archive.manifest.acceptedFrameCount),
            eventCount: UInt64(archive.manifest.eventCount)
        )
        return try RecoveredArchive(
            finalization: finalization,
            acceptedJournalRecordCount: UInt64(archive.manifest.journalRecordCount),
            firstInvalidJournalSequence: nil,
            quarantineSHA256: nil
        )
    }
}

extension CaptureRecoveryError {
    init(_ error: ArchiveVerificationError) {
        switch error {
        case .invalidRoot:
            self = .invalidRoot
        case .missingManifest:
            self = .missingManifest
        case .invalidJSON, .nonCanonicalJSON:
            self = .invalidJSON
        case .unsupportedContractVersion:
            self = .unsupportedContractVersion
        case .invalidPath:
            self = .invalidPath
        case .byteLimitExceeded, .numericOutOfRange:
            self = .byteLimitExceeded
        case .digestMismatch:
            self = .digestMismatch
        case .projectionMismatch:
            self = .projectionMismatch
        case .nonContiguousJournal:
            self = .nonContiguousJournal
        case .ioFailure:
            self = .ioFailure
        case .schemaValidation, .unknownProperty, .invalidIdentity, .semanticInvariant,
             .archiveOpen:
            self = .invalidManifest
        }
    }
}
