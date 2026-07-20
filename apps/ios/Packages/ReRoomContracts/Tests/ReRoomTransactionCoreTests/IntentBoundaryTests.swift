import Foundation
@testable import ReRoomTransactionCore
import Testing

@Suite("Strict local intent boundary")
struct IntentBoundaryTests {
    @Test("tap and typed ingress share one trusted context-bound proposal type")
    func tapAndTypedAreEquivalent() throws {
        let scene = IntentFixtures.scene
        let bytes = IntentFixtures.placeIntent
        let sceneBefore = try IntentFixtures.encode(scene)

        let typed = try IntentBoundary.submitUserIntent(
            bytes,
            source: .typed,
            trustedContext: IntentFixtures.context,
            currentScene: scene
        )
        let tap = try IntentBoundary.submitUserIntent(
            bytes,
            source: .tap,
            trustedContext: IntentFixtures.context,
            currentScene: scene
        )

        #expect(type(of: typed) == BoundProposal.self)
        #expect(type(of: tap) == BoundProposal.self)
        #expect(typed.schemaVersion == "1.0.0")
        #expect(typed.sessionID == tap.sessionID)
        #expect(typed.revisionAuthority == tap.revisionAuthority)
        #expect(typed.baseSceneRevision == tap.baseSceneRevision)
        #expect(typed.targetContext == tap.targetContext)
        #expect(typed.intent.operation == tap.intent.operation)
        #expect(typed.intent.arguments == tap.intent.arguments)
        #expect(typed.intent.constraints == tap.intent.constraints)
        #expect(typed.intent.source == "typed")
        #expect(tap.intent.source == "tap")
        #expect(try IntentFixtures.encode(scene) == sceneBefore)
        #expect(scene.editHistory.isEmpty)
    }

