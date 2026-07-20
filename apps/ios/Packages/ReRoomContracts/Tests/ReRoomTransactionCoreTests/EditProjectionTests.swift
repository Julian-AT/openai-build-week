import Foundation
import ReRoomContracts
@testable import ReRoomTransactionCore
import Testing

@Suite("RR-EDIT-PROJECTION-1")
struct EditProjectionTests {
    @Test("construction is complete, sorted, and hashes only the projection member")
    func constructionAndDigestScopeAreExact() throws {
        let scene = TransactionTestFixtures.scene(revision: 4)
        let projection = try EditProjectionEngine.build(from: scene)

        #expect(projection.projectionVersion == "RR-EDIT-PROJECTION-1")
        #expect(projection.objectEditStates.map(\.objectID) == TransactionTestFixtures.objectIDs.sorted())
        #expect(projection.placedAssets.map(\.placedAssetID) == TransactionTestFixtures.assetInstanceIDs.sorted())
        #expect(projection.assetSupportRelations.map(\.relationID) == TransactionTestFixtures.assetSupportIDs.sorted())
        #expect(projection.assetSupportRelations.allSatisfy { $0.subjectID.hasPrefix("assetinst_") })

        let digest = try EditProjectionEngine.digest(projection)
        let semanticallyNewer = TransactionTestFixtures.scene(
            revision: 99,
            labelSuffix: " changed",
            readiness: "degraded",
            timestamp: "2026-07-18T15:00:00Z"
        )
        #expect(try EditProjectionEngine.digest(EditProjectionEngine.build(from: semanticallyNewer)) == digest)

        let changedEdit = TransactionTestFixtures.scene(revision: 4, firstObjectVisible: false)
        #expect(try EditProjectionEngine.digest(EditProjectionEngine.build(from: changedEdit)) != digest)

        let snapshot = try EditProjectionEngine.snapshot(
            projection,
            capturedSceneRevision: 4,
            origin: .capturedExact
        )
        #expect(snapshot.projectionSHA256 == digest)
        #expect(snapshot.derivation == nil)
    }

    @Test(
        "semantic projection corruption rejects before output",
        arguments: ProjectionCorruption.allCases
    )
    func corruptProjectionRejects(corruption: ProjectionCorruption) throws {
        let valid = try EditProjectionEngine.build(from: TransactionTestFixtures.scene(revision: 4))
        let corrupt = corruption.apply(to: valid)
        #expect(throws: corruption.expectedError) {
            try EditProjectionEngine.validate(corrupt)
        }
    }

    @Test("diff, ordered operations, artifact union, and touched application are exact")
    func diffAndApplicationAreExact() throws {
        let prePlace = try EditProjectionEngine.build(from: TransactionTestFixtures.scene(revision: 3, includeFirstAsset: false))
        let committed = try EditProjectionEngine.build(from: TransactionTestFixtures.scene(revision: 4))
        let touched = try EditProjectionEngine.diff(sourceBefore: committed, sourceAfter: prePlace)

        #expect(touched.objectIDs == [])
        #expect(touched.placedAssetIDs == [TransactionTestFixtures.assetInstanceIDs[0]])
        #expect(touched.assetSupportRelationIDs == [TransactionTestFixtures.assetSupportIDs[0]])

        let operation = TransactionTestFixtures.createFirstAssetOperation()
        try EditProjectionEngine.verify(touched: touched, against: [operation])

        let refs = try EditProjectionEngine.requiredArtifactReferences(for: prePlace)
        #expect(refs == [TransactionTestFixtures.secondManifest])
        #expect(throws: EditProjectionRejection.artifactUnionMismatch) {
            try EditProjectionEngine.verifyRequiredArtifactReferences([], for: prePlace)
        }
        #expect(throws: EditProjectionRejection.artifactUnionMismatch) {
            try EditProjectionEngine.verifyRequiredArtifactReferences([TransactionTestFixtures.staleSecondManifest], for: prePlace)
        }

        let current = try EditProjectionEngine.build(from: TransactionTestFixtures.scene(revision: 8, includeNewObject: true))
        let rebased = try EditProjectionEngine.apply(
            sourceBefore: committed,
            sourceAfter: prePlace,
            to: current,
            touched: touched
        )
        #expect(rebased.objectEditStates.map(\.objectID).contains(TransactionTestFixtures.newObjectID))
        #expect(!rebased.placedAssets.map(\.placedAssetID).contains(TransactionTestFixtures.assetInstanceIDs[0]))
        #expect(rebased.placedAssets.map(\.placedAssetID).contains(TransactionTestFixtures.assetInstanceIDs[1]))

        let drifted = TransactionTestFixtures.replacingFirstAssetState(in: current, state: "hidden")
        #expect(throws: EditProjectionRejection.unexpectedTouchedEntityDrift) {
            try EditProjectionEngine.apply(
                sourceBefore: committed,
                sourceAfter: prePlace,
                to: drifted,
                touched: touched
            )
        }
        #expect(throws: EditProjectionRejection.touchedOperationMismatch) {
            try EditProjectionEngine.verify(touched: touched, against: [])
        }
    }
}

