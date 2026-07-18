import ARKit
import Foundation
import Observation
import ReRoomCaptureCore
import ReRoomContracts
import ReRoomTransactionCore

enum RoomEditOperation: String, CaseIterable, Identifiable, Sendable {
    case place
    case replace
    case remove
    case restore

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum RoomEditBlocker: Equatable, Sendable {
    case healthySupportRequired
    case replaceDeferred
    case removeDeferred
    case restoreSourceRequired
    case transactionRejected(String)
}

enum RoomEditLocalState: String, Equatable, Sendable {
    case ready = "Local store ready"
    case durable = "Saved locally"
}

struct RoomEditPreviewSnapshot: Equatable, Sendable {
    let proxyID: String
    let baseRevision: UInt64
    let currentRevision: UInt64
    let supportStatus: String
}

struct RoomEditSnapshot: Equatable, Sendable {
    let operations: [RoomEditOperation]
    let selectedOperation: RoomEditOperation?
    let revision: UInt64
    let preview: RoomEditPreviewSnapshot?
    let blocker: RoomEditBlocker?
    let localState: RoomEditLocalState
    let placedAssetVisible: Bool
    let canConfirm: Bool
    let canRestore: Bool
    let status: String

    static let loading = RoomEditSnapshot(
        operations: RoomEditOperation.allCases,
        selectedOperation: nil,
        revision: 0,
        preview: nil,
        blocker: nil,
        localState: .ready,
        placedAssetVisible: false,
        canConfirm: false,
        canRestore: false,
        status: "Loading local room state"
    )
}

struct RoomEditSupportContext: Equatable, Sendable {
    let capturedFrameID: String
    let surfaceID: String
    let cameraPose: Matrix4
    let worldFromAsset: Matrix4
    let confidence: Double
    let method: String
}

typealias RoomEditSupportProvider = @MainActor @Sendable (SceneState) async -> RoomEditSupportContext?

struct Phase3ProxyManifest: Codable, Equatable, Sendable {
    let schemaVersion: String
    let proxyID: String
    let contractAssetID: String
    let artifactID: String
    let artifactType: String
    let artifactRevision: UInt64
    let sourceFile: String
    let sourceSHA256: String
    let provenanceFile: String
    let generationRecipe: String
    let qualification: String

    var artifactReference: ArtifactReference {
        ArtifactReference(
            artifactID: artifactID,
            artifactType: artifactType,
            artifactRevision: artifactRevision,
            sha256: sourceSHA256
        )
    }

    static func load(bundle: Bundle) throws -> Phase3ProxyManifest {
        guard let manifestURL = bundle.url(forResource: "asset-manifest", withExtension: "json"),
              let sourceURL = bundle.url(forResource: "proxy-chair", withExtension: "usda")
        else { throw RoomEditSetupError.missingProxyResource }
        let data = try Data(contentsOf: manifestURL)
        guard let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(raw.keys) == Set(CodingKeys.allCases.map(\.rawValue))
        else { throw RoomEditSetupError.openProxyManifest }
        let manifest = try JSONDecoder().decode(Self.self, from: data)
        guard manifest.schemaVersion == "1.0.0",
              manifest.proxyID == "asset_proxy-chair-phase3",
              manifest.artifactType == "asset_manifest",
              manifest.artifactRevision == 1,
              manifest.sourceFile == "proxy-chair.usda",
              manifest.provenanceFile == "PROVENANCE.md",
              manifest.qualification == "phase3_local_demo_proxy_only",
              manifest.contractAssetID.hasPrefix("asset_"),
              manifest.artifactID.hasPrefix("artifact_"),
              manifest.sourceSHA256 == CanonicalJSON.sha256Hex(try Data(contentsOf: sourceURL))
        else { throw RoomEditSetupError.invalidProxyManifest }
        return manifest
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case proxyID = "proxy_id"
        case contractAssetID = "contract_asset_id"
        case artifactID = "artifact_id"
        case artifactType = "artifact_type"
        case artifactRevision = "artifact_revision"
        case sourceFile = "source_file"
        case sourceSHA256 = "source_sha256"
        case provenanceFile = "provenance_file"
        case generationRecipe = "generation_recipe"
        case qualification
    }
}

@MainActor
@Observable
final class RoomEditModel {
    private(set) var snapshot: RoomEditSnapshot = .loading

