import CryptoKit
import Foundation

public enum AssetDerivative: String, Equatable, Sendable {
  case glb
  case usdz
}

public struct AssetDeliveryDescriptor: Equatable, Sendable {
  public let assetID: String
  public let derivative: AssetDerivative
  public let expectedSHA256: String
  public let expectedByteLength: Int

  public init(
    assetID: String,
    derivative: AssetDerivative,
    expectedSHA256: String,
    expectedByteLength: Int
  ) throws {
    guard
      isSafeAssetIdentifier(assetID),
      expectedSHA256.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil,
      expectedByteLength > 0
    else {
      throw AssetDeliveryError.invalidDescriptor
    }
    self.assetID = assetID
    self.derivative = derivative
    self.expectedSHA256 = expectedSHA256
    self.expectedByteLength = expectedByteLength
  }

  public func verify(bytes: Data) throws -> Data {
    guard bytes.count == expectedByteLength else { throw AssetDeliveryError.lengthMismatch }
    guard hex(SHA256.hash(data: bytes)) == expectedSHA256 else {
      throw AssetDeliveryError.hashMismatch
    }
    return bytes
  }

  /// Rendering consumes only a verified local cache file. Transport and retry
  /// belong to the client-cache synchronizer, never the frame path.
  public func verifiedFileURL(_ fileURL: URL) async throws -> URL {
    guard fileURL.isFileURL else { throw AssetDeliveryError.unreadableFile }
    let bytes = try await Task.detached {
      try Data(contentsOf: fileURL, options: .mappedIfSafe)
    }.value
    _ = try verify(bytes: bytes)
    return fileURL
  }
}

public enum AssetDeliveryError: Error, Equatable, Sendable {
  case invalidDescriptor
  case lengthMismatch
  case hashMismatch
  case unreadableFile
  case unsupportedDerivative
}

private func isSafeAssetIdentifier(_ value: String) -> Bool {
  guard value.count <= 128 else { return false }
  return value.range(
    of: #"^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$"#,
    options: .regularExpression
  ) != nil
}

private func hex(_ digest: SHA256.Digest) -> String {
  digest.map { String(format: "%02x", $0) }.joined()
}
