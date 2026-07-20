import Foundation
import ReRoomContracts

public enum PlaceRejection: String, Error, Equatable, Sendable {
    case invalidPlaceProposal = "invalid_place_proposal"
    case staleBaseRevision = "stale_base_revision"
    case authorityMismatch = "authority_mismatch"
    case worldMismatch = "world_mismatch"
    case missingSupport = "missing_support"
    case staleSupport = "stale_support"
    case assetNotAllowlisted = "asset_not_allowlisted"
    case collisionProxyFailed = "collision_proxy_failed"
    case assetLicenseFailed = "asset_license_failed"
    case artifactIntegrityFailed = "artifact_integrity_failed"
    case invalidDeterministicCandidate = "invalid_deterministic_candidate"
    case previewMismatch = "preview_mismatch"
    case confirmationMismatch = "confirmation_mismatch"
    case unsupportedOperation = "unsupported_operation"
}

/// Asset policy output supplied by deterministic local code, never by intent bytes.
public struct ProxyAssetCandidate: Codable, Equatable, Sendable {
    public let assetID: String
    public let placedAssetID: String
    public let manifestArtifactRef: ArtifactReference
    public let allowlisted: Bool
    public let collisionProxyPassed: Bool
    public let assetLicensePassed: Bool
    public let artifactIntegrityPassed: Bool

    public init(
        assetID: String,
        placedAssetID: String,
        manifestArtifactRef: ArtifactReference,
        allowlisted: Bool,
        collisionProxyPassed: Bool,
        assetLicensePassed: Bool,
        artifactIntegrityPassed: Bool
    ) {
        self.assetID = assetID
        self.placedAssetID = placedAssetID
        self.manifestArtifactRef = manifestArtifactRef
        self.allowlisted = allowlisted
        self.collisionProxyPassed = collisionProxyPassed
        self.assetLicensePassed = assetLicensePassed
        self.artifactIntegrityPassed = artifactIntegrityPassed
    }
}

/// Spatial output supplied by deterministic support/world code, never by intent bytes.
public struct DeterministicSupportCandidate: Codable, Equatable, Sendable {
    public let relationID: String
    public let surfaceID: String
    public let worldFrameID: String
    public let worldFrameVersion: UInt64
    public let capturedSceneRevision: UInt64
    public let worldFromAsset: Matrix4
    public let confidence: Double
    public let method: String

    public init(
        relationID: String,
        surfaceID: String,
        worldFrameID: String,
        worldFrameVersion: UInt64,
        capturedSceneRevision: UInt64,
        worldFromAsset: Matrix4,
        confidence: Double,
        method: String
    ) {
        self.relationID = relationID
        self.surfaceID = surfaceID
        self.worldFrameID = worldFrameID
        self.worldFrameVersion = worldFrameVersion
        self.capturedSceneRevision = capturedSceneRevision
        self.worldFromAsset = worldFromAsset
        self.confidence = confidence
        self.method = method
    }
}

public struct DeterministicPlaceCandidate: Codable, Equatable, Sendable {
    public let asset: ProxyAssetCandidate
    public let support: DeterministicSupportCandidate?

    public init(asset: ProxyAssetCandidate, support: DeterministicSupportCandidate?) {
        self.asset = asset
        self.support = support
    }
}

/// IDs and expiry are supplied by the local transaction coordinator so reducer replay is stable.
public struct PlacePreviewSeed: Codable, Equatable, Sendable {
    public let transactionID: String
    public let previewID: String
    public let expiresAtUTC: String

    public init(transactionID: String, previewID: String, expiresAtUTC: String) {
        self.transactionID = transactionID
        self.previewID = previewID
        self.expiresAtUTC = expiresAtUTC
    }
}

public struct PlaceConfirmationRequest: Codable, Equatable, Sendable {
    public let transactionID: String
    public let idempotencyKey: String
    public let updatedAtUTC: String

