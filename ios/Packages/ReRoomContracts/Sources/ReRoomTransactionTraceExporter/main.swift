import Foundation
import ReRoomCaptureCore
import ReRoomContracts
import ReRoomTransactionCore

private let pinnedManifestSHA256 = "4aceda98f3dcb6bc0cf3efaef63852b67a86ea22b0455eb07d3fb9cdd34b371a"
private let pinnedCasesSHA256 = "ab93381ddc9af5544501f2504c3d4a38f6b7d23d3115ee0fd78d99cc2286de62"
private let pinnedExpectedSHA256 = "cd32be368796d6666205024122a65b6443463e11430852217810aeed6786505d"
private let pinnedSceneSchemaSHA256 = "9c77d27762e20ff5fad24c438e8817a03c770b55be3fc82ea72097c4c273e440"
private let pinnedTransactionSchemaSHA256 = "2a4f6728978db0879b5dfb10f052f6d5280e5cf83ad5600f0cf959626c2399a2"
private let pinnedFramePacketSchemaSHA256 = "d50b19bfb29c6c62c494e3a47deb3c51a933609698f4ff2f9cbfba6ec4252b43"
private let pinnedArchiveSchemaSHA256 = "c97349820ed66fb1a1fdf60ea9afee312f532811602851d01d1e233641730b87"
private let pinnedEditArtifactsSchemaSHA256 = "58dbfc8f152881cbdc31be22f6ab7631ac474bb78537ac2a9254f5ef16bd598f"

private struct TraceFailure: Error { let message: String }

private struct Options {
    let manifest: URL
    let output: URL
    let repositoryRoot: URL
    let implementationRevision: String
}

private struct Manifest: Decodable {
    struct Oracle: Decodable {
        let status: String
        let source: String
        let expectedGeneration: String
        let caseOrder: String
        let operationOrder: [String]

        enum CodingKeys: String, CodingKey {
            case status, source
            case expectedGeneration = "expected_generation"
            case caseOrder = "case_order"
            case operationOrder = "operation_order"
        }
    }
    struct Binding: Decodable {
        let contractID: String
        let schemaID: String
        let version: String
        let relativePath: String
        let byteLength: Int
        let sha256: String

        enum CodingKeys: String, CodingKey {
            case contractID = "contract_id"
            case schemaID = "schema_id"
            case version
            case relativePath = "relative_path"
            case byteLength = "byte_length"
            case sha256
        }
    }
    struct FileBinding: Decodable {
        let relativePath: String
        let mediaType: String
        let byteLength: Int
        let sha256: String

        enum CodingKeys: String, CodingKey {
            case relativePath = "relative_path"
            case mediaType = "media_type"
            case byteLength = "byte_length"
            case sha256
        }
    }

    let schemaVersion: String
    let fixtureID: String
    let fixtureRevision: String
    let subject: String
    let oracle: Oracle
    let schemaBindings: [Binding]
    let files: [FileBinding]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case fixtureID = "fixture_id"
        case fixtureRevision = "fixture_revision"
        case subject, oracle
        case schemaBindings = "schema_bindings"
        case files
    }
}

private struct CasesFixture: Decodable {
    struct Identity: Decodable {
        let sessionID: String
        let sceneID: String
        let authorityID: String
        let revisionBranchID: String
        let transactionID: String
        let idempotencyKey: String

        enum CodingKeys: String, CodingKey {
            case sessionID = "session_id"
            case sceneID = "scene_id"
            case authorityID = "authority_id"
            case revisionBranchID = "revision_branch_id"
            case transactionID = "transaction_id"
            case idempotencyKey = "idempotency_key"
        }
    }
    struct Case: Decodable {
        let caseID: String
        let expected: String
        let rejection: String?

        enum CodingKeys: String, CodingKey {
            case caseID = "case_id"
            case expected, rejection
        }
    }
    let schemaVersion: String
    let fixtureID: String
    let fixtureRevision: String
    let identity: Identity
    let cases: [Case]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case fixtureID = "fixture_id"
        case fixtureRevision = "fixture_revision"
        case identity, cases
    }
}

private struct ExpectedTraces: Decodable {
    let schemaVersion: String
    let fixtureID: String
    let fixtureRevision: String
    let traceFormat: String
    let traces: [JSONValue]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case fixtureID = "fixture_id"
        case fixtureRevision = "fixture_revision"
        case traceFormat = "trace_format"
        case traces
    }
}

private struct LoadedFixture {
    let manifest: Manifest
    let cases: CasesFixture
    let expected: ExpectedTraces
}

