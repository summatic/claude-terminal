import XCTest
@testable import ClaudeTerminal

// MARK: - HookEvent Codable Tests

final class HookEventCodableTests: XCTestCase {

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Round-trip encode/decode

    func testTaskEventRoundTrip() throws {
        let original = HookEvent(
            type: .preToolUse,
            agentID: "agent-abc-123",
            parentAgentID: "parent-xyz",
            sessionID: "session-001",
            toolName: "Task",
            taskDescription: "Refactor authentication module"
        )

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(HookEvent.self, from: data)

        XCTAssertEqual(decoded.type, .preToolUse)
        XCTAssertEqual(decoded.agentID, "agent-abc-123")
        XCTAssertEqual(decoded.parentAgentID, "parent-xyz")
        XCTAssertEqual(decoded.sessionID, "session-001")
        XCTAssertEqual(decoded.toolName, "Task")
        XCTAssertEqual(decoded.taskDescription, "Refactor authentication module")
    }

    func testFileTouchedEventRoundTrip() throws {
        let original = HookEvent(
            type: .fileTouched,
            agentID: "agent-001",
            filePath: "/Users/alice/project/main.swift",
            fileOperation: "write"
        )

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(HookEvent.self, from: data)

        XCTAssertEqual(decoded.type, .fileTouched)
        XCTAssertEqual(decoded.filePath, "/Users/alice/project/main.swift")
        XCTAssertEqual(decoded.fileOperation, "write")
    }

    func testAgentStatusEventRoundTrip() throws {
        let original = HookEvent(
            type: .agentStatus,
            agentID: "agent-001",
            status: .thinking
        )

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(HookEvent.self, from: data)

        XCTAssertEqual(decoded.type, .agentStatus)
        XCTAssertEqual(decoded.status, .thinking)
    }

    func testNilOptionalFieldsPreserved() throws {
        let original = HookEvent(type: .preToolUse, agentID: "a")
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(HookEvent.self, from: data)

        XCTAssertNil(decoded.parentAgentID)
        XCTAssertNil(decoded.sessionID)
        XCTAssertNil(decoded.toolName)
        XCTAssertNil(decoded.filePath)
        XCTAssertNil(decoded.status)
        XCTAssertNil(decoded.taskDescription)
    }

    // MARK: - Invalid JSON rejected

    func testInvalidJSONRejected() {
        let garbage = "{ not valid json }".data(using: .utf8)!
        XCTAssertThrowsError(try decoder.decode(HookEvent.self, from: garbage))
    }

    func testMissingRequiredFieldRejected() {
        // Missing "agentID"
        let json = """
        {"type":"PreToolUse","timestamp":"2026-03-07T00:00:00Z"}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try decoder.decode(HookEvent.self, from: json))
    }

    func testInvalidEnumValueRejected() {
        let json = """
        {"type":"UnknownType","agentID":"a","timestamp":"2026-03-07T00:00:00Z"}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try decoder.decode(HookEvent.self, from: json))
    }

    // MARK: - All HookEventType values round-trip

    func testAllEventTypesRoundTrip() throws {
        let types: [HookEventType] = [
            .preToolUse, .postToolUse, .agentStatus, .fileTouched,
            .sessionStart, .sessionEnd
        ]
        for type_ in types {
            let event = HookEvent(type: type_, agentID: "a")
            let data = try encoder.encode(event)
            let decoded = try decoder.decode(HookEvent.self, from: data)
            XCTAssertEqual(decoded.type, type_, "Round-trip failed for \(type_.rawValue)")
        }
    }

    // MARK: - All AgentStatus values round-trip

    func testAllAgentStatusesRoundTrip() throws {
        let statuses: [AgentStatus] = [
            .idle, .thinking, .writing, .running, .waiting, .done, .error
        ]
        for status in statuses {
            let event = HookEvent(type: .agentStatus, agentID: "a", status: status)
            let data = try encoder.encode(event)
            let decoded = try decoder.decode(HookEvent.self, from: data)
            XCTAssertEqual(decoded.status, status, "Round-trip failed for \(status.rawValue)")
        }
    }
}

// MARK: - HookResponse Tests

final class HookResponseTests: XCTestCase {

    func testSuccessResponseRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let response = HookResponse(success: true, paneID: UUID(), message: nil)
        let data = try encoder.encode(response)
        let decoded = try decoder.decode(HookResponse.self, from: data)

        XCTAssertTrue(decoded.success)
        XCTAssertEqual(decoded.paneID, response.paneID)
        XCTAssertNil(decoded.message)
    }

    func testFailureResponseRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let response = HookResponse(success: false, paneID: nil, message: "Auth failed")
        let data = try encoder.encode(response)
        let decoded = try decoder.decode(HookResponse.self, from: data)

        XCTAssertFalse(decoded.success)
        XCTAssertNil(decoded.paneID)
        XCTAssertEqual(decoded.message, "Auth failed")
    }
}

// MARK: - AgentInfo Tests

final class AgentInfoTests: XCTestCase {

    func testDefaultInit() {
        let info = AgentInfo(agentID: "test-agent")
        XCTAssertEqual(info.agentID, "test-agent")
        XCTAssertEqual(info.roleName, "agent")
        XCTAssertEqual(info.status, .idle)
        XCTAssertEqual(info.color, .blue)
        XCTAssertTrue(info.touchedFiles.isEmpty)
        XCTAssertNil(info.parentAgentID)
        XCTAssertNil(info.taskDescription)
    }

    func testAgentInfoCodableRoundTrip() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let original = AgentInfo(
            agentID: "agent-123",
            roleName: "researcher",
            status: .thinking,
            color: .green,
            touchedFiles: ["/Users/alice/file.swift"],
            parentAgentID: "parent-456",
            taskDescription: "Search web"
        )

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(AgentInfo.self, from: data)

        XCTAssertEqual(decoded.agentID, original.agentID)
        XCTAssertEqual(decoded.roleName, original.roleName)
        XCTAssertEqual(decoded.status, original.status)
        XCTAssertEqual(decoded.color, original.color)
        XCTAssertEqual(decoded.touchedFiles, original.touchedFiles)
        XCTAssertEqual(decoded.parentAgentID, original.parentAgentID)
    }

    func testAgentInfoEquality() {
        let id = UUID()
        let a = AgentInfo(id: id, agentID: "x", roleName: "r", status: .idle,
                          color: .blue, touchedFiles: [], parentAgentID: nil)
        let b = AgentInfo(id: id, agentID: "x", roleName: "r", status: .idle,
                          color: .blue, touchedFiles: [], parentAgentID: nil)
        XCTAssertEqual(a, b)
    }
}
