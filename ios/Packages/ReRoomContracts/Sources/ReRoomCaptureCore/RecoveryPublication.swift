import Foundation
import ReRoomContracts

public struct RecoveryPublication: Sendable {
    public let sourceIdentity: VerifiedArchiveSourceIdentity
    public let generationID: String
    public let inventorySHA256: String
    public let archive: VerifiedArchive
    public let recoveredArchive: RecoveredArchive
    public let reusedExistingGeneration: Bool
}

/// Synchronous pointer-last publication for one source-scoped recovery result.
///
/// A publication becomes visible only when the exclusively installed active
/// pointer and its containing source directory have both been synchronized.
public struct RecoveryPublisher: Sendable {
    private static let formatVersion = "1.0.0"
    private static let maximumInventoryBytes = 1_048_576
    private static let maximumPointerBytes = 16_384

    private let fileSystem: any CaptureFileSystem
    private let verifier: ArchiveVerifier
    private let rootPath: String
    private let stagingToken: @Sendable () -> String

    public init(
        fileSystem: any CaptureFileSystem,
        verifier: ArchiveVerifier,
        rootPath: String = "recovery-publications",
        stagingToken: @escaping @Sendable () -> String = {
            UUID().uuidString.lowercased()
        }
    ) {
        self.fileSystem = fileSystem
        self.verifier = verifier
        self.rootPath = rootPath
        self.stagingToken = stagingToken
    }

    public func recover(
        sourceIdentitySHA256: String
    ) throws -> RecoveryPublication? {
        guard Self.validDigest(sourceIdentitySHA256), Self.validComponent(rootPath) else {
            throw CaptureRecoveryError.invalidPath
        }
        let sourceRoot = sourceRoot(for: sourceIdentitySHA256)
        guard try fileSystem.fileExists(at: sourceRoot) else { return nil }
        let pointerPath = activePointerPath(sourceRoot: sourceRoot)
        guard try fileSystem.fileExists(at: pointerPath) else { return nil }

        let pointer = try readPointer(at: pointerPath)
        guard pointer.sourceIdentitySHA256 == sourceIdentitySHA256,
              pointer.generationID == pointer.inventorySHA256
        else { throw CaptureRecoveryError.publicationConflict }
        return try verifyGeneration(
            at: generationRoot(sourceRoot: sourceRoot, generationID: pointer.generationID),
            expectedGenerationID: pointer.generationID,
            expectedSourceIdentitySHA256: sourceIdentitySHA256,
            reusedExistingGeneration: true
        )
    }

