import CryptoKit
import Foundation

public enum FramePacketError: Error, Equatable, Sendable {
  case invalidLength
  case invalidMagic
  case unsupportedVersion
  case invalidMetadata
  case invalidImage
}

public struct FramePacketImage: Codable, Equatable, Sendable {
  public let codec: String
  public let width: Int
  public let height: Int
  public let orientation: String
  public let colorSpace: String
  public let payloadBytes: Int

  public init(
    codec: String,
    width: Int,
    height: Int,
    orientation: String,
    colorSpace: String,
    payloadBytes: Int
  ) {
    self.codec = codec
    self.width = width
    self.height = height
    self.orientation = orientation
    self.colorSpace = colorSpace
    self.payloadBytes = payloadBytes
  }

  private enum CodingKeys: String, CodingKey {
    case codec, width, height, orientation
    case colorSpace = "color_space"
    case payloadBytes = "payload_bytes"
  }
}

public struct FramePacketTracking: Codable, Equatable, Sendable {
  public let state: String
  public let reason: String
  public let worldFrameVersion: Int

  public init(state: String, reason: String, worldFrameVersion: Int) {
    self.state = state
    self.reason = reason
    self.worldFrameVersion = worldFrameVersion
  }

  private enum CodingKeys: String, CodingKey {
    case state, reason
    case worldFrameVersion = "world_frame_version"
  }
}

public struct FramePacketCaptureQuality: Codable, Equatable, Sendable {
  public let blurScore: Double
  public let angularVelocityRadiansPerSecond: Double
  public let translationSinceLastMeters: Double
  public let rotationSinceLastDegrees: Double
  public let exposureSeconds: Double
  public let iso: Int

  public init(
    blurScore: Double,
    angularVelocityRadiansPerSecond: Double,
    translationSinceLastMeters: Double,
    rotationSinceLastDegrees: Double,
    exposureSeconds: Double,
    iso: Int
  ) {
    self.blurScore = blurScore
    self.angularVelocityRadiansPerSecond = angularVelocityRadiansPerSecond
    self.translationSinceLastMeters = translationSinceLastMeters
    self.rotationSinceLastDegrees = rotationSinceLastDegrees
    self.exposureSeconds = exposureSeconds
    self.iso = iso
  }

  private enum CodingKeys: String, CodingKey {
    case blurScore = "blur_score"
    case angularVelocityRadiansPerSecond = "angular_velocity_rad_s"
    case translationSinceLastMeters = "translation_since_last_m"
    case rotationSinceLastDegrees = "rotation_since_last_deg"
    case exposureSeconds = "exposure_s"
    case iso
  }
}

public struct FramePacketMetadata: Codable, Equatable, Sendable {
  public static let protocolVersion = 1

  public let protocolVersionValue: Int
  public let sessionID: String
  public let submapID: Int
  public let frameID: UInt64
  public let timestampNanoseconds: UInt64
  public let clockDomain: String
  public let image: FramePacketImage
  public let intrinsicsEncoded: [Double]
  public let worldFromCameraARKit: SpatialTransform
  public let tracking: FramePacketTracking
  public let captureQuality: FramePacketCaptureQuality

  public init(
    sessionID: String,
    submapID: Int,
    frameID: UInt64,
    timestampNanoseconds: UInt64,
    image: FramePacketImage,
    intrinsicsEncoded: [Double],
    worldFromCameraARKit: SpatialTransform,
    tracking: FramePacketTracking,
    captureQuality: FramePacketCaptureQuality
  ) throws {
    protocolVersionValue = Self.protocolVersion
    self.sessionID = sessionID
    self.submapID = submapID
    self.frameID = frameID
    self.timestampNanoseconds = timestampNanoseconds
    clockDomain = "ios_monotonic_uptime"
    self.image = image
    self.intrinsicsEncoded = intrinsicsEncoded
    self.worldFromCameraARKit = worldFromCameraARKit
    self.tracking = tracking
    self.captureQuality = captureQuality
    try validate()
  }