enum ProjectionCorruption: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case duplicateObject
    case unsortedObject
    case danglingSupport
    case wrongBranch
    case staleManifestType

    var testDescription: String { rawValue }

    var expectedError: EditProjectionRejection {
        switch self {
        case .duplicateObject: .duplicateID
        case .unsortedObject: .nonLexicographicOrder
        case .danglingSupport: .danglingSupport
        case .wrongBranch: .identityMismatch
        case .staleManifestType: .invalidArtifactReference
        }
    }

    func apply(to value: EditProjection) -> EditProjection {
        var objects = value.objectEditStates
        var assets = value.placedAssets
        var supports = value.assetSupportRelations
        var branch = value.revisionBranchID
        switch self {
        case .duplicateObject:
            objects.append(objects[0])
        case .unsortedObject:
            objects.reverse()
        case .danglingSupport:
            supports[0] = SupportRelation(
                contractRelationID: supports[0].relationID,
                subjectID: TransactionTestFixtures.missingAssetID,
                surfaceID: supports[0].surfaceID,
                confidence: supports[0].confidence,
                method: supports[0].method
            )
        case .wrongBranch:
            branch = "not-a-branch"
        case .staleManifestType:
            let asset = assets[0]
            assets[0] = PlacedAsset(
                contractPlacedAssetID: asset.placedAssetID,
                assetID: asset.assetID,
                manifestArtifactRef: ArtifactReference(
                    artifactID: asset.manifestArtifactRef.artifactID,
                    artifactType: "reveal_bundle",
                    artifactRevision: asset.manifestArtifactRef.artifactRevision,
                    sha256: asset.manifestArtifactRef.sha256
                ),
                worldFromAsset: asset.worldFromAsset,
                state: asset.state,
                supportRelationID: asset.supportRelationID,
                sourceTransactionID: asset.sourceTransactionID
            )
        }
        return EditProjection(
            contractProjectionVersion: value.projectionVersion,
            sceneID: value.sceneID,
            revisionBranchID: branch,
            worldFrameID: value.worldFrameID,
            worldFrameVersion: value.worldFrameVersion,
            objectEditStates: objects,
            placedAssets: assets,
            assetSupportRelations: supports
        )
    }
}

enum TransactionTestFixtures {
    static let sceneID = "scene_10000000-0000-4000-8000-000000000001"
    static let sessionID = "session_10000000-0000-4000-8000-000000000002"
    static let branchID = "branch_10000000-0000-4000-8000-000000000003"
    static let deviceID = "device_10000000-0000-4000-8000-000000000004"
    static let worldID = "world_10000000-0000-4000-8000-000000000005"
    static let frameID = "frame_10000000-0000-4000-8000-000000000006"
    static let surfaceID = "surface_10000000-0000-4000-8000-000000000007"
    static let objectIDs = [
        "object_10000000-0000-4000-8000-000000000008",
        "object_10000000-0000-4000-8000-000000000009",
    ]
    static let newObjectID = "object_10000000-0000-4000-8000-00000000000a"
    static let assetInstanceIDs = [
        "assetinst_10000000-0000-4000-8000-00000000000b",
        "assetinst_10000000-0000-4000-8000-00000000000c",
    ]
    static let missingAssetID = "assetinst_10000000-0000-4000-8000-00000000000d"
    static let assetSupportIDs = [
        "support_10000000-0000-4000-8000-00000000000e",
        "support_10000000-0000-4000-8000-00000000000f",
    ]
    static let objectSupportID = "support_10000000-0000-4000-8000-000000000010"
    static let transactionIDs = [
        "tx_10000000-0000-4000-8000-000000000011",
        "tx_10000000-0000-4000-8000-000000000012",
    ]
    static let firstManifest = ArtifactReference(
        artifactID: "artifact_10000000-0000-4000-8000-000000000013",
        artifactType: "asset_manifest",
        artifactRevision: 1,
        sha256: String(repeating: "1", count: 64)
    )
    static let secondManifest = ArtifactReference(
        artifactID: "artifact_10000000-0000-4000-8000-000000000014",
        artifactType: "asset_manifest",
        artifactRevision: 2,
        sha256: String(repeating: "2", count: 64)
    )
    static let staleSecondManifest = ArtifactReference(
        artifactID: secondManifest.artifactID,
        artifactType: secondManifest.artifactType,
        artifactRevision: 1,
        sha256: secondManifest.sha256
    )

    static let identity = Matrix4(values: [
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    ])

