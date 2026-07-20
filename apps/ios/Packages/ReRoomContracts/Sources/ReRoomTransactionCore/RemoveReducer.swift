import Foundation
import ReRoomContracts

public enum RemoveRejection: String, Error, Equatable, Sendable {
    case invalidRemoveProposal = "invalid_remove_proposal"
    case staleBaseRevision = "stale_base_revision"
    case authorityMismatch = "authority_mismatch"
    case worldMismatch = "world_mismatch"
    case targetMissing = "target_missing"
    case targetMismatch = "target_mismatch"
    case targetNotTracked = "target_not_tracked"
    case targetNotVisible = "target_not_visible"
    case normalRemoveCapabilityPromoted = "normal_remove_capability_promoted"
    case capabilityNotDegradedFixture = "capability_not_degraded_fixture"
    case unsupportedView = "unsupported_view"
    case staleViewFixture = "stale_view_fixture"
    case artifactIntegrityFailed = "artifact_integrity_failed"
    case missingLocalArtifact = "missing_local_artifact"
    case invalidRevealArtifact = "invalid_reveal_artifact"
    case invalidDeterministicCandidate = "invalid_deterministic_candidate"
    case previewMismatch = "preview_mismatch"
    case confirmationMismatch = "confirmation_mismatch"
}

/// Deterministic policy output for the launch-gated degraded reveal fixture.
/// Intent bytes never provide these values and this type is not production reveal evidence.
public struct DeterministicRemoveCandidate: Codable, Equatable, Sendable {
    public let targetObjectID: String
    public let capabilityClassification: String
    public let validatorVersion: String
    public let poseEnvelopePolicy: String
    public let supportedViewEnvelopeID: String
    public let supportedView: Bool
    public let revealReference: ArtifactReference
    public let artifactIntegrityPassed: Bool
    public let artifactLocallyAvailable: Bool
    public let capturedSceneRevision: UInt64
    public let worldFrameID: String
    public let worldFrameVersion: UInt64

    public init(
        targetObjectID: String,
        capabilityClassification: String,
        validatorVersion: String,
        poseEnvelopePolicy: String,
        supportedViewEnvelopeID: String,
        supportedView: Bool,
        revealReference: ArtifactReference,
        artifactIntegrityPassed: Bool,
        artifactLocallyAvailable: Bool,
        capturedSceneRevision: UInt64,
        worldFrameID: String,
        worldFrameVersion: UInt64
    ) {
        self.targetObjectID = targetObjectID
        self.capabilityClassification = capabilityClassification
        self.validatorVersion = validatorVersion
        self.poseEnvelopePolicy = poseEnvelopePolicy
        self.supportedViewEnvelopeID = supportedViewEnvelopeID
        self.supportedView = supportedView
        self.revealReference = revealReference
        self.artifactIntegrityPassed = artifactIntegrityPassed
        self.artifactLocallyAvailable = artifactLocallyAvailable
        self.capturedSceneRevision = capturedSceneRevision
        self.worldFrameID = worldFrameID
        self.worldFrameVersion = worldFrameVersion
    }
}

public struct RemovePreviewSeed: Codable, Equatable, Sendable {
    public let transactionID: String
    public let previewID: String
    public let expiresAtUTC: String

    public init(transactionID: String, previewID: String, expiresAtUTC: String) {
        self.transactionID = transactionID
        self.previewID = previewID
        self.expiresAtUTC = expiresAtUTC
    }
}

public struct RemovePreviewReduction: Codable, Equatable, Sendable {
    public let proposal: BoundProposal
    public let candidate: DeterministicRemoveCandidate
    public let seed: RemovePreviewSeed
    public let validation: TransactionValidation
    public let preview: TransactionPreview
    public let proposedOperations: [TransactionOperation]
    public let canonicalSceneRevision: UInt64
    public let sourceProjection: EditProjection
    public let committedProjection: EditProjection
    public let networkReads: UInt64
}

public struct RemoveCancellation: Codable, Equatable, Sendable {
    public let baseSceneRevision: UInt64
    public let canonicalSceneRevision: UInt64
    public let proposedOperations: [TransactionOperation]
}

public struct RemoveConfirmationReduction: Codable, Equatable, Sendable {
    public let proposedOperations: [TransactionOperation]
    public let inverseOperation: TransactionOperation
    public let pendingSceneRevision: UInt64
    public let pendingScene: SceneState
    public let receiptCandidate: TransactionReceipt
    public let networkReads: UInt64
}

public enum RemoveReducer {
    private static let degradedClassification = "degraded_demo_fixture"
    private static let demoValidatorVersion = "RR-DEMO-REMOVE-VALIDATOR-1"
    private static let posePolicy = "deterministic_demo_pose_bound"

