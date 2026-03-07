import SwiftUI

// MARK: - Content View (Root)

struct ContentView: View {

    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            SessionTabBar(appState: appState)

            // Session workspace
            if let session = appState.activeSession {
                SessionWorkspaceView(
                    session: session,
                    ptyProcesses: appState.ptyProcesses,
                    onActivatePane: { paneID in
                        appState.activatePane(id: paneID, in: session)
                    },
                    onClosePane: { paneID in
                        appState.closePane(id: paneID, in: session)
                    },
                    onSplitPane: { paneID, direction in
                        appState.splitActivePane(direction: direction)
                    }
                )
            } else {
                emptyState
            }

            // Status bar
            if let session = appState.activeSession {
                AgentStatusBar(session: session)
            }
        }
        .background(Color(white: 0.07))
        .sheet(isPresented: $appState.showNewRemoteSessionSheet) {
            NewRemoteSessionView(appState: appState)
        }
        // Keyboard shortcuts
        .keyboardShortcut("t", modifiers: .command)  // handled via commands
        .onReceive(NotificationCenter.default.publisher(for: .newSession)) { _ in
            appState.newLocalSession()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.2))
            Text("No active session")
                .font(.system(size: 16, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
            Button("New Session") { appState.newLocalSession() }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.07))
    }
}

// MARK: - Session Workspace View

struct SessionWorkspaceView: View {

    @ObservedObject var session: Session
    let ptyProcesses: [UUID: PTYProcess]
    var onActivatePane: ((UUID) -> Void)?
    var onClosePane: ((UUID) -> Void)?
    var onSplitPane: ((UUID, SplitDirection) -> Void)?

    var body: some View {
        PaneSplitView(
            layout: session.layout,
            session: session,
            ptyProcesses: ptyProcesses,
            onActivatePane: onActivatePane,
            onClosePane: onClosePane,
            onSplitPane: onSplitPane
        )
        .animation(.spring(duration: 0.25), value: session.layout.allPanes.count)
    }
}

// MARK: - New Remote Session Sheet

struct NewRemoteSessionView: View {

    @ObservedObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var host = ""
    @State private var sshPort = "22"
    @State private var wsPort = "9901"

    var body: some View {
        VStack(spacing: 20) {
            Text("Connect to Remote Server")
                .font(.headline)

            Form {
                TextField("Host (e.g. user@server.com)", text: $host)
                TextField("SSH Port", text: $sshPort)
                TextField("WebSocket Port (for hook events)", text: $wsPort)
            }

            Text("Make sure to install the hook script on the remote server.\nSee: ~/.claude/hooks/notify-terminal.sh")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Connect") {
                    let port = Int(sshPort) ?? 22
                    let ws = Int(wsPort) ?? 9901
                    appState.newRemoteSession(host: host, sshPort: port, wsPort: ws)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(host.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let newSession = Notification.Name("ClaudeTerminal.NewSession")
}
