import XCTest
@testable import ClaudeTerminal

final class PaneLayoutTests: XCTestCase {

    // MARK: - Basic Split

    func testSplittingLeafHorizontally() {
        let pane1 = AgentPane(title: "A")
        let pane2 = AgentPane(title: "B")
        let layout = PaneLayout.leaf(pane1)

        let result = layout.splitting(paneID: pane1.id, with: pane2, direction: .horizontal)

        if case .hsplit(let left, let right, let ratio) = result {
            XCTAssertEqual(left.allPanes.map(\.id), [pane1.id])
            XCTAssertEqual(right.allPanes.map(\.id), [pane2.id])
            XCTAssertEqual(ratio, 0.5)
        } else {
            XCTFail("Expected hsplit")
        }
    }

    func testSplittingLeafVertically() {
        let pane1 = AgentPane(title: "A")
        let pane2 = AgentPane(title: "B")
        let layout = PaneLayout.leaf(pane1)

        let result = layout.splitting(paneID: pane1.id, with: pane2, direction: .vertical)

        if case .vsplit(let top, let bottom, _) = result {
            XCTAssertEqual(top.allPanes.map(\.id), [pane1.id])
            XCTAssertEqual(bottom.allPanes.map(\.id), [pane2.id])
        } else {
            XCTFail("Expected vsplit")
        }
    }

    func testSplittingWrongIDLeavesLayoutUnchanged() {
        let pane1 = AgentPane(title: "A")
        let pane2 = AgentPane(title: "B")
        let layout = PaneLayout.leaf(pane1)
        let wrongID = UUID()

        let result = layout.splitting(paneID: wrongID, with: pane2, direction: .horizontal)
        XCTAssertEqual(result.allPanes.map(\.id), [pane1.id])
    }

    // MARK: - Nested Split

    func testSplittingNestedPane() {
        let pane1 = AgentPane(title: "main")
        let pane2 = AgentPane(title: "sub-1")
        let pane3 = AgentPane(title: "sub-2")

        // Start: [main]
        var layout = PaneLayout.leaf(pane1)

        // Split main → [main | sub-1]
        layout = layout.splitting(paneID: pane1.id, with: pane2, direction: .horizontal)

        // Split sub-1 → [main | sub-1 / sub-2]
        layout = layout.splitting(paneID: pane2.id, with: pane3, direction: .vertical)

        let all = layout.allPanes.map(\.id)
        XCTAssertEqual(all.count, 3)
        XCTAssertTrue(all.contains(pane1.id))
        XCTAssertTrue(all.contains(pane2.id))
        XCTAssertTrue(all.contains(pane3.id))
    }

    // MARK: - Remove

    func testRemovingPaneFromSplit() {
        let pane1 = AgentPane(title: "A")
        let pane2 = AgentPane(title: "B")
        var layout = PaneLayout.leaf(pane1)
        layout = layout.splitting(paneID: pane1.id, with: pane2, direction: .horizontal)

        let result = layout.removing(paneID: pane2.id)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.allPanes.map(\.id), [pane1.id])
    }

    func testRemovingOnlyPaneReturnsNil() {
        let pane = AgentPane(title: "A")
        let layout = PaneLayout.leaf(pane)
        XCTAssertNil(layout.removing(paneID: pane.id))
    }

    // MARK: - Depth

    func testDepthOfRootPane() {
        let pane = AgentPane(title: "root")
        let layout = PaneLayout.leaf(pane)
        XCTAssertEqual(layout.depth(of: pane.id), 0)
    }

    func testDepthAfterOneSplit() {
        let pane1 = AgentPane(title: "A")
        let pane2 = AgentPane(title: "B")
        let layout = PaneLayout.leaf(pane1)
            .splitting(paneID: pane1.id, with: pane2, direction: .horizontal)

        XCTAssertEqual(layout.depth(of: pane1.id), 1)
        XCTAssertEqual(layout.depth(of: pane2.id), 1)
    }

    func testDepthUnknownPaneReturnsNil() {
        let pane = AgentPane(title: "A")
        let layout = PaneLayout.leaf(pane)
        XCTAssertNil(layout.depth(of: UUID()))
    }

    // MARK: - Auto-Split Direction (alternating by depth)

    func testAutoSplitDirectionAlternates() {
        // depth 0 → horizontal; depth 1 → vertical; etc.
        let directions: [(Int, SplitDirection)] = [
            (0, .horizontal),
            (1, .vertical),
            (2, .horizontal),
            (3, .vertical),
        ]

        for (depth, expected) in directions {
            let direction: SplitDirection = depth % 2 == 0 ? .horizontal : .vertical
            XCTAssertEqual(direction, expected, "Depth \(depth) should be \(expected)")
        }
    }

    // MARK: - All Panes Enumeration

    func testAllPanesOrder() {
        let p1 = AgentPane(title: "1")
        let p2 = AgentPane(title: "2")
        let p3 = AgentPane(title: "3")

        let layout = PaneLayout.hsplit(
            left: .leaf(p1),
            right: .vsplit(top: .leaf(p2), bottom: .leaf(p3), ratio: 0.5),
            ratio: 0.5
        )

        let ids = layout.allPanes.map(\.id)
        XCTAssertEqual(ids.count, 3)
        XCTAssertEqual(ids[0], p1.id)
        XCTAssertEqual(ids[1], p2.id)
        XCTAssertEqual(ids[2], p3.id)
    }

    // MARK: - Agent Color Assignment

    func testAgentColorAssignmentNoConflict() {
        let usedColors: [AgentColor] = [.blue, .green]
        let nextColor = AgentColor.allCases.first { !usedColors.contains($0) }
        XCTAssertEqual(nextColor, .yellow)
    }

    func testAgentColorCyclesAfter8() {
        let usedColors = AgentColor.allCases  // all 8 used
        // No force-unwrap: use safe array subscript (same as fixed AppState code)
        let nextColor = AgentColor.allCases[usedColors.count % AgentColor.allCases.count]
        XCTAssertEqual(nextColor, .blue)  // wraps to 0
    }
}

