import Foundation
import CoreGraphics
import ReRoomCaptureCore
import ReRoomContracts
import ReRoomTransactionCore
import Testing
@testable import ReRoomDeviceProof

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
            supportProvider: { _ in await supportProbe.value() },
            removeLaunchMode: .degradedDemoFixture
        )
        await harness.model.prepare()
        await harness.model.groundTarget(candidates: [.heroFixture], tracking: .normal)
        await harness.model.selectOperation(.remove)
        #expect(harness.model.snapshot.blocker == .removeViewUnsupported)
        #expect(harness.model.snapshot.render.targetProxy?.kind == .frozenTarget)
        #expect(harness.model.snapshot.render.revealProxySurfaces.isEmpty)

        await supportProbe.set(.healthyFixture)
        await harness.model.selectOperation(.remove)
        #expect(harness.model.snapshot.render.revealProxySurfaces.count == 2)
        await harness.model.updateTargetTracking(.limited)
        #expect(harness.model.snapshot.preview == nil)
        #expect(harness.model.snapshot.render.targetProxy?.kind == .frozenTarget)
        #expect(harness.model.snapshot.render.revealProxySurfaces.isEmpty)
        #expect((await harness.authority.activeSnapshot()).scene.sceneRevision == 0)
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
            locallyAvailableArtifacts: [manifest.artifactReference]
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
            locallyAvailableArtifacts: [manifest.artifactReference]
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
