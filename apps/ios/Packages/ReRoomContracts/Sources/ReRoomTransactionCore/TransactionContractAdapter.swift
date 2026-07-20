import Foundation
import ReRoomContracts

public struct FrozenContractBinding: Equatable, Sendable {
    public let identifier: ContractSchemaIdentifier
    public let version: String
    public let schemaSHA256: String

    public init(identifier: ContractSchemaIdentifier, version: String, schemaSHA256: String) {
        self.identifier = identifier
        self.version = version
        self.schemaSHA256 = schemaSHA256
    }

    public static let sceneStateV1 = Self(
        identifier: .sceneState,
        version: "1.0.0",
        schemaSHA256: "9c77d27762e20ff5fad24c438e8817a03c770b55be3fc82ea72097c4c273e440"
    )

    public static let transactionV1 = Self(
        identifier: .transaction,
        version: "1.0.0",
        schemaSHA256: "2a4f6728978db0879b5dfb10f052f6d5280e5cf83ad5600f0cf959626c2399a2"
    )
}

public enum TransactionContractRejection: Error, Equatable, Sendable {
    case emptyInput
    case contract(ContractValidationRejection)
    case typedDecode
    case noncanonicalTypedRoundTrip
}

public struct ValidatedContract<Value: Equatable & Sendable>: Equatable, Sendable {
    public let value: Value
    public let canonicalData: Data
    public let canonicalSHA256: String
}

public struct TransactionContractAdapter: Sendable {
    private let validator: ContractValidator

    public init(validator: ContractValidator) {
        self.validator = validator
    }

    public func decodeSceneState(_ data: Data) throws -> ValidatedContract<SceneState> {
        try decode(data, binding: .sceneStateV1, as: SceneState.self)
    }

    public func decodeTransaction(_ data: Data) throws -> ValidatedContract<TransactionRecord> {
        try decode(data, binding: .transactionV1, as: TransactionRecord.self)
    }

    private func decode<Value: Codable & Equatable & Sendable>(
        _ data: Data,
        binding: FrozenContractBinding,
        as type: Value.Type
    ) throws -> ValidatedContract<Value> {
        guard data.isEmpty == false else { throw TransactionContractRejection.emptyInput }

        let canonical: Data
        do {
            canonical = try CanonicalJSON.canonicalize(jsonData: data)
        } catch let rejection as CanonicalJSONRejection {
            switch rejection {
            case .numericOutOfRange:
                throw TransactionContractRejection.contract(.numericOutOfRange)
            case .duplicateName, .invalidUnicode, .jsonParse:
                throw TransactionContractRejection.contract(.jsonParse)
            }
        } catch {
            throw TransactionContractRejection.contract(.jsonParse)
        }

        let verdict = validator.validate(
            ContractValidationRequest(
                schemaID: binding.identifier.rawValue,
                schemaVersion: binding.version,
                schemaSHA256: binding.schemaSHA256,
                documentData: canonical
            )
        )
        guard case .accepted = verdict else {
            guard case .rejected(let rejection) = verdict else {
                throw TransactionContractRejection.contract(.semanticInvariant)
            }
            throw TransactionContractRejection.contract(rejection)
        }

        let value: Value
        do {
            value = try JSONDecoder().decode(Value.self, from: canonical)
        } catch {
            throw TransactionContractRejection.typedDecode
        }

        let typedCanonical: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            typedCanonical = try CanonicalJSON.canonicalize(jsonData: encoder.encode(value))
        } catch {
            throw TransactionContractRejection.noncanonicalTypedRoundTrip
        }
        guard typedCanonical == canonical else {
            throw TransactionContractRejection.noncanonicalTypedRoundTrip
        }

        return ValidatedContract(
            value: value,
            canonicalData: canonical,
            canonicalSHA256: CanonicalJSON.sha256Hex(canonical)
        )
    }
}
