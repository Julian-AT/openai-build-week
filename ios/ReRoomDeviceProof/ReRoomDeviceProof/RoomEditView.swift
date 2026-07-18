import Observation
import ReRoomContracts
import ReRoomTransactionCore
import RealityKit
import SwiftUI
import UIKit

enum RoomEditLaunchConfiguration {
    static let uiTestArgument = "--room-edit-ui-test"
    static let resetArgument = "--room-edit-reset"
    static let healthyTargetArgument = "--room-edit-target-healthy"
    static let missedTargetArgument = "--room-edit-target-miss"
    static let ambiguousTargetArgument = "--room-edit-target-ambiguous"
    static let trackingLossArgument = "--room-edit-target-tracking-loss"
    static let proxyLoadFailureArgument = "--room-edit-proxy-load-fail"

    static func usesRoomEditSurface(arguments: [String]) -> Bool {
        arguments.contains(uiTestArgument)
    }

    static func targetFixtureScenario(arguments: [String]) -> RoomEditTargetFixtureScenario {
        if arguments.contains(missedTargetArgument) { return .miss }
        if arguments.contains(ambiguousTargetArgument) { return .ambiguous }
        if arguments.contains(trackingLossArgument) { return .trackingLossAfterSeed }
        return .healthy
    }
}

@MainActor
@Observable
final class RoomEditAppOwner {
    let runtime: RoomEditRuntime?
    let setupMessage: String?
    let replacementLoadForcedFailure: Bool

    var model: RoomEditModel? { runtime?.model }

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        replacementLoadForcedFailure = arguments.contains(
            RoomEditLaunchConfiguration.proxyLoadFailureArgument
        )
        do {
            runtime = try RoomEditFactory.runtime(
                resetStore: arguments.contains(RoomEditLaunchConfiguration.resetArgument),
                useFixtureSupport: arguments.contains(RoomEditLaunchConfiguration.uiTestArgument),
                fixtureScenario: RoomEditLaunchConfiguration.targetFixtureScenario(arguments: arguments)
            )
            setupMessage = nil
        } catch {
            runtime = nil
            setupMessage = "The local room-edit store could not be opened."
        }
    }
}

struct RoomEditContainer: View {
    let owner: RoomEditAppOwner

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let runtime = owner.runtime {
                RoomEditView(
                    runtime: runtime,
                    replacementLoadForcedFailure: owner.replacementLoadForcedFailure
                )
            } else {
                ContentUnavailableView(
                    "Local room state unavailable",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(owner.setupMessage ?? "Unknown local setup error")
                )
                .padding()
                .accessibilityIdentifier("roomedit.setup.failure")
            }

            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityLabel("ReRoom device check")
                .accessibilityIdentifier("release.root.candidate")
                .allowsHitTesting(false)
        }
    }
}

struct RoomEditView: View {
    @Bindable var model: RoomEditModel
    let runtime: RoomEditRuntime
    let replacementLoadForcedFailure: Bool
    @State private var lastTapPoint = CGPoint(x: 160, y: 180)

    init(runtime: RoomEditRuntime, replacementLoadForcedFailure: Bool = false) {
        self.model = runtime.model
        self.runtime = runtime
        self.replacementLoadForcedFailure = replacementLoadForcedFailure
    }

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
                    RoomEditReplacementQualificationPanel(snapshot: model.snapshot)
                    RoomEditActionTray(snapshot: model.snapshot, model: model)
                    RoomEditCameraStage(
                        liveView: runtime.sharedSession?.view,
                        fixtureScenario: runtime.fixtureScenario,
                        snapshot: model.snapshot.render,
                        replacementLoadForcedFailure: replacementLoadForcedFailure,
                        replacementAssetStateChanged: updateReplacementAssetState,
                        tap: groundTarget
                    )
                    RoomEditTargetPanel(
                        snapshot: model.snapshot,
                        reseed: reseedTarget
                    )
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

    private func groundTarget(_ point: CGPoint) {
        lastTapPoint = point
        Task { await model.groundTarget(at: point) }
    }

    private func reseedTarget() {
        Task { await model.reseedTarget(at: lastTapPoint) }
    }

    private func updateReplacementAssetState(_ state: RoomEditReplacementAssetState) {
        Task { await model.updateReplacementAssetState(state) }
    }
}

