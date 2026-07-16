import Foundation
import Testing

@testable import ReRoomContracts

@Suite("CanonicalJSONTests")
struct CanonicalJSONTests {
    @Test(
        "FX-JCS-001 canonical bytes and digests match the immutable oracle",
        arguments: [
            "jcs.basic-object",
            "jcs.negative-zero",
            "jcs.scope.artifact",
            "jcs.scope.commit",
            "jcs.scope.journal",
            "jcs.scope.manifest",
            "jcs.scope.packet",
            "jcs.scope.projection",
            "jcs.scope.transaction",
            "jcs.scope.validation",
        ]
    )
    func canonicalOracle(caseID: String) throws {
        let fixture = try PolicyFixture.jcs()
        let inputExtension = caseID.hasPrefix("jcs.scope.") ? "json" : "raw"
        let input = try fixture.read("inputs/\(caseID).\(inputExtension)")
        let expected = try fixture.read("expected/\(caseID).jcs")
        let expectedDigest = try fixture.text("expected/\(caseID).sha256")

        let canonical = try CanonicalJSON.canonicalize(jsonData: input)

        #expect(canonical == expected)
        #expect(CanonicalJSON.sha256Hex(canonical) == expectedDigest)
        #expect(try CanonicalJSON.digest(jsonData: input) == expectedDigest)
    }

    @Test(
        "FX-JCS-001 rejects duplicate names and invalid Unicode with stable classes",
        arguments: [
            ("jcs.duplicate-name.raw", CanonicalJSONRejection.duplicateName),
            ("jcs.invalid-unicode.raw", CanonicalJSONRejection.invalidUnicode),
        ]
    )
    func canonicalRejections(file: String, expected: CanonicalJSONRejection) throws {
        let input = try PolicyFixture.jcs().read("inputs/\(file)")

        #expect(throws: expected) {
            try CanonicalJSON.canonicalize(jsonData: input)
        }
    }

    @Test("RFC 8785 number serialization uses ECMAScript shortest forms")
    func rfc8785NumberSerialization() throws {
        let input = Data("[333333333.33333329,1E30,4.50,2e-3,1e-27,1e-6,1e-7]".utf8)
        let expected = "[333333333.3333333,1e+30,4.5,0.002,1e-27,0.000001,1e-7]"
        let actual = String(
            decoding: try CanonicalJSON.canonicalize(jsonData: input),
            as: UTF8.self
        )

        #expect(actual == expected)
    }

    @Test("JCS manifest case order remains lexicographic and authoritative")
    func manifestOrderIsStable() throws {
        let manifest = try PolicyFixture.jcs().jsonObject("manifest.json")
        let cases = try #require(manifest["cases"] as? [[String: Any]])
        let caseIDs = try cases.map { try #require($0["case_id"] as? String) }

        #expect(caseIDs == caseIDs.sorted())
    }

    @Test(
        "archive-relative paths accept normalized ASCII segments",
        arguments: [
            "media/source.mp4",
            "frames/frame_001/image.jpeg",
            "events/import.json",
            "a-b_c/0.1.json",
        ]
    )
    func safeArchivePaths(path: String) throws {
        #expect(throws: Never.self) {
            try ArchivePath.validate(path)
        }
    }

    @Test(
        "archive-relative paths reject absolute traversal backslash empty and confusable forms",
        arguments: [
            "",
            "/absolute",
            "C:/drive",
            "C:\\drive",
            "\\\\server\\share",
            ".",
            "..",
            "a/./b",
            "a/../b",
            "a//b",
            "a\\b",
            ".hidden",
            "a/.hidden",
            "a／b",
            "a∕b",
            "a\0b",
        ]
    )
    func unsafeArchivePaths(path: String) {
        #expect(throws: ArchivePathRejection.invalidPath) {
            try ArchivePath.validate(path)
        }
    }

    @Test("FX-CONTRACT-001 unsafe archive path rejects with invalid_path")
    func contractUnsafePathFixture() throws {
        let descriptor = try PolicyFixture.contractUnsafePath()
        let mutations = try #require(descriptor["mutations"] as? [[String: Any]])
        let mutation = try #require(mutations.first)
        let path = try #require(mutation["value"] as? String)

        #expect(throws: ArchivePathRejection.invalidPath) {
            try ArchivePath.validate(path)
        }
    }

    @Test("archive resolution rejects a symlink that escapes its root")
    func archiveSymlinkEscape() throws {
        let fileManager = FileManager.default
        let scratch = fileManager.temporaryDirectory
            .appendingPathComponent("reroom-archive-path-\(UUID().uuidString)")
        let root = scratch.appendingPathComponent("root")
        let outside = scratch.appendingPathComponent("outside")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: scratch) }
        try fileManager.createSymbolicLink(
            at: root.appendingPathComponent("link"),
            withDestinationURL: outside
        )

        #expect(throws: ArchivePathRejection.invalidPath) {
            try ArchivePath.resolve("link/secret.json", under: root)
        }
    }
}

private struct PolicyFixture {
    let root: URL

    static func jcs() throws -> PolicyFixture {
        PolicyFixture(
            root: try repositoryRoot()
                .appendingPathComponent("fixtures/policies/RR-JCS-SHA256-1/rev-001")
        )
    }

    static func contractUnsafePath() throws -> [String: Any] {
        let data = try Data(
            contentsOf: repositoryRoot().appendingPathComponent(
                "fixtures/contracts/1.0.0/rev-001/cases/contract.con002.unsafe-path.json"
            )
        )
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func read(_ relativePath: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent(relativePath))
    }

    func text(_ relativePath: String) throws -> String {
        try String(decoding: read(relativePath), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func jsonObject(_ relativePath: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: read(relativePath)) as? [String: Any])
    }

    private static func repositoryRoot() throws -> URL {
        let fileManager = FileManager.default
        var cursor = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !fileManager.fileExists(atPath: cursor.appendingPathComponent(".git").path) {
            let parent = cursor.deletingLastPathComponent()
            guard parent.path != cursor.path else { throw PolicyFixtureError.repositoryRootNotFound }
            cursor = parent
        }
        return cursor
    }
}

private enum PolicyFixtureError: Error {
    case repositoryRootNotFound
}
