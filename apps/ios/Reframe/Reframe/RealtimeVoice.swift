import AVFoundation
import Foundation
import WebRTC

enum RealtimeVoiceError: Error, Equatable {
  case microphonePermissionDenied
  case audioSessionUnavailable
  case peerConnectionUnavailable
  case offerCreationFailed
  case localDescriptionFailed
  case remoteDescriptionFailed
  case dataChannelUnavailable
}

/// The native transport owns audio and signaling. Model tool calls are reduced
/// to a validated utterance and handed to the deterministic scene coordinator;
/// this object never commits or mutates scene state itself.
@MainActor
final class NativeRealtimeVoiceTransport: NSObject, RTCDataChannelDelegate {
  private let audioSession = AVAudioSession.sharedInstance()
  private var factory: RTCPeerConnectionFactory?
  private var peerConnection: RTCPeerConnection?
  private var audioTrack: RTCAudioTrack?
  private var dataChannel: RTCDataChannel?
  private var onUserTurn: (@MainActor @Sendable (String) async -> String)?
  private var active = false

  func start(
    client: GatewayClient,
    onUserTurn: @escaping @MainActor @Sendable (String) async -> String
  ) async throws {
    guard !active else { return }
    guard await requestMicrophonePermission() else {
      throw RealtimeVoiceError.microphonePermissionDenied
    }
    do {
      try audioSession.setCategory(
        .playAndRecord,
        mode: .voiceChat,
        options: [.defaultToSpeaker, .allowBluetooth]
      )
      try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    } catch {
      throw RealtimeVoiceError.audioSessionUnavailable
    }

    guard RTCInitializeSSL() else {
      deactivateAudio()
      throw RealtimeVoiceError.audioSessionUnavailable
    }
    let factory = RTCPeerConnectionFactory()
    let configuration = RTCConfiguration()
    configuration.sdpSemantics = .unifiedPlan
    let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
    guard
      let peer = factory.peerConnection(
        with: configuration,
        constraints: constraints,
        delegate: nil
      )
    else {
      deactivateAudio()
      throw RealtimeVoiceError.peerConnectionUnavailable
    }
    let source = factory.audioSource(with: nil)
    let track = factory.audioTrack(with: source, trackId: "reframe-microphone")
    guard peer.add(track, streamIds: ["reframe-voice"]) != nil else {
      peer.close()
      deactivateAudio()
      throw RealtimeVoiceError.peerConnectionUnavailable
    }
    let channelConfiguration = RTCDataChannelConfiguration()
    guard
      let channel = peer.dataChannel(
        forLabel: "oai-events",
        configuration: channelConfiguration
      )
    else {
      peer.close()
      deactivateAudio()
      throw RealtimeVoiceError.dataChannelUnavailable
    }
    channel.delegate = self

    do {
      let offer = try await createOffer(peer: peer, constraints: constraints)
      try await setLocalDescription(peer: peer, description: offer)
      try await waitForIceGathering(peer: peer)
      guard let localDescription = peer.localDescription else {
        throw RealtimeVoiceError.offerCreationFailed
      }
      let answerSDP = try await client.exchangeRealtimeSDP(offer: localDescription.sdp)
      try await setRemoteDescription(
        peer: peer,
        description: RTCSessionDescription(type: .answer, sdp: answerSDP)
      )
    } catch {
      channel.close()
      peer.close()
      deactivateAudio()
      throw error
    }

    self.factory = factory
    self.peerConnection = peer
    self.audioTrack = track
    self.dataChannel = channel
    self.onUserTurn = onUserTurn
    active = true
  }

  func stop() {
    dataChannel?.close()
    peerConnection?.close()
    dataChannel = nil
    audioTrack = nil
    peerConnection = nil
    factory = nil
    onUserTurn = nil
    active = false
    deactivateAudio()
  }

