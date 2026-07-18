import Foundation
import ReRoomContracts
import Synchronization
import Testing

@testable import ReRoomCaptureCore

@Suite("CaptureLifecycleTests")
struct CaptureLifecycleTests {
    @Test("the lifecycle accepts only the exact next state")
    func exactLifecycleAdjacency() throws {
        var state = CaptureFrameState.selected
        state = try state.advanced(to: .imageAndMetadataDurable)
        state = try state.advanced(to: .journaled)
        state = try state.advanced(to: .networkEligible)
        state = try state.advanced(to: .serverAcknowledged)
        #expect(state == .serverAcknowledged)
    }

    @Test(
        "duplicate skipped and inverted lifecycle transitions reject",
        arguments: [
            InvalidTransition(.selected, .selected),
            InvalidTransition(.selected, .journaled),
            InvalidTransition(.selected, .networkEligible),
            InvalidTransition(.selected, .serverAcknowledged),
            InvalidTransition(.imageAndMetadataDurable, .selected),
            InvalidTransition(.imageAndMetadataDurable, .imageAndMetadataDurable),
            InvalidTransition(.imageAndMetadataDurable, .networkEligible),
            InvalidTransition(.imageAndMetadataDurable, .serverAcknowledged),
            InvalidTransition(.journaled, .selected),
            InvalidTransition(.journaled, .imageAndMetadataDurable),
            InvalidTransition(.journaled, .journaled),
            InvalidTransition(.journaled, .serverAcknowledged),
            InvalidTransition(.networkEligible, .selected),
            InvalidTransition(.networkEligible, .imageAndMetadataDurable),
            InvalidTransition(.networkEligible, .journaled),
            InvalidTransition(.networkEligible, .networkEligible),
            InvalidTransition(.serverAcknowledged, .selected),
            InvalidTransition(.serverAcknowledged, .imageAndMetadataDurable),
            InvalidTransition(.serverAcknowledged, .journaled),
            InvalidTransition(.serverAcknowledged, .networkEligible),
            InvalidTransition(.serverAcknowledged, .serverAcknowledged),
        ]
    )
    func invalidLifecycleAdjacency(_ transition: InvalidTransition) {
        #expect(throws: CaptureArchiveError.invalidLifecycleTransition) {
            try transition.from.advanced(to: transition.to)
        }
    }

    @Test("explicit consent starts one session and mismatched consent writes nothing")
    func consentIsSessionBound() async throws {
        let fixture = try CaptureWriterFixture(sessionOrdinal: 1)
        defer { fixture.remove() }
        let otherAuthorization = try CaptureSessionAuthorization(
            sessionID: TestIDs.session(2),
            consentGranted: true
        )

        await #expect(throws: CaptureArchiveError.sessionMismatch) {
            try await fixture.store.startSession(authorization: otherAuthorization)
        }
        #expect(fixture.archiveExists == false)

        let descriptor = try await fixture.store.startSession(
            authorization: fixture.authorization
        )
        #expect(descriptor == fixture.descriptor)
        #expect(fixture.archiveExists)

        let snapshot = await fixture.store.snapshot()
        #expect(snapshot.sessionID == fixture.authorization.sessionID)
        #expect(snapshot.eventTypes == ["session_started"])
        #expect(snapshot.acceptedFrames.isEmpty)
        #expect(snapshot.networkEligibleReceipts.isEmpty)
    }

    @Test("denied or malformed authorization cannot create capture bytes")
    func deniedAndMalformedConsentWriteNothing() throws {
        let fixture = try CaptureWriterFixture(sessionOrdinal: 3)
        defer { fixture.remove() }

        #expect(throws: CaptureValueError.consentDenied) {
            try CaptureSessionAuthorization(
                sessionID: fixture.descriptor.sessionID,
                consentGranted: false
            )
        }
        #expect(throws: CaptureValueError.invalidIdentity) {
            try CaptureSessionAuthorization(
                sessionID: "session_bad",
                consentGranted: true
            )
        }
        #expect(fixture.archiveExists == false)
        #expect(fixture.allArchiveFiles.isEmpty)
    }

    @Test("concurrent starts cannot transfer or reuse consent across session IDs")
    func concurrentStartsKeepConsentPerSession() async throws {
        let fixture = try CaptureWriterFixture(sessionOrdinal: 4)
        defer { fixture.remove() }
        let wrong = try CaptureSessionAuthorization(
            sessionID: TestIDs.session(5),
            consentGranted: true
        )

        let results = await withTaskGroup(of: StartResult.self) { group in
            group.addTask {
                do {
                    _ = try await fixture.store.startSession(authorization: fixture.authorization)
                    return .started
                } catch {
                    return .rejected
                }
            }
            group.addTask {
                do {
                    _ = try await fixture.store.startSession(authorization: wrong)
                    return .started
                } catch {
                    return .rejected
                }
            }
            var values = [StartResult]()
            for await value in group { values.append(value) }
            return values
        }

        #expect(results.filter { $0 == .started }.count == 1)
        #expect(results.filter { $0 == .rejected }.count == 1)
        let snapshot = await fixture.store.snapshot()
        #expect(snapshot.sessionID == fixture.authorization.sessionID)
        #expect(snapshot.eventTypes == ["session_started"])
    }

    @Test("one selected frame publishes an exact durable network receipt")
    func frameTransactionIsExactAndByteValid() async throws {
        let fixture = try CaptureWriterFixture(sessionOrdinal: 6)
        defer { fixture.remove() }
        _ = try await fixture.store.startSession(authorization: fixture.authorization)

        let receipt = try await fixture.store.publishSelectedFrame(fixture.candidate(ordinal: 1))
        #expect(receipt.acceptedSequence == 0)
        #expect(receipt.durableJournalSequence == 3)

        let snapshot = await fixture.store.snapshot()
        #expect(
            snapshot.eventTypes == [
                "session_started",
                "frame_selected",
                "frame_image_and_metadata_durable",
                "frame_journaled",
                "frame_network_eligible",
            ]
        )
        #expect(snapshot.journalEntries.map(\.journalSequence) == [0, 1, 2, 3, 4, 5])
        #expect(snapshot.journalEntries.map(\.entryType) == ["event", "event", "event", "frame", "event", "event"])
        #expect(snapshot.acceptedFrames.map(\.sequence) == [0])
        #expect(snapshot.acceptedFrames.map(\.durableJournalSequence) == [3])
        #expect(snapshot.networkEligibleReceipts == [receipt])

        let packet = try fixture.fileSystem.read(at: fixture.archivePath(receipt.packetRelativePath))
        let image = try fixture.fileSystem.read(
            at: fixture.archivePath(fixture.candidate(ordinal: 1).imageRelativePath)
        )
        #expect(CanonicalJSON.sha256Hex(packet) == receipt.packetSHA256)
        #expect(CanonicalJSON.sha256Hex(image) == receipt.imageSHA256)
        #expect(
            fixture.validator.validate(
                ContractValidationRequest(
                    schemaID: ContractSchemaIdentifier.framePacket.rawValue,
                    schemaVersion: "1.0.0",
                    schemaSHA256: TestSchemas.framePacketDigest,
                    documentData: packet,
                    payloadData: image
                )
            ) == .accepted
        )
        let wire = try fixture.encoder.wireFrame(
            for: fixture.candidate(ordinal: 1),
            durableJournalSequence: receipt.durableJournalSequence
        )
        let decoded = try RRFPWireFrame.decode(wire)
        #expect(decoded.headerJSON == packet)
        #expect(decoded.payload == image)
    }

    @Test("a durable frame and acknowledgement expose every exact lifecycle boundary")
    func lifecycleObserverExposesExactDurableBoundaries() async throws {
        let observed = OSAllocatedUnfairLock(initialState: [CaptureLifecycleObservation]())
        let fixture = try CaptureWriterFixture(
            sessionOrdinal: 60,
            lifecycleObserver: { observation in
                observed.withLock { $0.append(observation) }
            }
        )
        defer { fixture.remove() }
        _ = try await fixture.store.startSession(authorization: fixture.authorization)
        let candidate = try fixture.candidate(ordinal: 1)

        let receipt = try await fixture.store.publishSelectedFrame(candidate)
        try await fixture.store.recordAcknowledgement(fixture.acknowledgement(for: receipt))

        #expect(
            observed.withLock { $0 } == CaptureFrameState.allCases.map { state in
                CaptureLifecycleObservation(
                    sessionID: candidate.sessionID,
                    frameID: candidate.frameID,
                    selectedReason: .userEvent,
                    state: state
                )
            }
        )
    }

    @Test("frame identity and idempotency collisions reject without mutation")
    func duplicateFrameAndIdempotencyReject() async throws {
        let fixture = try CaptureWriterFixture(sessionOrdinal: 7)
        defer { fixture.remove() }
        _ = try await fixture.store.startSession(authorization: fixture.authorization)
        let first = try fixture.candidate(ordinal: 1)
        _ = try await fixture.store.publishSelectedFrame(first)
        let before = await fixture.store.snapshot()

        await #expect(throws: CaptureArchiveError.identityCollision) {
            _ = try await fixture.store.publishSelectedFrame(first)
        }
        let reusedKey = try fixture.candidate(
            ordinal: 2,
            idempotencyKey: first.idempotencyKey
        )
        await #expect(throws: CaptureArchiveError.idempotencyCollision) {
            _ = try await fixture.store.publishSelectedFrame(reusedKey)
        }
        #expect(await fixture.store.snapshot() == before)
    }

    @Test("acknowledgement must match every receipt binding")
    func acknowledgementMatching() async throws {
        let fixture = try CaptureWriterFixture(sessionOrdinal: 8)
        defer { fixture.remove() }
        _ = try await fixture.store.startSession(authorization: fixture.authorization)
        let receipt = try await fixture.store.publishSelectedFrame(fixture.candidate(ordinal: 1))
        let acknowledgement = try fixture.acknowledgement(for: receipt)

        try await fixture.store.recordAcknowledgement(acknowledgement)
        let snapshot = await fixture.store.snapshot()
        #expect(snapshot.eventTypes.last == "frame_server_acknowledged")
        #expect(snapshot.acceptedFrames.first?.serverAcknowledged == true)
        #expect(snapshot.networkEligibleReceipts == [receipt])

        await #expect(throws: CaptureArchiveError.duplicateAcknowledgement) {
            try await fixture.store.recordAcknowledgement(acknowledgement)
        }
        #expect(await fixture.store.snapshot() == snapshot)
    }

    @Test(
        "wrong session frame key digest or accepted sequence acknowledgement rejects",
        arguments: AcknowledgementMismatch.allCases
    )
    func acknowledgementMismatch(_ mismatch: AcknowledgementMismatch) async throws {
        let fixture = try CaptureWriterFixture(sessionOrdinal: 9 + mismatch.rawValue)
        defer { fixture.remove() }
        _ = try await fixture.store.startSession(authorization: fixture.authorization)
        let receipt = try await fixture.store.publishSelectedFrame(fixture.candidate(ordinal: 1))
        let before = await fixture.store.snapshot()
        let acknowledgement = try fixture.acknowledgement(for: receipt, mismatch: mismatch)

        await #expect(throws: CaptureArchiveError.acknowledgementMismatch) {
            try await fixture.store.recordAcknowledgement(acknowledgement)
        }
        #expect(await fixture.store.snapshot() == before)
    }

    @Test("explicit finalization publishes a valid immutable empty archive")
    func emptySessionFinalization() async throws {
        let fixture = try CaptureWriterFixture(sessionOrdinal: 20)
        defer { fixture.remove() }
        _ = try await fixture.store.startSession(authorization: fixture.authorization)

        let finalization = try await fixture.store.finalizeExplicitly()
        #expect(finalization.state == .finalized)
        #expect(finalization.acceptedFrameCount == 0)
        #expect(finalization.eventCount == 2)
        #expect(finalization.lastDurableJournalSequence == 1)

        let snapshot = await fixture.store.snapshot()
        let manifest = try #require(snapshot.manifestData)
        #expect(snapshot.eventTypes == ["session_started", "session_finalized"])
        #expect(snapshot.finalization == finalization)
        #expect(
            fixture.validator.validate(
                ContractValidationRequest(
                    schemaID: ContractSchemaIdentifier.rrcapManifest.rawValue,
                    schemaVersion: "1.0.0",
                    schemaSHA256: TestSchemas.manifestDigest,
                    documentData: manifest
                )
            ) == .accepted
        )
        try assertManifestSelfDigest(manifest, expected: finalization.manifestSHA256)

        await #expect(throws: CaptureArchiveError.sessionFinalized) {
            _ = try await fixture.store.finalizeExplicitly()
        }
    }

    @Test("finalized frame archive projects the complete journal and acknowledgement")
    func finalizedFrameArchive() async throws {
        let fixture = try CaptureWriterFixture(sessionOrdinal: 21)
        defer { fixture.remove() }
        _ = try await fixture.store.startSession(authorization: fixture.authorization)
        let receipt = try await fixture.store.publishSelectedFrame(fixture.candidate(ordinal: 1))
        try await fixture.store.recordAcknowledgement(fixture.acknowledgement(for: receipt))

        let finalization = try await fixture.store.finalizeExplicitly()
        let snapshot = await fixture.store.snapshot()
        let manifest = try #require(snapshot.manifestData)
        #expect(finalization.acceptedFrameCount == 1)
        #expect(finalization.eventCount == 7)
        #expect(finalization.lastDurableJournalSequence == 7)
        #expect(snapshot.journalEntries.map(\.journalSequence) == Array(0...7))
        #expect(snapshot.acceptedFrames.first?.serverAcknowledged == true)
        #expect(snapshot.eventTypes.last == "session_finalized")
        #expect(
            fixture.validator.validate(
                ContractValidationRequest(
                    schemaID: ContractSchemaIdentifier.rrcapManifest.rawValue,
                    schemaVersion: "1.0.0",
                    schemaSHA256: TestSchemas.manifestDigest,
                    documentData: manifest
                )
            ) == .accepted
        )
        try assertManifestSelfDigest(manifest, expected: finalization.manifestSHA256)
    }

    @Test("local finalization does not depend on server acknowledgement")
    func localFinalizationWithoutAcknowledgement() async throws {
        let fixture = try CaptureWriterFixture(sessionOrdinal: 22)
        defer { fixture.remove() }
        _ = try await fixture.store.startSession(authorization: fixture.authorization)
        _ = try await fixture.store.publishSelectedFrame(fixture.candidate(ordinal: 1))

        let finalization = try await fixture.store.finalizeExplicitly()
        let snapshot = await fixture.store.snapshot()
        #expect(finalization.acceptedFrameCount == 1)
        #expect(finalization.eventCount == 6)
        #expect(finalization.lastDurableJournalSequence == 6)
        #expect(snapshot.acceptedFrames.first?.serverAcknowledged == false)
        #expect(snapshot.eventTypes.contains("frame_server_acknowledged") == false)
        #expect(snapshot.finalization?.state == .finalized)
    }
}

