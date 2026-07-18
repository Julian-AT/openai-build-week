import ARKit
import CoreGraphics
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

enum ManualTargetCategory: Equatable, Sendable {
    case chair
    case smallTable
    case unsupported(String)
}

enum TargetTrackingHealth: String, Equatable, Sendable {
    case normal
    case limited
    case notAvailable = "not_available"
    case interrupted
    case failed

    var isHealthy: Bool { self == .normal }
}

enum TargetLifecycle: String, Equatable, Sendable {
    case candidate
    case tracked
    case lost
    case retired
}

enum TargetGroundingFailure: String, Equatable, Sendable {
    case targetMissed = "target_missed"
    case targetAmbiguous = "target_ambiguous"
    case trackingNotNormal = "tracking_not_normal"
    case staleSceneRevision = "stale_scene_revision"
    case worldFrameMismatch = "world_frame_mismatch"
    case unsupportedTargetCategory = "unsupported_target_category"
    case invalidSpatialEvidence = "invalid_spatial_evidence"
}

enum TargetReadinessValue: String, Equatable, Sendable {
    case unavailable
    case warming
    case ready
    case degraded
    case failed
}

enum TargetReadinessReasonCode: String, Equatable, Sendable {
    case trackingNotNormal = "tracking_not_normal"
    case targetAmbiguous = "target_ambiguous"
    case targetLost = "target_lost"
    case unsupportedTargetCategory = "unsupported_target_category"
    case supportMissing = "support_missing"
    case artifactMissing = "artifact_missing"
    case providerUnavailable = "provider_unavailable"
    case revealQualityFailed = "reveal_quality_failed"
    case noEligibleRestore = "no_eligible_restore"
    case worldFrameMismatch = "world_frame_mismatch"
    case authorityConflict = "authority_conflict"
}

struct TargetReadinessMatrix: Equatable, Sendable {
    let select: TargetReadinessValue
    let place: TargetReadinessValue
    let replace: TargetReadinessValue
    let remove: TargetReadinessValue
    let restore: TargetReadinessValue
}

struct TargetReadinessReasons: Equatable, Sendable {
    let select: [TargetReadinessReasonCode]
    let place: [TargetReadinessReasonCode]
    let replace: [TargetReadinessReasonCode]
    let remove: [TargetReadinessReasonCode]
    let restore: [TargetReadinessReasonCode]
}

enum RoomEditCompositorLayerID: String, CaseIterable, Equatable, Sendable {
    case camera
    case reveal
    case occluder
    case assetProxy = "asset_proxy"
    case debug
    case swiftUI = "swiftui"
}

enum RoomEditCompositorLayerReason: String, Equatable, Sendable {
    case liveCamera = "live_camera"
    case localRenderer = "local_renderer"
    case revealArtifactMissing = "reveal_artifact_missing"
    case occluderArtifactMissing = "occluder_artifact_missing"
    case debugOverlayDisabled = "debug_overlay_disabled"
    case nativeControls = "native_controls"
}

enum RoomEditCompositorLayerAvailability: Equatable, Sendable {
    case available(RoomEditCompositorLayerReason)
    case unavailable(RoomEditCompositorLayerReason)
}

struct RoomEditCompositorLayer: Equatable, Sendable {
    let id: RoomEditCompositorLayerID
    let availability: RoomEditCompositorLayerAvailability
}

struct RoomEditCompositorDescriptor: Equatable, Sendable {
    let layers: [RoomEditCompositorLayer]

    static let canonical = RoomEditCompositorDescriptor(layers: [
        RoomEditCompositorLayer(id: .camera, availability: .available(.liveCamera)),
        RoomEditCompositorLayer(id: .reveal, availability: .unavailable(.revealArtifactMissing)),
        RoomEditCompositorLayer(id: .occluder, availability: .unavailable(.occluderArtifactMissing)),
        RoomEditCompositorLayer(id: .assetProxy, availability: .available(.localRenderer)),
        RoomEditCompositorLayer(id: .debug, availability: .unavailable(.debugOverlayDisabled)),
        RoomEditCompositorLayer(id: .swiftUI, availability: .available(.nativeControls)),
    ])

    static func isCanonical(_ layers: [RoomEditCompositorLayer]) -> Bool {
        layers == canonical.layers
    }
}

struct ManualTargetCandidate: Equatable, Sendable {
    let category: ManualTargetCategory
    let capturedAtFrameID: String
    let capturedSceneRevision: UInt64
    let worldFrameID: String
    let worldFrameVersion: UInt64
    let cameraPose: Matrix4
    let worldFromTarget: Matrix4
    let screenPointEncodedPixels: [Double]
}

struct ManualFrozenProxy: Equatable, Sendable {
    let version: UInt64
    let capturedAtFrameID: String
    let capturedSceneRevision: UInt64
    let worldFrameID: String
    let worldFrameVersion: UInt64
    let cameraPose: Matrix4
    let worldFromTarget: Matrix4
    let screenPointEncodedPixels: [Double]
}

