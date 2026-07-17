import Foundation
import Testing

@testable import ReRoomCaptureCore

@Suite("BoundedQueueTests")
struct BoundedQueueTests {
    @Test("capacity zero rejects configuration")
    func zeroCapacityRejects() throws {
        let policy = try pressurePolicy(capacity: 1)
        #expect(throws: BoundedQueueError.invalidCapacity) {
            _ = try BoundedLatestQueue<NetworkEligibleReceipt>(
                capacity: 0,
                pressurePolicy: policy
            )
        }
    }

    @Test("concurrent producers never exceed configured live depth")
    func concurrentProducersStayBounded() async throws {
        let capacity = 4
        let queue = try BoundedLatestQueue<NetworkEligibleReceipt>(
            capacity: capacity,
            pressurePolicy: pressurePolicy(capacity: capacity)
        )

        await withTaskGroup(of: Void.self) { group in
            for ordinal in 0..<128 {
                group.addTask {
                    _ = await queue.offer(receipt(ordinal), priority: .cadence)
                }
            }
        }

        let snapshot = await queue.snapshot()
        #expect(snapshot.offered == 128)
        #expect(snapshot.currentDepth == capacity)
        #expect(snapshot.maximumDepth == capacity)
        #expect(snapshot.replaced > 0)
        #expect(snapshot.dropped > 0)
    }

    @Test("capacity one replaces stale ordinary work with newest useful work")
    func newestUsefulReplacement() async throws {
        let queue = try BoundedLatestQueue<NetworkEligibleReceipt>(
            capacity: 1,
            pressurePolicy: pressurePolicy(capacity: 1)
        )
        let first = receipt(1)
        let latest = receipt(2)

        #expect(await queue.offer(first, priority: .cadence) == .accepted)
        #expect(await queue.offer(latest, priority: .cadence) == .replacedStale)
        let lease = try #require(await queue.next())
        #expect(lease.element == latest)
        #expect(await queue.complete(lease))

        let snapshot = await queue.snapshot()
        #expect(snapshot.replaced == 1)
        #expect(snapshot.dropped == 1)
        #expect(snapshot.completed == 1)
        #expect(snapshot.currentDepth == 0)
    }

    @Test("user-event and keyframe work cannot be displaced by cadence")
    func priorityWorkIsProtected() async throws {
        let queue = try BoundedLatestQueue<NetworkEligibleReceipt>(
            capacity: 2,
            pressurePolicy: pressurePolicy(capacity: 2)
        )
        let explicit = receipt(10)
        let keyframe = receipt(11)

        #expect(await queue.offer(explicit, priority: .userEvent) == .accepted)
        #expect(await queue.offer(keyframe, priority: .keyframe) == .accepted)
        #expect(await queue.offer(receipt(12), priority: .cadence) == .droppedLowerPriority)

        let first = try #require(await queue.next())
        #expect(first.element == explicit)
        #expect(await queue.complete(first))
        let second = try #require(await queue.next())
        #expect(second.element == keyframe)
        #expect(await queue.complete(second))
        #expect(await queue.snapshot().dropped == 1)
    }

    @Test("pressure follows optional-compute upload-pause cadence-reduction order")
    func pressureOrderIsLocked() async throws {
        let policy = try pressurePolicy(capacity: 3)
        let queue = try BoundedLatestQueue<NetworkEligibleReceipt>(
            capacity: 3,
            pressurePolicy: policy
        )

        _ = await queue.offer(receipt(20), priority: .cadence)
        let optionalDrop = await queue.snapshot()
        _ = await queue.offer(receipt(21), priority: .cadence)
        let uploadPause = await queue.snapshot()
        _ = await queue.offer(receipt(22), priority: .cadence)
        let cadenceReduction = await queue.snapshot()

        #expect(optionalDrop.pressureReason == .optionalComputeDropped)
        #expect(optionalDrop.uploadPaused == false)
        #expect(uploadPause.pressureReason == .uploadPaused)
        #expect(uploadPause.uploadPaused)
        #expect(cadenceReduction.pressureReason == .cadenceQualityReduced)
        #expect(cadenceReduction.uploadPaused)

        let gate = CaptureAdmissionGate(pressurePolicy: policy)
        #expect(gate.offer(admissionCandidate(1)).isAdmitted)
        #expect(gate.snapshot().pressureReason == .optionalComputeDropped)
        #expect(gate.offer(admissionCandidate(2)).isAdmitted)
        #expect(gate.snapshot().pressureReason == .uploadPaused)
        #expect(gate.offer(admissionCandidate(3)).isAdmitted)
        #expect(gate.snapshot().pressureReason == .cadenceQualityReduced)
        #expect(gate.offer(admissionCandidate(4)) == .rejected(.ordinaryCapacity))
        #expect(gate.snapshot().outstanding == 3)
    }

    @Test("cancelAll empties queued and in-flight work deterministically")
    func cancellationIsBounded() async throws {
        let queue = try BoundedLatestQueue<NetworkEligibleReceipt>(
            capacity: 3,
            pressurePolicy: pressurePolicy(capacity: 3)
        )
        for ordinal in 30..<33 {
            _ = await queue.offer(receipt(ordinal), priority: .viewNovelty)
        }
        _ = try #require(await queue.next())

        let cancelled = await queue.cancelAll()
        #expect(cancelled.map(\.durableJournalSequence).sorted() == [30, 31, 32])
        let snapshot = await queue.snapshot()
        #expect(snapshot.cancelled == 3)
        #expect(snapshot.currentDepth == 0)
        #expect(await queue.next() == nil)
        #expect(await queue.offer(receipt(33), priority: .userEvent) == .droppedCancelled)
    }

    @Test("blackhole duplicate and reversed completions cannot invent receipts or reorder durable history")
    func transportCompletionOrderIsNonAuthoritative() throws {
        let receipts = [receipt(40), receipt(41), receipt(42)]
        let durableOrder = receipts.map(\.durableJournalSequence)
        let transport = try CaptureTransport(gatewayID: gatewayID)

        #expect(try transport.completions(for: receipts, behavior: .blackhole).isEmpty)

        let reversed = try transport.completions(for: receipts, behavior: .reversed)
        #expect(reversed.map(\.receipt.durableJournalSequence) == durableOrder.reversed())
        #expect(reversed.allSatisfy(transport.validate))
        #expect(receipts.map(\.durableJournalSequence) == durableOrder)

        let duplicated = try transport.completions(for: receipts, behavior: .duplicateFirst)
        #expect(duplicated.count == receipts.count + 1)
        #expect(duplicated.allSatisfy(transport.validate))
        #expect(Set(duplicated.map(\.receipt.frameID)).isSubset(of: Set(receipts.map(\.frameID))))
        #expect(receipts.map(\.durableJournalSequence) == durableOrder)
    }

    @Test("typed acknowledgement validation rejects every mismatched binding")
    func acknowledgementValidationIsExact() throws {
        let transport = try CaptureTransport(gatewayID: gatewayID)
        let source = receipt(50)
        let other = receipt(51)
        let acknowledgement = try transport.acknowledgement(for: source)

        #expect(transport.validate(acknowledgement, for: source))
        #expect(transport.validate(acknowledgement, for: other) == false)
    }

    private func pressurePolicy(capacity: Int) throws -> CapturePressurePolicy {
        try CapturePressurePolicy(
            policyID: "policy_queue_target_\(capacity)",
            classification: .target,
            ordinaryCapacity: capacity,
            optionalComputeDropDepth: 1,
            uploadPauseDepth: max(1, capacity - 1),
            cadenceReductionDepth: capacity
        )
    }
}

private let gatewayID = "gateway_00000000-0000-4000-8000-000000000001"

private func receipt(_ ordinal: Int) -> NetworkEligibleReceipt {
    try! NetworkEligibleReceipt(
        sessionID: "session_00000000-0000-4000-8000-000000000001",
        frameID: String(format: "frame_00000000-0000-4000-8000-%012d", ordinal + 1),
        idempotencyKey: String(
            format: "frameidem_00000000-0000-4000-8000-%012d",
            ordinal + 1
        ),
        packetRelativePath: "frames/frame_\(ordinal + 1)/packet.json",
        packetSHA256: String(repeating: "a", count: 64),
        imageSHA256: String(repeating: "b", count: 64),
        acceptedSequence: UInt64(ordinal),
        durableJournalSequence: UInt64(ordinal)
    )
}

private func admissionCandidate(_ ordinal: Int) -> CaptureAdmissionCandidate {
    CaptureAdmissionCandidate(
        candidateID: "candidate_\(ordinal)",
        monotonicTimestampNanoseconds: UInt64(ordinal),
        selectedReason: .cadence,
        selectorPolicyID: "policy_selection_hypothesis_1",
        selectorClassification: .hypothesis
    )
}
