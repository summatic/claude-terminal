import SwiftUI

// MARK: - Agent Status Bar (bottom bar)

struct AgentStatusBar: View {

    @ObservedObject var session: Session

    var activeAgents: [AgentInfo] {
        session.allPanes.compactMap { $0.agentInfo }
    }

    var body: some View {
        HStack(spacing: 8) {
            // Agent pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(activeAgents) { info in
                        AgentPill(info: info)
                    }
                }
                .padding(.horizontal, 8)
            }

            Spacer()

            // Pane count
            Text("\(session.allPanes.count) pane\(session.allPanes.count == 1 ? "" : "s")")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
                .padding(.trailing, 8)
        }
        .frame(height: 24)
        .background(Color(white: 0.08))
    }
}

// MARK: - Agent Pill

struct AgentPill: View {

    let info: AgentInfo

    var body: some View {
        HStack(spacing: 4) {
            AgentStatusDot(status: info.status, color: info.color.swiftUIColor)
                .frame(width: 8, height: 8)

            Text(info.roleName)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.75))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(info.color.swiftUIColor.opacity(0.15))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(info.color.swiftUIColor.opacity(0.3), lineWidth: 0.5)
        )
    }
}
