import Foundation
import Testing

@testable import ReRoomContracts

@Suite("WireFrameTests")
struct WireFrameTests {
    @Test("RRFP-WIRE-1 encoder emits the exact trailer-less frozen bytes")
    func exactWireEncoding() throws {
        let fixture = try WireFixture.load()
        let header = try fixture.repositoryData(
            "fixtures/contracts/1.0.0/rev-001/instances/con001.frame-packet.valid.json"
        )
        let payload = Data("test".utf8)
        let expected = try Data(hexadecimal: fixture.text("expected/wire.valid.hex"))

        let encoded = try RRFPWireFrame.encode(headerJSON: header, payload: payload)

        #expect(encoded == expected)
        #expect(encoded.count == RRFPWireFrame.fixedHeaderBytes + 1_823 + payload.count)
    }

    @Test("RRFP-WIRE-1 decoder returns the canonical header payload and capture sequence")
    func exactWireDecoding() throws {
        let fixture = try WireFixture.load()
        let wire = try Data(hexadecimal: fixture.text("expected/wire.valid.hex"))
        let decoded = try RRFPWireFrame.decode(wire)

        #expect(decoded.payload == Data("test".utf8))
        #expect(decoded.captureSequence == 0)
        #expect(decoded.headerJSON.count == 1_823)
        #expect(try CanonicalJSON.canonicalize(jsonData: decoded.headerJSON) == decoded.headerJSON)
    }

    @Test(
        "all frozen RRFP mutations reject with their stable class",
        arguments: [
            ("wire.bad-magic", WireFrameRejection.wireMagic),
            ("wire.bad-version", WireFrameRejection.wireVersion),
            ("wire.header-length-mismatch", WireFrameRejection.wireLength),
            ("wire.header-over-limit", WireFrameRejection.wireLength),
            ("wire.nonzero-flags", WireFrameRejection.wireFlags),
            ("wire.payload-length-mismatch", WireFrameRejection.wireLength),
            ("wire.payload-over-limit", WireFrameRejection.wireLength),
            ("wire.payload-tamper", WireFrameRejection.digestMismatch),
            ("wire.sequence-mismatch", WireFrameRejection.wireSequence),
            ("wire.trailing-byte", WireFrameRejection.wireTrailingBytes),
            ("wire.truncated", WireFrameRejection.wireTruncated),
        ]
    )
    func frozenWireRejections(caseID: String, expected: WireFrameRejection) throws {
        let fixture = try WireFixture.load()
        let descriptor = try fixture.jsonObject("inputs/\(caseID).json")
        let base = try #require(descriptor["base"] as? String)
        let mutations = try #require(descriptor["mutations"] as? [[String: Any]])
        let wire = try Data(hexadecimal: fixture.text(base))
        let mutated = try wire.applying(mutations)

        #expect(throws: expected) {
            try RRFPWireFrame.decode(mutated)
        }
    }

    @Test("wire fixture case order remains lexicographic and the frame has no trailer")
    func wireManifestAndTrailerAuthority() throws {
        let fixture = try WireFixture.load()
        let manifest = try fixture.jsonObject("manifest.json")
        let cases = try #require(manifest["cases"] as? [[String: Any]])
        let wireIDs = try cases.compactMap { item -> String? in
            let caseID = try #require(item["case_id"] as? String)
            return caseID.hasPrefix("wire.") ? caseID : nil
        }
        let wire = try Data(hexadecimal: fixture.text("expected/wire.valid.hex"))
        let headerLength = Int(wire.readUInt32BE(at: 8))
        let payloadLength = Int(wire.readUInt32BE(at: 12))

        #expect(wireIDs == wireIDs.sorted())
        #expect(wire.count == 24 + headerLength + payloadLength)
    }
}

private struct WireFixture {
    let repositoryRoot: URL
    let root: URL

    static func load() throws -> WireFixture {
        let repositoryRoot = try findRepositoryRoot()
        return WireFixture(
            repositoryRoot: repositoryRoot,
            root: repositoryRoot.appendingPathComponent("fixtures/policies/RR-COORD-1/rev-001")
        )
    }

    func data(_ relativePath: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent(relativePath))
    }

    func repositoryData(_ relativePath: String) throws -> Data {
        try Data(contentsOf: repositoryRoot.appendingPathComponent(relativePath))
    }

    func text(_ relativePath: String) throws -> String {
        String(decoding: try data(relativePath), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func jsonObject(_ relativePath: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data(relativePath)) as? [String: Any])
    }

    private static func findRepositoryRoot() throws -> URL {
        let fileManager = FileManager.default
        var cursor = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !fileManager.fileExists(atPath: cursor.appendingPathComponent(".git").path) {
            let parent = cursor.deletingLastPathComponent()
            guard parent.path != cursor.path else { throw WireFixtureError.repositoryRootNotFound }
            cursor = parent
        }
        return cursor
    }
}

private enum WireFixtureError: Error {
    case repositoryRootNotFound
    case invalidHexadecimal
    case invalidMutation
}

private extension Data {
    init(hexadecimal: String) throws {
        guard hexadecimal.count.isMultiple(of: 2) else { throw WireFixtureError.invalidHexadecimal }
        var bytes = [UInt8]()
        bytes.reserveCapacity(hexadecimal.count / 2)
        var index = hexadecimal.startIndex
        while index < hexadecimal.endIndex {
            let next = hexadecimal.index(index, offsetBy: 2)
            guard let byte = UInt8(hexadecimal[index..<next], radix: 16) else {
                throw WireFixtureError.invalidHexadecimal
            }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }

    func readUInt32BE(at offset: Int) -> UInt32 {
        self[offset..<(offset + 4)].reduce(0) { ($0 << 8) | UInt32($1) }
    }

    func applying(_ mutations: [[String: Any]]) throws -> Data {
        var output = self
        for mutation in mutations {
            let operation = try #require(mutation["op"] as? String)
            switch operation {
            case "replace_byte":
                let offset = try #require(mutation["offset"] as? Int)
                let value = try #require(mutation["value_hex"] as? String)
                let byte = try #require(UInt8(value, radix: 16))
                output[offset] = byte
            case "replace_u32be":
                let offset = try #require(mutation["offset"] as? Int)
                let value = try #require(mutation["value"] as? UInt32)
                output.replaceSubrange(offset..<(offset + 4), with: value.bigEndianBytes)
            case "replace_u64be":
                let offset = try #require(mutation["offset"] as? Int)
                let value = try #require(mutation["value"] as? UInt64)
                output.replaceSubrange(offset..<(offset + 8), with: value.bigEndianBytes)
            case "append_hex":
                output.append(try Data(hexadecimal: try #require(mutation["value_hex"] as? String)))
            case "truncate":
                output = output.prefix(try #require(mutation["byte_length"] as? Int))
            default:
                throw WireFixtureError.invalidMutation
            }
        }
        return output
    }
}

private extension FixedWidthInteger {
    var bigEndianBytes: [UInt8] {
        withUnsafeBytes(of: bigEndian) { Array($0) }
    }
}
