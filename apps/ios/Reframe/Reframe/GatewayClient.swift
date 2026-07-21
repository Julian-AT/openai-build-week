import Foundation
import RenderCore
import SpatialProtocol

enum GatewayClientError: Error, Equatable {
  case invalidBaseURL
  case unauthorized
  case invalidResponse
  case requestFailed
}

/// Thin room-scoped control transport. It never runs from the render loop and
/// returns opaque JSON for the gateway-owned proposal/transaction schemas.
struct GatewayClient: Sendable {
  let baseURL: URL
  let room: RoomSessionCredentials

  init(baseURL: URL, room: RoomSessionCredentials) throws {
    guard baseURL.scheme == "http" || baseURL.scheme == "https",
      baseURL.user == nil, baseURL.password == nil
    else { throw GatewayClientError.invalidBaseURL }
    self.baseURL = baseURL
    self.room = room
  }

  func submitTurn(
    utterance: String,
    sceneRevision: Int,
    pointerContextID: String? = nil,
    pendingProposalID: String? = nil,
    clientTurnID: String = "turn_\(UUID().uuidString.lowercased())"
  ) async throws -> Data {
    try await post(
      path: "/v1/turns",
      body: [
        "client_turn_id": clientTurnID,
        "utterance": utterance,
        "intent_hint": NSNull(),
        "pointer_context_id": pointerContextID ?? NSNull(),
        "client_scene_revision": sceneRevision,
        "pending_proposal_id": pendingProposalID ?? NSNull(),
      ]
    )
  }

  func confirmPreview(previewID: String, expectedSceneRevision: Int, idempotencyKey: String)
    async throws -> Data
  {
    try await post(
      path: "/v1/edit/confirmations",
      body: [
        "preview_id": previewID,
        "expected_scene_revision": expectedSceneRevision,
        "idempotency_key": idempotencyKey,
      ])
  }

  func preparePreview(proposalID: String) async throws -> Data {
    try await post(path: "/v1/edit/previews", body: ["proposal_id": proposalID])
  }

  func restore(transactionID: String, expectedSceneRevision: Int, idempotencyKey: String)
    async throws -> Data
  {
    try await post(
      path: "/v1/edit/restores",
      body: [
        "transaction_id": transactionID,
        "expected_scene_revision": expectedSceneRevision,
        "idempotency_key": idempotencyKey,
      ])
  }

  /// Downloads only an already-authorized signed delivery URL. Catalog/API
  /// resolution stays outside this transport and supplies the descriptor.
  func downloadVerifiedUSDZ(
    descriptor: AssetDeliveryDescriptor,
    from signedURL: URL
  ) async throws -> Data {
    guard descriptor.derivative == .usdz else { throw AssetDeliveryError.unsupportedDerivative }
    guard signedURL.scheme == "https" || signedURL.scheme == "http",
      signedURL.user == nil, signedURL.password == nil
    else { throw GatewayClientError.invalidBaseURL }
    var request = URLRequest(url: signedURL)
    request.httpMethod = "GET"
    request.setValue("Bearer \(room.credential)", forHTTPHeaderField: "Authorization")
    let (bytes, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
      throw GatewayClientError.requestFailed
    }
    return try descriptor.verify(bytes: bytes)
  }

  private func post(path: String, body: [String: Any]) async throws -> Data {
    var request = URLRequest(url: endpoint(path))
    request.httpMethod = "POST"
    request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(room.credential)", forHTTPHeaderField: "Authorization")
    let (bytes, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw GatewayClientError.invalidResponse
    }
    switch httpResponse.statusCode {
    case 200...299: return bytes
    case 401: throw GatewayClientError.unauthorized
    default: throw GatewayClientError.requestFailed
    }
  }

  private func endpoint(_ path: String) -> URL {
    baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
  }
}
