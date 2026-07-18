import Foundation
import ReRoomContracts

/// The complete and exclusive RR-JCS request fingerprint scope.
public struct TransactionFingerprintScope: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let sessionID: String
    public let revisionAuthority: RevisionAuthority
    public let baseSceneRevision: UInt64
    public let targetContext: TargetContext
    public let intent: TransactionIntent
    public let proposedOperations: [TransactionOperation]

    public init(
        schemaVersion: String,
        sessionID: String,
        revisionAuthority: RevisionAuthority,
        baseSceneRevision: UInt64,
        targetContext: TargetContext,
        intent: TransactionIntent,
        proposedOperations: [TransactionOperation]
    ) {
        self.schemaVersion = schemaVersion
        self.sessionID = sessionID
        self.revisionAuthority = revisionAuthority
        self.baseSceneRevision = baseSceneRevision
        self.targetContext = targetContext
        self.intent = intent
        self.proposedOperations = proposedOperations
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case sessionID = "session_id"
        case revisionAuthority = "revision_authority"
        case baseSceneRevision = "base_scene_revision"
        case targetContext = "target_context"
        case intent
        case proposedOperations = "proposed_operations"
    }
}

public enum TransactionFingerprint {
    public static func canonicalData(_ scope: TransactionFingerprintScope) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let encoded = try encoder.encode(scope)
        let canonical = try CanonicalJSON.canonicalize(jsonData: encoded)

        // Keep the public typed scope and its wire representation locked together.
        let roundTrip = try JSONDecoder().decode(TransactionFingerprintScope.self, from: canonical)
        guard roundTrip == scope else { throw TransactionFingerprintRejection.roundTripMismatch }
        return canonical
    }

    public static func digest(_ scope: TransactionFingerprintScope) throws -> String {
        CanonicalJSON.sha256Hex(try canonicalData(scope))
    }

    public static func digest(
        proposal: BoundProposal,
        proposedOperations: [TransactionOperation]
    ) throws -> String {
        try digest(TransactionFingerprintScope(
            schemaVersion: proposal.schemaVersion,
            sessionID: proposal.sessionID,
            revisionAuthority: proposal.revisionAuthority,
            baseSceneRevision: proposal.baseSceneRevision,
            targetContext: proposal.targetContext,
            intent: proposal.intent,
            proposedOperations: proposedOperations
        ))
    }

    public static func digest(_ transaction: TransactionRecord) throws -> String {
        try digest(TransactionFingerprintScope(
            schemaVersion: transaction.schemaVersion,
            sessionID: transaction.sessionID,
            revisionAuthority: transaction.revisionAuthority,
            baseSceneRevision: transaction.baseSceneRevision,
            targetContext: transaction.targetContext,
            intent: transaction.intent,
            proposedOperations: transaction.proposedOperations
        ))
    }
}

public enum TransactionFingerprintRejection: String, Error, Equatable, Sendable {
    case roundTripMismatch = "round_trip_mismatch"
}