    @ObservationIgnored private let authority: NativeBranchAuthority
    @ObservationIgnored private let manifest: Phase3ProxyManifest
    @ObservationIgnored private let supportProvider: RoomEditSupportProvider
    @ObservationIgnored private var placePreview: PlacePreviewReduction?

    init(
        authority: NativeBranchAuthority,
        manifest: Phase3ProxyManifest,
        supportProvider: @escaping RoomEditSupportProvider
    ) {
        self.authority = authority
        self.manifest = manifest
        self.supportProvider = supportProvider
    }

    func prepare() async {
        placePreview = nil
        await refresh(status: "Local room state recovered")
    }

    func selectOperation(_ operation: RoomEditOperation) async {
        placePreview = nil
        switch operation {
        case .place:
            await proposePlace()
        case .replace:
            await refresh(
                selected: operation,
                blocker: .replaceDeferred,
                status: "Replace needs the later target-and-reveal capability"
            )
        case .remove:
            await refresh(
                selected: operation,
                blocker: .removeDeferred,
                status: "Remove needs the later target-and-reveal capability"
            )
        case .restore:
            let active = await authority.activeSnapshot()
            await publish(
                active,
                selected: operation,
                blocker: hasEligibleRestore(in: active) ? nil : .restoreSourceRequired,
                status: hasEligibleRestore(in: active)
                    ? "Restore is ready offline"
                    : "Restore needs a committed place"
            )
        }
    }

    func cancelPreview() async {
        guard let preview = placePreview else { return }
        do {
            let active = await authority.activeSnapshot()
            _ = try PlaceReducer.cancel(preview, currentScene: active.scene)
            placePreview = nil
            await publish(active, selected: .place, status: "Provisional placement cancelled; revision unchanged")
        } catch {
            await fail(error)
        }
    }

    /// This is the sole place-confirmation ingress. RoomEditView invokes it only from a native Button.
    func confirmPlacementFromButton() async {
        guard let preview = placePreview else { return }
        do {
            _ = try await authority.commitPlace(
                preview,
                confirmation: ExplicitConfirmation(
                    actorID: RoomEditIdentity.userID,
                    source: "native_ui",
                    previewID: preview.preview.previewID,
                    confirmationEventID: RoomEditIdentity.placeEventID,
                    confirmedAtUTC: RoomEditIdentity.placeTimestamp
                ),
                request: PlaceConfirmationRequest(
                    transactionID: RoomEditIdentity.placeTransactionID,
                    idempotencyKey: RoomEditIdentity.placeIdempotencyKey,
                    updatedAtUTC: RoomEditIdentity.placeTimestamp
                ),
                localUndoToken: RoomEditIdentity.placeUndoToken
            )
            placePreview = nil
            await refresh(selected: .place, status: "Placement committed and saved locally")
        } catch {
            await fail(error)
        }
    }

    /// This is the sole restore-confirmation ingress. RoomEditView invokes it only from a native Button.
    func restoreFromButton() async {
        do {
            let active = await authority.activeSnapshot()
            guard let source = eligibleRestoreSource(in: active) else {
                await publish(
                    active,
                    selected: .restore,
                    blocker: .restoreSourceRequired,
                    status: "Restore needs a committed place"
                )
                return
            }
            let proposal = proposal(for: .restore, scene: active.scene, support: nil)
            let reduction = try await authority.previewRestore(
                proposal: proposal,
                request: RestoreRequest(
                    transactionID: RoomEditIdentity.restoreTransactionID,
                    compensatesTransactionID: source.transactionID,
                    updatedAtUTC: RoomEditIdentity.restoreTimestamp
                ),
                seed: RestorePreviewSeed(
                    previewID: RoomEditIdentity.restorePreviewID,
                    expiresAtUTC: RoomEditIdentity.previewExpiry
                )
            )
            _ = try await authority.commitRestore(
                reduction,
                confirmation: ExplicitConfirmation(
                    actorID: RoomEditIdentity.userID,
                    source: "native_ui",
                    previewID: reduction.preview.previewID,
                    confirmationEventID: RoomEditIdentity.restoreEventID,
                    confirmedAtUTC: RoomEditIdentity.restoreTimestamp
                ),
                idempotencyKey: RoomEditIdentity.restoreIdempotencyKey,
                localUndoToken: RoomEditIdentity.restoreUndoToken
            )
            await refresh(selected: .restore, status: "Restore committed as a new local revision")
        } catch {
            await fail(error)
        }
    }

