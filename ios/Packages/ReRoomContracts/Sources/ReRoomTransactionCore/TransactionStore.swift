import Foundation
import ReRoomContracts

public struct PersistentIdempotencyRecord: Codable, Equatable, Sendable {
    public let idempotencyKey: String
    public let requestFingerprintSHA256: String
    public let transactionID: String
    public let receipt: TransactionReceipt

    public init(
        idempotencyKey: String,
        requestFingerprintSHA256: String,
        transactionID: String,
        receipt: TransactionReceipt
    ) {
        self.idempotencyKey = idempotencyKey
        self.requestFingerprintSHA256 = requestFingerprintSHA256
        self.transactionID = transactionID
        self.receipt = receipt
    }

    enum CodingKeys: String, CodingKey {
        case idempotencyKey = "idempotency_key"
        case requestFingerprintSHA256 = "request_fingerprint_sha256"
        case transactionID = "transaction_id"
        case receipt
    }
}

public struct TransactionGenerationCandidate: Equatable, Sendable {
    public let scene: SceneState
    public let transactions: [TransactionRecord]
    public let requiredArtifacts: [ArtifactReference]
    public let receipts: [TransactionReceipt]
    public let idempotencyRecords: [PersistentIdempotencyRecord]

    public init(
        scene: SceneState,
        transactions: [TransactionRecord],
        requiredArtifacts: [ArtifactReference],
        receipts: [TransactionReceipt],
        idempotencyRecords: [PersistentIdempotencyRecord]
    ) {
        self.scene = scene
        self.transactions = transactions
        self.requiredArtifacts = requiredArtifacts
        self.receipts = receipts
        self.idempotencyRecords = idempotencyRecords
    }
}

public struct TransactionGenerationSnapshot: Codable, Equatable, Sendable {
    public let generationSHA256: String
    public let scene: SceneState
    public let transactions: [TransactionRecord]
    public let requiredArtifacts: [ArtifactReference]
    public let receipts: [TransactionReceipt]
    public let idempotencyRecords: [PersistentIdempotencyRecord]

    public init(
        generationSHA256: String,
        scene: SceneState,
        transactions: [TransactionRecord],
        requiredArtifacts: [ArtifactReference],
        receipts: [TransactionReceipt],
        idempotencyRecords: [PersistentIdempotencyRecord]
    ) {
        self.generationSHA256 = generationSHA256
        self.scene = scene
        self.transactions = transactions
        self.requiredArtifacts = requiredArtifacts
        self.receipts = receipts
        self.idempotencyRecords = idempotencyRecords
    }

    public var candidate: TransactionGenerationCandidate {
        TransactionGenerationCandidate(
            scene: scene,
            transactions: transactions,
            requiredArtifacts: requiredArtifacts,
            receipts: receipts,
            idempotencyRecords: idempotencyRecords
        )
    }
}

public enum TransactionStoreDiagnostic: String, Codable, Equatable, Sendable {
    case activePointerInvalid = "active_pointer_invalid"
    case generationInventoryInvalid = "generation_inventory_invalid"
    case generationMemberMissing = "generation_member_missing"
    case memberDigestMismatch = "member_digest_mismatch"
    case contractRejected = "contract_rejected"
    case semanticMismatch = "semantic_mismatch"
    case ioFailure = "io_failure"
}

public enum TransactionStoreRecovery: Equatable, Sendable {
    case noActiveGeneration
    case active(TransactionGenerationSnapshot)
    case corrupt(TransactionStoreDiagnostic)
}

public enum TransactionStoreError: String, Error, Equatable, Sendable {
    case semanticMismatch = "semantic_mismatch"
    case contractRejected = "contract_rejected"
    case incompleteGeneration = "incomplete_generation"
    case ioFailure = "io_failure"
}

