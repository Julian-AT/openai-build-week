import SwiftUI

struct DesignCopilotPanel: View {
    @Bindable var copilot: DesignCopilotModel
    let catalog: RoomEditAssetCatalog
    @State private var settingsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            promptComposer
            consentControls
            submitButton
            voiceButton
            response
            catalogStrip
            settings
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color.indigo.opacity(0.28), Color.cyan.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        }
        .clipShape(.rect(cornerRadius: 18))
        .onDisappear {
            Task { await copilot.cancelVoice() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("design-copilot.panel")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.title2)
                .foregroundStyle(.cyan)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("AI design copilot")
                    .font(.headline)
                Text("GPT-5.6 Sol · suggestions only")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.cyan)
            }
            Spacer()
            Text("OPTIONAL")
                .font(.caption2.monospaced().weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.white.opacity(0.10), in: Capsule())
        }
    }

    private var promptComposer: some View {
        TextField(
            "Describe the room feeling or change",
            text: $copilot.prompt,
            axis: .vertical
        )
        .lineLimit(2...5)
        .textFieldStyle(.plain)
        .padding(12)
        .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("design-copilot.prompt")
    }

    private var consentControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Include one current camera frame", isOn: $copilot.includeCurrentFrame)
                .accessibilityIdentifier("design-copilot.include-frame")
            if copilot.includeCurrentFrame {
                Toggle(
                    "I consent to send this one frame to the configured gateway and OpenAI",
                    isOn: $copilot.frameConsentGranted
                )
                .font(.caption)
                .tint(.cyan)
                .accessibilityIdentifier("design-copilot.frame-consent")
                Text("The live render loop never uploads or waits. Encoding happens only when you tap Ask.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.subheadline)
        .tint(.cyan)
    }

    private var submitButton: some View {
        Button {
            Task { await copilot.submitUserIntent() }
        } label: {
            HStack {
                if copilot.isWorking {
                    ProgressView()
                        .tint(.white)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: copilot.includeCurrentFrame ? "camera.aperture" : "sparkles")
                        .accessibilityHidden(true)
                }
                Text(copilot.includeCurrentFrame ? "Ask Sol about this view" : "Ask Sol")
                    .fontWeight(.semibold)
                Spacer()
                Text("No auto-commit")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
        }
        .buttonStyle(.plain)
        .background(.indigo, in: RoundedRectangle(cornerRadius: 12))
        .disabled(!copilot.canAsk)
        .accessibilityIdentifier("design-copilot.ask")
    }

    private var voiceButton: some View {
        Button {
            Task {
                if copilot.isVoiceActive {
                    await copilot.stopVoice()
                } else if copilot.isAwaitingTranscript {
                    await copilot.cancelVoice()
                } else {
                    await copilot.startVoice()
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: copilot.isVoiceActive
                    ? "stop.circle.fill"
                    : (copilot.isAwaitingTranscript ? "xmark.circle.fill" : "waveform.circle.fill"))
                    .foregroundStyle((copilot.isVoiceActive || copilot.isAwaitingTranscript) ? .red : .cyan)
                    .accessibilityHidden(true)
                Text(copilot.isVoiceActive
                    ? "Stop & transcribe"
                    : (copilot.isAwaitingTranscript ? "Cancel transcript wait" : "Push-to-talk with Realtime"))
                    .fontWeight(.semibold)
                Spacer()
                Text("ephemeral")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint((copilot.isVoiceActive || copilot.isAwaitingTranscript) ? .red : .cyan)
        .disabled(copilot.isWorking)
        .accessibilityHint("Voice produces a proposal only; local validation and confirmation remain separate")
        .accessibilityIdentifier(copilot.isVoiceActive
            ? "design-copilot.voice.stop"
            : (copilot.isAwaitingTranscript
                ? "design-copilot.voice.cancel"
                : "design-copilot.voice.start"))
    }

    private var response: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(copilot.message)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("design-copilot.status")
            if let envelope = copilot.envelope {
                HStack(spacing: 7) {
                    Image(systemName: envelope.status == .ready ? "checkmark.shield.fill" : "questionmark.bubble.fill")
                        .foregroundStyle(envelope.status == .ready ? .green : .orange)
                    Text(envelope.status == .ready ? "Strict proposal validated" : "Clarification requested")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text("r\(envelope.requestContext.baseSceneRevision)")
                        .font(.caption.monospaced())
                }
                if let asset = copilot.proposedAsset {
                    Label(asset.displayName, systemImage: asset.category == "chair" ? "chair.lounge.fill" : "table.furniture.fill")
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("design-copilot.proposed-asset")
                }
                if copilot.canApplyProposal {
                    Button("Create deterministic preview") {
                        Task { await copilot.applyProposal() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityHint("Creates a local revision-neutral preview; confirmation remains separate")
                    .accessibilityIdentifier("design-copilot.apply")
                }
            }
        }
    }

    private var catalogStrip: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Curated local catalog")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("3 digest-bound proxies")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(catalog.assets) { asset in
                        assetCard(asset)
                    }
                }
            }
        }
    }

    private func assetCard(_ asset: RoomEditCatalogAsset) -> some View {
        Button {
            Task { await copilot.selectLocalAsset(asset) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: asset.category == "chair" ? "chair.lounge.fill" : "table.furniture.fill")
                    .font(.title2)
                    .foregroundStyle(assetColor(asset))
                    .accessibilityHidden(true)
                Text(asset.displayName)
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.leading)
                Text(asset.styleTags.prefix(2).joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Use locally")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.cyan)
            }
            .frame(width: 132, alignment: .leading)
            .frame(minHeight: 116, alignment: .leading)
            .padding(11)
            .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Select \(asset.displayName) locally")
        .accessibilityIdentifier("design-copilot.asset.\(asset.assetID)")
    }

    private func assetColor(_ asset: RoomEditCatalogAsset) -> Color {
        if asset.colorTags.contains("cobalt") { return .blue }
        if asset.colorTags.contains("amber") { return .orange }
        return .mint
    }

    private var settings: some View {
        DisclosureGroup("Gateway setup", isExpanded: $settingsExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("http://Mac-LAN-address:8787/", text: $copilot.gatewayURLText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textFieldStyle(.roundedBorder)
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("design-copilot.gateway-url")
                SecureField(
                    copilot.hasSavedGatewayToken ? "Saved token (enter to replace)" : "Gateway bearer token",
                    text: $copilot.pendingGatewayToken
                )
                .textFieldStyle(.roundedBorder)
                .foregroundStyle(.primary)
                .privacySensitive()
                .accessibilityIdentifier("design-copilot.gateway-token")
                Button("Save on this iPhone") {
                    copilot.saveGatewaySettings()
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
                .accessibilityIdentifier("design-copilot.gateway-save")
                Text("The standard OpenAI API key stays on the Mac gateway. The iPhone stores only this gateway token in Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 10)
        }
        .font(.subheadline)
    }
}
