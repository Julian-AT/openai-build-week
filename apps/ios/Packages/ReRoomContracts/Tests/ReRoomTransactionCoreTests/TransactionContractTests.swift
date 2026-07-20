import Foundation
import ReRoomContracts
@testable import ReRoomTransactionCore
import Testing

@Suite("Transaction contract oracle")
struct TransactionContractTests {
    @Test("operation and lifecycle inventories remain closed and stable")
    func inventoriesAreExact() {
        #expect(ProductOperation.stableAllowlist.map(\.rawValue) == ["place", "replace", "remove", "restore"])
        #expect(TransactionCanonicalState.allCases.map(\.rawValue) == ["draft", "validated", "previewed", "committed", "rejected", "cancelled"])
        #expect(TransactionSyncState.allCases.map(\.rawValue) == ["local_only", "pending_sync", "synced", "conflict", "sync_failed"])
    }

    @Test("fixture manifest is closed, hash-bound, and lexicographically ordered")
    func fixtureManifestIsImmutable() throws {
        let fixture = try TransactionFixture.load()
        #expect(fixture.manifest.fixtureID == "FX-TRANSACTION-001")
        #expect(fixture.manifest.fixtureRevision == "rev-001")
        #expect(fixture.manifest.oracle.expectedGeneration == "forbidden_during_verification")
        #expect(fixture.manifest.oracle.operationOrder == ["place", "replace", "remove", "restore"])

        for member in fixture.manifest.files {
            let bytes = try fixture.read(member.relativePath)
            #expect(bytes.count == member.byteLength, Comment(rawValue: member.relativePath))
            #expect(CanonicalJSON.sha256Hex(bytes) == member.sha256, Comment(rawValue: member.relativePath))
        }

        let cases: FixtureCases = try fixture.decode("cases.json")
        let caseIDs = cases.cases.map(\.caseID)
        #expect(caseIDs == caseIDs.sorted())
        #expect(Set(caseIDs).count == caseIDs.count)
        #expect(cases.operationInventory == ["place", "replace", "remove", "restore"])
    }

    @Test("frozen schemas and exact typed adapters accept canonical minimal records")
    func canonicalRecordsRoundTrip() throws {
        let fixture = try TransactionFixture.load()
        let adapter = try fixture.makeAdapter()
        let sceneBytes = try fixture.readRepository("fixtures/contracts/1.0.0/rev-001/instances/con003.scene-state.valid.json")
        let transactionBytes = try fixture.readRepository("fixtures/contracts/1.0.0/rev-001/instances/con005.transaction.valid.json")

        let scene = try adapter.decodeSceneState(sceneBytes)
        let transaction = try adapter.decodeTransaction(transactionBytes)

        #expect(scene.value.sceneRevision == 0)
        #expect(scene.value.revisionAuthority.kind == .nativeDevice)
        #expect(transaction.value.canonicalState == .draft)
        #expect(transaction.value.intent.operation == .remove)
        #expect(transaction.value.transactionID != transaction.value.idempotencyKey)
        #expect(transaction.value.revisionAuthority.authorityID.hasPrefix("device_"))
        #expect(transaction.value.revisionAuthority.revisionBranchID.hasPrefix("branch_"))
        let expectedScene = try CanonicalJSON.canonicalize(jsonData: sceneBytes)
        let expectedTransaction = try CanonicalJSON.canonicalize(jsonData: transactionBytes)
        #expect(scene.canonicalData == expectedScene)
        #expect(transaction.canonicalData == expectedTransaction)
    }

