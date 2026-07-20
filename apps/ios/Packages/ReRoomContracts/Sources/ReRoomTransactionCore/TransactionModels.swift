import Foundation

public enum ProductOperation: String, CaseIterable, Codable, Sendable {
    case place
    case replace
    case remove
    case restore

    public static let stableAllowlist: [Self] = [.place, .replace, .remove, .restore]
}

public enum TransactionCanonicalState: String, CaseIterable, Codable, Sendable {
    case draft
    case validated
    case previewed
    case committed
    case rejected
    case cancelled
}

public enum TransactionSyncState: String, CaseIterable, Codable, Sendable {
    case localOnly = "local_only"
    case pendingSync = "pending_sync"
    case synced
    case conflict
    case syncFailed = "sync_failed"
}

public struct RevisionAuthority: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case nativeDevice = "native_device"
        case replayGateway = "replay_gateway"
    }

    public let kind: Kind
    public let authorityID: String
    public let revisionBranchID: String

    public init(kind: Kind, authorityID: String, revisionBranchID: String) {
        self.kind = kind
        self.authorityID = authorityID
        self.revisionBranchID = revisionBranchID
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case authorityID = "authority_id"
        case revisionBranchID = "revision_branch_id"
    }
}

public struct Matrix4: Codable, Equatable, Sendable {
    public let layout: String
    public let scalarType: String
    public let mathConvention: String
    public let units: String
    public let values: [Double]

    public init(
        layout: String = "row_major",
        scalarType: String = "float32",
        mathConvention: String = "column_vector",
        units: String = "meters",
        values: [Double]
    ) {
        self.layout = layout
        self.scalarType = scalarType
        self.mathConvention = mathConvention
        self.units = units
        self.values = values
    }

    enum CodingKeys: String, CodingKey {
        case layout
        case scalarType = "scalar_type"
        case mathConvention = "math_convention"
        case units
        case values
    }
}

public struct ArtifactReference: Codable, Equatable, Sendable {
    public let artifactID: String
    public let artifactType: String
    public let artifactRevision: UInt64
    public let sha256: String

    public init(artifactID: String, artifactType: String, artifactRevision: UInt64, sha256: String) {
        self.artifactID = artifactID
        self.artifactType = artifactType
        self.artifactRevision = artifactRevision
        self.sha256 = sha256
    }

    enum CodingKeys: String, CodingKey {
        case artifactID = "artifact_id"
        case artifactType = "artifact_type"
        case artifactRevision = "artifact_revision"
        case sha256
    }
}

public struct WorldFrame: Codable, Equatable, Sendable {
    public let worldFrameID: String
    public let worldFrameVersion: UInt64
    public let coordinateConvention: String
    public let authority: String
    public let createdByFrameID: String
    public let supersedesWorldFrameVersion: UInt64?
    public let correctionArtifactID: String?

    enum CodingKeys: String, CodingKey {
        case worldFrameID = "world_frame_id"
        case worldFrameVersion = "world_frame_version"
        case coordinateConvention = "coordinate_convention"
        case authority
        case createdByFrameID = "created_by_frame_id"
        case supersedesWorldFrameVersion = "supersedes_world_frame_version"
        case correctionArtifactID = "correction_artifact_id"
    }
}

public struct SceneSurface: Codable, Equatable, Sendable {
    public let surfaceID: String
    public let kind: String
    public let worldFromSurface: Matrix4
    public let extentM: [Double]
    public let confidence: Double
    public let lifecycle: String
    public let artifactRefs: [ArtifactReference]

    enum CodingKeys: String, CodingKey {
        case surfaceID = "surface_id"
        case kind
        case worldFromSurface = "world_from_surface"
        case extentM = "extent_m"
        case confidence
        case lifecycle
        case artifactRefs = "artifact_refs"
    }
}

public struct Readiness: Codable, Equatable, Sendable {
    public let select: String
    public let place: String
    public let replace: String
    public let remove: String
    public let restore: String
}

public struct ReadinessReason: Codable, Equatable, Sendable {
    public let code: String
    public let message: String
}

public struct ReadinessReasons: Codable, Equatable, Sendable {
    public let select: [ReadinessReason]
    public let place: [ReadinessReason]
    public let replace: [ReadinessReason]
    public let remove: [ReadinessReason]
    public let restore: [ReadinessReason]
}