public enum TransactionIntegrity {
    public static func commitResultSHA256(
        authorityID: String,
        revisionBranchID: String,
        compareAndSwapBaseRevision: UInt64,
        committedSceneRevision: UInt64,
        confirmation: ExplicitConfirmation,
        committedAtUTC: String,
        localDurableBeforeVisibleAck: Bool
    ) throws -> String {
        let scope = CommitResultScope(
            authorityID: authorityID,
            revisionBranchID: revisionBranchID,
            compareAndSwapBaseRevision: compareAndSwapBaseRevision,
            committedSceneRevision: committedSceneRevision,
            confirmation: confirmation,
            committedAtUTC: committedAtUTC,
            localDurableBeforeVisibleAck: localDurableBeforeVisibleAck,
            resultSHA256Algorithm: "RR-JCS-SHA256-1",
            resultSHA256Scope: "commit_object_with_result_sha256_member_omitted"
        )
        return try digest(scope)
    }

    static func inverseOperationsSHA256(_ operations: [TransactionOperation]) throws -> String {
        try digest(operations)
    }

    public static func requiredArtifactUnion(
        scene: SceneState,
        transactions: [TransactionRecord]
    ) throws -> [ArtifactReference] {
        try TransactionStore.requiredArtifactUnion(scene: scene, transactions: transactions)
    }

    private static func digest<Value: Encodable>(_ value: Value) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try CanonicalJSON.digest(jsonData: encoder.encode(value))
    }
}

public struct TransactionStore: Sendable {
    private let fileSystem: TransactionFileSystemAdapter
    private let contracts: TransactionContractAdapter

    public init(
        fileSystem: TransactionFileSystemAdapter,
        contracts: TransactionContractAdapter
    ) {
        self.fileSystem = fileSystem
        self.contracts = contracts
    }

    public static func generationSHA256(for candidate: TransactionGenerationCandidate) throws -> String {
        try makeEncodedGeneration(candidate).generationSHA256
    }

    public func validateCandidate(_ candidate: TransactionGenerationCandidate) throws {
        let encoded = try Self.makeEncodedGeneration(candidate)
        try validate(encoded: encoded, expectedCandidate: candidate)
    }

    @discardableResult
    public func activate(_ candidate: TransactionGenerationCandidate) throws -> TransactionGenerationSnapshot {
        let encoded = try Self.makeEncodedGeneration(candidate)
        try validate(encoded: encoded, expectedCandidate: candidate)

        do {
            try fileSystem.prepareRoot()
            if try fileSystem.generationExists(encoded.generationSHA256) {
                guard case .active(let existing) = recoverGeneration(
                    digest: encoded.generationSHA256,
                    pointer: encoded.pointer
                ) else { throw TransactionStoreError.incompleteGeneration }
                try fileSystem.activatePointer(encoded.pointerData)
                return existing
            }

            try fileSystem.createGeneration(encoded.generationSHA256)
            for name in EncodedGeneration.payloadMemberNames {
                try fileSystem.writeGenerationMember(
                    encoded.members[name]!,
                    named: name,
                    generation: encoded.generationSHA256
                )
            }
            try fileSystem.writeGenerationMember(
                encoded.inventoryData,
                named: "inventory.json",
                generation: encoded.generationSHA256
            )
            try fileSystem.finishGeneration(encoded.generationSHA256)
            try fileSystem.activatePointer(encoded.pointerData)
            return encoded.snapshot
        } catch let error as TransactionStoreError {
            throw error
        } catch {
            throw error
        }
    }

    public func recover() -> TransactionStoreRecovery {
        do {
            guard try fileSystem.activePointerExists() else { return .noActiveGeneration }
            let pointerData = try fileSystem.readActivePointer()
            let pointer: ActiveGenerationPointer
            do {
                pointer = try Self.decodeExact(ActiveGenerationPointer.self, from: pointerData)
            } catch {
                return .corrupt(.activePointerInvalid)
            }
            guard Self.validSHA256(pointer.generationSHA256) else {
                return .corrupt(.activePointerInvalid)
            }
            return recoverGeneration(digest: pointer.generationSHA256, pointer: pointer)
        } catch {
            return .corrupt(.ioFailure)
        }
    }

