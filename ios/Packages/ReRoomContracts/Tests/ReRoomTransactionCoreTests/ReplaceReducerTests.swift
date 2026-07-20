import Foundation
@testable import ReRoomTransactionCore
import Testing

@Suite("Pure no-reveal replace preview and confirmation reducer")
struct ReplaceReducerTests {
    @Test("valid local fallback emits visibility then asset creation without mutating revision")
    func previewIsOrderedStableAndNonmutating() throws {
        let scene = ReplaceFixtures.scene
        let before = try ReplaceFixtures.encode(scene)

        let first = try ReplaceReducer.preview(
            proposal: ReplaceFixtures.proposal,
            currentScene: scene,
            candidate: ReplaceFixtures.candidate,
            seed: ReplaceFixtures.seed
        )
        let second = try ReplaceReducer.preview(
            proposal: ReplaceFixtures.proposal,
            currentScene: scene,
            candidate: ReplaceFixtures.candidate,
            seed: ReplaceFixtures.seed
        )

        #expect(try ReplaceFixtures.encode(first) == ReplaceFixtures.encode(second))
        #expect(first.preview.baseSceneRevision == scene.sceneRevision)
        #expect(first.canonicalSceneRevision == scene.sceneRevision)
        #expect(first.networkReads == 0)
        #expect(first.validation.state == "passed")
        #expect(first.validation.checks.map(\.checkID) == [
            "scene_revision",
            "artifact_integrity",
            "target_exists",
            "capability_ready",
            "view_envelope",
            "support",
            "collision_proxy",
            "asset_license",
        ])
        #expect(first.validation.checks.allSatisfy { $0.result == "pass" })
        #expect(first.proposedOperations.count == 2)

        let visibility = try #require(first.proposedOperations.first?.visibilityChange)
        #expect(visibility.entityID == ReplaceFixtures.targetObjectID)
        #expect(visibility.before.visible)
        #expect(!visibility.after.visible)
        #expect(visibility.requiredArtifactRefs == [])

        let create = try #require(first.proposedOperations.last?.createdAsset)
        #expect(create.entityID == ReplaceFixtures.assetInstanceID)
        #expect(create.after.assetID == ReplaceFixtures.assetID)
        #expect(create.after.worldFromAsset == ReplaceFixtures.transform)
        #expect(create.after.supportRelation.relationID == ReplaceFixtures.assetSupportID)
        #expect(create.requiredArtifactRefs == [TransactionTestFixtures.firstManifest])

        let target = try #require(first.committedProjection.objectEditStates.first {
            $0.objectID == ReplaceFixtures.targetObjectID
        })
        #expect(!target.visible)
        #expect(target.activeReveal == nil)
        #expect(first.committedProjection.placedAssets.contains {
            $0.placedAssetID == ReplaceFixtures.assetInstanceID
        })
        #expect(try ReplaceFixtures.encode(scene) == before)
        #expect(scene.sceneRevision == 8)
        #expect(scene.editHistory.isEmpty)
    }

    @Test("model-attributed voice uses the same deterministic replacement preview")
    func modelAttributedVoicePreview() throws {
        let proposal = ReplaceFixtures.proposalValue(
            source: "voice",
            semanticModel: ReplaceFixtures.semanticModel
        )
        let preview = try ReplaceReducer.preview(
            proposal: proposal,
            currentScene: ReplaceFixtures.scene,
            candidate: ReplaceFixtures.candidate,
            seed: ReplaceFixtures.seed
        )
        #expect(preview.proposal.intent.source == "voice")
        #expect(preview.proposal.intent.semanticModel == ReplaceFixtures.semanticModel)
        #expect(preview.canonicalSceneRevision == ReplaceFixtures.scene.sceneRevision)
    }

    @Test(
        "target visibility readiness view support asset world and revision failures reject atomically",
        arguments: ReplaceFailureCase.allCases
    )
    func failuresAreNonDestructive(failure: ReplaceFailureCase) throws {
        let scenario = ReplaceFixtures.failureScenario(failure)
        let before = try ReplaceFixtures.encode(scenario.scene)

        #expect(throws: failure.expected) {
            try ReplaceReducer.preview(
                proposal: scenario.proposal,
                currentScene: scenario.scene,
                candidate: scenario.candidate,
                seed: ReplaceFixtures.seed
            )
        }

        #expect(try ReplaceFixtures.encode(scenario.scene) == before)
        #expect(scenario.scene.sceneRevision == 8)
        #expect(scenario.scene.editHistory.isEmpty)
    }

    @Test("cancel is neutral and explicit confirmation creates one replace revision plus exact inverse")
    func cancelAndConfirm() throws {
        let scene = ReplaceFixtures.scene
        let before = try ReplaceFixtures.encode(scene)
        let preview = try ReplaceFixtures.preview()

        let cancelled = try ReplaceReducer.cancel(preview, currentScene: scene)
        #expect(cancelled.baseSceneRevision == scene.sceneRevision)
        #expect(cancelled.canonicalSceneRevision == scene.sceneRevision)
        #expect(cancelled.proposedOperations.isEmpty)
        #expect(try ReplaceFixtures.encode(scene) == before)

        let confirmed = try ReplaceReducer.confirm(
            preview,
            currentScene: scene,
            confirmation: ReplaceFixtures.confirmation,
            request: ReplaceFixtures.confirmationRequest
        )

        #expect(confirmed.proposedOperations == preview.proposedOperations)
        #expect(confirmed.pendingSceneRevision == scene.sceneRevision + 1)
        #expect(confirmed.pendingScene.sceneRevision == scene.sceneRevision + 1)
        #expect(confirmed.pendingScene.editHistory == [
            EditReference(
                contractTransactionID: ReplaceFixtures.transactionID,
                operation: .replace,
                committedSceneRevision: scene.sceneRevision + 1
            ),
        ])
        let pendingTarget = try #require(confirmed.pendingScene.objects.first {
            $0.objectID == ReplaceFixtures.targetObjectID
        })
        #expect(!pendingTarget.editState.visible)
        #expect(pendingTarget.editState.activeReveal == nil)
        #expect(confirmed.pendingScene.placedAssets.contains {
            $0.placedAssetID == ReplaceFixtures.assetInstanceID
        })
        #expect(confirmed.pendingScene.supportRelations.contains {
            $0.relationID == ReplaceFixtures.assetSupportID &&
                $0.subjectID == ReplaceFixtures.assetInstanceID
        })

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
        #expect(try ReplaceFixtures.encode(scene) == before)
    }

    @Test("confirmation must replay current state and remain bound to explicit native input")
    func confirmationFailsClosed() throws {
        let scene = ReplaceFixtures.scene
        let preview = try ReplaceFixtures.preview()
        let before = try ReplaceFixtures.encode(scene)
        let wrongPreview = ExplicitConfirmation(
            actorID: ReplaceFixtures.userID,
            source: "native_ui",
            previewID: "preview_50000000-0000-4000-8000-000000000099",
            confirmationEventID: ReplaceFixtures.eventID,
            confirmedAtUTC: "2026-07-18T19:01:00Z"
        )

        #expect(throws: ReplaceRejection.confirmationMismatch) {
            try ReplaceReducer.confirm(
                preview,
                currentScene: scene,
                confirmation: wrongPreview,
                request: ReplaceFixtures.confirmationRequest
            )
        }

        let hiddenScene = ReplaceFixtures.replacingTarget(in: scene, visible: false)
        #expect(throws: ReplaceRejection.targetNotVisible) {
            try ReplaceReducer.confirm(
                preview,
                currentScene: hiddenScene,
                confirmation: ReplaceFixtures.confirmation,
                request: ReplaceFixtures.confirmationRequest
            )
        }
        #expect(try ReplaceFixtures.encode(scene) == before)
    }
}

