import Testing

@testable import ReRoomCaptureCore

@Suite("FrameSelectionTests")
struct FrameSelectionTests {
    private let policy = try! FrameSelectionPolicy(
        policyID: "policy_selection_hypothesis_1",
        classification: .hypothesis,
        minimumCadenceNanoseconds: 100,
        minimumViewNovelty: 0.25,
        maximumMotionScore: 0.5,
        minimumBlurScore: 0.25,
        minimumExposureScore: 0.25
    )

    @Test("an initial explicit user event is eligible independently of ordinary thresholds")
    func explicitUserEventIsEligible() {
        let input = FrameSelectionInput(
            monotonicTimestampNanoseconds: 1,
            previousSelectedTimestampNanoseconds: nil,
            viewNovelty: 0,
            motionScore: 1,
            blurScore: 0,
            exposureScore: 0,
            isKeyframe: false,
            isUserEvent: true
        )

        #expect(policy.evaluate(input) == .selected(.userEvent))
    }

    @Test("selection uses exact cadence and view-novelty boundaries")
    func exactBoundaries() {
        let cadenceBoundary = validInput(
            timestamp: 200,
            previousTimestamp: 100,
            viewNovelty: 0
        )
        let cadenceAdjacent = validInput(
            timestamp: 199,
            previousTimestamp: 100,
            viewNovelty: 0
        )
        let noveltyBoundary = validInput(
            timestamp: 199,
            previousTimestamp: 100,
            viewNovelty: 0.25
        )
        let noveltyAdjacent = validInput(
            timestamp: 199,
            previousTimestamp: 100,
            viewNovelty: Float(0.25).nextDown
        )

        #expect(policy.evaluate(cadenceBoundary) == .selected(.cadence))
        #expect(policy.evaluate(cadenceAdjacent) == .rejected(.cadenceAndViewInsufficient))
        #expect(policy.evaluate(noveltyBoundary) == .selected(.viewNovelty))
        #expect(policy.evaluate(noveltyAdjacent) == .rejected(.cadenceAndViewInsufficient))
    }

    @Test("keyframe meaning is preserved after deterministic quality checks")
    func keyframeReasonIsStable() {
        let input = FrameSelectionInput(
            monotonicTimestampNanoseconds: 199,
            previousSelectedTimestampNanoseconds: 100,
            viewNovelty: 0,
            motionScore: 0.5,
            blurScore: 0.25,
            exposureScore: 0.25,
            isKeyframe: true,
            isUserEvent: false
        )

        #expect(policy.evaluate(input) == .selected(.keyframe))
    }

    @Test(
        "ordinary quality rejections are explicit and ordered",
        arguments: [
            QualityCase(motion: Float(0.5).nextUp, blur: 1, exposure: 1, expected: .motionTooHigh),
            QualityCase(motion: 0, blur: Float(0.25).nextDown, exposure: 1, expected: .blurTooLow),
            QualityCase(motion: 0, blur: 1, exposure: Float(0.25).nextDown, expected: .exposureTooLow),
        ]
    )
    func qualityRejections(_ fixture: QualityCase) {
        let input = FrameSelectionInput(
            monotonicTimestampNanoseconds: 200,
            previousSelectedTimestampNanoseconds: 100,
            viewNovelty: 1,
            motionScore: fixture.motion,
            blurScore: fixture.blur,
            exposureScore: fixture.exposure,
            isKeyframe: false,
            isUserEvent: false
        )

        #expect(policy.evaluate(input) == .rejected(fixture.expected))
    }

    @Test(
        "invalid and non-finite facts reject before selection",
        arguments: [
            InvalidCase(view: .nan, motion: 0, blur: 1, exposure: 1),
            InvalidCase(view: 0, motion: .infinity, blur: 1, exposure: 1),
            InvalidCase(view: 0, motion: 0, blur: -.infinity, exposure: 1),
            InvalidCase(view: 0, motion: 0, blur: 1, exposure: 1.01),
        ]
    )
    func invalidFactsReject(_ fixture: InvalidCase) {
        let input = FrameSelectionInput(
            monotonicTimestampNanoseconds: 200,
            previousSelectedTimestampNanoseconds: 100,
            viewNovelty: fixture.view,
            motionScore: fixture.motion,
            blurScore: fixture.blur,
            exposureScore: fixture.exposure,
            isKeyframe: false,
            isUserEvent: false
        )

        #expect(policy.evaluate(input) == .rejected(.invalidInput))
    }

    @Test("equal inputs repeat the same decision and reason")
    func deterministicRepeat() {
        let input = validInput(timestamp: 199, previousTimestamp: 100, viewNovelty: 0.75)
        let decisions = (0..<32).map { _ in policy.evaluate(input) }

        #expect(decisions == Array(repeating: .selected(.viewNovelty), count: 32))
        #expect(policy.classification == .hypothesis)
        #expect(policy.policyID == "policy_selection_hypothesis_1")
    }

    @Test("timestamp inversion is invalid instead of underflowing cadence")
    func timestampInversionRejects() {
        let input = validInput(timestamp: 99, previousTimestamp: 100, viewNovelty: 0)
        #expect(policy.evaluate(input) == .rejected(.invalidInput))
    }

    private func validInput(
        timestamp: UInt64,
        previousTimestamp: UInt64?,
        viewNovelty: Float
    ) -> FrameSelectionInput {
        FrameSelectionInput(
            monotonicTimestampNanoseconds: timestamp,
            previousSelectedTimestampNanoseconds: previousTimestamp,
            viewNovelty: viewNovelty,
            motionScore: 0.5,
            blurScore: 0.25,
            exposureScore: 0.25,
            isKeyframe: false,
            isUserEvent: false
        )
    }
}

struct QualityCase: Sendable {
    let motion: Float
    let blur: Float
    let exposure: Float
    let expected: FrameSelectionRejectionReason
}

struct InvalidCase: Sendable {
    let view: Float
    let motion: Float
    let blur: Float
    let exposure: Float
}
