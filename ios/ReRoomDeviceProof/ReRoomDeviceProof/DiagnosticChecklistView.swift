import Observation
import ReRoomContracts
import SwiftUI
import UIKit

enum DiagnosticChecklistRowID: String, CaseIterable, Identifiable, Sendable {
    case camera = "debug.check.camera"
    case microphone = "debug.check.microphone"
    case orientation = "debug.check.orientation"
    case tracking = "debug.check.tracking"
    case horizontalPlanes = "debug.check.planes.horizontal"
    case verticalPlanes = "debug.check.planes.vertical"
    case epoch = "debug.check.epoch"
    case packet = "debug.check.packet"
    case journal = "debug.check.journal"
    case build = "debug.check.build"
    case gate = "debug.check.gate"

    var id: String { rawValue }
}

enum DiagnosticFactState: Equatable, Sendable {
    case ready
    case pending
    case warning
    case failed

    var symbolName: String {
        switch self {
        case .ready: "checkmark.circle.fill"
        case .pending: "clock.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .ready: Color(red: 48 / 255, green: 209 / 255, blue: 88 / 255)
        case .pending: Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255)
        case .warning: Color(red: 255 / 255, green: 214 / 255, blue: 10 / 255)
        case .failed: Color(red: 255 / 255, green: 69 / 255, blue: 58 / 255)
        }
    }
}

struct DiagnosticChecklistFact: Identifiable, Equatable, Sendable {
    let id: DiagnosticChecklistRowID
    let label: String
    let value: String
    let reason: String?
    let state: DiagnosticFactState
}

struct DiagnosticChecklistSnapshot: Equatable, Sendable {
    let rows: [DiagnosticChecklistFact]

    init(
        deviceState: DeviceProofState,
        epochValue: String,
        epochState: DiagnosticFactState,
        packetValue: String,
        packetState: DiagnosticFactState,
        journalValue: String,
        journalState: DiagnosticFactState,
        buildValue: String,
        buildState: DiagnosticFactState,
        gateState: String
    ) {
        rows = [
            Self.permissionFact(
                id: .camera,
                label: "Camera permission",
                authorization: deviceState.cameraAuthorization,
                optional: false
            ),
            Self.permissionFact(
                id: .microphone,
                label: "Optional microphone permission",
                authorization: deviceState.microphoneAuthorization,
                optional: true
            ),
            DiagnosticChecklistFact(
                id: .orientation,
                label: "Physical orientation",
                value: deviceState.physicalOrientation == .portrait ? "Portrait" : "Landscape",
                reason: deviceState.physicalOrientation == .portrait
                    ? nil
                    : "Tracking stays active; test capture is paused.",
                state: deviceState.physicalOrientation == .portrait ? .ready : .warning
            ),
            DiagnosticChecklistFact(
                id: .tracking,
                label: "ARKit tracking",
                value: Self.trackingValue(deviceState.session.trackingState),
                reason: deviceState.session.trackingState == .normal
                    ? nil
                    : "Tracking must recover before test capture.",
                state: Self.trackingFactState(deviceState.session.trackingState)
            ),
            Self.planeFact(
                id: .horizontalPlanes,
                label: "Horizontal planes",
                observed: deviceState.horizontalPlaneObserved
            ),
            Self.planeFact(
                id: .verticalPlanes,
                label: "Vertical planes",
                observed: deviceState.verticalPlaneObserved
            ),
            DiagnosticChecklistFact(
                id: .epoch,
                label: "World epoch / correction / quarantine",
                value: epochValue,
                reason: epochState == .ready ? nil : "Capture stays paused until alignment is verified.",
                state: epochState
            ),
            DiagnosticChecklistFact(
                id: .packet,
                label: "Packet image and metadata durability",
                value: packetValue,
                reason: packetState == .ready ? nil : "No incomplete packet is published.",
                state: packetState
            ),
            DiagnosticChecklistFact(
                id: .journal,
                label: "Authoritative journal and visibility",
                value: journalValue,
                reason: journalState == .ready ? nil : "Visibility requires a synced journal record.",
                state: journalState
            ),
            DiagnosticChecklistFact(
                id: .build,
                label: "Build, signing, and capability facts",
                value: buildValue,
                reason: "No rear LiDAR capability is required.",
                state: buildState
            ),
            DiagnosticChecklistFact(
                id: .gate,
                label: "Current gate record state",
                value: ["UNRUN", "RUNNING", "RED"].contains(gateState) ? gateState : "UNRUN",
                reason: "Automation cannot approve GREEN or WAIVED_BY_HUMAN.",
                state: gateState == "RED" ? .failed : .pending
            ),
        ]
    }