private struct RoomEditHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ReRoom device check")
                .font(.title.weight(.semibold))
            Text("Manual target + local compositor")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Deterministic demo proxy — formal physical, provider, and compositor gates remain pending.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct RoomEditCameraStage: View {
    let liveView: ARView?
    let fixtureScenario: RoomEditTargetFixtureScenario?
    let snapshot: RoomEditRenderSnapshot
    let replacementLoadForcedFailure: Bool
    let replacementAssetStateChanged: (RoomEditReplacementAssetState) -> Void
    let tap: (CGPoint) -> Void

    var body: some View {
        ZStack {
            RoomEditRenderSurface(
                liveView: liveView,
                fixtureScenario: fixtureScenario,
                snapshot: snapshot,
                replacementLoadForcedFailure: replacementLoadForcedFailure,
                replacementAssetStateChanged: replacementAssetStateChanged,
                tap: tap
            )

            Image(systemName: "plus")
                .font(.title2.weight(.light))
                .foregroundStyle(.white)
                .padding(12)
                .background(.black.opacity(0.35), in: Circle())
                .accessibilityHidden(true)

            VStack {
                Spacer()
                Text(fixtureScenario == nil
                    ? "Aim at visible floor beside one chair or small table, then tap."
                    : "Simulator fixture — no AR tracking or camera evidence.")
                    .font(.callout.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.68), in: Capsule())
                    .padding(12)
            }
            .allowsHitTesting(false)

            if fixtureScenario != nil {
                Button {
                    tap(CGPoint(x: 160, y: 140))
                } label: {
                    Color.clear
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Manual target camera surface")
                .accessibilityHint("Tap to ground one chair or small table")
                .accessibilityIdentifier("roomedit.target.surface")
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 280)
        .compositingGroup()
        .clipShape(.rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.white.opacity(0.22), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }
}

private struct RoomEditTargetPanel: View {
    let snapshot: RoomEditSnapshot
    let reseed: () -> Void

    private var readinessRows: [RoomEditReadinessRow] {
        let readiness = snapshot.target.readiness
        let reasons = snapshot.target.reasons
        return [
            RoomEditReadinessRow(id: .select, value: readiness.select, reasons: reasons.select),
            RoomEditReadinessRow(id: .place, value: readiness.place, reasons: reasons.place),
            RoomEditReadinessRow(id: .replace, value: readiness.replace, reasons: reasons.replace),
            RoomEditReadinessRow(id: .remove, value: readiness.remove, reasons: reasons.remove),
            RoomEditReadinessRow(id: .restore, value: readiness.restore, reasons: reasons.restore),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Target readiness")
                    .font(.headline)
                Spacer(minLength: 12)
                Button("Reseed target", action: reseed)
                    .buttonStyle(.bordered)
                    .disabled(snapshot.target.target == nil)
                    .accessibilityHint("Uses the last explicit tap in the current world epoch")
                    .accessibilityIdentifier("roomedit.target.reseed")
            }

            targetIdentity
            targetFailure

            VStack(alignment: .leading, spacing: 8) {
                ForEach(readinessRows) { row in
                    Text(row.label)
                        .font(.subheadline.monospaced())
                        .foregroundStyle(row.value == .ready ? .green : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("roomedit.readiness.\(row.id.rawValue)")
                }
            }
            .accessibilityElement(children: .contain)

            RoomEditFallbackPanel()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.black.opacity(0.62))
        .clipShape(.rect(cornerRadius: 16))
    }

    @ViewBuilder
    private var targetIdentity: some View {
        if let target = snapshot.target.target {
            VStack(alignment: .leading, spacing: 5) {
                Text(target.objectID)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .accessibilityLabel("Target ID \(target.objectID)")
                    .accessibilityIdentifier("roomedit.target.id")
                Text("World epoch \(snapshot.target.worldFrameVersion)")
                    .accessibilityIdentifier("roomedit.target.epoch")
                Text("Frozen proxy v\(target.frozenProxy.version)")
                    .accessibilityIdentifier("roomedit.target.proxy.version")
                Text("Tracking: \(snapshot.target.tracking.rawValue)")
                    .foregroundStyle(snapshot.target.tracking.isHealthy ? .green : .orange)
                    .accessibilityIdentifier(
                        snapshot.target.tracking.isHealthy
                            ? "roomedit.target.tracking.normal"
                            : "roomedit.target.tracking.unavailable"
                    )
            }
            .accessibilityElement(children: .contain)
        } else {
            Text("No manual target selected")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("roomedit.target.empty")
        }
    }

    @ViewBuilder
    private var targetFailure: some View {
        switch snapshot.target.failure {
        case .targetMissed:
            Label("No target found. Keep visible floor in view and tap again.", systemImage: "scope")
                .accessibilityIdentifier("roomedit.target.failure.miss")
        case .targetAmbiguous:
            Label("More than one target candidate. Isolate one chair or table and retry.", systemImage: "square.stack.3d.up")
                .accessibilityIdentifier("roomedit.target.failure.ambiguous")
        case .trackingNotNormal, .worldFrameMismatch:
            Label("Tracking changed. Recover tracking, then reseed explicitly.", systemImage: "exclamationmark.triangle")
                .accessibilityIdentifier("roomedit.target.failure.tracking")
        case .staleSceneRevision, .unsupportedTargetCategory, .invalidSpatialEvidence:
            Label(snapshot.status, systemImage: "exclamationmark.triangle")
                .accessibilityIdentifier("roomedit.target.failure.other")
        case nil:
            EmptyView()
        }
    }
}

private enum RoomEditReadinessID: String, Identifiable {
    case select
    case place
    case replace
    case remove
    case restore

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

private struct RoomEditReadinessRow: Identifiable {
    let id: RoomEditReadinessID
    let value: TargetReadinessValue
    let reasons: [TargetReadinessReasonCode]

    var label: String {
        let suffix = reasons.isEmpty ? "" : " — \(reasons.map(\.rawValue).joined(separator: ", "))"
        return "\(id.title): \(value.rawValue)\(suffix)"
    }
}

private struct RoomEditFallbackPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Manual tap/reseed fallback", systemImage: "hand.tap")
                .accessibilityIdentifier("roomedit.fallback.manual")
            Label("No-dense ARKit plane/proxy fallback", systemImage: "cube.transparent")
                .accessibilityIdentifier("roomedit.fallback.no-dense")
            Label("Local renderer — no cloud/provider wait", systemImage: "iphone")
                .accessibilityIdentifier("roomedit.fallback.local")
            Label("Reveal unavailable: artifact missing", systemImage: "eye.slash")
                .accessibilityIdentifier("roomedit.compositor.reveal.unavailable")
            Label("Occluder unavailable: artifact missing", systemImage: "square.slash")
                .accessibilityIdentifier("roomedit.compositor.occluder.unavailable")
            Text("GATE-003/004/005/007/012 formal campaigns: PENDING")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
                .accessibilityIdentifier("roomedit.gates.pending")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .contain)
    }
}

