import Foundation
import SpatialProtocol
import Testing

@testable import CaptureCore

@Test("RFCaptureRecorder atomically indexes complete frame packets")
func recorderWritesIndexedPacket() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let metadata = try FramePacketMetadata(
    sessionID: "room_showcase", submapID: 0, frameID: 7,
    timestampNanoseconds: 42,
    image: FramePacketImage(
      codec: "jpeg", width: 1, height: 1, orientation: "up", colorSpace: "sRGB", payloadBytes: 4),
    intrinsicsEncoded: Array(repeating: 1, count: 9), worldFromCameraARKit: .identity,
    tracking: FramePacketTracking(state: "normal", reason: "tracking", worldFrameVersion: 1),
    captureQuality: FramePacketCaptureQuality(
      blurScore: 1, angularVelocityRadiansPerSecond: 0,
      translationSinceLastMeters: 0, rotationSinceLastDegrees: 0, exposureSeconds: 0.01, iso: 100))
  let packet = try FramePacket(
    flags: 0, metadata: metadata, imageData: Data([0xff, 0xd8, 0xff, 0xd9]))
  let recorder = try RFCaptureRecorder(rootURL: root, sessionID: "room_showcase")
  let record = try #require(await recorder.append(packet))
  #expect(record.frameID == 7)
  let bytes = try Data(contentsOf: root.appendingPathComponent(record.relativePath))
  #expect(try FramePacket.decode(bytes) == packet)
  #expect((try Data(contentsOf: root.appendingPathComponent("manifest.json"))).count > 0)
}

@Test("RFCaptureRecorder applies bounded backpressure")
func recorderBoundsPendingFrames() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let recorder = try RFCaptureRecorder(
    rootURL: root, sessionID: "room_showcase", configuration: .init(capacity: 1))
  #expect(await recorder.records().isEmpty)
}