struct GroundedManualTarget: Equatable, Sendable {
    let objectID: String
    let category: ManualTargetCategory
    let lifecycle: TargetLifecycle
    let frozenProxy: ManualFrozenProxy

    func with(lifecycle: TargetLifecycle) -> Self {
        Self(
            objectID: objectID,
            category: category,
            lifecycle: lifecycle,
            frozenProxy: frozenProxy
        )
    }
}

struct TargetGroundingEnvironment: Equatable, Sendable {
    let sceneRevision: UInt64
    let worldFrameID: String
    let worldFrameVersion: UInt64
    let tracking: TargetTrackingHealth
    let supportReady: Bool
    let restoreEligible: Bool
    let replaceTargetCanonical: Bool
}

enum TargetGroundingEvent: Equatable, Sendable {
    case select([ManualTargetCandidate])
    case reseed([ManualTargetCandidate])
    case trackingChanged
    case worldReset
}

struct TargetGroundingSnapshot: Equatable, Sendable {
    let target: GroundedManualTarget?
    let failure: TargetGroundingFailure?
    let sceneRevision: UInt64
    let worldFrameID: String
    let worldFrameVersion: UInt64
    let tracking: TargetTrackingHealth
    let readiness: TargetReadinessMatrix
    let reasons: TargetReadinessReasons

    static let loading = TargetGroundingSnapshot(
        target: nil,
        failure: nil,
        sceneRevision: 0,
        worldFrameID: RoomEditIdentity.worldFrameID,
        worldFrameVersion: 1,
        tracking: .limited,
        readiness: TargetReadinessMatrix(
            select: .warming,
            place: .warming,
            replace: .unavailable,
            remove: .unavailable,
            restore: .unavailable
        ),
        reasons: TargetReadinessReasons(
            select: [.trackingNotNormal],
            place: [.trackingNotNormal],
            replace: [.targetLost],
            remove: [.revealQualityFailed],
            restore: [.noEligibleRestore]
        )
    )

    var targetContext: TargetContext? {
        guard let target,
              target.lifecycle == .tracked,
              target.frozenProxy.capturedSceneRevision == sceneRevision,
              target.frozenProxy.worldFrameID == worldFrameID,
              target.frozenProxy.worldFrameVersion == worldFrameVersion,
              tracking.isHealthy
        else { return nil }
        let proxy = target.frozenProxy
        return TargetContext(
            contractCapturedAtFrameID: proxy.capturedAtFrameID,
            capturedSceneRevision: proxy.capturedSceneRevision,
            worldFrameID: proxy.worldFrameID,
            worldFrameVersion: proxy.worldFrameVersion,
            cameraPose: proxy.cameraPose,
            screenPointEncodedPixels: proxy.screenPointEncodedPixels,
            candidateObjectIDs: [target.objectID],
            selectedObjectID: target.objectID,
            artifactRefs: []
        )
    }
}

enum TargetGroundingReducer {
    static func initial(environment: TargetGroundingEnvironment) -> TargetGroundingSnapshot {
        build(target: nil, failure: nil, environment: environment)
    }

    static func reduce(
        _ current: TargetGroundingSnapshot,
        event: TargetGroundingEvent,
        environment: TargetGroundingEnvironment,
        stableObjectID: String = RoomEditIdentity.targetObjectID
    ) -> TargetGroundingSnapshot {
        switch event {
        case let .select(candidates):
            return grounding(
                current,
                candidates: candidates,
                environment: environment,
                stableObjectID: current.target?.objectID ?? stableObjectID,
                requiresExistingTarget: false
            )
        case let .reseed(candidates):
            return grounding(
                current,
                candidates: candidates,
                environment: environment,
                stableObjectID: current.target?.objectID ?? stableObjectID,
                requiresExistingTarget: true
            )
        case .trackingChanged:
            let target = environment.tracking.isHealthy
                ? current.target
                : current.target?.with(lifecycle: .lost)
            let failure: TargetGroundingFailure? = environment.tracking.isHealthy
                ? current.failure
                : .trackingNotNormal
            return build(target: target, failure: failure, environment: environment)
        case .worldReset:
            return build(
                target: current.target?.with(lifecycle: .lost),
                failure: .worldFrameMismatch,
                environment: environment
            )
        }
    }

