import Foundation
import CoreGraphics
import RealityKit
import ReRoomCaptureCore
import ReRoomContracts
import ReRoomTransactionCore
import Testing
@testable import ReRoomDeviceProof

private enum RoomEditTestFixtureError: Error {
    case repositoryRootNotFound
}

@Suite("Phase 3 room-edit presentation boundary")
@MainActor
struct RoomEditModelTests {
    @Test("Phase 5 bootstrap contains the exact visible controlled target with independent readiness")
    func phase5BootstrapBindsCanonicalTarget() throws {
        let manifest = try Phase3ProxyManifest.load(bundle: Bundle(for: RoomEditModel.self))
        let bootstrap = RoomEditFactory.bootstrap(manifest: manifest)
        let target = try #require(bootstrap.scene.objects.first {
            $0.objectID == RoomEditIdentity.targetObjectID
        })

        #expect(bootstrap.scene.objects.count == 1)
        #expect(target.lifecycle == "tracked")
        #expect(target.editState.visible)
        #expect(target.readiness.select == "ready")
        #expect(target.readiness.replace == "degraded")
        #expect(target.readiness.remove == "unavailable")
        #expect(target.readiness.restore == "unavailable")
        #expect(bootstrap.scene.sceneRevision == 0)
    }

    @Test("replace proposal and local candidate bind the selected canonical target")
    func replaceBindingIsDeterministic() throws {
        let manifest = try Phase3ProxyManifest.load(bundle: Bundle(for: RoomEditModel.self))
        let scene = RoomEditFactory.bootstrap(manifest: manifest).scene
        let target = TargetGroundingReducer.reduce(
            TargetGroundingReducer.initial(environment: .fixture),
            event: .select([.heroFixture]),
            environment: .fixture
        )
        let context = try #require(target.targetContext)
        let proposal = RoomEditFactory.replaceProposal(
            scene: scene,
            targetContext: context,
            manifest: manifest
        )
        let candidate = try #require(RoomEditFactory.replaceCandidate(
            scene: scene,
            targetContext: context,
            manifest: manifest,
            support: .healthyFixture,
            supportedView: true
        ))

        #expect(proposal.intent.operation == .replace)
        #expect(proposal.intent.source == "tap")
        #expect(proposal.intent.arguments.assetID == manifest.contractAssetID)
        #expect(proposal.targetContext.selectedObjectID == RoomEditIdentity.targetObjectID)
        #expect(candidate.targetObjectID == RoomEditIdentity.targetObjectID)
        #expect(candidate.capabilityReadiness == "degraded")
        #expect(candidate.readinessSource == "manual_proxy_fallback")
        #expect(candidate.supportedView)
        #expect(candidate.capturedSceneRevision == scene.sceneRevision)
    }

    @Test("recovered empty Phase 3 generation keeps replace unavailable with migration reason")
    func recoveredEmptyGenerationFailsClosedForReplace() async throws {
        let manifest = try Phase3ProxyManifest.load(bundle: Bundle(for: RoomEditModel.self))
        let phase5 = RoomEditFactory.bootstrap(manifest: manifest)
        let emptyScene = SceneState(
            contractSchemaVersion: phase5.scene.schemaVersion,
            sessionID: phase5.scene.sessionID,
            sceneID: phase5.scene.sceneID,
            revisionAuthority: phase5.scene.revisionAuthority,
            sceneRevision: phase5.scene.sceneRevision,
            worldFrame: phase5.scene.worldFrame,
            surfaces: phase5.scene.surfaces,
            objects: [],
            supportRelations: [],
            placedAssets: [],
            editHistory: [],
            updatedAtUTC: phase5.scene.updatedAtUTC
        )
        let legacy = TransactionGenerationCandidate(
            scene: emptyScene,
            transactions: [],
            requiredArtifacts: [],
            receipts: [],
            idempotencyRecords: []
        )
        let harness = try TestRoomEditHarness(
            support: .healthyFixture,
            preloadedCandidate: legacy
        )

        await harness.model.prepare()
        #expect(harness.model.snapshot.blocker == .replaceDeferred)
        #expect(harness.model.snapshot.status.contains("fresh local room"))
        await harness.model.groundTarget(candidates: [.heroFixture], tracking: .normal)
        #expect(harness.model.snapshot.target.readiness.replace == .unavailable)
        #expect(harness.model.snapshot.target.reasons.replace == [.authorityConflict])
        #expect((await harness.authority.activeSnapshot()).scene.objects.isEmpty)
    }

    @Test("compositor descriptor is exactly ordered and unavailable layers cannot be promoted")
    func compositorDescriptorIsClosedAndHonest() {
        let canonical = RoomEditCompositorDescriptor.canonical

        #expect(canonical.layers.map(\.id) == [
            .camera,
            .reveal,
            .occluder,
            .assetProxy,
            .debug,
            .swiftUI,
        ])
        #expect(canonical.layers.count == 6)
        #expect(canonical.layers[1].availability == .unavailable(.revealArtifactMissing))
        #expect(canonical.layers[2].availability == .unavailable(.occluderArtifactMissing))
        #expect(RoomEditCompositorDescriptor.isCanonical(canonical.layers))

        var reordered = canonical.layers
        reordered.swapAt(0, 1)
        #expect(!RoomEditCompositorDescriptor.isCanonical(reordered))
        #expect(!RoomEditCompositorDescriptor.isCanonical(Array(canonical.layers.dropLast())))
        #expect(!RoomEditCompositorDescriptor.isCanonical(canonical.layers + [canonical.layers[0]]))

        var promotedReveal = canonical.layers
        promotedReveal[1] = RoomEditCompositorLayer(
            id: .reveal,
            availability: .available(.localRenderer)
        )
        #expect(!RoomEditCompositorDescriptor.isCanonical(promotedReveal))

        var promotedOccluder = canonical.layers
        promotedOccluder[2] = RoomEditCompositorLayer(
            id: .occluder,
            availability: .available(.localRenderer)
        )
        #expect(!RoomEditCompositorDescriptor.isCanonical(promotedOccluder))
    }

    @Test("target session prepares once and tap plus loss publish immutable render snapshots")
    func targetSessionWiringIsCoarsenedAndRevisionNeutral() async throws {
        let targetSession = RoomEditFixtureTargetSession(scenario: .trackingLossAfterSeed)
        let harness = try TestRoomEditHarness(
            support: .healthyFixture,
            targetSession: targetSession
        )

        await harness.model.prepare()
        await harness.model.prepare()
        #expect(targetSession.prepareCount == 1)

        let before = await harness.authority.activeSnapshot()
        await harness.model.groundTarget(at: CGPoint(x: 120, y: 240))
        await Task.yield()

        let after = harness.model.snapshot
        #expect(after.revision == before.scene.sceneRevision)
        #expect(after.render.layers == RoomEditCompositorDescriptor.canonical.layers)
        #expect(after.render.targetProxy?.objectID == RoomEditIdentity.targetObjectID)
        #expect(after.render.targetProxy?.worldFrameVersion == 1)
        #expect(after.target.target?.lifecycle == .lost)
        #expect(after.target.readiness.select == .unavailable)
        #expect(after.target.readiness.replace == .unavailable)
        #expect(await harness.authority.activeSnapshot() == before)
    }

    @Test("deterministic target fixtures cover healthy miss and ambiguity without AR tracking")
    func targetFixturesAreDeterministic() async throws {
        for (scenario, failure) in [
            (RoomEditTargetFixtureScenario.healthy, nil),
            (.miss, TargetGroundingFailure.targetMissed),
            (.ambiguous, TargetGroundingFailure.targetAmbiguous),
        ] {
            let targetSession = RoomEditFixtureTargetSession(scenario: scenario)
            let harness = try TestRoomEditHarness(
                support: .healthyFixture,
                targetSession: targetSession
            )
            await harness.model.prepare()
            await harness.model.groundTarget(at: CGPoint(x: 160, y: 320))

            #expect(harness.model.snapshot.target.failure == failure)
            #expect(harness.model.snapshot.revision == 0)
            #expect(targetSession.requestedPoints == [CGPoint(x: 160, y: 320)])
        }
    }

    @Test("bundled proxy has a closed identity and exact source digest")
    func proxyIdentityAndDigestAreBound() throws {
        let manifest = try Phase3ProxyManifest.load(bundle: Bundle(for: RoomEditModel.self))
        let sourceURL = try #require(Bundle(for: RoomEditModel.self).url(
            forResource: "proxy-chair",
            withExtension: "usda"
        ))

        #expect(manifest.proxyID == "asset_proxy-chair-phase3")
        #expect(manifest.qualification == "phase3_local_demo_proxy_only")
        #expect(manifest.sourceSHA256 == CanonicalJSON.sha256Hex(try Data(contentsOf: sourceURL)))
        #expect(manifest.artifactReference.artifactID == manifest.artifactID)
        #expect(manifest.artifactReference.artifactType == "asset_manifest")
    }

    @Test("curated hackathon catalog contains exactly three digest-bound local assets")
    func curatedCatalogIsClosedAndLocal() throws {
        let bundle = Bundle(for: RoomEditModel.self)
        let catalog = try RoomEditAssetCatalog.load(bundle: bundle)

        #expect(catalog.assets.map(\.assetID) == [
            "asset_53000000-0000-4000-8000-000000000002",
            "asset_53000000-0000-4000-8000-000000000003",
            "asset_53000000-0000-4000-8000-000000000004",
        ])
        #expect(catalog.assets.map(\.displayName) == [
            "Warm Arc Chair",
            "Cobalt Lounge Chair",
            "Halo Side Table",
        ])

        for asset in catalog.assets {
            let source = try #require(bundle.url(
                forResource: asset.sourceResourceName,
                withExtension: "usda"
            ))
            #expect(asset.sourceSHA256 == CanonicalJSON.sha256Hex(try Data(contentsOf: source)))
            let native = try #require(bundle.url(
                forResource: asset.nativeResourceName,
                withExtension: "usdz"
            ))
            #expect(asset.nativeSHA256 == CanonicalJSON.sha256Hex(try Data(contentsOf: native)))
            #expect(asset.artifactReference.sha256 == asset.canonicalManifestContentSHA256)
            #expect(asset.artifactReference.sha256 != asset.sourceSHA256)
            _ = try Entity.load(named: asset.nativeFile, in: bundle)
            #expect(asset.qualification == "hackathon_repo_owned_demo_proxy_only")
            #expect(asset.gate011Status == "PENDING")
        }
    }

    @Test("CON-004 manifest reference invalidates every load-bearing mutation")
    func assetManifestDigestCoversIdentityAndQualification() throws {
        let bundle = Bundle(for: RoomEditModel.self)
        let asset = try #require(RoomEditAssetCatalog.load(bundle: bundle).assets.first)
        let name = URL(fileURLWithPath: asset.canonicalManifestFile)
            .deletingPathExtension().lastPathComponent
        let url = try #require(bundle.url(forResource: name, withExtension: "json"))
        let data = try Data(contentsOf: url)
        try RoomEditAssetManifestVerifier.verifyContentDigest(
            manifestData: data,
            expectedContentSHA256: asset.canonicalManifestContentSHA256
        )
        let original = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let mutations: [(String, ([String: Any]) throws -> [String: Any])] = [
            ("identity", { root in
                var root = root
                root["asset_id"] = "asset_53000000-0000-4000-8000-000000000099"
                return root
            }),
            ("dimensions", { root in
                var root = root
                root["canonical_dimensions_m"] = [0.61, 1.0, 0.6]
                return root
            }),
            ("license", { root in
                var root = root
                var license = try #require(root["license"] as? [String: Any])
                license["spdx_or_terms"] = "Apache-2.0"
                root["license"] = license
                return root
            }),
            ("provenance", { root in
                var root = root
                var provider = try #require(root["provider"] as? [String: Any])
                provider["provenance"] = "human_validated"
                root["provider"] = provider
                return root
            }),
            ("collision", { root in
                var root = root
                var collision = try #require(root["collision"] as? [String: Any])
                collision["sha256"] = String(repeating: "f", count: 64)
                root["collision"] = collision
                return root
            }),
            ("delivery", { root in
                var root = root
                var delivery = try #require(root["delivery"] as? [String: Any])
                delivery["state"] = "preloaded_cache"
                root["delivery"] = delivery
                return root
            }),
            ("payload", { root in
                var root = root
                var glb = try #require(root["glb"] as? [String: Any])
                glb["sha256"] = String(repeating: "e", count: 64)
                root["glb"] = glb
                return root
            }),
        ]

        for (name, mutate) in mutations {
            let mutated = try JSONSerialization.data(
                withJSONObject: mutate(original),
                options: [.sortedKeys, .withoutEscapingSlashes]
            )
            #expect(throws: RoomEditAssetManifestError.contentDigestMismatch) {
                try RoomEditAssetManifestVerifier.verifyContentDigest(
                    manifestData: mutated,
                    expectedContentSHA256: asset.canonicalManifestContentSHA256
                )
            }
            #expect(!name.isEmpty)
        }
    }

    @Test("CON-006 proposal echoes trusted context and remains revision-neutral")
    func semanticProposalBindsExactNativeContext() throws {
        let catalog = try RoomEditAssetCatalog.load(bundle: Bundle(for: RoomEditModel.self))
        let scene = RoomEditFactory.bootstrap(manifest: catalog.assets[0].transactionManifest).scene
        let target = TargetContext(
            contractCapturedAtFrameID: RoomEditIdentity.frameID,
            capturedSceneRevision: scene.sceneRevision,
            worldFrameID: scene.worldFrame.worldFrameID,
            worldFrameVersion: scene.worldFrame.worldFrameVersion,
            cameraPose: .identity,
            screenPointEncodedPixels: [1, 1],
            candidateObjectIDs: [],
            selectedObjectID: nil,
            artifactRefs: []
        )
        let trusted = TrustedIntentContext(
            sessionID: scene.sessionID,
            revisionAuthority: scene.revisionAuthority,
            baseSceneRevision: scene.sceneRevision,
            targetContext: target
        )
        let context = DesignCopilotRequestContext(scene: scene, targetContext: target)
        let envelope = SemanticProposalEnvelope(
            schemaVersion: "1.0.0",
            envelopeID: "envelope_54000000-0000-4000-8000-000000000001",
            createdAtUTC: "2026-07-19T18:00:00Z",
            requestContext: context,
            ingressSource: .vision,
            semanticModel: SemanticModelReference(
                contractProvider: "openai",
                model: "gpt-5.6-sol",
                responseID: "resp_54000000-0000-4000-8000-000000000002"
            ),
            status: .ready,
            intent: SemanticProposalIntent(
                operation: .place,
                arguments: IntentArguments(assetID: catalog.assets[1].assetID),
                constraints: [TypedConstraint(contractKind: "style_tag", value: .string("modern"))]
            ),
            explanation: "The cobalt chair gives the room a stronger focal point.",
            clarification: nil
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let decoded = try SemanticProposalEnvelope.decodeStrict(encoder.encode(envelope))
        let bound = try decoded.bind(
            expectedContext: context,
            trustedContext: trusted,
            currentScene: scene,
            catalog: catalog
        )
        let proposal = try #require(bound)

        #expect(proposal.intent.operation == .place)
        #expect(proposal.intent.arguments.assetID == catalog.assets[1].assetID)
        #expect(proposal.intent.source == "typed")
        #expect(proposal.intent.semanticModel?.model == "gpt-5.6-sol")
        #expect(proposal.baseSceneRevision == scene.sceneRevision)
        #expect(scene.editHistory.isEmpty)
    }

    @Test("native decoder consumes the same immutable CON-006 accept vectors")
    func semanticProposalFixtureRevisionIsSharedAcrossRuntimes() throws {
        let root = try repositoryRoot()
        let fixtureData = try Data(contentsOf: root.appending(path:
            "fixtures/semantic-proposals/1.0.0/rev-001/cases.json"
        ))
        let schemaData = try Data(contentsOf: root.appending(path:
            "docs/contracts/semantic-proposal.schema.json"
        ))
        let fixture = try #require(
            JSONSerialization.jsonObject(with: fixtureData) as? [String: Any]
        )
        let cases = try #require(fixture["cases"] as? [[String: Any]])
        let caseIDs = try cases.map { try #require($0["case_id"] as? String) }

        #expect(fixture["contract_id"] as? String == "CON-006")
        #expect(fixture["contract_schema_sha256"] as? String == CanonicalJSON.sha256Hex(schemaData))
        #expect(caseIDs.count == 10)
        #expect(caseIDs == caseIDs.sorted())
        #expect(Set(caseIDs).count == caseIDs.count)

        var accepted = 0
        for fixtureCase in cases where fixtureCase["expected_verdict"] as? String == "accept" {
            let object = try #require(fixtureCase["expected_envelope"] as? [String: Any])
            let bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            let envelope = try SemanticProposalEnvelope.decodeStrict(bytes)
            #expect(envelope.schemaVersion == "1.0.0")
            accepted += 1
        }
        #expect(accepted == 3)
    }

    @Test("CON-006 rejects an injected model-supplied authority field")
    func semanticProposalRejectsForbiddenShape() throws {
        let bytes = Data("""
        {
          "schema_version":"1.0.0",
          "envelope_id":"envelope_54000000-0000-4000-8000-000000000001",
          "created_at_utc":"2026-07-19T18:00:00Z",
          "request_context":{
            "session_id":"session_41000000-0000-4000-8000-000000000001",
            "revision_branch_id":"branch_41000000-0000-4000-8000-000000000002",
            "base_scene_revision":0,
            "world_frame_id":"world_41000000-0000-4000-8000-000000000003",
            "world_frame_version":1,
            "selected_object_id":null
          },
          "ingress_source":"typed",
          "semantic_model":{"provider":"openai","model":"gpt-5.6-sol","response_id":"resp_safe"},
          "status":"ready",
          "intent":{
            "operation":"place",
            "arguments":{"asset_id":"asset_53000000-0000-4000-8000-000000000002"},
            "constraints":[],
            "world_from_asset":[1,0,0,0]
          },
          "explanation":"Injected transform must fail.",
          "clarification":null
        }
        """.utf8)

        #expect(throws: SemanticProposalRejection.invalidShape) {
            try SemanticProposalEnvelope.decodeStrict(bytes)
        }
    }

    @Test("CON-006 native decoder enforces response and safe-copy schema bounds")
    func semanticProposalRejectsUnsafeCopyAndOversizedResponseID() throws {
        func envelope(responseID: String, explanation: String) -> Data {
            Data("""
            {
              "schema_version":"1.0.0",
              "envelope_id":"envelope_54000000-0000-4000-8000-000000000001",
              "created_at_utc":"2026-07-19T18:00:00Z",
              "request_context":{
                "session_id":"session_41000000-0000-4000-8000-000000000001",
                "revision_branch_id":"branch_41000000-0000-4000-8000-000000000002",
                "base_scene_revision":0,
                "world_frame_id":"world_41000000-0000-4000-8000-000000000003",
                "world_frame_version":1,
                "selected_object_id":null
              },
              "ingress_source":"typed",
              "semantic_model":{"provider":"openai","model":"gpt-5.6-sol","response_id":"\(responseID)"},
              "status":"ready",
              "intent":{
                "operation":"place",
                "arguments":{"asset_id":"asset_53000000-0000-4000-8000-000000000002"},
                "constraints":[]
              },
              "explanation":"\(explanation)",
              "clarification":null
            }
            """.utf8)
        }

        #expect(throws: SemanticProposalRejection.invalidEnvelope) {
            try SemanticProposalEnvelope.decodeStrict(envelope(
                responseID: String(repeating: "r", count: 129),
                explanation: "Safe copy"
            ))
        }
        #expect(throws: SemanticProposalRejection.invalidEnvelope) {
            try SemanticProposalEnvelope.decodeStrict(envelope(
                responseID: "resp_safe",
                explanation: "Open https://example.invalid"
            ))
        }
    }

    @Test("Realtime bootstrap accepts only the short-lived closed credential response")
    func realtimeCredentialIsStrictAndEphemeral() throws {
        let nowEpochSeconds: Int64 = 4_102_444_200
        let valid = Data("""
        {"value":"ek_fixture_only","expires_at":4102444800,"session":{"id":"sess_fixture_only","model":"gpt-realtime-2.1"}}
        """.utf8)
        let secret = try RealtimeClientSecret.decodeStrict(
            valid,
            nowEpochSeconds: nowEpochSeconds
        )
        #expect(secret.isUsable)
        #expect(secret.session.model == "gpt-realtime-2.1")

        let injected = Data("""
        {"value":"ek_fixture_only","expires_at":4102444800,"session":{"id":"sess_fixture_only","model":"gpt-realtime-2.1"},"api_key":"forbidden"}
        """.utf8)
        #expect(throws: DesignCopilotGatewayError.rejected) {
            try RealtimeClientSecret.decodeStrict(
                injected,
                nowEpochSeconds: nowEpochSeconds
            )
        }

        let unsafeVariants = [
            Data("""
            {"\\u0076alue":"ek_attacker","value":"ek_fixture_only","expires_at":4102444800,"session":{"id":"sess_fixture_only","model":"gpt-realtime-2.1"}}
            """.utf8),
            Data("""
            {"value":"ek_bad\\nheader","expires_at":4102444800,"session":{"id":"sess_fixture_only","model":"gpt-realtime-2.1"}}
            """.utf8),
            Data("""
            {"value":"ek_fixture_only","expires_at":4202444800,"session":{"id":"sess_fixture_only","model":"gpt-realtime-2.1"}}
            """.utf8),
        ]
        for bytes in unsafeVariants {
            #expect(throws: DesignCopilotGatewayError.rejected) {
                try RealtimeClientSecret.decodeStrict(
                    bytes,
                    nowEpochSeconds: nowEpochSeconds
                )
            }
        }
    }

    @Test("gateway credentials can use HTTPS or local cleartext roots only")
    func gatewayURLBoundaryRejectsPublicCleartextAndDecoratedURLs() throws {
        let local = try DesignCopilotGatewayClient(
            baseURL: try #require(URL(string: "http://192.168.1.20:8787/")),
            bearerToken: "fixture-token"
        )
        #expect(local.baseURL.host == "192.168.1.20")

        let secure = try DesignCopilotGatewayClient(
            baseURL: try #require(URL(string: "https://gateway.example.test/")),
            bearerToken: "fixture-token"
        )
        #expect(secure.baseURL.scheme == "https")

        for rawURL in [
            "http://gateway.example.test:8787/",
            "http://fcorp.example.test:8787/",
            "http://192.168.1.20:8787/proxy",
            "http://user@192.168.1.20:8787/",
            "http://192.168.1.20:8787/?token=leak",
        ] {
            #expect(throws: DesignCopilotGatewayError.invalidConfiguration) {
                try DesignCopilotGatewayClient(
                    baseURL: try #require(URL(string: rawURL)),
                    bearerToken: "fixture-token"
                )
            }
        }
    }

    private func repositoryRoot() throws -> URL {
        var cursor = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: cursor.appending(path: ".git").path) {
            let parent = cursor.deletingLastPathComponent()
            guard parent.path != cursor.path else {
                throw RoomEditTestFixtureError.repositoryRootNotFound
            }
            cursor = parent
        }
        return cursor
    }

    private func designCopilotRuntime(
        support: RoomEditSupportContext?,
        replacementAssetState: RoomEditReplacementAssetState = .loading
    ) throws -> (runtime: RoomEditRuntime, authority: NativeBranchAuthority) {
        let harness = try TestRoomEditHarness(support: support)
        let catalog = try RoomEditAssetCatalog.load(bundle: Bundle(for: RoomEditModel.self))
        let model = RoomEditModel(
            authority: harness.authority,
            manifest: harness.manifest,
            catalog: catalog,
            supportProvider: { _ in support },
            replacementAssetState: replacementAssetState,
            replacementSupportedViewPolicy: .fixtureDemoHypothesis
        )
        return (
            RoomEditRuntime(
                model: model,
                catalog: catalog,
                sharedSession: nil,
                deviceProof: nil,
                fixtureScenario: .healthy
            ),
            harness.authority
        )
    }

    private func strictSemanticEnvelope(
        request: DesignCopilotProposalRequest,
        operation: ProductOperation,
        assetID: String?,
        suffix: String
    ) throws -> SemanticProposalEnvelope {
        let envelope = SemanticProposalEnvelope(
            schemaVersion: "1.0.0",
            envelopeID: "envelope_54000000-0000-4000-8000-000000000\(suffix)",
            createdAtUTC: "2026-07-19T18:00:00Z",
            requestContext: request.requestContext,
            ingressSource: request.ingressSource,
            semanticModel: SemanticModelReference(
                contractProvider: "openai",
                model: "gpt-5.6-sol",
                responseID: "resp_no_preview_\(suffix)"
            ),
            status: .ready,
            intent: SemanticProposalIntent(
                operation: operation,
                arguments: IntentArguments(assetID: assetID),
                constraints: []
            ),
            explanation: "Preview only after deterministic readiness passes.",
            clarification: nil
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try SemanticProposalEnvelope.decodeStrict(encoder.encode(envelope))
    }

    @Test("Realtime accepts only the completed bounded transcript event")
    func realtimeTranscriptEventIsClosed() {
        let valid = Data("""
        {"type":"conversation.item.input_audio_transcription.completed","transcript":"Try the cobalt lounge chair"}
        """.utf8)
        #expect(DesignCopilotRealtimeSession.event(from: valid) == .transcript("Try the cobalt lounge chair"))

        let partial = Data("""
        {"type":"conversation.item.input_audio_transcription.delta","transcript":"Try"}
        """.utf8)
        #expect(DesignCopilotRealtimeSession.event(from: partial) == .ignored)

        let duplicateType = Data("""
        {"type":"error","\\u0074ype":"conversation.item.input_audio_transcription.completed","transcript":"unsafe"}
        """.utf8)
        #expect(DesignCopilotRealtimeSession.event(from: duplicateType) == .invalid)
        #expect(DesignCopilotRealtimeSession.event(from: Data(repeating: 0x20, count: 32_769)) == .invalid)
        #expect(DesignCopilotRealtimeSession.event(from: Data([0xff, 0xfe])) == .invalid)

        let providerError = Data("""
        {"type":"error"}
        """.utf8)
        #expect(DesignCopilotRealtimeSession.event(from: providerError) == .providerError)
    }

    @Test("partial audio acquisition rolls back and a retry releases every resource exactly once")
    func realtimeAudioSetupRollsBackEveryFailureStep() throws {
        for failure in FaultInjectingRealtimeAudioBackend.Step.allCases {
            let backend = FaultInjectingRealtimeAudioBackend(failure: failure)
            let capture = RealtimeAudioCapture(backend: backend)

            #expect(throws: DesignCopilotRealtimeError.audioUnavailable) {
                try capture.start { _ in }
            }
            #expect(!backend.sessionActive)
            #expect(!backend.tapInstalled)
            #expect(!backend.engineStarted)

            backend.failure = nil
            try capture.start { _ in }
            capture.stop()
            capture.stop()

            #expect(!backend.sessionActive)
            #expect(!backend.tapInstalled)
            #expect(!backend.engineStarted)
            #expect(backend.successfulEngineStarts == 1)
            #expect(backend.successfulTapRemovals == (failure == .startEngine ? 2 : 1))
            #expect(backend.successfulDeactivations == (failure == .activateSession ? 1 : 2))
        }
    }

    @Test("Realtime send and transcript deadlines close once and preserve fallback")
    func realtimeDeadlinesTerminateStalledSocket() async throws {
        let secret = RealtimeClientSecret(
            value: "ek_test_deadline",
            expiresAt: Int64(Date().timeIntervalSince1970) + 120,
            session: RealtimeClientSession(id: "sess_test_deadline", model: "gpt-realtime-2.1")
        )

        let stalledSend = TestRealtimeSocket(stallSend: true, received: [])
        let sendAudio = FaultInjectingRealtimeAudioBackend(failure: nil, bytesOnInstall: Data([1, 2]))
        let sendFailures = RealtimeCallbackProbe()
        let sendSession = DesignCopilotRealtimeSession(
            secret: secret,
            audioCapture: RealtimeAudioCapture(backend: sendAudio),
            socketFactory: { _ in stalledSend },
            sendTimeoutNanoseconds: 15_000_000,
            transcriptTimeoutNanoseconds: 15_000_000,
            maximumSessionNanoseconds: 1_000_000_000,
            onTranscript: { _ in await sendFailures.recordTranscript() },
            onFailure: { await sendFailures.recordFailure() }
        )
        try await sendSession.start()
        try await Task.sleep(nanoseconds: 80_000_000)
        #expect(await sendFailures.failures == 1)
        #expect(await sendFailures.transcripts == 0)
        #expect(stalledSend.cancelCount == 1)

        let stalledReceive = TestRealtimeSocket(stallSend: false, received: [])
        let receiveFailures = RealtimeCallbackProbe()
        let receiveSession = DesignCopilotRealtimeSession(
            secret: secret,
            audioCapture: RealtimeAudioCapture(
                backend: FaultInjectingRealtimeAudioBackend(failure: nil)
            ),
            socketFactory: { _ in stalledReceive },
            sendTimeoutNanoseconds: 15_000_000,
            transcriptTimeoutNanoseconds: 15_000_000,
            maximumSessionNanoseconds: 1_000_000_000,
            onTranscript: { _ in await receiveFailures.recordTranscript() },
            onFailure: { await receiveFailures.recordFailure() }
        )
        try await receiveSession.start()
        try await receiveSession.finishInput()
        try await Task.sleep(nanoseconds: 80_000_000)
        #expect(await receiveFailures.failures == 1)
        #expect(await receiveFailures.transcripts == 0)
        #expect(stalledReceive.cancelCount == 1)
    }

    @Test("Realtime rejects an oversized inbound event before JSON parsing")
    func realtimeOversizedInboundEventFailsClosed() async throws {
        let secret = RealtimeClientSecret(
            value: "ek_test_oversize",
            expiresAt: Int64(Date().timeIntervalSince1970) + 120,
            session: RealtimeClientSession(id: "sess_test_oversize", model: "gpt-realtime-2.1")
        )
        let socket = TestRealtimeSocket(
            stallSend: false,
            received: [Data(repeating: 0x20, count: 32_769)]
        )
        let callbacks = RealtimeCallbackProbe()
        let session = DesignCopilotRealtimeSession(
            secret: secret,
            audioCapture: RealtimeAudioCapture(
                backend: FaultInjectingRealtimeAudioBackend(failure: nil)
            ),
            socketFactory: { _ in socket },
            sendTimeoutNanoseconds: 100_000_000,
            transcriptTimeoutNanoseconds: 100_000_000,
            maximumSessionNanoseconds: 1_000_000_000,
            onTranscript: { _ in await callbacks.recordTranscript() },
            onFailure: { await callbacks.recordFailure() }
        )

        try await session.start()
        try await Task.sleep(nanoseconds: 80_000_000)
        #expect(await callbacks.failures == 1)
        #expect(await callbacks.transcripts == 0)
        #expect(socket.cancelCount == 1)
    }

    @Test("voice cancellation invalidates delayed permission before any Realtime session exists")
    func voiceCancellationDuringPermissionCannotStartAudio() async throws {
        let setup = try designCopilotRuntime(support: .healthyFixture)
        await setup.runtime.model.prepare()
        let permission = SuspendedMicrophonePermission()
        let factory = RealtimeSessionFactoryProbe()
        let copilot = DesignCopilotModel(
            runtime: setup.runtime,
            gatewayTokenProvider: { "fixture-gateway-token" },
            microphonePermissionProvider: { await permission.request() },
            realtimeSecretProvider: { _, _ in .validFixture },
            realtimeSessionFactory: { secret, callbacks in
                factory.make(secret: secret, callbacks: callbacks)
            }
        )

        let startup = Task { @MainActor in await copilot.startVoice() }
        await permission.waitUntilRequested()
        await copilot.cancelVoice()
        permission.resolve(true)
        await startup.value

        #expect(factory.creations == 0)
        #expect(!copilot.isWorking)
        #expect(!copilot.isVoiceActive)
        #expect(!copilot.isAwaitingTranscript)
        #expect(copilot.message == "Voice turn cancelled. Typed/tap editing remains available.")
    }

    @Test("voice cancellation invalidates delayed credential mint before socket or audio creation")
    func voiceCancellationDuringSecretMintCannotStartAudio() async throws {
        let setup = try designCopilotRuntime(support: .healthyFixture)
        await setup.runtime.model.prepare()
        let secret = SuspendedRealtimeSecretProvider()
        let factory = RealtimeSessionFactoryProbe()
        let copilot = DesignCopilotModel(
            runtime: setup.runtime,
            gatewayTokenProvider: { "fixture-gateway-token" },
            microphonePermissionProvider: { true },
            realtimeSecretProvider: { _, _ in try await secret.request() },
            realtimeSessionFactory: { value, callbacks in
                factory.make(secret: value, callbacks: callbacks)
            }
        )

        let startup = Task { @MainActor in await copilot.startVoice() }
        await secret.waitUntilRequested()
        await copilot.cancelVoice()
        secret.resolve(.validFixture)
        await startup.value

        #expect(factory.creations == 0)
        #expect(!copilot.isWorking)
        #expect(!copilot.isVoiceActive)
        #expect(!copilot.isAwaitingTranscript)
        #expect(copilot.message == "Voice turn cancelled. Typed/tap editing remains available.")
    }

    @Test("voice cleanup cannot release or overwrite a suspended typed Ask")
    func voiceCleanupDoesNotInterfereWithTypedAsk() async throws {
        let setup = try designCopilotRuntime(support: .healthyFixture)
        await setup.runtime.model.prepare()
        let proposal = SuspendedDesignCopilotProposalProvider()
        let copilot = DesignCopilotModel(
            runtime: setup.runtime,
            gatewayTokenProvider: { "fixture-gateway-token" },
            proposalProvider: { _, _, request in try await proposal.provide(request) }
        )

        let ask = Task { @MainActor in await copilot.ask() }
        await proposal.waitUntilRequested()
        #expect(copilot.isWorking)
        let messageBeforeCleanup = copilot.message
        await copilot.cancelVoice()
        #expect(copilot.isWorking)
        #expect(copilot.message == messageBeforeCleanup)

        let request = try #require(proposal.request)
        proposal.resolve(try strictSemanticEnvelope(
            request: request,
            operation: .place,
            assetID: setup.runtime.catalog.assets[0].assetID,
            suffix: "114"
        ))
        await ask.value

        #expect(!copilot.isWorking)
        #expect(copilot.envelope?.envelopeID.hasSuffix("114") == true)
        #expect(copilot.message == "Preview only after deterministic readiness passes.")
    }

    @Test("AI apply rejects an existing manual preview and Cancel still targets the visible preview")
    func semanticProposalCannotCreateASecondPreview() async throws {
        let harness = try TestRoomEditHarness(support: .healthyFixture)
        await harness.model.prepare()
        await harness.model.selectOperation(.place)
        let visiblePreview = try #require(harness.model.snapshot.preview)
        let context = await harness.model.designCopilotRequestContext()
        let envelope = SemanticProposalEnvelope(
            schemaVersion: "1.0.0",
            envelopeID: "envelope_54000000-0000-4000-8000-000000000099",
            createdAtUTC: "2026-07-19T18:00:00Z",
            requestContext: context,
            ingressSource: .typed,
            semanticModel: SemanticModelReference(
                contractProvider: "openai",
                model: "gpt-5.6-sol",
                responseID: "resp_preview_collision"
            ),
            status: .ready,
            intent: SemanticProposalIntent(
                operation: .place,
                arguments: IntentArguments(assetID: harness.manifest.contractAssetID),
                constraints: []
            ),
            explanation: "Keep the deterministic preview singular.",
            clarification: nil
        )

        do {
            try await harness.model.previewSemanticProposal(envelope)
            Issue.record("AI apply created a second preview")
        } catch {
            #expect(error as? SemanticProposalRejection == .previewAlreadyActive)
        }

        #expect(harness.model.snapshot.preview == visiblePreview)
        #expect(harness.model.snapshot.revision == 0)
        await harness.model.cancelPreview()
        #expect(harness.model.snapshot.preview == nil)
        #expect((await harness.authority.activeSnapshot()).transactions.isEmpty)
    }

    @Test("AI Ask to Apply creates only a deterministic revision-neutral preview")
    func designCopilotAskApplyEndsAtNativePreview() async throws {
        let harness = try TestRoomEditHarness(support: .healthyFixture)
        let catalog = try RoomEditAssetCatalog.load(bundle: Bundle(for: RoomEditModel.self))
        let model = RoomEditModel(
            authority: harness.authority,
            manifest: harness.manifest,
            catalog: catalog,
            supportProvider: { _ in .healthyFixture }
        )
        let runtime = RoomEditRuntime(
            model: model,
            catalog: catalog,
            sharedSession: nil,
            deviceProof: nil,
            fixtureScenario: .healthy
        )
        let proposedAssetID = catalog.assets[1].assetID
        let copilot = DesignCopilotModel(
            runtime: runtime,
            gatewayTokenProvider: { "fixture-gateway-token" },
            proposalProvider: { _, token, request in
                guard token == "fixture-gateway-token" else {
                    throw DesignCopilotGatewayError.rejected
                }
                let envelope = SemanticProposalEnvelope(
                    schemaVersion: "1.0.0",
                    envelopeID: "envelope_54000000-0000-4000-8000-000000000100",
                    createdAtUTC: "2026-07-19T18:00:00Z",
                    requestContext: request.requestContext,
                    ingressSource: request.ingressSource,
                    semanticModel: SemanticModelReference(
                        contractProvider: "openai",
                        model: "gpt-5.6-sol",
                        responseID: "resp_54000000-0000-4000-8000-000000000101"
                    ),
                    status: .ready,
                    intent: SemanticProposalIntent(
                        operation: .place,
                        arguments: IntentArguments(assetID: proposedAssetID),
                        constraints: []
                    ),
                    explanation: "Use the curated cobalt chair.",
                    clarification: nil
                )
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
                return try SemanticProposalEnvelope.decodeStrict(encoder.encode(envelope))
            }
        )

        await model.prepare()
        let revisionBeforeAsk = model.snapshot.revision
        await copilot.ask()

        #expect(copilot.envelope?.status == .ready)
        #expect(copilot.proposedAsset?.assetID == proposedAssetID)
        #expect(copilot.canApplyProposal)
        #expect(model.snapshot.preview == nil)
        #expect(model.snapshot.revision == revisionBeforeAsk)

        await copilot.applyProposal()

        let active = await harness.authority.activeSnapshot()
        #expect(copilot.envelope == nil)
        #expect(model.snapshot.preview != nil)
        #expect(model.snapshot.canConfirm)
        #expect(model.snapshot.selectedOperation == .place)
        #expect(model.snapshot.revision == revisionBeforeAsk)
        #expect(active.scene.sceneRevision == revisionBeforeAsk)
        #expect(active.scene.editHistory.isEmpty)
        #expect(active.receipts.isEmpty)
    }

    @Test("rapid double Apply owns one native preview transition")
    func designCopilotDoubleApplyCreatesOnePreview() async throws {
        let support = SuspendedRoomEditSupportProvider(defaultValue: .healthyFixture)
        let harness = try TestRoomEditHarness(support: .healthyFixture)
        let catalog = try RoomEditAssetCatalog.load(bundle: Bundle(for: RoomEditModel.self))
        let model = RoomEditModel(
            authority: harness.authority,
            manifest: harness.manifest,
            catalog: catalog,
            supportProvider: { _ in await support.provide() }
        )
        let runtime = RoomEditRuntime(
            model: model,
            catalog: catalog,
            sharedSession: nil,
            deviceProof: nil,
            fixtureScenario: .healthy
        )
        let proposedAssetID = catalog.assets[1].assetID
        let copilot = DesignCopilotModel(
            runtime: runtime,
            gatewayTokenProvider: { "fixture-gateway-token" },
            proposalProvider: { _, _, request in
                try strictSemanticEnvelope(
                    request: request,
                    operation: .place,
                    assetID: proposedAssetID,
                    suffix: "113"
                )
            }
        )
        await model.prepare()
        await copilot.ask()
        let pendingEnvelopeID = try #require(copilot.envelope?.envelopeID)
        support.suspendNext()

        let firstApply = Task { @MainActor in await copilot.applyProposal() }
        await support.waitUntilSuspended()
        #expect(model.previewTransitionOwner == .semanticProposal)
        #expect(copilot.isWorking)
        await copilot.ask()
        #expect(copilot.envelope?.envelopeID == pendingEnvelopeID)
        await copilot.applyProposal()
        #expect(copilot.envelope?.envelopeID == pendingEnvelopeID)

        support.resolve(.healthyFixture)
        await firstApply.value

        let active = await harness.authority.activeSnapshot()
        #expect(copilot.envelope == nil)
        #expect(model.previewTransitionOwner == nil)
        #expect(model.snapshot.preview != nil)
        #expect(model.snapshot.revision == 0)
        #expect(active.transactions.isEmpty)
        #expect(active.receipts.isEmpty)
    }

    @Test("AI Apply retains its proposal and reports local blockers when no preview exists")
    func designCopilotApplyCannotReportFalsePreviewSuccess() async throws {
        let cases: [(ProductOperation, RoomEditSupportContext?, RoomEditReplacementAssetState, String)] = [
            (.place, nil, .loading, "110"),
            (.replace, .healthyFixture, .available, "111"),
            (.restore, .healthyFixture, .loading, "112"),
        ]

        for (operation, support, replacementState, suffix) in cases {
            let setup = try designCopilotRuntime(
                support: support,
                replacementAssetState: replacementState
            )
            let proposedAssetID = setup.runtime.catalog.assets[1].assetID
            let copilot = DesignCopilotModel(
                runtime: setup.runtime,
                gatewayTokenProvider: { "fixture-gateway-token" },
                proposalProvider: { _, _, request in
                    try strictSemanticEnvelope(
                        request: request,
                        operation: operation,
                        assetID: operation == .place || operation == .replace
                            ? proposedAssetID
                            : nil,
                        suffix: suffix
                    )
                }
            )
            await setup.runtime.model.prepare()
            await copilot.ask()
            let envelopeID = try #require(copilot.envelope?.envelopeID)

            await copilot.applyProposal()

            let active = await setup.authority.activeSnapshot()
            #expect(copilot.envelope?.envelopeID == envelopeID)
            #expect(copilot.message.hasPrefix("No preview was created:"))
            #expect(setup.runtime.model.snapshot.preview == nil)
            #expect(setup.runtime.model.snapshot.revision == 0)
            #expect(active.scene.editHistory.isEmpty)
            #expect(active.receipts.isEmpty)
        }
    }

    @Test("missing healthy support blocks place without changing canonical revision")
    func supportFailureIsTypedAndNonmutating() async throws {
        let harness = try TestRoomEditHarness(support: nil)
        await harness.model.prepare()
        await harness.model.selectOperation(.place)

        #expect(harness.model.snapshot.revision == 0)
        #expect(harness.model.snapshot.preview == nil)
        #expect(harness.model.snapshot.blocker == .healthySupportRequired)
        #expect((await harness.authority.activeSnapshot()).scene.sceneRevision == 0)
    }

    @Test("preview and cancel keep r0; explicit button confirmation durably activates r1")
    func previewCancelAndConfirmationAreExact() async throws {
        let harness = try TestRoomEditHarness(support: .healthyFixture)
        await harness.model.prepare()
        await harness.model.selectOperation(.place)

        #expect(harness.model.snapshot.operations == RoomEditOperation.allCases)
        #expect(harness.model.snapshot.preview?.baseRevision == 0)
        #expect(harness.model.snapshot.revision == 0)
        #expect(harness.model.snapshot.canConfirm)
        await harness.model.cancelPreview()
        #expect(harness.model.snapshot.preview == nil)
        #expect((await harness.authority.activeSnapshot()).scene.sceneRevision == 0)

        await harness.model.selectOperation(.place)
        await harness.model.confirmPlacementFromButton()
        #expect(harness.model.snapshot.revision == 1)
        #expect(harness.model.snapshot.localState == .durable)
        #expect(harness.model.snapshot.preview == nil)
        #expect(!harness.model.snapshot.canConfirm)
        #expect(harness.model.snapshot.canRestore)
        #expect((await harness.authority.activeSnapshot()).transactions.count == 1)
    }

    @Test("Confirm owns one preview transition across Cancel, manual select, and double tap")
    func confirmationTransitionIsLinearizedAcrossSuspension() async throws {
        let support = SuspendedRoomEditSupportProvider(defaultValue: .healthyFixture)
        let harness = try TestRoomEditHarness(
            support: nil,
            supportProvider: { _ in await support.provide() },
            replacementAssetState: .available,
            replacementSupportedViewPolicy: .fixtureDemoHypothesis
        )
        await harness.model.prepare()
        await harness.model.groundTarget(candidates: [.heroFixture], tracking: .normal)
        await harness.model.selectOperation(.replace)
        let preview = try #require(harness.model.snapshot.preview)
        support.suspendNext()

        let confirmation = Task { @MainActor in
            await harness.model.confirmReplacementFromButton()
        }
        await support.waitUntilSuspended()
        #expect(harness.model.previewTransitionOwner == .confirm(.replace))

        await harness.model.cancelPreview()
        await harness.model.selectOperation(.place)
        await harness.model.confirmReplacementFromButton()
        #expect(harness.model.snapshot.preview == preview)
        #expect(harness.model.snapshot.revision == 0)

        support.resolve(.healthyFixture)
        await confirmation.value

        let active = await harness.authority.activeSnapshot()
        #expect(harness.model.previewTransitionOwner == nil)
        #expect(harness.model.snapshot.preview == nil)
        #expect(harness.model.snapshot.revision == 1)
        #expect(active.transactions.count == 1)
        #expect(active.receipts.count == 1)
    }

    @Test("Manual selection owns the transition and cannot leave a stale confirmed preview")
    func manualSelectionTransitionRejectsStaleConfirmation() async throws {
        let support = SuspendedRoomEditSupportProvider(defaultValue: .healthyFixture)
        let harness = try TestRoomEditHarness(
            support: nil,
            supportProvider: { _ in await support.provide() },
            replacementAssetState: .available,
            replacementSupportedViewPolicy: .fixtureDemoHypothesis
        )
        await harness.model.prepare()
        await harness.model.groundTarget(candidates: [.heroFixture], tracking: .normal)
        await harness.model.selectOperation(.replace)
        support.suspendNext()

        let selection = Task { @MainActor in
            await harness.model.selectOperation(.place)
        }
        await support.waitUntilSuspended()
        #expect(harness.model.previewTransitionOwner == .select(.place))
        await harness.model.confirmReplacementFromButton()
        await harness.model.cancelPreview()
        #expect(harness.model.snapshot.revision == 0)

        support.resolve(.healthyFixture)
        await selection.value

        let active = await harness.authority.activeSnapshot()
        #expect(harness.model.previewTransitionOwner == nil)
        #expect(harness.model.snapshot.selectedOperation == .place)
        #expect(harness.model.snapshot.preview != nil)
        #expect(harness.model.snapshot.revision == 0)
        #expect(active.transactions.isEmpty)
        #expect(active.receipts.isEmpty)
    }

    @Test("restart recovers r1 and offline restore creates a compensating r2")
    func restartAndOfflineRestoreAreDurable() async throws {
        let harness = try TestRoomEditHarness(support: .healthyFixture)
        await harness.model.prepare()
        await harness.model.selectOperation(.place)
        await harness.model.confirmPlacementFromButton()

        let restarted = try harness.restarted(support: nil)
        await restarted.model.prepare()
        #expect(restarted.model.snapshot.revision == 1)
        #expect(restarted.model.snapshot.placedAssetVisible)
        #expect(restarted.model.snapshot.canRestore)

        await restarted.model.restoreFromButton()
        #expect(restarted.model.snapshot.revision == 2)
        #expect(!restarted.model.snapshot.placedAssetVisible)
        #expect(restarted.model.snapshot.localState == .durable)
        let canonical = await restarted.authority.activeSnapshot()
        #expect(canonical.transactions.count == 2)
        #expect(canonical.transactions.last?.compensatesTransactionID == canonical.transactions.first?.transactionID)
    }

    @Test("restore selection previews without mutation until explicit confirmation")
    func restoreRequiresExplicitConfirmation() async throws {
        let harness = try TestRoomEditHarness(support: .healthyFixture)
        await harness.model.prepare()
        await harness.model.selectOperation(.place)
        await harness.model.confirmPlacementFromButton()

        await harness.model.selectOperation(.restore)
        #expect(harness.model.snapshot.preview != nil)
        #expect(harness.model.snapshot.canConfirm)
        #expect(harness.model.snapshot.revision == 1)
        #expect((await harness.authority.activeSnapshot()).transactions.count == 1)

        await harness.model.cancelPreview()
        #expect(harness.model.snapshot.preview == nil)
        #expect(harness.model.snapshot.revision == 1)

        await harness.model.selectOperation(.restore)
        await harness.model.confirmRestoreFromButton()
        #expect(harness.model.snapshot.revision == 2)
        #expect((await harness.authority.activeSnapshot()).transactions.count == 2)
    }

    @Test("replace preview, cancel, confirm, retry, and restore remain exact")
    func replacementJourneyIsExactAndIdempotent() async throws {
        let harness = try TestRoomEditHarness(
            support: .healthyFixture,
            replacementAssetState: .available
        )
        await harness.model.prepare()
        await harness.model.groundTarget(candidates: [.heroFixture], tracking: .normal)

        await harness.model.selectOperation(.replace)
        let preview = harness.model.snapshot
        #expect(preview.revision == 0)
        #expect(preview.canConfirm)
        #expect(preview.preview?.proxyID == harness.manifest.proxyID)
        #expect(preview.render.targetProxy?.kind == .frozenTarget)
        #expect(preview.render.replacementProxy?.kind == .provisionalReplacement)
        #expect(preview.render.targetProxy?.objectID == RoomEditIdentity.targetObjectID)
        #expect(preview.render.replacementProxy?.objectID == RoomEditIdentity.replacementPlacedAssetID)

        await harness.model.cancelPreview()
        #expect(harness.model.snapshot.revision == 0)
        #expect(harness.model.snapshot.preview == nil)
        #expect(harness.model.snapshot.render.replacementProxy == nil)

        await harness.model.selectOperation(.replace)
        await harness.model.confirmReplacementFromButton()
        #expect(harness.model.snapshot.revision == 1)
        #expect(harness.model.snapshot.render.replacementProxy?.kind == .committedReplacement)
        #expect(harness.model.snapshot.canRetryReplacement)
        #expect(harness.model.snapshot.canRestore)

        await harness.model.retryReplacementFromButton()
        #expect(harness.model.snapshot.revision == 1)
        #expect((await harness.authority.activeSnapshot()).transactions.count == 1)

        await harness.model.restoreFromButton()
        #expect(harness.model.snapshot.revision == 2)
        #expect(harness.model.snapshot.render.replacementProxy == nil)
        #expect((await harness.authority.activeSnapshot()).transactions.count == 2)
    }

    @Test("tracking or supported-view revocation freezes the safe target without mutation")
    func replacementRevocationFailsClosed() async throws {
        let harness = try TestRoomEditHarness(
            support: .healthyFixture,
            replacementAssetState: .available
        )
        await harness.model.prepare()
        await harness.model.groundTarget(candidates: [.heroFixture], tracking: .normal)
        await harness.model.selectOperation(.replace)
        #expect(harness.model.snapshot.render.replacementProxy != nil)

        await harness.model.updateTargetTracking(.limited)
        #expect(harness.model.snapshot.revision == 0)
        #expect(harness.model.snapshot.preview == nil)
        #expect(harness.model.snapshot.render.targetProxy?.kind == .frozenTarget)
        #expect(harness.model.snapshot.render.replacementProxy == nil)
        #expect(!harness.model.snapshot.canConfirm)
        #expect((await harness.authority.activeSnapshot()).transactions.isEmpty)
    }

    @Test("missing, corrupt, or unloadable replacement asset keeps replace closed")
    func replacementAssetFailureIsActionableAndNonmutating() async throws {
        for failure in RoomEditReplacementAssetFailure.allCases {
            let harness = try TestRoomEditHarness(
                support: .healthyFixture,
                replacementAssetState: .unavailable(failure)
            )
            await harness.model.prepare()
            await harness.model.groundTarget(candidates: [.heroFixture], tracking: .normal)
            await harness.model.selectOperation(.replace)

            #expect(harness.model.snapshot.revision == 0)
            #expect(harness.model.snapshot.preview == nil)
            #expect(harness.model.snapshot.blocker == .replacementAssetUnavailable(failure))
            #expect(harness.model.snapshot.status.contains("local demo proxy"))
            #expect(harness.model.snapshot.render.replacementProxy == nil)
            #expect((await harness.authority.activeSnapshot()).transactions.isEmpty)
        }
    }

    @Test("replace stays supported-view only and remove remains deferred")
    func unsupportedReplacementViewCannotMutate() async throws {
        let harness = try TestRoomEditHarness(
            support: .healthyFixture,
            replacementAssetState: .available,
            replacementSupportedViewPolicy: .denyAll
        )
        await harness.model.prepare()
        await harness.model.groundTarget(candidates: [.heroFixture], tracking: .normal)
        let before = await harness.authority.activeSnapshot()

        await harness.model.selectOperation(.replace)
        #expect(harness.model.snapshot.blocker == .replacementViewUnsupported)
        #expect(harness.model.snapshot.status.contains("supported view"))
        await harness.model.selectOperation(.remove)
        #expect(harness.model.snapshot.blocker == .removeDeferred)
        #expect(harness.model.snapshot.operations.count == 4)
        #expect(await harness.authority.activeSnapshot() == before)
    }

    @Test("remove is normal-unavailable and only exact compiled demo bytes open the degraded fixture")
    func removeLaunchIsolationAndFixtureDecodingAreClosed() async throws {
        let normal = try TestRoomEditHarness(
            support: .healthyFixture,
            removeLaunchMode: .normal
        )
        await normal.model.prepare()
        await normal.model.groundTarget(candidates: [.heroFixture], tracking: .normal)
        await normal.model.selectOperation(.remove)
        #expect(normal.model.snapshot.blocker == .removeDeferred)
        #expect(normal.model.snapshot.target.readiness.remove == .unavailable)
        #expect(normal.model.snapshot.target.reasons.remove == [.revealQualityFailed])
        #expect(normal.model.snapshot.removeDemo == nil)

        for bytes in [Data(), Data("corrupt".utf8)] {
            let invalid = try TestRoomEditHarness(
                support: .healthyFixture,
                removeLaunchMode: .degradedDemoFixture,
                removeFixtureBytesProvider: { bytes }
            )
            await invalid.model.prepare()
            await invalid.model.groundTarget(candidates: [.heroFixture], tracking: .normal)
            await invalid.model.selectOperation(.remove)
            #expect(invalid.model.snapshot.blocker == .removeFixtureUnavailable)
            #expect(invalid.model.snapshot.removeDemo == nil)
            #expect((await invalid.authority.activeSnapshot()).transactions.isEmpty)
        }

        let fixture = try RoomEditDemoRevealFixture.decodeExact(
            bytes: RoomEditDemoRevealFixture.compiledBytes
        )
        #expect(fixture.classification == "degraded_demo_fixture")
        #expect(fixture.envelopeID.hasPrefix("envelope_"))
        #expect(fixture.surfaces.map(\.surfaceID) == [
            "surface_63000000-0000-4000-8000-000000000041",
            "surface_63000000-0000-4000-8000-000000000042",
        ])
        #expect(fixture.surfaces.count == 2)
        #expect(fixture.assumptionStatus == "HYPOTHESIS")
        #expect(fixture.gate006Status == "PENDING")

        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let auditBytes = try Data(contentsOf: projectRoot.appendingPathComponent(
            "ReRoomDeviceProof/Resources/Phase6Reveal/demo-reveal-fixture.json"
        ))
        let pbxText = try String(contentsOf: projectRoot.appendingPathComponent(
            "ReRoomDeviceProof.xcodeproj/project.pbxproj"
        ), encoding: .utf8)
        #expect(auditBytes == RoomEditDemoRevealFixture.compiledBytes)
        #expect(CanonicalJSON.sha256Hex(auditBytes) == "5a7cb9efb312bef528c279b59bbec55bbd9c54c9d720a0a453b9c177c4c63783")
        #expect(!pbxText.contains("Phase6Reveal"))
    }

    @Test("degraded remove preview confirm retry restart and restore stay exact")
    func removeDemoJourneyIsBoundedAndExactlyOnce() async throws {
        let harness = try TestRoomEditHarness(
            support: .healthyFixture,
            removeLaunchMode: .degradedDemoFixture
        )
        await harness.model.prepare()
        await harness.model.groundTarget(candidates: [.heroFixture], tracking: .normal)
        await harness.model.selectOperation(.remove)

        #expect(harness.model.snapshot.revision == 0)
        #expect(harness.model.snapshot.canConfirm)
        #expect(harness.model.snapshot.removeDemo?.classification == "degraded_demo_fixture")
        #expect(harness.model.snapshot.render.revealProxySurfaces.count == 2)
        #expect(harness.model.snapshot.render.targetProxy == nil)

        await harness.model.confirmRemovalFromButton()
        #expect(harness.model.snapshot.revision == 1)
        #expect(harness.model.snapshot.canRetryRemove)
        #expect(harness.model.snapshot.render.revealProxySurfaces.count == 2)
        await harness.model.retryRemovalFromButton()
        #expect(harness.model.snapshot.revision == 1)
        #expect((await harness.authority.activeSnapshot()).transactions.count == 1)

        let restarted = try harness.restarted(
            support: .healthyFixture,
            removeLaunchMode: .degradedDemoFixture
        )
        await restarted.model.prepare()
        #expect(restarted.model.snapshot.revision == 1)
        #expect(restarted.model.snapshot.render.revealProxySurfaces.count == 2)
        await restarted.model.restoreFromButton()
        #expect(restarted.model.snapshot.revision == 2)
        #expect(restarted.model.snapshot.render.revealProxySurfaces.isEmpty)
        #expect((await restarted.authority.activeSnapshot()).transactions.count == 2)
    }

    @Test("remove fixture pose, tracking, and world invalidation retain the safe original")
    func removeDemoInvalidationFailsClosed() async throws {
        let supportProbe = RoomEditSupportProbe(.outOfViewFixture)
        let harness = try TestRoomEditHarness(
            support: nil,
            supportProvider: { _ in supportProbe.value },
            removeLaunchMode: .degradedDemoFixture
        )
        await harness.model.prepare()
        await harness.model.groundTarget(candidates: [.heroFixture], tracking: .normal)
        await harness.model.selectOperation(.remove)
        #expect(harness.model.snapshot.blocker == .removeViewUnsupported)
        #expect(harness.model.snapshot.render.targetProxy?.kind == .frozenTarget)
        #expect(harness.model.snapshot.render.revealProxySurfaces.isEmpty)

        supportProbe.value = .healthyFixture
        await harness.model.selectOperation(.remove)
        #expect(harness.model.snapshot.render.revealProxySurfaces.count == 2)
        await harness.model.updateTargetTracking(.limited)
        #expect(harness.model.snapshot.preview == nil)
        #expect(harness.model.snapshot.render.targetProxy?.kind == .frozenTarget)
        #expect(harness.model.snapshot.render.revealProxySurfaces.isEmpty)
        #expect((await harness.authority.activeSnapshot()).scene.sceneRevision == 0)

        let worldHarness = try TestRoomEditHarness(
            support: .healthyFixture,
            removeLaunchMode: .degradedDemoFixture
        )
        await worldHarness.model.prepare()
        await worldHarness.model.groundTarget(candidates: [.heroFixture], tracking: .normal)
        await worldHarness.model.selectOperation(.remove)
        await worldHarness.model.noteTargetWorldReset(
            worldFrameID: "world_63000000-0000-4000-8000-000000000099",
            worldFrameVersion: 2,
            tracking: .normal
        )
        #expect(worldHarness.model.snapshot.preview == nil)
        #expect(worldHarness.model.snapshot.render.revealProxySurfaces.isEmpty)
        #expect(worldHarness.model.snapshot.render.targetProxy?.kind == .frozenTarget)
        #expect((await worldHarness.authority.activeSnapshot()).scene.sceneRevision == 0)
    }

    @Test("omitting a supported-view policy fails closed instead of authorizing replace")
    func omittedReplacementPolicyCannotMutate() async throws {
        let harness = try TestRoomEditHarness(
            support: .healthyFixture,
            replacementAssetState: .available,
            replacementSupportedViewPolicy: nil
        )
        await harness.model.prepare()
        await harness.model.groundTarget(candidates: [.heroFixture], tracking: .normal)

        await harness.model.selectOperation(.replace)

        #expect(harness.model.snapshot.blocker == .replacementViewUnsupported)
        #expect(harness.model.snapshot.preview == nil)
        #expect(harness.model.snapshot.render.targetProxy?.kind == .frozenTarget)
        #expect(harness.model.snapshot.render.replacementProxy == nil)
        #expect((await harness.authority.activeSnapshot()).transactions.isEmpty)
    }

    @Test("live demo policy binds the current epoch and a bounded camera pose")
    func liveReplacementPolicyRejectsStaleOrOutOfViewEvidence() throws {
        let manifest = try Phase3ProxyManifest.load(bundle: Bundle(for: RoomEditModel.self))
        let scene = RoomEditFactory.bootstrap(manifest: manifest).scene
        let currentTarget = TargetGroundingReducer.reduce(
            TargetGroundingReducer.initial(environment: .fixture),
            event: .select([.heroFixture]),
            environment: .fixture
        )
        let staleEnvironment = TargetGroundingEnvironment(
            sceneRevision: 1,
            worldFrameID: RoomEditIdentity.worldFrameID,
            worldFrameVersion: 1,
            tracking: .normal,
            supportReady: true,
            restoreEligible: false,
            replaceTargetCanonical: true
        )
        let staleTarget = TargetGroundingReducer.reduce(
            TargetGroundingReducer.initial(environment: staleEnvironment),
            event: .select([.heroFixture(capturedSceneRevision: 1)]),
            environment: staleEnvironment
        )

        #expect(RoomEditSupportedViewPolicy.liveDemoHypothesis.allows(
            scene: scene,
            target: currentTarget,
            support: .healthyFixture
        ))
        #expect(!RoomEditSupportedViewPolicy.liveDemoHypothesis.allows(
            scene: scene,
            target: staleTarget,
            support: .healthyFixture
        ))
        #expect(!RoomEditSupportedViewPolicy.liveDemoHypothesis.allows(
            scene: scene,
            target: currentTarget,
            support: .outOfViewFixture
        ))
    }

    @Test("moving outside the supported view after preview revokes confirmation")
    func replacementConfirmationRevalidatesCurrentPose() async throws {
        let supportProbe = RoomEditSupportProbe(.healthyFixture)
        let harness = try TestRoomEditHarness(
            support: nil,
            supportProvider: { _ in supportProbe.value },
            replacementAssetState: .available,
            replacementSupportedViewPolicy: .liveDemoHypothesis
        )
        await harness.model.prepare()
        await harness.model.groundTarget(candidates: [.heroFixture], tracking: .normal)
        await harness.model.selectOperation(.replace)
        #expect(harness.model.snapshot.preview != nil)

        supportProbe.value = .outOfViewFixture
        await harness.model.confirmReplacementFromButton()

        #expect(harness.model.snapshot.revision == 0)
        #expect(harness.model.snapshot.blocker == .replacementViewUnsupported)
        #expect(harness.model.snapshot.preview == nil)
        #expect(harness.model.snapshot.render.targetProxy?.kind == .frozenTarget)
        #expect(harness.model.snapshot.render.replacementProxy == nil)
        #expect((await harness.authority.activeSnapshot()).transactions.isEmpty)
    }

    @Test("manual target seed is epoch-bound, revision-neutral, and proposal-ready")
    func manualTargetSeedBindsStableContextWithoutMutation() async throws {
        let harness = try TestRoomEditHarness(support: .healthyFixture)
        await harness.model.prepare()
        let before = await harness.authority.activeSnapshot()

        await harness.model.groundTarget(
            candidates: [.heroFixture],
            tracking: .normal
        )

        let target = try #require(harness.model.snapshot.target.target)
        let context = try #require(harness.model.snapshot.targetContext)
        #expect(target.objectID == RoomEditIdentity.targetObjectID)
        #expect(target.lifecycle == .tracked)
        #expect(target.frozenProxy.version == 1)
        #expect(target.frozenProxy.capturedSceneRevision == 0)
        #expect(context.selectedObjectID == RoomEditIdentity.targetObjectID)
        #expect(context.candidateObjectIDs == [RoomEditIdentity.targetObjectID])
        #expect(context.worldFrameID == before.scene.worldFrame.worldFrameID)
        #expect(context.worldFrameVersion == before.scene.worldFrame.worldFrameVersion)
        #expect(harness.model.snapshot.revision == before.scene.sceneRevision)
        #expect(await harness.authority.activeSnapshot() == before)
    }

    @Test("miss and ambiguity are typed and preserve prior target plus revision")
    func failedGroundingIsNonmutating() async throws {
        let harness = try TestRoomEditHarness(support: .healthyFixture)
        await harness.model.prepare()
        await harness.model.groundTarget(candidates: [.heroFixture], tracking: .normal)
        let grounded = harness.model.snapshot.target.target

        await harness.model.groundTarget(candidates: [], tracking: .normal)
        #expect(harness.model.snapshot.target.failure == .targetMissed)
        #expect(harness.model.snapshot.target.target == grounded)
        #expect(harness.model.snapshot.revision == 0)

        await harness.model.groundTarget(
            candidates: [.heroFixture, .heroFixture(offsetX: 0.25)],
            tracking: .normal
        )
        #expect(harness.model.snapshot.target.failure == .targetAmbiguous)
        #expect(harness.model.snapshot.target.target == grounded)
        #expect((await harness.authority.activeSnapshot()).scene.sceneRevision == 0)
    }

    @Test("stale, wrong-epoch, unsupported, and unhealthy candidates fail closed")
    func invalidCandidatesFailClosed() {
        let environment = TargetGroundingEnvironment.fixture
        let initial = TargetGroundingReducer.initial(environment: environment)
        let invalidCases: [(ManualTargetCandidate, TargetGroundingFailure)] = [
            (.heroFixture(capturedSceneRevision: 1), .staleSceneRevision),
            (.heroFixture(worldFrameVersion: 2), .worldFrameMismatch),
            (.heroFixture(category: .unsupported("sofa")), .unsupportedTargetCategory),
        ]

        for (candidate, expectedFailure) in invalidCases {
            let reduced = TargetGroundingReducer.reduce(
                initial,
                event: .select([candidate]),
                environment: environment
            )
            #expect(reduced.failure == expectedFailure)
            #expect(reduced.target == nil)
        }

        let unhealthy = TargetGroundingReducer.reduce(
            initial,
            event: .select([.heroFixture]),
            environment: environment.with(tracking: .limited)
        )
        #expect(unhealthy.failure == .trackingNotNormal)
        #expect(unhealthy.target == nil)
    }

    @Test("tracking loss revokes edit readiness but restore remains transaction-derived")
    func readinessIsIndependentAcrossCapabilities() throws {
        let readyEnvironment = TargetGroundingEnvironment.fixture.with(restoreEligible: true)
        let seeded = TargetGroundingReducer.reduce(
            TargetGroundingReducer.initial(environment: readyEnvironment),
            event: .select([.heroFixture]),
            environment: readyEnvironment
        )

        #expect(seeded.readiness.select == .ready)
        #expect(seeded.readiness.place == .ready)
        #expect(seeded.readiness.replace == .degraded)
        #expect(seeded.readiness.remove == .unavailable)
        #expect(seeded.readiness.restore == .ready)
        #expect(seeded.reasons.replace == [.providerUnavailable])
        #expect(seeded.reasons.remove == [.revealQualityFailed])

        let lostEnvironment = readyEnvironment.with(tracking: .notAvailable)
        let lost = TargetGroundingReducer.reduce(
            seeded,
            event: .trackingChanged,
            environment: lostEnvironment
        )
        #expect(lost.target?.lifecycle == .lost)
        #expect(lost.readiness.select == .unavailable)
        #expect(lost.readiness.place == .unavailable)
        #expect(lost.readiness.replace == .unavailable)
        #expect(lost.readiness.restore == .ready)
        #expect(lost.reasons.select == [.trackingNotNormal])
    }

    @Test("world reset requires explicit reseed and preserves semantic identity")
    func reseedReplacesOnlySpatialEvidence() throws {
        let firstEnvironment = TargetGroundingEnvironment.fixture
        let seeded = TargetGroundingReducer.reduce(
            TargetGroundingReducer.initial(environment: firstEnvironment),
            event: .select([.heroFixture]),
            environment: firstEnvironment
        )
        let firstTarget = try #require(seeded.target)
        let resetEnvironment = firstEnvironment.with(worldFrameVersion: 2)
        let reset = TargetGroundingReducer.reduce(
            seeded,
            event: .worldReset,
            environment: resetEnvironment
        )
        #expect(reset.target?.lifecycle == .lost)
        #expect(reset.target?.frozenProxy == firstTarget.frozenProxy)
        #expect(reset.failure == .worldFrameMismatch)

        let recovered = TargetGroundingReducer.reduce(
            reset,
            event: .reseed([.heroFixture(worldFrameVersion: 2, offsetX: 0.4)]),
            environment: resetEnvironment
        )
        let recoveredTarget = try #require(recovered.target)
        #expect(recoveredTarget.objectID == firstTarget.objectID)
        #expect(recoveredTarget.lifecycle == .tracked)
        #expect(recoveredTarget.frozenProxy.version == 2)
        #expect(recoveredTarget.frozenProxy.worldFrameVersion == 2)
        #expect(recoveredTarget.frozenProxy.worldFromTarget != firstTarget.frozenProxy.worldFromTarget)
        #expect(recovered.failure == nil)
    }
}

