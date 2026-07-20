import ARKit
import AVFoundation
import CaptureCore
import Observation
import SpatialProtocol

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
  private(set) var latestFrameObservation: CameraFrameObservation?
  private(set) var lastTargetSeed: TargetSeed?

  let session = ARSession()
  let sessionID = "session_\(UUID().uuidString.lowercased())"
  private var delegate: SessionDelegate?
  private var planeStore = ObservedPlaneStore()

  var lightEstimate: SpatialLightEstimate? { latestFrameObservation?.lightEstimate }
  var cameraPose: SpatialTransform? { latestFrameObservation?.worldFromCameraARKit }
  var observedPlanes: [String: ObservedPlane] { planeStore.planes }

  func start() async {
    let granted = await requestCameraAccess()
    guard granted else {
      phase = .unavailable
      return
    }
    phase = .initializing
    let delegate = SessionDelegate(
      updatePhase: { [weak self] phase in self?.phase = phase },
      updateFrame: { [weak self] observation in self?.accept(observation) },
      upsertPlane: { [weak self] plane in self?.accept(plane) },
      removePlane: { [weak self] planeID, revision in self?.removePlane(planeID, revision: revision)
      }
    )
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

  func targetFrame(matching timestamp: TimeInterval) -> TargetFrame? {
    guard let targetFrame = latestFrameObservation?.targetFrame,
      abs(targetFrame.timestamp - timestamp) < 0.000_001
    else { return nil }
    return targetFrame
  }

  func record(_ targetSeed: TargetSeed) {
    guard targetSeed.sessionID == sessionID else { return }
    lastTargetSeed = targetSeed
  }

  private func accept(_ observation: CameraFrameObservation) {
    guard observation.targetFrame.id > (latestFrameObservation?.targetFrame.id ?? 0) else { return }
    latestFrameObservation = observation
  }

  private func accept(_ plane: ObservedPlane) {
    planeStore.upsert(plane)
  }

  private func removePlane(_ planeID: String, revision: Int) {
    planeStore.remove(id: planeID, revision: revision)
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
  private let updatePhase: @MainActor @Sendable (SpatialSession.Phase) -> Void
  private let updateFrame: @MainActor @Sendable (CameraFrameObservation) -> Void
  private let upsertPlane: @MainActor @Sendable (ObservedPlane) -> Void
  private let removePlane: @MainActor @Sendable (String, Int) -> Void
  private var nextFrameID: UInt64 = 1
  private var planeRevisions: [UUID: Int] = [:]
  private let frameHandoffLock = NSLock()
  private var pendingFrameObservation: CameraFrameObservation?
  private var isFrameDeliveryScheduled = false

  init(
    updatePhase: @escaping @MainActor @Sendable (SpatialSession.Phase) -> Void,
    updateFrame: @escaping @MainActor @Sendable (CameraFrameObservation) -> Void,
    upsertPlane: @escaping @MainActor @Sendable (ObservedPlane) -> Void,
    removePlane: @escaping @MainActor @Sendable (String, Int) -> Void
  ) {
    self.updatePhase = updatePhase
    self.updateFrame = updateFrame
    self.upsertPlane = upsertPlane
    self.removePlane = removePlane
  }

  func session(_ session: ARSession, didUpdate frame: ARFrame) {
    let frameID = nextFrameID
    nextFrameID &+= 1
    let image = frame.capturedImage
    let light = frame.lightEstimate.map {
      SpatialLightEstimate(
        ambientIntensityLumens: $0.ambientIntensity,
        ambientColorTemperatureKelvin: $0.ambientColorTemperature
      )
    }
    let observation = CameraFrameObservation(
      targetFrame: TargetFrame(
        id: frameID,
        timestamp: frame.timestamp,
        encodedImageWidth: CVPixelBufferGetWidth(image),
        encodedImageHeight: CVPixelBufferGetHeight(image)
      ),
      worldFromCameraARKit: spatialTransform(frame.camera.transform),
      lightEstimate: light
    )
    enqueueLatestFrame(observation)
  }

  func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
    for observation in anchors.compactMap(makePlaneObservation) {
      Task { @MainActor in upsertPlane(observation) }
    }
  }

  func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
    for observation in anchors.compactMap(makePlaneObservation) {
      Task { @MainActor in upsertPlane(observation) }
    }
  }

  func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
    for anchor in anchors where anchor is ARPlaneAnchor {
      let revision = (planeRevisions[anchor.identifier] ?? 0) + 1
      planeRevisions[anchor.identifier] = revision
      let planeID = planeIdentifier(anchor.identifier)
      Task { @MainActor in removePlane(planeID, revision) }
    }
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
    Task { @MainActor in updatePhase(phase) }
  }

  private func makePlaneObservation(_ anchor: ARAnchor) -> ObservedPlane? {
    guard let plane = anchor as? ARPlaneAnchor else { return nil }
    let revision = (planeRevisions[plane.identifier] ?? 0) + 1
    planeRevisions[plane.identifier] = revision
    let extent = plane.planeExtent
    return ObservedPlane(
      id: planeIdentifier(plane.identifier),
      revision: revision,
      classification: plane.classification.spatialClassification,
      worldFromPlane: spatialTransform(plane.transform),
      extent: PlaneExtent(
        widthMeters: Double(extent.width),
        heightMeters: Double(extent.height)
      ),
      boundaryVerticesLocalXZ: plane.geometry.boundaryVertices.map {
        PlaneBoundaryPoint(xMeters: Double($0.x), zMeters: Double($0.z))
      }
    )
  }

  private func enqueueLatestFrame(_ observation: CameraFrameObservation) {
    frameHandoffLock.lock()
    pendingFrameObservation = observation
    guard !isFrameDeliveryScheduled else {
      frameHandoffLock.unlock()
      return
    }
    isFrameDeliveryScheduled = true
    frameHandoffLock.unlock()

    Task { @MainActor [weak self] in self?.deliverLatestFrame() }
  }

  @MainActor private func deliverLatestFrame() {
    frameHandoffLock.lock()
    let observation = pendingFrameObservation
    pendingFrameObservation = nil
    isFrameDeliveryScheduled = false
    frameHandoffLock.unlock()
    if let observation { updateFrame(observation) }
  }
}

func planeIdentifier(_ identifier: UUID) -> String {
  "arkit_plane_\(identifier.uuidString.lowercased())"
}

private func spatialTransform(_ matrix: simd_float4x4) -> SpatialTransform {
  SpatialTransform(values: [
    Double(matrix.columns.0.x), Double(matrix.columns.1.x), Double(matrix.columns.2.x),
    Double(matrix.columns.3.x),
    Double(matrix.columns.0.y), Double(matrix.columns.1.y), Double(matrix.columns.2.y),
    Double(matrix.columns.3.y),
    Double(matrix.columns.0.z), Double(matrix.columns.1.z), Double(matrix.columns.2.z),
    Double(matrix.columns.3.z),
    Double(matrix.columns.0.w), Double(matrix.columns.1.w), Double(matrix.columns.2.w),
    Double(matrix.columns.3.w),
  ])
}

extension ARPlaneAnchor.Classification {
  fileprivate var spatialClassification: ObservedPlaneClassification {
    switch self {
    case .floor: .floor
    case .wall: .wall
    case .ceiling: .ceiling
    case .table: .table
    case .seat: .seat
    case .door: .door
    case .window: .window
    case .none: .unknown
    @unknown default: .unknown
    }
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
