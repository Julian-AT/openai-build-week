import os

public struct CaptureAdmissionCandidate: Equatable, Sendable {
    public let candidateID: String
    public let monotonicTimestampNanoseconds: UInt64
    public let selectedReason: SelectedFrameReason
    public let selectorPolicyID: String
    public let selectorClassification: EvidenceClassification

    public init(
        candidateID: String,
        monotonicTimestampNanoseconds: UInt64,
        selectedReason: SelectedFrameReason,
        selectorPolicyID: String,
        selectorClassification: EvidenceClassification
    ) {
        self.candidateID = candidateID
        self.monotonicTimestampNanoseconds = monotonicTimestampNanoseconds
        self.selectedReason = selectedReason
        self.selectorPolicyID = selectorPolicyID
        self.selectorClassification = selectorClassification
    }

    fileprivate var usesReservedUserEventLane: Bool {
        selectedReason == .userEvent
    }
}

public struct AdmittedCaptureCandidate: Equatable, Sendable {
    public let admissionSequence: UInt64
    public let candidate: CaptureAdmissionCandidate

    fileprivate init(admissionSequence: UInt64, candidate: CaptureAdmissionCandidate) {
        self.admissionSequence = admissionSequence
        self.candidate = candidate
    }
}

public enum CaptureAdmissionRejectionReason: String, Equatable, Sendable {
    case ordinaryCapacity = "ordinary_capacity"
    case userEventBusy = "user_event_busy"
    case closed
}

public enum CaptureAdmissionDisposition: Equatable, Sendable {
    case admitted(AdmittedCaptureCandidate)
    case rejected(CaptureAdmissionRejectionReason)

    public var isAdmitted: Bool {
        guard case .admitted = self else { return false }
        return true
    }
}

public enum CaptureAdmissionCloseReason: String, Equatable, Sendable {
    case gracefulStop = "graceful_stop"
    case cancellation
    case expiration
    case storageUnavailable = "storage_unavailable"
}

public enum CaptureAdmissionCloseMode: String, Equatable, Sendable {
    case drainThenClose = "drain_then_close"
    case abortQueuedBeforeSelection = "abort_queued_before_selection"
}

public enum CaptureAdmissionTerminalStatus: String, Equatable, Sendable {
    case completed
    case writerFailed = "writer_failed"
    case cancelledBeforeSelection = "cancelled_before_selection"
    case storageUnavailableBeforeSelection = "storage_unavailable_before_selection"
}

public struct CaptureAdmissionTerminalResult: Equatable, Sendable {
    public let admitted: AdmittedCaptureCandidate
    public let status: CaptureAdmissionTerminalStatus
}

public enum CaptureAdmissionError: String, Error, Equatable, Sendable {
    case consumerAlreadyLeased = "consumer_already_leased"
}

public struct CaptureAdmissionSnapshot: Equatable, Sendable {
    public let offered: UInt64
    public let admitted: UInt64
    public let rejectedOrdinaryCapacity: UInt64
    public let rejectedUserEventBusy: UInt64
    public let rejectedClosed: UInt64
    public let queued: Int
    public let inFlight: Int
    public let outstanding: Int
    public let maximumOutstanding: Int
    public let completed: UInt64
    public let writerFailed: UInt64
    public let cancelledBeforeSelection: UInt64
    public let storageUnavailableBeforeSelection: UInt64
    public let closeReason: CaptureAdmissionCloseReason?
    public let pressureReason: CapturePressureReason
    public let optionalComputeDropped: Bool
    public let uploadPaused: Bool
    public let cadenceQualityReductionRequested: Bool
}

public struct CaptureAdmissionCloseReport: Equatable, Sendable {
    public let terminatedBeforeSelection: [CaptureAdmissionTerminalResult]
    public let snapshot: CaptureAdmissionSnapshot
}

/// Synchronous pre-durability handoff. `offer` never suspends, creates a task, or calls user code.
public final class CaptureAdmissionGate: Sendable {
    private struct State: Sendable {
        let pressurePolicy: CapturePressurePolicy
        var ordinaryQueue: FixedRing<AdmittedCaptureCandidate>
        var reservedUserEvent: AdmittedCaptureCandidate?
        var inFlight: AdmittedCaptureCandidate?
        var nextAdmissionSequence: UInt64 = 0
        var ordinaryOutstanding = 0
        var userEventOutstanding = false
        var consumerLeased = false
        var closeReason: CaptureAdmissionCloseReason?
        var closeMode: CaptureAdmissionCloseMode?
        var offered: UInt64 = 0
        var admitted: UInt64 = 0
        var rejectedOrdinaryCapacity: UInt64 = 0
        var rejectedUserEventBusy: UInt64 = 0
        var rejectedClosed: UInt64 = 0
        var maximumOutstanding = 0
        var completed: UInt64 = 0
        var writerFailed: UInt64 = 0
        var cancelledBeforeSelection: UInt64 = 0
        var storageUnavailableBeforeSelection: UInt64 = 0

