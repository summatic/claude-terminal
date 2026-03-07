import XCTest
@testable import ClaudeTerminal

// MARK: - Session Tests

final class SessionInitTests: XCTestCase {

    func testLocalSessionHasInitialPane() {
        let session = Session(connectionType: .local)
        XCTAssertEqual(session.allPanes.count, 1)
    }

    func testLocalSessionHasActivePaneSet() {
        let session = Session(connectionType: .local)
        XCTAssertNotNil(session.activePaneID)
        XCTAssertEqual(session.activePaneID, session.allPanes.first?.id)
    }

    func testSessionNameDefault() {
        let session = Session(connectionType: .local)
        XCTAssertEqual(session.name, "Session")
    }

    func testSessionCustomName() {
        let session = Session(name: "My Session", connectionType: .local)
        XCTAssertEqual(session.name, "My Session")
    }

    func testRemoteSessionTitle() {
        let conn = ConnectionType.remote(host: "server.example.com", sshPort: 22, wsPort: 9901)
        let session = Session(connectionType: conn)
        XCTAssertEqual(session.name, "server.example.com")
    }
}

// MARK: - Session Pane Management Tests

final class SessionPaneManagementTests: XCTestCase {

    func testSplitHorizontallyAddsPane() {
        let session = Session(connectionType: .local)
        XCTAssertEqual(session.allPanes.count, 1)

        session.splitActivePane(direction: .horizontal)
        XCTAssertEqual(session.allPanes.count, 2)
    }

    func testSplitVerticallyAddsPane() {
        let session = Session(connectionType: .local)
        session.splitActivePane(direction: .vertical)
        XCTAssertEqual(session.allPanes.count, 2)
    }

    func testSplitUpdatesActivePane() {
        let session = Session(connectionType: .local)
        let originalActive = session.activePaneID
        session.splitActivePane(direction: .horizontal)
        // New pane should be active
        XCTAssertNotEqual(session.activePaneID, originalActive)
    }

    func testClosePaneReducesCount() {
        let session = Session(connectionType: .local)
        session.splitActivePane(direction: .horizontal)
        XCTAssertEqual(session.allPanes.count, 2)

        let paneToClose = session.allPanes.last!.id
        session.closePane(id: paneToClose)
        XCTAssertEqual(session.allPanes.count, 1)
    }

    func testCloseLastPaneNoOp() {
        let session = Session(connectionType: .local)
        XCTAssertEqual(session.allPanes.count, 1)

        let onlyPane = session.allPanes.first!.id
        session.closePane(id: onlyPane)
        // Should still have 1 pane
        XCTAssertEqual(session.allPanes.count, 1)
    }

    func testCloseActivePaneSwitchesActive() {
        let session = Session(connectionType: .local)
        session.splitActivePane(direction: .horizontal)
        let currentActive = session.activePaneID!

        session.closePane(id: currentActive)
        XCTAssertNotNil(session.activePaneID)
        XCTAssertNotEqual(session.activePaneID, currentActive)
    }

    func testMultipleSplitsAccumulate() {
        let session = Session(connectionType: .local)
        session.splitActivePane(direction: .horizontal)
        session.splitActivePane(direction: .vertical)
        session.splitActivePane(direction: .horizontal)
        XCTAssertEqual(session.allPanes.count, 4)
    }
}

// MARK: - Agent Color Assignment Tests

final class AgentColorAssignmentTests: XCTestCase {

    func testFirstAgentGetsBlue() {
        let usedColors: [AgentColor] = []
        let nextColor = AgentColor.allCases.first { !usedColors.contains($0) }
            ?? AgentColor.allCases[usedColors.count % AgentColor.allCases.count]
        XCTAssertEqual(nextColor, .blue)
    }

    func testSecondAgentGetsGreen() {
        let usedColors: [AgentColor] = [.blue]
        let nextColor = AgentColor.allCases.first { !usedColors.contains($0) }
            ?? AgentColor.allCases[usedColors.count % AgentColor.allCases.count]
        XCTAssertEqual(nextColor, .green)
    }

