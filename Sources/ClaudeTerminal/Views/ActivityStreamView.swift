import SwiftUI

// MARK: - Activity Stream (Phase 10)

/// 모든 에이전트의 승인 요청을 순서대로 표시하는 우측 사이드바.
///
/// `AppState.pendingPermissions`를 관찰하며, 에이전트가 `PermissionRequest` 이벤트를
/// 전송하면 자동으로 열립니다. 승인/거절 버튼 클릭 시 해당 항목을 목록에서 제거합니다.
struct ActivityStreamView: View {

    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if appState.pendingPermissions.isEmpty {
                emptyState
            } else {
                requestList
            }
        }
        .frame(width: 300)
        .background(Color(white: 0.09))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Label("승인 요청", systemImage: "hand.raised.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))

            if !appState.pendingPermissions.isEmpty {
                Text("\(appState.pendingPermissions.count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.orange)
                    .clipShape(Capsule())
            }

            Spacer()

            Button {
                appState.showActivityStream = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 28))
                .foregroundColor(.white.opacity(0.15))
            Text("대기 중인 요청 없음")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Request List

    private var requestList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(appState.pendingPermissions) { req in
                    PermissionCard(request: req, appState: appState)
                }
            }
            .padding(8)
        }
    }
}

// MARK: - Permission Card

private struct PermissionCard: View {

    let request: PermissionRequest
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Agent ID + time
            HStack {
                Text(request.agentID.prefix(8))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
                Text(request.requestedAt, style: .relative)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
            }

            // Tool name
            Label(request.toolName, systemImage: toolIcon(for: request.toolName))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))

            // Key inputs (max 3 lines)
            ForEach(Array(request.toolInput.prefix(3)), id: \.key) { key, value in
                HStack(alignment: .top, spacing: 4) {
                    Text(key)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(width: 60, alignment: .leading)
                    Text(value)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.65))
                        .lineLimit(2)
                }
            }

            // Action buttons
            HStack(spacing: 6) {
                Button("승인") {
                    appState.resolvePermission(id: request.id)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .buttonStyle(.plain)

                Button("거절") {
                    appState.resolvePermission(id: request.id)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.25), lineWidth: 0.5)
        )
    }

    private func toolIcon(for toolName: String) -> String {
        switch toolName.lowercased() {
        case "bash": return "terminal"
        case "write", "edit", "notebookedit": return "pencil.line"
        case "read": return "doc.text"
        case "websearch": return "magnifyingglass"
        case "task": return "cpu"
        default: return "wrench.and.screwdriver"
        }
    }
}
