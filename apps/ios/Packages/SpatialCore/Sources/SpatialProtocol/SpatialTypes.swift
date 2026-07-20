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

  public init(from decoder: Decoder) throws {
    var container = try decoder.unkeyedContainer()
    var decoded: [Double] = []
    while !container.isAtEnd {
      decoded.append(try container.decode(Double.self))
    }
    guard decoded.count == 16 else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "A spatial transform requires 16 row-major values"
      )
    }
    values = decoded
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.unkeyedContainer()
    for value in values { try container.encode(value) }
  }
}

public enum SceneObjectVisibility: String, Codable, Equatable, Sendable {
  case visible
  case hidden
}

public struct SceneObject: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public var assetID: String?
  public var visibility: SceneObjectVisibility

  public init(
    id: String,
    assetID: String?,
    visibility: SceneObjectVisibility
  ) {
    self.id = id
    self.assetID = assetID
    self.visibility = visibility
  }
}

public struct SceneReveal: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public var isVisible: Bool

  public init(id: String, isVisible: Bool) {
    self.id = id
    self.isVisible = isVisible
  }
}

public struct AssetInstance: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let assetID: String
  public var worldFromAsset: SpatialTransform

  public init(id: String, assetID: String, worldFromAsset: SpatialTransform) {
    self.id = id
    self.assetID = assetID
    self.worldFromAsset = worldFromAsset
  }
}

/// The last complete canonical scene received from the gateway plus locally activated render state.
public struct SceneSnapshot: Codable, Equatable, Sendable {
  public let sessionID: String
  public var sceneRevision: Int
  public var objects: [SceneObject]
  public var reveals: [SceneReveal]
  public var assetInstances: [AssetInstance]

  public init(
    sessionID: String,
    sceneRevision: Int,
    objects: [SceneObject] = [],
    reveals: [SceneReveal] = [],
    assetInstances: [AssetInstance] = []
  ) {
    precondition(sceneRevision >= 0)
    self.sessionID = sessionID
    self.sceneRevision = sceneRevision
    self.objects = objects
    self.reveals = reveals
    self.assetInstances = assetInstances
  }
}

public enum SceneOperation: Codable, Equatable, Sendable {
  case setObjectVisibility(objectID: String, visibility: SceneObjectVisibility)
  case setRevealVisibility(revealID: String, isVisible: Bool)
  case placeAsset(assetID: String, instanceID: String, worldFromAsset: SpatialTransform)
  case removeAssetInstance(instanceID: String)

  private enum OperationName: String, Codable {
    case setObjectVisibility = "set_object_visibility"
    case setRevealVisibility = "set_reveal_visibility"
    case placeAsset = "place_asset"
    case removeAssetInstance = "remove_asset_instance"
  }

  private enum CodingKeys: String, CodingKey {
    case operation = "op"
    case objectID = "object_id"
    case value
    case revealID = "reveal_bundle_id"
    case assetID = "asset_id"
    case instanceID = "instance_id"
    case worldFromAsset = "world_from_asset"
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    switch try values.decode(OperationName.self, forKey: .operation) {
    case .setObjectVisibility:
      self = .setObjectVisibility(
        objectID: try values.decode(String.self, forKey: .objectID),
        visibility: try values.decode(SceneObjectVisibility.self, forKey: .value)
      )
    case .setRevealVisibility:
      self = .setRevealVisibility(
        revealID: try values.decode(String.self, forKey: .revealID),
        isVisible: try values.decode(Bool.self, forKey: .value)
      )
    case .placeAsset:
      self = .placeAsset(
        assetID: try values.decode(String.self, forKey: .assetID),
        instanceID: try values.decode(String.self, forKey: .instanceID),
        worldFromAsset: try values.decode(SpatialTransform.self, forKey: .worldFromAsset)
      )
    case .removeAssetInstance:
      self = .removeAssetInstance(
        instanceID: try values.decode(String.self, forKey: .instanceID)
      )
    }
  }

