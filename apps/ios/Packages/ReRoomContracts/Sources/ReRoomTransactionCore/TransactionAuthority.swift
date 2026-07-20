import Foundation
import ReRoomContracts

public enum TransactionAuthorityError: String, Error, Equatable, Sendable {
    case recoveryCorrupt = "recovery_corrupt"
    case bootstrapMismatch = "bootstrap_mismatch"
    case idempotencyConflict = "idempotency_conflict"
    case authorityFrozen = "authority_frozen"
    case invalidLocalUndoToken = "invalid_local_undo_token"
    case missingRequiredArtifact = "missing_required_artifact"
    case invalidRestorePreview = "invalid_restore_preview"
    case invalidDivergence = "invalid_divergence"
}

public struct RestorePreviewSeed: Equatable, Sendable {
    public let previewID: String
    public let expiresAtUTC: String

    public init(previewID: String, expiresAtUTC: String) {
        self.previewID = previewID
        self.expiresAtUTC = expiresAtUTC
    }
}

public struct RestorePreviewReduction: Equatable, Sendable {
    public let proposal: BoundProposal
    public let request: RestoreRequest
    public let reduction: RestoreReduction
    public let validation: TransactionValidation
    public let preview: TransactionPreview

    public init(
        proposal: BoundProposal,
        request: RestoreRequest,
        reduction: RestoreReduction,
        validation: TransactionValidation,
        preview: TransactionPreview
    ) {
        self.proposal = proposal
        self.request = request
        self.reduction = reduction
        self.validation = validation
        self.preview = preview
    }
}

public struct AuthorityDivergenceQuarantine: Equatable, Sendable {
    public let localSnapshot: TransactionGenerationSnapshot
    public let divergentSnapshot: TransactionGenerationSnapshot
    public let reconciliation: Reconciliation

    public init(
        localSnapshot: TransactionGenerationSnapshot,
        divergentSnapshot: TransactionGenerationSnapshot,
        reconciliation: Reconciliation
    ) {
        self.localSnapshot = localSnapshot
        self.divergentSnapshot = divergentSnapshot
        self.reconciliation = reconciliation
    }
}

