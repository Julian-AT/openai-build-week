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
    var detectedPlaneAlignments: Set<PlaneAlignment> = []
    var requiresRearLiDAR = false

    static let deviceProof = ARSessionPolicy()
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

    // Task 2 replaces these conservative seed defaults with the tested policy.
    var cameraCapabilityAvailable: Bool { false }
    var optionalMicrophoneCapabilityAvailable: Bool { false }
    var shouldRunARSession: Bool { false }
    var arTrackingAvailable: Bool { false }
    var planeDetectionAvailable: Bool { false }
    var visualFrameCaptureAvailable: Bool { false }
    var minimalVisualFramePacketAvailable: Bool { false }
    var typedTapP0Available: Bool { true }
}

enum CandidatePrimaryAction: Equatable, Sendable {
    case requestCamera
    case openSettings

    var label: String {
        switch self {
        case .requestCamera:
            "Allow Camera Access"
        case .openSettings:
            "Open Settings"
        }
    }
}

@MainActor
@Observable
final class DeviceProofModel {
    private(set) var state = DeviceProofState()
    private(set) var isPerformingPermissionRequest = false

    var statusTitle: String {
        switch state.cameraAuthorization {
        case .notDetermined:
            "Camera access is required"
        case .denied, .restricted:
            "Camera access is off"
        case .granted:
            "Starting AR tracking"
        }
    }

    var statusMessage: String {
        switch state.cameraAuthorization {
        case .notDetermined:
            "ReRoom needs the camera to run this device check. No frame is captured until you allow access."
        case .denied, .restricted:
            "Turn on camera access in Settings to run tracking and capture a test frame."
        case .granted:
            "Keep the phone upright and point it toward visible floor."
        }
    }

    var primaryAction: CandidatePrimaryAction? {
        switch state.cameraAuthorization {
        case .notDetermined:
            .requestCamera
        case .denied, .restricted:
            .openSettings
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
        case .granted:
            "release.status.session"
        }
    }

    func prepare() async {
        // Permission and AR session adapters are introduced by Task 2.
    }

    func performPrimaryAction() async {
        // Permission and Settings actions are introduced by Task 2.
    }

    func refreshPhysicalOrientation() {
        let deviceOrientation = UIDevice.current.orientation
        if deviceOrientation.isLandscape {
            state.physicalOrientation = .landscape
        } else if deviceOrientation.isPortrait {
            state.physicalOrientation = .portrait
        }
    }
}
