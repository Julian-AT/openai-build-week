import CryptoKit
import Foundation
import JSONSchema

enum FrozenSchemaDefinitionError: Error, Equatable, Sendable {
    case invalidJSON
    case invalidSchema
    case schemaCompilation
    case metaSchemaUnavailable
    case metaSchemaRejected
    case schemaIdentifierMismatch
    case unsupportedKeyword(String)
    case dynamicResolutionForbidden(String)
    case remoteReferenceForbidden(String)
}

enum FrozenSchemaRejection: String, Error, Equatable, Sendable {
    case jsonParse = "json_parse"
    case schemaValidation = "schema_validation"
    case unsupportedContractVersion = "unsupported_contract_version"
    case unknownProperty = "unknown_property"
    case invalidIdentity = "invalid_identity"
    case invalidPath = "invalid_path"
    case numericOutOfRange = "numeric_out_of_range"
    case semanticInvariant = "semantic_invariant"
    case digestMismatch = "digest_mismatch"
}

enum FrozenSchemaVerdict: Equatable, Sendable {
    case accepted
    case rejected(FrozenSchemaRejection)
}

struct FrozenSchemaValidator {
    static let draft202012URI = "https://json-schema.org/draft/2020-12/schema"
    static let float32Maximum = 3.4028234663852886e38

    static let frozenSupportedKeywords: Set<String> = [
        "$defs", "$id", "$ref", "$schema", "additionalProperties", "allOf", "anyOf",
        "const", "contains", "description", "else", "enum", "exclusiveMinimum", "format",
        "if", "items", "maxContains", "maxItems", "maxLength", "maxProperties", "maximum",
        "minContains", "minItems", "minLength", "minProperties", "minimum", "not", "oneOf",
        "pattern", "prefixItems", "properties", "required", "then", "title", "type",
        "uniqueItems",
    ]

    let contractID: String
    let schemaID: String
    let usedSchemaKeywords: Set<String>

    private let schema: Schema
    private let documentSchemaVersion: String

    init(
        contractID: String,
        expectedSchemaID: String,
        documentSchemaVersion: String = "1.0.0",
        schemaData: Data
    ) throws {
        let rawSchema: JSONValue
        do {
            rawSchema = try JSONValue.parse(schemaData)
        } catch {
            throw FrozenSchemaDefinitionError.invalidJSON
        }

        guard let root = rawSchema.object,
              root["$schema"]?.string == Self.draft202012URI,
              root["$id"]?.string == expectedSchemaID
        else {
            throw FrozenSchemaDefinitionError.schemaIdentifierMismatch
        }

        var usedKeywords = Set<String>()
        try Self.inspectSchema(
            rawSchema,
            location: "#",
            isRoot: true,
            usedKeywords: &usedKeywords
        )

        let context = Context(
            dialect: .draft2020_12,
            remoteSchema: [:],
            formatValidators: [ReRoomDateTimeFormatValidator(), ReRoomURIFormatValidator()]
        )
        let compiled: Schema
        do {
            compiled = try Schema(
                rawSchema: rawSchema,
                context: context,
                baseURI: URL(string: expectedSchemaID)!
            )
        } catch {
            throw FrozenSchemaDefinitionError.schemaCompilation
        }
        let metaSchemaResult: ValidationResult
        do {
            metaSchemaResult = try Self.validateAgainstDraftMetaSchema(rawSchema)
        } catch {
            throw FrozenSchemaDefinitionError.metaSchemaUnavailable
        }
        guard metaSchemaResult.isValid else {
            throw FrozenSchemaDefinitionError.metaSchemaRejected
        }

        self.contractID = contractID
        self.schemaID = expectedSchemaID
        self.usedSchemaKeywords = usedKeywords
        self.schema = compiled
        self.documentSchemaVersion = documentSchemaVersion
    }

    private static func validateAgainstDraftMetaSchema(
        _ rawSchema: JSONValue
    ) throws -> ValidationResult {
        let bundle = try metaSchemaResourceBundle()
        guard let schemaURL = bundle.url(forResource: "schema", withExtension: "json"),
              let baseURI = URL(string: draft202012URI)
        else {
            throw FrozenSchemaDefinitionError.metaSchemaUnavailable
        }

        let decoder = JSONDecoder()
        func jsonValue(from url: URL) throws -> JSONValue {
            try decoder.decode(JSONValue.self, from: Data(contentsOf: url))
        }

        let remoteSchemas = try bundle.urls(
            forResourcesWithExtension: "json",
            subdirectory: nil
        )?.reduce(into: [String: JSONValue]()) { result, url in
            guard url.lastPathComponent.hasPrefix("schema") == false else { return }
            let resourceName = url.deletingPathExtension().lastPathComponent
            if let key = URL(
                string: "meta/\(resourceName)",
                relativeTo: baseURI
            )?.absoluteString {
                result[key] = try jsonValue(from: url)
            }
        } ?? [:]

        let metaSchema = try Schema(
            rawSchema: jsonValue(from: schemaURL),
            context: Context(dialect: .draft2020_12, remoteSchema: remoteSchemas),
            baseURI: baseURI
        )
        return metaSchema.validate(rawSchema)
    }