private final class FaultInjectingRealtimeAudioBackend: @unchecked Sendable, RealtimeAudioCaptureBackend {
    enum Step: CaseIterable {
        case activateSession
        case installTap
        case startEngine
    }

    var failure: Step?
    private let bytesOnInstall: Data?
    private(set) var sessionActive = false
    private(set) var tapInstalled = false
    private(set) var engineStarted = false
    private(set) var successfulEngineStarts = 0
    private(set) var successfulTapRemovals = 0
    private(set) var successfulDeactivations = 0

    init(failure: Step?, bytesOnInstall: Data? = nil) {
        self.failure = failure
        self.bytesOnInstall = bytesOnInstall
    }

    func activateSession() throws {
        if failure == .activateSession { throw DesignCopilotRealtimeError.audioUnavailable }
        sessionActive = true
    }

    func installTap(yield: @escaping @Sendable (Data) -> Void) throws {
        if failure == .installTap { throw DesignCopilotRealtimeError.audioUnavailable }
        tapInstalled = true
        if let bytesOnInstall {
            yield(bytesOnInstall)
        }
    }

    func startEngine() throws {
        if failure == .startEngine { throw DesignCopilotRealtimeError.audioUnavailable }
        engineStarted = true
        successfulEngineStarts += 1
    }