        init(pressurePolicy: CapturePressurePolicy) {
            self.pressurePolicy = pressurePolicy
            self.ordinaryQueue = FixedRing(capacity: pressurePolicy.ordinaryCapacity)
        }

        var queued: Int { ordinaryQueue.count + (reservedUserEvent == nil ? 0 : 1) }
        var outstanding: Int { ordinaryOutstanding + (userEventOutstanding ? 1 : 0) }

        mutating func admit(_ candidate: CaptureAdmissionCandidate) -> CaptureAdmissionDisposition {
            offered += 1
            guard closeReason == nil else {
                rejectedClosed += 1
                return .rejected(.closed)
            }
            if candidate.usesReservedUserEventLane {
                guard userEventOutstanding == false else {
                    rejectedUserEventBusy += 1
                    return .rejected(.userEventBusy)
                }
            } else {
                guard ordinaryOutstanding < pressurePolicy.ordinaryCapacity else {
                    rejectedOrdinaryCapacity += 1
                    return .rejected(.ordinaryCapacity)
                }
            }

            let value = AdmittedCaptureCandidate(
                admissionSequence: nextAdmissionSequence,
                candidate: candidate
            )
            nextAdmissionSequence += 1
            if candidate.usesReservedUserEventLane {
                reservedUserEvent = value
                userEventOutstanding = true
            } else {
                precondition(ordinaryQueue.append(value))
                ordinaryOutstanding += 1
            }
            admitted += 1
            maximumOutstanding = max(maximumOutstanding, outstanding)
            return .admitted(value)
        }

        mutating func takeNext() -> AdmittedCaptureCandidate? {
            guard inFlight == nil else { return nil }
            let ordinary = ordinaryQueue.first
            let userEvent = reservedUserEvent
            let next: AdmittedCaptureCandidate?
            switch (ordinary, userEvent) {
            case let (ordinary?, userEvent?):
                if ordinary.admissionSequence < userEvent.admissionSequence {
                    next = ordinaryQueue.removeFirst()
                } else {
                    next = userEvent
                    reservedUserEvent = nil
                }
            case (.some, .none):
                next = ordinaryQueue.removeFirst()
            case (.none, .some):
                next = userEvent
                reservedUserEvent = nil
            case (.none, .none):
                next = nil
            }
            inFlight = next
            return next
        }

        mutating func finishInFlight(
            _ admitted: AdmittedCaptureCandidate,
            status: CaptureAdmissionTerminalStatus
        ) {
            precondition(inFlight == admitted)
            inFlight = nil
            releaseLane(for: admitted)
            switch status {
            case .completed: completed += 1
            case .writerFailed: writerFailed += 1
            case .cancelledBeforeSelection: cancelledBeforeSelection += 1
            case .storageUnavailableBeforeSelection: storageUnavailableBeforeSelection += 1
            }
        }

        mutating func close(
            reason: CaptureAdmissionCloseReason,
            mode: CaptureAdmissionCloseMode
        ) -> [CaptureAdmissionTerminalResult] {
            guard closeReason == nil else { return [] }
            closeReason = reason
            closeMode = mode
            guard mode == .abortQueuedBeforeSelection else { return [] }

            var aborted = ordinaryQueue.removeAll()
            if let reservedUserEvent {
                aborted.append(reservedUserEvent)
                self.reservedUserEvent = nil
            }
            aborted.sort { $0.admissionSequence < $1.admissionSequence }
            let status: CaptureAdmissionTerminalStatus = reason == .storageUnavailable
                ? .storageUnavailableBeforeSelection
                : .cancelledBeforeSelection
            for admitted in aborted {
                releaseLane(for: admitted)
                if status == .storageUnavailableBeforeSelection {
                    storageUnavailableBeforeSelection += 1
                } else {
                    cancelledBeforeSelection += 1
                }
            }
            return aborted.map { CaptureAdmissionTerminalResult(admitted: $0, status: status) }
        }

        func shouldConsumerExit() -> Bool {
            closeReason != nil && queued == 0 && inFlight == nil
        }

        func snapshot() -> CaptureAdmissionSnapshot {
            let depth = outstanding
            let reason: CapturePressureReason
            if closeReason == .storageUnavailable {
                reason = .storageUnavailable
            } else if depth >= pressurePolicy.cadenceReductionDepth {
                reason = .cadenceQualityReduced
            } else if depth >= pressurePolicy.uploadPauseDepth {
                reason = .uploadPaused
            } else if depth >= pressurePolicy.optionalComputeDropDepth {
                reason = .optionalComputeDropped
            } else {
                reason = .none
            }
            return CaptureAdmissionSnapshot(
                offered: offered,
                admitted: admitted,
                rejectedOrdinaryCapacity: rejectedOrdinaryCapacity,
                rejectedUserEventBusy: rejectedUserEventBusy,
                rejectedClosed: rejectedClosed,
                queued: queued,
                inFlight: inFlight == nil ? 0 : 1,
                outstanding: depth,
                maximumOutstanding: maximumOutstanding,
                completed: completed,
                writerFailed: writerFailed,
                cancelledBeforeSelection: cancelledBeforeSelection,
                storageUnavailableBeforeSelection: storageUnavailableBeforeSelection,
                closeReason: closeReason,
                pressureReason: reason,
                optionalComputeDropped: reason != .none,
                uploadPaused: [.uploadPaused, .cadenceQualityReduced, .storageUnavailable]
                    .contains(reason),
                cadenceQualityReductionRequested: reason == .cadenceQualityReduced
            )
        }

