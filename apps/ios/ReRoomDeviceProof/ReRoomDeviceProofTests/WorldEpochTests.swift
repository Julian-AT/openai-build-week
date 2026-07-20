import Testing
@testable import ReRoomDeviceProof

@Suite("World epoch ownership")
struct WorldEpochTests {
    private let worldFrameID = "world_00000000-0000-4000-8000-000000000001"
    private let identity = [
        1.0, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    ]

    @Test(
        "Reset and relocalization always advance the sole epoch owner",
        arguments: [WorldEpochChangeReason.arkitReset, .relocalization]
    )
    func everyCoordinateMeaningChangeAdvances(reason: WorldEpochChangeReason) {
        var controller = WorldEpochController(worldFrameID: worldFrameID)

        let transition = controller.advance(
            reason: reason,
            correctionEvidence: .absent
        )

        #expect(transition.previousVersion == 1)
        #expect(transition.currentVersion == 2)
        #expect(controller.worldFrameVersion == 2)
        #expect(transition.quarantinedVersions == [1, 2])
        #expect(controller.snapshot.captureAvailable == false)
    }

    @Test("A finite rigid directed correction releases quarantine")
    func validDirectedCorrectionReleasesQuarantine() {
        var controller = WorldEpochController(worldFrameID: worldFrameID)
        let correction = DirectedWorldFrameCorrection(
            baseWorldFrameVersion: 1,
            targetWorldFrameVersion: 2,
            targetFromBaseTransform: identity
        )

        let transition = controller.advance(
            reason: .arkitReset,
            correctionEvidence: .candidate(correction)
        )

        #expect(transition.currentVersion == 2)
        #expect(transition.correction?.baseWorldFrameVersion == 1)
        #expect(transition.correction?.targetWorldFrameVersion == 2)
        #expect(transition.correction?.targetFromBaseTransform == identity)
        #expect(transition.quarantinedVersions.isEmpty)
        #expect(controller.snapshot.captureAvailable)
    }

    @Test(
        "Missing, ambiguous, invalid, nonfinite, and reverse correction evidence stays quarantined",
        arguments: WorldEpochTests.rejectedEvidence
    )
    func rejectedCorrectionStaysQuarantined(evidence: WorldFrameCorrectionEvidence) {
        var controller = WorldEpochController(worldFrameID: worldFrameID)

        let transition = controller.advance(
            reason: .relocalization,
            correctionEvidence: evidence
        )

        #expect(transition.currentVersion == 2)
        #expect(transition.correction == nil)
        #expect(transition.quarantinedVersions == [1, 2])
        #expect(controller.snapshot.captureAvailable == false)
    }

    private static var rejectedEvidence: [WorldFrameCorrectionEvidence] {
        let identity = [
            1.0, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1,
        ]
        let valid = DirectedWorldFrameCorrection(
            baseWorldFrameVersion: 1,
            targetWorldFrameVersion: 2,
            targetFromBaseTransform: identity
        )
        let invalidRigid = DirectedWorldFrameCorrection(
            baseWorldFrameVersion: 1,
            targetWorldFrameVersion: 2,
            targetFromBaseTransform: [
                2, 0, 0, 0,
                0, 1, 0, 0,
                0, 0, 1, 0,
                0, 0, 0, 1,
            ]
        )
        let nonfinite = DirectedWorldFrameCorrection(
            baseWorldFrameVersion: 1,
            targetWorldFrameVersion: 2,
            targetFromBaseTransform: [
                .infinity, 0, 0, 0,
                0, 1, 0, 0,
                0, 0, 1, 0,
                0, 0, 0, 1,
            ]
        )
        let reverse = DirectedWorldFrameCorrection(
            baseWorldFrameVersion: 2,
            targetWorldFrameVersion: 1,
            targetFromBaseTransform: identity
        )
        return [
            .absent,
            .ambiguous([valid, valid]),
            .candidate(invalidRigid),
            .candidate(nonfinite),
            .candidate(reverse),
        ]
    }
}
