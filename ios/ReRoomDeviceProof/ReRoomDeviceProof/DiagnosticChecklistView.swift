import SwiftUI

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
        epochValue: String = "Version 1 — usable",
        epochState: DiagnosticFactState = .ready,
        packetValue: String = "No test frame captured",
        packetState: DiagnosticFactState = .pending,
        journalValue: String = "No network-eligible frame",
        journalState: DiagnosticFactState = .pending,
        buildValue: String = "Candidate — physical verification pending",
        gateState: String = "UNRUN"
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
                state: .pending
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

@MainActor
struct DiagnosticChecklistView: View {
    @Bindable var model: DeviceProofModel
    let evidenceRequest: EvidenceExportRequest?

    @State private var exportState: DiagnosticEvidenceExportState = .notReady

    init(model: DeviceProofModel, evidenceRequest: EvidenceExportRequest? = nil) {
        self.model = model
        self.evidenceRequest = evidenceRequest
    }

    var body: some View {
        ZStack {
            Color(red: 11 / 255, green: 15 / 255, blue: 20 / 255)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    DiagnosticChecklistHeader()
                    DiagnosticCandidateStatus(model: model)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(snapshot.rows) { fact in
                            DiagnosticFactRow(fact: fact)
                        }
                    }
                    microphoneControl
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
            await model.prepare()
            refreshExportReadiness()
        }
    }

    private var snapshot: DiagnosticChecklistSnapshot {
        DiagnosticChecklistSnapshot(
            deviceState: model.state,
            gateState: evidenceRequest?.gateState ?? "UNRUN"
        )
    }

    private var microphoneControl: some View {
        Button("Check Microphone Access") {
            Task { await model.checkMicrophoneAccess() }
        }
        .font(.body.weight(.semibold))
        .frame(maxWidth: .infinity, minHeight: 44)
        .buttonStyle(.bordered)
        .accessibilityIdentifier("debug.permission.microphone")
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
        }
    }

    private func refreshExportReadiness() {
        guard let evidenceRequest else {
            exportState = .notReady
            return
        }
        do {
            _ = try EvidenceExporter().validatedData(for: evidenceRequest)
            exportState = .ready
        } catch {
            exportState = .validationFailed
        }
    }

    private func exportEvidence() {
        guard let evidenceRequest,
              let directory = FileManager.default.urls(
                  for: .documentDirectory,
                  in: .userDomainMask
              ).first
        else {
            exportState = .validationFailed
            return
        }
        do {
            _ = try EvidenceExporter().export(
                evidenceRequest,
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
        case .ready, .exported:
            "Sanitized evidence is ready to export."
        case .notReady, .validationFailed:
            "Evidence wasn’t exported because validation failed. No file was shared. Review the failed check, then try exporting again."
        }
    }

    var accessibilityValue: String {
        canExport ? "Validated and available" : "Unavailable because validation failed"
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
