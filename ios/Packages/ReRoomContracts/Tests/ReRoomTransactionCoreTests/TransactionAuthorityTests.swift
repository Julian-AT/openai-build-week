import Foundation
@testable import ReRoomTransactionCore
import Testing

@Suite("FR-TRANSACTION-001 native branch authority")
struct TransactionAuthorityTests {
    @Test("concurrent replace confirms publish one durable revision and survive restart")
    func concurrentReplaceIsExactlyOnceAndRestartSafe() async throws {
        let context = try AuthorityFixtures.context()
        let preview = try await context.authority.previewReplace(
            proposal: ReplaceFixtures.proposal,
            candidate: ReplaceFixtures.candidate,
            seed: ReplaceFixtures.seed
        )

        let receipts = try await withThrowingTaskGroup(of: TransactionReceipt.self) { group in
            for _ in 0..<16 {
                group.addTask {
                    try await context.authority.commitReplace(
                        preview,
                        confirmation: ReplaceFixtures.confirmation,
                        request: ReplaceFixtures.confirmationRequest,
                        localUndoToken: AuthorityFixtures.replaceUndoToken
                    )
                }
            }
            var values = [TransactionReceipt]()
            for try await receipt in group { values.append(receipt) }
            return values
        }

        let receipt = try #require(receipts.first)
        #expect(receipts.allSatisfy { $0 == receipt })
        let committed = await context.authority.activeSnapshot()
        #expect(committed.scene.sceneRevision == 9)
        #expect(committed.transactions.count == 1)
        #expect(committed.transactions[0].intent.operation == .replace)
        #expect(committed.receipts == [receipt])

        let restarted = try AuthorityFixtures.authority(fileSystem: context.fileSystem)
        #expect(await restarted.activeSnapshot() == committed)
        let durableBytes = context.fileSystem.snapshotFiles()
        #expect(try await restarted.commitReplace(
            preview,
            confirmation: ReplaceFixtures.confirmation,
            request: ReplaceFixtures.confirmationRequest,
            localUndoToken: AuthorityFixtures.replaceUndoToken
        ) == receipt)
        #expect(context.fileSystem.snapshotFiles() == durableBytes)
    }

    @Test("replace conflicts invalid confirmation and activation fault publish no replacement")
    func replaceFailuresAreNonPublishing() async throws {
        let context = try AuthorityFixtures.context()
        let preview = try await context.authority.previewReplace(
            proposal: ReplaceFixtures.proposal,
            candidate: ReplaceFixtures.candidate,
            seed: ReplaceFixtures.seed
        )
        _ = try await context.authority.commitReplace(
            preview,
            confirmation: ReplaceFixtures.confirmation,
            request: ReplaceFixtures.confirmationRequest,
            localUndoToken: AuthorityFixtures.replaceUndoToken
        )
        let afterCommit = context.fileSystem.snapshotFiles()
        let changed = ReplacePreviewReduction(
            proposal: preview.proposal,
            candidate: preview.candidate,
            seed: preview.seed,
            validation: preview.validation,
            preview: preview.preview,
            proposedOperations: [],
            canonicalSceneRevision: preview.canonicalSceneRevision,
            sourceProjection: preview.sourceProjection,
            committedProjection: preview.committedProjection,
            networkReads: preview.networkReads
        )
        await #expect(throws: TransactionAuthorityError.idempotencyConflict) {
            try await context.authority.commitReplace(
                changed,
                confirmation: ReplaceFixtures.confirmation,
                request: ReplaceFixtures.confirmationRequest,
                localUndoToken: AuthorityFixtures.replaceUndoToken
            )
        }
        #expect(context.fileSystem.snapshotFiles() == afterCommit)

        let controller = TransactionStoreFaultController()
        let faultedFileSystem = DurableMemoryCaptureFileSystem(
            observe: controller.observeBefore,
            afterOperation: controller.observeAfter
        )
        let faulted = try AuthorityFixtures.authority(fileSystem: faultedFileSystem)
        let faultedPreview = try await faulted.previewReplace(
            proposal: ReplaceFixtures.proposal,
            candidate: ReplaceFixtures.candidate,
            seed: ReplaceFixtures.seed
        )
        let beforeFault = await faulted.activeSnapshot()
        controller.arm(.init(kind: .replace, phase: .before, pathSuffix: "active-generation.json"))
        await #expect(throws: InjectedTransactionStoreFault.self) {
            try await faulted.commitReplace(
                faultedPreview,
                confirmation: ReplaceFixtures.confirmation,
                request: ReplaceFixtures.confirmationRequest,
                localUndoToken: AuthorityFixtures.replaceUndoToken
            )
        }
        #expect(await faulted.activeSnapshot() == beforeFault)
        let recovered = try AuthorityFixtures.authority(fileSystem: faultedFileSystem.crashedCopy())
        #expect(await recovered.activeSnapshot() == beforeFault)
    }

    @Test("concurrent identical confirms serialize to one durable revision and one receipt")
    func concurrentIdenticalConfirmIsExactlyOnce() async throws {
        let context = try AuthorityFixtures.context()
        let preview = try await context.authority.previewPlace(
            proposal: PlaceFixtures.proposal,
            candidate: PlaceFixtures.candidate,
            seed: PlaceFixtures.seed
        )

        let receipts = try await withThrowingTaskGroup(of: TransactionReceipt.self) { group in
            for _ in 0..<16 {
                group.addTask {
                    try await context.authority.commitPlace(
                        preview,
                        confirmation: PlaceFixtures.confirmation,
                        request: PlaceFixtures.confirmationRequest,
                        localUndoToken: AuthorityFixtures.placeUndoToken
                    )
                }
            }
            var values = [TransactionReceipt]()
            for try await receipt in group { values.append(receipt) }
            return values
        }

        let active = await context.authority.activeSnapshot()
        #expect(receipts.allSatisfy { $0 == receipts[0] })
        #expect(active.scene.sceneRevision == 9)
        #expect(active.transactions.count == 1)
        #expect(active.receipts == [receipts[0]])
        let durableBytes = context.fileSystem.snapshotFiles()
        let retried = try await context.authority.commitPlace(
            preview,
            confirmation: PlaceFixtures.confirmation,
            request: PlaceFixtures.confirmationRequest,
            localUndoToken: AuthorityFixtures.placeUndoToken
        )
        #expect(retried == receipts[0])
        #expect(context.fileSystem.snapshotFiles() == durableBytes)
    }

    @Test("changed fingerprint stale base and wrong authority reject without filesystem writes")
    func conflictsRejectWithoutWrites() async throws {
        let context = try AuthorityFixtures.context()
        let preview = try await context.authority.previewPlace(
            proposal: PlaceFixtures.proposal,
            candidate: PlaceFixtures.candidate,
            seed: PlaceFixtures.seed
        )
        _ = try await context.authority.commitPlace(
            preview,
            confirmation: PlaceFixtures.confirmation,
            request: PlaceFixtures.confirmationRequest,
            localUndoToken: AuthorityFixtures.placeUndoToken
        )
        let afterCommit = context.fileSystem.snapshotFiles()

        let changed = PlacePreviewReduction(
            proposal: preview.proposal,
            candidate: preview.candidate,
            seed: preview.seed,
            validation: preview.validation,
            preview: preview.preview,
            proposedOperations: [],
            canonicalSceneRevision: preview.canonicalSceneRevision,
            sourceProjection: preview.sourceProjection,
            committedProjection: preview.committedProjection,
            networkReads: preview.networkReads
        )
        await #expect(throws: TransactionAuthorityError.idempotencyConflict) {
            try await context.authority.commitPlace(
                changed,
                confirmation: PlaceFixtures.confirmation,
                request: PlaceFixtures.confirmationRequest,
                localUndoToken: AuthorityFixtures.placeUndoToken
            )
        }

        let newKey = PlaceConfirmationRequest(
            transactionID: PlaceFixtures.transactionID,
            idempotencyKey: "txidem_40000000-0000-4000-8000-000000000001",
            updatedAtUTC: PlaceFixtures.confirmationRequest.updatedAtUTC
        )
        await #expect(throws: PlaceRejection.staleBaseRevision) {
            try await context.authority.commitPlace(
                preview,
                confirmation: PlaceFixtures.confirmation,
                request: newKey,
                localUndoToken: AuthorityFixtures.placeUndoToken
            )
        }
        #expect(context.fileSystem.snapshotFiles() == afterCommit)

        let fresh = try AuthorityFixtures.context()
        let wrongAuthority = RevisionAuthority(
            kind: .nativeDevice,
            authorityID: "device_40000000-0000-4000-8000-000000000002",
            revisionBranchID: TransactionTestFixtures.branchID
        )
        let beforeWrongAuthority = fresh.fileSystem.snapshotFiles()
        await #expect(throws: PlaceRejection.authorityMismatch) {
            try await fresh.authority.previewPlace(
                proposal: PlaceFixtures.proposal(operation: .place, authority: wrongAuthority),
                candidate: PlaceFixtures.candidate,
                seed: PlaceFixtures.seed
            )
        }
        #expect(fresh.fileSystem.snapshotFiles() == beforeWrongAuthority)

        let wrongBranch = RevisionAuthority(
            kind: .nativeDevice,
            authorityID: TransactionTestFixtures.deviceID,
            revisionBranchID: "branch_40000000-0000-4000-8000-000000000003"
        )
        await #expect(throws: PlaceRejection.authorityMismatch) {
            try await fresh.authority.previewPlace(
                proposal: PlaceFixtures.proposal(operation: .place, authority: wrongBranch),
                candidate: PlaceFixtures.candidate,
                seed: PlaceFixtures.seed
            )
        }
        #expect(fresh.fileSystem.snapshotFiles() == beforeWrongAuthority)
    }

    @Test("place then explicit offline restore survives restart with exact immutable trace")
    func placeRestoreAndRestart() async throws {
        let context = try AuthorityFixtures.context()
        let placePreview = try await context.authority.previewPlace(
            proposal: PlaceFixtures.proposal,
            candidate: PlaceFixtures.candidate,
            seed: PlaceFixtures.seed
        )
        let placeReceipt = try await context.authority.commitPlace(
            placePreview,
            confirmation: PlaceFixtures.confirmation,
            request: PlaceFixtures.confirmationRequest,
            localUndoToken: AuthorityFixtures.placeUndoToken
        )
        let placeSnapshot = await context.authority.activeSnapshot()
        let sourceBytes = try AuthorityFixtures.encode(placeSnapshot.transactions[0])

        let restarted = try AuthorityFixtures.authority(fileSystem: context.fileSystem)
        #expect(await restarted.activeSnapshot() == placeSnapshot)
        let beforePlaceRetry = context.fileSystem.snapshotFiles()
        #expect(try await restarted.commitPlace(
            placePreview,
            confirmation: PlaceFixtures.confirmation,
            request: PlaceFixtures.confirmationRequest,
            localUndoToken: AuthorityFixtures.placeUndoToken
        ) == placeReceipt)
        #expect(context.fileSystem.snapshotFiles() == beforePlaceRetry)
        let restorePreview = try await restarted.previewRestore(
            proposal: AuthorityFixtures.restoreProposal(scene: placeSnapshot.scene),
            request: AuthorityFixtures.restoreRequest,
            seed: AuthorityFixtures.restoreSeed
        )
        #expect(restorePreview.reduction.networkReads == 0)
        let restoreReceipts = try await withThrowingTaskGroup(of: TransactionReceipt.self) { group in
            for _ in 0..<16 {
                group.addTask {
                    try await restarted.commitRestore(
                        restorePreview,
                        confirmation: AuthorityFixtures.restoreConfirmation,
                        idempotencyKey: AuthorityFixtures.restoreIdempotencyKey,
                        localUndoToken: AuthorityFixtures.restoreUndoToken
                    )
                }
            }
            var values = [TransactionReceipt]()
            for try await receipt in group { values.append(receipt) }
            return values
        }
        let receipt = restoreReceipts[0]
        #expect(restoreReceipts.allSatisfy { $0 == receipt })

        let restored = await restarted.activeSnapshot()
        #expect(receipt.committedSceneRevision == 10)
        #expect(restored.scene.sceneRevision == 10)
        #expect(restored.scene.editHistory.map(\.committedSceneRevision) == [9, 10])
        #expect(restored.transactions.map(\.baseSceneRevision) == [8, 9])
        #expect(restored.transactions.map(\.commit?.committedSceneRevision) == [9, 10])
        #expect(restored.transactions[1].compensatesTransactionID == restored.transactions[0].transactionID)
        #expect(try AuthorityFixtures.encode(restored.transactions[0]) == sourceBytes)
        #expect(restored.scene.placedAssets.map(\.placedAssetID).contains(PlaceFixtures.assetInstanceID) == false)

        let restartedAgain = try AuthorityFixtures.authority(fileSystem: context.fileSystem)
        #expect(await restartedAgain.activeSnapshot() == restored)
        let beforeRestoreRetry = context.fileSystem.snapshotFiles()
        #expect(try await restartedAgain.commitRestore(
            restorePreview,
            confirmation: AuthorityFixtures.restoreConfirmation,
            idempotencyKey: AuthorityFixtures.restoreIdempotencyKey,
            localUndoToken: AuthorityFixtures.restoreUndoToken
        ) == receipt)
        #expect(context.fileSystem.snapshotFiles() == beforeRestoreRetry)
    }

    @Test("same-branch divergence preserves both snapshots quarantines and freezes mutation")
    func divergenceFreezesAuthority() async throws {
        let context = try AuthorityFixtures.context()
        let preview = try await context.authority.previewPlace(
            proposal: PlaceFixtures.proposal,
            candidate: PlaceFixtures.candidate,
            seed: PlaceFixtures.seed
        )
        _ = try await context.authority.commitPlace(
            preview,
            confirmation: PlaceFixtures.confirmation,
            request: PlaceFixtures.confirmationRequest,
            localUndoToken: AuthorityFixtures.placeUndoToken
        )
        let local = await context.authority.activeSnapshot()
        let divergent = try TransactionGenerationSnapshot(
            generationSHA256: TransactionStore.generationSHA256(for: TransactionPersistenceFixtures.baseline),
            scene: TransactionPersistenceFixtures.baseline.scene,
            transactions: [],
            requiredArtifacts: TransactionPersistenceFixtures.baseline.requiredArtifacts,
            receipts: [],
            idempotencyRecords: []
        )
        let bytesBefore = context.fileSystem.snapshotFiles()

        let quarantine = try await context.authority.reportUnexpectedSameBranchDivergence(
            divergent,
            quarantinedBranchID: AuthorityFixtures.quarantinedBranchID,
            lastKnownGatewayRevision: divergent.scene.sceneRevision
        )
        #expect(quarantine.localSnapshot == local)
        #expect(quarantine.divergentSnapshot == divergent)
        #expect(quarantine.reconciliation.state == "manual_required")
        #expect(quarantine.reconciliation.resolution == "quarantined_divergent_branch")
        #expect(quarantine.reconciliation.automaticMergePermitted == false)
        #expect(quarantine.reconciliation.quarantinedBranchID == AuthorityFixtures.quarantinedBranchID)

        let restorePreview = try await context.authority.previewRestore(
            proposal: AuthorityFixtures.restoreProposal(scene: local.scene),
            request: AuthorityFixtures.restoreRequest,
            seed: AuthorityFixtures.restoreSeed
        )
        await #expect(throws: TransactionAuthorityError.authorityFrozen) {
            try await context.authority.commitRestore(
                restorePreview,
                confirmation: AuthorityFixtures.restoreConfirmation,
                idempotencyKey: AuthorityFixtures.restoreIdempotencyKey,
                localUndoToken: AuthorityFixtures.restoreUndoToken
            )
        }
        #expect(context.fileSystem.snapshotFiles() == bytesBefore)
        #expect(await context.authority.activeSnapshot() == local)
    }
}

