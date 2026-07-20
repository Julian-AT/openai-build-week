import Foundation
import SpatialProtocol

public struct TargetFrame: Equatable, Sendable {
  public let id: UInt64
  public let timestamp: TimeInterval
  public let encodedImageWidth: Int
  public let encodedImageHeight: Int

  public init(
    id: UInt64,
    timestamp: TimeInterval,
    encodedImageWidth: Int,
    encodedImageHeight: Int
  ) {
    precondition(encodedImageWidth > 0 && encodedImageHeight > 0)
    self.id = id
    self.timestamp = timestamp
    self.encodedImageWidth = encodedImageWidth
    self.encodedImageHeight = encodedImageHeight
  }
}

public enum TargetSeedBuildError: Error, Equatable {
  case frameUnavailable
  case imagePointOutsideFrame
  case invalidTargetSeed(TargetSeedValidationError)
}

/// Converts an AR display-space result into the single encoded-image target contract.
public struct TargetSeedBuilder: Sendable {
  public let sessionID: String

  public init(sessionID: String) {
    self.sessionID = sessionID
  }

  public func build(
    frame: TargetFrame?,
    normalizedImagePoint: ImagePoint,
    rayWorld: SpatialRay,
    arkitHit: RaycastHit?,
    source: TargetSeedSource
  ) throws -> TargetSeed {
    guard let frame else { throw TargetSeedBuildError.frameUnavailable }
    guard normalizedImagePoint.x.isFinite,
      normalizedImagePoint.y.isFinite,
      (0...1).contains(normalizedImagePoint.x),
      (0...1).contains(normalizedImagePoint.y)
    else { throw TargetSeedBuildError.imagePointOutsideFrame }

    do {
      return try TargetSeed(
        sessionID: sessionID,
        frameID: frame.id,
        pixelEncoded: ImagePoint(
          x: normalizedImagePoint.x * Double(frame.encodedImageWidth),
          y: normalizedImagePoint.y * Double(frame.encodedImageHeight)
        ),
        rayWorld: rayWorld,
        arkitHit: arkitHit,
        source: source
      )
    } catch let error as TargetSeedValidationError {
      throw TargetSeedBuildError.invalidTargetSeed(error)
    }
  }
}

/// Small value-state machine used by the native reticle sampler.
public struct ReticleDwellTracker: Sendable {
  public let dwellDuration: TimeInterval
  public let maximumDriftMeters: Double

  private var candidatePosition: SpatialVector3?
  private var candidateStart: TimeInterval?
  private var emittedPosition: SpatialVector3?

  public init(dwellDuration: TimeInterval = 0.4, maximumDriftMeters: Double = 0.03) {
    precondition(dwellDuration > 0 && maximumDriftMeters > 0)
    self.dwellDuration = dwellDuration
    self.maximumDriftMeters = maximumDriftMeters
  }

  public mutating func observe(
    timestamp: TimeInterval,
    worldPosition: SpatialVector3?
  ) -> Bool {
    guard let worldPosition else {
      candidatePosition = nil
      candidateStart = nil
      return false
    }

    if let emittedPosition {
      guard distance(from: emittedPosition, to: worldPosition) > maximumDriftMeters else {
        return false
      }
      self.emittedPosition = nil
      candidatePosition = worldPosition
      candidateStart = timestamp
      return false
    }

    guard let candidatePosition, let candidateStart else {
      self.candidatePosition = worldPosition
      self.candidateStart = timestamp
      return false
    }
    guard distance(from: candidatePosition, to: worldPosition) <= maximumDriftMeters else {
      self.candidatePosition = worldPosition
      self.candidateStart = timestamp
      return false
    }
    guard timestamp - candidateStart + 1e-9 >= dwellDuration else { return false }

    emittedPosition = worldPosition
    self.candidatePosition = nil
    self.candidateStart = nil
    return true
  }
}

private func distance(from lhs: SpatialVector3, to rhs: SpatialVector3) -> Double {
  let x = lhs.x - rhs.x
  let y = lhs.y - rhs.y
  let z = lhs.z - rhs.z
  return sqrt(x * x + y * y + z * z)
}
