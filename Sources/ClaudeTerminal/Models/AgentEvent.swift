import Foundation

// MARK: - Agent Status

enum AgentStatus: String, Codable, Equatable {
    case idle
    case thinking   // LLM generating response
    case writing    // Writing to file
    case running    // Executing tool/bash
    case waiting    // Waiting for sub-agent
    case done       // Task complete
    case error      // Error state
}

// MARK: - Agent Color

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

struct AgentInfo: Identifiable, Codable, Equatable {
    let id: UUID
    var agentID: String         // Stable ID from hook (session/agent identifier)
    var roleName: String        // "main", "sub-1", "researcher", etc.
    var status: AgentStatus
    var color: AgentColor
    var touchedFiles: Set<String>
    var parentAgentID: String?
    var taskDescription: String?
    var spawnedAt: Date

    init(
        id: UUID = UUID(),
        agentID: String,
        roleName: String = "agent",
        status: AgentStatus = .idle,
        color: AgentColor = .blue,
        touchedFiles: Set<String> = [],
        parentAgentID: String? = nil,
        taskDescription: String? = nil,
        spawnedAt: Date = Date()
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
    }
}

// MARK: - Hook Event (Hook → App via IPC)

enum HookEventType: String, Codable {
    case preToolUse   = "PreToolUse"
    case postToolUse  = "PostToolUse"
    case agentStatus  = "AgentStatus"
    case fileTouched  = "FileTouched"
    case sessionStart = "SessionStart"
    case sessionEnd   = "SessionEnd"
}

struct HookEvent: Codable {
    let type: HookEventType
    let agentID: String
    let parentAgentID: String?
    let sessionID: String?
    let toolName: String?
    let toolInput: [String: String]?
    let status: AgentStatus?
    let filePath: String?
    let fileOperation: String?      // "read", "write", "create", "delete"
    let taskDescription: String?
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
        self.timestamp = timestamp
    }
}

// MARK: - Hook Response (App → Hook)

struct HookResponse: Codable {
    let success: Bool
    let paneID: UUID?
    let message: String?
}
