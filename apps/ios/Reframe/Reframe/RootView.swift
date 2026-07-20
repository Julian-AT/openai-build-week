import EditCore
import SpatialProtocol
import SwiftUI

struct RootView: View {
  @Environment(\.scenePhase) private var scenePhase
  @State private var spatialSession = SpatialSession()
  @State private var prompt = ""
  @State private var isListening = false

  var body: some View {
    ZStack {
      CameraSurface(session: spatialSession.session)
        .ignoresSafeArea()

      LinearGradient(
        colors: [.black.opacity(0.62), .clear, .black.opacity(0.8)],
        startPoint: .top,
        endPoint: .bottom
      )
      .ignoresSafeArea()
      .allowsHitTesting(false)

      VStack(spacing: 0) {
        SessionHeader(phase: spatialSession.phase)
        Spacer()
        AgentComposer(prompt: $prompt, isListening: $isListening)
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
        Button("Send", systemImage: "arrow.up") { submit() }
          .labelStyle(.iconOnly)
          .buttonStyle(.borderedProminent)
          .tint(.white)
          .foregroundStyle(.black)
          .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
      .padding(12)
      .background(.white.opacity(0.1), in: .rect(cornerRadius: 14))

      Text("Every suggestion becomes a reversible preview. Reframe commits only after you confirm.")
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .padding(16)
    .background(.ultraThinMaterial, in: .rect(cornerRadius: 24))
    .compositingGroup()
    .clipShape(.rect(cornerRadius: 24))
  }

  private func submit() {
    prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
