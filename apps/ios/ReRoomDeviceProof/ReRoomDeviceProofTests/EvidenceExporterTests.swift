import Foundation
import ReRoomContracts
import Testing
@testable import ReRoomDeviceProof

@Suite("Sanitized evidence export")
struct EvidenceExporterTests {
    private let shaA = String(repeating: "a", count: 64)

    @Test(
        "Automation emits only deterministic UNRUN, RUNNING, and RED reports",
        arguments: ["UNRUN", "RUNNING", "RED"]
    )
    func allowedAutomationStatesAreDeterministic(state: String) throws {
        let exporter = EvidenceExporter()
        let request = request(state: state)

        let first = try exporter.validatedData(for: request)
        let second = try exporter.validatedData(for: request)
        let object = try #require(
            JSONSerialization.jsonObject(with: first) as? [String: Any]
        )

        #expect(first == second)
        #expect(object["schema_version"] as? String == "2.0.0")
        #expect(object["gate_state"] as? String == state)
        #expect(object["decision_actor"] as? String == "automation")
        #expect(Set(object.keys) == Self.gateReportKeys)
        #expect(object["operator_checklist_sha256"] is NSNull)
        #expect(object["locked_decision_change_id"] is NSNull)
        #expect(object["prd_sha256"] is NSNull)

