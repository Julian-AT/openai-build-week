import Foundation
import ReRoomContracts
import Testing

@testable import ReRoomCaptureCore

@Suite("CaptureRecoveryTests")
struct CaptureRecoveryTests {
    @Test(
        "finalized and recovered fixtures are immutable verified archives",
        arguments: [
            ("finalized-empty.rrcap", CaptureFinalizationState.finalized, 2, 0, 2),
            ("finalized-one-frame.rrcap", .finalized, 8, 1, 7),
            ("recovered-prefix.rrcap", .recoveredPrefix, 6, 1, 5),
        ]
    )
    func completeArchives(
        archiveName: String,
        state: CaptureFinalizationState,
        journalCount: Int,
        frameCount: Int,
        eventCount: Int
    ) throws {
        let fixture = try RecoveryFixture(copying: archiveName)
        defer { fixture.remove() }
        let before = try fixture.snapshot()

        let recovered = try fixture.recovery().inspect(root: fixture.archiveURL)

        #expect(recovered.finalization.state == state)
        #expect(recovered.acceptedJournalRecordCount == journalCount)
        #expect(recovered.finalization.acceptedFrameCount == frameCount)
        #expect(recovered.finalization.eventCount == eventCount)
        #expect(recovered.firstInvalidJournalSequence == nil)
        #expect(recovered.quarantineSHA256 == nil)
        #expect(try fixture.snapshot() == before)
        #expect(FileManager.default.fileExists(atPath: fixture.recoveredURL.path) == false)
    }

    @Test("a stale open manifest cannot truncate later fsynced journal records")
    func staleOpenManifest() async throws {
        let fixture = try await RecoveryWriterFixture.staleAfterDurableFrameBytes()
        defer { fixture.remove() }
        let sourceBefore = try RecoveryFixture.snapshot(of: fixture.archiveURL)

        let candidate = try fixture.recovery.recoveryCandidate(root: fixture.archiveURL)

        #expect(candidate.finalizationState == .recoveredPrefix)
        #expect(candidate.acceptedJournalRecordCount == 6)
        #expect(candidate.acceptedFrameCount == 1)
        #expect(candidate.eventCount == 5)
        #expect(candidate.members.count == 7)
        #expect(candidate.invalidSuffix == nil)
        #expect(candidate.acceptedPrefixJournalSHA256 == CanonicalJSON.sha256Hex(candidate.journalData))
        #expect(try RecoveryFixture.snapshot(of: fixture.archiveURL) == sourceBefore)
        #expect(FileManager.default.fileExists(atPath: fixture.recoveredURL.path) == false)

        let verified = try fixture.materializeAndVerify(candidate)
        let replay = try ReplayCore.replay(verified)
        #expect(replay.timeline.count == 6)
        #expect(replay.finalization.acceptedFrameCount == 1)
        #expect(replay.finalization.eventCount == 5)
    }

    @Test("a prefix ending at the fsynced frame record remains verifier-replayable")
    func frameJournalBoundary() async throws {
        let fixture = try await RecoveryWriterFixture.staleAfterDurableFrameBytes()
        defer { fixture.remove() }
        try fixture.replaceJournal(objects: Array(try fixture.journalObjects().prefix(4)))

        let candidate = try fixture.recovery.recoveryCandidate(root: fixture.archiveURL)

        #expect(candidate.acceptedJournalRecordCount == 4)
        #expect(candidate.acceptedFrameCount == 1)
        #expect(candidate.eventCount == 3)
        let replay = try ReplayCore.replay(fixture.materializeAndVerify(candidate))
        #expect(replay.timeline.map(\.journalSequence) == [0, 1, 2, 3])
        #expect(replay.finalization.acceptedFrameCount == 1)
    }

