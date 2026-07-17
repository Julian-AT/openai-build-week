import Foundation
import Observation
import UIKit

enum PermissionAuthorizationState: String, CaseIterable, Sendable {
    case notDetermined
    case granted
    case denied
    case restricted
}

enum PhysicalOrientation: String, Sendable {
    case portrait
    case landscape
}

enum DeviceTrackingState: String, Sendable {
    case initializing
    case normal
    case limited
    case unavailable
}

enum PlaneAlignment: String, Hashable, Sendable {
    case horizontal
    case vertical
}

struct ARSessionPolicy: Equatable, Sendable {
    var detectedPlaneAlignments: Set<PlaneAlignment>
    var requiresRearLiDAR: Bool

    static let deviceProof = ARSessionPolicy(
        detectedPlaneAlignments: [.horizontal, .vertical],
        requiresRearLiDAR: false
    )
}

struct ARSessionEvidence: Equatable, Sendable {
    var isRunning = false
    var trackingState: DeviceTrackingState = .initializing
    var observedPlaneAlignments: Set<PlaneAlignment> = []
}

struct DeviceProofState: Equatable, Sendable {
    var cameraAuthorization: PermissionAuthorizationState = .notDetermined
    var microphoneAuthorization: PermissionAuthorizationState = .notDetermined
    var physicalOrientation: PhysicalOrientation = .portrait
    var session = ARSessionEvidence()

    var cameraCapabilityAvailable: Bool {
        cameraAuthorization == .granted
    }

    var optionalMicrophoneCapabilityAvailable: Bool {
        microphoneAuthorization == .granted
    }

    var shouldRunARSession: Bool {
        cameraCapabilityAvailable
    }

    var arTrackingAvailable: Bool {
        cameraCapabilityAvailable
            && session.isRunning
            && session.trackingState != .unavailable
    }

    var planeDetectionAvailable: Bool {
        arTrackingAvailable
    }

    var horizontalPlaneObserved: Bool {
        session.observedPlaneAlignments.contains(.horizontal)
    }

    var verticalPlaneObserved: Bool {
        session.observedPlaneAlignments.contains(.vertical)
    }

    var visualFrameCaptureAvailable: Bool {
        cameraCapabilityAvailable
            && physicalOrientation == .portrait
            && session.isRunning
            && session.trackingState == .normal
            && session.observedPlaneAlignments.isEmpty == false
    }

    var minimalVisualFramePacketAvailable: Bool {
        visualFrameCaptureAvailable
    }

    var typedTapP0Available: Bool {
        true
    }

    mutating func apply(_ event: ARSessionEvent) {
        switch event {
        case let .running(isRunning):
            session.isRunning = isRunning
            if isRunning == false {
                session.trackingState = .unavailable
            }
        case let .tracking(trackingState):
            session.trackingState = trackingState
        case let .planeObserved(alignment):
            session.observedPlaneAlignments.insert(alignment)
        }
    }
}

enum CandidatePrimaryAction: Equatable, Sendable {
    case requestCamera
    case openSettings
    case restartTracking

    var label: String {
        switch self {
        case .requestCamera:
            "Allow Camera Access"
        case .openSettings:
            "Open Settings"
        case .restartTracking:
            "Restart Tracking"
        }
    }
}

@MainActor
@Observable
final class DeviceProofModel {
    private(set) var state: DeviceProofState
    private(set) var isPerformingPermissionRequest = false

    @ObservationIgnored
    private let permissionController: any PermissionControlling

    @ObservationIgnored
    private let arSessionController: ARSessionController

    init(
        state: DeviceProofState = DeviceProofState(),
        permissionController: (any PermissionControlling)? = nil,
        arSessionController: ARSessionController? = nil
    ) {
        self.state = state
        self.permissionController = permissionController ?? PermissionController()
        self.arSessionController = arSessionController ?? ARSessionController()
        self.arSessionController.onEvent = { [weak self] event in
            self?.state.apply(event)
        }
    }

