import Foundation
import SpatialProtocol
import Testing

@Test(
  "all native target routes share the same snake-case wire contract",
  arguments: [
    TargetSeedSource.reticleDwell,
    .tap,
    .voiceCapture,
  ])
func targetSeedWireContract(source: TargetSeedSource) throws {
  let seed = try TargetSeed(
    sessionID: "session_1",
    frameID: 842,
    pixelEncoded: ImagePoint(x: 318, y: 251),
    rayWorld: SpatialRay(
      origin: SpatialVector3(x: 1.42, y: 1.53, z: -2.18),
      direction: SpatialVector3(x: 0, y: 0, z: -1)
    ),
    arkitHit: RaycastHit(
      surfaceID: "arkit_plane_07",
      positionWorld: SpatialVector3(x: 1.66, y: 0.01, z: -4.31)
    ),
    source: source
  )

  let data = try JSONEncoder().encode(seed)
  let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  #expect(object["session_id"] as? String == "session_1")
  #expect(object["frame_id"] as? Int == 842)
  #expect(object["pixel_encoded"] as? [Double] == [318, 251])
  #expect(object["source"] as? String == source.rawValue)
  #expect(try JSONDecoder().decode(TargetSeed.self, from: data) == seed)
}

@Test("target seed rejects a non-unit or non-finite world ray")
func targetSeedRejectsInvalidRay() {
  #expect(throws: TargetSeedValidationError.directionMustBeNormalized) {
    try TargetSeed(
      sessionID: "session_1",
      frameID: 1,
      pixelEncoded: ImagePoint(x: 1, y: 1),
      rayWorld: SpatialRay(
        origin: SpatialVector3(x: 0, y: 0, z: 0),
        direction: SpatialVector3(x: 0, y: 0, z: -2)
      ),
      arkitHit: nil,
      source: .tap
    )
  }

  #expect(throws: TargetSeedValidationError.nonFiniteComponent) {
    try TargetSeed(
      sessionID: "session_1",
      frameID: 1,
      pixelEncoded: ImagePoint(x: .infinity, y: 1),
      rayWorld: SpatialRay(
        origin: SpatialVector3(x: 0, y: 0, z: 0),
        direction: SpatialVector3(x: 0, y: 0, z: -1)
      ),
      arkitHit: nil,
      source: .tap
    )
  }
}

@Test("edit delta uses the normative operation wire shape")
func editDeltaWireContract() throws {
  let delta = EditDelta(
    sceneRevision: 8,
    baseSceneRevision: 7,
    transactionID: "txn_replace",
    idempotencyKey: "idem_replace",
    operations: [
      .setObjectVisibility(objectID: "object_chair", visibility: .hidden),
      .setRevealVisibility(revealID: "reveal_chair", isVisible: true),
      .placeAsset(assetID: "asset_chair", instanceID: "instance_chair", worldFromAsset: .identity),
    ],
    inverseOperations: [.removeAssetInstance(instanceID: "instance_chair")],
    localUndo: LocalUndoToken(token: "undo_replace", validForCommittedRevision: 8)
  )

  let data = try JSONEncoder().encode(delta)
  let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  #expect(object["type"] as? String == "edit_delta")
  #expect(object["scene_revision"] as? Int == 8)
  #expect(object["base_scene_revision"] as? Int == 7)
  let operations = try #require(object["ops"] as? [[String: Any]])
  #expect(operations[0]["op"] as? String == "set_object_visibility")
  #expect(operations[0]["object_id"] as? String == "object_chair")
  #expect(operations[1]["reveal_bundle_id"] as? String == "reveal_chair")
  #expect(operations[2]["world_from_asset"] as? [Double] == SpatialTransform.identity.values)
  #expect(try JSONDecoder().decode(EditDelta.self, from: data) == delta)
}