  private enum CodingKeys: String, CodingKey {
    case protocolVersionValue = "protocol_version"
    case sessionID = "session_id"
    case submapID = "submap_id"
    case frameID = "frame_id"
    case timestampNanoseconds = "timestamp_ns"
    case clockDomain = "clock_domain"
    case image
    case intrinsicsEncoded = "intrinsics_encoded"
    case worldFromCameraARKit = "world_from_camera_arkit"
    case tracking
    case captureQuality = "capture_quality"
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    protocolVersionValue = try values.decode(Int.self, forKey: .protocolVersionValue)
    sessionID = try values.decode(String.self, forKey: .sessionID)
    submapID = try values.decode(Int.self, forKey: .submapID)
    frameID = try values.decode(UInt64.self, forKey: .frameID)
    timestampNanoseconds = try values.decode(UInt64.self, forKey: .timestampNanoseconds)
    clockDomain = try values.decode(String.self, forKey: .clockDomain)
    image = try values.decode(FramePacketImage.self, forKey: .image)
    intrinsicsEncoded = try values.decode([Double].self, forKey: .intrinsicsEncoded)
    worldFromCameraARKit = try values.decode(SpatialTransform.self, forKey: .worldFromCameraARKit)
    tracking = try values.decode(FramePacketTracking.self, forKey: .tracking)
    captureQuality = try values.decode(FramePacketCaptureQuality.self, forKey: .captureQuality)
    try validate()
  }

  private func validate() throws {
    guard
      protocolVersionValue == Self.protocolVersion,
      sessionID.range(of: "^room_[a-z0-9_]{3,120}$", options: .regularExpression) != nil,
      submapID >= 0,
      frameID <= UInt64(Int.max),
      timestampNanoseconds <= UInt64(Int.max),
      clockDomain == "ios_monotonic_uptime",
      image.codec == "jpeg",
      (1...4_096).contains(image.width),
      (1...4_096).contains(image.height),
      image.orientation == "up",
      image.colorSpace == "sRGB",
      image.payloadBytes >= 4,
      intrinsicsEncoded.count == 9,
      intrinsicsEncoded.allSatisfy(\.isFinite),
      worldFromCameraARKit.values.allSatisfy(\.isFinite),
      ["normal", "limited", "not_available"].contains(tracking.state),
      !tracking.reason.isEmpty,
      tracking.reason.count <= 64,
      tracking.worldFrameVersion >= 0,
      [
        captureQuality.blurScore,
        captureQuality.angularVelocityRadiansPerSecond,
        captureQuality.translationSinceLastMeters,
        captureQuality.rotationSinceLastDegrees,
        captureQuality.exposureSeconds,
      ].allSatisfy(\.isFinite),
      captureQuality.blurScore >= 0,
      captureQuality.angularVelocityRadiansPerSecond >= 0,
      captureQuality.translationSinceLastMeters >= 0,
      captureQuality.rotationSinceLastDegrees >= 0,
      captureQuality.exposureSeconds > 0,
      (1...102_400).contains(captureQuality.iso)
    else {
      throw FramePacketError.invalidMetadata
    }
  }
}

/// The exact 24-byte little-endian `RFFP` frame envelope shared with the gateway.
public struct FramePacket: Equatable, Sendable {
  public static let magic = Data("RFFP".utf8)
  public static let headerLength = 24

  public let flags: UInt16
  public let metadata: FramePacketMetadata
  public let imageData: Data

  public init(flags: UInt16, metadata: FramePacketMetadata, imageData: Data) throws {
    guard imageData.count == metadata.image.payloadBytes else {
      throw FramePacketError.invalidLength
    }
    guard imageData.count >= 4, imageData.starts(with: [0xff, 0xd8]),
      imageData.suffix(2) == Data([0xff, 0xd9])
    else {
      throw FramePacketError.invalidImage
    }
    self.flags = flags
    self.metadata = metadata
    self.imageData = imageData
  }

