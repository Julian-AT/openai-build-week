import ARKit

enum ARSessionEvent: Equatable, Sendable {
    case running(Bool)
    case tracking(DeviceTrackingState)
    case planeObserved(PlaneAlignment)
}

@MainActor
protocol ARSessionDriving: AnyObject {
    var delegate: (any ARSessionDelegate)? { get set }
    var currentFrame: ARFrame? { get }

    func run(policy: ARSessionPolicy)
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
        let configuration = ARWorldTrackingConfiguration()
        var planeDetection: ARWorldTrackingConfiguration.PlaneDetection = []
        if policy.detectedPlaneAlignments.contains(.horizontal) {
            planeDetection.insert(.horizontal)
        }
        if policy.detectedPlaneAlignments.contains(.vertical) {
            planeDetection.insert(.vertical)
        }
        configuration.planeDetection = planeDetection
        session.run(configuration)
    }

    func pause() {
        session.pause()
    }
}

@MainActor
final class ARSessionController: NSObject {
    private let driver: any ARSessionDriving
    private(set) var isRunning = false
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

        guard isRunning == false else {
            return
        }

        driver.run(policy: .deviceProof)
        isRunning = true
        onEvent?(.running(true))
    }

    func handlePhysicalOrientation(_ orientation: PhysicalOrientation) {
        // Orientation controls capture eligibility in DeviceProofState. It never
        // pauses or restarts a healthy AR session.
        _ = orientation
    }

    func recordPlaneObservation(_ alignment: PlaneAlignment) {
        onEvent?(.planeObserved(alignment))
    }

    private func stopForUnavailableCamera() {
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
        onEvent?(.tracking(.unavailable))
    }

    func sessionWasInterrupted(_ session: ARSession) {
        onEvent?(.tracking(.unavailable))
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
