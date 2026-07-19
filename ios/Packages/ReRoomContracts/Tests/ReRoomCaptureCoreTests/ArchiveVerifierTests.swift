import Foundation
import ReRoomContracts
import Testing

@testable import ReRoomCaptureCore

@Suite("ArchiveVerifierTests")
struct ArchiveVerifierTests {
    @Test(
        "closed archives mint one deterministic immutable descriptor set",
        arguments: [
            ("finalized-empty.rrcap", CaptureFinalizationState.finalized, 2, 2),
            ("finalized-one-frame.rrcap", .finalized, 8, 9),
            ("recovered-prefix.rrcap", .recoveredPrefix, 6, 7),
        ]
    )
    func closedArchives(
        archiveName: String,
        state: CaptureFinalizationState,
        journalCount: Int,
        memberCount: Int
    ) throws {
        let verifier = ArchiveVerifier(validator: try ArchiveVerifierFixture.validator())
        let first = try verifier.verify(root: ArchiveVerifierFixture.archive(archiveName))
        let second = try verifier.verify(root: ArchiveVerifierFixture.archive(archiveName))

        #expect(first.manifest.finalizationState == state)
        #expect(first.manifest.journalRecordCount == journalCount)
        #expect(first.inventory.memberCount == memberCount)
        #expect(first.members.count == memberCount)
        #expect(first.sourceIdentity == second.sourceIdentity)
        #expect(first.generation == second.generation)
        #expect(first.manifest == second.manifest)
        #expect(first.inventory == second.inventory)
        #expect(first.members == second.members)
        #expect(first.members.map(\.relativePath) == first.members.map(\.relativePath).sorted())
    }

    @Test("a contract-valid open archive is recovery-only")
    func openArchiveIsRecoveryOnly() throws {
        let fixture = try ArchiveVerifierFixture.mutableArchive("recovered-prefix.rrcap")
        defer { fixture.remove() }
        try fixture.mutateManifest { manifest in
            var finalization = manifest["finalization"] as! [String: Any]
            finalization["state"] = "open"
            manifest["finalization"] = finalization
        }
        let verifier = ArchiveVerifier(validator: try ArchiveVerifierFixture.validator())

        #expect(throws: ArchiveVerificationError.archiveOpen) {
            try verifier.verify(root: fixture.archiveURL)
        }
        let recoverySource = try verifier.verifyRecoverySource(root: fixture.archiveURL)
        #expect(recoverySource.manifest.finalizationState == .open)
        #expect(recoverySource.sourceIdentity.sessionID.hasPrefix("session_"))
    }

    @Test(
        "rehashed contract and binding mutations fail before capability minting",
        arguments: ArchiveVerifierMutation.allCases
    )
    func rehashedAdversarialMutations(_ mutation: ArchiveVerifierMutation) throws {
        let fixture = try ArchiveVerifierFixture.mutableArchive("finalized-one-frame.rrcap")
        defer { fixture.remove() }
        try fixture.mutate(mutation)
        let verifier = ArchiveVerifier(validator: try ArchiveVerifierFixture.validator())

        #expect(throws: mutation.expectedError) {
            try verifier.verify(root: fixture.archiveURL)
        }
    }

    @Test("symlinked inventory members are rejected before reading")
    func symlinkedMember() throws {
        let fixture = try ArchiveVerifierFixture.mutableArchive("finalized-one-frame.rrcap")
        defer { fixture.remove() }
        try fixture.replaceImageWithSymlink()
        let verifier = ArchiveVerifier(validator: try ArchiveVerifierFixture.validator())

        #expect(throws: ArchiveVerificationError.invalidPath) {
            try verifier.verify(root: fixture.archiveURL)
        }
    }

    @Test("a member changed after admission cannot retain the prior capability verdict")
    func postAdmissionSubstitution() throws {
        let fixture = try ArchiveVerifierFixture.mutableArchive("finalized-one-frame.rrcap")
        defer { fixture.remove() }
        let verifier = ArchiveVerifier(validator: try ArchiveVerifierFixture.validator())
        let archive = try verifier.verify(root: fixture.archiveURL)
        try fixture.replaceImageBytes()

        #expect(throws: ArchiveVerificationError.digestMismatch) {
            try archive.consumeVerifiedContents()
        }
    }
}

enum ArchiveVerifierMutation: CaseIterable, Sendable {
    case falseConsent
    case invalidFrameID
    case invalidEventType
    case unknownPacketMember
    case sessionMismatch
    case worldMismatch
    case acceptedSequenceInversion
    case journalSequenceInversion
    case lifecycleContradiction
    case idempotencyContradiction
    case invalidRigidTransform
    case unsafePath
    case payloadMismatch
    case inventoryContradiction

