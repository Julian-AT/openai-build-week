import Foundation

public struct SpatialTransform: Codable, Equatable, Sendable {
  public let values: [Double]

  public init(values: [Double]) {
    precondition(values.count == 16)
    self.values = values
  }

  public static let identity = SpatialTransform(values: [
    1, 0, 0, 0,
    0, 1, 0, 0,
    0, 0, 1, 0,
    0, 0, 0, 1,
  ])
}

public struct SceneObject: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public var assetID: String
  public var transform: SpatialTransform

  public init(id: String, assetID: String, transform: SpatialTransform) {
    self.id = id
    self.assetID = assetID
    self.transform = transform
  }
}

public struct SceneState: Codable, Equatable, Sendable {
  public let sessionID: String
  public let branchID: String
  public var revision: Int
  public var objects: [SceneObject]

  public init(sessionID: String, branchID: String, revision: Int = 0, objects: [SceneObject] = []) {
    self.sessionID = sessionID
    self.branchID = branchID
    self.revision = revision
    self.objects = objects
  }
}

public enum EditOperation: Codable, Equatable, Sendable {
  case place(assetID: String, transform: SpatialTransform)
  case replace(objectID: String, assetID: String)
  case remove(objectID: String)
  case restore(transactionID: String)
}

public struct EditProposal: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let baseRevision: Int
  public let operation: EditOperation

  public init(id: String, baseRevision: Int, operation: EditOperation) {
    self.id = id
    self.baseRevision = baseRevision
    self.operation = operation
  }
}

public struct EditPreview: Codable, Equatable, Identifiable, Sendable {
  public var id: String { proposal.id }
  public let proposal: EditProposal
  public let baseRevision: Int
  public let projectedScene: SceneState

  public init(proposal: EditProposal, baseRevision: Int, projectedScene: SceneState) {
    self.proposal = proposal
    self.baseRevision = baseRevision
    self.projectedScene = projectedScene
  }
}

public struct EditTransaction: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let proposalID: String
  public let baseRevision: Int
  public let committedRevision: Int
  public let before: SceneState
  public let after: SceneState

  public init(
    id: String,
    proposalID: String,
    baseRevision: Int,
    committedRevision: Int,
    before: SceneState,
    after: SceneState
  ) {
    self.id = id
    self.proposalID = proposalID
    self.baseRevision = baseRevision
    self.committedRevision = committedRevision
    self.before = before
    self.after = after
  }
}
