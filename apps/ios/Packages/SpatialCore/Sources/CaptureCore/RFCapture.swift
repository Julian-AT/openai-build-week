import CryptoKit
import Foundation
import SpatialProtocol

/// A bounded, append-only native capture writer. Each packet is written to a
/// temporary file and atomically renamed before it is indexed, so an
/// interrupted write can never appear as an accepted frame.
public actor RFCaptureRecorder {
  public struct Configuration: Sendable {
    public let capacity: Int
    public init(capacity: Int = 2) {
      precondition(capacity > 0)
      self.capacity = capacity
    }
  }

  public struct Record: Codable, Equatable, Sendable {
    public let frameID: UInt64
    public let relativePath: String
    public let byteLength: Int
    public let sha256: String
    public let timestampNanoseconds: UInt64
  }

  private struct Index: Codable, Sendable {
    let formatVersion: String
    let sessionID: String
    var records: [Record]
    private enum CodingKeys: String, CodingKey {
      case formatVersion = "format_version"
      case sessionID = "session_id"
      case records
    }
  }

  public let rootURL: URL
  public let configuration: Configuration
  private var index: Index
  private var pending = 0

  public init(rootURL: URL, sessionID: String, configuration: Configuration = .init()) throws {
    self.rootURL = rootURL
    self.configuration = configuration
    self.index = Index(formatVersion: "1.0.0", sessionID: sessionID, records: [])
    try FileManager.default.createDirectory(
      at: rootURL.appendingPathComponent("frames"), withIntermediateDirectories: true)
  }

  /// Returns false when the bounded recorder is full; callers should drop the
  /// newest non-keyframe and keep the render loop unblocked.
  public func append(_ packet: FramePacket) throws -> Record? {
    guard pending < configuration.capacity else { return nil }
    pending += 1
    defer { pending -= 1 }
    let encoded = try packet.encoded()
    let filename = String(format: "%020llu.rffp", packet.metadata.frameID)
    let relative = "frames/\(filename)"
    let destination = rootURL.appendingPathComponent(relative)
    let temporary = destination.appendingPathExtension("part")
    try encoded.write(to: temporary, options: [.atomic])
    if FileManager.default.fileExists(atPath: destination.path) {
      try FileManager.default.removeItem(at: destination)
    }
    try FileManager.default.moveItem(at: temporary, to: destination)
    let digest = SHA256.hash(data: encoded).map { String(format: "%02x", $0) }.joined()
    let record = Record(
      frameID: packet.metadata.frameID, relativePath: relative,
      byteLength: encoded.count, sha256: digest,
      timestampNanoseconds: packet.metadata.timestampNanoseconds)
    index.records.append(record)
    try persistIndex()
    return record
  }

  public func records() -> [Record] { index.records }

  private func persistIndex() throws {
    let data = try JSONEncoder.sorted.encode(index)
    let destination = rootURL.appendingPathComponent("manifest.json")
    try data.write(to: destination, options: [.atomic])
  }
}

extension JSONEncoder {
  fileprivate static var sorted: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return encoder
  }
}