struct InvalidTransition: Sendable, CustomTestStringConvertible {
    let from: CaptureFrameState
    let to: CaptureFrameState

    init(_ from: CaptureFrameState, _ to: CaptureFrameState) {
        self.from = from
        self.to = to
    }

    var testDescription: String { "\(from.rawValue)->\(to.rawValue)" }
}

private enum StartResult: Sendable {
    case started
    case rejected
}

enum AcknowledgementMismatch: Int, CaseIterable, Sendable, CustomTestStringConvertible {
    case session
    case frame
    case idempotencyKey
    case digest
    case sequence

    var testDescription: String { String(describing: self) }
}

private struct CaptureWriterFixture: Sendable {
    let root: URL
    let fileSystem: FoundationCaptureFileSystem
    let validator: ContractValidator
    let descriptor: CaptureSessionDescriptor
    let authorization: CaptureSessionAuthorization
    let encoder: FramePacketEncoder
    let store: CaptureArchiveStore

    init(
        sessionOrdinal: Int,
        lifecycleObserver: @escaping CaptureLifecycleObserver = { _ in }
    ) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("reroom-capture-lifecycle-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        fileSystem = try FoundationCaptureFileSystem(root: root)
        validator = try TestSchemas.validator()
        descriptor = try CaptureSessionDescriptor(
            sessionID: TestIDs.session(sessionOrdinal),
            archivePath: "archives/\(TestIDs.session(sessionOrdinal)).rrcap",
            worldFrameID: TestIDs.world(sessionOrdinal),
            startedAtMonotonicNanoseconds: String(1_000_000_000 + sessionOrdinal * 1_000)
        )
        authorization = try CaptureSessionAuthorization(
            sessionID: descriptor.sessionID,
            consentGranted: true
        )
        encoder = FramePacketEncoder(
            validator: validator,
            profile: .syntheticOnePixelPNG
        )
        store = CaptureArchiveStore(
            fileSystem: fileSystem,
            encoder: encoder,
            descriptor: descriptor,
            source: CaptureArchiveSource(
                deviceModel: "Synthetic iPhone Fixture",
                osVersion: "fixture-1.0.0",
                appVersion: "fixture-1.0.0",
                buildID: "build_fixture_0001",
                recordedAtUTC: "2026-07-17T00:00:00Z"
            ),
            eventID: { sequence in TestIDs.event(sessionOrdinal * 100 + Int(sequence) + 1) },
            lifecycleObserver: lifecycleObserver
        )
    }

