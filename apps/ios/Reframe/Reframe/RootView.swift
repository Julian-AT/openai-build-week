import EditCore
import SpatialProtocol
import SwiftUI

struct RootView: View {
  @Environment(\.scenePhase) private var scenePhase
  @State private var spatialSession = SpatialSession()
  @State private var prompt = ""
  @State private var isListening = false
  @State private var targetCaptureRequest: TargetCaptureRequest?

  var body: some View {
    ZStack {
      CameraSurface(
        spatialSession: spatialSession,
        captureRequest: targetCaptureRequest
      )
      .ignoresSafeArea()

      LinearGradient(
        colors: [.black.opacity(0.62), .clear, .black.opacity(0.8)],
        startPoint: .top,
        endPoint: .bottom
      )
      .ignoresSafeArea()
      .allowsHitTesting(false)

      TargetReticle(
        isTracking: spatialSession.phase == .tracking,
        lastSource: spatialSession.lastTargetSeed?.source
      )
      .allowsHitTesting(false)

      VStack(spacing: 0) {
        SessionHeader(phase: spatialSession.phase)
        Spacer()
        AgentComposer(
          prompt: $prompt,
          isListening: $isListening,
          captureVoiceTarget: {
            targetCaptureRequest = TargetCaptureRequest(source: .voiceCapture)
          },
          submitPrompt: { value in
            Task { await spatialSession.submitTypedTurn(value) }
          },
          confirmPreview: {
            Task { await spatialSession.confirmPendingPreview() }
          },
          restoreLatest: {
            Task { await spatialSession.restoreLatest() }
          },
          isSubmitting: spatialSession.isSubmittingTurn,
          gatewayStatus: spatialSession.gatewayStatus
        )
      }
      .padding(.horizontal, 18)
      .padding(.vertical, 12)
    }
    .task { await spatialSession.start() }
    .onChange(of: scenePhase) {
      if scenePhase != .active { spatialSession.pause() }
    }
    .preferredColorScheme(.dark)
  }
}

private struct TargetReticle: View {
  let isTracking: Bool
  let lastSource: TargetSeedSource?

  var body: some View {
    ZStack {
      Circle()
        .strokeBorder(color.opacity(0.9), lineWidth: 2)
        .frame(width: 30, height: 30)
      Circle()
        .fill(color)
        .frame(width: 4, height: 4)
    }
    .shadow(color: .black.opacity(0.7), radius: 2)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Target reticle")
    .accessibilityValue(isTracking ? "Ready" : "Waiting for spatial tracking")
  }

  private var color: Color {
    guard isTracking else { return .white.opacity(0.45) }
    return lastSource == nil ? .white : .green
  }
}

private struct SessionHeader: View {
  let phase: SpatialSession.Phase

  var body: some View {
    HStack(spacing: 12) {
      Text("Reframe")
        .font(.title3.weight(.bold))
        .tracking(-0.5)
      Spacer()
      Label(status, systemImage: "circle.fill")
        .font(.caption.weight(.semibold))
        .foregroundStyle(statusColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.42), in: Capsule())
        .accessibilityLabel("Spatial status: \(status)")
    }
  }

  private var status: String {
    switch phase {
    case .awaitingPermission: "Camera access"
    case .initializing: "Mapping space"
    case .tracking: "Space ready"
    case .limited(let message): message
    case .unavailable: "Camera unavailable"
    }
  }

  private var statusColor: Color {
    phase == .tracking ? .green : .white.opacity(0.82)
  }
}

private struct AgentComposer: View {
  @Binding var prompt: String
  @Binding var isListening: Bool
  let captureVoiceTarget: () -> Void
  let submitPrompt: (String) -> Void
  let confirmPreview: () -> Void
  let restoreLatest: () -> Void
  let isSubmitting: Bool
  let gatewayStatus: String

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text("Design with Reframe")
            .font(.headline)
          Text(
            isListening ? "Listening and understanding your space" : "Ask for a change to this room"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        Spacer()
        Button(
          isListening ? "Stop listening" : "Start voice",
          systemImage: isListening ? "stop.fill" : "waveform"
        ) {
          if !isListening { captureVoiceTarget() }
          isListening.toggle()
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderedProminent)
        .tint(isListening ? .red : .white)
        .foregroundStyle(.black)
        .accessibilityHint("Starts or stops the realtime design conversation")
      }

      HStack(spacing: 10) {
        TextField("Try a lighter chair by the window", text: $prompt)
          .textFieldStyle(.plain)
          .submitLabel(.send)
          .onSubmit(submit)
        Button(
          isSubmitting ? "Preparing" : "Send", systemImage: isSubmitting ? "hourglass" : "arrow.up"
        ) { submit() }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderedProminent)
        .tint(.white)
        .foregroundStyle(.black)
        .disabled(isSubmitting || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
      .padding(12)
      .background(.white.opacity(0.1), in: .rect(cornerRadius: 14))

      Text("Every suggestion becomes a reversible preview. Reframe commits only after you confirm.")
        .font(.caption2)
        .foregroundStyle(.secondary)
      Text(gatewayStatus)
        .font(.caption2.weight(.medium))
        .foregroundStyle(.tertiary)
      HStack(spacing: 10) {
        Button("Confirm preview", action: confirmPreview)
          .buttonStyle(.borderedProminent)
          .tint(.green)
        Button("Restore", action: restoreLatest)
          .buttonStyle(.bordered)
      }
    }
    .padding(16)
    .background(.ultraThinMaterial, in: .rect(cornerRadius: 24))
    .compositingGroup()
    .clipShape(.rect(cornerRadius: 24))
  }

  private func submit() {
    let value = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return }
    prompt = value
    submitPrompt(value)
  }
}