    private func recoverGeneration(
        digest: String,
        pointer: ActiveGenerationPointer
    ) -> TransactionStoreRecovery {
        do {
            guard try fileSystem.generationMemberExists("inventory.json", generation: digest) else {
                return .corrupt(.generationMemberMissing)
            }
            let inventoryData = try fileSystem.readGenerationMember("inventory.json", generation: digest)
            guard CanonicalJSON.sha256Hex(inventoryData) == digest else {
                return .corrupt(.generationInventoryInvalid)
            }
            let inventory: GenerationInventory
            do {
                inventory = try Self.decodeExact(GenerationInventory.self, from: inventoryData)
            } catch {
                return .corrupt(.generationInventoryInvalid)
            }
            guard inventory.schemaVersion == "1.0.0",
                  inventory.sceneID == pointer.sceneID,
                  inventory.revisionBranchID == pointer.revisionBranchID,
                  inventory.sceneRevision == pointer.sceneRevision,
                  inventory.members.map(\.name) == EncodedGeneration.payloadMemberNames
            else { return .corrupt(.generationInventoryInvalid) }

            var members = [String: Data]()
            for member in inventory.members {
                guard try fileSystem.generationMemberExists(member.name, generation: digest) else {
                    return .corrupt(.generationMemberMissing)
                }
                let data = try fileSystem.readGenerationMember(member.name, generation: digest)
                guard data.count == member.byteCount,
                      CanonicalJSON.sha256Hex(data) == member.sha256
                else { return .corrupt(.memberDigestMismatch) }
                members[member.name] = data
            }
            let encoded = try Self.decodeMembers(
                members,
                inventory: inventory,
                inventoryData: inventoryData,
                pointer: pointer
            )
            do {
                try validate(encoded: encoded, expectedCandidate: encoded.snapshot.candidate)
            } catch TransactionStoreError.contractRejected {
                return .corrupt(.contractRejected)
            } catch {
                return .corrupt(.semanticMismatch)
            }
            return .active(encoded.snapshot)
        } catch {
            return .corrupt(.ioFailure)
        }
    }

    private func validate(
        encoded: EncodedGeneration,
        expectedCandidate candidate: TransactionGenerationCandidate
    ) throws {
        do {
            let scene = try contracts.decodeSceneState(encoded.members["scene.json"]!)
            guard scene.value == candidate.scene else { throw TransactionStoreError.semanticMismatch }
            for (index, transaction) in candidate.transactions.enumerated() {
                let bytes = try Self.canonicalData(transaction)
                let validated = try contracts.decodeTransaction(bytes)
                guard validated.value == transaction,
                      encoded.history.transactions[index] == transaction
                else { throw TransactionStoreError.semanticMismatch }
            }
        } catch let error as TransactionStoreError {
            throw error
        } catch {
            throw TransactionStoreError.contractRejected
        }
        try Self.validateSemantic(candidate, inverseIndex: encoded.inverseIndex.entries)
    }

