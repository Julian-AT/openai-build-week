import SpatialProtocol

public enum SceneReplicaError: Error, Equatable {
  case sessionMismatch(expected: String, received: String)
  case staleRevision(expected: Int, received: Int)
  case nonSequentialRevision(base: Int, committed: Int)
  case idempotencyConflict
  case staleSnapshot(current: Int, received: Int)
  case snapshotConflict(revision: Int)
  case objectNotFound(String)
  case revealNotFound(String)
  case assetInstanceNotFound(String)
  case duplicateAssetInstance(String)
  case transactionNotFound(String)
  case localUndoUnavailable(String)
  case localUndoRevisionConflict(expected: Int, current: Int)
}

public enum ReplicaApplyResult: Equatable, Sendable {
  case applied
  case alreadyApplied
  case alreadyCurrent
}

public struct PendingLocalUndo: Equatable, Sendable {
  public let transactionID: String
  public let token: String
  public let validForCommittedRevision: Int

  public init(transactionID: String, token: String, validForCommittedRevision: Int) {
    self.transactionID = transactionID
    self.token = token
    self.validForCommittedRevision = validForCommittedRevision
  }
}

/// A deterministic local replica. Only gateway snapshots and deltas advance its canonical revision.
public struct SceneReplica: Sendable {
  public private(set) var scene: SceneSnapshot
  public private(set) var pendingUndo: PendingLocalUndo?

  private var deltasByTransactionID: [String: EditDelta] = [:]
  private var transactionIDByIdempotencyKey: [String: String] = [:]

  public init(snapshot: SceneSnapshot) {
    scene = snapshot
  }

  public func preview(
    id: String,
    baseSceneRevision: Int,
    operations: [SceneOperation]
  ) throws -> EditPreview {
    guard baseSceneRevision == scene.sceneRevision else {
      throw SceneReplicaError.staleRevision(
        expected: scene.sceneRevision,
        received: baseSceneRevision
      )
    }
    let projected = try reducing(operations, into: scene)
    return EditPreview(
      id: id,
      baseSceneRevision: baseSceneRevision,
      operations: operations,
      projectedScene: projected
    )
  }

  public mutating func apply(_ delta: EditDelta) throws -> ReplicaApplyResult {
    if let previous = deltasByTransactionID[delta.transactionID] {
      guard previous == delta else { throw SceneReplicaError.idempotencyConflict }
      return .alreadyApplied
    }
    if transactionIDByIdempotencyKey[delta.idempotencyKey] != nil {
      throw SceneReplicaError.idempotencyConflict
    }
    guard delta.baseSceneRevision == scene.sceneRevision else {
      throw SceneReplicaError.staleRevision(
        expected: scene.sceneRevision,
        received: delta.baseSceneRevision
      )
    }
    guard delta.sceneRevision == delta.baseSceneRevision + 1 else {
      throw SceneReplicaError.nonSequentialRevision(
        base: delta.baseSceneRevision,
        committed: delta.sceneRevision
      )
    }

    var next = try reducing(delta.operations, into: scene)
    next.sceneRevision = delta.sceneRevision
    scene = next
    deltasByTransactionID[delta.transactionID] = delta
    transactionIDByIdempotencyKey[delta.idempotencyKey] = delta.transactionID
    pendingUndo = nil
    return .applied
  }

  public mutating func apply(snapshot: SceneSnapshot) throws -> ReplicaApplyResult {
    guard snapshot.sessionID == scene.sessionID else {
      throw SceneReplicaError.sessionMismatch(
        expected: scene.sessionID,
        received: snapshot.sessionID
      )
    }
    guard snapshot.sceneRevision >= scene.sceneRevision else {
      throw SceneReplicaError.staleSnapshot(
        current: scene.sceneRevision,
        received: snapshot.sceneRevision
      )
    }
    if snapshot.sceneRevision == scene.sceneRevision {
      guard snapshot == scene else {
        throw SceneReplicaError.snapshotConflict(revision: snapshot.sceneRevision)
      }
      return .alreadyCurrent
    }
    scene = snapshot
    pendingUndo = nil
    return .applied
  }

  public mutating func applyLocalInverse(transactionID: String) throws -> ReplicaApplyResult {
    if pendingUndo?.transactionID == transactionID { return .alreadyApplied }
    guard let delta = deltasByTransactionID[transactionID] else {
      throw SceneReplicaError.transactionNotFound(transactionID)
    }
    guard let undo = delta.localUndo else {
      throw SceneReplicaError.localUndoUnavailable(transactionID)
    }
    guard undo.validForCommittedRevision == scene.sceneRevision else {
      throw SceneReplicaError.localUndoRevisionConflict(
        expected: undo.validForCommittedRevision,
        current: scene.sceneRevision
      )
    }

    scene = try reducing(delta.inverseOperations, into: scene)
    pendingUndo = PendingLocalUndo(
      transactionID: transactionID,
      token: undo.token,
      validForCommittedRevision: undo.validForCommittedRevision
    )
    return .applied
  }
}

private func reducing(
  _ operations: [SceneOperation],
  into snapshot: SceneSnapshot
) throws -> SceneSnapshot {
  var result = snapshot
  for operation in operations {
    switch operation {
    case .setObjectVisibility(let objectID, let visibility):
      guard let index = result.objects.firstIndex(where: { $0.id == objectID }) else {
        throw SceneReplicaError.objectNotFound(objectID)
      }
      result.objects[index].visibility = visibility
    case .setRevealVisibility(let revealID, let isVisible):
      guard let index = result.reveals.firstIndex(where: { $0.id == revealID }) else {
        throw SceneReplicaError.revealNotFound(revealID)
      }
      result.reveals[index].isVisible = isVisible
    case .placeAsset(let assetID, let instanceID, let transform):
      guard !result.assetInstances.contains(where: { $0.id == instanceID }) else {
        throw SceneReplicaError.duplicateAssetInstance(instanceID)
      }
      result.assetInstances.append(
        AssetInstance(id: instanceID, assetID: assetID, worldFromAsset: transform)
      )
    case .removeAssetInstance(let instanceID):
      guard let index = result.assetInstances.firstIndex(where: { $0.id == instanceID }) else {
        throw SceneReplicaError.assetInstanceNotFound(instanceID)
      }
      result.assetInstances.remove(at: index)
    }
  }
  return result
}
