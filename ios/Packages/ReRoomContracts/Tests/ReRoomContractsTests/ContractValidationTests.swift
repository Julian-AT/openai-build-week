import Foundation
import Testing

@testable import ReRoomContracts

@Suite("ContractValidationTests", .serialized)
struct ContractValidationTests {
    @Test("FX-CONTRACT-001 agrees with the frozen reference oracle")
    func frozenReferenceAgreement() throws {
        let fixture = try ContractFixture.load()
        let validators = try fixture.makeValidators()

        #expect(Set(validators.keys) == Set(["CON-001", "CON-002", "CON-003", "CON-004", "CON-005"]))

        for fixtureCase in fixture.manifest.cases {
            let actual = try fixture.execute(fixtureCase, validators: validators)
            #expect(
                actual.verdict == fixtureCase.expected.verdict,
                Comment(rawValue: fixtureCase.caseID)
            )
            #expect(
                actual.rejectionClass == fixtureCase.expected.rejectionClass,
                Comment(rawValue: fixtureCase.caseID)
            )
        }
    }

    @Test("the frozen profile covers exactly the canonical schema keyword surface")
    func canonicalKeywordSurfaceIsSupported() throws {
        let fixture = try ContractFixture.load()
        let validators = try fixture.makeValidators()
        let expectedKeywords: Set<String> = [
            "$defs", "$id", "$ref", "$schema", "additionalProperties", "allOf", "anyOf",
            "const", "contains", "description", "else", "enum", "exclusiveMinimum", "format",
            "if", "items", "maxItems", "maxLength", "maxProperties", "maximum", "minContains",
            "minItems", "minLength", "minProperties", "minimum", "not", "oneOf", "pattern",
            "prefixItems", "properties", "required", "then", "title", "type", "uniqueItems",
        ]

        let actualKeywords = validators.values.reduce(into: Set<String>()) { result, validator in
            result.formUnion(validator.usedSchemaKeywords)
        }
        #expect(actualKeywords == expectedKeywords)
        #expect(actualKeywords.isSubset(of: FrozenSchemaValidator.frozenSupportedKeywords))
    }

    @Test("unknown, dynamic, and remote schema behavior fails closed", arguments: [
        SchemaMutation.unknownKeyword,
        .dynamicReference,
        .remoteReference,
    ])
    func unsafeSchemaSurfaceIsRejected(mutation: SchemaMutation) throws {
        let fixture = try ContractFixture.load()
        let reference = try #require(
            fixture.manifest.schemaHashes.first { $0.contractID == "CON-001" }
        )
        let original = try fixture.readRepositoryFile(reference.relativePath)
        var object = try #require(
            JSONSerialization.jsonObject(with: original) as? [String: Any]
        )

        switch mutation {
        case .unknownKeyword:
            object["reroomUnknownKeyword"] = true
        case .dynamicReference:
            object["$dynamicRef"] = "#/$defs/frameId"
        case .remoteReference:
            object["$ref"] = "https://example.invalid/schema.json"
        }

        let mutated = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        do {
            _ = try FrozenSchemaValidator(
                contractID: reference.contractID,
                expectedSchemaID: reference.schemaID,
                schemaData: mutated
            )
            Issue.record("unsafe schema mutation was accepted")
        } catch let error as FrozenSchemaDefinitionError {
            switch (mutation, error) {
            case (.unknownKeyword, .unsupportedKeyword),
                 (.dynamicReference, .dynamicResolutionForbidden),
                 (.remoteReference, .remoteReferenceForbidden):
                break
            default:
                Issue.record("unexpected rejection: \(error)")
            }
        }
    }

    @Test("the selected validator completes the frozen corpus inside its timebox")
    func selectedValidatorBenchmark() throws {
        let fixture = try ContractFixture.load()
        let compilationStart = ContinuousClock.now
        let validators = try fixture.makeValidators()
        let compilationNanoseconds = compilationStart.duration(to: .now).nanoseconds

        let repetitions = 20
        var accepted = 0
        var rejected = 0
        let validationStart = ContinuousClock.now
        for _ in 0..<repetitions {
            for fixtureCase in fixture.manifest.cases {
                let actual = try fixture.execute(fixtureCase, validators: validators)
                guard actual.verdict == fixtureCase.expected.verdict,
                      actual.rejectionClass == fixtureCase.expected.rejectionClass
                else {
                    throw FixtureError.benchmarkOracleMismatch(fixtureCase.caseID)
                }
                if actual.verdict == "accept" { accepted += 1 } else { rejected += 1 }
            }
        }
        let validationNanoseconds = validationStart.duration(to: .now).nanoseconds
        let totalNanoseconds = compilationNanoseconds + validationNanoseconds
        #expect(totalNanoseconds < 10_000_000_000)

        if let rawEvidencePath = ProcessInfo.processInfo.environment["REROOM_SCHEMA_RAW_EVIDENCE"] {
            let rawEvidence: [String: Any] = [
                "accepted_verdicts": accepted,
                "benchmark_id": "BENCH-SWIFT-SCHEMA-001",
                "compilation_nanoseconds": compilationNanoseconds,
                "corpus_cases": fixture.manifest.cases.count,
                "rejected_verdicts": rejected,
                "repetitions": repetitions,
                "timebox_nanoseconds": 10_000_000_000,
                "total_nanoseconds": totalNanoseconds,
                "validation_nanoseconds": validationNanoseconds,
            ]
            let bytes = try JSONSerialization.data(withJSONObject: rawEvidence, options: [.sortedKeys])
            try bytes.write(to: URL(fileURLWithPath: rawEvidencePath), options: .atomic)
        }
    }
}