    private func proposePlace() async {
        do {
            let active = await authority.activeSnapshot()
            guard let support = await supportProvider(active.scene),
                  support.surfaceID == RoomEditIdentity.surfaceID
            else {
                await publish(
                    active,
                    selected: .place,
                    blocker: .healthySupportRequired,
                    status: "Place needs normal tracking and a visible horizontal floor"
                )
                return
            }
            let reduction = try await authority.previewPlace(
                proposal: proposal(for: .place, scene: active.scene, support: support),
                candidate: DeterministicPlaceCandidate(
                    asset: ProxyAssetCandidate(
                        assetID: manifest.contractAssetID,
                        placedAssetID: RoomEditIdentity.placedAssetID,
                        manifestArtifactRef: manifest.artifactReference,
                        allowlisted: true,
                        collisionProxyPassed: true,
                        assetLicensePassed: true,
                        artifactIntegrityPassed: true
                    ),
                    support: DeterministicSupportCandidate(
                        relationID: RoomEditIdentity.supportRelationID,
                        surfaceID: support.surfaceID,
                        worldFrameID: active.scene.worldFrame.worldFrameID,
                        worldFrameVersion: active.scene.worldFrame.worldFrameVersion,
                        capturedSceneRevision: active.scene.sceneRevision,
                        worldFromAsset: support.worldFromAsset,
                        confidence: support.confidence,
                        method: support.method
                    )
                ),
                seed: PlacePreviewSeed(
                    transactionID: RoomEditIdentity.placeTransactionID,
                    previewID: RoomEditIdentity.placePreviewID,
                    expiresAtUTC: RoomEditIdentity.previewExpiry
                )
            )
            placePreview = reduction
            snapshot = RoomEditSnapshot(
                operations: RoomEditOperation.allCases,
                selectedOperation: .place,
                revision: active.scene.sceneRevision,
                preview: RoomEditPreviewSnapshot(
                    proxyID: manifest.proxyID,
                    baseRevision: reduction.preview.baseSceneRevision,
                    currentRevision: active.scene.sceneRevision,
                    supportStatus: "Captured healthy horizontal support"
                ),
                blocker: nil,
                localState: active.receipts.isEmpty ? .ready : .durable,
                placedAssetVisible: active.scene.placedAssets.isEmpty == false,
                canConfirm: true,
                canRestore: hasEligibleRestore(in: active),
                status: "Provisional Phase 3 proxy; confirm or cancel"
            )
        } catch {
            await fail(error)
        }
    }

    private func proposal(
        for operation: ProductOperation,
        scene: SceneState,
        support: RoomEditSupportContext?
    ) -> BoundProposal {
        BoundProposal(
            sessionID: scene.sessionID,
            revisionAuthority: scene.revisionAuthority,
            baseSceneRevision: scene.sceneRevision,
            targetContext: TargetContext(
                contractCapturedAtFrameID: support?.capturedFrameID ?? RoomEditIdentity.frameID,
                capturedSceneRevision: scene.sceneRevision,
                worldFrameID: scene.worldFrame.worldFrameID,
                worldFrameVersion: scene.worldFrame.worldFrameVersion,
                cameraPose: support?.cameraPose ?? .identity,
                screenPointEncodedPixels: [1, 1],
                candidateObjectIDs: [],
                selectedObjectID: nil,
                artifactRefs: []
            ),
            intent: TransactionIntent(
                contractOperation: operation,
                source: "tap",
                arguments: operation == .place
                    ? IntentArguments(assetID: manifest.contractAssetID)
                    : IntentArguments(),
                constraints: []
            )
        )
    }

    private func refresh(
        selected: RoomEditOperation? = nil,
        blocker: RoomEditBlocker? = nil,
        status: String
    ) async {
        await publish(
            authority.activeSnapshot(),
            selected: selected,
            blocker: blocker,
            status: status
        )
    }

    private func publish(
        _ active: TransactionGenerationSnapshot,
        selected: RoomEditOperation? = nil,
        blocker: RoomEditBlocker? = nil,
        status: String
    ) async {
        snapshot = RoomEditSnapshot(
            operations: RoomEditOperation.allCases,
            selectedOperation: selected,
            revision: active.scene.sceneRevision,
            preview: nil,
            blocker: blocker,
            localState: active.receipts.isEmpty ? .ready : .durable,
            placedAssetVisible: active.scene.placedAssets.isEmpty == false,
            canConfirm: false,
            canRestore: hasEligibleRestore(in: active),
            status: status
        )
    }

