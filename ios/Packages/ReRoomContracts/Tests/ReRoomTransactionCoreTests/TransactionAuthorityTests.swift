import Foundation
@testable import ReRoomTransactionCore
import Testing

@Suite("FR-TRANSACTION-001 native branch authority")
struct TransactionAuthorityTests {
    @Test("concurrent remove confirms publish one durable revision and exact retry survives restart")
    func concurrentRemoveIsExactlyOnceAndRestartSafe() async throws {
        let context = try AuthorityFixtures.removeContext()
        let preview = try await context.authority.previewRemove(
            proposal: RemoveFixtures.proposal,
            candidate: RemoveFixtures.candidate,
            seed: RemoveFixtures.seed
        )

        let receipts = try await withThrowingTaskGroup(of: TransactionReceipt.self) { group in
            for _ in 0..<16 {
                group.addTask {
                    try await context.authority.commitRemove(
                        preview,
                        confirmation: RemoveFixtures.confirmation,
                        request: RemoveFixtures.confirmationRequest,
                        localUndoToken: AuthorityFixtures.removeUndoToken
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
        #expect(committed.scene.sceneRevision == 13)
        #expect(committed.transactions.count == 1)
        #expect(committed.transactions[0].intent.operation == .remove)
        #expect(committed.transactions[0].proposedOperations == preview.proposedOperations)
        #expect(committed.receipts == [receipt])
        #expect(committed.requiredArtifacts.contains(RemoveFixtures.reveal))
        let target = try #require(committed.scene.objects.first {
            $0.objectID == RemoveFixtures.targetObjectID
        })
        #expect(!target.editState.visible)
        #expect(target.editState.activeReveal == RemoveFixtures.reveal)
        let inverseOperation = try #require(committed.transactions[0].inverseOperations?.first)
        guard case .restoreSnapshot(_, let inverseBefore, _, _) = inverseOperation else {
            Issue.record("remove inverse must be restore_snapshot")
            return
        }
        #expect(inverseBefore.projectionSHA256 == (try EditProjectionEngine.digest(
            EditProjectionEngine.build(from: committed.scene)
        )))