enum SchemaMutation: String, CaseIterable, Sendable {
    case unknownKeyword
    case dynamicReference
    case remoteReference
}

private struct FixtureOutcome: Equatable {
    let verdict: String
    let rejectionClass: String?

    static let accepted = FixtureOutcome(verdict: "accept", rejectionClass: nil)

    static func rejected(_ rejection: FrozenSchemaRejection) -> FixtureOutcome {
        FixtureOutcome(verdict: "reject", rejectionClass: rejection.rawValue)
    }
}

private struct ContractFixture {
    let repositoryRoot: URL
    let fixtureRoot: URL
    let manifest: Manifest

    static func load() throws -> ContractFixture {
        let fileManager = FileManager.default
        var cursor = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !fileManager.fileExists(atPath: cursor.appendingPathComponent(".git").path) {
            let parent = cursor.deletingLastPathComponent()
            guard parent.path != cursor.path else {
                throw FixtureError.repositoryRootNotFound
            }
            cursor = parent
        }

        let fixtureRoot = cursor.appendingPathComponent("fixtures/contracts/1.0.0/rev-001")
        let manifestData = try Data(contentsOf: fixtureRoot.appendingPathComponent("manifest.json"))
        return ContractFixture(
            repositoryRoot: cursor,
            fixtureRoot: fixtureRoot,
            manifest: try JSONDecoder().decode(Manifest.self, from: manifestData)
        )
    }

    func readRepositoryFile(_ relativePath: String) throws -> Data {
        try Data(contentsOf: repositoryRoot.appendingPathComponent(relativePath))
    }

    func readFixtureFile(_ relativePath: String) throws -> Data {
        try Data(contentsOf: fixtureRoot.appendingPathComponent(relativePath))
    }

    func makeValidators() throws -> [String: FrozenSchemaValidator] {
        try Dictionary(uniqueKeysWithValues: manifest.schemaHashes.map { reference in
            let bytes = try readRepositoryFile(reference.relativePath)
            return (
                reference.contractID,
                try FrozenSchemaValidator(
                    contractID: reference.contractID,
                    expectedSchemaID: reference.schemaID,
                    schemaData: bytes
                )
            )
        })
    }

    func execute(
        _ fixtureCase: FixtureCase,
        validators: [String: FrozenSchemaValidator]
    ) throws -> FixtureOutcome {
        let inputData = try readFixtureFile(fixtureCase.input.relativePath)
        if fixtureCase.caseKind == "json_instance" {
            let contractID = try contractID(for: fixtureCase.input.relativePath)
            return try validate(inputData, payload: nil, contractID: contractID, validators: validators)
        }

        let descriptor = try #require(
            JSONSerialization.jsonObject(with: inputData) as? [String: Any]
        )
        if descriptor["migration"] != nil {
            if descriptor["migration"] as? String == "named_1.0_to_1.1",
               descriptor["source_version"] as? String == "1.0.0",
               descriptor["reader_version"] as? String == "1.1.0",
               descriptor["representable"] as? Bool == true,
               let source = descriptor["source"] as? String
            {
                return try validate(
                    readFixtureFile(source),
                    payload: nil,
                    contractID: "CON-001",
                    validators: validators
                )
            }
            return .rejected(.unsupportedContractVersion)
        }

