import SwiftUI

// MARK: - App Entry Point

@main
struct ClaudeTerminalApp: App {

    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState)
                .frame(minWidth: 800, minHeight: 500)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            // Session commands
            CommandGroup(after: .newItem) {
                Button("New Session") {
                    appState.newLocalSession()
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("New Remote Session (SSH)") {
                    appState.showNewRemoteSessionSheet = true
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Button("Close Session") {
                    if let id = appState.activeSessionID {
                        appState.closeSession(id: id)
                    }
                }
                .keyboardShortcut("w", modifiers: .command)
            }

            // Pane commands
            CommandMenu("Pane") {
                Button("Split Horizontally") {
                    appState.splitActivePane(direction: .horizontal)
                }
                .keyboardShortcut("d", modifiers: .command)

                Button("Split Vertically") {
                    appState.splitActivePane(direction: .vertical)
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Button("Close Pane") {
                    guard let session = appState.activeSession,
                          let paneID = session.activePaneID else { return }
                    appState.closePane(id: paneID, in: session)
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])

                Divider()

                // Switch sessions 1-9
                ForEach(0..<9, id: \.self) { index in
                    Button("Switch to Session \(index + 1)") {
                        if index < appState.sessions.count {
                            appState.activeSessionID = appState.sessions[index].id
                        }
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
            }

            // View commands
            CommandMenu("View") {
                Button("Toggle Activity Stream") {
                    appState.handleKeyboardCommand(.toggleActivityStream)
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])

                Button("Toggle File Sidebar") {
                    appState.handleKeyboardCommand(.toggleFileSidebar)
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }
        }
    }
}
