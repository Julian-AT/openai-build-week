import Testing

@testable import ReRoomCaptureCore

@Suite("CaptureAdmissionTests")
struct CaptureAdmissionTests {
    @Test("ordinary capacity and the single reserved explicit lane are exact")
    func reservedLaneIsBoundedAndNonreplaceable() throws {
        let gate = try makeGate(capacity: 2)

        #expect(gate.offer(candidate(1, reason: .cadence)).isAdmitted)
        #expect(gate.offer(candidate(2, reason: .viewNovelty)).isAdmitted)
        #expect(gate.offer(candidate(3, reason: .cadence)) == .rejected(.ordinaryCapacity))
        #expect(gate.offer(candidate(4, reason: .userEvent)).isAdmitted)
        #expect(gate.offer(candidate(5, reason: .userEvent)) == .rejected(.userEventBusy))

        let snapshot = gate.snapshot()
        #expect(snapshot.offered == 5)
        #expect(snapshot.admitted == 3)
        #expect(snapshot.rejectedOrdinaryCapacity == 1)
        #expect(snapshot.rejectedUserEventBusy == 1)
        #expect(snapshot.queued == 3)
        #expect(snapshot.inFlight == 0)
        #expect(snapshot.outstanding == 3)
        #expect(snapshot.maximumOutstanding == 3)
    }

    @Test("stalled writer keeps concurrent synchronous offers within capacity plus one")
    func stalledWriterStressIsBounded() async throws {
        let capacity = 3
        let gate = try makeGate(capacity: capacity)
        let barrier = WriterBarrier()
        let terminalProbe = TerminalProbe()
        #expect(gate.offer(candidate(1, reason: .cadence)).isAdmitted)

        let consumer = Task {
            try await gate.runConsumer(
                writer: { admitted in try await barrier.write(admitted) },
                onTerminal: { result in await terminalProbe.record(result) }
            )
        }
        await barrier.waitUntilEntered(1)

        let dispositions = await withTaskGroup(
            of: CaptureAdmissionDisposition.self,
            returning: [CaptureAdmissionDisposition].self
        ) { group in
            for ordinal in 2...32 {
                group.addTask {
                    gate.offer(candidate(ordinal, reason: .cadence))
                }
            }
            group.addTask {
                gate.offer(candidate(100, reason: .userEvent))
            }
            var values = [CaptureAdmissionDisposition]()
            for await value in group { values.append(value) }
            return values
        }

        let stalled = gate.snapshot()
        #expect(dispositions.count == 32)
        #expect(stalled.inFlight == 1)
        #expect(stalled.outstanding <= capacity + 1)
        #expect(stalled.maximumOutstanding == capacity + 1)
        #expect(stalled.rejectedOrdinaryCapacity > 0)
        #expect(stalled.rejectedUserEventBusy == 0)
        #expect(await barrier.enteredCount == 1)

        _ = gate.close(reason: .gracefulStop, mode: .drainThenClose)
        await barrier.releaseAll()
        let final = try await consumer.value
        #expect(final.outstanding == 0)
        #expect(final.completed == UInt64(capacity + 1))
        #expect(await terminalProbe.results.count == capacity + 1)
        #expect(await barrier.maximumConcurrentWrites == 1)

        let admittedSequences = await barrier.admittedSequences
        #expect(admittedSequences == admittedSequences.sorted())
        #expect(Set(admittedSequences).count == admittedSequences.count)
    }

    @Test("graceful close drains only the already admitted bounded set")
    func gracefulCloseDrains() async throws {
        let gate = try makeGate(capacity: 2)
        let probe = TerminalProbe()
        #expect(gate.offer(candidate(1, reason: .cadence)).isAdmitted)
        #expect(gate.offer(candidate(2, reason: .userEvent)).isAdmitted)

        let report = gate.close(reason: .gracefulStop, mode: .drainThenClose)
        #expect(report.terminatedBeforeSelection.isEmpty)
        #expect(gate.offer(candidate(3, reason: .cadence)) == .rejected(.closed))

        let final = try await gate.runConsumer(
            writer: { _ in },
            onTerminal: { result in await probe.record(result) }
        )
        #expect(final.completed == 2)
        #expect(final.rejectedClosed == 1)
        #expect(final.outstanding == 0)
        #expect(await probe.results.map(\.status) == [.completed, .completed])
    }

