import SwiftUI

// MARK: - Session Tab Bar

struct SessionTabBar: View {

    @ObservedObject var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            // Session tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(appState.sessions) { session in
                        SessionTab(
                            session: session,
                            isActive: appState.activeSessionID == session.id,
                            onSelect: { appState.activeSessionID = session.id },
                            onClose: { appState.closeSession(id: session.id) }
                        )
                    }
                }
                .padding(.horizontal, 8)
            }

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 4)

            // New session buttons
            HStack(spacing: 4) {
                // New local session
                Button(action: { appState.newLocalSession() }) {
                    Label("Local", systemImage: "plus")
                        .font(.system(size: 11))
                }
                .buttonStyle(TabBarButtonStyle())
                .help("New Local Session (⌘T)")

                // New remote session
                Button(action: { appState.showNewRemoteSessionSheet = true }) {
                    Label("SSH", systemImage: "network")
                        .font(.system(size: 11))
                }
                .buttonStyle(TabBarButtonStyle())
                .help("Connect to Remote SSH Server")
            }
            .padding(.trailing, 8)
        }
        .frame(height: 34)
        .background(Color(white: 0.1))
    }
}

// MARK: - Session Tab

struct SessionTab: View {

    @ObservedObject var session: Session
    let isActive: Bool
    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            // Connection indicator
            Circle()
                .fill(session.connectionType.isRemote ? Color.orange : Color.green)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 1) {
                Text(session.name)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    .foregroundColor(isActive ? .white : .white.opacity(0.6))
                    .lineLimit(1)
                // Git 브랜치 표시 (Phase 12)
                if let branch = session.gitBranch {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 8))
                        Text(branch)
                            .font(.system(size: 9))
                    }
                    .foregroundColor(.white.opacity(0.35))
                }
            }

            // Active agent count badge
            let agentCount = session.allPanes.filter { $0.agentInfo != nil }.count
            if agentCount > 0 {
                Text("\(agentCount)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.blue.opacity(0.6))
                    .clipShape(Capsule())
            }

            // Close button
            if isHovered || isActive {
                Button(action: { onClose?() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isActive ? Color(white: 0.18) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .onHover { isHovered = $0 }
        .onTapGesture { onSelect?() }
    }
}

// MARK: - Tab Bar Button Style

struct TabBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white.opacity(configuration.isPressed ? 0.5 : 0.7))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(white: 0.18).opacity(configuration.isPressed ? 1 : 0))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
