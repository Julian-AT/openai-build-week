import Foundation
import ReRoomCaptureCore
import ReRoomContracts
import ReRoomTransactionCore
import Testing
@testable import ReRoomDeviceProof

@Suite("Phase 3 room-edit presentation boundary")
@MainActor
struct RoomEditModelTests {
    @Test("bundled proxy has a closed identity and exact source digest")
    func proxyIdentityAndDigestAreBound() throws {
        let manifest = try Phase3ProxyManifest.load(bundle: Bundle(for: RoomEditModel.self))
        let sourceURL = try #require(Bundle(for: RoomEditModel.self).url(
            forResource: "proxy-chair",
            withExtension: "usda"
        ))

        #expect(manifest.proxyID == "asset_proxy-chair-phase3")
        #expect(manifest.qualification == "phase3_local_demo_proxy_only")
        #expect(manifest.sourceSHA256 == CanonicalJSON.sha256Hex(try Data(contentsOf: sourceURL)))
        #expect(manifest.artifactReference.artifactID == manifest.artifactID)
        #expect(manifest.artifactReference.artifactType == "asset_manifest")
    }

    @Test("missing healthy support blocks place without changing canonical revision")
    func supportFailureIsTypedAndNonmutating() async throws {
        let harness = try TestRoomEditHarness(support: nil)
        await harness.model.prepare()
        await harness.model.selectOperation(.place)

        #expect(harness.model.snapshot.revision == 0)
        #expect(harness.model.snapshot.preview == nil)
        #expect(harness.model.snapshot.blocker == .healthySupportRequired)
        #expect((await harness.authority.activeSnapshot()).scene.sceneRevision == 0)
    }

    @Test("preview and cancel keep r0; explicit button confirmation durably activates r1")
    func previewCancelAndConfirmationAreExact() async throws {
        let harness = try TestRoomEditHarness(support: .healthyFixture)
        await harness.model.prepare()
        await harness.model.selectOperation(.place)

        #expect(harness.model.snapshot.operations == RoomEditOperation.allCases)
        #expect(harness.model.snapshot.preview?.baseRevision == 0)
        #expect(harness.model.snapshot.revision == 0)
        #expect(harness.model.snapshot.canConfirm)
        await harness.model.cancelPreview()
        #expect(harness.model.snapshot.preview == nil)
        #expect((await harness.authority.activeSnapshot()).scene.sceneRevision == 0)

        await harness.model.selectOperation(.place)
        await harness.model.confirmPlacementFromButton()
        #expect(harness.model.snapshot.revision == 1)
        #expect(harness.model.snapshot.localState == .durable)
        #expect(harness.model.snapshot.preview == nil)
        #expect(!harness.model.snapshot.canConfirm)
        #expect(harness.model.snapshot.canRestore)
        #expect((await harness.authority.activeSnapshot()).transactions.count == 1)
    }

    @Test("restart recovers r1 and offline restore creates a compensating r2")
    func restartAndOfflineRestoreAreDurable() async throws {
        let harness = try TestRoomEditHarness(support: .healthyFixture)
        await harness.model.prepare()
        await harness.model.selectOperation(.place)
        await harness.model.confirmPlacementFromButton()

        let restarted = try harness.restartedModel(support: nil)
        await restarted.prepare()
        #expect(restarted.snapshot.revision == 1)
        #expect(restarted.snapshot.placedAssetVisible)
        #expect(restarted.snapshot.canRestore)

        await restarted.restoreFromButton()
        #expect(restarted.snapshot.revision == 2)
        #expect(!restarted.snapshot.placedAssetVisible)
        #expect(restarted.snapshot.localState == .durable)
        let canonical = await harness.authority.activeSnapshot()
        #expect(canonical.transactions.count == 2)
        #expect(canonical.transactions.last?.compensatesTransactionID == canonical.transactions.first?.transactionID)
    }

    @Test("replace and remove stay visible as typed nonmutating blockers")
    func deferredOperationsCannotMutate() async throws {
        let harness = try TestRoomEditHarness(support: .healthyFixture)
        await harness.model.prepare()
        let before = await harness.authority.activeSnapshot()

        await harness.model.selectOperation(.replace)
        #expect(harness.model.snapshot.blocker == .replaceDeferred)
        await harness.model.selectOperation(.remove)
        #expect(harness.model.snapshot.blocker == .removeDeferred)
        #expect(harness.model.snapshot.operations.count == 4)
        #expect(await harness.authority.activeSnapshot() == before)
    }
}

