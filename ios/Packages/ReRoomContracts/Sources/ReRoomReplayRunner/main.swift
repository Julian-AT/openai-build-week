import Foundation
import ReRoomCaptureCore
import ReRoomContracts

private let pinnedManifestSHA256 = "3b4519d2730e158df73e938f7b841664c6ce5f7d65ed2650c90ca8e89c7a7610"
private let pinnedReportSchemaSHA256 = "821784ce1a3e4f45c2fe4db70f8f16643284f2e3e9f6effe85a7aee3e17bb9a9"
private let maximumCases = 2_048

private struct RunnerFailure: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

private struct Options {
    let manifest: URL
    let outputRoot: URL
    let repositoryRoot: URL
    let implementationRevision: String
}

private struct LoadedFixture {
    let root: URL
    let archiveVerifier: ArchiveVerifier
    let manifestSHA256: String
    let archives: [[String: Any]]
    let edgeProbes: [[String: Any]]
    let consentDenied: [String: Any]
    let caseIDs: [String]
}

private func parseOptions(_ arguments: [String]) throws -> Options {
    let names = Set(["--manifest", "--output-root", "--repo-root", "--implementation-revision"])
    guard arguments.count == 8 else {
        throw RunnerFailure("exactly four named arguments are required")
    }
    var values = [String: String]()
    var index = 0
    while index < arguments.count {
        let name = arguments[index]
        guard names.contains(name), values[name] == nil, index + 1 < arguments.count else {
            throw RunnerFailure("unsupported, duplicate, or incomplete argument")
        }
        values[name] = arguments[index + 1]
        index += 2
    }
    guard Set(values.keys) == names,
          let manifest = values["--manifest"],
          let output = values["--output-root"],
          let repository = values["--repo-root"],
          let revision = values["--implementation-revision"],
          revision.range(of: #"^git:[0-9a-f]{40}$"#, options: .regularExpression) != nil
    else { throw RunnerFailure("invalid exact runner arguments") }
    return Options(
        manifest: URL(fileURLWithPath: manifest),
        outputRoot: URL(fileURLWithPath: output),
        repositoryRoot: URL(fileURLWithPath: repository),
        implementationRevision: revision
    )
}

private func readBounded(_ url: URL, maximum: Int = ReplayInputIntegrity.maximumDocumentBytes) throws -> Data {
    let values: URLResourceValues
    do {
        values = try url.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        )
    } catch {
        throw RunnerFailure("input file is unavailable")
    }
    guard values.isRegularFile == true,
          values.isSymbolicLink != true,
          let size = values.fileSize,
          size <= maximum
    else { throw RunnerFailure("input is not a bounded regular file") }
    let data: Data
    do {
        data = try Data(contentsOf: url, options: .mappedIfSafe)
    } catch {
        throw RunnerFailure("input file cannot be read")
    }
    guard data.count == size else { throw RunnerFailure("input changed while being read") }
    return data
}

private func strictObject(_ data: Data) throws -> [String: Any] {
    do {
        _ = try ReplayInputIntegrity.canonicalizeJSON(data)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RunnerFailure("expected a JSON object")
        }
        return object
    } catch let error as RunnerFailure {
        throw error
    } catch {
        throw RunnerFailure("invalid strict JSON")
    }
}

private func requireKeys(_ object: [String: Any], _ expected: Set<String>) throws {
    guard Set(object.keys) == expected else { throw RunnerFailure("unknown or missing manifest property") }
}

private func safeFile(_ path: String, root: URL) throws -> URL {
    do {
        return try ReplayInputIntegrity.resolveArchivePath(path, under: root)
    } catch {
        throw RunnerFailure("unsafe manifest path")
    }
}

private func exactInt(_ value: Any?) -> Int? {
    guard let number = value as? NSNumber,
          number.objCType.pointee != 0x63,
          number.doubleValue >= 0,
          number.doubleValue.rounded(.towardZero) == number.doubleValue,
          number.doubleValue <= Double(Int.max)
    else { return nil }
    return number.intValue
}

