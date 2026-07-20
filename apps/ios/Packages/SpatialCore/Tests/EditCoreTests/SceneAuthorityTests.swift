import EditCore
import Foundation
import SpatialProtocol
import Testing

@Test("preview is revision-neutral and commit increments exactly once")
func previewThenCommit() throws {
  var authority = SceneAuthority(sessionID: "session-1", branchID: "main")
  let proposal = EditProposal(
    id: "proposal-1",
    baseRevision: 0,
    operation: .place(assetID: "ikea-us-99017186", transform: .identity)
  )

  let preview = try authority.preview(proposal)
  #expect(preview.baseRevision == 0)
  #expect(authority.scene.revision == 0)

  let transaction = try authority.commit(preview, idempotencyKey: "turn-1")
  #expect(transaction.committedRevision == 1)
  #expect(authority.scene.revision == 1)
  #expect(authority.scene.objects.count == 1)
}

@Test("the same idempotency key cannot authorize changed intent")
func idempotencyBindsIntent() throws {
  var authority = SceneAuthority(sessionID: "session-1", branchID: "main")
  let first = EditProposal(
    id: "proposal-1",
    baseRevision: 0,
    operation: .place(assetID: "ikea-us-00000001", transform: .identity)
  )
  _ = try authority.commit(authority.preview(first), idempotencyKey: "turn-1")
  let changed = EditProposal(
    id: "proposal-2",
    baseRevision: 1,
    operation: .place(assetID: "ikea-us-00000002", transform: .identity)
  )

  #expect(throws: SceneAuthorityError.idempotencyConflict) {
    try authority.commit(authority.preview(changed), idempotencyKey: "turn-1")
  }
}
