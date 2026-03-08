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
    /// 작업 디렉터리의 Git 브랜치 이름 (Phase 12)
    @Published var gitBranch: String? = nil
    /// `recordFileTouched` 호출 시마다 증가 — FileSidebarView 트리 캐시 무효화용
    @Published private(set) var touchedFilesVersion: Int = 0
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

    /// 모든 에이전트가 접근한 (agentID, filePath) 쌍 목록 (Phase 11 파일 사이드바용)
    var allTouchedFiles: [(agentID: String, filePath: String)] {
        allPanes.compactMap { $0.agentInfo }.flatMap { info in
            info.touchedFiles.map { (info.agentID, $0) }
        }
    }

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

    /// Task 툴 이벤트 수신 시 부모 에이전트 패인을 자동 분할하고 새 패인을 반환합니다.
    ///
    /// - Returns: 생성된 자식 패인. 이벤트 조건 미충족이거나 부모를 찾지 못하면 `nil`.
    /// - Note: `AppState`가 반환된 패인으로 PTY를 실행합니다.
    @discardableResult
    func handleSubAgentSpawn(event: HookEvent) -> AgentPane? {
        guard event.type == .preToolUse, event.toolName == "Task" else { return nil }

        // Find parent pane by agentID
        let parentPane: AgentPane?
        if let parentID = event.parentAgentID {
            parentPane = allPanes.first { $0.agentInfo?.agentID == parentID }
        } else {
            parentPane = allPanes.first { $0.agentInfo == nil } ?? allPanes.first
        }

        guard let parent = parentPane else { return nil }

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
        return childPane
    }

    /// 주어진 `agentID`를 가진 모든 패인의 에이전트 상태를 갱신합니다.
    func updateAgentStatus(agentID: String, status: AgentStatus) {
        forEachPane(agentID: agentID) { $0.agentInfo?.status = status }
    }

    /// 에이전트가 파일에 접근했을 때 해당 경로를 `AgentInfo.touchedFiles`에 추가합니다.
    ///
    /// Phase 5 파일트리 시각화에서 에이전트별 작업 파일을 하이라이트하는 데 사용됩니다.
    func recordFileTouched(agentID: String, filePath: String) {
        forEachPane(agentID: agentID) { $0.agentInfo?.touchedFiles.insert(filePath) }
        touchedFilesVersion += 1
    }

    /// 에이전트가 툴을 호출할 때마다 카운터를 증가시킵니다 (Phase 8 메트릭).
    func incrementToolCall(agentID: String, toolName: String?) {
        forEachPane(agentID: agentID) {
            $0.agentInfo?.toolCallCount += 1
            $0.agentInfo?.lastToolName = toolName
        }
    }

    private func forEachPane(agentID: String, _ action: (AgentPane) -> Void) {
        allPanes.filter { $0.agentInfo?.agentID == agentID }.forEach(action)
    }

    // MARK: - Git Branch (Phase 12)

    /// 홈 디렉터리의 Git 브랜치를 비동기로 읽어 `gitBranch`를 갱신합니다.
    func refreshGitBranch() {
        let directory = FileManager.default.homeDirectoryForCurrentUser.path
        Task {
            let branch = await Self.readGitBranch(in: directory)
            await MainActor.run { self.gitBranch = branch }
        }
    }

    private static func readGitBranch(in directory: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                proc.arguments = ["-C", directory, "rev-parse", "--abbrev-ref", "HEAD"]
                proc.currentDirectoryURL = URL(fileURLWithPath: directory)
                let pipe = Pipe()
                proc.standardOutput = pipe
                proc.standardError = Pipe()
                do {
                    try proc.run()
                    proc.waitUntilExit()
                    guard proc.terminationStatus == 0 else {
                        return continuation.resume(returning: nil)
                    }
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let branch = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: branch?.isEmpty == true ? nil : branch)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
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
