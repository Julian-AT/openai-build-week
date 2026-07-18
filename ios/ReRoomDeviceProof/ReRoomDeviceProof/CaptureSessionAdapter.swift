import ARKit
import Darwin
import Foundation
import os
import ReRoomContracts
import ReRoomCaptureCore
import UIKit

final class Gate001TerminationController: @unchecked Sendable {
    private let state = OSAllocatedUnfairLock<CaptureFrameState?>(initialState: nil)
    private let terminate: @Sendable () -> Void

    init(terminate: @escaping @Sendable () -> Void) {
        self.terminate = terminate
    }

    static func live() -> Gate001TerminationController {
        Gate001TerminationController {
            _ = Darwin.kill(Darwin.getpid(), SIGKILL)
        }
    }

    var armedState: CaptureFrameState? {
        state.withLock { $0 }
    }

    @discardableResult
    func arm(_ lifecycleState: CaptureFrameState) -> Bool {
        state.withLock { armedState in
            guard armedState == nil else { return false }
            armedState = lifecycleState
            return true
        }
    }

    func disarm() {
        state.withLock { $0 = nil }
    }

    func observe(_ observation: CaptureLifecycleObservation) {
        let shouldTerminate = state.withLock { armedState in
            guard observation.selectedReason == .userEvent,
                  observation.state == armedState
            else { return false }
            armedState = nil
            return true
        }
        if shouldTerminate { terminate() }
    }
}

enum CaptureSessionPhase: String, Equatable, Sendable {
    case idle
    case declined
    case recording
    case finalizing
    case finalized
    case recovered
    case interrupted
    case failed
}

enum CaptureUploadState: String, Equatable, Sendable {
    case notConfigured
    case ready
    case paused
}

enum CaptureShareState: String, Equatable, Sendable {
    case notShared
    case shared
}

struct VerifiedCaptureReplay: Equatable, Sendable {
    let recovered: RecoveredArchive
    let report: ReplayReportV1
    let timeline: [ReplayTimelineEntry]
}

struct CaptureRecoveryFailureSnapshot: Equatable, Sendable {
    let archiveName: String
    let message: String
}

struct CaptureRecoveryDiscoverySnapshot: Equatable, Sendable {
    let verified: [VerifiedCaptureReplay]
    let failures: [CaptureRecoveryFailureSnapshot]

    static let empty = CaptureRecoveryDiscoverySnapshot(verified: [], failures: [])
}

enum VerifiedReplayInspectorError: Error, Equatable, Sendable {
    case invalidVerifiedReplay
    case unverifiedSelection
}

struct VerifiedReplayInspector: Equatable, Sendable {
    let recovered: RecoveredArchive
    let report: ReplayReportV1
    let timeline: [ReplayTimelineEntry]

    var status: CaptureFinalizationState { recovered.finalization.state }
    var digests: ReplayDigestSet { report.digests }

    init(replay: VerifiedCaptureReplay) throws {
        let finalization = replay.recovered.finalization
        guard replay.report.verdict == .accept,
              replay.report.rejection == nil,
              replay.report.archive.manifestSHA256 == finalization.manifestSHA256,
              replay.report.archive.finalizationState == finalization.state,
              replay.report.archive.acceptedFrameCount == finalization.acceptedFrameCount,
              replay.report.archive.eventCount == finalization.eventCount,
              replay.report.archive.journalRecordCount == UInt64(replay.timeline.count),
              replay.timeline.indices.allSatisfy({
                  replay.timeline[$0].journalSequence == UInt64($0)
              })
        else { throw VerifiedReplayInspectorError.invalidVerifiedReplay }
        recovered = replay.recovered
        report = replay.report
        timeline = replay.timeline
    }

    func entry(journalSequence: UInt64) throws -> ReplayTimelineEntry {
        guard journalSequence < UInt64(timeline.count),
              timeline[Int(journalSequence)].journalSequence == journalSequence
        else { throw VerifiedReplayInspectorError.unverifiedSelection }
        return timeline[Int(journalSequence)]
    }
}

