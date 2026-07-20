import Foundation

public enum RestoreRejection: String, Error, Equatable, Sendable {
    case noEligibleSource = "no_eligible_source"
    case sourceAlreadyCompensated = "source_already_compensated"
    case sourceNotLatestEligible = "source_not_latest_eligible"
    case sourceTransactionInvalid = "source_transaction_invalid"
    case inverseIntegrity = "inverse_integrity"
    case branchWorldMismatch = "branch_world_mismatch"
    case touchedOperationMismatch = "touched_operation_mismatch"
    case unexpectedTouchedEntityDrift = "unexpected_touched_entity_drift"
    case artifactUnionMismatch = "artifact_union_mismatch"
    case missingRequiredArtifact = "missing_required_artifact"
    case invalidRestoreRequest = "invalid_restore_request"
}

public struct RestoreRequest: Equatable, Sendable {
    public let transactionID: String
    public let compensatesTransactionID: String
    public let updatedAtUTC: String

    public init(transactionID: String, compensatesTransactionID: String, updatedAtUTC: String) {
        self.transactionID = transactionID
        self.compensatesTransactionID = compensatesTransactionID
        self.updatedAtUTC = updatedAtUTC
    }
}

public struct RestoreCompensatingTransaction: Equatable, Sendable {
    public let transactionID: String
    public let compensatesTransactionID: String
    public let baseSceneRevision: UInt64
    public let pendingSceneRevision: UInt64
    public let proposedOperation: TransactionOperation
    public let inverseOperation: TransactionOperation

    public init(
        transactionID: String,
        compensatesTransactionID: String,
        baseSceneRevision: UInt64,
        pendingSceneRevision: UInt64,
        proposedOperation: TransactionOperation,
        inverseOperation: TransactionOperation
    ) {
        self.transactionID = transactionID
        self.compensatesTransactionID = compensatesTransactionID
        self.baseSceneRevision = baseSceneRevision
        self.pendingSceneRevision = pendingSceneRevision
        self.proposedOperation = proposedOperation
        self.inverseOperation = inverseOperation
    }
}

public struct RestoreReduction: Equatable, Sendable {
    public let sourceTransactionID: String
    public let pendingScene: SceneState
    public let transaction: RestoreCompensatingTransaction
    public let networkReads: UInt64

    public init(
        sourceTransactionID: String,
        pendingScene: SceneState,
        transaction: RestoreCompensatingTransaction,
        networkReads: UInt64 = 0
    ) {
        self.sourceTransactionID = sourceTransactionID
        self.pendingScene = pendingScene
        self.transaction = transaction
        self.networkReads = networkReads
    }
}