    private static func validateSemantic(
        _ candidate: TransactionGenerationCandidate,
        inverseIndex: [InverseIndexEntry]
    ) throws {
        let scene = candidate.scene
        let projection = try EditProjectionEngine.build(from: scene)
        let transactions = candidate.transactions
        guard Set(transactions.map(\.transactionID)).count == transactions.count,
              Set(candidate.receipts.map(\.transactionID)).count == candidate.receipts.count,
              Set(candidate.idempotencyRecords.map(\.idempotencyKey)).count == candidate.idempotencyRecords.count,
              candidate.receipts.count == transactions.count,
              candidate.idempotencyRecords.count == transactions.count,
              inverseIndex.count == transactions.count
        else { throw TransactionStoreError.semanticMismatch }

        if transactions.isEmpty {
            guard scene.editHistory.isEmpty,
                  candidate.receipts.isEmpty,
                  candidate.idempotencyRecords.isEmpty,
                  inverseIndex.isEmpty
            else { throw TransactionStoreError.semanticMismatch }
        } else {
            var priorRevision: UInt64?
            var expectedHistory = [EditReference]()
            for (index, transaction) in transactions.enumerated() {
                guard transaction.canonicalState == .committed,
                      transaction.syncState == .localOnly || transaction.syncState == .pendingSync,
                      transaction.validation.state == "passed",
                      let preview = transaction.preview,
                      let commit = transaction.commit,
                      let inverse = transaction.inverseOperations,
                      inverse.count == 1,
                      transaction.localUndoToken != nil,
                      transaction.sessionID == scene.sessionID,
                      transaction.revisionAuthority == scene.revisionAuthority,
                      transaction.targetContext.worldFrameID == scene.worldFrame.worldFrameID,
                      transaction.targetContext.worldFrameVersion == scene.worldFrame.worldFrameVersion,
                      transaction.baseSceneRevision == commit.compareAndSwapBaseRevision,
                      commit.committedSceneRevision == transaction.baseSceneRevision + 1,
                      commit.authorityID == transaction.revisionAuthority.authorityID,
                      commit.revisionBranchID == transaction.revisionAuthority.revisionBranchID,
                      preview.baseSceneRevision == transaction.baseSceneRevision,
                      commit.confirmation.previewID == preview.previewID,
                      commit.confirmation.kind == "explicit_user_confirmation",
                      transaction.requestFingerprintSHA256 == (try TransactionFingerprint.digest(transaction)),
                      commit.resultSHA256 == (try TransactionIntegrity.commitResultSHA256(
                          authorityID: commit.authorityID,
                          revisionBranchID: commit.revisionBranchID,
                          compareAndSwapBaseRevision: commit.compareAndSwapBaseRevision,
                          committedSceneRevision: commit.committedSceneRevision,
                          confirmation: commit.confirmation,
                          committedAtUTC: commit.committedAtUTC,
                          localDurableBeforeVisibleAck: commit.localDurableBeforeVisibleAck
                      )),
                      priorRevision == nil || commit.committedSceneRevision == priorRevision! + 1
                else { throw TransactionStoreError.semanticMismatch }
                priorRevision = commit.committedSceneRevision
                expectedHistory.append(EditReference(
                    contractTransactionID: transaction.transactionID,
                    operation: transaction.intent.operation,
                    committedSceneRevision: commit.committedSceneRevision
                ))

                guard case .restoreSnapshot(_, let inverseBefore, let inverseAfter, let inverseRefs) = inverse[0] else {
                    throw TransactionStoreError.semanticMismatch
                }
                try EditProjectionEngine.validate(inverseBefore)
                try EditProjectionEngine.validate(inverseAfter)
                try EditProjectionEngine.verifyRequiredArtifactReferences(inverseRefs, for: inverseAfter.projection)
                let touched = try EditProjectionEngine.diff(
                    sourceBefore: inverseAfter.projection,
                    sourceAfter: inverseBefore.projection
                )
                try EditProjectionEngine.verify(touched: touched, against: transaction.proposedOperations)
                guard inverseIndex[index] == InverseIndexEntry(
                    transactionID: transaction.transactionID,
                    inverseOperationsSHA256: try TransactionIntegrity.inverseOperationsSHA256(inverse),
                    requiredArtifactRefs: inverseRefs
                ) else { throw TransactionStoreError.semanticMismatch }

                let receipt = candidate.receipts[index]
                guard receipt == TransactionReceipt(
                    contractTransactionID: transaction.transactionID,
                    idempotencyKey: transaction.idempotencyKey,
                    requestFingerprintSHA256: transaction.requestFingerprintSHA256,
                    revisionAuthority: transaction.revisionAuthority,
                    committedSceneRevision: commit.committedSceneRevision,
                    resultSHA256: commit.resultSHA256
                ) else { throw TransactionStoreError.semanticMismatch }
                let idempotency = candidate.idempotencyRecords[index]
                guard idempotency == PersistentIdempotencyRecord(
                    idempotencyKey: transaction.idempotencyKey,
                    requestFingerprintSHA256: transaction.requestFingerprintSHA256,
                    transactionID: transaction.transactionID,
                    receipt: receipt
                ) else { throw TransactionStoreError.semanticMismatch }
            }
            guard scene.editHistory == expectedHistory,
                  transactions.last?.commit?.committedSceneRevision == scene.sceneRevision,
                  transactions.last?.inverseOperations?.first?.restoreBeforeProjection.map({
                      currentProjectionPreservesCommittedEdit($0, current: projection)
                  }) == true
            else { throw TransactionStoreError.semanticMismatch }
        }

        let exactArtifacts = try requiredArtifactUnion(scene: scene, transactions: transactions)
        guard candidate.requiredArtifacts == exactArtifacts else {
            throw TransactionStoreError.semanticMismatch
        }
    }