enum AuthorityFixtures {
    static let placeUndoToken = "undo_40000000-0000-4000-8000-000000000010"
    static let replaceUndoToken = "undo_40000000-0000-4000-8000-000000000017"
    static let restoreTransactionID = "tx_40000000-0000-4000-8000-000000000011"
    static let restoreIdempotencyKey = "txidem_40000000-0000-4000-8000-000000000012"
    static let restorePreviewID = "preview_40000000-0000-4000-8000-000000000013"
    static let restoreEventID = "event_40000000-0000-4000-8000-000000000014"
    static let restoreUndoToken = "undo_40000000-0000-4000-8000-000000000015"
    static let quarantinedBranchID = "branch_40000000-0000-4000-8000-000000000016"

    struct Context {
        let fileSystem: DurableMemoryCaptureFileSystem
        let authority: NativeBranchAuthority
    }

    static func context() throws -> Context {
        let fileSystem = DurableMemoryCaptureFileSystem()
        return Context(
            fileSystem: fileSystem,
            authority: try authority(fileSystem: fileSystem)
        )
    }

    static func authority(fileSystem: DurableMemoryCaptureFileSystem) throws -> NativeBranchAuthority {
        try NativeBranchAuthority(
            store: TransactionPersistenceFixtures.store(fileSystem: fileSystem),
            bootstrap: TransactionPersistenceFixtures.baseline,
            locallyAvailableArtifacts: [
                TransactionTestFixtures.firstManifest,
                TransactionTestFixtures.secondManifest,
            ]
        )
    }