    public static func preview(
        proposal: BoundProposal,
        currentScene: SceneState,
        candidate: DeterministicRemoveCandidate,
        seed: RemovePreviewSeed
    ) throws -> RemovePreviewReduction {
        try validateContext(proposal, currentScene: currentScene)
        guard proposal.intent.operation == .remove,
              validIngress(proposal.intent),
              proposal.intent.arguments.assetID == nil,
              proposal.intent.arguments.catalogQuery == nil,
              proposal.intent.constraints.isEmpty,
              proposal.targetContext.artifactRefs.isEmpty,
              validID(seed.transactionID, prefix: "tx_"),
              validID(seed.previewID, prefix: "preview_"),
              !seed.expiresAtUTC.isEmpty
        else { throw RemoveRejection.invalidRemoveProposal }

        guard proposal.targetContext.selectedObjectID == candidate.targetObjectID,
              proposal.targetContext.candidateObjectIDs == [candidate.targetObjectID]
        else { throw RemoveRejection.targetMismatch }
        guard let target = currentScene.objects.first(where: {
            $0.objectID == candidate.targetObjectID
        }) else { throw RemoveRejection.targetMissing }
        guard target.lifecycle == "tracked" else { throw RemoveRejection.targetNotTracked }
        guard target.editState.visible, target.editState.activeReveal == nil else {
            throw RemoveRejection.targetNotVisible
        }

        // This reducer is deliberately unavailable to the normal ready product path.
        guard target.readiness.remove == "unavailable" else {
            throw RemoveRejection.normalRemoveCapabilityPromoted
        }
        guard candidate.capabilityClassification == degradedClassification,
              candidate.validatorVersion == demoValidatorVersion,
              candidate.poseEnvelopePolicy == posePolicy
        else { throw RemoveRejection.capabilityNotDegradedFixture }

        guard candidate.capturedSceneRevision == currentScene.sceneRevision else {
            throw RemoveRejection.staleViewFixture
        }
        guard candidate.worldFrameID == currentScene.worldFrame.worldFrameID,
              candidate.worldFrameVersion == currentScene.worldFrame.worldFrameVersion
        else { throw RemoveRejection.worldMismatch }
        guard candidate.supportedView else { throw RemoveRejection.unsupportedView }
        guard candidate.artifactIntegrityPassed else {
            throw RemoveRejection.artifactIntegrityFailed
        }
        guard candidate.artifactLocallyAvailable else {
            throw RemoveRejection.missingLocalArtifact
        }
        try validateCandidate(candidate)

        let operations: [TransactionOperation] = [
            .setRevealBundle(
                entityID: candidate.targetObjectID,
                before: nil,
                after: candidate.revealReference,
                requiredArtifactRefs: [candidate.revealReference]
            ),
            .setObjectVisibility(
                entityID: candidate.targetObjectID,
                before: VisibilitySnapshot(contractVisible: true),
                after: VisibilitySnapshot(contractVisible: false),
                requiredArtifactRefs: []
            ),
        ]

        let sourceProjection = try EditProjectionEngine.build(from: currentScene)
        let provisionalScene = SceneState(
            contractSchemaVersion: currentScene.schemaVersion,
            sessionID: currentScene.sessionID,
            sceneID: currentScene.sceneID,
            revisionAuthority: currentScene.revisionAuthority,
            sceneRevision: currentScene.sceneRevision,
            worldFrame: currentScene.worldFrame,
            surfaces: currentScene.surfaces,
            objects: removingTarget(
                target,
                reveal: candidate.revealReference,
                in: currentScene.objects
            ),
            supportRelations: currentScene.supportRelations,
            placedAssets: currentScene.placedAssets,
            editHistory: currentScene.editHistory,
            updatedAtUTC: currentScene.updatedAtUTC
        )
        let committedProjection = try EditProjectionEngine.build(from: provisionalScene)
        let touched = try EditProjectionEngine.diff(
            sourceBefore: sourceProjection,
            sourceAfter: committedProjection
        )
        try EditProjectionEngine.verify(touched: touched, against: operations)
        try EditProjectionEngine.verifyRequiredArtifactReferences(
            try EditProjectionEngine.requiredArtifactReferences(for: committedProjection),
            for: committedProjection
        )

        let checks = validationChecks(scene: currentScene, candidate: candidate)
        let validation = TransactionValidation(
            contractState: "passed",
            checks: checks,
            validatorVersion: demoValidatorVersion,
            inputSHA256: try validationInputDigest(
                proposal: proposal,
                operations: operations,
                checks: checks
            )
        )
        return RemovePreviewReduction(
            proposal: proposal,
            candidate: candidate,
            seed: seed,
            validation: validation,
            preview: TransactionPreview(
                contractPreviewID: seed.previewID,
                baseSceneRevision: currentScene.sceneRevision,
                expiresAtUTC: seed.expiresAtUTC,
                artifactRefs: [candidate.revealReference]
            ),
            proposedOperations: operations,
            canonicalSceneRevision: currentScene.sceneRevision,
            sourceProjection: sourceProjection,
            committedProjection: committedProjection,
            networkReads: 0
        )
    }

