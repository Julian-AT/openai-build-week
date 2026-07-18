import Observation
import SwiftUI

enum RoomEditLaunchConfiguration {
    static let uiTestArgument = "--room-edit-ui-test"
    static let resetArgument = "--room-edit-reset"

    static func usesRoomEditSurface(arguments: [String]) -> Bool {
        arguments.contains(uiTestArgument)
    }
}

@MainActor
@Observable
final class RoomEditAppOwner {
    let model: RoomEditModel?
    let setupMessage: String?

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        do {
            model = try RoomEditFactory.live(
                resetStore: arguments.contains(RoomEditLaunchConfiguration.resetArgument),
                useFixtureSupport: arguments.contains(RoomEditLaunchConfiguration.uiTestArgument)
            )
            setupMessage = nil
        } catch {
            model = nil
            setupMessage = "The local room-edit store could not be opened."
        }
    }
}

struct RoomEditContainer: View {
    let owner: RoomEditAppOwner

    var body: some View {
        Group {
            if let model = owner.model {
                RoomEditView(model: model)
            } else {
                ContentUnavailableView(
                    "Local room state unavailable",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(owner.setupMessage ?? "Unknown local setup error")
                )
                .padding()
                .accessibilityIdentifier("roomedit.setup.failure")
            }
        }
        .accessibilityIdentifier("release.root.candidate")
    }
}

struct RoomEditView: View {
    @Bindable var model: RoomEditModel

    var body: some View {
        ZStack {
            Color(red: 10 / 255, green: 14 / 255, blue: 19 / 255)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    RoomEditHeader()
                    RoomEditRevisionPanel(snapshot: model.snapshot)
                    RoomEditOperationGrid(
                        snapshot: model.snapshot,
                        select: selectOperation
                    )
                    RoomEditStatePanel(snapshot: model.snapshot)
                    RoomEditActionTray(snapshot: model.snapshot, model: model)
                }
                .frame(maxWidth: 640, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 24)
            }
        }
        .foregroundStyle(.white)
        .accessibilityIdentifier("roomedit.root")
        .task {
            await model.prepare()
        }
    }

    private func selectOperation(_ operation: RoomEditOperation) {
        Task {
            if operation == .restore, model.snapshot.canRestore {
                await model.restoreFromButton()
            } else {
                await model.selectOperation(operation)
            }
        }
    }
}

private struct RoomEditHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ReRoom device check")
                .font(.title.weight(.semibold))
            Text("Phase 3 local place + restore")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Deterministic demo proxy — physical and deferred gate verification remain pending.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct RoomEditRevisionPanel: View {
    let snapshot: RoomEditSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Label("Current revision r\(snapshot.revision)", systemImage: "point.3.connected.trianglepath.dotted")
                .accessibilityIdentifier("roomedit.revision.current")
            Spacer(minLength: 8)
            Text(snapshot.localState.rawValue)
                .foregroundStyle(snapshot.localState == .durable ? .green : .secondary)
                .accessibilityIdentifier(
                    snapshot.localState == .durable
                        ? "roomedit.local.durable"
                        : "roomedit.local.ready"
                )
        }
        .font(.subheadline.weight(.semibold))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.white.opacity(0.08))
        .clipShape(.rect(cornerRadius: 14))
        .accessibilityElement(children: .contain)
    }
}

private struct RoomEditOperationGrid: View {
    let snapshot: RoomEditSnapshot
    let select: (RoomEditOperation) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 128), spacing: 10),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Operations")
                .font(.headline)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(snapshot.operations) { operation in
                    Button {
                        select(operation)
                    } label: {
                        Label(operation.title, systemImage: symbol(for: operation))
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(snapshot.selectedOperation == operation ? .blue : .gray.opacity(0.55))
                    .accessibilityIdentifier("roomedit.operation.\(operation.rawValue)")
                    .accessibilityAddTraits(snapshot.selectedOperation == operation ? .isSelected : [])
                }
            }
        }
    }

    private func symbol(for operation: RoomEditOperation) -> String {
        switch operation {
        case .place: "plus.square.on.square"
        case .replace: "arrow.triangle.2.circlepath"
        case .remove: "eye.slash"
        case .restore: "arrow.uturn.backward.circle"
        }
    }
}

private struct RoomEditStatePanel: View {
    let snapshot: RoomEditSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(snapshot.status)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)

            if let preview = snapshot.preview {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Provisional Phase 3 proxy", systemImage: "cube.transparent")
                        .font(.title3.weight(.semibold))
                    Text(preview.proxyID)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text("Preview base r\(preview.baseRevision)")
                        .accessibilityIdentifier("roomedit.preview.base")
                    Text(preview.supportStatus)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.16))
                .clipShape(.rect(cornerRadius: 14))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("roomedit.preview.proxy")
            }

            if snapshot.placedAssetVisible {
                Label("Committed proxy is active in local scene state", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("roomedit.asset.committed")
            } else if snapshot.selectedOperation == .restore, snapshot.revision >= 2 {
                Label("Restore committed as revision r\(snapshot.revision)", systemImage: "arrow.uturn.backward.circle.fill")
                    .foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("roomedit.restore.committed")
            }

            blockerView
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.white.opacity(0.08))
        .clipShape(.rect(cornerRadius: 16))
    }

    @ViewBuilder
    private var blockerView: some View {
        switch snapshot.blocker {
        case .healthySupportRequired:
            blocker(
                "Place needs normal ARKit tracking and a visible horizontal floor.",
                identifier: "roomedit.blocker.support"
            )
        case .replaceDeferred:
            blocker(
                "Replace is visible but blocked until target authorization and reveal artifacts are implemented.",
                identifier: "roomedit.blocker.replace"
            )
        case .removeDeferred:
            blocker(
                "Remove is visible but blocked until target authorization and reveal artifacts are implemented.",
                identifier: "roomedit.blocker.remove"
            )
        case .restoreSourceRequired:
            blocker("Restore needs a committed local place transaction.", identifier: "roomedit.blocker.restore")
        case .transactionRejected(let detail):
            blocker("Transaction rejected safely: \(detail)", identifier: "roomedit.blocker.transaction")
        case nil:
            EmptyView()
        }
    }

    private func blocker(_ message: String, identifier: String) -> some View {
        Label(message, systemImage: "lock.fill")
            .font(.subheadline)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(identifier)
    }
}

private struct RoomEditActionTray: View {
    let snapshot: RoomEditSnapshot
    let model: RoomEditModel

    var body: some View {
        if snapshot.preview != nil {
            HStack(spacing: 12) {
                Button("Cancel") {
                    Task { await model.cancelPreview() }
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("roomedit.action.cancel")

                Button("Confirm placement") {
                    Task { await model.confirmPlacementFromButton() }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, minHeight: 44)
                .disabled(!snapshot.canConfirm)
                .accessibilityIdentifier("roomedit.action.confirm")
            }
        }
    }
}