    func publish(
        _ candidate: RecoveryGenerationCandidate
    ) throws -> RecoveryPublication {
        let encoded = try Self.encode(candidate)
        let sourceDigest = candidate.sourceIdentity.sha256
        guard Self.validComponent(rootPath), Self.validDigest(sourceDigest) else {
            throw CaptureRecoveryError.invalidPath
        }

        let sourceRoot = sourceRoot(for: sourceDigest)
        let generations = generationsPath(sourceRoot: sourceRoot)
        try prepareDirectories(sourceRoot: sourceRoot, generations: generations)

        if let active = try recover(sourceIdentitySHA256: sourceDigest) {
            guard active.generationID == encoded.generationID else {
                throw CaptureRecoveryError.publicationConflict
            }
            return active
        }

        let token = stagingToken()
        guard Self.validToken(token) else { throw CaptureRecoveryError.invalidPath }
        let stagingRoot = "\(sourceRoot)/_recovery-staging-\(token)"
        let stagedPointer = "\(sourceRoot)/_active-pointer-staging-\(token).json"
        guard try fileSystem.fileExists(at: stagingRoot) == false,
              try fileSystem.fileExists(at: stagedPointer) == false
        else { throw CaptureRecoveryError.publicationConflict }

        defer {
            try? removeOwnedItemIfPresent(at: stagingRoot)
            try? removeOwnedItemIfPresent(at: stagedPointer)
        }

        try fileSystem.createDirectory(at: stagingRoot)
        try createPayloadDirectories(encoded.directories, under: stagingRoot)
        for member in encoded.members {
            let path = "\(stagingRoot)/\(member.path)"
            try fileSystem.write(member.data, to: path)
            try fileSystem.synchronizeFile(at: path)
        }
        let stagedInventory = "\(stagingRoot)/inventory.json"
        try fileSystem.write(encoded.inventoryData, to: stagedInventory)
        try fileSystem.synchronizeFile(at: stagedInventory)
        try synchronizeStagingDirectories(encoded.directories, stagingRoot: stagingRoot)

        _ = try verifyGeneration(
            at: stagingRoot,
            expectedGenerationID: encoded.generationID,
            expectedSourceIdentitySHA256: sourceDigest,
            reusedExistingGeneration: false
        )

        let finalRoot = generationRoot(
            sourceRoot: sourceRoot,
            generationID: encoded.generationID
        )
        var reusedGeneration = false
        do {
            try fileSystem.renameExclusively(from: stagingRoot, to: finalRoot)
            try fileSystem.synchronizeDirectory(at: generations)
        } catch CaptureFileSystemError.destinationExists {
            reusedGeneration = true
            try fileSystem.synchronizeDirectory(at: generations)
        }

        let finalPublication = try verifyGeneration(
            at: finalRoot,
            expectedGenerationID: encoded.generationID,
            expectedSourceIdentitySHA256: sourceDigest,
            reusedExistingGeneration: reusedGeneration
        )

        let pointer = RecoveryActivePointer(
            formatVersion: Self.formatVersion,
            sourceIdentitySHA256: sourceDigest,
            generationID: encoded.generationID,
            inventorySHA256: encoded.generationID
        )
        let pointerData = try Self.canonicalData(pointer)
        try fileSystem.write(pointerData, to: stagedPointer)
        try fileSystem.synchronizeFile(at: stagedPointer)

        let activePointer = activePointerPath(sourceRoot: sourceRoot)
        do {
            try fileSystem.installFileExclusively(
                from: stagedPointer,
                to: activePointer
            )
        } catch CaptureFileSystemError.destinationExists {
            guard let winner = try recover(sourceIdentitySHA256: sourceDigest) else {
                throw CaptureRecoveryError.ioFailure
            }
            guard winner.generationID == encoded.generationID,
                  winner.inventorySHA256 == encoded.generationID
            else { throw CaptureRecoveryError.publicationConflict }
            return RecoveryPublication(
                sourceIdentity: winner.sourceIdentity,
                generationID: winner.generationID,
                inventorySHA256: winner.inventorySHA256,
                archive: winner.archive,
                recoveredArchive: winner.recoveredArchive,
                reusedExistingGeneration: true
            )
        }
        try fileSystem.synchronizeFile(at: activePointer)
        try fileSystem.synchronizeDirectory(at: sourceRoot)

        let committedPointer = try readPointer(at: activePointer)
        guard committedPointer == pointer else {
            throw CaptureRecoveryError.publicationConflict
        }
        return RecoveryPublication(
            sourceIdentity: finalPublication.sourceIdentity,
            generationID: finalPublication.generationID,
            inventorySHA256: finalPublication.inventorySHA256,
            archive: finalPublication.archive,
            recoveredArchive: finalPublication.recoveredArchive,
            reusedExistingGeneration: reusedGeneration
        )
    }

    private func prepareDirectories(
        sourceRoot: String,
        generations: String
    ) throws {
        if try ensureDirectory(rootPath) {
            try fileSystem.synchronizeDirectory(at: "")
        }
        if try ensureDirectory(sourceRoot) {
            try fileSystem.synchronizeDirectory(at: rootPath)
        }
        if try ensureDirectory(generations) {
            try fileSystem.synchronizeDirectory(at: sourceRoot)
        }
    }

    private func ensureDirectory(_ path: String) throws -> Bool {
        if try fileSystem.fileExists(at: path) { return false }
        do {
            try fileSystem.createDirectory(at: path)
            return true
        } catch CaptureFileSystemError.destinationExists {
            guard try fileSystem.fileExists(at: path) else { throw CaptureRecoveryError.ioFailure }
            return false
        }
    }