struct CapturePresentationSnapshot: Equatable, Sendable {
    var phase: CaptureSessionPhase
    var sessionID: String?
    var admission: CaptureAdmissionSnapshot?
    var finalization: CaptureFinalization?
    var recovered: VerifiedCaptureReplay?
    var recoveryFailures: [CaptureRecoveryFailureSnapshot]
    var explicitCaptureBusy: Bool
    var busyMessage: String?
    var uploadState: CaptureUploadState
    var isOffline: Bool
    var shareState: CaptureShareState
    var failureMessage: String?

    static let idle = CapturePresentationSnapshot(
        phase: .idle,
        sessionID: nil,
        admission: nil,
        finalization: nil,
        recovered: nil,
        recoveryFailures: [],
        explicitCaptureBusy: false,
        busyMessage: nil,
        uploadState: .notConfigured,
        isOffline: false,
        shareState: .notShared,
        failureMessage: nil
    )

    var localRecordingLabel: String {
        phase == .recording ? "Recording locally" : "Local recording stopped"
    }

    var uploadLabel: String {
        if isOffline { return "Offline — no upload connection" }
        return switch uploadState {
        case .notConfigured: "Upload not configured"
        case .ready: "Upload ready"
        case .paused: "Capture continues locally — upload paused"
        }
    }

    var shareLabel: String {
        shareState == .shared ? "Shared" : "Not shared"
    }
}

enum CaptureFrameOfferResult: Equatable, Sendable {
    case notRecording
    case invalidSnapshot
    case notSelected(FrameSelectionRejectionReason)
    case admission(CaptureAdmissionDisposition)
}

@MainActor
protocol CaptureIdentityDriving: AnyObject {
    func makeSessionID() -> String
    func makeWorldFrameID() -> String
    func makeSubmapID() -> String
    func makeFrameID(candidateID: String) -> String
    func makeIdempotencyKey(candidateID: String) -> String
    func makeArchivePath(sessionID: String) -> String
    func monotonicTimestampNanoseconds() -> UInt64
}

protocol CaptureArchiveSessionWriting: Sendable {
    func startSession(authorization: CaptureSessionAuthorization) async throws
    func publishSelectedFrame(
        _ candidate: SelectedFrameCandidate,
        profile: FramePacketEncodingProfile
    ) async throws -> NetworkEligibleReceipt
    func recordAcknowledgement(for receipt: NetworkEligibleReceipt) async throws
    func finalizeExplicitly() async throws -> CaptureFinalization
}

protocol CaptureArchiveSessionFactory: Sendable {
    func makeSession(
        descriptor: CaptureSessionDescriptor
    ) async throws -> any CaptureArchiveSessionWriting
}

protocol CaptureRecoveryDriving: Sendable {
    func discoverArchives() async -> CaptureRecoveryDiscoverySnapshot
    func recoverInterruptedArchive(at archivePath: String) async -> VerifiedCaptureReplay?
}

protocol CaptureStorageDriving: Sendable {
    var isAvailable: Bool { get }
}

@MainActor
protocol CaptureBackgroundDriving: AnyObject {
    func begin(expiration: @escaping @MainActor @Sendable () -> Void) -> Int
    func end(_ identifier: Int)
}

@MainActor
protocol CaptureARFrameSnapshotting: Sendable {
    func capture(
        frame: ARFrame,
        orientation: CaptureInterfaceOrientation,
        codec: String
    ) throws -> CapturedFrameSnapshot
}

@MainActor
struct NativeCaptureARFrameSnapshotter: CaptureARFrameSnapshotting {
    private let adapter = ARFrameCaptureAdapter()

    func capture(
        frame: ARFrame,
        orientation: CaptureInterfaceOrientation,
        codec: String
    ) throws -> CapturedFrameSnapshot {
        try adapter.capture(frame: frame, orientation: orientation, codec: codec)
    }
}

