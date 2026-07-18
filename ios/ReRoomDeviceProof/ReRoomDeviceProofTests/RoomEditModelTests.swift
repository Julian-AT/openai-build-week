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

        let restarted = try harness.restarted(support: nil)
        await restarted.model.prepare()
        #expect(restarted.model.snapshot.revision == 1)
        #expect(restarted.model.snapshot.placedAssetVisible)
        #expect(restarted.model.snapshot.canRestore)

        await restarted.model.restoreFromButton()
        #expect(restarted.model.snapshot.revision == 2)
        #expect(!restarted.model.snapshot.placedAssetVisible)
        #expect(restarted.model.snapshot.localState == .durable)
        let canonical = await restarted.authority.activeSnapshot()
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

    @Test("manual target seed is epoch-bound, revision-neutral, and proposal-ready")
    func manualTargetSeedBindsStableContextWithoutMutation() async throws {
        let harness = try TestRoomEditHarness(support: .healthyFixture)
        await harness.model.prepare()
        let before = await harness.authority.activeSnapshot()

        await harness.model.groundTarget(
            candidates: [.heroFixture],
            tracking: .normal
        )

        let target = try #require(harness.model.snapshot.target.target)
        let context = try #require(harness.model.snapshot.targetContext)
        #expect(target.objectID == RoomEditIdentity.targetObjectID)
        #expect(target.lifecycle == .tracked)
        #expect(target.frozenProxy.version == 1)
        #expect(target.frozenProxy.capturedSceneRevision == 0)
        #expect(context.selectedObjectID == RoomEditIdentity.targetObjectID)
        #expect(context.candidateObjectIDs == [RoomEditIdentity.targetObjectID])
        #expect(context.worldFrameID == before.scene.worldFrame.worldFrameID)
        #expect(context.worldFrameVersion == before.scene.worldFrame.worldFrameVersion)
        #expect(harness.model.snapshot.revision == before.scene.sceneRevision)
        #expect(await harness.authority.activeSnapshot() == before)
    }

    @Test("miss and ambiguity are typed and preserve prior target plus revision")
    func failedGroundingIsNonmutating() async throws {
        let harness = try TestRoomEditHarness(support: .healthyFixture)
        await harness.model.prepare()
        await harness.model.groundTarget(candidates: [.heroFixture], tracking: .normal)
        let grounded = harness.model.snapshot.target.target

        await harness.model.groundTarget(candidates: [], tracking: .normal)
        #expect(harness.model.snapshot.target.failure == .targetMissed)
        #expect(harness.model.snapshot.target.target == grounded)
        #expect(harness.model.snapshot.revision == 0)

        await harness.model.groundTarget(
            candidates: [.heroFixture, .heroFixture(offsetX: 0.25)],
            tracking: .normal
        )
        #expect(harness.model.snapshot.target.failure == .targetAmbiguous)
        #expect(harness.model.snapshot.target.target == grounded)
        #expect((await harness.authority.activeSnapshot()).scene.sceneRevision == 0)
    }

    @Test("stale, wrong-epoch, unsupported, and unhealthy candidates fail closed")
    func invalidCandidatesFailClosed() {
        let environment = TargetGroundingEnvironment.fixture
        let initial = TargetGroundingReducer.initial(environment: environment)
        let invalidCases: [(ManualTargetCandidate, TargetGroundingFailure)] = [
            (.heroFixture(capturedSceneRevision: 1), .staleSceneRevision),
            (.heroFixture(worldFrameVersion: 2), .worldFrameMismatch),
            (.heroFixture(category: .unsupported("sofa")), .unsupportedTargetCategory),
        ]

        for (candidate, expectedFailure) in invalidCases {
            let reduced = TargetGroundingReducer.reduce(
                initial,
                event: .select([candidate]),
                environment: environment
            )
            #expect(reduced.failure == expectedFailure)
            #expect(reduced.target == nil)
        }

        let unhealthy = TargetGroundingReducer.reduce(
            initial,
            event: .select([.heroFixture]),
            environment: environment.with(tracking: .limited)
        )
        #expect(unhealthy.failure == .trackingNotNormal)
        #expect(unhealthy.target == nil)
    }

    @Test("tracking loss revokes edit readiness but restore remains transaction-derived")
    func readinessIsIndependentAcrossCapabilities() throws {
        let readyEnvironment = TargetGroundingEnvironment.fixture.with(restoreEligible: true)
        let seeded = TargetGroundingReducer.reduce(
            TargetGroundingReducer.initial(environment: readyEnvironment),
            event: .select([.heroFixture]),
            environment: readyEnvironment
        )

        #expect(seeded.readiness.select == .ready)
        #expect(seeded.readiness.place == .ready)
        #expect(seeded.readiness.replace == .degraded)
        #expect(seeded.readiness.remove == .unavailable)
        #expect(seeded.readiness.restore == .ready)
        #expect(seeded.reasons.replace == [.providerUnavailable])
        #expect(seeded.reasons.remove == [.revealQualityFailed])

        let lostEnvironment = readyEnvironment.with(tracking: .notAvailable)
        let lost = TargetGroundingReducer.reduce(
            seeded,
            event: .trackingChanged,
            environment: lostEnvironment
        )
        #expect(lost.target?.lifecycle == .lost)
        #expect(lost.readiness.select == .unavailable)
        #expect(lost.readiness.place == .unavailable)
        #expect(lost.readiness.replace == .unavailable)
        #expect(lost.readiness.restore == .ready)
        #expect(lost.reasons.select == [.trackingNotNormal])
    }

    @Test("world reset requires explicit reseed and preserves semantic identity")
    func reseedReplacesOnlySpatialEvidence() throws {
        let firstEnvironment = TargetGroundingEnvironment.fixture
        let seeded = TargetGroundingReducer.reduce(
            TargetGroundingReducer.initial(environment: firstEnvironment),
            event: .select([.heroFixture]),
            environment: firstEnvironment
        )
        let firstTarget = try #require(seeded.target)
        let resetEnvironment = firstEnvironment.with(worldFrameVersion: 2)
        let reset = TargetGroundingReducer.reduce(
            seeded,
            event: .worldReset,
            environment: resetEnvironment
        )
        #expect(reset.target?.lifecycle == .lost)
        #expect(reset.target?.frozenProxy == firstTarget.frozenProxy)
        #expect(reset.failure == .worldFrameMismatch)

        let recovered = TargetGroundingReducer.reduce(
            reset,
            event: .reseed([.heroFixture(worldFrameVersion: 2, offsetX: 0.4)]),
            environment: resetEnvironment
        )
        let recoveredTarget = try #require(recovered.target)
        #expect(recoveredTarget.objectID == firstTarget.objectID)
        #expect(recoveredTarget.lifecycle == .tracked)
        #expect(recoveredTarget.frozenProxy.version == 2)
        #expect(recoveredTarget.frozenProxy.worldFrameVersion == 2)
        #expect(recoveredTarget.frozenProxy.worldFromTarget != firstTarget.frozenProxy.worldFromTarget)
        #expect(recovered.failure == nil)
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
    func restarted(support: RoomEditSupportContext?) throws -> (
        model: RoomEditModel,
        authority: NativeBranchAuthority
    ) {
        let recoveredAuthority = try NativeBranchAuthority(
            store: TransactionStore(
                fileSystem: TransactionFileSystemAdapter(fileSystem: fileSystem, rootPath: "room-edit-test"),
                contracts: TransactionContractAdapter(validator: try DiagnosticAppOwner.makeContractValidator())
            ),
            bootstrap: RoomEditFactory.bootstrap(manifest: manifest),
            locallyAvailableArtifacts: [manifest.artifactReference]
        )
        return (
            model: RoomEditModel(
                authority: recoveredAuthority,
                manifest: manifest,
                supportProvider: { _ in support }
            ),
            authority: recoveredAuthority
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

private extension ManualTargetCandidate {
    static var heroFixture: Self { heroFixture() }

    static func heroFixture(
        category: ManualTargetCategory = .chair,
        capturedSceneRevision: UInt64 = 0,
        worldFrameVersion: UInt64 = 1,
        offsetX: Double = 0
    ) -> Self {
        ManualTargetCandidate(
            category: category,
            capturedAtFrameID: RoomEditIdentity.frameID,
            capturedSceneRevision: capturedSceneRevision,
            worldFrameID: RoomEditIdentity.worldFrameID,
            worldFrameVersion: worldFrameVersion,
            cameraPose: .identity,
            worldFromTarget: Matrix4(values: [
                1, 0, 0, offsetX,
                0, 1, 0, 0,
                0, 0, 1, -1.2,
                0, 0, 0, 1,
            ]),
            screenPointEncodedPixels: [320, 480]
        )
    }
}

private extension TargetGroundingEnvironment {
    static let fixture = TargetGroundingEnvironment(
        sceneRevision: 0,
        worldFrameID: RoomEditIdentity.worldFrameID,
        worldFrameVersion: 1,
        tracking: .normal,
        supportReady: true,
        restoreEligible: false
    )

    func with(
        worldFrameVersion: UInt64? = nil,
        tracking: TargetTrackingHealth? = nil,
        restoreEligible: Bool? = nil
    ) -> Self {
        TargetGroundingEnvironment(
            sceneRevision: sceneRevision,
            worldFrameID: worldFrameID,
            worldFrameVersion: worldFrameVersion ?? self.worldFrameVersion,
            tracking: tracking ?? self.tracking,
            supportReady: supportReady,
            restoreEligible: restoreEligible ?? self.restoreEligible
        )
    }
}

private final class RoomEditMemoryFileSystem: ReRoomCaptureCore.CaptureFileSystem, @unchecked Sendable {
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