    var archiveExists: Bool {
        FileManager.default.fileExists(
            atPath: root.appendingPathComponent(descriptor.archivePath).path
        )
    }

    var allArchiveFiles: [String] {
        guard let enumerator = FileManager.default.enumerator(atPath: root.path) else { return [] }
        return enumerator.compactMap { $0 as? String }.sorted()
    }

    func candidate(
        ordinal: Int,
        idempotencyKey: String? = nil
    ) throws -> SelectedFrameCandidate {
        let frameID = TestIDs.frame(ordinal)
        return try SelectedFrameCandidate(
            sessionID: descriptor.sessionID,
            frameID: frameID,
            submapID: TestIDs.submap(1),
            worldFrameID: descriptor.worldFrameID,
            worldFrameVersion: 1,
            captureSequence: UInt64(ordinal - 1),
            monotonicTimestampNanoseconds: String(2_000_000_000 + ordinal),
            imageRelativePath: "frames/\(frameID)/image.png",
            packetRelativePath: "frames/\(frameID)/packet.json",
            imageBytes: TestImages.onePixelPNG,
            selectedReason: .userEvent,
            idempotencyKey: idempotencyKey ?? TestIDs.idempotency(ordinal)
        )
    }

    func acknowledgement(
        for receipt: NetworkEligibleReceipt,
        mismatch: AcknowledgementMismatch? = nil
    ) throws -> GatewayAcknowledgement {
        try GatewayAcknowledgement(
            gatewayID: TestIDs.gateway(1),
            sessionID: mismatch == .session ? TestIDs.session(99) : receipt.sessionID,
            frameID: mismatch == .frame ? TestIDs.frame(99) : receipt.frameID,
            idempotencyKey: mismatch == .idempotencyKey
                ? TestIDs.idempotency(99) : receipt.idempotencyKey,
            packetSHA256: mismatch == .digest
                ? String(repeating: "f", count: 64) : receipt.packetSHA256,
            acceptedSequence: mismatch == .sequence
                ? receipt.acceptedSequence + 1 : receipt.acceptedSequence
        )
    }

