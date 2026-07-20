import Foundation

public enum CoordinateMathRejection: String, Error, Equatable, Sendable {
    case coordinateInvalid = "coordinate_invalid"
    case numericOutOfRange = "numeric_out_of_range"
}

public struct RRIntrinsics: Equatable, Sendable {
    public let fx: Double
    public let fy: Double
    public let cx: Double
    public let cy: Double

    public init(fx: Double, fy: Double, cx: Double, cy: Double) {
        self.fx = fx
        self.fy = fy
        self.cx = cx
        self.cy = cy
    }
}

public struct RRProjection: Equatable, Sendable {
    public let encodedPixel: [Double]
    public let visible: Bool

    public init(encodedPixel: [Double], visible: Bool) {
        self.encodedPixel = encodedPixel
        self.visible = visible
    }
}

public struct RRTransformedIntrinsics: Equatable, Sendable {
    public let intrinsics: RRIntrinsics
    public let encodedSize: [Int]
    public let orientation: String

    public init(intrinsics: RRIntrinsics, encodedSize: [Int], orientation: String) {
        self.intrinsics = intrinsics
        self.encodedSize = encodedSize
        self.orientation = orientation
    }
}

public enum RRCoordinateMath {
    public static let float32Maximum = 3.402_823_466_385_288_6e38
    public static let scalarAbsoluteTolerance = 1e-5
    public static let scalarRelativeTolerance = 1e-6
    public static let translationAbsoluteTolerance = 1e-4
    public static let transformedIntrinsicsAbsoluteTolerance = 1e-3
    public static let rigidTransformTolerance = 1e-4
    public static let homogeneousRowTolerance = 1e-6

    public static func quantize(_ value: Double) throws -> Float {
        guard value.isFinite, abs(value) <= float32Maximum else {
            throw CoordinateMathRejection.numericOutOfRange
        }
        let result = Float(value)
        guard result.isFinite else { throw CoordinateMathRejection.numericOutOfRange }
        return result
    }

    public static func scalarEqual(_ left: Double, _ right: Double) throws -> Bool {
        let a = Double(try quantize(left))
        let b = Double(try quantize(right))
        return abs(a - b) <= scalarAbsoluteTolerance
            + scalarRelativeTolerance * max(abs(a), abs(b))
    }

    public static func translationEqual(_ left: Double, _ right: Double) throws -> Bool {
        let a = Double(try quantize(left))
        let b = Double(try quantize(right))
        return try scalarEqual(a, b)
            && abs(a - b) <= translationAbsoluteTolerance
    }

    public static func transformedIntrinsicsEqual(
        _ left: Double,
        _ right: Double
    ) throws -> Bool {
        let a = Double(try quantize(left))
        let b = Double(try quantize(right))
        return try scalarEqual(a, b)
            && abs(a - b) <= transformedIntrinsicsAbsoluteTolerance
    }

    public static func project(
        cameraPoint: [Double],
        intrinsics: RRIntrinsics
    ) throws -> RRProjection {
        let point = try quantized(cameraPoint, count: 3)
        let fx = Double(try quantize(intrinsics.fx))
        let fy = Double(try quantize(intrinsics.fy))
        let cx = Double(try quantize(intrinsics.cx))
        let cy = Double(try quantize(intrinsics.cy))
        guard fx > 0, fy > 0, point[2] != 0 else {
            throw CoordinateMathRejection.coordinateInvalid
        }
        return RRProjection(
            encodedPixel: [
                normalizedZero(fx * (point[0] / point[2]) + cx),
                normalizedZero(fy * (point[1] / point[2]) + cy),
            ],
            visible: point[2] < 0
        )
    }

    public static func transformIntrinsics(
        sensor: RRIntrinsics,
        encodedFromSensor: [Double],
        encodedSize: [Int],
        orientation: String
    ) throws -> RRTransformedIntrinsics {
        guard orientation == "up",
              encodedSize.count == 2,
              encodedSize.allSatisfy({ $0 > 0 })
        else {
            throw CoordinateMathRejection.coordinateInvalid
        }
        let transform = try quantized(encodedFromSensor, count: 9)
        guard abs(transform[6]) <= homogeneousRowTolerance,
              abs(transform[7]) <= homogeneousRowTolerance,
              abs(transform[8] - 1) <= homogeneousRowTolerance
        else {
            throw CoordinateMathRejection.coordinateInvalid
        }

        let fx = Double(try quantize(sensor.fx))
        let fy = Double(try quantize(sensor.fy))
        let cx = Double(try quantize(sensor.cx))
        let cy = Double(try quantize(sensor.cy))
        guard fx > 0, fy > 0 else { throw CoordinateMathRejection.coordinateInvalid }
        let camera = [fx, 0, cx, 0, fy, cy, 0, 0, 1]
        let encoded = multiplyMatrices(transform, camera, dimension: 3)
        let encodedFX = hypot(encoded[0], encoded[1])
        let encodedFY = hypot(encoded[3], encoded[4])
        guard encodedFX > 0, encodedFY > 0 else {
            throw CoordinateMathRejection.coordinateInvalid
        }

        return RRTransformedIntrinsics(
            intrinsics: RRIntrinsics(
                fx: normalizedZero(encodedFX),
                fy: normalizedZero(encodedFY),
                cx: normalizedZero(encoded[2]),
                cy: normalizedZero(encoded[5])
            ),
            encodedSize: encodedSize,
            orientation: "up"
        )
    }

