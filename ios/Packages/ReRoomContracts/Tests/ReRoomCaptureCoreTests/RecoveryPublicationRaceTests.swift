import Foundation
import ReRoomContracts
import Testing

@testable import ReRoomCaptureCore

@Suite("RecoveryPublicationRaceTests")
struct RecoveryPublicationRaceTests {
    @Test(
        "identical publishers converge at rename and pointer in both arrival orders",
        arguments: PublicationRaceOrder.allCases
    )
    func identicalPublishers(order: PublicationRaceOrder) async throws {
        let candidate = try RecoveryPublicationFixture.candidateWithInvalidSuffix()
        let verifier = try RecoveryPublicationFixture.verifier()
        let expectedGeneration = try generationID(for: candidate, verifier: verifier)
        let run = await PublicationRaceRun.execute(
            order: order,
            firstCandidate: candidate,
            secondCandidate: candidate,
            verifier: verifier
        )

        #expect(run.outcomes[.first] == .success(expectedGeneration))
        #expect(run.outcomes[.second] == .success(expectedGeneration))
        #expect(run.controller.participants(at: .generationRename) == Set(PublicationRaceParticipant.allCases))
        #expect(run.controller.participants(at: .activePointerInstall) == Set(PublicationRaceParticipant.allCases))
        #expect(generationIDs(in: run.fileSystem.snapshotFiles()).sorted() == [expectedGeneration])
        try assertOwnedCleanupOnly(run.controller.operations)

        let beforeRepeat = run.fileSystem.snapshotFiles()
        let repeated = try RecoveryPublisher(
            fileSystem: run.fileSystem,
            verifier: verifier,
            stagingToken: { "repeat-identical" }
        ).publish(candidate)
        #expect(repeated.generationID == expectedGeneration)
        #expect(repeated.reusedExistingGeneration)
        #expect(run.fileSystem.snapshotFiles() == beforeRepeat)

        let restarted = RecoveryPublisher(
            fileSystem: run.fileSystem.crashedCopy(),
            verifier: verifier,
            stagingToken: { "restart-identical" }
        )
        let winner = try restarted.recover(
            sourceIdentitySHA256: candidate.sourceIdentity.sha256
        )
        #expect(winner?.generationID == expectedGeneration)
        #expect(try winner.map { try ReplayCore.replay($0.archive).timeline.count } == 6)
    }

