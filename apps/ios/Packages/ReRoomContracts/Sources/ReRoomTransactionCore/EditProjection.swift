import Foundation
import ReRoomContracts

public enum EditProjectionRejection: String, Error, Equatable, Sendable {
    case identityMismatch = "identity_mismatch"
    case duplicateID = "duplicate_id"
    case nonLexicographicOrder = "non_lexicographic_order"
    case incompleteProjection = "incomplete_projection"
    case danglingSupport = "dangling_support"
    case invalidArtifactReference = "invalid_artifact_reference"
    case artifactUnionMismatch = "artifact_union_mismatch"
    case projectionDigestMismatch = "projection_digest_mismatch"
    case touchedOperationMismatch = "touched_operation_mismatch"
    case operationOrderMismatch = "operation_order_mismatch"
    case unexpectedTouchedEntityDrift = "unexpected_touched_entity_drift"
    case invalidSceneRevision = "invalid_scene_revision"
}

public struct EditProjectionTouchedIDs: Codable, Equatable, Sendable {
    public let objectIDs: [String]
    public let placedAssetIDs: [String]
    public let assetSupportRelationIDs: [String]

    public init(objectIDs: [String], placedAssetIDs: [String], assetSupportRelationIDs: [String]) {
        self.objectIDs = objectIDs
        self.placedAssetIDs = placedAssetIDs
        self.assetSupportRelationIDs = assetSupportRelationIDs
    }
}

public enum EditProjectionOrigin: String, Sendable {
    case capturedExact = "captured_exact"
    case restoreRebase = "restore_rebase"
}

public enum EditProjectionEngine {
    public static func build(from scene: SceneState) throws -> EditProjection {
        guard validID(scene.sceneID, prefix: "scene_"),
              validID(scene.revisionAuthority.revisionBranchID, prefix: "branch_"),
              validID(scene.worldFrame.worldFrameID, prefix: "world_"),
              scene.worldFrame.worldFrameVersion > 0
        else { throw EditProjectionRejection.identityMismatch }

        try requireUnique(scene.objects.map(\.objectID))
        try requireUnique(scene.placedAssets.map(\.placedAssetID))
        try requireUnique(scene.supportRelations.map(\.relationID))
        try requireUnique(scene.surfaces.map(\.surfaceID))

        let knownSurfaces = Set(scene.surfaces.map(\.surfaceID))
        let assetRelations = scene.supportRelations.filter { $0.subjectID.hasPrefix("assetinst_") }
        guard assetRelations.allSatisfy({ knownSurfaces.contains($0.surfaceID) }) else {
            throw EditProjectionRejection.danglingSupport
        }

        let projection = EditProjection(
            sceneID: scene.sceneID,
            revisionBranchID: scene.revisionAuthority.revisionBranchID,
            worldFrameID: scene.worldFrame.worldFrameID,
            worldFrameVersion: scene.worldFrame.worldFrameVersion,
            objectEditStates: scene.objects
                .map {
                    EditProjectionObjectState(
                        contractObjectID: $0.objectID,
                        visible: $0.editState.visible,
                        activeReveal: $0.editState.activeReveal
                    )
                }
                .sorted { $0.objectID < $1.objectID },
            placedAssets: scene.placedAssets.sorted { $0.placedAssetID < $1.placedAssetID },
            assetSupportRelations: assetRelations.sorted { $0.relationID < $1.relationID }
        )
        try validate(projection)
        return projection
    }

