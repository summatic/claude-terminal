import SwiftUI

// MARK: - App State (single source of truth)

@MainActor
final class AppState: ObservableObject {

    // MARK: - Sessions

    @Published var sessions: [Session] = []
    @Published var activeSessionID: UUID?
    @Published var showNewRemoteSessionSheet = false

    var activeSession: Session? {
        guard let id = activeSessionID else { return nil }
        return sessions.first { $0.id == id }
    }

    // MARK: - PTY Processes
    // Keyed by AgentPane.id

    @Published var ptyProcesses: [UUID: PTYProcess] = [:]

    // MARK: - IPC Servers

    private let ipcServer = IPCServer()
    private let wsServer = WebSocketEventServer()

    // MARK: - Init

    init() {
        setupIPC()
        newLocalSession()
    }

    // MARK: - Session Management

    func newLocalSession() {
        let session = Session(name: "Session \(sessions.count + 1)", connectionType: .local)
        sessions.append(session)
        activeSessionID = session.id
        launchPTY(for: session.layout.allPanes.first!, in: session)
    }

    func newRemoteSession(host: String, sshPort: Int = 22, wsPort: Int = 9901) {
        let conn = ConnectionType.remote(host: host, sshPort: sshPort, wsPort: wsPort)
        let session = Session(name: host, connectionType: conn)
        sessions.append(session)
        activeSessionID = session.id
        launchRemotePTY(for: session.layout.allPanes.first!, host: host, sshPort: sshPort)
    }

    func closeSession(id: UUID) {
        guard sessions.count > 1 else { return }
        if let session = sessions.first(where: { $0.id == id }) {
            // Terminate all PTYs in this session
            session.allPanes.forEach { terminatePTY(for: $0.id) }
        }
        sessions.removeAll { $0.id == id }
        if activeSessionID == id {
            activeSessionID = sessions.last?.id
        }
    }

    // MARK: - Pane Management

    func splitActivePane(direction: SplitDirection) {
        guard let session = activeSession else { return }
        guard let paneID = session.activePaneID else { return }

        let newPane = AgentPane(title: "Terminal")
        session.layout = session.layout.splitting(paneID: paneID, with: newPane, direction: direction)
        session.activePaneID = newPane.id

        launchPTY(for: newPane, in: session)
    }

    func closePane(id: UUID, in session: Session) {
        guard session.allPanes.count > 1 else { return }
        terminatePTY(for: id)
        session.closePane(id: id)
    }

    func activatePane(id: UUID, in session: Session) {
        session.activePaneID = id
    }

    // MARK: - PTY Lifecycle

    private func launchPTY(for pane: AgentPane, in session: Session) {
        let pty = PTYProcess()
        pty.onTermination = { [weak self, weak pane] _ in
            Task { @MainActor in
                pane?.isAlive = false
            }
        }

        do {
            try pty.launch(
                executable: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh",
                arguments: ["-l"],
                workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path
            )
            ptyProcesses[pane.id] = pty
        } catch {
            print("[AppState] PTY launch failed: \(error)")
        }
    }

    private func launchRemotePTY(for pane: AgentPane, host: String, sshPort: Int) {
        // Launch ssh process wrapped in PTY
        let pty = PTYProcess()
        pty.onTermination = { [weak pane] _ in
            Task { @MainActor in
                pane?.isAlive = false
            }
        }

        do {
            try pty.launch(
                executable: "/usr/bin/ssh",
                arguments: ["-p", "\(sshPort)", host],
                workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path
            )
            ptyProcesses[pane.id] = pty
        } catch {
            print("[AppState] Remote PTY launch failed: \(error)")
        }
    }

    private func terminatePTY(for paneID: UUID) {
        ptyProcesses[paneID]?.terminate()
        ptyProcesses.removeValue(forKey: paneID)
    }

    // MARK: - IPC Setup

    private func setupIPC() {
        ipcServer.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.handleHookEvent(event)
            }
        }

        wsServer.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.handleHookEvent(event)
            }
        }

        do {
            try ipcServer.start()
            try wsServer.start()
        } catch {
            print("[AppState] IPC server start failed: \(error)")
        }
    }

    // MARK: - Hook Event Handling

    func handleHookEvent(_ event: HookEvent) {
        // Find the target session (by sessionID or use active)
        let targetSession: Session
        if let sid = event.sessionID,
           let found = sessions.first(where: { $0.id.uuidString == sid }) {
            targetSession = found
        } else if let active = activeSession {
            targetSession = active
        } else {
            return
        }

        switch event.type {
        case .preToolUse where event.toolName == "Task":
            handleSubAgentSpawn(event: event, in: targetSession)

        case .postToolUse where event.toolName == "Task":
            if let agentID = event.toolInput?["agent_id"] {
                targetSession.updateAgentStatus(agentID: agentID, status: .done)
            }

        case .agentStatus:
            if let status = event.status {
                targetSession.updateAgentStatus(agentID: event.agentID, status: status)
            }

        case .fileTouched:
            if let path = event.filePath {
                targetSession.recordFileTouched(agentID: event.agentID, filePath: path)
            }

        default:
            break
        }
    }

    private func handleSubAgentSpawn(event: HookEvent, in session: Session) {
        // Determine split direction based on depth
        let parentPane: AgentPane?
        if let parentID = event.parentAgentID {
            parentPane = session.allPanes.first { $0.agentInfo?.agentID == parentID }
        } else {
            parentPane = session.allPanes.first { $0.agentInfo == nil } ?? session.allPanes.first
        }

        guard let parent = parentPane else { return }

        let depth = session.layout.depth(of: parent.id) ?? 0
        let direction: SplitDirection = depth % 2 == 0 ? .horizontal : .vertical

        let usedColors = session.allPanes.compactMap { $0.agentInfo?.color }
        let nextColor = AgentColor.allCases.first { !usedColors.contains($0) }
            ?? AgentColor(rawValue: usedColors.count % AgentColor.allCases.count)!

        let childInfo = AgentInfo(
            agentID: event.agentID,
            roleName: shortRoleName(from: event.taskDescription, index: usedColors.count),
            status: .idle,
            color: nextColor,
            parentAgentID: event.parentAgentID,
            taskDescription: event.taskDescription
        )
        let childPane = AgentPane(agentInfo: childInfo, title: childInfo.roleName)

        withAnimation(.spring(duration: 0.3)) {
            session.layout = session.layout.splitting(
                paneID: parent.id,
                with: childPane,
                direction: direction,
                ratio: 0.5
            )
        }

        // Launch PTY for child pane (shell that sub-agent will inherit)
        launchPTY(for: childPane, in: session)
    }

    private func shortRoleName(from description: String?, index: Int) -> String {
        guard let desc = description, !desc.isEmpty else { return "sub-\(index + 1)" }
        let words = desc.split(separator: " ").prefix(2)
        return words.joined(separator: " ")
    }

    // MARK: - Keyboard Commands

    func handleKeyboardCommand(_ command: KeyboardCommand) {
        switch command {
        case .newSession:
            newLocalSession()
        case .closeSession:
            if let id = activeSessionID { closeSession(id: id) }
        case .splitHorizontal:
            splitActivePane(direction: .horizontal)
        case .splitVertical:
            splitActivePane(direction: .vertical)
        case .switchSession(let index):
            if index < sessions.count {
                activeSessionID = sessions[index].id
            }
        }
    }
}

// MARK: - Keyboard Commands

enum KeyboardCommand {
    case newSession
    case closeSession
    case splitHorizontal
    case splitVertical
    case switchSession(Int)
}