    private func createPayloadDirectories(
        _ directories: [String],
        under stagingRoot: String
    ) throws {
        for directory in directories {
            try fileSystem.createDirectory(at: "\(stagingRoot)/\(directory)")
        }
    }

    private func synchronizeStagingDirectories(
        _ directories: [String],
        stagingRoot: String
    ) throws {
        for directory in directories.sorted(by: Self.deeperPathFirst) {
            try fileSystem.synchronizeDirectory(at: "\(stagingRoot)/\(directory)")
        }
        try fileSystem.synchronizeDirectory(at: stagingRoot)
    }

    private func verifyGeneration(
        at root: String,
        expectedGenerationID: String,
        expectedSourceIdentitySHA256: String,
        reusedExistingGeneration: Bool
    ) throws -> RecoveryPublication {
        let inventoryData = try fileSystem.read(
            at: "\(root)/inventory.json",
            maximumBytes: Self.maximumInventoryBytes
        )
        guard CanonicalJSON.sha256Hex(inventoryData) == expectedGenerationID else {
            throw CaptureRecoveryError.digestMismatch
        }
        let inventory: RecoveryGenerationInventory
        do {
            inventory = try Self.decodeExact(
                RecoveryGenerationInventory.self,
                from: inventoryData
            )
        } catch {
            throw CaptureRecoveryError.invalidManifest
        }
        try Self.validateInventory(
            inventory,
            generationID: expectedGenerationID,
            sourceIdentitySHA256: expectedSourceIdentitySHA256
        )

        let expectedPaths = (["inventory.json"] + inventory.members.map(\.path)).sorted()
        guard try fileSystem.listFilesRecursively(at: root) == expectedPaths else {
            throw CaptureRecoveryError.projectionMismatch
        }
        var aggregateBytes = inventoryData.count
        for member in inventory.members {
            guard aggregateBytes <= ArchiveVerifier.maximumAggregateMemberBytes - member.byteCount else {
                throw CaptureRecoveryError.byteLimitExceeded
            }
            aggregateBytes += member.byteCount
            let data = try fileSystem.read(
                at: "\(root)/\(member.path)",
                maximumBytes: ArchiveVerifier.maximumMemberBytes
            )
            guard data.count == member.byteCount,
                  CanonicalJSON.sha256Hex(data) == member.sha256
            else { throw CaptureRecoveryError.digestMismatch }
        }

        let manifestData = try fileSystem.read(
            at: "\(root)/archive/manifest.json",
            maximumBytes: ArchiveVerifier.maximumManifestBytes
        )
        let journalData = try fileSystem.read(
            at: "\(root)/archive/journal/global.jsonl",
            maximumBytes: CaptureRecovery.maximumJournalBytes
        )
        guard CanonicalJSON.sha256Hex(manifestData) == inventory.archive.manifestBytesSHA256,
              CanonicalJSON.sha256Hex(journalData) == inventory.acceptedPrefix.journalSHA256
        else { throw CaptureRecoveryError.digestMismatch }

        let archiveURL = try fileSystem.localURL(at: "\(root)/archive")
        let archive: VerifiedArchive
        do {
            archive = try verifier.verify(root: archiveURL)
        } catch let error as ArchiveVerificationError {
            throw CaptureRecoveryError(error)
        }
        guard archive.sourceIdentity.sessionID == inventory.source.sessionID,
              archive.sourceIdentity.manifestSHA256 == inventory.archive.manifestSHA256,
              archive.manifest.sha256 == inventory.archive.manifestBytesSHA256,
              archive.manifest.finalizationState.rawValue == inventory.archive.finalizationState,
              archive.manifest.lastDurableJournalSequence
                == inventory.acceptedPrefix.lastDurableJournalSequence,
              archive.manifest.journalRecordCount
                == inventory.acceptedPrefix.journalRecordCount,
              archive.manifest.acceptedFrameCount == inventory.acceptedPrefix.acceptedFrameCount,
              archive.manifest.eventCount == inventory.acceptedPrefix.eventCount
        else { throw CaptureRecoveryError.projectionMismatch }

        let archiveMembers = Dictionary(uniqueKeysWithValues: archive.members.map {
            ("archive/\($0.relativePath)", $0)
        })
        for member in inventory.members where member.path.hasPrefix("archive/") {
            if member.path == "archive/manifest.json" || member.path == "archive/journal/global.jsonl" {
                continue
            }
            guard let descriptor = archiveMembers[member.path],
                  descriptor.byteLength == member.byteCount,
                  descriptor.sha256 == member.sha256,
                  descriptor.role == member.role
            else { throw CaptureRecoveryError.projectionMismatch }
        }
        let inventoriedArchiveMemberCount = inventory.members.filter {
            $0.path.hasPrefix("archive/")
                && $0.path != "archive/manifest.json"
                && $0.path != "archive/journal/global.jsonl"
        }.count
        guard archiveMembers.count == inventoriedArchiveMemberCount else {
            throw CaptureRecoveryError.projectionMismatch
        }

        try verifyQuarantine(inventory.quarantine, at: root)
        let status = try recoveredArchive(
            inventory: inventory,
            archive: archive,
            archivePath: "\(root)/archive"
        )
        return RecoveryPublication(
            sourceIdentity: VerifiedArchiveSourceIdentity(
                sessionID: inventory.source.sessionID,
                manifestSHA256: inventory.source.manifestSHA256,
                sha256: inventory.source.identitySHA256
            ),
            generationID: expectedGenerationID,
            inventorySHA256: expectedGenerationID,
            archive: archive,
            recoveredArchive: status,
            reusedExistingGeneration: reusedExistingGeneration
        )
    }

