import Foundation
@testable import ReRoomTransactionCore
import Testing

@Suite("Exact degraded-fixture remove reducer")
struct RemoveReducerTests {
    @Test("preview emits reveal then visibility without mutating canonical state")
    func previewIsRevealFirstDeterministicAndRevisionNeutral() throws {
        let scene = RemoveFixtures.scene
        let before = try RemoveFixtures.encode(scene)

        let first = try RemoveReducer.preview(
            proposal: RemoveFixtures.proposal,
            currentScene: scene,
            candidate: RemoveFixtures.candidate,
            seed: RemoveFixtures.seed
        )
        let second = try RemoveReducer.preview(
            proposal: RemoveFixtures.proposal,
            currentScene: scene,
            candidate: RemoveFixtures.candidate,
            seed: RemoveFixtures.seed
        )

        #expect(try RemoveFixtures.encode(first) == RemoveFixtures.encode(second))
        #expect(first.preview.baseSceneRevision == scene.sceneRevision)
        #expect(first.canonicalSceneRevision == scene.sceneRevision)
        #expect(first.networkReads == 0)
        #expect(first.validation.state == "passed")
        #expect(first.validation.validatorVersion == "RR-DEMO-REMOVE-VALIDATOR-1")
        #expect(first.validation.checks.map(\.checkID) == [
            "scene_revision",
            "target_exists",
            "capability_ready",
            "view_envelope",
            "artifact_integrity",
        ])
        #expect(first.validation.checks.allSatisfy { $0.result == "pass" })
        let capability = try #require(first.validation.checks.first {
            $0.checkID == "capability_ready"
        })
        #expect(capability.measured == .string("degraded_demo_fixture"))
        #expect(capability.threshold == .string("degraded_demo_fixture"))
        let envelope = try #require(first.validation.checks.first {
            $0.checkID == "view_envelope"
        })
        #expect(envelope.measured == .string(RemoveFixtures.envelopeID))
        #expect(envelope.threshold == .string(RemoveFixtures.envelopeID))

        #expect(first.proposedOperations.count == 2)
        let reveal = try #require(first.proposedOperations.first?.revealChange)
        #expect(reveal.entityID == RemoveFixtures.targetObjectID)
        #expect(reveal.before == nil)
        #expect(reveal.after == RemoveFixtures.reveal)
        #expect(reveal.requiredArtifactRefs == [RemoveFixtures.reveal])

        let visibility = try #require(first.proposedOperations.last?.visibilityChange)
        #expect(visibility.entityID == RemoveFixtures.targetObjectID)
        #expect(visibility.before.visible)
        #expect(!visibility.after.visible)
        #expect(visibility.requiredArtifactRefs == [])
        #expect(first.preview.artifactRefs == [RemoveFixtures.reveal])

        let target = try #require(first.committedProjection.objectEditStates.first {
            $0.objectID == RemoveFixtures.targetObjectID
        })
        #expect(!target.visible)
        #expect(target.activeReveal == RemoveFixtures.reveal)
        #expect(try RemoveFixtures.encode(scene) == before)
        #expect(scene.sceneRevision == 12)
        #expect(scene.editHistory.isEmpty)

        let validationText = String(decoding: try RemoveFixtures.encode(first.validation), as: UTF8.self)
        for forbidden in ["coverage", "vote", "seam", "foreground", "observed_atlas", "provider", "physical_result", "gate_pass"] {
            #expect(!validationText.contains(forbidden))
        }
    }

    @Test(
        "target authority capability view artifact and proposal failures reject without mutation",
        arguments: RemoveFailureCase.allCases
    )
    func failuresAreNonDestructive(failure: RemoveFailureCase) throws {
        let scenario = RemoveFixtures.failureScenario(failure)
        let before = try RemoveFixtures.encode(scenario.scene)

        #expect(throws: failure.expected) {
            try RemoveReducer.preview(
                proposal: scenario.proposal,
                currentScene: scenario.scene,
                candidate: scenario.candidate,
                seed: RemoveFixtures.seed
            )
        }

        #expect(try RemoveFixtures.encode(scenario.scene) == before)
        #expect(scenario.scene.sceneRevision == 12)
        #expect(scenario.scene.editHistory.isEmpty)
    }

    @Test(
        "reordered incomplete added stale-before and artifact-union previews reject",
        arguments: RemovePreviewTamper.allCases
    )
    func tamperedPreviewRejects(tamper: RemovePreviewTamper) throws {
        let preview = try RemoveFixtures.preview()
        let operations = tamper.operations(from: preview.proposedOperations)
        let tampered = RemoveFixtures.replacingOperations(in: preview, with: operations)
        let before = try RemoveFixtures.encode(RemoveFixtures.scene)

        #expect(throws: RemoveRejection.previewMismatch) {
            try RemoveReducer.confirm(
                tampered,
                currentScene: RemoveFixtures.scene,
                confirmation: RemoveFixtures.confirmation,
                request: RemoveFixtures.confirmationRequest
            )
        }

        #expect(try RemoveFixtures.encode(RemoveFixtures.scene) == before)
    }

    @Test("cancel is neutral and confirmation creates one atomic revision plus captured-exact inverse")
    func cancelAndConfirmAreExact() throws {
        let scene = RemoveFixtures.scene
        let before = try RemoveFixtures.encode(scene)
        let preview = try RemoveFixtures.preview()

        let cancelled = try RemoveReducer.cancel(preview, currentScene: scene)
        #expect(cancelled.baseSceneRevision == scene.sceneRevision)
        #expect(cancelled.canonicalSceneRevision == scene.sceneRevision)
        #expect(cancelled.proposedOperations.isEmpty)
        #expect(try RemoveFixtures.encode(scene) == before)

        let confirmed = try RemoveReducer.confirm(
            preview,
            currentScene: scene,
            confirmation: RemoveFixtures.confirmation,
            request: RemoveFixtures.confirmationRequest
        )

        #expect(confirmed.proposedOperations == preview.proposedOperations)
        #expect(confirmed.pendingSceneRevision == scene.sceneRevision + 1)
        #expect(confirmed.pendingScene.sceneRevision == scene.sceneRevision + 1)
        #expect(confirmed.pendingScene.editHistory == [
            EditReference(
                contractTransactionID: RemoveFixtures.transactionID,
                operation: .remove,
                committedSceneRevision: scene.sceneRevision + 1
            ),
        ])
        let target = try #require(confirmed.pendingScene.objects.first {
            $0.objectID == RemoveFixtures.targetObjectID
        })
        #expect(!target.editState.visible)
        #expect(target.editState.activeReveal == RemoveFixtures.reveal)

        let inverse = try #require(confirmed.inverseOperation.restoreSnapshots)
        let source = try EditProjectionEngine.build(from: scene)
        let committed = try EditProjectionEngine.build(from: confirmed.pendingScene)
        #expect(inverse.before.projection == committed)
        #expect(inverse.before.capturedSceneRevision == scene.sceneRevision + 1)
        #expect(inverse.before.projectionOrigin == "captured_exact")
        #expect(inverse.after.projection == source)
        #expect(inverse.after.capturedSceneRevision == scene.sceneRevision)
        #expect(inverse.after.projectionOrigin == "captured_exact")
        #expect(inverse.requiredArtifactRefs == (try EditProjectionEngine.requiredArtifactReferences(for: source)))
        #expect(confirmed.receiptCandidate.committedSceneRevision == scene.sceneRevision + 1)
        #expect(try RemoveFixtures.encode(scene) == before)
    }

    @Test("confirmation replays current state and requires explicit native confirmation")
    func confirmationFailsClosed() throws {
        let preview = try RemoveFixtures.preview()
        let wrongPreview = ExplicitConfirmation(
            actorID: RemoveFixtures.userID,
            source: "native_ui",
            previewID: "preview_60000000-0000-4000-8000-000000000099",
            confirmationEventID: RemoveFixtures.eventID,
            confirmedAtUTC: "2026-07-18T20:01:00Z"
        )

        #expect(throws: RemoveRejection.confirmationMismatch) {
            try RemoveReducer.confirm(
                preview,
                currentScene: RemoveFixtures.scene,
                confirmation: wrongPreview,
                request: RemoveFixtures.confirmationRequest
            )
        }

        let hidden = RemoveFixtures.replacingTarget(in: RemoveFixtures.scene, visible: false)
        #expect(throws: RemoveRejection.targetNotVisible) {
            try RemoveReducer.confirm(
                preview,
                currentScene: hidden,
                confirmation: RemoveFixtures.confirmation,
                request: RemoveFixtures.confirmationRequest
            )
        }
    }
}