private struct RoomEditReplacementQualificationPanel: View {
    let snapshot: RoomEditSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            switch snapshot.replacementAssetState {
            case .loading:
                Label("Loading exact local demo proxy", systemImage: "hourglass")
                    .accessibilityIdentifier("roomedit.asset.proxy.loading")
            case .available:
                Label("Six-cube local demo proxy loaded", systemImage: "cube.fill")
                    .foregroundStyle(.green)
                    .accessibilityIdentifier("roomedit.asset.proxy.loaded")
            case .unavailable:
                Label("Exact local demo proxy failed to load", systemImage: "cube.transparent.fill")
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("roomedit.asset.proxy.failed")
            }
            Text("Replace: deterministic supported view only")
                .accessibilityIdentifier("roomedit.replace.supported-view")
            Text("GATE-003/005/009/011 + OPS-GOLDEN-001: PENDING")
                .foregroundStyle(.orange)
                .accessibilityIdentifier("roomedit.replace.gate.pending")
        }
        .font(.caption.weight(.semibold))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.white.opacity(0.08))
        .clipShape(.rect(cornerRadius: 14))
        .accessibilityElement(children: .contain)
    }
}

private struct RoomEditRenderSurface: UIViewRepresentable {
    let liveView: ARView?
    let fixtureScenario: RoomEditTargetFixtureScenario?
    let snapshot: RoomEditRenderSnapshot
    let replacementLoadForcedFailure: Bool
    let replacementAssetStateChanged: (RoomEditReplacementAssetState) -> Void
    let tap: (CGPoint) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            tap: tap,
            forceReplacementLoadFailure: replacementLoadForcedFailure,
            replacementAssetStateChanged: replacementAssetStateChanged
        )
    }

    func makeUIView(context: Context) -> UIView {
        let view: UIView = liveView ?? RoomEditFixtureRenderView()
        view.isAccessibilityElement = !(view is RoomEditFixtureRenderView)
        view.accessibilityLabel = "Manual target camera surface"
        view.accessibilityHint = "Tap to ground one chair or small table"
        view.accessibilityIdentifier = fixtureScenario == nil
            ? "roomedit.target.surface"
            : "roomedit.target.fixture.render"
        let recognizer = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        view.addGestureRecognizer(recognizer)
        context.coordinator.publishReplacementAssetStateOnce()
        context.coordinator.apply(snapshot, to: view, fixtureScenario: fixtureScenario)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.tap = tap
        context.coordinator.apply(snapshot, to: view, fixtureScenario: fixtureScenario)
    }

    @MainActor
    final class Coordinator: NSObject {
        var tap: (CGPoint) -> Void
        private var lastSnapshot: RoomEditRenderSnapshot?
        private var targetAnchor: AnchorEntity?
        private var replacementAnchor: AnchorEntity?
        private let replacementTemplate: Entity?
        private let replacementAssetState: RoomEditReplacementAssetState
        private let replacementAssetStateChanged: (RoomEditReplacementAssetState) -> Void
        private var didPublishReplacementAssetState = false

        init(
            tap: @escaping (CGPoint) -> Void,
            forceReplacementLoadFailure: Bool,
            replacementAssetStateChanged: @escaping (RoomEditReplacementAssetState) -> Void
        ) {
            self.tap = tap
            self.replacementAssetStateChanged = replacementAssetStateChanged
            if forceReplacementLoadFailure {
                replacementTemplate = nil
                replacementAssetState = .unavailable(.realityKitLoadFailed)
            } else {
                do {
                    let loaded = try Entity.load(named: "proxy-chair.usda", in: .main)
                    guard Self.modelEntityCount(in: loaded) == 6 else {
                        replacementTemplate = nil
                        replacementAssetState = .unavailable(.realityKitLoadFailed)
                        return
                    }
                    replacementTemplate = loaded
                    replacementAssetState = .available
                } catch {
                    replacementTemplate = nil
                    replacementAssetState = .unavailable(.realityKitLoadFailed)
                }
            }
        }

        func publishReplacementAssetStateOnce() {
            guard !didPublishReplacementAssetState else { return }
            didPublishReplacementAssetState = true
            replacementAssetStateChanged(replacementAssetState)
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let view = recognizer.view else { return }
            tap(recognizer.location(in: view))
        }

        func apply(
            _ snapshot: RoomEditRenderSnapshot,
            to view: UIView,
            fixtureScenario: RoomEditTargetFixtureScenario?
        ) {
            guard snapshot != lastSnapshot else { return }
            lastSnapshot = snapshot

            if let fixtureView = view as? RoomEditFixtureRenderView {
                fixtureView.apply(snapshot, scenario: fixtureScenario)
                return
            }
            guard let arView = view as? ARView else { return }
            targetAnchor?.removeFromParent()
            replacementAnchor?.removeFromParent()
            targetAnchor = nil
            replacementAnchor = nil

            if let target = snapshot.targetProxy {
                let anchor = AnchorEntity(world: Self.matrix(target.worldFromProxy))
                let mesh = MeshResource.generateBox(width: 0.72, height: 0.82, depth: 0.72)
                let material = SimpleMaterial(
                    color: UIColor.systemTeal.withAlphaComponent(0.28),
                    roughness: 0.8,
                    isMetallic: false
                )
                let coverage = ModelEntity(mesh: mesh, materials: [material])
                coverage.position.y = 0.41
                anchor.addChild(coverage)
                arView.scene.addAnchor(anchor)
                targetAnchor = anchor
            }

            if let replacement = snapshot.replacementProxy,
               let replacementTemplate {
                let anchor = AnchorEntity(world: Self.matrix(replacement.worldFromProxy))
                anchor.addChild(replacementTemplate.clone(recursive: true))
                arView.scene.addAnchor(anchor)
                replacementAnchor = anchor
            }
        }

        private static func modelEntityCount(in entity: Entity) -> Int {
            let ownCount = entity is ModelEntity ? 1 : 0
            return ownCount + entity.children.reduce(0) { partial, child in
                partial + modelEntityCount(in: child)
            }
        }

        private static func matrix(_ value: Matrix4) -> simd_float4x4 {
            let v = value.values.map(Float.init)
            guard v.count == 16 else { return matrix_identity_float4x4 }
            return simd_float4x4(
                SIMD4(v[0], v[4], v[8], v[12]),
                SIMD4(v[1], v[5], v[9], v[13]),
                SIMD4(v[2], v[6], v[10], v[14]),
                SIMD4(v[3], v[7], v[11], v[15])
            )
        }
    }
}