    private func verifyQuarantine(
        _ quarantine: RecoveryQuarantineBinding?,
        at root: String
    ) throws {
        guard let quarantine else { return }
        let metadataData = try fileSystem.read(
            at: "\(root)/quarantine/metadata.json",
            maximumBytes: Self.maximumPointerBytes
        )
        let metadata: RecoveryQuarantineMetadata
        do {
            metadata = try Self.decodeExact(RecoveryQuarantineMetadata.self, from: metadataData)
        } catch {
            throw CaptureRecoveryError.invalidManifest
        }
        guard CanonicalJSON.sha256Hex(metadataData) == quarantine.metadataSHA256,
              metadataData.count == quarantine.metadataByteCount,
              metadata.acceptedInventoryMember == false,
              metadata.firstInvalidJournalSequence == quarantine.firstInvalidJournalSequence,
              metadata.suffixByteLength == quarantine.suffixByteCount,
              metadata.suffixSHA256 == quarantine.suffixSHA256
        else { throw CaptureRecoveryError.projectionMismatch }
    }

    private func recoveredArchive(
        inventory: RecoveryGenerationInventory,
        archive: VerifiedArchive,
        archivePath: String
    ) throws -> RecoveredArchive {
        let finalization = try CaptureFinalization(
            sessionID: archive.sourceIdentity.sessionID,
            archivePath: archivePath,
            state: archive.manifest.finalizationState,
            manifestSHA256: archive.sourceIdentity.manifestSHA256,
            lastDurableJournalSequence: archive.manifest.lastDurableJournalSequence,
            acceptedFrameCount: UInt64(archive.manifest.acceptedFrameCount),
            eventCount: UInt64(archive.manifest.eventCount)
        )
        return try RecoveredArchive(
            finalization: finalization,
            acceptedJournalRecordCount: UInt64(archive.manifest.journalRecordCount),
            firstInvalidJournalSequence: inventory.quarantine?.firstInvalidJournalSequence,
            quarantineSHA256: inventory.quarantine?.suffixSHA256
        )
    }