@MainActor
final class UUIDCaptureIdentityDriver: CaptureIdentityDriving {
    func makeSessionID() -> String { "session_\(UUID().uuidString.lowercased())" }
    func makeWorldFrameID() -> String { "world_\(UUID().uuidString.lowercased())" }
    func makeSubmapID() -> String { "submap_\(UUID().uuidString.lowercased())" }
    func makeFrameID(candidateID: String) -> String { "frame_\(UUID().uuidString.lowercased())" }
    func makeIdempotencyKey(candidateID: String) -> String {
        "frameidem_\(UUID().uuidString.lowercased())"
    }
    func makeArchivePath(sessionID: String) -> String {
        "diagnostic-captures/\(sessionID).rrcap"
    }
    func monotonicTimestampNanoseconds() -> UInt64 {
        UInt64(max(1, (ProcessInfo.processInfo.systemUptime * 1_000_000_000).rounded()))
    }
}

struct CaptureStorageState: CaptureStorageDriving, Sendable {
    private let state: OSAllocatedUnfairLock<Bool>

    init(isAvailable: Bool = true) {
        state = OSAllocatedUnfairLock(initialState: isAvailable)
    }

    var isAvailable: Bool { state.withLock { $0 } }

    func update(isAvailable: Bool) {
        state.withLock { $0 = isAvailable }
    }
}

@MainActor
final class UIApplicationCaptureBackgroundDriver: CaptureBackgroundDriving {
    func begin(expiration: @escaping @MainActor @Sendable () -> Void) -> Int {
        let identifier = UIApplication.shared.beginBackgroundTask(
            withName: "ReRoom capture finalization",
            expirationHandler: expiration
        )
        return identifier.rawValue
    }

    func end(_ identifier: Int) {
        let value = UIBackgroundTaskIdentifier(rawValue: identifier)
        guard value != .invalid else { return }
        UIApplication.shared.endBackgroundTask(value)
    }
}

struct CoreCaptureArchiveSession: CaptureArchiveSessionWriting, Sendable {
    let store: CaptureArchiveStore
    let transport: CaptureTransport
    let pressureHarness: Gate001PressureHarness?

    func startSession(authorization: CaptureSessionAuthorization) async throws {
        _ = try await store.startSession(authorization: authorization)
    }

    func publishSelectedFrame(
        _ candidate: SelectedFrameCandidate,
        profile: FramePacketEncodingProfile
    ) async throws -> NetworkEligibleReceipt {
        await pressureHarness?.beforePublish(selectedReason: candidate.selectedReason)
        return try await store.publishSelectedFrame(candidate, profile: profile)
    }

    func recordAcknowledgement(for receipt: NetworkEligibleReceipt) async throws {
        try await store.recordAcknowledgement(transport.acknowledgement(for: receipt))
    }

    func finalizeExplicitly() async throws -> CaptureFinalization {
        try await store.finalizeExplicitly()
    }
}

struct CoreCaptureArchiveSessionFactory: CaptureArchiveSessionFactory, Sendable {
    let root: URL
    let validator: ContractValidator
    let source: CaptureArchiveSource
    let lifecycleObserver: CaptureLifecycleObserver
    let pressureHarness: Gate001PressureHarness?

    init(
        root: URL,
        validator: ContractValidator,
        source: CaptureArchiveSource,
        lifecycleObserver: @escaping CaptureLifecycleObserver = { _ in },
        pressureHarness: Gate001PressureHarness? = nil
    ) {
        self.root = root
        self.validator = validator
        self.source = source
        self.lifecycleObserver = lifecycleObserver
        self.pressureHarness = pressureHarness
    }

    func makeSession(
        descriptor: CaptureSessionDescriptor
    ) async throws -> any CaptureArchiveSessionWriting {
        let fileSystem = try ReRoomCaptureCore.FoundationCaptureFileSystem(root: root)
        let store = CaptureArchiveStore(
            fileSystem: fileSystem,
            encoder: FramePacketEncoder(
                validator: validator,
                profile: .syntheticOnePixelPNG
            ),
            descriptor: descriptor,
            source: source,
            lifecycleObserver: lifecycleObserver
        )
        return CoreCaptureArchiveSession(
            store: store,
            transport: try CaptureTransport(
                gatewayID: "gateway_00000000-0000-4000-8000-000000000001"
            ),
            pressureHarness: pressureHarness
        )
    }
}