enum RemoveFailureCase: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case missingTarget
    case wrongSelectedTarget
    case ambiguousTarget
    case targetHidden
    case targetLost
    case normalRemoveReady
    case wrongClassification
    case wrongValidator
    case wrongPosePolicy
    case unsupportedView
    case staleViewFixture
    case invalidEnvelopeID
    case integrityFailure
    case localArtifactMissing
    case wrongArtifactType
    case invalidArtifactRevision
    case invalidArtifactDigest
    case worldMismatch
    case staleBase
    case wrongAuthority
    case wrongOperation
    case voiceSource
    case replaySource
    case intentAssetInjection
    case targetArtifactInjection

    var testDescription: String { rawValue }

    var expected: RemoveRejection {
        switch self {
        case .missingTarget: .targetMissing
        case .wrongSelectedTarget, .ambiguousTarget: .targetMismatch
        case .targetHidden: .targetNotVisible
        case .targetLost: .targetNotTracked
        case .normalRemoveReady: .normalRemoveCapabilityPromoted
        case .wrongClassification, .wrongValidator, .wrongPosePolicy: .capabilityNotDegradedFixture
        case .unsupportedView: .unsupportedView
        case .staleViewFixture: .staleViewFixture
        case .invalidEnvelopeID: .invalidDeterministicCandidate
        case .integrityFailure: .artifactIntegrityFailed
        case .localArtifactMissing: .missingLocalArtifact
        case .wrongArtifactType, .invalidArtifactRevision, .invalidArtifactDigest: .invalidRevealArtifact
        case .worldMismatch: .worldMismatch
        case .staleBase: .staleBaseRevision
        case .wrongAuthority: .authorityMismatch
        case .wrongOperation, .voiceSource, .replaySource, .intentAssetInjection, .targetArtifactInjection:
            .invalidRemoveProposal
        }
    }
}