    @Test("a torn final JSONL record produces an unpublished preceding-prefix candidate")
    func tornFinalRecord() async throws {
        let fixture = try await RecoveryWriterFixture.completedFrame()
        defer { fixture.remove() }
        let tail = Data(#"{"journal_sequence":6"#.utf8)
        try fixture.appendJournal(tail)
        let original = try RecoveryFixture.snapshot(of: fixture.archiveURL)

        let candidate = try fixture.recovery.recoveryCandidate(root: fixture.archiveURL)

        #expect(candidate.acceptedJournalRecordCount == 6)
        #expect(candidate.invalidSuffix?.firstInvalidJournalSequence == 6)
        #expect(candidate.invalidSuffix?.bytes == tail)
        #expect(candidate.invalidSuffix?.sha256 == CanonicalJSON.sha256Hex(tail))
        #expect(try RecoveryFixture.snapshot(of: fixture.archiveURL) == original)
        #expect(FileManager.default.fileExists(atPath: fixture.recoveredURL.path) == false)
        #expect(try ReplayCore.replay(fixture.materializeAndVerify(candidate)).timeline.count == 6)
    }

    @Test("a hash-invalid final record is a suffix but accepted-record corruption is fatal")
    func corruptSuffixVersusInterior() async throws {
        let suffix = try await RecoveryWriterFixture.completedFrame()
        defer { suffix.remove() }
        var finalEntry = try suffix.journalObjects().last!
        finalEntry["content_sha256"] = String(repeating: "0", count: 64)
        try suffix.replaceJournal(objects: Array(try suffix.journalObjects().dropLast()) + [finalEntry])

        let candidate = try suffix.recovery.recoveryCandidate(root: suffix.archiveURL)
        #expect(candidate.acceptedJournalRecordCount == 5)
        #expect(candidate.invalidSuffix?.firstInvalidJournalSequence == 5)
        #expect(try ReplayCore.replay(suffix.materializeAndVerify(candidate)).timeline.count == 5)

        let interior = try await RecoveryWriterFixture.completedFrame()
        defer { interior.remove() }
        var objects = try interior.journalObjects()
        objects[2]["content_sha256"] = String(repeating: "0", count: 64)
        try interior.replaceJournal(objects: objects)

        #expect(throws: CaptureRecoveryError.interiorCorruption) {
            try interior.recovery.recoveryCandidate(root: interior.archiveURL)
        }
        #expect(FileManager.default.fileExists(atPath: interior.recoveredURL.path) == false)
    }

    @Test(
        "first-record corruption and interior adjacency failures never skip ahead",
        arguments: [RecoveryJournalMutation.firstRecord, .gap, .reorder]
    )
    func journalAdjacency(_ mutation: RecoveryJournalMutation) async throws {
        let fixture = try await RecoveryWriterFixture.completedFrame()
        defer { fixture.remove() }
        try fixture.mutateJournal(mutation)

        #expect(throws: mutation == .firstRecord
            ? CaptureRecoveryError.noRecoverablePrefix
            : CaptureRecoveryError.nonContiguousJournal
        ) {
            try fixture.recovery.recoveryCandidate(root: fixture.archiveURL)
        }
        #expect(FileManager.default.fileExists(atPath: fixture.recoveredURL.path) == false)
    }

    @Test(
        "closed manifest inventory and accepted bytes reject independent mutations",
        arguments: RecoveryManifestMutation.allCases
    )
    func manifestAndInventoryMutations(_ mutation: RecoveryManifestMutation) throws {
        let fixture = try RecoveryFixture(copying: "finalized-one-frame.rrcap")
        defer { fixture.remove() }
        try fixture.mutateManifestOrInventory(mutation)

        #expect(throws: mutation.expectedError) {
            try fixture.recovery().inspect(root: fixture.archiveURL)
        }
    }

    @Test("missing or empty launch inventory has a stable rejection")
    func missingAndEmptyLaunchInputs() throws {
        let missing = try RecoveryFixture.emptyArchive()
        defer { missing.remove() }
        #expect(throws: CaptureRecoveryError.missingManifest) {
            try missing.recovery().inspect(root: missing.archiveURL)
        }

        let empty = try RecoveryFixture.openArchive()
        defer { empty.remove() }
        try Data().write(to: empty.journalURL)
        #expect(throws: CaptureRecoveryError.emptyJournal) {
            try empty.recovery().inspect(root: empty.archiveURL)
        }
    }

    @Test("candidate construction is deterministic and never publishes or rewrites its source")
    func repeatedRecovery() async throws {
        let fixture = try await RecoveryWriterFixture.completedFrame()
        defer { fixture.remove() }
        let suffix = Data("not-json".utf8)
        try fixture.appendJournal(suffix)
        let original = try RecoveryFixture.snapshot(of: fixture.archiveURL)

        let first = try fixture.recovery.recoveryCandidate(root: fixture.archiveURL)
        let second = try fixture.recovery.recoveryCandidate(root: fixture.archiveURL)

        #expect(first == second)
        #expect(try RecoveryFixture.snapshot(of: fixture.archiveURL) == original)
        #expect(FileManager.default.fileExists(atPath: fixture.recoveredURL.path) == false)
    }
}