    func stopEngine() {
        engineStarted = false
    }

    func removeTap() {
        guard tapInstalled else { return }
        tapInstalled = false
        successfulTapRemovals += 1
    }

    func deactivateSession() {
        guard sessionActive else { return }
        sessionActive = false
        successfulDeactivations += 1
    }
}

private final class TestRealtimeSocket: @unchecked Sendable, DesignCopilotRealtimeSocket {
    private let lock = NSLock()
    private let stallSend: Bool
    private var received: [Data]
    private var sendContinuation: CheckedContinuation<Void, any Error>?
    private var receiveContinuation: CheckedContinuation<Data, any Error>?
    private var cancelled = false
    private var cancellationCount = 0

    init(stallSend: Bool, received: [Data]) {
        self.stallSend = stallSend
        self.received = received
    }

    var cancelCount: Int {
        lock.withLock { cancellationCount }
    }

    func resume() {}

    func send(_: Data) async throws {
        if !stallSend { return }
        try await withCheckedThrowingContinuation { continuation in
            let cancelImmediately = lock.withLock {
                if cancelled { return true }
                sendContinuation = continuation
                return false
            }
            if cancelImmediately {
                continuation.resume(throwing: CancellationError())
            }
        }
    }

    func receive() async throws -> Data {
        if let next = lock.withLock({ received.isEmpty ? nil : received.removeFirst() }) {
            return next
        }
        return try await withCheckedThrowingContinuation { continuation in
            let cancelImmediately = lock.withLock {
                if cancelled { return true }
                receiveContinuation = continuation
                return false
            }
            if cancelImmediately {
                continuation.resume(throwing: CancellationError())
            }
        }
    }

