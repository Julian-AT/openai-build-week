import Foundation
import ReRoomContracts
import Testing

@testable import ReRoomCaptureCore

@Suite("ReplayCoreTests")
struct ReplayCoreTests {
    @Test(
        "finalized and recovered archives expose only journal-authorized snapshots",
        arguments: [
            ("finalized-empty.rrcap", CaptureFinalizationState.finalized, 2, 0, 2,
             "a2e96a9cd56970bd5662771fb3c811d5f37c193a2fcbfa467a4011ac7557b5cd",
             "4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945",
             "01f737418108c622e858776ece30e2bed9af230fbabff081311a98fdb22c1cdb",
             "7324ce53148183fa257cd983c8f2417dfecaa16b605cdd89ee942f52bbf1882e"),
            ("finalized-one-frame.rrcap", .finalized, 8, 1, 7,
             "236daa228c1d5ebe91e5e332263ed3a9168a5cfd6d991b29bab0ddc395ed69eb",
             "0f710fc1527b278bd3b3c8f137487b5690de5ab2e14049a8f37ccee26ddc0466",
             "869db922b2e28b7534be6d1ee99dd9202d82eee60f8f3251f66b575f80b8b14b",
             "ccd7b8ea7bf8c707a87d81f220cf08307e0888b7b35e535095b493daf5da282f"),
            ("recovered-prefix.rrcap", .recoveredPrefix, 6, 1, 5,
             "26d33f49df29526f231e1c59ff9702c5fc68984d235cd3e7e86c1b48a7cbbd47",
             "b13c45203086ba4b398c80a7281d104bb3abbbf3129e29549837c3f29d9aa9dd",
             "934cede735932fc62d2c7a341a229a0be5acef82c9c0b96fb96e97bfa6462325",
             "f4560e1898672e49135b96137dbcc8a86348b37d500e50df8e87455c0a8e43d6"),
        ]
    )
    func positiveArchives(
        archiveName: String,
        state: CaptureFinalizationState,
        journalCount: Int,
        frameCount: Int,
        eventCount: Int,
        journalDigest: String,
        frameDigest: String,
        eventDigest: String,
        revisionDigest: String
    ) throws {
        let replay = try ReplayCore.replay(try ReplayFixture.verifiedArchive(archiveName))

        #expect(replay.finalization.state == state)
        #expect(replay.timeline.count == journalCount)
        #expect(replay.finalization.acceptedFrameCount == frameCount)
        #expect(replay.finalization.eventCount == eventCount)
        #expect(replay.digests.journalTupleSHA256 == journalDigest)
        #expect(replay.digests.frameProjectionSHA256 == frameDigest)
        #expect(replay.digests.eventProjectionSHA256 == eventDigest)
        #expect(replay.digests.revisionTraceSHA256 == revisionDigest)
        #expect(replay.timeline.map(\.journalSequence) == (0..<UInt64(journalCount)).map { $0 })
        #expect(replay.timeline.filter { $0.entryType == .frame }.count == frameCount)
        #expect(replay.timeline.filter { $0.entryType == .event }.count == eventCount)
    }

    @Test("the valid zero-frame archive still replays its ordered session events")
    func validEmptyFrameProjection() throws {
        let replay = try ReplayCore.replay(
            try ReplayFixture.verifiedArchive("finalized-empty.rrcap")
        )

        #expect(replay.timeline.map(\.entryType) == [.event, .event])
        #expect(replay.timeline.map(\.journalSequence) == [0, 1])
        #expect(replay.finalization.acceptedFrameCount == 0)
    }

