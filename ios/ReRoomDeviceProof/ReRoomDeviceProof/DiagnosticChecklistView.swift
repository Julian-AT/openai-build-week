import Observation
import ReRoomContracts
import ReRoomCaptureCore
import SwiftUI
import UIKit

private final class DiagnosticAppBundleToken {}

enum DiagnosticCaptureAccessibility {
    static let userEventBusy = "diagnostic.capture.user-event-busy"
}

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
    let deviceModel: String?
    let osVersion: String
    let appVersion: String

    @MainActor
    static func live(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        date: Date = Date(),
        bundle: Bundle = .main
    ) -> DiagnosticRuntimeFacts {
        let provenance = bundledProvenance(in: bundle)
        return DiagnosticRuntimeFacts(
            recordedAtUTC: DiagnosticUTCClock.string(from: date),
            implementationRevision: provenance["implementation_revision"] as? String
                ?? environment["REROOM_IMPLEMENTATION_REVISION"] ?? "",
            fixtureSHA256: provenance["fixture_sha256"] as? String
                ?? environment["REROOM_FIXTURE_SHA256"] ?? "",
            deviceModel: nil,
            osVersion: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            appVersion: bundle.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "unavailable"
        )
    }

    private static func bundledProvenance(in bundle: Bundle) -> [String: Any] {
        guard let url = bundle.url(
                  forResource: "ReRoomBuildProvenance",
                  withExtension: "plist"
              ),
              let values = NSDictionary(contentsOf: url) as? [String: Any]
        else {
            return [:]
        }
        return values
    }
}

