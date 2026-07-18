import Foundation
import ReRoomContracts

public enum ReplaceRejection: String, Error, Equatable, Sendable {
    case invalidReplaceProposal = "invalid_replace_proposal"
    case staleBaseRevision = "stale_base_revision"
    case authorityMismatch = "authority_mismatch"
    case worldMismatch = "world_mismatch"
    case targetMissing = "target_missing"
    case targetMismatch = "target_mismatch"
    case targetNotTracked = "target_not_tracked"
    case targetNotVisible = "target_not_visible"
    case capabilityNotReady = "capability_not_ready"
    case unsupportedView = "unsupported_view"
    case staleViewFixture = "stale_view_fixture"
    case missingSupport = "missing_support"
    case staleSupport = "stale_support"
    case assetNotAllowlisted = "asset_not_allowlisted"
    case collisionProxyFailed = "collision_proxy_failed"
    case assetLicenseFailed = "asset_license_failed"
    case artifactIntegrityFailed = "artifact_integrity_failed"
    case invalidDeterministicCandidate = "invalid_deterministic_candidate"
    case previewMismatch = "preview_mismatch"
    case confirmationMismatch = "confirmation_mismatch"
}

/// Complete deterministic policy output for the bounded no-reveal replacement path.
/// Intent bytes select only `asset.assetID`; every spatial and policy value lives here.
public struct DeterministicReplaceCandidate: Codable, Equatable, Sendable {
    public let asset: ProxyAssetCandidate
    public let support: DeterministicSupportCandidate?
    public let targetObjectID: String
    public let capabilityReadiness: String
    public let readinessSource: String
    public let supportedViewFixtureID: String
    public let supportedView: Bool
    public let capturedSceneRevision: UInt64
    public let worldFrameID: String
    public let worldFrameVersion: UInt64

    public init(
        asset: ProxyAssetCandidate,
        support: DeterministicSupportCandidate?,
        targetObjectID: String,
        capabilityReadiness: String,
        readinessSource: String,
        supportedViewFixtureID: String,
        supportedView: Bool,
        capturedSceneRevision: UInt64,
        worldFrameID: String,
        worldFrameVersion: UInt64
    ) {
        self.asset = asset
        self.support = support
        self.targetObjectID = targetObjectID
        self.capabilityReadiness = capabilityReadiness
        self.readinessSource = readinessSource
        self.supportedViewFixtureID = supportedViewFixtureID
        self.supportedView = supportedView
        self.capturedSceneRevision = capturedSceneRevision
        self.worldFrameID = worldFrameID
        self.worldFrameVersion = worldFrameVersion
    }
}

public struct ReplacePreviewReduction: Codable, Equatable, Sendable {
    public let proposal: BoundProposal
    public let candidate: DeterministicReplaceCandidate
    public let seed: PlacePreviewSeed
    public let validation: TransactionValidation
    public let preview: TransactionPreview
    public let proposedOperations: [TransactionOperation]
    public let canonicalSceneRevision: UInt64
    public let sourceProjection: EditProjection
    public let committedProjection: EditProjection
    public let networkReads: UInt64
}

public struct ReplaceCancellation: Codable, Equatable, Sendable {
    public let baseSceneRevision: UInt64
    public let canonicalSceneRevision: UInt64
    public let proposedOperations: [TransactionOperation]
}

public struct ReplaceConfirmationReduction: Codable, Equatable, Sendable {
    public let proposedOperations: [TransactionOperation]
    public let inverseOperation: TransactionOperation
    public let pendingSceneRevision: UInt64
    public let pendingScene: SceneState
    public let receiptCandidate: TransactionReceipt
    public let networkReads: UInt64
}

