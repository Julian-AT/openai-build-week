import ARKit
import AVFoundation
import CaptureCore
import Observation
import RenderCore
import Security
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
  private(set) var roomCredentials: RoomSessionCredentials?
  private(set) var gatewayStatus = "Room not connected"
  private(set) var pendingPreviewID: String?
  private(set) var pendingPreviewRevision: Int?
  private(set) var pendingPlacementAssetID: String?
  private(set) var pendingPlacementTransform: SpatialTransform?
  private(set) var isSubmittingTurn = false
  private(set) var lastTransactionID: String?
  private(set) var lastCommittedRevision: Int?

  /// Observation token consumed by the AR view. Keeping this as a value (rather
  /// than relying on the session reference changing) ensures a newly prepared
  /// preview invalidates the SwiftUI representable and gets materialized.
  var placementPreviewToken: String? {
    guard let transform = pendingPlacementTransform else { return nil }
    let assetID = pendingPlacementAssetID ?? "placement-preview"
    return "\(assetID):\(transform.values.map { String($0) }.joined(separator: ","))"
  }

  let session = ARSession()
  private(set) var sessionID = "room_pending"
  private var delegate: SessionDelegate?
  private var planeStore = ObservedPlaneStore()
  private var gatewayClient: GatewayClient?
  private let realtimeVoice = NativeRealtimeVoiceTransport()
  private let roomConnectionStore = RoomConnectionStore()
  private var verifiedUSDZFiles: [String: (descriptor: AssetDeliveryDescriptor, url: URL)] = [:]

  var lightEstimate: SpatialLightEstimate? { latestFrameObservation?.lightEstimate }
  var cameraPose: SpatialTransform? { latestFrameObservation?.worldFromCameraARKit }
  var observedPlanes: [String: ObservedPlane] { planeStore.planes }

  func adopt(room credentials: RoomSessionCredentials) {
    sessionID = credentials.sessionID
    roomCredentials = credentials
  }

  func start() async {
    configureRoomFromEnvironment()
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
    realtimeVoice.stop()
  }

  func targetFrame(matching timestamp: TimeInterval) -> TargetFrame? {
    guard let targetFrame = latestFrameObservation?.targetFrame,
      abs(targetFrame.timestamp - timestamp) < 0.25
    else { return nil }
    return targetFrame
  }

  func record(_ targetSeed: TargetSeed) {
    guard targetSeed.sessionID == sessionID else { return }
    lastTargetSeed = targetSeed
  }

  /// Checks the room gateway when the operator starts voice. This is a
  /// room-scoped WebRTC session. Realtime only owns audio and diagnostics;
  /// deterministic typed turns retain all scene authority.
  func startRealtimeVoice() async -> Bool {
    guard let gatewayClient else {
      gatewayStatus = "Realtime unavailable after room connection"
      return false
    }
    gatewayStatus = "Requesting microphone and connecting realtime voice…"
    do {
      try await realtimeVoice.start(client: gatewayClient) { [weak self] utterance in
        guard let self else { return "{\"status\":\"unavailable\"}" }
        await self.submitTypedTurn(utterance)
        let output: [String: String] = [
          "status": "accepted",
          "gateway_status": self.gatewayStatus,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: output),
          let text = String(data: data, encoding: .utf8),
          text.utf8.count <= 8_000
        else { return "{\"status\":\"accepted\"}" }
        return text
      }
      gatewayStatus = "Realtime voice connected — scene edits still require typed confirmation"
      return true
    } catch RealtimeVoiceError.microphonePermissionDenied {
      gatewayStatus = "Microphone permission denied — typed edits remain ready"
    } catch GatewayClientError.gatewayUnreachable {
      gatewayStatus = "Gateway unreachable — use the Mac LAN address"
    } catch GatewayClientError.unauthorized {
      gatewayStatus = "Realtime authorization expired — reconnect the room"
    } catch {
      gatewayStatus = "Realtime voice unavailable — typed edits remain ready"
    }
    return false
  }

  func stopRealtimeGateway() {
    realtimeVoice.stop()
    gatewayStatus = gatewayClient == nil ? "Room not connected" : "Realtime gateway disconnected"
  }

  func submitTypedTurn(_ utterance: String) async {
    guard !isSubmittingTurn else { return }
    isSubmittingTurn = true
    gatewayStatus = "Preparing preview…"
    defer { isSubmittingTurn = false }
    pendingPlacementAssetID = nil
    pendingPlacementTransform = nil
    guard lastTargetSeed?.arkitHit != nil else {
      gatewayStatus = "Aim at the floor and let the reticle settle"
      return
    }
    guard let gatewayClient else {
      gatewayStatus = "Preview available after room connection"
      return
    }
    do {
      let proposalData = try await gatewayClient.submitTurn(
        utterance: utterance,
        sceneRevision: lastCommittedRevision ?? 0,
        pointerContextID: lastTargetSeed.map { "pointer_\($0.frameID)" },
        pointerContext: lastTargetSeed?.arkitHit
      )
      let proposalID: String
      if jsonString("type", in: proposalData) == "placement_preview" {
        guard let placementProposalID = jsonString("proposal_id", in: proposalData) else {
          gatewayStatus = "Typed response was not a preview"
          return
        }
        proposalID = placementProposalID
      } else if let responseProposalID = jsonString("proposal_id", in: proposalData) {
        proposalID = responseProposalID
      } else {
        gatewayStatus = "Typed response was not a preview"
        return
      }
      if let values = jsonDoubleArray("world_from_asset", in: proposalData), values.count == 16 {
        pendingPlacementAssetID = jsonStringInObject("asset_id", key: "intent", in: proposalData)
        pendingPlacementTransform = try AuthoritativeAssetTransform.decode(values)
      }
      let previewData = try await gatewayClient.preparePreview(proposalID: proposalID)
      pendingPreviewID = jsonString("preview_id", in: previewData)
      pendingPreviewRevision = jsonInt("base_scene_revision", in: previewData)
      guard pendingPreviewID != nil, pendingPreviewRevision != nil else {
        gatewayStatus = "Preview response was incomplete"
        return
      }
      gatewayStatus =
        pendingPlacementTransform == nil
        ? "Preview ready — confirm to commit"
        : "Preview ready — loading verified model…"
    } catch GatewayClientError.gatewayUnreachable {
      gatewayStatus = "Gateway unreachable — use the Mac LAN address"
    } catch {
      gatewayStatus = "Typed preview unavailable"
    }
  }

  /// Called by the render coordinator after the verified USDZ has been loaded.
  func placementAssetDidLoad() {
    guard pendingPlacementTransform != nil else { return }
    gatewayStatus = "Preview ready — confirm to commit"
  }

  /// A missing or invalid catalog derivative must be visible to the operator;
  /// silently leaving an empty anchor looks like a spatial tracking failure.
  func placementAssetDidFail(_ error: Error) {
    guard pendingPlacementTransform != nil else { return }
    if let gatewayError = error as? GatewayClientError,
      gatewayError == .gatewayUnreachable
    {
      gatewayStatus = "Gateway unreachable — use the Mac LAN address"
    } else {
      gatewayStatus = "Preview model unavailable — try again"
    }
  }

  func confirmPendingPreview() async {
    guard let gatewayClient else {
      gatewayStatus = "Room not connected"
      return
    }
    guard let previewID = pendingPreviewID, let revision = pendingPreviewRevision else {
      gatewayStatus = "No preview is waiting for confirmation"
      return
    }
    do {
      let delta = try await gatewayClient.confirmPreview(
        previewID: previewID,
        expectedSceneRevision: revision,
        idempotencyKey: "txidem_\(UUID().uuidString.lowercased())"
      )
      lastTransactionID = jsonString("transaction_id", in: delta)
      lastCommittedRevision = jsonInt("scene_revision", in: delta)
      pendingPreviewID = nil
      pendingPreviewRevision = nil
      gatewayStatus = "Edit committed"
    } catch {
      gatewayStatus = "Confirmation rejected safely"
    }
  }

  func restore(transactionID: String, expectedSceneRevision: Int, idempotencyKey: String) async {
    guard let gatewayClient else {
      gatewayStatus = "Room not connected"
      return
    }
    do {
      let delta = try await gatewayClient.restore(
        transactionID: transactionID,
        expectedSceneRevision: expectedSceneRevision,
        idempotencyKey: idempotencyKey
      )
      lastCommittedRevision = jsonInt("scene_revision", in: delta) ?? lastCommittedRevision
      gatewayStatus = "Restore synchronized"
    } catch {
      gatewayStatus = "Restore pending synchronization"
    }
  }

  func restoreLatest() async {
    guard let transactionID = lastTransactionID else {
      gatewayStatus = "No committed edit to restore"
      return
    }
    await restore(
      transactionID: transactionID,
      expectedSceneRevision: lastCommittedRevision ?? 1,
      idempotencyKey: "txidem_\(UUID().uuidString.lowercased())"
    )
  }

  private func jsonString(_ key: String, in data: Data) -> String? {
    guard let object = try? JSONSerialization.jsonObject(with: data),
      let dictionary = object as? [String: Any],
      let value = dictionary[key] as? String,
      !value.isEmpty
    else { return nil }
    return value
  }

  private func jsonInt(_ key: String, in data: Data) -> Int? {
    guard let object = try? JSONSerialization.jsonObject(with: data),
      let dictionary = object as? [String: Any],
      let value = dictionary[key] as? Int
    else { return nil }
    return value
  }

  private func jsonDoubleArray(_ key: String, in data: Data) -> [Double]? {
    guard let object = try? JSONSerialization.jsonObject(with: data),
      let dictionary = object as? [String: Any],
      let values = dictionary[key] as? [NSNumber]
    else { return nil }
    let result = values.map(\.doubleValue)
    return result.allSatisfy(\.isFinite) ? result : nil
  }

  private func jsonStringInObject(_ key: String, key objectKey: String, in data: Data) -> String? {
    guard let object = try? JSONSerialization.jsonObject(with: data),
      let dictionary = object as? [String: Any],
      let nested = dictionary[objectKey] as? [String: Any],
      let value = nested[key] as? String,
      !value.isEmpty
    else { return nil }
    return value
  }

  private func configureRoomFromEnvironment() {
    if let roomID = ProcessInfo.processInfo.environment["REFRAME_ROOM_ID"],
      let credential = ProcessInfo.processInfo.environment["REFRAME_ROOM_CREDENTIAL"],
      let expiryText = ProcessInfo.processInfo.environment["REFRAME_ROOM_EXPIRES_AT_MS"],
      let expiresAt = Int64(expiryText),
      let baseURLText = ProcessInfo.processInfo.environment["REFRAME_GATEWAY_URL"],
      let baseURL = URL(string: baseURLText),
      let room = try? RoomSessionCredentials(
        sessionID: roomID,
        credential: credential,
        expiresAtMilliseconds: expiresAt
      ),
      let client = try? GatewayClient(baseURL: baseURL, room: room)
    {
      connect(room: room, client: client)
      roomConnectionStore.save(room: room, baseURL: baseURL)
      return
    }
    guard let saved = roomConnectionStore.load(),
      saved.room.expiresAtMilliseconds > nowMilliseconds()
    else {
      gatewayStatus = "Room connection expired"
      return
    }
    guard let client = try? GatewayClient(baseURL: saved.baseURL, room: saved.room) else {
      gatewayStatus = "Room connection unavailable"
      return
    }
    connect(room: saved.room, client: client)
  }

  private func connect(room: RoomSessionCredentials, client: GatewayClient) {
    sessionID = room.sessionID
    roomCredentials = room
    gatewayClient = client
    gatewayStatus = "Room connected"
  }

  /// Materializes a room-authorized USDZ in the app cache. This is intentionally
  /// outside the AR render loop; callers hand the verified file to RenderCore,
  /// which performs the final hash check immediately before RealityKit loads it.
  func verifiedUSDZFile(
    for assetID: String
  ) async throws -> (descriptor: AssetDeliveryDescriptor, url: URL) {
    if let cached = verifiedUSDZFiles[assetID],
      FileManager.default.fileExists(atPath: cached.url.path)
    {
      return cached
    }
    guard let gatewayClient else { throw GatewayClientError.unauthorized }
    let delivery = try await gatewayClient.downloadVerifiedUSDZ(assetID: assetID)
    let directory = try assetCacheDirectory()
    let fileURL = directory.appendingPathComponent("\(delivery.descriptor.expectedSHA256).usdz")
    try await Task.detached(priority: .utility) {
      try delivery.bytes.write(to: fileURL, options: [.atomic])
    }.value
    _ = try await delivery.descriptor.verifiedFileURL(fileURL)
    let result = (descriptor: delivery.descriptor, url: fileURL)
    verifiedUSDZFiles[assetID] = result
    return result
  }

  private func nowMilliseconds() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1_000)
  }

  private func assetCacheDirectory() throws -> URL {
    guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    else {
      throw AssetDeliveryError.unreadableFile
    }
    let directory = caches.appendingPathComponent("Reframe/Assets", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
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

private struct RoomConnectionStore {
  private let service = "com.julianschmidt.reframe.room-connection"
  private let account = "active"

  func save(room: RoomSessionCredentials, baseURL: URL) {
    guard let data = try? JSONEncoder().encode(StoredRoomConnection(room: room, baseURL: baseURL))
    else { return }
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    SecItemDelete(query as CFDictionary)
    var attributes = query
    attributes[kSecValueData as String] = data
    attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    SecItemAdd(attributes as CFDictionary, nil)
  }

  func load() -> (room: RoomSessionCredentials, baseURL: URL)? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data,
      let stored = try? JSONDecoder().decode(StoredRoomConnection.self, from: data),
      let baseURL = URL(string: stored.baseURL)
    else { return nil }
    return (stored.room, baseURL)
  }
}

private struct StoredRoomConnection: Codable {
  let room: RoomSessionCredentials
  let baseURL: String

  init(room: RoomSessionCredentials, baseURL: URL) {
    self.room = room
    self.baseURL = baseURL.absoluteString
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