    @Test("two sequential reports are canonical and byte-identical")
    func sequentialReportIdentity() throws {
        let archive = try ReplayFixture.verifiedArchive("finalized-one-frame.rrcap")
        let first = try ReplayCore.replay(archive)
        let second = try ReplayCore.replay(archive)
        let firstReport = try ReplayReport.make(
            snapshot: first,
            caseID: "archive.finalized-one-frame",
            fixtureManifestSHA256: ReplayFixture.fixtureManifestSHA256,
            repositoryRevision: ReplayFixture.repositoryRevision
        )
        let secondReport = try ReplayReport.make(
            snapshot: second,
            caseID: "archive.finalized-one-frame",
            fixtureManifestSHA256: ReplayFixture.fixtureManifestSHA256,
            repositoryRevision: ReplayFixture.repositoryRevision
        )
        let firstBytes = try ReplayReport.encode(firstReport)
        let secondBytes = try ReplayReport.encode(secondReport)

        #expect(first == second)
        #expect(firstReport == secondReport)
        #expect(firstBytes == secondBytes)
        #expect(firstReport.verdict == .accept)
        #expect(firstReport.rejection == nil)
        #expect(firstReport.reportSHA256 == ReplayFixture.reportDigest(firstBytes))
        #expect(try CanonicalJSON.canonicalize(jsonData: firstBytes) == firstBytes)
        #expect(ReplayFixture.reportKeys(firstBytes) == Set([
            "archive", "digests", "evaluator", "fixture", "implementation", "metrics",
            "rejection", "report_sha256", "report_version", "verdict",
        ]))
    }

    @Test("two concurrent readers and report encoders emit the same verified bytes")
    func concurrentReportIdentity() async throws {
        let archive = try ReplayFixture.verifiedArchive("recovered-prefix.rrcap")
        async let first = ReplayCore.replay(archive)
        async let second = ReplayCore.replay(archive)
        let snapshots = try await (first, second)

        let firstReport = try ReplayReport.make(
            snapshot: snapshots.0,
            caseID: "archive.recovered-prefix",
            fixtureManifestSHA256: ReplayFixture.fixtureManifestSHA256,
            repositoryRevision: ReplayFixture.repositoryRevision
        )
        let secondReport = try ReplayReport.make(
            snapshot: snapshots.1,
            caseID: "archive.recovered-prefix",
            fixtureManifestSHA256: ReplayFixture.fixtureManifestSHA256,
            repositoryRevision: ReplayFixture.repositoryRevision
        )
        async let firstBytes = ReplayReport.encode(firstReport)
        async let secondBytes = ReplayReport.encode(secondReport)

        #expect(snapshots.0 == snapshots.1)
        #expect(try await firstBytes == secondBytes)
    }

    @Test(
        "independent archive mutations reject before any replay snapshot exists",
        arguments: ReplayMutation.allCases
    )
    func failClosedMutations(_ mutation: ReplayMutation) throws {
        let fixture = try ReplayFixture.mutableArchive()
        defer { fixture.remove() }
        try fixture.mutate(mutation)

        #expect(throws: mutation.expectedAdmissionError) {
            try ReplayFixture.verifier().verify(root: fixture.archiveURL)
        }
    }

    @Test(
        "post-verification member changes reject before replay exposure",
        arguments: ReplayPostVerificationMutation.allCases
    )
    func postVerificationMutations(_ mutation: ReplayPostVerificationMutation) throws {
        let fixture = try ReplayFixture.mutableArchive()
        defer { fixture.remove() }
        let archive = try ReplayFixture.verifier().verify(root: fixture.archiveURL)
        try fixture.mutateAfterVerification(mutation)

        #expect(throws: mutation.expectedError) {
            try ReplayCore.replay(archive)
        }
    }

    @Test("unrelated filesystem noise does not alter verified replay")
    func unrelatedNoise() throws {
        let fixture = try ReplayFixture.mutableArchive()
        defer { fixture.remove() }
        let archive = try ReplayFixture.verifier().verify(root: fixture.archiveURL)
        let expected = try ReplayCore.replay(archive)
        try Data("not an inventory member".utf8).write(
            to: fixture.archiveURL.appendingPathComponent("unrelated-noise.bin")
        )

        #expect(try ReplayCore.replay(archive) == expected)
    }

    @Test("public replay requires the opaque capability and has no raw URL overload")
    func capabilityOnlySurface() throws {
        let replaySource = try String(contentsOf: ReplayFixture.replayCoreSource, encoding: .utf8)
        let verifierSource = try String(contentsOf: ReplayFixture.archiveVerifierSource, encoding: .utf8)
        let replayCore = try #require(
            replaySource.split(separator: "public enum ReplayInputIntegrity", maxSplits: 1).first
        )
        let capabilityBody = try #require(
            verifierSource.split(separator: "public struct VerifiedArchive: Sendable", maxSplits: 1).last?
                .split(separator: "struct VerifiedRecoverySource", maxSplits: 1).first
        )

        #expect(replayCore.contains("public static func replay(_ archive: VerifiedArchive)"))
        #expect(replayCore.contains("replay(root:") == false)
        #expect(capabilityBody.contains("fileprivate init(storage:") == true)
        #expect(capabilityBody.contains("public init") == false)
        #expect(capabilityBody.contains("package init") == false)
        try ReplayFixture.requireExternalConstructionFailure()
    }

    @Test("report encoding rejects a changed self digest")
    func reportSelfDigest() throws {
        let snapshot = try ReplayCore.replay(
            try ReplayFixture.verifiedArchive("finalized-empty.rrcap")
        )
        let report = try ReplayReport.make(
            snapshot: snapshot,
            caseID: "archive.finalized-empty",
            fixtureManifestSHA256: ReplayFixture.fixtureManifestSHA256,
            repositoryRevision: ReplayFixture.repositoryRevision
        )
        let invalid = try ReplayReportV1(
            evaluator: report.evaluator,
            fixture: report.fixture,
            archive: report.archive,
            implementation: report.implementation,
            verdict: report.verdict,
            digests: report.digests,
            rejection: report.rejection,
            metrics: report.metrics,
            reportSHA256: String(repeating: "0", count: 64)
        )

        #expect(throws: ReplayReportError.digestMismatch) {
            try ReplayReport.encode(invalid)
        }
    }
}