public enum RestoreReducer {
    public static func reduce(
        currentScene: SceneState,
        committedTransactions: [TransactionRecord],
        request: RestoreRequest,
        locallyAvailableArtifacts: [ArtifactReference]
    ) throws -> RestoreReduction {
        guard request.transactionID != request.compensatesTransactionID,
              validID(request.transactionID, prefix: "tx_"),
              validID(request.compensatesTransactionID, prefix: "tx_"),
              !committedTransactions.contains(where: { $0.transactionID == request.transactionID }),
              currentScene.sceneRevision < UInt64.max
        else { throw RestoreRejection.invalidRestoreRequest }
        guard Set(committedTransactions.map(\.transactionID)).count == committedTransactions.count else {
            throw RestoreRejection.sourceTransactionInvalid
        }
        guard let source = committedTransactions.first(where: { $0.transactionID == request.compensatesTransactionID }) else {
            throw RestoreRejection.noEligibleSource
        }

        let compensations = Set(committedTransactions.compactMap(\.compensatesTransactionID))
        guard !compensations.contains(source.transactionID) else {
            throw RestoreRejection.sourceAlreadyCompensated
        }

        let currentProjection: EditProjection
        do {
            currentProjection = try EditProjectionEngine.build(from: currentScene)
        } catch {
            throw RestoreRejection.branchWorldMismatch
        }
        guard source.sessionID == currentScene.sessionID,
              source.revisionAuthority == currentScene.revisionAuthority,
              source.targetContext.worldFrameID == currentProjection.worldFrameID,
              source.targetContext.worldFrameVersion == currentProjection.worldFrameVersion
        else { throw RestoreRejection.branchWorldMismatch }

        let uncompensatedOnBranch = committedTransactions.filter {
            $0.canonicalState == .committed &&
                $0.revisionAuthority.revisionBranchID == currentProjection.revisionBranchID &&
                !compensations.contains($0.transactionID)
        }
        let latest = uncompensatedOnBranch.max {
            committedRevision($0) < committedRevision($1)
        }
        guard latest?.transactionID == source.transactionID else {
            throw RestoreRejection.sourceNotLatestEligible
        }

        let sourceCommit = try validateSourceEnvelope(source, currentScene: currentScene)
        let inverse = try capturedInverse(from: source, commit: sourceCommit, currentProjection: currentProjection)
        let touched: EditProjectionTouchedIDs
        do {
            touched = try EditProjectionEngine.diff(
                sourceBefore: inverse.before.projection,
                sourceAfter: inverse.after.projection
            )
            try EditProjectionEngine.verify(touched: touched, against: source.proposedOperations)
            try verifyOperations(source.proposedOperations, transactionID: source.transactionID, pre: inverse.after.projection, committed: inverse.before.projection)
        } catch EditProjectionRejection.unexpectedTouchedEntityDrift {
            throw RestoreRejection.unexpectedTouchedEntityDrift
        } catch {
            throw RestoreRejection.touchedOperationMismatch
        }

        do {
            try EditProjectionEngine.verifyRequiredArtifactReferences(inverse.requiredArtifactRefs, for: inverse.after.projection)
        } catch {
            throw RestoreRejection.artifactUnionMismatch
        }

        let rebased: EditProjection
        do {
            rebased = try EditProjectionEngine.apply(
                sourceBefore: inverse.before.projection,
                sourceAfter: inverse.after.projection,
                to: currentProjection,
                touched: touched
            )
        } catch EditProjectionRejection.unexpectedTouchedEntityDrift {
            throw RestoreRejection.unexpectedTouchedEntityDrift
        } catch {
            throw RestoreRejection.inverseIntegrity
        }

        let derivation = RestoreRebaseDerivation(
            sourceTransactionID: source.transactionID,
            sourceInverseBeforeProjectionSHA256: inverse.before.projectionSHA256,
            sourceInverseAfterProjectionSHA256: inverse.after.projectionSHA256,
            touchedObjectIDs: touched.objectIDs,
            touchedPlacedAssetIDs: touched.placedAssetIDs,
            touchedAssetSupportRelationIDs: touched.assetSupportRelationIDs
        )
        let pendingRevision = currentScene.sceneRevision + 1
        let beforeSnapshot = try EditProjectionEngine.snapshot(
            currentProjection,
            capturedSceneRevision: currentScene.sceneRevision,
            origin: .capturedExact
        )
        let afterSnapshot = try EditProjectionEngine.snapshot(
            rebased,
            capturedSceneRevision: pendingRevision,
            origin: .restoreRebase,
            derivation: derivation
        )
        let forwardRefs = try EditProjectionEngine.requiredArtifactReferences(for: rebased)
        let inverseRefs = try EditProjectionEngine.requiredArtifactReferences(for: currentProjection)
        try requireLocallyAvailable(forwardRefs + inverseRefs, in: locallyAvailableArtifacts)

        let proposed = TransactionOperation.restoreSnapshot(
            entityID: currentScene.sceneID,
            before: beforeSnapshot,
            after: afterSnapshot,
            requiredArtifactRefs: forwardRefs
        )
        let freshInverseBefore = try EditProjectionEngine.snapshot(
            rebased,
            capturedSceneRevision: pendingRevision,
            origin: .capturedExact
        )
        let freshInverseAfter = try EditProjectionEngine.snapshot(
            currentProjection,
            capturedSceneRevision: currentScene.sceneRevision,
            origin: .capturedExact
        )
        let freshInverse = TransactionOperation.restoreSnapshot(
            entityID: currentScene.sceneID,
            before: freshInverseBefore,
            after: freshInverseAfter,
            requiredArtifactRefs: inverseRefs
        )
        let history = EditReference(
            contractTransactionID: request.transactionID,
            operation: .restore,
            committedSceneRevision: pendingRevision
        )
        let pendingScene = try EditProjectionEngine.apply(
            projection: rebased,
            to: currentScene,
            pendingRevision: pendingRevision,
            appending: history,
            updatedAtUTC: request.updatedAtUTC
        )
        return RestoreReduction(
            sourceTransactionID: source.transactionID,
            pendingScene: pendingScene,
            transaction: RestoreCompensatingTransaction(
                transactionID: request.transactionID,
                compensatesTransactionID: source.transactionID,
                baseSceneRevision: currentScene.sceneRevision,
                pendingSceneRevision: pendingRevision,
                proposedOperation: proposed,
                inverseOperation: freshInverse
            )
        )
    }