  nonisolated func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
    // The coordinator owns scene state; this callback only tracks transport.
  }

  nonisolated func dataChannel(
    _ dataChannel: RTCDataChannel,
    didReceiveMessageWith buffer: RTCDataBuffer
  ) {
    guard let object = try? JSONSerialization.jsonObject(with: buffer.data),
      let event = object as? [String: Any],
      event["type"] as? String == "response.function_call_arguments.done",
      event["name"] as? String == "submit_user_turn",
      let callID = event["call_id"] as? String,
      callID.range(of: #"^[A-Za-z0-9._-]{1,128}$"#, options: .regularExpression) != nil,
      let arguments = event["arguments"] as? String,
      arguments.utf8.count <= 8_000,
      let argumentData = arguments.data(using: .utf8),
      let argumentObject = try? JSONSerialization.jsonObject(with: argumentData),
      let argumentMap = argumentObject as? [String: Any],
      argumentMap.count == 6 || argumentMap.count == 7,
      [
        "client_turn_id", "utterance", "intent_hint", "pointer_context_id",
        "client_scene_revision", "pending_proposal_id",
      ].allSatisfy({ argumentMap.keys.contains($0) }),
      argumentMap.keys.allSatisfy({
        [
          "client_turn_id", "utterance", "intent_hint", "pointer_context_id",
          "pointer_context", "client_scene_revision", "pending_proposal_id",
        ].contains($0)
      }),
      let clientTurnID = argumentMap["client_turn_id"] as? String,
      clientTurnID.range(of: #"^[A-Za-z][A-Za-z0-9_-]{0,127}$"#, options: .regularExpression)
        != nil,
      let utterance = argumentMap["utterance"] as? String,
      !utterance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      utterance == utterance.trimmingCharacters(in: .whitespacesAndNewlines),
      utterance.utf8.count <= 2_000,
      !utterance.unicodeScalars.contains(where: { $0.value <= 31 || $0.value == 127 }),
      argumentMap["intent_hint"] is NSNull
        || ["place", "replace", "remove", "restore"].contains(argumentMap["intent_hint"] as? String),
      argumentMap["pointer_context_id"] is NSNull
        || ((argumentMap["pointer_context_id"] as? String)?.range(
          of: #"^[A-Za-z][A-Za-z0-9_-]{0,127}$"#, options: .regularExpression
        ) != nil),
      let sceneRevision = argumentMap["client_scene_revision"] as? Int,
      sceneRevision >= 0,
      argumentMap["pending_proposal_id"] is NSNull
        || ((argumentMap["pending_proposal_id"] as? String)?.range(
          of: #"^[A-Za-z][A-Za-z0-9_-]{0,127}$"#, options: .regularExpression
        ) != nil)
    else { return }
    Task { @MainActor [weak self] in
      guard let self, let onUserTurn = self.onUserTurn else { return }
      let output = await onUserTurn(utterance)
      guard output.utf8.count <= 8_000, self.dataChannel?.readyState == .open else {
        return
      }
      let event: [String: Any] = [
        "type": "conversation.item.create",
        "item": [
          "type": "function_call_output",
          "call_id": callID,
          "output": output,
        ],
      ]
      guard let encoded = try? JSONSerialization.data(withJSONObject: event) else { return }
      _ = self.dataChannel?.sendData(RTCDataBuffer(data: encoded, isBinary: false))
      let response = try? JSONSerialization.data(withJSONObject: ["type": "response.create"])
      if let response {
        _ = self.dataChannel?.sendData(RTCDataBuffer(data: response, isBinary: false))
      }
    }
  }

  private func requestMicrophonePermission() async -> Bool {
    switch audioSession.recordPermission {
    case .granted:
      return true
    case .denied:
      return false
    case .undetermined:
      return await withCheckedContinuation { continuation in
        audioSession.requestRecordPermission { granted in
          continuation.resume(returning: granted)
        }
      }
    @unknown default:
      return false
    }
  }

  private func deactivateAudio() {
    try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
  }

  private func createOffer(
    peer: RTCPeerConnection,
    constraints: RTCMediaConstraints
  ) async throws -> RTCSessionDescription {
    let sdp = try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<String, Error>) in
      peer.offer(for: constraints) { description, error in
        if let description {
          continuation.resume(returning: description.sdp)
        } else {
          continuation.resume(throwing: error ?? RealtimeVoiceError.offerCreationFailed)
        }
      }
    }
    return RTCSessionDescription(type: .offer, sdp: sdp)
  }

  private func setLocalDescription(
    peer: RTCPeerConnection,
    description: RTCSessionDescription
  ) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      peer.setLocalDescription(description) { error in
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
      }
    }
  }

  private func setRemoteDescription(
    peer: RTCPeerConnection,
    description: RTCSessionDescription
  ) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      peer.setRemoteDescription(description) { error in
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
      }
    }
  }

  private func waitForIceGathering(peer: RTCPeerConnection) async throws {
    for _ in 0..<40 {
      if peer.iceGatheringState == .complete { return }
      try await Task.sleep(for: .milliseconds(50))
    }
  }
}
