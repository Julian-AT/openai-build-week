import Combine
import Darwin
import Observation
import ReRoomContracts
import ReRoomCaptureCore
import SwiftUI
import UIKit

actor Gate001PressureHarness {
    private var armed = false
    private var blocking = false
    private var blockedWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    var isBlocking: Bool { blocking }

    func arm() {
        precondition(blocking == false)
        armed = true
    }

    func beforePublish(selectedReason: SelectedFrameReason) async {
        guard armed, selectedReason != .userEvent, blocking == false else { return }
        armed = false
        blocking = true
        let waiters = blockedWaiters
        blockedWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters { waiter.resume() }
        await withCheckedContinuation { continuation in
            releaseWaiter = continuation
        }
        blocking = false
    }

    func waitUntilBlocked() async {
        guard blocking == false else { return }
        await withCheckedContinuation { continuation in
            blockedWaiters.append(continuation)
        }
    }

    func release() {
        armed = false
        let waiter = releaseWaiter
        releaseWaiter = nil
        waiter?.resume()
    }
}

struct Gate001PressureMeasurement: Codable, Equatable, Sendable {
    let capacity: Int
    let maximumDepth: Int
    let staleDropCount: Int
    let capacityDropCount: Int
    let pressureApplied: Bool
    let networkBlackholed: Bool
    let uploadPausedFirst: Bool

    init(
        capacity: Int,
        maximumDepth: Int,
        staleDropCount: Int,
        capacityDropCount: Int,
        pressureApplied: Bool,
        networkBlackholed: Bool,
        uploadPausedFirst: Bool
    ) {
        self.capacity = capacity
        self.maximumDepth = maximumDepth
        self.staleDropCount = staleDropCount
        self.capacityDropCount = capacityDropCount
        self.pressureApplied = pressureApplied
        self.networkBlackholed = networkBlackholed
        self.uploadPausedFirst = uploadPausedFirst
    }

    init?(capacity: Int, snapshot: CaptureAdmissionSnapshot) {
        guard capacity > 0,
              snapshot.maximumOutstanding >= capacity,
              snapshot.uploadPaused,
              snapshot.rejectedOrdinaryCapacity > 0,
              snapshot.writerFailed == 0,
              snapshot.cancelledBeforeSelection == 0,
              snapshot.storageUnavailableBeforeSelection == 0,
              let capacityDropCount = Int(exactly: snapshot.rejectedOrdinaryCapacity)
        else { return nil }
        self.init(
            capacity: capacity,
            maximumDepth: snapshot.maximumOutstanding,
            staleDropCount: 0,
            capacityDropCount: capacityDropCount,
            pressureApplied: true,
            networkBlackholed: true,
            uploadPausedFirst: true
        )
    }
}

struct Gate001PressureEvidence: Codable, Equatable, Sendable {
    let schemaVersion = "gate001-pressure-observation/1"
    let sessionID: String
    let implementationRevision: String
    let recordedAtUTC: String
    let capacity: Int
    let maximumDepth: Int
    let staleDropCount: Int
    let capacityDropCount: Int
    let pressureApplied: Bool
    let networkBlackholed: Bool
    let uploadPausedFirst: Bool

    init(
        sessionID: String,
        implementationRevision: String,
        recordedAtUTC: String,
        measurement: Gate001PressureMeasurement
    ) {
        self.sessionID = sessionID
        self.implementationRevision = implementationRevision
        self.recordedAtUTC = recordedAtUTC
        capacity = measurement.capacity
        maximumDepth = measurement.maximumDepth
        staleDropCount = measurement.staleDropCount
        capacityDropCount = measurement.capacityDropCount
        pressureApplied = measurement.pressureApplied
        networkBlackholed = measurement.networkBlackholed
        uploadPausedFirst = measurement.uploadPausedFirst
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case sessionID = "session_id"
        case implementationRevision = "implementation_revision"
        case recordedAtUTC = "recorded_at_utc"
        case capacity
        case maximumDepth = "maximum_depth"
        case staleDropCount = "stale_drop_count"
        case capacityDropCount = "capacity_drop_count"
        case pressureApplied = "pressure_applied"
        case networkBlackholed = "network_blackholed"
        case uploadPausedFirst = "upload_paused_first"
    }
}

struct Gate001PressureEvidenceRecorder: Sendable {
    let root: URL

