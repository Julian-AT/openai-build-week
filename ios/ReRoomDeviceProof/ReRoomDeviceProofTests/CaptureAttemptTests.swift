import Testing
@testable import ReRoomDeviceProof

@Suite("Capture attempts")
struct CaptureAttemptTests {
    private let readyEpoch = WorldEpochSnapshot(
        worldFrameID: "world_00000000-0000-4000-8000-000000000001",
        worldFrameVersion: 1,
        isQuarantined: false
    )

    @Test("Landscape during an attempt rejects capture, preserves ARSession, and coaches retry")
    func landscapeMidAttemptRejectsWithoutStoppingSession() {
        var machine = CaptureAttemptMachine()
        let selection = machine.select(
            orientation: .portrait,
            sessionIsRunning: true,
            worldEpoch: readyEpoch
        )
        #expect(selection == .selected(machine.selectedAttempt!))

        let result = machine.finish(
            currentOrientation: .landscape,
            sessionIsRunning: true,
            worldEpoch: readyEpoch
        )

        #expect(result == .rejected(.orientation(.returnToPortrait)))
        #expect(CaptureRetryCoaching.returnToPortrait.title == "Capture stopped")
        #expect(
            CaptureRetryCoaching.returnToPortrait.message
                == "The phone turned sideways. Return to portrait and try again."
        )
        #expect(CaptureRetryCoaching.returnToPortrait.retryAvailable)
        #expect(CaptureRetryCoaching.returnToPortrait.preservesARSession)
    }

    @Test("A changed epoch rejects stale selected work")
    func changedEpochRejectsAttempt() {
        var machine = CaptureAttemptMachine()
        _ = machine.select(
            orientation: .portrait,
            sessionIsRunning: true,
            worldEpoch: readyEpoch
        )
        let advanced = WorldEpochSnapshot(
            worldFrameID: readyEpoch.worldFrameID,
            worldFrameVersion: 2,
            isQuarantined: false
        )

        #expect(
            machine.finish(
                currentOrientation: .portrait,
                sessionIsRunning: true,
                worldEpoch: advanced
            ) == .rejected(.worldFrameChanged)
        )
    }

    @Test("Quarantine disables selection and completion")
    func quarantineRejectsCapture() {
        let quarantined = WorldEpochSnapshot(
            worldFrameID: readyEpoch.worldFrameID,
            worldFrameVersion: readyEpoch.worldFrameVersion,
            isQuarantined: true
        )
        var selectionMachine = CaptureAttemptMachine()
        #expect(
            selectionMachine.select(
                orientation: .portrait,
                sessionIsRunning: true,
                worldEpoch: quarantined
            ) == .rejected(.worldFrameQuarantined)
        )

        var completionMachine = CaptureAttemptMachine()
        _ = completionMachine.select(
            orientation: .portrait,
            sessionIsRunning: true,
            worldEpoch: readyEpoch
        )
        #expect(
            completionMachine.finish(
                currentOrientation: .portrait,
                sessionIsRunning: true,
                worldEpoch: quarantined
            ) == .rejected(.worldFrameQuarantined)
        )
    }

    @Test("Portrait with a stable healthy epoch produces a bounded capture authorization")
    func stablePortraitAttemptIsReady() {
        var machine = CaptureAttemptMachine()
        _ = machine.select(
            orientation: .portrait,
            sessionIsRunning: true,
            worldEpoch: readyEpoch
        )

        #expect(
            machine.finish(
                currentOrientation: .portrait,
                sessionIsRunning: true,
                worldEpoch: readyEpoch
            ) == .ready(
                ValidatedCaptureAttempt(
                    worldFrameID: readyEpoch.worldFrameID,
                    worldFrameVersion: readyEpoch.worldFrameVersion
                )
            )
        )
    }
}