    @Test(
        "forbidden malformed empty oversized and injected input rejects without mutation",
        arguments: IntentAttack.allCases
    )
    func attacksRejectWithoutMutation(attack: IntentAttack) throws {
        let scene = IntentFixtures.scene
        let sceneBefore = try IntentFixtures.encode(scene)
        #expect(throws: attack.expected) {
            try IntentBoundary.submitUserIntent(
                attack.bytes,
                source: .typed,
                trustedContext: IntentFixtures.context,
                currentScene: scene
            )
        }
        #expect(try IntentFixtures.encode(scene) == sceneBefore)
        #expect(scene.editHistory.isEmpty)
    }

    @Test("stale trusted context and optional voice reject locally")
    func staleContextAndVoiceReject() throws {
        let scene = IntentFixtures.scene
        let stale = TrustedIntentContext(
            sessionID: scene.sessionID,
            revisionAuthority: scene.revisionAuthority,
            baseSceneRevision: scene.sceneRevision - 1,
            targetContext: IntentFixtures.context.targetContext
        )
        #expect(throws: IntentBoundaryRejection.staleContext) {
            try IntentBoundary.submitUserIntent(IntentFixtures.placeIntent, source: .typed, trustedContext: stale, currentScene: scene)
        }
        #expect(throws: IntentBoundaryRejection.voiceUnavailable) {
            try IntentBoundary.submitUserIntent(IntentFixtures.placeIntent, source: .voice, trustedContext: IntentFixtures.context, currentScene: scene)
        }
    }

    @Test("model-assisted voice binds provenance without gaining trusted authority")
    func modelAssistedVoiceBindsProvenance() throws {
        let model = SemanticModelReference(
            contractProvider: "openai",
            model: "gpt-realtime-2.1",
            responseID: "resp_10000000-0000-4000-8000-000000000001"
        )

        let proposal = try IntentBoundary.submitUserIntent(
            IntentFixtures.placeIntent,
            source: .voice,
            trustedContext: IntentFixtures.context,
            currentScene: IntentFixtures.scene,
            semanticModel: model
        )

        #expect(proposal.intent.source == "voice")
        #expect(proposal.intent.semanticModel == model)
        #expect(proposal.sessionID == IntentFixtures.context.sessionID)
        #expect(proposal.baseSceneRevision == IntentFixtures.context.baseSceneRevision)
        #expect(proposal.targetContext == IntentFixtures.context.targetContext)
        #expect(IntentFixtures.scene.editHistory.isEmpty)
    }

    @Test("invalid model provenance rejects before a proposal is created")
    func invalidModelProvenanceRejects() {
        let invalid = SemanticModelReference(
            contractProvider: "openai",
            model: "",
            responseID: "resp_10000000-0000-4000-8000-000000000001"
        )

        #expect(throws: IntentBoundaryRejection.invalidValue) {
            try IntentBoundary.submitUserIntent(
                IntentFixtures.placeIntent,
                source: .voice,
                trustedContext: IntentFixtures.context,
                currentScene: IntentFixtures.scene,
                semanticModel: invalid
            )
        }

        let oversizedResponse = SemanticModelReference(
            contractProvider: "openai",
            model: "gpt-5.6-sol",
            responseID: String(repeating: "r", count: 129)
        )
        #expect(throws: IntentBoundaryRejection.invalidValue) {
            try IntentBoundary.submitUserIntent(
                IntentFixtures.placeIntent,
                source: .voice,
                trustedContext: IntentFixtures.context,
                currentScene: IntentFixtures.scene,
                semanticModel: oversizedResponse
            )
        }
    }

    @Test("parallel local submissions remain deterministic and isolated")
    func concurrentSubmissionsAreDeterministic() async throws {
        let proposals = try await withThrowingTaskGroup(of: BoundProposal.self) { group in
            for _ in 0..<32 {
                group.addTask {
                    try IntentBoundary.submitUserIntent(
                        IntentFixtures.placeIntent,
                        source: .typed,
                        trustedContext: IntentFixtures.context,
                        currentScene: IntentFixtures.scene
                    )
                }
            }
            var values = [BoundProposal]()
            for try await proposal in group { values.append(proposal) }
            return values
        }
        #expect(proposals.count == 32)
        let digests = try proposals.map {
            try TransactionFingerprint.digest(
                proposal: $0,
                proposedOperations: [TransactionTestFixtures.createFirstAssetOperation()]
            )
        }
        #expect(Set(digests).count == 1)
    }

    @Test(
        "each of the seven included members changes the request fingerprint",
        arguments: FingerprintIncludedMutation.allCases
    )
    func includedFingerprintMembersAreExact(mutation: FingerprintIncludedMutation) throws {
        let base = IntentFixtures.fingerprintScope
        let baseline = try TransactionFingerprint.digest(base)
        #expect(try TransactionFingerprint.digest(mutation.apply(to: base)) != baseline)
    }

    @Test("fingerprint scope has exactly seven members and excludes transaction lifecycle metadata")
    func fingerprintExclusionsAreExact() throws {
        let scope = IntentFixtures.fingerprintScope
        let canonical = try TransactionFingerprint.canonicalData(scope)
        let object = try #require(JSONSerialization.jsonObject(with: canonical) as? [String: Any])
        #expect(Set(object.keys) == [
            "schema_version",
            "session_id",
            "revision_authority",
            "base_scene_revision",
            "target_context",
            "intent",
            "proposed_operations",
        ])

        let first = IntentFixtures.record(canonicalState: .draft, syncState: .localOnly, transactionID: "tx_40000000-0000-4000-8000-000000000001")
        let second = IntentFixtures.record(canonicalState: .cancelled, syncState: .syncFailed, transactionID: "tx_40000000-0000-4000-8000-000000000002")
        #expect(try TransactionFingerprint.digest(first) == TransactionFingerprint.digest(second))
        #expect(try TransactionFingerprint.digest(first) == TransactionFingerprint.digest(scope))
    }
}