    public static func validateRigidTransform(_ values: [Double]) throws -> [Double] {
        let matrix = try quantized(values, count: 16)
        let rotation = [
            matrix[0], matrix[1], matrix[2],
            matrix[4], matrix[5], matrix[6],
            matrix[8], matrix[9], matrix[10],
        ]

        var orthogonalitySquared = 0.0
        for row in 0..<3 {
            for column in 0..<3 {
                var dot = 0.0
                for index in 0..<3 {
                    dot += rotation[index * 3 + row] * rotation[index * 3 + column]
                }
                let difference = dot - (row == column ? 1 : 0)
                orthogonalitySquared += difference * difference
            }
        }
        guard sqrt(orthogonalitySquared) <= rigidTransformTolerance,
              abs(determinant3(rotation) - 1) <= rigidTransformTolerance
        else {
            throw CoordinateMathRejection.coordinateInvalid
        }

        let expectedLastRow = [0.0, 0.0, 0.0, 1.0]
        guard matrix[12..<16].enumerated().allSatisfy({ index, value in
            abs(value - expectedLastRow[index]) <= homogeneousRowTolerance
        }) else {
            throw CoordinateMathRejection.coordinateInvalid
        }
        return matrix
    }

    public static func applyWorldCorrection(
        fromVersion: Int,
        toVersion: Int,
        transform: [Double],
        point: [Double]
    ) throws -> [Double] {
        guard fromVersion >= 1, toVersion > fromVersion else {
            throw CoordinateMathRejection.coordinateInvalid
        }
        return multiplyMatrixVector(
            try validateRigidTransform(transform),
            try quantized(point, count: 4),
            dimension: 4
        )
    }

    public static func arkitToOpenCVCamera(
        cameraPoint: [Double],
        conversion: [Double]
    ) throws -> [Double] {
        let matrix = try validateRigidMatrix3(conversion)
        return multiplyMatrixVector(
            matrix,
            try quantized(cameraPoint, count: 3),
            dimension: 3
        )
    }

    public static func evaluate(jsonData: Data) throws -> Data {
        let document: CanonicalJSONValue
        do {
            document = try CanonicalJSON.parse(jsonData)
        } catch CanonicalJSONRejection.numericOutOfRange {
            throw CoordinateMathRejection.numericOutOfRange
        } catch {
            throw CoordinateMathRejection.coordinateInvalid
        }
        guard let root = document.object, let operation = root["operation"]?.string else {
            throw CoordinateMathRejection.coordinateInvalid
        }

        let result: CanonicalJSONValue
        switch operation {
        case "project":
            guard root["pixel_center"]?.string == "half_integer",
                  let intrinsics = try? intrinsics(from: root["intrinsics"]),
                  let point = try? numbers(from: root["camera_point"], count: 3)
            else {
                throw CoordinateMathRejection.coordinateInvalid
            }
            let projection = try project(cameraPoint: point, intrinsics: intrinsics)
            result = .object([
                "encoded_pixel": .array(projection.encodedPixel.map(CanonicalJSONValue.number)),
                "visible": .boolean(projection.visible),
            ])
        case "transform_intrinsics":
            guard let sensor = try? intrinsics(from: root["sensor_intrinsics"]),
                  let transform = try? numbers(from: root["encoded_from_sensor"], count: 9),
                  let size = try? integers(from: root["encoded_size"], count: 2),
                  let orientation = root["orientation"]?.string
            else {
                throw CoordinateMathRejection.coordinateInvalid
            }
            let transformed = try transformIntrinsics(
                sensor: sensor,
                encodedFromSensor: transform,
                encodedSize: size,
                orientation: orientation
            )
            let intrinsics = transformed.intrinsics
            let output = "{\"encoded_intrinsics\":{\"fx\":\(numberText(intrinsics.fx)),"
                + "\"fy\":\(numberText(intrinsics.fy)),\"cx\":\(numberText(intrinsics.cx)),"
                + "\"cy\":\(numberText(intrinsics.cy))},\"encoded_size\":["
                + transformed.encodedSize.map { String($0) }.joined(separator: ",")
                + "],\"orientation\":\"up\"}\n"
            return Data(output.utf8)
        case "arkit_to_opencv_camera":
            guard let point = try? numbers(from: root["camera_point"], count: 3),
                  let conversion = try? numbers(from: root["conversion"], count: 9)
            else {
                throw CoordinateMathRejection.coordinateInvalid
            }
            result = .object([
                "opencv_camera_point": .array(
                    try arkitToOpenCVCamera(cameraPoint: point, conversion: conversion)
                        .map(CanonicalJSONValue.number)
                )
            ])
        case "apply_world_correction":
            guard let from = root["from_world_frame_version"]?.exactPositiveInt,
                  let to = root["to_world_frame_version"]?.exactPositiveInt,
                  let transform = try? numbers(
                      from: root["to_from_from_transform"], count: 16
                  ),
                  let point = try? numbers(from: root["point_from"], count: 4)
            else {
                throw CoordinateMathRejection.coordinateInvalid
            }
            result = .object([
                "point_to": .array(
                    try applyWorldCorrection(
                        fromVersion: from,
                        toVersion: to,
                        transform: transform,
                        point: point
                    ).map(CanonicalJSONValue.number)
                )
            ])
        case "validate_rr_float":
            guard let value = root["value"]?.number else {
                throw CoordinateMathRejection.coordinateInvalid
            }
            let bits = try quantize(value).bitPattern
            result = .object(["binary32_hex": .string(String(format: "%08x", bits))])
        case "validate_rigid_transform":
            guard let values = try? numbers(from: root["values"], count: 16) else {
                throw CoordinateMathRejection.coordinateInvalid
            }
            _ = try validateRigidTransform(values)
            result = .object(["valid": .boolean(true)])
        default:
            throw CoordinateMathRejection.coordinateInvalid
        }

        return Data((result.canonicalText + "\n").utf8)
    }