enum DiagnosticEvidenceRequestFactory {
    static func unrun(
        deviceState: DeviceProofState,
        runtime: DiagnosticRuntimeFacts
    ) -> EvidenceExportRequest {
        var environmentFacts: [String: EvidenceEnvironmentFactValue] = [
            "os_version": .string(runtime.osVersion),
            "runtime_tier": .string("base-iphone-candidate"),
            "camera_permission": .string(cameraFact(deviceState.cameraAuthorization)),
            "arkit_world_tracking": .string(trackingFact(deviceState)),
            "plane_detection": .string(planeFact(deviceState)),
            "lidar_required": .boolean(false),
            "signing_result": .string("not_tested"),
        ]
        if let deviceModel = runtime.deviceModel {
            environmentFacts["device_model"] = .string(deviceModel)
        }
        return EvidenceExportRequest(
            gateID: "GATE-013",
            gateState: "UNRUN",
            recordedAtUTC: runtime.recordedAtUTC,
            implementationRevision: runtime.implementationRevision,
            testIDs: ["TST-DEVICE-001"],
            requirementIDs: ["OPS-DEVICE-001"],
            adrIDs: ["ADR-002", "ADR-003"],
            fixtureReferences: [
                EvidenceFixtureReference(
                    fixtureID: "FX-CONTRACT-001",
                    fixtureRevision: "rev-001",
                    sha256: runtime.fixtureSHA256
                )
            ],
            environmentFacts: environmentFacts,
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
    private(set) var replayInspector: VerifiedReplayInspector?
    private(set) var replaySelection: ReplayTimelineEntry?
    private(set) var replaySelectionError: String?

    @ObservationIgnored private let runtime: DiagnosticRuntimeFacts
    @ObservationIgnored private var epochController: WorldEpochController

    init(
        model: DeviceProofModel? = nil,
        runtime: DiagnosticRuntimeFacts? = nil
    ) {
        let resolvedRuntime = runtime ?? .live()
        let worldUUID = UUID().uuidString.lowercased()
        self.runtime = resolvedRuntime
        self.model = model ?? Self.makeLiveModel(runtime: resolvedRuntime)
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
            buildValue: "\(runtime.deviceModel ?? "Model not recorded"), \(runtime.osVersion), app \(runtime.appVersion); signing not tested",
            buildState: .pending,
            gateState: "UNRUN"
        )
    }

    var canPerformExplicitWorldReset: Bool {
        model.state.cameraAuthorization == .granted
            && model.state.session.isRunning
            && epoch.isQuarantined == false
    }

    func prepare() async {
        await model.prepare()
        await model.discoverInterruptedRoomCaptures()
    }

    func refreshPhysicalOrientation() {
        model.refreshPhysicalOrientation()
    }

    var capturePresentation: CapturePresentationSnapshot {
        model.capturePresentation
    }

    func grantCaptureConsent() async {
        captureConsent = .granted
        packetValue = "No ARFrame snapshot captured"
        packetState = .pending
        await model.acceptRoomCaptureDisclosure()
    }

    func denyCaptureConsent() {
        captureConsent = .denied
        model.declineRoomCaptureDisclosure()
        packetValue = "Room capture remains off by your choice"
        packetState = .warning
    }

    func captureTestFrame() {
        switch model.offerCurrentFrameForCapture(isUserEvent: true) {
        case .admission(.admitted):
            packetValue = "Explicit frame admitted to bounded local saving"
            packetState = .pending
        case .admission(.rejected(.userEventBusy)):
            packetValue = CaptureSessionAdapter.userEventBusyMessage
            packetState = .warning
        case .admission(.rejected):
            packetValue = "Capture candidate rejected before selection"
            packetState = .warning
        case .notSelected:
            packetValue = "Frame did not meet the deterministic selector"
            packetState = .warning
        case .notRecording, .invalidSnapshot:
            packetValue = "Capture unavailable: no healthy ARFrame"
            packetState = .warning
        }
    }

    func stopCapture() async {
        await model.stopRoomCapture()
    }

    func startNewCaptureDisclosure() {
        captureConsent = .unanswered
        replayInspector = nil
        replaySelection = nil
        replaySelectionError = nil
    }

    func inspectReplay() {
        guard let replay = capturePresentation.recovered else {
            replayInspector = nil
            replaySelectionError = "No hash-verified replay is available."
            return
        }
        do {
            replayInspector = try VerifiedReplayInspector(replay: replay)
            replaySelection = nil
            replaySelectionError = nil
        } catch {
            replayInspector = nil
            replaySelectionError = "Replay verification failed; no frame was exposed."
        }
    }

    func selectReplayEntry(journalSequence: UInt64) {
        do {
            replaySelection = try replayInspector?.entry(journalSequence: journalSequence)
            replaySelectionError = nil
        } catch {
            replaySelection = nil
            replaySelectionError = "That journal item is not part of the verified replay."
        }
    }

    func performExplicitWorldReset() {
        guard canPerformExplicitWorldReset,
              model.performExplicitWorldReset()
        else {
            return
        }

        _ = epochController.advance(
            reason: .arkitReset,
            correctionEvidence: .absent
        )
        epoch = epochController.snapshot
    }

    static func makeContractValidator() throws -> ContractValidator {
        let resources: [(ContractSchemaIdentifier, String, String)] = [
            (.framePacket, "frame-packet", "d50b19bfb29c6c62c494e3a47deb3c51a933609698f4ff2f9cbfba6ec4252b43"),
            (.rrcapManifest, "rrcap-manifest", "c97349820ed66fb1a1fdf60ea9afee312f532811602851d01d1e233641730b87"),
            (.sceneState, "scene-state", "9c77d27762e20ff5fad24c438e8817a03c770b55be3fc82ea72097c4c273e440"),
            (.editArtifacts, "edit-artifacts", "58dbfc8f152881cbdc31be22f6ab7631ac474bb78537ac2a9254f5ef16bd598f"),
            (.transaction, "transaction", "2a4f6728978db0879b5dfb10f052f6d5280e5cf83ad5600f0cf959626c2399a2"),
        ]
        return try ContractValidator(registrations: resources.map { identifier, name, digest in
            guard let url = Bundle(for: DiagnosticAppBundleToken.self).url(
                forResource: "\(name).schema",
                withExtension: "json"
            ) else {
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

    private static func makeLiveModel(runtime: DiagnosticRuntimeFacts) -> DeviceProofModel {
        do {
            let documents = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let adapter = CaptureSessionAdapter(
                identities: UUIDCaptureIdentityDriver(),
                archiveFactory: CoreCaptureArchiveSessionFactory(
                    root: documents,
                    validator: try makeContractValidator(),
                    source: CaptureArchiveSource(
                        deviceModel: runtime.deviceModel ?? "unreported",
                        osVersion: runtime.osVersion,
                        appVersion: runtime.appVersion,
                        buildID: runtime.implementationRevision,
                        recordedAtUTC: runtime.recordedAtUTC
                    )
                ),
                recoveryDriver: FoundationCaptureRecoveryDriver(
                    root: documents,
                    fixtureManifestSHA256: runtime.fixtureSHA256,
                    repositoryRevision: runtime.implementationRevision
                ),
                storageDriver: CaptureStorageState(),
                backgroundDriver: UIApplicationCaptureBackgroundDriver(),
                selectorPolicy: try FrameSelectionPolicy(
                    policyID: "policy_selection_hypothesis_device_1",
                    classification: .hypothesis,
                    minimumCadenceNanoseconds: 500_000_000,
                    minimumViewNovelty: 0.15,
                    maximumMotionScore: 0.5,
                    minimumBlurScore: 0.5,
                    minimumExposureScore: 0.25
                ),
                pressurePolicy: try CapturePressurePolicy(
                    policyID: "policy_pressure_hypothesis_device_1",
                    classification: .hypothesis,
                    ordinaryCapacity: 3,
                    optionalComputeDropDepth: 1,
                    uploadPauseDepth: 2,
                    cadenceReductionDepth: 3
                )
            )
            return DeviceProofModel(captureSessionAdapter: adapter)
        } catch {
            return DeviceProofModel()
        }
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
    @State private var showsWorldResetConfirmation = false

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
                    worldResetControl
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
            if owner.capturePresentation.phase == .recovered,
               let recovered = owner.capturePresentation.recovered {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recovered — capture may be incomplete")
                        .font(.headline)
                    Text(
                        "Verified \(recovered.recovered.acceptedJournalRecordCount) authoritative journal records; "
                            + "status \(recovered.recovered.finalization.state.rawValue)."
                    )
                    .font(.body)
                    .foregroundStyle(Color(red: 183 / 255, green: 192 / 255, blue: 202 / 255))
                    .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Inspect replay") {
                            owner.inspectReplay()
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("diagnostic.capture.inspect-replay")
                        Button("Start new capture") {
                            owner.startNewCaptureDisclosure()
                            showsCaptureConsent = true
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("diagnostic.capture.start-new")
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("diagnostic.capture.recovery")
            }

            if owner.capturePresentation.recoveryFailures.isEmpty == false {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Archive verification failed")
                        .font(.headline)
                    ForEach(
                        owner.capturePresentation.recoveryFailures,
                        id: \.archiveName
                    ) { failure in
                        Text("\(failure.archiveName): \(failure.message)")
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .foregroundStyle(.orange)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("diagnostic.capture.recovery-failure")
            }

            if owner.capturePresentation.phase == .recording {
                captureStateRow(
                    label: owner.capturePresentation.localRecordingLabel,
                    identifier: "diagnostic.capture.local-state"
                )
                captureStateRow(
                    label: owner.capturePresentation.uploadLabel,
                    identifier: "diagnostic.capture.upload-state"
                )
                captureStateRow(
                    label: owner.capturePresentation.shareLabel,
                    identifier: "diagnostic.capture.share-state"
                )

                if let admission = owner.capturePresentation.admission {
                    Text(
                        "HYPOTHESIS capacity — offered \(admission.offered), queued \(admission.queued), "
                            + "in flight \(admission.inFlight), maximum \(admission.maximumOutstanding); "
                            + "ordinary rejected \(admission.rejectedOrdinaryCapacity), "
                            + "explicit busy \(admission.rejectedUserEventBusy); "
                            + "close \(admission.closeReason?.rawValue ?? "open")"
                    )
                    .font(.caption)
                    .foregroundStyle(Color(red: 183 / 255, green: 192 / 255, blue: 202 / 255))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("diagnostic.capture.admission")
                }

                Button("Save explicit capture frame") {
                    owner.captureTestFrame()
                }
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .buttonStyle(.bordered)
                .disabled(owner.capturePresentation.explicitCaptureBusy)
                .accessibilityIdentifier("diagnostic.capture.explicit")

                if let busyMessage = owner.capturePresentation.busyMessage {
                    Text(busyMessage)
                        .font(.body)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(
                            DiagnosticCaptureAccessibility.userEventBusy
                        )
                }

                Button("Stop room capture", role: .destructive) {
                    Task { await owner.stopCapture() }
                }
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .buttonStyle(.bordered)
                .accessibilityIdentifier("diagnostic.capture.stop")
            } else {
                Button("Start room capture") {
                    showsCaptureConsent = true
                }
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .buttonStyle(.bordered)
                .accessibilityIdentifier("diagnostic.capture.start")

                if owner.captureConsent == .denied {
                    Text("Room capture is off. Diagnostics remain available without recording.")
                        .font(.body)
                        .foregroundStyle(Color(red: 183 / 255, green: 192 / 255, blue: 202 / 255))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("diagnostic.capture.denied")
                }
                if owner.capturePresentation.phase == .failed,
                   let failure = owner.capturePresentation.failureMessage {
                    Text(failure)
                        .font(.body)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("diagnostic.capture.failure")
                }
            }

            if let inspector = owner.replayInspector {
                replayInspector(inspector)
            }
            if let error = owner.replaySelectionError {
                Text(error)
                    .font(.body)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("diagnostic.capture.inspector-error")
            }
        }
        .confirmationDialog(
            "Start local room capture?",
            isPresented: $showsCaptureConsent,
            titleVisibility: .visible
        ) {
            Button("Accept and Start") {
                Task { await owner.grantCaptureConsent() }
            }
            Button("Keep Capture Off") {
                owner.denyCaptureConsent()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "ARFrame images, calibration, pose, and events are recorded locally for this new session. "
                    + "Nothing is uploaded or shared unless you choose that separately."
            )
        }
    }

    private func captureStateRow(label: String, identifier: String) -> some View {
        Text(label)
            .font(.body.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(identifier)
    }

    private func replayInspector(_ inspector: VerifiedReplayInspector) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Verified replay")
                .font(.headline)
            Text("Verdict \(inspector.report.verdict.rawValue); status \(inspector.status.rawValue)")
                .font(.body)
                .accessibilityIdentifier("diagnostic.capture.inspector-verdict")
            Text(
                "Journal \(inspector.digests.journalTupleSHA256.prefix(12))… · "
                    + "frames \(inspector.digests.frameProjectionSHA256.prefix(12))… · "
                    + "events \(inspector.digests.eventProjectionSHA256.prefix(12))…"
            )
            .font(.caption.monospaced())
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("diagnostic.capture.inspector-digests")

            ForEach(inspector.timeline, id: \.journalSequence) { entry in
                Button {
                    owner.selectReplayEntry(journalSequence: entry.journalSequence)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("#\(entry.journalSequence) · \(entry.entryType.rawValue)")
                            .font(.body.weight(.semibold))
                        Text(entry.referenceID)
                            .font(.caption.monospaced())
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "Journal sequence \(entry.journalSequence), \(entry.entryType.rawValue), \(entry.referenceID)"
                )
                .accessibilityIdentifier(
                    "diagnostic.capture.timeline.\(entry.journalSequence)"
                )
            }

            if let selection = owner.replaySelection {
                Text("Selected verified ID \(selection.referenceID)")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("diagnostic.capture.inspector-selection")
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("diagnostic.capture.inspector")
    }

    private var worldResetControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Run Explicit World Reset") {
                showsWorldResetConfirmation = true
            }
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
            .buttonStyle(.bordered)
            .disabled(owner.canPerformExplicitWorldReset == false)
            .accessibilityIdentifier("debug.action.worldReset")
            .confirmationDialog(
                "Reset ARKit world tracking?",
                isPresented: $showsWorldResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset and Quarantine", role: .destructive) {
                    owner.performExplicitWorldReset()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This advances world_frame_version and quarantines capture because no physical correction is inferred.")
            }

            Text("Use once for GATE-002 after the portrait and landscape checks. Capture remains disabled until a separately validated correction exists.")
                .font(.body)
                .foregroundStyle(Color(red: 183 / 255, green: 192 / 255, blue: 202 / 255))
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