    private static func validateSourceEnvelope(
        _ source: TransactionRecord,
        currentScene: SceneState
    ) throws -> TransactionCommit {
        guard source.canonicalState == .committed,
              let commit = source.commit,
              commit.authorityID == source.revisionAuthority.authorityID,
              commit.revisionBranchID == source.revisionAuthority.revisionBranchID,
              commit.compareAndSwapBaseRevision == source.baseSceneRevision,
              commit.committedSceneRevision == source.baseSceneRevision + 1,
              commit.committedSceneRevision <= currentScene.sceneRevision,
              source.validation.state == "passed",
              source.transactionID != source.idempotencyKey,
              operationOrderMatchesIntent(source),
              source.intent.operation == .restore ? source.compensatesTransactionID != nil : source.compensatesTransactionID == nil,
              currentScene.editHistory.filter({ $0.transactionID == source.transactionID }) == [
                  EditReference(
                      contractTransactionID: source.transactionID,
                      operation: source.intent.operation,
                      committedSceneRevision: commit.committedSceneRevision
                  )
              ]
        else { throw RestoreRejection.sourceTransactionInvalid }
        return commit
    }

    private static func capturedInverse(
        from source: TransactionRecord,
        commit: TransactionCommit,
        currentProjection: EditProjection
    ) throws -> (before: EditProjectionSnapshot, after: EditProjectionSnapshot, requiredArtifactRefs: [ArtifactReference]) {
        guard let operations = source.inverseOperations,
              operations.count == 1,
              case .restoreSnapshot(let entityID, let before, let after, let refs) = operations[0],
              entityID == currentProjection.sceneID,
              before.projectionOrigin == "captured_exact",
              before.derivation == nil,
              after.projectionOrigin == "captured_exact",
              after.derivation == nil,
              before.capturedSceneRevision == commit.committedSceneRevision,
              after.capturedSceneRevision == source.baseSceneRevision
        else { throw RestoreRejection.inverseIntegrity }
        do {
            try EditProjectionEngine.validate(before)
            try EditProjectionEngine.validate(after)
            let currentIdentity = EditProjection(
                sceneID: currentProjection.sceneID,
                revisionBranchID: currentProjection.revisionBranchID,
                worldFrameID: currentProjection.worldFrameID,
                worldFrameVersion: currentProjection.worldFrameVersion,
                objectEditStates: before.projection.objectEditStates,
                placedAssets: before.projection.placedAssets,
                assetSupportRelations: before.projection.assetSupportRelations
            )
            guard currentIdentity == before.projection else { throw RestoreRejection.branchWorldMismatch }
            let afterIdentity = EditProjection(
                sceneID: currentProjection.sceneID,
                revisionBranchID: currentProjection.revisionBranchID,
                worldFrameID: currentProjection.worldFrameID,
                worldFrameVersion: currentProjection.worldFrameVersion,
                objectEditStates: after.projection.objectEditStates,
                placedAssets: after.projection.placedAssets,
                assetSupportRelations: after.projection.assetSupportRelations
            )
            guard afterIdentity == after.projection else { throw RestoreRejection.branchWorldMismatch }
        } catch let rejection as RestoreRejection {
            throw rejection
        } catch {
            throw RestoreRejection.inverseIntegrity
        }
        return (before, after, refs)
    }

