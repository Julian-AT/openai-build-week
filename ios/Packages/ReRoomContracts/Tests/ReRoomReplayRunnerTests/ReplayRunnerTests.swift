import Foundation
import ReRoomContracts
import Testing

@Suite("ReplayRunnerTests")
struct ReplayRunnerTests {
    static let revision = "git:" + String(repeating: "b", count: 40)

    @Test("package exposes the named local-only replay executable")
    func packageShape() throws {
        let fixture = try ReplayRunnerFixture.make()
        defer { fixture.remove() }
        let result = try fixture.runProcess(
            executable: URL(fileURLWithPath: "/usr/bin/swift"),
            arguments: ["package", "--package-path", fixture.packageRoot.path, "dump-package"]
        )

        #expect(result.status == 0)
        let package = try #require(
            JSONSerialization.jsonObject(with: result.standardOutput) as? [String: Any]
        )
        let products = try #require(package["products"] as? [[String: Any]])
        let targets = try #require(package["targets"] as? [[String: Any]])
        #expect(products.contains { $0["name"] as? String == "ReRoomReplayRunner" })
        let target = try #require(targets.first { $0["name"] as? String == "ReRoomReplayRunner" })
        let dependencies = try #require(target["dependencies"] as? [[String: Any]])
        #expect(dependencies.count == 1)
        #expect(dependencies[0]["byName"] as? [String] == ["ReRoomCaptureCore", nil].compactMap { $0 })
    }

    @Test("two isolated invocations emit the complete sorted byte-identical report set")
    func completeStableReports() throws {
        let fixture = try ReplayRunnerFixture.make()
        defer { fixture.remove() }
        let first = fixture.scratch.appendingPathComponent("first")
        let second = fixture.scratch.appendingPathComponent("second")

        try fixture.run(outputRoot: first)
        try fixture.run(outputRoot: second)

        let firstFiles = try fixture.reportFiles(first)
        let secondFiles = try fixture.reportFiles(second)
        #expect(firstFiles.map(\.lastPathComponent) == ReplayRunnerFixture.expectedFileNames)
        #expect(secondFiles.map(\.lastPathComponent) == ReplayRunnerFixture.expectedFileNames)
        for (left, right) in zip(firstFiles, secondFiles) {
            let leftBytes = try Data(contentsOf: left)
            let rightBytes = try Data(contentsOf: right)
            #expect(leftBytes == rightBytes)
            #expect(try CanonicalJSON.canonicalize(jsonData: leftBytes) == leftBytes)
            let report = try #require(
                JSONSerialization.jsonObject(with: leftBytes) as? [String: Any]
            )
            #expect(Set(report.keys) == ReplayRunnerFixture.reportKeys)
            #expect(report["report_version"] as? String == "1.0.0")
            #expect(report["report_sha256"] as? String == fixture.reportDigest(report))
            let archive = try #require(report["archive"] as? [String: Any])
            let caseID = try #require(archive["case_id"] as? String)
            #expect(left.lastPathComponent == "\(caseID).replay-report.json")
        }
    }

    @Test(
        "invalid CLI and exclusive output roots fail without accepted publication",
        arguments: ReplayRunnerInvocationMutation.allCases
    )
    func invalidInvocation(_ mutation: ReplayRunnerInvocationMutation) throws {
        let fixture = try ReplayRunnerFixture.make()
        defer { fixture.remove() }
        let output = fixture.scratch.appendingPathComponent("invalid-\(mutation.rawValue)")
        let result = try fixture.invoke(outputRoot: output, mutation: mutation)

        #expect(result.status != 0)
        #expect(result.standardError.contains("replay-runner: FAIL:"))
        if mutation == .preexistingOutput {
            #expect(try FileManager.default.contentsOfDirectory(atPath: output.path).isEmpty)
        } else {
            #expect(FileManager.default.fileExists(atPath: output.path) == false)
        }
    }

    @Test(
        "manifest and fixture drift fail before any report root is published",
        arguments: ReplayRunnerFixtureMutation.allCases
    )
    func invalidFixture(_ mutation: ReplayRunnerFixtureMutation) throws {
        let fixture = try ReplayRunnerFixture.make()
        defer { fixture.remove() }
        let mutatedManifest = try fixture.mutatedFixture(mutation)
        let output = fixture.scratch.appendingPathComponent("drift-\(mutation.rawValue)")

        let result = try fixture.invoke(outputRoot: output, manifest: mutatedManifest)

        #expect(result.status != 0)
        #expect(result.standardError.contains("replay-runner: FAIL:"))
        #expect(FileManager.default.fileExists(atPath: output.path) == false)
    }
}

enum ReplayRunnerInvocationMutation: String, CaseIterable, Equatable, Sendable {
    case missingArgument
    case unknownArgument
    case invalidRevision
    case preexistingOutput
    case symlinkOutput
}

enum ReplayRunnerFixtureMutation: String, CaseIterable, Sendable {
    case omittedArchive
    case duplicateArchive
    case reorderedArchives
    case sourceManifestDrift
    case rawArchiveDrift
}