  public func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .setObjectVisibility(let objectID, let visibility):
      try values.encode(OperationName.setObjectVisibility, forKey: .operation)
      try values.encode(objectID, forKey: .objectID)
      try values.encode(visibility, forKey: .value)
    case .setRevealVisibility(let revealID, let isVisible):
      try values.encode(OperationName.setRevealVisibility, forKey: .operation)
      try values.encode(revealID, forKey: .revealID)
      try values.encode(isVisible, forKey: .value)
    case .placeAsset(let assetID, let instanceID, let worldFromAsset):
      try values.encode(OperationName.placeAsset, forKey: .operation)
      try values.encode(assetID, forKey: .assetID)
      try values.encode(instanceID, forKey: .instanceID)
      try values.encode(worldFromAsset, forKey: .worldFromAsset)
    case .removeAssetInstance(let instanceID):
      try values.encode(OperationName.removeAssetInstance, forKey: .operation)
      try values.encode(instanceID, forKey: .instanceID)
    }
  }
}

public struct LocalUndoToken: Codable, Equatable, Sendable {
  public let token: String
  public let validForCommittedRevision: Int

  public init(token: String, validForCommittedRevision: Int) {
    self.token = token
    self.validForCommittedRevision = validForCommittedRevision
  }

  private enum CodingKeys: String, CodingKey {
    case token
    case validForCommittedRevision = "valid_for_committed_revision"
  }
}

/// A committed, authoritative gateway event. The client may only reduce this into its replica.
public struct EditDelta: Codable, Equatable, Sendable {
  public let sceneRevision: Int
  public let baseSceneRevision: Int
  public let transactionID: String
  public let idempotencyKey: String
  public let operations: [SceneOperation]
  public let inverseOperations: [SceneOperation]
  public let localUndo: LocalUndoToken?

  public init(
    sceneRevision: Int,
    baseSceneRevision: Int,
    transactionID: String,
    idempotencyKey: String,
    operations: [SceneOperation],
    inverseOperations: [SceneOperation],
    localUndo: LocalUndoToken?
  ) {
    self.sceneRevision = sceneRevision
    self.baseSceneRevision = baseSceneRevision
    self.transactionID = transactionID
    self.idempotencyKey = idempotencyKey
    self.operations = operations
    self.inverseOperations = inverseOperations
    self.localUndo = localUndo
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    let type = try values.decode(String.self, forKey: .type)
    guard type == Self.eventType else {
      throw DecodingError.dataCorruptedError(
        forKey: .type,
        in: values,
        debugDescription: "Expected \(Self.eventType)"
      )
    }
    sceneRevision = try values.decode(Int.self, forKey: .sceneRevision)
    baseSceneRevision = try values.decode(Int.self, forKey: .baseSceneRevision)
    transactionID = try values.decode(String.self, forKey: .transactionID)
    idempotencyKey = try values.decode(String.self, forKey: .idempotencyKey)
    operations = try values.decode([SceneOperation].self, forKey: .operations)
    inverseOperations = try values.decode([SceneOperation].self, forKey: .inverseOperations)
    localUndo = try values.decodeIfPresent(LocalUndoToken.self, forKey: .localUndo)
  }

  public func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(Self.eventType, forKey: .type)
    try values.encode(sceneRevision, forKey: .sceneRevision)
    try values.encode(baseSceneRevision, forKey: .baseSceneRevision)
    try values.encode(transactionID, forKey: .transactionID)
    try values.encode(idempotencyKey, forKey: .idempotencyKey)
    try values.encode(operations, forKey: .operations)
    try values.encode(inverseOperations, forKey: .inverseOperations)
    try values.encodeIfPresent(localUndo, forKey: .localUndo)
  }

  private static let eventType = "edit_delta"

  private enum CodingKeys: String, CodingKey {
    case type
    case sceneRevision = "scene_revision"
    case baseSceneRevision = "base_scene_revision"
    case transactionID = "transaction_id"
    case idempotencyKey = "idempotency_key"
    case operations = "ops"
    case inverseOperations = "inverse_ops"
    case localUndo = "local_undo"
  }
}

public struct EditPreview: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let baseSceneRevision: Int
  public let operations: [SceneOperation]
  public let projectedScene: SceneSnapshot

  public init(
    id: String,
    baseSceneRevision: Int,
    operations: [SceneOperation],
    projectedScene: SceneSnapshot
  ) {
    self.id = id
    self.baseSceneRevision = baseSceneRevision
    self.operations = operations
    self.projectedScene = projectedScene
  }
}
