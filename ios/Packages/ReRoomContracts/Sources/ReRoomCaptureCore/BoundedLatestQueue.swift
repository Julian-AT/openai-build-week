public enum BoundedQueueError: String, Error, Equatable, Sendable {
    case invalidCapacity = "invalid_capacity"
}

public enum CaptureQueuePriority: Int, Comparable, CaseIterable, Sendable {
    case cadence = 0
    case viewNovelty = 1
    case keyframe = 2
    case userEvent = 3

    public static func < (lhs: CaptureQueuePriority, rhs: CaptureQueuePriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public init(selectedReason: SelectedFrameReason) {
        self = switch selectedReason {
        case .cadence, .recovery: .cadence
        case .viewNovelty: .viewNovelty
        case .keyframe: .keyframe
        case .userEvent: .userEvent
        }
    }
}

public enum BoundedQueueOfferDisposition: String, Equatable, Sendable {
    case accepted
    case replacedStale = "replaced_stale"
    case droppedLowerPriority = "dropped_lower_priority"
    case droppedCapacity = "dropped_capacity"
    case droppedCancelled = "dropped_cancelled"
}

public struct CapturePressureObservation: Equatable, Sendable {
    public let pressureReason: CapturePressureReason
    public let optionalComputeDropped: Bool
    public let uploadPaused: Bool
    public let cadenceQualityReductionRequested: Bool
}

public extension CapturePressurePolicy {
    func observe(depth: Int, storageUnavailable: Bool = false) -> CapturePressureObservation {
        let reason: CapturePressureReason
        if storageUnavailable {
            reason = .storageUnavailable
        } else if depth >= cadenceReductionDepth {
            reason = .cadenceQualityReduced
        } else if depth >= uploadPauseDepth {
            reason = .uploadPaused
        } else if depth >= optionalComputeDropDepth {
            reason = .optionalComputeDropped
        } else {
            reason = .none
        }
        return CapturePressureObservation(
            pressureReason: reason,
            optionalComputeDropped: reason != .none,
            uploadPaused: [.uploadPaused, .cadenceQualityReduced, .storageUnavailable]
                .contains(reason),
            cadenceQualityReductionRequested: reason == .cadenceQualityReduced
        )
    }
}

public struct BoundedQueueLease<Element: Sendable>: Sendable {
    public let token: UInt64
    public let element: Element

    fileprivate init(token: UInt64, element: Element) {
        self.token = token
        self.element = element
    }
}

extension BoundedQueueLease: Equatable where Element: Equatable {}

/// A post-durability actor queue. Its fixed capacity includes queued and single in-flight work.
public actor BoundedLatestQueue<Element: Sendable> {
    private struct Entry: Sendable {
        let offerSequence: UInt64
        let priority: CaptureQueuePriority
        let element: Element
    }

    private let capacity: Int
    private let pressurePolicy: CapturePressurePolicy
    private var entries = [Entry]()
    private var inFlight: (token: UInt64, entry: Entry)?
    private var nextOfferSequence: UInt64 = 0
    private var nextLeaseToken: UInt64 = 0
    private var isCancelled = false
    private var offered: UInt64 = 0
    private var accepted: UInt64 = 0
    private var replaced: UInt64 = 0
    private var dropped: UInt64 = 0
    private var completed: UInt64 = 0
    private var cancelled: UInt64 = 0
    private var maximumDepth = 0

    public init(capacity: Int, pressurePolicy: CapturePressurePolicy) throws {
        guard capacity > 0, capacity <= pressurePolicy.ordinaryCapacity else {
            throw BoundedQueueError.invalidCapacity
        }
        self.capacity = capacity
        self.pressurePolicy = pressurePolicy
        entries.reserveCapacity(capacity)
    }

    public func offer(
        _ element: Element,
        priority: CaptureQueuePriority
    ) -> BoundedQueueOfferDisposition {
        offered += 1
        guard isCancelled == false else {
            dropped += 1
            return .droppedCancelled
        }

        let incoming = Entry(
            offerSequence: nextOfferSequence,
            priority: priority,
            element: element
        )
        nextOfferSequence += 1
        if currentDepth < capacity {
            entries.append(incoming)
            accepted += 1
            maximumDepth = max(maximumDepth, currentDepth)
            return .accepted
        }

        guard let replacementIndex = leastUsefulQueuedIndex() else {
            dropped += 1
            return .droppedCapacity
        }
        let victim = entries[replacementIndex]
        guard incoming.priority >= victim.priority else {
            dropped += 1
            return .droppedLowerPriority
        }
        entries[replacementIndex] = incoming
        accepted += 1
        replaced += 1
        dropped += 1
        return .replacedStale
    }

    public func next() -> BoundedQueueLease<Element>? {
        guard isCancelled == false, inFlight == nil, let index = nextUsefulIndex() else {
            return nil
        }
        let entry = entries.remove(at: index)
        let token = nextLeaseToken
        nextLeaseToken += 1
        inFlight = (token, entry)
        return BoundedQueueLease(token: token, element: entry.element)
    }

    @discardableResult
    public func complete(_ lease: BoundedQueueLease<Element>) -> Bool {
        guard let current = inFlight, current.token == lease.token else { return false }
        inFlight = nil
        completed += 1
        return true
    }

    @discardableResult
    public func cancelAll() -> [Element] {
        guard isCancelled == false else { return [] }
        isCancelled = true
        var values = entries.map(\.element)
        entries.removeAll(keepingCapacity: true)
        if let inFlight {
            values.append(inFlight.entry.element)
            self.inFlight = nil
        }
        cancelled += UInt64(values.count)
        return values
    }

    public func snapshot() -> QueueMetricsSnapshot {
        let pressure = pressurePolicy.observe(depth: currentDepth)
        return try! QueueMetricsSnapshot(
            offered: offered,
            accepted: accepted,
            replaced: replaced,
            dropped: dropped,
            completed: completed,
            cancelled: cancelled,
            currentDepth: currentDepth,
            maximumDepth: maximumDepth,
            uploadPaused: pressure.uploadPaused,
            pressureReason: pressure.pressureReason
        )
    }

    private var currentDepth: Int {
        entries.count + (inFlight == nil ? 0 : 1)
    }

    private func leastUsefulQueuedIndex() -> Int? {
        entries.indices.min { lhs, rhs in
            let left = entries[lhs]
            let right = entries[rhs]
            if left.priority != right.priority {
                return left.priority < right.priority
            }
            return left.offerSequence < right.offerSequence
        }
    }

    private func nextUsefulIndex() -> Int? {
        entries.indices.max { lhs, rhs in
            let left = entries[lhs]
            let right = entries[rhs]
            if left.priority != right.priority {
                return left.priority < right.priority
            }
            return left.offerSequence < right.offerSequence
        }
    }
}
