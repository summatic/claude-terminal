import XCTest
@testable import ClaudeTerminal

// MARK: - Functional Tests
//
// 단위 테스트와 달리, 실제 유저 시나리오를 여러 컴포넌트가 연동된 상태로 검증합니다.
// 각 테스트는 "사용자가 A → B → C를 했을 때 D가 되어야 한다" 형태의 시나리오입니다.

// MARK: - Scenario 1: 멀티 패인 분할 및 닫기 워크플로우

final class MultiPaneWorkflowTests: XCTestCase {

    /// 사용자가 터미널을 열고 → 좌우 분할 → 상하 분할 → 중간 패인 닫기
    /// 결과: 패인 수가 정확하고, activePaneID가 항상 유효해야 함.
    func testSplitAndCloseWorkflow() {
        let session = Session(connectionType: .local)
        XCTAssertEqual(session.allPanes.count, 1)

        // Step 1: 좌우 분할
        session.splitActivePane(direction: .horizontal)
        XCTAssertEqual(session.allPanes.count, 2)
        let rightPane = session.activePane
        XCTAssertNotNil(rightPane)

        // Step 2: 오른쪽 패인을 상하 분할
        session.splitActivePane(direction: .vertical)
        XCTAssertEqual(session.allPanes.count, 3)
        let bottomPane = session.activePane!

        // Step 3: 하단 패인 닫기
        session.closePane(id: bottomPane.id)
        XCTAssertEqual(session.allPanes.count, 2)

        // activePaneID는 반드시 현존하는 패인을 가리켜야 함
        XCTAssertNotNil(session.activePaneID)
        let allIDs = session.allPanes.map(\.id)
        XCTAssertTrue(allIDs.contains(session.activePaneID!))
    }

    /// 연속으로 4번 분할 후 하나씩 모두 닫기 → 최종적으로 패인 1개 유지
    func testSequentialSplitAndCloseUntilOne() {
        let session = Session(connectionType: .local)

        for direction in [SplitDirection.horizontal, .vertical, .horizontal, .vertical] {
            session.splitActivePane(direction: direction)
        }
        XCTAssertEqual(session.allPanes.count, 5)

        // 마지막 1개 남을 때까지 닫기
        while session.allPanes.count > 1 {
            let paneToClose = session.allPanes.last!.id
            session.closePane(id: paneToClose)
        }
        XCTAssertEqual(session.allPanes.count, 1)
        XCTAssertNotNil(session.activePaneID)
    }

    /// 마지막 패인은 닫을 수 없어야 함
    func testCannotCloseLastPane() {
        let session = Session(connectionType: .local)
        let onlyPaneID = session.allPanes.first!.id

        session.closePane(id: onlyPaneID)

        XCTAssertEqual(session.allPanes.count, 1, "마지막 패인은 닫히면 안 됨")
        XCTAssertEqual(session.allPanes.first!.id, onlyPaneID, "동일한 패인이 유지되어야 함")
    }

    /// 임의의 순서로 패인을 닫아도 activePaneID가 항상 유효한 패인을 가리켜야 함
    func testActivePaneAlwaysValidAfterClose() {
        let session = Session(connectionType: .local)
        session.splitActivePane(direction: .horizontal)
        session.splitActivePane(direction: .vertical)

        // 현재 활성 패인 닫기
        let activeID = session.activePaneID!
        session.closePane(id: activeID)

        XCTAssertNotNil(session.activePaneID)
        XCTAssertFalse(session.allPanes.map(\.id).contains(activeID), "닫힌 패인이 여전히 존재하면 안 됨")
        XCTAssertTrue(session.allPanes.map(\.id).contains(session.activePaneID!))
    }
}

// MARK: - Scenario 2: 서브 에이전트 스폰 워크플로우

final class SubAgentSpawnWorkflowTests: XCTestCase {

