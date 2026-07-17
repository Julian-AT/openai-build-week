import Darwin
import Foundation
import ReRoomContracts

enum EvidenceEnvironmentFactValue: Equatable, Sendable {
    case string(String)
    case boolean(Bool)
}

struct EvidenceFixtureReference: Equatable, Sendable {
    let fixtureID: String
    let fixtureRevision: String
    let sha256: String
}

struct EvidenceArtifactReference: Equatable, Sendable {
    let opaqueArtifactID: String
    let artifactKind: String
    let sha256: String
}

struct EvidenceExportRequest: Equatable, Sendable {
    var gateID: String
    var gateState: String
    var recordedAtUTC: String
    var implementationRevision: String
    var testIDs: [String]
    var requirementIDs: [String]
    var adrIDs: [String]
    var fixtureReferences: [EvidenceFixtureReference]
    var environmentFacts: [String: EvidenceEnvironmentFactValue]
    var valueClassification: String
    var evidenceArtifacts: [EvidenceArtifactReference]
    var automatedReportSHA256: String?
}

struct ExportedEvidence: Equatable, Sendable {
    let url: URL
    let data: Data
    let sha256: String
}

enum EvidenceExportRejection: Error, Equatable, Sendable {
    case forbiddenField(String)
    case invalidGateState(String)
    case invalidCapability(String)
    case unboundEvidence
    case invalidSchema
    case invalidDestination
    case persistenceFailure
}

struct EvidenceExporter {
    private static let maximumEvidenceBytes = 1_048_576

    func validatedData(for request: EvidenceExportRequest) throws -> Data {
        let sanitized = try GateReportSanitizer.sanitize(request)
        let encoded = try JSONSerialization.data(withJSONObject: sanitized, options: [.sortedKeys])
        let canonical = try CanonicalJSON.canonicalize(
            jsonData: encoded,
            maximumBytes: Self.maximumEvidenceBytes
        )
        guard canonical.count <= Self.maximumEvidenceBytes,
              GateReportV1Validator.validate(canonical)
        else {
            throw EvidenceExportRejection.invalidSchema
        }
        return canonical
    }

    func export(_ request: EvidenceExportRequest, to destination: URL) throws -> ExportedEvidence {
        // Validation intentionally happens before the destination directory or a
        // temporary file is created.
        let data = try validatedData(for: request)
        guard destination.isFileURL, destination.lastPathComponent.isEmpty == false else {
            throw EvidenceExportRejection.invalidDestination
        }

        let directory = destination.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(
            ".\(destination.lastPathComponent).\(UUID().uuidString.lowercased()).tmp"
        )
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try data.write(to: temporary)
            let handle = try FileHandle(forWritingTo: temporary)
            try handle.synchronize()
            try handle.close()

            let renameResult = temporary.path.withCString { source in
                destination.path.withCString { target in
                    Darwin.rename(source, target)
                }
            }
            guard renameResult == 0 else {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }
            let descriptor = Darwin.open(directory.path, O_RDONLY)
            guard descriptor >= 0 else {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }
            defer { Darwin.close(descriptor) }
            guard Darwin.fsync(descriptor) == 0 else {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            if let rejection = error as? EvidenceExportRejection {
                throw rejection
            }
            throw EvidenceExportRejection.persistenceFailure
        }

        return ExportedEvidence(
            url: destination,
            data: data,
            sha256: CanonicalJSON.sha256Hex(data)
        )
    }
}

private enum GateReportSanitizer {
    private static let environmentAllowlist: Set<String> = [
        "device_model", "os_version", "xcode_version", "runtime_tier",
        "camera_permission", "arkit_world_tracking", "plane_detection",
        "lidar_required", "signing_result",
    ]
    private static let requiredEnvironmentFacts: Set<String> = [
        "runtime_tier", "camera_permission", "arkit_world_tracking", "plane_detection",
        "lidar_required", "signing_result",
    ]
    private static let capabilityValues: [String: Set<String>] = [
        "camera_permission": ["not_tested", "granted", "denied", "not_applicable"],
        "arkit_world_tracking": ["not_tested", "pass", "fail", "not_applicable"],
        "plane_detection": ["not_tested", "pass", "fail", "not_applicable"],
        "signing_result": ["not_tested", "pass", "fail", "not_applicable"],
    ]
    private static let artifactKinds: Set<String> = [
        "automated_report", "log", "trace", "screenshot", "video", "metric_output",
        "ballot",
    ]

