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
        guard worldEpoch.captureAvailable else {
            selectedAttempt = nil
            return .rejected(.worldFrameQuarantined)
        }
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
        guard let selectedAttempt else { return .rejected(.noSelection) }
        self.selectedAttempt = nil

        if case .rejected(let coaching) = orientationGate.evaluate(
            selectedAttempt.orientation,
            currentOrientation: currentOrientation,
            sessionIsRunning: sessionIsRunning
        ) {
            return .rejected(.orientation(coaching))
        }
        guard selectedAttempt.worldEpoch.worldFrameID == worldEpoch.worldFrameID,
              selectedAttempt.worldEpoch.worldFrameVersion == worldEpoch.worldFrameVersion
        else {
            return .rejected(.worldFrameChanged)
        }
        guard worldEpoch.captureAvailable else {
            return .rejected(.worldFrameQuarantined)
        }

        return .ready(
            ValidatedCaptureAttempt(
                worldFrameID: selectedAttempt.worldEpoch.worldFrameID,
                worldFrameVersion: selectedAttempt.worldEpoch.worldFrameVersion
            )
        )
    }
}
