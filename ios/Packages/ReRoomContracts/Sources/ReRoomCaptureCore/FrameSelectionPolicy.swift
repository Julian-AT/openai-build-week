public struct FrameSelectionInput: Equatable, Sendable {
    public let monotonicTimestampNanoseconds: UInt64
    public let previousSelectedTimestampNanoseconds: UInt64?
    public let viewNovelty: Float
    public let motionScore: Float
    public let blurScore: Float
    public let exposureScore: Float
    public let isKeyframe: Bool
    public let isUserEvent: Bool

    public init(
        monotonicTimestampNanoseconds: UInt64,
        previousSelectedTimestampNanoseconds: UInt64?,
        viewNovelty: Float,
        motionScore: Float,
        blurScore: Float,
        exposureScore: Float,
        isKeyframe: Bool,
        isUserEvent: Bool
    ) {
        self.monotonicTimestampNanoseconds = monotonicTimestampNanoseconds
        self.previousSelectedTimestampNanoseconds = previousSelectedTimestampNanoseconds
        self.viewNovelty = viewNovelty
        self.motionScore = motionScore
        self.blurScore = blurScore
        self.exposureScore = exposureScore
        self.isKeyframe = isKeyframe
        self.isUserEvent = isUserEvent
    }
}

public enum FrameSelectionRejectionReason: String, Equatable, Sendable {
    case invalidInput = "invalid_input"
    case motionTooHigh = "motion_too_high"
    case blurTooLow = "blur_too_low"
    case exposureTooLow = "exposure_too_low"
    case cadenceAndViewInsufficient = "cadence_and_view_insufficient"
}

public enum FrameSelectionDecision: Equatable, Sendable {
    case selected(SelectedFrameReason)
    case rejected(FrameSelectionRejectionReason)

    public var selectedReason: SelectedFrameReason? {
        guard case let .selected(reason) = self else { return nil }
        return reason
    }
}

public extension FrameSelectionPolicy {
    /// A pure binary32 decision. Policy numbers remain injected TARGET or HYPOTHESIS values.
    func evaluate(_ input: FrameSelectionInput) -> FrameSelectionDecision {
        guard input.monotonicTimestampNanoseconds > 0,
              input.previousSelectedTimestampNanoseconds.map({
                  input.monotonicTimestampNanoseconds >= $0
              }) != false,
              [input.viewNovelty, input.motionScore, input.blurScore, input.exposureScore]
              .allSatisfy({ $0.isFinite && (0...1).contains($0) })
        else {
            return .rejected(.invalidInput)
        }

        // Explicit capture intent owns the reserved lane and is not an ordinary quality sample.
        if input.isUserEvent {
            return .selected(.userEvent)
        }
        guard input.motionScore <= maximumMotionScore else {
            return .rejected(.motionTooHigh)
        }
        guard input.blurScore >= minimumBlurScore else {
            return .rejected(.blurTooLow)
        }
        guard input.exposureScore >= minimumExposureScore else {
            return .rejected(.exposureTooLow)
        }
        if input.isKeyframe {
            return .selected(.keyframe)
        }
        if input.viewNovelty >= minimumViewNovelty {
            return .selected(.viewNovelty)
        }
        guard let previous = input.previousSelectedTimestampNanoseconds else {
            return .selected(.cadence)
        }
        if input.monotonicTimestampNanoseconds - previous >= minimumCadenceNanoseconds {
            return .selected(.cadence)
        }
        return .rejected(.cadenceAndViewInsufficient)
    }

    /// Converts an eligible decision into a metadata-only, pre-lifecycle admission candidate.
    func admissionCandidate(
        candidateID: String,
        input: FrameSelectionInput
    ) -> CaptureAdmissionCandidate? {
        guard case let .selected(reason) = evaluate(input) else { return nil }
        return CaptureAdmissionCandidate(
            candidateID: candidateID,
            monotonicTimestampNanoseconds: input.monotonicTimestampNanoseconds,
            selectedReason: reason,
            selectorPolicyID: policyID,
            selectorClassification: classification
        )
    }
}