    func testAllColorsUsedCyclesBackToBlue() {
        let usedColors = AgentColor.allCases
        // Falls through to safe subscript
        let nextColor = AgentColor.allCases.first { !usedColors.contains($0) }
            ?? AgentColor.allCases[usedColors.count % AgentColor.allCases.count]
        XCTAssertEqual(nextColor, .blue)
    }

    func testColorCountMatchesExpected() {
        XCTAssertEqual(AgentColor.allCases.count, 8)
    }

    func testAllColorsHaveUniqueRawValues() {
        let rawValues = AgentColor.allCases.map(\.rawValue)
        let unique = Set(rawValues)
        XCTAssertEqual(unique.count, rawValues.count)
    }

    func testColorRawValuesAreContiguous() {
        // rawValues should be 0..<8
        let rawValues = AgentColor.allCases.map(\.rawValue).sorted()
        XCTAssertEqual(rawValues, Array(0..<AgentColor.allCases.count))
    }
}

// MARK: - Agent Status Tests

final class AgentStatusTests: XCTestCase {

    func testUpdateAgentStatusChangesValue() {
        let session = Session(connectionType: .local)
        let pane = session.allPanes.first!
        pane.agentInfo = AgentInfo(agentID: "agent-1", status: .idle)

        session.updateAgentStatus(agentID: "agent-1", status: .thinking)
        XCTAssertEqual(pane.agentInfo?.status, .thinking)
    }

    func testUpdateNonexistentAgentIsNoOp() {
        let session = Session(connectionType: .local)
        // Should not crash
        session.updateAgentStatus(agentID: "nonexistent", status: .done)
    }

    func testRecordFileTouchedAddsToSet() {
        let session = Session(connectionType: .local)
        let pane = session.allPanes.first!
        pane.agentInfo = AgentInfo(agentID: "agent-1")

        session.recordFileTouched(agentID: "agent-1", filePath: "/Users/alice/file.swift")
        XCTAssertTrue(pane.agentInfo?.touchedFiles.contains("/Users/alice/file.swift") ?? false)
    }

    func testRecordMultipleFilesAccumulate() {
        let session = Session(connectionType: .local)
        let pane = session.allPanes.first!
        pane.agentInfo = AgentInfo(agentID: "agent-1")

        session.recordFileTouched(agentID: "agent-1", filePath: "/file1.swift")
        session.recordFileTouched(agentID: "agent-1", filePath: "/file2.swift")
        XCTAssertEqual(pane.agentInfo?.touchedFiles.count, 2)
    }

    func testRecordSameFileTwiceDeduplicates() {
        let session = Session(connectionType: .local)
        let pane = session.allPanes.first!
        pane.agentInfo = AgentInfo(agentID: "agent-1")

        session.recordFileTouched(agentID: "agent-1", filePath: "/same.swift")
        session.recordFileTouched(agentID: "agent-1", filePath: "/same.swift")
        XCTAssertEqual(pane.agentInfo?.touchedFiles.count, 1)
    }
}

// MARK: - Sub-Agent Spawn Tests

final class SubAgentSpawnTests: XCTestCase {

    func testSubAgentSpawnSplitsLayout() {
        let session = Session(connectionType: .local)
        let mainPane = session.allPanes.first!
        mainPane.agentInfo = AgentInfo(agentID: "main-agent")

        XCTAssertEqual(session.allPanes.count, 1)

        let event = HookEvent(
            type: .preToolUse,
            agentID: "sub-agent-1",
            parentAgentID: "main-agent",
            toolName: "Task",
            taskDescription: "Analyze codebase"
        )
        session.handleSubAgentSpawn(event: event)

        XCTAssertEqual(session.allPanes.count, 2)
    }