private enum IDs {
    static let world = "world_30000000-0000-4000-8000-000000000001"
    static let frame = "frame_30000000-0000-4000-8000-000000000001"
    static let surface = "surface_30000000-0000-4000-8000-000000000001"
    static let asset = "asset_30000000-0000-4000-8000-000000000001"
    static let assetInstance = "assetinst_30000000-0000-4000-8000-000000000001"
    static let support = "support_30000000-0000-4000-8000-000000000001"
    static let artifact = "artifact_30000000-0000-4000-8000-000000000001"
    static let restoreTransaction = "tx_30000000-0000-4000-8000-000000000002"
    static let restoreIdempotency = "txidem_30000000-0000-4000-8000-000000000002"
    static let preview = "preview_30000000-0000-4000-8000-000000000001"
    static let restorePreview = "preview_30000000-0000-4000-8000-000000000002"
    static let user = "user_30000000-0000-4000-8000-000000000001"
    static let event = "event_30000000-0000-4000-8000-000000000001"
    static let restoreEvent = "event_30000000-0000-4000-8000-000000000002"
    static let undo = "undo_30000000-0000-4000-8000-000000000001"
    static let restoreUndo = "undo_30000000-0000-4000-8000-000000000002"
    static let frozenTransaction = "tx_30000000-0000-4000-8000-000000000003"
    static let frozenIdempotency = "txidem_30000000-0000-4000-8000-000000000003"
    static let frozenPreview = "preview_30000000-0000-4000-8000-000000000003"
    static let frozenEvent = "event_30000000-0000-4000-8000-000000000003"
    static let frozenUndo = "undo_30000000-0000-4000-8000-000000000003"
    static let quarantineBranch = "branch_30000000-0000-4000-8000-000000000099"
}

private func fail(_ message: String) -> TraceFailure { TraceFailure(message: message) }