    private static func grounding(
        _ current: TargetGroundingSnapshot,
        candidates: [ManualTargetCandidate],
        environment: TargetGroundingEnvironment,
        stableObjectID: String,
        requiresExistingTarget: Bool
    ) -> TargetGroundingSnapshot {
        if requiresExistingTarget, current.target == nil {
            return build(target: current.target, failure: .targetMissed, environment: environment)
        }
        guard environment.tracking.isHealthy else {
            return build(target: current.target, failure: .trackingNotNormal, environment: environment)
        }
        guard candidates.count == 1 else {
            let failure: TargetGroundingFailure = candidates.isEmpty ? .targetMissed : .targetAmbiguous
            return build(target: current.target, failure: failure, environment: environment)
        }
        let candidate = candidates[0]
        guard candidate.category == .chair || candidate.category == .smallTable else {
            return build(
                target: current.target,
                failure: .unsupportedTargetCategory,
                environment: environment
            )
        }
        guard candidate.capturedSceneRevision == environment.sceneRevision else {
            return build(target: current.target, failure: .staleSceneRevision, environment: environment)
        }
        guard candidate.worldFrameID == environment.worldFrameID,
              candidate.worldFrameVersion == environment.worldFrameVersion
        else {
            return build(target: current.target, failure: .worldFrameMismatch, environment: environment)
        }
        guard valid(candidate), validStableObjectID(stableObjectID) else {
            return build(target: current.target, failure: .invalidSpatialEvidence, environment: environment)
        }
        let target = GroundedManualTarget(
            objectID: stableObjectID,
            category: candidate.category,
            lifecycle: .tracked,
            frozenProxy: ManualFrozenProxy(
                version: (current.target?.frozenProxy.version ?? 0) + 1,
                capturedAtFrameID: candidate.capturedAtFrameID,
                capturedSceneRevision: candidate.capturedSceneRevision,
                worldFrameID: candidate.worldFrameID,
                worldFrameVersion: candidate.worldFrameVersion,
                cameraPose: candidate.cameraPose,
                worldFromTarget: candidate.worldFromTarget,
                screenPointEncodedPixels: candidate.screenPointEncodedPixels
            )
        )
        return build(target: target, failure: nil, environment: environment)
    }

    private static func valid(_ candidate: ManualTargetCandidate) -> Bool {
        candidate.capturedAtFrameID.hasPrefix("frame_")
            && candidate.cameraPose.values.count == 16
            && candidate.cameraPose.values.allSatisfy(\.isFinite)
            && candidate.worldFromTarget.values.count == 16
            && candidate.worldFromTarget.values.allSatisfy(\.isFinite)
            && candidate.screenPointEncodedPixels.count == 2
            && candidate.screenPointEncodedPixels.allSatisfy(\.isFinite)
    }

    private static func validStableObjectID(_ value: String) -> Bool {
        value.range(
            of: #"^object_[0-9a-f]{8}-[0-9a-f]{4}-[47][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"#,
            options: .regularExpression
        ) != nil
    }

    private static func build(
        target: GroundedManualTarget?,
        failure: TargetGroundingFailure?,
        environment: TargetGroundingEnvironment
    ) -> TargetGroundingSnapshot {
        let hasCurrentTarget = target?.lifecycle == .tracked
            && target?.frozenProxy.capturedSceneRevision == environment.sceneRevision
            && target?.frozenProxy.worldFrameID == environment.worldFrameID
            && target?.frozenProxy.worldFrameVersion == environment.worldFrameVersion
            && environment.replaceTargetCanonical
        let trackingFailure: TargetReadinessValue = environment.tracking == .failed ? .failed : .unavailable

        let select: TargetReadinessValue = environment.tracking.isHealthy ? .ready : trackingFailure
        let place: TargetReadinessValue
        if !environment.tracking.isHealthy {
            place = trackingFailure
        } else {
            place = environment.supportReady ? .ready : .unavailable
        }
        let replace: TargetReadinessValue
        if !environment.tracking.isHealthy {
            replace = trackingFailure
        } else {
            replace = hasCurrentTarget ? .degraded : .unavailable
        }
        let remove: TargetReadinessValue = .unavailable
        let restore: TargetReadinessValue = environment.restoreEligible ? .ready : .unavailable

        let selectReasons: [TargetReadinessReasonCode] = select == .ready ? [] : [.trackingNotNormal]
        let placeReasons: [TargetReadinessReasonCode]
        if place == .ready {
            placeReasons = []
        } else {
            placeReasons = environment.tracking.isHealthy ? [.supportMissing] : [.trackingNotNormal]
        }
        let replaceReasons: [TargetReadinessReasonCode]
        if !environment.tracking.isHealthy {
            replaceReasons = [.trackingNotNormal]
        } else if hasCurrentTarget {
            replaceReasons = [.providerUnavailable]
        } else if target != nil, !environment.replaceTargetCanonical {
            replaceReasons = [.authorityConflict]
        } else if target != nil {
            replaceReasons = target?.frozenProxy.worldFrameID == environment.worldFrameID
                && target?.frozenProxy.worldFrameVersion == environment.worldFrameVersion
                ? [.authorityConflict]
                : [.worldFrameMismatch]
        } else {
            replaceReasons = failure == .targetAmbiguous ? [.targetAmbiguous] : [.targetLost]
        }

        return TargetGroundingSnapshot(
            target: target,
            failure: failure,
            sceneRevision: environment.sceneRevision,
            worldFrameID: environment.worldFrameID,
            worldFrameVersion: environment.worldFrameVersion,
            tracking: environment.tracking,
            readiness: TargetReadinessMatrix(
                select: select,
                place: place,
                replace: replace,
                remove: remove,
                restore: restore
            ),
            reasons: TargetReadinessReasons(
                select: selectReasons,
                place: placeReasons,
                replace: replaceReasons,
                remove: [.revealQualityFailed],
                restore: restore == .ready ? [] : [.noEligibleRestore]
            )
        )
    }
}