private struct TestRoomEditHarness {
    let fileSystem: RoomEditMemoryFileSystem
    let manifest: Phase3ProxyManifest
    let authority: NativeBranchAuthority
    let model: RoomEditModel

    @MainActor
    init(support: RoomEditSupportContext?) throws {
        let fileSystem = RoomEditMemoryFileSystem()
        let manifest = try Phase3ProxyManifest.load(bundle: Bundle(for: RoomEditModel.self))
        let store = TransactionStore(
            fileSystem: TransactionFileSystemAdapter(fileSystem: fileSystem, rootPath: "room-edit-test"),
            contracts: TransactionContractAdapter(validator: try DiagnosticAppOwner.makeContractValidator())
        )
        let authority = try NativeBranchAuthority(
            store: store,
            bootstrap: RoomEditFactory.bootstrap(manifest: manifest),
            locallyAvailableArtifacts: [manifest.artifactReference]
        )
        self.fileSystem = fileSystem
        self.manifest = manifest
        self.authority = authority
        self.model = RoomEditModel(
            authority: authority,
            manifest: manifest,
            supportProvider: { _ in support }
        )
    }

    @MainActor
    func restartedModel(support: RoomEditSupportContext?) throws -> RoomEditModel {
        let recoveredAuthority = try NativeBranchAuthority(
            store: TransactionStore(
                fileSystem: TransactionFileSystemAdapter(fileSystem: fileSystem, rootPath: "room-edit-test"),
                contracts: TransactionContractAdapter(validator: try DiagnosticAppOwner.makeContractValidator())
            ),
            bootstrap: RoomEditFactory.bootstrap(manifest: manifest),
            locallyAvailableArtifacts: [manifest.artifactReference]
        )
        return RoomEditModel(
            authority: recoveredAuthority,
            manifest: manifest,
            supportProvider: { _ in support }
        )
    }
}

private extension RoomEditSupportContext {
    static let healthyFixture = RoomEditSupportContext(
        capturedFrameID: RoomEditIdentity.frameID,
        surfaceID: RoomEditIdentity.surfaceID,
        cameraPose: .identity,
        worldFromAsset: Matrix4(values: [
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, -1.2,
            0, 0, 0, 1,
        ]),
        confidence: 0.95,
        method: "arkit_plane"
    )
}

private final class RoomEditMemoryFileSystem: CaptureFileSystem, @unchecked Sendable {
    let limits = CaptureFileSystemLimits.production
    private let lock = NSLock()
    private var directories: Set<String> = []
    private var files: [String: Data] = [:]

    func createDirectory(at path: String) throws {
        try withLock {
            guard directories.insert(path).inserted else { throw CaptureFileSystemError.destinationExists }
        }
    }

    func write(_ data: Data, to path: String) throws {
        try withLock {
            guard files[path] == nil else { throw CaptureFileSystemError.destinationExists }
            files[path] = data
        }
    }

    func synchronizeFile(at path: String) throws {
        guard try fileExists(at: path) else { throw CaptureFileSystemError.missingFile }
    }

    func synchronizeDirectory(at path: String) throws {
        let exists = withLock { directories.contains(path) }
        guard exists else { throw CaptureFileSystemError.missingFile }
    }

    func append(_ data: Data, to path: String) throws {
        try withLock {
            guard files[path] != nil else { throw CaptureFileSystemError.missingFile }
            files[path]!.append(data)
        }
    }

    func replace(_ data: Data, at path: String) throws { withLock { files[path] = data } }

    func rename(from sourcePath: String, to destinationPath: String) throws {
        try withLock {
            guard directories.remove(sourcePath) != nil else { throw CaptureFileSystemError.missingFile }
            directories.insert(destinationPath)
        }
    }

    func read(at path: String, maximumBytes: Int?) throws -> Data {
        try withLock {
            guard let data = files[path] else { throw CaptureFileSystemError.missingFile }
            guard data.count <= (maximumBytes ?? limits.maximumReadBytes) else {
                throw CaptureFileSystemError.byteLimitExceeded
            }
            return data
        }
    }

    func fileExists(at path: String) throws -> Bool {
        withLock { directories.contains(path) || files[path] != nil }
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
