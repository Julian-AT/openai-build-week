import Foundation
import SpatialProtocol

public struct SpatialLightEstimate: Equatable, Sendable {
  public let ambientIntensityLumens: Double
  public let ambientColorTemperatureKelvin: Double

  public init(ambientIntensityLumens: Double, ambientColorTemperatureKelvin: Double) {
    self.ambientIntensityLumens = ambientIntensityLumens
    self.ambientColorTemperatureKelvin = ambientColorTemperatureKelvin
  }
}

public struct CameraFrameObservation: Equatable, Sendable {
  public let targetFrame: TargetFrame
  public let worldFromCameraARKit: SpatialTransform
  public let lightEstimate: SpatialLightEstimate?

  public init(
    targetFrame: TargetFrame,
    worldFromCameraARKit: SpatialTransform,
    lightEstimate: SpatialLightEstimate?
  ) {
    self.targetFrame = targetFrame
    self.worldFromCameraARKit = worldFromCameraARKit
    self.lightEstimate = lightEstimate
  }
}

public enum ObservedPlaneClassification: String, Equatable, Sendable {
  case floor
  case wall
  case ceiling
  case table
  case seat
  case door
  case window
  case unknown
}

public struct PlaneExtent: Equatable, Sendable {
  public let widthMeters: Double
  public let heightMeters: Double

  public init(widthMeters: Double, heightMeters: Double) {
    self.widthMeters = widthMeters
    self.heightMeters = heightMeters
  }
}

public struct PlaneBoundaryPoint: Equatable, Sendable {
  public let xMeters: Double
  public let zMeters: Double

  public init(xMeters: Double, zMeters: Double) {
    self.xMeters = xMeters
    self.zMeters = zMeters
  }
}

public struct ObservedPlane: Equatable, Identifiable, Sendable {
  public let id: String
  public let revision: Int
  public let classification: ObservedPlaneClassification
  public let worldFromPlane: SpatialTransform
  public let extent: PlaneExtent
  public let boundaryVerticesLocalXZ: [PlaneBoundaryPoint]

  public init(
    id: String,
    revision: Int,
    classification: ObservedPlaneClassification,
    worldFromPlane: SpatialTransform,
    extent: PlaneExtent,
    boundaryVerticesLocalXZ: [PlaneBoundaryPoint]
  ) {
    precondition(revision > 0)
    self.id = id
    self.revision = revision
    self.classification = classification
    self.worldFromPlane = worldFromPlane
    self.extent = extent
    self.boundaryVerticesLocalXZ = boundaryVerticesLocalXZ
  }
}

/// Monotonic observed-anchor state that rejects delayed delegate deliveries after removal.
public struct ObservedPlaneStore: Equatable, Sendable {
  public private(set) var planes: [String: ObservedPlane] = [:]
  private var latestRevisions: [String: Int] = [:]

  public init() {}

  @discardableResult
  public mutating func upsert(_ plane: ObservedPlane) -> Bool {
    guard plane.revision > (latestRevisions[plane.id] ?? 0) else { return false }
    latestRevisions[plane.id] = plane.revision
    planes[plane.id] = plane
    return true
  }

  @discardableResult
  public mutating func remove(id: String, revision: Int) -> Bool {
    guard revision > (latestRevisions[id] ?? 0) else { return false }
    latestRevisions[id] = revision
    planes.removeValue(forKey: id)
    return true
  }
}
