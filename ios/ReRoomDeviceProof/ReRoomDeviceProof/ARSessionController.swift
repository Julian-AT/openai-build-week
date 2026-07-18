import ARKit
import CoreGraphics
import ReRoomTransactionCore
import RealityKit

enum ARSessionEvent: Equatable, Sendable {
    case running(Bool)
    case tracking(DeviceTrackingState)
    case planeObserved(PlaneAlignment)
    case worldReset
}

enum ARSessionRecoveryRequirement: Equatable, Sendable {
    case interruption
    case failure
}

struct ARSessionObserverToken: Hashable, Sendable {
    fileprivate let rawValue: UInt64
}

enum TargetRaycastSource: String, Hashable, Sendable {
    case existingPlaneGeometry = "existing_plane_geometry"
    case estimatedHorizontalPlane = "estimated_horizontal_plane"
}

struct TargetRaycastContext: Equatable, Sendable {
    let worldFrameID: String
    let worldFrameVersion: UInt64
    let capturedSceneRevision: UInt64
}

struct TargetRaycastCandidate: Equatable, Sendable {
    let source: TargetRaycastSource
    let worldFrameID: String
    let worldFrameVersion: UInt64
    let capturedSceneRevision: UInt64
    let worldFromCandidate: Matrix4
}

@MainActor
protocol TargetRaycastResolving: AnyObject {
    func raycast(at point: CGPoint, source: TargetRaycastSource) -> [simd_float4x4]
}

@MainActor
final class ClosureTargetRaycastResolver: TargetRaycastResolving {
    typealias Handler = (CGPoint, TargetRaycastSource) -> [simd_float4x4]

    private let handler: Handler

    init(_ handler: @escaping Handler) {
        self.handler = handler
    }

    func raycast(at point: CGPoint, source: TargetRaycastSource) -> [simd_float4x4] {
        handler(point, source)
    }
}

@MainActor
final class RealityKitTargetRaycastResolver: TargetRaycastResolving {
    private let view: ARView

    init(view: ARView) {
        self.view = view
    }

    func raycast(at point: CGPoint, source: TargetRaycastSource) -> [simd_float4x4] {
        let target: ARRaycastQuery.Target
        switch source {
        case .existingPlaneGeometry:
            target = .existingPlaneGeometry
        case .estimatedHorizontalPlane:
            target = .estimatedPlane
        }
        return view.raycast(from: point, allowing: target, alignment: .horizontal)
            .map(\.worldTransform)
    }
}

@MainActor
protocol ARSessionDriving: AnyObject {
    var delegate: (any ARSessionDelegate)? { get set }
    var currentFrame: ARFrame? { get }

    func run(policy: ARSessionPolicy)
    func reset(policy: ARSessionPolicy)
    func pause()
}

@MainActor
final class SystemARSessionDriver: ARSessionDriving {
    let session: ARSession

    init(session: ARSession = ARSession()) {
        self.session = session
    }

    var delegate: (any ARSessionDelegate)? {
        get { session.delegate }
        set { session.delegate = newValue }
    }

    var currentFrame: ARFrame? {
        session.currentFrame
    }

    func run(policy: ARSessionPolicy) {
        session.run(configuration(for: policy))
    }

    func reset(policy: ARSessionPolicy) {
        session.run(
            configuration(for: policy),
            options: [.resetTracking, .removeExistingAnchors]
        )
    }

    private func configuration(for policy: ARSessionPolicy) -> ARWorldTrackingConfiguration {
        let configuration = ARWorldTrackingConfiguration()
        var planeDetection: ARWorldTrackingConfiguration.PlaneDetection = []
        if policy.detectedPlaneAlignments.contains(.horizontal) {
            planeDetection.insert(.horizontal)
        }
        if policy.detectedPlaneAlignments.contains(.vertical) {
            planeDetection.insert(.vertical)
        }
        configuration.planeDetection = planeDetection
        return configuration
    }

    func pause() {
        session.pause()
    }
}

@MainActor
final class ARSessionController: NSObject {
    static let maximumTargetCandidateCount = 4

    private struct Observer {
        let token: ARSessionObserverToken
        let handler: (ARSessionEvent) -> Void
    }

    private let driver: any ARSessionDriving
    private let raycastResolver: (any TargetRaycastResolving)?
    private var observers: [Observer] = []
    private var nextObserverID: UInt64 = 0
    private var lastTrackingState: DeviceTrackingState?
    private var observedPlaneAlignments: Set<PlaneAlignment> = []
    private(set) var isRunning = false
    private(set) var recoveryRequirement: ARSessionRecoveryRequirement?

    // Compatibility seam for the existing device-proof consumer. Additional
    // consumers register independently and cannot replace this callback.
    var onEvent: ((ARSessionEvent) -> Void)?

    init(
        driver: any ARSessionDriving = SystemARSessionDriver(),
        raycastResolver: (any TargetRaycastResolving)? = nil
    ) {
        self.driver = driver
        self.raycastResolver = raycastResolver
        super.init()
        self.driver.delegate = self
    }

    var currentFrame: ARFrame? {
        driver.currentFrame
    }

    @discardableResult
    func addObserver(_ handler: @escaping (ARSessionEvent) -> Void) -> ARSessionObserverToken {
        precondition(nextObserverID < UInt64.max, "AR session observer token space exhausted")
        let token = ARSessionObserverToken(rawValue: nextObserverID)
        nextObserverID += 1
        observers.append(Observer(token: token, handler: handler))
        return token
    }

    func removeObserver(_ token: ARSessionObserverToken) {
        observers.removeAll { $0.token == token }
    }