    static let restoreRequest = RestoreRequest(
        transactionID: restoreTransactionID,
        compensatesTransactionID: PlaceFixtures.transactionID,
        updatedAtUTC: "2026-07-18T17:03:00Z"
    )
    static let restoreSeed = RestorePreviewSeed(
        previewID: restorePreviewID,
        expiresAtUTC: "2026-07-18T18:03:00Z"
    )
    static let restoreConfirmation = ExplicitConfirmation(
        actorID: PlaceFixtures.userID,
        source: "native_ui",
        previewID: restorePreviewID,
        confirmationEventID: restoreEventID,
        confirmedAtUTC: "2026-07-18T17:03:00Z"
    )

    static func restoreProposal(scene: SceneState) -> BoundProposal {
        BoundProposal(
            sessionID: scene.sessionID,
            revisionAuthority: scene.revisionAuthority,
            baseSceneRevision: scene.sceneRevision,
            targetContext: TargetContext(
                contractCapturedAtFrameID: TransactionTestFixtures.frameID,
                capturedSceneRevision: scene.sceneRevision,
                worldFrameID: scene.worldFrame.worldFrameID,
                worldFrameVersion: scene.worldFrame.worldFrameVersion,
                cameraPose: TransactionTestFixtures.identity,
                screenPointEncodedPixels: [1, 1],
                candidateObjectIDs: [],
                selectedObjectID: nil,
                artifactRefs: []
            ),
            intent: TransactionIntent(
                contractOperation: .restore,
                source: "typed",
                arguments: IntentArguments(),
                constraints: []
            )
        )
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}