    /// Semantic tracking may discover additional objects without allocating an edit
    /// revision. The last committed inverse remains authoritative for every object it
    /// knew about, while newly tracked object edit states are allowed as an additive
    /// superset. Asset instances and their support relations remain transaction-only
    /// and therefore must still match exactly.
    private static func currentProjectionPreservesCommittedEdit(
        _ committed: EditProjection,
        current: EditProjection
    ) -> Bool {
        guard committed.sceneID == current.sceneID,
              committed.revisionBranchID == current.revisionBranchID,
              committed.worldFrameID == current.worldFrameID,
              committed.worldFrameVersion == current.worldFrameVersion,
              committed.placedAssets == current.placedAssets,
              committed.assetSupportRelations == current.assetSupportRelations
        else { return false }

        let currentObjects = Dictionary(
            uniqueKeysWithValues: current.objectEditStates.map { ($0.objectID, $0) }
        )
        return committed.objectEditStates.allSatisfy { currentObjects[$0.objectID] == $0 }
    }

    fileprivate static func requiredArtifactUnion(
        scene: SceneState,
        transactions: [TransactionRecord]
    ) throws -> [ArtifactReference] {
        var values = try EditProjectionEngine.requiredArtifactReferences(
            for: EditProjectionEngine.build(from: scene)
        )
        for transaction in transactions {
            for operation in transaction.proposedOperations + (transaction.inverseOperations ?? []) {
                values.append(contentsOf: operation.requiredArtifactReferences)
            }
        }
        var byID = [String: ArtifactReference]()
        for value in values {
            if let prior = byID[value.artifactID], prior != value {
                throw TransactionStoreError.semanticMismatch
            }
            byID[value.artifactID] = value
        }
        return byID.values.sorted(by: artifactLessThan)
    }

    private static func makeEncodedGeneration(_ candidate: TransactionGenerationCandidate) throws -> EncodedGeneration {
        let history = TransactionHistoryEnvelope(transactions: candidate.transactions)
        let inverse = InverseIndexEnvelope(entries: try candidate.transactions.map { transaction in
            let operations = transaction.inverseOperations ?? []
            return InverseIndexEntry(
                transactionID: transaction.transactionID,
                inverseOperationsSHA256: try TransactionIntegrity.inverseOperationsSHA256(operations),
                requiredArtifactRefs: operations.flatMap(\.requiredArtifactReferences)
            )
        })
        let artifacts = ArtifactInventoryEnvelope(artifacts: candidate.requiredArtifacts)
        let receipts = ReceiptEnvelope(receipts: candidate.receipts)
        let idempotency = IdempotencyEnvelope(records: candidate.idempotencyRecords)
        let members: [String: Data] = [
            "scene.json": try canonicalData(candidate.scene),
            "transactions.json": try canonicalData(history),
            "inverse-index.json": try canonicalData(inverse),
            "artifacts.json": try canonicalData(artifacts),
            "receipts.json": try canonicalData(receipts),
            "idempotency.json": try canonicalData(idempotency),
        ]
        let bindings = EncodedGeneration.payloadMemberNames.map { name in
            GenerationMember(
                name: name,
                byteCount: members[name]!.count,
                sha256: CanonicalJSON.sha256Hex(members[name]!)
            )
        }
        let inventory = GenerationInventory(
            sceneID: candidate.scene.sceneID,
            revisionBranchID: candidate.scene.revisionAuthority.revisionBranchID,
            sceneRevision: candidate.scene.sceneRevision,
            members: bindings
        )
        let inventoryData = try canonicalData(inventory)
        let generationSHA256 = CanonicalJSON.sha256Hex(inventoryData)
        let pointer = ActiveGenerationPointer(
            generationSHA256: generationSHA256,
            sceneID: candidate.scene.sceneID,
            revisionBranchID: candidate.scene.revisionAuthority.revisionBranchID,
            sceneRevision: candidate.scene.sceneRevision
        )
        return EncodedGeneration(
            generationSHA256: generationSHA256,
            members: members,
            history: history,
            inverseIndex: inverse,
            inventory: inventory,
            inventoryData: inventoryData,
            pointer: pointer,
            pointerData: try canonicalData(pointer),
            snapshot: TransactionGenerationSnapshot(
                generationSHA256: generationSHA256,
                scene: candidate.scene,
                transactions: candidate.transactions,
                requiredArtifacts: candidate.requiredArtifacts,
                receipts: candidate.receipts,
                idempotencyRecords: candidate.idempotencyRecords
            )
        )
    }