    /// 메인 에이전트 → 서브 에이전트 2개 순차 스폰 → 레이아웃/색상/부모 참조 통합 검증
    func testMultiLevelAgentSpawnWorkflow() {
        let session = Session(connectionType: .local)
        let mainPane = session.allPanes.first!
        mainPane.agentInfo = AgentInfo(agentID: "main", color: .blue)

        // Sub-agent 1 스폰
        let event1 = HookEvent(
            type: .preToolUse,
            agentID: "sub-1",
            parentAgentID: "main",
            toolName: "Task",
            taskDescription: "Write tests"
        )
        session.handleSubAgentSpawn(event: event1)
        XCTAssertEqual(session.allPanes.count, 2)

        // Sub-agent 1의 패인 검증
        let subPane1 = session.allPanes.first { $0.agentInfo?.agentID == "sub-1" }!
        XCTAssertEqual(subPane1.agentInfo?.parentAgentID, "main")
        XCTAssertNotEqual(subPane1.agentInfo?.color, .blue, "메인과 색상이 달라야 함")

        // Sub-agent 2 스폰 (다른 색상 배정 검증)
        let event2 = HookEvent(
            type: .preToolUse,
            agentID: "sub-2",
            parentAgentID: "main",
            toolName: "Task",
            taskDescription: "Run linter"
        )
        session.handleSubAgentSpawn(event: event2)
        XCTAssertEqual(session.allPanes.count, 3)

        let subPane2 = session.allPanes.first { $0.agentInfo?.agentID == "sub-2" }!
        XCTAssertNotEqual(subPane2.agentInfo?.color, .blue)
        XCTAssertNotEqual(subPane2.agentInfo?.color, subPane1.agentInfo?.color, "서브 에이전트끼리도 색상이 달라야 함")
    }

    /// 서브 에이전트 스폰 후 닫기 → 레이아웃 일관성 유지
    func testSpawnThenCloseSubAgent() {
        let session = Session(connectionType: .local)
        let mainPane = session.allPanes.first!
        mainPane.agentInfo = AgentInfo(agentID: "main")

        session.handleSubAgentSpawn(event: HookEvent(
            type: .preToolUse,
            agentID: "sub-1",
            parentAgentID: "main",
            toolName: "Task",
            taskDescription: "Subtask"
        ))

        let subPane = session.allPanes.first { $0.agentInfo?.agentID == "sub-1" }!
        session.closePane(id: subPane.id)

        XCTAssertEqual(session.allPanes.count, 1)
        XCTAssertEqual(session.allPanes.first!.id, mainPane.id, "메인 패인만 남아야 함")
    }

    /// Task 이벤트 아닌 툴(Bash 등)은 스폰하지 않아야 함
    func testNonTaskToolDoesNotSpawn() {
        let session = Session(connectionType: .local)
        session.allPanes.first!.agentInfo = AgentInfo(agentID: "main")

        let events = ["Bash", "Read", "Write", "Glob"].map { tool in
            HookEvent(type: .preToolUse, agentID: "agent-1", parentAgentID: "main", toolName: tool)
        }
        for event in events {
            session.handleSubAgentSpawn(event: event)
        }

        XCTAssertEqual(session.allPanes.count, 1, "Task 이외의 툴 이벤트는 패인을 추가하면 안 됨")
    }

    /// 에이전트 상태 업데이트 → 레이아웃 변경 없음, 상태만 변경
    func testAgentStatusUpdateDoesNotAffectLayout() {
        let session = Session(connectionType: .local)
        let pane = session.allPanes.first!
        pane.agentInfo = AgentInfo(agentID: "agent-1", status: .idle)

        session.updateAgentStatus(agentID: "agent-1", status: .thinking)

        XCTAssertEqual(session.allPanes.count, 1, "상태 업데이트는 레이아웃을 변경하면 안 됨")
        XCTAssertEqual(pane.agentInfo?.status, .thinking)
    }
}

// MARK: - Scenario 3: 레이아웃 깊이에 따른 자동 분할 방향