    private static func permissionFact(
        id: DiagnosticChecklistRowID,
        label: String,
        authorization: PermissionAuthorizationState,
        optional: Bool
    ) -> DiagnosticChecklistFact {
        let value: String
        let state: DiagnosticFactState
        switch authorization {
        case .notDetermined:
            value = "Not checked"
            state = .pending
        case .granted:
            value = "Allowed"
            state = .ready
        case .denied:
            value = "Denied"
            state = optional ? .warning : .failed
        case .restricted:
            value = "Restricted"
            state = optional ? .warning : .failed
        }
        return DiagnosticChecklistFact(
            id: id,
            label: label,
            value: value,
            reason: optional ? "Optional; no audio is recorded and visual capture remains independent." : nil,
            state: state
        )
    }

    private static func planeFact(
        id: DiagnosticChecklistRowID,
        label: String,
        observed: Bool
    ) -> DiagnosticChecklistFact {
        DiagnosticChecklistFact(
            id: id,
            label: label,
            value: observed ? "Observed" : "Not observed",
            reason: observed ? nil : "Move slowly with a visible floor or wall.",
            state: observed ? .ready : .pending
        )
    }

    private static func trackingValue(_ state: DeviceTrackingState) -> String {
        switch state {
        case .initializing: "Starting"
        case .normal: "Normal"
        case .limited: "Limited"
        case .unavailable: "Unavailable"
        }
    }

    private static func trackingFactState(_ state: DeviceTrackingState) -> DiagnosticFactState {
        switch state {
        case .initializing: .pending
        case .normal: .ready
        case .limited: .warning
        case .unavailable: .failed
        }
    }
}

struct DiagnosticRuntimeFacts: Equatable, Sendable {
    let recordedAtUTC: String
    let implementationRevision: String
    let fixtureSHA256: String
    let deviceModel: String
    let osVersion: String
    let appVersion: String

    @MainActor
    static func live(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        date: Date = Date()
    ) -> DiagnosticRuntimeFacts {
        DiagnosticRuntimeFacts(
            recordedAtUTC: DiagnosticUTCClock.string(from: date),
            implementationRevision: environment["REROOM_IMPLEMENTATION_REVISION"] ?? "",
            fixtureSHA256: environment["REROOM_FIXTURE_SHA256"] ?? "",
            deviceModel: UIDevice.current.model,
            osVersion: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            appVersion: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "unavailable"
        )
    }
}

enum DiagnosticEvidenceRequestFactory {
    static func unrun(
        deviceState: DeviceProofState,
        runtime: DiagnosticRuntimeFacts
    ) -> EvidenceExportRequest {
        EvidenceExportRequest(
            gateID: "GATE-013",
            gateState: "UNRUN",
            recordedAtUTC: runtime.recordedAtUTC,
            implementationRevision: runtime.implementationRevision,
            testIDs: ["TST-DEVICE-001"],
            requirementIDs: ["OPS-DEVICE-001"],
            adrIDs: ["ADR-002", "ADR-003"],
            fixtureReferences: [
                EvidenceFixtureReference(
                    fixtureID: "FX-RRCAP-010S",
                    fixtureRevision: "rev-001",
                    sha256: runtime.fixtureSHA256
                )
            ],
            environmentFacts: [
                "device_model": .string(runtime.deviceModel),
                "os_version": .string(runtime.osVersion),
                "runtime_tier": .string("base-iphone-candidate"),
                "camera_permission": .string(cameraFact(deviceState.cameraAuthorization)),
                "arkit_world_tracking": .string(trackingFact(deviceState)),
                "plane_detection": .string(planeFact(deviceState)),
                "lidar_required": .boolean(false),
                "signing_result": .string("not_tested"),
            ],
            valueClassification: "TARGET",
            evidenceArtifacts: [],
            automatedReportSHA256: nil
        )
    }

    private static func cameraFact(_ state: PermissionAuthorizationState) -> String {
        switch state {
        case .notDetermined: "not_tested"
        case .granted: "granted"
        case .denied, .restricted: "denied"
        }
    }

    private static func trackingFact(_ state: DeviceProofState) -> String {
        guard state.cameraAuthorization == .granted else { return "not_tested" }
        return state.session.isRunning && state.session.trackingState == .normal ? "pass" : "fail"
    }

    private static func planeFact(_ state: DeviceProofState) -> String {
        guard state.cameraAuthorization == .granted else { return "not_tested" }
        return state.session.observedPlaneAlignments.isEmpty ? "fail" : "pass"
    }
}

private enum DiagnosticUTCClock {
    static func string(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return formatter.string(from: date)
    }
}

