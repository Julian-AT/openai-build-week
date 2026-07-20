import ARKit
import CoreImage
import Foundation
import ImageIO
import ReRoomContracts
import UniformTypeIdentifiers

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

enum CapturedFrameSnapshotRejection: Error, Equatable, Sendable {
    case invalidInput
}

enum CaptureInterfaceOrientation: Equatable, Sendable {
    case portrait
    case portraitUpsideDown
    case landscapeLeft
    case landscapeRight
}

struct UprightImageGeometry: Equatable, Sendable {
    let encodedWidth: Int
    let encodedHeight: Int
    let encodedFromSensor: [Double]

    static func forSensor(
        width: Int,
        height: Int,
        orientation: CaptureInterfaceOrientation
    ) -> UprightImageGeometry {
        switch orientation {
        case .portrait:
            UprightImageGeometry(
                encodedWidth: height,
                encodedHeight: width,
                encodedFromSensor: [0, -1, Double(height), 1, 0, 0, 0, 0, 1]
            )
        case .portraitUpsideDown:
            UprightImageGeometry(
                encodedWidth: height,
                encodedHeight: width,
                encodedFromSensor: [0, 1, 0, -1, 0, Double(width), 0, 0, 1]
            )
        case .landscapeLeft:
            UprightImageGeometry(
                encodedWidth: width,
                encodedHeight: height,
                encodedFromSensor: [-1, 0, Double(width), 0, -1, Double(height), 0, 0, 1]
            )
        case .landscapeRight:
            UprightImageGeometry(
                encodedWidth: width,
                encodedHeight: height,
                encodedFromSensor: [1, 0, 0, 0, 1, 0, 0, 0, 1]
            )
        }
    }

    func map(x: Double, y: Double) -> [Double] {
        [
            encodedFromSensor[0] * x + encodedFromSensor[1] * y + encodedFromSensor[2],
            encodedFromSensor[3] * x + encodedFromSensor[4] * y + encodedFromSensor[5],
        ]
    }
}

struct CapturedFrameSnapshot: Equatable, Sendable {
    let id: String
    let imageData: Data
    let imageCodec: String
    let imageWidth: Int
    let imageHeight: Int
    let orientation: String
    let colorSpace: String
    let imageRange: String
    let cropInSensorPixels: FrameCrop
    let intrinsicsEncodedPixels: FrameIntrinsics
    let encodedFromSensor: [Double]
    let worldFromCamera: [Double]
    let trackingState: String
    let trackingReason: String

    static func validated(
        id: String,
        imageData: Data,
        imageCodec: String,
        colorSpace: String,
        imageRange: String,
        cropInSensorPixels: FrameCrop,
        sensorIntrinsics: FrameIntrinsics,
        encodedFromSensor: [Double],
        worldFromCamera: [Double],
        trackingState: String,
        trackingReason: String
    ) throws -> CapturedFrameSnapshot {
        guard imageData.isEmpty == false,
              imageData.count <= FramePacketBuilder.maximumPayloadBytes,
              id.wholeNumberValue != nil,
              ["jpeg", "hevc_intra", "png"].contains(imageCodec),
              ["srgb", "display_p3"].contains(colorSpace),
              ["full", "video"].contains(imageRange),
              trackingState == "normal",
              trackingReason == "none",
              let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0,
              height > 0,
              ((properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1) == 1,
              encodedFromSensor.count == 9,
              sensorIntrinsics.width > 0,
              sensorIntrinsics.height > 0,
              worldFromCamera.count == 16,
              (try? RRCoordinateMath.validateRigidTransform(worldFromCamera)) != nil,
              cropAndTransformAgree(
                crop: cropInSensorPixels,
                transform: encodedFromSensor,
                encodedWidth: width,
                encodedHeight: height
              ),
              let transformed = try? RRCoordinateMath.transformIntrinsics(
                sensor: RRIntrinsics(
                    fx: sensorIntrinsics.fx,
                    fy: sensorIntrinsics.fy,
                    cx: sensorIntrinsics.cx,
                    cy: sensorIntrinsics.cy
                ),
                encodedFromSensor: encodedFromSensor,
                encodedSize: [width, height],
                orientation: "up"
              )
        else {
            throw CapturedFrameSnapshotRejection.invalidInput
        }
        return CapturedFrameSnapshot(
            id: id,
            imageData: imageData,
            imageCodec: imageCodec,
            imageWidth: width,
            imageHeight: height,
            orientation: "up",
            colorSpace: colorSpace,
            imageRange: imageRange,
            cropInSensorPixels: cropInSensorPixels,
            intrinsicsEncodedPixels: FrameIntrinsics(
                fx: transformed.intrinsics.fx,
                fy: transformed.intrinsics.fy,
                cx: transformed.intrinsics.cx,
                cy: transformed.intrinsics.cy,
                width: width,
                height: height
            ),
            encodedFromSensor: encodedFromSensor,
            worldFromCamera: worldFromCamera,
            trackingState: trackingState,
            trackingReason: trackingReason
        )
    }

    private static func cropAndTransformAgree(
        crop: FrameCrop,
        transform: [Double],
        encodedWidth: Int,
        encodedHeight: Int
    ) -> Bool {
        guard crop.x >= 0, crop.y >= 0, crop.width > 0, crop.height > 0 else {
            return false
        }
        let corners = [
            (crop.x, crop.y),
            (crop.x + crop.width, crop.y),
            (crop.x, crop.y + crop.height),
            (crop.x + crop.width, crop.y + crop.height),
        ].map { x, y in
            (
                transform[0] * x + transform[1] * y + transform[2],
                transform[3] * x + transform[4] * y + transform[5]
            )
        }
        let xs = corners.map(\.0)
        let ys = corners.map(\.1)
        let tolerance = RRCoordinateMath.transformedIntrinsicsAbsoluteTolerance
        return abs((xs.min() ?? .infinity) - 0) <= tolerance
            && abs((ys.min() ?? .infinity) - 0) <= tolerance
            && abs((xs.max() ?? -.infinity) - Double(encodedWidth)) <= tolerance
            && abs((ys.max() ?? -.infinity) - Double(encodedHeight)) <= tolerance
    }
}

@MainActor
struct ARFrameCaptureAdapter {
    private let context = CIContext(options: [.cacheIntermediates: false])

