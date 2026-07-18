import ARKit

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
    private struct Observer {
        let token: ARSessionObserverToken
        let handler: (ARSessionEvent) -> Void
    }

    private let driver: any ARSessionDriving
    private var observers: [Observer] = []
    private var nextObserverID: UInt64 = 0
    private var lastTrackingState: DeviceTrackingState?
    private var observedPlaneAlignments: Set<PlaneAlignment> = []
    private(set) var isRunning = false
    private(set) var recoveryRequirement: ARSessionRecoveryRequirement?

    // Compatibility seam for the existing device-proof consumer. Additional
    // consumers register independently and cannot replace this callback.
    var onEvent: ((ARSessionEvent) -> Void)?

    init(driver: any ARSessionDriving = SystemARSessionDriver()) {
        self.driver = driver
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
