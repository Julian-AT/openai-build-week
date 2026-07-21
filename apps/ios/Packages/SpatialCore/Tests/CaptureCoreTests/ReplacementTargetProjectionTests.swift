import CaptureCore
import SpatialProtocol
import Testing

@Test("projects an aimed object hit onto the detected floor without moving it laterally")
func projectsReplacementHitOntoFloor() throws {
  let aimedHit = RaycastHit(
    surfaceID: "chair_surface",
    positionWorld: SpatialVector3(x: 1.2, y: 0.74, z: -2.1)
  )

  let projected = try #require(
    floorProjectedReplacementHit(aimedHit, floorYWorld: 0.03)
  )

  #expect(projected.surfaceID == "chair_surface")
  #expect(projected.positionWorld == SpatialVector3(x: 1.2, y: 0.03, z: -2.1))
}
