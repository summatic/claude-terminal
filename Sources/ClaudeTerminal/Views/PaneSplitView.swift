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
                HStack(spacing: 2) {
                    layoutView(for: left)
                        .frame(width: geo.size.width * ratio - 1)
                    layoutView(for: right)
                        .frame(width: geo.size.width * (1 - ratio) - 1)
                }
            }

        case .vsplit(let top, let bottom, let ratio):
            GeometryReader { geo in
                VStack(spacing: 2) {
                    layoutView(for: top)
                        .frame(height: geo.size.height * ratio - 1)
                    layoutView(for: bottom)
                        .frame(height: geo.size.height * (1 - ratio) - 1)
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
