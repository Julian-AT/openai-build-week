import Foundation
import ReRoomContracts

public enum FramePacketEncodingError: String, Error, Equatable, Sendable {
    case invalidProfile = "invalid_profile"
    case invalidCandidate = "invalid_candidate"
    case contractRejected = "contract_rejected"
    case wireRejected = "wire_rejected"
}

public struct FramePacketEncodingProfile: Equatable, Sendable {
    public let codec: String
    public let width: Int
    public let height: Int
    public let colorSpace: String
    public let imageRange: String
    public let cropInSensorPixels: [Double]
    public let intrinsicsEncodedPixels: [Double]
    public let encodedFromSensor: [Double]
    public let worldFromCamera: [Double]
    public let trackingState: String
    public let trackingReason: String
    public let motionScore: Double
    public let blurScore: Double
    public let exposureScore: Double

    public init(
        codec: String,
        width: Int,
        height: Int,
        colorSpace: String,
        imageRange: String,
        cropInSensorPixels: [Double],
        intrinsicsEncodedPixels: [Double],
        encodedFromSensor: [Double],
        worldFromCamera: [Double],
        trackingState: String,
        trackingReason: String,
        motionScore: Double,
        blurScore: Double,
        exposureScore: Double
    ) throws {
        let numericValues = cropInSensorPixels
            + intrinsicsEncodedPixels
            + encodedFromSensor
            + worldFromCamera
            + [motionScore, blurScore, exposureScore]
        guard ["jpeg", "hevc_intra", "png"].contains(codec),
              width > 0,
              height > 0,
              ["srgb", "display_p3"].contains(colorSpace),
              ["full", "video"].contains(imageRange),
              cropInSensorPixels.count == 4,
              cropInSensorPixels[0] >= 0,
              cropInSensorPixels[1] >= 0,
              cropInSensorPixels[2] > 0,
              cropInSensorPixels[3] > 0,
              intrinsicsEncodedPixels.count == 4,
              intrinsicsEncodedPixels[0] > 0,
              intrinsicsEncodedPixels[1] > 0,
              encodedFromSensor.count == 9,
              worldFromCamera.count == 16,
              (try? RRCoordinateMath.validateRigidTransform(worldFromCamera)) != nil,
              numericValues.allSatisfy({ (try? RRCoordinateMath.quantize($0)) != nil }),
              [motionScore, blurScore, exposureScore].allSatisfy({ (0...1).contains($0) }),
              Self.validTracking(state: trackingState, reason: trackingReason)
        else {
            throw FramePacketEncodingError.invalidProfile
        }

        self.codec = codec
        self.width = width
        self.height = height
        self.colorSpace = colorSpace
        self.imageRange = imageRange
        self.cropInSensorPixels = cropInSensorPixels
        self.intrinsicsEncodedPixels = intrinsicsEncodedPixels
        self.encodedFromSensor = encodedFromSensor
        self.worldFromCamera = worldFromCamera
        self.trackingState = trackingState
        self.trackingReason = trackingReason
        self.motionScore = motionScore
        self.blurScore = blurScore
        self.exposureScore = exposureScore
    }

    public static let syntheticOnePixelPNG = try! FramePacketEncodingProfile(
        codec: "png",
        width: 1,
        height: 1,
        colorSpace: "srgb",
        imageRange: "full",
        cropInSensorPixels: [0, 0, 1, 1],
        intrinsicsEncodedPixels: [1, 1, 0.5, 0.5],
        encodedFromSensor: [1, 0, 0, 0, 1, 0, 0, 0, 1],
        worldFromCamera: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
        trackingState: "normal",
        trackingReason: "none",
        motionScore: 0,
        blurScore: 1,
        exposureScore: 1
    )

    private static func validTracking(state: String, reason: String) -> Bool {
        switch state {
        case "normal": reason == "none"
        case "limited": [
            "initializing", "excessive_motion", "insufficient_features", "relocalizing",
            "unknown",
        ].contains(reason)
        case "not_available": ["camera_unavailable", "unknown"].contains(reason)
        default: false
        }
    }
}

public struct EncodedFramePacket: Equatable, Sendable {
    public let packetData: Data
    public let imageData: Data
    public let wireData: Data
    public let packetSHA256: String
    public let imageSHA256: String
    public let durableJournalSequence: UInt64
}

public struct FramePacketEncoder: Sendable {
    public static let framePacketSchemaSHA256 =
        "d50b19bfb29c6c62c494e3a47deb3c51a933609698f4ff2f9cbfba6ec4252b43"

    public let validator: ContractValidator
    public let profile: FramePacketEncodingProfile

    public init(validator: ContractValidator, profile: FramePacketEncodingProfile) {
        self.validator = validator
        self.profile = profile
    }