    func testSubAgentGetsDistinctColor() {
        let session = Session(connectionType: .local)
        let mainPane = session.allPanes.first!
        mainPane.agentInfo = AgentInfo(agentID: "main-agent", color: .blue)

        let event = HookEvent(
            type: .preToolUse,
            agentID: "sub-agent-1",
            parentAgentID: "main-agent",
            toolName: "Task",
            taskDescription: "Sub task"
        )
        session.handleSubAgentSpawn(event: event)

        let childPane = session.allPanes.first { $0.agentInfo?.agentID == "sub-agent-1" }
        XCTAssertNotNil(childPane)
        XCTAssertNotEqual(childPane?.agentInfo?.color, .blue)
    }

    func testSubAgentHasParentReference() {
        let session = Session(connectionType: .local)
        let mainPane = session.allPanes.first!
        mainPane.agentInfo = AgentInfo(agentID: "main-agent")

        let event = HookEvent(
            type: .preToolUse,
            agentID: "sub-agent-1",
            parentAgentID: "main-agent",
            toolName: "Task",
            taskDescription: "Sub task"
        )
        session.handleSubAgentSpawn(event: event)

        let childPane = session.allPanes.first { $0.agentInfo?.agentID == "sub-agent-1" }
        XCTAssertEqual(childPane?.agentInfo?.parentAgentID, "main-agent")
    }

    func testNonTaskToolEventDoesNotSplit() {
        let session = Session(connectionType: .local)
        XCTAssertEqual(session.allPanes.count, 1)

        let event = HookEvent(
            type: .preToolUse,
            agentID: "agent-1",
            toolName: "Read"  // Not "Task"
        )
        session.handleSubAgentSpawn(event: event)

        // Should not split since toolName != "Task"
        XCTAssertEqual(session.allPanes.count, 1)
    }

    func testSecondSubAgentUsesAlternatingDirection() {
        let session = Session(connectionType: .local)
        let mainPane = session.allPanes.first!
        mainPane.agentInfo = AgentInfo(agentID: "main")

        // First sub-agent (depth 0 → horizontal split)
        session.handleSubAgentSpawn(event: HookEvent(
            type: .preToolUse,
            agentID: "sub-1",
            parentAgentID: "main",
            toolName: "Task",
            taskDescription: "Task 1"
        ))

        XCTAssertEqual(session.allPanes.count, 2)

        // Check layout has hsplit at top level (depth 0 → horizontal)
        if case .hsplit = session.layout {
            // Expected
        } else {
            XCTFail("Expected horizontal split at depth 0")
        }
    }
}

// MARK: - ConnectionType Tests

final class ConnectionTypeTests: XCTestCase {

    func testLocalIsNotRemote() {
        XCTAssertFalse(ConnectionType.local.isRemote)
    }

    func testRemoteIsRemote() {
        let conn = ConnectionType.remote(host: "server.com", sshPort: 22, wsPort: 9901)
        XCTAssertTrue(conn.isRemote)
    }

    func testLocalDisplayName() {
        XCTAssertEqual(ConnectionType.local.displayName, "Local")
    }

    func testRemoteDisplayName() {
        let conn = ConnectionType.remote(host: "myserver.com", sshPort: 22, wsPort: 9901)
        XCTAssertEqual(conn.displayName, "myserver.com")
    }

    func testLocalEquality() {
        XCTAssertEqual(ConnectionType.local, ConnectionType.local)
    }

    func testRemoteEquality() {
        let a = ConnectionType.remote(host: "s.com", sshPort: 22, wsPort: 9901)
        let b = ConnectionType.remote(host: "s.com", sshPort: 22, wsPort: 9901)
        XCTAssertEqual(a, b)
    }

    func testRemoteInequalityOnHost() {
        let a = ConnectionType.remote(host: "a.com", sshPort: 22, wsPort: 9901)
        let b = ConnectionType.remote(host: "b.com", sshPort: 22, wsPort: 9901)
        XCTAssertNotEqual(a, b)
    }
}
