import SpatialProtocol

/// Keeps the aimed object's lateral position while placing a floor-supported
/// replacement at the room's detected floor height.
public func floorProjectedReplacementHit(
  _ aimedHit: RaycastHit,
  floorYWorld: Double
) -> RaycastHit? {
  guard floorYWorld.isFinite else { return nil }
  let position = aimedHit.positionWorld
  guard position.x.isFinite, position.y.isFinite, position.z.isFinite else { return nil }
  return RaycastHit(
    surfaceID: aimedHit.surfaceID,
    positionWorld: SpatialVector3(x: position.x, y: floorYWorld, z: position.z)
  )
}
