import SwiftUI

// MARK: - App State (single source of truth)

/// 앱 전체의 상태를 관리하는 단일 진실의 원천(Single Source of Truth).
///
/// `@MainActor`로 선언되어 모든 프로퍼티 접근과 메서드 호출이 메인 스레드에서 실행됩니다.
/// IPC 콜백 및 PTY 종료 콜백은 `Task { @MainActor in ... }`로 메인 스레드에 전달됩니다.
///
/// ## 책임 범위
/// - 세션(탭) 목록 및 활성 세션 관리
/// - PTY 프로세스 수명주기 (`launchPTY`, `terminatePTY`)
/// - 훅 이벤트 수신 및 레이아웃 자동 분할 트리거
/// - 키보드 단축키 처리
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

    /// 새 로컬 세션을 생성하고 즉시 PTY 프로세스를 실행합니다.
    func newLocalSession() {
        let session = Session(name: "Session \(sessions.count + 1)", connectionType: .local)
        sessions.append(session)
        activeSessionID = session.id
        if let pane = session.layout.allPanes.first {
            launchPTY(for: pane, in: session)
        }
    }

    /// 원격 SSH 세션을 생성합니다.
    ///
    /// 입력값을 검증한 후 `ssh -p <sshPort> <host>` 프로세스를 PTY로 실행합니다.
    /// 유효하지 않은 호스트나 포트이면 조용히 무시합니다.
    ///
    /// - Parameters:
    ///   - host: SSH 호스트명 또는 IP (제어문자 포함 불가)
    ///   - sshPort: SSH 포트 (1–65535)
    ///   - wsPort: 원격 훅 이벤트 수신 포트 (SSH 터널 경유)
    func newRemoteSession(host: String, sshPort: Int = 22, wsPort: Int = 9901) {
        guard isValidSSHPort(sshPort) else {
            print("[AppState] Invalid SSH port: \(sshPort)")
            return
        }
        guard isValidHost(host) else {
            print("[AppState] Invalid host: \(host)")
            return
        }

        let conn = ConnectionType.remote(host: host, sshPort: sshPort, wsPort: wsPort)
        let session = Session(name: host, connectionType: conn)
        sessions.append(session)
        activeSessionID = session.id
        if let pane = session.layout.allPanes.first {
            launchRemotePTY(for: pane, host: host, sshPort: sshPort)
        }
    }

    /// 세션을 닫고 해당 세션의 모든 PTY 프로세스를 종료합니다.
    ///
    /// 마지막 남은 세션은 닫을 수 없습니다 (`sessions.count > 1` 보장).
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
            pane.agentInfo?.status = .error
            pane.title = "Error: \(error.localizedDescription)"
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
            pane.agentInfo?.status = .error
            pane.title = "SSH Error: \(error.localizedDescription)"
        }
    }

    private func terminatePTY(for paneID: UUID) {
        // Terminate but don't remove immediately; the termination callback
        // will fire from the background queue. We nil out after sending signal
        // so PTY is cleaned up even if no further operations reference it.
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

    /// IPC 서버로부터 수신한 훅 이벤트를 처리합니다.
    ///
    /// 이벤트의 `sessionID`로 대상 세션을 찾고, 없으면 활성 세션에 적용합니다.
    ///
    /// | 이벤트 | 처리 |
    /// |--------|------|
    /// | `preToolUse(Task)` | 서브에이전트 패인 자동 분할 |
    /// | `postToolUse(Task)` | 서브에이전트 상태 `.done` 으로 갱신 |
    /// | `agentStatus` | 해당 에이전트 상태 갱신 |
    /// | `fileTouched` | 파일 경로 검증 후 `touchedFiles`에 추가 |
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
            if let path = event.filePath, isValidFilePath(path) {
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
        // Safe color selection: no force unwrap
        let nextColor = AgentColor.allCases.first { !usedColors.contains($0) }
            ?? AgentColor.allCases[usedColors.count % AgentColor.allCases.count]

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

    // isValidFilePath, isValidSSHPort, isValidHost defined in Validation.swift

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
