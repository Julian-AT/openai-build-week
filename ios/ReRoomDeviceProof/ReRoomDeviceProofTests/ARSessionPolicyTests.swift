import ARKit
import Testing
@testable import ReRoomDeviceProof

@Suite("AR session policy")
struct ARSessionPolicyTests {
    @Test(
        "Camera authorization controls the required visual capability",
        arguments: [
            (PermissionAuthorizationState.notDetermined, false),
            (.granted, true),
            (.denied, false),
            (.restricted, false),
        ]
    )
    func cameraAuthorization(
        authorization: PermissionAuthorizationState,
        expectedAvailable: Bool
    ) {
        let state = DeviceProofState(cameraAuthorization: authorization)

        #expect(state.cameraCapabilityAvailable == expectedAvailable)
        #expect(state.shouldRunARSession == expectedAvailable)
    }

    @Test(
        "Microphone authorization controls only the optional capability",
        arguments: [
            (PermissionAuthorizationState.notDetermined, false),
            (.granted, true),
            (.denied, false),
            (.restricted, false),
        ]
    )
    func microphoneAuthorization(
        authorization: PermissionAuthorizationState,
        expectedAvailable: Bool
    ) {
        let state = otherwiseReadyState(microphoneAuthorization: authorization)

        #expect(state.optionalMicrophoneCapabilityAvailable == expectedAvailable)
    }

    @Test(
        "Camera denial and restriction block visual work",
        arguments: [
            PermissionAuthorizationState.denied,
            .restricted,
        ]
    )
    func cameraFailureBlocksVisualWork(authorization: PermissionAuthorizationState) {
        var state = otherwiseReadyState(microphoneAuthorization: .granted)
        state.cameraAuthorization = authorization

        #expect(state.cameraCapabilityAvailable == false)
        #expect(state.shouldRunARSession == false)
        #expect(state.arTrackingAvailable == false)
        #expect(state.planeDetectionAvailable == false)
        #expect(state.visualFrameCaptureAvailable == false)
        #expect(state.minimalVisualFramePacketAvailable == false)
    }

    @Test(
        "Microphone denial and restriction leave the visual and typed paths ready",
        arguments: [
            PermissionAuthorizationState.denied,
            .restricted,
        ]
    )
    func microphoneFailureIsIndependent(authorization: PermissionAuthorizationState) {
        let state = otherwiseReadyState(microphoneAuthorization: authorization)

        #expect(state.optionalMicrophoneCapabilityAvailable == false)
        #expect(state.cameraCapabilityAvailable)
        #expect(state.shouldRunARSession)
        #expect(state.arTrackingAvailable)
        #expect(state.planeDetectionAvailable)
        #expect(state.visualFrameCaptureAvailable)
        #expect(state.minimalVisualFramePacketAvailable)
        #expect(state.typedTapP0Available)
    }

    @Test("Landscape gates capture without pausing tracking")
    func landscapePreservesSession() {
        var state = otherwiseReadyState(microphoneAuthorization: .denied)
        #expect(state.visualFrameCaptureAvailable)

        state.physicalOrientation = .landscape

        #expect(state.visualFrameCaptureAvailable == false)
        #expect(state.minimalVisualFramePacketAvailable == false)
        #expect(state.shouldRunARSession)
        #expect(state.session.isRunning)
        #expect(state.arTrackingAvailable)
        #expect(state.planeDetectionAvailable)
    }

    @Test("World reset clears stale plane observations and capture readiness")
    func worldResetClearsSpatialReadiness() {
        var state = otherwiseReadyState(microphoneAuthorization: .denied)

        state.apply(.worldReset)

        #expect(state.session.isRunning)
        #expect(state.session.trackingState == .initializing)
        #expect(state.session.observedPlaneAlignments.isEmpty)
        #expect(state.visualFrameCaptureAvailable == false)
    }

    @Test("World tracking requests both plane types without rear LiDAR")
    func worldTrackingConfiguration() {
        let policy = ARSessionPolicy.deviceProof

        #expect(policy.detectedPlaneAlignments == [.horizontal, .vertical])
        #expect(policy.requiresRearLiDAR == false)
    }