    @Test(
        "malformed and hostile contract bytes reject before typed use",
        arguments: HostileCase.all
    )
    fileprivate func hostileInputRejects(testCase: HostileCase) throws {
        let fixture = try TransactionFixture.load()
        let adapter = try fixture.makeAdapter()
        let valid = try fixture.readRepository("fixtures/contracts/1.0.0/rev-001/instances/con005.transaction.valid.json")
        let input = try testCase.mutate(valid)
        #expect(throws: testCase.expected) {
            _ = try adapter.decodeTransaction(input)
        }
    }

    @Test("fixture binds distinct branch authority, transaction, and idempotency identities")
    func identitiesRemainDistinct() throws {
        let fixture = try TransactionFixture.load()
        let cases: FixtureCases = try fixture.decode("cases.json")
        #expect(cases.identity.authorityID != cases.identity.revisionBranchID)
        #expect(cases.identity.transactionID != cases.identity.idempotencyKey)
        #expect(cases.identity.authorityID.hasPrefix("device_"))
        #expect(cases.identity.revisionBranchID.hasPrefix("branch_"))
        #expect(cases.identity.transactionID.hasPrefix("tx_"))
        #expect(cases.identity.idempotencyKey.hasPrefix("txidem_"))
    }

    @Test("oracle traces pin preview no-op, exactly-once commit, retry, restore, and fail-closed conflicts")
    func normalizedTracesArePinned() throws {
        let fixture = try TransactionFixture.load()
        let traces: FixtureTraces = try fixture.decode("expected-traces.json")
        #expect(traces.traces.map(\.traceID) == ["place.commit.replay", "place.restore.offline", "conflict.fail-closed"])

        let place = try #require(traces.traces.first { $0.traceID == "place.commit.replay" })
        #expect(place.events.map(\.sceneRevision) == [0, 0, 0, 1, 1])
        #expect(place.events.compactMap(\.mutationCount) == [0, 0, 0, 1, 1])

        let restore = try #require(traces.traces.first { $0.traceID == "place.restore.offline" })
        #expect(restore.networkReads == 0)
        #expect(restore.sourceTransactionImmutable == true)
        #expect(restore.events.map(\.sceneRevision) == [1, 2])

        let conflict = try #require(traces.traces.first { $0.traceID == "conflict.fail-closed" })
        #expect(conflict.events.allSatisfy { $0.sceneRevision == 0 && $0.mutationCount == 0 })
    }
}

private struct HostileCase: Sendable, CustomTestStringConvertible {
    let name: String
    let expected: TransactionContractRejection
    let mutation: @Sendable (Data) throws -> Data
    var testDescription: String { name }
    func mutate(_ data: Data) throws -> Data { try mutation(data) }

    static let all: [Self] = [
        .init(name: "empty", expected: .emptyInput) { _ in Data() },
        .init(name: "malformed", expected: .contract(.jsonParse)) { _ in Data("{".utf8) },
        .init(name: "duplicate", expected: .contract(.jsonParse)) { _ in Data("{\"a\":1,\"a\":2}".utf8) },
        .init(name: "missing required", expected: .contract(.schemaValidation)) { data in try remove(data, key: "validation") },
        .init(name: "unknown property", expected: .contract(.unknownProperty)) { data in try mutate(data, key: "unknown", value: true) },
        .init(name: "wrong version", expected: .contract(.unsupportedContractVersion)) { data in try mutate(data, key: "schema_version", value: "1.1.0") },
        .init(name: "wrong transaction ID family", expected: .contract(.invalidIdentity)) { data in try mutate(data, key: "transaction_id", value: "scene_00000000-0000-4000-8000-000000000005") },
    ]

    private static func mutate(_ data: Data, key: String, value: Any) throws -> Data {
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object[key] = value
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private static func remove(_ data: Data, key: String) throws -> Data {
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: key)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}

private struct TransactionFixture {
    let repositoryRoot: URL
    let root: URL
    let manifest: FixtureManifest