    @Test(
        "abort close terminates queued work before selected while an entered writer finishes",
        arguments: [
            AbortFixture(
                reason: .cancellation,
                expected: .cancelledBeforeSelection
            ),
            AbortFixture(
                reason: .expiration,
                expected: .cancelledBeforeSelection
            ),
            AbortFixture(
                reason: .storageUnavailable,
                expected: .storageUnavailableBeforeSelection
            ),
        ]
    )
    func abortCloseIsExplicit(_ fixture: AbortFixture) async throws {
        let gate = try makeGate(capacity: 2)
        let barrier = WriterBarrier()
        let probe = TerminalProbe()
        #expect(gate.offer(candidate(1, reason: .cadence)).isAdmitted)
        #expect(gate.offer(candidate(2, reason: .cadence)).isAdmitted)
        #expect(gate.offer(candidate(3, reason: .userEvent)).isAdmitted)

        let consumer = Task {
            try await gate.runConsumer(
                writer: { admitted in try await barrier.write(admitted) },
                onTerminal: { result in await probe.record(result) }
            )
        }
        await barrier.waitUntilEntered(1)

        let close = gate.close(reason: fixture.reason, mode: .abortQueuedBeforeSelection)
        #expect(close.terminatedBeforeSelection.count == 2)
        #expect(close.terminatedBeforeSelection.allSatisfy { $0.status == fixture.expected })
        #expect(close.snapshot.inFlight == 1)
        #expect(close.snapshot.outstanding == 1)
        #expect(close.snapshot.closeReason == fixture.reason)
        #expect(await barrier.enteredCount == 1)

        await barrier.releaseAll()
        let final = try await consumer.value
        #expect(final.outstanding == 0)
        #expect(final.completed == 1)
        #expect(final.cancelledBeforeSelection == (fixture.expected == .cancelledBeforeSelection ? 2 : 0))
        #expect(
            final.storageUnavailableBeforeSelection
                == (fixture.expected == .storageUnavailableBeforeSelection ? 2 : 0)
        )
        #expect(await barrier.enteredCount == 1)
        #expect(await probe.results.map(\.status) == [.completed])
    }

    @Test("a gate grants exactly one consumer lease")
    func oneConsumerLease() async throws {
        let gate = try makeGate(capacity: 1)
        _ = gate.close(reason: .gracefulStop, mode: .drainThenClose)
        _ = try await gate.runConsumer(writer: { _ in })

        await #expect(throws: CaptureAdmissionError.consumerAlreadyLeased) {
            _ = try await gate.runConsumer(writer: { _ in })
        }
    }

    @Test("invalid capacity is rejected through classified pressure policy")
    func invalidCapacityRejects() {
        #expect(throws: CaptureValueError.invalidPolicy) {
            _ = try CapturePressurePolicy(
                policyID: "policy_admission_hypothesis_invalid",
                classification: .hypothesis,
                ordinaryCapacity: 0,
                optionalComputeDropDepth: 0,
                uploadPauseDepth: 0,
                cadenceReductionDepth: 0
            )
        }
    }

    private func makeGate(capacity: Int) throws -> CaptureAdmissionGate {
        let policy = try CapturePressurePolicy(
            policyID: "policy_admission_hypothesis_\(capacity)",
            classification: .hypothesis,
            ordinaryCapacity: capacity,
            optionalComputeDropDepth: 1,
            uploadPauseDepth: max(1, capacity - 1),
            cadenceReductionDepth: capacity
        )
        return CaptureAdmissionGate(pressurePolicy: policy)
    }
}

private func candidate(
    _ ordinal: Int,
    reason: SelectedFrameReason
) -> CaptureAdmissionCandidate {
    CaptureAdmissionCandidate(
        candidateID: "candidate_\(ordinal)",
        monotonicTimestampNanoseconds: UInt64(ordinal),
        selectedReason: reason,
        selectorPolicyID: "policy_selection_hypothesis_1",
        selectorClassification: .hypothesis
    )
}

struct AbortFixture: Sendable {
    let reason: CaptureAdmissionCloseReason
    let expected: CaptureAdmissionTerminalStatus
}

private actor TerminalProbe {
    private(set) var results = [CaptureAdmissionTerminalResult]()

    func record(_ result: CaptureAdmissionTerminalResult) {
        results.append(result)
    }
}

private actor WriterBarrier {
    private var entered = [AdmittedCaptureCandidate]()
    private var activeWrites = 0
    private var maximumActiveWrites = 0
    private var entryWaiters = [(count: Int, continuation: CheckedContinuation<Void, Never>)]()
    private var releaseWaiters = [CheckedContinuation<Void, Never>]()
    private var releaseImmediately = false

    var enteredCount: Int { entered.count }
    var maximumConcurrentWrites: Int { maximumActiveWrites }
    var admittedSequences: [UInt64] { entered.map(\.admissionSequence) }

    func write(_ admitted: AdmittedCaptureCandidate) async throws {
        entered.append(admitted)
        activeWrites += 1
        maximumActiveWrites = max(maximumActiveWrites, activeWrites)
        resumeSatisfiedEntryWaiters()
        if releaseImmediately == false {
            await withCheckedContinuation { continuation in
                releaseWaiters.append(continuation)
            }
        }
        activeWrites -= 1
    }

    func waitUntilEntered(_ count: Int) async {
        if entered.count >= count { return }
        await withCheckedContinuation { continuation in
            entryWaiters.append((count, continuation))
        }
    }

    func releaseAll() {
        releaseImmediately = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters { waiter.resume() }
    }

    private func resumeSatisfiedEntryWaiters() {
        var remaining = [(count: Int, continuation: CheckedContinuation<Void, Never>)]()
        for waiter in entryWaiters {
            if entered.count >= waiter.count {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }
        entryWaiters = remaining
    }
}
