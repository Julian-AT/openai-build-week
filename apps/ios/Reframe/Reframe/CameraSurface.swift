import ARKit
import CaptureCore
import RealityKit
import RenderCore
import SpatialProtocol
import SwiftUI

struct TargetCaptureRequest: Equatable, Identifiable {
  let id = UUID()
  let source: TargetSeedSource
}

struct CameraSurface: UIViewRepresentable {
  let spatialSession: SpatialSession
  let captureRequest: TargetCaptureRequest?
  /// Explicitly observes preview changes so SwiftUI updates the representable
  /// even though the session object itself remains the same reference.
  let placementToken: String?

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeUIView(context: Context) -> ARView {
    let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
    view.session = spatialSession.session
    view.renderOptions.insert(.disableMotionBlur)
    context.coordinator.attach(to: view)
    return view
  }

  func updateUIView(_ view: ARView, context: Context) {
    context.coordinator.parent = self
    if view.session !== spatialSession.session {
      view.session = spatialSession.session
    }
    context.coordinator.consume(captureRequest)
    context.coordinator.consumePlacementPreview()
  }

  static func dismantleUIView(_ view: ARView, coordinator: Coordinator) {
    coordinator.detach()
  }

  @MainActor
  final class Coordinator: NSObject {
    var parent: CameraSurface
    private weak var view: ARView?
    private var displayLink: CADisplayLink?
    private var lastReticleSampleTime: CFTimeInterval = 0
    private var lastCaptureRequestID: UUID?
    private var pendingCaptureRequest: TargetCaptureRequest?
    private var dwellTracker = ReticleDwellTracker()
    private var placementPreviewAnchor: AnchorEntity?
    private var placementPreviewKey: String?
    private var placementLoadTask: Task<Void, Never>?

    init(parent: CameraSurface) {
      self.parent = parent
    }