    private static func decodeMembers(
        _ members: [String: Data],
        inventory: GenerationInventory,
        inventoryData: Data,
        pointer: ActiveGenerationPointer
    ) throws -> EncodedGeneration {
        let scene = try decodeExact(SceneState.self, from: members["scene.json"]!)
        let history = try decodeExact(TransactionHistoryEnvelope.self, from: members["transactions.json"]!)
        let inverse = try decodeExact(InverseIndexEnvelope.self, from: members["inverse-index.json"]!)
        let artifacts = try decodeExact(ArtifactInventoryEnvelope.self, from: members["artifacts.json"]!)
        let receipts = try decodeExact(ReceiptEnvelope.self, from: members["receipts.json"]!)
        let idempotency = try decodeExact(IdempotencyEnvelope.self, from: members["idempotency.json"]!)
        let digest = CanonicalJSON.sha256Hex(inventoryData)
        return EncodedGeneration(
            generationSHA256: digest,
            members: members,
            history: history,
            inverseIndex: inverse,
            inventory: inventory,
            inventoryData: inventoryData,
            pointer: pointer,
            pointerData: try canonicalData(pointer),
            snapshot: TransactionGenerationSnapshot(
                generationSHA256: digest,
                scene: scene,
                transactions: history.transactions,
                requiredArtifacts: artifacts.artifacts,
                receipts: receipts.receipts,
                idempotencyRecords: idempotency.records
            )
        )
    }

    private static func decodeExact<Value: Codable & Equatable>(
        _ type: Value.Type,
        from data: Data
    ) throws -> Value {
        let canonical = try CanonicalJSON.canonicalize(jsonData: data)
        guard canonical == data else { throw TransactionStoreError.semanticMismatch }
        let value = try JSONDecoder().decode(type, from: canonical)
        guard try canonicalData(value) == canonical else { throw TransactionStoreError.semanticMismatch }
        return value
    }

    private static func canonicalData<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try CanonicalJSON.canonicalize(jsonData: encoder.encode(value))
    }

    private static func validSHA256(_ value: String) -> Bool {
        value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
    }

    private static func artifactLessThan(_ lhs: ArtifactReference, _ rhs: ArtifactReference) -> Bool {
        if lhs.artifactID != rhs.artifactID { return lhs.artifactID < rhs.artifactID }
        if lhs.artifactRevision != rhs.artifactRevision { return lhs.artifactRevision < rhs.artifactRevision }
        if lhs.artifactType != rhs.artifactType { return lhs.artifactType < rhs.artifactType }
        return lhs.sha256 < rhs.sha256
    }
}

private struct EncodedGeneration {
    static let payloadMemberNames = [
        "scene.json",
        "transactions.json",
        "inverse-index.json",
        "artifacts.json",
        "receipts.json",
        "idempotency.json",
    ]

    let generationSHA256: String
    let members: [String: Data]
    let history: TransactionHistoryEnvelope
    let inverseIndex: InverseIndexEnvelope
    let inventory: GenerationInventory
    let inventoryData: Data
    let pointer: ActiveGenerationPointer
    let pointerData: Data
    let snapshot: TransactionGenerationSnapshot
}