public enum JSONPrimitive: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case boolean(Bool)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) { self = .boolean(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else { self = .string(try container.decode(String.self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .boolean(let value): try container.encode(value)
        }
    }
}

public struct ObjectEditState: Codable, Equatable, Sendable {
    public let visible: Bool
    public let activeReveal: ArtifactReference?

    enum CodingKeys: String, CodingKey {
        case visible
        case activeReveal = "active_reveal"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(visible, forKey: .visible)
        try container.encode(activeReveal, forKey: .activeReveal)
    }
}

public struct RendererBinding: Codable, Equatable, Sendable {
    public let generation: UInt64
    public let opaqueHandle: String

    enum CodingKeys: String, CodingKey {
        case generation
        case opaqueHandle = "opaque_handle"
    }
}

public struct SceneObject: Codable, Equatable, Sendable {
    public let objectID: String
    public let label: String
    public let labelConfidence: Double
    public let attributes: [String: JSONPrimitive]?
    public let lifecycle: String
    public let readiness: Readiness
    public let readinessReasons: ReadinessReasons
    public let artifactRefs: [ArtifactReference]
    public let editState: ObjectEditState
    public let createdSceneRevision: UInt64
    public let lastObservedFrameID: String
    public let rendererBinding: RendererBinding?

    enum CodingKeys: String, CodingKey {
        case objectID = "object_id"
        case label
        case labelConfidence = "label_confidence"
        case attributes
        case lifecycle
        case readiness
        case readinessReasons = "readiness_reasons"
        case artifactRefs = "artifact_refs"
        case editState = "edit_state"
        case createdSceneRevision = "created_scene_revision"
        case lastObservedFrameID = "last_observed_frame_id"
        case rendererBinding = "renderer_binding"
    }
}

public struct SupportRelation: Codable, Equatable, Sendable {
    public let relationID: String
    public let subjectID: String
    public let surfaceID: String
    public let confidence: Double
    public let method: String

    enum CodingKeys: String, CodingKey {
        case relationID = "relation_id"
        case subjectID = "subject_id"
        case surfaceID = "surface_id"
        case confidence
        case method
    }
}

public struct PlacedAsset: Codable, Equatable, Sendable {
    public let placedAssetID: String
    public let assetID: String
    public let manifestArtifactRef: ArtifactReference
    public let worldFromAsset: Matrix4
    public let state: String
    public let supportRelationID: String
    public let sourceTransactionID: String

    enum CodingKeys: String, CodingKey {
        case placedAssetID = "placed_asset_id"
        case assetID = "asset_id"
        case manifestArtifactRef = "manifest_artifact_ref"
        case worldFromAsset = "world_from_asset"
        case state
        case supportRelationID = "support_relation_id"
        case sourceTransactionID = "source_transaction_id"
    }
}

public struct EditReference: Codable, Equatable, Sendable {
    public let transactionID: String
    public let operation: ProductOperation
    public let committedSceneRevision: UInt64

    enum CodingKeys: String, CodingKey {
        case transactionID = "transaction_id"
        case operation
        case committedSceneRevision = "committed_scene_revision"
    }
}

public struct SceneState: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let sessionID: String
    public let sceneID: String
    public let revisionAuthority: RevisionAuthority
    public let sceneRevision: UInt64
    public let worldFrame: WorldFrame
    public let surfaces: [SceneSurface]
    public let objects: [SceneObject]
    public let supportRelations: [SupportRelation]
    public let placedAssets: [PlacedAsset]
    public let editHistory: [EditReference]
    public let updatedAtUTC: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case sessionID = "session_id"
        case sceneID = "scene_id"
        case revisionAuthority = "revision_authority"
        case sceneRevision = "scene_revision"
        case worldFrame = "world_frame"
        case surfaces
        case objects
        case supportRelations = "support_relations"
        case placedAssets = "placed_assets"
        case editHistory = "edit_history"
        case updatedAtUTC = "updated_at_utc"
    }
}

public struct TargetContext: Codable, Equatable, Sendable {
    public let capturedAtFrameID: String
    public let capturedSceneRevision: UInt64
    public let worldFrameID: String
    public let worldFrameVersion: UInt64
    public let cameraPose: Matrix4
    public let screenPointEncodedPixels: [Double]
    public let candidateObjectIDs: [String]
    public let selectedObjectID: String?
    public let artifactRefs: [ArtifactReference]

    enum CodingKeys: String, CodingKey {
        case capturedAtFrameID = "captured_at_frame_id"
        case capturedSceneRevision = "captured_scene_revision"
        case worldFrameID = "world_frame_id"
        case worldFrameVersion = "world_frame_version"
        case cameraPose = "camera_pose"
        case screenPointEncodedPixels = "screen_point_encoded_pixels"
        case candidateObjectIDs = "candidate_object_ids"
        case selectedObjectID = "selected_object_id"
        case artifactRefs = "artifact_refs"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(capturedAtFrameID, forKey: .capturedAtFrameID)
        try container.encode(capturedSceneRevision, forKey: .capturedSceneRevision)
        try container.encode(worldFrameID, forKey: .worldFrameID)
        try container.encode(worldFrameVersion, forKey: .worldFrameVersion)
        try container.encode(cameraPose, forKey: .cameraPose)
        try container.encode(screenPointEncodedPixels, forKey: .screenPointEncodedPixels)
        try container.encode(candidateObjectIDs, forKey: .candidateObjectIDs)
        try container.encode(selectedObjectID, forKey: .selectedObjectID)
        try container.encode(artifactRefs, forKey: .artifactRefs)
    }
}

public struct IntentArguments: Codable, Equatable, Sendable {
    public let assetID: String?
    public let catalogQuery: String?

    public init(assetID: String? = nil, catalogQuery: String? = nil) {
        self.assetID = assetID
        self.catalogQuery = catalogQuery
    }

    enum CodingKeys: String, CodingKey {
        case assetID = "asset_id"
        case catalogQuery = "catalog_query"
    }
}

public struct TypedConstraint: Codable, Equatable, Sendable {
    public let kind: String
    public let value: JSONPrimitive
}

public struct SemanticModelReference: Codable, Equatable, Sendable {
    public let provider: String
    public let model: String
    public let responseID: String