struct FoundationCaptureRecoveryDriver: CaptureRecoveryDriving, Sendable {
    let root: URL
    let fixtureManifestSHA256: String
    let repositoryRevision: String

    func discoverArchives() async -> CaptureRecoveryDiscoverySnapshot {
        scanArchives()
    }

    private func scanArchives() -> CaptureRecoveryDiscoverySnapshot {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return .empty }
        var urls = [URL]()
        for case let url as URL in enumerator where url.lastPathComponent.hasSuffix(".rrcap") {
            urls.append(url)
        }
        var verified = [VerifiedCaptureReplay]()
        var failures = [CaptureRecoveryFailureSnapshot]()
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            do {
                verified.append(try verifiedReplay(at: url))
            } catch {
                failures.append(
                    CaptureRecoveryFailureSnapshot(
                        archiveName: url.lastPathComponent,
                        message: "Integrity verification failed; no archive records were exposed."
                    )
                )
            }
        }
        return CaptureRecoveryDiscoverySnapshot(verified: verified, failures: failures)
    }

    func recoverInterruptedArchive(at archivePath: String) async -> VerifiedCaptureReplay? {
        try? verifiedReplay(at: root.appendingPathComponent(archivePath))
    }

    private func verifiedReplay(at sourceURL: URL) throws -> VerifiedCaptureReplay {
        let recovered = try CaptureRecovery.inspect(root: sourceURL)
        let replayURL = sourceURL.deletingLastPathComponent()
            .appendingPathComponent(recovered.finalization.archivePath)
        let snapshot = try ReplayCore.replay(root: replayURL)
        let report = try ReplayReport.make(
            snapshot: snapshot,
            caseID: recovered.finalization.sessionID,
            fixtureManifestSHA256: fixtureManifestSHA256,
            repositoryRevision: repositoryRevision
        )
        return VerifiedCaptureReplay(
            recovered: recovered,
            report: report,
            timeline: snapshot.timeline
        )
    }
}

struct EmptyCaptureRecoveryDriver: CaptureRecoveryDriving, Sendable {
    func discoverArchives() async -> CaptureRecoveryDiscoverySnapshot { .empty }
    func recoverInterruptedArchive(at archivePath: String) async -> VerifiedCaptureReplay? { nil }
}

@MainActor
final class CaptureSessionAdapter {
    static let userEventBusyMessage = "Saving this capture frame — try again when ready."

    private let identities: any CaptureIdentityDriving
    private let archiveFactory: any CaptureArchiveSessionFactory
    private let recoveryDriver: any CaptureRecoveryDriving
    private let storageDriver: any CaptureStorageDriving
    private let backgroundDriver: any CaptureBackgroundDriving
    private let frameSnapshotter: any CaptureARFrameSnapshotting
    private let selectorPolicy: FrameSelectionPolicy
    private let pressurePolicy: CapturePressurePolicy

    private var gate: CaptureAdmissionGate?
    private var payloads: CapturePayloadStore?
    private var archive: (any CaptureArchiveSessionWriting)?
    private var descriptor: CaptureSessionDescriptor?
    private var submapID: String?
    private var previousSelectedTimestampNanoseconds: UInt64?
    private var consumerTask: Task<CaptureConsumerOutcome, Never>?
    private var backgroundAssertionID: Int?
    private var backgroundExpired = false

    private(set) var presentation: CapturePresentationSnapshot = .idle
    var onPresentationChange: (@MainActor (CapturePresentationSnapshot) -> Void)?

