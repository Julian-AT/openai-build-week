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

    /// Imports finalized/recovered input or reconstructs an open input, then
    /// crosses the visibility boundary only through `RecoveryPublisher`.
    public func publish(
        root: URL,
        using publisher: RecoveryPublisher
    ) throws -> RecoveryPublication {
        try publisher.publish(publicationCandidate(root: root))
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

    private func publicationCandidate(root: URL) throws -> RecoveryGenerationCandidate {
        do {
            let archive = try verifier.verify(root: root)
            let boundary = try RecoveryPublicationSourceBoundary(root: root)
            let manifestData = try boundary.read(
                relativePath: "manifest.json",
                maximumBytes: ArchiveVerifier.maximumManifestBytes
            )
            guard manifestData.count == archive.manifest.byteLength,
                  CanonicalJSON.sha256Hex(manifestData) == archive.manifest.sha256
            else { throw CaptureRecoveryError.digestMismatch }
            let journalData = try canonicalJournalData(from: manifestData)
            let members = try archive.members.map { descriptor in
                let data = try boundary.read(
                    relativePath: descriptor.relativePath,
                    maximumBytes: ArchiveVerifier.maximumMemberBytes
                )
                guard data.count == descriptor.byteLength,
                      CanonicalJSON.sha256Hex(data) == descriptor.sha256
                else { throw CaptureRecoveryError.digestMismatch }
                return RecoveryCandidateMember(descriptor: descriptor, data: data)
            }
            return RecoveryGenerationCandidate(
                sourceIdentity: archive.sourceIdentity,
                manifestData: manifestData,
                members: members,
                journalData: journalData,
                invalidSuffix: nil,
                acceptedPrefixJournalSHA256: CanonicalJSON.sha256Hex(journalData),
                finalizationState: archive.manifest.finalizationState,
                manifestSHA256: archive.sourceIdentity.manifestSHA256,
                lastDurableJournalSequence: archive.manifest.lastDurableJournalSequence,
                acceptedFrameCount: UInt64(archive.manifest.acceptedFrameCount),
                eventCount: UInt64(archive.manifest.eventCount)
            )
        } catch ArchiveVerificationError.archiveOpen {
            return try recoveryCandidate(root: root)
        } catch let error as CaptureRecoveryError {
            throw error
        } catch let error as ArchiveVerificationError {
            throw CaptureRecoveryError(error)
        } catch {
            throw CaptureRecoveryError.ioFailure
        }
    }

    private func canonicalJournalData(from manifestData: Data) throws -> Data {
        let object: [String: Any]
        do {
            guard let value = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any] else {
                throw CaptureRecoveryError.invalidJSON
            }
            object = value
        } catch let error as CaptureRecoveryError {
            throw error
        } catch {
            throw CaptureRecoveryError.invalidJSON
        }
        guard let records = object["journal"] as? [Any], records.isEmpty == false else {
            throw CaptureRecoveryError.invalidManifest
        }
        var result = Data()
        for record in records {
            do {
                let encoded = try JSONSerialization.data(
                    withJSONObject: record,
                    options: [.sortedKeys]
                )
                result.append(try CanonicalJSON.canonicalize(jsonData: encoded))
                result.append(0x0a)
            } catch {
                throw CaptureRecoveryError.invalidJSON
            }
        }
        guard result.count <= Self.maximumJournalBytes else {
            throw CaptureRecoveryError.byteLimitExceeded
        }
        return result
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

private struct RecoveryPublicationSourceBoundary {
    let root: URL

    init(root: URL) throws {
        guard root.isFileURL else { throw CaptureRecoveryError.invalidRoot }
        let standardized = root.standardizedFileURL
        let values = try? standardized.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard values?.isDirectory == true,
              values?.isSymbolicLink != true,
              standardized.resolvingSymlinksInPath().path == standardized.path
        else { throw CaptureRecoveryError.invalidRoot }
        self.root = standardized
    }

    func read(relativePath: String, maximumBytes: Int) throws -> Data {
        guard maximumBytes > 0 else { throw CaptureRecoveryError.byteLimitExceeded }
        let url: URL
        do {
            url = try ArchivePath.resolve(relativePath, under: root)
        } catch {
            throw CaptureRecoveryError.invalidPath
        }
        var cursor = root
        for component in relativePath.split(separator: "/") {
            cursor.appendPathComponent(String(component))
            let values = try? cursor.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values?.isSymbolicLink != true else {
                throw CaptureRecoveryError.invalidPath
            }
        }
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
