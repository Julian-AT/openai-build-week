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