    public func encode(
        _ candidate: SelectedFrameCandidate,
        durableJournalSequence: UInt64,
        profile overrideProfile: FramePacketEncodingProfile? = nil
    ) throws -> EncodedFramePacket {
        let profile = overrideProfile ?? self.profile
        guard candidate.captureSequence <= 9_007_199_254_740_991,
              durableJournalSequence <= 9_007_199_254_740_991,
              candidate.worldFrameVersion <= 9_007_199_254_740_991,
              candidate.imageBytes.count <= RRFPWireFrame.maximumPayloadBytes,
              Self.pathExtension(for: profile.codec).map(candidate.imageRelativePath.hasSuffix) == true,
              candidate.packetRelativePath.hasSuffix(".json")
        else {
            throw FramePacketEncodingError.invalidCandidate
        }

        let imageSHA256 = CanonicalJSON.sha256Hex(candidate.imageBytes)
        let crop = profile.cropInSensorPixels
        let intrinsics = profile.intrinsicsEncodedPixels
        let object: [String: Any] = [
            "protocol_version": "1.0.0",
            "session_id": candidate.sessionID,
            "submap_id": candidate.submapID,
            "frame_id": candidate.frameID,
            "world_frame_id": candidate.worldFrameID,
            "world_frame_version": candidate.worldFrameVersion,
            "capture_sequence": candidate.captureSequence,
            "monotonic_timestamp_ns": candidate.monotonicTimestampNanoseconds,
            "timestamp_domain": "device_monotonic_boot",
            "coordinate_convention": "RR-COORD-1",
            "image": [
                "codec": profile.codec,
                "width": profile.width,
                "height": profile.height,
                "orientation": "up",
                "pixel_origin": "top_left",
                "pixel_center": "half_integer",
                "color_space": profile.colorSpace,
                "range": profile.imageRange,
                "crop_in_sensor_pixels": [
                    "x": crop[0], "y": crop[1], "width": crop[2], "height": crop[3],
                ],
                "payload": [
                    "kind": "rrcap_file",
                    "relative_path": candidate.imageRelativePath,
                    "sha256": imageSHA256,
                    "byte_length": candidate.imageBytes.count,
                ],
            ],
            "intrinsics_encoded_pixels": [
                "fx": intrinsics[0], "fy": intrinsics[1],
                "cx": intrinsics[2], "cy": intrinsics[3],
                "width": profile.width, "height": profile.height,
                "units": "encoded_pixels",
            ],
            "encoded_from_sensor": [
                "layout": "row_major",
                "scalar_type": "float32",
                "math_convention": "column_vector",
                "values": profile.encodedFromSensor,
            ],
            "world_from_camera": [
                "layout": "row_major",
                "scalar_type": "float32",
                "math_convention": "column_vector",
                "units": "meters",
                "values": profile.worldFromCamera,
            ],
            "tracking": [
                "state": profile.trackingState,
                "reason": profile.trackingReason,
            ],
            "quality": [
                "motion_score": profile.motionScore,
                "blur_score": profile.blurScore,
                "exposure_score": profile.exposureScore,
                "selected_reason": candidate.selectedReason.rawValue,
            ],
            "durability": [
                "state": "network_eligible",
                "image_and_metadata_durable": true,
                "journal_sequence": durableJournalSequence,
                "network_eligible": true,
            ],
            "idempotency_key": candidate.idempotencyKey,
            "previous_durable_frame_id": NSNull(),
            "payload_sha256": imageSHA256,
            "wire_framing": [
                "format": "RRFP-WIRE-1",
                "magic_ascii": "RRFP",
                "version_major": 1,
                "version_minor": 0,
                "byte_order": "network_big_endian",
                "fixed_header_bytes": 24,
                "json_encoding": "rfc8785_jcs_utf8",
                "json_header_max_bytes": 65_536,
                "payload_max_bytes": 16_777_216,
            ],
        ]

        let encoded = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let canonical = try CanonicalJSON.canonicalize(
            jsonData: encoded,
            maximumBytes: RRFPWireFrame.maximumJSONHeaderBytes
        )
        guard validator.validate(
            ContractValidationRequest(
                schemaID: ContractSchemaIdentifier.framePacket.rawValue,
                schemaVersion: "1.0.0",
                schemaSHA256: Self.framePacketSchemaSHA256,
                documentData: canonical,
                payloadData: candidate.imageBytes
            )
        ) == .accepted else {
            throw FramePacketEncodingError.contractRejected
        }

        let wire: Data
        do {
            wire = try RRFPWireFrame.encode(headerJSON: canonical, payload: candidate.imageBytes)
        } catch {
            throw FramePacketEncodingError.wireRejected
        }
        return EncodedFramePacket(
            packetData: canonical,
            imageData: candidate.imageBytes,
            wireData: wire,
            packetSHA256: CanonicalJSON.sha256Hex(canonical),
            imageSHA256: imageSHA256,
            durableJournalSequence: durableJournalSequence
        )
    }

    public func wireFrame(
        for candidate: SelectedFrameCandidate,
        durableJournalSequence: UInt64
    ) throws -> Data {
        try encode(candidate, durableJournalSequence: durableJournalSequence).wireData
    }

    private static func pathExtension(for codec: String) -> String? {
        switch codec {
        case "jpeg": ".jpg"
        case "hevc_intra": ".heic"
        case "png": ".png"
        default: nil
        }
    }
}
