import Combine
import ReRoomContracts
import SwiftUI
import UIKit

@main
@MainActor
struct ReRoomDeviceProofApp: App {
    @State private var model = DeviceProofModel()

    var body: some Scene {
        WindowGroup {
            CandidateSeedView(model: model)
        }
    }
}

struct CandidateSeedView: View {
    @Bindable var model: DeviceProofModel

    var body: some View {
        ZStack {
            Color(red: 11 / 255, green: 15 / 255, blue: 20 / 255)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    candidateHeader
                    statusPanel
                    Spacer(minLength: 48)
                    actionTray
                }
                .frame(maxWidth: .infinity, minHeight: 640, alignment: .topLeading)
                .padding(.horizontal, 16)
                .padding(.vertical, 24)
            }
        }
        .foregroundStyle(Color(red: 245 / 255, green: 247 / 255, blue: 250 / 255))
        .accessibilityIdentifier("release.root.candidate")
        .task {
            await model.prepare()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            model.refreshPhysicalOrientation()
        }
    }

    private var candidateHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ReRoom device check")
                .font(.title.weight(.semibold))
            Text("Candidate — physical verification pending")
                .font(.body)
                .foregroundStyle(Color(red: 183 / 255, green: 192 / 255, blue: 202 / 255))
#if DEBUG
            Text("Internal diagnostic build")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255))
#endif
        }
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(model.statusTitle, systemImage: statusSymbol)
                .font(.title2.weight(.semibold))
            Text(model.statusMessage)
                .font(.body)
                .foregroundStyle(Color(red: 183 / 255, green: 192 / 255, blue: 202 / 255))
                .fixedSize(horizontal: false, vertical: true)
            if model.isPerformingPermissionRequest {
                ProgressView()
                    .tint(Color(red: 77 / 255, green: 163 / 255, blue: 255 / 255))
                    .accessibilityLabel("Waiting for camera permission")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(red: 23 / 255, green: 29 / 255, blue: 36 / 255).opacity(0.94))
        .clipShape(.rect(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(model.statusAccessibilityIdentifier)
    }

    @ViewBuilder
    private var actionTray: some View {
        if let action = model.primaryAction {
            Button(action.label) {
                Task {
                    await model.performPrimaryAction()
                }
            }
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(Color(red: 11 / 255, green: 15 / 255, blue: 20 / 255))
            .background(Color(red: 77 / 255, green: 163 / 255, blue: 255 / 255))
            .clipShape(.rect(cornerRadius: 12))
            .disabled(model.isPerformingPermissionRequest)
            .accessibilityIdentifier(
                action == .openSettings ? "release.action.settings" : "release.permission.camera"
            )
        }
    }

    private var statusSymbol: String {
        switch model.state.cameraAuthorization {
        case .notDetermined:
            "camera.fill"
        case .granted:
            "viewfinder"
        case .denied, .restricted:
            "camera.fill.badge.exclamationmark"
        }
    }
}