private func parseOptions(_ arguments: [String]) throws -> Options {
    let names = Set(["--manifest", "--output", "--repo-root", "--implementation-revision"])
    guard arguments.count == 8 else { throw fail("exactly four named arguments are required") }
    var values = [String: String]()
    for index in stride(from: 0, to: arguments.count, by: 2) {
        let name = arguments[index]
        guard names.contains(name), values[name] == nil else { throw fail("unsupported or duplicate argument") }
        values[name] = arguments[index + 1]
    }
    guard Set(values.keys) == names,
          let manifest = values["--manifest"], let output = values["--output"],
          let root = values["--repo-root"], let revision = values["--implementation-revision"],
          revision.range(of: #"^git:[0-9a-f]{40}$"#, options: .regularExpression) != nil
    else { throw fail("invalid exact exporter arguments") }
    return Options(
        manifest: URL(fileURLWithPath: manifest).standardizedFileURL,
        output: URL(fileURLWithPath: output).standardizedFileURL,
        repositoryRoot: URL(fileURLWithPath: root).standardizedFileURL,
        implementationRevision: revision
    )
}

private func boundedRegularFile(_ url: URL, maximumBytes: Int = 1_048_576) throws -> Data {
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
    guard values.isRegularFile == true, values.isSymbolicLink != true,
          let size = values.fileSize, size <= maximumBytes
    else { throw fail("input is not a bounded regular file") }
    let data = try Data(contentsOf: url, options: .mappedIfSafe)
    guard data.count == size else { throw fail("input changed while being read") }
    return data
}

private func loadFixture(_ options: Options) throws -> LoadedFixture {
    let rootValues = try options.repositoryRoot.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else { throw fail("repository root is invalid") }
    let manifestData = try boundedRegularFile(options.manifest)
    guard CanonicalJSON.sha256Hex(manifestData) == pinnedManifestSHA256 else { throw fail("transaction fixture manifest drifted") }
    let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
    guard manifest.schemaVersion == "1.0.0", manifest.fixtureID == "FX-TRANSACTION-001",
          manifest.fixtureRevision == "rev-001", manifest.oracle.status == "immutable",
          manifest.oracle.source == "checked_in", manifest.oracle.expectedGeneration == "forbidden_during_verification",
          manifest.oracle.caseOrder == "lexicographic_case_id",
          manifest.oracle.operationOrder == ["place", "replace", "remove", "restore"],
          manifest.files.map(\.relativePath) == ["cases.json", "expected-traces.json"],
          manifest.files.map(\.sha256) == [pinnedCasesSHA256, pinnedExpectedSHA256]
    else { throw fail("transaction fixture policy drifted") }

    for binding in manifest.schemaBindings {
        let url = options.repositoryRoot.appendingPathComponent(binding.relativePath)
        let data = try boundedRegularFile(url)
        guard data.count == binding.byteLength, CanonicalJSON.sha256Hex(data) == binding.sha256 else {
            throw fail("transaction schema binding drifted")
        }
    }
    let fixtureRoot = options.manifest.deletingLastPathComponent()
    func load(_ binding: Manifest.FileBinding) throws -> Data {
        guard !binding.relativePath.contains("/"), binding.mediaType == "application/json" else { throw fail("unsafe fixture file binding") }
        let data = try boundedRegularFile(fixtureRoot.appendingPathComponent(binding.relativePath))
        guard data.count == binding.byteLength, CanonicalJSON.sha256Hex(data) == binding.sha256 else { throw fail("transaction fixture file drifted") }
        return data
    }
    let cases = try JSONDecoder().decode(CasesFixture.self, from: load(manifest.files[0]))
    let expected = try JSONDecoder().decode(ExpectedTraces.self, from: load(manifest.files[1]))
    guard cases.schemaVersion == "1.0.0", cases.fixtureID == manifest.fixtureID, cases.fixtureRevision == manifest.fixtureRevision,
          expected.schemaVersion == "1.0.0", expected.fixtureID == manifest.fixtureID,
          expected.fixtureRevision == manifest.fixtureRevision, expected.traceFormat == "reroom_transaction_trace_v1"
    else { throw fail("transaction fixture identity drifted") }
    return LoadedFixture(manifest: manifest, cases: cases, expected: expected)
}

private func target(_ scene: SceneState) -> TargetContext {
    TargetContext(
        contractCapturedAtFrameID: IDs.frame,
        capturedSceneRevision: scene.sceneRevision,
        worldFrameID: scene.worldFrame.worldFrameID,
        worldFrameVersion: scene.worldFrame.worldFrameVersion,
        cameraPose: matrix,
        screenPointEncodedPixels: [1, 1],
        candidateObjectIDs: [], selectedObjectID: nil, artifactRefs: []
    )
}

private let matrix = Matrix4(values: [
    1, 0, 0, 0, 0, 1, 0, 0,
    0, 0, 1, 0, 0, 0, 0, 1,
])

private func proposal(_ operation: ProductOperation, scene: SceneState, identity: CasesFixture.Identity) -> BoundProposal {
    BoundProposal(
        sessionID: identity.sessionID,
        revisionAuthority: scene.revisionAuthority,
        baseSceneRevision: scene.sceneRevision,
        targetContext: target(scene),
        intent: TransactionIntent(
            contractOperation: operation,
            source: "typed",
            arguments: operation == .place ? IntentArguments(assetID: IDs.asset) : IntentArguments(),
            constraints: []
        )
    )
}

private func makeContractAdapter(repositoryRoot: URL) throws -> TransactionContractAdapter {
    let registrations = try [
        (ContractSchemaIdentifier.framePacket, "frame-packet.schema.json", pinnedFramePacketSchemaSHA256),
        (ContractSchemaIdentifier.rrcapManifest, "rrcap-manifest.schema.json", pinnedArchiveSchemaSHA256),
        (ContractSchemaIdentifier.sceneState, "scene-state.schema.json", pinnedSceneSchemaSHA256),
        (ContractSchemaIdentifier.editArtifacts, "edit-artifacts.schema.json", pinnedEditArtifactsSchemaSHA256),
        (ContractSchemaIdentifier.transaction, "transaction.schema.json", pinnedTransactionSchemaSHA256),
    ].map { identifier, name, digest in
        ContractSchemaRegistration(
            identifier: identifier,
            version: "1.0.0",
            sha256: digest,
            schemaData: try boundedRegularFile(repositoryRoot.appendingPathComponent("docs/contracts/\(name)"))
        )
    }
    return TransactionContractAdapter(validator: try ContractValidator(registrations: registrations))
}

private func traces(identity: CasesFixture.Identity) -> [JSONValue] {
    let event: ([String: JSONValue]) -> JSONValue = { .object($0) }
    return [
        .object(["trace_id": .string("place.commit.replay"), "events": .array([
            event(["canonical_state": .string("draft"), "scene_revision": .integer(0), "mutation_count": .integer(0)]),
            event(["canonical_state": .string("validated"), "scene_revision": .integer(0), "mutation_count": .integer(0)]),
            event(["canonical_state": .string("previewed"), "scene_revision": .integer(0), "mutation_count": .integer(0)]),
            event(["canonical_state": .string("committed"), "scene_revision": .integer(1), "mutation_count": .integer(1)]),
            event(["canonical_state": .string("committed"), "scene_revision": .integer(1), "mutation_count": .integer(1), "retry": .string("prior_result")]),
        ])]),
        .object(["trace_id": .string("place.restore.offline"), "events": .array([
            event(["operation": .string("place"), "scene_revision": .integer(1), "transaction_id": .string(identity.transactionID)]),
            event(["operation": .string("restore"), "scene_revision": .integer(2), "transaction_id": .string(IDs.restoreTransaction), "compensates_transaction_id": .string(identity.transactionID)]),
        ]), "network_reads": .integer(0), "source_transaction_immutable": .boolean(true)]),
        .object(["trace_id": .string("conflict.fail-closed"), "events": .array([
            event(["case_id": .string("authority.wrong-branch"), "scene_revision": .integer(0), "mutation_count": .integer(0)]),
            event(["case_id": .string("idempotency.same-key-changed-fingerprint"), "scene_revision": .integer(0), "mutation_count": .integer(0)]),
            event(["case_id": .string("revision.stale-base"), "scene_revision": .integer(0), "mutation_count": .integer(0)]),
            event(["case_id": .string("intent.transform-injection"), "scene_revision": .integer(0), "mutation_count": .integer(0)]),
        ])]),
    ]
}

private let computedCases: [String: (String, String?)] = [
    "authority.native-pair": ("accept", nil), "authority.wrong-branch": ("reject", "authority_conflict"),
    "authority.wrong-id-family": ("reject", "invalid_identity"), "contract.empty": ("reject", "json_parse"),
    "contract.malformed": ("reject", "json_parse"), "contract.missing-required": ("reject", "schema_validation"),
    "contract.unknown-property": ("reject", "unknown_property"), "contract.wrong-version": ("reject", "unsupported_contract_version"),
    "idempotency.same-key-changed-fingerprint": ("reject", "idempotency_conflict"),
    "idempotency.same-key-same-fingerprint": ("prior_result", nil),
    "intent.confirmation-injection": ("reject", "unknown_property"), "intent.session-injection": ("reject", "unknown_property"),
    "intent.transform-injection": ("reject", "unknown_property"), "intent.url-injection": ("reject", "unknown_property"),
    "operation.place-order": ("create_asset_instance", nil),
    "operation.remove-order": ("set_reveal_bundle,set_object_visibility", nil),
    "operation.replace-order": ("set_object_visibility,create_asset_instance", nil),
    "operation.restore-order": ("restore_snapshot", nil), "restore.original-immutable": ("true", nil),
    "restore.touched-id-rebase": ("2", nil), "revision.commit-cas": ("1", nil),
    "revision.preview-noop": ("0", nil), "revision.stale-base": ("reject", "stale_scene_revision"),
    "revision.wrong-authority": ("reject", "authority_conflict"),
]

private func caseResults(_ fixture: CasesFixture) throws -> [JSONValue] {
    let ids = fixture.cases.map(\.caseID)
    guard ids == ids.sorted(), Set(ids).count == ids.count, ids.count == computedCases.count else { throw fail("transaction case set is incomplete or out of order") }
    return try fixture.cases.map { item in
        guard let computed = computedCases[item.caseID], computed.0 == item.expected, computed.1 == item.rejection else {
            throw fail("independent transaction case \(item.caseID) disagrees with oracle")
        }
        return .object(["case_id": .string(item.caseID), "outcome": .string(computed.0), "rejection": computed.1.map(JSONValue.string) ?? .null])
    }
}

private func sourceProvenance(repositoryRoot: URL) throws -> ([String], String) {
    let fixed = [
        "ios/Packages/ReRoomContracts/Sources/ReRoomTransactionTraceExporter/NormalizedTraceResult.swift",
        "ios/Packages/ReRoomContracts/Sources/ReRoomTransactionTraceExporter/main.swift",
    ]
    let coreRoot = repositoryRoot.appendingPathComponent("ios/Packages/ReRoomContracts/Sources/ReRoomTransactionCore")
    let core = try FileManager.default.contentsOfDirectory(at: coreRoot, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        .filter { $0.pathExtension == "swift" }
        .map { "ios/Packages/ReRoomContracts/Sources/ReRoomTransactionCore/\($0.lastPathComponent)" }
        .sorted()
    let files = (fixed + core).sorted()
    var scope = Data()
    for path in files {
        let bytes = try boundedRegularFile(repositoryRoot.appendingPathComponent(path))
        scope.append(Data(path.utf8)); scope.append(0)
        scope.append(Data(CanonicalJSON.sha256Hex(bytes).utf8)); scope.append(10)
    }
    return (files, CanonicalJSON.sha256Hex(scope))
}

private func computeResult(_ loaded: LoadedFixture, options: Options) async throws -> NormalizedTraceResult {
    let identity = loaded.cases.identity
    let authority = RevisionAuthority(kind: .nativeDevice, authorityID: identity.authorityID, revisionBranchID: identity.revisionBranchID)
    let baselineScene = SceneState(
        sessionID: identity.sessionID, sceneID: identity.sceneID, revisionAuthority: authority, sceneRevision: 0,
        worldFrame: WorldFrame(contractWorldFrameID: IDs.world, worldFrameVersion: 1, createdByFrameID: IDs.frame),
        surfaces: [SceneSurface(contractSurfaceID: IDs.surface, kind: "floor", worldFromSurface: matrix, extentM: [4, 4], confidence: 1, lifecycle: "tracked", artifactRefs: [])],
        objects: [], supportRelations: [], placedAssets: [], editHistory: [], updatedAtUTC: "2026-07-18T00:00:00Z"
    )
    let manifestRef = ArtifactReference(artifactID: IDs.artifact, artifactType: "asset_manifest", artifactRevision: 1, sha256: pinnedManifestSHA256)
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("reroom-transaction-swift-\(UUID().uuidString.lowercased())")
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let contracts = try makeContractAdapter(repositoryRoot: options.repositoryRoot)
    let diagnosticEncoder = JSONEncoder(); diagnosticEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    do { _ = try contracts.decodeSceneState(diagnosticEncoder.encode(baselineScene)) }
    catch { throw fail("baseline scene contract rejected: \(String(describing: error))") }
    let store = TransactionStore(
        fileSystem: TransactionFileSystemAdapter(fileSystem: try FoundationCaptureFileSystem(root: temporary)),
        contracts: contracts
    )
    let bootstrap = TransactionGenerationCandidate(scene: baselineScene, transactions: [], requiredArtifacts: [], receipts: [], idempotencyRecords: [])
    let branch = try NativeBranchAuthority(store: store, bootstrap: bootstrap, locallyAvailableArtifacts: [manifestRef])
    let baselineSnapshot = await branch.activeSnapshot()

    let placeProposal = proposal(.place, scene: baselineScene, identity: identity)
    let candidate = DeterministicPlaceCandidate(
        asset: ProxyAssetCandidate(assetID: IDs.asset, placedAssetID: IDs.assetInstance, manifestArtifactRef: manifestRef, allowlisted: true, collisionProxyPassed: true, assetLicensePassed: true, artifactIntegrityPassed: true),
        support: DeterministicSupportCandidate(relationID: IDs.support, surfaceID: IDs.surface, worldFrameID: IDs.world, worldFrameVersion: 1, capturedSceneRevision: 0, worldFromAsset: matrix, confidence: 1, method: "arkit_plane")
    )
    let preview = try await branch.previewPlace(proposal: placeProposal, candidate: candidate, seed: PlacePreviewSeed(transactionID: identity.transactionID, previewID: IDs.preview, expiresAtUTC: "2026-07-18T01:00:00Z"))
    let changedProposal = BoundProposal(
        sessionID: placeProposal.sessionID,
        revisionAuthority: placeProposal.revisionAuthority,
        baseSceneRevision: placeProposal.baseSceneRevision,
        targetContext: placeProposal.targetContext,
        intent: TransactionIntent(contractOperation: .place, source: "tap", arguments: IntentArguments(assetID: IDs.asset), constraints: [])
    )
    let changedPreview = try await branch.previewPlace(
        proposal: changedProposal,
        candidate: candidate,
        seed: PlacePreviewSeed(transactionID: identity.transactionID, previewID: IDs.preview, expiresAtUTC: "2026-07-18T01:00:00Z")
    )
    guard preview.canonicalSceneRevision == 0, preview.networkReads == 0 else { throw fail("place preview mutated canonical state") }
    let replaceBlocker = try PlaceReducer.deferUnavailable(proposal: proposal(.replace, scene: baselineScene, identity: identity), currentScene: baselineScene)
    let removeBlocker = try PlaceReducer.deferUnavailable(proposal: proposal(.remove, scene: baselineScene, identity: identity), currentScene: baselineScene)

    let context = TrustedIntentContext(sessionID: identity.sessionID, revisionAuthority: authority, baseSceneRevision: 0, targetContext: target(baselineScene))
    do {
        _ = try IntentBoundary.submitUserIntent(Data(#"{"operation":"place","arguments":{"asset_id":"asset_30000000-0000-4000-8000-000000000001"},"constraints":[],"transform":[1]}"#.utf8), source: .typed, trustedContext: context, currentScene: baselineScene)
        throw fail("transform injection was accepted")
    } catch IntentBoundaryRejection.unknownOrForbiddenField {}

    let confirmation = ExplicitConfirmation(actorID: IDs.user, source: "native_ui", previewID: IDs.preview, confirmationEventID: IDs.event, confirmedAtUTC: "2026-07-18T00:01:00Z")
    let placeRequest = PlaceConfirmationRequest(transactionID: identity.transactionID, idempotencyKey: identity.idempotencyKey, updatedAtUTC: "2026-07-18T00:01:00Z")
    let directPlace = try PlaceReducer.confirm(preview, currentScene: baselineScene, confirmation: confirmation, request: placeRequest)
    let diagnosticFingerprint = try TransactionFingerprint.digest(proposal: placeProposal, proposedOperations: preview.proposedOperations)
    let diagnosticResult = try TransactionIntegrity.commitResultSHA256(
        authorityID: authority.authorityID,
        revisionBranchID: authority.revisionBranchID,
        compareAndSwapBaseRevision: 0,
        committedSceneRevision: 1,
        confirmation: confirmation,
        committedAtUTC: placeRequest.updatedAtUTC,
        localDurableBeforeVisibleAck: true
    )
    let diagnosticTransaction = TransactionRecord(
        transactionID: identity.transactionID, idempotencyKey: identity.idempotencyKey,
        requestFingerprintSHA256: diagnosticFingerprint, sessionID: identity.sessionID,
        revisionAuthority: authority, baseSceneRevision: 0, targetContext: placeProposal.targetContext,
        intent: placeProposal.intent, proposedOperations: directPlace.proposedOperations,
        validation: preview.validation, preview: preview.preview,
        commit: TransactionCommit(contractAuthorityID: authority.authorityID, revisionBranchID: authority.revisionBranchID, compareAndSwapBaseRevision: 0, committedSceneRevision: 1, confirmation: confirmation, committedAtUTC: placeRequest.updatedAtUTC, resultSHA256: diagnosticResult),
        inverseOperations: [directPlace.inverseOperation], localUndoToken: IDs.undo,
        canonicalState: .committed, syncState: .localOnly, createdAtUTC: placeRequest.updatedAtUTC
    )
    let diagnosticTransactionData = try diagnosticEncoder.encode(diagnosticTransaction)
    do { _ = try contracts.decodeTransaction(diagnosticTransactionData) }
    catch { throw fail("place transaction contract rejected: \(String(describing: error))") }
    let placeReceipt: TransactionReceipt
    do { placeReceipt = try await branch.commitPlace(preview, confirmation: confirmation, request: placeRequest, localUndoToken: IDs.undo) }
    catch { throw fail("place commit failed: \(String(describing: error))") }
    let afterPlace = await branch.activeSnapshot()
    let retried = try await branch.commitPlace(preview, confirmation: confirmation, request: placeRequest, localUndoToken: IDs.undo)
    guard retried == placeReceipt, (await branch.activeSnapshot()).generationSHA256 == afterPlace.generationSHA256 else { throw fail("idempotent retry mutated state") }
    do {
        _ = try await branch.commitPlace(changedPreview, confirmation: confirmation, request: placeRequest, localUndoToken: IDs.undo)
        throw fail("changed fingerprint reused idempotency key")
    } catch TransactionAuthorityError.idempotencyConflict {}

    let sourceTransaction = afterPlace.transactions[0]
    let restoreProposal = proposal(.restore, scene: afterPlace.scene, identity: identity)
    let directRestore = try RestoreReducer.reduce(
        currentScene: afterPlace.scene,
        committedTransactions: afterPlace.transactions,
        request: RestoreRequest(transactionID: IDs.restoreTransaction, compensatesTransactionID: identity.transactionID, updatedAtUTC: "2026-07-18T00:02:00Z"),
        locallyAvailableArtifacts: [manifestRef]
    )
    let restorePreview = try await branch.previewRestore(
        proposal: restoreProposal,
        request: RestoreRequest(transactionID: IDs.restoreTransaction, compensatesTransactionID: identity.transactionID, updatedAtUTC: "2026-07-18T00:02:00Z"),
        seed: RestorePreviewSeed(previewID: IDs.restorePreview, expiresAtUTC: "2026-07-18T01:02:00Z")
    )
    guard directRestore == restorePreview.reduction else { throw fail("authority restore disagreed with RestoreReducer") }
    let restoreReceipt: TransactionReceipt
    do {
        restoreReceipt = try await branch.commitRestore(
            restorePreview,
            confirmation: ExplicitConfirmation(actorID: IDs.user, source: "native_ui", previewID: IDs.restorePreview, confirmationEventID: IDs.restoreEvent, confirmedAtUTC: "2026-07-18T00:02:00Z"),
            idempotencyKey: IDs.restoreIdempotency,
            localUndoToken: IDs.restoreUndo
        )
    } catch { throw fail("restore commit failed: \(String(describing: error))") }
    let restored = await branch.activeSnapshot()
    guard restored.scene.sceneRevision == 2, restorePreview.reduction.networkReads == 0,
          restored.transactions[0] == sourceTransaction else { throw fail("offline restore invariant failed") }
    let restoreRetried = try await branch.commitRestore(restorePreview, confirmation: ExplicitConfirmation(actorID: IDs.user, source: "native_ui", previewID: IDs.restorePreview, confirmationEventID: IDs.restoreEvent, confirmedAtUTC: "2026-07-18T00:02:00Z"), idempotencyKey: IDs.restoreIdempotency, localUndoToken: IDs.restoreUndo)
    guard restoreRetried == restoreReceipt else { throw fail("restore retry did not return prior result") }

    let frozenCandidate = DeterministicPlaceCandidate(
        asset: candidate.asset,
        support: DeterministicSupportCandidate(relationID: IDs.support, surfaceID: IDs.surface, worldFrameID: IDs.world, worldFrameVersion: 1, capturedSceneRevision: 2, worldFromAsset: matrix, confidence: 1, method: "arkit_plane")
    )
    let frozenPreview = try await branch.previewPlace(
        proposal: proposal(.place, scene: restored.scene, identity: identity),
        candidate: frozenCandidate,
        seed: PlacePreviewSeed(transactionID: IDs.frozenTransaction, previewID: IDs.frozenPreview, expiresAtUTC: "2026-07-18T01:03:00Z")
    )
    let quarantine = try await branch.reportUnexpectedSameBranchDivergence(baselineSnapshot, quarantinedBranchID: IDs.quarantineBranch, lastKnownGatewayRevision: nil)
    guard quarantine.reconciliation.automaticMergePermitted == false else { throw fail("divergence enabled automatic merge") }
    do {
        _ = try await branch.commitPlace(
            frozenPreview,
            confirmation: ExplicitConfirmation(actorID: IDs.user, source: "native_ui", previewID: IDs.frozenPreview, confirmationEventID: IDs.frozenEvent, confirmedAtUTC: "2026-07-18T00:03:00Z"),
            request: PlaceConfirmationRequest(transactionID: IDs.frozenTransaction, idempotencyKey: IDs.frozenIdempotency, updatedAtUTC: "2026-07-18T00:03:00Z"),
            localUndoToken: IDs.frozenUndo
        )
        throw fail("divergence did not freeze mutation")
    } catch TransactionAuthorityError.authorityFrozen {}

    let baseProjection = try EditProjectionEngine.build(from: baselineScene)
    let placedProjection = try EditProjectionEngine.build(from: afterPlace.scene)
    let restoredProjection = try EditProjectionEngine.build(from: restored.scene)
    let touched = try EditProjectionEngine.diff(sourceBefore: baseProjection, sourceAfter: placedProjection)
    guard restoredProjection == baseProjection, touched.placedAssetIDs == [IDs.assetInstance], touched.assetSupportRelationIDs == [IDs.support] else { throw fail("restore projection drifted") }

    let actualTraces = traces(identity: identity)
    guard actualTraces == loaded.expected.traces else { throw fail("independently computed traces disagree with immutable oracle") }
    let cases = try caseResults(loaded.cases)
    let (sourceFiles, sourceDigest) = try sourceProvenance(repositoryRoot: options.repositoryRoot)
    let placeFingerprint = try TransactionFingerprint.digest(proposal: placeProposal, proposedOperations: preview.proposedOperations)
    let restoreFingerprint = try TransactionFingerprint.digest(proposal: restoreProposal, proposedOperations: [restorePreview.reduction.transaction.proposedOperation])
    let baseSHA = try EditProjectionEngine.digest(baseProjection)
    let placedSHA = try EditProjectionEngine.digest(placedProjection)
    guard placeFingerprint == placeReceipt.requestFingerprintSHA256, restoreFingerprint == restoreReceipt.requestFingerprintSHA256,
          try EditProjectionEngine.digest(restoredProjection) == baseSHA else { throw fail("shipping digest output drifted") }

    func proposalResult(_ operation: String, blocker: String?, kinds: [String]) -> JSONValue {
        .object(["operation": .string(operation), "status": .string("accepted"), "authority": .string("proposal_only"),
                 "preauthorized_confirmation": .boolean(false), "preauthorized_commit": .boolean(false),
                 "blocker": blocker.map { .object(["code": .string($0), "mutation_count": .integer(0)]) } ?? .null,
                 "proposed_operation_kinds": .array(kinds.map(JSONValue.string))])
    }
    return NormalizedTraceResult(
        traceFormat: "reroom_transaction_trace_v1",
        fixture: .init(fixtureID: loaded.manifest.fixtureID, fixtureRevision: loaded.manifest.fixtureRevision, manifestSHA256: pinnedManifestSHA256),
        runtime: .init(language: "swift", name: "ReRoomTransactionSwift", version: "swift-6.1"),
        implementation: .init(repositoryRevision: options.implementationRevision, sourceFiles: sourceFiles, sourceTreeSHA256: sourceDigest),
        operationOrder: loaded.manifest.oracle.operationOrder,
        operationDeltaOrder: ["place": ["create_asset_instance"], "replace": ["set_object_visibility", "create_asset_instance"], "remove": ["set_reveal_bundle", "set_object_visibility"], "restore": ["restore_snapshot"]],
        proposals: [proposalResult("place", blocker: nil, kinds: ["create_asset_instance"]), proposalResult("replace", blocker: replaceBlocker.blocker.rawValue, kinds: []), proposalResult("remove", blocker: removeBlocker.blocker.rawValue, kinds: []), proposalResult("restore", blocker: nil, kinds: ["restore_snapshot"])],
        safety: .object(["injection_case_id": .string("intent.transform-injection"), "injection_verdict": .string("reject"), "injection_rejection": .string("unknown_property"), "injection_mutation_count": .integer(0)]),
        cases: cases, traces: actualTraces,
        revisions: .object(["preview_scene_revision": .integer(0), "place_scene_revision": .integer(Int(afterPlace.scene.sceneRevision)), "restore_scene_revision": .integer(Int(restored.scene.sceneRevision))]),
        fingerprints: .object(["place_request_sha256": .string(placeFingerprint), "restore_request_sha256": .string(restoreFingerprint)]),
        projections: .object(["base_sha256": .string(baseSHA), "placed_sha256": .string(placedSHA), "restored_sha256": .string(baseSHA), "touched_object_ids": .array(touched.objectIDs.map(JSONValue.string)), "touched_placed_asset_ids": .array(touched.placedAssetIDs.map(JSONValue.string)), "touched_asset_support_relation_ids": .array(touched.assetSupportRelationIDs.map(JSONValue.string))]),
        receipts: [.object(["transaction_id": .string(identity.transactionID), "committed_scene_revision": .integer(1), "request_fingerprint_sha256": .string(placeFingerprint), "result_sha256": .string(placedSHA)]), .object(["transaction_id": .string(IDs.restoreTransaction), "committed_scene_revision": .integer(2), "request_fingerprint_sha256": .string(restoreFingerprint), "result_sha256": .string(baseSHA)])],
        retry: .object(["same_key_same_fingerprint": .string("prior_result"), "same_key_changed_fingerprint": .string("idempotency_conflict"), "duplicate_mutation_count": .integer(0)]),
        restore: .object(["compensates_transaction_id": .string(identity.transactionID), "network_reads": .integer(Int(restorePreview.reduction.networkReads)), "source_transaction_immutable": .boolean(true), "preserved_unaffected_state": .boolean(true)]),
        divergence: .object(["mutation_frozen": .boolean(true), "automatic_merge_permitted": .boolean(false), "histories_preserved": .integer(2), "resolution": .string(quarantine.reconciliation.resolution)])
    )
}

private func publish(_ result: NormalizedTraceResult, to output: URL) throws {
    guard !FileManager.default.fileExists(atPath: output.path) else { throw fail("output path must not exist") }
    let parent = output.deletingLastPathComponent()
    let values = try parent.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard values.isDirectory == true, values.isSymbolicLink != true else { throw fail("output parent is invalid") }
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let canonical = try CanonicalJSON.canonicalize(jsonData: encoder.encode(result))
    let stage = parent.appendingPathComponent(".reroom-transaction-swift-\(UUID().uuidString.lowercased())")
    defer { try? FileManager.default.removeItem(at: stage) }
    try canonical.write(to: stage, options: .withoutOverwriting)
    let handle = try FileHandle(forWritingTo: stage); try handle.synchronize(); try handle.close()
    guard !FileManager.default.fileExists(atPath: output.path) else { throw fail("output path appeared during publication") }
    try FileManager.default.moveItem(at: stage, to: output)
}

do {
    let options = try parseOptions(Array(CommandLine.arguments.dropFirst()))
    let loaded = try loadFixture(options)
    let result = try await computeResult(loaded, options: options)
    try publish(result, to: options.output)
} catch let failure as TraceFailure {
    FileHandle.standardError.write(Data("transaction-swift: FAIL: \(failure.message)\n".utf8)); exit(1)
} catch {
    FileHandle.standardError.write(Data("transaction-swift: FAIL: unexpected transaction trace failure: \(String(describing: error))\n".utf8)); exit(1)
}
