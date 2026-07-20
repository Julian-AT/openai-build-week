import AVFoundation

enum DevicePermission: Equatable, Sendable {
    case camera
    case microphone

    var mediaType: AVMediaType {
        switch self {
        case .camera:
            .video
        case .microphone:
            .audio
        }
    }
}

@MainActor
protocol PermissionControlling: AnyObject {
    func authorizationState(for permission: DevicePermission) -> PermissionAuthorizationState
    func requestAccess(for permission: DevicePermission) async -> PermissionAuthorizationState
}

@MainActor
final class PermissionController: PermissionControlling {
    typealias StatusProvider = (DevicePermission) -> PermissionAuthorizationState
    typealias RequestProvider = (DevicePermission) async -> PermissionAuthorizationState

    private let statusProvider: StatusProvider
    private let requestProvider: RequestProvider

    init(
        statusProvider: @escaping StatusProvider,
        requestProvider: @escaping RequestProvider
    ) {
        self.statusProvider = statusProvider
        self.requestProvider = requestProvider
    }

    convenience init() {
        self.init(
            statusProvider: { permission in
                Self.map(AVCaptureDevice.authorizationStatus(for: permission.mediaType))
            },
            requestProvider: { permission in
                _ = await AVCaptureDevice.requestAccess(for: permission.mediaType)
                return Self.map(AVCaptureDevice.authorizationStatus(for: permission.mediaType))
            }
        )
    }

    func authorizationState(for permission: DevicePermission) -> PermissionAuthorizationState {
        statusProvider(permission)
    }

    func requestAccess(for permission: DevicePermission) async -> PermissionAuthorizationState {
        let currentState = statusProvider(permission)
        guard currentState == .notDetermined else {
            return currentState
        }

        return await requestProvider(permission)
    }

    private static func map(_ status: AVAuthorizationStatus) -> PermissionAuthorizationState {
        switch status {
        case .notDetermined:
            .notDetermined
        case .authorized:
            .granted
        case .denied:
            .denied
        case .restricted:
            .restricted
        @unknown default:
            .restricted
        }
    }
}
