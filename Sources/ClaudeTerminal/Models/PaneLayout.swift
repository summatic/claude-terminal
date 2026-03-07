import Foundation

// MARK: - Pane

/// 단일 터미널 패인을 나타내는 클래스.
///
/// `PaneLayout` 이진 트리의 말단(leaf) 노드로 사용됩니다.
/// 에이전트 정보(`agentInfo`)를 보유하며 PTY 프로세스와 1:1 대응됩니다.
///
/// `ObservableObject`이므로 SwiftUI 뷰가 상태 변화에 자동으로 반응합니다.
final class AgentPane: ObservableObject, Identifiable {
    /// 패인의 고유 식별자. `PTYProcess` 딕셔너리의 키로도 사용됩니다.
    let id: UUID
    /// 이 패인에서 실행 중인 에이전트의 메타데이터. 일반 터미널이면 `nil`.
    @Published var agentInfo: AgentInfo?
    /// 헤더에 표시되는 탭 제목.
    @Published var title: String
    /// PTY 프로세스가 살아있는지 여부. 종료 시 `false`로 설정됩니다.
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

/// 세션의 연결 종류를 나타냅니다.
///
/// - `local`: 현재 Mac에서 실행 중인 Claude Code 프로세스
/// - `remote`: SSH를 통해 연결된 원격 서버의 Claude Code (WebSocket 이벤트 수신)
enum ConnectionType: Equatable {
    /// 로컬 PTY 프로세스 (기본값)
    case local
    /// SSH 원격 세션. `host`는 표시 이름, `sshPort`는 SSH 포트, `wsPort`는 이벤트 수신 포트.
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

/// 패인 분할 방향.
enum SplitDirection {
    /// 좌우 분할 — 왼쪽(기존) + 오른쪽(신규) `[A | B]`
    case horizontal
    /// 상하 분할 — 위쪽(기존) + 아래쪽(신규) `[A / B]`
    case vertical
}

// MARK: - Layout Node (Binary Split Tree)

/// 패인 레이아웃을 표현하는 이진 분할 트리.
///
/// 재귀적인 `indirect enum`으로 tmux 스타일의 레이아웃을 모델링합니다.
///
/// ```
/// PaneLayout
///   ├── .leaf(AgentPane)                 — 단일 패인
///   ├── .hsplit(left, right, ratio)      — 좌우 분할 [A | B]
///   └── .vsplit(top, bottom, ratio)      — 상하 분할 [A / B]
/// ```
///
/// 모든 변환 메서드(`splitting`, `removing`, `updatingRatio`)는
/// 불변(value-semantic) 방식으로 새 트리를 반환합니다.
indirect enum PaneLayout {
    /// 단일 패인 말단 노드
    case leaf(AgentPane)
    /// 좌우 분할. `ratio`는 왼쪽 패인의 비율 (0.0–1.0)
    case hsplit(left: PaneLayout, right: PaneLayout, ratio: CGFloat)
    /// 상하 분할. `ratio`는 위쪽 패인의 비율 (0.0–1.0)
    case vsplit(top: PaneLayout, bottom: PaneLayout, ratio: CGFloat)

    // MARK: Queries

    /// 트리에 포함된 모든 패인을 좌→우, 위→아래 순서로 반환합니다.
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

    /// 주어진 `id`를 가진 패인을 트리에서 찾아 반환합니다. 없으면 `nil`.
    func pane(id: UUID) -> AgentPane? {
        allPanes.first { $0.id == id }
    }

    /// 주어진 패인의 트리 깊이를 반환합니다.
    ///
    /// - 루트 패인(단독 leaf)의 깊이는 `0`
    /// - 분할할 때마다 깊이가 1씩 증가
    /// - 존재하지 않는 패인이면 `nil`
    ///
    /// 이 값을 이용해 자동 분할 방향을 결정합니다:
    /// 짝수 깊이 → `.horizontal`, 홀수 깊이 → `.vertical`
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

    /// 지정한 패인을 분할하여 기존 패인과 새 패인을 나란히 배치한 새 트리를 반환합니다.
    ///
    /// `paneID`를 가진 leaf를 찾아 해당 위치를 split 노드로 교체합니다.
    /// 일치하는 패인이 없으면 현재 트리를 그대로 반환합니다.
    ///
    /// - Parameters:
    ///   - paneID: 분할할 기존 패인의 ID
    ///   - newPane: 분할 후 추가될 새 패인
    ///   - direction: `.horizontal`(좌우) 또는 `.vertical`(상하)
    ///   - ratio: 기존 패인이 차지하는 비율 (기본값 0.5)
    /// - Returns: 분할이 적용된 새 `PaneLayout`
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

    /// 지정한 패인을 트리에서 제거하고 부모 split을 축소(collapse)한 새 트리를 반환합니다.
    ///
    /// - 제거할 패인이 split의 한 쪽이면 나머지 쪽이 부모 자리를 대체합니다.
    /// - 트리에 패인이 하나뿐이면(root leaf) 제거할 수 없으므로 `nil`을 반환합니다.
    ///
    /// - Parameter paneID: 제거할 패인의 ID
    /// - Returns: 패인이 제거된 새 트리, 또는 트리에 패인이 없으면 `nil`
    func removing(paneID: UUID) -> PaneLayout? {
        switch self {
        case .leaf(let pane):
            return pane.id == paneID ? nil : self

        case .hsplit(let left, let right, let r):
            if left.pane(id: paneID) != nil {
                // pane is in left subtree; nil means left was the sole leaf
                guard let newLeft = left.removing(paneID: paneID) else { return right }
                return .hsplit(left: newLeft, right: right, ratio: r)
            }
            if right.pane(id: paneID) != nil {
                guard let newRight = right.removing(paneID: paneID) else { return left }
                return .hsplit(left: left, right: newRight, ratio: r)
            }
            return self

        case .vsplit(let top, let bottom, let r):
            if top.pane(id: paneID) != nil {
                guard let newTop = top.removing(paneID: paneID) else { return bottom }
                return .vsplit(top: newTop, bottom: bottom, ratio: r)
            }
            if bottom.pane(id: paneID) != nil {
                guard let newBottom = bottom.removing(paneID: paneID) else { return top }
                return .vsplit(top: top, bottom: newBottom, ratio: r)
            }
            return self
        }
    }

    /// 지정한 패인을 포함하는 직접 부모 split 노드의 비율을 갱신한 새 트리를 반환합니다.
    ///
    /// 드래그 가능한 분할선(divider)을 사용자가 조작할 때 호출됩니다.
    /// 조상 노드가 아닌, 해당 패인의 **직접 부모** split에만 비율을 적용합니다.
    ///
    /// - Parameters:
    ///   - newRatio: 새 비율 (0.0–1.0; hsplit이면 왼쪽 비율, vsplit이면 위쪽 비율)
    ///   - paneID: 비율을 변경할 split 노드에 속한 패인의 ID
    /// - Returns: 비율이 갱신된 새 `PaneLayout`
    func updatingRatio(_ newRatio: CGFloat, forSplitContaining paneID: UUID) -> PaneLayout {
        switch self {
        case .leaf:
            return self

        case .hsplit(let left, let right, let r):
            if left.allPanes.contains(where: { $0.id == paneID }) ||
               right.allPanes.contains(where: { $0.id == paneID }) {
                return .hsplit(left: left, right: right, ratio: newRatio)
            }
            return .hsplit(
                left: left.updatingRatio(newRatio, forSplitContaining: paneID),
                right: right.updatingRatio(newRatio, forSplitContaining: paneID),
                ratio: r
            )

        case .vsplit(let top, let bottom, let r):
            if top.allPanes.contains(where: { $0.id == paneID }) ||
               bottom.allPanes.contains(where: { $0.id == paneID }) {
                return .vsplit(top: top, bottom: bottom, ratio: newRatio)
            }
            return .vsplit(
                top: top.updatingRatio(newRatio, forSplitContaining: paneID),
                bottom: bottom.updatingRatio(newRatio, forSplitContaining: paneID),
                ratio: r
            )
        }
    }
}
