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

/// `(agentID, filePath)` 배열을 디렉터리 트리 구조로 변환합니다.
private func buildTree(from files: [(agentID: String, filePath: String)]) -> [FileNode] {
    var root: [String: FileNode] = [:]

    for (agentID, filePath) in files {
        let components = filePath.split(separator: "/").map(String.init)
        guard !components.isEmpty else { continue }

        var currentDict = root
        var currentPath = ""

        for (index, component) in components.enumerated() {
            currentPath = currentPath.isEmpty ? component : "\(currentPath)/\(component)"
            let isLast = index == components.count - 1

            if var existing = currentDict[component] {
                if isLast {
                    existing.touchedByAgentIDs.append(agentID)
                }
                currentDict[component] = existing
            } else {
                var newNode = FileNode(
                    name: component,
                    fullPath: "/" + currentPath,
                    isDirectory: !isLast
                )
                if isLast {
                    newNode.touchedByAgentIDs.append(agentID)
                }
                currentDict[component] = newNode
            }

            if isLast { root = currentDict }
        }
    }

    return root.values.sorted { $0.name < $1.name }
}
