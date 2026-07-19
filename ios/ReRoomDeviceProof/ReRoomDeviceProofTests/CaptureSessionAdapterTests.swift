import Foundation
import os
import ReRoomContracts
import ReRoomCaptureCore
import Testing

@testable import ReRoomDeviceProof

@Suite("Capture session adapter")
struct CaptureSessionAdapterTests {
    @Test("the GATE-001 launch argument alone enables Release termination diagnostics")
    func releaseLaunchArgumentIsExplicit() {
        #expect(
            Gate001LaunchConfiguration.usesDiagnosticSurface(
                arguments: ["ReRoomDeviceProof"],
                isDebugBuild: false
            ) == false
        )
        #expect(
            Gate001LaunchConfiguration.usesDiagnosticSurface(
                arguments: ["ReRoomDeviceProof", "--gate-001-termination-controls"],
                isDebugBuild: false
            )
        )
        #expect(
            Gate001LaunchConfiguration.usesDiagnosticSurface(
                arguments: ["ReRoomDeviceProof"],
                isDebugBuild: true
            )
        )
    }

    @Test("armed termination matches one exact user-event lifecycle boundary only")
    func gateTerminationIsExactAndOneShot() {
        let terminationCount = OSAllocatedUnfairLock(initialState: 0)
        let controller = Gate001TerminationController {
            terminationCount.withLock { $0 += 1 }
        }
        controller.arm(.journaled)

        controller.observe(
            lifecycleObservation(reason: .cadence, state: .journaled)
        )
        controller.observe(
            lifecycleObservation(reason: .userEvent, state: .selected)
        )
        #expect(terminationCount.withLock { $0 } == 0)
        #expect(controller.armedState == .journaled)

        controller.observe(
            lifecycleObservation(reason: .userEvent, state: .journaled)
        )
        controller.observe(
            lifecycleObservation(reason: .userEvent, state: .journaled)
        )
        #expect(terminationCount.withLock { $0 } == 1)
        #expect(controller.armedState == nil)
    }

    @Test("GATE-001 pressure measurement requires a bounded upload-paused burst")
    func gatePressureMeasurementIsExact() throws {
        let policy = try CapturePressurePolicy(
            policyID: "policy_pressure_hypothesis_device_1",
            classification: .hypothesis,
            ordinaryCapacity: 3,
            optionalComputeDropDepth: 1,
            uploadPauseDepth: 2,
            cadenceReductionDepth: 3
        )
        let gate = CaptureAdmissionGate(pressurePolicy: policy)
        for ordinal in 1...3 {
            #expect(
                gate.offer(
                    CaptureAdmissionCandidate(
                        candidateID: TestCaptureIDs.frame(ordinal),
                        monotonicTimestampNanoseconds: UInt64(ordinal),
                        selectedReason: .viewNovelty,
                        selectorPolicyID: "policy_selection_hypothesis_device_1",
                        selectorClassification: .hypothesis
                    )
                ).isAdmitted
            )
        }
        #expect(
            gate.offer(
                CaptureAdmissionCandidate(
                    candidateID: TestCaptureIDs.frame(4),
                    monotonicTimestampNanoseconds: 4,
                    selectedReason: .viewNovelty,
                    selectorPolicyID: "policy_selection_hypothesis_device_1",
                    selectorClassification: .hypothesis
                )
            ) == .rejected(.ordinaryCapacity)
        )

        let measurement = try #require(
            Gate001PressureMeasurement(capacity: 3, snapshot: gate.snapshot())
        )
        #expect(measurement.capacity == 3)
        #expect(measurement.maximumDepth == 3)
        #expect(measurement.staleDropCount == 0)
        #expect(measurement.capacityDropCount == 1)
        #expect(measurement.pressureApplied)
        #expect(measurement.networkBlackholed)
        #expect(measurement.uploadPausedFirst)
    }

    @Test("GATE-001 pressure harness stalls one ordinary write and never a user event")
    func gatePressureHarnessIsScoped() async {
        let harness = Gate001PressureHarness()
        await harness.arm()
        let blocked = Task {
            await harness.beforePublish(selectedReason: .viewNovelty)
        }
        await harness.waitUntilBlocked()
        #expect(await harness.isBlocking)
        await harness.release()
        await blocked.value
        #expect(await harness.isBlocking == false)

        await harness.arm()
        await harness.beforePublish(selectedReason: .userEvent)
        #expect(await harness.isBlocking == false)
        await harness.release()
    }

    @Test("GATE-001 pressure evidence is durable and machine-readable")
    func gatePressureEvidenceIsExact() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = Gate001PressureEvidenceRecorder(root: root)
        let evidence = Gate001PressureEvidence(
            sessionID: "session_00000000-0000-4000-8000-000000000001",
            implementationRevision: "git:" + String(repeating: "a", count: 40),
            recordedAtUTC: "2026-07-18T12:00:00Z",
            measurement: Gate001PressureMeasurement(
                capacity: 3,
                maximumDepth: 3,
                staleDropCount: 0,
                capacityDropCount: 1,
                pressureApplied: true,
                networkBlackholed: true,
                uploadPausedFirst: true
            )
        )

        let url = try recorder.record(evidence)
        #expect(url.lastPathComponent == "session_00000000-0000-4000-8000-000000000001.json")
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        #expect(Set(object.keys) == [
            "schema_version", "session_id", "implementation_revision", "recorded_at_utc",
            "capacity", "maximum_depth", "stale_drop_count", "capacity_drop_count",
            "pressure_applied", "network_blackholed", "upload_paused_first",
        ])
        #expect(object["schema_version"] as? String == "gate001-pressure-observation/1")
        #expect(object["maximum_depth"] as? Int == 3)
        #expect(object["capacity_drop_count"] as? Int == 1)
        #expect(object["upload_paused_first"] as? Bool == true)
    }

    @MainActor
    @Test("denial writes nothing and each acceptance authorizes a fresh local-only session")
    func consentBoundaryAndFreshSessions() async throws {
        let firstWriter = TestCaptureArchiveSession()
        let secondWriter = TestCaptureArchiveSession()
        let factory = TestCaptureArchiveFactory(writers: [firstWriter, secondWriter])
        let adapter = try makeAdapter(
            identities: TestCaptureIdentities(sessionOrdinals: [1, 2]),
            factory: factory
        )

        adapter.declineDisclosure()

        #expect(adapter.presentation.phase == .declined)
        #expect(await factory.makeCount == 0)
        #expect(await firstWriter.startAuthorizations.isEmpty)

        await adapter.acceptDisclosure()

        #expect(adapter.presentation.phase == .recording)
        #expect(adapter.presentation.sessionID == TestCaptureIDs.session(1))
        let firstAuthorization = try #require(await firstWriter.startAuthorizations.first)
        #expect(firstAuthorization.sessionID == TestCaptureIDs.session(1))
        #expect(firstAuthorization.consentGranted)
        #expect(firstAuthorization.retentionPolicy == .localOnlyUntilShare)

        await adapter.stop()
        await adapter.acceptDisclosure()

        #expect(adapter.presentation.phase == .recording)
        #expect(adapter.presentation.sessionID == TestCaptureIDs.session(2))
        #expect(await factory.makeCount == 2)
        #expect(await secondWriter.startAuthorizations.first?.sessionID == TestCaptureIDs.session(2))
    }

    @MainActor
    @Test("stalled persistence bounds ordinary work plus one nonreplaceable explicit frame")
    func stalledWriterIsBoundedAndTruthful() async throws {
        let writer = TestCaptureArchiveSession(stallsWrites: true)
        let adapter = try makeAdapter(
            identities: TestCaptureIdentities(sessionOrdinals: [1]),
            factory: TestCaptureArchiveFactory(writers: [writer]),
            ordinaryCapacity: 2
        )
        await adapter.acceptDisclosure()

        let first = adapter.offerCapturedFrame(
            snapshot(ordinal: 1, translationX: 0),
            selectionInput: selectionInput(ordinal: 1)
        )
        #expect(first.isAdmitted)
        await writer.waitUntilPublishEntered(1)

        let second = adapter.offerCapturedFrame(
            snapshot(ordinal: 2, translationX: 1),
            selectionInput: selectionInput(ordinal: 2)
        )
        #expect(second.isAdmitted)
        for ordinal in 3...24 {
            #expect(
                adapter.offerCapturedFrame(
                    snapshot(ordinal: ordinal, translationX: Double(ordinal)),
                    selectionInput: selectionInput(ordinal: ordinal)
                ) == .admission(.rejected(.ordinaryCapacity))
            )
        }

        let explicit = adapter.offerCapturedFrame(
            snapshot(ordinal: 100, translationX: 100),
            selectionInput: selectionInput(ordinal: 100, isUserEvent: true)
        )
        let repeatedExplicit = adapter.offerCapturedFrame(
            snapshot(ordinal: 101, translationX: 101),
            selectionInput: selectionInput(ordinal: 101, isUserEvent: true)
        )

        #expect(explicit.isAdmitted)
        #expect(repeatedExplicit == .admission(.rejected(.userEventBusy)))
        #expect(adapter.presentation.explicitCaptureBusy)
        #expect(adapter.presentation.busyMessage == "Saving this capture frame — try again when ready.")
        let admission = try #require(adapter.presentation.admission)
        #expect(admission.outstanding == 3)
        #expect(admission.maximumOutstanding == 3)
        #expect(admission.rejectedOrdinaryCapacity == 22)
        #expect(admission.rejectedUserEventBusy == 1)
        #expect(await writer.publishEnteredCount == 1)
        #expect(await writer.maximumConcurrentPublishes == 1)

        await writer.releaseWrites()
        await adapter.stop()

        #expect(await writer.publishedCandidates.map(\.frameID) == [
            TestCaptureIDs.frame(1),
            TestCaptureIDs.frame(2),
            TestCaptureIDs.frame(100),
        ])
        #expect(await writer.maximumConcurrentPublishes == 1)
        #expect(adapter.presentation.phase == .finalized)
        #expect(adapter.presentation.explicitCaptureBusy == false)

        let profiles = await writer.encodingProfiles
        #expect(profiles.count == 3)
        #expect(profiles[0].worldFromCamera[3] == 0)
        #expect(profiles[1].worldFromCamera[3] == 1)
        #expect(profiles[2].worldFromCamera[3] == 100)
    }

    @MainActor
    @Test("a durable explicit frame receives one provider-independent local acknowledgement")
    func explicitFrameReceivesLocalAcknowledgement() async throws {
        let writer = TestCaptureArchiveSession()
        let adapter = try makeAdapter(
            identities: TestCaptureIdentities(sessionOrdinals: [1]),
            factory: TestCaptureArchiveFactory(writers: [writer])
        )
        await adapter.acceptDisclosure()

        #expect(
            adapter.offerCapturedFrame(
                snapshot(ordinal: 1, translationX: 0),
                selectionInput: selectionInput(ordinal: 1, isUserEvent: true)
            ).isAdmitted
        )
        await adapter.stop()

        #expect(await writer.acknowledgedReceipts.map(\.frameID) == [TestCaptureIDs.frame(1)])
        #expect(adapter.presentation.uploadLabel == "Upload not configured")
    }

    @MainActor
    @Test("background finalization drains when possible and expiration always releases assertion")
    func backgroundFinalizationAndExpiration() async throws {
        let successfulBackground = TestCaptureBackgroundDriver()
        let successful = try makeAdapter(
            identities: TestCaptureIdentities(sessionOrdinals: [1]),
            factory: TestCaptureArchiveFactory(writers: [TestCaptureArchiveSession()]),
            background: successfulBackground
        )
        await successful.acceptDisclosure()

        await successful.finalizeForBackground()

        #expect(successful.presentation.phase == .finalized)
        #expect(successfulBackground.beginCount == 1)
        #expect(successfulBackground.endCount == 1)

        let expiringBackground = TestCaptureBackgroundDriver(expiresImmediately: true)
        let expiring = try makeAdapter(
            identities: TestCaptureIdentities(sessionOrdinals: [2]),
            factory: TestCaptureArchiveFactory(writers: [TestCaptureArchiveSession()]),
            background: expiringBackground
        )
        await expiring.acceptDisclosure()

        await expiring.finalizeForBackground()

        #expect(expiring.presentation.phase == .interrupted)
        #expect(expiring.presentation.admission?.closeReason == .expiration)
        #expect(expiringBackground.beginCount == 1)
        #expect(expiringBackground.endCount == 1)
    }

    @MainActor
    @Test("storage failure recovers only a verified prefix and launch discovery never resumes it")
    func storageFailureAndLaunchDiscovery() async throws {
        let recovered = try verifiedRecovery(sessionOrdinal: 7)
        let discoveryFailure = CaptureRecoveryFailureSnapshot(
            archiveName: "session_corrupt.rrcap",
            message: "Integrity verification failed; no archive records were exposed."
        )
        let recovery = TestCaptureRecoveryDriver(
            discovered: [recovered],
            discoveryFailures: [discoveryFailure],
            recoveredAfterFailure: recovered
        )
        let failingWriter = TestCaptureArchiveSession(stallsWrites: true, failsWrites: true)
        let factory = TestCaptureArchiveFactory(writers: [failingWriter])
        let adapter = try makeAdapter(
            identities: TestCaptureIdentities(sessionOrdinals: [1]),
            factory: factory,
            recovery: recovery
        )

        await adapter.discoverInterruptedArchives()

        #expect(adapter.presentation.phase == .recovered)
        #expect(adapter.presentation.recovered?.report.verdict == .accept)
        #expect(adapter.presentation.recovered?.timeline.map(\.journalSequence) == [0])
        #expect(adapter.presentation.recoveryFailures == [discoveryFailure])
        #expect(await factory.makeCount == 0)

        await adapter.acceptDisclosure()
        #expect(adapter.presentation.sessionID == TestCaptureIDs.session(1))
        #expect(adapter.presentation.sessionID != recovered.recovered.finalization.sessionID)
        #expect(
            adapter.offerCapturedFrame(
                snapshot(ordinal: 1, translationX: 0),
                selectionInput: selectionInput(ordinal: 1)
            ).isAdmitted
        )
        await failingWriter.waitUntilPublishEntered(1)
        await failingWriter.releaseWrites()
        while adapter.presentation.phase == .recording {
            await Task.yield()
        }
        await adapter.stop()

        #expect(adapter.presentation.phase == .recovered)
        #expect(adapter.presentation.recovered == recovered)
        #expect(adapter.presentation.admission?.closeReason == .storageUnavailable)
        #expect(adapter.presentation.failureMessage == "Recovered — capture may be incomplete")
        #expect(await recovery.recoverCount == 1)
    }

    @Test("foundation recovery publishes finalized and recovered inputs before inspection")
    func foundationRecoveryUsesActiveGenerations() async throws {
        let fixture = try NativeRecoveryFixture(
            copying: ["finalized-one-frame.rrcap", "recovered-prefix.rrcap"]
        )
        defer { fixture.remove() }
        try fixture.addOpenTerminalSuffixArchive(
            copying: "recovered-prefix.rrcap",
            as: "open-terminal-suffix.rrcap"
        )
        let driver = FoundationCaptureRecoveryDriver(
            root: fixture.root,
            fixtureManifestSHA256: String(repeating: "a", count: 64),
            repositoryRevision: "git:" + String(repeating: "1", count: 40)
        )

        let discovery = await driver.discoverArchives()

        #expect(discovery.failures.isEmpty)
        #expect(discovery.verified.map(\.recovered.finalization.state) == [
            .finalized, .recoveredPrefix, .recoveredPrefix,
        ])
        #expect(discovery.verified.map(\.timeline.count) == [8, 6, 6])
        #expect(discovery.verified.compactMap(\.recovered.firstInvalidJournalSequence) == [6])
        #expect(try fixture.activePublicationPointers().count == 3)
        for replay in discovery.verified {
            let labels = Set(Mirror(reflecting: replay.report).children.compactMap(\.label))
            #expect(labels.contains("fixture") == false)
            #expect(labels.contains("gate") == false)
        }
    }

    @MainActor
    @Test("launch discovery reports rejected archives without exposing replay records")
    func launchDiscoveryFailureIsVisibleAndClosed() async throws {
        let failure = CaptureRecoveryFailureSnapshot(
            archiveName: "session_rejected.rrcap",
            message: "Integrity verification failed; no archive records were exposed."
        )
        let adapter = try makeAdapter(
            identities: TestCaptureIdentities(sessionOrdinals: [1]),
            factory: TestCaptureArchiveFactory(writers: []),
            recovery: TestCaptureRecoveryDriver(discoveryFailures: [failure])
        )

        await adapter.discoverInterruptedArchives()

        #expect(adapter.presentation.phase == .failed)
        #expect(adapter.presentation.recovered == nil)
        #expect(adapter.presentation.recoveryFailures == [failure])
        #expect(adapter.presentation.failureMessage == failure.message)
    }

    @MainActor
    @Test("per-frame encoding uses the exact pose supplied with each admitted ARFrame snapshot")
    func framePacketEncoderUsesPerFrameProfile() throws {
        let validator = try contractValidator()
        let encoder = FramePacketEncoder(
            validator: validator,
            profile: .syntheticOnePixelPNG
        )
        let firstProfile = try encodingProfile(for: snapshot(ordinal: 1, translationX: 0))
        let secondProfile = try encodingProfile(for: snapshot(ordinal: 2, translationX: 2.5))

        let first = try encoder.encode(
            selectedCandidate(ordinal: 1),
            durableJournalSequence: 2,
            profile: firstProfile
        )
        let second = try encoder.encode(
            selectedCandidate(ordinal: 2),
            durableJournalSequence: 3,
            profile: secondProfile
        )

        let firstPacket = try #require(
            JSONSerialization.jsonObject(with: first.packetData) as? [String: Any]
        )
        let secondPacket = try #require(
            JSONSerialization.jsonObject(with: second.packetData) as? [String: Any]
        )
        let firstPose = try #require(
            (firstPacket["world_from_camera"] as? [String: Any])?["values"] as? [Double]
        )
        let secondPose = try #require(
            (secondPacket["world_from_camera"] as? [String: Any])?["values"] as? [Double]
        )

        #expect(firstPose[3] == 0)
        #expect(secondPose[3] == 2.5)
        #expect(firstPose != secondPose)
    }

    @MainActor
    @Test("presentation keeps local durability upload connectivity and sharing independent")
    func truthfulPresentationLabels() async throws {
        let writer = TestCaptureArchiveSession(stallsWrites: true)
        let adapter = try makeAdapter(
            identities: TestCaptureIdentities(sessionOrdinals: [1]),
            factory: TestCaptureArchiveFactory(writers: [writer]),
            ordinaryCapacity: 2
        )
        await adapter.acceptDisclosure()

        #expect(adapter.presentation.localRecordingLabel == "Recording locally")
        #expect(adapter.presentation.uploadLabel == "Upload not configured")
        #expect(adapter.presentation.shareLabel == "Not shared")

        adapter.setOffline(true)
        #expect(adapter.presentation.localRecordingLabel == "Recording locally")
        #expect(adapter.presentation.uploadLabel == "Offline — no upload connection")
        #expect(adapter.presentation.shareLabel == "Not shared")

        #expect(
            adapter.offerCapturedFrame(
                snapshot(ordinal: 1, translationX: 0),
                selectionInput: selectionInput(ordinal: 1, isUserEvent: true)
            ).isAdmitted
        )
        await writer.waitUntilPublishEntered(1)
        #expect(adapter.presentation.explicitCaptureBusy)
        #expect(DiagnosticCaptureAccessibility.userEventBusy == "diagnostic.capture.user-event-busy")

        await writer.releaseWrites()
        await adapter.stop()
        #expect(adapter.presentation.explicitCaptureBusy == false)
    }

    @Test("verified replay inspector exposes only accepted authoritative timeline entries")
    func verifiedReplayInspectorBoundary() throws {
        let replay = try verifiedRecovery(sessionOrdinal: 7)
        let inspector = try VerifiedReplayInspector(replay: replay)

        #expect(inspector.report.verdict == .accept)
        #expect(inspector.status == .recoveredPrefix)
        #expect(inspector.timeline.map(\.journalSequence) == [0])
        #expect(try inspector.entry(journalSequence: 0).referenceID == TestCaptureIDs.event(1))
        #expect(throws: VerifiedReplayInspectorError.unverifiedSelection) {
            _ = try inspector.entry(journalSequence: 1)
        }
    }

    @MainActor
    @Test("internal diagnostic owner starts the real local archive only after acceptance")
    func diagnosticOwnerStartsCoreArchive() async {
        let owner = DiagnosticAppOwner(
            runtime: DiagnosticRuntimeFacts(
                recordedAtUTC: "2026-07-18T00:00:00Z",
                implementationRevision: "git:" + String(repeating: "1", count: 40),
                fixtureSHA256: String(repeating: "a", count: 64),
                deviceModel: "Simulator fixture",
                osVersion: "iOS fixture",
                appVersion: "0.1.0"
            )
        )

        await owner.grantCaptureConsent()

        #expect(owner.capturePresentation.failureMessage == nil)
        #expect(owner.capturePresentation.phase == .recording)
        await owner.stopCapture()
        #expect(owner.capturePresentation.phase == .finalized)
    }

    @MainActor
    private func makeAdapter(
        identities: TestCaptureIdentities,
        factory: TestCaptureArchiveFactory,
        recovery: TestCaptureRecoveryDriver = TestCaptureRecoveryDriver(),
        background: TestCaptureBackgroundDriver = TestCaptureBackgroundDriver(),
        ordinaryCapacity: Int = 3
    ) throws -> CaptureSessionAdapter {
        CaptureSessionAdapter(
            identities: identities,
            archiveFactory: factory,
            recoveryDriver: recovery,
            storageDriver: TestCaptureStorageDriver(isAvailable: true),
            backgroundDriver: background,
            selectorPolicy: try FrameSelectionPolicy(
                policyID: "policy_selection_hypothesis_device_1",
                classification: .hypothesis,
                minimumCadenceNanoseconds: 1,
                minimumViewNovelty: 0,
                maximumMotionScore: 1,
                minimumBlurScore: 0,
                minimumExposureScore: 0
            ),
            pressurePolicy: try CapturePressurePolicy(
                policyID: "policy_pressure_hypothesis_device_1",
                classification: .hypothesis,
                ordinaryCapacity: ordinaryCapacity,
                optionalComputeDropDepth: 1,
                uploadPauseDepth: max(1, ordinaryCapacity - 1),
                cadenceReductionDepth: ordinaryCapacity
            )
        )
    }

    private func snapshot(ordinal: Int, translationX: Double) -> CapturedFrameSnapshot {
        CapturedFrameSnapshot(
            id: String(1_000_000_000 + ordinal),
            imageData: onePixelPNG,
            imageCodec: "png",
            imageWidth: 1,
            imageHeight: 1,
            orientation: "up",
            colorSpace: "srgb",
            imageRange: "full",
            cropInSensorPixels: FrameCrop(x: 0, y: 0, width: 1, height: 1),
            intrinsicsEncodedPixels: FrameIntrinsics(
                fx: 1,
                fy: 1,
                cx: 0.5,
                cy: 0.5,
                width: 1,
                height: 1
            ),
            encodedFromSensor: [1, 0, 0, 0, 1, 0, 0, 0, 1],
            worldFromCamera: [
                1, 0, 0, translationX,
                0, 1, 0, 0,
                0, 0, 1, 0,
                0, 0, 0, 1,
            ],
            trackingState: "normal",
            trackingReason: "none"
        )
    }

    private func selectionInput(ordinal: Int, isUserEvent: Bool = false) -> FrameSelectionInput {
        FrameSelectionInput(
            monotonicTimestampNanoseconds: UInt64(1_000_000_000 + ordinal),
            previousSelectedTimestampNanoseconds: nil,
            viewNovelty: 1,
            motionScore: 0,
            blurScore: 1,
            exposureScore: 1,
            isKeyframe: false,
            isUserEvent: isUserEvent
        )
    }

    private func encodingProfile(
        for snapshot: CapturedFrameSnapshot
    ) throws -> FramePacketEncodingProfile {
        try FramePacketEncodingProfile(
            codec: snapshot.imageCodec,
            width: snapshot.imageWidth,
            height: snapshot.imageHeight,
            colorSpace: snapshot.colorSpace,
            imageRange: snapshot.imageRange,
            cropInSensorPixels: [
                snapshot.cropInSensorPixels.x,
                snapshot.cropInSensorPixels.y,
                snapshot.cropInSensorPixels.width,
                snapshot.cropInSensorPixels.height,
            ],
            intrinsicsEncodedPixels: [
                snapshot.intrinsicsEncodedPixels.fx,
                snapshot.intrinsicsEncodedPixels.fy,
                snapshot.intrinsicsEncodedPixels.cx,
                snapshot.intrinsicsEncodedPixels.cy,
            ],
            encodedFromSensor: snapshot.encodedFromSensor,
            worldFromCamera: snapshot.worldFromCamera,
            trackingState: snapshot.trackingState,
            trackingReason: snapshot.trackingReason,
            motionScore: 0,
            blurScore: 1,
            exposureScore: 1
        )
    }

    private func selectedCandidate(ordinal: Int) throws -> SelectedFrameCandidate {
        let frameID = TestCaptureIDs.frame(ordinal)
        return try SelectedFrameCandidate(
            sessionID: TestCaptureIDs.session(1),
            frameID: frameID,
            submapID: TestCaptureIDs.submap(1),
            worldFrameID: TestCaptureIDs.world(1),
            worldFrameVersion: 1,
            captureSequence: UInt64(ordinal - 1),
            monotonicTimestampNanoseconds: String(1_000_000_000 + ordinal),
            imageRelativePath: "frames/\(frameID)/image.png",
            packetRelativePath: "frames/\(frameID)/packet.json",
            imageBytes: onePixelPNG,
            selectedReason: .cadence,
            idempotencyKey: TestCaptureIDs.idempotency(ordinal)
        )
    }

    private func lifecycleObservation(
        reason: SelectedFrameReason,
        state: CaptureFrameState
    ) -> CaptureLifecycleObservation {
        CaptureLifecycleObservation(
            sessionID: TestCaptureIDs.session(1),
            frameID: TestCaptureIDs.frame(1),
            selectedReason: reason,
            state: state
        )
    }

    private func verifiedRecovery(sessionOrdinal: Int) throws -> VerifiedCaptureReplay {
        let digest = String(repeating: "a", count: 64)
        let finalization = try CaptureFinalization(
            sessionID: TestCaptureIDs.session(sessionOrdinal),
            archivePath: "\(TestCaptureIDs.session(sessionOrdinal)).recovered-prefix.rrcap",
            state: .recoveredPrefix,
            manifestSHA256: digest,
            lastDurableJournalSequence: 0,
            acceptedFrameCount: 0,
            eventCount: 1
        )
        let recovered = try RecoveredArchive(
            finalization: finalization,
            acceptedJournalRecordCount: 1,
            firstInvalidJournalSequence: 1,
            quarantineSHA256: digest
        )
        let timeline = [
            try ReplayTimelineEntry(
                journalSequence: 0,
                entryType: .event,
                referenceID: TestCaptureIDs.event(1),
                contentSHA256: digest,
                monotonicTimestampNanoseconds: "1000000000"
            ),
        ]
        let report = CaptureReplayIntegrityReport(
            verdict: .accept,
            implementationRevision: "git:" + String(repeating: "1", count: 40),
            sourceIdentitySHA256: digest,
            generationID: digest,
            inventorySHA256: digest,
            archive: CaptureReplayArchiveIntegrity(
                manifestSHA256: digest,
                finalizationState: .recoveredPrefix,
                acceptedFrameCount: 0,
                eventCount: 1,
                journalRecordCount: 1
            ),
            digests: try ReplayDigestSet(
                journalTupleSHA256: digest,
                frameProjectionSHA256: digest,
                eventProjectionSHA256: digest,
                revisionTraceSHA256: digest
            )
        )
        return VerifiedCaptureReplay(recovered: recovered, report: report, timeline: timeline)
    }

    @MainActor
    private func contractValidator() throws -> ContractValidator {
        try DiagnosticAppOwner.makeContractValidator()
    }

    private var onePixelPNG: Data {
        Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        )!
    }
}

