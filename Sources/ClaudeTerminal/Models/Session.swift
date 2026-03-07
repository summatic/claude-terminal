import Foundation

// MARK: - Session

/// 독립적인 작업공간 단위. tmux의 세션에 해당합니다.
///
/// 각 세션은 하나의 `PaneLayout` 트리를 소유하며, 세션 탭바에서 탭으로 표시됩니다.
/// 로컬 세션은 로컬 PTY 프로세스를, 원격 세션은 SSH PTY를 실행합니다.
///
/// `AppState`가 `[Session]` 배열을 소유하며, `@MainActor`에서만 수정됩니다.
final class Session: ObservableObject, Identifiable {
    /// 세션의 고유 식별자
    let id: UUID
    /// 탭바에 표시되는 세션 이름 (로컬: "Session N", 원격: 호스트명)
    @Published var name: String
    /// 패인 배치를 나타내는 이진 분할 트리
    @Published var layout: PaneLayout
    /// 현재 포커스된 패인의 ID
    @Published var activePaneID: UUID?
    /// 로컬/원격 연결 종류
    @Published var connectionType: ConnectionType
    let createdAt: Date

    init(
        id: UUID = UUID(),
        name: String? = nil,
        connectionType: ConnectionType = .local,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.createdAt = createdAt
        self.connectionType = connectionType

        // Create initial pane
        let initialPane = AgentPane(title: connectionType.isRemote ? "Remote Terminal" : "Terminal")
        self.layout = .leaf(initialPane)
        self.activePaneID = initialPane.id
        self.name = name ?? (connectionType.isRemote ? connectionType.displayName : "Session")
    }

    var allPanes: [AgentPane] { layout.allPanes }

    var activePane: AgentPane? {
        guard let id = activePaneID else { return nil }
        return layout.pane(id: id)
    }

    // MARK: - Pane Management

    /// 현재 활성 패인을 지정한 방향으로 분할하고, 새 패인을 활성화합니다.
    ///
    /// - Parameter direction: `.horizontal`(좌우) 또는 `.vertical`(상하)
    func splitActivePane(direction: SplitDirection) {
        guard let paneID = activePaneID else { return }
        let newPane = AgentPane(title: "Terminal")
        layout = layout.splitting(paneID: paneID, with: newPane, direction: direction)
        activePaneID = newPane.id
    }

    /// 지정한 패인을 세션에서 제거합니다. 마지막 패인은 제거할 수 없습니다.
    ///
    /// 활성 패인이 제거되면 자동으로 다른 패인이 활성화됩니다.
    func closePane(id: UUID) {
        guard allPanes.count > 1 else { return }
        if let newLayout = layout.removing(paneID: id) {
            layout = newLayout
            if activePaneID == id {
                activePaneID = layout.allPanes.first?.id
            }
        }
    }

    // MARK: - Auto-split for sub-agent

    /// Called when a Task tool fires: automatically split the parent agent's pane
    func handleSubAgentSpawn(event: HookEvent) {
        guard event.type == .preToolUse, event.toolName == "Task" else { return }

        // Find parent pane by agentID
        let parentPane: AgentPane?
        if let parentID = event.parentAgentID {
            parentPane = allPanes.first { $0.agentInfo?.agentID == parentID }
        } else {
            parentPane = allPanes.first { $0.agentInfo == nil } ?? allPanes.first
        }

        guard let parent = parentPane else { return }

        // Choose split direction based on depth (alternating)
        let depth = layout.depth(of: parent.id) ?? 0
        let direction: SplitDirection = depth % 2 == 0 ? .horizontal : .vertical

        // Assign color to new agent
        let usedColors = allPanes.compactMap { $0.agentInfo?.color }
        let nextColor = AgentColor.allCases.first { !usedColors.contains($0) }
            ?? AgentColor.allCases[usedColors.count % AgentColor.allCases.count]

        let childInfo = AgentInfo(
            agentID: event.agentID,
            roleName: inferRoleName(from: event.taskDescription, index: usedColors.count),
            status: .idle,
            color: nextColor,
            parentAgentID: event.parentAgentID,
            taskDescription: event.taskDescription
        )
        let childPane = AgentPane(agentInfo: childInfo, title: childInfo.roleName)

        layout = layout.splitting(
            paneID: parent.id,
            with: childPane,
            direction: direction,
            ratio: 0.5
        )
    }

    /// 주어진 `agentID`를 가진 모든 패인의 에이전트 상태를 갱신합니다.
    func updateAgentStatus(agentID: String, status: AgentStatus) {
        allPanes
            .filter { $0.agentInfo?.agentID == agentID }
            .forEach { $0.agentInfo?.status = status }
    }

    /// 에이전트가 파일에 접근했을 때 해당 경로를 `AgentInfo.touchedFiles`에 추가합니다.
    ///
    /// Phase 5 파일트리 시각화에서 에이전트별 작업 파일을 하이라이트하는 데 사용됩니다.
    func recordFileTouched(agentID: String, filePath: String) {
        allPanes
            .filter { $0.agentInfo?.agentID == agentID }
            .forEach { $0.agentInfo?.touchedFiles.insert(filePath) }
    }

    // MARK: - Helpers

    private func inferRoleName(from description: String?, index: Int) -> String {
        guard let desc = description, !desc.isEmpty else {
            return "sub-\(index + 1)"
        }
        // Take first few words as role name
        let words = desc.split(separator: " ").prefix(2)
        return words.joined(separator: " ")
    }
}

extension Session: Equatable {
    static func == (lhs: Session, rhs: Session) -> Bool {
        lhs.id == rhs.id
    }
}