    @MainActor
    @Test("Permission requests use the injected independent boundary")
    func injectedPermissionBoundary() async {
        var requests: [DevicePermission] = []
        let controller = PermissionController(
            statusProvider: { permission in
                permission == .camera ? .notDetermined : .denied
            },
            requestProvider: { permission in
                requests.append(permission)
                return permission == .camera ? .granted : .denied
            }
        )

        #expect(controller.authorizationState(for: .camera) == .notDetermined)
        #expect(controller.authorizationState(for: .microphone) == .denied)
        #expect(await controller.requestAccess(for: .camera) == .granted)
        #expect(await controller.requestAccess(for: .microphone) == .denied)
        #expect(requests == [.camera])
    }

    @MainActor
    @Test("AR controller preserves the running session in landscape")
    func controllerPreservesLandscapeSession() {
        let driver = TestARSessionDriver()
        let controller = ARSessionController(driver: driver)
        var events: [ARSessionEvent] = []
        controller.onEvent = { events.append($0) }

        controller.synchronize(cameraAuthorization: .granted)
        controller.handlePhysicalOrientation(.landscape)
        controller.recordPlaneObservation(.horizontal)

        #expect(driver.runPolicies == [.deviceProof])
        #expect(driver.pauseCallCount == 0)
        #expect(controller.isRunning)
        #expect(events == [.running(true), .planeObserved(.horizontal)])

        controller.synchronize(cameraAuthorization: .denied)

        #expect(driver.pauseCallCount == 1)
        #expect(controller.isRunning == false)
        #expect(events.last == .running(false))
    }

    @MainActor
    @Test("Interruption and failure revoke running state until explicit recovery")
    func controllerRequiresExplicitRecovery() {
        let interruptedDriver = TestARSessionDriver()
        let interrupted = ARSessionController(driver: interruptedDriver)
        var interruptedEvents: [ARSessionEvent] = []
        interrupted.onEvent = { interruptedEvents.append($0) }
        interrupted.synchronize(cameraAuthorization: .granted)

        interrupted.sessionWasInterrupted(ARSession())

        #expect(interrupted.isRunning == false)
        #expect(interrupted.recoveryRequirement == .interruption)
        #expect(interruptedDriver.pauseCallCount == 1)
        #expect(interruptedEvents.suffix(2) == [.tracking(.unavailable), .running(false)])
        interrupted.synchronize(cameraAuthorization: .granted)
        #expect(interruptedDriver.runPolicies.count == 1)
        #expect(interrupted.restartAfterRecovery(cameraAuthorization: .granted))
        #expect(interrupted.isRunning)
        #expect(interrupted.recoveryRequirement == nil)
        #expect(interruptedDriver.runPolicies.count == 2)

        let failedDriver = TestARSessionDriver()
        let failed = ARSessionController(driver: failedDriver)
        failed.synchronize(cameraAuthorization: .granted)
        failed.session(ARSession(), didFailWithError: TestSessionFailure())
        #expect(failed.isRunning == false)
        #expect(failed.recoveryRequirement == .failure)
        #expect(failedDriver.pauseCallCount == 1)
    }

    @MainActor
    @Test("Explicit world reset uses ARKit reset semantics and emits a new spatial epoch event")
    func controllerPerformsExplicitWorldReset() {
        let driver = TestARSessionDriver()
        let controller = ARSessionController(driver: driver)
        var events: [ARSessionEvent] = []
        controller.onEvent = { events.append($0) }
        controller.synchronize(cameraAuthorization: .granted)
        controller.recordPlaneObservation(.horizontal)

        let didReset = controller.performExplicitWorldReset(
            cameraAuthorization: .granted
        )

        #expect(didReset)
        #expect(driver.runPolicies == [.deviceProof])
        #expect(driver.resetPolicies == [.deviceProof])
        #expect(controller.isRunning)
        #expect(events.suffix(2) == [.worldReset, .running(true)])
    }