enum ReplaceFailureCase: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case missingTarget
    case wrongSelectedTarget
    case ambiguousTarget
    case targetHidden
    case targetLost
    case capabilityUnavailable
    case unsupportedView
    case staleViewFixture
    case missingSupport
    case staleSupport
    case missingSurface
    case assetNotAllowlisted
    case collisionFailure
    case licenseFailure
    case integrityFailure
    case worldMismatch
    case staleBase
    case wrongAuthority
    case wrongAssetIntent
    case catalogIntent

    var testDescription: String { rawValue }

    var expected: ReplaceRejection {
        switch self {
        case .missingTarget: .targetMissing
        case .wrongSelectedTarget, .ambiguousTarget: .targetMismatch
        case .targetHidden: .targetNotVisible
        case .targetLost: .targetNotTracked
        case .capabilityUnavailable: .capabilityNotReady
        case .unsupportedView: .unsupportedView
        case .staleViewFixture: .staleViewFixture
        case .missingSupport, .missingSurface: .missingSupport
        case .staleSupport: .staleSupport
        case .assetNotAllowlisted: .assetNotAllowlisted
        case .collisionFailure: .collisionProxyFailed
        case .licenseFailure: .assetLicenseFailed
        case .integrityFailure: .artifactIntegrityFailed
        case .worldMismatch: .worldMismatch
        case .staleBase: .staleBaseRevision
        case .wrongAuthority: .authorityMismatch
        case .wrongAssetIntent, .catalogIntent: .invalidReplaceProposal
        }
    }
}

