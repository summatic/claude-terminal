import Foundation

// MARK: - Pane

final class AgentPane: ObservableObject, Identifiable {
    let id: UUID
    @Published var agentInfo: AgentInfo?
    @Published var title: String
    @Published var isAlive: Bool = true

    // Connection info
    var connectionType: ConnectionType = .local

    init(
        id: UUID = UUID(),
        agentInfo: AgentInfo? = nil,
        title: String = "Terminal"
    ) {
        self.id = id
        self.agentInfo = agentInfo
        self.title = title
    }
}

extension AgentPane: Equatable {
    static func == (lhs: AgentPane, rhs: AgentPane) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Connection Type

enum ConnectionType: Equatable {
    case local
    case remote(host: String, sshPort: Int, wsPort: Int)

    var isRemote: Bool {
        if case .remote = self { return true }
        return false
    }

    var displayName: String {
        switch self {
        case .local: return "Local"
        case .remote(let host, _, _): return host
        }
    }
}

// MARK: - Split Direction

enum SplitDirection {
    case horizontal     // left | right
    case vertical       // top / bottom
}

// MARK: - Layout Node (Binary Split Tree)

indirect enum PaneLayout {
    case leaf(AgentPane)
    case hsplit(left: PaneLayout, right: PaneLayout, ratio: CGFloat)
    case vsplit(top: PaneLayout, bottom: PaneLayout, ratio: CGFloat)

    // MARK: Queries

    var allPanes: [AgentPane] {
        switch self {
        case .leaf(let pane):
            return [pane]
        case .hsplit(let left, let right, _):
            return left.allPanes + right.allPanes
        case .vsplit(let top, let bottom, _):
            return top.allPanes + bottom.allPanes
        }
    }

    func pane(id: UUID) -> AgentPane? {
        allPanes.first { $0.id == id }
    }

    func depth(of paneID: UUID, current: Int = 0) -> Int? {
        switch self {
        case .leaf(let pane):
            return pane.id == paneID ? current : nil
        case .hsplit(let left, let right, _):
            return left.depth(of: paneID, current: current + 1)
                ?? right.depth(of: paneID, current: current + 1)
        case .vsplit(let top, let bottom, _):
            return top.depth(of: paneID, current: current + 1)
                ?? bottom.depth(of: paneID, current: current + 1)
        }
    }

    // MARK: Mutations

    /// Replace a leaf pane with a split containing the original pane + new pane
    func splitting(
        paneID: UUID,
        with newPane: AgentPane,
        direction: SplitDirection,
        ratio: CGFloat = 0.5
    ) -> PaneLayout {
        switch self {
        case .leaf(let pane):
            guard pane.id == paneID else { return self }
            switch direction {
            case .horizontal:
                return .hsplit(left: .leaf(pane), right: .leaf(newPane), ratio: ratio)
            case .vertical:
                return .vsplit(top: .leaf(pane), bottom: .leaf(newPane), ratio: ratio)
            }

        case .hsplit(let left, let right, let r):
            return .hsplit(
                left: left.splitting(paneID: paneID, with: newPane, direction: direction, ratio: ratio),
                right: right.splitting(paneID: paneID, with: newPane, direction: direction, ratio: ratio),
                ratio: r
            )

        case .vsplit(let top, let bottom, let r):
            return .vsplit(
                top: top.splitting(paneID: paneID, with: newPane, direction: direction, ratio: ratio),
                bottom: bottom.splitting(paneID: paneID, with: newPane, direction: direction, ratio: ratio),
                ratio: r
            )
        }
    }

    /// Remove a pane, collapsing the parent split
    func removing(paneID: UUID) -> PaneLayout? {
        switch self {
        case .leaf(let pane):
            return pane.id == paneID ? nil : self

        case .hsplit(let left, let right, _):
            if let newLeft = left.removing(paneID: paneID) {
                return .hsplit(left: newLeft, right: right, ratio: 0.5)
            }
            if let newRight = right.removing(paneID: paneID) {
                return .hsplit(left: left, right: newRight, ratio: 0.5)
            }
            // pane was a direct child leaf
            let leftPanes = left.allPanes.filter { $0.id != paneID }
            let rightPanes = right.allPanes.filter { $0.id != paneID }
            if leftPanes.isEmpty { return right }
            if rightPanes.isEmpty { return left }
            return self

        case .vsplit(let top, let bottom, _):
            if let newTop = top.removing(paneID: paneID) {
                return .vsplit(top: newTop, bottom: bottom, ratio: 0.5)
            }
            if let newBottom = bottom.removing(paneID: paneID) {
                return .vsplit(top: top, bottom: newBottom, ratio: 0.5)
            }
            let topPanes = top.allPanes.filter { $0.id != paneID }
            let bottomPanes = bottom.allPanes.filter { $0.id != paneID }
            if topPanes.isEmpty { return bottom }
            if bottomPanes.isEmpty { return top }
            return self
        }
    }

    /// Update ratio of a split node containing the given pane
    func updatingRatio(_ newRatio: CGFloat, forSplitContaining paneID: UUID) -> PaneLayout {
        switch self {
        case .leaf:
            return self

        case .hsplit(let left, let right, _):
            if left.allPanes.contains(where: { $0.id == paneID }) ||
               right.allPanes.contains(where: { $0.id == paneID }) {
                return .hsplit(left: left, right: right, ratio: newRatio)
            }
            return .hsplit(
                left: left.updatingRatio(newRatio, forSplitContaining: paneID),
                right: right.updatingRatio(newRatio, forSplitContaining: paneID),
                ratio: 0.5
            )

        case .vsplit(let top, let bottom, _):
            if top.allPanes.contains(where: { $0.id == paneID }) ||
               bottom.allPanes.contains(where: { $0.id == paneID }) {
                return .vsplit(top: top, bottom: bottom, ratio: newRatio)
            }
            return .vsplit(
                top: top.updatingRatio(newRatio, forSplitContaining: paneID),
                bottom: bottom.updatingRatio(newRatio, forSplitContaining: paneID),
                ratio: 0.5
            )
        }
    }
}