struct RoomEditPreviewSnapshot: Equatable, Sendable {
    let proxyID: String
    let baseRevision: UInt64
    let currentRevision: UInt64
    let supportStatus: String
}

enum RoomEditRenderProxyKind: String, Equatable, Sendable {
    case frozenTarget = "frozen_target"
    case provisionalPlace = "provisional_place"
    case committedPlace = "committed_place"
}

struct RoomEditRenderProxySnapshot: Equatable, Sendable {
    let objectID: String
    let worldFrameVersion: UInt64
    let worldFromProxy: Matrix4
    let kind: RoomEditRenderProxyKind
}

struct RoomEditRenderSnapshot: Equatable, Sendable {
    let revision: UInt64
    let layers: [RoomEditCompositorLayer]
    let targetProxy: RoomEditRenderProxySnapshot?
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
    let target: TargetGroundingSnapshot
    let targetContext: TargetContext?
    let status: String

    var render: RoomEditRenderSnapshot {
        let proxy: RoomEditRenderProxySnapshot?
        if let target = target.target {
            proxy = RoomEditRenderProxySnapshot(
                objectID: target.objectID,
                worldFrameVersion: target.frozenProxy.worldFrameVersion,
                worldFromProxy: target.frozenProxy.worldFromTarget,
                kind: .frozenTarget
            )
        } else if preview != nil || placedAssetVisible {
            proxy = RoomEditRenderProxySnapshot(
                objectID: RoomEditIdentity.placedAssetID,
                worldFrameVersion: target.worldFrameVersion,
                worldFromProxy: .phase3ProxyPlacement,
                kind: placedAssetVisible ? .committedPlace : .provisionalPlace
            )
        } else {
            proxy = nil
        }
        return RoomEditRenderSnapshot(
            revision: revision,
            layers: RoomEditCompositorDescriptor.canonical.layers,
            targetProxy: proxy
        )
    }

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
        target: .loading,
        targetContext: nil,
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

    static let fixture = RoomEditSupportContext(
        capturedFrameID: RoomEditIdentity.frameID,
        surfaceID: RoomEditIdentity.surfaceID,
        cameraPose: .identity,
        worldFromAsset: .phase3ProxyPlacement,
        confidence: 0.95,
        method: "arkit_plane"
    )
}

typealias RoomEditSupportProvider = @MainActor @Sendable (SceneState) async -> RoomEditSupportContext?

enum RoomEditTargetSessionEvent: Equatable, Sendable {
    case tracking(TargetTrackingHealth)
    case worldReset
}

@MainActor
protocol RoomEditTargetSession: AnyObject {
    var tracking: TargetTrackingHealth { get }
    var cameraPose: Matrix4? { get }

    func prepare() async
    func candidates(at point: CGPoint, context: TargetRaycastContext) -> [TargetRaycastCandidate]
    func setEventHandler(_ handler: @escaping (RoomEditTargetSessionEvent) -> Void)
}

enum RoomEditTargetFixtureScenario: String, Equatable, Sendable {
    case healthy
    case miss
    case ambiguous
    case trackingLossAfterSeed = "tracking_loss_after_seed"
}

@MainActor
final class RoomEditFixtureTargetSession: RoomEditTargetSession {
    private(set) var prepareCount = 0
    private(set) var requestedPoints: [CGPoint] = []
    private let scenario: RoomEditTargetFixtureScenario
    private var eventHandler: ((RoomEditTargetSessionEvent) -> Void)?

    init(scenario: RoomEditTargetFixtureScenario) {
        self.scenario = scenario
    }

    var tracking: TargetTrackingHealth { .normal }
    var cameraPose: Matrix4? { .identity }

    func prepare() async {
        prepareCount += 1
    }

    func candidates(at point: CGPoint, context: TargetRaycastContext) -> [TargetRaycastCandidate] {
        requestedPoints.append(point)
        let first = candidate(context: context, offsetX: 0)
        switch scenario {
        case .healthy:
            return [first]
        case .miss:
            return []
        case .ambiguous:
            return [first, candidate(context: context, offsetX: 0.25)]
        case .trackingLossAfterSeed:
            eventHandler?(.tracking(.notAvailable))
            return [first]
        }
    }

    func setEventHandler(_ handler: @escaping (RoomEditTargetSessionEvent) -> Void) {
        eventHandler = handler
    }

    private func candidate(
        context: TargetRaycastContext,
        offsetX: Double
    ) -> TargetRaycastCandidate {
        TargetRaycastCandidate(
            source: .existingPlaneGeometry,
            worldFrameID: context.worldFrameID,
            worldFrameVersion: context.worldFrameVersion,
            capturedSceneRevision: context.capturedSceneRevision,
            worldFromCandidate: Matrix4(values: [
                1, 0, 0, offsetX,
                0, 1, 0, 0,
                0, 0, 1, -1.2,
                0, 0, 0, 1,
            ])
        )
    }
}