    @Test(
        "different same-source publishers preserve both generations and conflict the loser",
        arguments: PublicationRaceOrder.allCases
    )
    func conflictingPublishers(order: PublicationRaceOrder) async throws {
        let firstCandidate = try RecoveryPublicationFixture.candidateWithInvalidSuffix()
        let secondCandidate = try alternateCandidate(from: firstCandidate)
        let verifier = try RecoveryPublicationFixture.verifier()
        let firstGeneration = try generationID(for: firstCandidate, verifier: verifier)
        let secondGeneration = try generationID(for: secondCandidate, verifier: verifier)
        let expectedWinner = order.firstParticipant == .first
            ? firstGeneration
            : secondGeneration
        let expectedLoser = order.firstParticipant == .first
            ? secondGeneration
            : firstGeneration

        let run = await PublicationRaceRun.execute(
            order: order,
            firstCandidate: firstCandidate,
            secondCandidate: secondCandidate,
            verifier: verifier
        )

        #expect(run.outcomes[order.firstParticipant] == .success(expectedWinner))
        #expect(run.outcomes[order.firstParticipant.other] == .publicationConflict)
        #expect(run.controller.participants(at: .generationRename) == Set(PublicationRaceParticipant.allCases))
        #expect(run.controller.participants(at: .activePointerInstall) == Set(PublicationRaceParticipant.allCases))
        #expect(Set(generationIDs(in: run.fileSystem.snapshotFiles())) == Set([
            firstGeneration, secondGeneration,
        ]))
        try assertOwnedCleanupOnly(run.controller.operations)

        let restarted = RecoveryPublisher(
            fileSystem: run.fileSystem.crashedCopy(),
            verifier: verifier,
            stagingToken: { "restart-conflict" }
        )
        let winner = try restarted.recover(
            sourceIdentitySHA256: firstCandidate.sourceIdentity.sha256
        )
        #expect(winner?.generationID == expectedWinner)

        let beforeRepeat = run.fileSystem.snapshotFiles()
        let loserCandidate = expectedLoser == firstGeneration ? firstCandidate : secondCandidate
        #expect(throws: CaptureRecoveryError.publicationConflict) {
            _ = try RecoveryPublisher(
                fileSystem: run.fileSystem,
                verifier: verifier,
                stagingToken: { "repeat-loser" }
            ).publish(loserCandidate)
        }
        #expect(run.fileSystem.snapshotFiles() == beforeRepeat)

        let winnerCandidate = expectedWinner == firstGeneration ? firstCandidate : secondCandidate
        let repeated = try RecoveryPublisher(
            fileSystem: run.fileSystem,
            verifier: verifier,
            stagingToken: { "repeat-winner" }
        ).publish(winnerCandidate)
        #expect(repeated.generationID == expectedWinner)
        #expect(repeated.reusedExistingGeneration)
        #expect(run.fileSystem.snapshotFiles() == beforeRepeat)
    }

    @Test(
        "an identical pointer loser completes durability when the installer dies",
        arguments: PublicationRaceOrder.allCases
    )
    func loserCompletesPointerDurability(order: PublicationRaceOrder) async throws {
        let candidate = try RecoveryPublicationFixture.candidateWithInvalidSuffix()
        let verifier = try RecoveryPublicationFixture.verifier()
        let expectedGeneration = try generationID(for: candidate, verifier: verifier)
        let run = await PublicationRaceRun.execute(
            order: order,
            firstCandidate: candidate,
            secondCandidate: candidate,
            verifier: verifier,
            faultPointerWinnerBeforeFileSync: true
        )

        #expect(run.outcomes[order.firstParticipant] == .injectedFault)
        #expect(run.outcomes[order.firstParticipant.other] == .success(expectedGeneration))
        try assertOwnedCleanupOnly(run.controller.operations)

        let restartedFileSystem = run.fileSystem.crashedCopy()
        let restarted = RecoveryPublisher(
            fileSystem: restartedFileSystem,
            verifier: verifier,
            stagingToken: { "restart-winner-fault" }
        )
        let winner = try restarted.recover(
            sourceIdentitySHA256: candidate.sourceIdentity.sha256
        )
        #expect(winner?.generationID == expectedGeneration)
        #expect(try winner.map { try ReplayCore.replay($0.archive).timeline.count } == 6)
        #expect(generationIDs(in: restartedFileSystem.snapshotFiles()).contains(expectedGeneration))
    }

    private func generationID(
        for candidate: RecoveryGenerationCandidate,
        verifier: ArchiveVerifier
    ) throws -> String {
        try RecoveryPublisher(
            fileSystem: PublicationDurableMemoryFileSystem(),
            verifier: verifier,
            stagingToken: { "expected" }
        ).publish(candidate).generationID
    }

    private func alternateCandidate(
        from candidate: RecoveryGenerationCandidate
    ) throws -> RecoveryGenerationCandidate {
        let bytes = Data(#"{"journal_sequence":6,"alternate":true"#.utf8)
        let digest = CanonicalJSON.sha256Hex(bytes)
        let metadataObject: [String: Any] = [
            "accepted_inventory_member": false,
            "first_invalid_journal_sequence": candidate.acceptedJournalRecordCount,
            "suffix_byte_length": bytes.count,
            "suffix_sha256": digest,
        ]
        let encoded = try JSONSerialization.data(
            withJSONObject: metadataObject,
            options: [.sortedKeys]
        )
        let metadata = try CanonicalJSON.canonicalize(jsonData: encoded)
        return RecoveryGenerationCandidate(
            sourceIdentity: candidate.sourceIdentity,
            manifestData: candidate.manifestData,
            members: candidate.members,
            journalData: candidate.journalData,
            invalidSuffix: RecoveryInvalidSuffix(
                firstInvalidJournalSequence: candidate.acceptedJournalRecordCount,
                bytes: bytes,
                sha256: digest,
                metadataData: metadata
            ),
            acceptedPrefixJournalSHA256: candidate.acceptedPrefixJournalSHA256,
            finalizationState: candidate.finalizationState,
            manifestSHA256: candidate.manifestSHA256,
            lastDurableJournalSequence: candidate.lastDurableJournalSequence,
            acceptedFrameCount: candidate.acceptedFrameCount,
            eventCount: candidate.eventCount
        )
    }

    private func generationIDs(in files: [String: Data]) -> [String] {
        Set(files.keys.compactMap { path -> String? in
            let components = path.split(separator: "/")
            guard let generations = components.firstIndex(of: "generations"),
                  generations + 1 < components.count
            else { return nil }
            return String(components[generations + 1])
        }).sorted()
    }

    private func assertOwnedCleanupOnly(
        _ operations: [PublicationRaceOperation]
    ) throws {
        let cleanup = operations.filter { $0.operation.kind == .removeItem }
        #expect(cleanup.isEmpty == false)
        for record in cleanup {
            let token = record.participant == .first ? "race-first" : "race-second"
            #expect(record.operation.path.contains(token))
            #expect(record.operation.path.contains("/generations/") == false)
            #expect(record.operation.path.hasSuffix("/active-generation.json") == false)
            #expect(record.operation.path.contains("/archive/") == false)
            #expect(record.operation.path.contains("/quarantine/") == false)
        }
    }
}