    func cancel() {
        let continuations = lock.withLock { () -> (
            CheckedContinuation<Void, any Error>?,
            CheckedContinuation<Data, any Error>?
        ) in
            guard !cancelled else { return (nil, nil) }
            cancelled = true
            cancellationCount += 1
            defer {
                sendContinuation = nil
                receiveContinuation = nil
            }
            return (sendContinuation, receiveContinuation)
        }
        continuations.0?.resume(throwing: CancellationError())
        continuations.1?.resume(throwing: CancellationError())
    }
}

private actor RealtimeCallbackProbe {
    private(set) var failures = 0
    private(set) var transcripts = 0

    func recordFailure() {
        failures += 1
    }

    func recordTranscript() {
        transcripts += 1
    }
}

private extension RealtimeClientSecret {
    static var validFixture: Self {
        Self(
            value: "ek_test_cancelled_startup",
            expiresAt: Int64(Date().timeIntervalSince1970) + 120,
            session: RealtimeClientSession(
                id: "sess_test_cancelled_startup",
                model: "gpt-realtime-2.1"
            )
        )
    }
}

@MainActor
private final class SuspendedMicrophonePermission {
    private var continuation: CheckedContinuation<Bool, Never>?
    private(set) var requested = false

    func request() async -> Bool {
        requested = true
        return await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilRequested() async {
        while !requested {
            await Task.yield()
        }
    }

    func resolve(_ granted: Bool) {
        let pending = continuation
        continuation = nil
        pending?.resume(returning: granted)
    }
}

@MainActor
private final class SuspendedRealtimeSecretProvider {
    private var continuation: CheckedContinuation<RealtimeClientSecret, any Error>?
    private(set) var requested = false

