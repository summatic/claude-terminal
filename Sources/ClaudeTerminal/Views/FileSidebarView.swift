import SwiftUI

// MARK: - File Sidebar (Phase 11)

/// 에이전트들이 접근한 파일을 디렉터리 트리로 시각화하는 우측 사이드바.
///
/// `Session.allTouchedFiles`를 디렉터리 트리로 변환해 표시하며,
/// 에이전트별 색상 점으로 어떤 에이전트가 해당 파일에 접근했는지 구분합니다.
struct FileSidebarView: View {

    @ObservedObject var session: Session

    private var rootNodes: [FileNode] {
        buildTree(from: session.allTouchedFiles)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if rootNodes.isEmpty {
                emptyState
            } else {
                fileTree
            }
        }
        .frame(width: 260)
        .background(Color(white: 0.09))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Label("파일 접근", systemImage: "doc.text.magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))

            let totalFiles = session.allTouchedFiles.count
            if totalFiles > 0 {
                Text("\(totalFiles)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 28))
                .foregroundColor(.white.opacity(0.15))
            Text("접근한 파일 없음")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - File Tree

    private var fileTree: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(rootNodes) { node in
                    FileNodeRow(node: node, session: session, depth: 0)
                }
            }
            .padding(8)
        }
    }
}

// MARK: - File Node Model

struct FileNode: Identifiable {
    let id = UUID()
    let name: String
    let fullPath: String
    let isDirectory: Bool
    var children: [FileNode] = []
    /// 이 파일/디렉터리에 접근한 agentID 목록
    var touchedByAgentIDs: [String] = []
}

// MARK: - File Node Row

private struct FileNodeRow: View {

    let node: FileNode
    let session: Session
    let depth: Int

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                // 인덴트
                Spacer().frame(width: CGFloat(depth) * 10)

                // 아이콘
                Image(systemName: node.isDirectory ? (isExpanded ? "folder.fill" : "folder") : fileIcon(for: node.name))
                    .font(.system(size: 10))
                    .foregroundColor(node.isDirectory ? .blue.opacity(0.7) : .white.opacity(0.4))
                    .frame(width: 14)

                // 파일명
                Text(node.name)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)

                Spacer()

                // 에이전트 색상 점 (최대 4개)
                HStack(spacing: 2) {
                    ForEach(agentColors(for: node.touchedByAgentIDs).prefix(4), id: \.self) { color in
                        Circle()
                            .fill(color)
                            .frame(width: 5, height: 5)
                    }
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .background(Color.clear)
            .contentShape(Rectangle())
            .onTapGesture {
                if node.isDirectory { isExpanded.toggle() }
            }

            // 자식 노드 (디렉터리 펼쳐진 경우)
            if isExpanded {
                ForEach(node.children) { child in
                    FileNodeRow(node: child, session: session, depth: depth + 1)
                }
            }
        }
    }

    /// agentID 목록을 해당 에이전트의 SwiftUI Color로 변환
    private func agentColors(for agentIDs: [String]) -> [Color] {
        let uniqueIDs = Array(Set(agentIDs))
        return uniqueIDs.compactMap { agentID in
            session.allPanes
                .first { $0.agentInfo?.agentID == agentID }?
                .agentInfo?.color.swiftUIColor
        }
    }

    private func fileIcon(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "py": return "doc.text"
        case "md": return "doc.richtext"
        case "json": return "curlybraces"
        case "sh": return "terminal"
        default: return "doc"
        }
    }
}

// MARK: - Tree Builder

/// 내부 가변 트리 노드. 클래스(참조 타입)를 사용해 부모-자식 관계를 정확히 연결한다.
/// Swift Dictionary는 값 타입이라 중첩 변경이 부모에 반영되지 않으므로
/// 참조 타입 노드가 필수.
private final class MutableTreeNode {
    let name: String
    let fullPath: String
    let isDirectory: Bool
    var children: [String: MutableTreeNode] = [:]
    var touchedByAgentIDs: [String] = []

    init(name: String, fullPath: String, isDirectory: Bool) {
        self.name = name
        self.fullPath = fullPath
        self.isDirectory = isDirectory
    }

    func getOrCreate(component: String, fullPath: String, isDirectory: Bool) -> MutableTreeNode {
        if let existing = children[component] { return existing }
        let node = MutableTreeNode(name: component, fullPath: fullPath, isDirectory: isDirectory)
        children[component] = node
        return node
    }

    func toFileNode() -> FileNode {
        var node = FileNode(name: name, fullPath: fullPath, isDirectory: isDirectory)
        node.touchedByAgentIDs = touchedByAgentIDs
        node.children = children.values
            .sorted { $0.name < $1.name }
            .map { $0.toFileNode() }
        return node
    }
}

/// `(agentID, filePath)` 배열을 디렉터리 트리 구조로 변환합니다.
///
/// `MutableTreeNode` (클래스)로 내부 트리를 구성한 뒤 불변 `FileNode`로 변환합니다.
/// 이를 통해 Swift Dictionary 값 타입 한계(중첩 변경이 부모에 미반영)를 우회합니다.
private func buildTree(from files: [(agentID: String, filePath: String)]) -> [FileNode] {
    let root = MutableTreeNode(name: "", fullPath: "", isDirectory: true)

    for (agentID, filePath) in files {
        let components = filePath.split(separator: "/").filter { !$0.isEmpty }.map(String.init)
        guard !components.isEmpty else { continue }

        var current = root
        var pathSoFar = ""

        for (index, component) in components.enumerated() {
            pathSoFar += "/" + component
            let isLast = index == components.count - 1
            let child = current.getOrCreate(
                component: component,
                fullPath: pathSoFar,
                isDirectory: !isLast
            )
            if isLast {
                child.touchedByAgentIDs.append(agentID)
            }
            current = child
        }
    }

    return root.children.values
        .sorted { $0.name < $1.name }
        .map { $0.toFileNode() }
}