enum PublicationRaceOrder: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case firstThenSecond
    case secondThenFirst

    var firstParticipant: PublicationRaceParticipant {
        self == .firstThenSecond ? .first : .second
    }

    var testDescription: String { rawValue }
}

enum PublicationRaceParticipant: String, CaseIterable, Hashable, Sendable {
    case first
    case second

    var other: Self { self == .first ? .second : .first }
}

enum PublicationRacePoint: Hashable, Sendable {
    case generationRename
    case activePointerInstall
}

enum PublicationRaceOutcome: Equatable, Sendable {
    case success(String)
    case publicationConflict
    case injectedFault
    case unexpected(String)
}

struct PublicationRaceOperation: Equatable, Sendable {
    let participant: PublicationRaceParticipant
    let operation: CaptureFileOperation
}

struct PublicationRaceInjectedFault: Error, Equatable, Sendable {}

final class PublicationRaceController: @unchecked Sendable {
    private let condition = NSCondition()
    private let firstParticipant: PublicationRaceParticipant
    private let faultPointerWinnerBeforeFileSync: Bool
    private var arrivals = [PublicationRacePoint: Set<PublicationRaceParticipant>]()
    private var firstCompleted = Set<PublicationRacePoint>()
    private var records = [PublicationRaceOperation]()
    private var pointerWinnerInstalled = false
    private var pointerFaultFired = false

    init(
        firstParticipant: PublicationRaceParticipant,
        faultPointerWinnerBeforeFileSync: Bool
    ) {
        self.firstParticipant = firstParticipant
        self.faultPointerWinnerBeforeFileSync = faultPointerWinnerBeforeFileSync
    }

    var operations: [PublicationRaceOperation] {
        condition.withLock { records }
    }

    func participants(at point: PublicationRacePoint) -> Set<PublicationRaceParticipant> {
        condition.withLock { arrivals[point] ?? [] }
    }

    func record(
        _ operation: CaptureFileOperation,
        participant: PublicationRaceParticipant
    ) {
        condition.withLock {
            records.append(PublicationRaceOperation(
                participant: participant,
                operation: operation
            ))
        }
    }