    func request() async throws -> RealtimeClientSecret {
        requested = true
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func waitUntilRequested() async {
        while !requested {
            await Task.yield()
        }
    }

    func resolve(_ secret: RealtimeClientSecret) {
        let pending = continuation
        continuation = nil
        pending?.resume(returning: secret)
    }
}

@MainActor
private final class SuspendedDesignCopilotProposalProvider {
    private var continuation: CheckedContinuation<SemanticProposalEnvelope, any Error>?
    private(set) var request: DesignCopilotProposalRequest?

    func provide(_ request: DesignCopilotProposalRequest) async throws -> SemanticProposalEnvelope {
        self.request = request
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func waitUntilRequested() async {
        while request == nil {
            await Task.yield()
        }
    }

    func resolve(_ envelope: SemanticProposalEnvelope) {
        let pending = continuation
        continuation = nil
        pending?.resume(returning: envelope)
    }
}

@MainActor
private final class RealtimeSessionFactoryProbe {
    private(set) var creations = 0

    func make(
        secret: RealtimeClientSecret,
        callbacks: DesignCopilotRealtimeCallbacks
    ) -> DesignCopilotRealtimeSession {
        creations += 1
        return DesignCopilotRealtimeSession(
            secret: secret,
            audioCapture: RealtimeAudioCapture(
                backend: FaultInjectingRealtimeAudioBackend(failure: nil)
            ),
            socketFactory: { _ in TestRealtimeSocket(stallSend: false, received: []) },
            onTranscript: callbacks.onTranscript,
            onFailure: callbacks.onFailure
        )
    }
}

private struct TestRoomEditHarness {
    let fileSystem: RoomEditMemoryFileSystem
    let manifest: Phase3ProxyManifest
    let authority: NativeBranchAuthority
    let model: RoomEditModel

