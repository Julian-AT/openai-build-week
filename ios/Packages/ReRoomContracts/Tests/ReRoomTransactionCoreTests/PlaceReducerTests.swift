import Foundation
@testable import ReRoomTransactionCore
import Testing

@Suite("Pure place preview and confirmation reducer")
struct PlaceReducerTests {
    @Test("valid support and allowlisted proxy produce a byte-stable noncanonical preview")
    func previewIsStableAndNonmutating() throws {
        let scene = PlaceFixtures.scene
        let before = try PlaceFixtures.encode(scene)

        let first = try PlaceReducer.preview(
            proposal: PlaceFixtures.proposal,
            currentScene: scene,
            candidate: PlaceFixtures.candidate,
            seed: PlaceFixtures.seed
        )
        let second = try PlaceReducer.preview(
            proposal: PlaceFixtures.proposal,
            currentScene: scene,
            candidate: PlaceFixtures.candidate,
            seed: PlaceFixtures.seed
        )

        #expect(try PlaceFixtures.encode(first) == PlaceFixtures.encode(second))
        #expect(first.preview.baseSceneRevision == scene.sceneRevision)
        #expect(first.preview.previewID == PlaceFixtures.previewID)
        #expect(first.validation.state == "passed")
        #expect(first.validation.checks.map(\.checkID) == [
            "scene_revision", "support", "collision_proxy", "asset_license", "artifact_integrity",
        ])
        #expect(first.validation.checks.allSatisfy { $0.result == "pass" })
        #expect(first.proposedOperations.count == 1)
        #expect(first.canonicalSceneRevision == scene.sceneRevision)
        #expect(first.networkReads == 0)
        #expect(try PlaceFixtures.encode(scene) == before)
        #expect(scene.editHistory.isEmpty)
    }

    @Test(
        "support asset revision world authority and policy failures reject without mutation",
        arguments: PlaceFailureCase.allCases
    )
    func failuresAreNonDestructive(failure: PlaceFailureCase) throws {
        let scenario = PlaceFixtures.failureScenario(failure)
        let before = try PlaceFixtures.encode(scenario.scene)
        #expect(throws: failure.expected) {
            try PlaceReducer.preview(
                proposal: scenario.proposal,
                currentScene: scenario.scene,
                candidate: scenario.candidate,
                seed: PlaceFixtures.seed
            )
        }
        #expect(try PlaceFixtures.encode(scenario.scene) == before)
        #expect(scenario.scene.editHistory.isEmpty)
    }

    @Test("cancel is revision-neutral and exact confirmation yields one pending place plus complete inverse")
    func cancelAndConfirm() throws {
        let scene = PlaceFixtures.scene
        let before = try PlaceFixtures.encode(scene)
        let preview = try PlaceFixtures.preview()

        let cancelled = try PlaceReducer.cancel(preview, currentScene: scene)
        #expect(cancelled.baseSceneRevision == scene.sceneRevision)
        #expect(cancelled.canonicalSceneRevision == scene.sceneRevision)
        #expect(cancelled.proposedOperations.isEmpty)
        #expect(try PlaceFixtures.encode(scene) == before)

        let confirmed = try PlaceReducer.confirm(
            preview,
            currentScene: scene,
            confirmation: PlaceFixtures.confirmation,
            request: PlaceFixtures.confirmationRequest
        )
        #expect(confirmed.proposedOperations.count == 1)
        let create = try #require(confirmed.proposedOperations.first?.createdAsset)
        #expect(create.entityID == PlaceFixtures.assetInstanceID)
        #expect(create.after.assetID == PlaceFixtures.assetID)
        #expect(create.after.worldFromAsset == PlaceFixtures.transform)
        #expect(create.after.supportRelation.relationID == PlaceFixtures.supportID)
        #expect(confirmed.pendingSceneRevision == scene.sceneRevision + 1)
        #expect(confirmed.pendingScene.sceneRevision == scene.sceneRevision + 1)
        #expect(confirmed.pendingScene.editHistory == [
            EditReference(contractTransactionID: PlaceFixtures.transactionID, operation: .place, committedSceneRevision: scene.sceneRevision + 1),
        ])
        #expect(confirmed.pendingScene.placedAssets.contains { $0.placedAssetID == PlaceFixtures.assetInstanceID })

        let inverse = try #require(confirmed.inverseOperation.restoreSnapshots)
        let pre = try EditProjectionEngine.build(from: scene)
        let committed = try EditProjectionEngine.build(from: confirmed.pendingScene)
        #expect(inverse.before.projection == committed)
        #expect(inverse.before.capturedSceneRevision == scene.sceneRevision + 1)
        #expect(inverse.before.projectionOrigin == "captured_exact")
        #expect(inverse.after.projection == pre)
        #expect(inverse.after.capturedSceneRevision == scene.sceneRevision)
        #expect(inverse.after.projectionOrigin == "captured_exact")
        #expect(inverse.requiredArtifactRefs == (try EditProjectionEngine.requiredArtifactReferences(for: pre)))
        #expect(confirmed.receiptCandidate.committedSceneRevision == scene.sceneRevision + 1)
        #expect(try PlaceFixtures.encode(scene) == before)
    }

    @Test("confirmation must be explicit native user input bound to the current preview")
    func invalidConfirmationRejects() throws {
        let scene = PlaceFixtures.scene
        let preview = try PlaceFixtures.preview()
        let before = try PlaceFixtures.encode(scene)
        let invalid = ExplicitConfirmation(
            contractKind: "explicit_user_confirmation",
            actorID: PlaceFixtures.userID,
            source: "native_ui",
            previewID: "preview_30000000-0000-4000-8000-000000000099",
            confirmationEventID: PlaceFixtures.eventID,
            confirmedAtUTC: "2026-07-18T17:01:00Z"
        )
        #expect(throws: PlaceRejection.confirmationMismatch) {
            try PlaceReducer.confirm(
                preview,
                currentScene: scene,
                confirmation: invalid,
                request: PlaceFixtures.confirmationRequest
            )
        }
        #expect(try PlaceFixtures.encode(scene) == before)
    }

    @Test("replace and remove remain typed context-bound proposals with readiness blockers")
    func unavailableOperationsHaveNoDelta() throws {
        for operation in [ProductOperation.replace, .remove] {
            let proposal = PlaceFixtures.proposal(operation: operation)
            let result = try PlaceReducer.deferUnavailable(proposal: proposal, currentScene: PlaceFixtures.scene)
            #expect(result.operation == operation)
            #expect(result.blocker == .capabilityNotReady)
            #expect(result.proposedOperations.isEmpty)
            #expect(result.baseSceneRevision == PlaceFixtures.scene.sceneRevision)
        }
        let restore = try PlaceReducer.deferUnavailable(
            proposal: PlaceFixtures.proposal(operation: .restore),
            currentScene: PlaceFixtures.scene
        )
        #expect(restore.blocker == .restoreSourceRequired)
        #expect(restore.proposedOperations.isEmpty)
    }
}