private func makeArchiveVerifier(repositoryRoot: URL) throws -> ArchiveVerifier {
    let registrations: [(ContractSchemaIdentifier, String, String)] = [
        (.framePacket, "frame-packet.schema.json", "d50b19bfb29c6c62c494e3a47deb3c51a933609698f4ff2f9cbfba6ec4252b43"),
        (.rrcapManifest, "rrcap-manifest.schema.json", "c97349820ed66fb1a1fdf60ea9afee312f532811602851d01d1e233641730b87"),
        (.sceneState, "scene-state.schema.json", "9c77d27762e20ff5fad24c438e8817a03c770b55be3fc82ea72097c4c273e440"),
        (.editArtifacts, "edit-artifacts.schema.json", "58dbfc8f152881cbdc31be22f6ab7631ac474bb78537ac2a9254f5ef16bd598f"),
        (.transaction, "transaction.schema.json", "2a4f6728978db0879b5dfb10f052f6d5280e5cf83ad5600f0cf959626c2399a2"),
    ]
    do {
        let schemas = try registrations.map { identifier, name, digest in
            ContractSchemaRegistration(
                identifier: identifier,
                version: identifier.version,
                sha256: digest,
                schemaData: try readBounded(
                    safeFile("docs/contracts/\(name)", root: repositoryRoot)
                )
            )
        }
        return ArchiveVerifier(validator: try ContractValidator(registrations: schemas))
    } catch {
        throw RunnerFailure("archive contract registry is invalid")
    }
}

private func loadFixture(_ options: Options) throws -> LoadedFixture {
    let repositoryValues = try? options.repositoryRoot.resourceValues(
        forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
    )
    guard repositoryValues?.isDirectory == true, repositoryValues?.isSymbolicLink != true else {
        throw RunnerFailure("repository root is invalid")
    }
    let manifestBytes = try readBounded(options.manifest)
    let manifestSHA = ReplayInputIntegrity.sha256Hex(manifestBytes)
    guard manifestSHA == pinnedManifestSHA256 else {
        throw RunnerFailure("capture fixture manifest drifted")
    }
    let root = options.manifest.deletingLastPathComponent()
    let object = try strictObject(manifestBytes)
    try requireKeys(object, [
        "archives", "consent_denied_case", "description", "directories", "edge_probes",
        "files", "fixture_id", "fixture_revision", "privacy", "report_schema", "schema_version",
    ])
    guard object["schema_version"] as? String == "1.0.0",
          object["fixture_id"] as? String == "FX-CAPTURE-001",
          object["fixture_revision"] as? String == "rev-001",
          let archives = object["archives"] as? [[String: Any]],
          let probes = object["edge_probes"] as? [[String: Any]],
          let consent = object["consent_denied_case"] as? [String: Any],
          let files = object["files"] as? [[String: Any]],
          let reportSchema = object["report_schema"] as? [String: Any],
          archives.count == 3,
          probes.count == 12,
          files.count <= maximumCases
    else { throw RunnerFailure("capture fixture manifest is incomplete") }

    let archiveNames = try archives.map { archive -> String in
        guard let name = archive["archive_name"] as? String,
              name.hasSuffix(".rrcap"), name.contains("/") == false
        else { throw RunnerFailure("archive identity is invalid") }
        return name
    }
    guard archiveNames == [
        "finalized-empty.rrcap", "finalized-one-frame.rrcap", "recovered-prefix.rrcap",
    ], Set(archiveNames).count == archiveNames.count else {
        throw RunnerFailure("archive set is incomplete, duplicated, or unsorted")
    }

    var seenPaths = Set<String>()
    for file in files {
        guard Set(file.keys) == Set(["byte_length", "relative_path", "sha256"]),
              let path = file["relative_path"] as? String,
              let length = exactInt(file["byte_length"]),
              let digest = file["sha256"] as? String,
              seenPaths.insert(path).inserted
        else { throw RunnerFailure("fixture file inventory is invalid") }
        let data = try readBounded(try safeFile(path, root: root))
        guard data.count == length, ReplayInputIntegrity.sha256Hex(data) == digest else {
            throw RunnerFailure("fixture file digest mismatch")
        }
    }

    guard let schemaPath = reportSchema["relative_path"] as? String,
          let schemaLength = exactInt(reportSchema["byte_length"]),
          reportSchema["sha256"] as? String == pinnedReportSchemaSHA256
    else { throw RunnerFailure("report schema reference is invalid") }
    let schema = try readBounded(try safeFile(schemaPath, root: options.repositoryRoot))
    guard schema.count == schemaLength,
          ReplayInputIntegrity.sha256Hex(schema) == pinnedReportSchemaSHA256
    else { throw RunnerFailure("report schema drifted") }

    let probeIDs = try probes.map { probe -> String in
        guard let caseID = probe["case_id"] as? String, caseID.isEmpty == false else {
            throw RunnerFailure("edge probe identity is invalid")
        }
        return caseID
    }
    guard probeIDs == probeIDs.sorted(), Set(probeIDs).count == probeIDs.count else {
        throw RunnerFailure("edge probe set is duplicated or unsorted")
    }
    guard consent["expected_verdict"] as? String == "reject",
          consent["rejection_class"] as? String == "semantic_invariant",
          consent["archive_created"] as? Bool == false,
          consent["consent_granted"] as? Bool == false
    else { throw RunnerFailure("consent-denied case is invalid") }

    let caseIDs = (
        archiveNames.map { "archive." + String($0.dropLast(".rrcap".count)) }
        + probeIDs + ["sec-consent.denied"]
    ).sorted()
    guard caseIDs.count == 16, Set(caseIDs).count == caseIDs.count else {
        throw RunnerFailure("complete case set is invalid")
    }
    return LoadedFixture(
        root: root,
        archiveVerifier: try makeArchiveVerifier(repositoryRoot: options.repositoryRoot),
        manifestSHA256: manifestSHA,
        archives: archives,
        edgeProbes: probes,
        consentDenied: consent,
        caseIDs: caseIDs
    )
}

