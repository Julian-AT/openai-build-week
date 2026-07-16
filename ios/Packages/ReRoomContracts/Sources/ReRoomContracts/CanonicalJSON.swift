import CryptoKit
import Foundation

public enum CanonicalJSONRejection: String, Error, Equatable, Sendable {
    case duplicateName = "duplicate_name"
    case invalidUnicode = "invalid_unicode"
    case jsonParse = "json_parse"
    case numericOutOfRange = "numeric_out_of_range"
}

public enum CanonicalJSON {
    public static let maximumDocumentBytes = 33_554_432
    public static let maximumDocumentDepth = 64

    public static func canonicalize(
        jsonData: Data,
        maximumBytes: Int = maximumDocumentBytes,
        maximumDepth: Int = maximumDocumentDepth
    ) throws -> Data {
        let value = try parse(
            jsonData,
            maximumBytes: maximumBytes,
            maximumDepth: maximumDepth
        )
        return Data(value.canonicalText.utf8)
    }

    public static func digest(
        jsonData: Data,
        maximumBytes: Int = maximumDocumentBytes,
        maximumDepth: Int = maximumDocumentDepth
    ) throws -> String {
        sha256Hex(
            try canonicalize(
                jsonData: jsonData,
                maximumBytes: maximumBytes,
                maximumDepth: maximumDepth
            )
        )
    }

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func parse(
        _ data: Data,
        maximumBytes: Int = maximumDocumentBytes,
        maximumDepth: Int = maximumDocumentDepth
    ) throws -> CanonicalJSONValue {
        guard (1...Self.maximumDocumentBytes).contains(maximumBytes),
              (1...Self.maximumDocumentDepth).contains(maximumDepth),
              data.count <= maximumBytes
        else { throw CanonicalJSONRejection.jsonParse }
        guard String(data: data, encoding: .utf8) != nil else {
            throw CanonicalJSONRejection.invalidUnicode
        }

        var parser = CanonicalJSONParser(bytes: Array(data), maximumDepth: maximumDepth)
        return try parser.parseDocument()
    }
}

indirect enum CanonicalJSONValue: Equatable, Sendable {
    case null
    case boolean(Bool)
    case number(Double)
    case string(String)
    case array([CanonicalJSONValue])
    case object([String: CanonicalJSONValue])

    var canonicalText: String {
        switch self {
        case .null:
            return "null"
        case .boolean(let value):
            return value ? "true" : "false"
        case .number(let value):
            return Self.canonicalNumber(value)
        case .string(let value):
            return Self.quoted(value)
        case .array(let values):
            return "[" + values.map(\.canonicalText).joined(separator: ",") + "]"
        case .object(let object):
            let keys = object.keys.sorted { left, right in
                left.utf16.lexicographicallyPrecedes(right.utf16)
            }
            return "{" + keys.map { key in
                Self.quoted(key) + ":" + object[key]!.canonicalText
            }.joined(separator: ",") + "}"
        }
    }

    var object: [String: CanonicalJSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var string: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var exactNonnegativeUInt64: UInt64? {
        guard case .number(let value) = self,
              value.isFinite,
              value >= 0,
              value <= 9_007_199_254_740_991,
              value.rounded(.towardZero) == value
        else {
            return nil
        }
        return UInt64(value)
    }

    private static func canonicalNumber(_ value: Double) -> String {
        if value == 0 { return "0" }

        let shortest = String(value).lowercased()
        guard let marker = shortest.firstIndex(of: "e") else {
            return shortest.hasSuffix(".0") ? String(shortest.dropLast(2)) : shortest
        }

        let mantissa = String(shortest[..<marker])
        let exponentText = String(shortest[shortest.index(after: marker)...])
        let exponent = Int(exponentText)!
        if (-6...20).contains(exponent) {
            return expandScientific(mantissa: mantissa, exponent: exponent)
        }

        let sign = exponent >= 0 ? "+" : "-"
        return mantissa + "e" + sign + String(abs(exponent))
    }

    private static func expandScientific(mantissa: String, exponent: Int) -> String {
        let negative = mantissa.hasPrefix("-")
        let unsigned = negative ? String(mantissa.dropFirst()) : mantissa
        let pieces = unsigned.split(separator: ".", omittingEmptySubsequences: false)
        let integerDigits = String(pieces[0])
        let fractionalDigits = pieces.count == 2 ? String(pieces[1]) : ""
        let digits = integerDigits + fractionalDigits
        let decimalIndex = integerDigits.count + exponent

        let body: String
        if decimalIndex <= 0 {
            body = "0." + String(repeating: "0", count: -decimalIndex) + digits
        } else if decimalIndex >= digits.count {
            body = digits + String(repeating: "0", count: decimalIndex - digits.count)
        } else {
            let split = digits.index(digits.startIndex, offsetBy: decimalIndex)
            body = String(digits[..<split]) + "." + String(digits[split...])
        }
        return negative ? "-" + body : body
    }

    private static func quoted(_ value: String) -> String {
        var output = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x08: output += "\\b"
            case 0x09: output += "\\t"
            case 0x0a: output += "\\n"
            case 0x0c: output += "\\f"
            case 0x0d: output += "\\r"
            case 0x22: output += "\\\""
            case 0x5c: output += "\\\\"
            case 0x00...0x1f: output += String(format: "\\u%04x", scalar.value)
            default: output.unicodeScalars.append(scalar)
            }
        }
        output += "\""
        return output
    }
}