    enum CodingKeys: String, CodingKey {
        case provider
        case model
        case responseID = "response_id"
    }
}

public struct TransactionIntent: Codable, Equatable, Sendable {
    public let operation: ProductOperation
    public let source: String
    public let arguments: IntentArguments
    public let constraints: [TypedConstraint]
    public let semanticModel: SemanticModelReference?

    enum CodingKeys: String, CodingKey {
        case operation
        case source
        case arguments
        case constraints
        case semanticModel = "semantic_model"
    }
}

public struct VisibilitySnapshot: Codable, Equatable, Sendable {
    public let visible: Bool
}

public struct AssetSupportSnapshot: Codable, Equatable, Sendable {
    public let relationID: String
    public let surfaceID: String
    public let confidence: Double
    public let method: String

    enum CodingKeys: String, CodingKey {
        case relationID = "relation_id"
        case surfaceID = "surface_id"
        case confidence
        case method
    }
}

public struct AssetInstanceSnapshot: Codable, Equatable, Sendable {
    public let assetID: String
    public let manifestArtifactRef: ArtifactReference
    public let worldFromAsset: Matrix4
    public let supportRelation: AssetSupportSnapshot

    enum CodingKeys: String, CodingKey {
        case assetID = "asset_id"
        case manifestArtifactRef = "manifest_artifact_ref"
        case worldFromAsset = "world_from_asset"
        case supportRelation = "support_relation"
    }
}

public struct EditProjectionObjectState: Codable, Equatable, Sendable {
    public let objectID: String
    public let visible: Bool
    public let activeReveal: ArtifactReference?

    enum CodingKeys: String, CodingKey {
        case objectID = "object_id"
        case visible
        case activeReveal = "active_reveal"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(objectID, forKey: .objectID)
        try container.encode(visible, forKey: .visible)
        try container.encode(activeReveal, forKey: .activeReveal)
    }
}

public struct EditProjection: Codable, Equatable, Sendable {
    public let projectionVersion: String
    public let sceneID: String
    public let revisionBranchID: String
    public let worldFrameID: String
    public let worldFrameVersion: UInt64
    public let objectEditStates: [EditProjectionObjectState]
    public let placedAssets: [PlacedAsset]
    public let assetSupportRelations: [SupportRelation]

    enum CodingKeys: String, CodingKey {
        case projectionVersion = "projection_version"
        case sceneID = "scene_id"
        case revisionBranchID = "revision_branch_id"
        case worldFrameID = "world_frame_id"
        case worldFrameVersion = "world_frame_version"
        case objectEditStates = "object_edit_states"
        case placedAssets = "placed_assets"
        case assetSupportRelations = "asset_support_relations"
    }
}

public struct RestoreRebaseDerivation: Codable, Equatable, Sendable {
    public let rule: String
    public let sourceTransactionID: String
    public let sourceInverseBeforeProjectionSHA256: String
    public let sourceInverseAfterProjectionSHA256: String
    public let touchedObjectIDs: [String]
    public let touchedPlacedAssetIDs: [String]
    public let touchedAssetSupportRelationIDs: [String]

    enum CodingKeys: String, CodingKey {
        case rule
        case sourceTransactionID = "source_transaction_id"
        case sourceInverseBeforeProjectionSHA256 = "source_inverse_before_projection_sha256"
        case sourceInverseAfterProjectionSHA256 = "source_inverse_after_projection_sha256"
        case touchedObjectIDs = "touched_object_ids"
        case touchedPlacedAssetIDs = "touched_placed_asset_ids"
        case touchedAssetSupportRelationIDs = "touched_asset_support_relation_ids"
    }
}

public struct EditProjectionSnapshot: Codable, Equatable, Sendable {
    public let capturedSceneRevision: UInt64
    public let projectionOrigin: String
    public let derivation: RestoreRebaseDerivation?
    public let projectionSHA256Algorithm: String
    public let projectionSHA256Scope: String
    public let projectionSHA256: String
    public let projection: EditProjection

    enum CodingKeys: String, CodingKey {
        case capturedSceneRevision = "captured_scene_revision"
        case projectionOrigin = "projection_origin"
        case derivation
        case projectionSHA256Algorithm = "projection_sha256_algorithm"
        case projectionSHA256Scope = "projection_sha256_scope"
        case projectionSHA256 = "projection_sha256"
        case projection
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(capturedSceneRevision, forKey: .capturedSceneRevision)
        try container.encode(projectionOrigin, forKey: .projectionOrigin)
        try container.encode(derivation, forKey: .derivation)
        try container.encode(projectionSHA256Algorithm, forKey: .projectionSHA256Algorithm)
        try container.encode(projectionSHA256Scope, forKey: .projectionSHA256Scope)
        try container.encode(projectionSHA256, forKey: .projectionSHA256)
        try container.encode(projection, forKey: .projection)
    }
}

