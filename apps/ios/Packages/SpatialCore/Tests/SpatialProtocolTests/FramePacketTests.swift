import Foundation
import SpatialProtocol
import Testing

@Test("FramePacket preserves the strict RFFP binary envelope and fails closed")
func framePacketRoundTrip() throws {
  let image = Data([0xff, 0xd8, 0xff, 0xd9])
  let metadata = try FramePacketMetadata(
    sessionID: "room_2026_07_13_01",
    submapID: 0,
    frameID: 842,
    timestampNanoseconds: 1_783_918_472_391_823,
    image: FramePacketImage(
      codec: "jpeg", width: 640, height: 480, orientation: "up", colorSpace: "sRGB",
      payloadBytes: image.count),
    intrinsicsEncoded: [514.4, 0, 319.8, 0, 513.9, 239.6, 0, 0, 1],
    worldFromCameraARKit: SpatialTransform.identity,
    tracking: FramePacketTracking(state: "normal", reason: "none", worldFrameVersion: 1),
    captureQuality: FramePacketCaptureQuality(
      blurScore: 0.08, angularVelocityRadiansPerSecond: 0.19, translationSinceLastMeters: 0.034,
      rotationSinceLastDegrees: 3.2, exposureSeconds: 0.0083, iso: 142)
  )
  let packet = try FramePacket(flags: 0b1001, metadata: metadata, imageData: image)
  let encoded = try packet.encoded()

  #expect(try FramePacket.decode(encoded) == packet)
  #expect(throws: FramePacketError.invalidLength) {
    try FramePacket.decode(Data(encoded.dropLast()))
  }
}
