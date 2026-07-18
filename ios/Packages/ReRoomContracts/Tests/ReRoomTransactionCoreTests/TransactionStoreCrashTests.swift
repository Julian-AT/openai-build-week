import Foundation
import ReRoomCaptureCore
import ReRoomContracts
@testable import ReRoomTransactionCore
import Testing

@Suite("TST-PERSIST-001 transaction generation store")
struct TransactionStoreCrashTests {
    @Test(
        "every generation write sync and pointer edge recovers the exact old or new generation",
        arguments: TransactionStoreFaultCase.cases
    )
    func faultMatrix(testCase: TransactionStoreFaultCase) throws {
        let controller = TransactionStoreFaultController()
        let fileSystem = DurableMemoryCaptureFileSystem(
            observe: controller.observeBefore,
            afterOperation: controller.observeAfter
        )
        let store = try TransactionPersistenceFixtures.store(fileSystem: fileSystem)
        let old = try store.activate(TransactionPersistenceFixtures.baseline)
        controller.arm(testCase.target)

        #expect(throws: InjectedTransactionStoreFault.self) {
            _ = try store.activate(TransactionPersistenceFixtures.placed)
        }
        #expect(controller.didFire)

        let restarted = try TransactionPersistenceFixtures.store(fileSystem: fileSystem.crashedCopy())
        let recovered = try #require(restarted.recover().activeSnapshot)
        let expected = testCase.expectsNewGeneration ? TransactionPersistenceFixtures.placed : TransactionPersistenceFixtures.baseline
        #expect(recovered.scene == expected.scene)
        #expect(recovered.transactions == expected.transactions)
        #expect(recovered.generationSHA256 == (testCase.expectsNewGeneration
            ? try TransactionStore.generationSHA256(for: TransactionPersistenceFixtures.placed)
            : old.generationSHA256))
        #expect(recovered.scene.sceneRevision == (testCase.expectsNewGeneration ? 9 : 8))
    }

    @Test("Foundation and in-memory filesystems publish byte-identical generations and operation order")
    func foundationParity() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("reroom-transaction-store-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let foundationRecorder = TransactionStoreFaultController()
        let foundationFS = try FoundationCaptureFileSystem(
            root: root,
            observe: foundationRecorder.observeBefore,
            afterOperation: foundationRecorder.observeAfter
        )
        let memoryRecorder = TransactionStoreFaultController()
        let memoryFS = DurableMemoryCaptureFileSystem(
            observe: memoryRecorder.observeBefore,
            afterOperation: memoryRecorder.observeAfter
        )
        let foundationStore = try TransactionPersistenceFixtures.store(fileSystem: foundationFS)
        let memoryStore = try TransactionPersistenceFixtures.store(fileSystem: memoryFS)

        _ = try foundationStore.activate(TransactionPersistenceFixtures.baseline)
        let foundationResult = try foundationStore.activate(TransactionPersistenceFixtures.placed)
        _ = try memoryStore.activate(TransactionPersistenceFixtures.baseline)
        let memoryResult = try memoryStore.activate(TransactionPersistenceFixtures.placed)

        #expect(foundationResult == memoryResult)
        #expect(try foundationStore.recover() == memoryStore.recover())
        #expect(foundationRecorder.observations == memoryRecorder.observations)
        #expect(try recursiveRelativeFiles(root: root) == memoryFS.snapshotFiles())
    }

    @Test("recovery follows only the active pointer and rejects corrupt active members with sanitized diagnostics")
    func recoveryIsPointerOnlyAndFailClosed() throws {
        let fileSystem = DurableMemoryCaptureFileSystem()
        let store = try TransactionPersistenceFixtures.store(fileSystem: fileSystem)
        let baseline = try store.activate(TransactionPersistenceFixtures.baseline)

        fileSystem.installDurable(
            Data("newest-but-unactivated".utf8),
            at: "transactions/generations/ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff/inventory.json"
        )
        #expect(try #require(store.recover().activeSnapshot).generationSHA256 == baseline.generationSHA256)

        let activeScenePath = "transactions/generations/\(baseline.generationSHA256)/scene.json"
        fileSystem.installDurable(Data("{}".utf8), at: activeScenePath)
        #expect(store.recover() == .corrupt(.memberDigestMismatch))
    }

    @Test("invalid semantic links reject before any generation filesystem mutation")
    func invalidCandidateIsPreflightOnly() throws {
        let recorder = TransactionStoreFaultController()
        let fileSystem = DurableMemoryCaptureFileSystem(
            observe: recorder.observeBefore,
            afterOperation: recorder.observeAfter
        )
        let store = try TransactionPersistenceFixtures.store(fileSystem: fileSystem)
        _ = try store.activate(TransactionPersistenceFixtures.baseline)
        let before = fileSystem.snapshotFiles()
        let operationsBefore = recorder.observations
        let invalid = TransactionGenerationCandidate(
            scene: TransactionPersistenceFixtures.placed.scene,
            transactions: TransactionPersistenceFixtures.placed.transactions,
            requiredArtifacts: [],
            receipts: TransactionPersistenceFixtures.placed.receipts,
            idempotencyRecords: TransactionPersistenceFixtures.placed.idempotencyRecords
        )
        #expect(throws: TransactionStoreError.semanticMismatch) {
            _ = try store.activate(invalid)
        }
        #expect(fileSystem.snapshotFiles() == before)
        #expect(recorder.observations == operationsBefore)
    }
}

