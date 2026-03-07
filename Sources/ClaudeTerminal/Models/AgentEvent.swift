import Foundation

// MARK: - Agent Status

/// Claude Code 에이전트의 현재 실행 상태.
///
/// 훅 이벤트(`HookEvent.type == .agentStatus`)를 통해 앱에 전달되며,
/// `AgentStatusDot` 뷰의 애니메이션을 결정합니다.
enum AgentStatus: String, Codable, Equatable {
    /// 대기 중 — 아무 작업도 하지 않는 상태
    case idle
    /// LLM이 응답을 생성 중 (맥박 애니메이션)
    case thinking
    /// 파일 쓰기 작업 중 (펜 애니메이션)
    case writing
    /// Bash/Tool 실행 중 (스피너 애니메이션)
    case running
    /// 서브에이전트 완료를 기다리는 중
    case waiting
    /// 태스크 완료 (체크마크)
    case done
    /// 오류 발생 (빨간 X)
    case error
}

// MARK: - Agent Color

/// 에이전트 패인에 할당되는 고유 색상.
///
/// 최대 8개의 에이전트를 색상으로 구분합니다.
/// `CaseIterable`이므로 순서대로 순환 할당이 가능합니다.
enum AgentColor: Int, CaseIterable, Codable {
    case blue = 0
    case green
    case yellow
    case orange
    case red
    case purple
    case cyan
    case pink

    var displayName: String {
        switch self {
        case .blue: return "Blue"
        case .green: return "Green"
        case .yellow: return "Yellow"
        case .orange: return "Orange"
        case .red: return "Red"
        case .purple: return "Purple"
        case .cyan: return "Cyan"
        case .pink: return "Pink"
        }
    }
}

// MARK: - Agent Info

/// 에이전트 패인에 표시되는 에이전트 메타데이터.
///
/// `AgentPane.agentInfo`로 보유되며, 훅 이벤트를 통해 갱신됩니다.
/// 일반 터미널 패인(에이전트 없음)에서는 `AgentPane.agentInfo`가 `nil`입니다.
struct AgentInfo: Identifiable, Codable, Equatable {
    /// SwiftUI `Identifiable` 요구사항용 내부 UUID (agentID와 별개)
    let id: UUID
    /// 훅에서 전달받은 안정적인 에이전트 식별자 (세션/에이전트 구분용)
    var agentID: String
    /// 패인 헤더에 표시되는 역할 이름 ("main", "sub-1", "researcher" 등)
    var roleName: String
    var status: AgentStatus
    /// 패인 헤더의 컬러 액센트 및 상태 도트 색상
    var color: AgentColor
    /// 이 에이전트가 접근한 파일 경로 집합 (Phase 11 파일트리 시각화용)
    var touchedFiles: Set<String>
    /// 부모 에이전트의 `agentID`. 루트 에이전트면 `nil`.
    var parentAgentID: String?
    /// Task 툴에 전달된 태스크 설명 (패인 헤더 툴팁으로 표시)
    var taskDescription: String?
    var spawnedAt: Date
    /// 이 에이전트가 호출한 총 툴 횟수 (Phase 8 메트릭)
    var toolCallCount: Int
    /// 가장 최근에 호출한 툴 이름 (Phase 8 메트릭)
    var lastToolName: String?

    init(
        id: UUID = UUID(),
        agentID: String,
        roleName: String = "agent",
        status: AgentStatus = .idle,
        color: AgentColor = .blue,
        touchedFiles: Set<String> = [],
        parentAgentID: String? = nil,
        taskDescription: String? = nil,
        spawnedAt: Date = Date(),
        toolCallCount: Int = 0,
        lastToolName: String? = nil
    ) {
        self.id = id
        self.agentID = agentID
        self.roleName = roleName
        self.status = status
        self.color = color
        self.touchedFiles = touchedFiles
        self.parentAgentID = parentAgentID
        self.taskDescription = taskDescription
        self.spawnedAt = spawnedAt
        self.toolCallCount = toolCallCount
        self.lastToolName = lastToolName
    }
}

// MARK: - Permission Request (Phase 10)

/// 에이전트가 툴 실행 전 사용자 승인을 요청할 때 생성되는 구조체.
/// `AppState.pendingPermissions`에 누적되며 `ActivityStreamView`에서 표시됩니다.
struct PermissionRequest: Identifiable, Codable {
    let id: UUID
    let agentID: String
    let toolName: String
    let toolInput: [String: String]
    let sessionID: String?
    let requestedAt: Date
    /// 처리 결과: true=승인, false=거절, nil=미처리
    var wasApproved: Bool? = nil
}