    private static func metaSchemaResourceBundle() throws -> Bundle {
        let dependencyBundle = Bundle.jsonSchemaResources
        if dependencyBundle.url(forResource: "schema", withExtension: "json") != nil {
            return dependencyBundle
        }

        let bundleName = "swift-json-schema_JSONSchema.bundle"
        let roots = [
            Bundle.main.resourceURL,
            Bundle(for: FrozenSchemaResourceBundleToken.self).resourceURL,
            dependencyBundle.resourceURL,
        ] + Bundle.allBundles.map(\.resourceURL) + Bundle.allFrameworks.map(\.resourceURL)

        for root in roots.compactMap({ $0 }) {
            let candidateURL = root.lastPathComponent == bundleName
                ? root
                : root.appendingPathComponent(bundleName, isDirectory: true)
            if let candidate = Bundle(url: candidateURL),
               candidate.url(forResource: "schema", withExtension: "json") != nil {
                return candidate
            }
        }
        throw FrozenSchemaDefinitionError.metaSchemaUnavailable
    }

    func validate(documentData: Data, payloadData: Data? = nil) -> FrozenSchemaVerdict {
        let document: JSONValue
        do {
            document = try JSONValue.parse(documentData)
        } catch {
            return .rejected(.jsonParse)
        }

        if let rejection = Self.validateDocumentBoundary(
            document,
            schemaVersion: documentSchemaVersion
        ) {
            return .rejected(rejection)
        }
        if let rejection = validateSemanticInvariants(document) {
            return .rejected(rejection)
        }
        if let payloadData, let rejection = validatePayload(payloadData, document: document) {
            return .rejected(rejection)
        }

        let result = schema.validate(document)
        guard result.isValid else {
            return .rejected(Self.classify(result))
        }
        return .accepted
    }

    private static func inspectSchema(
        _ value: JSONValue,
        location: String,
        isRoot: Bool,
        usedKeywords: inout Set<String>
    ) throws {
        if value.boolean != nil { return }
        guard let object = value.object else {
            throw FrozenSchemaDefinitionError.invalidSchema
        }

        for (keyword, _) in object {
            if keyword == "$dynamicRef" || keyword == "$dynamicAnchor" {
                throw FrozenSchemaDefinitionError.dynamicResolutionForbidden("\(location)/\(keyword)")
            }
            guard frozenSupportedKeywords.contains(keyword) else {
                throw FrozenSchemaDefinitionError.unsupportedKeyword("\(location)/\(keyword)")
            }
            usedKeywords.insert(keyword)
        }

        if !isRoot, object["$id"] != nil || object["$schema"] != nil {
            throw FrozenSchemaDefinitionError.remoteReferenceForbidden(location)
        }
        if let reference = object["$ref"]?.string,
           reference != "#", !reference.hasPrefix("#/")
        {
            throw FrozenSchemaDefinitionError.remoteReferenceForbidden(reference)
        }

        for keyword in [
            "additionalProperties", "contains", "else", "if", "items", "not", "then",
        ] {
            if let child = object[keyword] {
                try inspectSchema(
                    child,
                    location: "\(location)/\(keyword)",
                    isRoot: false,
                    usedKeywords: &usedKeywords
                )
            }
        }

        for keyword in ["$defs", "properties"] {
            guard let children = object[keyword]?.object else { continue }
            for (name, child) in children {
                try inspectSchema(
                    child,
                    location: "\(location)/\(keyword)/\(name)",
                    isRoot: false,
                    usedKeywords: &usedKeywords
                )
            }
        }

        for keyword in ["allOf", "anyOf", "oneOf", "prefixItems"] {
            guard let children = object[keyword]?.array else { continue }
            for (index, child) in children.enumerated() {
                try inspectSchema(
                    child,
                    location: "\(location)/\(keyword)/\(index)",
                    isRoot: false,
                    usedKeywords: &usedKeywords
                )
            }
        }
    }