    func attach(to view: ARView) {
      self.view = view
      let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
      view.addGestureRecognizer(tap)
      let displayLink = CADisplayLink(target: self, selector: #selector(sampleReticle(_:)))
      displayLink.add(to: .main, forMode: .common)
      self.displayLink = displayLink
    }

    func detach() {
      placementLoadTask?.cancel()
      placementLoadTask = nil
      displayLink?.invalidate()
      displayLink = nil
      view = nil
    }

    func consume(_ request: TargetCaptureRequest?) {
      guard let request, request.id != lastCaptureRequestID else { return }
      pendingCaptureRequest = request
      capturePendingRequest()
    }

    func consumePlacementPreview() {
      guard let view else { return }
      guard let transform = parent.spatialSession.pendingPlacementTransform else {
        placementLoadTask?.cancel()
        placementLoadTask = nil
        placementPreviewAnchor?.removeFromParent()
        placementPreviewAnchor = nil
        placementPreviewKey = nil
        return
      }
      let assetID = parent.spatialSession.pendingPlacementAssetID ?? "placement-preview"
      let key =
        parent.placementToken
        ?? "\(assetID):\(transform.values.map { String($0) }.joined(separator: ","))"
      guard key != placementPreviewKey else { return }
      placementLoadTask?.cancel()
      placementPreviewAnchor?.removeFromParent()
      let matrix = simd_float4x4(rows: [
        SIMD4<Float>(
          Float(transform.values[0]),
          Float(transform.values[1]),
          Float(transform.values[2]),
          Float(transform.values[3])
        ),
        SIMD4<Float>(
          Float(transform.values[4]),
          Float(transform.values[5]),
          Float(transform.values[6]),
          Float(transform.values[7])
        ),
        SIMD4<Float>(
          Float(transform.values[8]),
          Float(transform.values[9]),
          Float(transform.values[10]),
          Float(transform.values[11])
        ),
        SIMD4<Float>(
          Float(transform.values[12]),
          Float(transform.values[13]),
          Float(transform.values[14]),
          Float(transform.values[15])
        ),
      ])
      let anchor = AnchorEntity(world: matrix)
      view.scene.addAnchor(anchor)
      placementPreviewAnchor = anchor
      placementPreviewKey = key

      // Keep network, disk, hashing, and RealityKit decoding off the frame
      // path. A preview is not rendered as a misleading proxy: until the
      // gateway-delivered, hash-verified USDZ is ready, no virtual geometry
      // is shown.
      let spatialSession = parent.spatialSession
      placementLoadTask = Task { @MainActor [weak self, weak anchor] in
        do {
          let delivery = try await spatialSession.verifiedUSDZFile(for: assetID)
          let entity = try await RealityKitAssetLoader.loadUSDZ(
            from: delivery.url,
            delivery: delivery.descriptor
          )
          guard let self, !Task.isCancelled, self.placementPreviewKey == key else { return }
          guard let anchor else { return }
          let bounds = entity.visualBounds(relativeTo: entity)
          if bounds.min.y.isFinite { entity.position.y = -bounds.min.y }
          entity.name = "reframe-placement-\(assetID)"
          anchor.addChild(entity)
          spatialSession.placementAssetDidLoad()
        } catch {
          // The preview remains empty rather than displaying an unverified or
          // dimensionally misleading stand-in. Surface the failure so the
          // operator can retry instead of mistaking it for tracking loss.
          guard !Task.isCancelled else { return }
          spatialSession.placementAssetDidFail(error)
        }
      }
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
      guard let view else { return }
      _ = capture(at: recognizer.location(in: view), source: .tap)
    }

    @objc private func sampleReticle(_ displayLink: CADisplayLink) {
      guard displayLink.timestamp - lastReticleSampleTime >= 0.1,
        parent.spatialSession.phase == .tracking,
        let view,
        let frame = view.session.currentFrame
      else { return }
      lastReticleSampleTime = displayLink.timestamp
      capturePendingRequest()
      let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
      let result = raycastResult(in: view, at: center)
      let worldPosition = result.map { spatialVector($0.worldTransform.columns.3) }
      if dwellTracker.observe(timestamp: frame.timestamp, worldPosition: worldPosition) {
        _ = capture(at: center, source: .reticleDwell)
      }
    }

    private func capturePendingRequest() {
      guard let request = pendingCaptureRequest, let view else { return }
      let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
      guard capture(at: center, source: request.source) else { return }
      lastCaptureRequestID = request.id
      pendingCaptureRequest = nil
    }

    @discardableResult
    private func capture(at point: CGPoint, source: TargetSeedSource) -> Bool {
      guard parent.spatialSession.phase == .tracking,
        let view,
        view.bounds.width > 0,
        view.bounds.height > 0,
        let frame = view.session.currentFrame,
        let targetFrame = parent.spatialSession.targetFrame(matching: frame.timestamp),
        let ray = view.ray(through: point)
      else { return false }

      let normalizedViewPoint = CGPoint(
        x: point.x / view.bounds.width,
        y: point.y / view.bounds.height
      )
      let orientation = view.window?.windowScene?.interfaceOrientation ?? .portrait
      let imageFromView = frame.displayTransform(
        for: orientation,
        viewportSize: view.bounds.size
      ).inverted()
      let normalizedImagePoint = normalizedViewPoint.applying(imageFromView)
      let result = raycastResult(in: view, at: point)
      let hit = result.flatMap { result -> RaycastHit? in
        let surfaceID =
          result.anchor.map { planeIdentifier($0.identifier) } ?? "arkit_estimated_surface"
        return RaycastHit(
          surfaceID: surfaceID,
          positionWorld: spatialVector(result.worldTransform.columns.3)
        )
      }

      let direction = simd_normalize(ray.direction)
      guard direction.x.isFinite, direction.y.isFinite, direction.z.isFinite else { return false }
      let builder = TargetSeedBuilder(sessionID: parent.spatialSession.sessionID)
      guard
        let seed = try? builder.build(
          frame: targetFrame,
          normalizedImagePoint: ImagePoint(
            x: Double(normalizedImagePoint.x),
            y: Double(normalizedImagePoint.y)
          ),
          rayWorld: SpatialRay(
            origin: spatialVector(ray.origin),
            direction: spatialVector(direction)
          ),
          arkitHit: hit,
          source: source
        )
      else { return false }
      parent.spatialSession.record(seed)
      return true
    }

    private func raycastResult(in view: ARView, at point: CGPoint) -> ARRaycastResult? {
      let exact = view.makeRaycastQuery(
        from: point,
        allowing: .existingPlaneGeometry,
        alignment: .any
      ).flatMap { view.session.raycast($0).first }
      if let exact { return exact }
      let infinite = view.makeRaycastQuery(
        from: point,
        allowing: .existingPlaneInfinite,
        alignment: .horizontal
      ).flatMap { view.session.raycast($0).first }
      if let infinite { return infinite }
      return view.makeRaycastQuery(
        from: point,
        allowing: .estimatedPlane,
        alignment: .any
      ).flatMap { view.session.raycast($0).first }
    }
  }
}

private func spatialVector(_ value: SIMD3<Float>) -> SpatialVector3 {
  SpatialVector3(x: Double(value.x), y: Double(value.y), z: Double(value.z))
}

private func spatialVector(_ value: SIMD4<Float>) -> SpatialVector3 {
  SpatialVector3(x: Double(value.x), y: Double(value.y), z: Double(value.z))
}