    public static func validate(_ projection: EditProjection) throws {
        guard projection.projectionVersion == "RR-EDIT-PROJECTION-1",
              validID(projection.sceneID, prefix: "scene_"),
              validID(projection.revisionBranchID, prefix: "branch_"),
              validID(projection.worldFrameID, prefix: "world_"),
              projection.worldFrameVersion > 0
        else { throw EditProjectionRejection.identityMismatch }

        try validateOrderAndUniqueness(projection.objectEditStates.map(\.objectID))
        try validateOrderAndUniqueness(projection.placedAssets.map(\.placedAssetID))
        try validateOrderAndUniqueness(projection.assetSupportRelations.map(\.relationID))

        for object in projection.objectEditStates {
            guard validID(object.objectID, prefix: "object_") else {
                throw EditProjectionRejection.identityMismatch
            }
            if let reveal = object.activeReveal {
                guard !object.visible, reveal.artifactType == "reveal_bundle" else {
                    throw EditProjectionRejection.invalidArtifactReference
                }
                try validateArtifact(reveal)
            }
        }

        let assetsByID = Dictionary(uniqueKeysWithValues: projection.placedAssets.map { ($0.placedAssetID, $0) })
        let supportsByID = Dictionary(uniqueKeysWithValues: projection.assetSupportRelations.map { ($0.relationID, $0) })
        for asset in projection.placedAssets {
            guard validID(asset.placedAssetID, prefix: "assetinst_"),
                  validID(asset.assetID, prefix: "asset_"),
                  validID(asset.supportRelationID, prefix: "support_"),
                  validID(asset.sourceTransactionID, prefix: "tx_"),
                  ["committed", "hidden", "restored"].contains(asset.state),
                  asset.manifestArtifactRef.artifactType == "asset_manifest"
            else { throw EditProjectionRejection.invalidArtifactReference }
            try validateArtifact(asset.manifestArtifactRef)
            guard let support = supportsByID[asset.supportRelationID], support.subjectID == asset.placedAssetID else {
                throw EditProjectionRejection.danglingSupport
            }
        }
        for support in projection.assetSupportRelations {
            guard validID(support.relationID, prefix: "support_"),
                  validID(support.subjectID, prefix: "assetinst_"),
                  validID(support.surfaceID, prefix: "surface_"),
                  support.confidence.isFinite,
                  (0...1).contains(support.confidence),
                  assetsByID[support.subjectID]?.supportRelationID == support.relationID
            else { throw EditProjectionRejection.danglingSupport }
        }
        guard projection.placedAssets.count == projection.assetSupportRelations.count else {
            throw EditProjectionRejection.incompleteProjection
        }
    }

    public static func digest(_ projection: EditProjection) throws -> String {
        try validate(projection)
        return try CanonicalJSON.digest(jsonData: try encode(projection))
    }

    public static func snapshot(
        _ projection: EditProjection,
        capturedSceneRevision: UInt64,
        origin: EditProjectionOrigin,
        derivation: RestoreRebaseDerivation? = nil
    ) throws -> EditProjectionSnapshot {
        switch origin {
        case .capturedExact:
            guard derivation == nil else { throw EditProjectionRejection.identityMismatch }
        case .restoreRebase:
            guard let derivation, derivation.rule == "RR-RESTORE-REBASE-1" else {
                throw EditProjectionRejection.identityMismatch
            }
            try validateTouchedOrder(derivation)
        }
        return EditProjectionSnapshot(
            contractCapturedSceneRevision: capturedSceneRevision,
            projectionOrigin: origin.rawValue,
            derivation: derivation,
            projectionSHA256: try digest(projection),
            projection: projection
        )
    }

    public static func validate(_ snapshot: EditProjectionSnapshot) throws {
        guard snapshot.projectionSHA256Algorithm == "RR-JCS-SHA256-1",
              snapshot.projectionSHA256Scope == "entire_rr_edit_projection_1",
              snapshot.projectionSHA256 == (try digest(snapshot.projection))
        else { throw EditProjectionRejection.projectionDigestMismatch }
        switch snapshot.projectionOrigin {
        case EditProjectionOrigin.capturedExact.rawValue:
            guard snapshot.derivation == nil else { throw EditProjectionRejection.identityMismatch }
        case EditProjectionOrigin.restoreRebase.rawValue:
            guard let derivation = snapshot.derivation,
                  derivation.rule == "RR-RESTORE-REBASE-1"
            else { throw EditProjectionRejection.identityMismatch }
            try validateTouchedOrder(derivation)
        default:
            throw EditProjectionRejection.identityMismatch
        }
    }

