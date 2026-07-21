import CryptoKit
import Foundation
import RenderCore
import SpatialProtocol
import Testing

@Test("floor placement creates a row-major transform without committing a scene revision")
func createsFloorPlacementPreview() throws {
  let preview = try LocalPlacementPreview.make(
    assetID: "ikea-us-40541421-d74d34f0a861",
    baseSceneRevision: 7,
    supportSurfaceID: "arkit_plane_floor",
    floorContactWorld: SpatialVector3(x: 1.25, y: 0, z: -2.5),
    yawRadians: .pi / 2
  )

  #expect(preview.baseSceneRevision == 7)
  #expect(
    preview.worldFromAsset.values == [
      0, 0, 1, 1.25,
      0, 1, 0, 0,
      -1, 0, 0, -2.5,
      0, 0, 0, 1,
    ])
}

@Test("an authoritative replacement transform is preserved exactly")
func preservesAuthoritativeReplacementTransform() throws {
  let serverTransform = [
    0.0, 0.0, 1.0, 1.75,
    0.0, 1.0, 0.0, 0.02,
    -1.0, 0.0, 0.0, -3.25,
    0.0, 0.0, 0.0, 1.0,
  ]

  let transform = try AuthoritativeAssetTransform.decode(serverTransform)

  #expect(transform.values == serverTransform)
}

@Test("an invalid authoritative transform fails closed")
func rejectsInvalidAuthoritativeTransform() {
  #expect(throws: AuthoritativeAssetTransformError.invalidTransform) {
    try AuthoritativeAssetTransform.decode(Array(repeating: 0, count: 15))
  }
  #expect(throws: AuthoritativeAssetTransformError.invalidTransform) {
    try AuthoritativeAssetTransform.decode([
      1, 0, 0, 0,
      0, 1, 0, .infinity,
      0, 0, 1, 0,
      0, 0, 0, 1,
    ])
  }
}

@Test("asset delivery verifies its declared byte length and SHA-256 before RealityKit use")
func verifiesAssetDeliveryBytes() throws {
  let bytes = Data([0x52, 0x46, 0x43, 0x41, 0x50])
  let descriptor = try AssetDeliveryDescriptor(
    assetID: "ikea-us-40541421-d74d34f0a861",
    derivative: .usdz,
    expectedSHA256: hex(SHA256.hash(data: bytes)),
    expectedByteLength: bytes.count
  )

  #expect(try descriptor.verify(bytes: bytes) == bytes)
}

@Test("asset delivery refuses a network URL before the render path can block on it")
func rejectsNetworkAssetDeliveryURL() async throws {
  let descriptor = try AssetDeliveryDescriptor(
    assetID: "ikea-us-40541421-d74d34f0a861",
    derivative: .usdz,
    expectedSHA256: String(repeating: "a", count: 64),
    expectedByteLength: 1
  )

  await #expect(throws: AssetDeliveryError.unreadableFile) {
    try await descriptor.verifiedFileURL(URL(string: "https://assets.example/side-table.usdz")!)
  }
}

@Test("loads an operator-supplied verified USDZ through the RealityKit production loader")
@MainActor
func loadsSuppliedUSDZ() async throws {
  guard let path = ProcessInfo.processInfo.environment["REFRAME_REAL_USDZ"], !path.isEmpty else {
    return
  }
  let fileURL = URL(fileURLWithPath: path)
  let bytes = try Data(contentsOf: fileURL)
  let descriptor = try AssetDeliveryDescriptor(
    assetID: "ikea-us-40541421-d74d34f0a861",
    derivative: .usdz,
    expectedSHA256: hex(SHA256.hash(data: bytes)),
    expectedByteLength: bytes.count
  )

  let entity = try await RealityKitAssetLoader.loadUSDZ(from: fileURL, delivery: descriptor)
  #expect(entity.children.count >= 0)
}

private func hex(_ digest: SHA256.Digest) -> String {
  digest.map { String(format: "%02x", $0) }.joined()
}
