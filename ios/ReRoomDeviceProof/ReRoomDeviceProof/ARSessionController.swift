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
    private let driver: any ARSessionDriving
    private(set) var isRunning = false
    private(set) var recoveryRequirement: ARSessionRecoveryRequirement?
    var onEvent: ((ARSessionEvent) -> Void)?

    init(driver: any ARSessionDriving = SystemARSessionDriver()) {
        self.driver = driver
        super.init()
        self.driver.delegate = self
    }

    var currentFrame: ARFrame? {
        driver.currentFrame
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
        onEvent?(.running(true))
    }

    @discardableResult
    func restartAfterRecovery(cameraAuthorization: PermissionAuthorizationState) -> Bool {
        guard cameraAuthorization == .granted, recoveryRequirement != nil else {
            return false
        }
        driver.run(policy: .deviceProof)
        recoveryRequirement = nil
        isRunning = true
        onEvent?(.running(true))
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
        onEvent?(.worldReset)
        onEvent?(.running(true))
        return true
    }

    func recordPlaneObservation(_ alignment: PlaneAlignment) {
        onEvent?(.planeObserved(alignment))
    }

    private func stopForUnavailableCamera() {
        recoveryRequirement = nil
        guard isRunning else {
            return
        }

        driver.pause()
        isRunning = false
        onEvent?(.running(false))
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
        onEvent?(.tracking(state))
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
        onEvent?(.tracking(.unavailable))
        onEvent?(.running(false))
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