enum IntentAttack: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case empty
    case malformed
    case duplicateKey
    case unknownField
    case emptyAsset
    case oversized
    case transformInjection
    case urlInjection
    case constraintURLInjection
    case confirmationInjection
    case authorityInjection
    case revisionInjection
    case sessionInjection
    case targetInjection
    case toolInjection
    case unsortedConstraints
    case duplicateConstraints

    var testDescription: String { rawValue }

    var expected: IntentBoundaryRejection {
        switch self {
        case .empty: .emptyInput
        case .malformed, .duplicateKey: .malformedJSON
        case .oversized: .oversized
        case .emptyAsset, .urlInjection, .constraintURLInjection: .invalidValue
        case .unsortedConstraints, .duplicateConstraints: .invalidConstraintOrder
        default: .unknownOrForbiddenField
        }
    }

    var bytes: Data {
        switch self {
        case .empty: Data()
        case .malformed: Data("{".utf8)
        case .duplicateKey: Data("{\"operation\":\"remove\",\"operation\":\"restore\",\"arguments\":{},\"constraints\":[]}".utf8)
        case .unknownField: IntentFixtures.inject("unknown", value: true)
        case .emptyAsset: Data("{\"operation\":\"place\",\"arguments\":{\"asset_id\":\"\"},\"constraints\":[]}".utf8)
        case .oversized: Data(repeating: 0x20, count: IntentBoundary.maximumIntentBytes + 1)
        case .transformInjection: IntentFixtures.inject("world_from_asset", value: [1, 0, 0, 0])
        case .urlInjection: Data("{\"operation\":\"place\",\"arguments\":{\"catalog_query\":\"https://example.invalid/chair\"},\"constraints\":[]}".utf8)
        case .constraintURLInjection:
            Data("{\"operation\":\"place\",\"arguments\":{\"asset_id\":\"asset_10000000-0000-4000-8000-000000000020\"},\"constraints\":[{\"kind\":\"style_tag\",\"value\":\"https://example.invalid/style\"}]}".utf8)
        case .confirmationInjection: IntentFixtures.inject("confirmed", value: true)
        case .authorityInjection: IntentFixtures.inject("revision_authority", value: ["kind": "native_device"])
        case .revisionInjection: IntentFixtures.inject("committed_scene_revision", value: 99)
        case .sessionInjection: IntentFixtures.inject("session_id", value: TransactionTestFixtures.sessionID)
        case .targetInjection: IntentFixtures.inject("selected_object_id", value: TransactionTestFixtures.objectIDs[0])
        case .toolInjection: IntentFixtures.inject("tool", value: "deploy")
        case .unsortedConstraints:
            Data("{\"operation\":\"place\",\"arguments\":{\"asset_id\":\"asset_10000000-0000-4000-8000-000000000020\"},\"constraints\":[{\"kind\":\"support_required\",\"value\":true},{\"kind\":\"color_tag\",\"value\":\"blue\"}]}".utf8)
        case .duplicateConstraints:
            Data("{\"operation\":\"place\",\"arguments\":{\"asset_id\":\"asset_10000000-0000-4000-8000-000000000020\"},\"constraints\":[{\"kind\":\"color_tag\",\"value\":\"blue\"},{\"kind\":\"color_tag\",\"value\":\"blue\"}]}".utf8)
        }
    }
}

enum FingerprintIncludedMutation: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case schemaVersion
    case sessionID
    case revisionAuthority
    case baseSceneRevision
    case targetContext
    case intent
    case proposedOperations

    var testDescription: String { rawValue }

    func apply(to value: TransactionFingerprintScope) -> TransactionFingerprintScope {
        var schema = value.schemaVersion
        var session = value.sessionID
        var authority = value.revisionAuthority
        var revision = value.baseSceneRevision
        var target = value.targetContext
        var intent = value.intent
        var operations = value.proposedOperations
        switch self {
        case .schemaVersion: schema = "1.0.1"
        case .sessionID: session = "session_40000000-0000-4000-8000-000000000003"
        case .revisionAuthority:
            authority = RevisionAuthority(kind: .nativeDevice, authorityID: "device_40000000-0000-4000-8000-000000000004", revisionBranchID: authority.revisionBranchID)
        case .baseSceneRevision: revision += 1
        case .targetContext:
            target = TargetContext(
                contractCapturedAtFrameID: target.capturedAtFrameID,
                capturedSceneRevision: target.capturedSceneRevision,
                worldFrameID: target.worldFrameID,
                worldFrameVersion: target.worldFrameVersion,
                cameraPose: target.cameraPose,
                screenPointEncodedPixels: [2, 3],
                candidateObjectIDs: target.candidateObjectIDs,
                selectedObjectID: target.selectedObjectID,
                artifactRefs: target.artifactRefs
            )
        case .intent:
            intent = TransactionIntent(contractOperation: .place, source: intent.source, arguments: intent.arguments, constraints: [TypedConstraint(contractKind: "color_tag", value: .string("blue"))])
        case .proposedOperations:
            operations = [.createAssetInstance(
                entityID: "assetinst_40000000-0000-4000-8000-000000000005",
                before: nil,
                after: TransactionTestFixtures.createFirstAssetOperation().assetInstanceAfter!,
                requiredArtifactRefs: [TransactionTestFixtures.firstManifest]
            )]
        }
        return TransactionFingerprintScope(
            schemaVersion: schema,
            sessionID: session,
            revisionAuthority: authority,
            baseSceneRevision: revision,
            targetContext: target,
            intent: intent,
            proposedOperations: operations
        )
    }
}

