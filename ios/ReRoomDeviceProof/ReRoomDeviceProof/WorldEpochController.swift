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
        let previousVersion = worldFrameVersion
        worldFrameVersion += 1
        let currentVersion = worldFrameVersion
        quarantinedVersions.formUnion([previousVersion, currentVersion])

        let correction = validatedCorrection(
            evidence: correctionEvidence,
            reason: reason,
            expectedBaseVersion: previousVersion,
            expectedTargetVersion: currentVersion
        )
        if correction != nil {
            quarantinedVersions.remove(previousVersion)
            quarantinedVersions.remove(currentVersion)
        }

        return WorldEpochTransition(
            previousVersion: previousVersion,
            currentVersion: currentVersion,
            correction: correction,
            quarantinedVersions: quarantinedVersions
        )
    }

    private func validatedCorrection(
        evidence: WorldFrameCorrectionEvidence,
        reason: WorldEpochChangeReason,
        expectedBaseVersion: Int,
        expectedTargetVersion: Int
    ) -> ValidatedWorldFrameCorrection? {
        guard case .candidate(let candidate) = evidence,
              candidate.baseWorldFrameVersion == expectedBaseVersion,
              candidate.targetWorldFrameVersion == expectedTargetVersion,
              candidate.targetWorldFrameVersion > candidate.baseWorldFrameVersion,
              let transform = try? RRCoordinateMath.validateRigidTransform(
                  candidate.targetFromBaseTransform
              )
        else {
            return nil
        }

        return ValidatedWorldFrameCorrection(
            baseWorldFrameVersion: candidate.baseWorldFrameVersion,
            targetWorldFrameVersion: candidate.targetWorldFrameVersion,
            targetFromBaseTransform: transform,
            reason: reason
        )
    }
}
