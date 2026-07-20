import Foundation

public struct ImagePoint: Codable, Equatable, Sendable {
  public let x: Double
  public let y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }

  public init(from decoder: Decoder) throws {
    var values = try decoder.unkeyedContainer()
    x = try values.decode(Double.self)
    y = try values.decode(Double.self)
    guard values.isAtEnd else {
      throw DecodingError.dataCorruptedError(in: values, debugDescription: "Expected [x, y]")
    }
  }

  public func encode(to encoder: Encoder) throws {
    var values = encoder.unkeyedContainer()
    try values.encode(x)
    try values.encode(y)
  }
}

public struct SpatialVector3: Codable, Equatable, Sendable {
  public let x: Double
  public let y: Double
  public let z: Double

  public init(x: Double, y: Double, z: Double) {
    self.x = x
    self.y = y
    self.z = z
  }

  public init(from decoder: Decoder) throws {
    var values = try decoder.unkeyedContainer()
    x = try values.decode(Double.self)
    y = try values.decode(Double.self)
    z = try values.decode(Double.self)
    guard values.isAtEnd else {
      throw DecodingError.dataCorruptedError(in: values, debugDescription: "Expected [x, y, z]")
    }
  }

  public func encode(to encoder: Encoder) throws {
    var values = encoder.unkeyedContainer()
    try values.encode(x)
    try values.encode(y)
    try values.encode(z)
  }
}

public struct SpatialRay: Codable, Equatable, Sendable {
  public let origin: SpatialVector3
  public let direction: SpatialVector3

  public init(origin: SpatialVector3, direction: SpatialVector3) {
    self.origin = origin
    self.direction = direction
  }
}

public struct RaycastHit: Codable, Equatable, Sendable {
  public let surfaceID: String
  public let positionWorld: SpatialVector3

  public init(surfaceID: String, positionWorld: SpatialVector3) {
    self.surfaceID = surfaceID
    self.positionWorld = positionWorld
  }

  private enum CodingKeys: String, CodingKey {
    case surfaceID = "surface_id"
    case positionWorld = "position_world"
  }
}

public enum TargetSeedSource: String, Codable, CaseIterable, Sendable {
  case reticleDwell = "reticle_dwell"
  case tap
  case voiceCapture = "voice_capture"
  case debugWeb = "debug_web"
}

public enum TargetSeedValidationError: Error, Equatable {
  case emptySessionID
  case nonFiniteComponent
  case directionMustBeNormalized
  case emptySurfaceID
}

/// ARKit-independent pointer context shared by reticle dwell, tap, and voice capture.
public struct TargetSeed: Codable, Equatable, Sendable {
  public let sessionID: String
  public let frameID: UInt64
  public let pixelEncoded: ImagePoint
  public let rayWorld: SpatialRay
  public let arkitHit: RaycastHit?
  public let source: TargetSeedSource

  public init(
    sessionID: String,
    frameID: UInt64,
    pixelEncoded: ImagePoint,
    rayWorld: SpatialRay,
    arkitHit: RaycastHit?,
    source: TargetSeedSource
  ) throws {
    guard !sessionID.isEmpty else { throw TargetSeedValidationError.emptySessionID }
    let components = [
      pixelEncoded.x, pixelEncoded.y,
      rayWorld.origin.x, rayWorld.origin.y, rayWorld.origin.z,
      rayWorld.direction.x, rayWorld.direction.y, rayWorld.direction.z,
      arkitHit?.positionWorld.x, arkitHit?.positionWorld.y, arkitHit?.positionWorld.z,
    ].compactMap { $0 }
    guard components.allSatisfy(\.isFinite) else {
      throw TargetSeedValidationError.nonFiniteComponent
    }
    let directionLength = sqrt(
      rayWorld.direction.x * rayWorld.direction.x
        + rayWorld.direction.y * rayWorld.direction.y
        + rayWorld.direction.z * rayWorld.direction.z
    )
    guard abs(directionLength - 1) <= 0.001 else {
      throw TargetSeedValidationError.directionMustBeNormalized
    }
    if let arkitHit, arkitHit.surfaceID.isEmpty {
      throw TargetSeedValidationError.emptySurfaceID
    }
    self.sessionID = sessionID
    self.frameID = frameID
    self.pixelEncoded = pixelEncoded
    self.rayWorld = rayWorld
    self.arkitHit = arkitHit
    self.source = source
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      sessionID: values.decode(String.self, forKey: .sessionID),
      frameID: values.decode(UInt64.self, forKey: .frameID),
      pixelEncoded: values.decode(ImagePoint.self, forKey: .pixelEncoded),
      rayWorld: values.decode(SpatialRay.self, forKey: .rayWorld),
      arkitHit: values.decodeIfPresent(RaycastHit.self, forKey: .arkitHit),
      source: values.decode(TargetSeedSource.self, forKey: .source)
    )
  }

  private enum CodingKeys: String, CodingKey {
    case sessionID = "session_id"
    case frameID = "frame_id"
    case pixelEncoded = "pixel_encoded"
    case rayWorld = "ray_world"
    case arkitHit = "arkit_hit"
    case source
  }
}