    var expectedError: ArchiveVerificationError {
        switch self {
        case .falseConsent, .invalidEventType:
            .schemaValidation
        case .invalidFrameID:
            .invalidIdentity
        case .unknownPacketMember:
            .unknownProperty
        case .sessionMismatch, .worldMismatch, .lifecycleContradiction,
             .idempotencyContradiction, .invalidRigidTransform:
            .semanticInvariant
        case .payloadMismatch:
            .digestMismatch
        case .acceptedSequenceInversion, .inventoryContradiction:
            .projectionMismatch
        case .journalSequenceInversion:
            .nonContiguousJournal
        case .unsafePath:
            .invalidPath
        }
    }
}

private final class ArchiveVerifierFixture {
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

    static func mutableArchive(_ name: String) throws -> ArchiveVerifierFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("reroom-archive-verifier-\(UUID().uuidString.lowercased())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let destination = root.appendingPathComponent("fixture.rrcap")
        try FileManager.default.copyItem(at: archive(name), to: destination)
        return ArchiveVerifierFixture(rootURL: root, archiveURL: destination)
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func mutate(_ mutation: ArchiveVerifierMutation) throws {
        switch mutation {
        case .falseConsent:
            try mutateManifest { manifest in
                var privacy = manifest["privacy"] as! [String: Any]
                privacy["capture_consent_recorded"] = false
                manifest["privacy"] = privacy
            }
        case .invalidFrameID:
            try mutatePacket { packet in packet["frame_id"] = "frame_invalid" }
        case .invalidEventType:
            try mutateEvent(at: 1) { descriptor, payload in
                descriptor["type"] = "invented_transition"
                payload["type"] = "invented_transition"
            }
        case .unknownPacketMember:
            try mutatePacket { packet in packet["unexpected"] = true }
        case .sessionMismatch:
            try mutatePacket { packet in
                packet["session_id"] = "session_ffffffff-ffff-4fff-bfff-ffffffffffff"
            }
        case .worldMismatch:
            try mutatePacket { packet in
                packet["world_frame_id"] = "world_ffffffff-ffff-4fff-bfff-ffffffffffff"
            }
        case .acceptedSequenceInversion:
            try mutateManifest { manifest in
                var frames = manifest["accepted_frame_order"] as! [[String: Any]]
                frames[0]["sequence"] = 1
                manifest["accepted_frame_order"] = frames
            }
        case .journalSequenceInversion:
            try mutateManifest { manifest in
                var journal = manifest["journal"] as! [[String: Any]]
                journal[0]["journal_sequence"] = 1
                manifest["journal"] = journal
            }
        case .lifecycleContradiction:
            try mutatePacket { packet in
                var durability = packet["durability"] as! [String: Any]
                durability["journal_sequence"] = 2
                packet["durability"] = durability
            }
        case .idempotencyContradiction:
            try mutateEvent(at: 1) { _, payload in
                var details = payload["details"] as! [String: Any]
                details["idempotency_key"] = "frameidem_ffffffff-ffff-4fff-bfff-ffffffffffff"
                payload["details"] = details
            }
        case .invalidRigidTransform:
            try mutatePacket { packet in
                var transform = packet["world_from_camera"] as! [String: Any]
                var values = transform["values"] as! [Any]
                values[0] = 2
                transform["values"] = values
                packet["world_from_camera"] = transform
            }
        case .unsafePath:
            try mutateManifest { manifest in
                var files = manifest["files"] as! [[String: Any]]
                files[0]["relative_path"] = "../outside.json"
                manifest["files"] = files
            }
        case .payloadMismatch:
            try mutatePacket { packet in
                packet["payload_sha256"] = String(repeating: "0", count: 64)
            }
        case .inventoryContradiction:
            try mutateManifest { manifest in
                var files = manifest["files"] as! [[String: Any]]
                files.append(files[0])
                manifest["files"] = files
            }
        }
    }

    func mutateManifest(_ body: (inout [String: Any]) throws -> Void) throws {
        var manifest = try manifestObject()
        try body(&manifest)
        try writeManifest(manifest)
    }

    func mutatePacket(_ body: (inout [String: Any]) throws -> Void) throws {
        var manifest = try manifestObject()
        var frames = manifest["accepted_frame_order"] as! [[String: Any]]
        let path = frames[0]["packet_path"] as! String
        let url = archiveURL.appendingPathComponent(path)
        var packet = try Self.object(Data(contentsOf: url))
        try body(&packet)
        let bytes = try Self.canonical(packet)
        try bytes.write(to: url)
        let digest = CanonicalJSON.sha256Hex(bytes)

        var files = manifest["files"] as! [[String: Any]]
        let fileIndex = files.firstIndex { $0["relative_path"] as? String == path }!
        files[fileIndex]["byte_length"] = bytes.count
        files[fileIndex]["sha256"] = digest
        frames[0]["packet_sha256"] = digest
        var journal = manifest["journal"] as! [[String: Any]]
        let sequence = frames[0]["durable_journal_sequence"] as! Int
        journal[sequence]["content_sha256"] = digest
        manifest["files"] = files
        manifest["accepted_frame_order"] = frames
        manifest["journal"] = journal
        try writeManifest(manifest)
    }

    func mutateEvent(
        at index: Int,
        _ body: (inout [String: Any], inout [String: Any]) throws -> Void
    ) throws {
        var manifest = try manifestObject()
        var events = manifest["events"] as! [[String: Any]]
        var descriptor = events[index]
        let path = descriptor["payload_path"] as! String
        let url = archiveURL.appendingPathComponent(path)
        var payload = try Self.object(Data(contentsOf: url))
        try body(&descriptor, &payload)

        let payloadBytes = try Self.canonical(payload)
        try payloadBytes.write(to: url)
        let payloadDigest = CanonicalJSON.sha256Hex(payloadBytes)
        descriptor["payload_sha256"] = payloadDigest
        descriptor.removeValue(forKey: "record_sha256")
        let recordDigest = CanonicalJSON.sha256Hex(try Self.canonical(descriptor))
        descriptor["record_sha256"] = recordDigest
        events[index] = descriptor

        var files = manifest["files"] as! [[String: Any]]
        let fileIndex = files.firstIndex { $0["relative_path"] as? String == path }!
        files[fileIndex]["byte_length"] = payloadBytes.count
        files[fileIndex]["sha256"] = payloadDigest
        var journal = manifest["journal"] as! [[String: Any]]
        let sequence = descriptor["durable_journal_sequence"] as! Int
        journal[sequence]["content_sha256"] = recordDigest
        manifest["files"] = files
        manifest["events"] = events
        manifest["journal"] = journal
        try writeManifest(manifest)
    }

    func replaceImageWithSymlink() throws {
        let manifest = try manifestObject()
        let files = manifest["files"] as! [[String: Any]]
        let path = files.first { $0["role"] as? String == "frame_image" }!["relative_path"] as! String
        let imageURL = archiveURL.appendingPathComponent(path)
        let copyURL = rootURL.appendingPathComponent("image-copy.png")
        try FileManager.default.copyItem(at: imageURL, to: copyURL)
        try FileManager.default.removeItem(at: imageURL)
        try FileManager.default.createSymbolicLink(at: imageURL, withDestinationURL: copyURL)
    }

    func replaceImageBytes() throws {
        let manifest = try manifestObject()
        let files = manifest["files"] as! [[String: Any]]
        let path = files.first { $0["role"] as? String == "frame_image" }!["relative_path"] as! String
        try Data("substituted".utf8).write(to: archiveURL.appendingPathComponent(path))
    }

    func manifestObject() throws -> [String: Any] {
        try Self.object(Data(contentsOf: archiveURL.appendingPathComponent("manifest.json")))
    }

    func writeManifest(_ value: [String: Any]) throws {
        var manifest = value
        var finalization = manifest["finalization"] as! [String: Any]
        finalization.removeValue(forKey: "manifest_sha256")
        manifest["finalization"] = finalization
        finalization["manifest_sha256"] = CanonicalJSON.sha256Hex(try Self.canonical(manifest))
        manifest["finalization"] = finalization
        try Self.canonical(manifest).write(to: archiveURL.appendingPathComponent("manifest.json"))
    }

    static func validator() throws -> ContractValidator {
        let contracts = repositoryRoot.appendingPathComponent("docs/contracts")
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
                schemaData: try Data(contentsOf: contracts.appendingPathComponent(name))
            )
        })
    }

    private static var repositoryRoot: URL {
        var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return root
    }

    private static var fixtureRoot: URL {
        repositoryRoot.appendingPathComponent("fixtures/capture/1.0.0/rev-001")
    }

    private static func object(_ data: Data) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    private static func canonical(_ value: Any) throws -> Data {
        let encoded = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return try CanonicalJSON.canonicalize(jsonData: encoded)
    }
}