struct TransactionStoreFaultCase: Sendable, CustomTestStringConvertible {
    let name: String
    let target: TransactionStoreFaultTarget
    let expectsNewGeneration: Bool
    var testDescription: String { name }

    static let cases: [Self] = {
        var values = [Self]()
        func add(_ label: String, _ kind: CaptureFileOperationKind, _ suffix: String) {
            values.append(Self(name: "\(label)/before", target: .init(kind: kind, phase: .before, pathSuffix: suffix), expectsNewGeneration: false))
            values.append(Self(name: "\(label)/after", target: .init(kind: kind, phase: .after, pathSuffix: suffix), expectsNewGeneration: label == "active root directory sync"))
        }
        add("generation directory create", .createDirectory, "/generations/")
        for member in [
            "scene.json", "transactions.json", "inverse-index.json", "artifacts.json",
            "receipts.json", "idempotency.json", "inventory.json",
        ] {
            add("\(member) write", .write, member)
            add("\(member) file sync", .synchronizeFile, member)
        }
        add("generation directory sync", .synchronizeDirectory, "/generations/")
        add("generations parent sync", .synchronizeDirectory, "/generations")
        add("active pointer replace", .replace, "active-generation.json")
        add("active pointer file sync", .synchronizeFile, "active-generation.json")
        add("active root directory sync", .synchronizeDirectory, "transactions")
        return values
    }()
}

enum TransactionStoreFaultPhase: String, Sendable {
    case before
    case after
}

struct TransactionStoreFaultTarget: Sendable {
    let kind: CaptureFileOperationKind
    let phase: TransactionStoreFaultPhase
    let pathSuffix: String
}

struct TransactionStoreOperationObservation: Equatable, Sendable {
    let phase: TransactionStoreFaultPhase
    let operation: CaptureFileOperation
}

struct InjectedTransactionStoreFault: Error, Equatable, Sendable {}

final class TransactionStoreFaultController: @unchecked Sendable {
    private let lock = NSLock()
    private var target: TransactionStoreFaultTarget?
    private var fired = false
    private var recorded = [TransactionStoreOperationObservation]()

    var didFire: Bool { withLock { fired } }
    var observations: [TransactionStoreOperationObservation] { withLock { recorded } }

    func arm(_ target: TransactionStoreFaultTarget) {
        withLock { self.target = target; fired = false }
    }

    func observeBefore(_ operation: CaptureFileOperation) throws {
        try observe(operation, phase: .before)
    }

    func observeAfter(_ operation: CaptureFileOperation) throws {
        try observe(operation, phase: .after)
    }

