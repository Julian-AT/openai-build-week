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

        let recovered = try CaptureRecovery.inspect(root: fixture.archiveURL)

        #expect(recovered.finalization.state == state)
        #expect(recovered.acceptedJournalRecordCount == journalCount)
        #expect(recovered.finalization.acceptedFrameCount == frameCount)
        #expect(recovered.finalization.eventCount == eventCount)
        #expect(recovered.firstInvalidJournalSequence == nil)
        #expect(recovered.quarantineSHA256 == nil)
        #expect(try fixture.snapshot() == before)
        #expect(FileManager.default.fileExists(atPath: fixture.recoveredURL.path) == false)
    }

    @Test("a torn final JSONL record publishes only the immediately preceding prefix")
    func tornFinalRecord() throws {
        let fixture = try RecoveryFixture.openArchive()
        defer { fixture.remove() }
        let original = try fixture.snapshot(excludingJournal: true)
        try fixture.appendJournal(Data(#"{"journal_sequence":6"#.utf8))

        let recovered = try CaptureRecovery.inspect(root: fixture.archiveURL)

        #expect(recovered.finalization.state == .recoveredPrefix)
        #expect(recovered.acceptedJournalRecordCount == 6)
        #expect(recovered.firstInvalidJournalSequence == 6)
        #expect(recovered.quarantineSHA256 == CanonicalJSON.sha256Hex(Data(#"{"journal_sequence":6"#.utf8)))
        #expect(try fixture.snapshot(excludingJournal: true) == original)
        #expect(FileManager.default.fileExists(atPath: fixture.recoveredURL.path))
        #expect(FileManager.default.fileExists(atPath: fixture.quarantineBytesURL.path))
        #expect(try Data(contentsOf: fixture.quarantineBytesURL) == Data(#"{"journal_sequence":6"#.utf8))

        let replayable = try CaptureRecovery.inspect(root: fixture.recoveredURL)
        #expect(replayable.finalization.state == .recoveredPrefix)
        #expect(replayable.acceptedJournalRecordCount == 6)
        #expect(replayable.firstInvalidJournalSequence == nil)
    }

    @Test("a hash-invalid final record is a suffix but accepted-record corruption is fatal")
    func corruptSuffixVersusInterior() throws {
        let suffix = try RecoveryFixture.openArchive()
        defer { suffix.remove() }
        var finalEntry = try suffix.journalObjects().last!
        finalEntry["content_sha256"] = String(repeating: "0", count: 64)
        try suffix.replaceJournal(objects: Array(try suffix.journalObjects().dropLast()) + [finalEntry])

        let recovered = try CaptureRecovery.inspect(root: suffix.archiveURL)
        #expect(recovered.acceptedJournalRecordCount == 5)
        #expect(recovered.firstInvalidJournalSequence == 5)

        let interior = try RecoveryFixture.openArchive()
        defer { interior.remove() }
        var objects = try interior.journalObjects()
        objects[2]["content_sha256"] = String(repeating: "0", count: 64)
        try interior.replaceJournal(objects: objects)

        #expect(throws: CaptureRecoveryError.interiorCorruption) {
            try CaptureRecovery.inspect(root: interior.archiveURL)
        }
        #expect(FileManager.default.fileExists(atPath: interior.recoveredURL.path) == false)
    }

    @Test(
        "first-record corruption and interior adjacency failures never skip ahead",
        arguments: [RecoveryJournalMutation.firstRecord, .gap, .reorder]
    )
    func journalAdjacency(_ mutation: RecoveryJournalMutation) throws {
        let fixture = try RecoveryFixture.openArchive()
        defer { fixture.remove() }
        try fixture.mutateJournal(mutation)

        #expect(throws: mutation == .firstRecord
            ? CaptureRecoveryError.noRecoverablePrefix
            : CaptureRecoveryError.nonContiguousJournal
        ) {
            try CaptureRecovery.inspect(root: fixture.archiveURL)
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
            try CaptureRecovery.inspect(root: fixture.archiveURL)
        }
    }

    @Test("missing or empty launch inventory has a stable rejection")
    func missingAndEmptyLaunchInputs() throws {
        let missing = try RecoveryFixture.emptyArchive()
        defer { missing.remove() }
        #expect(throws: CaptureRecoveryError.missingManifest) {
            try CaptureRecovery.inspect(root: missing.archiveURL)
        }

        let empty = try RecoveryFixture.openArchive()
        defer { empty.remove() }
        try Data().write(to: empty.journalURL)
        #expect(throws: CaptureRecoveryError.emptyJournal) {
            try CaptureRecovery.inspect(root: empty.archiveURL)
        }
    }

    @Test("recovery is idempotent and never resumes or rewrites the interrupted archive")
    func repeatedRecovery() throws {
        let fixture = try RecoveryFixture.openArchive()
        defer { fixture.remove() }
        let suffix = Data("not-json".utf8)
        try fixture.appendJournal(suffix)
        let original = try fixture.snapshot()

        let first = try CaptureRecovery.inspect(root: fixture.archiveURL)
        let published = try RecoveryFixture.snapshot(of: fixture.recoveredURL)
        let second = try CaptureRecovery.inspect(root: fixture.archiveURL)

        #expect(first == second)
        #expect(try fixture.snapshot() == original)
        #expect(try RecoveryFixture.snapshot(of: fixture.recoveredURL) == published)
    }

    @Test("a pre-publication failure leaves no accepted partial recovered archive")
    func publicationRollback() throws {
        let fixture = try RecoveryFixture.openArchive()
        defer { fixture.remove() }
        try fixture.appendJournal(Data("torn".utf8))
        let original = try fixture.snapshot()

        #expect(throws: InjectedRecoveryPublicationFailure.self) {
            try CaptureRecovery.inspect(root: fixture.archiveURL) { stage in
                if stage == .beforePublish { throw InjectedRecoveryPublicationFailure() }
            }
        }

        #expect(try fixture.snapshot() == original)
        #expect(FileManager.default.fileExists(atPath: fixture.recoveredURL.path) == false)
        #expect(FileManager.default.fileExists(atPath: fixture.quarantineRootURL.path) == false)
        #expect(fixture.stagingPaths.isEmpty)
    }
}

private struct InjectedRecoveryPublicationFailure: Error {}

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
        case .wrongRawHash, .wrongEventRecordHash, .wrongPacketHash, .wrongManifestHash:
            .digestMismatch
        case .unsupportedVersion: .unsupportedContractVersion
        case .unsupportedCodec: .unsupportedCodec
        case .unsupportedDigestAlgorithm, .unsupportedDigestScope: .unsupportedDigest
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
        if excludingJournal { values.removeValue(forKey: "journal/global.jsonl") }
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
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return root.appendingPathComponent("fixtures/capture/1.0.0/rev-001/archives")
    }

    private static func canonical(_ value: Any) throws -> Data {
        let encoded = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return try CanonicalJSON.canonicalize(jsonData: encoded)
    }
}
