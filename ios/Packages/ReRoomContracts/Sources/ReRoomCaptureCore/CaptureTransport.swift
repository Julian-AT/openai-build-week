public enum CaptureTransportBehavior: String, CaseIterable, Sendable {
    case echo
    case blackhole
    case reversed
    case duplicateFirst = "duplicate_first"
    case delayedFirst = "delayed_first"
}

public struct CaptureTransportCompletion: Equatable, Sendable {
    public let receipt: NetworkEligibleReceipt
    public let acknowledgement: GatewayAcknowledgement

    fileprivate init(
        receipt: NetworkEligibleReceipt,
        acknowledgement: GatewayAcknowledgement
    ) {
        self.receipt = receipt
        self.acknowledgement = acknowledgement
    }
}

/// Deterministic provider-independent transport fixture. It performs no network operation.
public struct CaptureTransport: Sendable {
    public let gatewayID: String

    public init(gatewayID: String) throws {
        // Reuse the frozen identifier validator without adding a transport-specific schema.
        _ = try GatewayAcknowledgement(
            gatewayID: gatewayID,
            sessionID: "session_00000000-0000-4000-8000-000000000000",
            frameID: "frame_00000000-0000-4000-8000-000000000000",
            idempotencyKey: "frameidem_00000000-0000-4000-8000-000000000000",
            packetSHA256: String(repeating: "0", count: 64),
            acceptedSequence: 0
        )
        self.gatewayID = gatewayID
    }

    public func acknowledgement(
        for receipt: NetworkEligibleReceipt
    ) throws -> GatewayAcknowledgement {
        try GatewayAcknowledgement(
            gatewayID: gatewayID,
            sessionID: receipt.sessionID,
            frameID: receipt.frameID,
            idempotencyKey: receipt.idempotencyKey,
            packetSHA256: receipt.packetSHA256,
            acceptedSequence: receipt.acceptedSequence
        )
    }

    public func completions(
        for receipts: [NetworkEligibleReceipt],
        behavior: CaptureTransportBehavior
    ) throws -> [CaptureTransportCompletion] {
        let ordered: [NetworkEligibleReceipt] = switch behavior {
        case .echo:
            receipts
        case .blackhole:
            []
        case .reversed:
            Array(receipts.reversed())
        case .duplicateFirst:
            receipts + Array(receipts.prefix(1))
        case .delayedFirst:
            Array(receipts.dropFirst()) + Array(receipts.prefix(1))
        }
        return try ordered.map { receipt in
            CaptureTransportCompletion(
                receipt: receipt,
                acknowledgement: try acknowledgement(for: receipt)
            )
        }
    }

    public func validate(_ completion: CaptureTransportCompletion) -> Bool {
        validate(completion.acknowledgement, for: completion.receipt)
    }

    public func validate(
        _ acknowledgement: GatewayAcknowledgement,
        for receipt: NetworkEligibleReceipt
    ) -> Bool {
        acknowledgement.gatewayID == gatewayID
            && acknowledgement.sessionID == receipt.sessionID
            && acknowledgement.frameID == receipt.frameID
            && acknowledgement.idempotencyKey == receipt.idempotencyKey
            && acknowledgement.packetSHA256 == receipt.packetSHA256
            && acknowledgement.acceptedSequence == receipt.acceptedSequence
    }
}
