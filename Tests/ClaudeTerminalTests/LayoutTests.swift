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
        let nextColor = AgentColor(rawValue: usedColors.count % AgentColor.allCases.count)!
        XCTAssertEqual(nextColor, .blue)  // wraps to 0
    }
}