    public init(transactionID: String, idempotencyKey: String, updatedAtUTC: String) {
        self.transactionID = transactionID
        self.idempotencyKey = idempotencyKey
        self.updatedAtUTC = updatedAtUTC
    }
}

public struct PlacePreviewReduction: Codable, Equatable, Sendable {
    public let proposal: BoundProposal
    public let candidate: DeterministicPlaceCandidate
    public let seed: PlacePreviewSeed
    public let validation: TransactionValidation
    public let preview: TransactionPreview
    public let proposedOperations: [TransactionOperation]
    public let canonicalSceneRevision: UInt64
    public let sourceProjection: EditProjection
    public let committedProjection: EditProjection
    public let networkReads: UInt64
}

public struct PlaceCancellation: Codable, Equatable, Sendable {
    public let baseSceneRevision: UInt64
    public let canonicalSceneRevision: UInt64
    public let proposedOperations: [TransactionOperation]
}

public struct PlaceConfirmationReduction: Codable, Equatable, Sendable {
    public let proposedOperations: [TransactionOperation]
    public let inverseOperation: TransactionOperation
    public let pendingSceneRevision: UInt64
    public let pendingScene: SceneState
    public let receiptCandidate: TransactionReceipt
    public let networkReads: UInt64
}

public enum PlaceReadinessBlocker: String, Codable, Equatable, Sendable {
    case capabilityNotReady = "capability_not_ready"
    case restoreSourceRequired = "restore_source_required"
}

public struct DeferredOperationProposal: Codable, Equatable, Sendable {
    public let operation: ProductOperation
    public let blocker: PlaceReadinessBlocker
    public let proposedOperations: [TransactionOperation]
    public let baseSceneRevision: UInt64
}

