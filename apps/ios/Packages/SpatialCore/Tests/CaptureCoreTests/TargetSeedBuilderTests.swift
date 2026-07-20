import CaptureCore
import SpatialProtocol
import Testing

private let frame = TargetFrame(
  id: 842,
  timestamp: 12.5,
  encodedImageWidth: 640,
  encodedImageHeight: 480
)
private let ray = SpatialRay(
  origin: SpatialVector3(x: 1, y: 1.5, z: -2),
  direction: SpatialVector3(x: 0, y: 0, z: -1)
)

@Test(
  "tap, reticle dwell, and voice capture share one target builder",
  arguments: [
    TargetSeedSource.tap,
    .reticleDwell,
    .voiceCapture,
  ])
func targetRoutesShareBuilder(source: TargetSeedSource) throws {
  let seed = try TargetSeedBuilder(sessionID: "session_room").build(
    frame: frame,
    normalizedImagePoint: ImagePoint(x: 0.25, y: 0.75),
    rayWorld: ray,
    arkitHit: nil,
    source: source
  )

  #expect(seed.frameID == 842)
  #expect(seed.pixelEncoded == ImagePoint(x: 160, y: 360))
  #expect(seed.rayWorld == ray)
  #expect(seed.source == source)
}

@Test("target builder fails closed without a matching frame or image point")
func targetBuilderFailsClosed() {
  let builder = TargetSeedBuilder(sessionID: "session_room")

  #expect(throws: TargetSeedBuildError.frameUnavailable) {
    try builder.build(
      frame: nil,
      normalizedImagePoint: ImagePoint(x: 0.5, y: 0.5),
      rayWorld: ray,
      arkitHit: nil,
      source: .tap
    )
  }
  #expect(throws: TargetSeedBuildError.imagePointOutsideFrame) {
    try builder.build(
      frame: frame,
      normalizedImagePoint: ImagePoint(x: 1.1, y: 0.5),
      rayWorld: ray,
      arkitHit: nil,
      source: .tap
    )
  }
}

@Test("reticle dwell emits once after stability and rearms after meaningful movement")
func reticleDwellStability() {
  var dwell = ReticleDwellTracker(dwellDuration: 0.4, maximumDriftMeters: 0.03)
  let first = SpatialVector3(x: 0, y: 0, z: -2)

  let initial = dwell.observe(timestamp: 1.0, worldPosition: first)
  let early = dwell.observe(timestamp: 1.39, worldPosition: first)
  let emitted = dwell.observe(timestamp: 1.4, worldPosition: first)
  let duplicate = dwell.observe(timestamp: 1.9, worldPosition: first)
  #expect(!initial)
  #expect(!early)
  #expect(emitted)
  #expect(!duplicate)

  let moved = SpatialVector3(x: 0.2, y: 0, z: -2)
  let rearmed = dwell.observe(timestamp: 2.0, worldPosition: moved)
  let secondEmission = dwell.observe(timestamp: 2.4, worldPosition: moved)
  #expect(!rearmed)
  #expect(secondEmission)
}

@Test("reticle dwell resets on tracking loss or excessive drift")
func reticleDwellResets() {
  var dwell = ReticleDwellTracker(dwellDuration: 0.4, maximumDriftMeters: 0.03)
  let initial = dwell.observe(
    timestamp: 1.0,
    worldPosition: .init(x: 0, y: 0, z: -2)
  )
  let trackingLost = dwell.observe(timestamp: 1.2, worldPosition: nil)
  let reacquired = dwell.observe(
    timestamp: 1.5,
    worldPosition: .init(x: 0, y: 0, z: -2)
  )
  let drifted = dwell.observe(
    timestamp: 1.7,
    worldPosition: .init(x: 0.1, y: 0, z: -2)
  )
  let emitted = dwell.observe(
    timestamp: 2.1,
    worldPosition: .init(x: 0.1, y: 0, z: -2)
  )
  #expect(!initial)
  #expect(!trackingLost)
  #expect(!reacquired)
  #expect(!drifted)
  #expect(emitted)
}