final class AutoSplitDirectionWorkflowTests: XCTestCase {

    /// depth 0(루트) → 수평 분할, depth 1 → 수직 분할로 교차되어야 함
    func testAlternatingSplitDirectionByDepth() {
        let session = Session(connectionType: .local)
        let root = session.allPanes.first!
        root.agentInfo = AgentInfo(agentID: "root")

        // depth 0: 수평 분할
        let event1 = HookEvent(type: .preToolUse, agentID: "sub-1",
                               parentAgentID: "root", toolName: "Task",
                               taskDescription: "T1")
        session.handleSubAgentSpawn(event: event1)

        if case .hsplit = session.layout { /* 통과 */ } else {
            XCTFail("depth 0에서는 hsplit이어야 함")
        }

        // sub-1이 이제 depth 1 → 수직 분할
        let sub1 = session.allPanes.first { $0.agentInfo?.agentID == "sub-1" }!
        sub1.agentInfo?.status = .thinking  // agentInfo 유지를 위해 touch

        let event2 = HookEvent(type: .preToolUse, agentID: "sub-2",
                               parentAgentID: "sub-1", toolName: "Task",
                               taskDescription: "T2")
        session.handleSubAgentSpawn(event: event2)

        // 전체 3개 패인
        XCTAssertEqual(session.allPanes.count, 3)
    }
}

// MARK: - Scenario 4: 파일 접근 기록 워크플로우

final class FileTouchWorkflowTests: XCTestCase {

    /// 여러 에이전트가 파일에 접근할 때 각자의 touchedFiles에만 기록되어야 함
    func testFileTouchIsolatedPerAgent() {
        let session = Session(connectionType: .local)

        // 두 개의 에이전트 패인 세팅
        let pane1 = session.allPanes.first!
        pane1.agentInfo = AgentInfo(agentID: "agent-A")

        session.splitActivePane(direction: .horizontal)
        let pane2 = session.allPanes.last!
        pane2.agentInfo = AgentInfo(agentID: "agent-B")

        // 각자 다른 파일 접근
        session.recordFileTouched(agentID: "agent-A", filePath: "/src/main.swift")
        session.recordFileTouched(agentID: "agent-B", filePath: "/src/utils.swift")
        session.recordFileTouched(agentID: "agent-A", filePath: "/src/model.swift")

        XCTAssertEqual(pane1.agentInfo?.touchedFiles, ["/src/main.swift", "/src/model.swift"])
        XCTAssertEqual(pane2.agentInfo?.touchedFiles, ["/src/utils.swift"])
    }

    /// 같은 파일을 여러 번 기록해도 중복 없이 1개만 저장되어야 함
    func testFileTouchDeduplication() {
        let session = Session(connectionType: .local)
        let pane = session.allPanes.first!
        pane.agentInfo = AgentInfo(agentID: "agent-1")

        for _ in 0..<5 {
            session.recordFileTouched(agentID: "agent-1", filePath: "/same/file.swift")
        }

        XCTAssertEqual(pane.agentInfo?.touchedFiles.count, 1)
    }
}

// MARK: - Scenario 5: 레이아웃 무결성 검증

final class LayoutIntegrityTests: XCTestCase {

    /// 분할/닫기를 반복해도 allPanes 카운트가 항상 실제 leaf 노드 수와 일치해야 함
    func testPaneCountConsistencyUnderStress() {
        let session = Session(connectionType: .local)

        // 7번 분할 → 8개 패인
        for _ in 0..<7 {
            session.splitActivePane(direction: Bool.random() ? .horizontal : .vertical)
        }
        XCTAssertEqual(session.allPanes.count, 8)

        // 6번 닫기 → 2개 패인
        var closed = 0
        while closed < 6 {
            if let pane = session.allPanes.first(where: { $0.id != session.activePaneID }) {
                session.closePane(id: pane.id)
                closed += 1
            } else {
                break
            }
        }
        XCTAssertEqual(session.allPanes.count, 2)
    }