    private func fail(_ error: any Error) async {
        placePreview = nil
        await refresh(
            blocker: .transactionRejected(String(describing: error)),
            status: "Local transaction rejected safely"
        )
    }

    private func hasEligibleRestore(in active: TransactionGenerationSnapshot) -> Bool {
        eligibleRestoreSource(in: active) != nil
    }

    private func eligibleRestoreSource(in active: TransactionGenerationSnapshot) -> TransactionRecord? {
        let compensated = Set(active.transactions.compactMap(\.compensatesTransactionID))
        return active.transactions.reversed().first {
            $0.intent.operation == .place
                && $0.canonicalState == .committed
                && $0.inverseOperations?.isEmpty == false
                && !compensated.contains($0.transactionID)
        }
    }
}

enum RoomEditIdentity {
    static let sessionID = "session_53000000-0000-4000-8000-000000000010"
    static let sceneID = "scene_53000000-0000-4000-8000-000000000011"
    static let deviceID = "device_53000000-0000-4000-8000-000000000012"
    static let branchID = "branch_53000000-0000-4000-8000-000000000013"
    static let worldFrameID = "world_53000000-0000-4000-8000-000000000014"
    static let frameID = "frame_53000000-0000-4000-8000-000000000015"
    static let surfaceID = "surface_53000000-0000-4000-8000-000000000016"
    static let placedAssetID = "assetinst_53000000-0000-4000-8000-000000000017"
    static let supportRelationID = "support_53000000-0000-4000-8000-000000000018"
    static let userID = "user_53000000-0000-4000-8000-000000000019"
    static let placeTransactionID = "tx_53000000-0000-4000-8000-000000000020"
    static let placePreviewID = "preview_53000000-0000-4000-8000-000000000021"
    static let placeIdempotencyKey = "txidem_53000000-0000-4000-8000-000000000022"
    static let placeUndoToken = "undo_53000000-0000-4000-8000-000000000023"
    static let placeEventID = "event_53000000-0000-4000-8000-000000000024"
    static let restoreTransactionID = "tx_53000000-0000-4000-8000-000000000025"
    static let restorePreviewID = "preview_53000000-0000-4000-8000-000000000026"
    static let restoreIdempotencyKey = "txidem_53000000-0000-4000-8000-000000000027"
    static let restoreUndoToken = "undo_53000000-0000-4000-8000-000000000028"
    static let restoreEventID = "event_53000000-0000-4000-8000-000000000029"
    static let bootstrapTimestamp = "2026-07-18T12:00:00Z"
    static let placeTimestamp = "2026-07-18T12:01:00Z"
    static let restoreTimestamp = "2026-07-18T12:02:00Z"
    static let previewExpiry = "2027-07-18T12:00:00Z"
}

enum RoomEditFactory {
    static func bootstrap(manifest: Phase3ProxyManifest) -> TransactionGenerationCandidate {
        let scene = SceneState(
            sessionID: RoomEditIdentity.sessionID,
            sceneID: RoomEditIdentity.sceneID,
            revisionAuthority: RevisionAuthority(
                kind: .nativeDevice,
                authorityID: RoomEditIdentity.deviceID,
                revisionBranchID: RoomEditIdentity.branchID
            ),
            sceneRevision: 0,
            worldFrame: WorldFrame(
                contractWorldFrameID: RoomEditIdentity.worldFrameID,
                worldFrameVersion: 1,
                createdByFrameID: RoomEditIdentity.frameID
            ),
            surfaces: [SceneSurface(
                contractSurfaceID: RoomEditIdentity.surfaceID,
                kind: "floor",
                worldFromSurface: .identity,
                extentM: [4, 4],
                confidence: 1,
                lifecycle: "tracked",
                artifactRefs: []
            )],
            objects: [],
            supportRelations: [],
            placedAssets: [],
            editHistory: [],
            updatedAtUTC: RoomEditIdentity.bootstrapTimestamp
        )
        return TransactionGenerationCandidate(
            scene: scene,
            transactions: [],
            requiredArtifacts: [],
            receipts: [],
            idempotencyRecords: []
        )
    }