private struct TransactionHistoryEnvelope: Codable, Equatable {
    let schemaVersion = "1.0.0"
    let transactions: [TransactionRecord]
    enum CodingKeys: String, CodingKey { case schemaVersion = "schema_version", transactions }
}

private struct InverseIndexEnvelope: Codable, Equatable {
    let schemaVersion = "1.0.0"
    let entries: [InverseIndexEntry]
    enum CodingKeys: String, CodingKey { case schemaVersion = "schema_version", entries }
}

private struct InverseIndexEntry: Codable, Equatable {
    let transactionID: String
    let inverseOperationsSHA256: String
    let requiredArtifactRefs: [ArtifactReference]
    enum CodingKeys: String, CodingKey {
        case transactionID = "transaction_id"
        case inverseOperationsSHA256 = "inverse_operations_sha256"
        case requiredArtifactRefs = "required_artifact_refs"
    }
}

private struct ArtifactInventoryEnvelope: Codable, Equatable {
    let schemaVersion = "1.0.0"
    let artifacts: [ArtifactReference]
    enum CodingKeys: String, CodingKey { case schemaVersion = "schema_version", artifacts }
}

private struct ReceiptEnvelope: Codable, Equatable {
    let schemaVersion = "1.0.0"
    let receipts: [TransactionReceipt]
    enum CodingKeys: String, CodingKey { case schemaVersion = "schema_version", receipts }
}

private struct IdempotencyEnvelope: Codable, Equatable {
    let schemaVersion = "1.0.0"
    let records: [PersistentIdempotencyRecord]
    enum CodingKeys: String, CodingKey { case schemaVersion = "schema_version", records }
}

private struct GenerationInventory: Codable, Equatable {
    let schemaVersion = "1.0.0"
    let sceneID: String
    let revisionBranchID: String
    let sceneRevision: UInt64
    let members: [GenerationMember]
    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case sceneID = "scene_id"
        case revisionBranchID = "revision_branch_id"
        case sceneRevision = "scene_revision"
        case members
    }
}

private struct GenerationMember: Codable, Equatable {
    let name: String
    let byteCount: Int
    let sha256: String
    enum CodingKeys: String, CodingKey { case name, byteCount = "byte_count", sha256 }
}

private struct ActiveGenerationPointer: Codable, Equatable {
    let schemaVersion = "1.0.0"
    let generationSHA256: String
    let sceneID: String
    let revisionBranchID: String
    let sceneRevision: UInt64
    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generationSHA256 = "generation_sha256"
        case sceneID = "scene_id"
        case revisionBranchID = "revision_branch_id"
        case sceneRevision = "scene_revision"
    }
}

private struct CommitResultScope: Codable {
    let authorityID: String
    let revisionBranchID: String
    let compareAndSwapBaseRevision: UInt64
    let committedSceneRevision: UInt64
    let confirmation: ExplicitConfirmation
    let committedAtUTC: String
    let localDurableBeforeVisibleAck: Bool
    let resultSHA256Algorithm: String
    let resultSHA256Scope: String
    enum CodingKeys: String, CodingKey {
        case authorityID = "authority_id"
        case revisionBranchID = "revision_branch_id"
        case compareAndSwapBaseRevision = "compare_and_swap_base_revision"
        case committedSceneRevision = "committed_scene_revision"
        case confirmation
        case committedAtUTC = "committed_at_utc"
        case localDurableBeforeVisibleAck = "local_durable_before_visible_ack"
        case resultSHA256Algorithm = "result_sha256_algorithm"
        case resultSHA256Scope = "result_sha256_scope"
    }
}

extension TransactionOperation {
    var requiredArtifactReferences: [ArtifactReference] {
        switch self {
        case .createAssetInstance(_, _, _, let refs): refs
        case .setAssetTransform(_, _, _, let refs): refs ?? []
        case .setObjectVisibility(_, _, _, let refs): refs ?? []
        case .setRevealBundle(_, _, _, let refs): refs
        case .restoreSnapshot(_, _, _, let refs): refs
        }
    }

    var restoreBeforeProjection: EditProjection? {
        guard case .restoreSnapshot(_, let before, _, _) = self else { return nil }
        return before.projection
    }
}
