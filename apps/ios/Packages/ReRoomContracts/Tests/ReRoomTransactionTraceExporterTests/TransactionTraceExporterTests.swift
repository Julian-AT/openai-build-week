import Foundation
import ReRoomContracts
import Testing

@Suite("Phase 3 shipping Swift transaction trace exporter")
struct TransactionTraceExporterTests {
    static let revision = "git:" + String(repeating: "a", count: 40)

    @Test("package exposes one shipping-core transaction trace executable")
    func packageShape() throws {
        let fixture = try SwiftTraceFixture.make()
        defer { fixture.remove() }
        let package = try String(contentsOf: fixture.packageRoot.appendingPathComponent("Package.swift"), encoding: .utf8)
        #expect(package.contains(#".executable(name: "ReRoomTransactionTraceExporter""#))
        #expect(package.contains(#"name: "ReRoomTransactionTraceExporter""#))
        #expect(package.contains("ReRoomTransactionCore"))
    }

    @Test("two isolated executable invocations emit complete canonical byte-identical results")
    func completeStableResult() throws {
        let fixture = try SwiftTraceFixture.make()
        defer { fixture.remove() }
        let first = fixture.scratch.appendingPathComponent("first.json")
        let second = fixture.scratch.appendingPathComponent("second.json")
        try fixture.run(output: first)
        try fixture.run(output: second)
        let firstBytes = try Data(contentsOf: first)
        let secondBytes = try Data(contentsOf: second)
        #expect(firstBytes == secondBytes)
        #expect(try CanonicalJSON.canonicalize(jsonData: firstBytes) == firstBytes)

        let result = try #require(JSONSerialization.jsonObject(with: firstBytes) as? [String: Any])
        #expect(result["trace_format"] as? String == "reroom_transaction_trace_v1")
        let fixtureValue = try #require(result["fixture"] as? [String: Any])
        #expect(fixtureValue["fixture_id"] as? String == "FX-TRANSACTION-001")
        #expect(fixtureValue["fixture_revision"] as? String == "rev-001")
        #expect(fixtureValue["manifest_sha256"] as? String == SwiftTraceFixture.fixtureSHA256)
        let runtime = try #require(result["runtime"] as? [String: Any])
        #expect(runtime["language"] as? String == "swift")
        #expect(runtime["name"] as? String == "ReRoomTransactionSwift")
        #expect((runtime["version"] as? String)?.hasPrefix("swift-") == true)
        let implementation = try #require(result["implementation"] as? [String: Any])
        #expect(implementation["repository_revision"] as? String == Self.revision)
        #expect((implementation["source_tree_sha256"] as? String)?.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil)

        let operationOrder = try #require(result["operation_order"] as? [String])
        #expect(operationOrder == ["place", "replace", "remove", "restore"])
        let proposals = try #require(result["proposals"] as? [[String: Any]])
        #expect(proposals.compactMap { $0["operation"] as? String } == operationOrder)
        #expect(proposals.allSatisfy { $0["status"] as? String == "accepted" })
        #expect(proposals.allSatisfy { $0["authority"] as? String == "proposal_only" })
        #expect(proposals.allSatisfy { $0["preauthorized_confirmation"] as? Bool == false })
        #expect(proposals.allSatisfy { $0["preauthorized_commit"] as? Bool == false })
        let replaceBlocker = try #require(proposals[1]["blocker"] as? [String: Any])
        let removeBlocker = try #require(proposals[2]["blocker"] as? [String: Any])
        #expect(replaceBlocker["code"] as? String == "capability_not_ready")
        #expect(replaceBlocker["mutation_count"] as? Int == 0)
        #expect(removeBlocker["code"] as? String == "capability_not_ready")
        #expect(removeBlocker["mutation_count"] as? Int == 0)

        let safety = try #require(result["safety"] as? [String: Any])
        #expect(safety["injection_case_id"] as? String == "intent.transform-injection")
        #expect(safety["injection_verdict"] as? String == "reject")
        #expect(safety["injection_mutation_count"] as? Int == 0)
        let cases = try #require(result["cases"] as? [[String: Any]])
        #expect(cases.count == 24)
        #expect(cases.compactMap { $0["case_id"] as? String } == cases.compactMap { $0["case_id"] as? String }.sorted())
        let traces = try #require(result["traces"] as? [[String: Any]])
        #expect(traces.count == 3)
        let revisions = try #require(result["revisions"] as? [String: Any])
        #expect(revisions["preview_scene_revision"] as? Int == 0)
        #expect(revisions["place_scene_revision"] as? Int == 1)
        #expect(revisions["restore_scene_revision"] as? Int == 2)
        let restore = try #require(result["restore"] as? [String: Any])
        #expect(restore["network_reads"] as? Int == 0)
        #expect(restore["source_transaction_immutable"] as? Bool == true)
        let divergence = try #require(result["divergence"] as? [String: Any])
        #expect(divergence["mutation_frozen"] as? Bool == true)
        #expect(divergence["automatic_merge_permitted"] as? Bool == false)
    }