@MainActor
private final class TestCaptureIdentities: CaptureIdentityDriving {
    private var sessionOrdinals: [Int]
    private var currentSessionOrdinal = 0

    init(sessionOrdinals: [Int]) {
        self.sessionOrdinals = sessionOrdinals
    }

    func makeSessionID() -> String {
        currentSessionOrdinal = sessionOrdinals.removeFirst()
        return TestCaptureIDs.session(currentSessionOrdinal)
    }

    func makeWorldFrameID() -> String { TestCaptureIDs.world(currentSessionOrdinal) }
    func makeSubmapID() -> String { TestCaptureIDs.submap(currentSessionOrdinal) }
    func makeFrameID(candidateID: String) -> String {
        let ordinal = (Int(candidateID) ?? 1_000_000_001) - 1_000_000_000
        return TestCaptureIDs.frame(ordinal)
    }
    func makeIdempotencyKey(candidateID: String) -> String {
        let suffix = candidateID.replacingOccurrences(of: "frame_", with: "")
        return "frameidem_\(suffix)"
    }
    func makeArchivePath(sessionID: String) -> String { "archives/\(sessionID).rrcap" }
    func monotonicTimestampNanoseconds() -> UInt64 { 1_000_000_000 }
}

private actor TestCaptureArchiveFactory: CaptureArchiveSessionFactory {
    private var writers: [TestCaptureArchiveSession]
    private(set) var makeCount = 0

    init(writers: [TestCaptureArchiveSession]) {
        self.writers = writers
    }

    func makeSession(descriptor: CaptureSessionDescriptor) async throws -> any CaptureArchiveSessionWriting {
        makeCount += 1
        return writers.removeFirst()
    }
}