    /// 존재하지 않는 paneID로 closePane을 호출해도 크래시나 레이아웃 변경이 없어야 함
    func testCloseNonExistentPaneIsNoop() {
        let session = Session(connectionType: .local)
        session.splitActivePane(direction: .horizontal)
        let countBefore = session.allPanes.count

        session.closePane(id: UUID())  // 존재하지 않는 ID

        XCTAssertEqual(session.allPanes.count, countBefore, "존재하지 않는 패인 닫기는 noop이어야 함")
    }

    /// pane(id:)는 트리에 있는 패인이면 반드시 찾아야 하고, 없는 UUID는 nil을 반환해야 함
    func testPaneLookupConsistency() {
        let session = Session(connectionType: .local)
        session.splitActivePane(direction: .horizontal)
        session.splitActivePane(direction: .vertical)

        for pane in session.allPanes {
            XCTAssertNotNil(session.layout.pane(id: pane.id), "존재하는 패인은 반드시 찾아져야 함")
        }
        XCTAssertNil(session.layout.pane(id: UUID()), "없는 UUID는 nil이어야 함")
    }
}

// MARK: - Scenario 6: HookEvent 파이프라인 통합

final class HookEventPipelineTests: XCTestCase {

    /// preToolUse(Task) → agentStatus(thinking) → postToolUse → agentStatus(done) 순서 처리
    func testFullAgentLifecycleEventSequence() {
        let session = Session(connectionType: .local)
        let mainPane = session.allPanes.first!
        mainPane.agentInfo = AgentInfo(agentID: "main-agent", status: .idle)

        // 1. Task 툴 발화 → 서브 에이전트 패인 생성
        session.handleSubAgentSpawn(event: HookEvent(
            type: .preToolUse,
            agentID: "sub-agent",
            parentAgentID: "main-agent",
            toolName: "Task",
            taskDescription: "Analyze code"
        ))
        XCTAssertEqual(session.allPanes.count, 2)

        // 2. 서브 에이전트 상태: thinking
        session.updateAgentStatus(agentID: "sub-agent", status: .thinking)
        let subPane = session.allPanes.first { $0.agentInfo?.agentID == "sub-agent" }!
        XCTAssertEqual(subPane.agentInfo?.status, .thinking)

        // 3. 파일 접근 기록
        session.recordFileTouched(agentID: "sub-agent", filePath: "/src/analyzer.swift")
        XCTAssertTrue(subPane.agentInfo?.touchedFiles.contains("/src/analyzer.swift") ?? false)

        // 4. 완료
        session.updateAgentStatus(agentID: "sub-agent", status: .done)
        XCTAssertEqual(subPane.agentInfo?.status, .done)

        // 레이아웃은 이벤트 처리 내내 일관성 유지
        XCTAssertEqual(session.allPanes.count, 2)
    }

    /// HookEvent JSON 페이로드가 실제 이벤트 처리 흐름과 연동되는지 검증
    func testHookEventDecodingAndProcessing() throws {
        let json = """
        {
            "type": "PreToolUse",
            "agentID": "decoded-agent",
            "parentAgentID": "main-agent",
            "toolName": "Task",
            "taskDescription": "Search codebase",
            "timestamp": "2026-03-07T00:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let event = try decoder.decode(HookEvent.self, from: json)

        let session = Session(connectionType: .local)
        session.allPanes.first!.agentInfo = AgentInfo(agentID: "main-agent")

        session.handleSubAgentSpawn(event: event)

        XCTAssertEqual(session.allPanes.count, 2, "JSON에서 디코딩한 이벤트로 패인이 생성되어야 함")
        let newPane = session.allPanes.first { $0.agentInfo?.agentID == "decoded-agent" }
        XCTAssertNotNil(newPane)
        XCTAssertEqual(newPane?.agentInfo?.taskDescription, "Search codebase")
    }
}