        let restarted = try AuthorityFixtures.removeAuthority(fileSystem: context.fileSystem)
        #expect(await restarted.activeSnapshot() == committed)
        let durableBytes = context.fileSystem.snapshotFiles()
        let wrongConfirmation = ExplicitConfirmation(
            actorID: RemoveFixtures.userID,
            source: "native_ui",
            previewID: "preview_61000000-0000-4000-8000-000000000001",
            confirmationEventID: RemoveFixtures.eventID,
            confirmedAtUTC: RemoveFixtures.confirmation.confirmedAtUTC
        )
        #expect(try await restarted.commitRemove(
            preview,
            confirmation: wrongConfirmation,
            request: RemoveFixtures.confirmationRequest,
            localUndoToken: "invalid"
        ) == receipt)
        #expect(context.fileSystem.snapshotFiles() == durableBytes)
    }

    @Test("remove conflicts confirmation inventory freeze and activation faults publish no hidden state")
    func removeFailuresAreNonPublishing() async throws {
        let fresh = try AuthorityFixtures.removeContext()
        let freshPreview = try await fresh.authority.previewRemove(
            proposal: RemoveFixtures.proposal,
            candidate: RemoveFixtures.candidate,
            seed: RemoveFixtures.seed
        )
        let freshSnapshot = await fresh.authority.activeSnapshot()
        let freshBytes = fresh.fileSystem.snapshotFiles()
        let wrongConfirmation = ExplicitConfirmation(
            actorID: RemoveFixtures.userID,
            source: "native_ui",
            previewID: "preview_61000000-0000-4000-8000-000000000002",
            confirmationEventID: RemoveFixtures.eventID,
            confirmedAtUTC: RemoveFixtures.confirmation.confirmedAtUTC
        )
        await #expect(throws: RemoveRejection.confirmationMismatch) {
            try await fresh.authority.commitRemove(
                freshPreview,
                confirmation: wrongConfirmation,
                request: RemoveFixtures.confirmationRequest,
                localUndoToken: AuthorityFixtures.removeUndoToken
            )
        }
        await #expect(throws: TransactionAuthorityError.invalidLocalUndoToken) {
            try await fresh.authority.commitRemove(
                freshPreview,
                confirmation: RemoveFixtures.confirmation,
                request: RemoveFixtures.confirmationRequest,
                localUndoToken: "invalid"
            )
        }
        #expect(await fresh.authority.activeSnapshot() == freshSnapshot)
        #expect(fresh.fileSystem.snapshotFiles() == freshBytes)

        let missingArtifact = try AuthorityFixtures.removeContext(includeReveal: false)
        let missingPreview = try await missingArtifact.authority.previewRemove(
            proposal: RemoveFixtures.proposal,
            candidate: RemoveFixtures.candidate,
            seed: RemoveFixtures.seed
        )
        let beforeMissing = await missingArtifact.authority.activeSnapshot()
        let missingBytes = missingArtifact.fileSystem.snapshotFiles()
        await #expect(throws: TransactionAuthorityError.missingRequiredArtifact) {
            try await missingArtifact.authority.commitRemove(
                missingPreview,
                confirmation: RemoveFixtures.confirmation,
                request: RemoveFixtures.confirmationRequest,
                localUndoToken: AuthorityFixtures.removeUndoToken
            )
        }
        #expect(await missingArtifact.authority.activeSnapshot() == beforeMissing)
        #expect(missingArtifact.fileSystem.snapshotFiles() == missingBytes)

        let committedContext = try AuthorityFixtures.removeContext()
        let committedPreview = try await committedContext.authority.previewRemove(
            proposal: RemoveFixtures.proposal,
            candidate: RemoveFixtures.candidate,
            seed: RemoveFixtures.seed
        )
        _ = try await committedContext.authority.commitRemove(
            committedPreview,
            confirmation: RemoveFixtures.confirmation,
            request: RemoveFixtures.confirmationRequest,
            localUndoToken: AuthorityFixtures.removeUndoToken
        )
        let afterCommit = committedContext.fileSystem.snapshotFiles()
        let changed = RemovePreviewReduction(
            proposal: committedPreview.proposal,
            candidate: committedPreview.candidate,
            seed: committedPreview.seed,
            validation: committedPreview.validation,
            preview: committedPreview.preview,
            proposedOperations: [],
            canonicalSceneRevision: committedPreview.canonicalSceneRevision,
            sourceProjection: committedPreview.sourceProjection,
            committedProjection: committedPreview.committedProjection,
            networkReads: committedPreview.networkReads
        )
        await #expect(throws: TransactionAuthorityError.idempotencyConflict) {
            try await committedContext.authority.commitRemove(
                changed,
                confirmation: RemoveFixtures.confirmation,
                request: RemoveFixtures.confirmationRequest,
                localUndoToken: AuthorityFixtures.removeUndoToken
            )
        }
        let newKey = PlaceConfirmationRequest(
            transactionID: RemoveFixtures.transactionID,
            idempotencyKey: "txidem_61000000-0000-4000-8000-000000000003",
            updatedAtUTC: RemoveFixtures.confirmationRequest.updatedAtUTC
        )
        await #expect(throws: RemoveRejection.staleBaseRevision) {
            try await committedContext.authority.commitRemove(
                committedPreview,
                confirmation: RemoveFixtures.confirmation,
                request: newKey,
                localUndoToken: AuthorityFixtures.removeUndoToken
            )
        }
        #expect(committedContext.fileSystem.snapshotFiles() == afterCommit)

        let faultController = TransactionStoreFaultController()
        let faultedFileSystem = DurableMemoryCaptureFileSystem(
            observe: faultController.observeBefore,
            afterOperation: faultController.observeAfter
        )
        let faulted = try AuthorityFixtures.removeAuthority(fileSystem: faultedFileSystem)
        let faultedPreview = try await faulted.previewRemove(
            proposal: RemoveFixtures.proposal,
            candidate: RemoveFixtures.candidate,
            seed: RemoveFixtures.seed
        )
        let beforeFault = await faulted.activeSnapshot()
        faultController.arm(.init(kind: .replace, phase: .before, pathSuffix: "active-generation.json"))
        await #expect(throws: InjectedTransactionStoreFault.self) {
            try await faulted.commitRemove(
                faultedPreview,
                confirmation: RemoveFixtures.confirmation,
                request: RemoveFixtures.confirmationRequest,
                localUndoToken: AuthorityFixtures.removeUndoToken
            )
        }
        #expect(await faulted.activeSnapshot() == beforeFault)
        let recovered = try AuthorityFixtures.removeAuthority(fileSystem: faultedFileSystem.crashedCopy())
        #expect(await recovered.activeSnapshot() == beforeFault)

        let frozen = try AuthorityFixtures.removeContext()
        let frozenPreview = try await frozen.authority.previewRemove(
            proposal: RemoveFixtures.proposal,
            candidate: RemoveFixtures.candidate,
            seed: RemoveFixtures.seed
        )
        let divergent = try AuthorityFixtures.snapshot(
            candidate: TransactionPersistenceFixtures.placed
        )
        _ = try await frozen.authority.reportUnexpectedSameBranchDivergence(
            divergent,
            quarantinedBranchID: AuthorityFixtures.quarantinedBranchID,
            lastKnownGatewayRevision: divergent.scene.sceneRevision
        )
        let frozenBytes = frozen.fileSystem.snapshotFiles()
        await #expect(throws: TransactionAuthorityError.authorityFrozen) {
            try await frozen.authority.commitRemove(
                frozenPreview,
                confirmation: RemoveFixtures.confirmation,
                request: RemoveFixtures.confirmationRequest,
                localUndoToken: AuthorityFixtures.removeUndoToken
            )
        }
        #expect(frozen.fileSystem.snapshotFiles() == frozenBytes)
    }

    @Test("remove restart and restore preserve unrelated state and immutable source record")
    func removeRestorePreservesUnrelatedState() async throws {
        let context = try AuthorityFixtures.removeContext()
        let preview = try await context.authority.previewRemove(
            proposal: RemoveFixtures.proposal,
            candidate: RemoveFixtures.candidate,
            seed: RemoveFixtures.seed
        )
        let removeReceipt = try await context.authority.commitRemove(
            preview,
            confirmation: RemoveFixtures.confirmation,
            request: RemoveFixtures.confirmationRequest,
            localUndoToken: AuthorityFixtures.removeUndoToken
        )
        let removed = await context.authority.activeSnapshot()
        let immutableRemoveBytes = try AuthorityFixtures.encode(removed.transactions[0])

        let trackedScene = AuthorityFixtures.addingUnrelatedObject(to: removed.scene)
        _ = try TransactionPersistenceFixtures.store(fileSystem: context.fileSystem).activate(
            TransactionGenerationCandidate(
                scene: trackedScene,
                transactions: removed.transactions,
                requiredArtifacts: removed.requiredArtifacts,
                receipts: removed.receipts,
                idempotencyRecords: removed.idempotencyRecords
            )
        )

        let restarted = try AuthorityFixtures.removeAuthority(fileSystem: context.fileSystem)
        let tracked = await restarted.activeSnapshot()
        #expect(tracked.scene.objects.contains { $0.objectID == TransactionTestFixtures.newObjectID })
        #expect(try await restarted.commitRemove(
            preview,
            confirmation: RemoveFixtures.confirmation,
            request: RemoveFixtures.confirmationRequest,
            localUndoToken: AuthorityFixtures.removeUndoToken
        ) == removeReceipt)
        let restorePreview = try await restarted.previewRestore(
            proposal: AuthorityFixtures.restoreProposal(scene: tracked.scene),
            request: AuthorityFixtures.removeRestoreRequest,
            seed: AuthorityFixtures.removeRestoreSeed
        )
        _ = try await restarted.commitRestore(
            restorePreview,
            confirmation: AuthorityFixtures.removeRestoreConfirmation,
            idempotencyKey: AuthorityFixtures.removeRestoreIdempotencyKey,
            localUndoToken: AuthorityFixtures.removeRestoreUndoToken
        )

        let restored = await restarted.activeSnapshot()
        #expect(restored.scene.sceneRevision == 14)
        #expect(restored.scene.editHistory.map(\.operation) == [.remove, .restore])
        #expect(restored.scene.objects.contains { $0.objectID == TransactionTestFixtures.newObjectID })
        let target = try #require(restored.scene.objects.first {
            $0.objectID == RemoveFixtures.targetObjectID
        })
        #expect(target.editState.visible)
        #expect(target.editState.activeReveal == nil)
        #expect(restored.transactions.count == 2)
        #expect(restored.transactions[1].compensatesTransactionID == removed.transactions[0].transactionID)
        #expect(try AuthorityFixtures.encode(restored.transactions[0]) == immutableRemoveBytes)
        let restartedAgain = try AuthorityFixtures.removeAuthority(fileSystem: context.fileSystem)
        #expect(await restartedAgain.activeSnapshot() == restored)
    }

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

    @Test("replace restore preserves newly tracked unrelated state and immutable history")
    func replaceRestorePreservesUnrelatedState() async throws {
        let context = try AuthorityFixtures.context()
        let replacePreview = try await context.authority.previewReplace(
            proposal: ReplaceFixtures.proposal,
            candidate: ReplaceFixtures.candidate,
            seed: ReplaceFixtures.seed
        )
        _ = try await context.authority.commitReplace(
            replacePreview,
            confirmation: ReplaceFixtures.confirmation,
            request: ReplaceFixtures.confirmationRequest,
            localUndoToken: AuthorityFixtures.replaceUndoToken
        )
        let replaced = await context.authority.activeSnapshot()
        let immutableReplaceBytes = try AuthorityFixtures.encode(replaced.transactions[0])

        let trackedScene = AuthorityFixtures.addingUnrelatedObject(to: replaced.scene)
        let trackedCandidate = TransactionGenerationCandidate(
            scene: trackedScene,
            transactions: replaced.transactions,
            requiredArtifacts: replaced.requiredArtifacts,
            receipts: replaced.receipts,
            idempotencyRecords: replaced.idempotencyRecords
        )
        _ = try TransactionPersistenceFixtures.store(fileSystem: context.fileSystem).activate(trackedCandidate)

        let restarted = try AuthorityFixtures.authority(fileSystem: context.fileSystem)
        let tracked = await restarted.activeSnapshot()
        #expect(tracked.scene.objects.contains { $0.objectID == TransactionTestFixtures.newObjectID })
        let restorePreview = try await restarted.previewRestore(
            proposal: AuthorityFixtures.restoreProposal(scene: tracked.scene),
            request: AuthorityFixtures.replaceRestoreRequest,
            seed: AuthorityFixtures.replaceRestoreSeed
        )
        _ = try await restarted.commitRestore(
            restorePreview,
            confirmation: AuthorityFixtures.replaceRestoreConfirmation,
            idempotencyKey: AuthorityFixtures.replaceRestoreIdempotencyKey,
            localUndoToken: AuthorityFixtures.replaceRestoreUndoToken
        )

        let restored = await restarted.activeSnapshot()
        #expect(restored.scene.sceneRevision == 10)
        #expect(restored.scene.editHistory.map(\.operation) == [.replace, .restore])
        #expect(restored.scene.objects.contains { $0.objectID == TransactionTestFixtures.newObjectID })
        #expect(restored.scene.objects.first { $0.objectID == ReplaceFixtures.targetObjectID }?.editState.visible == true)
        #expect(restored.scene.placedAssets.contains { $0.placedAssetID == ReplaceFixtures.assetInstanceID } == false)
        #expect(restored.transactions.count == 2)
        #expect(restored.transactions[1].compensatesTransactionID == replaced.transactions[0].transactionID)
        #expect(try AuthorityFixtures.encode(restored.transactions[0]) == immutableReplaceBytes)
        let restartedAgain = try AuthorityFixtures.authority(fileSystem: context.fileSystem)
        #expect(await restartedAgain.activeSnapshot() == restored)
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
    static let replaceRestoreTransactionID = "tx_40000000-0000-4000-8000-000000000018"
    static let replaceRestoreIdempotencyKey = "txidem_40000000-0000-4000-8000-000000000019"
    static let replaceRestorePreviewID = "preview_40000000-0000-4000-8000-00000000001a"
    static let replaceRestoreEventID = "event_40000000-0000-4000-8000-00000000001b"
    static let replaceRestoreUndoToken = "undo_40000000-0000-4000-8000-00000000001c"
    static let removeUndoToken = "undo_61000000-0000-4000-8000-000000000010"
    static let removeRestoreTransactionID = "tx_61000000-0000-4000-8000-000000000011"
    static let removeRestoreIdempotencyKey = "txidem_61000000-0000-4000-8000-000000000012"
    static let removeRestorePreviewID = "preview_61000000-0000-4000-8000-000000000013"
    static let removeRestoreEventID = "event_61000000-0000-4000-8000-000000000014"
    static let removeRestoreUndoToken = "undo_61000000-0000-4000-8000-000000000015"

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

    static func removeContext(includeReveal: Bool = true) throws -> Context {
        let fileSystem = DurableMemoryCaptureFileSystem()
        return Context(
            fileSystem: fileSystem,
            authority: try removeAuthority(fileSystem: fileSystem, includeReveal: includeReveal)
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

    static func removeAuthority(
        fileSystem: DurableMemoryCaptureFileSystem,
        includeReveal: Bool = true
    ) throws -> NativeBranchAuthority {
        var artifacts = [TransactionTestFixtures.secondManifest]
        if includeReveal { artifacts.append(RemoveFixtures.reveal) }
        return try NativeBranchAuthority(
            store: TransactionPersistenceFixtures.store(fileSystem: fileSystem),
            bootstrap: TransactionGenerationCandidate(
                scene: RemoveFixtures.scene,
                transactions: [],
                requiredArtifacts: [TransactionTestFixtures.secondManifest],
                receipts: [],
                idempotencyRecords: []
            ),
            locallyAvailableArtifacts: artifacts
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
    static let replaceRestoreRequest = RestoreRequest(
        transactionID: replaceRestoreTransactionID,
        compensatesTransactionID: ReplaceFixtures.transactionID,
        updatedAtUTC: "2026-07-18T19:03:00Z"
    )
    static let replaceRestoreSeed = RestorePreviewSeed(
        previewID: replaceRestorePreviewID,
        expiresAtUTC: "2026-07-18T20:03:00Z"
    )
    static let replaceRestoreConfirmation = ExplicitConfirmation(
        actorID: ReplaceFixtures.userID,
        source: "native_ui",
        previewID: replaceRestorePreviewID,
        confirmationEventID: replaceRestoreEventID,
        confirmedAtUTC: "2026-07-18T19:03:00Z"
    )
    static let removeRestoreRequest = RestoreRequest(
        transactionID: removeRestoreTransactionID,
        compensatesTransactionID: RemoveFixtures.transactionID,
        updatedAtUTC: "2026-07-18T20:03:00Z"
    )
    static let removeRestoreSeed = RestorePreviewSeed(
        previewID: removeRestorePreviewID,
        expiresAtUTC: "2026-07-18T21:03:00Z"
    )
    static let removeRestoreConfirmation = ExplicitConfirmation(
        actorID: RemoveFixtures.userID,
        source: "native_ui",
        previewID: removeRestorePreviewID,
        confirmationEventID: removeRestoreEventID,
        confirmedAtUTC: "2026-07-18T20:03:00Z"
    )

    static func snapshot(candidate: TransactionGenerationCandidate) throws -> TransactionGenerationSnapshot {
        TransactionGenerationSnapshot(
            generationSHA256: try TransactionStore.generationSHA256(for: candidate),
            scene: candidate.scene,
            transactions: candidate.transactions,
            requiredArtifacts: candidate.requiredArtifacts,
            receipts: candidate.receipts,
            idempotencyRecords: candidate.idempotencyRecords
        )
    }

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

    static func addingUnrelatedObject(to scene: SceneState) -> SceneState {
        let unrelated = TransactionTestFixtures.scene(
            revision: scene.sceneRevision,
            includeFirstAsset: false,
            includeNewObject: true
        ).objects.first { $0.objectID == TransactionTestFixtures.newObjectID }!
        return SceneState(
            contractSchemaVersion: scene.schemaVersion,
            sessionID: scene.sessionID,
            sceneID: scene.sceneID,
            revisionAuthority: scene.revisionAuthority,
            sceneRevision: scene.sceneRevision,
            worldFrame: scene.worldFrame,
            surfaces: scene.surfaces,
            objects: scene.objects + [unrelated],
            supportRelations: scene.supportRelations,
            placedAssets: scene.placedAssets,
            editHistory: scene.editHistory,
            updatedAtUTC: scene.updatedAtUTC
        )
    }
}
