import SpatialProtocol
import Testing

@Test("room credentials accept only gateway-issued room identifiers")
func validatesRoomCredentials() throws {
  let room = try RoomSessionCredentials(
    sessionID: "room_demo_01",
    credential: "credential_123",
    expiresAtMilliseconds: 1_000
  )
  #expect(room.sessionID == "room_demo_01")
}

@Test("room credentials reject legacy session identifiers")
func rejectsLegacySessionIdentifier() {
  #expect(throws: RoomSessionError.invalidCredentials) {
    try RoomSessionCredentials(
      sessionID: "session_legacy",
      credential: "credential_123",
      expiresAtMilliseconds: 1_000
    )
  }
}