    static func scene(
        revision: UInt64,
        includeFirstAsset: Bool = true,
        includeNewObject: Bool = false,
        labelSuffix: String = "",
        readiness: String = "ready",
        timestamp: String = "2026-07-18T14:00:00Z",
        firstObjectVisible: Bool = true
    ) -> SceneState {
        let ready = Readiness(contractSelect: readiness, place: readiness, replace: readiness, remove: readiness, restore: readiness)
        let reasons = ReadinessReasons(contractSelect: [], place: [], replace: [], remove: [], restore: [])
        func object(_ id: String, visible: Bool = true) -> SceneObject {
            SceneObject(
                contractObjectID: id,
                label: "chair\(labelSuffix)",
                labelConfidence: 0.9,
                lifecycle: "tracked",
                readiness: ready,
                readinessReasons: reasons,
                artifactRefs: [],
                editState: ObjectEditState(contractVisible: visible, activeReveal: nil),
                createdSceneRevision: 0,
                lastObservedFrameID: frameID
            )
        }
        var objects = [object(objectIDs[1]), object(objectIDs[0], visible: firstObjectVisible)]
        if includeNewObject { objects.append(object(newObjectID)) }

        let assets = [
            placedAsset(index: 1),
            includeFirstAsset ? placedAsset(index: 0) : nil,
        ].compactMap { $0 }
        let supports = [
            SupportRelation(contractRelationID: objectSupportID, subjectID: objectIDs[0], surfaceID: surfaceID, confidence: 1, method: "arkit_plane"),
            assetSupport(index: 1),
            includeFirstAsset ? assetSupport(index: 0) : nil,
        ].compactMap { $0 }

        return SceneState(
            sessionID: sessionID,
            sceneID: sceneID,
            revisionAuthority: RevisionAuthority(kind: .nativeDevice, authorityID: deviceID, revisionBranchID: branchID),
            sceneRevision: revision,
            worldFrame: WorldFrame(contractWorldFrameID: worldID, worldFrameVersion: 1, createdByFrameID: frameID),
            surfaces: [SceneSurface(contractSurfaceID: surfaceID, kind: "floor", worldFromSurface: identity, extentM: [4, 4], confidence: 1, lifecycle: "tracked", artifactRefs: [])],
            objects: objects,
            supportRelations: supports,
            placedAssets: assets,
            editHistory: [],
            updatedAtUTC: timestamp
        )
    }

    static func placedAsset(index: Int) -> PlacedAsset {
        PlacedAsset(
            contractPlacedAssetID: assetInstanceIDs[index],
            assetID: "asset_10000000-0000-4000-8000-00000000002\(index)",
            manifestArtifactRef: index == 0 ? firstManifest : secondManifest,
            worldFromAsset: identity,
            state: "committed",
            supportRelationID: assetSupportIDs[index],
            sourceTransactionID: transactionIDs[index]
        )
    }

    static func assetSupport(index: Int) -> SupportRelation {
        SupportRelation(
            contractRelationID: assetSupportIDs[index],
            subjectID: assetInstanceIDs[index],
            surfaceID: surfaceID,
            confidence: 1,
            method: "arkit_plane"
        )
    }

    static func createFirstAssetOperation() -> TransactionOperation {
        .createAssetInstance(
            entityID: assetInstanceIDs[0],
            before: nil,
            after: AssetInstanceSnapshot(
                contractAssetID: placedAsset(index: 0).assetID,
                manifestArtifactRef: firstManifest,
                worldFromAsset: identity,
                supportRelation: AssetSupportSnapshot(
                    contractRelationID: assetSupportIDs[0],
                    surfaceID: surfaceID,
                    confidence: 1,
                    method: "arkit_plane"
                )
            ),
            requiredArtifactRefs: [firstManifest]
        )
    }

    static func replacingFirstAssetState(in projection: EditProjection, state: String) -> EditProjection {
        var assets = projection.placedAssets
        let index = assets.firstIndex { $0.placedAssetID == assetInstanceIDs[0] }!
        let asset = assets[index]
        assets[index] = PlacedAsset(
            contractPlacedAssetID: asset.placedAssetID,
            assetID: asset.assetID,
            manifestArtifactRef: asset.manifestArtifactRef,
            worldFromAsset: asset.worldFromAsset,
            state: state,
            supportRelationID: asset.supportRelationID,
            sourceTransactionID: asset.sourceTransactionID
        )
        return EditProjection(
            sceneID: projection.sceneID,
            revisionBranchID: projection.revisionBranchID,
            worldFrameID: projection.worldFrameID,
            worldFrameVersion: projection.worldFrameVersion,
            objectEditStates: projection.objectEditStates,
            placedAssets: assets,
            assetSupportRelations: projection.assetSupportRelations
        )
    }
}