    public static func diff(
        sourceBefore: EditProjection,
        sourceAfter: EditProjection
    ) throws -> EditProjectionTouchedIDs {
        try validate(sourceBefore)
        try validate(sourceAfter)
        try requireSameIdentity(sourceBefore, sourceAfter)
        return EditProjectionTouchedIDs(
            objectIDs: differingIDs(
                Dictionary(uniqueKeysWithValues: sourceBefore.objectEditStates.map { ($0.objectID, $0) }),
                Dictionary(uniqueKeysWithValues: sourceAfter.objectEditStates.map { ($0.objectID, $0) })
            ),
            placedAssetIDs: differingIDs(
                Dictionary(uniqueKeysWithValues: sourceBefore.placedAssets.map { ($0.placedAssetID, $0) }),
                Dictionary(uniqueKeysWithValues: sourceAfter.placedAssets.map { ($0.placedAssetID, $0) })
            ),
            assetSupportRelationIDs: differingIDs(
                Dictionary(uniqueKeysWithValues: sourceBefore.assetSupportRelations.map { ($0.relationID, $0) }),
                Dictionary(uniqueKeysWithValues: sourceAfter.assetSupportRelations.map { ($0.relationID, $0) })
            )
        )
    }

    public static func verify(
        touched: EditProjectionTouchedIDs,
        against operations: [TransactionOperation]
    ) throws {
        guard !operations.isEmpty else { throw EditProjectionRejection.touchedOperationMismatch }
        try validateOperationOrder(operations)
        var objects = Set<String>()
        var assets = Set<String>()
        var supports = Set<String>()
        for operation in operations {
            switch operation {
            case .createAssetInstance(let entityID, _, let after, _):
                assets.insert(entityID)
                supports.insert(after.supportRelation.relationID)
            case .setAssetTransform(let entityID, _, _, _):
                assets.insert(entityID)
            case .setObjectVisibility(let entityID, _, _, _),
                 .setRevealBundle(let entityID, _, _, _):
                objects.insert(entityID)
            case .restoreSnapshot(_, let before, let after, _):
                let restoreTouched = try diff(sourceBefore: before.projection, sourceAfter: after.projection)
                objects.formUnion(restoreTouched.objectIDs)
                assets.formUnion(restoreTouched.placedAssetIDs)
                supports.formUnion(restoreTouched.assetSupportRelationIDs)
            }
        }
        let expected = EditProjectionTouchedIDs(
            objectIDs: objects.sorted(),
            placedAssetIDs: assets.sorted(),
            assetSupportRelationIDs: supports.sorted()
        )
        guard touched == expected else { throw EditProjectionRejection.touchedOperationMismatch }
    }

    public static func requiredArtifactReferences(for projection: EditProjection) throws -> [ArtifactReference] {
        try validate(projection)
        var refs = projection.placedAssets.map(\.manifestArtifactRef)
        refs.append(contentsOf: projection.objectEditStates.compactMap(\.activeReveal))
        for ref in refs { try validateArtifact(ref) }

        var byIdentity = [String: ArtifactReference]()
        for ref in refs {
            if let prior = byIdentity[ref.artifactID], prior != ref {
                throw EditProjectionRejection.invalidArtifactReference
            }
            byIdentity[ref.artifactID] = ref
        }
        return byIdentity.values.sorted(by: artifactLessThan)
    }

    public static func verifyRequiredArtifactReferences(
        _ references: [ArtifactReference],
        for projection: EditProjection
    ) throws {
        guard references == (try requiredArtifactReferences(for: projection)) else {
            throw EditProjectionRejection.artifactUnionMismatch
        }
    }