    func rendezvous(
        _ point: PublicationRacePoint,
        participant: PublicationRaceParticipant
    ) {
        condition.lock()
        arrivals[point, default: []].insert(participant)
        condition.broadcast()
        while arrivals[point]?.count != PublicationRaceParticipant.allCases.count {
            condition.wait()
        }
        while participant != firstParticipant && firstCompleted.contains(point) == false {
            condition.wait()
        }
        condition.unlock()
    }

    func complete(
        _ point: PublicationRacePoint,
        participant: PublicationRaceParticipant,
        succeeded: Bool
    ) {
        condition.withLock {
            if participant == firstParticipant {
                firstCompleted.insert(point)
                if point == .activePointerInstall, succeeded {
                    pointerWinnerInstalled = true
                }
                condition.broadcast()
            }
        }
    }

    func shouldFaultActivePointerSync(
        participant: PublicationRaceParticipant,
        path: String
    ) -> Bool {
        condition.withLock {
            guard faultPointerWinnerBeforeFileSync,
                  participant == firstParticipant,
                  pointerWinnerInstalled,
                  pointerFaultFired == false,
                  path.hasSuffix("/active-generation.json")
            else { return false }
            pointerFaultFired = true
            return true
        }
    }
}

private extension NSCondition {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

struct PublicationRaceRun: Sendable {
    let fileSystem: PublicationDurableMemoryFileSystem
    let controller: PublicationRaceController
    let outcomes: [PublicationRaceParticipant: PublicationRaceOutcome]

    static func execute(
        order: PublicationRaceOrder,
        firstCandidate: RecoveryGenerationCandidate,
        secondCandidate: RecoveryGenerationCandidate,
        verifier: ArchiveVerifier,
        faultPointerWinnerBeforeFileSync: Bool = false
    ) async -> PublicationRaceRun {
        let fileSystem = PublicationDurableMemoryFileSystem()
        let controller = PublicationRaceController(
            firstParticipant: order.firstParticipant,
            faultPointerWinnerBeforeFileSync: faultPointerWinnerBeforeFileSync
        )
        let firstFileSystem = PublicationRendezvousFileSystem(
            base: fileSystem,
            participant: .first,
            controller: controller
        )
        let secondFileSystem = PublicationRendezvousFileSystem(
            base: fileSystem,
            participant: .second,
            controller: controller
        )
        let firstPublisher = RecoveryPublisher(
            fileSystem: firstFileSystem,
            verifier: verifier,
            stagingToken: { "race-first" }
        )
        let secondPublisher = RecoveryPublisher(
            fileSystem: secondFileSystem,
            verifier: verifier,
            stagingToken: { "race-second" }
        )

        let pairs = await withTaskGroup(
            of: (PublicationRaceParticipant, PublicationRaceOutcome).self,
            returning: [(PublicationRaceParticipant, PublicationRaceOutcome)].self
        ) { group in
            group.addTask {
                (.first, publish(firstCandidate, using: firstPublisher))
            }
            group.addTask {
                (.second, publish(secondCandidate, using: secondPublisher))
            }
            var values = [(PublicationRaceParticipant, PublicationRaceOutcome)]()
            for await value in group { values.append(value) }
            return values
        }
        return PublicationRaceRun(
            fileSystem: fileSystem,
            controller: controller,
            outcomes: Dictionary(uniqueKeysWithValues: pairs)
        )
    }

    private static func publish(
        _ candidate: RecoveryGenerationCandidate,
        using publisher: RecoveryPublisher
    ) -> PublicationRaceOutcome {
        do {
            return .success(try publisher.publish(candidate).generationID)
        } catch CaptureRecoveryError.publicationConflict {
            return .publicationConflict
        } catch is PublicationRaceInjectedFault {
            return .injectedFault
        } catch {
            return .unexpected(String(describing: error))
        }
    }
}

struct PublicationRendezvousFileSystem: CaptureFileSystem, Sendable {
    let base: PublicationDurableMemoryFileSystem
    let participant: PublicationRaceParticipant
    let controller: PublicationRaceController

