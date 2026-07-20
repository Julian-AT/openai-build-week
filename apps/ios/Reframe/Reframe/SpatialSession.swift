import ARKit
import AVFoundation
import Observation

@MainActor
@Observable
final class SpatialSession {
  enum Phase: Equatable {
    case awaitingPermission
    case initializing
    case tracking
    case limited(String)
    case unavailable
  }

  private(set) var phase: Phase = .awaitingPermission
  let session = ARSession()
  private var delegate: SessionDelegate?

  func start() async {
    let granted = await requestCameraAccess()
    guard granted else {
      phase = .unavailable
      return
    }
    phase = .initializing
    let delegate = SessionDelegate { [weak self] phase in
      self?.phase = phase
    }
    self.delegate = delegate
    session.delegate = delegate
    let configuration = ARWorldTrackingConfiguration()
    configuration.planeDetection = [.horizontal, .vertical]
    configuration.environmentTexturing = .automatic
    session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
  }

  func pause() {
    session.pause()
  }

  private func requestCameraAccess() async -> Bool {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      true
    case .notDetermined:
      await AVCaptureDevice.requestAccess(for: .video)
    case .denied, .restricted:
      false
    @unknown default:
      false
    }
  }
}

private final class SessionDelegate: NSObject, ARSessionDelegate, @unchecked Sendable {
  private let update: @MainActor @Sendable (SpatialSession.Phase) -> Void

  init(update: @escaping @MainActor @Sendable (SpatialSession.Phase) -> Void) {
    self.update = update
  }

  func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
    let phase: SpatialSession.Phase =
      switch camera.trackingState {
      case .normal:
        .tracking
      case .notAvailable:
        .unavailable
      case .limited(let reason):
        .limited(reason.description)
      }
    Task { @MainActor in update(phase) }
  }
}

extension ARCamera.TrackingState.Reason {
  fileprivate var description: String {
    switch self {
    case .initializing: "Initializing spatial tracking"
    case .excessiveMotion: "Move the iPhone more slowly"
    case .insufficientFeatures: "Point toward a textured surface"
    case .relocalizing: "Returning to the mapped space"
    @unknown default: "Spatial tracking is limited"
    }
  }
}