    func archivePath(_ relativePath: String) -> String {
        "\(descriptor.archivePath)/\(relativePath)"
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private enum TestIDs {
    static func session(_ ordinal: Int) -> String { id("session", ordinal) }
    static func frame(_ ordinal: Int) -> String { id("frame", ordinal) }
    static func submap(_ ordinal: Int) -> String { id("submap", ordinal) }
    static func world(_ ordinal: Int) -> String { id("world", ordinal) }
    static func event(_ ordinal: Int) -> String { id("event", ordinal) }
    static func gateway(_ ordinal: Int) -> String { id("gateway", ordinal) }
    static func idempotency(_ ordinal: Int) -> String { id("frameidem", ordinal) }

    private static func id(_ prefix: String, _ ordinal: Int) -> String {
        "\(prefix)_\(String(format: "%08x", ordinal))-0000-4000-8000-000000000001"
    }
}

private enum TestImages {
    static let onePixelPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!
}

private enum TestSchemas {
    static let framePacketDigest = "d50b19bfb29c6c62c494e3a47deb3c51a933609698f4ff2f9cbfba6ec4252b43"
    static let manifestDigest = "c97349820ed66fb1a1fdf60ea9afee312f532811602851d01d1e233641730b87"

    static func validator() throws -> ContractValidator {
        let root = try repositoryRoot()
        let registrations: [(ContractSchemaIdentifier, String, String)] = [
            (.framePacket, "frame-packet.schema.json", framePacketDigest),
            (.rrcapManifest, "rrcap-manifest.schema.json", manifestDigest),
            (.sceneState, "scene-state.schema.json", "9c77d27762e20ff5fad24c438e8817a03c770b55be3fc82ea72097c4c273e440"),
            (.editArtifacts, "edit-artifacts.schema.json", "58dbfc8f152881cbdc31be22f6ab7631ac474bb78537ac2a9254f5ef16bd598f"),
            (.transaction, "transaction.schema.json", "2a4f6728978db0879b5dfb10f052f6d5280e5cf83ad5600f0cf959626c2399a2"),
        ]
        return try ContractValidator(registrations: registrations.map { identifier, name, digest in
            ContractSchemaRegistration(
                identifier: identifier,
                version: "1.0.0",
                sha256: digest,
                schemaData: try Data(contentsOf: root.appendingPathComponent("docs/contracts/\(name)"))
            )
        })
    }

    private static func repositoryRoot() throws -> URL {
        var cursor = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<12 {
            if FileManager.default.fileExists(
                atPath: cursor.appendingPathComponent("docs/contracts/frame-packet.schema.json").path
            ) {
                return cursor
            }
            cursor.deleteLastPathComponent()
        }
        throw TestFixtureError.repositoryRootNotFound
    }
}

private enum TestFixtureError: Error {
    case repositoryRootNotFound
    case invalidManifest
}

private func assertManifestSelfDigest(_ data: Data, expected: String) throws {
    guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          var finalization = root["finalization"] as? [String: Any],
          finalization.removeValue(forKey: "manifest_sha256") as? String == expected
    else {
        throw TestFixtureError.invalidManifest
    }
    root["finalization"] = finalization
    let encoded = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    let canonical = try CanonicalJSON.canonicalize(jsonData: encoded)
    #expect(CanonicalJSON.sha256Hex(canonical) == expected)
}
