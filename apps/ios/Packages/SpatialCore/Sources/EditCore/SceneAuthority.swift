import CryptoKit
import Foundation
import SpatialProtocol

public enum SceneAuthorityError: Error, Equatable {
  case revisionConflict
  case idempotencyConflict
  case objectNotFound
  case transactionNotFound
}

public struct SceneAuthority: Sendable {
  public private(set) var scene: SceneState
  public private(set) var transactions: [EditTransaction] = []
  private var committedKeys: [String: (fingerprint: String, transaction: EditTransaction)] = [:]

  public init(sessionID: String, branchID: String) {
    scene = SceneState(sessionID: sessionID, branchID: branchID)
  }

  public func preview(_ proposal: EditProposal) throws -> EditPreview {
    guard proposal.baseRevision == scene.revision else {
      throw SceneAuthorityError.revisionConflict
    }
    let projected = try projectedScene(for: proposal.operation)
    return EditPreview(proposal: proposal, baseRevision: scene.revision, projectedScene: projected)
  }

  public mutating func commit(
    _ preview: EditPreview,
    idempotencyKey: String
  ) throws -> EditTransaction {
    let fingerprint = try proposalFingerprint(preview.proposal)
    if let previous = committedKeys[idempotencyKey] {
      guard previous.fingerprint == fingerprint else {
        throw SceneAuthorityError.idempotencyConflict
      }
      return previous.transaction
    }
    guard preview.baseRevision == scene.revision,
      preview.proposal.baseRevision == scene.revision
    else { throw SceneAuthorityError.revisionConflict }

    let before = scene
    var after = preview.projectedScene
    after.revision = before.revision + 1
    let transaction = EditTransaction(
      id: "transaction-\(UUID().uuidString.lowercased())",
      proposalID: preview.proposal.id,
      baseRevision: before.revision,
      committedRevision: after.revision,
      before: before,
      after: after
    )
    scene = after
    transactions.append(transaction)
    committedKeys[idempotencyKey] = (fingerprint, transaction)
    return transaction
  }

  private func projectedScene(for operation: EditOperation) throws -> SceneState {
    var projected = scene
    switch operation {
    case .place(let assetID, let transform):
      projected.objects.append(
        SceneObject(
          id: "object-\(UUID().uuidString.lowercased())",
          assetID: assetID,
          transform: transform
        )
      )
    case .replace(let objectID, let assetID):
      guard let index = projected.objects.firstIndex(where: { $0.id == objectID }) else {
        throw SceneAuthorityError.objectNotFound
      }
      projected.objects[index].assetID = assetID
    case .remove(let objectID):
      guard let index = projected.objects.firstIndex(where: { $0.id == objectID }) else {
        throw SceneAuthorityError.objectNotFound
      }
      projected.objects.remove(at: index)
    case .restore(let transactionID):
      guard let transaction = transactions.first(where: { $0.id == transactionID }) else {
        throw SceneAuthorityError.transactionNotFound
      }
      projected.objects = transaction.before.objects
    }
    return projected
  }
}

private func proposalFingerprint(_ proposal: EditProposal) throws -> String {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
  let digest = SHA256.hash(data: try encoder.encode(proposal))
  return digest.map { String(format: "%02x", $0) }.joined()
}