enum PlaceFailureCase: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case missingSupport
    case staleSupport
    case worldMismatch
    case collisionFailure
    case licenseFailure
    case integrityFailure
    case notAllowlisted
    case staleBase
    case wrongAuthority
    case wrongBranch

    var testDescription: String { rawValue }

    var expected: PlaceRejection {
        switch self {
        case .missingSupport: .missingSupport
        case .staleSupport: .staleSupport
        case .worldMismatch: .worldMismatch
        case .collisionFailure: .collisionProxyFailed
        case .licenseFailure: .assetLicenseFailed
        case .integrityFailure: .artifactIntegrityFailed
        case .notAllowlisted: .assetNotAllowlisted
        case .staleBase: .staleBaseRevision
        case .wrongAuthority, .wrongBranch: .authorityMismatch
        }
    }
}

enum PlaceFixtures {
    static let transactionID = "tx_30000000-0000-4000-8000-000000000010"
    static let idempotencyKey = "txidem_30000000-0000-4000-8000-000000000011"
    static let previewID = "preview_30000000-0000-4000-8000-000000000012"
    static let assetID = "asset_10000000-0000-4000-8000-000000000020"
    static let assetInstanceID = "assetinst_30000000-0000-4000-8000-000000000013"
    static let supportID = "support_30000000-0000-4000-8000-000000000014"
    static let userID = "user_30000000-0000-4000-8000-000000000015"
    static let eventID = "event_30000000-0000-4000-8000-000000000016"
    static let transform = Matrix4(values: [
        1, 0, 0, 0.25,
        0, 1, 0, 0,
        0, 0, 1, -0.5,
        0, 0, 0, 1,
    ])
    static let scene = TransactionTestFixtures.scene(revision: 8, includeFirstAsset: false)
    static let seed = PlacePreviewSeed(
        transactionID: transactionID,
        previewID: previewID,
        expiresAtUTC: "2026-07-18T18:00:00Z"
    )
    static let confirmation = ExplicitConfirmation(
        actorID: userID,
        source: "native_ui",
        previewID: previewID,
        confirmationEventID: eventID,
        confirmedAtUTC: "2026-07-18T17:01:00Z"
    )
    static let confirmationRequest = PlaceConfirmationRequest(
        transactionID: transactionID,
        idempotencyKey: idempotencyKey,
        updatedAtUTC: "2026-07-18T17:01:00Z"
    )

    static var proposal: BoundProposal { proposal(operation: .place) }