    @MainActor
    init(
        support: RoomEditSupportContext?,
        supportProvider: RoomEditSupportProvider? = nil,
        targetSession: (any RoomEditTargetSession)? = nil,
        preloadedCandidate: TransactionGenerationCandidate? = nil,
        replacementAssetState: RoomEditReplacementAssetState = .available,
        replacementSupportedViewPolicy: RoomEditSupportedViewPolicy? = .fixtureDemoHypothesis,
        removeLaunchMode: RoomEditRemoveLaunchMode = .normal,
        removeFixtureBytesProvider: @escaping RoomEditRemoveFixtureBytesProvider = {
            RoomEditDemoRevealFixture.compiledBytes
        }
    ) throws {
        let fileSystem = RoomEditMemoryFileSystem()
        let manifest = try Phase3ProxyManifest.load(bundle: Bundle(for: RoomEditModel.self))
        let store = TransactionStore(
            fileSystem: TransactionFileSystemAdapter(fileSystem: fileSystem, rootPath: "room-edit-test"),
            contracts: TransactionContractAdapter(validator: try DiagnosticAppOwner.makeContractValidator())
        )
        if let preloadedCandidate {
            _ = try store.activate(preloadedCandidate)
        }
        let authority = try NativeBranchAuthority(
            store: store,
            bootstrap: RoomEditFactory.bootstrap(manifest: manifest),
            locallyAvailableArtifacts: [manifest.artifactReference] + [
                removeLaunchMode == .degradedDemoFixture
                    ? try? RoomEditDemoRevealFixture.decodeExact(bytes: removeFixtureBytesProvider())
                        .revealReference
                    : nil,
            ].compactMap { $0 }
        )
        self.fileSystem = fileSystem
        self.manifest = manifest
        self.authority = authority
        if let replacementSupportedViewPolicy {
            self.model = RoomEditModel(
                authority: authority,
                manifest: manifest,
                supportProvider: supportProvider ?? { _ in support },
                targetSession: targetSession,
                replacementAssetState: replacementAssetState,
                replacementSupportedViewPolicy: replacementSupportedViewPolicy,
                removeLaunchMode: removeLaunchMode,
                removeFixtureBytesProvider: removeFixtureBytesProvider
            )
        } else {
            self.model = RoomEditModel(
                authority: authority,
                manifest: manifest,
                supportProvider: supportProvider ?? { _ in support },
                targetSession: targetSession,
                replacementAssetState: replacementAssetState,
                removeLaunchMode: removeLaunchMode,
                removeFixtureBytesProvider: removeFixtureBytesProvider
            )
        }
    }