        private mutating func releaseLane(for admitted: AdmittedCaptureCandidate) {
            if admitted.candidate.usesReservedUserEventLane {
                precondition(userEventOutstanding)
                userEventOutstanding = false
            } else {
                precondition(ordinaryOutstanding > 0)
                ordinaryOutstanding -= 1
            }
        }
    }

    private let state: OSAllocatedUnfairLock<State>
    private let wakeStream: AsyncStream<Void>
    private let wakeContinuation: AsyncStream<Void>.Continuation

    public init(pressurePolicy: CapturePressurePolicy) {
        state = OSAllocatedUnfairLock(initialState: State(pressurePolicy: pressurePolicy))
        let wake = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        wakeStream = wake.stream
        wakeContinuation = wake.continuation
    }

    public func offer(_ candidate: CaptureAdmissionCandidate) -> CaptureAdmissionDisposition {
        let disposition = state.withLock { $0.admit(candidate) }
        if disposition.isAdmitted {
            wakeContinuation.yield(())
        }
        return disposition
    }

    public func snapshot() -> CaptureAdmissionSnapshot {
        state.withLock { $0.snapshot() }
    }

    @discardableResult
    public func close(
        reason: CaptureAdmissionCloseReason,
        mode: CaptureAdmissionCloseMode
    ) -> CaptureAdmissionCloseReport {
        let report = state.withLock { state in
            let terminated = state.close(reason: reason, mode: mode)
            return CaptureAdmissionCloseReport(
                terminatedBeforeSelection: terminated,
                snapshot: state.snapshot()
            )
        }
        wakeContinuation.finish()
        return report
    }

    public func runConsumer(
        writer: @escaping @Sendable (AdmittedCaptureCandidate) async throws -> Void,
        onTerminal: @escaping @Sendable (CaptureAdmissionTerminalResult) async -> Void = { _ in }
    ) async throws -> CaptureAdmissionSnapshot {
        let leased = state.withLock { state in
            guard state.consumerLeased == false else { return false }
            state.consumerLeased = true
            return true
        }
        guard leased else { throw CaptureAdmissionError.consumerAlreadyLeased }

        var wakeIterator = wakeStream.makeAsyncIterator()
        while true {
            while let admitted = state.withLock({ $0.takeNext() }) {
                do {
                    try await writer(admitted)
                    let terminal = CaptureAdmissionTerminalResult(
                        admitted: admitted,
                        status: .completed
                    )
                    state.withLock { $0.finishInFlight(admitted, status: .completed) }
                    await onTerminal(terminal)
                } catch {
                    let terminal = CaptureAdmissionTerminalResult(
                        admitted: admitted,
                        status: .writerFailed
                    )
                    state.withLock { $0.finishInFlight(admitted, status: .writerFailed) }
                    await onTerminal(terminal)
                    let aborted = close(
                        reason: .storageUnavailable,
                        mode: .abortQueuedBeforeSelection
                    )
                    for result in aborted.terminatedBeforeSelection {
                        await onTerminal(result)
                    }
                    throw error
                }
            }

            if state.withLock({ $0.shouldConsumerExit() }) {
                return snapshot()
            }
            guard await wakeIterator.next() != nil else {
                return snapshot()
            }
        }
    }
}

private struct FixedRing<Element: Sendable>: Sendable {
    private var storage: [Element?]
    private var head = 0
    private(set) var count = 0

    init(capacity: Int) {
        precondition(capacity > 0)
        storage = Array(repeating: nil, count: capacity)
    }

    var first: Element? {
        guard count > 0 else { return nil }
        return storage[head]
    }

    mutating func append(_ element: Element) -> Bool {
        guard count < storage.count else { return false }
        let index = (head + count) % storage.count
        storage[index] = element
        count += 1
        return true
    }

    mutating func removeFirst() -> Element? {
        guard count > 0 else { return nil }
        let element = storage[head]
        storage[head] = nil
        head = (head + 1) % storage.count
        count -= 1
        return element
    }

    mutating func removeAll() -> [Element] {
        var elements = [Element]()
        elements.reserveCapacity(count)
        while let element = removeFirst() {
            elements.append(element)
        }
        return elements
    }
}
