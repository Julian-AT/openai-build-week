import ReRoomContracts

enum WorldEpochChangeReason: String, Equatable, Sendable {
    case arkitReset = "arkit_reset"
    case relocalization
}

struct DirectedWorldFrameCorrection: Equatable, Sendable {
    let baseWorldFrameVersion: Int
    let targetWorldFrameVersion: Int
    let targetFromBaseTransform: [Double]
}

enum WorldFrameCorrectionEvidence: Equatable, Sendable {
    case absent
    case candidate(DirectedWorldFrameCorrection)
    case ambiguous([DirectedWorldFrameCorrection])
}

struct ValidatedWorldFrameCorrection: Equatable, Sendable {
    let baseWorldFrameVersion: Int
    let targetWorldFrameVersion: Int
    let targetFromBaseTransform: [Double]
    let reason: WorldEpochChangeReason
}

struct WorldEpochSnapshot: Equatable, Sendable {
    let worldFrameID: String
    let worldFrameVersion: Int
    let isQuarantined: Bool

    var captureAvailable: Bool { isQuarantined == false }
}

struct WorldEpochTransition: Equatable, Sendable {
    let previousVersion: Int
    let currentVersion: Int
    let correction: ValidatedWorldFrameCorrection?
    let quarantinedVersions: Set<Int>
}

struct WorldEpochController: Sendable {
    let worldFrameID: String
    private(set) var worldFrameVersion: Int
    private(set) var quarantinedVersions: Set<Int> = []

    init(worldFrameID: String, initialVersion: Int = 1) {
        self.worldFrameID = worldFrameID
        self.worldFrameVersion = initialVersion
    }

    var snapshot: WorldEpochSnapshot {
        WorldEpochSnapshot(
            worldFrameID: worldFrameID,
            worldFrameVersion: worldFrameVersion,
            isQuarantined: quarantinedVersions.contains(worldFrameVersion)
        )
    }

    mutating func advance(
        reason: WorldEpochChangeReason,
        correctionEvidence: WorldFrameCorrectionEvidence
    ) -> WorldEpochTransition {
        _ = reason
        _ = correctionEvidence
        return WorldEpochTransition(
            previousVersion: worldFrameVersion,
            currentVersion: worldFrameVersion,
            correction: nil,
            quarantinedVersions: quarantinedVersions
        )
    }
}