    private func readPointer(at path: String) throws -> RecoveryActivePointer {
        let data = try fileSystem.read(at: path, maximumBytes: Self.maximumPointerBytes)
        let pointer: RecoveryActivePointer
        do {
            pointer = try Self.decodeExact(RecoveryActivePointer.self, from: data)
        } catch {
            throw CaptureRecoveryError.invalidManifest
        }
        guard pointer.formatVersion == Self.formatVersion,
              Self.validDigest(pointer.sourceIdentitySHA256),
              Self.validDigest(pointer.generationID),
              Self.validDigest(pointer.inventorySHA256)
        else { throw CaptureRecoveryError.invalidManifest }
        return pointer
    }

    private func removeOwnedItemIfPresent(at path: String) throws {
        if try fileSystem.fileExists(at: path) {
            try fileSystem.removeItem(at: path)
        }
    }

    private func sourceRoot(for sourceIdentitySHA256: String) -> String {
        "\(rootPath)/\(sourceIdentitySHA256)"
    }

    private func generationsPath(sourceRoot: String) -> String {
        "\(sourceRoot)/generations"
    }

    private func generationRoot(sourceRoot: String, generationID: String) -> String {
        "\(generationsPath(sourceRoot: sourceRoot))/\(generationID)"
    }

    private func activePointerPath(sourceRoot: String) -> String {
        "\(sourceRoot)/active-generation.json"
    }
}

private extension RecoveryPublisher {
    struct EncodedCandidate {
        let members: [RecoveryPublicationMember]
        let directories: [String]
        let inventoryData: Data
        let generationID: String
    }