    static func sanitize(_ request: EvidenceExportRequest) throws -> [String: Any] {
        for field in request.environmentFacts.keys where environmentAllowlist.contains(field) == false {
            throw EvidenceExportRejection.forbiddenField(field)
        }
        guard requiredEnvironmentFacts.isSubset(of: request.environmentFacts.keys) else {
            throw EvidenceExportRejection.invalidSchema
        }
        guard ["UNRUN", "RUNNING", "RED"].contains(request.gateState) else {
            throw EvidenceExportRejection.invalidGateState(request.gateState)
        }
        for (field, allowed) in capabilityValues {
            guard case let .string(value)? = request.environmentFacts[field],
                  allowed.contains(value)
            else {
                throw EvidenceExportRejection.invalidCapability(field)
            }
        }
        guard case .boolean(false)? = request.environmentFacts["lidar_required"] else {
            throw EvidenceExportRejection.invalidCapability("lidar_required")
        }

        switch request.gateState {
        case "UNRUN":
            guard request.evidenceArtifacts.isEmpty,
                  request.automatedReportSHA256 == nil
            else { throw EvidenceExportRejection.unboundEvidence }
        case "RUNNING":
            guard request.automatedReportSHA256 == nil else {
                throw EvidenceExportRejection.unboundEvidence
            }
        case "RED":
            guard request.evidenceArtifacts.isEmpty == false,
                  request.automatedReportSHA256 != nil
            else { throw EvidenceExportRejection.unboundEvidence }
        default:
            throw EvidenceExportRejection.invalidGateState(request.gateState)
        }

        let environment: [String: Any] = [
            "device_model": try optionalSafeFact("device_model", request.environmentFacts),
            "os_version": try optionalSafeFact("os_version", request.environmentFacts),
            "xcode_version": try optionalSafeFact("xcode_version", request.environmentFacts),
            "runtime_tier": try requiredSafeFact("runtime_tier", request.environmentFacts),
            "capability_flags": [
                "camera_permission": try requiredString("camera_permission", request.environmentFacts),
                "arkit_world_tracking": try requiredString("arkit_world_tracking", request.environmentFacts),
                "plane_detection": try requiredString("plane_detection", request.environmentFacts),
                "lidar_required": false,
            ],
            "signing_result": try requiredString("signing_result", request.environmentFacts),
        ]

        return [
            "schema_version": "1.0.0",
            "gate_id": request.gateID,
            "gate_state": request.gateState,
            "decision_actor": "automation",
            "recorded_at_utc": request.recordedAtUTC,
            "implementation_revision": request.implementationRevision,
            "test_ids": try uniqueSorted(request.testIDs),
            "requirement_ids": try uniqueSorted(request.requirementIDs),
            "adr_ids": try uniqueSorted(request.adrIDs),
            "fixture_refs": try sanitizedFixtures(request.fixtureReferences),
            "environment": environment,
            "value_classification": request.valueClassification,
            "evidence_artifacts": try sanitizedArtifacts(request.evidenceArtifacts),
            "automated_report_sha256": request.automatedReportSHA256 ?? NSNull(),
            "operator_checklist_sha256": NSNull(),
            "locked_decision_change_id": NSNull(),
            "prd_sha256": NSNull(),
            "affected_adr_sha256": [],
        ]
    }

    private static func optionalSafeFact(
        _ key: String,
        _ facts: [String: EvidenceEnvironmentFactValue]
    ) throws -> Any {
        guard let value = facts[key] else { return NSNull() }
        guard case let .string(text) = value, isSafeEnvironmentText(text) else {
            throw EvidenceExportRejection.forbiddenField(key)
        }
        return text
    }

    private static func requiredSafeFact(
        _ key: String,
        _ facts: [String: EvidenceEnvironmentFactValue]
    ) throws -> String {
        let text = try requiredString(key, facts)
        guard isSafeEnvironmentText(text) else {
            throw EvidenceExportRejection.forbiddenField(key)
        }
        return text
    }

    private static func requiredString(
        _ key: String,
        _ facts: [String: EvidenceEnvironmentFactValue]
    ) throws -> String {
        guard case let .string(text)? = facts[key] else {
            throw EvidenceExportRejection.invalidCapability(key)
        }
        return text
    }