    private static func intrinsics(from value: CanonicalJSONValue?) throws -> RRIntrinsics {
        guard let object = value?.object,
              let fx = object["fx"]?.number,
              let fy = object["fy"]?.number,
              let cx = object["cx"]?.number,
              let cy = object["cy"]?.number
        else {
            throw CoordinateMathRejection.coordinateInvalid
        }
        return RRIntrinsics(fx: fx, fy: fy, cx: cx, cy: cy)
    }

    private static func numberText(_ value: Double) -> String {
        CanonicalJSONValue.number(value).canonicalText
    }

    private static func numbers(
        from value: CanonicalJSONValue?,
        count: Int
    ) throws -> [Double] {
        guard let array = value?.array, array.count == count else {
            throw CoordinateMathRejection.coordinateInvalid
        }
        return try array.map { item in
            guard let number = item.number else {
                throw CoordinateMathRejection.coordinateInvalid
            }
            return number
        }
    }

    private static func integers(
        from value: CanonicalJSONValue?,
        count: Int
    ) throws -> [Int] {
        guard let array = value?.array, array.count == count else {
            throw CoordinateMathRejection.coordinateInvalid
        }
        return try array.map { item in
            guard let integer = item.exactPositiveInt else {
                throw CoordinateMathRejection.coordinateInvalid
            }
            return integer
        }
    }

    private static func quantized(_ values: [Double], count: Int) throws -> [Double] {
        guard values.count == count else { throw CoordinateMathRejection.coordinateInvalid }
        return try values.map { Double(try quantize($0)) }
    }

    private static func multiplyMatrixVector(
        _ matrix: [Double],
        _ vector: [Double],
        dimension: Int
    ) -> [Double] {
        (0..<dimension).map { row in
            normalizedZero(
                (0..<dimension).reduce(0) { partial, column in
                    partial + matrix[row * dimension + column] * vector[column]
                }
            )
        }
    }

    private static func multiplyMatrices(
        _ left: [Double],
        _ right: [Double],
        dimension: Int
    ) -> [Double] {
        (0..<(dimension * dimension)).map { flatIndex in
            let row = flatIndex / dimension
            let column = flatIndex % dimension
            return (0..<dimension).reduce(0) { partial, index in
                partial + left[row * dimension + index] * right[index * dimension + column]
            }
        }
    }

    private static func validateRigidMatrix3(_ values: [Double]) throws -> [Double] {
        let matrix = try quantized(values, count: 9)
        var orthogonalitySquared = 0.0
        for row in 0..<3 {
            for column in 0..<3 {
                var dot = 0.0
                for index in 0..<3 {
                    dot += matrix[index * 3 + row] * matrix[index * 3 + column]
                }
                let difference = dot - (row == column ? 1 : 0)
                orthogonalitySquared += difference * difference
            }
        }
        guard sqrt(orthogonalitySquared) <= rigidTransformTolerance,
              abs(determinant3(matrix) - 1) <= rigidTransformTolerance
        else {
            throw CoordinateMathRejection.coordinateInvalid
        }
        return matrix
    }

    private static func determinant3(_ matrix: [Double]) -> Double {
        matrix[0] * (matrix[4] * matrix[8] - matrix[5] * matrix[7])
            - matrix[1] * (matrix[3] * matrix[8] - matrix[5] * matrix[6])
            + matrix[2] * (matrix[3] * matrix[7] - matrix[4] * matrix[6])
    }

    private static func normalizedZero(_ value: Double) -> Double {
        value == 0 ? 0 : value
    }
}

private extension CanonicalJSONValue {
    var number: Double? {
        guard case .number(let value) = self else { return nil }
        return value
    }

    var array: [CanonicalJSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    var exactPositiveInt: Int? {
        guard let value = exactNonnegativeUInt64,
              value >= 1,
              value <= UInt64(Int.max)
        else {
            return nil
        }
        return Int(value)
    }
}
