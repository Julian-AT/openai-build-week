import ARKit
import Foundation
import os
import ReRoomContracts
import ReRoomCaptureCore
import UIKit

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

struct CapturePresentationSnapshot: Equatable, Sendable {
    var phase: CaptureSessionPhase
    var sessionID: String?
    var admission: CaptureAdmissionSnapshot?
    var finalization: CaptureFinalization?
    var recovered: VerifiedCaptureReplay?
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
    func finalizeExplicitly() async throws -> CaptureFinalization
}

protocol CaptureArchiveSessionFactory: Sendable {
    func makeSession(
        descriptor: CaptureSessionDescriptor
    ) async throws -> any CaptureArchiveSessionWriting
}

protocol CaptureRecoveryDriving: Sendable {
    func discoverVerifiedArchives() async -> [VerifiedCaptureReplay]
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

    func startSession(authorization: CaptureSessionAuthorization) async throws {
        _ = try await store.startSession(authorization: authorization)
    }

    func publishSelectedFrame(
        _ candidate: SelectedFrameCandidate,
        profile: FramePacketEncodingProfile
    ) async throws -> NetworkEligibleReceipt {
        try await store.publishSelectedFrame(candidate, profile: profile)
    }

    func finalizeExplicitly() async throws -> CaptureFinalization {
        try await store.finalizeExplicitly()
    }
}

struct CoreCaptureArchiveSessionFactory: CaptureArchiveSessionFactory, Sendable {
    let root: URL
    let validator: ContractValidator
    let source: CaptureArchiveSource

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
            source: source
        )
        return CoreCaptureArchiveSession(store: store)
    }
}

struct FoundationCaptureRecoveryDriver: CaptureRecoveryDriving, Sendable {
    let root: URL
    let fixtureManifestSHA256: String
    let repositoryRevision: String

    func discoverVerifiedArchives() async -> [VerifiedCaptureReplay] {
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return []
        }
        return urls
            .filter { $0.lastPathComponent.hasSuffix(".rrcap") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap(verifiedReplay(at:))
    }

    func recoverInterruptedArchive(at archivePath: String) async -> VerifiedCaptureReplay? {
        verifiedReplay(at: root.appendingPathComponent(archivePath))
    }

    private func verifiedReplay(at sourceURL: URL) -> VerifiedCaptureReplay? {
        do {
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
        } catch {
            return nil
        }
    }
}

struct EmptyCaptureRecoveryDriver: CaptureRecoveryDriving, Sendable {
    func discoverVerifiedArchives() async -> [VerifiedCaptureReplay] { [] }
    func recoverInterruptedArchive(at archivePath: String) async -> VerifiedCaptureReplay? { nil }
}

@MainActor
final class CaptureSessionAdapter {
    static let userEventBusyMessage = "Saving this capture frame — try again when ready."
    static let userEventBusyAccessibilityIdentifier = "diagnostic.capture.user-event-busy"

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
        guard presentation.phase != .recording else { return }
        presentation = .idle
        presentation.phase = .declined
        presentation.failureMessage = "Room capture remains off. You can start again when ready."
    }

    func acceptDisclosure() async {
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
                            _ = try await nextArchive.publishSelectedFrame(
                                candidate,
                                profile: payload.profile
                            )
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
        let verified = await recoveryDriver.discoverVerifiedArchives()
        guard let latest = verified.last else { return }
        presentation = .idle
        presentation.phase = .recovered
        presentation.sessionID = latest.recovered.finalization.sessionID
        presentation.recovered = latest
        presentation.finalization = latest.recovered.finalization
    }

    func setOffline(_ offline: Bool) {
        presentation.isOffline = offline
    }

    private func expireBackgroundFinalization() {
        backgroundExpired = true
        guard let gate else { return }
        let close = gate.close(reason: .expiration, mode: .abortQueuedBeforeSelection)
        applyCloseReport(close)
        consumerTask?.cancel()
        presentation.phase = .interrupted
        presentation.failureMessage = "Background time expired; the durable prefix was preserved."
    }

    private func recordTerminal(_ result: CaptureAdmissionTerminalResult) {
        if result.admitted.candidate.selectedReason == .userEvent {
            presentation.explicitCaptureBusy = false
            presentation.busyMessage = nil
        }
        if let gate { applyAdmissionSnapshot(gate.snapshot()) }
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