private struct CanonicalJSONParser {
    let bytes: [UInt8]
    let maximumDepth: Int
    var index = 0

    mutating func parseDocument() throws -> CanonicalJSONValue {
        skipWhitespace()
        let value = try parseValue(depth: 0)
        skipWhitespace()
        guard index == bytes.count else { throw CanonicalJSONRejection.jsonParse }
        return value
    }

    private mutating func parseValue(depth: Int) throws -> CanonicalJSONValue {
        guard depth <= maximumDepth, index < bytes.count else {
            throw CanonicalJSONRejection.jsonParse
        }
        switch bytes[index] {
        case 0x6e:
            try consume("null")
            return .null
        case 0x74:
            try consume("true")
            return .boolean(true)
        case 0x66:
            try consume("false")
            return .boolean(false)
        case 0x22:
            return .string(try parseString())
        case 0x5b:
            return try parseArray(depth: depth)
        case 0x7b:
            return try parseObject(depth: depth)
        case 0x2d, 0x30...0x39:
            return .number(try parseNumber())
        default:
            throw CanonicalJSONRejection.jsonParse
        }
    }

    private mutating func parseArray(depth: Int) throws -> CanonicalJSONValue {
        index += 1
        skipWhitespace()
        if consumeIf(0x5d) { return .array([]) }

        var values = [CanonicalJSONValue]()
        while true {
            values.append(try parseValue(depth: depth + 1))
            skipWhitespace()
            if consumeIf(0x5d) { return .array(values) }
            guard consumeIf(0x2c) else { throw CanonicalJSONRejection.jsonParse }
            skipWhitespace()
        }
    }

    private mutating func parseObject(depth: Int) throws -> CanonicalJSONValue {
        index += 1
        skipWhitespace()
        if consumeIf(0x7d) { return .object([:]) }

        var object = [String: CanonicalJSONValue]()
        while true {
            guard index < bytes.count, bytes[index] == 0x22 else {
                throw CanonicalJSONRejection.jsonParse
            }
            let key = try parseString()
            guard object[key] == nil else { throw CanonicalJSONRejection.duplicateName }
            skipWhitespace()
            guard consumeIf(0x3a) else { throw CanonicalJSONRejection.jsonParse }
            skipWhitespace()
            object[key] = try parseValue(depth: depth + 1)
            skipWhitespace()
            if consumeIf(0x7d) { return .object(object) }
            guard consumeIf(0x2c) else { throw CanonicalJSONRejection.jsonParse }
            skipWhitespace()
        }
    }

