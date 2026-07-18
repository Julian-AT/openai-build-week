import Foundation
import ReRoomContracts

/// The only local ingress channels admitted by the P0 deterministic intent boundary.
public enum IntentIngressSource: String, Codable, Equatable, Sendable {
    case typed
    case tap
    case voice
}

public enum IntentBoundaryRejection: String, Error, Equatable, Sendable {
    case emptyInput = "empty_input"
    case malformedJSON = "malformed_json"
    case oversized
    case invalidValue = "invalid_value"
    case unknownOrForbiddenField = "unknown_or_forbidden_field"
    case invalidConstraintOrder = "invalid_constraint_order"
    case staleContext = "stale_context"
    case voiceUnavailable = "voice_unavailable"
}

/// Context captured from trusted native state. Untrusted intent bytes never populate these fields.
public struct TrustedIntentContext: Codable, Equatable, Sendable {
    public let sessionID: String
    public let revisionAuthority: RevisionAuthority
    public let baseSceneRevision: UInt64
    public let targetContext: TargetContext

    public init(
        sessionID: String,
        revisionAuthority: RevisionAuthority,
        baseSceneRevision: UInt64,
        targetContext: TargetContext
    ) {
        self.sessionID = sessionID
        self.revisionAuthority = revisionAuthority
        self.baseSceneRevision = baseSceneRevision
        self.targetContext = targetContext
    }
}

/// A parsed semantic intent bound to the trusted session, authority, revision, and target snapshot.
public struct BoundProposal: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let sessionID: String
    public let revisionAuthority: RevisionAuthority
    public let baseSceneRevision: UInt64
    public let targetContext: TargetContext
    public let intent: TransactionIntent

    public init(
        schemaVersion: String = "1.0.0",
        sessionID: String,
        revisionAuthority: RevisionAuthority,
        baseSceneRevision: UInt64,
        targetContext: TargetContext,
        intent: TransactionIntent
    ) {
        self.schemaVersion = schemaVersion
        self.sessionID = sessionID
        self.revisionAuthority = revisionAuthority
        self.baseSceneRevision = baseSceneRevision
        self.targetContext = targetContext
        self.intent = intent
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case sessionID = "session_id"
        case revisionAuthority = "revision_authority"
        case baseSceneRevision = "base_scene_revision"
        case targetContext = "target_context"
        case intent
    }
}

public enum IntentBoundary {
    public static let maximumIntentBytes = 4_096
    private static let maximumIntentDepth = 8
    private static let maximumConstraints = 8

    /// Parses only the allowlisted semantic envelope, then attaches trusted native context.
    /// This function is synchronous and has no persistence, network, model, or revision side effects.
    public static func submitUserIntent(
        _ bytes: Data,
        source: IntentIngressSource,
        trustedContext: TrustedIntentContext,
        currentScene: SceneState
    ) throws -> BoundProposal {
        guard source != .voice else { throw IntentBoundaryRejection.voiceUnavailable }
        guard !bytes.isEmpty else { throw IntentBoundaryRejection.emptyInput }
        guard bytes.count <= maximumIntentBytes else { throw IntentBoundaryRejection.oversized }

        let canonical: Data
        do {
            canonical = try CanonicalJSON.canonicalize(
                jsonData: bytes,
                maximumBytes: maximumIntentBytes,
                maximumDepth: maximumIntentDepth
            )
        } catch {
            throw IntentBoundaryRejection.malformedJSON
        }

        let object: [String: Any]
        do {
            guard let decoded = try JSONSerialization.jsonObject(with: canonical) as? [String: Any] else {
                throw IntentBoundaryRejection.malformedJSON
            }
            object = decoded
        } catch let rejection as IntentBoundaryRejection {
            throw rejection
        } catch {
            throw IntentBoundaryRejection.malformedJSON
        }
        try validateShape(object)

        let input: UserIntentInput
        do {
            input = try JSONDecoder().decode(UserIntentInput.self, from: canonical)
        } catch {
            throw IntentBoundaryRejection.invalidValue
        }
        try validateSemantics(input)
        try validateContext(trustedContext, against: currentScene)

        return BoundProposal(
            sessionID: trustedContext.sessionID,
            revisionAuthority: trustedContext.revisionAuthority,
            baseSceneRevision: trustedContext.baseSceneRevision,
            targetContext: trustedContext.targetContext,
            intent: TransactionIntent(
                contractOperation: input.operation,
                source: source.rawValue,
                arguments: input.arguments,
                constraints: input.constraints
            )
        )
    }

