import EditCore
import SpatialProtocol
import Testing

private let initialScene = SceneSnapshot(
  sessionID: "session_1",
  sceneRevision: 7,
  objects: [SceneObject(id: "object_chair", assetID: nil, visibility: .visible)],
  reveals: [SceneReveal(id: "reveal_chair", isVisible: false)]
)

private let replacementDelta = EditDelta(
  sceneRevision: 8,
  baseSceneRevision: 7,
  transactionID: "txn_replace",
  idempotencyKey: "idem_replace",
  operations: [
    .setObjectVisibility(objectID: "object_chair", visibility: .hidden),
    .setRevealVisibility(revealID: "reveal_chair", isVisible: true),
    .placeAsset(
      assetID: "asset_chair",
      instanceID: "instance_chair",
      worldFromAsset: .identity
    ),
  ],
  inverseOperations: [
    .removeAssetInstance(instanceID: "instance_chair"),
    .setRevealVisibility(revealID: "reveal_chair", isVisible: false),
    .setObjectVisibility(objectID: "object_chair", visibility: .visible),
  ],
  localUndo: LocalUndoToken(token: "undo_replace", validForCommittedRevision: 8)
)

@Test("preview projects operations without changing the replica revision")
func previewIsRevisionNeutral() throws {
  let replica = SceneReplica(snapshot: initialScene)

  let preview = try replica.preview(
    id: "preview_replace",
    baseSceneRevision: 7,
    operations: replacementDelta.operations
  )

  #expect(replica.scene == initialScene)
  #expect(preview.projectedScene.sceneRevision == 7)
  #expect(preview.projectedScene.objects.first?.visibility == .hidden)
  #expect(preview.projectedScene.assetInstances.map(\.id) == ["instance_chair"])
}

@Test("an authoritative delta applies once and duplicate delivery is idempotent")
func deltaIsIdempotent() throws {
  var replica = SceneReplica(snapshot: initialScene)

  #expect(try replica.apply(replacementDelta) == .applied)
  let committed = replica.scene
  #expect(committed.sceneRevision == 8)
  #expect(try replica.apply(replacementDelta) == .alreadyApplied)
  #expect(replica.scene == committed)
}

@Test("stale, skipped, or conflicting deltas fail without partially changing state")
func staleDeltaFailsClosed() throws {
  var replica = SceneReplica(snapshot: initialScene)
  let stale = EditDelta(
    sceneRevision: 7,
    baseSceneRevision: 6,
    transactionID: "txn_stale",
    idempotencyKey: "idem_stale",
    operations: [],
    inverseOperations: [],
    localUndo: nil
  )

  #expect(throws: SceneReplicaError.staleRevision(expected: 7, received: 6)) {
    try replica.apply(stale)
  }
  #expect(replica.scene == initialScene)

  let skipped = EditDelta(
    sceneRevision: 9,
    baseSceneRevision: 7,
    transactionID: "txn_skipped",
    idempotencyKey: "idem_skipped",
    operations: replacementDelta.operations,
    inverseOperations: replacementDelta.inverseOperations,
    localUndo: nil
  )
  #expect(throws: SceneReplicaError.nonSequentialRevision(base: 7, committed: 9)) {
    try replica.apply(skipped)
  }
  #expect(replica.scene == initialScene)
}

@Test("operation failure leaves the complete replica unchanged")
func operationFailureIsAtomic() throws {
  var replica = SceneReplica(snapshot: initialScene)
  let invalid = EditDelta(
    sceneRevision: 8,
    baseSceneRevision: 7,
    transactionID: "txn_invalid",
    idempotencyKey: "idem_invalid",
    operations: [
      .setObjectVisibility(objectID: "object_chair", visibility: .hidden),
      .setRevealVisibility(revealID: "reveal_missing", isVisible: true),
    ],
    inverseOperations: [],
    localUndo: nil
  )

  #expect(throws: SceneReplicaError.revealNotFound("reveal_missing")) {
    try replica.apply(invalid)
  }
  #expect(replica.scene == initialScene)
}

@Test("a conflicting replay cannot reuse transaction or idempotency identity")
func identityConflictFailsClosed() throws {
  var replica = SceneReplica(snapshot: initialScene)
  _ = try replica.apply(replacementDelta)
  let changed = EditDelta(
    sceneRevision: 8,
    baseSceneRevision: 7,
    transactionID: replacementDelta.transactionID,
    idempotencyKey: replacementDelta.idempotencyKey,
    operations: [],
    inverseOperations: [],
    localUndo: replacementDelta.localUndo
  )

  #expect(throws: SceneReplicaError.idempotencyConflict) {
    try replica.apply(changed)
  }
}

@Test("local inverse is immediate, revision-neutral, and pending synchronization")
func localInverse() throws {
  var replica = SceneReplica(snapshot: initialScene)
  _ = try replica.apply(replacementDelta)

  #expect(try replica.applyLocalInverse(transactionID: "txn_replace") == .applied)
  #expect(replica.scene.sceneRevision == 8)
  #expect(replica.scene.objects.first?.visibility == .visible)
  #expect(replica.scene.reveals.first?.isVisible == false)
  #expect(replica.scene.assetInstances.isEmpty)
  #expect(
    replica.pendingUndo
      == PendingLocalUndo(
        transactionID: "txn_replace",
        token: "undo_replace",
        validForCommittedRevision: 8
      )
  )
  #expect(try replica.applyLocalInverse(transactionID: "txn_replace") == .alreadyApplied)
}

@Test("a newer snapshot replaces state while stale and divergent snapshots are rejected")
func snapshotReconciliation() throws {
  var replica = SceneReplica(snapshot: initialScene)
  #expect(try replica.apply(snapshot: initialScene) == .alreadyCurrent)

  let divergent = SceneSnapshot(
    sessionID: initialScene.sessionID,
    sceneRevision: initialScene.sceneRevision,
    objects: [],
    reveals: []
  )
  #expect(throws: SceneReplicaError.snapshotConflict(revision: 7)) {
    try replica.apply(snapshot: divergent)
  }

  let newer = SceneSnapshot(
    sessionID: initialScene.sessionID,
    sceneRevision: 9,
    objects: [],
    reveals: []
  )
  #expect(try replica.apply(snapshot: newer) == .applied)
  #expect(replica.scene == newer)
  #expect(replica.pendingUndo == nil)

  #expect(throws: SceneReplicaError.staleSnapshot(current: 9, received: 7)) {
    try replica.apply(snapshot: initialScene)
  }
}
