import Foundation
import ReRoomContracts
import Testing

@testable import ReRoomCaptureCore

@Suite("RecoveryPublicationTests")
struct RecoveryPublicationTests {
    @Test("every publication durability edge exposes no pointer or one complete generation")
    func durabilityDeathMatrix() throws {
        let candidate = try RecoveryPublicationFixture.candidateWithInvalidSuffix()
        let probeController = PublicationFaultController()
        let probeFileSystem = PublicationDurableMemoryFileSystem(controller: probeController)
        let probePublisher = RecoveryPublisher(
            fileSystem: probeFileSystem,
            verifier: try RecoveryPublicationFixture.verifier(),
            stagingToken: { "probe" }
        )

        let probe = try probePublisher.publish(candidate)
        let mutationIndices = probeController.beforeOperations.indices.filter { index in
            switch probeController.beforeOperations[index].kind {
            case .createDirectory, .write, .synchronizeFile, .synchronizeDirectory,
                 .renameExclusive, .installExclusive:
                true
            default:
                false
            }
        }
        let visibilityIndex = try #require(
            probeController.beforeOperations.indices.last { index in
                let operation = probeController.beforeOperations[index]
                return operation.kind == .synchronizeDirectory
                    && operation.path.hasSuffix(candidate.sourceIdentity.sha256)
            }
        )
        #expect(try ReplayCore.replay(probe.archive).timeline.count == 6)
        #expect(mutationIndices.isEmpty == false)