    private static func validIngress(_ intent: TransactionIntent) -> Bool {
        if ["typed", "tap"].contains(intent.source) { return true }
        guard intent.source == "voice", let model = intent.semanticModel else { return false }
        return model.provider == "openai"
            && !model.model.isEmpty
            && !model.responseID.isEmpty
    }

    public static func cancel(
        _ reduction: RemovePreviewReduction,
        currentScene: SceneState
    ) throws -> RemoveCancellation {
        let replay = try preview(
            proposal: reduction.proposal,
            currentScene: currentScene,
            candidate: reduction.candidate,
            seed: reduction.seed
        )
        guard replay == reduction else { throw RemoveRejection.previewMismatch }
        return RemoveCancellation(
            baseSceneRevision: reduction.preview.baseSceneRevision,
            canonicalSceneRevision: currentScene.sceneRevision,
            proposedOperations: []
        )
    }

    public static func confirm(
        _ reduction: RemovePreviewReduction,
        currentScene: SceneState,
        confirmation: ExplicitConfirmation,
        request: PlaceConfirmationRequest
    ) throws -> RemoveConfirmationReduction {
        let replay = try preview(
            proposal: reduction.proposal,
            currentScene: currentScene,
            candidate: reduction.candidate,
            seed: reduction.seed
        )
        guard replay == reduction else { throw RemoveRejection.previewMismatch }
        guard confirmation.kind == "explicit_user_confirmation",
              validID(confirmation.actorID, prefix: "user_"),
              confirmation.source == "native_ui",
              confirmation.previewID == reduction.preview.previewID,
              validID(confirmation.confirmationEventID, prefix: "event_"),
              !confirmation.confirmedAtUTC.isEmpty,
              request.transactionID == reduction.seed.transactionID,
              validID(request.idempotencyKey, prefix: "txidem_"),
              !request.updatedAtUTC.isEmpty
        else { throw RemoveRejection.confirmationMismatch }

        guard currentScene.sceneRevision < UInt64.max else {
            throw RemoveRejection.invalidDeterministicCandidate
        }
        let pendingRevision = currentScene.sceneRevision + 1
        let pendingScene = try EditProjectionEngine.apply(
            projection: reduction.committedProjection,
            to: currentScene,
            pendingRevision: pendingRevision,
            appending: EditReference(
                contractTransactionID: request.transactionID,
                operation: .remove,
                committedSceneRevision: pendingRevision
            ),
            updatedAtUTC: request.updatedAtUTC
        )
        let committedSnapshot = try EditProjectionEngine.snapshot(
            reduction.committedProjection,
            capturedSceneRevision: pendingRevision,
            origin: .capturedExact
        )
        let priorSnapshot = try EditProjectionEngine.snapshot(
            reduction.sourceProjection,
            capturedSceneRevision: currentScene.sceneRevision,
            origin: .capturedExact
        )
        let inverse = TransactionOperation.restoreSnapshot(
            entityID: currentScene.sceneID,
            before: committedSnapshot,
            after: priorSnapshot,
            requiredArtifactRefs: try EditProjectionEngine.requiredArtifactReferences(
                for: reduction.sourceProjection
            )
        )
        return RemoveConfirmationReduction(
            proposedOperations: reduction.proposedOperations,
            inverseOperation: inverse,
            pendingSceneRevision: pendingRevision,
            pendingScene: pendingScene,
            receiptCandidate: TransactionReceipt(
                contractTransactionID: request.transactionID,
                idempotencyKey: request.idempotencyKey,
                requestFingerprintSHA256: try TransactionFingerprint.digest(
                    proposal: reduction.proposal,
                    proposedOperations: reduction.proposedOperations
                ),
                revisionAuthority: currentScene.revisionAuthority,
                committedSceneRevision: pendingRevision,
                resultSHA256: try EditProjectionEngine.digest(reduction.committedProjection)
            ),
            networkReads: 0
        )
    }