    static func encode(_ candidate: RecoveryGenerationCandidate) throws -> EncodedCandidate {
        guard validDigest(candidate.sourceIdentity.sha256),
              validDigest(candidate.sourceIdentity.manifestSHA256),
              validDigest(candidate.manifestSHA256),
              CanonicalJSON.sha256Hex(candidate.journalData)
                == candidate.acceptedPrefixJournalSHA256,
              candidate.acceptedJournalRecordCount <= UInt64(ArchiveVerifier.maximumJournalRecords),
              candidate.members.count <= ArchiveVerifier.maximumInventoryMembers
        else { throw CaptureRecoveryError.invalidManifest }

        var members = [RecoveryPublicationMember(
            path: "archive/manifest.json",
            byteCount: candidate.manifestData.count,
            sha256: CanonicalJSON.sha256Hex(candidate.manifestData),
            role: "archive_manifest",
            data: candidate.manifestData
        ), RecoveryPublicationMember(
            path: "archive/journal/global.jsonl",
            byteCount: candidate.journalData.count,
            sha256: candidate.acceptedPrefixJournalSHA256,
            role: "archive_journal",
            data: candidate.journalData
        )]
        for candidateMember in candidate.members {
            let descriptor = candidateMember.descriptor
            guard descriptor.byteLength == candidateMember.data.count,
                  descriptor.sha256 == CanonicalJSON.sha256Hex(candidateMember.data)
            else { throw CaptureRecoveryError.digestMismatch }
            members.append(RecoveryPublicationMember(
                path: "archive/\(descriptor.relativePath)",
                byteCount: descriptor.byteLength,
                sha256: descriptor.sha256,
                role: descriptor.role,
                data: candidateMember.data
            ))
        }

        let quarantine: RecoveryQuarantineBinding?
        if let suffix = candidate.invalidSuffix {
            guard suffix.bytes.isEmpty == false,
                  suffix.sha256 == CanonicalJSON.sha256Hex(suffix.bytes),
                  suffix.firstInvalidJournalSequence == candidate.acceptedJournalRecordCount,
                  try CanonicalJSON.canonicalize(jsonData: suffix.metadataData)
                    == suffix.metadataData
            else { throw CaptureRecoveryError.invalidManifest }
            let metadata: RecoveryQuarantineMetadata
            do {
                metadata = try decodeExact(
                    RecoveryQuarantineMetadata.self,
                    from: suffix.metadataData
                )
            } catch {
                throw CaptureRecoveryError.invalidManifest
            }
            guard metadata.acceptedInventoryMember == false,
                  metadata.firstInvalidJournalSequence == suffix.firstInvalidJournalSequence,
                  metadata.suffixByteLength == suffix.bytes.count,
                  metadata.suffixSHA256 == suffix.sha256
            else { throw CaptureRecoveryError.projectionMismatch }
            members.append(RecoveryPublicationMember(
                path: "quarantine/invalid-suffix.bin",
                byteCount: suffix.bytes.count,
                sha256: suffix.sha256,
                role: "invalid_journal_suffix",
                data: suffix.bytes
            ))
            members.append(RecoveryPublicationMember(
                path: "quarantine/metadata.json",
                byteCount: suffix.metadataData.count,
                sha256: CanonicalJSON.sha256Hex(suffix.metadataData),
                role: "quarantine_metadata",
                data: suffix.metadataData
            ))
            quarantine = RecoveryQuarantineBinding(
                firstInvalidJournalSequence: suffix.firstInvalidJournalSequence,
                suffixByteCount: suffix.bytes.count,
                suffixSHA256: suffix.sha256,
                metadataByteCount: suffix.metadataData.count,
                metadataSHA256: CanonicalJSON.sha256Hex(suffix.metadataData)
            )
        } else {
            quarantine = nil
        }

        members.sort { $0.path < $1.path }
        guard Set(members.map(\.path)).count == members.count,
              members.allSatisfy({ validPublicationPath($0.path) })
        else { throw CaptureRecoveryError.invalidPath }

        let bindings = members.map {
            RecoveryInventoryMember(
                path: $0.path,
                byteCount: $0.byteCount,
                sha256: $0.sha256,
                role: $0.role
            )
        }
        let inventory = RecoveryGenerationInventory(
            formatVersion: formatVersion,
            source: RecoverySourceBinding(
                sessionID: candidate.sourceIdentity.sessionID,
                manifestSHA256: candidate.sourceIdentity.manifestSHA256,
                identitySHA256: candidate.sourceIdentity.sha256
            ),
            archive: RecoveryArchiveBinding(
                finalizationState: candidate.finalizationState.rawValue,
                manifestSHA256: candidate.manifestSHA256,
                manifestBytesSHA256: CanonicalJSON.sha256Hex(candidate.manifestData)
            ),
            acceptedPrefix: RecoveryAcceptedPrefixBinding(
                journalSHA256: candidate.acceptedPrefixJournalSHA256,
                lastDurableJournalSequence: candidate.lastDurableJournalSequence,
                journalRecordCount: Int(candidate.acceptedJournalRecordCount),
                acceptedFrameCount: Int(candidate.acceptedFrameCount),
                eventCount: Int(candidate.eventCount)
            ),
            quarantine: quarantine,
            members: bindings
        )
        let inventoryData = try canonicalData(inventory)
        guard inventoryData.count <= maximumInventoryBytes else {
            throw CaptureRecoveryError.byteLimitExceeded
        }
        let directories = Set(members.flatMap { parentDirectories(of: $0.path) })
            .sorted(by: shallowerPathFirst)
        return EncodedCandidate(
            members: members,
            directories: directories,
            inventoryData: inventoryData,
            generationID: CanonicalJSON.sha256Hex(inventoryData)
        )
    }

