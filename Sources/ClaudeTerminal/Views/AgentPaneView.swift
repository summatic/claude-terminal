import SwiftUI
import SwiftTerm

// MARK: - Agent Pane View

struct AgentPaneView: View {

    @ObservedObject var pane: AgentPane
    let ptyProcess: PTYProcess
    let isActive: Bool
    var onActivate: (() -> Void)?
    var onClose: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            paneHeader
            terminalBody
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(borderColor, lineWidth: isActive ? 1.5 : 0.5)
        )
        .onTapGesture { onActivate?() }
    }

    // MARK: - Header

    private var paneHeader: some View {
        HStack(spacing: 8) {
            // Agent status dot
            AgentStatusDot(status: pane.agentInfo?.status ?? .idle,
                           color: agentDisplayColor)

            // Title
            Text(pane.title)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)

            // Connection type badge
            if pane.connectionType.isRemote {
                Text("SSH")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.orange.opacity(0.2))
                    .clipShape(Capsule())
            }

            Spacer()

            // 메트릭 칩 (Phase 8) — 툴 호출 횟수 + 런타임
            if let info = pane.agentInfo {
                if info.toolCallCount > 0 {
                    Label("\(info.toolCallCount)", systemImage: "wrench.and.screwdriver.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                }
                Text(info.spawnedAt, style: .timer)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundColor(.white.opacity(0.3))
            }

            // Task description (truncated)
            if let task = pane.agentInfo?.taskDescription {
                Text(task)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            // Close button
            Button(action: { onClose?() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
            .opacity(isActive ? 1 : 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(headerBackground)
    }

    // MARK: - Terminal Body

    private var terminalBody: some View {
        TerminalViewRepresentable(ptyProcess: ptyProcess)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(white: 0.07))
    }

    // MARK: - Styling

    private var agentDisplayColor: Color {
        guard let color = pane.agentInfo?.color else { return .white }
        return color.swiftUIColor
    }

    private var headerBackground: some View {
        ZStack {
            Color(white: 0.12)
            // Color accent strip on left for agent identification
            if let agentInfo = pane.agentInfo {
                HStack {
                    Rectangle()
                        .fill(agentInfo.color.swiftUIColor)
                        .frame(width: 3)
                    Spacer()
                }
            }
        }
    }

    private var borderColor: Color {
        if isActive {
            return agentDisplayColor.opacity(0.7)
        }
        return Color.white.opacity(0.1)
    }
}

// MARK: - Agent Status Dot

struct AgentStatusDot: View {

    let status: AgentStatus
    let color: Color

    @State private var animating = false

    var body: some View {
        ZStack {
            switch status {
            case .thinking:
                thinkingDot
            case .writing:
                writingDot
            case .running:
                runningDot
            case .done:
                doneDot
            case .error:
                errorDot
            default:
                idleDot
            }
        }
        .frame(width: 10, height: 10)
        .onAppear { animating = true }
    }

    private var thinkingDot: some View {
        Circle()
            .fill(color)
            .opacity(animating ? 1.0 : 0.3)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: animating)
    }

    private var writingDot: some View {
        Circle()
            .trim(from: 0, to: 0.75)
            .stroke(color, lineWidth: 2)
            .rotationEffect(.degrees(animating ? 360 : 0))
            .animation(.linear(duration: 0.8).repeatForever(autoreverses: false), value: animating)
    }

    private var runningDot: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: 8, height: animating ? 8 : 3)
            .animation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true), value: animating)
    }

    private var doneDot: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 10))
            .foregroundColor(.green)
    }

    private var errorDot: some View {
        Image(systemName: "exclamationmark.circle.fill")
            .font(.system(size: 10))
            .foregroundColor(.red)
    }

    private var idleDot: some View {
        Circle()
            .fill(Color.white.opacity(0.3))
    }
}

// MARK: - AgentColor SwiftUI Extension

extension AgentColor {
    var swiftUIColor: Color {
        switch self {
        case .blue:   return .blue
        case .green:  return .green
        case .yellow: return .yellow
        case .orange: return .orange
        case .red:    return .red
        case .purple: return .purple
        case .cyan:   return .cyan
        case .pink:   return .pink
        }
    }
}