enum ReplaceFixtures {
    static let transactionID = "tx_50000000-0000-4000-8000-000000000010"
    static let idempotencyKey = "txidem_50000000-0000-4000-8000-000000000011"
    static let previewID = "preview_50000000-0000-4000-8000-000000000012"
    static let assetID = "asset_50000000-0000-4000-8000-000000000013"
    static let assetInstanceID = "assetinst_50000000-0000-4000-8000-000000000014"
    static let assetSupportID = "support_50000000-0000-4000-8000-000000000015"
    static let viewFixtureID = "envelope_50000000-0000-4000-8000-000000000016"
    static let userID = "user_50000000-0000-4000-8000-000000000017"
    static let eventID = "event_50000000-0000-4000-8000-000000000018"
    static let targetObjectID = TransactionTestFixtures.objectIDs[0]
    static let otherObjectID = TransactionTestFixtures.objectIDs[1]
    static let transform = Matrix4(values: [
        1, 0, 0, 0.20,
        0, 1, 0, 0,
        0, 0, 1, -0.45,
        0, 0, 0, 1,
    ])
    static let scene = TransactionTestFixtures.scene(revision: 8, includeFirstAsset: false)
    static let seed = PlacePreviewSeed(
        transactionID: transactionID,
        previewID: previewID,
        expiresAtUTC: "2026-07-18T20:00:00Z"
    )
    static let confirmation = ExplicitConfirmation(
        actorID: userID,
        source: "native_ui",
        previewID: previewID,
        confirmationEventID: eventID,
        confirmedAtUTC: "2026-07-18T19:01:00Z"
    )
    static let confirmationRequest = PlaceConfirmationRequest(
        transactionID: transactionID,
        idempotencyKey: idempotencyKey,
        updatedAtUTC: "2026-07-18T19:01:00Z"
    )

    static var proposal: BoundProposal { proposalValue() }

    static func proposalValue(
        baseRevision: UInt64 = 8,
        authority: RevisionAuthority? = nil,
        selectedObjectID: String? = targetObjectID,
        candidateObjectIDs: [String] = [targetObjectID],
        assetID: String? = assetID,
        catalogQuery: String? = nil,
        source: String = "typed",
        semanticModel: SemanticModelReference? = nil
    ) -> BoundProposal {
        BoundProposal(
            sessionID: TransactionTestFixtures.sessionID,
            revisionAuthority: authority ?? scene.revisionAuthority,
            baseSceneRevision: baseRevision,
            targetContext: TargetContext(
                contractCapturedAtFrameID: TransactionTestFixtures.frameID,
                capturedSceneRevision: baseRevision,
                worldFrameID: TransactionTestFixtures.worldID,
                worldFrameVersion: 1,
                cameraPose: TransactionTestFixtures.identity,
                screenPointEncodedPixels: [120, 220],
                candidateObjectIDs: candidateObjectIDs,
                selectedObjectID: selectedObjectID,
                artifactRefs: []
            ),
            intent: TransactionIntent(
                contractOperation: .replace,
                source: source,
                arguments: IntentArguments(assetID: assetID, catalogQuery: catalogQuery),
                constraints: [],
                semanticModel: semanticModel
            )
        )
    }