    @MainActor
    @Test("Registered observers share one ordered synchronous AR event stream")
    func controllerDeliversToMultipleObserversInRegistrationOrder() {
        let driver = TestARSessionDriver()
        let controller = ARSessionController(driver: driver)
        var deliveries: [ObservedDelivery] = []
        let first = controller.addObserver { event in
            deliveries.append(ObservedDelivery(observer: "first", event: event))
        }
        _ = controller.addObserver { event in
            deliveries.append(ObservedDelivery(observer: "second", event: event))
        }

        controller.synchronize(cameraAuthorization: .granted)
        controller.recordTrackingState(.normal)
        controller.recordPlaneObservation(.horizontal)

        #expect(driver.runPolicies == [.deviceProof])
        #expect(deliveries == [
            ObservedDelivery(observer: "first", event: .running(true)),
            ObservedDelivery(observer: "second", event: .running(true)),
            ObservedDelivery(observer: "first", event: .tracking(.normal)),
            ObservedDelivery(observer: "second", event: .tracking(.normal)),
            ObservedDelivery(observer: "first", event: .planeObserved(.horizontal)),
            ObservedDelivery(observer: "second", event: .planeObserved(.horizontal)),
        ])

        #expect(controller.performExplicitWorldReset(cameraAuthorization: .granted))
        #expect(deliveries.suffix(4) == [
            ObservedDelivery(observer: "first", event: .worldReset),
            ObservedDelivery(observer: "second", event: .worldReset),
            ObservedDelivery(observer: "first", event: .running(true)),
            ObservedDelivery(observer: "second", event: .running(true)),
        ])

        controller.removeObserver(first)
        controller.sessionWasInterrupted(ARSession())

        #expect(deliveries.suffix(2) == [
            ObservedDelivery(observer: "second", event: .tracking(.unavailable)),
            ObservedDelivery(observer: "second", event: .running(false)),
        ])
        #expect(driver.pauseCallCount == 1)
        #expect(controller.restartAfterRecovery(cameraAuthorization: .granted))
        #expect(deliveries.last == ObservedDelivery(observer: "second", event: .running(true)))
        #expect(driver.runPolicies == [.deviceProof, .deviceProof])
    }

    @MainActor
    @Test("No-op session state is coalesced without another driver run or event buffer")
    func controllerCoalescesDuplicateNoOpState() {
        let driver = TestARSessionDriver()
        let controller = ARSessionController(driver: driver)
        var events: [ARSessionEvent] = []
        _ = controller.addObserver { events.append($0) }

        controller.synchronize(cameraAuthorization: .granted)
        controller.synchronize(cameraAuthorization: .granted)
        controller.recordTrackingState(.limited)
        controller.recordTrackingState(.limited)
        controller.recordPlaneObservation(.horizontal)
        controller.recordPlaneObservation(.horizontal)

        #expect(driver.runPolicies == [.deviceProof])
        #expect(events == [
            .running(true),
            .tracking(.limited),
            .planeObserved(.horizontal),
        ])
    }

    @MainActor
    @Test("Manual raycast prefers detected horizontal geometry and preserves current-world values")
    func targetRaycastPrefersDetectedGeometry() throws {
        let detected = translatedTransform(x: 0.25, y: 0.5, z: -1.5)
        let estimated = translatedTransform(x: 9, y: 9, z: 9)
        let resolver = TestTargetRaycastResolver(results: [
            .existingPlaneGeometry: [detected],
            .estimatedHorizontalPlane: [estimated],
        ])
        let driver = TestARSessionDriver()
        let controller = ARSessionController(driver: driver, raycastResolver: resolver)
        controller.synchronize(cameraAuthorization: .granted)

        let candidates = controller.targetCandidates(
            at: CGPoint(x: 120, y: 240),
            context: TargetRaycastContext(
                worldFrameID: "world_40000000-0000-4000-8000-000000000001",
                worldFrameVersion: 7,
                capturedSceneRevision: 11
            )
        )

        let candidate = try #require(candidates.first)
        #expect(candidates.count == 1)
        #expect(resolver.requests == [.existingPlaneGeometry])
        #expect(candidate.source == .existingPlaneGeometry)
        #expect(candidate.worldFrameID == "world_40000000-0000-4000-8000-000000000001")
        #expect(candidate.worldFrameVersion == 7)
        #expect(candidate.capturedSceneRevision == 11)
        #expect(candidate.worldFromCandidate.layout == "row_major")
        #expect(candidate.worldFromCandidate.mathConvention == "column_vector")
        #expect(candidate.worldFromCandidate.units == "meters")
        #expect(candidate.worldFromCandidate.values == [
            1, 0, 0, 0.25,
            0, 1, 0, 0.5,
            0, 0, 1, -1.5,
            0, 0, 0, 1,
        ])
    }

    @MainActor
    @Test("Manual raycast falls back explicitly, rejects nonfinite values, and caps candidates")
    func targetRaycastUsesBoundedEstimatedFallback() {
        var nonfinite = matrix_identity_float4x4
        nonfinite.columns.3.x = .infinity
        let resolver = TestTargetRaycastResolver(results: [
            .existingPlaneGeometry: [nonfinite],
            .estimatedHorizontalPlane: (0..<8).map {
                translatedTransform(x: Float($0), y: 0, z: -1)
            },
        ])
        let controller = ARSessionController(
            driver: TestARSessionDriver(),
            raycastResolver: resolver
        )
        controller.synchronize(cameraAuthorization: .granted)

        let candidates = controller.targetCandidates(
            at: CGPoint(x: 10, y: 20),
            context: .init(
                worldFrameID: "world_40000000-0000-4000-8000-000000000002",
                worldFrameVersion: 1,
                capturedSceneRevision: 0
            )
        )

        #expect(resolver.requests == [.existingPlaneGeometry, .estimatedHorizontalPlane])
        #expect(candidates.count == ARSessionController.maximumTargetCandidateCount)
        #expect(candidates.allSatisfy { $0.source == .estimatedHorizontalPlane })
        #expect(
            candidates
                .flatMap { $0.worldFromCandidate.values }
                .allSatisfy { $0.isFinite }
        )
    }

    @MainActor
    @Test("Manual raycast miss and unavailable session return no candidates without hidden work")
    func targetRaycastMissIsEmpty() {
        let resolver = TestTargetRaycastResolver(results: [:])
        let controller = ARSessionController(
            driver: TestARSessionDriver(),
            raycastResolver: resolver
        )
        let context = TargetRaycastContext(
            worldFrameID: "world_40000000-0000-4000-8000-000000000003",
            worldFrameVersion: 1,
            capturedSceneRevision: 2
        )

        #expect(controller.targetCandidates(at: .zero, context: context).isEmpty)
        #expect(resolver.requests.isEmpty)

        controller.synchronize(cameraAuthorization: .granted)
        #expect(controller.targetCandidates(at: .zero, context: context).isEmpty)
        #expect(resolver.requests == [.existingPlaneGeometry, .estimatedHorizontalPlane])
    }

    @MainActor
    @Test("System driver retains the injected AR session as the only world authority")
    func systemDriverUsesInjectedSession() {
        let session = ARSession()
        let driver = SystemARSessionDriver(session: session)

        #expect(driver.session === session)
    }

    private func otherwiseReadyState(
        microphoneAuthorization: PermissionAuthorizationState
    ) -> DeviceProofState {
        DeviceProofState(
            cameraAuthorization: .granted,
            microphoneAuthorization: microphoneAuthorization,
            physicalOrientation: .portrait,
            session: ARSessionEvidence(
                isRunning: true,
                trackingState: .normal,
                observedPlaneAlignments: [.horizontal, .vertical]
            )
        )
    }
}