    func targetCandidates(
        at point: CGPoint,
        context: TargetRaycastContext
    ) -> [TargetRaycastCandidate] {
        guard isRunning,
              point.x.isFinite,
              point.y.isFinite,
              context.worldFrameID.hasPrefix("world_"),
              context.worldFrameVersion > 0,
              let raycastResolver
        else { return [] }

        let existing = finiteCandidates(
            from: raycastResolver.raycast(at: point, source: .existingPlaneGeometry),
            source: .existingPlaneGeometry,
            context: context
        )
        if existing.isEmpty == false {
            return existing
        }
        return finiteCandidates(
            from: raycastResolver.raycast(at: point, source: .estimatedHorizontalPlane),
            source: .estimatedHorizontalPlane,
            context: context
        )
    }

    func synchronize(cameraAuthorization: PermissionAuthorizationState) {
        guard cameraAuthorization == .granted else {
            stopForUnavailableCamera()
            return
        }

        guard isRunning == false, recoveryRequirement == nil else {
            return
        }

        driver.run(policy: .deviceProof)
        isRunning = true
        publish(.running(true))
    }

    @discardableResult
    func restartAfterRecovery(cameraAuthorization: PermissionAuthorizationState) -> Bool {
        guard cameraAuthorization == .granted, recoveryRequirement != nil else {
            return false
        }
        driver.run(policy: .deviceProof)
        recoveryRequirement = nil
        isRunning = true
        publish(.running(true))
        return true
    }

    func handlePhysicalOrientation(_ orientation: PhysicalOrientation) {
        // Orientation controls capture eligibility in DeviceProofState. It never
        // pauses or restarts a healthy AR session.
        _ = orientation
    }

    @discardableResult
    func performExplicitWorldReset(
        cameraAuthorization: PermissionAuthorizationState
    ) -> Bool {
        guard cameraAuthorization == .granted, isRunning else {
            return false
        }

        driver.reset(policy: .deviceProof)
        recoveryRequirement = nil
        lastTrackingState = nil
        observedPlaneAlignments.removeAll(keepingCapacity: true)
        publish(.worldReset)
        publish(.running(true))
        return true
    }

    func recordTrackingState(_ state: DeviceTrackingState) {
        guard state != lastTrackingState else { return }
        lastTrackingState = state
        publish(.tracking(state))
    }

    func recordPlaneObservation(_ alignment: PlaneAlignment) {
        guard observedPlaneAlignments.insert(alignment).inserted else { return }
        publish(.planeObserved(alignment))
    }

    private func stopForUnavailableCamera() {
        recoveryRequirement = nil
        guard isRunning else {
            return
        }

        driver.pause()
        isRunning = false
        publish(.running(false))
    }

    private func publish(_ event: ARSessionEvent) {
        onEvent?(event)
        // Copying this deliberately small registry makes removal during a
        // callback deterministic. Delivery is synchronous and has no queue.
        for observer in observers {
            observer.handler(event)
        }
    }

    private func finiteCandidates(
        from transforms: [simd_float4x4],
        source: TargetRaycastSource,
        context: TargetRaycastContext
    ) -> [TargetRaycastCandidate] {
        transforms.prefix(Self.maximumTargetCandidateCount).compactMap { transform in
            guard Self.isFinite(transform) else { return nil }
            return TargetRaycastCandidate(
                source: source,
                worldFrameID: context.worldFrameID,
                worldFrameVersion: context.worldFrameVersion,
                capturedSceneRevision: context.capturedSceneRevision,
                worldFromCandidate: Matrix4(simdTransform: transform)
            )
        }
    }

    private static func isFinite(_ transform: simd_float4x4) -> Bool {
        for column in 0..<4 {
            for row in 0..<4 where transform[column][row].isFinite == false {
                return false
            }
        }
        return true
    }
}

@MainActor
final class SharedRealityKitSession {
    let view: ARView
    let controller: ARSessionController

    init(frame: CGRect = .zero) {
        let view = ARView(
            frame: frame,
            cameraMode: .ar,
            automaticallyConfigureSession: false
        )
        self.view = view
        controller = ARSessionController(
            driver: SystemARSessionDriver(session: view.session),
            raycastResolver: RealityKitTargetRaycastResolver(view: view)
        )
    }
}

extension ARSessionController: @preconcurrency ARSessionDelegate {
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let state: DeviceTrackingState
        switch camera.trackingState {
        case .normal:
            state = .normal
        case .limited:
            state = .limited
        case .notAvailable:
            state = .unavailable
        }
        recordTrackingState(state)
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        recordPlaneObservations(in: anchors)
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        recordPlaneObservations(in: anchors)
    }

    func session(_ session: ARSession, didFailWithError error: any Error) {
        _ = error
        revokeRunningState(requiring: .failure)
    }

    func sessionWasInterrupted(_ session: ARSession) {
        revokeRunningState(requiring: .interruption)
    }

    private func revokeRunningState(requiring requirement: ARSessionRecoveryRequirement) {
        recoveryRequirement = requirement
        if isRunning {
            driver.pause()
        }
        isRunning = false
        recordTrackingState(.unavailable)
        publish(.running(false))
    }

    private func recordPlaneObservations(in anchors: [ARAnchor]) {
        for case let plane as ARPlaneAnchor in anchors {
            switch plane.alignment {
            case .horizontal:
                recordPlaneObservation(.horizontal)
            case .vertical:
                recordPlaneObservation(.vertical)
            @unknown default:
                continue
            }
        }
    }
}