    static let semanticModel = SemanticModelReference(
        contractProvider: "openai",
        model: "gpt-5.6-sol",
        responseID: "resp_50000000-0000-4000-8000-000000000099"
    )

    static var candidate: DeterministicReplaceCandidate { candidateValue() }

    static func candidateValue(
        targetObjectID: String = targetObjectID,
        capabilityReadiness: String = "degraded",
        supportedView: Bool = true,
        capturedSceneRevision: UInt64 = 8,
        worldFrameID: String = TransactionTestFixtures.worldID,
        support: DeterministicSupportCandidate? = supportCandidate(),
        allowlisted: Bool = true,
        collisionPassed: Bool = true,
        licensePassed: Bool = true,
        integrityPassed: Bool = true
    ) -> DeterministicReplaceCandidate {
        DeterministicReplaceCandidate(
            asset: ProxyAssetCandidate(
                assetID: assetID,
                placedAssetID: assetInstanceID,
                manifestArtifactRef: TransactionTestFixtures.firstManifest,
                allowlisted: allowlisted,
                collisionProxyPassed: collisionPassed,
                assetLicensePassed: licensePassed,
                artifactIntegrityPassed: integrityPassed
            ),
            support: support,
            targetObjectID: targetObjectID,
            capabilityReadiness: capabilityReadiness,
            readinessSource: "manual_proxy_fallback",
            supportedViewFixtureID: viewFixtureID,
            supportedView: supportedView,
            capturedSceneRevision: capturedSceneRevision,
            worldFrameID: worldFrameID,
            worldFrameVersion: 1
        )
    }