private func replayArchive(
    _ descriptor: [String: Any],
    fixture: LoadedFixture
) throws -> ReplaySnapshot {
    guard let archiveName = descriptor["archive_name"] as? String,
          let directory = descriptor["directory"] as? [String: Any],
          let path = directory["relative_path"] as? String,
          path == "archives/\(archiveName)",
          let expected = descriptor["expected"] as? [String: Any]
    else { throw RunnerFailure("archive descriptor is invalid") }
    let snapshot: ReplaySnapshot
    do {
        let archive = try fixture.archiveVerifier.verify(
            root: safeFile(path, root: fixture.root)
        )
        snapshot = try ReplayCore.replay(archive)
    } catch {
        throw RunnerFailure("archive replay verification failed")
    }
    guard expected["verdict"] as? String == "accept",
          expected["rejection_class"] is NSNull,
          expected["finalization_state"] as? String == snapshot.finalization.state.rawValue,
          exactInt(expected["journal_record_count"]) == snapshot.timeline.count,
          exactInt(expected["accepted_frame_count"]) == Int(snapshot.finalization.acceptedFrameCount),
          exactInt(expected["event_count"]) == Int(snapshot.finalization.eventCount),
          expected["journal_tuple_sha256"] as? String == snapshot.digests.journalTupleSHA256,
          expected["frame_projection_sha256"] as? String == snapshot.digests.frameProjectionSHA256,
          expected["event_projection_sha256"] as? String == snapshot.digests.eventProjectionSHA256,
          expected["revision_trace_sha256"] as? String == snapshot.digests.revisionTraceSHA256
    else { throw RunnerFailure("archive replay disagrees with frozen oracle") }
    return snapshot
}

private func rejectionClass(_ text: String?) throws -> ReplayRejectionClass? {
    guard let text else { return nil }
    guard let value = ReplayRejectionClass(rawValue: text) else {
        throw RunnerFailure("unknown replay rejection class")
    }
    return value
}

private func makeReport(
    snapshot: ReplaySnapshot,
    caseID: String,
    expected: [String: Any],
    fixture: LoadedFixture,
    revision: String
) throws -> Data {
    guard let verdictText = expected["verdict"] as? String,
          let verdict = ReplayVerdict(rawValue: verdictText)
    else { throw RunnerFailure("case verdict is invalid") }
    let rejectionText = expected["rejection_class"] is NSNull
        ? nil : expected["rejection_class"] as? String
    let rejection = try rejectionClass(rejectionText).map {
        ReplayRejection(rejectionClass: $0, detail: "frozen fixture expected \($0.rawValue)")
    }
    do {
        let report = try ReplayReport.make(
            snapshot: snapshot,
            caseID: caseID,
            fixtureManifestSHA256: fixture.manifestSHA256,
            repositoryRevision: revision,
            verdict: verdict,
            rejection: rejection
        )
        return try ReplayReport.encode(report)
    } catch {
        throw RunnerFailure("replay report could not be encoded")
    }
}