        for operationIndex in mutationIndices {
            for phase in PublicationFaultPhase.allCases {
                let controller = PublicationFaultController(
                    target: PublicationFaultTarget(operationIndex: operationIndex, phase: phase)
                )
                let fileSystem = PublicationDurableMemoryFileSystem(controller: controller)
                let publisher = RecoveryPublisher(
                    fileSystem: fileSystem,
                    verifier: try RecoveryPublicationFixture.verifier(),
                    stagingToken: { "fault" }
                )

                #expect(throws: PublicationInjectedFault.self) {
                    _ = try publisher.publish(candidate)
                }
                #expect(controller.didFire)

                let restartedFileSystem = fileSystem.crashedCopy()
                let restarted = RecoveryPublisher(
                    fileSystem: restartedFileSystem,
                    verifier: try RecoveryPublicationFixture.verifier(),
                    stagingToken: { "restart" }
                )
                let recovered = try restarted.recover(
                    sourceIdentitySHA256: candidate.sourceIdentity.sha256
                )
                let expectedVisible = phase == .after && operationIndex == visibilityIndex

                if expectedVisible {
                    let winner = try #require(recovered)
                    #expect(winner.generationID == probe.generationID)
                    #expect(winner.inventorySHA256 == probe.inventorySHA256)
                    #expect(winner.recoveredArchive.quarantineSHA256 == candidate.invalidSuffix?.sha256)
                    #expect(try ReplayCore.replay(winner.archive).timeline.count == 6)
                } else {
                    #expect(recovered == nil)
                }
            }
        }
    }

    @Test("archive and quarantine bytes form one closed content-addressed generation")
    func closedArchiveAndQuarantineGeneration() throws {
        let candidate = try RecoveryPublicationFixture.candidateWithInvalidSuffix()
        let fileSystem = PublicationDurableMemoryFileSystem()
        let publisher = RecoveryPublisher(
            fileSystem: fileSystem,
            verifier: try RecoveryPublicationFixture.verifier(),
            stagingToken: { "closed" }
        )

        let result = try publisher.publish(candidate)
        let sourceRoot = "recovery-publications/\(candidate.sourceIdentity.sha256)"
        let generationRoot = "\(sourceRoot)/generations/\(result.generationID)"
        let files = fileSystem.snapshotFiles()
        let inventoryData = try #require(files["\(generationRoot)/inventory.json"])
        let inventory = try #require(
            JSONSerialization.jsonObject(with: inventoryData) as? [String: Any]
        )
        let listed = try #require(inventory["members"] as? [[String: Any]])
            .compactMap { $0["path"] as? String }
        let physical = files.keys
            .filter { $0.hasPrefix(generationRoot + "/") }
            .map { String($0.dropFirst(generationRoot.count + 1)) }
            .filter { $0 != "inventory.json" }
            .sorted()

        #expect(result.generationID == CanonicalJSON.sha256Hex(inventoryData))
        #expect(result.inventorySHA256 == result.generationID)
        #expect(listed == physical)
        #expect(listed.contains("archive/manifest.json"))
        #expect(listed.contains("archive/journal/global.jsonl"))
        #expect(listed.contains("quarantine/invalid-suffix.bin"))
        #expect(listed.contains("quarantine/metadata.json"))
        #expect(files.keys.contains { $0.hasSuffix("active-generation.json") })
        #expect(files.keys.contains { $0.contains(".recovered-prefix.rrcap") } == false)
        #expect(files.keys.contains { $0.hasSuffix("/quarantine/invalid-suffix.bin") })

        let restarted = RecoveryPublisher(
            fileSystem: fileSystem.crashedCopy(),
            verifier: try RecoveryPublicationFixture.verifier(),
            stagingToken: { "restart" }
        )
        let recovered = try #require(
            restarted.recover(sourceIdentitySHA256: candidate.sourceIdentity.sha256)
        )
        #expect(recovered.generationID == result.generationID)
        #expect(recovered.sourceIdentity == candidate.sourceIdentity)
        #expect(recovered.recoveredArchive.firstInvalidJournalSequence == 6)
        #expect(recovered.recoveredArchive.quarantineSHA256 == candidate.invalidSuffix?.sha256)
        #expect(try ReplayCore.replay(recovered.archive).timeline.count == 6)
    }

    @Test(
        "CaptureRecovery imports finalized input and reconstructs open input through publication",
        arguments: [RecoveryPublicationInput.finalized, .openWithSuffix]
    )
    func captureRecoveryIntegration(input: RecoveryPublicationInput) throws {
        let source = try RecoveryPublicationFixture.copySource(input)
        defer { source.remove() }
        let verifier = try RecoveryPublicationFixture.verifier()
        let recovery = CaptureRecovery(verifier: verifier)
        let before = try RecoveryPublicationFixture.snapshot(source.archiveURL)
        let fileSystem = PublicationDurableMemoryFileSystem()
        let publisher = RecoveryPublisher(
            fileSystem: fileSystem,
            verifier: verifier,
            stagingToken: { "integration" }
        )

        let result = try recovery.publish(root: source.archiveURL, using: publisher)

        #expect(try RecoveryPublicationFixture.snapshot(source.archiveURL) == before)
        #expect(result.sourceIdentity.sessionID.hasPrefix("session_"))
        #expect(try ReplayCore.replay(result.archive).timeline.isEmpty == false)
        #expect(result.recoveredArchive.quarantineSHA256 == (
            input == .openWithSuffix ? CanonicalJSON.sha256Hex(source.invalidSuffix) : nil
        ))
        #expect(try publisher.recover(
            sourceIdentitySHA256: result.sourceIdentity.sha256
        )?.generationID == result.generationID)
    }
}

enum RecoveryPublicationInput: Sendable {
    case finalized
    case openWithSuffix
}

enum PublicationFaultPhase: CaseIterable, Sendable {
    case before
    case after
}

struct PublicationFaultTarget: Sendable {
    let operationIndex: Int
    let phase: PublicationFaultPhase
}

struct PublicationInjectedFault: Error, Equatable, Sendable {}

final class PublicationFaultController: @unchecked Sendable {
    private let lock = NSLock()
    private let target: PublicationFaultTarget?
    private var nextIndex = 0
    private var activeIndex = -1
    private var fired = false
    private var operations = [CaptureFileOperation]()

    init(target: PublicationFaultTarget? = nil) {
        self.target = target
    }

    var didFire: Bool { withLock { fired } }
    var beforeOperations: [CaptureFileOperation] { withLock { operations } }

    func observeBefore(_ operation: CaptureFileOperation) throws {
        let shouldThrow = withLock { () -> Bool in
            activeIndex = nextIndex
            nextIndex += 1
            operations.append(operation)
            return shouldFire(index: activeIndex, phase: .before)
        }
        if shouldThrow { throw PublicationInjectedFault() }
    }