    private static func validateContext(
        _ proposal: BoundProposal,
        currentScene: SceneState
    ) throws {
        guard proposal.sessionID == currentScene.sessionID,
              proposal.revisionAuthority == currentScene.revisionAuthority,
              proposal.revisionAuthority.kind == .nativeDevice
        else { throw RemoveRejection.authorityMismatch }
        guard proposal.baseSceneRevision == currentScene.sceneRevision,
              proposal.targetContext.capturedSceneRevision == currentScene.sceneRevision
        else { throw RemoveRejection.staleBaseRevision }
        guard proposal.targetContext.worldFrameID == currentScene.worldFrame.worldFrameID,
              proposal.targetContext.worldFrameVersion == currentScene.worldFrame.worldFrameVersion
        else { throw RemoveRejection.worldMismatch }
    }

    private static func validateCandidate(_ candidate: DeterministicRemoveCandidate) throws {
        guard validID(candidate.targetObjectID, prefix: "object_"),
              validID(candidate.supportedViewEnvelopeID, prefix: "envelope_")
        else { throw RemoveRejection.invalidDeterministicCandidate }
        guard validID(candidate.revealReference.artifactID, prefix: "artifact_"),
              candidate.revealReference.artifactType == "reveal_bundle",
              candidate.revealReference.artifactRevision > 0,
              candidate.revealReference.sha256.range(
                  of: "^[0-9a-f]{64}$",
                  options: .regularExpression
              ) != nil
        else { throw RemoveRejection.invalidRevealArtifact }
    }

    private static func removingTarget(
        _ target: SceneObject,
        reveal: ArtifactReference,
        in objects: [SceneObject]
    ) -> [SceneObject] {
        objects.map { object in
            guard object.objectID == target.objectID else { return object }
            return SceneObject(
                contractObjectID: object.objectID,
                label: object.label,
                labelConfidence: object.labelConfidence,
                attributes: object.attributes,
                lifecycle: object.lifecycle,
                readiness: object.readiness,
                readinessReasons: object.readinessReasons,
                artifactRefs: object.artifactRefs,
                editState: ObjectEditState(contractVisible: false, activeReveal: reveal),
                createdSceneRevision: object.createdSceneRevision,
                lastObservedFrameID: object.lastObservedFrameID,
                rendererBinding: object.rendererBinding
            )
        }
    }

    private static func validationChecks(
        scene: SceneState,
        candidate: DeterministicRemoveCandidate
    ) -> [ValidationCheck] {
        [
            ValidationCheck(
                contractCheckID: "scene_revision",
                result: "pass",
                measured: .number(Double(scene.sceneRevision)),
                threshold: .number(Double(scene.sceneRevision))
            ),
            ValidationCheck(
                contractCheckID: "target_exists",
                result: "pass",
                measured: .string(candidate.targetObjectID),
                threshold: .string(candidate.targetObjectID)
            ),
            ValidationCheck(
                contractCheckID: "capability_ready",
                result: "pass",
                measured: .string(degradedClassification),
                threshold: .string(degradedClassification)
            ),
            ValidationCheck(
                contractCheckID: "view_envelope",
                result: "pass",
                measured: .string(candidate.supportedViewEnvelopeID),
                threshold: .string(candidate.supportedViewEnvelopeID)
            ),
            ValidationCheck(
                contractCheckID: "artifact_integrity",
                result: "pass",
                measured: .boolean(candidate.artifactIntegrityPassed),
                threshold: .boolean(true)
            ),
        ]
    }

    private static func validationInputDigest(
        proposal: BoundProposal,
        operations: [TransactionOperation],
        checks: [ValidationCheck]
    ) throws -> String {
        let input = RemoveValidationDigestInput(
            requestFingerprint: try TransactionFingerprint.digest(
                proposal: proposal,
                proposedOperations: operations
            ),
            checks: checks.map {
                RemoveValidationDigestCheck(
                    checkID: $0.checkID,
                    measured: $0.measured,
                    threshold: $0.threshold
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try CanonicalJSON.digest(jsonData: encoder.encode(input))
    }

    private static func validID(_ value: String, prefix: String) -> Bool {
        let suffix = String(value.dropFirst(prefix.count))
        guard value.hasPrefix(prefix) else { return false }
        return suffix.range(
            of: "^[0-9a-f]{8}-[0-9a-f]{4}-[47][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
            options: .regularExpression
        ) != nil
    }
}

private struct RemoveValidationDigestInput: Codable {
    let requestFingerprint: String
    let checks: [RemoveValidationDigestCheck]

    enum CodingKeys: String, CodingKey {
        case requestFingerprint = "request_fingerprint"
        case checks
    }
}

private struct RemoveValidationDigestCheck: Codable {
    let checkID: String
    let measured: ValidationMeasurement
    let threshold: ValidationMeasurement

    enum CodingKeys: String, CodingKey {
        case checkID = "check_id"
        case measured
        case threshold
    }
}