@MainActor
@Observable
final class DiagnosticAppOwner {
    let model: DeviceProofModel
    private(set) var epoch: WorldEpochSnapshot
    private(set) var packetValue = "No ARFrame snapshot captured"
    private(set) var packetState: DiagnosticFactState = .pending
    private(set) var journalValue = "No authoritative journal prefix"
    private(set) var journalState: DiagnosticFactState = .pending
    private(set) var captureConsent: DiagnosticCaptureConsentChoice = .unanswered

    @ObservationIgnored private let runtime: DiagnosticRuntimeFacts
    @ObservationIgnored private let sessionID: String
    @ObservationIgnored private let submapID: String
    @ObservationIgnored private var epochController: WorldEpochController
    @ObservationIgnored private var journal: DiagnosticJournal?
    @ObservationIgnored private var captureSequence: UInt64 = 0

    init(
        model: DeviceProofModel = DeviceProofModel(),
        runtime: DiagnosticRuntimeFacts? = nil
    ) {
        let sessionUUID = UUID().uuidString.lowercased()
        let worldUUID = UUID().uuidString.lowercased()
        self.model = model
        self.runtime = runtime ?? .live()
        sessionID = "session_\(sessionUUID)"
        submapID = "submap_\(UUID().uuidString.lowercased())"
        epochController = WorldEpochController(worldFrameID: "world_\(worldUUID)")
        epoch = epochController.snapshot
    }

    var evidenceRequest: EvidenceExportRequest {
        DiagnosticEvidenceRequestFactory.unrun(deviceState: model.state, runtime: runtime)
    }

    var snapshot: DiagnosticChecklistSnapshot {
        DiagnosticChecklistSnapshot(
            deviceState: model.state,
            epochValue: "Version \(epoch.worldFrameVersion) — \(epoch.isQuarantined ? "quarantined" : "usable")",
            epochState: epoch.isQuarantined ? .failed : .ready,
            packetValue: packetValue,
            packetState: packetState,
            journalValue: journalValue,
            journalState: journalState,
            buildValue: "\(runtime.deviceModel), \(runtime.osVersion), app \(runtime.appVersion); signing not tested",
            buildState: .pending,
            gateState: "UNRUN"
        )
    }

    func prepare() async {
        await model.prepare()
    }

    func refreshPhysicalOrientation() {
        model.refreshPhysicalOrientation()
    }

    func grantCaptureConsent() {
        captureConsent = .granted
        packetValue = "No ARFrame snapshot captured"
        packetState = .pending
    }

    func denyCaptureConsent() {
        captureConsent = .denied
        packetValue = "Test capture remains off by your choice"
        packetState = .warning
    }

    func captureTestFrame() {
        guard captureConsent == .granted,
              captureSequence == 0,
              let frame = model.currentARFrame,
              let validator = try? makeContractValidator()
        else {
            packetValue = captureConsent == .granted
                ? "Capture unavailable: no healthy ARFrame"
                : "Capture consent is required"
            packetState = .warning
            return
        }
        do {
            let captured = try ARFrameCaptureAdapter().capture(
                frame: frame,
                orientation: .portrait
            )
            let health = CaptureFrameSnapshot(
                id: captured.id,
                sessionIsRunning: model.state.session.isRunning,
                trackingState: model.state.session.trackingState
            )
            var attemptMachine = CaptureAttemptMachine()
            _ = attemptMachine.select(
                orientation: model.state.physicalOrientation,
                frameSnapshot: health,
                worldEpoch: epoch
            )
            let attempt = attemptMachine.finish(
                currentOrientation: model.state.physicalOrientation,
                frameSnapshot: health,
                worldEpoch: epoch
            )
            let journal = try journal ?? makeJournal(validator: validator)
            self.journal = journal
            let receipt = try journal.capture(
                input: FramePacketCaptureInput(
                    sessionID: sessionID,
                    submapID: submapID,
                    frameID: "frame_\(UUID().uuidString.lowercased())",
                    captureSequence: captureSequence,
                    capturedFrame: captured,
                    quality: FrameQuality(
                        motionScore: 0,
                        blurScore: 1,
                        exposureScore: 1,
                        selectedReason: "user_event"
                    ),
                    idempotencyKey: "frameidem_\(UUID().uuidString.lowercased())",
                    previousDurableFrameID: nil,
                    lifecycleEventIDs: (0..<4).map { _ in
                        "event_\(UUID().uuidString.lowercased())"
                    }
                ),
                attempt: attempt
            )
            captureSequence += 1
            packetValue = "\(receipt.packet.frameID) — \(receipt.lifecycle.rawValue)"
            packetState = .ready
            let recovered = try journal.recover()
            journalValue = "\(recovered.journal.count) synced records; \(recovered.networkEligibleFrameIDs.count) visible frame"
            journalState = .ready
        } catch {
            packetValue = "Capture rejected before publication"
            packetState = .failed
            journalValue = "Journal unchanged"
            journalState = .pending
        }
    }