// MARK: - Hook Event (Hook → App via IPC)

/// Claude Code 훅 스크립트가 앱에 전송하는 이벤트 유형.
///
/// `hook-notify.py`가 Claude Code의 PreToolUse/PostToolUse 훅에서 실행되며,
/// 이 타입에 따라 앱의 레이아웃과 에이전트 상태가 갱신됩니다.
enum HookEventType: String, Codable {
    /// `Task` 툴 실행 직전 — 서브에이전트 생성 신호 (자동 분할 트리거)
    case preToolUse   = "PreToolUse"
    /// `Task` 툴 실행 완료 — 서브에이전트 종료 신호
    case postToolUse  = "PostToolUse"
    /// 에이전트 상태 변경 (thinking/writing/running 등)
    case agentStatus  = "AgentStatus"
    /// 에이전트가 파일을 읽거나 쓴 이벤트 (Phase 11 파일트리 시각화용)
    case fileTouched  = "FileTouched"
    /// Claude Code 세션 시작
    case sessionStart = "SessionStart"
    /// Claude Code 세션 종료
    case sessionEnd   = "SessionEnd"
    /// API 레이트 리밋 도달 (Phase 9)
    case rateLimited  = "RateLimited"
    /// 툴 실행 전 사용자 승인 요청 (Phase 10)
    case permissionRequest = "PermissionRequest"
}

/// IPC(Unix Socket 또는 HTTP POST)로 전달되는 훅 이벤트 페이로드.
///
/// 로컬 훅의 경우 `AuthenticatedMessage`로 래핑되어 HMAC 서명이 함께 전송됩니다.
/// 원격 훅의 경우 HTTP 바디에 직접 JSON으로 전송됩니다.
///
/// 필수 필드: `type`, `agentID`, `timestamp`
/// 나머지 필드는 이벤트 유형에 따라 선택적으로 채워집니다.
struct HookEvent: Codable {
    /// 이벤트 종류
    let type: HookEventType
    /// 이벤트를 발생시킨 에이전트의 식별자
    let agentID: String
    /// 부모 에이전트 ID. `preToolUse` 이벤트에서 계층 추적에 사용.
    let parentAgentID: String?
    /// Claude Code 세션 ID. 멀티세션 환경에서 대상 세션을 특정하는 데 사용.
    let sessionID: String?
    /// 실행된 툴 이름 (예: `"Task"`, `"Bash"`, `"Write"`)
    let toolName: String?
    /// 툴 입력 파라미터 (예: `["agent_id": "abc"]`)
    let toolInput: [String: String]?
    /// `agentStatus` 이벤트일 때 새 상태값
    let status: AgentStatus?
    /// `fileTouched` 이벤트일 때 접근된 파일 절대 경로
    let filePath: String?
    /// 파일 작업 종류: `"read"`, `"write"`, `"create"`, `"delete"`
    let fileOperation: String?
    /// `preToolUse(Task)` 이벤트일 때 태스크 설명 (패인 헤더에 표시)
    let taskDescription: String?
    /// `rateLimited` 이벤트일 때 레이트 리밋 해제 시각 (ISO8601, Phase 9)
    let rateLimitResetAt: String?
    let timestamp: Date

    init(
        type: HookEventType,
        agentID: String,
        parentAgentID: String? = nil,
        sessionID: String? = nil,
        toolName: String? = nil,
        toolInput: [String: String]? = nil,
        status: AgentStatus? = nil,
        filePath: String? = nil,
        fileOperation: String? = nil,
        taskDescription: String? = nil,
        rateLimitResetAt: String? = nil,
        timestamp: Date = Date()
    ) {
        self.type = type
        self.agentID = agentID
        self.parentAgentID = parentAgentID
        self.sessionID = sessionID
        self.toolName = toolName
        self.toolInput = toolInput
        self.status = status
        self.filePath = filePath
        self.fileOperation = fileOperation
        self.taskDescription = taskDescription
        self.rateLimitResetAt = rateLimitResetAt
        self.timestamp = timestamp
    }
}

// MARK: - Hook Response (App → Hook)

/// 훅 이벤트 수신 후 앱이 훅 스크립트에 돌려주는 응답.
///
/// `IPCServer`가 Unix Socket 연결에 4바이트 길이 헤더 + JSON 형태로 응답합니다.
struct HookResponse: Codable {
    /// 이벤트 처리 성공 여부
    let success: Bool
    /// 이벤트 처리 결과 생성된 패인 ID (서브에이전트 spawn 시)
    let paneID: UUID?
    /// 실패 시 오류 메시지 (예: `"Auth failed"`, `"Field too long"`)
    let message: String?
}