    static func validateInventory(
        _ inventory: RecoveryGenerationInventory,
        generationID: String,
        sourceIdentitySHA256: String
    ) throws {
        guard inventory.formatVersion == formatVersion,
              inventory.source.identitySHA256 == sourceIdentitySHA256,
              validDigest(inventory.source.identitySHA256),
              validDigest(inventory.source.manifestSHA256),
              validDigest(inventory.archive.manifestSHA256),
              validDigest(inventory.archive.manifestBytesSHA256),
              validDigest(inventory.acceptedPrefix.journalSHA256),
              inventory.acceptedPrefix.journalRecordCount > 0,
              inventory.acceptedPrefix.lastDurableJournalSequence
                == UInt64(inventory.acceptedPrefix.journalRecordCount - 1),
              inventory.members.count <= ArchiveVerifier.maximumInventoryMembers + 4,
              inventory.members == inventory.members.sorted(by: { $0.path < $1.path }),
              Set(inventory.members.map(\.path)).count == inventory.members.count,
              inventory.members.allSatisfy({ member in
                  member.byteCount > 0
                      && member.byteCount <= ArchiveVerifier.maximumMemberBytes
                      && validDigest(member.sha256)
                      && member.role.isEmpty == false
                      && validPublicationPath(member.path)
              }),
              inventory.members.contains(where: { $0.path == "archive/manifest.json" }),
              inventory.members.contains(where: { $0.path == "archive/journal/global.jsonl" })
        else { throw CaptureRecoveryError.invalidManifest }

        let membersByPath = Dictionary(uniqueKeysWithValues: inventory.members.map {
            ($0.path, $0)
        })
        guard membersByPath["archive/manifest.json"]?.role == "archive_manifest",
              membersByPath["archive/journal/global.jsonl"]?.role == "archive_journal"
        else { throw CaptureRecoveryError.projectionMismatch }

        let sourceDigest = try canonicalDigest([
            "manifest_sha256": inventory.source.manifestSHA256,
            "session_id": inventory.source.sessionID,
        ])
        guard sourceDigest == sourceIdentitySHA256 else {
            throw CaptureRecoveryError.digestMismatch
        }
        if let quarantine = inventory.quarantine {
            guard quarantine.firstInvalidJournalSequence
                    == UInt64(inventory.acceptedPrefix.journalRecordCount),
                  quarantine.suffixByteCount > 0,
                  validDigest(quarantine.suffixSHA256),
                  quarantine.metadataByteCount > 0,
                  validDigest(quarantine.metadataSHA256),
                  inventory.members.contains(where: {
                      $0.path == "quarantine/invalid-suffix.bin"
                          && $0.byteCount == quarantine.suffixByteCount
                          && $0.sha256 == quarantine.suffixSHA256
                          && $0.role == "invalid_journal_suffix"
                  }),
                  inventory.members.contains(where: {
                      $0.path == "quarantine/metadata.json"
                          && $0.byteCount == quarantine.metadataByteCount
                          && $0.sha256 == quarantine.metadataSHA256
                          && $0.role == "quarantine_metadata"
                  })
            else { throw CaptureRecoveryError.projectionMismatch }
        } else if inventory.members.contains(where: { $0.path.hasPrefix("quarantine/") }) {
            throw CaptureRecoveryError.projectionMismatch
        }
        _ = generationID
    }

    static func canonicalData<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do {
            return try CanonicalJSON.canonicalize(jsonData: encoder.encode(value))
        } catch {
            throw CaptureRecoveryError.invalidJSON
        }
    }

    static func decodeExact<Value: Codable & Equatable>(
        _ type: Value.Type,
        from data: Data
    ) throws -> Value {
        let canonical = try CanonicalJSON.canonicalize(jsonData: data)
        guard canonical == data else { throw CaptureRecoveryError.invalidJSON }
        let value = try JSONDecoder().decode(type, from: canonical)
        guard try canonicalData(value) == canonical else {
            throw CaptureRecoveryError.invalidJSON
        }
        return value
    }

    static func canonicalDigest(_ value: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return CanonicalJSON.sha256Hex(try CanonicalJSON.canonicalize(jsonData: data))
    }

    static func parentDirectories(of path: String) -> [String] {
        let components = path.split(separator: "/").dropLast()
        guard components.isEmpty == false else { return [] }
        return components.indices.map { index in
            components[components.startIndex...index].joined(separator: "/")
        }
    }

    static func shallowerPathFirst(_ lhs: String, _ rhs: String) -> Bool {
        let lhsDepth = lhs.filter { $0 == "/" }.count
        let rhsDepth = rhs.filter { $0 == "/" }.count
        return lhsDepth == rhsDepth ? lhs < rhs : lhsDepth < rhsDepth
    }

    static func deeperPathFirst(_ lhs: String, _ rhs: String) -> Bool {
        shallowerPathFirst(rhs, lhs)
    }

    static func validComponent(_ value: String) -> Bool {
        value.isEmpty == false && value != "." && value != ".." && value.contains("/") == false
    }

    static func validToken(_ value: String) -> Bool {
        value.range(of: "^[a-z0-9][a-z0-9-]{0,63}$", options: .regularExpression) != nil
    }

    static func validDigest(_ value: String) -> Bool {
        value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
    }

    static func validPublicationPath(_ path: String) -> Bool {
        do {
            try ArchivePath.validate(path)
            return path.hasPrefix("archive/") || path.hasPrefix("quarantine/")
        } catch {
            return false
        }
    }
}