    func observeAfter(_ operation: CaptureFileOperation) throws {
        let shouldThrow = withLock {
            shouldFire(index: activeIndex, phase: .after)
        }
        if shouldThrow { throw PublicationInjectedFault() }
    }

    private func shouldFire(index: Int, phase: PublicationFaultPhase) -> Bool {
        guard fired == false,
              let target,
              target.operationIndex == index,
              target.phase == phase
        else { return false }
        fired = true
        return true
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

final class PublicationDurableMemoryFileSystem: CaptureFileSystem, @unchecked Sendable {
    let limits = CaptureFileSystemLimits.production

    private let lock = NSLock()
    private var directories: Set<String>
    private var files: [String: Data]
    private var synchronizedFiles: [String: Data]
    private var durableDirectories: Set<String>
    private var durableFiles: [String: Data]
    private let controller: PublicationFaultController?
    private var mirrorRoots = [URL]()

    init(
        directories: Set<String> = [""],
        files: [String: Data] = [:],
        synchronizedFiles: [String: Data] = [:],
        durableDirectories: Set<String> = [""],
        durableFiles: [String: Data] = [:],
        controller: PublicationFaultController? = nil
    ) {
        self.directories = directories
        self.files = files
        self.synchronizedFiles = synchronizedFiles
        self.durableDirectories = durableDirectories
        self.durableFiles = durableFiles
        self.controller = controller
    }

    deinit {
        for root in mirrorRoots { try? FileManager.default.removeItem(at: root) }
    }

    func createDirectory(at path: String) throws {
        let operation = CaptureFileOperation(kind: .createDirectory, path: path)
        try before(operation)
        try withLock {
            guard path.isEmpty == false,
                  directories.contains(Self.parent(of: path)),
                  directories.contains(path) == false,
                  files[path] == nil
            else { throw CaptureFileSystemError.destinationExists }
            directories.insert(path)
        }
        try after(operation)
    }

    func write(_ data: Data, to path: String) throws {
        let operation = CaptureFileOperation(kind: .write, path: path, byteCount: data.count)
        try before(operation)
        try withLock {
            guard directories.contains(Self.parent(of: path)), files[path] == nil else {
                throw CaptureFileSystemError.destinationExists
            }
            files[path] = data
        }
        try after(operation)
    }

    func synchronizeFile(at path: String) throws {
        let operation = CaptureFileOperation(kind: .synchronizeFile, path: path)
        try before(operation)
        try withLock {
            guard let data = files[path] else { throw CaptureFileSystemError.missingFile }
            synchronizedFiles[path] = data
        }
        try after(operation)
    }

    func synchronizeDirectory(at path: String) throws {
        let operation = CaptureFileOperation(kind: .synchronizeDirectory, path: path)
        try before(operation)
        try withLock {
            guard directories.contains(path) else { throw CaptureFileSystemError.missingFile }
            let contains: (String) -> Bool = { candidate in
                path.isEmpty || candidate == path || candidate.hasPrefix(path + "/")
            }
            durableDirectories = durableDirectories.filter { contains($0) == false }
            durableDirectories.formUnion(directories.filter(contains))
            durableFiles = durableFiles.filter { contains($0.key) == false }
            for (file, data) in synchronizedFiles where contains(file) && files[file] == data {
                durableFiles[file] = data
            }
        }
        try after(operation)
    }

    func append(_ data: Data, to path: String) throws {
        let operation = CaptureFileOperation(kind: .append, path: path, byteCount: data.count)
        try before(operation)
        try withLock {
            guard files[path] != nil else { throw CaptureFileSystemError.missingFile }
            files[path]!.append(data)
        }
        try after(operation)
    }

    func replace(_ data: Data, at path: String) throws {
        let operation = CaptureFileOperation(kind: .replace, path: path, byteCount: data.count)
        try before(operation)
        withLock { files[path] = data }
        try after(operation)
    }

    func rename(from sourcePath: String, to destinationPath: String) throws {
        try renameImpl(
            from: sourcePath,
            to: destinationPath,
            kind: .rename,
            requiresMissingDestination: true
        )
    }

    func renameExclusively(from sourcePath: String, to destinationPath: String) throws {
        try renameImpl(
            from: sourcePath,
            to: destinationPath,
            kind: .renameExclusive,
            requiresMissingDestination: true
        )
    }

    func installFileExclusively(from sourcePath: String, to destinationPath: String) throws {
        let operation = CaptureFileOperation(
            kind: .installExclusive,
            path: sourcePath,
            destinationPath: destinationPath
        )
        try before(operation)
        try withLock {
            guard let data = files[sourcePath] else { throw CaptureFileSystemError.missingFile }
            guard files[destinationPath] == nil,
                  directories.contains(Self.parent(of: destinationPath))
            else { throw CaptureFileSystemError.destinationExists }
            files[destinationPath] = data
        }
        try after(operation)
    }

    func removeItem(at path: String) throws {
        let operation = CaptureFileOperation(kind: .removeItem, path: path)
        try before(operation)
        try withLock {
            let existed = files.removeValue(forKey: path) != nil || directories.contains(path)
            guard existed else { throw CaptureFileSystemError.missingFile }
            directories = directories.filter { $0 != path && !$0.hasPrefix(path + "/") }
            files = files.filter { $0.key != path && !$0.key.hasPrefix(path + "/") }
            synchronizedFiles = synchronizedFiles.filter {
                $0.key != path && !$0.key.hasPrefix(path + "/")
            }
        }
        try after(operation)
    }

    func read(at path: String, maximumBytes: Int?) throws -> Data {
        let limit = maximumBytes ?? limits.maximumReadBytes
        let operation = CaptureFileOperation(kind: .read, path: path, byteCount: limit)
        try before(operation)
        let data = try withLock {
            guard let data = files[path] else { throw CaptureFileSystemError.missingFile }
            guard data.count <= limit else { throw CaptureFileSystemError.byteLimitExceeded }
            return data
        }
        try after(operation)
        return data
    }

    func fileExists(at path: String) throws -> Bool {
        let operation = CaptureFileOperation(kind: .fileExists, path: path)
        try before(operation)
        let exists = withLock { directories.contains(path) || files[path] != nil }
        try after(operation)
        return exists
    }

    func listFilesRecursively(at path: String) throws -> [String] {
        let operation = CaptureFileOperation(kind: .listFiles, path: path)
        try before(operation)
        let prefix = path.isEmpty ? "" : path + "/"
        let result = try withLock { () throws -> [String] in
            guard directories.contains(path) else { throw CaptureFileSystemError.missingFile }
            return files.keys.compactMap { file in
                guard prefix.isEmpty || file.hasPrefix(prefix) else { return nil }
                return prefix.isEmpty ? file : String(file.dropFirst(prefix.count))
            }.sorted()
        }
        try after(operation)
        return result
    }

    func localURL(at path: String) throws -> URL {
        let snapshot = try withLock { () throws -> (Set<String>, [String: Data]) in
            guard directories.contains(path) else { throw CaptureFileSystemError.missingFile }
            let prefix = path.isEmpty ? "" : path + "/"
            let relativeDirectories = Set(directories.compactMap { directory -> String? in
                guard directory == path || prefix.isEmpty || directory.hasPrefix(prefix) else {
                    return nil
                }
                return directory == path ? "" : String(directory.dropFirst(prefix.count))
            })
            var relativeFiles = [String: Data]()
            for (file, data) in files where prefix.isEmpty || file.hasPrefix(prefix) {
                let relative = prefix.isEmpty ? file : String(file.dropFirst(prefix.count))
                relativeFiles[relative] = data
            }
            return (relativeDirectories, relativeFiles)
        }
        let mirror = FileManager.default.temporaryDirectory
            .appendingPathComponent("reroom-publication-memory-\(UUID().uuidString.lowercased())")
        try FileManager.default.createDirectory(at: mirror, withIntermediateDirectories: false)
        for directory in snapshot.0.sorted() where directory.isEmpty == false {
            try FileManager.default.createDirectory(
                at: mirror.appendingPathComponent(directory),
                withIntermediateDirectories: true
            )
        }
        for (file, data) in snapshot.1 {
            let url = mirror.appendingPathComponent(file)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: Data.WritingOptions.withoutOverwriting)
        }
        withLock { mirrorRoots.append(mirror) }
        return mirror
    }

    func crashedCopy() -> PublicationDurableMemoryFileSystem {
        withLock {
            PublicationDurableMemoryFileSystem(
                directories: durableDirectories,
                files: durableFiles,
                synchronizedFiles: durableFiles,
                durableDirectories: durableDirectories,
                durableFiles: durableFiles
            )
        }
    }

    func snapshotFiles() -> [String: Data] { withLock { files } }

    private func renameImpl(
        from sourcePath: String,
        to destinationPath: String,
        kind: CaptureFileOperationKind,
        requiresMissingDestination: Bool
    ) throws {
        let operation = CaptureFileOperation(
            kind: kind,
            path: sourcePath,
            destinationPath: destinationPath
        )
        try before(operation)
        try withLock {
            guard directories.contains(sourcePath) else { throw CaptureFileSystemError.missingFile }
            if requiresMissingDestination,
               directories.contains(destinationPath) || files[destinationPath] != nil {
                throw CaptureFileSystemError.destinationExists
            }
            guard directories.contains(Self.parent(of: destinationPath)) else {
                throw CaptureFileSystemError.missingFile
            }
            func remap(_ value: String) -> String {
                value == sourcePath
                    ? destinationPath
                    : destinationPath + value.dropFirst(sourcePath.count)
            }
            let movedDirectories = directories.filter {
                $0 == sourcePath || $0.hasPrefix(sourcePath + "/")
            }
            directories.subtract(movedDirectories)
            directories.formUnion(movedDirectories.map(remap))
            let movedFiles = files.filter { $0.key.hasPrefix(sourcePath + "/") }
            files = files.filter { !$0.key.hasPrefix(sourcePath + "/") }
            for (path, data) in movedFiles { files[remap(path)] = data }
            let movedSynchronized = synchronizedFiles.filter {
                $0.key.hasPrefix(sourcePath + "/")
            }
            synchronizedFiles = synchronizedFiles.filter {
                !$0.key.hasPrefix(sourcePath + "/")
            }
            for (path, data) in movedSynchronized {
                synchronizedFiles[remap(path)] = data
            }
        }
        try after(operation)
    }

    private func before(_ operation: CaptureFileOperation) throws {
        try controller?.observeBefore(operation)
    }

    private func after(_ operation: CaptureFileOperation) throws {
        try controller?.observeAfter(operation)
    }

    private static func parent(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[..<slash])
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

enum RecoveryPublicationFixture {
    static func candidateWithInvalidSuffix() throws -> RecoveryGenerationCandidate {
        let root = fixtureRoot.appendingPathComponent("recovered-prefix.rrcap")
        let verifier = try verifier()
        let archive = try verifier.verify(root: root)
        let journal = try Data(contentsOf: root.appendingPathComponent("journal/global.jsonl"))
        let suffix = Data(#"{"journal_sequence":6"#.utf8)
        let suffixSHA256 = CanonicalJSON.sha256Hex(suffix)
        let metadata = try canonical([
            "accepted_inventory_member": false,
            "first_invalid_journal_sequence": 6,
            "suffix_byte_length": suffix.count,
            "suffix_sha256": suffixSHA256,
        ])
        return RecoveryGenerationCandidate(
            sourceIdentity: archive.sourceIdentity,
            manifestData: try Data(contentsOf: root.appendingPathComponent("manifest.json")),
            members: try archive.members.map { descriptor in
                RecoveryCandidateMember(
                    descriptor: descriptor,
                    data: try Data(contentsOf: root.appendingPathComponent(descriptor.relativePath))
                )
            },
            journalData: journal,
            invalidSuffix: RecoveryInvalidSuffix(
                firstInvalidJournalSequence: 6,
                bytes: suffix,
                sha256: suffixSHA256,
                metadataData: metadata
            ),
            acceptedPrefixJournalSHA256: CanonicalJSON.sha256Hex(journal),
            finalizationState: archive.manifest.finalizationState,
            manifestSHA256: archive.sourceIdentity.manifestSHA256,
            lastDurableJournalSequence: archive.manifest.lastDurableJournalSequence,
            acceptedFrameCount: UInt64(archive.manifest.acceptedFrameCount),
            eventCount: UInt64(archive.manifest.eventCount)
        )
    }

    static func copySource(_ input: RecoveryPublicationInput) throws -> PublicationSourceFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("reroom-publication-source-\(UUID().uuidString.lowercased())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let archiveName = input == .finalized
            ? "finalized-one-frame.rrcap"
            : "recovered-prefix.rrcap"
        let archive = root.appendingPathComponent(archiveName)
        try FileManager.default.copyItem(
            at: fixtureRoot.appendingPathComponent(archiveName),
            to: archive
        )
        var suffix = Data()
        if input == .openWithSuffix {
            let manifestURL = archive.appendingPathComponent("manifest.json")
            var manifest = try JSONSerialization.jsonObject(
                with: Data(contentsOf: manifestURL)
            ) as! [String: Any]
            var finalization = manifest["finalization"] as! [String: Any]
            finalization["state"] = "open"
            finalization.removeValue(forKey: "manifest_sha256")
            manifest["finalization"] = finalization
            let digest = CanonicalJSON.sha256Hex(try canonical(manifest))
            finalization["manifest_sha256"] = digest
            manifest["finalization"] = finalization
            try canonical(manifest).write(to: manifestURL)
            suffix = Data(#"{"journal_sequence":6"#.utf8)
            let journalURL = archive.appendingPathComponent("journal/global.jsonl")
            let handle = try FileHandle(forWritingTo: journalURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: suffix)
        }
        return PublicationSourceFixture(rootURL: root, archiveURL: archive, invalidSuffix: suffix)
    }

    static func verifier() throws -> ArchiveVerifier {
        let registrations: [(ContractSchemaIdentifier, String, String)] = [
            (.framePacket, "frame-packet.schema.json", "d50b19bfb29c6c62c494e3a47deb3c51a933609698f4ff2f9cbfba6ec4252b43"),
            (.rrcapManifest, "rrcap-manifest.schema.json", "c97349820ed66fb1a1fdf60ea9afee312f532811602851d01d1e233641730b87"),
            (.sceneState, "scene-state.schema.json", "9c77d27762e20ff5fad24c438e8817a03c770b55be3fc82ea72097c4c273e440"),
            (.editArtifacts, "edit-artifacts.schema.json", "58dbfc8f152881cbdc31be22f6ab7631ac474bb78537ac2a9254f5ef16bd598f"),
            (.transaction, "transaction.schema.json", "2a4f6728978db0879b5dfb10f052f6d5280e5cf83ad5600f0cf959626c2399a2"),
        ]
        let validator = try ContractValidator(registrations: registrations.map { identifier, name, digest in
            ContractSchemaRegistration(
                identifier: identifier,
                version: "1.0.0",
                sha256: digest,
                schemaData: try Data(contentsOf: repositoryRoot.appendingPathComponent("docs/contracts/\(name)"))
            )
        })
        return ArchiveVerifier(validator: validator)
    }

    static func snapshot(_ root: URL) throws -> [String: String] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return [:] }
        var result = [String: String]()
        for case let url as URL in enumerator {
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                continue
            }
            let relative = String(url.path.dropFirst(root.path.count + 1))
            result[relative] = CanonicalJSON.sha256Hex(try Data(contentsOf: url))
        }
        return result
    }

    private static var fixtureRoot: URL {
        repositoryRoot.appendingPathComponent("fixtures/capture/1.0.0/rev-001/archives")
    }

    private static var repositoryRoot: URL {
        var cursor = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<12 {
            if FileManager.default.fileExists(
                atPath: cursor.appendingPathComponent("docs/contracts/frame-packet.schema.json").path
            ) { return cursor }
            cursor.deleteLastPathComponent()
        }
        preconditionFailure("repository root unavailable")
    }

    private static func canonical(_ value: Any) throws -> Data {
        let encoded = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return try CanonicalJSON.canonicalize(jsonData: encoded)
    }
}

struct PublicationSourceFixture {
    let rootURL: URL
    let archiveURL: URL
    let invalidSuffix: Data

    func remove() { try? FileManager.default.removeItem(at: rootURL) }
}