    static func proposal(
        operation: ProductOperation,
        baseRevision: UInt64 = 8,
        authority: RevisionAuthority? = nil
    ) -> BoundProposal {
        let target = TargetContext(
            contractCapturedAtFrameID: TransactionTestFixtures.frameID,
            capturedSceneRevision: baseRevision,
            worldFrameID: TransactionTestFixtures.worldID,
            worldFrameVersion: 1,
            cameraPose: TransactionTestFixtures.identity,
            screenPointEncodedPixels: [1, 1],
            candidateObjectIDs: TransactionTestFixtures.objectIDs,
            selectedObjectID: operation == .place ? nil : TransactionTestFixtures.objectIDs[0],
            artifactRefs: []
        )
        return BoundProposal(
            sessionID: TransactionTestFixtures.sessionID,
            revisionAuthority: authority ?? scene.revisionAuthority,
            baseSceneRevision: baseRevision,
            targetContext: target,
            intent: TransactionIntent(
                contractOperation: operation,
                source: "typed",
                arguments: operation == .place ? IntentArguments(assetID: assetID) : IntentArguments(),
                constraints: []
            )
        )
    }

    static var candidate: DeterministicPlaceCandidate {
        candidateValue()
    }

    static func candidateValue(
        support: DeterministicSupportCandidate? = supportCandidate(),
        collisionPassed: Bool = true,
        licensePassed: Bool = true,
        integrityPassed: Bool = true,
        allowlisted: Bool = true
    ) -> DeterministicPlaceCandidate {
        DeterministicPlaceCandidate(
            asset: ProxyAssetCandidate(
                assetID: assetID,
                placedAssetID: assetInstanceID,
                manifestArtifactRef: TransactionTestFixtures.firstManifest,
                allowlisted: allowlisted,
                collisionProxyPassed: collisionPassed,
                assetLicensePassed: licensePassed,
                artifactIntegrityPassed: integrityPassed
            ),
            support: support
        )
    }

    static func supportCandidate(
        capturedRevision: UInt64 = 8,
        worldFrameID: String = TransactionTestFixtures.worldID
    ) -> DeterministicSupportCandidate {
        DeterministicSupportCandidate(
            relationID: supportID,
            surfaceID: TransactionTestFixtures.surfaceID,
            worldFrameID: worldFrameID,
            worldFrameVersion: 1,
            capturedSceneRevision: capturedRevision,
            worldFromAsset: transform,
            confidence: 0.95,
            method: "arkit_plane"
        )
    }

    struct FailureScenario {
        let scene: SceneState
        let proposal: BoundProposal
        let candidate: DeterministicPlaceCandidate
    }

    static func failureScenario(_ failure: PlaceFailureCase) -> FailureScenario {
        var proposal = self.proposal
        var candidate = self.candidate
        switch failure {
        case .missingSupport: candidate = candidateValue(support: nil)
        case .staleSupport: candidate = candidateValue(support: supportCandidate(capturedRevision: 7))
        case .worldMismatch: candidate = candidateValue(support: supportCandidate(worldFrameID: "world_30000000-0000-4000-8000-000000000017"))
        case .collisionFailure: candidate = candidateValue(collisionPassed: false)
        case .licenseFailure: candidate = candidateValue(licensePassed: false)
        case .integrityFailure: candidate = candidateValue(integrityPassed: false)
        case .notAllowlisted: candidate = candidateValue(allowlisted: false)
        case .staleBase: proposal = self.proposal(operation: .place, baseRevision: 7)
        case .wrongAuthority:
            proposal = self.proposal(
                operation: .place,
                authority: RevisionAuthority(
                    kind: .nativeDevice,
                    authorityID: "device_30000000-0000-4000-8000-000000000018",
                    revisionBranchID: TransactionTestFixtures.branchID
                )
            )
        case .wrongBranch:
            proposal = self.proposal(
                operation: .place,
                authority: RevisionAuthority(
                    kind: .nativeDevice,
                    authorityID: TransactionTestFixtures.deviceID,
                    revisionBranchID: "branch_30000000-0000-4000-8000-000000000019"
                )
            )
        }
        return FailureScenario(scene: scene, proposal: proposal, candidate: candidate)
    }

    static func preview() throws -> PlacePreviewReduction {
        try PlaceReducer.preview(proposal: proposal, currentScene: scene, candidate: candidate, seed: seed)
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}

private extension TransactionOperation {
    var createdAsset: (entityID: String, after: AssetInstanceSnapshot)? {
        guard case .createAssetInstance(let entityID, _, let after, _) = self else { return nil }
        return (entityID, after)
    }

    var restoreSnapshots: (before: EditProjectionSnapshot, after: EditProjectionSnapshot, requiredArtifactRefs: [ArtifactReference])? {
        guard case .restoreSnapshot(_, let before, let after, let refs) = self else { return nil }
        return (before, after, refs)
    }
}