@MainActor
final class RoomEditLiveTargetSession: RoomEditTargetSession {
    let sharedSession: SharedRealityKitSession
    let deviceProof: DeviceProofModel

    private var prepared = false
    private var eventHandler: ((RoomEditTargetSessionEvent) -> Void)?

    init(sharedSession: SharedRealityKitSession, deviceProof: DeviceProofModel) {
        self.sharedSession = sharedSession
        self.deviceProof = deviceProof
        sharedSession.controller.addObserver { [weak self] event in
            self?.consume(event)
        }
    }

    var tracking: TargetTrackingHealth {
        switch deviceProof.state.session.trackingState {
        case .normal:
            .normal
        case .initializing, .limited:
            .limited
        case .unavailable:
            .notAvailable
        }
    }

    var cameraPose: Matrix4? {
        deviceProof.currentARFrame.map { Matrix4(simdTransform: $0.camera.transform) }
    }

    func prepare() async {
        guard prepared == false else { return }
        prepared = true
        await deviceProof.prepare()
    }

    func candidates(at point: CGPoint, context: TargetRaycastContext) -> [TargetRaycastCandidate] {
        sharedSession.controller.targetCandidates(at: point, context: context)
    }

    func setEventHandler(_ handler: @escaping (RoomEditTargetSessionEvent) -> Void) {
        eventHandler = handler
    }

    private func consume(_ event: ARSessionEvent) {
        switch event {
        case let .tracking(state):
            switch state {
            case .normal:
                eventHandler?(.tracking(.normal))
            case .initializing, .limited:
                eventHandler?(.tracking(.limited))
            case .unavailable:
                eventHandler?(.tracking(.notAvailable))
            }
        case let .running(isRunning) where isRunning == false:
            eventHandler?(.tracking(.notAvailable))
        case .worldReset:
            eventHandler?(.worldReset)
        case .running, .planeObserved:
            break
        }
    }
}

@MainActor
final class RoomEditRuntime {
    let model: RoomEditModel
    let sharedSession: SharedRealityKitSession?
    let deviceProof: DeviceProofModel?
    let fixtureScenario: RoomEditTargetFixtureScenario?

