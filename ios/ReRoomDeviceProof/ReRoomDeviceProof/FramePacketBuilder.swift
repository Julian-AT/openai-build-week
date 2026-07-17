import Foundation
import ReRoomContracts

enum FramePacketBuildRejection: Error, Equatable, Sendable {
    case invalidAttempt
    case invalidInput
    case payloadTooLarge
    case packetTooLarge
    case schemaRejected(ContractValidationRejection)
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
        guard case .ready(let validatedAttempt) = attempt else {
            throw FramePacketBuildRejection.invalidAttempt
        }
        guard input.imageData.isEmpty == false,
              input.imageData.count <= Self.maximumPayloadBytes,
              input.imageWidth > 0,
              input.imageHeight > 0,
              input.captureSequence <= 9_007_199_254_740_991,
              input.intrinsicsEncodedPixels.width == input.imageWidth,
              input.intrinsicsEncodedPixels.height == input.imageHeight,
              validatedAttempt.frameSnapshotID == input.monotonicTimestampNS,
              durableJournalSequence >= 0,
              validInput(input)
        else {
            if input.imageData.count > Self.maximumPayloadBytes {
                throw FramePacketBuildRejection.payloadTooLarge
            }
            throw FramePacketBuildRejection.invalidInput
        }

        let payloadSHA256 = CanonicalJSON.sha256Hex(input.imageData)
        let imagePath = "frames/\(input.frameID)/image.\(fileExtension(for: input.imageCodec))"
        let packetPath = "frames/\(input.frameID)/packet.json"
        let packet = packetObject(
            input: input,
            attempt: validatedAttempt,
            durableJournalSequence: durableJournalSequence,
            imagePath: imagePath,
            payloadSHA256: payloadSHA256
        )
        let encoded = try JSONSerialization.data(withJSONObject: packet, options: [.sortedKeys])
        let canonical: Data
        do {
            canonical = try CanonicalJSON.canonicalize(
                jsonData: encoded,
                maximumBytes: Self.maximumPacketBytes
            )
        } catch {
            throw FramePacketBuildRejection.invalidInput
        }
        guard canonical.count <= Self.maximumPacketBytes else {
            throw FramePacketBuildRejection.packetTooLarge
        }

        let verdict = validator.validate(
            ContractValidationRequest(
                schemaID: ContractSchemaIdentifier.framePacket.rawValue,
                schemaVersion: "1.0.0",
                schemaSHA256: "d50b19bfb29c6c62c494e3a47deb3c51a933609698f4ff2f9cbfba6ec4252b43",
                documentData: canonical,
                payloadData: input.imageData
            )
        )
        if case .rejected(let rejection) = verdict {
            throw FramePacketBuildRejection.schemaRejected(rejection)
        }