    init(
        identities: any CaptureIdentityDriving,
        archiveFactory: any CaptureArchiveSessionFactory,
        recoveryDriver: any CaptureRecoveryDriving,
        storageDriver: any CaptureStorageDriving,
        backgroundDriver: any CaptureBackgroundDriving,
        selectorPolicy: FrameSelectionPolicy,
        pressurePolicy: CapturePressurePolicy,
        frameSnapshotter: any CaptureARFrameSnapshotting = NativeCaptureARFrameSnapshotter()
    ) {
        self.identities = identities
        self.archiveFactory = archiveFactory
        self.recoveryDriver = recoveryDriver
        self.storageDriver = storageDriver
        self.backgroundDriver = backgroundDriver
        self.selectorPolicy = selectorPolicy
        self.pressurePolicy = pressurePolicy
        self.frameSnapshotter = frameSnapshotter
    }

    func declineDisclosure() {
        defer { notifyPresentationChange() }
        guard presentation.phase != .recording else { return }
        presentation = .idle
        presentation.phase = .declined
        presentation.failureMessage = "Room capture remains off. You can start again when ready."
    }

    func acceptDisclosure() async {
        defer { notifyPresentationChange() }
        guard presentation.phase != .recording,
              consumerTask == nil
        else { return }

        do {
            let sessionID = identities.makeSessionID()
            let startedAt = identities.monotonicTimestampNanoseconds()
            let nextDescriptor = try CaptureSessionDescriptor(
                sessionID: sessionID,
                archivePath: identities.makeArchivePath(sessionID: sessionID),
                worldFrameID: identities.makeWorldFrameID(),
                startedAtMonotonicNanoseconds: String(startedAt)
            )
            let authorization = try CaptureSessionAuthorization(
                sessionID: sessionID,
                consentGranted: true,
                retentionPolicy: .localOnlyUntilShare
            )
            let nextArchive = try await archiveFactory.makeSession(descriptor: nextDescriptor)
            try await nextArchive.startSession(authorization: authorization)

            let nextGate = CaptureAdmissionGate(pressurePolicy: pressurePolicy)
            let nextPayloads = CapturePayloadStore()
            let nextSubmapID = identities.makeSubmapID()
            gate = nextGate
            payloads = nextPayloads
            archive = nextArchive
            descriptor = nextDescriptor
            submapID = nextSubmapID
            previousSelectedTimestampNanoseconds = nil

            presentation = .idle
            presentation.phase = .recording
            presentation.sessionID = sessionID
            presentation.admission = nextGate.snapshot()

            consumerTask = Task { @concurrent [
                weak self,
                nextGate,
                nextPayloads,
                nextArchive,
                nextDescriptor,
                nextSubmapID,
                recoveryDriver
            ] in
                let outcome: CaptureConsumerOutcome
                do {
                    let finalSnapshot = try await nextGate.runConsumer(
                        writer: { admitted in
                            guard let payload = nextPayloads.take(
                                candidateID: admitted.candidate.candidateID
                            ) else {
                                throw CaptureAdapterError.missingPayload
                            }
                            let candidate = try Self.selectedCandidate(
                                admitted: admitted,
                                payload: payload,
                                descriptor: nextDescriptor,
                                submapID: nextSubmapID
                            )
                            let receipt = try await nextArchive.publishSelectedFrame(
                                candidate,
                                profile: payload.profile
                            )
                            try await nextArchive.recordAcknowledgement(for: receipt)
                        },
                        onTerminal: { [weak self] result in
                            await self?.recordTerminal(result)
                        }
                    )
                    outcome = .drained(finalSnapshot)
                } catch {
                    let recovered = await recoveryDriver.recoverInterruptedArchive(
                        at: nextDescriptor.archivePath
                    )
                    outcome = .failed(
                        nextGate.snapshot(),
                        recovered,
                        String(describing: error)
                    )
                }
                await self?.recordConsumerOutcome(outcome)
                return outcome
            }
        } catch {
            presentation = .idle
            presentation.phase = .failed
            presentation.failureMessage = "Capture could not start: \(error)"
        }
    }