public enum TransactionOperation: Codable, Equatable, Sendable {
    case createAssetInstance(entityID: String, before: NeverValue?, after: AssetInstanceSnapshot, requiredArtifactRefs: [ArtifactReference])
    case setAssetTransform(entityID: String, before: Matrix4, after: Matrix4, requiredArtifactRefs: [ArtifactReference]?)
    case setObjectVisibility(entityID: String, before: VisibilitySnapshot, after: VisibilitySnapshot, requiredArtifactRefs: [ArtifactReference]?)
    case setRevealBundle(entityID: String, before: ArtifactReference?, after: ArtifactReference?, requiredArtifactRefs: [ArtifactReference])
    case restoreSnapshot(entityID: String, before: EditProjectionSnapshot, after: EditProjectionSnapshot, requiredArtifactRefs: [ArtifactReference])

    enum CodingKeys: String, CodingKey { case kind, entityID = "entity_id", before, after, requiredArtifactRefs = "required_artifact_refs" }
    enum Kind: String, Codable { case createAssetInstance = "create_asset_instance", setAssetTransform = "set_asset_transform", setObjectVisibility = "set_object_visibility", setRevealBundle = "set_reveal_bundle", restoreSnapshot = "restore_snapshot" }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .createAssetInstance:
            self = .createAssetInstance(entityID: try container.decode(String.self, forKey: .entityID), before: try container.decodeIfPresent(NeverValue.self, forKey: .before), after: try container.decode(AssetInstanceSnapshot.self, forKey: .after), requiredArtifactRefs: try container.decode([ArtifactReference].self, forKey: .requiredArtifactRefs))
        case .setAssetTransform:
            self = .setAssetTransform(entityID: try container.decode(String.self, forKey: .entityID), before: try container.decode(Matrix4.self, forKey: .before), after: try container.decode(Matrix4.self, forKey: .after), requiredArtifactRefs: try container.decodeIfPresent([ArtifactReference].self, forKey: .requiredArtifactRefs))
        case .setObjectVisibility:
            self = .setObjectVisibility(entityID: try container.decode(String.self, forKey: .entityID), before: try container.decode(VisibilitySnapshot.self, forKey: .before), after: try container.decode(VisibilitySnapshot.self, forKey: .after), requiredArtifactRefs: try container.decodeIfPresent([ArtifactReference].self, forKey: .requiredArtifactRefs))
        case .setRevealBundle:
            self = .setRevealBundle(entityID: try container.decode(String.self, forKey: .entityID), before: try container.decodeIfPresent(ArtifactReference.self, forKey: .before), after: try container.decodeIfPresent(ArtifactReference.self, forKey: .after), requiredArtifactRefs: try container.decode([ArtifactReference].self, forKey: .requiredArtifactRefs))
        case .restoreSnapshot:
            self = .restoreSnapshot(entityID: try container.decode(String.self, forKey: .entityID), before: try container.decode(EditProjectionSnapshot.self, forKey: .before), after: try container.decode(EditProjectionSnapshot.self, forKey: .after), requiredArtifactRefs: try container.decode([ArtifactReference].self, forKey: .requiredArtifactRefs))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .createAssetInstance(let entityID, _, let after, let refs):
            try container.encode(Kind.createAssetInstance, forKey: .kind); try container.encode(entityID, forKey: .entityID); try container.encodeNil(forKey: .before); try container.encode(after, forKey: .after); try container.encode(refs, forKey: .requiredArtifactRefs)
        case .setAssetTransform(let entityID, let before, let after, let refs):
            try container.encode(Kind.setAssetTransform, forKey: .kind); try container.encode(entityID, forKey: .entityID); try container.encode(before, forKey: .before); try container.encode(after, forKey: .after); try container.encodeIfPresent(refs, forKey: .requiredArtifactRefs)
        case .setObjectVisibility(let entityID, let before, let after, let refs):
            try container.encode(Kind.setObjectVisibility, forKey: .kind); try container.encode(entityID, forKey: .entityID); try container.encode(before, forKey: .before); try container.encode(after, forKey: .after); try container.encodeIfPresent(refs, forKey: .requiredArtifactRefs)
        case .setRevealBundle(let entityID, let before, let after, let refs):
            try container.encode(Kind.setRevealBundle, forKey: .kind); try container.encode(entityID, forKey: .entityID); try container.encode(before, forKey: .before); try container.encode(after, forKey: .after); try container.encode(refs, forKey: .requiredArtifactRefs)
        case .restoreSnapshot(let entityID, let before, let after, let refs):
            try container.encode(Kind.restoreSnapshot, forKey: .kind); try container.encode(entityID, forKey: .entityID); try container.encode(before, forKey: .before); try container.encode(after, forKey: .after); try container.encode(refs, forKey: .requiredArtifactRefs)
        }
    }
}

public struct NeverValue: Codable, Equatable, Sendable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard container.decodeNil() else { throw DecodingError.typeMismatch(Self.self, .init(codingPath: decoder.codingPath, debugDescription: "Expected null")) }
    }
    public func encode(to encoder: Encoder) throws { var container = encoder.singleValueContainer(); try container.encodeNil() }
}