private struct TestSessionFailure: Error {}

private struct ObservedDelivery: Equatable {
    let observer: String
    let event: ARSessionEvent
}

private func translatedTransform(x: Float, y: Float, z: Float) -> simd_float4x4 {
    var transform = matrix_identity_float4x4
    transform.columns.3 = SIMD4<Float>(x, y, z, 1)
    return transform
}

@MainActor
private final class TestTargetRaycastResolver: TargetRaycastResolving {
    let results: [TargetRaycastSource: [simd_float4x4]]
    private(set) var requests: [TargetRaycastSource] = []

    init(results: [TargetRaycastSource: [simd_float4x4]]) {
        self.results = results
    }

    func raycast(at point: CGPoint, source: TargetRaycastSource) -> [simd_float4x4] {
        _ = point
        requests.append(source)
        return results[source, default: []]
    }
}

@MainActor
private final class TestARSessionDriver: ARSessionDriving {
    var delegate: (any ARSessionDelegate)?
    var currentFrame: ARFrame? { nil }
    private(set) var runPolicies: [ARSessionPolicy] = []
    private(set) var resetPolicies: [ARSessionPolicy] = []
    private(set) var pauseCallCount = 0

    func run(policy: ARSessionPolicy) {
        runPolicies.append(policy)
    }

    func reset(policy: ARSessionPolicy) {
        resetPolicies.append(policy)
    }

    func pause() {
        pauseCallCount += 1
    }
}
