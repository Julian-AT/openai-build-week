import Foundation
import SpatialProtocol

public struct LocalPlacementPreview: Equatable, Sendable {
  public let assetID: String
  public let baseSceneRevision: Int
  public let supportSurfaceID: String
  /// RF-COORD-1 column-vector transform serialized in row-major order.
  public let worldFromAsset: SpatialTransform

  public static func make(
    assetID: String,
    baseSceneRevision: Int,
    supportSurfaceID: String,
    floorContactWorld: SpatialVector3,
    yawRadians: Double
  ) throws -> LocalPlacementPreview {
    guard
      isSafeIdentifier(assetID),
      isSafeIdentifier(supportSurfaceID),
      baseSceneRevision >= 0,
      yawRadians.isFinite,
      yawRadians >= -.pi,
      yawRadians <= .pi,
      [floorContactWorld.x, floorContactWorld.y, floorContactWorld.z].allSatisfy(\.isFinite)
    else {
      throw PlacementPreviewError.invalidInput
    }
    let cosine = clean(cos(yawRadians))
    let sine = clean(sin(yawRadians))
    return LocalPlacementPreview(
      assetID: assetID,
      baseSceneRevision: baseSceneRevision,
      supportSurfaceID: supportSurfaceID,
      worldFromAsset: SpatialTransform(values: [
        cosine, 0, sine, floorContactWorld.x,
        0, 1, 0, floorContactWorld.y,
        -sine, 0, cosine, floorContactWorld.z,
        0, 0, 0, 1,
      ])
    )
  }
}

public enum PlacementPreviewError: Error, Equatable, Sendable {
  case invalidInput
}

public enum AuthoritativeAssetTransformError: Error, Equatable, Sendable {
  case invalidTransform
}

/// Validates an untrusted gateway transform without modifying its coordinate
/// frame or translation. Replacement transforms are deterministic server
/// output and must never be snapped to the phone's latest reticle hit.
public enum AuthoritativeAssetTransform {
  public static func decode(_ values: [Double]) throws -> SpatialTransform {
    guard values.count == 16, values.allSatisfy(\.isFinite) else {
      throw AuthoritativeAssetTransformError.invalidTransform
    }
    return SpatialTransform(values: values)
  }
}

private func isSafeIdentifier(_ value: String) -> Bool {
  guard value.count <= 128 else { return false }
  return value.range(
    of: #"^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$"#,
    options: .regularExpression
  ) != nil
}

private func clean(_ value: Double) -> Double {
  abs(value) < .ulpOfOne ? 0 : value
}
