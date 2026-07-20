import Foundation
import Testing

@Suite("RunnerTests")
struct RunnerTests {
    static let implementationRevision = "git:" + String(repeating: "a", count: 40)

    @Test("the Swift runner emits a stable complete ordered result")
    func stableCompleteResult() throws {
        let fixture = try RunnerFixture.make()
        defer { fixture.remove() }
        let first = fixture.scratch.appendingPathComponent("first.json")
        let second = fixture.scratch.appendingPathComponent("second.json")

        try fixture.run(manifest: fixture.jcsManifest, output: first)
        try fixture.run(manifest: fixture.jcsManifest, output: second)

        let firstBytes = try Data(contentsOf: first)
        let secondBytes = try Data(contentsOf: second)
        #expect(firstBytes == secondBytes)
        let result = try #require(
            JSONSerialization.jsonObject(with: firstBytes) as? [String: Any]
        )
        let runner = try #require(result["runner"] as? [String: Any])
        let caseResults = try #require(result["case_results"] as? [[String: Any]])
        let caseIDs = try caseResults.map { try #require($0["case_id"] as? String) }

        #expect(runner["runtime"] as? String == "swift")
        #expect(caseIDs.count == 12)
        #expect(caseIDs == caseIDs.sorted())
        #expect(Set(caseIDs).count == caseIDs.count)
    }

    @Test(
        "the Swift runner rejects incomplete duplicate and unknown manifests",
        arguments: ManifestMutation.allCases
    )
    func rejectsInvalidManifests(mutation: ManifestMutation) throws {
        let fixture = try RunnerFixture.make()
        defer { fixture.remove() }
        let manifest = try fixture.mutatedManifest(mutation)
        let output = fixture.scratch.appendingPathComponent("invalid-\(mutation.rawValue).json")

        let process = try fixture.invoke(manifest: manifest, output: output)

        #expect(process.status != 0)
        #expect(process.standardError.contains("runner: FAIL:"))
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }
}

enum ManifestMutation: String, CaseIterable, Sendable {
    case omittedCase
    case duplicateCase
    case unknownFixture
}

private struct RunnerFixture {
    let packageRoot: URL
    let repositoryRoot: URL
    let scratch: URL

    var executable: URL {
        packageRoot.appendingPathComponent(".build/debug/ReRoomContractRunner")
    }

    var jcsManifest: URL {
        repositoryRoot.appendingPathComponent(
            "fixtures/policies/RR-JCS-SHA256-1/rev-001/manifest.json"
        )
    }

    static func make() throws -> RunnerFixture {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        var repositoryRoot = packageRoot
        while !FileManager.default.fileExists(
            atPath: repositoryRoot.appendingPathComponent(".git").path
        ) {
            let parent = repositoryRoot.deletingLastPathComponent()
            guard parent.path != repositoryRoot.path else {
                throw RunnerTestError.repositoryRootNotFound
            }
            repositoryRoot = parent
        }
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("reroom-swift-runner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        return RunnerFixture(
            packageRoot: packageRoot,
            repositoryRoot: repositoryRoot,
            scratch: scratch
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: scratch)
    }

    func run(manifest: URL, output: URL) throws {
        let result = try invoke(manifest: manifest, output: output)
        guard result.status == 0 else {
            throw RunnerTestError.runnerFailed(result.standardError)
        }
    }

    func invoke(manifest: URL, output: URL) throws -> ProcessResult {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = executable
        process.arguments = [
            "--manifest", manifest.path,
            "--output", output.path,
            "--repo-root", repositoryRoot.path,
            "--implementation-revision", RunnerTests.implementationRevision,
        ]
        process.standardOutput = standardOutput
        process.standardError = standardError
        try process.run()
        process.waitUntilExit()
        return ProcessResult(
            status: process.terminationStatus,
            standardError: String(
                decoding: standardError.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            )
        )
    }

    func mutatedManifest(_ mutation: ManifestMutation) throws -> URL {
        var object = try requireObject(Data(contentsOf: jcsManifest))
        switch mutation {
        case .omittedCase:
            var cases = try requireCases(object)
            cases.removeLast()
            object["cases"] = cases
        case .duplicateCase:
            var cases = try requireCases(object)
            cases.insert(cases[0], at: 1)
            object["cases"] = cases
        case .unknownFixture:
            object["fixture_id"] = "FX-UNKNOWN-999"
        }
        let url = scratch.appendingPathComponent("manifest-\(mutation.rawValue).json")
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try data.write(to: url)
        return url
    }

    private func requireObject(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RunnerTestError.invalidManifest
        }
        return object
    }

    private func requireCases(_ object: [String: Any]) throws -> [[String: Any]] {
        guard let cases = object["cases"] as? [[String: Any]], !cases.isEmpty else {
            throw RunnerTestError.invalidManifest
        }
        return cases
    }
}

private struct ProcessResult {
    let status: Int32
    let standardError: String
}

private enum RunnerTestError: Error {
    case repositoryRootNotFound
    case runnerFailed(String)
    case invalidManifest
}
