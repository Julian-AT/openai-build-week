struct CaptureFrameSnapshot: Equatable, Sendable {
    let id: String
    let sessionIsRunning: Bool
    let trackingState: DeviceTrackingState

    var isHealthy: Bool {
        sessionIsRunning && trackingState == .normal && id.isEmpty == false
    }
}

struct CaptureAttemptSnapshot: Equatable, Sendable {
    let orientation: OrientationAttemptSnapshot
    let worldEpoch: WorldEpochSnapshot
    let frame: CaptureFrameSnapshot
}

struct ValidatedCaptureAttempt: Equatable, Sendable {
    let worldFrameID: String
    let worldFrameVersion: Int
    let frameSnapshotID: String
}

enum CaptureAttemptRejection: Equatable, Sendable {
    case orientation(CaptureRetryCoaching)
    case worldFrameChanged
    case worldFrameQuarantined
    case sessionUnavailable
    case frameSnapshotChanged
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
        frameSnapshot: CaptureFrameSnapshot,
        worldEpoch: WorldEpochSnapshot
    ) -> CaptureAttemptSelection {
        selectedAttempt = nil

        guard worldEpoch.captureAvailable else {
            return .rejected(.worldFrameQuarantined)
        }
        guard let orientationSnapshot = orientationGate.snapshot(
            orientation: orientation,
            sessionIsRunning: frameSnapshot.sessionIsRunning
        ) else {
            return .rejected(.orientation(.returnToPortrait))
        }
        guard frameSnapshot.isHealthy else {
            return .rejected(.sessionUnavailable)
        }
        let snapshot = CaptureAttemptSnapshot(
            orientation: orientationSnapshot,
            worldEpoch: worldEpoch,
            frame: frameSnapshot
        )
        selectedAttempt = snapshot
        return .selected(snapshot)
    }

    mutating func finish(
        currentOrientation: PhysicalOrientation,
        frameSnapshot: CaptureFrameSnapshot,
        worldEpoch: WorldEpochSnapshot
    ) -> CaptureAttemptResolution {
        guard let selectedAttempt else { return .rejected(.noSelection) }
        self.selectedAttempt = nil

        let orientationResult = orientationGate.evaluate(
            selectedAttempt.orientation,
            currentOrientation: currentOrientation,
            sessionIsRunning: frameSnapshot.sessionIsRunning
        )
        if case .rejected(let coaching) = orientationResult {
            return .rejected(.orientation(coaching))
        }
        if case .sessionUnavailable = orientationResult {
            return .rejected(.sessionUnavailable)
        }
        guard frameSnapshot.isHealthy else {
            return .rejected(.sessionUnavailable)
        }
        guard selectedAttempt.frame == frameSnapshot else {
            return .rejected(.frameSnapshotChanged)
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
                worldFrameVersion: selectedAttempt.worldEpoch.worldFrameVersion,
                frameSnapshotID: selectedAttempt.frame.id
            )
        )
    }
}
