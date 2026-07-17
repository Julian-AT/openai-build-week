import Foundation
import ReRoomContracts

public enum ReplayReportError: String, Error, Equatable, Sendable {
    case digestMismatch = "digest_mismatch"
    case invalidIdentity = "invalid_identity"
    case invalidReport = "invalid_report"
}

public enum ReplayReport {
    public static func make(
        snapshot: ReplaySnapshot,
        caseID: String,
        fixtureManifestSHA256: String,
        repositoryRevision: String,
        verdict: ReplayVerdict = .accept,
        rejection: ReplayRejection? = nil
    ) throws -> ReplayReportV1 {
        guard caseID.isEmpty == false,
              repositoryRevision.range(
                of: #"^git:[0-9a-f]{40}$"#,
                options: .regularExpression
              ) != nil
        else { throw ReplayReportError.invalidIdentity }

        let fixture: ReplayFixtureIdentity
        let archive: ReplayArchiveIdentity
        do {
            fixture = try ReplayFixtureIdentity(
                fixtureID: "FX-CAPTURE-001",
                fixtureRevision: "rev-001",
                manifestSHA256: fixtureManifestSHA256
            )
            archive = try ReplayArchiveIdentity(
                caseID: caseID,
                archiveName: snapshot.finalization.archivePath,
                finalizationState: snapshot.finalization.state,
                manifestSHA256: snapshot.finalization.manifestSHA256,
                acceptedFrameCount: snapshot.finalization.acceptedFrameCount,
                eventCount: snapshot.finalization.eventCount,
                journalRecordCount: UInt64(snapshot.timeline.count)
            )
        } catch {
            throw ReplayReportError.invalidIdentity
        }

        let evaluator = ReplayEvaluator(
            name: "ReRoomReplayCore",
            version: "1.0.0",
            platform: "swift"
        )
        let implementation = ReplayImplementationIdentity(
            repositoryRevision: repositoryRevision,
            runtime: "swift",
            buildID: "ReRoomReplayCore-1.0.0"
        )
        let metrics = ReplayMetrics(
            maximumQueueDepth: 0,
            droppedStaleCandidates: 0,
            recoveredPrefixRecords: snapshot.finalization.state == .recoveredPrefix
                ? UInt64(snapshot.timeline.count) : 0,
            quarantinedSuffixRecords: snapshot.finalization.state == .recoveredPrefix ? 1 : 0
        )
        let placeholder: ReplayReportV1
        do {
            placeholder = try ReplayReportV1(
                evaluator: evaluator,
                fixture: fixture,
                archive: archive,
                implementation: implementation,
                verdict: verdict,
                digests: snapshot.digests,
                rejection: rejection,
                metrics: metrics,
                reportSHA256: String(repeating: "0", count: 64)
            )
        } catch {
            throw ReplayReportError.invalidReport
        }
        let digest = try unsignedDigest(placeholder)
        do {
            return try ReplayReportV1(
                evaluator: evaluator,
                fixture: fixture,
                archive: archive,
                implementation: implementation,
                verdict: verdict,
                digests: snapshot.digests,
                rejection: rejection,
                metrics: metrics,
                reportSHA256: digest
            )
        } catch {
            throw ReplayReportError.invalidReport
        }
    }

    public static func encode(_ report: ReplayReportV1) throws -> Data {
        guard try unsignedDigest(report) == report.reportSHA256 else {
            throw ReplayReportError.digestMismatch
        }
        do {
            return try CanonicalJSON.canonicalize(jsonData: try encoded(report))
        } catch let error as ReplayReportError {
            throw error
        } catch {
            throw ReplayReportError.invalidReport
        }
    }

    private static func unsignedDigest(_ report: ReplayReportV1) throws -> String {
        do {
            let data = try encoded(report)
            guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  root.removeValue(forKey: "report_sha256") != nil
            else { throw ReplayReportError.invalidReport }
            return CanonicalJSON.sha256Hex(try replayCanonicalData(root))
        } catch let error as ReplayReportError {
            throw error
        } catch {
            throw ReplayReportError.invalidReport
        }
    }

    private static func encoded(_ report: ReplayReportV1) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(report)
    }
}