    /// Native AR callback boundary. This method is synchronous and never waits on archive work.
    func offerARFrame(
        _ frame: ARFrame,
        orientation: CaptureInterfaceOrientation,
        motionScore: Float,
        blurScore: Float,
        exposureScore: Float,
        viewNovelty: Float,
        isKeyframe: Bool,
        isUserEvent: Bool
    ) -> CaptureFrameOfferResult {
        do {
            let snapshot = try frameSnapshotter.capture(
                frame: frame,
                orientation: orientation,
                codec: "jpeg"
            )
            guard let timestamp = UInt64(snapshot.id) else { return .invalidSnapshot }
            return offerCapturedFrame(
                snapshot,
                selectionInput: FrameSelectionInput(
                    monotonicTimestampNanoseconds: timestamp,
                    previousSelectedTimestampNanoseconds: previousSelectedTimestampNanoseconds,
                    viewNovelty: viewNovelty,
                    motionScore: motionScore,
                    blurScore: blurScore,
                    exposureScore: exposureScore,
                    isKeyframe: isKeyframe,
                    isUserEvent: isUserEvent
                )
            )
        } catch {
            return .invalidSnapshot
        }
    }

    func offerCapturedFrame(
        _ snapshot: CapturedFrameSnapshot,
        selectionInput: FrameSelectionInput
    ) -> CaptureFrameOfferResult {
        defer { notifyPresentationChange() }
        guard presentation.phase == .recording,
              let gate,
              let payloads
        else { return .notRecording }
        guard UInt64(snapshot.id) == selectionInput.monotonicTimestampNanoseconds else {
            return .invalidSnapshot
        }

        let candidateID = identities.makeFrameID(candidateID: snapshot.id)
        guard let candidate = selectorPolicy.admissionCandidate(
            candidateID: candidateID,
            input: selectionInput
        ) else {
            guard case let .rejected(reason) = selectorPolicy.evaluate(selectionInput) else {
                return .invalidSnapshot
            }
            return .notSelected(reason)
        }
        let profile: FramePacketEncodingProfile
        do {
            profile = try Self.encodingProfile(snapshot: snapshot, input: selectionInput)
        } catch {
            return .invalidSnapshot
        }

        if storageDriver.isAvailable == false {
            let close = gate.close(
                reason: .storageUnavailable,
                mode: .abortQueuedBeforeSelection
            )
            applyCloseReport(close)
            presentation.phase = .failed
            presentation.failureMessage = "Local storage is unavailable; the durable prefix was preserved."
            consumerTask?.cancel()
            let rejected = gate.offer(candidate)
            presentation.admission = gate.snapshot()
            return .admission(rejected)
        }

        payloads.insert(
            CapturePendingPayload(
                candidateID: candidateID,
                snapshot: snapshot,
                profile: profile,
                idempotencyKey: identities.makeIdempotencyKey(candidateID: candidateID)
            )
        )
        let disposition = gate.offer(candidate)
        switch disposition {
        case .admitted:
            previousSelectedTimestampNanoseconds = selectionInput.monotonicTimestampNanoseconds
            if candidate.selectedReason == .userEvent {
                presentation.explicitCaptureBusy = true
            }
        case let .rejected(reason):
            payloads.remove(candidateID: candidateID)
            if reason == .userEventBusy {
                presentation.busyMessage = Self.userEventBusyMessage
            }
        }
        applyAdmissionSnapshot(gate.snapshot())
        return .admission(disposition)
    }

    func stop() async {
        defer { notifyPresentationChange() }
        guard let gate,
              let task = consumerTask,
              let archive
        else { return }
        presentation.phase = .finalizing
        let close = gate.close(reason: .gracefulStop, mode: .drainThenClose)
        applyCloseReport(close)
        let outcome = await task.value
        switch outcome {
        case .drained:
            do {
                presentation.finalization = try await archive.finalizeExplicitly()
                presentation.phase = .finalized
            } catch {
                presentation.phase = .failed
                presentation.failureMessage = "Capture finalization failed: \(error)"
            }
        case .failed:
            recordConsumerOutcome(outcome)
        }
        finishSessionOwnership()
    }

    func finalizeForInterruption() async {
        await finalizeForBackground()
    }

