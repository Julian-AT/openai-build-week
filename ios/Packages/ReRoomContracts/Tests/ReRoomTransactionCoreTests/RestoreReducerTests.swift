import Foundation
@testable import ReRoomTransactionCore
import Testing

@Suite("RR-RESTORE-REBASE-1")
struct RestoreReducerTests {
    @Test("latest eligible restore rebases only touched IDs and creates fresh immutable compensation")
    func offlineRestorePreservesCurrentCompleteState() throws {
        let source = try RestoreFixtures.sourceTransaction()
        let current = RestoreFixtures.currentScene()
        let sourceBytes = try RestoreFixtures.encode(source)
        let currentBytes = try RestoreFixtures.encode(current)

        let result = try RestoreReducer.reduce(
            currentScene: current,
            committedTransactions: [source],
            request: RestoreRequest(
                transactionID: RestoreFixtures.restoreTransactionID,
                compensatesTransactionID: source.transactionID,
                updatedAtUTC: "2026-07-18T16:00:00Z"
            ),
            locallyAvailableArtifacts: [TransactionTestFixtures.secondManifest]
        )

        #expect(result.networkReads == 0)
        #expect(result.transaction.transactionID == RestoreFixtures.restoreTransactionID)
        #expect(result.transaction.transactionID != source.transactionID)
        #expect(result.transaction.compensatesTransactionID == source.transactionID)
        #expect(result.transaction.baseSceneRevision == current.sceneRevision)
        #expect(result.transaction.pendingSceneRevision == current.sceneRevision + 1)
        #expect(result.pendingScene.sceneRevision == current.sceneRevision + 1)
        #expect(result.pendingScene.editHistory.last == EditReference(
            contractTransactionID: RestoreFixtures.restoreTransactionID,
            operation: .restore,
            committedSceneRevision: current.sceneRevision + 1
        ))

        let before = try #require(result.transaction.proposedOperation.restoreSnapshots?.before)
        let after = try #require(result.transaction.proposedOperation.restoreSnapshots?.after)
        #expect(before.projection == (try EditProjectionEngine.build(from: current)))
        #expect(before.projectionOrigin == "captured_exact")
        #expect(after.projectionOrigin == "restore_rebase")
        #expect(after.derivation?.sourceTransactionID == source.transactionID)
        #expect(after.derivation?.touchedPlacedAssetIDs == [TransactionTestFixtures.assetInstanceIDs[0]])
        #expect(after.derivation?.touchedAssetSupportRelationIDs == [TransactionTestFixtures.assetSupportIDs[0]])

        #expect(!result.pendingScene.placedAssets.map(\.placedAssetID).contains(TransactionTestFixtures.assetInstanceIDs[0]))
        #expect(result.pendingScene.placedAssets.map(\.placedAssetID).contains(TransactionTestFixtures.assetInstanceIDs[1]))
        let currentNewObject = try #require(current.objects.first { $0.objectID == TransactionTestFixtures.newObjectID })
        let restoredNewObject = try #require(result.pendingScene.objects.first { $0.objectID == TransactionTestFixtures.newObjectID })
        #expect(restoredNewObject == currentNewObject)
        #expect(result.pendingScene.surfaces == current.surfaces)
        #expect(result.pendingScene.objects.map(\.readiness) == current.objects.map(\.readiness))
        #expect(result.pendingScene.supportRelations.filter { !$0.subjectID.hasPrefix("assetinst_") } == current.supportRelations.filter { !$0.subjectID.hasPrefix("assetinst_") })

        let inverse = result.transaction.inverseOperation
        let inverseSnapshots = try #require(inverse.restoreSnapshots)
        #expect(inverseSnapshots.before.projectionOrigin == "captured_exact")
        #expect(inverseSnapshots.before.capturedSceneRevision == current.sceneRevision + 1)
        #expect(inverseSnapshots.after.projection == before.projection)
        #expect(inverseSnapshots.after.capturedSceneRevision == current.sceneRevision)

        #expect(try RestoreFixtures.encode(source) == sourceBytes)
        #expect(try RestoreFixtures.encode(current) == currentBytes)
    }

    @Test(
        "corruption, drift, eligibility, identity, and artifact failures are non-destructive",
        arguments: RestoreFailureCase.allCases
    )
    func failuresRejectWithoutMutation(failure: RestoreFailureCase) throws {
        let scenario = try RestoreFixtures.failureScenario(failure)
        let sceneBytes = try RestoreFixtures.encode(scenario.scene)
        let transactionBytes = try scenario.transactions.map(RestoreFixtures.encode)

        #expect(throws: failure.expectedError) {
            try RestoreReducer.reduce(
                currentScene: scenario.scene,
                committedTransactions: scenario.transactions,
                request: scenario.request,
                locallyAvailableArtifacts: scenario.availableArtifacts
            )
        }

        #expect(try RestoreFixtures.encode(scenario.scene) == sceneBytes)
        #expect(try scenario.transactions.map(RestoreFixtures.encode) == transactionBytes)
    }
}