        let artifacts = try #require(object["evidence_artifacts"] as? [[String: Any]])
        #expect(artifacts.allSatisfy { artifact in
            artifact["artifact_role"] as? String == "supporting_evidence"
        })
    }

    @Test(
        "Closed environment allowlist rejects every private source field",
        arguments: [
            "device_uuid", "team_id", "account", "user_path", "raw_room_bytes",
            "raw_logs", "signing_material",
        ]
    )
    func privateFieldsRejectBeforeSerialization(field: String) {
        var candidate = request(state: "UNRUN")
        candidate.environmentFacts[field] = .string("private")

        #expect(throws: EvidenceExportRejection.forbiddenField(field)) {
            try EvidenceExporter().validatedData(for: candidate)
        }
    }

    @Test("Non-iPhone device labels cannot escape the canonical V2 boundary")
    func nonIPhoneDeviceModelRejects() {
        var candidate = request(state: "UNRUN")
        candidate.environmentFacts["device_model"] = .string("MacBook Pro")

        #expect(throws: EvidenceExportRejection.forbiddenField("device_model")) {
            try EvidenceExporter().validatedData(for: candidate)
        }
    }

    @Test(
        "Unknown and human-only states cannot be exported by automation",
        arguments: ["PASS", "GREEN", "WAIVED_BY_HUMAN"]
    )
    func rejectedGateStates(state: String) {
        let candidate = request(state: state)

        #expect(throws: EvidenceExportRejection.invalidGateState(state)) {
            try EvidenceExporter().validatedData(for: candidate)
        }
    }

    @Test("Unknown capability values and LiDAR requirements fail closed")
    func invalidCapabilityFactsReject() {
        var unknown = request(state: "UNRUN")
        unknown.environmentFacts["camera_permission"] = .string("allowed")
        #expect(throws: EvidenceExportRejection.invalidCapability("camera_permission")) {
            try EvidenceExporter().validatedData(for: unknown)
        }

        var lidar = request(state: "UNRUN")
        lidar.environmentFacts["lidar_required"] = .boolean(true)
        #expect(throws: EvidenceExportRejection.invalidCapability("lidar_required")) {
            try EvidenceExporter().validatedData(for: lidar)
        }
    }

    @Test("RED evidence must bind an opaque external artifact and automated report digest")
    func redRequiresBoundEvidence() {
        var missingArtifact = request(state: "RED")
        missingArtifact.evidenceArtifacts = []
        #expect(throws: EvidenceExportRejection.unboundEvidence) {
            try EvidenceExporter().validatedData(for: missingArtifact)
        }

        var missingDigest = request(state: "RED")
        missingDigest.automatedReportSHA256 = nil
        #expect(throws: EvidenceExportRejection.unboundEvidence) {
            try EvidenceExporter().validatedData(for: missingDigest)
        }
    }

    @Test("Automation rejects operator attestations before serialization")
    func operatorAttestationRoleRejects() {
        var candidate = request(state: "RUNNING")
        candidate.evidenceArtifacts = [
            EvidenceArtifactReference(
                opaqueArtifactID: "opaque-gate-013-attestation-0001",
                artifactKind: "ballot",
                artifactRole: "operator_attestation",
                sha256: shaA
            )
        ]

        #expect(throws: EvidenceExportRejection.invalidSchema) {
            try EvidenceExporter().validatedData(for: candidate)
        }
    }

    @Test("Actual Swift output conforms to the checked-in GateReportV2 schema")
    func actualOutputConformsToCanonicalSchema() throws {
        let schemaData = try Data(
            contentsOf: repositoryRoot().appendingPathComponent(
                "evidence/templates/gate-report.schema.json"
            )
        )
        let canonicalValidator = try JSONSchemaDocumentValidator(
            schemaID: "urn:reroom:evidence-schema:gate-report:2",
            documentSchemaVersion: "2.0.0",
            schemaData: schemaData
        )

        for state in ["UNRUN", "RUNNING", "RED"] {
            let emitted = try EvidenceExporter().validatedData(for: request(state: state))
            #expect(
                canonicalValidator.validate(documentData: emitted) == .accepted,
                Comment(rawValue: state)
            )
        }

        let emitted = try EvidenceExporter().validatedData(for: request(state: "RUNNING"))
        var missingRole = try #require(
            JSONSerialization.jsonObject(with: emitted) as? [String: Any]
        )
        var artifacts = try #require(missingRole["evidence_artifacts"] as? [[String: Any]])
        artifacts[0].removeValue(forKey: "artifact_role")
        missingRole["evidence_artifacts"] = artifacts
        let mutated = try JSONSerialization.data(
            withJSONObject: missingRole,
            options: [.sortedKeys]
        )
        #expect(canonicalValidator.validate(documentData: mutated) != .accepted)
    }

    @Test("Schema-invalid identifiers reject before any file is written")
    func invalidSchemaLeavesDestinationUntouched() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("gate-report.json")
        var invalid = request(state: "UNRUN")
        invalid.gateID = "gate-13"

        #expect(throws: EvidenceExportRejection.invalidSchema) {
            try EvidenceExporter().export(invalid, to: destination)
        }
        #expect(FileManager.default.fileExists(atPath: destination.path) == false)
        #expect(FileManager.default.fileExists(atPath: root.path) == false)
    }

    @Test("Validated report publishes atomically with no temporary tail")
    func validReportPublishesAtomically() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("gate-report.json")

        let result = try EvidenceExporter().export(request(state: "RUNNING"), to: destination)
        let persistedData = try Data(contentsOf: destination)
        let paths = try FileManager.default.contentsOfDirectory(atPath: root.path)

        #expect(result.url == destination)
        #expect(result.data == persistedData)
        #expect(result.sha256.count == 64)
        #expect(paths == ["gate-report.json"])
    }

    @Test("Checklist rows preserve the approved independent order")
    func checklistOrderIsStable() {
        #expect(DiagnosticChecklistRowID.allCases.map(\.rawValue) == [
            "debug.check.camera",
            "debug.check.microphone",
            "debug.check.orientation",
            "debug.check.tracking",
            "debug.check.planes.horizontal",
            "debug.check.planes.vertical",
            "debug.check.epoch",
            "debug.check.packet",
            "debug.check.journal",
            "debug.check.build",
            "debug.check.gate",
        ])
    }

    @Test("UNRUN evidence request derives safe capability facts from live owner state")
    func liveUnrunRequestUsesIndependentFacts() throws {
        let state = DeviceProofState(
            cameraAuthorization: .granted,
            microphoneAuthorization: .denied,
            physicalOrientation: .portrait,
            session: ARSessionEvidence(
                isRunning: true,
                trackingState: .normal,
                observedPlaneAlignments: [.horizontal]
            )
        )
        let runtime = DiagnosticRuntimeFacts(
            recordedAtUTC: "2026-07-17T01:15:00Z",
            implementationRevision: "git:0123456789abcdef0123456789abcdef01234567",
            fixtureSHA256: shaA,
            deviceModel: "iPhone 17",
            osVersion: "iOS 26.0",
            appVersion: "0.1.0"
        )

        let request = DiagnosticEvidenceRequestFactory.unrun(
            deviceState: state,
            runtime: runtime
        )
        let data = try EvidenceExporter().validatedData(for: request)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let environment = try #require(object["environment"] as? [String: Any])
        let capabilities = try #require(
            environment["capability_flags"] as? [String: Any]
        )

        #expect(object["gate_state"] as? String == "UNRUN")
        #expect(capabilities["camera_permission"] as? String == "granted")
        #expect(capabilities["arkit_world_tracking"] as? String == "pass")
        #expect(capabilities["plane_detection"] as? String == "pass")
        #expect(environment["signing_result"] as? String == "not_tested")
    }

    @MainActor
    @Test("Normal Debug launch uses bundled build provenance without environment injection")
    func liveRuntimeFactsValidateWithoutEnvironmentInjection() throws {
        let runtime = DiagnosticRuntimeFacts.live(
            environment: [:],
            date: Date(timeIntervalSince1970: 1_768_608_900)
        )
        let request = DiagnosticEvidenceRequestFactory.unrun(
            deviceState: DeviceProofState(),
            runtime: runtime
        )
        let data = try EvidenceExporter().validatedData(for: request)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let environment = try #require(object["environment"] as? [String: Any])
        let revision = try #require(object["implementation_revision"] as? String)
        let fixtures = try #require(object["fixture_refs"] as? [[String: Any]])
        let fixture = try #require(fixtures.first)

        #expect(
            revision.range(
                of: #"^git:[0-9a-f]{40}$"#,
                options: .regularExpression
            ) != nil
        )
        #expect(fixture["fixture_id"] as? String == "FX-CONTRACT-001")
        #expect(
            fixture["sha256"] as? String
                == "54a0753df4c6a963136a59ed1361dc0c4460c59647ab202c0b7c8e565b79194c"
        )
        #expect(environment["device_model"] is NSNull)
    }

    @Test("Shared LaunchAction contains no provenance environment overrides")
    func sharedLaunchActionIsUnmodified() throws {
        let root = try repositoryRoot()
        let scheme = try String(
            contentsOf: root.appendingPathComponent(
                "apps/ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj/xcshareddata/xcschemes/ReRoomDeviceProof.xcscheme"
            ),
            encoding: .utf8
        )
        let start = try #require(scheme.range(of: "<LaunchAction"))
        let end = try #require(
            scheme.range(of: "</LaunchAction>", range: start.lowerBound..<scheme.endIndex)
        )
        let launchAction = scheme[start.lowerBound..<end.upperBound]

        #expect(launchAction.contains("REROOM_IMPLEMENTATION_REVISION") == false)
        #expect(launchAction.contains("REROOM_FIXTURE_SHA256") == false)
        #expect(launchAction.contains("EnvironmentVariables") == false)
    }

    private func request(state: String) -> EvidenceExportRequest {
        let artifacts: [EvidenceArtifactReference]
        let reportDigest: String?
        switch state {
        case "RUNNING":
            artifacts = [artifact]
            reportDigest = nil
        case "RED":
            artifacts = [artifact]
            reportDigest = shaA
        default:
            artifacts = []
            reportDigest = nil
        }
        return EvidenceExportRequest(
            gateID: "GATE-013",
            gateState: state,
            recordedAtUTC: "2026-07-17T01:15:00Z",
            implementationRevision: "git:0123456789abcdef0123456789abcdef01234567",
            testIDs: ["TST-DEVICE-001"],
            requirementIDs: ["OPS-DEVICE-001"],
            adrIDs: ["ADR-002", "ADR-003"],
            fixtureReferences: [
                EvidenceFixtureReference(
                    fixtureID: "FX-RRCAP-010S",
                    fixtureRevision: "rev-001",
                    sha256: shaA
                )
            ],
            environmentFacts: [
                "device_model": .string("iPhone 17"),
                "os_version": .string("iOS 26.0"),
                "xcode_version": .string("Xcode 26.4"),
                "runtime_tier": .string("base-iphone-candidate"),
                "camera_permission": .string("not_tested"),
                "arkit_world_tracking": .string("not_tested"),
                "plane_detection": .string("not_tested"),
                "lidar_required": .boolean(false),
                "signing_result": .string("not_tested"),
            ],
            valueClassification: "TARGET",
            evidenceArtifacts: artifacts,
            automatedReportSHA256: reportDigest
        )
    }

    private var artifact: EvidenceArtifactReference {
        EvidenceArtifactReference(
            opaqueArtifactID: "opaque-gate-013-run-0001",
            artifactKind: "automated_report",
            artifactRole: "supporting_evidence",
            sha256: shaA
        )
    }

    private func repositoryRoot() throws -> URL {
        let fileManager = FileManager.default
        var cursor = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while fileManager.fileExists(atPath: cursor.appendingPathComponent(".git").path) == false {
            let parent = cursor.deletingLastPathComponent()
            guard parent.path != cursor.path else {
                throw EvidenceExporterTestError.repositoryRootNotFound
            }
            cursor = parent
        }
        return cursor
    }

    private static let gateReportKeys: Set<String> = [
        "schema_version", "gate_id", "gate_state", "decision_actor", "recorded_at_utc",
        "implementation_revision", "test_ids", "requirement_ids", "adr_ids",
        "fixture_refs", "environment", "value_classification", "evidence_artifacts",
        "automated_report_sha256", "operator_checklist_sha256",
        "locked_decision_change_id", "prd_sha256", "affected_adr_sha256",
    ]
}

private enum EvidenceExporterTestError: Error {
    case repositoryRootNotFound
}
