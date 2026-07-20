import CaptureCore
import SpatialProtocol
import Testing

@Test("plane observations remain monotonic across delayed upserts and removals")
func planeObservationOrdering() {
  var store = ObservedPlaneStore()
  let revisionOne = plane(revision: 1)
  let revisionTwo = plane(revision: 2)

  let inserted = store.upsert(revisionOne)
  let updated = store.upsert(revisionTwo)
  let delayedUpsert = store.upsert(revisionOne)
  #expect(inserted)
  #expect(updated)
  #expect(!delayedUpsert)
  #expect(store.planes[revisionOne.id]?.revision == 2)

  let removed = store.remove(id: revisionOne.id, revision: 3)
  #expect(removed)
  #expect(store.planes.isEmpty)
  let delayedAfterRemoval = store.upsert(revisionTwo)
  let delayedRemoval = store.remove(id: revisionOne.id, revision: 2)
  #expect(!delayedAfterRemoval)
  #expect(!delayedRemoval)
}

private func plane(revision: Int) -> ObservedPlane {
  ObservedPlane(
    id: "arkit_plane_1",
    revision: revision,
    classification: .floor,
    worldFromPlane: .identity,
    extent: PlaneExtent(widthMeters: 2, heightMeters: 3),
    boundaryVerticesLocalXZ: []
  )
}
