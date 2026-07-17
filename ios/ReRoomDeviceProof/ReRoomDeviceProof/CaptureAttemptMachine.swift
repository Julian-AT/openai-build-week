struct CaptureAttemptSnapshot: Equatable, Sendable {
    let orientation: OrientationAttemptSnapshot
    let worldEpoch: WorldEpochSnapshot
}

struct ValidatedCaptureAttempt: Equatable, Sendable {
    let worldFrameID: String
    let worldFrameVersion: Int
}

enum CaptureAttemptRejection: Equatable, Sendable {
    case orientation(CaptureRetryCoaching)
    case worldFrameChanged
    case worldFrameQuarantined
    case noSelection
}

enum CaptureAttemptSelection: Equatable, Sendable {
    case selected(CaptureAttemptSnapshot)
    case rejected(CaptureAttemptRejection)
}

enum CaptureAttemptResolution: Equatable, Sendable {
    case ready(ValidatedCaptureAttempt)
    case rejected(CaptureAttemptRejection)
}

struct CaptureAttemptMachine: Sendable {
    private let orientationGate = OrientationGate()
    private(set) var selectedAttempt: CaptureAttemptSnapshot?

    mutating func select(
        orientation: PhysicalOrientation,
        sessionIsRunning: Bool,
        worldEpoch: WorldEpochSnapshot
    ) -> CaptureAttemptSelection {
        guard let orientationSnapshot = orientationGate.snapshot(
            orientation: orientation,
            sessionIsRunning: sessionIsRunning
        ) else {
            return .rejected(.orientation(.returnToPortrait))
        }
        let snapshot = CaptureAttemptSnapshot(
            orientation: orientationSnapshot,
            worldEpoch: worldEpoch
        )
        selectedAttempt = snapshot
        return .selected(snapshot)
    }

    mutating func finish(
        currentOrientation: PhysicalOrientation,
        sessionIsRunning: Bool,
        worldEpoch: WorldEpochSnapshot
    ) -> CaptureAttemptResolution {
        _ = currentOrientation
        _ = sessionIsRunning
        _ = worldEpoch
        guard let selectedAttempt else { return .rejected(.noSelection) }
        self.selectedAttempt = nil
        return .ready(
            ValidatedCaptureAttempt(
                worldFrameID: selectedAttempt.worldEpoch.worldFrameID,
                worldFrameVersion: selectedAttempt.worldEpoch.worldFrameVersion
            )
        )
    }
}