@MainActor
private final class RoomEditFixtureRenderView: UIView {
    private let statusLabel = UILabel()
    private let targetCoverageView = UIView()
    private let replacementView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.07, green: 0.1, blue: 0.14, alpha: 1)
        targetCoverageView.backgroundColor = UIColor.systemTeal.withAlphaComponent(0.28)
        targetCoverageView.layer.cornerRadius = 12
        targetCoverageView.isAccessibilityElement = true
        targetCoverageView.accessibilityLabel = "Frozen target coverage"
        targetCoverageView.accessibilityIdentifier = "roomedit.render.target.coverage"
        replacementView.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.72)
        replacementView.layer.cornerRadius = 10
        replacementView.isAccessibilityElement = true
        replacementView.accessibilityLabel = "Exact bundled replacement"
        replacementView.accessibilityIdentifier = "roomedit.render.replacement"
        statusLabel.textColor = .white
        statusLabel.font = .preferredFont(forTextStyle: .caption1)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        addSubview(targetCoverageView)
        addSubview(replacementView)
        addSubview(statusLabel)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        targetCoverageView.frame = CGRect(
            x: bounds.midX - 52,
            y: bounds.midY - 54,
            width: 104,
            height: 108
        )
        replacementView.frame = CGRect(
            x: bounds.midX - 34,
            y: bounds.midY - 46,
            width: 68,
            height: 92
        )
        statusLabel.frame = CGRect(x: 16, y: 14, width: bounds.width - 32, height: 42)
    }

    func apply(_ snapshot: RoomEditRenderSnapshot, scenario: RoomEditTargetFixtureScenario?) {
        targetCoverageView.isHidden = snapshot.targetProxy == nil
        replacementView.isHidden = snapshot.replacementProxy == nil
        statusLabel.text = "Deterministic \((scenario ?? .healthy).rawValue) fixture"
    }
}

