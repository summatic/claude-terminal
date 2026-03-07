import Foundation

// MARK: - Session

final class Session: ObservableObject, Identifiable {
    let id: UUID
    @Published var name: String
    @Published var layout: PaneLayout
    @Published var activePaneID: UUID?
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

    func splitActivePane(direction: SplitDirection) {
        guard let paneID = activePaneID else { return }
        let newPane = AgentPane(title: "Terminal")
        layout = layout.splitting(paneID: paneID, with: newPane, direction: direction)
        activePaneID = newPane.id
    }

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
            ?? AgentColor(rawValue: usedColors.count % AgentColor.allCases.count)!

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

    func updateAgentStatus(agentID: String, status: AgentStatus) {
        allPanes
            .filter { $0.agentInfo?.agentID == agentID }
            .forEach { $0.agentInfo?.status = status }
    }

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