    private static func validateShape(_ object: [String: Any]) throws {
        guard Set(object.keys) == ["operation", "arguments", "constraints"] else {
            throw IntentBoundaryRejection.unknownOrForbiddenField
        }
        guard let arguments = object["arguments"] as? [String: Any],
              Set(arguments.keys).isSubset(of: ["asset_id", "catalog_query"]),
              let constraints = object["constraints"] as? [[String: Any]]
        else {
            throw IntentBoundaryRejection.invalidValue
        }
        guard constraints.allSatisfy({ Set($0.keys) == ["kind", "value"] }) else {
            throw IntentBoundaryRejection.unknownOrForbiddenField
        }
    }

    private static func validateSemantics(_ input: UserIntentInput) throws {
        guard input.constraints.count <= maximumConstraints else {
            throw IntentBoundaryRejection.invalidValue
        }

        switch input.operation {
        case .place, .replace:
            let hasAsset = input.arguments.assetID != nil
            let hasQuery = input.arguments.catalogQuery != nil
            guard hasAsset != hasQuery else { throw IntentBoundaryRejection.invalidValue }
        case .remove, .restore:
            guard input.arguments.assetID == nil, input.arguments.catalogQuery == nil else {
                throw IntentBoundaryRejection.invalidValue
            }
        }

        if let assetID = input.arguments.assetID, !isStableAssetID(assetID) {
            throw IntentBoundaryRejection.invalidValue
        }
        if let query = input.arguments.catalogQuery {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()
            guard !trimmed.isEmpty,
                  trimmed.count <= 128,
                  trimmed == query,
                  !lower.contains("://"),
                  !lower.hasPrefix("www.")
            else { throw IntentBoundaryRejection.invalidValue }
        }

        var stableKeys = [String]()
        for constraint in input.constraints {
            try validateConstraint(constraint)
            stableKeys.append(try constraintStableKey(constraint))
        }
        guard stableKeys == stableKeys.sorted(), Set(stableKeys).count == stableKeys.count else {
            throw IntentBoundaryRejection.invalidConstraintOrder
        }
    }

    private static func validateConstraint(_ constraint: TypedConstraint) throws {
        switch (constraint.kind, constraint.value) {
        case ("color_tag", .string(let value)), ("style_tag", .string(let value)):
            guard !value.isEmpty, value.count <= 64 else { throw IntentBoundaryRejection.invalidValue }
        case ("support_required", .boolean), ("preserve_walkway", .boolean):
            break
        case ("max_footprint_m2", .number(let value)):
            guard value.isFinite, value > 0, value <= 20 else { throw IntentBoundaryRejection.invalidValue }
        default:
            throw IntentBoundaryRejection.invalidValue
        }
    }

    private static func constraintStableKey(_ constraint: TypedConstraint) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let value = try CanonicalJSON.canonicalize(jsonData: encoder.encode(constraint))
        return constraint.kind + "\u{0000}" + String(decoding: value, as: UTF8.self)
    }

    private static func validateContext(_ context: TrustedIntentContext, against scene: SceneState) throws {
        guard context.sessionID == scene.sessionID,
              context.revisionAuthority == scene.revisionAuthority,
              context.revisionAuthority.kind == .nativeDevice,
              context.baseSceneRevision == scene.sceneRevision,
              context.targetContext.capturedSceneRevision == scene.sceneRevision,
              context.targetContext.worldFrameID == scene.worldFrame.worldFrameID,
              context.targetContext.worldFrameVersion == scene.worldFrame.worldFrameVersion
        else { throw IntentBoundaryRejection.staleContext }
    }

    private static func isStableAssetID(_ value: String) -> Bool {
        guard value.hasPrefix("asset_"), value.count > "asset_".count else { return false }
        return value.dropFirst("asset_".count).allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_")
        }
    }
}

private struct UserIntentInput: Codable, Sendable {
    let operation: ProductOperation
    let arguments: IntentArguments
    let constraints: [TypedConstraint]
}
