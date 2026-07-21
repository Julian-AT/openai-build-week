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
    context.coordinator.consumeCommittedAssets()
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
    private weak var showcaseRemovalOverlay: UIImageView?
    private let showcaseImageContext = CIContext(options: [.cacheIntermediates: false])
    private var committedAnchors: [String: AnchorEntity] = [:]
    private var committedKeys: [String: String] = [:]
    private var committedLoadTasks: [String: Task<Void, Never>] = [:]

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
      showcaseRemovalOverlay?.removeFromSuperview()
      for task in committedLoadTasks.values { task.cancel() }
      committedLoadTasks.removeAll()
      for anchor in committedAnchors.values { anchor.removeFromParent() }
      committedAnchors.removeAll()
      committedKeys.removeAll()
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
      let anchor = AnchorEntity(world: worldMatrix(transform))
      view.scene.addAnchor(anchor)
      placementPreviewAnchor = anchor
      placementPreviewKey = key
      showShowcaseRemovalFrame(in: view, key: key)

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
          entity.name = "reframe-placement-\(assetID)"
          anchor.addChild(entity)
          try await Task.sleep(for: .milliseconds(450))
          self.hideShowcaseRemovalFrame(key: key)
          spatialSession.placementAssetDidLoad()
        } catch {
          // The preview remains empty rather than displaying an unverified or
          // dimensionally misleading stand-in. Surface the failure so the
          // operator can retry instead of mistaking it for tracking loss.
          guard !Task.isCancelled else { return }
          self?.hideShowcaseRemovalFrame(key: key)
          spatialSession.placementAssetDidFail(error)
        }
      }
    }

    func consumeCommittedAssets() {
      guard let view else { return }
      let instances = parent.spatialSession.committedAssetInstances
      let desiredIDs = Set(instances.map(\.id))
      for instanceID in Array(committedAnchors.keys) where !desiredIDs.contains(instanceID) {
        committedLoadTasks.removeValue(forKey: instanceID)?.cancel()
        committedAnchors.removeValue(forKey: instanceID)?.removeFromParent()
        committedKeys.removeValue(forKey: instanceID)
      }
      for instance in instances {
        let transformKey = instance.worldFromAsset.values.map { String($0) }.joined(separator: ",")
        let key = "\(instance.assetID):\(transformKey)"
        guard committedKeys[instance.id] != key else { continue }
        committedLoadTasks.removeValue(forKey: instance.id)?.cancel()
        committedAnchors.removeValue(forKey: instance.id)?.removeFromParent()
        let anchor = AnchorEntity(world: worldMatrix(instance.worldFromAsset))
        view.scene.addAnchor(anchor)
        committedAnchors[instance.id] = anchor
        committedKeys[instance.id] = key
        let spatialSession = parent.spatialSession
        committedLoadTasks[instance.id] = Task { @MainActor [weak self, weak anchor] in
          defer { self?.committedLoadTasks.removeValue(forKey: instance.id) }
          do {
            let delivery = try await spatialSession.verifiedUSDZFile(for: instance.assetID)
            let entity = try await RealityKitAssetLoader.loadUSDZ(
              from: delivery.url,
              delivery: delivery.descriptor
            )
            guard let self, !Task.isCancelled, self.committedKeys[instance.id] == key,
              let anchor
            else { return }
            entity.name = "reframe-committed-\(instance.id)"
            anchor.addChild(entity)
          } catch {
            guard !Task.isCancelled else { return }
            spatialSession.placementAssetDidFail(error)
          }
        }
      }
    }

    private func worldMatrix(_ transform: SpatialTransform) -> simd_float4x4 {
      simd_float4x4(rows: [
        SIMD4<Float>(
          Float(transform.values[0]), Float(transform.values[1]),
          Float(transform.values[2]), Float(transform.values[3])
        ),
        SIMD4<Float>(
          Float(transform.values[4]), Float(transform.values[5]),
          Float(transform.values[6]), Float(transform.values[7])
        ),
        SIMD4<Float>(
          Float(transform.values[8]), Float(transform.values[9]),
          Float(transform.values[10]), Float(transform.values[11])
        ),
        SIMD4<Float>(
          Float(transform.values[12]), Float(transform.values[13]),
          Float(transform.values[14]), Float(transform.values[15])
        ),
      ])
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
        let aimedHit = RaycastHit(
          surfaceID: surfaceID,
          positionWorld: spatialVector(result.worldTransform.columns.3)
        )
        guard let floorYWorld = floorYWorld(in: frame) else { return aimedHit }
        return floorProjectedReplacementHit(aimedHit, floorYWorld: floorYWorld)
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

    private func floorYWorld(in frame: ARFrame) -> Double? {
      let horizontalPlanes = frame.anchors.compactMap { $0 as? ARPlaneAnchor }.filter {
        $0.alignment == .horizontal
      }
      let classifiedFloors = horizontalPlanes.filter { $0.classification == .floor }
      let candidates = classifiedFloors.isEmpty ? horizontalPlanes : classifiedFloors
      return candidates.map { Double($0.transform.columns.3.y) }.min()
    }

    private func showShowcaseRemovalFrame(in view: ARView, key: String) {
      showcaseRemovalOverlay?.removeFromSuperview()
      view.snapshot(saveToHDR: false) { [weak self, weak view] image in
        guard let self, let view, self.placementPreviewKey == key, let image else { return }
        let overlay = UIImageView(frame: view.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.contentMode = .scaleAspectFill
        overlay.clipsToBounds = true
        overlay.image = self.showcaseDissolveFrame(from: image)
        overlay.isUserInteractionEnabled = false
        view.addSubview(overlay)
        self.showcaseRemovalOverlay = overlay
      }
    }

    private func hideShowcaseRemovalFrame(key: String) {
      guard placementPreviewKey == key, let overlay = showcaseRemovalOverlay else { return }
      UIView.animate(
        withDuration: 0.3,
        animations: { overlay.alpha = 0 },
        completion: { _ in overlay.removeFromSuperview() }
      )
    }

    private func showcaseDissolveFrame(from image: UIImage) -> UIImage {
      let size = image.size
      let target = CGRect(
        x: size.width * 0.16,
        y: size.height * 0.18,
        width: size.width * 0.68,
        height: size.height * 0.7
      )
      guard
        let left = showcaseCrop(
          image,
          rect: CGRect(
            x: size.width * 0.02,
            y: target.minY,
            width: size.width * 0.16,
            height: target.height
          )
        ),
        let right = showcaseCrop(
          image,
          rect: CGRect(
            x: size.width * 0.82,
            y: target.minY,
            width: size.width * 0.16,
            height: target.height
          )
        )
      else { return image }

      let patchLayer = UIGraphicsImageRenderer(size: size).image { _ in
        UIBezierPath(roundedRect: target, cornerRadius: size.width * 0.06).addClip()
        left.draw(
          in: CGRect(x: target.minX, y: target.minY, width: target.width / 2, height: target.height)
        )
        right.draw(
          in: CGRect(x: target.midX, y: target.minY, width: target.width / 2, height: target.height)
        )
      }
      guard let original = CIImage(image: image), let patch = CIImage(image: patchLayer) else {
        return image
      }
      let softened = patch.applyingFilter(
        "CIGaussianBlur",
        parameters: [kCIInputRadiusKey: max(10, size.width * 0.025)]
      ).cropped(to: original.extent)
      let composite = softened.composited(over: original)
      guard let output = showcaseImageContext.createCGImage(composite, from: original.extent) else {
        return image
      }
      return UIImage(cgImage: output, scale: image.scale, orientation: .up)
    }

    private func showcaseCrop(_ image: UIImage, rect: CGRect) -> UIImage? {
      let scale = image.scale
      let pixels = CGRect(
        x: rect.minX * scale,
        y: rect.minY * scale,
        width: rect.width * scale,
        height: rect.height * scale
      ).integral
      guard let crop = image.cgImage?.cropping(to: pixels) else { return nil }
      return UIImage(cgImage: crop, scale: scale, orientation: image.imageOrientation)
    }
  }
}

private func spatialVector(_ value: SIMD3<Float>) -> SpatialVector3 {
  SpatialVector3(x: Double(value.x), y: Double(value.y), z: Double(value.z))
}

private func spatialVector(_ value: SIMD4<Float>) -> SpatialVector3 {
  SpatialVector3(x: Double(value.x), y: Double(value.y), z: Double(value.z))
}