public enum ReplaceReducer {
    public static func preview(
        proposal: BoundProposal,
        currentScene: SceneState,
        candidate: DeterministicReplaceCandidate,
        seed: PlacePreviewSeed
    ) throws -> ReplacePreviewReduction {
        try validateContext(proposal, currentScene: currentScene)
        guard proposal.intent.operation == .replace,
              ["typed", "tap"].contains(proposal.intent.source),
              proposal.intent.arguments.assetID == candidate.asset.assetID,
              proposal.intent.arguments.catalogQuery == nil,
              validID(seed.transactionID, prefix: "tx_"),
              validID(seed.previewID, prefix: "preview_"),
              !seed.expiresAtUTC.isEmpty
        else { throw ReplaceRejection.invalidReplaceProposal }

        guard proposal.targetContext.selectedObjectID == candidate.targetObjectID,
              proposal.targetContext.candidateObjectIDs == [candidate.targetObjectID]
        else { throw ReplaceRejection.targetMismatch }
        guard let target = currentScene.objects.first(where: { $0.objectID == candidate.targetObjectID }) else {
            throw ReplaceRejection.targetMissing
        }
        guard target.lifecycle == "tracked" else { throw ReplaceRejection.targetNotTracked }
        guard target.editState.visible else { throw ReplaceRejection.targetNotVisible }
        guard ["ready", "degraded"].contains(target.readiness.replace),
              candidate.capabilityReadiness == "degraded",
              candidate.readinessSource == "manual_proxy_fallback"
        else { throw ReplaceRejection.capabilityNotReady }

        guard candidate.capturedSceneRevision == currentScene.sceneRevision else {
            throw ReplaceRejection.staleViewFixture
        }
        guard candidate.worldFrameID == currentScene.worldFrame.worldFrameID,
              candidate.worldFrameVersion == currentScene.worldFrame.worldFrameVersion
        else { throw ReplaceRejection.worldMismatch }
        guard candidate.supportedView else { throw ReplaceRejection.unsupportedView }

        guard candidate.asset.allowlisted else { throw ReplaceRejection.assetNotAllowlisted }
        guard candidate.asset.collisionProxyPassed else { throw ReplaceRejection.collisionProxyFailed }
        guard candidate.asset.assetLicensePassed else { throw ReplaceRejection.assetLicenseFailed }
        guard candidate.asset.artifactIntegrityPassed else { throw ReplaceRejection.artifactIntegrityFailed }
        guard let support = candidate.support else { throw ReplaceRejection.missingSupport }
        guard support.capturedSceneRevision == currentScene.sceneRevision else { throw ReplaceRejection.staleSupport }
        guard support.worldFrameID == currentScene.worldFrame.worldFrameID,
              support.worldFrameVersion == currentScene.worldFrame.worldFrameVersion
        else { throw ReplaceRejection.worldMismatch }
        guard currentScene.surfaces.contains(where: {
            $0.surfaceID == support.surfaceID && $0.lifecycle == "tracked"
        }) else { throw ReplaceRejection.missingSupport }
        try validateCandidate(candidate, scene: currentScene, transactionID: seed.transactionID)

        let replacement = AssetInstanceSnapshot(
            contractAssetID: candidate.asset.assetID,
            manifestArtifactRef: candidate.asset.manifestArtifactRef,
            worldFromAsset: support.worldFromAsset,
            supportRelation: AssetSupportSnapshot(
                contractRelationID: support.relationID,
                surfaceID: support.surfaceID,
                confidence: support.confidence,
                method: support.method
            )
        )
        let operations: [TransactionOperation] = [
            .setObjectVisibility(
                entityID: candidate.targetObjectID,
                before: VisibilitySnapshot(contractVisible: true),
                after: VisibilitySnapshot(contractVisible: false),
                requiredArtifactRefs: []
            ),
            .createAssetInstance(
                entityID: candidate.asset.placedAssetID,
                before: nil,
                after: replacement,
                requiredArtifactRefs: [candidate.asset.manifestArtifactRef]
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
            objects: replacingTarget(target, in: currentScene.objects),
            supportRelations: currentScene.supportRelations + [SupportRelation(
                contractRelationID: support.relationID,
                subjectID: candidate.asset.placedAssetID,
                surfaceID: support.surfaceID,
                confidence: support.confidence,
                method: support.method
            )],
            placedAssets: currentScene.placedAssets + [PlacedAsset(
                contractPlacedAssetID: candidate.asset.placedAssetID,
                assetID: candidate.asset.assetID,
                manifestArtifactRef: candidate.asset.manifestArtifactRef,
                worldFromAsset: support.worldFromAsset,
                state: "committed",
                supportRelationID: support.relationID,
                sourceTransactionID: seed.transactionID
            )],
            editHistory: currentScene.editHistory,
            updatedAtUTC: currentScene.updatedAtUTC
        )
        let committedProjection = try EditProjectionEngine.build(from: provisionalScene)
        let touched = try EditProjectionEngine.diff(
            sourceBefore: sourceProjection,
            sourceAfter: committedProjection
        )
        try EditProjectionEngine.verify(touched: touched, against: operations)

        let checks = validationChecks(scene: currentScene, candidate: candidate, support: support)
        let validation = TransactionValidation(
            contractState: "passed",
            checks: checks,
            validatorVersion: "RR-REPLACE-VALIDATOR-1",
            inputSHA256: try validationInputDigest(
                proposal: proposal,
                operations: operations,
                checks: checks
            )
        )
        return ReplacePreviewReduction(
            proposal: proposal,
            candidate: candidate,
            seed: seed,
            validation: validation,
            preview: TransactionPreview(
                contractPreviewID: seed.previewID,
                baseSceneRevision: currentScene.sceneRevision,
                expiresAtUTC: seed.expiresAtUTC,
                artifactRefs: [candidate.asset.manifestArtifactRef]
            ),
            proposedOperations: operations,
            canonicalSceneRevision: currentScene.sceneRevision,
            sourceProjection: sourceProjection,
            committedProjection: committedProjection,
            networkReads: 0
        )
    }

    public static func cancel(
        _ reduction: ReplacePreviewReduction,
        currentScene: SceneState
    ) throws -> ReplaceCancellation {
        let replay = try preview(
            proposal: reduction.proposal,
            currentScene: currentScene,
            candidate: reduction.candidate,
            seed: reduction.seed
        )
        guard replay == reduction else { throw ReplaceRejection.previewMismatch }
        return ReplaceCancellation(
            baseSceneRevision: reduction.preview.baseSceneRevision,
            canonicalSceneRevision: currentScene.sceneRevision,
            proposedOperations: []
        )
    }

    public static func confirm(
        _ reduction: ReplacePreviewReduction,
        currentScene: SceneState,
        confirmation: ExplicitConfirmation,
        request: PlaceConfirmationRequest
    ) throws -> ReplaceConfirmationReduction {
        let replay = try preview(
            proposal: reduction.proposal,
            currentScene: currentScene,
            candidate: reduction.candidate,
            seed: reduction.seed
        )
        guard replay == reduction else { throw ReplaceRejection.previewMismatch }
        guard confirmation.kind == "explicit_user_confirmation",
              validID(confirmation.actorID, prefix: "user_"),
              confirmation.source == "native_ui",
              confirmation.previewID == reduction.preview.previewID,
              validID(confirmation.confirmationEventID, prefix: "event_"),
              !confirmation.confirmedAtUTC.isEmpty,
              request.transactionID == reduction.seed.transactionID,
              validID(request.idempotencyKey, prefix: "txidem_"),
              !request.updatedAtUTC.isEmpty
        else { throw ReplaceRejection.confirmationMismatch }

        guard currentScene.sceneRevision < UInt64.max else {
            throw ReplaceRejection.invalidDeterministicCandidate
        }
        let pendingRevision = currentScene.sceneRevision + 1
        let pendingScene = try EditProjectionEngine.apply(
            projection: reduction.committedProjection,
            to: currentScene,
            pendingRevision: pendingRevision,
            appending: EditReference(
                contractTransactionID: request.transactionID,
                operation: .replace,
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
        return ReplaceConfirmationReduction(
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

    private static func validateContext(_ proposal: BoundProposal, currentScene: SceneState) throws {
        guard proposal.sessionID == currentScene.sessionID,
              proposal.revisionAuthority == currentScene.revisionAuthority,
              proposal.revisionAuthority.kind == .nativeDevice
        else { throw ReplaceRejection.authorityMismatch }
        guard proposal.baseSceneRevision == currentScene.sceneRevision,
              proposal.targetContext.capturedSceneRevision == currentScene.sceneRevision
        else { throw ReplaceRejection.staleBaseRevision }
        guard proposal.targetContext.worldFrameID == currentScene.worldFrame.worldFrameID,
              proposal.targetContext.worldFrameVersion == currentScene.worldFrame.worldFrameVersion
        else { throw ReplaceRejection.worldMismatch }
    }

    private static func validateCandidate(
        _ candidate: DeterministicReplaceCandidate,
        scene: SceneState,
        transactionID: String
    ) throws {
        guard validID(candidate.targetObjectID, prefix: "object_"),
              validID(candidate.supportedViewFixtureID, prefix: "envelope_"),
              validID(candidate.asset.assetID, prefix: "asset_"),
              validID(candidate.asset.placedAssetID, prefix: "assetinst_"),
              validID(transactionID, prefix: "tx_"),
              !scene.placedAssets.contains(where: {
                  $0.placedAssetID == candidate.asset.placedAssetID
              }),
              let support = candidate.support,
              validID(support.relationID, prefix: "support_"),
              !scene.supportRelations.contains(where: { $0.relationID == support.relationID }),
              support.confidence.isFinite,
              (0...1).contains(support.confidence),
              !support.method.isEmpty,
              support.worldFromAsset.values.count == 16,
              support.worldFromAsset.values.allSatisfy(\.isFinite)
        else { throw ReplaceRejection.invalidDeterministicCandidate }
    }

    private static func replacingTarget(
        _ target: SceneObject,
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
                editState: ObjectEditState(contractVisible: false, activeReveal: nil),
                createdSceneRevision: object.createdSceneRevision,
                lastObservedFrameID: object.lastObservedFrameID,
                rendererBinding: object.rendererBinding
            )
        }
    }

    private static func validationChecks(
        scene: SceneState,
        candidate: DeterministicReplaceCandidate,
        support: DeterministicSupportCandidate
    ) -> [ValidationCheck] {
        [
            ValidationCheck(
                contractCheckID: "scene_revision",
                result: "pass",
                measured: .number(Double(scene.sceneRevision)),
                threshold: .number(Double(scene.sceneRevision))
            ),
            ValidationCheck(
                contractCheckID: "artifact_integrity",
                result: "pass",
                measured: .boolean(candidate.asset.artifactIntegrityPassed),
                threshold: .boolean(true)
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
                measured: .string(candidate.capabilityReadiness),
                threshold: .string("degraded")
            ),
            ValidationCheck(
                contractCheckID: "view_envelope",
                result: "pass",
                measured: .string(candidate.supportedViewFixtureID),
                threshold: .string(candidate.supportedViewFixtureID)
            ),
            ValidationCheck(
                contractCheckID: "support",
                result: "pass",
                measured: .number(support.confidence),
                threshold: .number(0.5)
            ),
            ValidationCheck(
                contractCheckID: "collision_proxy",
                result: "pass",
                measured: .boolean(candidate.asset.collisionProxyPassed),
                threshold: .boolean(true)
            ),
            ValidationCheck(
                contractCheckID: "asset_license",
                result: "pass",
                measured: .boolean(candidate.asset.assetLicensePassed),
                threshold: .boolean(true)
            ),
        ]
    }

    private static func validationInputDigest(
        proposal: BoundProposal,
        operations: [TransactionOperation],
        checks: [ValidationCheck]
    ) throws -> String {
        let input = ReplaceValidationDigestInput(
            requestFingerprint: try TransactionFingerprint.digest(
                proposal: proposal,
                proposedOperations: operations
            ),
            checks: checks.map {
                ReplaceValidationDigestCheck(
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
        guard value.hasPrefix(prefix) else { return false }
        let suffix = String(value.dropFirst(prefix.count))
        return suffix.range(
            of: "^[0-9a-f]{8}-[0-9a-f]{4}-[47][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
            options: .regularExpression
        ) != nil
    }
}

private struct ReplaceValidationDigestInput: Codable {
    let requestFingerprint: String
    let checks: [ReplaceValidationDigestCheck]

    enum CodingKeys: String, CodingKey {
        case requestFingerprint = "request_fingerprint"
        case checks
    }
}

private struct ReplaceValidationDigestCheck: Codable {
    let checkID: String
    let measured: ValidationMeasurement
    let threshold: ValidationMeasurement

    enum CodingKeys: String, CodingKey {
        case checkID = "check_id"
        case measured
        case threshold
    }
}