enum ReplayMutation: CaseIterable, Sendable {
    case rawByte
    case manifestSelfDigest
    case eventProjectionOrder
    case journalGap
    case digestScope
    case unknownProperty

    var expectedAdmissionError: ArchiveVerificationError {
        switch self {
        case .rawByte, .manifestSelfDigest:
            .digestMismatch
        case .journalGap: .nonContiguousJournal
        case .digestScope: .schemaValidation
        case .eventProjectionOrder: .projectionMismatch
        case .unknownProperty: .unknownProperty
        }
    }
}

enum ReplayPostVerificationMutation: CaseIterable, Sendable {
    case replaceImage
    case symlinkEvent
    case truncatePacket
    case changeJournal

    var expectedError: ReplayCoreError {
        switch self {
        case .symlinkEvent: .invalidPath
        case .replaceImage, .truncatePacket, .changeJournal: .digestMismatch
        }
    }
}

private final class ReplayFixture {
    static let repositoryRevision = "git:" + String(repeating: "a", count: 40)
    static let manifestDigest = "c97349820ed66fb1a1fdf60ea9afee312f532811602851d01d1e233641730b87"
    static let framePacketDigest = "d50b19bfb29c6c62c494e3a47deb3c51a933609698f4ff2f9cbfba6ec4252b43"

    let rootURL: URL
    let archiveURL: URL

    init(rootURL: URL, archiveURL: URL) {
        self.rootURL = rootURL
        self.archiveURL = archiveURL
    }

    static func archive(_ name: String) -> URL {
        fixtureRoot.appendingPathComponent("archives/\(name)")
    }

    static func verifiedArchive(_ name: String) throws -> VerifiedArchive {
        try verifier().verify(root: archive(name))
    }