  public func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let metadataData = try encoder.encode(metadata)
    guard metadataData.count <= Int(UInt32.max), imageData.count <= Int(UInt32.max) else {
      throw FramePacketError.invalidLength
    }
    var result = Self.magic
    result.appendLittleEndian(UInt16(FramePacketMetadata.protocolVersion))
    result.appendLittleEndian(flags)
    result.appendLittleEndian(UInt32(metadataData.count))
    result.appendLittleEndian(UInt32(imageData.count))
    result.appendLittleEndian(metadata.frameID)
    result.append(metadataData)
    result.append(imageData)
    return result
  }

  public static func decode(_ data: Data) throws -> FramePacket {
    guard data.count >= headerLength else { throw FramePacketError.invalidLength }
    guard data.prefix(4) == magic else { throw FramePacketError.invalidMagic }
    let version: UInt16 = try data.littleEndian(at: 4)
    guard version == FramePacketMetadata.protocolVersion else {
      throw FramePacketError.unsupportedVersion
    }
    let flags: UInt16 = try data.littleEndian(at: 6)
    let metadataLength: UInt32 = try data.littleEndian(at: 8)
    let imageLength: UInt32 = try data.littleEndian(at: 12)
    let frameID: UInt64 = try data.littleEndian(at: 16)
    let expectedLength = headerLength + Int(metadataLength) + Int(imageLength)
    guard expectedLength == data.count else { throw FramePacketError.invalidLength }
    let metadataRange = headerLength..<(headerLength + Int(metadataLength))
    let metadataData = data.subdata(in: metadataRange)
    try validateStrictMetadataJSON(metadataData)
    let metadata: FramePacketMetadata
    do {
      metadata = try JSONDecoder().decode(FramePacketMetadata.self, from: metadataData)
    } catch {
      throw FramePacketError.invalidMetadata
    }
    guard metadata.frameID == frameID else { throw FramePacketError.invalidMetadata }
    return try FramePacket(
      flags: flags, metadata: metadata, imageData: data.suffix(Int(imageLength)))
  }
}

public func canonicalJSONSHA256(_ value: Any) throws -> String {
  guard JSONSerialization.isValidJSONObject(value) else { throw FramePacketError.invalidMetadata }
  let data = try JSONSerialization.data(
    withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
  return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

extension Data {
  fileprivate mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
    var encoded = value.littleEndian
    Swift.withUnsafeBytes(of: &encoded) { append(contentsOf: $0) }
  }

  fileprivate func littleEndian<T: FixedWidthInteger>(at offset: Int) throws -> T {
    let length = MemoryLayout<T>.size
    guard offset >= 0, offset + length <= count else { throw FramePacketError.invalidLength }
    return subdata(in: offset..<(offset + length)).withUnsafeBytes { bytes in
      bytes.loadUnaligned(as: T.self).littleEndian
    }
  }
}

private func validateStrictMetadataJSON(_ data: Data) throws {
  let raw = try JSONSerialization.jsonObject(with: data)
  guard let root = raw as? [String: Any],
    Set(root.keys)
      == Set([
        "protocol_version", "session_id", "submap_id", "frame_id", "timestamp_ns", "clock_domain",
        "image", "intrinsics_encoded", "world_from_camera_arkit", "tracking", "capture_quality",
      ])
  else { throw FramePacketError.invalidMetadata }
  guard let image = root["image"] as? [String: Any],
    Set(image.keys)
      == Set([
        "codec", "width", "height", "orientation", "color_space", "payload_bytes",
      ])
  else { throw FramePacketError.invalidMetadata }
  guard let tracking = root["tracking"] as? [String: Any],
    Set(tracking.keys)
      == Set([
        "state", "reason", "world_frame_version",
      ])
  else { throw FramePacketError.invalidMetadata }
  guard let quality = root["capture_quality"] as? [String: Any],
    Set(quality.keys)
      == Set([
        "blur_score", "angular_velocity_rad_s", "translation_since_last_m",
        "rotation_since_last_deg",
        "exposure_s", "iso",
      ])
  else { throw FramePacketError.invalidMetadata }
}
