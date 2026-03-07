import SwiftUI

// MARK: - Recursive Layout Renderer

/// Renders a PaneLayout tree into split views.
/// Uses GeometryReader + recursive composition to handle arbitrary depths.
struct PaneSplitView: View {

    let layout: PaneLayout
    let session: Session
    let ptyProcesses: [UUID: PTYProcess]
    var onActivatePane: ((UUID) -> Void)?
    var onClosePane: ((UUID) -> Void)?
    var onSplitPane: ((UUID, SplitDirection) -> Void)?

    var body: some View {
        layoutView(for: layout)
    }

    @ViewBuilder
    private func layoutView(for node: PaneLayout) -> some View {
        switch node {
        case .leaf(let pane):
            leafView(for: pane)

        case .hsplit(let left, let right, let ratio):
            GeometryReader { geo in
                HStack(spacing: 0) {
                    layoutView(for: left)
                        .frame(width: max(0, geo.size.width * ratio - 2))
                    if let anchorID = left.allPanes.first?.id {
                        PaneDivider(
                            axis: .horizontal,
                            anchorPaneID: anchorID,
                            containerSize: geo.size.width,
                            currentRatio: ratio,
                            session: session
                        )
                    }
                    layoutView(for: right)
                        .frame(width: max(0, geo.size.width * (1 - ratio) - 2))
                }
            }

        case .vsplit(let top, let bottom, let ratio):
            GeometryReader { geo in
                VStack(spacing: 0) {
                    layoutView(for: top)
                        .frame(height: max(0, geo.size.height * ratio - 2))
                    if let anchorID = top.allPanes.first?.id {
                        PaneDivider(
                            axis: .vertical,
                            anchorPaneID: anchorID,
                            containerSize: geo.size.height,
                            currentRatio: ratio,
                            session: session
                        )
                    }
                    layoutView(for: bottom)
                        .frame(height: max(0, geo.size.height * (1 - ratio) - 2))
                }
            }
        }
    }

    @ViewBuilder
    private func leafView(for pane: AgentPane) -> some View {
        if let pty = ptyProcesses[pane.id] {
            AgentPaneView(
                pane: pane,
                ptyProcess: pty,
                isActive: session.activePaneID == pane.id,
                onActivate: { onActivatePane?(pane.id) },
                onClose: { onClosePane?(pane.id) }
            )
        } else {
            // PTY not yet created (e.g. sub-agent pane waiting for connection)
            PanePlaceholderView(pane: pane)
                .onTapGesture { onActivatePane?(pane.id) }
        }
    }
}

// MARK: - Draggable Divider (Phase 7)

/// 드래그로 패인 비율을 조절하는 분할선.
/// `session.layout.updatingRatio(_:forSplitContaining:)`를 호출해 레이아웃을 갱신합니다.
private struct PaneDivider: View {

    let axis: Axis
    let anchorPaneID: UUID
    let containerSize: CGFloat
    let currentRatio: CGFloat
    let session: Session

    /// 드래그 시작 시점의 비율. 제스처 중 `currentRatio` 변경에 영향받지 않도록 캡처.
    @State private var startRatio: CGFloat? = nil
    @State private var isHovered = false

    var body: some View {
        Rectangle()
            .fill(isHovered ? Color.white.opacity(0.3) : Color.white.opacity(0.08))
            .frame(
                width: axis == .horizontal ? 4 : nil,
                height: axis == .vertical ? 4 : nil
            )
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    (axis == .horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        // 첫 이벤트에서 시작 비율 캡처 (이후 currentRatio가 변해도 기준점 유지)
                        let base: CGFloat
                        if let s = startRatio {
                            base = s
                        } else {
                            base = currentRatio
                            startRatio = currentRatio
                        }
                        guard containerSize > 0 else { return }
                        let delta = axis == .horizontal
                            ? value.translation.width
                            : value.translation.height
                        let newRatio = (base * containerSize + delta) / containerSize
                        session.layout = session.layout.updatingRatio(
                            min(max(newRatio, 0.1), 0.9),
                            forSplitContaining: anchorPaneID
                        )
                    }
                    .onEnded { _ in startRatio = nil }
            )
    }
}

// MARK: - Placeholder (for sub-agent panes before PTY is ready)

struct PanePlaceholderView: View {

    @ObservedObject var pane: AgentPane

    var body: some View {
        ZStack {
            Color(white: 0.07)

            VStack(spacing: 12) {
                if let info = pane.agentInfo {
                    Circle()
                        .fill(info.color.swiftUIColor.opacity(0.3))
                        .frame(width: 40, height: 40)
                        .overlay(
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(info.color.swiftUIColor)
                        )

                    Text(info.roleName)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))

                    if let task = info.taskDescription {
                        Text(task)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .padding(.horizontal, 20)
                    }
                } else {
                    Text("Connecting...")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
        }
    }
}