    static func supportCandidate(capturedRevision: UInt64 = 8) -> DeterministicSupportCandidate {
        DeterministicSupportCandidate(
            relationID: assetSupportID,
            surfaceID: TransactionTestFixtures.surfaceID,
            worldFrameID: TransactionTestFixtures.worldID,
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
        let candidate: DeterministicReplaceCandidate
    }

    static func failureScenario(_ failure: ReplaceFailureCase) -> FailureScenario {
        var scenarioScene = scene
        var scenarioProposal = proposal
        var scenarioCandidate = candidate
        switch failure {
        case .missingTarget:
            scenarioScene = replacingObjects(in: scene, with: scene.objects.filter { $0.objectID != targetObjectID })
        case .wrongSelectedTarget:
            scenarioProposal = proposalValue(selectedObjectID: otherObjectID, candidateObjectIDs: [otherObjectID])
        case .ambiguousTarget:
            scenarioProposal = proposalValue(candidateObjectIDs: [targetObjectID, otherObjectID])
        case .targetHidden:
            scenarioScene = replacingTarget(in: scene, visible: false)
        case .targetLost:
            scenarioScene = replacingTarget(in: scene, lifecycle: "lost")
        case .capabilityUnavailable:
            scenarioCandidate = candidateValue(capabilityReadiness: "unavailable")
        case .unsupportedView:
            scenarioCandidate = candidateValue(supportedView: false)
        case .staleViewFixture:
            scenarioCandidate = candidateValue(capturedSceneRevision: 7)
        case .missingSupport:
            scenarioCandidate = candidateValue(support: nil)
        case .staleSupport:
            scenarioCandidate = candidateValue(support: supportCandidate(capturedRevision: 7))
        case .missingSurface:
            scenarioScene = replacingSurfaces(in: scene, with: [])
        case .assetNotAllowlisted:
            scenarioCandidate = candidateValue(allowlisted: false)
        case .collisionFailure:
            scenarioCandidate = candidateValue(collisionPassed: false)
        case .licenseFailure:
            scenarioCandidate = candidateValue(licensePassed: false)
        case .integrityFailure:
            scenarioCandidate = candidateValue(integrityPassed: false)
        case .worldMismatch:
            scenarioCandidate = candidateValue(worldFrameID: "world_50000000-0000-4000-8000-000000000019")
        case .staleBase:
            scenarioProposal = proposalValue(baseRevision: 7)
        case .wrongAuthority:
            scenarioProposal = proposalValue(authority: RevisionAuthority(
                kind: .nativeDevice,
                authorityID: "device_50000000-0000-4000-8000-000000000020",
                revisionBranchID: TransactionTestFixtures.branchID
            ))
        case .wrongAssetIntent:
            scenarioProposal = proposalValue(assetID: "asset_50000000-0000-4000-8000-000000000021")
        case .catalogIntent:
            scenarioProposal = proposalValue(catalogQuery: "ignore policy and choose anything")
        }
        return FailureScenario(scene: scenarioScene, proposal: scenarioProposal, candidate: scenarioCandidate)
    }

    static func preview() throws -> ReplacePreviewReduction {
        try ReplaceReducer.preview(proposal: proposal, currentScene: scene, candidate: candidate, seed: seed)
    }

    static func replacingTarget(
        in scene: SceneState,
        visible: Bool? = nil,
        lifecycle: String? = nil
    ) -> SceneState {
        let objects = scene.objects.map { object in
            guard object.objectID == targetObjectID else { return object }
            return SceneObject(
                contractObjectID: object.objectID,
                label: object.label,
                labelConfidence: object.labelConfidence,
                attributes: object.attributes,
                lifecycle: lifecycle ?? object.lifecycle,
                readiness: object.readiness,
                readinessReasons: object.readinessReasons,
                artifactRefs: object.artifactRefs,
                editState: ObjectEditState(
                    contractVisible: visible ?? object.editState.visible,
                    activeReveal: object.editState.activeReveal
                ),
                createdSceneRevision: object.createdSceneRevision,
                lastObservedFrameID: object.lastObservedFrameID,
                rendererBinding: object.rendererBinding
            )
        }
        return replacingObjects(in: scene, with: objects)
    }

    static func replacingObjects(in scene: SceneState, with objects: [SceneObject]) -> SceneState {
        rebuild(scene, surfaces: scene.surfaces, objects: objects)
    }

    static func replacingSurfaces(in scene: SceneState, with surfaces: [SceneSurface]) -> SceneState {
        rebuild(scene, surfaces: surfaces, objects: scene.objects)
    }

    private static func rebuild(
        _ scene: SceneState,
        surfaces: [SceneSurface],
        objects: [SceneObject]
    ) -> SceneState {
        SceneState(
            contractSchemaVersion: scene.schemaVersion,
            sessionID: scene.sessionID,
            sceneID: scene.sceneID,
            revisionAuthority: scene.revisionAuthority,
            sceneRevision: scene.sceneRevision,
            worldFrame: scene.worldFrame,
            surfaces: surfaces,
            objects: objects,
            supportRelations: scene.supportRelations,
            placedAssets: scene.placedAssets,
            editHistory: scene.editHistory,
            updatedAtUTC: scene.updatedAtUTC
        )
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}

private extension TransactionOperation {
    var visibilityChange: (
        entityID: String,
        before: VisibilitySnapshot,
        after: VisibilitySnapshot,
        requiredArtifactRefs: [ArtifactReference]?
    )? {
        guard case .setObjectVisibility(let entityID, let before, let after, let refs) = self else {
            return nil
        }
        return (entityID, before, after, refs)
    }

    var createdAsset: (
        entityID: String,
        after: AssetInstanceSnapshot,
        requiredArtifactRefs: [ArtifactReference]
    )? {
        guard case .createAssetInstance(let entityID, _, let after, let refs) = self else {
            return nil
        }
        return (entityID, after, refs)
    }

    var restoreSnapshots: (
        before: EditProjectionSnapshot,
        after: EditProjectionSnapshot,
        requiredArtifactRefs: [ArtifactReference]
    )? {
        guard case .restoreSnapshot(_, let before, let after, let refs) = self else { return nil }
        return (before, after, refs)
    }
}