    @MainActor
    func restarted(
        support: RoomEditSupportContext?,
        removeLaunchMode: RoomEditRemoveLaunchMode = .normal
    ) throws -> (
        model: RoomEditModel,
        authority: NativeBranchAuthority
    ) {
        let recoveredAuthority = try NativeBranchAuthority(
            store: TransactionStore(
                fileSystem: TransactionFileSystemAdapter(fileSystem: fileSystem, rootPath: "room-edit-test"),
                contracts: TransactionContractAdapter(validator: try DiagnosticAppOwner.makeContractValidator())
            ),
            bootstrap: RoomEditFactory.bootstrap(manifest: manifest),
            locallyAvailableArtifacts: [manifest.artifactReference] + [
                removeLaunchMode == .degradedDemoFixture
                    ? try? RoomEditDemoRevealFixture.decodeExact(
                        bytes: RoomEditDemoRevealFixture.compiledBytes
                    ).revealReference
                    : nil,
            ].compactMap { $0 }
        )
        return (
            model: RoomEditModel(
                authority: recoveredAuthority,
                manifest: manifest,
                supportProvider: { _ in support },
                replacementSupportedViewPolicy: .fixtureDemoHypothesis,
                removeLaunchMode: removeLaunchMode
            ),
            authority: recoveredAuthority
        )
    }
}

private extension RoomEditSupportContext {
    static let healthyFixture = RoomEditSupportContext(
        capturedFrameID: RoomEditIdentity.frameID,
        surfaceID: RoomEditIdentity.surfaceID,
        cameraPose: .identity,
        worldFromAsset: Matrix4(values: [
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, -1.2,
            0, 0, 0, 1,
        ]),
        confidence: 0.95,
        method: "arkit_plane"
    )