enum IntentFixtures {
    static let scene = TransactionTestFixtures.scene(revision: 8)
    static let targetContext = TargetContext(
        contractCapturedAtFrameID: TransactionTestFixtures.frameID,
        capturedSceneRevision: 8,
        worldFrameID: TransactionTestFixtures.worldID,
        worldFrameVersion: 1,
        cameraPose: TransactionTestFixtures.identity,
        screenPointEncodedPixels: [1, 1],
        candidateObjectIDs: TransactionTestFixtures.objectIDs,
        selectedObjectID: nil,
        artifactRefs: []
    )
    static let context = TrustedIntentContext(
        sessionID: TransactionTestFixtures.sessionID,
        revisionAuthority: RevisionAuthority(kind: .nativeDevice, authorityID: TransactionTestFixtures.deviceID, revisionBranchID: TransactionTestFixtures.branchID),
        baseSceneRevision: 8,
        targetContext: targetContext
    )
    static let placeIntent = Data("{\"operation\":\"place\",\"arguments\":{\"asset_id\":\"asset_10000000-0000-4000-8000-000000000020\"},\"constraints\":[{\"kind\":\"color_tag\",\"value\":\"blue\"},{\"kind\":\"support_required\",\"value\":true}]}".utf8)
    static let fingerprintScope = TransactionFingerprintScope(
        schemaVersion: "1.0.0",
        sessionID: context.sessionID,
        revisionAuthority: context.revisionAuthority,
        baseSceneRevision: context.baseSceneRevision,
        targetContext: context.targetContext,
        intent: TransactionIntent(
            contractOperation: .place,
            source: "typed",
            arguments: IntentArguments(assetID: "asset_10000000-0000-4000-8000-000000000020"),
            constraints: []
        ),
        proposedOperations: [TransactionTestFixtures.createFirstAssetOperation()]
    )

    static func inject(_ key: String, value: Any) -> Data {
        var object = try! JSONSerialization.jsonObject(with: placeIntent) as! [String: Any]
        object[key] = value
        return try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    static func record(
        canonicalState: TransactionCanonicalState,
        syncState: TransactionSyncState,
        transactionID: String
    ) -> TransactionRecord {
        TransactionRecord(
            transactionID: transactionID,
            idempotencyKey: "txidem_40000000-0000-4000-8000-000000000006",
            requestFingerprintSHA256: String(repeating: "0", count: 64),
            sessionID: fingerprintScope.sessionID,
            revisionAuthority: fingerprintScope.revisionAuthority,
            baseSceneRevision: fingerprintScope.baseSceneRevision,
            targetContext: fingerprintScope.targetContext,
            intent: fingerprintScope.intent,
            proposedOperations: fingerprintScope.proposedOperations,
            validation: TransactionValidation(contractState: "not_run", checks: [], validatorVersion: "test", inputSHA256: String(repeating: "0", count: 64)),
            canonicalState: canonicalState,
            syncState: syncState,
            createdAtUTC: transactionID.hasSuffix("1") ? "2026-07-18T00:00:00Z" : "2026-07-19T00:00:00Z"
        )
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}

private extension TransactionOperation {
    var assetInstanceAfter: AssetInstanceSnapshot? {
        guard case .createAssetInstance(_, _, let after, _) = self else { return nil }
        return after
    }
}