    public static func apply(
        sourceBefore: EditProjection,
        sourceAfter: EditProjection,
        to current: EditProjection,
        touched: EditProjectionTouchedIDs
    ) throws -> EditProjection {
        let exactTouched = try diff(sourceBefore: sourceBefore, sourceAfter: sourceAfter)
        guard touched == exactTouched else { throw EditProjectionRejection.touchedOperationMismatch }
        try validate(current)
        try requireSameIdentity(sourceBefore, current)

        var objects = Dictionary(uniqueKeysWithValues: current.objectEditStates.map { ($0.objectID, $0) })
        let sourceBeforeObjects = Dictionary(uniqueKeysWithValues: sourceBefore.objectEditStates.map { ($0.objectID, $0) })
        let sourceAfterObjects = Dictionary(uniqueKeysWithValues: sourceAfter.objectEditStates.map { ($0.objectID, $0) })
        try applyValues(ids: touched.objectIDs, sourceBefore: sourceBeforeObjects, sourceAfter: sourceAfterObjects, current: &objects)

        var assets = Dictionary(uniqueKeysWithValues: current.placedAssets.map { ($0.placedAssetID, $0) })
        let sourceBeforeAssets = Dictionary(uniqueKeysWithValues: sourceBefore.placedAssets.map { ($0.placedAssetID, $0) })
        let sourceAfterAssets = Dictionary(uniqueKeysWithValues: sourceAfter.placedAssets.map { ($0.placedAssetID, $0) })
        try applyValues(ids: touched.placedAssetIDs, sourceBefore: sourceBeforeAssets, sourceAfter: sourceAfterAssets, current: &assets)

        var supports = Dictionary(uniqueKeysWithValues: current.assetSupportRelations.map { ($0.relationID, $0) })
        let sourceBeforeSupports = Dictionary(uniqueKeysWithValues: sourceBefore.assetSupportRelations.map { ($0.relationID, $0) })
        let sourceAfterSupports = Dictionary(uniqueKeysWithValues: sourceAfter.assetSupportRelations.map { ($0.relationID, $0) })
        try applyValues(ids: touched.assetSupportRelationIDs, sourceBefore: sourceBeforeSupports, sourceAfter: sourceAfterSupports, current: &supports)

        let result = EditProjection(
            sceneID: current.sceneID,
            revisionBranchID: current.revisionBranchID,
            worldFrameID: current.worldFrameID,
            worldFrameVersion: current.worldFrameVersion,
            objectEditStates: objects.values.sorted { $0.objectID < $1.objectID },
            placedAssets: assets.values.sorted { $0.placedAssetID < $1.placedAssetID },
            assetSupportRelations: supports.values.sorted { $0.relationID < $1.relationID }
        )
        try validate(result)
        return result
    }