private struct ReplayRunnerFixture {
    static let expectedCaseIDs = [
        "archive.finalized-empty",
        "archive.finalized-one-frame",
        "archive.recovered-prefix",
        "fr-b0.adjacency",
        "fr-b0.concurrency",
        "fr-b0.empty",
        "fr-b0.ordering",
        "fr-capture.adjacency",
        "fr-capture.boundary",
        "fr-capture.concurrency",
        "fr-capture.empty",
        "fr-capture.ordering",
        "fr-capture.precision",
        "nfr-replay.assumption",
        "sec-consent.concurrent-session-separation",
        "sec-consent.denied",
    ]
    static let expectedFileNames = expectedCaseIDs.map { "\($0).replay-report.json" }
    static let reportKeys = Set([
        "archive", "digests", "evaluator", "fixture", "implementation", "metrics",
        "rejection", "report_sha256", "report_version", "verdict",
    ])

    let packageRoot: URL
    let repositoryRoot: URL
    let scratch: URL

    var executable: URL { packageRoot.appendingPathComponent(".build/debug/ReRoomReplayRunner") }
    var manifest: URL {
        repositoryRoot.appendingPathComponent("fixtures/capture/1.0.0/rev-001/manifest.json")
    }

    static func make() throws -> ReplayRunnerFixture {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        var repositoryRoot = packageRoot
        while FileManager.default.fileExists(
            atPath: repositoryRoot.appendingPathComponent(".git").path
        ) == false {
            let parent = repositoryRoot.deletingLastPathComponent()
            guard parent.path != repositoryRoot.path else {
                throw ReplayRunnerTestError.repositoryRootNotFound
            }
            repositoryRoot = parent
        }
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("reroom-replay-runner-\(UUID().uuidString.lowercased())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: false)
        return ReplayRunnerFixture(
            packageRoot: packageRoot,
            repositoryRoot: repositoryRoot,
            scratch: scratch
        )
    }

    func remove() { try? FileManager.default.removeItem(at: scratch) }

    func run(outputRoot: URL) throws {
        let result = try invoke(outputRoot: outputRoot)
        guard result.status == 0 else {
            throw ReplayRunnerTestError.runnerFailed(result.standardError)
        }
    }

    func invoke(
        outputRoot: URL,
        manifest: URL? = nil,
        mutation: ReplayRunnerInvocationMutation? = nil
    ) throws -> ReplayRunnerProcessResult {
        var arguments = [
            "--manifest", (manifest ?? self.manifest).path,
            "--output-root", outputRoot.path,
            "--repo-root", repositoryRoot.path,
            "--implementation-revision", ReplayRunnerTests.revision,
        ]
        switch mutation {
        case .missingArgument:
            arguments.removeLast()
        case .unknownArgument:
            arguments += ["--unexpected", "value"]
        case .invalidRevision:
            arguments[arguments.count - 1] = "git:ABC"
        case .preexistingOutput:
            try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: false)
        case .symlinkOutput:
            let target = scratch.appendingPathComponent("symlink-target")
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
            try FileManager.default.createSymbolicLink(at: outputRoot, withDestinationURL: target)
        case nil:
            break
        }
        return try runProcess(executable: executable, arguments: arguments)
    }

    func runProcess(executable: URL, arguments: [String]) throws -> ReplayRunnerProcessResult {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = standardOutput
        process.standardError = standardError
        try process.run()
        process.waitUntilExit()
        return ReplayRunnerProcessResult(
            status: process.terminationStatus,
            standardOutput: standardOutput.fileHandleForReading.readDataToEndOfFile(),
            standardError: String(
                decoding: standardError.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            )
        )
    }

    func reportFiles(_ root: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey]
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func reportDigest(_ report: [String: Any]) -> String {
        var unsigned = report
        unsigned.removeValue(forKey: "report_sha256")
        let json = try! JSONSerialization.data(withJSONObject: unsigned, options: [.sortedKeys])
        let canonical = try! CanonicalJSON.canonicalize(jsonData: json)
        return CanonicalJSON.sha256Hex(canonical)
    }

    func mutatedFixture(_ mutation: ReplayRunnerFixtureMutation) throws -> URL {
        let copiedRoot = scratch.appendingPathComponent("fixture-\(mutation.rawValue)")
        try FileManager.default.copyItem(
            at: manifest.deletingLastPathComponent(),
            to: copiedRoot
        )
        let copiedManifest = copiedRoot.appendingPathComponent("manifest.json")
        if mutation == .rawArchiveDrift {
            let file = copiedRoot.appendingPathComponent(
                "archives/finalized-empty.rrcap/events/event_0000.json"
            )
            try Data("tampered".utf8).write(to: file)
            return copiedManifest
        }

        var object = try JSONSerialization.jsonObject(
            with: Data(contentsOf: copiedManifest)
        ) as! [String: Any]
        var archives = object["archives"] as! [[String: Any]]
        switch mutation {
        case .omittedArchive:
            archives.removeLast()
        case .duplicateArchive:
            archives.append(archives[0])
        case .reorderedArchives:
            archives.swapAt(0, 1)
        case .sourceManifestDrift:
            object["description"] = "drifted"
        case .rawArchiveDrift:
            break
        }
        object["archives"] = archives
        let encoded = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try CanonicalJSON.canonicalize(jsonData: encoded).write(to: copiedManifest)
        return copiedManifest
    }
}

private struct ReplayRunnerProcessResult {
    let status: Int32
    let standardOutput: Data
    let standardError: String
}

private enum ReplayRunnerTestError: Error {
    case repositoryRootNotFound
    case runnerFailed(String)
}