        return BuiltFramePacket(
            frameID: input.frameID,
            imagePath: imagePath,
            packetPath: packetPath,
            imageData: input.imageData,
            packetData: canonical,
            payloadSHA256: payloadSHA256,
            packetSHA256: CanonicalJSON.sha256Hex(canonical),
            durableJournalSequence: durableJournalSequence
        )
    }

    private func validInput(_ input: FramePacketCaptureInput) -> Bool {
        let crop = input.cropInSensorPixels
        let intrinsics = input.intrinsicsEncodedPixels
        let spatialValues = [
            crop.x, crop.y, crop.width, crop.height,
            intrinsics.fx, intrinsics.fy, intrinsics.cx, intrinsics.cy,
            input.quality.motionScore, input.quality.blurScore, input.quality.exposureScore,
        ] + input.encodedFromSensor + input.worldFromCamera
        guard spatialValues.allSatisfy({ (try? RRCoordinateMath.quantize($0)) != nil }),
              crop.x >= 0,
              crop.y >= 0,
              crop.width > 0,
              crop.height > 0,
              intrinsics.fx > 0,
              intrinsics.fy > 0,
              input.encodedFromSensor.count == 9,
              abs(input.encodedFromSensor[6]) <= RRCoordinateMath.homogeneousRowTolerance,
              abs(input.encodedFromSensor[7]) <= RRCoordinateMath.homogeneousRowTolerance,
              abs(input.encodedFromSensor[8] - 1) <= RRCoordinateMath.homogeneousRowTolerance,
              input.worldFromCamera.count == 16,
              (try? RRCoordinateMath.validateRigidTransform(input.worldFromCamera)) != nil,
              (0...1).contains(input.quality.motionScore),
              (0...1).contains(input.quality.blurScore),
              (0...1).contains(input.quality.exposureScore),
              ["jpeg", "hevc_intra", "png"].contains(input.imageCodec),
              ["srgb", "display_p3"].contains(input.colorSpace),
              ["full", "video"].contains(input.imageRange),
              ["cadence", "view_novelty", "keyframe", "user_event", "recovery"]
                .contains(input.quality.selectedReason),
              validTracking(state: input.trackingState, reason: input.trackingReason),
              input.monotonicTimestampNS.wholeNumberValue != nil
        else {
            return false
        }
        return true
    }

    private func validTracking(state: String, reason: String) -> Bool {
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

    private func fileExtension(for codec: String) -> String {
        switch codec {
        case "jpeg": "jpg"
        case "hevc_intra": "heic"
        default: "png"
        }
    }

    private func packetObject(
        input: FramePacketCaptureInput,
        attempt: ValidatedCaptureAttempt,
        durableJournalSequence: Int,
        imagePath: String,
        payloadSHA256: String
    ) -> [String: Any] {
        let crop = input.cropInSensorPixels
        let intrinsics = input.intrinsicsEncodedPixels
        return [
            "protocol_version": "1.0.0",
            "session_id": input.sessionID,
            "submap_id": input.submapID,
            "frame_id": input.frameID,
            "world_frame_id": attempt.worldFrameID,
            "world_frame_version": attempt.worldFrameVersion,
            "capture_sequence": input.captureSequence,
            "monotonic_timestamp_ns": input.monotonicTimestampNS,
            "timestamp_domain": "device_monotonic_boot",
            "coordinate_convention": "RR-COORD-1",
            "image": [
                "codec": input.imageCodec,
                "width": input.imageWidth,
                "height": input.imageHeight,
                "orientation": "up",
                "pixel_origin": "top_left",
                "pixel_center": "half_integer",
                "color_space": input.colorSpace,
                "range": input.imageRange,
                "crop_in_sensor_pixels": [
                    "x": crop.x,
                    "y": crop.y,
                    "width": crop.width,
                    "height": crop.height,
                ],
                "payload": [
                    "kind": "rrcap_file",
                    "relative_path": imagePath,
                    "sha256": payloadSHA256,
                    "byte_length": input.imageData.count,
                ],
            ],
            "intrinsics_encoded_pixels": [
                "fx": intrinsics.fx,
                "fy": intrinsics.fy,
                "cx": intrinsics.cx,
                "cy": intrinsics.cy,
                "width": intrinsics.width,
                "height": intrinsics.height,
                "units": "encoded_pixels",
            ],
            "encoded_from_sensor": [
                "layout": "row_major",
                "scalar_type": "float32",
                "math_convention": "column_vector",
                "values": input.encodedFromSensor,
            ],
            "world_from_camera": [
                "layout": "row_major",
                "scalar_type": "float32",
                "math_convention": "column_vector",
                "units": "meters",
                "values": input.worldFromCamera,
            ],
            "tracking": [
                "state": input.trackingState,
                "reason": input.trackingReason,
            ],
            "quality": [
                "motion_score": input.quality.motionScore,
                "blur_score": input.quality.blurScore,
                "exposure_score": input.quality.exposureScore,
                "selected_reason": input.quality.selectedReason,
            ],
            "durability": [
                "state": "network_eligible",
                "image_and_metadata_durable": true,
                "journal_sequence": durableJournalSequence,
                "network_eligible": true,
            ],
            "idempotency_key": input.idempotencyKey,
            "previous_durable_frame_id": input.previousDurableFrameID ?? NSNull(),
            "payload_sha256": payloadSHA256,
            "wire_framing": [
                "format": "RRFP-WIRE-1",
                "magic_ascii": "RRFP",
                "version_major": 1,
                "version_minor": 0,
                "byte_order": "network_big_endian",
                "fixed_header_bytes": 24,
                "json_encoding": "rfc8785_jcs_utf8",
                "json_header_max_bytes": Self.maximumPacketBytes,
                "payload_max_bytes": Self.maximumPayloadBytes,
            ],
        ]
    }
}

private extension String {
    var wholeNumberValue: UInt64? {
        guard isEmpty == false,
              self == "0" || first != "0",
              allSatisfy(\.isNumber)
        else {
            return nil
        }
        return UInt64(self)
    }
}