    var limits: CaptureFileSystemLimits { base.limits }

    func createDirectory(at path: String) throws {
        try record(.init(kind: .createDirectory, path: path)) {
            try base.createDirectory(at: path)
        }
    }

    func write(_ data: Data, to path: String) throws {
        try record(.init(kind: .write, path: path, byteCount: data.count)) {
            try base.write(data, to: path)
        }
    }

    func synchronizeFile(at path: String) throws {
        let operation = CaptureFileOperation(kind: .synchronizeFile, path: path)
        controller.record(operation, participant: participant)
        if controller.shouldFaultActivePointerSync(participant: participant, path: path) {
            throw PublicationRaceInjectedFault()
        }
        try base.synchronizeFile(at: path)
    }

    func synchronizeDirectory(at path: String) throws {
        try record(.init(kind: .synchronizeDirectory, path: path)) {
            try base.synchronizeDirectory(at: path)
        }
    }

    func append(_ data: Data, to path: String) throws {
        try record(.init(kind: .append, path: path, byteCount: data.count)) {
            try base.append(data, to: path)
        }
    }

    func replace(_ data: Data, at path: String) throws {
        try record(.init(kind: .replace, path: path, byteCount: data.count)) {
            try base.replace(data, at: path)
        }
    }

    func rename(from sourcePath: String, to destinationPath: String) throws {
        try record(.init(kind: .rename, path: sourcePath, destinationPath: destinationPath)) {
            try base.rename(from: sourcePath, to: destinationPath)
        }
    }

    func renameExclusively(from sourcePath: String, to destinationPath: String) throws {
        let operation = CaptureFileOperation(
            kind: .renameExclusive,
            path: sourcePath,
            destinationPath: destinationPath
        )
        controller.record(operation, participant: participant)
        controller.rendezvous(.generationRename, participant: participant)
        var succeeded = false
        defer {
            controller.complete(
                .generationRename,
                participant: participant,
                succeeded: succeeded
            )
        }
        try base.renameExclusively(from: sourcePath, to: destinationPath)
        succeeded = true
    }

    func installFileExclusively(from sourcePath: String, to destinationPath: String) throws {
        let operation = CaptureFileOperation(
            kind: .installExclusive,
            path: sourcePath,
            destinationPath: destinationPath
        )
        controller.record(operation, participant: participant)
        controller.rendezvous(.activePointerInstall, participant: participant)
        var succeeded = false
        defer {
            controller.complete(
                .activePointerInstall,
                participant: participant,
                succeeded: succeeded
            )
        }
        try base.installFileExclusively(from: sourcePath, to: destinationPath)
        succeeded = true
    }

    func removeItem(at path: String) throws {
        try record(.init(kind: .removeItem, path: path)) {
            try base.removeItem(at: path)
        }
    }

    func read(at path: String, maximumBytes: Int?) throws -> Data {
        let operation = CaptureFileOperation(
            kind: .read,
            path: path,
            byteCount: maximumBytes ?? limits.maximumReadBytes
        )
        controller.record(operation, participant: participant)
        return try base.read(at: path, maximumBytes: maximumBytes)
    }

    func fileExists(at path: String) throws -> Bool {
        let operation = CaptureFileOperation(kind: .fileExists, path: path)
        controller.record(operation, participant: participant)
        return try base.fileExists(at: path)
    }

    func listFilesRecursively(at path: String) throws -> [String] {
        let operation = CaptureFileOperation(kind: .listFiles, path: path)
        controller.record(operation, participant: participant)
        return try base.listFilesRecursively(at: path)
    }

    func localURL(at path: String) throws -> URL {
        try base.localURL(at: path)
    }

    private func record<T>(
        _ operation: CaptureFileOperation,
        body: () throws -> T
    ) rethrows -> T {
        controller.record(operation, participant: participant)
        return try body()
    }
}
