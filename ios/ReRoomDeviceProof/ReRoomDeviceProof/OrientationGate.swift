struct CaptureRetryCoaching: Equatable, Sendable {
    let title: String
    let message: String
    let retryAvailable: Bool
    let preservesARSession: Bool

    static let returnToPortrait = CaptureRetryCoaching(
        title: "Capture stopped",
        message: "The phone turned sideways. Return to portrait and try again.",
        retryAvailable: true,
        preservesARSession: true
    )
}

struct OrientationAttemptSnapshot: Equatable, Sendable {
    let orientation: PhysicalOrientation
    let sessionWasRunning: Bool
}

enum OrientationGateResult: Equatable, Sendable {
    case eligible
    case rejected(CaptureRetryCoaching)
}

struct OrientationGate: Sendable {
    func snapshot(
        orientation: PhysicalOrientation,
        sessionIsRunning: Bool
    ) -> OrientationAttemptSnapshot? {
        OrientationAttemptSnapshot(
            orientation: orientation,
            sessionWasRunning: sessionIsRunning
        )
    }

    func evaluate(
        _ snapshot: OrientationAttemptSnapshot,
        currentOrientation: PhysicalOrientation,
        sessionIsRunning: Bool
    ) -> OrientationGateResult {
        _ = snapshot
        _ = currentOrientation
        _ = sessionIsRunning
        return .eligible
    }
}