    func finalizeForBackground() async {
        defer { notifyPresentationChange() }
        guard gate != nil, consumerTask != nil, archive != nil else { return }
        backgroundExpired = false
        let identifier = backgroundDriver.begin { [weak self] in
            self?.expireBackgroundFinalization()
        }
        backgroundAssertionID = identifier
        defer { endBackgroundAssertion() }

        if backgroundExpired == false,
           let gate {
            presentation.phase = .finalizing
            applyCloseReport(gate.close(reason: .gracefulStop, mode: .drainThenClose))
        }
        guard let task = consumerTask else { return }
        let outcome = await task.value
        guard backgroundExpired == false else {
            presentation.phase = .interrupted
            finishSessionOwnership()
            return
        }
        guard case .drained = outcome,
              let archive
        else {
            finishSessionOwnership()
            return
        }
        do {
            presentation.finalization = try await archive.finalizeExplicitly()
            presentation.phase = .finalized
        } catch {
            presentation.phase = .interrupted
            presentation.failureMessage = "Background time ended before finalization completed."
        }
        finishSessionOwnership()
    }

    func discoverInterruptedArchives() async {
        defer { notifyPresentationChange() }
        let discovery = await recoveryDriver.discoverArchives()
        guard discovery.verified.isEmpty == false || discovery.failures.isEmpty == false else {
            return
        }
        presentation = .idle
        presentation.recoveryFailures = discovery.failures
        if let latest = discovery.verified.last {
            presentation.phase = .recovered
            presentation.sessionID = latest.recovered.finalization.sessionID
            presentation.recovered = latest
            presentation.finalization = latest.recovered.finalization
        } else {
            presentation.phase = .failed
            presentation.failureMessage = discovery.failures.last?.message
        }
    }

    func setOffline(_ offline: Bool) {
        presentation.isOffline = offline
        notifyPresentationChange()
    }

    private func expireBackgroundFinalization() {
        backgroundExpired = true
        guard let gate else { return }
        let close = gate.close(reason: .expiration, mode: .abortQueuedBeforeSelection)
        applyCloseReport(close)
        consumerTask?.cancel()
        presentation.phase = .interrupted
        presentation.failureMessage = "Background time expired; the durable prefix was preserved."
        notifyPresentationChange()
    }

    private func recordTerminal(_ result: CaptureAdmissionTerminalResult) {
        if result.admitted.candidate.selectedReason == .userEvent {
            presentation.explicitCaptureBusy = false
            presentation.busyMessage = nil
        }
        if let gate { applyAdmissionSnapshot(gate.snapshot()) }
        notifyPresentationChange()
    }

    private func recordConsumerOutcome(_ outcome: CaptureConsumerOutcome) {
        switch outcome {
        case let .drained(snapshot):
            applyAdmissionSnapshot(snapshot)
        case let .failed(snapshot, recovered, message):
            applyAdmissionSnapshot(snapshot)
            if let recovered {
                presentation.phase = .recovered
                presentation.recovered = recovered
                presentation.finalization = recovered.recovered.finalization
                presentation.failureMessage = "Recovered — capture may be incomplete"
            } else {
                presentation.phase = .failed
                presentation.failureMessage = "Capture storage failed: \(message)"
            }
        }
        notifyPresentationChange()
    }

    private func applyCloseReport(_ report: CaptureAdmissionCloseReport) {
        for terminal in report.terminatedBeforeSelection {
            payloads?.remove(candidateID: terminal.admitted.candidate.candidateID)
            if terminal.admitted.candidate.selectedReason == .userEvent {
                presentation.explicitCaptureBusy = false
                presentation.busyMessage = nil
            }
        }
        applyAdmissionSnapshot(report.snapshot)
    }

    private func applyAdmissionSnapshot(_ snapshot: CaptureAdmissionSnapshot) {
        presentation.admission = snapshot
        presentation.uploadState = snapshot.uploadPaused ? .paused : .notConfigured
    }