enum RemovePreviewTamper: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case reversed
    case omitted
    case added
    case staleRevealBefore
    case staleVisibilityBefore
    case missingArtifactUnion
    case extraArtifactUnion

    var testDescription: String { rawValue }

    func operations(from valid: [TransactionOperation]) -> [TransactionOperation] {
        switch self {
        case .reversed:
            return valid.reversed()
        case .omitted:
            return [valid[0]]
        case .added:
            return valid + [valid[1]]
        case .staleRevealBefore:
            return [
                .setRevealBundle(
                    entityID: RemoveFixtures.targetObjectID,
                    before: RemoveFixtures.otherReveal,
                    after: RemoveFixtures.reveal,
                    requiredArtifactRefs: [RemoveFixtures.reveal]
                ),
                valid[1],
            ]
        case .staleVisibilityBefore:
            return [
                valid[0],
                .setObjectVisibility(
                    entityID: RemoveFixtures.targetObjectID,
                    before: VisibilitySnapshot(contractVisible: false),
                    after: VisibilitySnapshot(contractVisible: false),
                    requiredArtifactRefs: []
                ),
            ]
        case .missingArtifactUnion:
            return [
                .setRevealBundle(
                    entityID: RemoveFixtures.targetObjectID,
                    before: nil,
                    after: RemoveFixtures.reveal,
                    requiredArtifactRefs: []
                ),
                valid[1],
            ]
        case .extraArtifactUnion:
            return [
                .setRevealBundle(
                    entityID: RemoveFixtures.targetObjectID,
                    before: nil,
                    after: RemoveFixtures.reveal,
                    requiredArtifactRefs: [RemoveFixtures.reveal, TransactionTestFixtures.firstManifest]
                ),
                valid[1],
            ]
        }
    }
}