    static func verifier() throws -> ArchiveVerifier {
        let contracts = repositoryRoot.appendingPathComponent("docs/contracts")
        let registrations: [(ContractSchemaIdentifier, String, String)] = [
            (.framePacket, "frame-packet.schema.json", framePacketDigest),
            (.rrcapManifest, "rrcap-manifest.schema.json", manifestDigest),
            (.sceneState, "scene-state.schema.json", "9c77d27762e20ff5fad24c438e8817a03c770b55be3fc82ea72097c4c273e440"),
            (.editArtifacts, "edit-artifacts.schema.json", "58dbfc8f152881cbdc31be22f6ab7631ac474bb78537ac2a9254f5ef16bd598f"),
            (.transaction, "transaction.schema.json", "2a4f6728978db0879b5dfb10f052f6d5280e5cf83ad5600f0cf959626c2399a2"),
        ]
        let validator = try ContractValidator(registrations: registrations.map { identifier, name, digest in
            ContractSchemaRegistration(
                identifier: identifier,
                version: "1.0.0",
                sha256: digest,
                schemaData: try Data(contentsOf: contracts.appendingPathComponent(name))
            )
        })
        return ArchiveVerifier(validator: validator)
    }

    static func mutableArchive() throws -> ReplayFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("reroom-replay-\(UUID().uuidString.lowercased())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let archive = root.appendingPathComponent("fixture.rrcap")
        try FileManager.default.copyItem(at: self.archive("finalized-one-frame.rrcap"), to: archive)
        return ReplayFixture(rootURL: root, archiveURL: archive)
    }

    func remove() { try? FileManager.default.removeItem(at: rootURL) }

    func mutate(_ mutation: ReplayMutation) throws {
        var manifest = try manifestObject()
        switch mutation {
        case .rawByte:
            let files = manifest["files"] as! [[String: Any]]
            let path = files.first { $0["role"] as? String == "event_log" }!["relative_path"] as! String
            try Data("tampered".utf8).write(to: archiveURL.appendingPathComponent(path))
        case .manifestSelfDigest:
            var finalization = manifest["finalization"] as! [String: Any]
            finalization["manifest_sha256"] = String(repeating: "0", count: 64)
            manifest["finalization"] = finalization
            try writeManifest(manifest, recomputingDigest: false)
        case .eventProjectionOrder:
            var events = manifest["events"] as! [[String: Any]]
            events.swapAt(0, 1)
            manifest["events"] = events
            try writeManifest(manifest)
        case .journalGap:
            var journal = manifest["journal"] as! [[String: Any]]
            journal[1]["journal_sequence"] = 2
            manifest["journal"] = journal
            try writeManifest(manifest)
        case .digestScope:
            var replay = manifest["replay"] as! [String: Any]
            replay["input_digest_scope"] = "timestamp_order"
            manifest["replay"] = replay
            try writeManifest(manifest)
        case .unknownProperty:
            manifest["unexpected"] = true
            try writeManifest(manifest)
        }
    }

    func mutateAfterVerification(_ mutation: ReplayPostVerificationMutation) throws {
        let manifest = try manifestObject()
        let files = manifest["files"] as! [[String: Any]]
        switch mutation {
        case .replaceImage:
            let path = files.first { $0["role"] as? String == "frame_image" }!["relative_path"] as! String
            try Data("substituted image".utf8).write(to: archiveURL.appendingPathComponent(path))
        case .symlinkEvent:
            let path = files.first { $0["role"] as? String == "event_log" }!["relative_path"] as! String
            let memberURL = archiveURL.appendingPathComponent(path)
            let copyURL = rootURL.appendingPathComponent("event-copy.json")
            try FileManager.default.copyItem(at: memberURL, to: copyURL)
            try FileManager.default.removeItem(at: memberURL)
            try FileManager.default.createSymbolicLink(at: memberURL, withDestinationURL: copyURL)
        case .truncatePacket:
            let path = files.first { $0["role"] as? String == "frame_metadata" }!["relative_path"] as! String
            let memberURL = archiveURL.appendingPathComponent(path)
            let bytes = try Data(contentsOf: memberURL)
            try Data(bytes.prefix(32)).write(to: memberURL)
        case .changeJournal:
            var changed = manifest
            var journal = changed["journal"] as! [[String: Any]]
            journal[0]["content_sha256"] = String(repeating: "0", count: 64)
            changed["journal"] = journal
            try Self.canonical(changed).write(to: archiveURL.appendingPathComponent("manifest.json"))
        }
    }

