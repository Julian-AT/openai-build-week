import Foundation
import ReRoomContracts

enum FramePacketBuildRejection: Error, Equatable, Sendable {
    case invalidAttempt
    case invalidInput
    case payloadTooLarge
    case packetTooLarge
    case schemaRejected(ContractValidationRejection)
    case notImplemented
}

struct FrameCrop: Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct FrameIntrinsics: Equatable, Sendable {
    let fx: Double
    let fy: Double
    let cx: Double
    let cy: Double
    let width: Int
    let height: Int
}

struct FrameQuality: Equatable, Sendable {
    let motionScore: Double
    let blurScore: Double
    let exposureScore: Double
    let selectedReason: String
}

struct FramePacketCaptureInput: Equatable, Sendable {
    let sessionID: String
    let submapID: String
    let frameID: String
    let captureSequence: UInt64
    let monotonicTimestampNS: String
    let imageData: Data
    let imageCodec: String
    let imageWidth: Int
    let imageHeight: Int
    let colorSpace: String
    let imageRange: String
    let cropInSensorPixels: FrameCrop
    let intrinsicsEncodedPixels: FrameIntrinsics
    let encodedFromSensor: [Double]
    let worldFromCamera: [Double]
    let trackingState: String
    let trackingReason: String
    let quality: FrameQuality
    let idempotencyKey: String
    let previousDurableFrameID: String?
    let lifecycleEventIDs: [String]
}

struct BuiltFramePacket: Equatable, Sendable {
    let frameID: String
    let imagePath: String
    let packetPath: String
    let imageData: Data
    let packetData: Data
    let payloadSHA256: String
    let packetSHA256: String
    let durableJournalSequence: Int
}

struct FramePacketBuilder: Sendable {
    static let maximumPacketBytes = 65_536
    static let maximumPayloadBytes = 16_777_216

    let validator: ContractValidator

    func build(
        input: FramePacketCaptureInput,
        attempt: CaptureAttemptResolution,
        durableJournalSequence: Int
    ) throws -> BuiltFramePacket {
        _ = input
        _ = attempt
        _ = durableJournalSequence
        throw FramePacketBuildRejection.notImplemented
    }
}