enum RemoveFixtures {
    static let transactionID = "tx_60000000-0000-4000-8000-000000000010"
    static let idempotencyKey = "txidem_60000000-0000-4000-8000-000000000011"
    static let previewID = "preview_60000000-0000-4000-8000-000000000012"
    static let envelopeID = "envelope_60000000-0000-4000-8000-000000000013"
    static let userID = "user_60000000-0000-4000-8000-000000000014"
    static let eventID = "event_60000000-0000-4000-8000-000000000015"
    static let targetObjectID = TransactionTestFixtures.objectIDs[0]
    static let otherObjectID = TransactionTestFixtures.objectIDs[1]
    static let reveal = ArtifactReference(
        artifactID: "artifact_60000000-0000-4000-8000-000000000016",
        artifactType: "reveal_bundle",
        artifactRevision: 1,
        sha256: String(repeating: "6", count: 64)
    )
    static let otherReveal = ArtifactReference(
        artifactID: "artifact_60000000-0000-4000-8000-000000000017",
        artifactType: "reveal_bundle",
        artifactRevision: 1,
        sha256: String(repeating: "7", count: 64)
    )
    static let scene = TransactionTestFixtures.scene(
        revision: 12,
        includeFirstAsset: false,
        readiness: "unavailable"
    )
    static let seed = PlacePreviewSeed(
        transactionID: transactionID,
        previewID: previewID,
        expiresAtUTC: "2026-07-18T21:00:00Z"
    )
    static let confirmation = ExplicitConfirmation(
        actorID: userID,
        source: "native_ui",
        previewID: previewID,
        confirmationEventID: eventID,
        confirmedAtUTC: "2026-07-18T20:01:00Z"
    )
    static let confirmationRequest = PlaceConfirmationRequest(
        transactionID: transactionID,
        idempotencyKey: idempotencyKey,
        updatedAtUTC: "2026-07-18T20:01:00Z"
    )

    static var proposal: BoundProposal { proposalValue() }