    func capture(
        frame: ARFrame,
        orientation: CaptureInterfaceOrientation,
        codec: String = "jpeg"
    ) throws -> CapturedFrameSnapshot {
        guard case .normal = frame.camera.trackingState else {
            throw CapturedFrameSnapshotRejection.invalidInput
        }
        let sensorWidth = CVPixelBufferGetWidth(frame.capturedImage)
        let sensorHeight = CVPixelBufferGetHeight(frame.capturedImage)
        let geometry = UprightImageGeometry.forSensor(
            width: sensorWidth,
            height: sensorHeight,
            orientation: orientation
        )
        let propertyOrientation: CGImagePropertyOrientation = switch orientation {
        case .portrait: .right
        case .portraitUpsideDown: .left
        case .landscapeLeft: .down
        case .landscapeRight: .up
        }
        let oriented = CIImage(cvPixelBuffer: frame.capturedImage)
            .oriented(propertyOrientation)
        let normalized = oriented.transformed(
            by: CGAffineTransform(
                translationX: -oriented.extent.minX,
                y: -oriented.extent.minY
            )
        )
        guard Int(normalized.extent.width.rounded()) == geometry.encodedWidth,
              Int(normalized.extent.height.rounded()) == geometry.encodedHeight,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        else {
            throw CapturedFrameSnapshotRejection.invalidInput
        }
        let imageData: Data?
        switch codec {
        case "jpeg":
            imageData = context.jpegRepresentation(
                of: normalized,
                colorSpace: colorSpace,
                options: [:]
            )
        case "png":
            imageData = context.pngRepresentation(
                of: normalized,
                format: .RGBA8,
                colorSpace: colorSpace,
                options: [:]
            )
        default:
            imageData = nil
        }
        guard let imageData else {
            throw CapturedFrameSnapshotRejection.invalidInput
        }

        let intrinsics = frame.camera.intrinsics
        let transform = frame.camera.transform
        let worldFromCamera = (0..<4).flatMap { row in
            (0..<4).map { column in Double(transform[column][row]) }
        }
        return try CapturedFrameSnapshot.validated(
            id: String(UInt64(max(0, (frame.timestamp * 1_000_000_000).rounded()))),
            imageData: imageData,
            imageCodec: codec,
            colorSpace: "srgb",
            imageRange: "full",
            cropInSensorPixels: FrameCrop(
                x: 0,
                y: 0,
                width: Double(sensorWidth),
                height: Double(sensorHeight)
            ),
            sensorIntrinsics: FrameIntrinsics(
                fx: Double(intrinsics[0][0]),
                fy: Double(intrinsics[1][1]),
                cx: Double(intrinsics[2][0]),
                cy: Double(intrinsics[2][1]),
                width: sensorWidth,
                height: sensorHeight
            ),
            encodedFromSensor: geometry.encodedFromSensor,
            worldFromCamera: worldFromCamera,
            trackingState: "normal",
            trackingReason: "none"
        )
    }
}

struct FramePacketCaptureInput: Equatable, Sendable {
    let sessionID: String
    let submapID: String
    let frameID: String
    let captureSequence: UInt64
    let capturedFrame: CapturedFrameSnapshot
    let quality: FrameQuality
    let idempotencyKey: String
    let previousDurableFrameID: String?
    let lifecycleEventIDs: [String]

    var monotonicTimestampNS: String { capturedFrame.id }
    var imageData: Data { capturedFrame.imageData }
    var imageCodec: String { capturedFrame.imageCodec }
    var imageWidth: Int { capturedFrame.imageWidth }
    var imageHeight: Int { capturedFrame.imageHeight }
    var colorSpace: String { capturedFrame.colorSpace }
    var imageRange: String { capturedFrame.imageRange }
    var cropInSensorPixels: FrameCrop { capturedFrame.cropInSensorPixels }
    var intrinsicsEncodedPixels: FrameIntrinsics { capturedFrame.intrinsicsEncodedPixels }
    var encodedFromSensor: [Double] { capturedFrame.encodedFromSensor }
    var worldFromCamera: [Double] { capturedFrame.worldFromCamera }
    var trackingState: String { capturedFrame.trackingState }
    var trackingReason: String { capturedFrame.trackingReason }
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
