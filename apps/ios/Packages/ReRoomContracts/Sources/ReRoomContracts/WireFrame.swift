import Foundation

public enum WireFrameRejection: String, Error, Equatable, Sendable {
    case wireMagic = "wire_magic"
    case wireVersion = "wire_version"
    case wireFlags = "wire_flags"
    case wireLength = "wire_length"
    case wireSequence = "wire_sequence"
    case wireTruncated = "wire_truncated"
    case wireTrailingBytes = "wire_trailing_bytes"
    case digestMismatch = "digest_mismatch"
}

public struct RRFPDecodedFrame: Equatable, Sendable {
    public let headerJSON: Data
    public let payload: Data
    public let captureSequence: UInt64

    public init(headerJSON: Data, payload: Data, captureSequence: UInt64) {
        self.headerJSON = headerJSON
        self.payload = payload
        self.captureSequence = captureSequence
    }
}

public enum RRFPWireFrame {
    public static let fixedHeaderBytes = 24
    public static let maximumJSONHeaderBytes = 65_536
    public static let maximumPayloadBytes = 16_777_216

    public static func encode(headerJSON: Data, payload: Data) throws -> Data {
        let canonicalHeader: Data
        let header: CanonicalJSONValue
        do {
            canonicalHeader = try CanonicalJSON.canonicalize(jsonData: headerJSON)
            header = try CanonicalJSON.parse(canonicalHeader)
        } catch {
            throw WireFrameRejection.wireLength
        }

        guard canonicalHeader.count <= maximumJSONHeaderBytes,
              payload.count <= maximumPayloadBytes
        else {
            throw WireFrameRejection.wireLength
        }
        let fields = try requiredFields(in: header)
        guard fields.payloadLength == payload.count else {
            throw WireFrameRejection.wireLength
        }
        guard fields.payloadSHA256 == CanonicalJSON.sha256Hex(payload) else {
            throw WireFrameRejection.digestMismatch
        }

        var output = Data("RRFP".utf8)
        output.append(contentsOf: [1, 0, 0, 0])
        output.append(contentsOf: UInt32(canonicalHeader.count).bigEndianBytes)
        output.append(contentsOf: UInt32(payload.count).bigEndianBytes)
        output.append(contentsOf: fields.captureSequence.bigEndianBytes)
        output.append(canonicalHeader)
        output.append(payload)
        return output
    }

    public static func decode(_ wire: Data) throws -> RRFPDecodedFrame {
        guard wire.count >= fixedHeaderBytes else { throw WireFrameRejection.wireTruncated }
        guard wire.prefix(4) == Data("RRFP".utf8) else { throw WireFrameRejection.wireMagic }
        guard wire[4] == 1, wire[5] == 0 else { throw WireFrameRejection.wireVersion }
        guard wire[6] == 0, wire[7] == 0 else { throw WireFrameRejection.wireFlags }

        let headerLength = Int(wire.readUInt32BE(at: 8))
        let payloadLength = Int(wire.readUInt32BE(at: 12))
        let captureSequence = wire.readUInt64BE(at: 16)
        guard headerLength <= maximumJSONHeaderBytes,
              payloadLength <= maximumPayloadBytes
        else {
            throw WireFrameRejection.wireLength
        }
        guard wire.count >= fixedHeaderBytes + headerLength else {
            throw WireFrameRejection.wireTruncated
        }

        let headerJSON = wire.subdata(in: fixedHeaderBytes..<(fixedHeaderBytes + headerLength))
        let header: CanonicalJSONValue
        do {
            header = try CanonicalJSON.parse(headerJSON)
            guard try CanonicalJSON.canonicalize(jsonData: headerJSON) == headerJSON else {
                throw WireFrameRejection.wireLength
            }
        } catch {
            throw WireFrameRejection.wireLength
        }
        let fields = try requiredFields(in: header)
        guard fields.payloadLength == payloadLength else {
            throw WireFrameRejection.wireLength
        }
        guard fields.captureSequence == captureSequence else {
            throw WireFrameRejection.wireSequence
        }

        let expectedLength = fixedHeaderBytes + headerLength + payloadLength
        guard wire.count >= expectedLength else { throw WireFrameRejection.wireTruncated }
        guard wire.count == expectedLength else { throw WireFrameRejection.wireTrailingBytes }

        let payload = wire.subdata(in: (fixedHeaderBytes + headerLength)..<expectedLength)
        guard fields.payloadSHA256 == CanonicalJSON.sha256Hex(payload) else {
            throw WireFrameRejection.digestMismatch
        }
        return RRFPDecodedFrame(
            headerJSON: headerJSON,
            payload: payload,
            captureSequence: captureSequence
        )
    }

    private static func requiredFields(
        in header: CanonicalJSONValue
    ) throws -> (payloadLength: Int, captureSequence: UInt64, payloadSHA256: String) {
        guard let root = header.object,
              let captureSequence = root["capture_sequence"]?.exactNonnegativeUInt64,
              let payloadSHA256 = root["payload_sha256"]?.string,
              payloadSHA256.count == 64,
              payloadSHA256.utf8.allSatisfy({
                  (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
              }),
              let image = root["image"]?.object,
              let payload = image["payload"]?.object,
              let payloadLengthValue = payload["byte_length"]?.exactNonnegativeUInt64,
              payloadLengthValue <= UInt64(maximumPayloadBytes)
        else {
            throw WireFrameRejection.wireLength
        }
        return (Int(payloadLengthValue), captureSequence, payloadSHA256)
    }
}

private extension Data {
    func readUInt32BE(at offset: Int) -> UInt32 {
        self[offset..<(offset + 4)].reduce(0) { ($0 << 8) | UInt32($1) }
    }

    func readUInt64BE(at offset: Int) -> UInt64 {
        self[offset..<(offset + 8)].reduce(0) { ($0 << 8) | UInt64($1) }
    }
}

private extension FixedWidthInteger {
    var bigEndianBytes: [UInt8] {
        withUnsafeBytes(of: bigEndian) { Array($0) }
    }
}