private final class StaleManifestProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let manifestURL: URL
    private var captured: Data?

    init(manifestURL: URL) {
        self.manifestURL = manifestURL
    }

    func observe(_ observation: CaptureLifecycleObservation) {
        guard observation.state == .imageAndMetadataDurable else { return }
        let data = try? Data(contentsOf: manifestURL)
        lock.lock()
        captured = data
        lock.unlock()
    }

    func manifestData() throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        guard let captured else { throw RecoveryWriterFixtureError.missingStaleManifest }
        return captured
    }
}

private struct RecoveryWriterFixture: Sendable {
    let rootURL: URL
    let archiveURL: URL
    let verifier: ArchiveVerifier
    let recovery: CaptureRecovery

    var journalURL: URL { archiveURL.appendingPathComponent("journal/global.jsonl") }
    var recoveredURL: URL {
        archiveURL.deletingPathExtension().appendingPathExtension("recovered-prefix.rrcap")
    }

    static func staleAfterDurableFrameBytes() async throws -> RecoveryWriterFixture {
        try await completedFrame(useStaleManifest: true)
    }

    static func completedFrame(
        useStaleManifest: Bool = false
    ) async throws -> RecoveryWriterFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("reroom-recovery-writer-\(UUID().uuidString.lowercased())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let sessionID = id(prefix: "session", ordinal: 901)
        let archivePath = "archives/\(sessionID).rrcap"
        let archiveURL = root.appendingPathComponent(archivePath)
        let probe = StaleManifestProbe(
            manifestURL: archiveURL.appendingPathComponent("manifest.json")
        )
        let validator = try validator()
        let store = CaptureArchiveStore(
            fileSystem: try FoundationCaptureFileSystem(root: root),
            encoder: FramePacketEncoder(
                validator: validator,
                profile: .syntheticOnePixelPNG
            ),
            descriptor: try CaptureSessionDescriptor(
                sessionID: sessionID,
                archivePath: archivePath,
                worldFrameID: id(prefix: "world", ordinal: 901),
                startedAtMonotonicNanoseconds: "3000000901"
            ),
            source: CaptureArchiveSource(
                deviceModel: "Synthetic iPhone Fixture",
                osVersion: "fixture-1.0.0",
                appVersion: "fixture-1.0.0",
                buildID: "build_fixture_0002",
                recordedAtUTC: "2026-07-17T00:00:00Z"
            ),
            eventID: { sequence in id(prefix: "event", ordinal: 90_100 + Int(sequence)) },
            lifecycleObserver: probe.observe
        )
        _ = try await store.startSession(
            authorization: CaptureSessionAuthorization(
                sessionID: sessionID,
                consentGranted: true
            )
        )
        let frameID = id(prefix: "frame", ordinal: 901)
        _ = try await store.publishSelectedFrame(
            SelectedFrameCandidate(
                sessionID: sessionID,
                frameID: frameID,
                submapID: id(prefix: "submap", ordinal: 901),
                worldFrameID: id(prefix: "world", ordinal: 901),
                worldFrameVersion: 1,
                captureSequence: 0,
                monotonicTimestampNanoseconds: "4000000901",
                imageRelativePath: "frames/\(frameID)/image.png",
                packetRelativePath: "frames/\(frameID)/packet.json",
                imageBytes: onePixelPNG,
                selectedReason: .userEvent,
                idempotencyKey: id(prefix: "frameidem", ordinal: 901)
            )
        )
        if useStaleManifest {
            try probe.manifestData().write(
                to: archiveURL.appendingPathComponent("manifest.json"),
                options: .atomic
            )
        }
        let verifier = ArchiveVerifier(validator: validator)
        return RecoveryWriterFixture(
            rootURL: root,
            archiveURL: archiveURL,
            verifier: verifier,
            recovery: CaptureRecovery(verifier: verifier)
        )
    }