    private mutating func parseString() throws -> String {
        guard consumeIf(0x22) else { throw CanonicalJSONRejection.jsonParse }
        var output = Data()

        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            switch byte {
            case 0x22:
                guard let value = String(data: output, encoding: .utf8) else {
                    throw CanonicalJSONRejection.invalidUnicode
                }
                return value
            case 0x00...0x1f:
                throw CanonicalJSONRejection.jsonParse
            case 0x5c:
                guard index < bytes.count else { throw CanonicalJSONRejection.jsonParse }
                let escaped = bytes[index]
                index += 1
                switch escaped {
                case 0x22, 0x2f, 0x5c: output.append(escaped)
                case 0x62: output.append(0x08)
                case 0x66: output.append(0x0c)
                case 0x6e: output.append(0x0a)
                case 0x72: output.append(0x0d)
                case 0x74: output.append(0x09)
                case 0x75:
                    let first = try parseHexCodeUnit()
                    let scalarValue: UInt32
                    if (0xd800...0xdbff).contains(first) {
                        guard index + 2 <= bytes.count,
                              bytes[index] == 0x5c,
                              bytes[index + 1] == 0x75
                        else {
                            throw CanonicalJSONRejection.invalidUnicode
                        }
                        index += 2
                        let second = try parseHexCodeUnit()
                        guard (0xdc00...0xdfff).contains(second) else {
                            throw CanonicalJSONRejection.invalidUnicode
                        }
                        scalarValue = 0x10000
                            + (UInt32(first - 0xd800) << 10)
                            + UInt32(second - 0xdc00)
                    } else {
                        guard !(0xdc00...0xdfff).contains(first) else {
                            throw CanonicalJSONRejection.invalidUnicode
                        }
                        scalarValue = UInt32(first)
                    }
                    guard let scalar = UnicodeScalar(scalarValue) else {
                        throw CanonicalJSONRejection.invalidUnicode
                    }
                    output.append(contentsOf: String(scalar).utf8)
                default:
                    throw CanonicalJSONRejection.jsonParse
                }
            default:
                output.append(byte)
            }
        }
        throw CanonicalJSONRejection.jsonParse
    }

    private mutating func parseHexCodeUnit() throws -> UInt16 {
        guard index + 4 <= bytes.count else { throw CanonicalJSONRejection.jsonParse }
        var result: UInt16 = 0
        for byte in bytes[index..<(index + 4)] {
            let digit: UInt16
            switch byte {
            case 0x30...0x39: digit = UInt16(byte - 0x30)
            case 0x41...0x46: digit = UInt16(byte - 0x41 + 10)
            case 0x61...0x66: digit = UInt16(byte - 0x61 + 10)
            default: throw CanonicalJSONRejection.jsonParse
            }
            result = result * 16 + digit
        }
        index += 4
        return result
    }

    private mutating func parseNumber() throws -> Double {
        let start = index
        _ = consumeIf(0x2d)
        guard index < bytes.count else { throw CanonicalJSONRejection.jsonParse }
        if consumeIf(0x30) {
            guard index == bytes.count || !(0x30...0x39).contains(bytes[index]) else {
                throw CanonicalJSONRejection.jsonParse
            }
        } else {
            guard consumeDigit(in: 0x31...0x39) else { throw CanonicalJSONRejection.jsonParse }
            while consumeDigit(in: 0x30...0x39) {}
        }
        if consumeIf(0x2e) {
            guard consumeDigit(in: 0x30...0x39) else { throw CanonicalJSONRejection.jsonParse }
            while consumeDigit(in: 0x30...0x39) {}
        }
        if index < bytes.count, bytes[index] == 0x65 || bytes[index] == 0x45 {
            index += 1
            if index < bytes.count, bytes[index] == 0x2b || bytes[index] == 0x2d { index += 1 }
            guard consumeDigit(in: 0x30...0x39) else { throw CanonicalJSONRejection.jsonParse }
            while consumeDigit(in: 0x30...0x39) {}
        }

        guard let text = String(bytes: bytes[start..<index], encoding: .utf8),
              let value = Double(text)
        else {
            throw CanonicalJSONRejection.jsonParse
        }
        guard value.isFinite else { throw CanonicalJSONRejection.numericOutOfRange }
        return value
    }

    private mutating func consume(_ literal: StaticString) throws {
        let literalBytes = Array(String(describing: literal).utf8)
        guard index + literalBytes.count <= bytes.count,
              Array(bytes[index..<(index + literalBytes.count)]) == literalBytes
        else {
            throw CanonicalJSONRejection.jsonParse
        }
        index += literalBytes.count
    }

    private mutating func consumeIf(_ byte: UInt8) -> Bool {
        guard index < bytes.count, bytes[index] == byte else { return false }
        index += 1
        return true
    }

    private mutating func consumeDigit(in range: ClosedRange<UInt8>) -> Bool {
        guard index < bytes.count, range.contains(bytes[index]) else { return false }
        index += 1
        return true
    }

    private mutating func skipWhitespace() {
        while index < bytes.count, [0x20, 0x09, 0x0a, 0x0d].contains(bytes[index]) {
            index += 1
        }
    }
}