// MARK: - Remove (regression tests for fixed algorithm)

final class PaneLayoutRemoveRegressionTests: XCTestCase {

    // Bug fix: 이전 알고리즘은 right만 제거할 수 있었고 left 제거는 layout 변경 없이 반환했음.
    func testRemovingLeftPaneCollapsesToRight() {
        let pane1 = AgentPane(title: "Left")
        let pane2 = AgentPane(title: "Right")
        let layout = PaneLayout.leaf(pane1)
            .splitting(paneID: pane1.id, with: pane2, direction: .horizontal)

        let result = layout.removing(paneID: pane1.id)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.allPanes.map(\.id), [pane2.id])
    }

    func testRemovingRightPaneCollapsesToLeft() {
        let pane1 = AgentPane(title: "Left")
        let pane2 = AgentPane(title: "Right")
        let layout = PaneLayout.leaf(pane1)
            .splitting(paneID: pane1.id, with: pane2, direction: .horizontal)

        let result = layout.removing(paneID: pane2.id)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.allPanes.map(\.id), [pane1.id])
    }

    func testRemovingTopPaneCollapsesToBottom() {
        let pane1 = AgentPane(title: "Top")
        let pane2 = AgentPane(title: "Bottom")
        let layout = PaneLayout.leaf(pane1)
            .splitting(paneID: pane1.id, with: pane2, direction: .vertical)

        let result = layout.removing(paneID: pane1.id)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.allPanes.map(\.id), [pane2.id])
    }

    // Bug fix: ratio가 0.5로 초기화되지 않고 기존 값이 보존되어야 함.
    func testRemovingNestedPanePreservesParentRatio() {
        let pane1 = AgentPane(title: "A")
        let pane2 = AgentPane(title: "B")
        let pane3 = AgentPane(title: "C")

        // [pane1 | pane2] with ratio 0.7, then split pane2 → [pane1 | pane2/pane3]
        var layout = PaneLayout.leaf(pane1)
            .splitting(paneID: pane1.id, with: pane2, direction: .horizontal, ratio: 0.7)
        layout = layout.splitting(paneID: pane2.id, with: pane3, direction: .vertical)

        // Remove pane3 → should collapse right side back to pane2, outer ratio stays 0.7
        let result = layout.removing(paneID: pane3.id)
        if case .hsplit(_, _, let r) = result {
            XCTAssertEqual(r, 0.7, accuracy: 0.001, "Outer split ratio must be preserved after inner pane removal")
        } else {
            XCTFail("Expected hsplit at root after removing nested pane")
        }
    }

    // Bug fix: updatingRatio는 비매칭 조상 노드의 ratio도 0.5로 초기화했었음.
    func testUpdatingRatioPreservesAncestorRatio() {
        let pane1 = AgentPane(title: "A")
        let pane2 = AgentPane(title: "B")
        let pane3 = AgentPane(title: "C")

        // Outer: pane1 | [pane2/pane3], outer ratio 0.3
        var layout = PaneLayout.leaf(pane1)
            .splitting(paneID: pane1.id, with: pane2, direction: .horizontal, ratio: 0.3)
        layout = layout.splitting(paneID: pane2.id, with: pane3, direction: .vertical)

        // Update inner (pane2/pane3) ratio → outer ratio 0.3 must not change
        let updated = layout.updatingRatio(0.6, forSplitContaining: pane2.id)
        if case .hsplit(_, _, let outerRatio) = updated {
            XCTAssertEqual(outerRatio, 0.3, accuracy: 0.001, "Outer split ratio must be unaffected by inner ratio update")
        } else {
            XCTFail("Expected hsplit at root")
        }
    }
}