private struct RecoveryPublicationMember {
    let path: String
    let byteCount: Int
    let sha256: String
    let role: String
    let data: Data
}

private struct RecoveryGenerationInventory: Codable, Equatable {
    let formatVersion: String
    let source: RecoverySourceBinding
    let archive: RecoveryArchiveBinding
    let acceptedPrefix: RecoveryAcceptedPrefixBinding
    let quarantine: RecoveryQuarantineBinding?
    let members: [RecoveryInventoryMember]

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case source
        case archive
        case acceptedPrefix = "accepted_prefix"
        case quarantine
        case members
    }
}

private struct RecoverySourceBinding: Codable, Equatable {
    let sessionID: String
    let manifestSHA256: String
    let identitySHA256: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case manifestSHA256 = "manifest_sha256"
        case identitySHA256 = "identity_sha256"
    }
}

private struct RecoveryArchiveBinding: Codable, Equatable {
    let finalizationState: String
    let manifestSHA256: String
    let manifestBytesSHA256: String

    enum CodingKeys: String, CodingKey {
        case finalizationState = "finalization_state"
        case manifestSHA256 = "manifest_sha256"
        case manifestBytesSHA256 = "manifest_bytes_sha256"
    }
}

private struct RecoveryAcceptedPrefixBinding: Codable, Equatable {
    let journalSHA256: String
    let lastDurableJournalSequence: UInt64
    let journalRecordCount: Int
    let acceptedFrameCount: Int
    let eventCount: Int

    enum CodingKeys: String, CodingKey {
        case journalSHA256 = "journal_sha256"
        case lastDurableJournalSequence = "last_durable_journal_sequence"
        case journalRecordCount = "journal_record_count"
        case acceptedFrameCount = "accepted_frame_count"
        case eventCount = "event_count"
    }
}

private struct RecoveryQuarantineBinding: Codable, Equatable {
    let firstInvalidJournalSequence: UInt64
    let suffixByteCount: Int
    let suffixSHA256: String
    let metadataByteCount: Int
    let metadataSHA256: String

    enum CodingKeys: String, CodingKey {
        case firstInvalidJournalSequence = "first_invalid_journal_sequence"
        case suffixByteCount = "suffix_byte_count"
        case suffixSHA256 = "suffix_sha256"
        case metadataByteCount = "metadata_byte_count"
        case metadataSHA256 = "metadata_sha256"
    }
}

private struct RecoveryInventoryMember: Codable, Equatable {
    let path: String
    let byteCount: Int
    let sha256: String
    let role: String

    enum CodingKeys: String, CodingKey {
        case path
        case byteCount = "byte_count"
        case sha256
        case role
    }
}

private struct RecoveryActivePointer: Codable, Equatable {
    let formatVersion: String
    let sourceIdentitySHA256: String
    let generationID: String
    let inventorySHA256: String

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case sourceIdentitySHA256 = "source_identity_sha256"
        case generationID = "generation_id"
        case inventorySHA256 = "inventory_sha256"
    }
}

private struct RecoveryQuarantineMetadata: Codable, Equatable {
    let acceptedInventoryMember: Bool
    let firstInvalidJournalSequence: UInt64
    let suffixByteLength: Int
    let suffixSHA256: String

    enum CodingKeys: String, CodingKey {
        case acceptedInventoryMember = "accepted_inventory_member"
        case firstInvalidJournalSequence = "first_invalid_journal_sequence"
        case suffixByteLength = "suffix_byte_length"
        case suffixSHA256 = "suffix_sha256"
    }
}