    private func makeJournal(validator: ContractValidator) throws -> DiagnosticJournal {
        let consent = try CaptureConsentRecord.granting(
            sessionID: sessionID,
            recordedAtUTC: runtime.recordedAtUTC,
            retentionPolicy: .localOnlyUntilShare,
            retentionExpiresAtUTC: nil
        )
        let root = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("diagnostic-captures/\(sessionID)", isDirectory: true)
        return DiagnosticJournal(
            fileSystem: FoundationCaptureFileSystem(root: root),
            framePacketBuilder: FramePacketBuilder(validator: validator),
            configuration: DiagnosticCaptureConfiguration(
                sessionID: sessionID,
                deviceModel: runtime.deviceModel,
                osVersion: runtime.osVersion,
                appVersion: runtime.appVersion,
                buildID: runtime.implementationRevision,
                recordedAtUTC: runtime.recordedAtUTC,
                worldFrameID: epoch.worldFrameID,
                initialWorldFrameVersion: epoch.worldFrameVersion,
                consent: .granted(consent)
            )
        )
    }

    private func makeContractValidator() throws -> ContractValidator {
        let resources: [(ContractSchemaIdentifier, String, String)] = [
            (.framePacket, "frame-packet", "d50b19bfb29c6c62c494e3a47deb3c51a933609698f4ff2f9cbfba6ec4252b43"),
            (.rrcapManifest, "rrcap-manifest", "c97349820ed66fb1a1fdf60ea9afee312f532811602851d01d1e233641730b87"),
            (.sceneState, "scene-state", "9c77d27762e20ff5fad24c438e8817a03c770b55be3fc82ea72097c4c273e440"),
            (.editArtifacts, "edit-artifacts", "58dbfc8f152881cbdc31be22f6ab7631ac474bb78537ac2a9254f5ef16bd598f"),
            (.transaction, "transaction", "2a4f6728978db0879b5dfb10f052f6d5280e5cf83ad5600f0cf959626c2399a2"),
        ]
        return try ContractValidator(registrations: resources.map { identifier, name, digest in
            guard let url = Bundle.main.url(forResource: name, withExtension: "schema.json") else {
                throw EvidenceExportRejection.invalidSchema
            }
            return ContractSchemaRegistration(
                identifier: identifier,
                version: "1.0.0",
                sha256: digest,
                schemaData: try Data(contentsOf: url)
            )
        })
    }
}

enum DiagnosticCaptureConsentChoice: Equatable, Sendable {
    case unanswered
    case granted
    case denied
}

@MainActor
struct DiagnosticChecklistView: View {
    @Bindable var owner: DiagnosticAppOwner

    @State private var exportState: DiagnosticEvidenceExportState = .notReady
    @State private var showsCaptureConsent = false