    init(
        model: RoomEditModel,
        sharedSession: SharedRealityKitSession?,
        deviceProof: DeviceProofModel?,
        fixtureScenario: RoomEditTargetFixtureScenario?
    ) {
        self.model = model
        self.sharedSession = sharedSession
        self.deviceProof = deviceProof
        self.fixtureScenario = fixtureScenario
    }
}

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
    @ObservationIgnored private let targetSession: (any RoomEditTargetSession)?
    @ObservationIgnored private var placePreview: PlacePreviewReduction?
    @ObservationIgnored private var targetGrounding: TargetGroundingSnapshot = .loading
    @ObservationIgnored private var hasPrepared = false
    @ObservationIgnored private var currentWorldFrameID = RoomEditIdentity.worldFrameID
    @ObservationIgnored private var currentWorldFrameVersion: UInt64 = 1
    @ObservationIgnored private var replaceStoreCompatible = false

    init(
        authority: NativeBranchAuthority,
        manifest: Phase3ProxyManifest,
        supportProvider: @escaping RoomEditSupportProvider,
        targetSession: (any RoomEditTargetSession)? = nil
    ) {
        self.authority = authority
        self.manifest = manifest
        self.supportProvider = supportProvider
        self.targetSession = targetSession
        targetSession?.setEventHandler { [weak self] event in
            Task { @MainActor [weak self] in
                await self?.consumeTargetSessionEvent(event)
            }
        }
    }

    func prepare() async {
        guard hasPrepared == false else { return }
        hasPrepared = true
        await targetSession?.prepare()
        placePreview = nil
        let active = await authority.activeSnapshot()
        currentWorldFrameID = active.scene.worldFrame.worldFrameID
        currentWorldFrameVersion = active.scene.worldFrame.worldFrameVersion
        replaceStoreCompatible = active.scene.objects.contains {
            $0.objectID == RoomEditIdentity.targetObjectID
        }
        targetGrounding = TargetGroundingReducer.initial(
            environment: targetEnvironment(
                for: active,
                tracking: targetSession?.tracking ?? .limited,
                supportReady: false
            )
        )
        publish(
            active,
            blocker: replaceStoreCompatible ? nil : .replaceDeferred,
            status: replaceStoreCompatible
                ? "Local room state recovered"
                : "Replace needs a fresh local room; recovered store predates Phase 5"
        )
    }

    func groundTarget(at point: CGPoint) async {
        await groundTarget(at: point, reseeding: false)
    }

    func reseedTarget(at point: CGPoint) async {
        await groundTarget(at: point, reseeding: true)
    }

    private func groundTarget(at point: CGPoint, reseeding: Bool) async {
        guard let targetSession,
              let cameraPose = targetSession.cameraPose,
              point.x.isFinite,
              point.y.isFinite
        else {
            if reseeding {
                await reseedTarget(candidates: [], tracking: targetSession?.tracking ?? .notAvailable)
            } else {
                await groundTarget(candidates: [], tracking: targetSession?.tracking ?? .notAvailable)
            }
            return
        }
        let active = await authority.activeSnapshot()
        let context = TargetRaycastContext(
            worldFrameID: currentWorldFrameID,
            worldFrameVersion: currentWorldFrameVersion,
            capturedSceneRevision: active.scene.sceneRevision
        )
        let candidates = targetSession.candidates(at: point, context: context).map {
            ManualTargetCandidate(
                category: .chair,
                capturedAtFrameID: RoomEditIdentity.frameID,
                capturedSceneRevision: $0.capturedSceneRevision,
                worldFrameID: $0.worldFrameID,
                worldFrameVersion: $0.worldFrameVersion,
                cameraPose: cameraPose,
                worldFromTarget: $0.worldFromCandidate,
                screenPointEncodedPixels: [Double(point.x), Double(point.y)]
            )
        }
        if reseeding {
            await reseedTarget(candidates: candidates, tracking: targetSession.tracking)
        } else {
            await groundTarget(candidates: candidates, tracking: targetSession.tracking)
        }
    }

    func groundTarget(
        candidates: [ManualTargetCandidate],
        tracking: TargetTrackingHealth
    ) async {
        let active = await authority.activeSnapshot()
        targetGrounding = TargetGroundingReducer.reduce(
            targetGrounding,
            event: .select(candidates),
            environment: targetEnvironment(for: active, tracking: tracking)
        )
        publish(
            active,
            blocker: replaceStoreCompatible ? nil : .replaceDeferred,
            status: replaceStoreCompatible
                ? (targetGrounding.failure == nil
                    ? "Manual target grounded with frozen no-dense proxy"
                    : targetFailureStatus(targetGrounding.failure))
                : "Replace needs a fresh local room; recovered store has no canonical target"
        )
    }

    func reseedTarget(
        candidates: [ManualTargetCandidate],
        tracking: TargetTrackingHealth
    ) async {
        let active = await authority.activeSnapshot()
        targetGrounding = TargetGroundingReducer.reduce(
            targetGrounding,
            event: .reseed(candidates),
            environment: targetEnvironment(for: active, tracking: tracking)
        )
        publish(
            active,
            blocker: replaceStoreCompatible ? nil : .replaceDeferred,
            status: replaceStoreCompatible
                ? (targetGrounding.failure == nil
                    ? "Manual target reseeded in the current world epoch"
                    : targetFailureStatus(targetGrounding.failure))
                : "Replace needs a fresh local room; recovered store has no canonical target"
        )
    }

    func updateTargetTracking(_ tracking: TargetTrackingHealth) async {
        let active = await authority.activeSnapshot()
        targetGrounding = TargetGroundingReducer.reduce(
            targetGrounding,
            event: .trackingChanged,
            environment: targetEnvironment(for: active, tracking: tracking)
        )
        publish(
            active,
            status: tracking.isHealthy
                ? "Tracking recovered; reseed a lost target before editing"
                : "Tracking is not normal; unsafe target edits are disabled"
        )
    }

    func noteTargetWorldReset(
        worldFrameID: String,
        worldFrameVersion: UInt64,
        tracking: TargetTrackingHealth
    ) async {
        currentWorldFrameID = worldFrameID
        currentWorldFrameVersion = worldFrameVersion
        let active = await authority.activeSnapshot()
        targetGrounding = TargetGroundingReducer.reduce(
            targetGrounding,
            event: .worldReset,
            environment: TargetGroundingEnvironment(
                sceneRevision: active.scene.sceneRevision,
                worldFrameID: worldFrameID,
                worldFrameVersion: worldFrameVersion,
                tracking: tracking,
                supportReady: false,
                restoreEligible: hasEligibleRestore(in: active),
                replaceTargetCanonical: replaceStoreCompatible
            )
        )
        publish(active, status: "World epoch changed; explicit target reseed required")
    }

    private func consumeTargetSessionEvent(_ event: RoomEditTargetSessionEvent) async {
        switch event {
        case let .tracking(tracking):
            await updateTargetTracking(tracking)
        case .worldReset:
            await noteTargetWorldReset(
                worldFrameID: currentWorldFrameID,
                worldFrameVersion: currentWorldFrameVersion + 1,
                tracking: targetSession?.tracking ?? .limited
            )
        }
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
            publish(
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
            publish(active, selected: .place, status: "Provisional placement cancelled; revision unchanged")
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
                publish(
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
            guard targetSession == nil || targetGrounding.tracking.isHealthy else {
                publish(
                    active,
                    selected: .place,
                    blocker: .healthySupportRequired,
                    status: "Place needs normal tracking and a visible horizontal floor"
                )
                return
            }
            guard let support = await supportProvider(active.scene),
                  support.surfaceID == RoomEditIdentity.surfaceID
            else {
                publish(
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
            targetGrounding = TargetGroundingReducer.reduce(
                targetGrounding,
                event: .trackingChanged,
                environment: targetEnvironment(for: active, tracking: .normal, supportReady: true)
            )
            assignSnapshot(RoomEditSnapshot(
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
                target: targetGrounding,
                targetContext: targetGrounding.targetContext,
                status: "Provisional Phase 3 proxy; confirm or cancel"
            ))
        } catch {
            await fail(error)
        }
    }

    private func proposal(
        for operation: ProductOperation,
        scene: SceneState,
        support: RoomEditSupportContext?
    ) -> BoundProposal {
        let groundedContext: TargetContext?
        switch operation {
        case .replace, .remove:
            groundedContext = targetGrounding.targetContext
        case .place, .restore:
            groundedContext = nil
        }
        return BoundProposal(
            sessionID: scene.sessionID,
            revisionAuthority: scene.revisionAuthority,
            baseSceneRevision: scene.sceneRevision,
            targetContext: groundedContext ?? TargetContext(
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
        let active = await authority.activeSnapshot()
        targetGrounding = TargetGroundingReducer.reduce(
            targetGrounding,
            event: .trackingChanged,
            environment: targetEnvironment(for: active, tracking: targetGrounding.tracking)
        )
        publish(
            active,
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
    ) {
        assignSnapshot(RoomEditSnapshot(
            operations: RoomEditOperation.allCases,
            selectedOperation: selected,
            revision: active.scene.sceneRevision,
            preview: nil,
            blocker: blocker,
            localState: active.receipts.isEmpty ? .ready : .durable,
            placedAssetVisible: active.scene.placedAssets.isEmpty == false,
            canConfirm: false,
            canRestore: hasEligibleRestore(in: active),
            target: targetGrounding,
            targetContext: targetGrounding.targetContext,
            status: status
        ))
    }

    private func assignSnapshot(_ next: RoomEditSnapshot) {
        guard next != snapshot else { return }
        snapshot = next
    }

    private func targetEnvironment(
        for active: TransactionGenerationSnapshot,
        tracking: TargetTrackingHealth,
        supportReady: Bool? = nil
    ) -> TargetGroundingEnvironment {
        TargetGroundingEnvironment(
            sceneRevision: active.scene.sceneRevision,
            worldFrameID: currentWorldFrameID,
            worldFrameVersion: currentWorldFrameVersion,
            tracking: tracking,
            supportReady: supportReady ?? active.scene.surfaces.contains {
                $0.lifecycle == "tracked"
                    && ["floor", "tabletop", "other_horizontal"].contains($0.kind)
            },
            restoreEligible: hasEligibleRestore(in: active),
            replaceTargetCanonical: replaceStoreCompatible
        )
    }

    private func targetFailureStatus(_ failure: TargetGroundingFailure?) -> String {
        switch failure {
        case .targetMissed:
            "No target found; aim at the visible chair/table and tap again"
        case .targetAmbiguous:
            "Target is ambiguous; isolate one chair/table and tap again"
        case .trackingNotNormal:
            "Tracking is not normal; move slowly and retry"
        case .staleSceneRevision:
            "Target evidence is stale; tap again in the current room state"
        case .worldFrameMismatch:
            "Target belongs to another world epoch; reseed it"
        case .unsupportedTargetCategory:
            "Only one freestanding chair or small table is supported"
        case .invalidSpatialEvidence:
            "Target evidence is invalid; aim at visible floor and retry"
        case nil:
            "Manual target ready"
        }
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
    static let storeDirectoryName = "phase5-room-edit-v1"
    static let sessionID = "session_53000000-0000-4000-8000-000000000010"
    static let sceneID = "scene_53000000-0000-4000-8000-000000000011"
    static let deviceID = "device_53000000-0000-4000-8000-000000000012"
    static let branchID = "branch_53000000-0000-4000-8000-000000000013"
    static let worldFrameID = "world_53000000-0000-4000-8000-000000000014"
    static let frameID = "frame_53000000-0000-4000-8000-000000000015"
    static let surfaceID = "surface_53000000-0000-4000-8000-000000000016"
    static let targetObjectID = "object_53000000-0000-4000-8000-000000000030"
    static let replacementPlacedAssetID = "assetinst_53000000-0000-4000-8000-000000000031"
    static let replacementSupportRelationID = "support_53000000-0000-4000-8000-000000000032"
    static let supportedViewFixtureID = "envelope_53000000-0000-4000-8000-000000000033"
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
        let targetReadiness = Readiness(
            contractSelect: "ready",
            place: "ready",
            replace: "degraded",
            remove: "unavailable",
            restore: "unavailable"
        )
        let targetReasons = ReadinessReasons(
            contractSelect: [],
            place: [],
            replace: [ReadinessReason(
                contractCode: "provider_unavailable",
                message: "Manual proxy fallback only; provider gate pending"
            )],
            remove: [ReadinessReason(
                contractCode: "reveal_quality_failed",
                message: "Validated reveal evidence is unavailable"
            )],
            restore: [ReadinessReason(
                contractCode: "no_eligible_restore",
                message: "No committed edit is eligible for restore"
            )]
        )
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
            objects: [SceneObject(
                contractObjectID: RoomEditIdentity.targetObjectID,
                label: "chair",
                labelConfidence: 1,
                lifecycle: "tracked",
                readiness: targetReadiness,
                readinessReasons: targetReasons,
                artifactRefs: [],
                editState: ObjectEditState(contractVisible: true, activeReveal: nil),
                createdSceneRevision: 0,
                lastObservedFrameID: RoomEditIdentity.frameID
            )],
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

    static func replaceProposal(
        scene: SceneState,
        targetContext: TargetContext,
        manifest: Phase3ProxyManifest
    ) -> BoundProposal {
        BoundProposal(
            sessionID: scene.sessionID,
            revisionAuthority: scene.revisionAuthority,
            baseSceneRevision: scene.sceneRevision,
            targetContext: targetContext,
            intent: TransactionIntent(
                contractOperation: .replace,
                source: "tap",
                arguments: IntentArguments(assetID: manifest.contractAssetID),
                constraints: []
            )
        )
    }

    static func replaceCandidate(
        scene: SceneState,
        targetContext: TargetContext,
        manifest: Phase3ProxyManifest,
        support: RoomEditSupportContext
    ) -> DeterministicReplaceCandidate? {
        guard targetContext.selectedObjectID == RoomEditIdentity.targetObjectID,
              targetContext.candidateObjectIDs == [RoomEditIdentity.targetObjectID],
              targetContext.capturedSceneRevision == scene.sceneRevision,
              targetContext.worldFrameID == scene.worldFrame.worldFrameID,
              targetContext.worldFrameVersion == scene.worldFrame.worldFrameVersion,
              scene.objects.contains(where: { $0.objectID == RoomEditIdentity.targetObjectID }),
              scene.surfaces.contains(where: {
                  $0.surfaceID == support.surfaceID && $0.lifecycle == "tracked"
              })
        else { return nil }

        return DeterministicReplaceCandidate(
            asset: ProxyAssetCandidate(
                assetID: manifest.contractAssetID,
                placedAssetID: RoomEditIdentity.replacementPlacedAssetID,
                manifestArtifactRef: manifest.artifactReference,
                allowlisted: true,
                collisionProxyPassed: true,
                assetLicensePassed: true,
                artifactIntegrityPassed: true
            ),
            support: DeterministicSupportCandidate(
                relationID: RoomEditIdentity.replacementSupportRelationID,
                surfaceID: support.surfaceID,
                worldFrameID: scene.worldFrame.worldFrameID,
                worldFrameVersion: scene.worldFrame.worldFrameVersion,
                capturedSceneRevision: scene.sceneRevision,
                worldFromAsset: support.worldFromAsset,
                confidence: support.confidence,
                method: support.method
            ),
            targetObjectID: RoomEditIdentity.targetObjectID,
            capabilityReadiness: "degraded",
            readinessSource: "manual_proxy_fallback",
            supportedViewFixtureID: RoomEditIdentity.supportedViewFixtureID,
            supportedView: true,
            capturedSceneRevision: scene.sceneRevision,
            worldFrameID: scene.worldFrame.worldFrameID,
            worldFrameVersion: scene.worldFrame.worldFrameVersion
        )
    }

    @MainActor
    static func runtime(
        resetStore: Bool = false,
        useFixtureSupport: Bool = false,
        fixtureScenario: RoomEditTargetFixtureScenario = .healthy
    ) throws -> RoomEditRuntime {
        let manifest = try Phase3ProxyManifest.load(bundle: .main)
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = documents.appendingPathComponent(RoomEditIdentity.storeDirectoryName, isDirectory: true)
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
        if useFixtureSupport {
            let targetSession = RoomEditFixtureTargetSession(scenario: fixtureScenario)
            let model = RoomEditModel(
                authority: authority,
                manifest: manifest,
                supportProvider: { _ in .fixture },
                targetSession: targetSession
            )
            return RoomEditRuntime(
                model: model,
                sharedSession: nil,
                deviceProof: nil,
                fixtureScenario: fixtureScenario
            )
        }

        let sharedSession = SharedRealityKitSession()
        let deviceProof = DeviceProofModel(arSessionController: sharedSession.controller)
        let targetSession = RoomEditLiveTargetSession(
            sharedSession: sharedSession,
            deviceProof: deviceProof
        )
        let model = RoomEditModel(
            authority: authority,
            manifest: manifest,
            supportProvider: { _ in
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
            },
            targetSession: targetSession
        )
        return RoomEditRuntime(
            model: model,
            sharedSession: sharedSession,
            deviceProof: deviceProof,
            fixtureScenario: nil
        )
    }

    @MainActor
    static func live(resetStore: Bool = false, useFixtureSupport: Bool = false) throws -> RoomEditModel {
        try runtime(
            resetStore: resetStore,
            useFixtureSupport: useFixtureSupport
        ).model
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

    static let phase3ProxyPlacement = Matrix4(values: [
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, -1.2,
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
