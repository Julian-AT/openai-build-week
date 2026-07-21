import Foundation

/// Credentials returned by the gateway's room-session endpoint. The room ID is
/// authoritative; clients never manufacture a server credential.
public struct RoomSessionCredentials: Codable, Equatable, Sendable {
  public let sessionID: String
  public let credential: String
  public let expiresAtMilliseconds: Int64

  public init(sessionID: String, credential: String, expiresAtMilliseconds: Int64) throws {
    guard
      sessionID.range(of: "^room_[a-z0-9_]{3,120}$", options: .regularExpression) != nil,
      credential.count >= 8,
      credential.count <= 512,
      credential.trimmingCharacters(in: .whitespacesAndNewlines) == credential,
      expiresAtMilliseconds > 0
    else { throw RoomSessionError.invalidCredentials }
    self.sessionID = sessionID
    self.credential = credential
    self.expiresAtMilliseconds = expiresAtMilliseconds
  }

  private enum CodingKeys: String, CodingKey {
    case sessionID = "session_id"
    case credential
    case expiresAtMilliseconds = "expires_at_ms"
  }
}

public enum RoomSessionError: Error, Equatable, Sendable {
  case invalidCredentials
  case sessionMismatch
}