private struct RoomEditRevisionPanel: View {
    let snapshot: RoomEditSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .accessibilityHidden(true)
            Text("Current revision r\(snapshot.revision)")
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
                    Label(
                        snapshot.selectedOperation == .replace
                            ? "Replacement local demo preview"
                            : "Provisional Phase 3 proxy",
                        systemImage: "cube.transparent"
                    )
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
                .accessibilityIdentifier(
                    snapshot.selectedOperation == .replace
                        ? "roomedit.preview.replacement"
                        : "roomedit.preview.proxy"
                )
            }

            if snapshot.replacementAssetVisible {
                Label("Exact bundled replacement is committed locally", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("roomedit.asset.replacement.committed")
            } else if snapshot.placedAssetVisible {
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
        case .replacementAssetUnavailable:
            blocker(
                "The exact local demo proxy is unavailable; the original display is retained.",
                identifier: "roomedit.blocker.replace.asset"
            )
        case .replacementViewUnsupported:
            blocker(
                "Replace is available only in the deterministic supported view.",
                identifier: "roomedit.blocker.replace.view"
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
        VStack(spacing: 10) {
            if snapshot.preview != nil {
            HStack(spacing: 12) {
                Button("Cancel") {
                    Task { await model.cancelPreview() }
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("roomedit.action.cancel")

                Button(snapshot.selectedOperation == .replace ? "Confirm replacement" : "Confirm placement") {
                    Task {
                        if snapshot.selectedOperation == .replace {
                            await model.confirmReplacementFromButton()
                        } else {
                            await model.confirmPlacementFromButton()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, minHeight: 44)
                .disabled(!snapshot.canConfirm)
                .accessibilityIdentifier(
                    snapshot.selectedOperation == .replace
                        ? "roomedit.action.confirm.replace"
                        : "roomedit.action.confirm"
                )
            }
            }

            if snapshot.canRetryReplacement {
                Button("Retry identical replacement") {
                    Task { await model.retryReplacementFromButton() }
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityHint("Reuses the same idempotency key and cannot create another revision")
                .accessibilityIdentifier("roomedit.action.retry.replace")
            }
        }
    }
}
