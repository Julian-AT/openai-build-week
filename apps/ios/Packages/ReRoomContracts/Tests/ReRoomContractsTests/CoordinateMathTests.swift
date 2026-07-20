import Foundation
import Testing

@testable import ReRoomContracts

@Suite("CoordinateMathTests")
struct CoordinateMathTests {
    @Test(
        "FX-COORD-001 accepted coordinate cases match exact oracle artifacts",
        arguments: [
            "coord.correction-forward",
            "coord.crop-scale-rotate",
            "coord.float-max",
            "coord.half-pixel",
            "coord.opencv-conversion",
            "coord.project-center",
        ]
    )
    func acceptedCoordinateOracle(caseID: String) throws {
        let fixture = try CoordinateFixture.load()
        let input = try fixture.read("inputs/\(caseID).json")
        let expected = try fixture.read("expected/\(caseID).json")

        #expect(try RRCoordinateMath.evaluate(jsonData: input) == expected)
    }

    @Test(
        "FX-COORD-001 invalid cases preserve stable rejection classes",
        arguments: [
            ("coord.correction-equal-version", CoordinateMathRejection.coordinateInvalid),
            ("coord.float-overflow", CoordinateMathRejection.numericOutOfRange),
            ("coord.rigid-reflection", CoordinateMathRejection.coordinateInvalid),
        ]
    )
    func rejectedCoordinateOracle(caseID: String, expected: CoordinateMathRejection) throws {
        let input = try CoordinateFixture.load().read("inputs/\(caseID).json")

        #expect(throws: expected) {
            try RRCoordinateMath.evaluate(jsonData: input)
        }
    }

    @Test("coordinate fixture case order is stable and lexicographic")
    func coordinateCaseOrder() throws {
        let manifest = try CoordinateFixture.load().jsonObject("manifest.json")
        let cases = try #require(manifest["cases"] as? [[String: Any]])
        let coordinateIDs = try cases.compactMap { item -> String? in
            let caseID = try #require(item["case_id"] as? String)
            return caseID.hasPrefix("coord.") ? caseID : nil
        }

        #expect(coordinateIDs == coordinateIDs.sorted())
    }

    @Test("RR-FLOAT-1 equality uses inclusive thresholds and rejects outside neighbors")
    func inclusiveAdjacencyThresholds() throws {
        #expect(try RRCoordinateMath.scalarEqual(0, 0.000_01))
        #expect(try !RRCoordinateMath.scalarEqual(0, 0.000_010_1))
        #expect(try RRCoordinateMath.translationEqual(100, 100.000_1))
        #expect(try !RRCoordinateMath.translationEqual(100, 100.000_11))
        #expect(try RRCoordinateMath.transformedIntrinsicsEqual(1_000, 1_000.001))
        #expect(try !RRCoordinateMath.transformedIntrinsicsEqual(1_000, 1_000.001_1))
    }

    @Test(
        "intrinsics follow row-major column-vector orientation crop and scale order",
        arguments: [
            IntrinsicsScenario(
                name: "identity",
                transform: [1, 0, 0, 0, 1, 0, 0, 0, 1],
                size: [1_280, 720],
                expected: RRIntrinsics(fx: 1_000, fy: 800, cx: 640, cy: 360)
            ),
            IntrinsicsScenario(
                name: "rotate-and-half-scale",
                transform: [0, 0.5, 0, -0.5, 0, 640, 0, 0, 1],
                size: [360, 640],
                expected: RRIntrinsics(fx: 400, fy: 500, cx: 180, cy: 320)
            ),
            IntrinsicsScenario(
                name: "crop",
                transform: [1, 0, -100, 0, 1, -50, 0, 0, 1],
                size: [1_080, 620],
                expected: RRIntrinsics(fx: 1_000, fy: 800, cx: 540, cy: 310)
            ),
            IntrinsicsScenario(
                name: "rotate-180-and-half-scale",
                transform: [-0.5, 0, 640, 0, -0.5, 360, 0, 0, 1],
                size: [640, 360],
                expected: RRIntrinsics(fx: 500, fy: 400, cx: 320, cy: 180)
            ),
        ]
    )
    func orientationCropScale(scenario: IntrinsicsScenario) throws {
        let result = try RRCoordinateMath.transformIntrinsics(
            sensor: RRIntrinsics(fx: 1_000, fy: 800, cx: 640, cy: 360),
            encodedFromSensor: scenario.transform,
            encodedSize: scenario.size,
            orientation: "up"
        )

        #expect(result.intrinsics == scenario.expected)
        #expect(result.encodedSize == scenario.size)
        #expect(result.orientation == "up")
    }

    @Test(
        "null empty wrong-length singular and malformed values reject rather than default",
        arguments: [
            #"{"operation":"validate_rigid_transform","values":null}"#,
            #"{"operation":"validate_rigid_transform","values":[]}"#,
            #"{"operation":"validate_rigid_transform","values":[1]}"#,
            #"{"operation":"validate_rigid_transform","values":[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1]}"#,
            #"{"operation":"project","intrinsics":{"fx":1,"fy":1,"cx":0,"cy":0},"camera_point":[],"pixel_center":"half_integer"}"#,
            #"{"operation":"project","intrinsics":{"fx":1,"fy":1,"cx":0,"cy":0},"camera_point":[0,0,0],"pixel_center":"half_integer"}"#,
            #"{"operation":"transform_intrinsics","sensor_intrinsics":{"fx":1,"fy":1,"cx":0,"cy":0},"encoded_from_sensor":[1,0,0,0,1,0,1,0,1],"encoded_size":[1,1],"orientation":"up"}"#,
            #"{"operation":"transform_intrinsics","sensor_intrinsics":{"fx":1,"fy":1,"cx":0,"cy":0},"encoded_from_sensor":[1,0,0,0,1,0,0,0,1],"encoded_size":[1,1],"orientation":"left"}"#,
        ]
    )
    func malformedInputs(document: String) {
        #expect(throws: CoordinateMathRejection.coordinateInvalid) {
            try RRCoordinateMath.evaluate(jsonData: Data(document.utf8))
        }
    }

    @Test("Frozen RR-COORD runtime boundaries match Swift")
    func frozenRuntimeBoundaries() throws {
        let fixtureURL = try CoordinateFixture.repositoryRoot()
            .appendingPathComponent("tools/verify/fixtures/rr-coord-runtime-boundaries.json")
        let root = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: Any]
        )
        let cases = try #require(root["cases"] as? [[String: Any]])
        for fixtureCase in cases {
            let input = try #require(fixtureCase["input"])
            let data = try JSONSerialization.data(withJSONObject: input, options: [.sortedKeys])
            if fixtureCase["expected"] as? String == "accept" {
                _ = try RRCoordinateMath.evaluate(jsonData: data)
            } else {
                #expect(throws: CoordinateMathRejection.coordinateInvalid) {
                    try RRCoordinateMath.evaluate(jsonData: data)
                }
            }
        }
    }

    @Test(
        "non-finite and binary32-overflow scalars reject",
        arguments: [Double.nan, .infinity, -.infinity, 3.402_823_6e38]
    )
    func nonFiniteScalars(value: Double) {
        #expect(throws: CoordinateMathRejection.numericOutOfRange) {
            try RRCoordinateMath.quantize(value)
        }
    }

    @Test("projection and correction retain column-vector direction and visibility")
    func projectionAndCorrectionDirection() throws {
        let behind = try RRCoordinateMath.project(
            cameraPoint: [0, 0, 1],
            intrinsics: RRIntrinsics(fx: 500, fy: 500, cx: 319.5, cy: 239.5)
        )
        let corrected = try RRCoordinateMath.applyWorldCorrection(
            fromVersion: 1,
            toVersion: 2,
            transform: [1, 0, 0, 1, 0, 1, 0, 2, 0, 0, 1, 3, 0, 0, 0, 1],
            point: [1, 1, 1, 1]
        )

        #expect(behind.encodedPixel == [319.5, 239.5])
        #expect(!behind.visible)
        #expect(corrected == [2, 3, 4, 1])
    }
}

struct IntrinsicsScenario: Sendable, CustomTestStringConvertible {
    let name: String
    let transform: [Double]
    let size: [Int]
    let expected: RRIntrinsics

    var testDescription: String { name }
}

private struct CoordinateFixture {
    let root: URL

    static func load() throws -> CoordinateFixture {
        CoordinateFixture(root: try repositoryRoot().appendingPathComponent(
            "fixtures/policies/RR-COORD-1/rev-001"
        ))
    }

    static func repositoryRoot() throws -> URL {
        let fileManager = FileManager.default
        var cursor = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !fileManager.fileExists(atPath: cursor.appendingPathComponent(".git").path) {
            let parent = cursor.deletingLastPathComponent()
            guard parent.path != cursor.path else { throw CoordinateFixtureError.repositoryRootNotFound }
            cursor = parent
        }
        return cursor
    }

    func read(_ relativePath: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent(relativePath))
    }

    func jsonObject(_ relativePath: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: read(relativePath)) as? [String: Any])
    }
}

private enum CoordinateFixtureError: Error {
    case repositoryRootNotFound
}