public enum ValidationMeasurement: Codable, Equatable, Sendable {
    case number(Double), string(String), boolean(Bool), null
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .boolean(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else { self = .string(try container.decode(String.self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self { case .number(let value): try container.encode(value); case .string(let value): try container.encode(value); case .boolean(let value): try container.encode(value); case .null: try container.encodeNil() }
    }
}

public struct ValidationCheck: Codable, Equatable, Sendable {
    public let checkID: String
    public let result: String
    public let measured: ValidationMeasurement
    public let threshold: ValidationMeasurement
    enum CodingKeys: String, CodingKey { case checkID = "check_id", result, measured, threshold }
}

public struct TransactionValidation: Codable, Equatable, Sendable {
    public let state: String
    public let checks: [ValidationCheck]
    public let validatorVersion: String
    public let inputSHA256Algorithm: String
    public let inputSHA256Scope: String
    public let inputSHA256: String
    enum CodingKeys: String, CodingKey { case state, checks, validatorVersion = "validator_version", inputSHA256Algorithm = "input_sha256_algorithm", inputSHA256Scope = "input_sha256_scope", inputSHA256 = "input_sha256" }
}

public struct TransactionPreview: Codable, Equatable, Sendable {
    public let previewID: String
    public let baseSceneRevision: UInt64
    public let expiresAtUTC: String
    public let artifactRefs: [ArtifactReference]
    enum CodingKeys: String, CodingKey { case previewID = "preview_id", baseSceneRevision = "base_scene_revision", expiresAtUTC = "expires_at_utc", artifactRefs = "artifact_refs" }
}

public struct ExplicitConfirmation: Codable, Equatable, Sendable {
    public let kind: String
    public let actorID: String
    public let source: String
    public let previewID: String
    public let confirmationEventID: String
    public let confirmedAtUTC: String
    enum CodingKeys: String, CodingKey { case kind, actorID = "actor_id", source, previewID = "preview_id", confirmationEventID = "confirmation_event_id", confirmedAtUTC = "confirmed_at_utc" }
}

public struct TransactionCommit: Codable, Equatable, Sendable {
    public let authorityID: String
    public let revisionBranchID: String
    public let compareAndSwapBaseRevision: UInt64
    public let committedSceneRevision: UInt64
    public let confirmation: ExplicitConfirmation
    public let committedAtUTC: String
    public let localDurableBeforeVisibleAck: Bool
    public let resultSHA256Algorithm: String
    public let resultSHA256Scope: String
    public let resultSHA256: String
    enum CodingKeys: String, CodingKey { case authorityID = "authority_id", revisionBranchID = "revision_branch_id", compareAndSwapBaseRevision = "compare_and_swap_base_revision", committedSceneRevision = "committed_scene_revision", confirmation, committedAtUTC = "committed_at_utc", localDurableBeforeVisibleAck = "local_durable_before_visible_ack", resultSHA256Algorithm = "result_sha256_algorithm", resultSHA256Scope = "result_sha256_scope", resultSHA256 = "result_sha256" }
}

public struct TransactionFailure: Codable, Equatable, Sendable {
    public let code: String
    public let message: String
    public let retryable: Bool
}

public struct Reconciliation: Codable, Equatable, Sendable {
    public let state: String
    public let lastKnownGatewayRevision: UInt64?
    public let resolution: String
    public let automaticMergePermitted: Bool
    public let quarantinedBranchID: String?
    public let resolvedTransactionID: String?
    enum CodingKeys: String, CodingKey { case state, lastKnownGatewayRevision = "last_known_gateway_revision", resolution, automaticMergePermitted = "automatic_merge_permitted", quarantinedBranchID = "quarantined_branch_id", resolvedTransactionID = "resolved_transaction_id" }
}

public struct TransactionRecord: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let transactionID: String
    public let idempotencyKey: String
    public let requestFingerprintAlgorithm: String
    public let requestFingerprintScope: String
    public let requestFingerprintSHA256: String
    public let sessionID: String
    public let revisionAuthority: RevisionAuthority
    public let baseSceneRevision: UInt64
    public let targetContext: TargetContext
    public let intent: TransactionIntent
    public let proposedOperations: [TransactionOperation]
    public let validation: TransactionValidation
    public let preview: TransactionPreview?
    public let commit: TransactionCommit?
    public let inverseOperations: [TransactionOperation]?
    public let localUndoToken: String?
    public let compensatesTransactionID: String?
    public let canonicalState: TransactionCanonicalState
    public let syncState: TransactionSyncState
    public let failureReasons: [TransactionFailure]?
    public let reconciliation: Reconciliation?
    public let createdAtUTC: String
    public let updatedAtUTC: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", transactionID = "transaction_id", idempotencyKey = "idempotency_key", requestFingerprintAlgorithm = "request_fingerprint_algorithm", requestFingerprintScope = "request_fingerprint_scope", requestFingerprintSHA256 = "request_fingerprint_sha256", sessionID = "session_id", revisionAuthority = "revision_authority", baseSceneRevision = "base_scene_revision", targetContext = "target_context", intent, proposedOperations = "proposed_operations", validation, preview, commit, inverseOperations = "inverse_operations", localUndoToken = "local_undo_token", compensatesTransactionID = "compensates_transaction_id", canonicalState = "canonical_state", syncState = "sync_state", failureReasons = "failure_reasons", reconciliation, createdAtUTC = "created_at_utc", updatedAtUTC = "updated_at_utc"
    }
}

public struct TransactionReceipt: Codable, Equatable, Sendable {
    public let transactionID: String
    public let idempotencyKey: String
    public let requestFingerprintSHA256: String
    public let revisionAuthority: RevisionAuthority
    public let committedSceneRevision: UInt64
    public let resultSHA256: String

