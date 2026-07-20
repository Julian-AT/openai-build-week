import Foundation
import RealityKit

public enum RealityKitAssetLoader {
  /// Creates an entity only from a verified local USDZ cache entry. This loader
  /// never performs transport work and must be called outside the frame loop.
  @MainActor
  public static func loadUSDZ(
    from fileURL: URL,
    delivery: AssetDeliveryDescriptor
  ) async throws -> Entity {
    guard delivery.derivative == .usdz else { throw AssetDeliveryError.unsupportedDerivative }
    let verifiedURL = try await delivery.verifiedFileURL(fileURL)
    return try await Entity(contentsOf: verifiedURL)
  }
}