    func appendJournal(_ data: Data) throws {
        let handle = try FileHandle(forWritingTo: journalURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    func journalObjects() throws -> [[String: Any]] {
        try Data(contentsOf: journalURL)
            .split(separator: 0x0a)
            .map { try JSONSerialization.jsonObject(with: Data($0)) as! [String: Any] }
    }

    func replaceJournal(objects: [[String: Any]]) throws {
        var data = Data()
        for object in objects {
            data.append(try canonical(object))
            data.append(0x0a)
        }
        try data.write(to: journalURL)
    }

    func mutateJournal(_ mutation: RecoveryJournalMutation) throws {
        var objects = try journalObjects()
        switch mutation {
        case .firstRecord:
            try Data("{".utf8).write(to: journalURL)
            return
        case .gap:
            objects[2]["journal_sequence"] = 3
        case .reorder:
            objects.swapAt(2, 3)
        }
        try replaceJournal(objects: objects)
    }

    func materializeAndVerify(
        _ candidate: RecoveryGenerationCandidate
    ) throws -> VerifiedArchive {
        let generation = rootURL
            .appendingPathComponent("candidate-\(UUID().uuidString.lowercased()).rrcap")
        try candidate.materialize(at: generation)
        return try verifier.verify(root: generation)
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    private static let onePixelPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!

    private static func id(prefix: String, ordinal: Int) -> String {
        "\(prefix)_\(String(format: "%08x", ordinal))-0000-4000-8000-000000000001"
    }

    fileprivate static func validator() throws -> ContractValidator {
        let root = try repositoryRoot()
        let registrations: [(ContractSchemaIdentifier, String, String)] = [
            (.framePacket, "frame-packet.schema.json", "d50b19bfb29c6c62c494e3a47deb3c51a933609698f4ff2f9cbfba6ec4252b43"),
            (.rrcapManifest, "rrcap-manifest.schema.json", "c97349820ed66fb1a1fdf60ea9afee312f532811602851d01d1e233641730b87"),
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
        throw RecoveryWriterFixtureError.repositoryRootNotFound
    }

    private func canonical(_ value: Any) throws -> Data {
        let encoded = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return try CanonicalJSON.canonicalize(jsonData: encoded)
    }
}

private enum RecoveryWriterFixtureError: Error {
    case missingStaleManifest
    case repositoryRootNotFound
}

enum RecoveryJournalMutation: Equatable, Sendable {
    case firstRecord
    case gap
    case reorder
}

enum RecoveryManifestMutation: CaseIterable, Sendable {
    case unsafePath
    case wrongRawHash
    case wrongEventRecordHash
    case wrongPacketHash
    case wrongManifestHash
    case unsupportedVersion
    case unsupportedCodec
    case unsupportedDigestAlgorithm
    case unsupportedDigestScope

    var expectedError: CaptureRecoveryError {
        switch self {
        case .unsafePath: .invalidPath
        case .wrongRawHash, .wrongEventRecordHash, .wrongManifestHash:
            .digestMismatch
        case .wrongPacketHash:
            .projectionMismatch
        case .unsupportedVersion: .unsupportedContractVersion
        case .unsupportedCodec, .unsupportedDigestAlgorithm, .unsupportedDigestScope:
            .invalidManifest
        }
    }
}

private final class RecoveryFixture {
    let rootURL: URL
    let archiveURL: URL

    var recoveredURL: URL {
        archiveURL.deletingPathExtension().appendingPathExtension("recovered-prefix.rrcap")
    }

    var journalURL: URL { archiveURL.appendingPathComponent("journal/global.jsonl") }
    var quarantineRootURL: URL {
        archiveURL.deletingPathExtension().appendingPathExtension("quarantine")
    }
    var quarantineBytesURL: URL {
        quarantineRootURL.appendingPathComponent("invalid-suffix.bin")
    }
    var stagingPaths: [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.contains(".recovery-staging-") }
    }

    init(rootURL: URL, archiveURL: URL) {
        self.rootURL = rootURL
        self.archiveURL = archiveURL
    }

    convenience init(copying archiveName: String) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("reroom-recovery-\(UUID().uuidString.lowercased())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let destination = root.appendingPathComponent(archiveName)
        try FileManager.default.copyItem(
            at: Self.fixtureRoot.appendingPathComponent(archiveName),
            to: destination
        )
        self.init(rootURL: root, archiveURL: destination)
    }

    static func openArchive() throws -> RecoveryFixture {
        let fixture = try RecoveryFixture(copying: "recovered-prefix.rrcap")
        try? FileManager.default.removeItem(at: fixture.archiveURL.appendingPathComponent("quarantine"))
        var manifest = try fixture.manifestObject()
        var finalization = manifest["finalization"] as! [String: Any]
        finalization["state"] = "open"
        manifest["finalization"] = finalization
        try fixture.writeManifest(manifest)

        let journal = manifest["journal"] as! [[String: Any]]
        try FileManager.default.createDirectory(
            at: fixture.journalURL.deletingLastPathComponent(),
            withIntermediateDirectories: false
        )
        try fixture.replaceJournal(objects: journal)
        return fixture
    }

    static func emptyArchive() throws -> RecoveryFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("reroom-recovery-\(UUID().uuidString.lowercased())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let archive = root.appendingPathComponent("empty.rrcap")
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: false)
        return RecoveryFixture(rootURL: root, archiveURL: archive)
    }

    func remove() { try? FileManager.default.removeItem(at: rootURL) }

    func recovery() throws -> CaptureRecovery {
        CaptureRecovery(
            verifier: ArchiveVerifier(validator: try RecoveryWriterFixture.validator())
        )
    }

    func manifestObject() throws -> [String: Any] {
        let data = try Data(contentsOf: archiveURL.appendingPathComponent("manifest.json"))
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    func writeManifest(_ value: [String: Any], preservingWrongDigest: Bool = false) throws {
        var root = value
        var finalization = root["finalization"] as! [String: Any]
        if preservingWrongDigest == false {
            finalization.removeValue(forKey: "manifest_sha256")
            root["finalization"] = finalization
            let digest = CanonicalJSON.sha256Hex(try Self.canonical(root))
            finalization["manifest_sha256"] = digest
        }
        root["finalization"] = finalization
        try Self.canonical(root).write(to: archiveURL.appendingPathComponent("manifest.json"))
    }

    func journalObjects() throws -> [[String: Any]] {
        try Data(contentsOf: journalURL)
            .split(separator: 0x0a)
            .map { try JSONSerialization.jsonObject(with: Data($0)) as! [String: Any] }
    }

    func replaceJournal(objects: [[String: Any]]) throws {
        var data = Data()
        for object in objects {
            data.append(try Self.canonical(object))
            data.append(0x0a)
        }
        try data.write(to: journalURL)
    }

    func appendJournal(_ data: Data) throws {
        let handle = try FileHandle(forWritingTo: journalURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    func mutateJournal(_ mutation: RecoveryJournalMutation) throws {
        var objects = try journalObjects()
        switch mutation {
        case .firstRecord:
            try Data("{".utf8).write(to: journalURL)
            return
        case .gap:
            objects[2]["journal_sequence"] = 3
        case .reorder:
            objects.swapAt(2, 3)
        }
        try replaceJournal(objects: objects)
    }

    func mutateManifestOrInventory(_ mutation: RecoveryManifestMutation) throws {
        var manifest = try manifestObject()
        switch mutation {
        case .unsafePath:
            var files = manifest["files"] as! [[String: Any]]
            files[0]["relative_path"] = "../outside.json"
            manifest["files"] = files
            try writeManifest(manifest)
        case .wrongRawHash:
            let files = manifest["files"] as! [[String: Any]]
            let path = files.first { $0["role"] as? String == "frame_image" }!["relative_path"] as! String
            try Data("tampered".utf8).write(to: archiveURL.appendingPathComponent(path))
        case .wrongEventRecordHash:
            var events = manifest["events"] as! [[String: Any]]
            events[0]["record_sha256"] = String(repeating: "0", count: 64)
            manifest["events"] = events
            try writeManifest(manifest)
        case .wrongPacketHash:
            var frames = manifest["accepted_frame_order"] as! [[String: Any]]
            frames[0]["packet_sha256"] = String(repeating: "0", count: 64)
            manifest["accepted_frame_order"] = frames
            try writeManifest(manifest)
        case .wrongManifestHash:
            var finalization = manifest["finalization"] as! [String: Any]
            finalization["manifest_sha256"] = String(repeating: "0", count: 64)
            manifest["finalization"] = finalization
            try writeManifest(manifest, preservingWrongDigest: true)
        case .unsupportedVersion:
            manifest["format_version"] = "1.1.0"
            try writeManifest(manifest)
        case .unsupportedCodec:
            var files = manifest["files"] as! [[String: Any]]
            files[0]["codec"] = "opaque"
            manifest["files"] = files
            try writeManifest(manifest)
        case .unsupportedDigestAlgorithm:
            var replay = manifest["replay"] as! [String: Any]
            replay["input_digest_algorithm"] = "sha256"
            manifest["replay"] = replay
            try writeManifest(manifest)
        case .unsupportedDigestScope:
            var finalization = manifest["finalization"] as! [String: Any]
            finalization["manifest_sha256_scope"] = "everything"
            manifest["finalization"] = finalization
            try writeManifest(manifest)
        }
    }

    func snapshot(excludingJournal: Bool = false) throws -> [String: String] {
        var values = try Self.snapshot(of: archiveURL)
        if excludingJournal {
            values = values.filter { $0.key.hasSuffix("journal/global.jsonl") == false }
        }
        return values
    }

    static func snapshot(of root: URL) throws -> [String: String] {
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])!
        var values = [String: String]()
        for case let url as URL in enumerator {
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            let relative = String(url.path.dropFirst(root.path.count + 1))
            values[relative] = CanonicalJSON.sha256Hex(try Data(contentsOf: url))
        }
        return values
    }

    private static var fixtureRoot: URL {
        var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path) {
            let parent = root.deletingLastPathComponent()
            precondition(parent != root, "repository root unavailable")
            root = parent
        }
        return root.appendingPathComponent("fixtures/capture/1.0.0/rev-001/archives")
    }

    private static func canonical(_ value: Any) throws -> Data {
        let encoded = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return try CanonicalJSON.canonicalize(jsonData: encoded)
    }
}