    static func proposalValue(
        baseRevision: UInt64 = 12,
        authority: RevisionAuthority? = nil,
        selectedObjectID: String? = targetObjectID,
        candidateObjectIDs: [String] = [targetObjectID],
        operation: ProductOperation = .remove,
        source: String = "tap",
        assetID: String? = nil,
        targetArtifactRefs: [ArtifactReference] = []
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
                artifactRefs: targetArtifactRefs
            ),
            intent: TransactionIntent(
                contractOperation: operation,
                source: source,
                arguments: IntentArguments(assetID: assetID, catalogQuery: nil),
                constraints: []
            )
        )
    }

    static var candidate: DeterministicRemoveCandidate { candidateValue() }

    static func candidateValue(
        targetObjectID: String = targetObjectID,
        capabilityClassification: String = "degraded_demo_fixture",
        validatorVersion: String = "RR-DEMO-REMOVE-VALIDATOR-1",
        poseEnvelopePolicy: String = "deterministic_demo_pose_bound",
        supportedView: Bool = true,
        supportedViewEnvelopeID: String = envelopeID,
        artifactIntegrityPassed: Bool = true,
        artifactLocallyAvailable: Bool = true,
        revealReference: ArtifactReference = reveal,
        capturedSceneRevision: UInt64 = 12,
        worldFrameID: String = TransactionTestFixtures.worldID
    ) -> DeterministicRemoveCandidate {
        DeterministicRemoveCandidate(
            targetObjectID: targetObjectID,
            capabilityClassification: capabilityClassification,
            validatorVersion: validatorVersion,
            poseEnvelopePolicy: poseEnvelopePolicy,
            supportedViewEnvelopeID: supportedViewEnvelopeID,
            supportedView: supportedView,
            revealReference: revealReference,
            artifactIntegrityPassed: artifactIntegrityPassed,
            artifactLocallyAvailable: artifactLocallyAvailable,
            capturedSceneRevision: capturedSceneRevision,
            worldFrameID: worldFrameID,
            worldFrameVersion: 1
        )
    }

    struct FailureScenario {
        let scene: SceneState
        let proposal: BoundProposal
        let candidate: DeterministicRemoveCandidate
    }

    static func failureScenario(_ failure: RemoveFailureCase) -> FailureScenario {
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
        case .normalRemoveReady:
            scenarioScene = replacingTarget(in: scene, removeReadiness: "ready")
        case .wrongClassification:
            scenarioCandidate = candidateValue(capabilityClassification: "ready")
        case .wrongValidator:
            scenarioCandidate = candidateValue(validatorVersion: "RR-REMOVE-VALIDATOR-1")
        case .wrongPosePolicy:
            scenarioCandidate = candidateValue(poseEnvelopePolicy: "measured_supported_view_envelope")
        case .unsupportedView:
            scenarioCandidate = candidateValue(supportedView: false)
        case .staleViewFixture:
            scenarioCandidate = candidateValue(capturedSceneRevision: 11)
        case .invalidEnvelopeID:
            scenarioCandidate = candidateValue(supportedViewEnvelopeID: "not-an-envelope")
        case .integrityFailure:
            scenarioCandidate = candidateValue(artifactIntegrityPassed: false)
        case .localArtifactMissing:
            scenarioCandidate = candidateValue(artifactLocallyAvailable: false)
        case .wrongArtifactType:
            scenarioCandidate = candidateValue(revealReference: ArtifactReference(
                artifactID: reveal.artifactID,
                artifactType: "asset_manifest",
                artifactRevision: reveal.artifactRevision,
                sha256: reveal.sha256
            ))
        case .invalidArtifactRevision:
            scenarioCandidate = candidateValue(revealReference: ArtifactReference(
                artifactID: reveal.artifactID,
                artifactType: reveal.artifactType,
                artifactRevision: 0,
                sha256: reveal.sha256
            ))
        case .invalidArtifactDigest:
            scenarioCandidate = candidateValue(revealReference: ArtifactReference(
                artifactID: reveal.artifactID,
                artifactType: reveal.artifactType,
                artifactRevision: reveal.artifactRevision,
                sha256: "invalid"
            ))
        case .worldMismatch:
            scenarioCandidate = candidateValue(worldFrameID: "world_60000000-0000-4000-8000-000000000018")
        case .staleBase:
            scenarioProposal = proposalValue(baseRevision: 11)
        case .wrongAuthority:
            scenarioProposal = proposalValue(authority: RevisionAuthority(
                kind: .nativeDevice,
                authorityID: "device_60000000-0000-4000-8000-000000000019",
                revisionBranchID: TransactionTestFixtures.branchID
            ))
        case .wrongOperation:
            scenarioProposal = proposalValue(operation: .replace)
        case .voiceSource:
            scenarioProposal = proposalValue(source: "voice")
        case .replaySource:
            scenarioProposal = proposalValue(source: "replay")
        case .intentAssetInjection:
            scenarioProposal = proposalValue(assetID: "asset_60000000-0000-4000-8000-000000000020")
        case .targetArtifactInjection:
            scenarioProposal = proposalValue(targetArtifactRefs: [reveal])
        }
        return FailureScenario(scene: scenarioScene, proposal: scenarioProposal, candidate: scenarioCandidate)
    }

    static func preview() throws -> RemovePreviewReduction {
        try RemoveReducer.preview(proposal: proposal, currentScene: scene, candidate: candidate, seed: seed)
    }

    static func replacingOperations(
        in reduction: RemovePreviewReduction,
        with operations: [TransactionOperation]
    ) -> RemovePreviewReduction {
        RemovePreviewReduction(
            proposal: reduction.proposal,
            candidate: reduction.candidate,
            seed: reduction.seed,
            validation: reduction.validation,
            preview: reduction.preview,
            proposedOperations: operations,
            canonicalSceneRevision: reduction.canonicalSceneRevision,
            sourceProjection: reduction.sourceProjection,
            committedProjection: reduction.committedProjection,
            networkReads: reduction.networkReads
        )
    }

    static func replacingTarget(
        in scene: SceneState,
        visible: Bool? = nil,
        lifecycle: String? = nil,
        removeReadiness: String? = nil
    ) -> SceneState {
        let objects = scene.objects.map { object in
            guard object.objectID == targetObjectID else { return object }
            return SceneObject(
                contractObjectID: object.objectID,
                label: object.label,
                labelConfidence: object.labelConfidence,
                attributes: object.attributes,
                lifecycle: lifecycle ?? object.lifecycle,
                readiness: Readiness(
                    contractSelect: object.readiness.select,
                    place: object.readiness.place,
                    replace: object.readiness.replace,
                    remove: removeReadiness ?? object.readiness.remove,
                    restore: object.readiness.restore
                ),
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
        SceneState(
            contractSchemaVersion: scene.schemaVersion,
            sessionID: scene.sessionID,
            sceneID: scene.sceneID,
            revisionAuthority: scene.revisionAuthority,
            sceneRevision: scene.sceneRevision,
            worldFrame: scene.worldFrame,
            surfaces: scene.surfaces,
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
    var revealChange: (
        entityID: String,
        before: ArtifactReference?,
        after: ArtifactReference?,
        requiredArtifactRefs: [ArtifactReference]
    )? {
        guard case .setRevealBundle(let entityID, let before, let after, let refs) = self else {
            return nil
        }
        return (entityID, before, after, refs)
    }

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

    var restoreSnapshots: (
        before: EditProjectionSnapshot,
        after: EditProjectionSnapshot,
        requiredArtifactRefs: [ArtifactReference]
    )? {
        guard case .restoreSnapshot(_, let before, let after, let refs) = self else { return nil }
        return (before, after, refs)
    }
}