    public static func apply(
        projection: EditProjection,
        to scene: SceneState,
        pendingRevision: UInt64,
        appending historyEntry: EditReference,
        updatedAtUTC: String
    ) throws -> SceneState {
        let current = try build(from: scene)
        try requireSameIdentity(current, projection)
        try validate(projection)
        guard pendingRevision == scene.sceneRevision + 1,
              historyEntry.committedSceneRevision == pendingRevision
        else { throw EditProjectionRejection.invalidSceneRevision }

        let editStates = Dictionary(uniqueKeysWithValues: projection.objectEditStates.map { ($0.objectID, $0) })
        guard Set(editStates.keys) == Set(scene.objects.map(\.objectID)) else {
            throw EditProjectionRejection.incompleteProjection
        }
        let objects = scene.objects.map { object in
            let edit = editStates[object.objectID]!
            return SceneObject(
                contractObjectID: object.objectID,
                label: object.label,
                labelConfidence: object.labelConfidence,
                attributes: object.attributes,
                lifecycle: object.lifecycle,
                readiness: object.readiness,
                readinessReasons: object.readinessReasons,
                artifactRefs: object.artifactRefs,
                editState: ObjectEditState(contractVisible: edit.visible, activeReveal: edit.activeReveal),
                createdSceneRevision: object.createdSceneRevision,
                lastObservedFrameID: object.lastObservedFrameID,
                rendererBinding: object.rendererBinding
            )
        }
        let nonAssetSupports = scene.supportRelations.filter { !$0.subjectID.hasPrefix("assetinst_") }
        return SceneState(
            contractSchemaVersion: scene.schemaVersion,
            sessionID: scene.sessionID,
            sceneID: scene.sceneID,
            revisionAuthority: scene.revisionAuthority,
            sceneRevision: pendingRevision,
            worldFrame: scene.worldFrame,
            surfaces: scene.surfaces,
            objects: objects,
            supportRelations: nonAssetSupports + projection.assetSupportRelations,
            placedAssets: projection.placedAssets,
            editHistory: scene.editHistory + [historyEntry],
            updatedAtUTC: updatedAtUTC
        )
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private static func validateArtifact(_ ref: ArtifactReference) throws {
        let allowed = ["mask_volume", "surface_mesh", "obb", "occluder_chunk", "reveal_bundle", "asset_manifest", "world_frame_correction"]
        guard validID(ref.artifactID, prefix: "artifact_"),
              allowed.contains(ref.artifactType),
              ref.artifactRevision > 0,
              ref.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
        else { throw EditProjectionRejection.invalidArtifactReference }
    }

    private static func validateOrderAndUniqueness(_ ids: [String]) throws {
        if Set(ids).count != ids.count { throw EditProjectionRejection.duplicateID }
        if ids != ids.sorted() { throw EditProjectionRejection.nonLexicographicOrder }
    }

    private static func requireUnique(_ ids: [String]) throws {
        guard Set(ids).count == ids.count else { throw EditProjectionRejection.duplicateID }
    }

    private static func requireSameIdentity(_ lhs: EditProjection, _ rhs: EditProjection) throws {
        guard lhs.sceneID == rhs.sceneID,
              lhs.revisionBranchID == rhs.revisionBranchID,
              lhs.worldFrameID == rhs.worldFrameID,
              lhs.worldFrameVersion == rhs.worldFrameVersion
        else { throw EditProjectionRejection.identityMismatch }
    }

    private static func validateTouchedOrder(_ derivation: RestoreRebaseDerivation) throws {
        try validateOrderAndUniqueness(derivation.touchedObjectIDs)
        try validateOrderAndUniqueness(derivation.touchedPlacedAssetIDs)
        try validateOrderAndUniqueness(derivation.touchedAssetSupportRelationIDs)
    }

    private static func validateOperationOrder(_ operations: [TransactionOperation]) throws {
        let kinds = operations.map { operation -> String in
            switch operation {
            case .createAssetInstance: "create_asset_instance"
            case .setAssetTransform: "set_asset_transform"
            case .setObjectVisibility: "set_object_visibility"
            case .setRevealBundle: "set_reveal_bundle"
            case .restoreSnapshot: "restore_snapshot"
            }
        }
        let allowed = [
            ["create_asset_instance"],
            ["set_object_visibility", "create_asset_instance"],
            ["set_reveal_bundle", "set_object_visibility", "create_asset_instance"],
            ["set_reveal_bundle", "set_object_visibility"],
            ["restore_snapshot"],
        ]
        guard allowed.contains(kinds) else { throw EditProjectionRejection.operationOrderMismatch }
    }

    private static func differingIDs<Value: Equatable>(_ lhs: [String: Value], _ rhs: [String: Value]) -> [String] {
        Set(lhs.keys).union(rhs.keys).filter { lhs[$0] != rhs[$0] }.sorted()
    }

    private static func applyValues<Value: Equatable>(
        ids: [String],
        sourceBefore: [String: Value],
        sourceAfter: [String: Value],
        current: inout [String: Value]
    ) throws {
        for id in ids {
            guard current[id] == sourceBefore[id] else {
                throw EditProjectionRejection.unexpectedTouchedEntityDrift
            }
            current[id] = sourceAfter[id]
        }
    }

    private static func artifactLessThan(_ lhs: ArtifactReference, _ rhs: ArtifactReference) -> Bool {
        if lhs.artifactID != rhs.artifactID { return lhs.artifactID < rhs.artifactID }
        if lhs.artifactType != rhs.artifactType { return lhs.artifactType < rhs.artifactType }
        if lhs.artifactRevision != rhs.artifactRevision { return lhs.artifactRevision < rhs.artifactRevision }
        return lhs.sha256 < rhs.sha256
    }

    private static func validID(_ value: String, prefix: String) -> Bool {
        let uuid = "[0-9a-f]{8}-[0-9a-f]{4}-[47][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}"
        return value.range(of: "^\(NSRegularExpression.escapedPattern(for: prefix))\(uuid)$", options: .regularExpression) != nil
    }
}