public enum PlaceReducer {
    public static func preview(
        proposal: BoundProposal,
        currentScene: SceneState,
        candidate: DeterministicPlaceCandidate,
        seed: PlacePreviewSeed
    ) throws -> PlacePreviewReduction {
        try validateContext(proposal, currentScene: currentScene)
        guard proposal.intent.operation == .place,
              validIngress(proposal.intent),
              proposal.intent.arguments.assetID == candidate.asset.assetID,
              proposal.intent.arguments.catalogQuery == nil,
              proposal.targetContext.selectedObjectID == nil,
              validID(seed.transactionID, prefix: "tx_"),
              validID(seed.previewID, prefix: "preview_"),
              !seed.expiresAtUTC.isEmpty
        else { throw PlaceRejection.invalidPlaceProposal }

        guard candidate.asset.allowlisted else { throw PlaceRejection.assetNotAllowlisted }
        guard candidate.asset.collisionProxyPassed else { throw PlaceRejection.collisionProxyFailed }
        guard candidate.asset.assetLicensePassed else { throw PlaceRejection.assetLicenseFailed }
        guard candidate.asset.artifactIntegrityPassed else { throw PlaceRejection.artifactIntegrityFailed }
        guard let support = candidate.support else { throw PlaceRejection.missingSupport }
        guard support.capturedSceneRevision == currentScene.sceneRevision else { throw PlaceRejection.staleSupport }
        guard support.worldFrameID == currentScene.worldFrame.worldFrameID,
              support.worldFrameVersion == currentScene.worldFrame.worldFrameVersion
        else { throw PlaceRejection.worldMismatch }
        guard currentScene.surfaces.contains(where: { $0.surfaceID == support.surfaceID && $0.lifecycle == "tracked" }) else {
            throw PlaceRejection.missingSupport
        }
        try validateCandidate(candidate, scene: currentScene, transactionID: seed.transactionID)

        let snapshot = AssetInstanceSnapshot(
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
        let operation = TransactionOperation.createAssetInstance(
            entityID: candidate.asset.placedAssetID,
            before: nil,
            after: snapshot,
            requiredArtifactRefs: [candidate.asset.manifestArtifactRef]
        )
        let operations = [operation]

        let sourceProjection = try EditProjectionEngine.build(from: currentScene)
        let provisionalScene = SceneState(
            contractSchemaVersion: currentScene.schemaVersion,
            sessionID: currentScene.sessionID,
            sceneID: currentScene.sceneID,
            revisionAuthority: currentScene.revisionAuthority,
            sceneRevision: currentScene.sceneRevision,
            worldFrame: currentScene.worldFrame,
            surfaces: currentScene.surfaces,
            objects: currentScene.objects,
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
        let touched = try EditProjectionEngine.diff(sourceBefore: sourceProjection, sourceAfter: committedProjection)
        try EditProjectionEngine.verify(touched: touched, against: operations)

        let checks = validationChecks(scene: currentScene, candidate: candidate, support: support)
        let validation = TransactionValidation(
            contractState: "passed",
            checks: checks,
            validatorVersion: "RR-PLACE-VALIDATOR-1",
            inputSHA256: try validationInputDigest(proposal: proposal, operations: operations, checks: checks)
        )
        return PlacePreviewReduction(
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

    private static func validIngress(_ intent: TransactionIntent) -> Bool {
        if ["typed", "tap"].contains(intent.source) { return true }
        guard intent.source == "voice", let model = intent.semanticModel else { return false }
        return model.provider == "openai"
            && !model.model.isEmpty
            && !model.responseID.isEmpty
    }

    public static func cancel(
        _ reduction: PlacePreviewReduction,
        currentScene: SceneState
    ) throws -> PlaceCancellation {
        let replay = try preview(
            proposal: reduction.proposal,
            currentScene: currentScene,
            candidate: reduction.candidate,
            seed: reduction.seed
        )
        guard replay == reduction else { throw PlaceRejection.previewMismatch }
        return PlaceCancellation(
            baseSceneRevision: reduction.preview.baseSceneRevision,
            canonicalSceneRevision: currentScene.sceneRevision,
            proposedOperations: []
        )
    }

    public static func confirm(
        _ reduction: PlacePreviewReduction,
        currentScene: SceneState,
        confirmation: ExplicitConfirmation,
        request: PlaceConfirmationRequest
    ) throws -> PlaceConfirmationReduction {
        let replay = try preview(
            proposal: reduction.proposal,
            currentScene: currentScene,
            candidate: reduction.candidate,
            seed: reduction.seed
        )
        guard replay == reduction else { throw PlaceRejection.previewMismatch }
        guard confirmation.kind == "explicit_user_confirmation",
              validID(confirmation.actorID, prefix: "user_"),
              confirmation.source == "native_ui",
              confirmation.previewID == reduction.preview.previewID,
              validID(confirmation.confirmationEventID, prefix: "event_"),
              !confirmation.confirmedAtUTC.isEmpty,
              request.transactionID == reduction.seed.transactionID,
              validID(request.idempotencyKey, prefix: "txidem_"),
              !request.updatedAtUTC.isEmpty
        else { throw PlaceRejection.confirmationMismatch }

        let pendingRevision = currentScene.sceneRevision + 1
        let pendingScene = try EditProjectionEngine.apply(
            projection: reduction.committedProjection,
            to: currentScene,
            pendingRevision: pendingRevision,
            appending: EditReference(
                contractTransactionID: request.transactionID,
                operation: .place,
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
            requiredArtifactRefs: try EditProjectionEngine.requiredArtifactReferences(for: reduction.sourceProjection)
        )
        return PlaceConfirmationReduction(
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

    public static func deferUnavailable(
        proposal: BoundProposal,
        currentScene: SceneState
    ) throws -> DeferredOperationProposal {
        try validateContext(proposal, currentScene: currentScene)
        let blocker: PlaceReadinessBlocker
        switch proposal.intent.operation {
        case .replace, .remove:
            blocker = .capabilityNotReady
        case .restore:
            blocker = .restoreSourceRequired
        case .place:
            throw PlaceRejection.unsupportedOperation
        }
        return DeferredOperationProposal(
            operation: proposal.intent.operation,
            blocker: blocker,
            proposedOperations: [],
            baseSceneRevision: proposal.baseSceneRevision
        )
    }

    private static func validateContext(_ proposal: BoundProposal, currentScene: SceneState) throws {
        guard proposal.sessionID == currentScene.sessionID,
              proposal.revisionAuthority == currentScene.revisionAuthority,
              proposal.revisionAuthority.kind == .nativeDevice
        else { throw PlaceRejection.authorityMismatch }
        guard proposal.baseSceneRevision == currentScene.sceneRevision,
              proposal.targetContext.capturedSceneRevision == currentScene.sceneRevision
        else { throw PlaceRejection.staleBaseRevision }
        guard proposal.targetContext.worldFrameID == currentScene.worldFrame.worldFrameID,
              proposal.targetContext.worldFrameVersion == currentScene.worldFrame.worldFrameVersion
        else { throw PlaceRejection.worldMismatch }
        if let selected = proposal.targetContext.selectedObjectID,
           !currentScene.objects.contains(where: { $0.objectID == selected }) {
            throw PlaceRejection.invalidPlaceProposal
        }
    }

    private static func validateCandidate(
        _ candidate: DeterministicPlaceCandidate,
        scene: SceneState,
        transactionID: String
    ) throws {
        guard validID(candidate.asset.assetID, prefix: "asset_"),
              validID(candidate.asset.placedAssetID, prefix: "assetinst_"),
              validID(transactionID, prefix: "tx_"),
              !scene.placedAssets.contains(where: { $0.placedAssetID == candidate.asset.placedAssetID }),
              let support = candidate.support,
              validID(support.relationID, prefix: "support_"),
              !scene.supportRelations.contains(where: { $0.relationID == support.relationID }),
              support.confidence.isFinite,
              (0...1).contains(support.confidence),
              !support.method.isEmpty,
              support.worldFromAsset.values.count == 16,
              support.worldFromAsset.values.allSatisfy(\.isFinite)
        else { throw PlaceRejection.invalidDeterministicCandidate }
    }

    private static func validationChecks(
        scene: SceneState,
        candidate: DeterministicPlaceCandidate,
        support: DeterministicSupportCandidate
    ) -> [ValidationCheck] {
        [
            ValidationCheck(contractCheckID: "scene_revision", result: "pass", measured: .number(Double(scene.sceneRevision)), threshold: .number(Double(scene.sceneRevision))),
            ValidationCheck(contractCheckID: "support", result: "pass", measured: .number(support.confidence), threshold: .number(0.5)),
            ValidationCheck(contractCheckID: "collision_proxy", result: "pass", measured: .boolean(candidate.asset.collisionProxyPassed), threshold: .boolean(true)),
            ValidationCheck(contractCheckID: "asset_license", result: "pass", measured: .boolean(candidate.asset.assetLicensePassed), threshold: .boolean(true)),
            ValidationCheck(contractCheckID: "artifact_integrity", result: "pass", measured: .boolean(candidate.asset.artifactIntegrityPassed), threshold: .boolean(true)),
        ]
    }

    private static func validationInputDigest(
        proposal: BoundProposal,
        operations: [TransactionOperation],
        checks: [ValidationCheck]
    ) throws -> String {
        let input = ValidationDigestInput(
            requestFingerprint: try TransactionFingerprint.digest(proposal: proposal, proposedOperations: operations),
            checks: checks.map { ValidationDigestCheck(checkID: $0.checkID, measured: $0.measured, threshold: $0.threshold) }
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

private struct ValidationDigestInput: Codable {
    let requestFingerprint: String
    let checks: [ValidationDigestCheck]

    enum CodingKeys: String, CodingKey {
        case requestFingerprint = "request_fingerprint"
        case checks
    }
}

private struct ValidationDigestCheck: Codable {
    let checkID: String
    let measured: ValidationMeasurement
    let threshold: ValidationMeasurement

    enum CodingKeys: String, CodingKey {
        case checkID = "check_id"
        case measured
        case threshold
    }
}