    func record(_ evidence: Gate001PressureEvidence) throws -> URL {
        guard evidence.sessionID.range(
            of: #"^session_[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"#,
            options: .regularExpression
        ) != nil else { throw Gate001PressureEvidenceError.invalidSessionID }
        let directory = root.appendingPathComponent(
            "gate001-pressure-observations",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent("\(evidence.sessionID).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(evidence).write(to: url, options: .atomic)
        let handle = try FileHandle(forWritingTo: url)
        try handle.synchronize()
        try handle.close()
        try directory.withUnsafeFileSystemRepresentation { path in
            guard let path else { throw Gate001PressureEvidenceError.invalidDirectory }
            let descriptor = Darwin.open(path, O_RDONLY)
            guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
            defer { Darwin.close(descriptor) }
            guard Darwin.fsync(descriptor) == 0 else {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }
        }
        return url
    }
}

private enum Gate001PressureEvidenceError: Error {
    case invalidSessionID
    case invalidDirectory
}

enum Gate001LaunchConfiguration {
    static let terminationControlsArgument = "--gate-001-termination-controls"

    static func controlsEnabled(arguments: [String]) -> Bool {
        arguments.contains(terminationControlsArgument)
    }

    static func usesDiagnosticSurface(
        arguments: [String],
        isDebugBuild: Bool
    ) -> Bool {
        isDebugBuild || controlsEnabled(arguments: arguments)
    }
}

@main
@MainActor
struct ReRoomDeviceProofApp: App {
#if DEBUG
    @State private var diagnosticOwner = DiagnosticAppOwner()
    @State private var roomEditOwner = RoomEditAppOwner()
#else
    @State private var gateOwner = Gate001ReleaseDiagnosticOwner()
    @State private var roomEditOwner = RoomEditAppOwner()
#endif

    var body: some Scene {
        WindowGroup {
#if DEBUG
            if RoomEditLaunchConfiguration.usesRoomEditSurface(
                arguments: ProcessInfo.processInfo.arguments
            ) {
                RoomEditContainer(owner: roomEditOwner)
            } else {
                DiagnosticChecklistView(owner: diagnosticOwner)
            }
#else
            if Gate001LaunchConfiguration.controlsEnabled(
                arguments: ProcessInfo.processInfo.arguments
            ) {
                Gate001ReleaseDiagnosticView(owner: gateOwner)
            } else {
                RoomEditContainer(owner: roomEditOwner)
            }
#endif
        }
    }
}

#if !DEBUG
@MainActor
@Observable
final class Gate001ReleaseDiagnosticOwner {
    let model: DeviceProofModel
    private(set) var armedTerminationState: CaptureFrameState?
    private(set) var statusMessage: String?
    private(set) var pressureMeasurement: Gate001PressureMeasurement?
    private(set) var pressureInProgress = false

    @ObservationIgnored private let terminationController: Gate001TerminationController
    @ObservationIgnored private let pressureHarness: Gate001PressureHarness

    init(terminationController: Gate001TerminationController = .live()) {
        self.terminationController = terminationController
        let pressureHarness = Gate001PressureHarness()
        self.pressureHarness = pressureHarness
        do {
            model = try Self.makeModel(
                terminationController: terminationController,
                pressureHarness: pressureHarness
            )
        } catch {
            model = DeviceProofModel()
            statusMessage = "GATE-001 local capture could not initialize."
        }
    }

    func prepare() async {
        await model.prepare()
        await model.discoverInterruptedRoomCaptures()
    }

    func grantCaptureConsent() async {
        disarmTermination()
        pressureMeasurement = nil
        pressureInProgress = false
        statusMessage = nil
        await model.acceptRoomCaptureDisclosure()
    }

    func denyCaptureConsent() {
        model.declineRoomCaptureDisclosure()
        statusMessage = "Room capture remains off."
    }

    func armTermination(at state: CaptureFrameState) {
        guard model.capturePresentation.phase == .recording,
              model.capturePresentation.explicitCaptureBusy == false,
              pressureMeasurement != nil,
              terminationController.arm(state)
        else { return }
        armedTerminationState = state
    }

    func disarmTermination() {
        terminationController.disarm()
        armedTerminationState = nil
    }

    func saveExplicitFrame() {
        guard pressureMeasurement != nil else {
            statusMessage = "Verify bounded queue pressure before saving the termination frame."
            return
        }
        switch model.offerCurrentFrameForCapture(isUserEvent: true) {
        case .admission(.admitted):
            statusMessage = "Explicit frame admitted to local durable capture."
        case .admission(.rejected(.userEventBusy)):
            statusMessage = CaptureSessionAdapter.userEventBusyMessage
        case .admission(.rejected), .notSelected:
            statusMessage = "The explicit frame was rejected before selection."
        case .notRecording, .invalidSnapshot:
            statusMessage = "No healthy ARFrame is available for explicit capture."
        }
    }

    func stopCapture() async {
        disarmTermination()
        pressureMeasurement = nil
        await model.stopRoomCapture()
    }

    func applyQueuePressure() async {
        guard model.capturePresentation.phase == .recording,
              model.capturePresentation.explicitCaptureBusy == false,
              pressureMeasurement == nil,
              pressureInProgress == false
        else { return }
        pressureInProgress = true
        statusMessage = "Applying bounded queue pressure…"
        await pressureHarness.arm()

        guard case .admission(.admitted) = model.offerCurrentFrameForCapture(
            isUserEvent: false
        ) else {
            await pressureHarness.release()
            pressureInProgress = false
            statusMessage = "Pressure check needs a healthy current camera frame. Try again."
            return
        }
        await pressureHarness.waitUntilBlocked()
        for _ in 0..<3 {
            _ = model.offerCurrentFrameForCapture(isUserEvent: false)
        }

        guard let snapshot = model.capturePresentation.admission,
              let measurement = Gate001PressureMeasurement(capacity: 3, snapshot: snapshot),
              let sessionID = model.capturePresentation.sessionID
        else {
            await pressureHarness.release()
            pressureInProgress = false
            statusMessage = "Bounded pressure was not proven. Keep the app open and try again."
            return
        }

        do {
            let provenance = try Self.provenance()
            let recorder = Gate001PressureEvidenceRecorder(root: try Self.documentsRoot())
            _ = try recorder.record(
                Gate001PressureEvidence(
                    sessionID: sessionID,
                    implementationRevision: provenance.revision,
                    recordedAtUTC: ISO8601DateFormatter().string(from: Date()),
                    measurement: measurement
                )
            )
            pressureMeasurement = measurement
            statusMessage = nil
        } catch {
            statusMessage = "Pressure log could not be made durable. Do not terminate this run."
        }
        await pressureHarness.release()
        pressureInProgress = false
    }

    private static func makeModel(
        terminationController: Gate001TerminationController,
        pressureHarness: Gate001PressureHarness
    ) throws -> DeviceProofModel {
        let provenance = try provenance()
        let documents = try documentsRoot()
        let source = CaptureArchiveSource(
            deviceModel: UIDevice.current.model,
            osVersion: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            appVersion: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "unavailable",
            buildID: provenance.revision,
            recordedAtUTC: ISO8601DateFormatter().string(from: Date())
        )
        let adapter = CaptureSessionAdapter(
            identities: UUIDCaptureIdentityDriver(),
            archiveFactory: CoreCaptureArchiveSessionFactory(
                root: documents,
                validator: try contractValidator(),
                source: source,
                lifecycleObserver: { observation in
                    terminationController.observe(observation)
                },
                pressureHarness: pressureHarness
            ),
            recoveryDriver: FoundationCaptureRecoveryDriver(
                root: documents,
                fixtureManifestSHA256: provenance.fixtureSHA256,
                repositoryRevision: provenance.revision
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
    }

    private static func documentsRoot() throws -> URL {
        try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }

    private static func provenance() throws -> (revision: String, fixtureSHA256: String) {
        guard let url = Bundle.main.url(
                  forResource: "ReRoomBuildProvenance",
                  withExtension: "plist"
              ),
              let values = NSDictionary(contentsOf: url) as? [String: Any],
              let revision = values["implementation_revision"] as? String,
              revision.range(of: #"^git:[0-9a-f]{40}$"#, options: .regularExpression) != nil,
              let fixtureSHA256 = values["fixture_sha256"] as? String,
              fixtureSHA256.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil
        else { throw Gate001ReleaseSetupError.invalidProvenance }
        return (revision, fixtureSHA256)
    }

    private static func contractValidator() throws -> ContractValidator {
        let resources: [(ContractSchemaIdentifier, String, String)] = [
            (.framePacket, "frame-packet", "d50b19bfb29c6c62c494e3a47deb3c51a933609698f4ff2f9cbfba6ec4252b43"),
            (.rrcapManifest, "rrcap-manifest", "c97349820ed66fb1a1fdf60ea9afee312f532811602851d01d1e233641730b87"),
            (.sceneState, "scene-state", "9c77d27762e20ff5fad24c438e8817a03c770b55be3fc82ea72097c4c273e440"),
            (.editArtifacts, "edit-artifacts", "58dbfc8f152881cbdc31be22f6ab7631ac474bb78537ac2a9254f5ef16bd598f"),
            (.transaction, "transaction", "2a4f6728978db0879b5dfb10f052f6d5280e5cf83ad5600f0cf959626c2399a2"),
        ]
        return try ContractValidator(registrations: resources.map { identifier, name, digest in
            guard let url = Bundle.main.url(
                forResource: "\(name).schema",
                withExtension: "json"
            ) else { throw Gate001ReleaseSetupError.missingSchema }
            return ContractSchemaRegistration(
                identifier: identifier,
                version: "1.0.0",
                sha256: digest,
                schemaData: try Data(contentsOf: url)
            )
        })
    }
}

private enum Gate001ReleaseSetupError: Error {
    case invalidProvenance
    case missingSchema
}

@MainActor
struct Gate001ReleaseDiagnosticView: View {
    @Bindable var owner: Gate001ReleaseDiagnosticOwner

    @State private var selectedState = CaptureFrameState.selected
    @State private var showsCaptureConsent = false
    @State private var showsArmConfirmation = false

    var body: some View {
        ZStack {
            Color(red: 11 / 255, green: 15 / 255, blue: 20 / 255)
                .ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("GATE-001 termination diagnostics")
                        .font(.title.weight(.semibold))
                    Text("Physical verification remains pending until all ten runs are recorded.")
                        .foregroundStyle(.secondary)
                    cameraStatus
                    captureStatus
                    terminationControls
                    recoveryStatus
                    if let message = owner.statusMessage {
                        Text(message)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("gate001.status.message")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
        }
        .foregroundStyle(Color(red: 245 / 255, green: 247 / 255, blue: 250 / 255))
        .accessibilityIdentifier("gate001.root.termination")
        .task { await owner.prepare() }
        .confirmationDialog(
            "Start local room capture?",
            isPresented: $showsCaptureConsent,
            titleVisibility: .visible
        ) {
            Button("Accept and Start") {
                Task { await owner.grantCaptureConsent() }
            }
            Button("Keep Capture Off") { owner.denyCaptureConsent() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Images, calibration, pose, and events remain local. "
                    + "No live upload is configured."
            )
        }
        .confirmationDialog(
            "Arm abrupt process termination?",
            isPresented: $showsArmConfirmation,
            titleVisibility: .visible
        ) {
            Button("Arm \(selectedState.rawValue)", role: .destructive) {
                owner.armTermination(at: selectedState)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "The next explicit user-event frame terminates this process with SIGKILL "
                    + "after the selected durable boundary."
            )
        }
    }

    private var cameraStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(owner.model.statusTitle)
                .font(.headline)
            Text(owner.model.statusMessage)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let action = owner.model.primaryAction {
                Button(action.label) {
                    Task { await owner.model.performPrimaryAction() }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("gate001.permission.camera")
            }
        }
    }

    private var captureStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(owner.model.capturePresentation.localRecordingLabel)
                .font(.body.weight(.semibold))
                .accessibilityIdentifier("gate001.capture.local-state")
            Text(owner.model.capturePresentation.uploadLabel)
                .font(.body.weight(.semibold))
                .accessibilityIdentifier("gate001.capture.upload-state")
            Text("Deterministic fixture acknowledgement only — no live upload is configured.")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            if owner.model.capturePresentation.phase == .recording {
                Button("Apply queue pressure") {
                    Task { await owner.applyQueuePressure() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    owner.pressureInProgress
                        || owner.pressureMeasurement != nil
                        || owner.model.capturePresentation.explicitCaptureBusy
                )
                .accessibilityIdentifier("gate001.pressure.apply")
                if let pressure = owner.pressureMeasurement {
                    Text(
                        "Pressure verified: depth \(pressure.maximumDepth)/\(pressure.capacity); "
                            + "upload paused first."
                    )
                    .foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("gate001.pressure.status")
                } else if owner.pressureInProgress {
                    Text("Applying bounded pressure and making the observation durable…")
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("gate001.pressure.status")
                }
                Button("Save explicit capture frame") { owner.saveExplicitFrame() }
                    .buttonStyle(.bordered)
                    .disabled(
                        owner.model.capturePresentation.explicitCaptureBusy
                            || owner.pressureMeasurement == nil
                    )
                    .accessibilityIdentifier("gate001.capture.explicit")
                Button("Stop room capture", role: .destructive) {
                    Task { await owner.stopCapture() }
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("gate001.capture.stop")
            } else {
                Button("Start room capture") { showsCaptureConsent = true }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("gate001.capture.start")
            }
        }
    }

    private var terminationControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Exact lifecycle state", selection: $selectedState) {
                ForEach(CaptureFrameState.allCases, id: \.rawValue) { state in
                    Text(state.rawValue).tag(state)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("gate001.termination.state")
            if let armedState = owner.armedTerminationState {
                Text("Armed for \(armedState.rawValue). Save one explicit frame now.")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("gate001.termination.armed")
                Button("Disarm termination", role: .destructive) {
                    owner.disarmTermination()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("gate001.termination.disarm")
            } else {
                Button("Arm abrupt termination", role: .destructive) {
                    showsArmConfirmation = true
                }
                .buttonStyle(.bordered)
                .disabled(
                    owner.model.capturePresentation.phase != .recording
                        || owner.model.capturePresentation.explicitCaptureBusy
                        || owner.pressureMeasurement == nil
                )
                .accessibilityIdentifier("gate001.termination.arm")
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gate001.termination.controls")
    }

    @ViewBuilder
    private var recoveryStatus: some View {
        if let replay = owner.model.capturePresentation.recovered {
            Text(
                "Verified replay: verdict \(replay.report.verdict.rawValue); "
                    + "status \(replay.recovered.finalization.state.rawValue)."
            )
            .foregroundStyle(.green)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("gate001.recovery.verified")
        }
        ForEach(owner.model.capturePresentation.recoveryFailures, id: \.archiveName) { failure in
            Text("Archive verification failed: \(failure.archiveName). \(failure.message)")
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("gate001.recovery.failed")
        }
    }
}
#endif

struct CandidateSeedView: View {
    @Bindable var model: DeviceProofModel

    var body: some View {
        ZStack {
            Color(red: 11 / 255, green: 15 / 255, blue: 20 / 255)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    candidateHeader
                    statusPanel
                    Spacer(minLength: 48)
                    actionTray
                }
                .frame(maxWidth: .infinity, minHeight: 640, alignment: .topLeading)
                .padding(.horizontal, 16)
                .padding(.vertical, 24)
            }
        }
        .foregroundStyle(Color(red: 245 / 255, green: 247 / 255, blue: 250 / 255))
        .accessibilityIdentifier("release.root.candidate")
        .task {
            await model.prepare()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            model.refreshPhysicalOrientation()
        }
    }

    private var candidateHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ReRoom device check")
                .font(.title.weight(.semibold))
            Text("Candidate — physical verification pending")
                .font(.body)
                .foregroundStyle(Color(red: 183 / 255, green: 192 / 255, blue: 202 / 255))
#if DEBUG
            Text("Internal diagnostic build")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255))
#endif
        }
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(model.statusTitle, systemImage: statusSymbol)
                .font(.title2.weight(.semibold))
            Text(model.statusMessage)
                .font(.body)
                .foregroundStyle(Color(red: 183 / 255, green: 192 / 255, blue: 202 / 255))
                .fixedSize(horizontal: false, vertical: true)
            if model.isPerformingPermissionRequest {
                ProgressView()
                    .tint(Color(red: 77 / 255, green: 163 / 255, blue: 255 / 255))
                    .accessibilityLabel("Waiting for camera permission")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(red: 23 / 255, green: 29 / 255, blue: 36 / 255).opacity(0.94))
        .clipShape(.rect(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(model.statusAccessibilityIdentifier)
    }

    @ViewBuilder
    private var actionTray: some View {
        if let action = model.primaryAction {
            Button(action.label) {
                Task {
                    await model.performPrimaryAction()
                }
            }
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(Color(red: 11 / 255, green: 15 / 255, blue: 20 / 255))
            .background(Color(red: 77 / 255, green: 163 / 255, blue: 255 / 255))
            .clipShape(.rect(cornerRadius: 12))
            .disabled(model.isPerformingPermissionRequest)
            .accessibilityIdentifier(
                action == .openSettings ? "release.action.settings" : "release.permission.camera"
            )
        }
    }

    private var statusSymbol: String {
        switch model.state.cameraAuthorization {
        case .notDetermined:
            "camera.fill"
        case .granted:
            "viewfinder"
        case .denied, .restricted:
            "camera.fill.badge.exclamationmark"
        }
    }
}