    var statusTitle: String {
        switch state.cameraAuthorization {
        case .notDetermined:
            "Camera access is required"
        case .denied, .restricted:
            "Camera access is off"
        case .granted where arSessionController.recoveryRequirement != nil:
            "AR tracking needs a restart"
        case .granted where state.physicalOrientation == .landscape:
            "Rotate to portrait"
        case .granted where state.session.isRunning == false:
            "Starting AR tracking"
        case .granted where state.session.trackingState == .unavailable:
            "Tracking is unavailable"
        case .granted where state.session.trackingState == .limited:
            "Move slowly to restore tracking"
        case .granted where state.session.observedPlaneAlignments.isEmpty:
            "Look for a floor or wall"
        case .granted:
            "Ready to capture a test frame"
        }
    }

    var statusMessage: String {
        switch state.cameraAuthorization {
        case .notDetermined:
            "ReRoom needs the camera to run this device check. No frame is captured until you allow access."
        case .denied, .restricted:
            "Turn on camera access in Settings to run tracking and capture a test frame."
        case .granted where arSessionController.recoveryRequirement != nil:
            "Restart tracking before selecting another capture frame. Saved evidence stays on this iPhone."
        case .granted where state.physicalOrientation == .landscape:
            "Tracking stays active. Return to portrait to capture a test frame."
        case .granted where state.session.isRunning == false:
            "Keep the phone upright and point it toward visible floor."
        case .granted where state.session.trackingState == .unavailable:
            "Restart the device check. Saved evidence stays on this iPhone."
        case .granted where state.session.trackingState == .limited:
            "Keep the floor in view and avoid fast movement."
        case .granted where state.session.observedPlaneAlignments.isEmpty:
            "Move the phone slowly so ARKit can observe a surface."
        case .granted:
            "Hold the phone steady. This candidate verifies only the capture policy; physical verification remains pending."
        }
    }

    var primaryAction: CandidatePrimaryAction? {
        switch state.cameraAuthorization {
        case .notDetermined:
            .requestCamera
        case .denied, .restricted:
            .openSettings
        case .granted where arSessionController.recoveryRequirement != nil:
            .restartTracking
        case .granted:
            nil
        }
    }

    var statusAccessibilityIdentifier: String {
        switch state.cameraAuthorization {
        case .notDetermined:
            "release.permission.camera"
        case .denied, .restricted:
            "release.permission.camera.blocked"
        case .granted where state.physicalOrientation == .landscape:
            "release.coaching.orientation"
        case .granted where state.session.isRunning == false:
            "release.status.session"
        case .granted where state.session.trackingState == .unavailable:
            "release.status.tracking.unavailable"
        case .granted where state.session.trackingState == .limited:
            "release.status.tracking"
        case .granted where state.session.observedPlaneAlignments.isEmpty:
            "release.status.planes.empty"
        case .granted:
            "release.status.capture"
        }
    }

    func prepare() async {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        state.cameraAuthorization = permissionController.authorizationState(for: .camera)
        state.microphoneAuthorization = permissionController.authorizationState(for: .microphone)
        refreshPhysicalOrientation()
        arSessionController.synchronize(cameraAuthorization: state.cameraAuthorization)
    }

    func performPrimaryAction() async {
        switch primaryAction {
        case .requestCamera:
            await requestCameraAccess()
        case .openSettings:
            await openSettings()
        case .restartTracking:
            _ = arSessionController.restartAfterRecovery(
                cameraAuthorization: state.cameraAuthorization
            )
        case nil:
            break
        }
    }

    func checkMicrophoneAccess() async {
        isPerformingPermissionRequest = true
        defer { isPerformingPermissionRequest = false }

        state.microphoneAuthorization = await permissionController.requestAccess(for: .microphone)
    }

    func refreshPhysicalOrientation() {
        let deviceOrientation = UIDevice.current.orientation
        if deviceOrientation.isLandscape {
            state.physicalOrientation = .landscape
        } else if deviceOrientation.isPortrait {
            state.physicalOrientation = .portrait
        }
        arSessionController.handlePhysicalOrientation(state.physicalOrientation)
    }

    private func requestCameraAccess() async {
        isPerformingPermissionRequest = true
        defer { isPerformingPermissionRequest = false }

        state.cameraAuthorization = await permissionController.requestAccess(for: .camera)
        arSessionController.synchronize(cameraAuthorization: state.cameraAuthorization)
    }

    private func openSettings() async {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        _ = await UIApplication.shared.open(settingsURL)
    }
}