    enum CodingKeys: String, CodingKey {
        case transactionID = "transaction_id"
        case idempotencyKey = "idempotency_key"
        case requestFingerprintSHA256 = "request_fingerprint_sha256"
        case revisionAuthority = "revision_authority"
        case committedSceneRevision = "committed_scene_revision"
        case resultSHA256 = "result_sha256"
    }
}

// Public construction is explicit so reducers, storage, replay, and app targets can
// share these values without relying on module-internal synthesized initializers.
public extension WorldFrame {
    init(contractWorldFrameID worldFrameID: String, worldFrameVersion: UInt64, coordinateConvention: String = "RR-COORD-1", authority: String = "arkit", createdByFrameID: String, supersedesWorldFrameVersion: UInt64? = nil, correctionArtifactID: String? = nil) {
        self.worldFrameID = worldFrameID; self.worldFrameVersion = worldFrameVersion; self.coordinateConvention = coordinateConvention; self.authority = authority; self.createdByFrameID = createdByFrameID; self.supersedesWorldFrameVersion = supersedesWorldFrameVersion; self.correctionArtifactID = correctionArtifactID
    }
}

public extension SceneSurface {
    init(contractSurfaceID surfaceID: String, kind: String, worldFromSurface: Matrix4, extentM: [Double], confidence: Double, lifecycle: String, artifactRefs: [ArtifactReference]) {
        self.surfaceID = surfaceID; self.kind = kind; self.worldFromSurface = worldFromSurface; self.extentM = extentM; self.confidence = confidence; self.lifecycle = lifecycle; self.artifactRefs = artifactRefs
    }
}

public extension Readiness {
    init(contractSelect select: String, place: String, replace: String, remove: String, restore: String) {
        self.select = select; self.place = place; self.replace = replace; self.remove = remove; self.restore = restore
    }
}

public extension ReadinessReason {
    init(contractCode code: String, message: String) { self.code = code; self.message = message }
}

public extension ReadinessReasons {
    init(contractSelect select: [ReadinessReason], place: [ReadinessReason], replace: [ReadinessReason], remove: [ReadinessReason], restore: [ReadinessReason]) {
        self.select = select; self.place = place; self.replace = replace; self.remove = remove; self.restore = restore
    }
}

public extension ObjectEditState {
    init(contractVisible visible: Bool, activeReveal: ArtifactReference?) { self.visible = visible; self.activeReveal = activeReveal }
}

public extension RendererBinding {
    init(contractGeneration generation: UInt64, opaqueHandle: String) { self.generation = generation; self.opaqueHandle = opaqueHandle }
}

public extension SceneObject {
    init(contractObjectID objectID: String, label: String, labelConfidence: Double, attributes: [String: JSONPrimitive]? = nil, lifecycle: String, readiness: Readiness, readinessReasons: ReadinessReasons, artifactRefs: [ArtifactReference], editState: ObjectEditState, createdSceneRevision: UInt64, lastObservedFrameID: String, rendererBinding: RendererBinding? = nil) {
        self.objectID = objectID; self.label = label; self.labelConfidence = labelConfidence; self.attributes = attributes; self.lifecycle = lifecycle; self.readiness = readiness; self.readinessReasons = readinessReasons; self.artifactRefs = artifactRefs; self.editState = editState; self.createdSceneRevision = createdSceneRevision; self.lastObservedFrameID = lastObservedFrameID; self.rendererBinding = rendererBinding
    }
}

public extension SupportRelation {
    init(contractRelationID relationID: String, subjectID: String, surfaceID: String, confidence: Double, method: String) {
        self.relationID = relationID; self.subjectID = subjectID; self.surfaceID = surfaceID; self.confidence = confidence; self.method = method
    }
}

public extension PlacedAsset {
    init(contractPlacedAssetID placedAssetID: String, assetID: String, manifestArtifactRef: ArtifactReference, worldFromAsset: Matrix4, state: String, supportRelationID: String, sourceTransactionID: String) {
        self.placedAssetID = placedAssetID; self.assetID = assetID; self.manifestArtifactRef = manifestArtifactRef; self.worldFromAsset = worldFromAsset; self.state = state; self.supportRelationID = supportRelationID; self.sourceTransactionID = sourceTransactionID
    }
}

public extension EditReference {
    init(contractTransactionID transactionID: String, operation: ProductOperation, committedSceneRevision: UInt64) {
        self.transactionID = transactionID; self.operation = operation; self.committedSceneRevision = committedSceneRevision
    }
}

public extension SceneState {
    init(contractSchemaVersion schemaVersion: String = "1.0.0", sessionID: String, sceneID: String, revisionAuthority: RevisionAuthority, sceneRevision: UInt64, worldFrame: WorldFrame, surfaces: [SceneSurface], objects: [SceneObject], supportRelations: [SupportRelation], placedAssets: [PlacedAsset], editHistory: [EditReference], updatedAtUTC: String) {
        self.schemaVersion = schemaVersion; self.sessionID = sessionID; self.sceneID = sceneID; self.revisionAuthority = revisionAuthority; self.sceneRevision = sceneRevision; self.worldFrame = worldFrame; self.surfaces = surfaces; self.objects = objects; self.supportRelations = supportRelations; self.placedAssets = placedAssets; self.editHistory = editHistory; self.updatedAtUTC = updatedAtUTC
    }
}

public extension TargetContext {
    init(contractCapturedAtFrameID capturedAtFrameID: String, capturedSceneRevision: UInt64, worldFrameID: String, worldFrameVersion: UInt64, cameraPose: Matrix4, screenPointEncodedPixels: [Double], candidateObjectIDs: [String], selectedObjectID: String?, artifactRefs: [ArtifactReference]) {
        self.capturedAtFrameID = capturedAtFrameID; self.capturedSceneRevision = capturedSceneRevision; self.worldFrameID = worldFrameID; self.worldFrameVersion = worldFrameVersion; self.cameraPose = cameraPose; self.screenPointEncodedPixels = screenPointEncodedPixels; self.candidateObjectIDs = candidateObjectIDs; self.selectedObjectID = selectedObjectID; self.artifactRefs = artifactRefs
    }
}

public extension TypedConstraint {
    init(contractKind kind: String, value: JSONPrimitive) { self.kind = kind; self.value = value }
}

public extension SemanticModelReference {
    init(contractProvider provider: String, model: String, responseID: String) { self.provider = provider; self.model = model; self.responseID = responseID }
}

public extension TransactionIntent {
    init(contractOperation operation: ProductOperation, source: String, arguments: IntentArguments, constraints: [TypedConstraint], semanticModel: SemanticModelReference? = nil) {
        self.operation = operation; self.source = source; self.arguments = arguments; self.constraints = constraints; self.semanticModel = semanticModel
    }
}

public extension VisibilitySnapshot {
    init(contractVisible visible: Bool) { self.visible = visible }
}

public extension AssetSupportSnapshot {
    init(contractRelationID relationID: String, surfaceID: String, confidence: Double, method: String) {
        self.relationID = relationID; self.surfaceID = surfaceID; self.confidence = confidence; self.method = method
    }
}

public extension AssetInstanceSnapshot {
    init(contractAssetID assetID: String, manifestArtifactRef: ArtifactReference, worldFromAsset: Matrix4, supportRelation: AssetSupportSnapshot) {
        self.assetID = assetID; self.manifestArtifactRef = manifestArtifactRef; self.worldFromAsset = worldFromAsset; self.supportRelation = supportRelation
    }
}

public extension EditProjectionObjectState {
    init(contractObjectID objectID: String, visible: Bool, activeReveal: ArtifactReference?) { self.objectID = objectID; self.visible = visible; self.activeReveal = activeReveal }
}

public extension EditProjection {
    init(contractProjectionVersion projectionVersion: String = "RR-EDIT-PROJECTION-1", sceneID: String, revisionBranchID: String, worldFrameID: String, worldFrameVersion: UInt64, objectEditStates: [EditProjectionObjectState], placedAssets: [PlacedAsset], assetSupportRelations: [SupportRelation]) {
        self.projectionVersion = projectionVersion; self.sceneID = sceneID; self.revisionBranchID = revisionBranchID; self.worldFrameID = worldFrameID; self.worldFrameVersion = worldFrameVersion; self.objectEditStates = objectEditStates; self.placedAssets = placedAssets; self.assetSupportRelations = assetSupportRelations
    }
}

public extension RestoreRebaseDerivation {
    init(contractRule rule: String = "RR-RESTORE-REBASE-1", sourceTransactionID: String, sourceInverseBeforeProjectionSHA256: String, sourceInverseAfterProjectionSHA256: String, touchedObjectIDs: [String], touchedPlacedAssetIDs: [String], touchedAssetSupportRelationIDs: [String]) {
        self.rule = rule; self.sourceTransactionID = sourceTransactionID; self.sourceInverseBeforeProjectionSHA256 = sourceInverseBeforeProjectionSHA256; self.sourceInverseAfterProjectionSHA256 = sourceInverseAfterProjectionSHA256; self.touchedObjectIDs = touchedObjectIDs; self.touchedPlacedAssetIDs = touchedPlacedAssetIDs; self.touchedAssetSupportRelationIDs = touchedAssetSupportRelationIDs
    }
}

public extension EditProjectionSnapshot {
    init(contractCapturedSceneRevision capturedSceneRevision: UInt64, projectionOrigin: String, derivation: RestoreRebaseDerivation?, projectionSHA256Algorithm: String = "RR-JCS-SHA256-1", projectionSHA256Scope: String = "entire_rr_edit_projection_1", projectionSHA256: String, projection: EditProjection) {
        self.capturedSceneRevision = capturedSceneRevision; self.projectionOrigin = projectionOrigin; self.derivation = derivation; self.projectionSHA256Algorithm = projectionSHA256Algorithm; self.projectionSHA256Scope = projectionSHA256Scope; self.projectionSHA256 = projectionSHA256; self.projection = projection
    }
}

public extension ValidationCheck {
    init(contractCheckID checkID: String, result: String, measured: ValidationMeasurement, threshold: ValidationMeasurement) { self.checkID = checkID; self.result = result; self.measured = measured; self.threshold = threshold }
}

public extension TransactionValidation {
    init(contractState state: String, checks: [ValidationCheck], validatorVersion: String, inputSHA256Algorithm: String = "RR-JCS-SHA256-1", inputSHA256Scope: String = "request_fingerprint_object_plus_validation_checks_without_validation_results", inputSHA256: String) {
        self.state = state; self.checks = checks; self.validatorVersion = validatorVersion; self.inputSHA256Algorithm = inputSHA256Algorithm; self.inputSHA256Scope = inputSHA256Scope; self.inputSHA256 = inputSHA256
    }
}

public extension TransactionPreview {
    init(contractPreviewID previewID: String, baseSceneRevision: UInt64, expiresAtUTC: String, artifactRefs: [ArtifactReference]) { self.previewID = previewID; self.baseSceneRevision = baseSceneRevision; self.expiresAtUTC = expiresAtUTC; self.artifactRefs = artifactRefs }
}

public extension ExplicitConfirmation {
    init(contractKind kind: String = "explicit_user_confirmation", actorID: String, source: String, previewID: String, confirmationEventID: String, confirmedAtUTC: String) {
        self.kind = kind; self.actorID = actorID; self.source = source; self.previewID = previewID; self.confirmationEventID = confirmationEventID; self.confirmedAtUTC = confirmedAtUTC
    }
}

public extension TransactionCommit {
    init(contractAuthorityID authorityID: String, revisionBranchID: String, compareAndSwapBaseRevision: UInt64, committedSceneRevision: UInt64, confirmation: ExplicitConfirmation, committedAtUTC: String, localDurableBeforeVisibleAck: Bool = true, resultSHA256Algorithm: String = "RR-JCS-SHA256-1", resultSHA256Scope: String = "commit_object_with_result_sha256_member_omitted", resultSHA256: String) {
        self.authorityID = authorityID; self.revisionBranchID = revisionBranchID; self.compareAndSwapBaseRevision = compareAndSwapBaseRevision; self.committedSceneRevision = committedSceneRevision; self.confirmation = confirmation; self.committedAtUTC = committedAtUTC; self.localDurableBeforeVisibleAck = localDurableBeforeVisibleAck; self.resultSHA256Algorithm = resultSHA256Algorithm; self.resultSHA256Scope = resultSHA256Scope; self.resultSHA256 = resultSHA256
    }
}

public extension TransactionFailure {
    init(contractCode code: String, message: String, retryable: Bool) { self.code = code; self.message = message; self.retryable = retryable }
}

public extension Reconciliation {
    init(contractState state: String, lastKnownGatewayRevision: UInt64?, resolution: String, automaticMergePermitted: Bool = false, quarantinedBranchID: String? = nil, resolvedTransactionID: String? = nil) {
        self.state = state; self.lastKnownGatewayRevision = lastKnownGatewayRevision; self.resolution = resolution; self.automaticMergePermitted = automaticMergePermitted; self.quarantinedBranchID = quarantinedBranchID; self.resolvedTransactionID = resolvedTransactionID
    }
}

public extension TransactionRecord {
    init(contractSchemaVersion schemaVersion: String = "1.0.0", transactionID: String, idempotencyKey: String, requestFingerprintAlgorithm: String = "RR-JCS-SHA256-1", requestFingerprintScope: String = "schema_version_session_id_revision_authority_base_scene_revision_target_context_intent_proposed_operations", requestFingerprintSHA256: String, sessionID: String, revisionAuthority: RevisionAuthority, baseSceneRevision: UInt64, targetContext: TargetContext, intent: TransactionIntent, proposedOperations: [TransactionOperation], validation: TransactionValidation, preview: TransactionPreview? = nil, commit: TransactionCommit? = nil, inverseOperations: [TransactionOperation]? = nil, localUndoToken: String? = nil, compensatesTransactionID: String? = nil, canonicalState: TransactionCanonicalState, syncState: TransactionSyncState, failureReasons: [TransactionFailure]? = nil, reconciliation: Reconciliation? = nil, createdAtUTC: String, updatedAtUTC: String? = nil) {
        self.schemaVersion = schemaVersion; self.transactionID = transactionID; self.idempotencyKey = idempotencyKey; self.requestFingerprintAlgorithm = requestFingerprintAlgorithm; self.requestFingerprintScope = requestFingerprintScope; self.requestFingerprintSHA256 = requestFingerprintSHA256; self.sessionID = sessionID; self.revisionAuthority = revisionAuthority; self.baseSceneRevision = baseSceneRevision; self.targetContext = targetContext; self.intent = intent; self.proposedOperations = proposedOperations; self.validation = validation; self.preview = preview; self.commit = commit; self.inverseOperations = inverseOperations; self.localUndoToken = localUndoToken; self.compensatesTransactionID = compensatesTransactionID; self.canonicalState = canonicalState; self.syncState = syncState; self.failureReasons = failureReasons; self.reconciliation = reconciliation; self.createdAtUTC = createdAtUTC; self.updatedAtUTC = updatedAtUTC
    }
}

public extension TransactionReceipt {
    init(contractTransactionID transactionID: String, idempotencyKey: String, requestFingerprintSHA256: String, revisionAuthority: RevisionAuthority, committedSceneRevision: UInt64, resultSHA256: String) {
        self.transactionID = transactionID; self.idempotencyKey = idempotencyKey; self.requestFingerprintSHA256 = requestFingerprintSHA256; self.revisionAuthority = revisionAuthority; self.committedSceneRevision = committedSceneRevision; self.resultSHA256 = resultSHA256
    }
}