    private func manifestObject() throws -> [String: Any] {
        let data = try Data(contentsOf: archiveURL.appendingPathComponent("manifest.json"))
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    private func writeManifest(
        _ value: [String: Any],
        recomputingDigest: Bool = true
    ) throws {
        var root = value
        if recomputingDigest {
            var finalization = root["finalization"] as! [String: Any]
            finalization.removeValue(forKey: "manifest_sha256")
            root["finalization"] = finalization
            finalization["manifest_sha256"] = CanonicalJSON.sha256Hex(try Self.canonical(root))
            root["finalization"] = finalization
        }
        try Self.canonical(root).write(to: archiveURL.appendingPathComponent("manifest.json"))
    }

    static var fixtureManifestSHA256: String {
        CanonicalJSON.sha256Hex(try! Data(contentsOf: fixtureRoot.appendingPathComponent("manifest.json")))
    }

    static func reportKeys(_ encoded: Data) -> Set<String> {
        let object = try! JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        return Set(object.keys)
    }

    static func reportDigest(_ encoded: Data) -> String {
        var object = try! JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        object.removeValue(forKey: "report_sha256")
        return CanonicalJSON.sha256Hex(try! canonical(object))
    }

    static var replayCoreSource: URL {
        packageRoot.appendingPathComponent("Sources/ReRoomCaptureCore/ReplayCore.swift")
    }

    static var archiveVerifierSource: URL {
        packageRoot.appendingPathComponent("Sources/ReRoomCaptureCore/ArchiveVerifier.swift")
    }

    static func requireExternalConstructionFailure() throws {
        let moduleDirectory = try #require(compiledModuleDirectory)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("reroom-capability-client-\(UUID().uuidString.lowercased())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Client.swift")
        try Data("import ReRoomCaptureCore\nlet make: () -> VerifiedArchive = VerifiedArchive.init\n".utf8)
            .write(to: source)

        let process = Process()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = [
            "swiftc", "-typecheck", "-I", moduleDirectory.path, source.path,
        ]
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let diagnostics = String(
            decoding: stderr.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )

        #expect(process.terminationStatus != 0)
        #expect(diagnostics.contains("VerifiedArchive"))
        #expect(diagnostics.contains("inaccessible") || diagnostics.contains("cannot convert"))
    }

    private static var compiledModuleDirectory: URL? {
        let buildRoot = packageRoot.appendingPathComponent(".build")
        guard let enumerator = FileManager.default.enumerator(
            at: buildRoot,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return nil }
        for case let url as URL in enumerator {
            if url.lastPathComponent == "ReRoomCaptureCore.swiftmodule" {
                return url.deletingLastPathComponent()
            }
        }
        return nil
    }

    private static var repositoryRoot: URL {
        var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return root
    }

    private static var packageRoot: URL {
        repositoryRoot.appendingPathComponent("ios/Packages/ReRoomContracts")
    }

    private static var fixtureRoot: URL {
        repositoryRoot.appendingPathComponent("fixtures/capture/1.0.0/rev-001")
    }

    private static func canonical(_ value: Any) throws -> Data {
        let encoded = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return try CanonicalJSON.canonicalize(jsonData: encoded)
    }
}