private actor TestCaptureArchiveSession: CaptureArchiveSessionWriting {
    private let stallsWrites: Bool
    private let failsWrites: Bool
    private var releaseImmediately = false
    private var releaseWaiters = [CheckedContinuation<Void, Never>]()
    private var entryWaiters = [(Int, CheckedContinuation<Void, Never>)]()
    private var activePublishes = 0

    private(set) var startAuthorizations = [CaptureSessionAuthorization]()
    private(set) var publishedCandidates = [SelectedFrameCandidate]()
    private(set) var encodingProfiles = [FramePacketEncodingProfile]()
    private(set) var acknowledgedReceipts = [NetworkEligibleReceipt]()
    private(set) var publishEnteredCount = 0
    private(set) var maximumConcurrentPublishes = 0

    init(stallsWrites: Bool = false, failsWrites: Bool = false) {
        self.stallsWrites = stallsWrites
        self.failsWrites = failsWrites
    }

    func startSession(authorization: CaptureSessionAuthorization) async throws {
        startAuthorizations.append(authorization)
    }

    func publishSelectedFrame(
        _ candidate: SelectedFrameCandidate,
        profile: FramePacketEncodingProfile
    ) async throws -> NetworkEligibleReceipt {
        publishEnteredCount += 1
        activePublishes += 1
        maximumConcurrentPublishes = max(maximumConcurrentPublishes, activePublishes)
        resumeEntryWaiters()
        if stallsWrites, releaseImmediately == false {
            await withCheckedContinuation { continuation in
                releaseWaiters.append(continuation)
            }
        }
        defer { activePublishes -= 1 }
        if failsWrites { throw TestCaptureError.storageUnavailable }
        publishedCandidates.append(candidate)
        encodingProfiles.append(profile)
        return try NetworkEligibleReceipt(
            sessionID: candidate.sessionID,
            frameID: candidate.frameID,
            idempotencyKey: candidate.idempotencyKey,
            packetRelativePath: candidate.packetRelativePath,
            packetSHA256: String(repeating: "a", count: 64),
            imageSHA256: String(repeating: "b", count: 64),
            acceptedSequence: UInt64(publishedCandidates.count - 1),
            durableJournalSequence: UInt64(publishedCandidates.count * 5)
        )
    }

    func recordAcknowledgement(for receipt: NetworkEligibleReceipt) async throws {
        acknowledgedReceipts.append(receipt)
    }

    func finalizeExplicitly() async throws -> CaptureFinalization {
        try CaptureFinalization(
            sessionID: startAuthorizations.last!.sessionID,
            archivePath: "archives/\(startAuthorizations.last!.sessionID).rrcap",
            state: .finalized,
            manifestSHA256: String(repeating: "c", count: 64),
            lastDurableJournalSequence: UInt64(max(0, publishedCandidates.count * 5)),
            acceptedFrameCount: UInt64(publishedCandidates.count),
            eventCount: UInt64(publishedCandidates.count * 4 + 2)
        )
    }

    func waitUntilPublishEntered(_ count: Int) async {
        guard publishEnteredCount < count else { return }
        await withCheckedContinuation { continuation in
            entryWaiters.append((count, continuation))
        }
    }

    func releaseWrites() {
        releaseImmediately = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func resumeEntryWaiters() {
        var remaining = [(Int, CheckedContinuation<Void, Never>)]()
        for waiter in entryWaiters {
            if publishEnteredCount >= waiter.0 {
                waiter.1.resume()
            } else {
                remaining.append(waiter)
            }
        }
        entryWaiters = remaining
    }
}

private actor TestCaptureRecoveryDriver: CaptureRecoveryDriving {
    private let discovered: [VerifiedCaptureReplay]
    private let discoveryFailures: [CaptureRecoveryFailureSnapshot]
    private let recoveredAfterFailure: VerifiedCaptureReplay?
    private(set) var recoverCount = 0

    init(
        discovered: [VerifiedCaptureReplay] = [],
        discoveryFailures: [CaptureRecoveryFailureSnapshot] = [],
        recoveredAfterFailure: VerifiedCaptureReplay? = nil
    ) {
        self.discovered = discovered
        self.discoveryFailures = discoveryFailures
        self.recoveredAfterFailure = recoveredAfterFailure
    }

    func discoverArchives() async -> CaptureRecoveryDiscoverySnapshot {
        CaptureRecoveryDiscoverySnapshot(
            verified: discovered,
            failures: discoveryFailures
        )
    }

    func recoverInterruptedArchive(at archivePath: String) async -> VerifiedCaptureReplay? {
        recoverCount += 1
        return recoveredAfterFailure
    }
}

private struct TestCaptureStorageDriver: CaptureStorageDriving {
    let isAvailable: Bool
}

@MainActor
private final class TestCaptureBackgroundDriver: CaptureBackgroundDriving {
    private let expiresImmediately: Bool
    private(set) var beginCount = 0
    private(set) var endCount = 0

    init(expiresImmediately: Bool = false) {
        self.expiresImmediately = expiresImmediately
    }

    func begin(expiration: @escaping @MainActor @Sendable () -> Void) -> Int {
        beginCount += 1
        if expiresImmediately { expiration() }
        return beginCount
    }

    func end(_ identifier: Int) {
        endCount += 1
    }
}

private enum TestCaptureError: Error {
    case storageUnavailable
}

private struct NativeRecoveryFixture {
    let root: URL

    init(copying archiveNames: [String]) throws {
        var repository = URL(fileURLWithPath: #filePath)
        while FileManager.default.fileExists(
            atPath: repository.appendingPathComponent(".git").path
        ) == false {
            let parent = repository.deletingLastPathComponent()
            guard parent.path != repository.path else {
                throw NativeRecoveryFixtureError.repositoryRootNotFound
            }
            repository = parent
        }
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "reroom-native-recovery-\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let archives = repository.appendingPathComponent(
            "fixtures/capture/1.0.0/rev-001/archives"
        )
        for name in archiveNames {
            try FileManager.default.copyItem(
                at: archives.appendingPathComponent(name),
                to: root.appendingPathComponent(name)
            )
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func activePublicationPointers() throws -> [URL] {
        let publications = root.appendingPathComponent("recovery-publications")
        guard let enumerator = FileManager.default.enumerator(
            at: publications,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        ) else { return [] }
        return enumerator.compactMap { value -> URL? in
            guard let url = value as? URL,
                  url.lastPathComponent == "active-generation.json"
            else { return nil }
            return url
        }.sorted { $0.path < $1.path }
    }

    func addOpenTerminalSuffixArchive(copying sourceName: String, as destinationName: String) throws {
        let source = root.appendingPathComponent(sourceName)
        let destination = root.appendingPathComponent(destinationName)
        try FileManager.default.copyItem(at: source, to: destination)
        let manifestURL = destination.appendingPathComponent("manifest.json")
        var object = try JSONSerialization.jsonObject(
            with: Data(contentsOf: manifestURL)
        ) as! [String: Any]
        let staleJournal = Array((object["journal"] as! [[String: Any]]).prefix(3))
        let staleEvents = Array((object["events"] as! [[String: Any]]).prefix(3))
        let referencedEventPaths = Set(staleEvents.map { $0["payload_path"] as! String })
        object["journal"] = staleJournal
        object["events"] = staleEvents
        object["accepted_frame_order"] = [[String: Any]]()
        object["keyframes"] = [[String: Any]]()
        object["files"] = (object["files"] as! [[String: Any]]).filter {
            referencedEventPaths.contains($0["relative_path"] as! String)
        }
        var replay = object["replay"] as! [String: Any]
        let tuples: [[Any]] = staleJournal.map {
            [
                $0["journal_sequence"]!,
                $0["entry_type"]!,
                $0["reference_id"]!,
                $0["content_sha256"]!,
            ]
        }
        let tupleBytes = try JSONSerialization.data(withJSONObject: tuples, options: [.sortedKeys])
        replay["input_digest"] = ReplayInputIntegrity.sha256Hex(
            try ReplayInputIntegrity.canonicalizeJSON(tupleBytes)
        )
        object["replay"] = replay
        var finalization = object["finalization"] as! [String: Any]
        finalization["state"] = "open"
        finalization["last_durable_journal_sequence"] = 2
        finalization.removeValue(forKey: "manifest_sha256")
        object["finalization"] = finalization
        let unsigned = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let canonicalUnsigned = try ReplayInputIntegrity.canonicalizeJSON(unsigned)
        finalization["manifest_sha256"] = ReplayInputIntegrity.sha256Hex(canonicalUnsigned)
        object["finalization"] = finalization
        let encoded = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try ReplayInputIntegrity.canonicalizeJSON(encoded).write(to: manifestURL, options: .atomic)

        let journal = destination.appendingPathComponent("journal/global.jsonl")
        let handle = try FileHandle(forWritingTo: journal)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(#"{"journal_sequence":6"#.utf8))
    }
}

private enum NativeRecoveryFixtureError: Error {
    case repositoryRootNotFound
}

private enum TestCaptureIDs {
    static func session(_ ordinal: Int) -> String { "session_00000000-0000-4000-8000-\(tail(ordinal))" }
    static func world(_ ordinal: Int) -> String { "world_00000000-0000-4000-8000-\(tail(ordinal))" }
    static func submap(_ ordinal: Int) -> String { "submap_00000000-0000-4000-8000-\(tail(ordinal))" }
    static func frame(_ ordinal: Int) -> String { "frame_00000000-0000-4000-8000-\(tail(ordinal))" }
    static func idempotency(_ ordinal: Int) -> String { "frameidem_00000000-0000-4000-8000-\(tail(ordinal))" }
    static func event(_ ordinal: Int) -> String { "event_00000000-0000-4000-8000-\(tail(ordinal))" }
    private static func tail(_ ordinal: Int) -> String { String(format: "%012d", ordinal) }
}

private extension CaptureFrameOfferResult {
    var isAdmitted: Bool {
        guard case .admission(.admitted) = self else { return false }
        return true
    }
}