    private static func validateDocumentBoundary(
        _ value: JSONValue,
        schemaVersion: String
    ) -> FrozenSchemaRejection? {
        switch value {
        case .number(let number):
            guard number.isFinite, abs(number) <= float32Maximum else {
                return .numericOutOfRange
            }
        case .object(let object):
            for (key, child) in object {
                if key.hasSuffix("path"), let path = child.string, !isSafeArchivePath(path) {
                    return .invalidPath
                }
                if let rejection = validateDocumentBoundary(
                    child,
                    schemaVersion: schemaVersion
                ) { return rejection }
            }
        case .array(let values):
            for child in values {
                if let rejection = validateDocumentBoundary(
                    child,
                    schemaVersion: schemaVersion
                ) { return rejection }
            }
        case .string, .integer, .boolean, .null:
            break
        }

        guard let object = value.object else { return nil }
        for versionField in ["protocol_version", "format_version", "schema_version"] {
            if let version = object[versionField], version.string != schemaVersion {
                return .unsupportedContractVersion
            }
        }
        return nil
    }

    private static func isSafeArchivePath(_ path: String) -> Bool {
        guard !path.isEmpty,
              path.utf8.count <= 240,
              !path.hasPrefix("/"),
              !path.contains("\\"),
              !path.contains("\0"),
              !(path.count >= 2 && path[path.index(after: path.startIndex)] == ":")
        else {
            return false
        }
        let segments = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !segments.isEmpty else { return false }
        return segments.allSatisfy { segment in
            guard segment != ".", segment != "..", let first = segment.utf8.first else {
                return false
            }
            let firstAllowed = first.isASCIILetter || first.isASCIIDigit || first == 45 || first == 95
            return firstAllowed && segment.utf8.allSatisfy {
                $0.isASCIILetter || $0.isASCIIDigit || $0 == 45 || $0 == 46 || $0 == 95
            }
        }
    }

    private func validateSemanticInvariants(_ document: JSONValue) -> FrozenSchemaRejection? {
        guard contractID == "CON-005",
              let root = document.object,
              let authority = root["revision_authority"]?.object,
              let kind = authority["kind"]?.string,
              let authorityID = authority["authority_id"]?.string
        else {
            return nil
        }

        let expectedPrefix: String?
        switch kind {
        case "native_device": expectedPrefix = "device_"
        case "gateway": expectedPrefix = "gateway_"
        default: expectedPrefix = nil
        }
        if let expectedPrefix, !authorityID.hasPrefix(expectedPrefix) {
            return .semanticInvariant
        }
        return nil
    }

    private func validatePayload(_ payload: Data, document: JSONValue) -> FrozenSchemaRejection? {
        guard contractID == "CON-001", let root = document.object else { return nil }
        guard root["payload_sha256"]?.string == SHA256.hash(data: payload).hexadecimal else {
            return .digestMismatch
        }
        return nil
    }

    private static func classify(_ result: ValidationResult) -> FrozenSchemaRejection {
        let errors = flatten(result.errors ?? [])
        if errors.contains(where: {
            $0.keyword == "additionalProperties"
                && $0.keywordLocation.description == "#/additionalProperties"
        }) {
            return .unknownProperty
        }
        if errors.contains(where: {
            $0.keyword == "pattern" && $0.instanceLocation.description.split(separator: "/").last?.hasSuffix("_id") == true
        }) {
            return .invalidIdentity
        }
        return .schemaValidation
    }

    private static func flatten(_ errors: [ValidationError]) -> [ValidationError] {
        errors.flatMap { error in
            [error] + flatten(error.errors ?? [])
        }
    }
}

private final class FrozenSchemaResourceBundleToken {}

private struct ReRoomDateTimeFormatValidator: FormatValidator {
    let formatName = "date-time"

    nonisolated(unsafe) private static let internetDateTime: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    nonisolated(unsafe) private static let fractionalInternetDateTime: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func validate(_ value: String) -> Bool {
        Self.internetDateTime.date(from: value) != nil
            || Self.fractionalInternetDateTime.date(from: value) != nil
    }
}

private struct ReRoomURIFormatValidator: FormatValidator {
    let formatName = "uri"

    func validate(_ value: String) -> Bool {
        URL(string: value)?.scheme != nil
    }
}

private extension UInt8 {
    var isASCIILetter: Bool { (65...90).contains(self) || (97...122).contains(self) }
    var isASCIIDigit: Bool { (48...57).contains(self) }
}

private extension SHA256.Digest {
    var hexadecimal: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
