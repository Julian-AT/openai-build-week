import CryptoKit
import Foundation

public enum ContractSchemaIdentifier: String, CaseIterable, Sendable {
    case framePacket = "urn:reroom:schema:frame-packet:1"
    case rrcapManifest = "urn:reroom:schema:rrcap-manifest:1"
    case sceneState = "urn:reroom:schema:scene-state:1"
    case editArtifacts = "urn:reroom:schema:edit-artifacts:1"
    case transaction = "urn:reroom:schema:transaction:1"

    public var version: String { "1.0.0" }

    var contractID: String {
        switch self {
        case .framePacket: "CON-001"
        case .rrcapManifest: "CON-002"
        case .sceneState: "CON-003"
        case .editArtifacts: "CON-004"
        case .transaction: "CON-005"
        }
    }

    var expectedSHA256: String {
        switch self {
        case .framePacket: "d50b19bfb29c6c62c494e3a47deb3c51a933609698f4ff2f9cbfba6ec4252b43"
        case .rrcapManifest: "c97349820ed66fb1a1fdf60ea9afee312f532811602851d01d1e233641730b87"
        case .sceneState: "9c77d27762e20ff5fad24c438e8817a03c770b55be3fc82ea72097c4c273e440"
        case .editArtifacts: "58dbfc8f152881cbdc31be22f6ab7631ac474bb78537ac2a9254f5ef16bd598f"
        case .transaction: "2a4f6728978db0879b5dfb10f052f6d5280e5cf83ad5600f0cf959626c2399a2"
        }
    }
}

public struct ContractSchemaRegistration: Sendable {
    public let identifier: ContractSchemaIdentifier
    public let version: String
    public let sha256: String
    public let schemaData: Data

    public init(
        identifier: ContractSchemaIdentifier,
        version: String,
        sha256: String,
        schemaData: Data
    ) {
        self.identifier = identifier
        self.version = version
        self.sha256 = sha256
        self.schemaData = schemaData
    }
}

public struct ContractValidationRequest: Sendable {
    public let schemaID: String
    public let schemaVersion: String
    public let schemaSHA256: String
    public let documentData: Data
    public let payloadData: Data?

    public init(
        schemaID: String,
        schemaVersion: String,
        schemaSHA256: String,
        documentData: Data,
        payloadData: Data? = nil
    ) {
        self.schemaID = schemaID
        self.schemaVersion = schemaVersion
        self.schemaSHA256 = schemaSHA256
        self.documentData = documentData
        self.payloadData = payloadData
    }
}

public enum ContractValidationRejection: String, Error, Equatable, Sendable {
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

public enum ContractValidationVerdict: Equatable, Sendable {
    case accepted
    case rejected(ContractValidationRejection)
}

public enum ContractValidatorConfigurationError: Error, Equatable, Sendable {
    case invalidLimits
    case incompleteSchemaRegistry
    case duplicateSchemaIdentifier
    case unsupportedSchemaVersion
    case schemaDigestMismatch
    case invalidSchema
}

public struct ContractValidator: Sendable {
    public static let maximumDocumentBytes = 33_554_432
    public static let maximumDocumentDepth = 64

    private let validators: [ContractSchemaIdentifier: FrozenSchemaValidator]
    private let maxDocumentBytes: Int
    private let maxDocumentDepth: Int

    public init(
        registrations: [ContractSchemaRegistration],
        maxDocumentBytes: Int = ContractValidator.maximumDocumentBytes,
        maxDocumentDepth: Int = ContractValidator.maximumDocumentDepth
    ) throws {
        guard (1...Self.maximumDocumentBytes).contains(maxDocumentBytes),
              (1...Self.maximumDocumentDepth).contains(maxDocumentDepth)
        else {
            throw ContractValidatorConfigurationError.invalidLimits
        }
        guard registrations.count == ContractSchemaIdentifier.allCases.count else {
            throw ContractValidatorConfigurationError.incompleteSchemaRegistry
        }

        var compiled = [ContractSchemaIdentifier: FrozenSchemaValidator]()
        for registration in registrations {
            guard compiled[registration.identifier] == nil else {
                throw ContractValidatorConfigurationError.duplicateSchemaIdentifier
            }
            guard registration.version == registration.identifier.version else {
                throw ContractValidatorConfigurationError.unsupportedSchemaVersion
            }
            let actualDigest = SHA256.hash(data: registration.schemaData).contractHexadecimal
            guard registration.sha256 == registration.identifier.expectedSHA256,
                  actualDigest == registration.identifier.expectedSHA256
            else {
                throw ContractValidatorConfigurationError.schemaDigestMismatch
            }
            do {
                compiled[registration.identifier] = try FrozenSchemaValidator(
                    contractID: registration.identifier.contractID,
                    expectedSchemaID: registration.identifier.rawValue,
                    schemaData: registration.schemaData
                )
            } catch {
                throw ContractValidatorConfigurationError.invalidSchema
            }
        }
        guard Set(compiled.keys) == Set(ContractSchemaIdentifier.allCases) else {
            throw ContractValidatorConfigurationError.incompleteSchemaRegistry
        }

        self.validators = compiled
        self.maxDocumentBytes = maxDocumentBytes
        self.maxDocumentDepth = maxDocumentDepth
    }

    public func validate(_ request: ContractValidationRequest) -> ContractValidationVerdict {
        guard let identifier = ContractSchemaIdentifier(rawValue: request.schemaID),
              request.schemaVersion == identifier.version
        else {
            return .rejected(.unsupportedContractVersion)
        }
        guard request.schemaSHA256 == identifier.expectedSHA256 else {
            return .rejected(.digestMismatch)
        }
        guard request.documentData.count <= maxDocumentBytes,
              Self.isWithinDepthLimit(request.documentData, maximum: maxDocumentDepth)
        else {
            return .rejected(.jsonParse)
        }
        guard let validator = validators[identifier] else {
            return .rejected(.semanticInvariant)
        }

        switch validator.validate(
            documentData: request.documentData,
            payloadData: request.payloadData
        ) {
        case .accepted:
            return .accepted
        case .rejected(let rejection):
            return .rejected(ContractValidationRejection(rejection))
        }
    }

    private static func isWithinDepthLimit(_ data: Data, maximum: Int) -> Bool {
        var depth = 0
        var inString = false
        var escaped = false

        for byte in data {
            if inString {
                if escaped {
                    escaped = false
                } else if byte == 0x5c {
                    escaped = true
                } else if byte == 0x22 {
                    inString = false
                }
                continue
            }

            switch byte {
            case 0x22:
                inString = true
            case 0x5b, 0x7b:
                depth += 1
                if depth > maximum { return false }
            case 0x5d, 0x7d:
                guard depth > 0 else { return false }
                depth -= 1
            default:
                break
            }
        }
        return true
    }
}

private extension ContractValidationRejection {
    init(_ rejection: FrozenSchemaRejection) {
        switch rejection {
        case .jsonParse: self = .jsonParse
        case .schemaValidation: self = .schemaValidation
        case .unsupportedContractVersion: self = .unsupportedContractVersion
        case .unknownProperty: self = .unknownProperty
        case .invalidIdentity: self = .invalidIdentity
        case .invalidPath: self = .invalidPath
        case .numericOutOfRange: self = .numericOutOfRange
        case .semanticInvariant: self = .semanticInvariant
        case .digestMismatch: self = .digestMismatch
        }
    }
}

private extension SHA256.Digest {
    var contractHexadecimal: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