private func buildReports(_ fixture: LoadedFixture, revision: String) throws -> [String: Data] {
    var reports = [String: Data]()
    var snapshots = [String: ReplaySnapshot]()
    for archive in fixture.archives {
        let snapshot = try replayArchive(archive, fixture: fixture)
        let name = archive["archive_name"] as! String
        snapshots[name] = snapshot
        let caseID = "archive." + String(name.dropLast(".rrcap".count))
        reports[caseID] = try makeReport(
            snapshot: snapshot,
            caseID: caseID,
            expected: archive["expected"] as! [String: Any],
            fixture: fixture,
            revision: revision
        )
    }
    guard let ordinary = snapshots["finalized-one-frame.rrcap"],
          let empty = snapshots["finalized-empty.rrcap"]
    else { throw RunnerFailure("baseline replay snapshots are absent") }
    for probe in fixture.edgeProbes {
        let caseID = probe["case_id"] as! String
        let expected = probe["expected"] as! [String: Any]
        reports[caseID] = try makeReport(
            snapshot: caseID == "fr-b0.empty" ? empty : ordinary,
            caseID: caseID,
            expected: expected,
            fixture: fixture,
            revision: revision
        )
    }
    let consentExpected: [String: Any] = [
        "verdict": fixture.consentDenied["expected_verdict"]!,
        "rejection_class": fixture.consentDenied["rejection_class"]!,
    ]
    reports["sec-consent.denied"] = try makeReport(
        snapshot: empty,
        caseID: "sec-consent.denied",
        expected: consentExpected,
        fixture: fixture,
        revision: revision
    )
    guard reports.keys.sorted() == fixture.caseIDs else {
        throw RunnerFailure("report set is incomplete")
    }
    return reports
}

private func validateOutput(_ output: URL) throws {
    if let values = try? output.resourceValues(forKeys: [.isSymbolicLinkKey]),
       values.isSymbolicLink == true {
        throw RunnerFailure("output root may not be a symlink")
    }
    guard FileManager.default.fileExists(atPath: output.path) == false else {
        throw RunnerFailure("output root must not exist")
    }
    let parent = output.deletingLastPathComponent()
    let parentValues = try? parent.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard parentValues?.isDirectory == true, parentValues?.isSymbolicLink != true else {
        throw RunnerFailure("output parent is invalid")
    }
}

private func publish(_ reports: [String: Data], to output: URL) throws {
    try validateOutput(output)
    let stage = output.deletingLastPathComponent().appendingPathComponent(
        ".reroom-replay-staging-\(UUID().uuidString.lowercased())"
    )
    defer {
        if FileManager.default.fileExists(atPath: stage.path) {
            try? FileManager.default.removeItem(at: stage)
        }
    }
    do {
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
        for caseID in reports.keys.sorted() {
            let file = stage.appendingPathComponent("\(caseID).replay-report.json")
            try reports[caseID]!.write(to: file, options: .withoutOverwriting)
        }
        let stagedNames = try FileManager.default.contentsOfDirectory(atPath: stage.path).sorted()
        let expectedNames = reports.keys.sorted().map { "\($0).replay-report.json" }
        guard stagedNames == expectedNames else { throw RunnerFailure("staged report set is incomplete") }
        try validateOutput(output)
        try FileManager.default.moveItem(at: stage, to: output)
    } catch let error as RunnerFailure {
        throw error
    } catch {
        throw RunnerFailure("report publication failed")
    }
}

do {
    let options = try parseOptions(Array(CommandLine.arguments.dropFirst()))
    try validateOutput(options.outputRoot)
    let fixture = try loadFixture(options)
    let reports = try buildReports(fixture, revision: options.implementationRevision)
    try publish(reports, to: options.outputRoot)
} catch let failure as RunnerFailure {
    FileHandle.standardError.write(Data("replay-runner: FAIL: \(failure.message)\n".utf8))
    exit(1)
} catch {
    FileHandle.standardError.write(Data("replay-runner: FAIL: unexpected failure\n".utf8))
    exit(1)
}