    @Test("invalid revision and fixture drift reject before output publication")
    func failClosedBoundaries() throws {
        let fixture = try SwiftTraceFixture.make()
        defer { fixture.remove() }
        let invalidRevision = fixture.scratch.appendingPathComponent("invalid-revision.json")
        let revisionResult = try fixture.invoke(output: invalidRevision, revision: "git:HEAD")
        #expect(revisionResult.status != 0)
        #expect(revisionResult.standardError.contains("transaction-swift: FAIL:"))
        #expect(FileManager.default.fileExists(atPath: invalidRevision.path) == false)

        let copied = fixture.scratch.appendingPathComponent("fixture")
        try FileManager.default.copyItem(at: fixture.manifest.deletingLastPathComponent(), to: copied)
        let expected = copied.appendingPathComponent("expected-traces.json")
        var bytes = try Data(contentsOf: expected)
        bytes[0] ^= 1
        try bytes.write(to: expected)
        let driftOutput = fixture.scratch.appendingPathComponent("drift.json")
        let driftResult = try fixture.invoke(output: driftOutput, manifest: copied.appendingPathComponent("manifest.json"))
        #expect(driftResult.status != 0)
        #expect(driftResult.standardError.contains("transaction-swift: FAIL:"))
        #expect(FileManager.default.fileExists(atPath: driftOutput.path) == false)
    }

    @Test("shipping exporter source uses transaction core without cross-runtime output")
    func sourceBoundary() throws {
        let fixture = try SwiftTraceFixture.make()
        defer { fixture.remove() }
        let sourceRoot = fixture.packageRoot.appendingPathComponent("Sources/ReRoomTransactionTraceExporter")
        let source = try FileManager.default.contentsOfDirectory(at: sourceRoot, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        #expect(source.contains("import ReRoomTransactionCore"))
        #expect(source.contains("NativeBranchAuthority"))
        #expect(source.contains("PlaceReducer"))
        #expect(source.contains("RestoreReducer"))
        #expect(source.contains("tools/javascript") == false)
        #expect(source.contains("tools/python") == false)
    }
}

private struct SwiftTraceFixture {
    static let fixtureSHA256 = "4aceda98f3dcb6bc0cf3efaef63852b67a86ea22b0455eb07d3fb9cdd34b371a"
    let packageRoot: URL
    let repositoryRoot: URL
    let scratch: URL
    var executable: URL { packageRoot.appendingPathComponent(".build/debug/ReRoomTransactionTraceExporter") }
    var manifest: URL { repositoryRoot.appendingPathComponent("fixtures/transactions/1.0.0/rev-001/manifest.json") }

    static func make() throws -> Self {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var repositoryRoot = packageRoot
        while !FileManager.default.fileExists(atPath: repositoryRoot.appendingPathComponent(".git").path) {
            let parent = repositoryRoot.deletingLastPathComponent()
            guard parent != repositoryRoot else { throw SwiftTraceTestError.repositoryRootNotFound }
            repositoryRoot = parent
        }
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("reroom-swift-transaction-\(UUID().uuidString.lowercased())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: false)
        return Self(packageRoot: packageRoot, repositoryRoot: repositoryRoot, scratch: scratch)
    }

    func remove() { try? FileManager.default.removeItem(at: scratch) }

    func run(output: URL) throws {
        let result = try invoke(output: output)
        guard result.status == 0 else { throw SwiftTraceTestError.runnerFailed(result.standardError) }
    }

    func invoke(output: URL, manifest: URL? = nil, revision: String = TransactionTraceExporterTests.revision) throws -> SwiftTraceProcessResult {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = executable
        process.arguments = [
            "--manifest", (manifest ?? self.manifest).path,
            "--output", output.path,
            "--repo-root", repositoryRoot.path,
            "--implementation-revision", revision,
        ]
        process.standardOutput = standardOutput
        process.standardError = standardError
        try process.run()
        let outputData = standardOutput.fileHandleForReading.readDataToEndOfFile()
        let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return SwiftTraceProcessResult(
            status: process.terminationStatus,
            standardOutput: outputData,
            standardError: String(decoding: errorData, as: UTF8.self)
        )
    }
}

private struct SwiftTraceProcessResult {
    let status: Int32
    let standardOutput: Data
    let standardError: String
}

private enum SwiftTraceTestError: Error {
    case repositoryRootNotFound
    case runnerFailed(String)
}