    private func finishSessionOwnership() {
        consumerTask = nil
        gate = nil
        payloads = nil
        archive = nil
        descriptor = nil
        submapID = nil
        previousSelectedTimestampNanoseconds = nil
        presentation.explicitCaptureBusy = false
        presentation.busyMessage = nil
    }

    private func endBackgroundAssertion() {
        guard let identifier = backgroundAssertionID else { return }
        backgroundAssertionID = nil
        backgroundDriver.end(identifier)
    }

    private func notifyPresentationChange() {
        onPresentationChange?(presentation)
    }

    nonisolated private static func selectedCandidate(
        admitted: AdmittedCaptureCandidate,
        payload: CapturePendingPayload,
        descriptor: CaptureSessionDescriptor,
        submapID: String
    ) throws -> SelectedFrameCandidate {
        let frameID = admitted.candidate.candidateID
        let extensionName = switch payload.snapshot.imageCodec {
        case "jpeg": "jpg"
        case "png": "png"
        case "hevc_intra": "heic"
        default: "bin"
        }
        return try SelectedFrameCandidate(
            sessionID: descriptor.sessionID,
            frameID: frameID,
            submapID: submapID,
            worldFrameID: descriptor.worldFrameID,
            worldFrameVersion: 1,
            captureSequence: admitted.admissionSequence,
            monotonicTimestampNanoseconds: String(
                admitted.candidate.monotonicTimestampNanoseconds
            ),
            imageRelativePath: "frames/\(frameID)/image.\(extensionName)",
            packetRelativePath: "frames/\(frameID)/packet.json",
            imageBytes: payload.snapshot.imageData,
            selectedReason: admitted.candidate.selectedReason,
            idempotencyKey: payload.idempotencyKey
        )
    }

    nonisolated private static func encodingProfile(
        snapshot: CapturedFrameSnapshot,
        input: FrameSelectionInput
    ) throws -> FramePacketEncodingProfile {
        try FramePacketEncodingProfile(
            codec: snapshot.imageCodec,
            width: snapshot.imageWidth,
            height: snapshot.imageHeight,
            colorSpace: snapshot.colorSpace,
            imageRange: snapshot.imageRange,
            cropInSensorPixels: [
                snapshot.cropInSensorPixels.x,
                snapshot.cropInSensorPixels.y,
                snapshot.cropInSensorPixels.width,
                snapshot.cropInSensorPixels.height,
            ],
            intrinsicsEncodedPixels: [
                snapshot.intrinsicsEncodedPixels.fx,
                snapshot.intrinsicsEncodedPixels.fy,
                snapshot.intrinsicsEncodedPixels.cx,
                snapshot.intrinsicsEncodedPixels.cy,
            ],
            encodedFromSensor: snapshot.encodedFromSensor,
            worldFromCamera: snapshot.worldFromCamera,
            trackingState: snapshot.trackingState,
            trackingReason: snapshot.trackingReason,
            motionScore: Double(input.motionScore),
            blurScore: Double(input.blurScore),
            exposureScore: Double(input.exposureScore)
        )
    }
}

private enum CaptureAdapterError: Error {
    case missingPayload
}

private enum CaptureConsumerOutcome: Sendable {
    case drained(CaptureAdmissionSnapshot)
    case failed(CaptureAdmissionSnapshot, VerifiedCaptureReplay?, String)
}

private struct CapturePendingPayload: Sendable {
    let candidateID: String
    let snapshot: CapturedFrameSnapshot
    let profile: FramePacketEncodingProfile
    let idempotencyKey: String
}

private final class CapturePayloadStore: Sendable {
    private let values = OSAllocatedUnfairLock(initialState: [String: CapturePendingPayload]())

    func insert(_ payload: CapturePendingPayload) {
        values.withLock { $0[payload.candidateID] = payload }
    }

    func take(candidateID: String) -> CapturePendingPayload? {
        values.withLock { $0.removeValue(forKey: candidateID) }
    }

    func remove(candidateID: String) {
        values.withLock { _ = $0.removeValue(forKey: candidateID) }
    }
}