    private func observe(_ operation: CaptureFileOperation, phase: TransactionStoreFaultPhase) throws {
        let shouldThrow = withLock { () -> Bool in
            recorded.append(.init(phase: phase, operation: operation))
            guard !fired,
                  let target,
                  target.kind == operation.kind,
                  target.phase == phase,
                  operation.path.hasSuffix(target.pathSuffix)
            else { return false }
            fired = true
            return true
        }
        if shouldThrow { throw InjectedTransactionStoreFault() }
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

final class DurableMemoryCaptureFileSystem: CaptureFileSystem, @unchecked Sendable {
    let limits = CaptureFileSystemLimits.production
    private let lock = NSLock()
    private var directories: Set<String>
    private var files: [String: Data]
    private var synchronizedFiles: [String: Data]
    private var durableDirectories: Set<String>
    private var durableFiles: [String: Data]
    private let observe: CaptureFileOperationObserver
    private let afterOperation: CaptureFileOperationObserver

    init(
        directories: Set<String> = [],
        files: [String: Data] = [:],
        durableDirectories: Set<String> = [],
        durableFiles: [String: Data] = [:],
        observe: @escaping CaptureFileOperationObserver = { _ in },
        afterOperation: @escaping CaptureFileOperationObserver = { _ in }
    ) {
        self.directories = directories
        self.files = files
        self.synchronizedFiles = durableFiles
        self.durableDirectories = durableDirectories
        self.durableFiles = durableFiles
        self.observe = observe
        self.afterOperation = afterOperation
    }

    func createDirectory(at path: String) throws {
        let operation = CaptureFileOperation(kind: .createDirectory, path: path)
        try observe(operation)
        try withLock {
            guard !directories.contains(path), files[path] == nil else { throw CaptureFileSystemError.destinationExists }
            directories.insert(path)
        }
        try afterOperation(operation)
    }

    func write(_ data: Data, to path: String) throws {
        let operation = CaptureFileOperation(kind: .write, path: path, byteCount: data.count)
        try observe(operation)
        try withLock {
            guard files[path] == nil else { throw CaptureFileSystemError.destinationExists }
            files[path] = data
        }
        try afterOperation(operation)
    }

    func synchronizeFile(at path: String) throws {
        let operation = CaptureFileOperation(kind: .synchronizeFile, path: path)
        try observe(operation)
        try withLock {
            guard let data = files[path] else { throw CaptureFileSystemError.missingFile }
            synchronizedFiles[path] = data
        }
        try afterOperation(operation)
    }

    func synchronizeDirectory(at path: String) throws {
        let operation = CaptureFileOperation(kind: .synchronizeDirectory, path: path)
        try observe(operation)
        try withLock {
            guard directories.contains(path) else { throw CaptureFileSystemError.missingFile }
            durableDirectories.formUnion(directories.filter { $0 == path || $0.hasPrefix(path + "/") })
            for (file, data) in synchronizedFiles where file.hasPrefix(path + "/") {
                durableFiles[file] = data
            }
        }
        try afterOperation(operation)
    }

    func append(_ data: Data, to path: String) throws {
        let operation = CaptureFileOperation(kind: .append, path: path, byteCount: data.count)
        try observe(operation)
        try withLock {
            guard files[path] != nil else { throw CaptureFileSystemError.missingFile }
            files[path]!.append(data)
        }
        try afterOperation(operation)
    }

    func replace(_ data: Data, at path: String) throws {
        let operation = CaptureFileOperation(kind: .replace, path: path, byteCount: data.count)
        try observe(operation)
        withLock { files[path] = data }
        try afterOperation(operation)
    }

    func rename(from sourcePath: String, to destinationPath: String) throws {
        let operation = CaptureFileOperation(kind: .rename, path: sourcePath, destinationPath: destinationPath)
        try observe(operation)
        try withLock {
            guard directories.remove(sourcePath) != nil else { throw CaptureFileSystemError.missingFile }
            directories.insert(destinationPath)
        }
        try afterOperation(operation)
    }

    func read(at path: String, maximumBytes: Int?) throws -> Data {
        let operation = CaptureFileOperation(kind: .read, path: path, byteCount: maximumBytes ?? limits.maximumReadBytes)
        try observe(operation)
        let data = try withLock {
            guard let data = files[path] else { throw CaptureFileSystemError.missingFile }
            return data
        }
        try afterOperation(operation)
        return data
    }

    func fileExists(at path: String) throws -> Bool {
        let operation = CaptureFileOperation(kind: .fileExists, path: path)
        try observe(operation)
        let result = withLock { directories.contains(path) || files[path] != nil }
        try afterOperation(operation)
        return result
    }

    func crashedCopy() -> DurableMemoryCaptureFileSystem {
        withLock {
            DurableMemoryCaptureFileSystem(
                directories: durableDirectories,
                files: durableFiles,
                durableDirectories: durableDirectories,
                durableFiles: durableFiles
            )
        }
    }

    func snapshotFiles() -> [String: Data] { withLock { files } }

    func installDurable(_ data: Data, at path: String) {
        withLock {
            files[path] = data
            synchronizedFiles[path] = data
            durableFiles[path] = data
        }
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

enum TransactionPersistenceFixtures {
    static let baseline: TransactionGenerationCandidate = {
        let scene = TransactionTestFixtures.scene(revision: 8, includeFirstAsset: false)
        return TransactionGenerationCandidate(
            scene: scene,
            transactions: [],
            requiredArtifacts: [TransactionTestFixtures.secondManifest],
            receipts: [],
            idempotencyRecords: []
        )
    }()

    static let placed: TransactionGenerationCandidate = try! makePlaced()

    static func makePlaced() throws -> TransactionGenerationCandidate {
        let preview = try PlaceFixtures.preview()
        let confirmation = try PlaceReducer.confirm(
            preview,
            currentScene: PlaceFixtures.scene,
            confirmation: PlaceFixtures.confirmation,
            request: PlaceFixtures.confirmationRequest
        )
        let resultSHA256 = try TransactionIntegrity.commitResultSHA256(
            authorityID: PlaceFixtures.scene.revisionAuthority.authorityID,
            revisionBranchID: PlaceFixtures.scene.revisionAuthority.revisionBranchID,
            compareAndSwapBaseRevision: PlaceFixtures.scene.sceneRevision,
            committedSceneRevision: confirmation.pendingSceneRevision,
            confirmation: PlaceFixtures.confirmation,
            committedAtUTC: PlaceFixtures.confirmationRequest.updatedAtUTC,
            localDurableBeforeVisibleAck: true
        )
        let fingerprint = try TransactionFingerprint.digest(
            proposal: preview.proposal,
            proposedOperations: confirmation.proposedOperations
        )
        let commit = TransactionCommit(
            contractAuthorityID: PlaceFixtures.scene.revisionAuthority.authorityID,
            revisionBranchID: PlaceFixtures.scene.revisionAuthority.revisionBranchID,
            compareAndSwapBaseRevision: PlaceFixtures.scene.sceneRevision,
            committedSceneRevision: confirmation.pendingSceneRevision,
            confirmation: PlaceFixtures.confirmation,
            committedAtUTC: PlaceFixtures.confirmationRequest.updatedAtUTC,
            resultSHA256: resultSHA256
        )
        let transaction = TransactionRecord(
            transactionID: PlaceFixtures.transactionID,
            idempotencyKey: PlaceFixtures.idempotencyKey,
            requestFingerprintSHA256: fingerprint,
            sessionID: preview.proposal.sessionID,
            revisionAuthority: preview.proposal.revisionAuthority,
            baseSceneRevision: preview.proposal.baseSceneRevision,
            targetContext: preview.proposal.targetContext,
            intent: preview.proposal.intent,
            proposedOperations: confirmation.proposedOperations,
            validation: preview.validation,
            preview: preview.preview,
            commit: commit,
            inverseOperations: [confirmation.inverseOperation],
            localUndoToken: "undo_30000000-0000-4000-8000-000000000020",
            canonicalState: .committed,
            syncState: .localOnly,
            createdAtUTC: PlaceFixtures.confirmationRequest.updatedAtUTC
        )
        let receipt = TransactionReceipt(
            contractTransactionID: transaction.transactionID,
            idempotencyKey: transaction.idempotencyKey,
            requestFingerprintSHA256: fingerprint,
            revisionAuthority: transaction.revisionAuthority,
            committedSceneRevision: confirmation.pendingSceneRevision,
            resultSHA256: resultSHA256
        )
        return TransactionGenerationCandidate(
            scene: confirmation.pendingScene,
            transactions: [transaction],
            requiredArtifacts: [TransactionTestFixtures.firstManifest, TransactionTestFixtures.secondManifest],
            receipts: [receipt],
            idempotencyRecords: [PersistentIdempotencyRecord(
                idempotencyKey: transaction.idempotencyKey,
                requestFingerprintSHA256: fingerprint,
                transactionID: transaction.transactionID,
                receipt: receipt
            )]
        )
    }

    static func store(fileSystem: any CaptureFileSystem) throws -> TransactionStore {
        TransactionStore(
            fileSystem: TransactionFileSystemAdapter(fileSystem: fileSystem),
            contracts: try contractAdapter()
        )
    }

    static func contractAdapter() throws -> TransactionContractAdapter {
        let root = try repositoryRoot()
        let registrations = [
            ContractSchemaRegistration(
                identifier: .sceneState,
                version: "1.0.0",
                sha256: FrozenContractBinding.sceneStateV1.schemaSHA256,
                schemaData: try Data(contentsOf: root.appendingPathComponent("docs/contracts/scene-state.schema.json"))
            ),
            ContractSchemaRegistration(
                identifier: .transaction,
                version: "1.0.0",
                sha256: FrozenContractBinding.transactionV1.schemaSHA256,
                schemaData: try Data(contentsOf: root.appendingPathComponent("docs/contracts/transaction.schema.json"))
            ),
        ]
        return TransactionContractAdapter(validator: try ContractValidator(registrations: registrations))
    }

    private static func repositoryRoot() throws -> URL {
        var cursor = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<12 {
            if FileManager.default.fileExists(atPath: cursor.appendingPathComponent("docs/contracts/transaction.schema.json").path) {
                return cursor
            }
            cursor.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }
}

private extension TransactionStoreRecovery {
    var activeSnapshot: TransactionGenerationSnapshot? {
        guard case .active(let snapshot) = self else { return nil }
        return snapshot
    }
}

private func recursiveRelativeFiles(root: URL) throws -> [String: Data] {
    guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
        return [:]
    }
    var files = [String: Data]()
    for case let url as URL in enumerator {
        if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
            files[String(url.path.dropFirst(root.path.count + 1))] = try Data(contentsOf: url)
        }
    }
    return files
}