    private static func verifyOperations(
        _ operations: [TransactionOperation],
        transactionID: String,
        pre: EditProjection,
        committed: EditProjection
    ) throws {
        var objects = Dictionary(uniqueKeysWithValues: pre.objectEditStates.map { ($0.objectID, $0) })
        var assets = Dictionary(uniqueKeysWithValues: pre.placedAssets.map { ($0.placedAssetID, $0) })
        var supports = Dictionary(uniqueKeysWithValues: pre.assetSupportRelations.map { ($0.relationID, $0) })

        for operation in operations {
            switch operation {
            case .createAssetInstance(let entityID, _, let after, let refs):
                guard assets[entityID] == nil,
                      supports[after.supportRelation.relationID] == nil,
                      refs == [after.manifestArtifactRef]
                else { throw RestoreRejection.touchedOperationMismatch }
                assets[entityID] = PlacedAsset(
                    contractPlacedAssetID: entityID,
                    assetID: after.assetID,
                    manifestArtifactRef: after.manifestArtifactRef,
                    worldFromAsset: after.worldFromAsset,
                    state: "committed",
                    supportRelationID: after.supportRelation.relationID,
                    sourceTransactionID: transactionID
                )
                supports[after.supportRelation.relationID] = SupportRelation(
                    contractRelationID: after.supportRelation.relationID,
                    subjectID: entityID,
                    surfaceID: after.supportRelation.surfaceID,
                    confidence: after.supportRelation.confidence,
                    method: after.supportRelation.method
                )
            case .setObjectVisibility(let entityID, let before, let after, let refs):
                guard var object = objects[entityID], object.visible == before.visible, refs?.isEmpty != false else {
                    throw RestoreRejection.touchedOperationMismatch
                }
                object = EditProjectionObjectState(contractObjectID: entityID, visible: after.visible, activeReveal: object.activeReveal)
                objects[entityID] = object
            case .setRevealBundle(let entityID, let before, let after, let refs):
                guard var object = objects[entityID], object.activeReveal == before else {
                    throw RestoreRejection.touchedOperationMismatch
                }
                if let after, !refs.contains(after) { throw RestoreRejection.touchedOperationMismatch }
                object = EditProjectionObjectState(contractObjectID: entityID, visible: object.visible, activeReveal: after)
                objects[entityID] = object
            case .restoreSnapshot(let entityID, let before, let after, let refs):
                guard entityID == pre.sceneID, before.projection == pre else {
                    throw RestoreRejection.touchedOperationMismatch
                }
                try EditProjectionEngine.verifyRequiredArtifactReferences(refs, for: after.projection)
                objects = Dictionary(uniqueKeysWithValues: after.projection.objectEditStates.map { ($0.objectID, $0) })
                assets = Dictionary(uniqueKeysWithValues: after.projection.placedAssets.map { ($0.placedAssetID, $0) })
                supports = Dictionary(uniqueKeysWithValues: after.projection.assetSupportRelations.map { ($0.relationID, $0) })
            case .setAssetTransform:
                throw RestoreRejection.touchedOperationMismatch
            }
        }
        let rebuilt = EditProjection(
            sceneID: pre.sceneID,
            revisionBranchID: pre.revisionBranchID,
            worldFrameID: pre.worldFrameID,
            worldFrameVersion: pre.worldFrameVersion,
            objectEditStates: objects.values.sorted { $0.objectID < $1.objectID },
            placedAssets: assets.values.sorted { $0.placedAssetID < $1.placedAssetID },
            assetSupportRelations: supports.values.sorted { $0.relationID < $1.relationID }
        )
        guard rebuilt == committed else { throw RestoreRejection.touchedOperationMismatch }
    }

    private static func requireLocallyAvailable(
        _ required: [ArtifactReference],
        in available: [ArtifactReference]
    ) throws {
        guard required.allSatisfy({ available.contains($0) }) else {
            throw RestoreRejection.missingRequiredArtifact
        }
    }

    private static func committedRevision(_ transaction: TransactionRecord) -> UInt64 {
        transaction.commit?.committedSceneRevision ?? 0
    }

    private static func operationOrderMatchesIntent(_ transaction: TransactionRecord) -> Bool {
        let kinds = transaction.proposedOperations.map { operation -> String in
            switch operation {
            case .createAssetInstance: "create_asset_instance"
            case .setAssetTransform: "set_asset_transform"
            case .setObjectVisibility: "set_object_visibility"
            case .setRevealBundle: "set_reveal_bundle"
            case .restoreSnapshot: "restore_snapshot"
            }
        }
        switch transaction.intent.operation {
        case .place:
            return kinds == ["create_asset_instance"]
        case .replace:
            return kinds == ["set_object_visibility", "create_asset_instance"] ||
                kinds == ["set_reveal_bundle", "set_object_visibility", "create_asset_instance"]
        case .remove:
            return kinds == ["set_reveal_bundle", "set_object_visibility"]
        case .restore:
            return kinds == ["restore_snapshot"]
        }
    }

    private static func validID(_ value: String, prefix: String) -> Bool {
        let uuid = "[0-9a-f]{8}-[0-9a-f]{4}-[47][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}"
        return value.range(of: "^\(NSRegularExpression.escapedPattern(for: prefix))\(uuid)$", options: .regularExpression) != nil
    }
}
