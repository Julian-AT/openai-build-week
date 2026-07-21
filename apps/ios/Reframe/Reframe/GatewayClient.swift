import Foundation
import RenderCore
import SpatialProtocol

enum GatewayClientError: Error, Equatable {
  case invalidBaseURL
  case invalidAssetIdentifier
  case invalidAssetDeliveryHeaders
  case unauthorized
  case invalidResponse
  case gatewayUnreachable
  case upstreamUnavailable
  case requestFailed
}

struct VerifiedUSDZDelivery: Sendable {
  let descriptor: AssetDeliveryDescriptor
  let bytes: Data
}

enum GatewayHealth: Equatable, Sendable {
  case ready
  case degraded
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

  /// Performs a bounded, read-only gateway health check for the native voice
  /// transport. It never runs on the render loop or mutates scene state.
  func checkGatewayHealth() async throws -> GatewayHealth {
    var request = URLRequest(url: endpoint("/health"))
    request.httpMethod = "GET"
    request.timeoutInterval = 5
    let bytes: Data
    let response: URLResponse
    do {
      (bytes, response) = try await URLSession.shared.data(for: request)
    } catch is URLError {
      throw GatewayClientError.gatewayUnreachable
    }
    guard let httpResponse = response as? HTTPURLResponse,
      (200...299).contains(httpResponse.statusCode)
    else { throw GatewayClientError.requestFailed }
    guard
      let object = try? JSONSerialization.jsonObject(with: bytes),
      let dictionary = object as? [String: Any],
      let status = dictionary["status"] as? String
    else { throw GatewayClientError.invalidResponse }
    switch status {
    case "ok": return .ready
    case "degraded": return .degraded
    default: throw GatewayClientError.invalidResponse
    }
  }

  /// Exchanges a native WebRTC offer for the gateway's OpenAI Realtime answer.
  /// The room credential is scoped to this request; the OpenAI key never leaves
  /// the gateway.
  func exchangeRealtimeSDP(offer: String) async throws -> String {
    guard !offer.isEmpty, offer.utf8.count <= 64_000 else {
      throw GatewayClientError.invalidResponse
    }
    var request = URLRequest(url: endpoint("/v1/realtime/calls"))
    request.httpMethod = "POST"
    request.httpBody = Data(offer.utf8)
    request.timeoutInterval = 20
    request.setValue("application/sdp", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(room.credential)", forHTTPHeaderField: "Authorization")
    let bytes: Data
    let response: URLResponse
    do {
      (bytes, response) = try await URLSession.shared.data(for: request)
    } catch is URLError {
      throw GatewayClientError.gatewayUnreachable
    }
    guard let httpResponse = response as? HTTPURLResponse else {
      throw GatewayClientError.invalidResponse
    }
    guard httpResponse.statusCode == 200 else {
      if httpResponse.statusCode == 401 { throw GatewayClientError.unauthorized }
      throw GatewayClientError.requestFailed
    }
    guard let answer = String(data: bytes, encoding: .utf8),
      !answer.isEmpty,
      answer.utf8.count <= 64_000
    else { throw GatewayClientError.invalidResponse }
    return answer
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
    let bytes: Data
    let response: URLResponse
    do {
      (bytes, response) = try await URLSession.shared.data(for: request)
    } catch is URLError {
      throw GatewayClientError.gatewayUnreachable
    }
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
      throw GatewayClientError.requestFailed
    }
    return try descriptor.verify(bytes: bytes)
  }

  /// Fetches the room-authorized normalized USDZ for an eligible asset. The
  /// gateway returns the content hash and byte length as immutable response
  /// facts; RealityKit never receives bytes until both facts verify locally.
  func downloadVerifiedUSDZ(assetID: String) async throws -> VerifiedUSDZDelivery {
    guard
      assetID.range(
        of: #"^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$"#,
        options: .regularExpression
      ) != nil
    else {
      throw GatewayClientError.invalidAssetIdentifier
    }
    var request = URLRequest(url: endpoint("/v1/assets/\(assetID)/usdz"))
    request.httpMethod = "GET"
    request.setValue("Bearer \(room.credential)", forHTTPHeaderField: "Authorization")
    let bytes: Data
    let response: URLResponse
    do {
      (bytes, response) = try await URLSession.shared.data(for: request)
    } catch is URLError {
      throw GatewayClientError.gatewayUnreachable
    }
    guard let httpResponse = response as? HTTPURLResponse else {
      throw GatewayClientError.invalidResponse
    }
    guard httpResponse.statusCode == 200 else {
      if httpResponse.statusCode == 401 { throw GatewayClientError.unauthorized }
      throw GatewayClientError.requestFailed
    }
    guard
      let hash = httpResponse.value(forHTTPHeaderField: "x-content-sha256"),
      let lengthText = httpResponse.value(forHTTPHeaderField: "content-length"),
      let length = Int(lengthText),
      length > 0,
      let descriptor = try? AssetDeliveryDescriptor(
        assetID: assetID,
        derivative: .usdz,
        expectedSHA256: hash,
        expectedByteLength: length
      )
    else {
      throw GatewayClientError.invalidAssetDeliveryHeaders
    }
    return VerifiedUSDZDelivery(descriptor: descriptor, bytes: try descriptor.verify(bytes: bytes))
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
    case 502: throw GatewayClientError.upstreamUnavailable
    default: throw GatewayClientError.requestFailed
    }
  }

  private func endpoint(_ path: String) -> URL {
    baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
  }
}