    @MainActor
    static func live(resetStore: Bool = false, useFixtureSupport: Bool = false) throws -> RoomEditModel {
        let manifest = try Phase3ProxyManifest.load(bundle: .main)
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = documents.appendingPathComponent("phase3-room-edit", isDirectory: true)
        if resetStore, FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = TransactionStore(
            fileSystem: TransactionFileSystemAdapter(
                fileSystem: try ReRoomCaptureCore.FoundationCaptureFileSystem(root: root),
                rootPath: "transactions"
            ),
            contracts: TransactionContractAdapter(validator: try contractValidator(bundle: .main))
        )
        let authority = try NativeBranchAuthority(
            store: store,
            bootstrap: bootstrap(manifest: manifest),
            locallyAvailableArtifacts: [manifest.artifactReference]
        )
        let deviceProof = DeviceProofModel()
        return RoomEditModel(
            authority: authority,
            manifest: manifest,
            supportProvider: { scene in
                if useFixtureSupport {
                    return RoomEditSupportContext(
                        capturedFrameID: RoomEditIdentity.frameID,
                        surfaceID: RoomEditIdentity.surfaceID,
                        cameraPose: .identity,
                        worldFromAsset: Matrix4(values: [
                            1, 0, 0, 0,
                            0, 1, 0, 0,
                            0, 0, 1, -1.2,
                            0, 0, 0, 1,
                        ]),
                        confidence: 0.95,
                        method: "arkit_plane"
                    )
                }
                await deviceProof.prepare()
                guard deviceProof.state.visualFrameCaptureAvailable,
                      deviceProof.state.horizontalPlaneObserved,
                      let frame = deviceProof.currentARFrame
                else { return nil }
                let camera = Matrix4(simdTransform: frame.camera.transform)
                var placement = camera.values
                placement[3] += camera.values[2] * -1.2
                placement[7] += camera.values[6] * -1.2
                placement[11] += camera.values[10] * -1.2
                return RoomEditSupportContext(
                    capturedFrameID: RoomEditIdentity.frameID,
                    surfaceID: RoomEditIdentity.surfaceID,
                    cameraPose: camera,
                    worldFromAsset: Matrix4(values: placement),
                    confidence: 0.9,
                    method: "arkit_plane"
                )
            }
        )
    }

    private static func contractValidator(bundle: Bundle) throws -> ContractValidator {
        let resources: [(ContractSchemaIdentifier, String, String)] = [
            (.framePacket, "frame-packet", "d50b19bfb29c6c62c494e3a47deb3c51a933609698f4ff2f9cbfba6ec4252b43"),
            (.rrcapManifest, "rrcap-manifest", "c97349820ed66fb1a1fdf60ea9afee312f532811602851d01d1e233641730b87"),
            (.sceneState, "scene-state", "9c77d27762e20ff5fad24c438e8817a03c770b55be3fc82ea72097c4c273e440"),
            (.editArtifacts, "edit-artifacts", "58dbfc8f152881cbdc31be22f6ab7631ac474bb78537ac2a9254f5ef16bd598f"),
            (.transaction, "transaction", "2a4f6728978db0879b5dfb10f052f6d5280e5cf83ad5600f0cf959626c2399a2"),
        ]
        return try ContractValidator(registrations: resources.map { identifier, name, digest in
            guard let url = bundle.url(forResource: "\(name).schema", withExtension: "json") else {
                throw RoomEditSetupError.missingContractSchema
            }
            return ContractSchemaRegistration(
                identifier: identifier,
                version: "1.0.0",
                sha256: digest,
                schemaData: try Data(contentsOf: url)
            )
        })
    }
}

extension Matrix4 {
    static let identity = Matrix4(values: [
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    ])

    init(simdTransform value: simd_float4x4) {
        self.init(values: [
            Double(value.columns.0.x), Double(value.columns.1.x), Double(value.columns.2.x), Double(value.columns.3.x),
            Double(value.columns.0.y), Double(value.columns.1.y), Double(value.columns.2.y), Double(value.columns.3.y),
            Double(value.columns.0.z), Double(value.columns.1.z), Double(value.columns.2.z), Double(value.columns.3.z),
            Double(value.columns.0.w), Double(value.columns.1.w), Double(value.columns.2.w), Double(value.columns.3.w),
        ])
    }
}

enum RoomEditSetupError: Error {
    case missingProxyResource
    case openProxyManifest
    case invalidProxyManifest
    case missingContractSchema
}