    var body: some View {
        ZStack {
            Color(red: 11 / 255, green: 15 / 255, blue: 20 / 255)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    DiagnosticChecklistHeader()
                    DiagnosticCandidateStatus(model: owner.model)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(snapshot.rows) { fact in
                            DiagnosticFactRow(fact: fact)
                        }
                    }
                    microphoneControl
                    captureControl
                    exportControl
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 24)
            }
        }
        .foregroundStyle(Color(red: 245 / 255, green: 247 / 255, blue: 250 / 255))
        .accessibilityIdentifier("debug.root.diagnostics")
        .task {
            await owner.prepare()
            refreshExportReadiness()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            owner.refreshPhysicalOrientation()
        }
    }

    private var snapshot: DiagnosticChecklistSnapshot {
        owner.snapshot
    }

    private var microphoneControl: some View {
        Button("Check Microphone Access") {
            Task { await owner.model.checkMicrophoneAccess() }
        }
        .font(.body.weight(.semibold))
        .frame(maxWidth: .infinity, minHeight: 44)
        .buttonStyle(.bordered)
        .accessibilityIdentifier("debug.permission.microphone")
    }

    private var captureControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Capture Test Frame") {
                if owner.captureConsent == .granted {
                    owner.captureTestFrame()
                } else {
                    showsCaptureConsent = true
                }
            }
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
            .buttonStyle(.bordered)
            .accessibilityIdentifier("debug.action.captureFrame")
            .confirmationDialog(
                "Allow one test-frame capture?",
                isPresented: $showsCaptureConsent,
                titleVisibility: .visible
            ) {
                Button("Allow One Test Frame") {
                    owner.grantCaptureConsent()
                }
                Button("Keep Capture Off", role: .cancel) {
                    owner.denyCaptureConsent()
                }
            } message: {
                Text("The frame stays on this iPhone unless you explicitly share sanitized evidence.")
            }
            Text(captureConsentExplanation)
                .font(.body)
                .foregroundStyle(Color(red: 183 / 255, green: 192 / 255, blue: 202 / 255))
        }
    }

    private var captureConsentExplanation: String {
        switch owner.captureConsent {
        case .unanswered:
            "Capture requires a separate, session-only consent choice."
        case .granted:
            "One test frame is allowed for this diagnostic session."
        case .denied:
            "Test capture is off. The checklist remains usable without it."
        }
    }

    private var exportControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Export Sanitized Evidence") {
                exportEvidence()
            }
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
            .buttonStyle(.borderedProminent)
            .disabled(exportState.canExport == false)
            .accessibilityValue(exportState.accessibilityValue)
            .accessibilityIdentifier("debug.action.exportEvidence")

            Text(exportState.message)
                .font(.body)
                .foregroundStyle(Color(red: 183 / 255, green: 192 / 255, blue: 202 / 255))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("debug.status.exportEvidence")
        }
    }

    private func refreshExportReadiness() {
        do {
            _ = try EvidenceExporter().validatedData(for: owner.evidenceRequest)
            exportState = .ready
        } catch {
            exportState = .validationFailed
        }
    }

    private func exportEvidence() {
        guard let directory = FileManager.default.urls(
                  for: .documentDirectory,
                  in: .userDomainMask
              ).first
        else {
            exportState = .validationFailed
            return
        }
        do {
            _ = try EvidenceExporter().export(
                owner.evidenceRequest,
                to: directory.appendingPathComponent("gate-report.json")
            )
            exportState = .exported
        } catch {
            exportState = .validationFailed
        }
    }
}

private enum DiagnosticEvidenceExportState: Equatable {
    case notReady
    case ready
    case exported
    case validationFailed

    var canExport: Bool { self == .ready || self == .exported }

    var message: String {
        switch self {
        case .ready:
            "Sanitized evidence is ready to export."
        case .exported:
            "Exported sanitized evidence. No file was shared automatically."
        case .notReady, .validationFailed:
            "Evidence wasn’t exported because validation failed. No file was shared. Review the failed check, then try exporting again."
        }
    }

    var accessibilityValue: String {
        switch self {
        case .ready: "Validated and available"
        case .exported: "Exported"
        case .notReady, .validationFailed: "Unavailable because validation failed"
        }
    }
}

private struct DiagnosticChecklistHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ReRoom device check")
                .font(.title.weight(.semibold))
            Text("Candidate — physical verification pending")
                .font(.body)
                .foregroundStyle(Color(red: 183 / 255, green: 192 / 255, blue: 202 / 255))
            Text("Internal diagnostic build")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255))
        }
    }
}

private struct DiagnosticCandidateStatus: View {
    @Bindable var model: DeviceProofModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.statusTitle)
                .font(.title2.weight(.semibold))
            Text(model.statusMessage)
                .font(.body)
                .foregroundStyle(Color(red: 183 / 255, green: 192 / 255, blue: 202 / 255))
                .fixedSize(horizontal: false, vertical: true)
            if let action = model.primaryAction {
                Button(action.label) {
                    Task { await model.performPrimaryAction() }
                }
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .buttonStyle(.borderedProminent)
                .disabled(model.isPerformingPermissionRequest)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(red: 23 / 255, green: 29 / 255, blue: 36 / 255).opacity(0.94))
        .clipShape(.rect(cornerRadius: 16))
        .accessibilityElement(children: .contain)
    }
}

private struct DiagnosticFactRow: View {
    let fact: DiagnosticChecklistFact

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: fact.state.symbolName)
                .foregroundStyle(fact.state.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(fact.label)
                    .font(.footnote.weight(.semibold))
                Text(fact.value)
                    .font(.body)
                if let reason = fact.reason {
                    Text(reason)
                        .font(.body)
                        .foregroundStyle(Color(red: 183 / 255, green: 192 / 255, blue: 202 / 255))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(16)
        .background(Color(red: 23 / 255, green: 29 / 255, blue: 36 / 255).opacity(0.94))
        .clipShape(.rect(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(fact.label)
        .accessibilityValue(fact.reason.map { "\(fact.value). \($0)" } ?? fact.value)
        .accessibilityIdentifier(fact.id.rawValue)
    }
}
