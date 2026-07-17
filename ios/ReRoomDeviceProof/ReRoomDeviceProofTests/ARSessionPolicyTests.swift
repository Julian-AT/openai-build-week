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