enum RestoreFailureCase: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case touchedDrift
    case corruptInverseHash
    case wrongSource
    case laterEdit
    case priorCompensation
    case branchMismatch
    case missingArtifact
    case artifactUnionMismatch

    var testDescription: String { rawValue }

    var expectedError: RestoreRejection {
        switch self {
        case .touchedDrift: .unexpectedTouchedEntityDrift
        case .corruptInverseHash: .inverseIntegrity
        case .wrongSource: .noEligibleSource
        case .laterEdit: .sourceNotLatestEligible
        case .priorCompensation: .sourceAlreadyCompensated
        case .branchMismatch: .branchWorldMismatch
        case .missingArtifact: .missingRequiredArtifact
        case .artifactUnionMismatch: .artifactUnionMismatch
        }
    }
}

enum RestoreFixtures {
    static let restoreTransactionID = "tx_20000000-0000-4000-8000-000000000001"
    static let laterTransactionID = "tx_20000000-0000-4000-8000-000000000002"
    static let unknownTransactionID = "tx_20000000-0000-4000-8000-000000000003"
    static let idempotencyID = "txidem_20000000-0000-4000-8000-000000000004"
    static let previewID = "preview_20000000-0000-4000-8000-000000000005"
    static let userID = "user_20000000-0000-4000-8000-000000000006"
    static let eventID = "event_20000000-0000-4000-8000-000000000007"

    struct Scenario {
        let scene: SceneState
        let transactions: [TransactionRecord]
        let request: RestoreRequest
        let availableArtifacts: [ArtifactReference]
    }

    static func currentScene(firstAssetState: String = "committed") -> SceneState {
        let base = TransactionTestFixtures.scene(revision: 8, includeNewObject: true, readiness: "degraded")
        let projection = try! EditProjectionEngine.build(from: base)
        let adjusted = firstAssetState == "committed"
            ? projection
            : TransactionTestFixtures.replacingFirstAssetState(in: projection, state: firstAssetState)
        let assets = adjusted.placedAssets
        let assetSupports = adjusted.assetSupportRelations
        let nonAssetSupports = base.supportRelations.filter { !$0.subjectID.hasPrefix("assetinst_") }
        return SceneState(
            contractSchemaVersion: base.schemaVersion,
            sessionID: base.sessionID,
            sceneID: base.sceneID,
            revisionAuthority: base.revisionAuthority,
            sceneRevision: base.sceneRevision,
            worldFrame: base.worldFrame,
            surfaces: base.surfaces,
            objects: base.objects,
            supportRelations: nonAssetSupports + assetSupports,
            placedAssets: assets,
            editHistory: [EditReference(contractTransactionID: TransactionTestFixtures.transactionIDs[0], operation: .place, committedSceneRevision: 4)],
            updatedAtUTC: base.updatedAtUTC
        )
    }