    static let outOfViewFixture = RoomEditSupportContext(
        capturedFrameID: RoomEditIdentity.frameID,
        surfaceID: RoomEditIdentity.surfaceID,
        cameraPose: Matrix4(values: [
            1, 0, 0, 1.0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1,
        ]),
        worldFromAsset: Matrix4(values: [
            1, 0, 0, 1.0,
            0, 1, 0, 0,
            0, 0, 1, -1.2,
            0, 0, 0, 1,
        ]),
        confidence: 0.95,
        method: "arkit_plane"
    )
}

@MainActor
private final class RoomEditSupportProbe {
    var value: RoomEditSupportContext?

    init(_ value: RoomEditSupportContext?) {
        self.value = value
    }
}

@MainActor
private final class SuspendedRoomEditSupportProvider {
    private let defaultValue: RoomEditSupportContext?
    private var shouldSuspend = false
    private var isSuspended = false
    private var continuation: CheckedContinuation<RoomEditSupportContext?, Never>?

    init(defaultValue: RoomEditSupportContext?) {
        self.defaultValue = defaultValue
    }

    func suspendNext() {
        shouldSuspend = true
        isSuspended = false
    }

    func provide() async -> RoomEditSupportContext? {
        guard shouldSuspend else { return defaultValue }
        shouldSuspend = false
        isSuspended = true
        return await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilSuspended() async {
        while !isSuspended {
            await Task.yield()
        }
    }

    func resolve(_ value: RoomEditSupportContext?) {
        let pending = continuation
        continuation = nil
        isSuspended = false
        pending?.resume(returning: value)
    }
}

private extension ManualTargetCandidate {
    static var heroFixture: Self { heroFixture() }

    static func heroFixture(
        category: ManualTargetCategory = .chair,
        capturedSceneRevision: UInt64 = 0,
        worldFrameVersion: UInt64 = 1,
        offsetX: Double = 0
    ) -> Self {
        ManualTargetCandidate(
            category: category,
            capturedAtFrameID: RoomEditIdentity.frameID,
            capturedSceneRevision: capturedSceneRevision,
            worldFrameID: RoomEditIdentity.worldFrameID,
            worldFrameVersion: worldFrameVersion,
            cameraPose: .identity,
            worldFromTarget: Matrix4(values: [
                1, 0, 0, offsetX,
                0, 1, 0, 0,
                0, 0, 1, -1.2,
                0, 0, 0, 1,
            ]),
            screenPointEncodedPixels: [320, 480]
        )
    }
}

private extension TargetGroundingEnvironment {
    static let fixture = TargetGroundingEnvironment(
        sceneRevision: 0,
        worldFrameID: RoomEditIdentity.worldFrameID,
        worldFrameVersion: 1,
        tracking: .normal,
        supportReady: true,
        restoreEligible: false,
        replaceTargetCanonical: true
    )

    func with(
        worldFrameVersion: UInt64? = nil,
        tracking: TargetTrackingHealth? = nil,
        restoreEligible: Bool? = nil
    ) -> Self {
        TargetGroundingEnvironment(
            sceneRevision: sceneRevision,
            worldFrameID: worldFrameID,
            worldFrameVersion: worldFrameVersion ?? self.worldFrameVersion,
            tracking: tracking ?? self.tracking,
            supportReady: supportReady,
            restoreEligible: restoreEligible ?? self.restoreEligible,
            replaceTargetCanonical: replaceTargetCanonical
        )
    }
}

private final class RoomEditMemoryFileSystem: ReRoomCaptureCore.CaptureFileSystem, @unchecked Sendable {
    let limits = CaptureFileSystemLimits.production
    private let lock = NSLock()
    private var directories: Set<String> = []
    private var files: [String: Data] = [:]

    func createDirectory(at path: String) throws {
        try withLock {
            guard directories.insert(path).inserted else { throw CaptureFileSystemError.destinationExists }
        }
    }

    func write(_ data: Data, to path: String) throws {
        try withLock {
            guard files[path] == nil else { throw CaptureFileSystemError.destinationExists }
            files[path] = data
        }
    }

    func synchronizeFile(at path: String) throws {
        guard try fileExists(at: path) else { throw CaptureFileSystemError.missingFile }
    }

    func synchronizeDirectory(at path: String) throws {
        let exists = withLock { directories.contains(path) }
        guard exists else { throw CaptureFileSystemError.missingFile }
    }

    func append(_ data: Data, to path: String) throws {
        try withLock {
            guard files[path] != nil else { throw CaptureFileSystemError.missingFile }
            files[path]!.append(data)
        }
    }

    func replace(_ data: Data, at path: String) throws { withLock { files[path] = data } }

    func rename(from sourcePath: String, to destinationPath: String) throws {
        try withLock {
            guard directories.remove(sourcePath) != nil else { throw CaptureFileSystemError.missingFile }
            directories.insert(destinationPath)
        }
    }

    func read(at path: String, maximumBytes: Int?) throws -> Data {
        try withLock {
            guard let data = files[path] else { throw CaptureFileSystemError.missingFile }
            guard data.count <= (maximumBytes ?? limits.maximumReadBytes) else {
                throw CaptureFileSystemError.byteLimitExceeded
            }
            return data
        }
    }

    func fileExists(at path: String) throws -> Bool {
        withLock { directories.contains(path) || files[path] != nil }
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