/// The only mutable owner of a native revision branch.
///
/// Calls cross actor isolation with an asynchronous hop, but every mutation below is a
/// synchronous actor-isolated function: CAS, pure reduction, durable activation, and
/// in-memory publication cannot be interleaved by actor reentrancy.
public actor NativeBranchAuthority {
    private let store: TransactionStore
    private let locallyAvailableArtifacts: [ArtifactReference]
    private var active: TransactionGenerationSnapshot
    private var divergenceQuarantine: AuthorityDivergenceQuarantine?

    public init(
        store: TransactionStore,
        bootstrap: TransactionGenerationCandidate,
        locallyAvailableArtifacts: [ArtifactReference]
    ) throws {
        self.store = store
        self.locallyAvailableArtifacts = locallyAvailableArtifacts
        switch store.recover() {
        case .noActiveGeneration:
            self.active = try store.activate(bootstrap)
        case .active(let recovered):
            guard recovered.scene.sessionID == bootstrap.scene.sessionID,
                  recovered.scene.sceneID == bootstrap.scene.sceneID,
                  recovered.scene.revisionAuthority == bootstrap.scene.revisionAuthority
            else { throw TransactionAuthorityError.bootstrapMismatch }
            self.active = recovered
        case .corrupt:
            throw TransactionAuthorityError.recoveryCorrupt
        }
        self.divergenceQuarantine = nil
    }

    public func activeSnapshot() -> TransactionGenerationSnapshot { active }

    public func quarantineState() -> AuthorityDivergenceQuarantine? { divergenceQuarantine }

    public func previewPlace(
        proposal: BoundProposal,
        candidate: DeterministicPlaceCandidate,
        seed: PlacePreviewSeed
    ) throws -> PlacePreviewReduction {
        try PlaceReducer.preview(
            proposal: proposal,
            currentScene: active.scene,
            candidate: candidate,
            seed: seed
        )
    }

    public func commitPlace(
        _ preview: PlacePreviewReduction,
        confirmation: ExplicitConfirmation,
        request: PlaceConfirmationRequest,
        localUndoToken: String
    ) throws -> TransactionReceipt {
        try commitPlaceCritical(
            preview,
            confirmation: confirmation,
            request: request,
            localUndoToken: localUndoToken
        )
    }

    private func commitPlaceCritical(
        _ preview: PlacePreviewReduction,
        confirmation: ExplicitConfirmation,
        request: PlaceConfirmationRequest,
        localUndoToken: String
    ) throws -> TransactionReceipt {
        let fingerprint = try TransactionFingerprint.digest(
            proposal: preview.proposal,
            proposedOperations: preview.proposedOperations
        )
        if let prior = active.idempotencyRecords.first(where: { $0.idempotencyKey == request.idempotencyKey }) {
            guard prior.requestFingerprintSHA256 == fingerprint else {
                throw TransactionAuthorityError.idempotencyConflict
            }
            return prior.receipt
        }
        guard divergenceQuarantine == nil else { throw TransactionAuthorityError.authorityFrozen }
        try requireUndoToken(localUndoToken)

        let reduction = try PlaceReducer.confirm(
            preview,
            currentScene: active.scene,
            confirmation: confirmation,
            request: request
        )
        let transaction = try makeCommittedTransaction(
            transactionID: request.transactionID,
            idempotencyKey: request.idempotencyKey,
            fingerprint: fingerprint,
            proposal: preview.proposal,
            validation: preview.validation,
            preview: preview.preview,
            proposedOperations: reduction.proposedOperations,
            inverseOperation: reduction.inverseOperation,
            compensatesTransactionID: nil,
            confirmation: confirmation,
            committedAtUTC: request.updatedAtUTC,
            localUndoToken: localUndoToken,
            committedSceneRevision: reduction.pendingSceneRevision
        )
        return try activate(
            transaction: transaction,
            pendingScene: reduction.pendingScene
        )
    }

    public func previewReplace(
        proposal: BoundProposal,
        candidate: DeterministicReplaceCandidate,
        seed: PlacePreviewSeed
    ) throws -> ReplacePreviewReduction {
        try ReplaceReducer.preview(
            proposal: proposal,
            currentScene: active.scene,
            candidate: candidate,
            seed: seed
        )
    }

    public func commitReplace(
        _ preview: ReplacePreviewReduction,
        confirmation: ExplicitConfirmation,
        request: PlaceConfirmationRequest,
        localUndoToken: String
    ) throws -> TransactionReceipt {
        try commitReplaceCritical(
            preview,
            confirmation: confirmation,
            request: request,
            localUndoToken: localUndoToken
        )
    }

    private func commitReplaceCritical(
        _ preview: ReplacePreviewReduction,
        confirmation: ExplicitConfirmation,
        request: PlaceConfirmationRequest,
        localUndoToken: String
    ) throws -> TransactionReceipt {
        let fingerprint = try TransactionFingerprint.digest(
            proposal: preview.proposal,
            proposedOperations: preview.proposedOperations
        )
        if let prior = active.idempotencyRecords.first(where: { $0.idempotencyKey == request.idempotencyKey }) {
            guard prior.requestFingerprintSHA256 == fingerprint else {
                throw TransactionAuthorityError.idempotencyConflict
            }
            return prior.receipt
        }
        guard divergenceQuarantine == nil else { throw TransactionAuthorityError.authorityFrozen }
        try requireUndoToken(localUndoToken)

        let reduction = try ReplaceReducer.confirm(
            preview,
            currentScene: active.scene,
            confirmation: confirmation,
            request: request
        )
        let transaction = try makeCommittedTransaction(
            transactionID: request.transactionID,
            idempotencyKey: request.idempotencyKey,
            fingerprint: fingerprint,
            proposal: preview.proposal,
            validation: preview.validation,
            preview: preview.preview,
            proposedOperations: reduction.proposedOperations,
            inverseOperation: reduction.inverseOperation,
            compensatesTransactionID: nil,
            confirmation: confirmation,
            committedAtUTC: request.updatedAtUTC,
            localUndoToken: localUndoToken,
            committedSceneRevision: reduction.pendingSceneRevision
        )
        return try activate(
            transaction: transaction,
            pendingScene: reduction.pendingScene
        )
    }

    public func previewRemove(
        proposal: BoundProposal,
        candidate: DeterministicRemoveCandidate,
        seed: RemovePreviewSeed
    ) throws -> RemovePreviewReduction {
        try RemoveReducer.preview(
            proposal: proposal,
            currentScene: active.scene,
            candidate: candidate,
            seed: seed
        )
    }

    public func commitRemove(
        _ preview: RemovePreviewReduction,
        confirmation: ExplicitConfirmation,
        request: PlaceConfirmationRequest,
        localUndoToken: String
    ) throws -> TransactionReceipt {
        try commitRemoveCritical(
            preview,
            confirmation: confirmation,
            request: request,
            localUndoToken: localUndoToken
        )
    }

    private func commitRemoveCritical(
        _ preview: RemovePreviewReduction,
        confirmation: ExplicitConfirmation,
        request: PlaceConfirmationRequest,
        localUndoToken: String
    ) throws -> TransactionReceipt {
        let fingerprint = try TransactionFingerprint.digest(
            proposal: preview.proposal,
            proposedOperations: preview.proposedOperations
        )
        if let prior = active.idempotencyRecords.first(where: {
            $0.idempotencyKey == request.idempotencyKey
        }) {
            guard prior.requestFingerprintSHA256 == fingerprint else {
                throw TransactionAuthorityError.idempotencyConflict
            }
            return prior.receipt
        }
        guard divergenceQuarantine == nil else {
            throw TransactionAuthorityError.authorityFrozen
        }
        try requireUndoToken(localUndoToken)

        let reduction = try RemoveReducer.confirm(
            preview,
            currentScene: active.scene,
            confirmation: confirmation,
            request: request
        )
        let transaction = try makeCommittedTransaction(
            transactionID: request.transactionID,
            idempotencyKey: request.idempotencyKey,
            fingerprint: fingerprint,
            proposal: preview.proposal,
            validation: preview.validation,
            preview: preview.preview,
            proposedOperations: reduction.proposedOperations,
            inverseOperation: reduction.inverseOperation,
            compensatesTransactionID: nil,
            confirmation: confirmation,
            committedAtUTC: request.updatedAtUTC,
            localUndoToken: localUndoToken,
            committedSceneRevision: reduction.pendingSceneRevision
        )
        return try activate(
            transaction: transaction,
            pendingScene: reduction.pendingScene
        )
    }

    public func previewRestore(
        proposal: BoundProposal,
        request: RestoreRequest,
        seed: RestorePreviewSeed
    ) throws -> RestorePreviewReduction {
        try requireCurrentProposal(proposal, operation: .restore)
        guard validID(seed.previewID, prefix: "preview_"),
              !seed.expiresAtUTC.isEmpty,
              request.updatedAtUTC.isEmpty == false
        else { throw TransactionAuthorityError.invalidRestorePreview }

        let reduction = try RestoreReducer.reduce(
            currentScene: active.scene,
            committedTransactions: active.transactions,
            request: request,
            locallyAvailableArtifacts: locallyAvailableArtifacts
        )
        let operation = reduction.transaction.proposedOperation
        let fingerprint = try TransactionFingerprint.digest(
            proposal: proposal,
            proposedOperations: [operation]
        )
        let checks = restoreValidationChecks(sceneRevision: active.scene.sceneRevision)
        let validation = TransactionValidation(
            contractState: "passed",
            checks: checks,
            validatorVersion: "RR-RESTORE-VALIDATOR-1",
            inputSHA256: try validationInputSHA256(fingerprint: fingerprint, checks: checks)
        )
        return RestorePreviewReduction(
            proposal: proposal,
            request: request,
            reduction: reduction,
            validation: validation,
            preview: TransactionPreview(
                contractPreviewID: seed.previewID,
                baseSceneRevision: proposal.baseSceneRevision,
                expiresAtUTC: seed.expiresAtUTC,
                artifactRefs: operation.requiredArtifactReferences
            )
        )
    }

    public func commitRestore(
        _ preview: RestorePreviewReduction,
        confirmation: ExplicitConfirmation,
        idempotencyKey: String,
        localUndoToken: String
    ) throws -> TransactionReceipt {
        try commitRestoreCritical(
            preview,
            confirmation: confirmation,
            idempotencyKey: idempotencyKey,
            localUndoToken: localUndoToken
        )
    }

    private func commitRestoreCritical(
        _ preview: RestorePreviewReduction,
        confirmation: ExplicitConfirmation,
        idempotencyKey: String,
        localUndoToken: String
    ) throws -> TransactionReceipt {
        let proposedOperations = [preview.reduction.transaction.proposedOperation]
        let fingerprint = try TransactionFingerprint.digest(
            proposal: preview.proposal,
            proposedOperations: proposedOperations
        )
        if let prior = active.idempotencyRecords.first(where: { $0.idempotencyKey == idempotencyKey }) {
            guard prior.requestFingerprintSHA256 == fingerprint else {
                throw TransactionAuthorityError.idempotencyConflict
            }
            return prior.receipt
        }
        guard divergenceQuarantine == nil else { throw TransactionAuthorityError.authorityFrozen }
        guard validID(idempotencyKey, prefix: "txidem_") else {
            throw TransactionAuthorityError.invalidRestorePreview
        }
        try requireUndoToken(localUndoToken)
        try requireConfirmation(confirmation, previewID: preview.preview.previewID)
        try requireCurrentProposal(preview.proposal, operation: .restore)
        let expectedChecks = restoreValidationChecks(sceneRevision: active.scene.sceneRevision)
        let expectedValidation = TransactionValidation(
            contractState: "passed",
            checks: expectedChecks,
            validatorVersion: "RR-RESTORE-VALIDATOR-1",
            inputSHA256: try validationInputSHA256(fingerprint: fingerprint, checks: expectedChecks)
        )
        guard preview.preview.baseSceneRevision == active.scene.sceneRevision,
              validID(preview.preview.previewID, prefix: "preview_"),
              preview.preview.expiresAtUTC.isEmpty == false,
              preview.preview.artifactRefs == proposedOperations[0].requiredArtifactReferences,
              preview.validation == expectedValidation,
              preview.request.transactionID == preview.reduction.transaction.transactionID,
              preview.request.compensatesTransactionID == preview.reduction.sourceTransactionID
        else { throw TransactionAuthorityError.invalidRestorePreview }

        let replay = try RestoreReducer.reduce(
            currentScene: active.scene,
            committedTransactions: active.transactions,
            request: preview.request,
            locallyAvailableArtifacts: locallyAvailableArtifacts
        )
        guard replay == preview.reduction else { throw TransactionAuthorityError.invalidRestorePreview }
        let transaction = try makeCommittedTransaction(
            transactionID: preview.request.transactionID,
            idempotencyKey: idempotencyKey,
            fingerprint: fingerprint,
            proposal: preview.proposal,
            validation: preview.validation,
            preview: preview.preview,
            proposedOperations: proposedOperations,
            inverseOperation: replay.transaction.inverseOperation,
            compensatesTransactionID: replay.sourceTransactionID,
            confirmation: confirmation,
            committedAtUTC: preview.request.updatedAtUTC,
            localUndoToken: localUndoToken,
            committedSceneRevision: replay.transaction.pendingSceneRevision
        )
        return try activate(transaction: transaction, pendingScene: replay.pendingScene)
    }

    public func reportUnexpectedSameBranchDivergence(
        _ divergent: TransactionGenerationSnapshot,
        quarantinedBranchID: String,
        lastKnownGatewayRevision: UInt64?
    ) throws -> AuthorityDivergenceQuarantine {
        guard divergenceQuarantine == nil,
              divergent.generationSHA256 != active.generationSHA256,
              divergent.scene.sessionID == active.scene.sessionID,
              divergent.scene.sceneID == active.scene.sceneID,
              divergent.scene.revisionAuthority == active.scene.revisionAuthority,
              (try TransactionStore.generationSHA256(for: divergent.candidate)) == divergent.generationSHA256,
              validID(quarantinedBranchID, prefix: "branch_"),
              quarantinedBranchID != active.scene.revisionAuthority.revisionBranchID
        else { throw TransactionAuthorityError.invalidDivergence }
        do {
            try store.validateCandidate(divergent.candidate)
        } catch {
            throw TransactionAuthorityError.invalidDivergence
        }
        let quarantine = AuthorityDivergenceQuarantine(
            localSnapshot: active,
            divergentSnapshot: divergent,
            reconciliation: Reconciliation(
                contractState: "manual_required",
                lastKnownGatewayRevision: lastKnownGatewayRevision,
                resolution: "quarantined_divergent_branch",
                automaticMergePermitted: false,
                quarantinedBranchID: quarantinedBranchID
            )
        )
        divergenceQuarantine = quarantine
        return quarantine
    }

    private func activate(
        transaction: TransactionRecord,
        pendingScene: SceneState
    ) throws -> TransactionReceipt {
        guard let commit = transaction.commit else { throw TransactionAuthorityError.invalidRestorePreview }
        let receipt = TransactionReceipt(
            contractTransactionID: transaction.transactionID,
            idempotencyKey: transaction.idempotencyKey,
            requestFingerprintSHA256: transaction.requestFingerprintSHA256,
            revisionAuthority: transaction.revisionAuthority,
            committedSceneRevision: commit.committedSceneRevision,
            resultSHA256: commit.resultSHA256
        )
        let transactions = active.transactions + [transaction]
        let candidate = TransactionGenerationCandidate(
            scene: pendingScene,
            transactions: transactions,
            requiredArtifacts: try TransactionIntegrity.requiredArtifactUnion(
                scene: pendingScene,
                transactions: transactions
            ),
            receipts: active.receipts + [receipt],
            idempotencyRecords: active.idempotencyRecords + [PersistentIdempotencyRecord(
                idempotencyKey: transaction.idempotencyKey,
                requestFingerprintSHA256: transaction.requestFingerprintSHA256,
                transactionID: transaction.transactionID,
                receipt: receipt
            )]
        )
        guard candidate.requiredArtifacts.allSatisfy({ locallyAvailableArtifacts.contains($0) }) else {
            throw TransactionAuthorityError.missingRequiredArtifact
        }
        let activated = try store.activate(candidate)
        active = activated
        return receipt
    }

    private func makeCommittedTransaction(
        transactionID: String,
        idempotencyKey: String,
        fingerprint: String,
        proposal: BoundProposal,
        validation: TransactionValidation,
        preview: TransactionPreview,
        proposedOperations: [TransactionOperation],
        inverseOperation: TransactionOperation,
        compensatesTransactionID: String?,
        confirmation: ExplicitConfirmation,
        committedAtUTC: String,
        localUndoToken: String,
        committedSceneRevision: UInt64
    ) throws -> TransactionRecord {
        let resultSHA256 = try TransactionIntegrity.commitResultSHA256(
            authorityID: proposal.revisionAuthority.authorityID,
            revisionBranchID: proposal.revisionAuthority.revisionBranchID,
            compareAndSwapBaseRevision: proposal.baseSceneRevision,
            committedSceneRevision: committedSceneRevision,
            confirmation: confirmation,
            committedAtUTC: committedAtUTC,
            localDurableBeforeVisibleAck: true
        )
        return TransactionRecord(
            transactionID: transactionID,
            idempotencyKey: idempotencyKey,
            requestFingerprintSHA256: fingerprint,
            sessionID: proposal.sessionID,
            revisionAuthority: proposal.revisionAuthority,
            baseSceneRevision: proposal.baseSceneRevision,
            targetContext: proposal.targetContext,
            intent: proposal.intent,
            proposedOperations: proposedOperations,
            validation: validation,
            preview: preview,
            commit: TransactionCommit(
                contractAuthorityID: proposal.revisionAuthority.authorityID,
                revisionBranchID: proposal.revisionAuthority.revisionBranchID,
                compareAndSwapBaseRevision: proposal.baseSceneRevision,
                committedSceneRevision: committedSceneRevision,
                confirmation: confirmation,
                committedAtUTC: committedAtUTC,
                resultSHA256: resultSHA256
            ),
            inverseOperations: [inverseOperation],
            localUndoToken: localUndoToken,
            compensatesTransactionID: compensatesTransactionID,
            canonicalState: .committed,
            syncState: .localOnly,
            createdAtUTC: committedAtUTC
        )
    }

    private func requireCurrentProposal(_ proposal: BoundProposal, operation: ProductOperation) throws {
        guard proposal.intent.operation == operation,
              ["typed", "tap"].contains(proposal.intent.source),
              proposal.sessionID == active.scene.sessionID,
              proposal.revisionAuthority == active.scene.revisionAuthority,
              proposal.revisionAuthority.kind == .nativeDevice
        else { throw PlaceRejection.authorityMismatch }
        guard proposal.baseSceneRevision == active.scene.sceneRevision,
              proposal.targetContext.capturedSceneRevision == active.scene.sceneRevision
        else { throw PlaceRejection.staleBaseRevision }
        guard proposal.targetContext.worldFrameID == active.scene.worldFrame.worldFrameID,
              proposal.targetContext.worldFrameVersion == active.scene.worldFrame.worldFrameVersion
        else { throw PlaceRejection.worldMismatch }
    }

    private func requireConfirmation(_ confirmation: ExplicitConfirmation, previewID: String) throws {
        guard confirmation.kind == "explicit_user_confirmation",
              validID(confirmation.actorID, prefix: "user_"),
              confirmation.source == "native_ui",
              confirmation.previewID == previewID,
              validID(confirmation.confirmationEventID, prefix: "event_"),
              !confirmation.confirmedAtUTC.isEmpty
        else { throw TransactionAuthorityError.invalidRestorePreview }
    }

    private func requireUndoToken(_ token: String) throws {
        guard validID(token, prefix: "undo_") else {
            throw TransactionAuthorityError.invalidLocalUndoToken
        }
    }

    private func restoreValidationChecks(sceneRevision: UInt64) -> [ValidationCheck] {
        [
            ValidationCheck(contractCheckID: "scene_revision", result: "pass", measured: .number(Double(sceneRevision)), threshold: .number(Double(sceneRevision))),
            ValidationCheck(contractCheckID: "artifact_integrity", result: "pass", measured: .boolean(true), threshold: .boolean(true)),
            ValidationCheck(contractCheckID: "snapshot_integrity", result: "pass", measured: .boolean(true), threshold: .boolean(true)),
            ValidationCheck(contractCheckID: "compensation_eligibility", result: "pass", measured: .boolean(true), threshold: .boolean(true)),
        ]
    }

    private func validationInputSHA256(
        fingerprint: String,
        checks: [ValidationCheck]
    ) throws -> String {
        let scope = AuthorityValidationDigest(
            requestFingerprint: fingerprint,
            checks: checks.map {
                AuthorityValidationDigestCheck(
                    checkID: $0.checkID,
                    measured: $0.measured,
                    threshold: $0.threshold
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try CanonicalJSON.digest(jsonData: encoder.encode(scope))
    }

    private func validID(_ value: String, prefix: String) -> Bool {
        let uuid = "[0-9a-f]{8}-[0-9a-f]{4}-[47][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}"
        return value.range(
            of: "^\(NSRegularExpression.escapedPattern(for: prefix))\(uuid)$",
            options: .regularExpression
        ) != nil
    }
}

private struct AuthorityValidationDigest: Codable {
    let requestFingerprint: String
    let checks: [AuthorityValidationDigestCheck]
    enum CodingKeys: String, CodingKey {
        case requestFingerprint = "request_fingerprint"
        case checks
    }
}

private struct AuthorityValidationDigestCheck: Codable {
    let checkID: String
    let measured: ValidationMeasurement
    let threshold: ValidationMeasurement
    enum CodingKeys: String, CodingKey {
        case checkID = "check_id"
        case measured, threshold
    }
}