    static func load() throws -> Self {
        var cursor = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while cursor.path != "/" {
            let root = cursor.appendingPathComponent("fixtures/transactions/1.0.0/rev-001")
            if FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest.json").path) {
                let manifest = try JSONDecoder().decode(FixtureManifest.self, from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
                return Self(repositoryRoot: cursor, root: root, manifest: manifest)
            }
            cursor.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }

    func read(_ relativePath: String) throws -> Data { try Data(contentsOf: root.appendingPathComponent(relativePath)) }
    func readRepository(_ relativePath: String) throws -> Data { try Data(contentsOf: repositoryRoot.appendingPathComponent(relativePath)) }
    func decode<Value: Decodable>(_ relativePath: String) throws -> Value { try JSONDecoder().decode(Value.self, from: read(relativePath)) }

    func makeAdapter() throws -> TransactionContractAdapter {
        let contractManifestData = try readRepository("fixtures/contracts/1.0.0/rev-001/manifest.json")
        let contractManifest = try JSONDecoder().decode(ContractFixtureManifest.self, from: contractManifestData)
        let registrations = try ContractSchemaIdentifier.allCases.map { identifier in
            let binding = try #require(contractManifest.schemaHashes.first { $0.schemaID == identifier.rawValue })
            return ContractSchemaRegistration(
                identifier: identifier,
                version: "1.0.0",
                sha256: binding.sha256,
                schemaData: try readRepository(binding.relativePath)
            )
        }
        return TransactionContractAdapter(validator: try ContractValidator(registrations: registrations))
    }
}

private struct ContractFixtureManifest: Decodable {
    let schemaHashes: [SchemaHash]
    enum CodingKeys: String, CodingKey { case schemaHashes = "schema_hashes" }
    struct SchemaHash: Decodable {
        let schemaID: String
        let relativePath: String
        let sha256: String
        enum CodingKeys: String, CodingKey { case schemaID = "schema_id", relativePath = "relative_path", sha256 }
    }
}

private struct FixtureManifest: Decodable {
    let fixtureID: String
    let fixtureRevision: String
    let oracle: Oracle
    let schemaBindings: [SchemaBinding]
    let files: [FileBinding]
    enum CodingKeys: String, CodingKey { case fixtureID = "fixture_id", fixtureRevision = "fixture_revision", oracle, schemaBindings = "schema_bindings", files }
    struct Oracle: Decodable { let expectedGeneration: String; let operationOrder: [String]; enum CodingKeys: String, CodingKey { case expectedGeneration = "expected_generation", operationOrder = "operation_order" } }
    struct SchemaBinding: Decodable { let schemaID: String; let version: String; let relativePath: String; let sha256: String; enum CodingKeys: String, CodingKey { case schemaID = "schema_id", version, relativePath = "relative_path", sha256 } }
    struct FileBinding: Decodable { let relativePath: String; let byteLength: Int; let sha256: String; enum CodingKeys: String, CodingKey { case relativePath = "relative_path", byteLength = "byte_length", sha256 } }
}

private struct FixtureCases: Decodable {
    let identity: Identity
    let operationInventory: [String]
    let cases: [Case]
    enum CodingKeys: String, CodingKey { case identity, operationInventory = "operation_inventory", cases }
    struct Identity: Decodable { let authorityID: String; let revisionBranchID: String; let transactionID: String; let idempotencyKey: String; enum CodingKeys: String, CodingKey { case authorityID = "authority_id", revisionBranchID = "revision_branch_id", transactionID = "transaction_id", idempotencyKey = "idempotency_key" } }
    struct Case: Decodable { let caseID: String; enum CodingKeys: String, CodingKey { case caseID = "case_id" } }
}

private struct FixtureTraces: Decodable {
    let traces: [Trace]
    struct Trace: Decodable { let traceID: String; let events: [Event]; let networkReads: Int?; let sourceTransactionImmutable: Bool?; enum CodingKeys: String, CodingKey { case traceID = "trace_id", events, networkReads = "network_reads", sourceTransactionImmutable = "source_transaction_immutable" } }
    struct Event: Decodable { let sceneRevision: UInt64; let mutationCount: UInt64?; enum CodingKeys: String, CodingKey { case sceneRevision = "scene_revision", mutationCount = "mutation_count" } }
}