        let basePath = try #require(descriptor["base"] as? String)
        var document: Any = try JSONSerialization.jsonObject(with: readFixtureFile(basePath))
        let mutations = try #require(descriptor["mutations"] as? [[String: Any]])
        for mutation in mutations {
            try apply(mutation: mutation, to: &document)
        }
        let documentData = try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
        let payload = try (descriptor["payload"] as? String).map(Data.init(hexadecimal:))
        return try validate(
            documentData,
            payload: payload,
            contractID: contractID(for: basePath),
            validators: validators
        )
    }

    private func validate(
        _ document: Data,
        payload: Data?,
        contractID: String,
        validators: [String: FrozenSchemaValidator]
    ) throws -> FixtureOutcome {
        let validator = try #require(validators[contractID])
        switch validator.validate(documentData: document, payloadData: payload) {
        case .accepted:
            return .accepted
        case .rejected(let rejection):
            return .rejected(rejection)
        }
    }

    private func contractID(for relativePath: String) throws -> String {
        if relativePath.contains("con001.") { return "CON-001" }
        if relativePath.contains("con002.") { return "CON-002" }
        if relativePath.contains("con003.") { return "CON-003" }
        if relativePath.contains("con004.") { return "CON-004" }
        if relativePath.contains("con005.") { return "CON-005" }
        throw FixtureError.contractNotIdentified(relativePath)
    }

    private func apply(mutation: [String: Any], to document: inout Any) throws {
        let pointer = try #require(mutation["pointer"] as? String)
        let operation = try #require(mutation["op"] as? String)
        let tokens = pointer.dropFirst().split(separator: "/", omittingEmptySubsequences: false).map {
            String($0).replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
        }
        try apply(
            operation: operation,
            tokens: ArraySlice(tokens),
            value: mutation["value"] as Any,
            to: &document
        )
    }

    private func apply(
        operation: String,
        tokens: ArraySlice<String>,
        value: Any,
        to document: inout Any
    ) throws {
        guard let token = tokens.first else { throw FixtureError.invalidMutation }
        let remaining = tokens.dropFirst()

        if var object = document as? [String: Any] {
            if remaining.isEmpty {
                guard operation == "add" || (operation == "replace" && object[token] != nil) else {
                    throw FixtureError.invalidMutation
                }
                object[token] = value
            } else {
                guard var child = object[token] else { throw FixtureError.invalidMutation }
                try apply(operation: operation, tokens: remaining, value: value, to: &child)
                object[token] = child
            }
            document = object
            return
        }

        if var array = document as? [Any], let index = Int(token), array.indices.contains(index) {
            if remaining.isEmpty {
                array[index] = value
            } else {
                var child = array[index]
                try apply(operation: operation, tokens: remaining, value: value, to: &child)
                array[index] = child
            }
            document = array
            return
        }
        throw FixtureError.invalidMutation
    }
}

private extension ContractFixture {
    struct Manifest: Decodable {
        let schemaHashes: [SchemaReference]
        let cases: [FixtureCase]

        enum CodingKeys: String, CodingKey {
            case schemaHashes = "schema_hashes"
            case cases
        }
    }

    struct SchemaReference: Decodable {
        let contractID: String
        let schemaID: String
        let relativePath: String

        enum CodingKeys: String, CodingKey {
            case contractID = "contract_id"
            case schemaID = "schema_id"
            case relativePath = "relative_path"
        }
    }

    struct FixtureCase: Decodable {
        let caseID: String
        let caseKind: String
        let input: InputReference
        let expected: Expected

        enum CodingKeys: String, CodingKey {
            case caseID = "case_id"
            case caseKind = "case_kind"
            case input
            case expected
        }
    }

    struct InputReference: Decodable {
        let relativePath: String

        enum CodingKeys: String, CodingKey {
            case relativePath = "relative_path"
        }
    }

    struct Expected: Decodable {
        let verdict: String
        let rejectionClass: String?

        enum CodingKeys: String, CodingKey {
            case verdict
            case rejectionClass = "rejection_class"
        }
    }
}

private enum FixtureError: Error {
    case repositoryRootNotFound
    case contractNotIdentified(String)
    case invalidMutation
    case invalidHexadecimal
    case benchmarkOracleMismatch(String)
}

private extension Data {
    init(hexadecimal: String) throws {
        guard hexadecimal.count.isMultiple(of: 2) else { throw FixtureError.invalidHexadecimal }
        var bytes = [UInt8]()
        bytes.reserveCapacity(hexadecimal.count / 2)
        var index = hexadecimal.startIndex
        while index < hexadecimal.endIndex {
            let next = hexadecimal.index(index, offsetBy: 2)
            guard let byte = UInt8(hexadecimal[index..<next], radix: 16) else {
                throw FixtureError.invalidHexadecimal
            }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}

private extension Duration {
    var nanoseconds: Int64 {
        let parts = components
        return parts.seconds * 1_000_000_000 + parts.attoseconds / 1_000_000_000
    }
}