    private static func isSafeEnvironmentText(_ text: String) -> Bool {
        guard matches(text, #"^[A-Za-z0-9][A-Za-z0-9 ._+():-]{0,127}$"#),
              matches(text, #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}"#) == false
        else {
            return false
        }
        let lowered = text.lowercased()
        return lowered.contains("team id") == false
            && lowered.contains("account") == false
            && lowered.contains("private key") == false
    }

    private static func uniqueSorted(_ values: [String]) throws -> [String] {
        guard values.isEmpty == false, Set(values).count == values.count else {
            throw EvidenceExportRejection.invalidSchema
        }
        return values.sorted()
    }

    private static func sanitizedFixtures(
        _ fixtures: [EvidenceFixtureReference]
    ) throws -> [[String: Any]] {
        guard fixtures.isEmpty == false,
              Set(fixtures.map { "\($0.fixtureID)|\($0.fixtureRevision)|\($0.sha256)" }).count
                == fixtures.count
        else {
            throw EvidenceExportRejection.invalidSchema
        }
        return fixtures.sorted {
            ($0.fixtureID, $0.fixtureRevision) < ($1.fixtureID, $1.fixtureRevision)
        }.map {
            [
                "fixture_id": $0.fixtureID,
                "fixture_revision": $0.fixtureRevision,
                "sha256": $0.sha256,
            ]
        }
    }

    private static func sanitizedArtifacts(
        _ artifacts: [EvidenceArtifactReference]
    ) throws -> [[String: Any]] {
        guard Set(artifacts.map(\.opaqueArtifactID)).count == artifacts.count else {
            throw EvidenceExportRejection.invalidSchema
        }
        return try artifacts.sorted { $0.opaqueArtifactID < $1.opaqueArtifactID }.map {
            guard matches($0.opaqueArtifactID, #"^opaque-[a-z0-9][a-z0-9._-]{7,95}$"#),
                  artifactKinds.contains($0.artifactKind),
                  matches($0.sha256, #"^[0-9a-f]{64}$"#)
            else {
                throw EvidenceExportRejection.invalidSchema
            }
            return [
                "opaque_artifact_id": $0.opaqueArtifactID,
                "artifact_kind": $0.artifactKind,
                "sha256": $0.sha256,
                "external_retention": true,
            ]
        }
    }

    fileprivate static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }
}

private enum GateReportV1Validator {
    private static let keys: Set<String> = [
        "schema_version", "gate_id", "gate_state", "decision_actor", "recorded_at_utc",
        "implementation_revision", "test_ids", "requirement_ids", "adr_ids",
        "fixture_refs", "environment", "value_classification", "evidence_artifacts",
        "automated_report_sha256", "operator_checklist_sha256",
        "locked_decision_change_id", "prd_sha256", "affected_adr_sha256",
    ]
    private static let environmentKeys: Set<String> = [
        "device_model", "os_version", "xcode_version", "runtime_tier", "capability_flags",
        "signing_result",
    ]
    private static let capabilityKeys: Set<String> = [
        "camera_permission", "arkit_world_tracking", "plane_detection", "lidar_required",
    ]

    static func validate(_ data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(root.keys) == keys,
              root["schema_version"] as? String == "1.0.0",
              root["decision_actor"] as? String == "automation",
              let gateID = root["gate_id"] as? String,
              GateReportSanitizer.matches(gateID, #"^GATE-[0-9]{3}$"#),
              let state = root["gate_state"] as? String,
              ["UNRUN", "RUNNING", "RED"].contains(state),
              let recordedAt = root["recorded_at_utc"] as? String,
              GateReportSanitizer.matches(recordedAt, #"^[0-9]{4}-(?:0[1-9]|1[0-2])-(?:0[1-9]|[12][0-9]|3[01])T(?:[01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]Z$"#),
              let revision = root["implementation_revision"] as? String,
              GateReportSanitizer.matches(revision, #"^git:[0-9a-f]{40}$"#),
              let tests = root["test_ids"] as? [String],
              tests.isEmpty == false, tests.count <= 64, Set(tests).count == tests.count,
              tests.allSatisfy({ GateReportSanitizer.matches($0, #"^TST-[A-Z0-9]+-[0-9]{3}$"#) }),
              let requirements = root["requirement_ids"] as? [String],
              requirements.isEmpty == false, requirements.count <= 64,
              Set(requirements).count == requirements.count,
              requirements.allSatisfy({ GateReportSanitizer.matches($0, #"^(?:FR|NFR|SEC|OPS|STR)-[A-Z0-9]+-[0-9]{3}$"#) }),
              let adrs = root["adr_ids"] as? [String],
              adrs.isEmpty == false, adrs.count <= 32, Set(adrs).count == adrs.count,
              adrs.allSatisfy({ GateReportSanitizer.matches($0, #"^ADR-[0-9]{3}$"#) }),
              let fixtures = root["fixture_refs"] as? [[String: Any]],
              fixtures.isEmpty == false, fixtures.count <= 64,
              fixtures.allSatisfy(validFixture),
              let environment = root["environment"] as? [String: Any],
              validEnvironment(environment),
              let classification = root["value_classification"] as? String,
              ["TARGET", "MEASURED"].contains(classification),
              let artifacts = root["evidence_artifacts"] as? [[String: Any]],
              artifacts.count <= 128,
              artifacts.allSatisfy(validArtifact),
              root["operator_checklist_sha256"] is NSNull,
              root["locked_decision_change_id"] is NSNull,
              root["prd_sha256"] is NSNull,
              let affected = root["affected_adr_sha256"] as? [Any], affected.isEmpty
        else {
            return false
        }

        switch state {
        case "UNRUN":
            return artifacts.isEmpty && root["automated_report_sha256"] is NSNull
        case "RUNNING":
            return root["automated_report_sha256"] is NSNull
        case "RED":
            return artifacts.isEmpty == false && isSHA256(root["automated_report_sha256"])
        default:
            return false
        }
    }

    private static func validFixture(_ fixture: [String: Any]) -> Bool {
        Set(fixture.keys) == ["fixture_id", "fixture_revision", "sha256"]
            && GateReportSanitizer.matches(fixture["fixture_id"] as? String ?? "", #"^FX-[A-Z0-9]+(?:-[A-Z0-9]+)+$"#)
            && GateReportSanitizer.matches(fixture["fixture_revision"] as? String ?? "", #"^rev-[0-9]{3}$"#)
            && isSHA256(fixture["sha256"])
    }

    private static func validEnvironment(_ environment: [String: Any]) -> Bool {
        guard Set(environment.keys) == environmentKeys,
              let flags = environment["capability_flags"] as? [String: Any],
              Set(flags.keys) == capabilityKeys,
              flags["lidar_required"] as? Bool == false,
              ["not_tested", "granted", "denied", "not_applicable"]
                .contains(flags["camera_permission"] as? String ?? ""),
              ["not_tested", "pass", "fail", "not_applicable"]
                .contains(flags["arkit_world_tracking"] as? String ?? ""),
              ["not_tested", "pass", "fail", "not_applicable"]
                .contains(flags["plane_detection"] as? String ?? ""),
              ["not_tested", "pass", "fail", "not_applicable"]
                .contains(environment["signing_result"] as? String ?? ""),
              safeLabel(environment["runtime_tier"])
        else {
            return false
        }
        return optionalSafeLabel(environment["device_model"])
            && optionalSafeLabel(environment["os_version"])
            && optionalSafeLabel(environment["xcode_version"])
    }

    private static func validArtifact(_ artifact: [String: Any]) -> Bool {
        Set(artifact.keys) == [
            "opaque_artifact_id", "artifact_kind", "sha256", "external_retention",
        ]
            && GateReportSanitizer.matches(artifact["opaque_artifact_id"] as? String ?? "", #"^opaque-[a-z0-9][a-z0-9._-]{7,95}$"#)
            && ["automated_report", "log", "trace", "screenshot", "video", "metric_output", "ballot"]
                .contains(artifact["artifact_kind"] as? String ?? "")
            && isSHA256(artifact["sha256"])
            && artifact["external_retention"] as? Bool == true
    }

    private static func optionalSafeLabel(_ value: Any?) -> Bool {
        value is NSNull || safeLabel(value)
    }

    private static func safeLabel(_ value: Any?) -> Bool {
        guard let string = value as? String else { return false }
        return GateReportSanitizer.matches(string, #"^[A-Za-z0-9][A-Za-z0-9 ._+():-]{0,127}$"#)
    }

    private static func isSHA256(_ value: Any?) -> Bool {
        GateReportSanitizer.matches(value as? String ?? "", #"^[0-9a-f]{64}$"#)
    }
}