    static func sourceTransaction(
        transactionID: String = TransactionTestFixtures.transactionIDs[0],
        branchID: String = TransactionTestFixtures.branchID,
        committedRevision: UInt64 = 4,
        compensates: String? = nil,
        corruptHash: Bool = false,
        artifactRefs: [ArtifactReference]? = nil
    ) throws -> TransactionRecord {
        let pre = try EditProjectionEngine.build(from: TransactionTestFixtures.scene(revision: 3, includeFirstAsset: false))
        let committed = try EditProjectionEngine.build(from: TransactionTestFixtures.scene(revision: 4))
        var before = try EditProjectionEngine.snapshot(committed, capturedSceneRevision: committedRevision, origin: .capturedExact)
        if corruptHash {
            before = EditProjectionSnapshot(
                contractCapturedSceneRevision: before.capturedSceneRevision,
                projectionOrigin: before.projectionOrigin,
                derivation: nil,
                projectionSHA256: String(repeating: "f", count: 64),
                projection: before.projection
            )
        }
        let after = try EditProjectionEngine.snapshot(pre, capturedSceneRevision: committedRevision - 1, origin: .capturedExact)
        let inverse = TransactionOperation.restoreSnapshot(
            entityID: TransactionTestFixtures.sceneID,
            before: before,
            after: after,
            requiredArtifactRefs: artifactRefs ?? [TransactionTestFixtures.secondManifest]
        )
        let authority = RevisionAuthority(kind: .nativeDevice, authorityID: TransactionTestFixtures.deviceID, revisionBranchID: branchID)
        let operation: ProductOperation = compensates == nil ? .place : .restore
        return TransactionRecord(
            transactionID: transactionID,
            idempotencyKey: idempotencyID,
            requestFingerprintSHA256: String(repeating: "3", count: 64),
            sessionID: TransactionTestFixtures.sessionID,
            revisionAuthority: authority,
            baseSceneRevision: committedRevision - 1,
            targetContext: TargetContext(
                contractCapturedAtFrameID: TransactionTestFixtures.frameID,
                capturedSceneRevision: committedRevision - 1,
                worldFrameID: TransactionTestFixtures.worldID,
                worldFrameVersion: 1,
                cameraPose: TransactionTestFixtures.identity,
                screenPointEncodedPixels: [1, 1],
                candidateObjectIDs: [],
                selectedObjectID: nil,
                artifactRefs: []
            ),
            intent: TransactionIntent(contractOperation: operation, source: "typed", arguments: IntentArguments(), constraints: []),
            proposedOperations: compensates == nil ? [TransactionTestFixtures.createFirstAssetOperation()] : [inverse],
            validation: TransactionValidation(
                contractState: "passed",
                checks: [],
                validatorVersion: "test",
                inputSHA256: String(repeating: "4", count: 64)
            ),
            preview: TransactionPreview(contractPreviewID: previewID, baseSceneRevision: committedRevision - 1, expiresAtUTC: "2026-07-18T17:00:00Z", artifactRefs: []),
            commit: TransactionCommit(
                contractAuthorityID: TransactionTestFixtures.deviceID,
                revisionBranchID: branchID,
                compareAndSwapBaseRevision: committedRevision - 1,
                committedSceneRevision: committedRevision,
                confirmation: ExplicitConfirmation(actorID: userID, source: "native_ui", previewID: previewID, confirmationEventID: eventID, confirmedAtUTC: "2026-07-18T15:00:00Z"),
                committedAtUTC: "2026-07-18T15:00:00Z",
                resultSHA256: String(repeating: "5", count: 64)
            ),
            inverseOperations: [inverse],
            localUndoToken: "undo_20000000-0000-4000-8000-000000000008",
            compensatesTransactionID: compensates,
            canonicalState: .committed,
            syncState: .localOnly,
            createdAtUTC: "2026-07-18T15:00:00Z"
        )
    }

    static func failureScenario(_ failure: RestoreFailureCase) throws -> Scenario {
        var scene = currentScene()
        var source = try sourceTransaction()
        var transactions = [source]
        var requestedSource = source.transactionID
        var available = [TransactionTestFixtures.secondManifest]

        switch failure {
        case .touchedDrift:
            scene = currentScene(firstAssetState: "hidden")
        case .corruptInverseHash:
            source = try sourceTransaction(corruptHash: true)
            transactions = [source]
        case .wrongSource:
            requestedSource = unknownTransactionID
        case .laterEdit:
            transactions.append(try sourceTransaction(transactionID: laterTransactionID, committedRevision: 5))
        case .priorCompensation:
            transactions.append(try sourceTransaction(transactionID: laterTransactionID, committedRevision: 5, compensates: source.transactionID))
        case .branchMismatch:
            source = try sourceTransaction(branchID: "branch_20000000-0000-4000-8000-000000000009")
            transactions = [source]
        case .missingArtifact:
            available = []
        case .artifactUnionMismatch:
            source = try sourceTransaction(artifactRefs: [])
            transactions = [source]
        }

        return Scenario(
            scene: scene,
            transactions: transactions,
            request: RestoreRequest(
                transactionID: restoreTransactionID,
                compensatesTransactionID: requestedSource,
                updatedAtUTC: "2026-07-18T16:00:00Z"
            ),
            availableArtifacts: available
        )
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}

private extension TransactionOperation {
    var restoreSnapshots: (before: EditProjectionSnapshot, after: EditProjectionSnapshot)? {
        guard case .restoreSnapshot(_, let before, let after, _) = self else { return nil }
        return (before, after)
    }
}
