# ClaudeTerminal — 추가 기능 구현 계획

> 기준일: 2026-03-07
> 현재 브랜치: `claude/mac-terminal-agent-viz-WYmJB`
> 완료된 Phase: 1(PTY), 2(멀티탭), 3(훅 통합), 4(SSH 원격), 4.5(테스트)

---

## 우선순위 요약

| # | Phase | 기능 | 난이도 | 수요 근거 | 변경 파일 수 |
|---|-------|------|--------|----------|------------|
| 1 | 7 | 드래그 가능한 분할선 | 낮음 | `updatingRatio` API 이미 구현됨 | 2 |
| 2 | 8 | 에이전트 메트릭 패널 | 낮음 | HN 수백 포인트, Usage Monitor 커뮤니티 툴 | 3 |
| 3 | 9 | 레이트 리밋 타이머 상태바 | 중간 | Claude Code 커뮤니티 1위 페인포인트 | 4 |
| 4 | 10 | 승인 요청 Activity Stream | 중간 | Issue #24537 핵심 요청 | 4 |
| 5 | 11 | 파일 접근 히트맵 사이드바 | 중간 | `touchedFiles` 데이터 이미 수집 중 | 3 |
| 6 | 12 | 세션별 Git 브랜치 표시 | 낮음 | cmux 벤치마크 기능 | 2 |

---

## Phase 7 — 드래그 가능한 분할선

### 목표
분할된 패인 사이의 경계선을 마우스로 드래그해 비율을 조절한다.

### 현재 상태
- `PaneLayout.updatingRatio(id:ratio:)` 메서드가 이미 구현됨 (`PaneLayout.swift`)
- `PaneSplitView`에서 `.hsplit` / `.vsplit` 렌더링 시 고정 비율 사용 중
- UI 제스처 없음

### 구현 내용

**`PaneSplitView.swift` 수정**

1. `hsplit(left, right, ratio)` 분기에서 HStack 사이 투명 드래그 핸들 삽입:
   ```swift
   // 기존: HStack { leftView; rightView }
   // 변경: HStack { leftView; DividerHandle(.horizontal); rightView }
   ```

2. `DividerHandle` View 신규 작성 (파일 내 private struct):
   ```swift
   private struct DividerHandle: View {
       let axis: Axis
       @Binding var layout: PaneLayout
       let splitNodeID: UUID  // 어느 split 노드의 ratio를 변경할지 식별
       @GestureState private var dragOffset: CGFloat = .zero

       var body: some View {
           Rectangle()
               .fill(Color.white.opacity(0.08))
               .frame(width: axis == .horizontal ? 4 : .infinity,
                      height: axis == .vertical ? 4 : .infinity)
               .cursor(axis == .horizontal ? .resizeLeftRight : .resizeUpDown)
               .gesture(DragGesture()
                   .updating($dragOffset) { value, state, _ in
                       state = axis == .horizontal ? value.translation.width
                                                   : value.translation.height
                   }
                   .onEnded { value in
                       // 부모 GeometryReader 크기 기반으로 새 ratio 계산
                       // layout.updatingRatio(id: splitNodeID, ratio: newRatio) 호출
                   }
               )
       }
   }
   ```

3. `PaneSplitView`가 `@Binding var layout: PaneLayout`을 받도록 시그니처 변경
4. `AppState`에서 `layout`을 `@Published`로 이미 관리 중 → Binding 전달만 추가

**`AppState.swift` 수정**

- `updatePaneRatio(sessionID:layoutID:ratio:)` 헬퍼 메서드 추가 (DragGesture onEnded에서 호출)

### 변경 파일
- `Sources/ClaudeTerminal/Views/PaneSplitView.swift`
- `Sources/ClaudeTerminal/AppState.swift`

### 테스트
- `LayoutTests.swift`에 `updatingRatio` 경계값 테스트 추가 (ratio 0.0, 0.1, 0.9, 1.0)

---

## Phase 8 — 에이전트 메트릭 패널

### 목표
각 패인 헤더 또는 하단 상태바에 에이전트별 툴 호출 횟수, 런타임, 비용 표시.

### 현재 상태
- `AgentInfo`에 `spawnedAt: Date`, `touchedFiles: Set<String>` 있음
- 툴 호출 횟수, 비용 필드 없음
- `AgentStatusBar`에 에이전트 이름/색상 pill만 표시

### 구현 내용

**`AgentEvent.swift` 수정**

`AgentInfo`에 필드 추가:
```swift
var toolCallCount: Int = 0
var tokenCount: Int = 0          // hook에서 수신 시 누적
var estimatedCostUSD: Double = 0.0
var lastToolName: String? = nil  // 최근 사용 툴 이름
```

`HookEvent`에 필드 추가:
```swift
var tokenUsage: Int? = nil       // postToolUse 시 누적 토큰
var costDelta: Double? = nil     // 해당 툴 호출의 비용 추정
```

**`AppState.swift` 수정**

`handleHookEvent()` 내 `postToolUse` 처리 시:
```swift
case .postToolUse:
    session.incrementToolCall(
        agentID: event.agentID,
        toolName: event.toolName,
        tokenDelta: event.tokenUsage ?? 0,
        costDelta: event.costDelta ?? 0.0
    )
```

**`AgentPaneView.swift` 수정**

패인 헤더에 메트릭 칩 추가:
```
[● thinking] [주 에이전트]  [🔧 12회] [⏱ 3m24s] [~$0.08]
```
- 런타임: `Date.now - agentInfo.spawnedAt` 실시간 타이머
- 툴 호출: `agentInfo.toolCallCount`
- 비용: `agentInfo.estimatedCostUSD` (API 사용자만 해당, Pro/Max는 "--")

**`hook-notify.py` 수정**

`postToolUse` 전송 시 `token_usage`, `cost_delta` 필드 포함 (Claude Code API 응답 헤더에서 파싱):
```python
# 환경변수 CLAUDE_TOKEN_USAGE, CLAUDE_COST_DELTA 읽기 (향후 Claude Code 지원 시)
```

### 변경 파일
- `Sources/ClaudeTerminal/Models/AgentEvent.swift`
- `Sources/ClaudeTerminal/Views/AgentPaneView.swift`
- `Sources/ClaudeTerminal/AppState.swift`

---

## Phase 9 — 레이트 리밋 타이머 상태바

### 목표
Claude Code 레이트 리밋 도달 시 남은 대기 시간을 하단 상태바에 카운트다운으로 표시.

### 현재 상태
- `AgentStatusBar`에 에이전트 pill만 있음
- 레이트 리밋 정보 수신 경로 없음

### 구현 내용

**레이트 리밋 감지 방식**

Claude Code는 레이트 리밋 도달 시 터미널에 고정 형식 출력:
```
⚠️  API Error 429: Rate limited. Resets at 2026-03-07T15:32:00Z
```

PTY 출력 스트림에서 이 패턴을 파싱 → AppState에 `rateLimitResetAt: Date?` 저장.

대안: `hook-notify.py`에 레이트 리밋 전용 이벤트 타입 추가 (`rateLimited`).

**`AgentEvent.swift` 수정**

`HookEventType`에 케이스 추가:
```swift
case rateLimited   // 레이트 리밋 도달 시
```

**`AppState.swift` 수정**

```swift
@Published var rateLimitResetAt: Date? = nil
@Published var affectedSessionID: UUID? = nil

// PTY 출력 파싱 or 훅 이벤트 수신 시
func handleRateLimit(resetAt: Date, sessionID: UUID) {
    rateLimitResetAt = resetAt
    affectedSessionID = sessionID
    // 타이머 시작: resetAt 도달 시 nil로 클리어
}
```

**`AgentStatusBar.swift` 수정**

상태바 우측에 레이트 리밋 타이머 컴포넌트 추가:
```
[에이전트 pills ...]    [⏸ 레이트 리밋: 14:32 후 해제]
```

```swift
private struct RateLimitBadge: View {
    let resetAt: Date
    @State private var remaining: TimeInterval = 0
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "pause.circle.fill").foregroundColor(.orange)
            Text(formattedRemaining)
                .monospacedDigit()
                .foregroundColor(.orange)
        }
        .onReceive(timer) { _ in remaining = resetAt.timeIntervalSinceNow }
    }
}
```

**`hook-notify.py` 수정**

Claude Code 오류 메시지 파싱:
```python
import re, sys
RATE_LIMIT_PATTERN = re.compile(r'Resets at (\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)')

def detect_rate_limit(stderr_line: str) -> str | None:
    m = RATE_LIMIT_PATTERN.search(stderr_line)
    return m.group(1) if m else None
```

또는 Claude Code `Stop` 훅에서 `CLAUDE_RATE_LIMIT_RESET` 환경변수 읽기.

### 변경 파일
- `Sources/ClaudeTerminal/Models/AgentEvent.swift`
- `Sources/ClaudeTerminal/Views/AgentStatusBar.swift`
- `Sources/ClaudeTerminal/AppState.swift`
- `Sources/ClaudeTerminal/Resources/hook-notify.py`

---

## Phase 10 — 승인 요청 Activity Stream

### 목표
모든 에이전트의 승인 요청(PermissionRequest)을 메인 대화 흐름과 분리된 사이드 패널에서 순서대로 처리.

### 현재 상태
- `HookEventType`에 `permissionRequest` 케이스 없음
- 승인 요청 UI 없음

### 구현 내용

**`AgentEvent.swift` 수정**

```swift
// HookEventType에 추가
case permissionRequest  // 도구 실행 전 사용자 승인 필요

// 새 모델 추가
struct PermissionRequest: Identifiable, Codable {
    let id: UUID
    let agentID: String
    let toolName: String
    let toolInput: [String: String]
    let requestedAt: Date
    var isResolved: Bool = false
    var wasApproved: Bool? = nil
}
```

**`AppState.swift` 수정**

```swift
@Published var pendingPermissions: [PermissionRequest] = []
@Published var showActivityStream: Bool = false

func handlePermissionRequest(_ event: HookEvent) {
    let req = PermissionRequest(
        id: UUID(),
        agentID: event.agentID,
        toolName: event.toolName ?? "unknown",
        toolInput: event.toolInput ?? [:],
        requestedAt: event.timestamp
    )
    pendingPermissions.append(req)
    showActivityStream = true  // 자동으로 사이드바 열기
}

func resolvePermission(id: UUID, approved: Bool) {
    // IPC로 응답 전송 (향후 양방향 IPC 구현 시)
    pendingPermissions.removeAll { $0.id == id }
}
```

**`ActivityStreamView.swift` 신규 작성**

```swift
struct ActivityStreamView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 헤더
            HStack {
                Text("승인 요청").font(.headline)
                Spacer()
                Badge(count: appState.pendingPermissions.count)
                Button("닫기") { appState.showActivityStream = false }
            }
            .padding(12)

            Divider()

            // 요청 목록
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(appState.pendingPermissions) { req in
                        PermissionCard(request: req)
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 320)
        .background(.ultraThinMaterial)
    }
}

private struct PermissionCard: View {
    let request: PermissionRequest
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                AgentColorDot(agentID: request.agentID)
                Text(request.agentID.prefix(8)).font(.caption).foregroundColor(.secondary)
                Spacer()
                Text(request.requestedAt, style: .relative).font(.caption2)
            }
            Text("🔧 \(request.toolName)").font(.subheadline).bold()
            // 주요 입력 파라미터 표시 (최대 2줄)
            ForEach(Array(request.toolInput.prefix(2)), id: \.key) { key, value in
                Text("\(key): \(value)").font(.caption).lineLimit(1)
            }
            HStack {
                Button("승인") { appState.resolvePermission(id: request.id, approved: true) }
                    .buttonStyle(.borderedProminent).tint(.green)
                Button("거절") { appState.resolvePermission(id: request.id, approved: false) }
                    .buttonStyle(.bordered).tint(.red)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
    }
}
```

**`ContentView.swift` 수정**

Activity Stream을 우측 사이드바로 추가:
```swift
HStack(spacing: 0) {
    SessionWorkspaceView(...)
    if appState.showActivityStream {
        Divider()
        ActivityStreamView()
            .transition(.move(edge: .trailing))
    }
}
.animation(.easeInOut(duration: 0.2), value: appState.showActivityStream)
```

키보드 단축키: `Cmd+Shift+A` → `showActivityStream.toggle()`

### 변경 파일
- `Sources/ClaudeTerminal/Models/AgentEvent.swift`
- `Sources/ClaudeTerminal/AppState.swift`
- `Sources/ClaudeTerminal/Views/ContentView.swift`
- `Sources/ClaudeTerminal/Views/ActivityStreamView.swift` (신규)

---

## Phase 11 — 파일 접근 히트맵 사이드바

### 목표
에이전트들이 접근한 파일을 디렉터리 트리 형태로 시각화. 에이전트별 색상 코딩.

### 현재 상태
- `AgentInfo.touchedFiles: Set<String>` 이미 수집 중
- `Session.recordFileTouched(agentID:filePath:)` 이미 구현
- UI 없음

### 구현 내용

**`FileSidebarView.swift` 신규 작성**

```swift
struct FileSidebarView: View {
    let session: Session

    // Set<String> → 트리 구조로 변환
    private var fileTree: [FileNode] { buildTree(from: session.allTouchedFiles) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("파일 접근").font(.headline).padding(12)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(fileTree) { node in
                        FileNodeRow(node: node, session: session)
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 260)
        .background(.ultraThinMaterial)
    }
}

struct FileNode: Identifiable {
    let id = UUID()
    let name: String        // 파일/디렉터리 이름
    let fullPath: String
    let isDirectory: Bool
    var children: [FileNode] = []
    var touchedByAgents: [String] = []  // agentID 목록
}

private struct FileNodeRow: View {
    let node: FileNode
    let session: Session
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                // 인덴트 (depth 기반)
                Image(systemName: node.isDirectory ? "folder.fill" : "doc.text.fill")
                    .foregroundColor(node.isDirectory ? .blue : .secondary)
                    .font(.caption)
                Text(node.name).font(.caption).lineLimit(1)
                Spacer()
                // 에이전트 색상 도트 (최대 3개)
                AgentColorDots(agentIDs: node.touchedByAgents, session: session)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .onTapGesture { if node.isDirectory { isExpanded.toggle() } }

            if isExpanded && node.isDirectory {
                ForEach(node.children) { child in
                    FileNodeRow(node: child, session: session)
                        .padding(.leading, 12)
                }
            }
        }
    }
}
```

**`Session.swift` 수정**

`allTouchedFiles` 집계 프로퍼티 추가:
```swift
// 모든 패인의 에이전트 touchedFiles 집합: [(agentID, filePath)]
var allTouchedFiles: [(agentID: String, filePath: String)] {
    allPanes.compactMap { $0.agentInfo }.flatMap { info in
        info.touchedFiles.map { (info.agentID, $0) }
    }
}
```

**`ContentView.swift` 수정**

파일 사이드바 토글 버튼을 `SessionTabBar` 우측에 추가:
```swift
Button { showFileSidebar.toggle() } label: {
    Image(systemName: "sidebar.right")
}
```

키보드 단축키: `Cmd+Shift+F`

### 변경 파일
- `Sources/ClaudeTerminal/Models/Session.swift`
- `Sources/ClaudeTerminal/Views/ContentView.swift`
- `Sources/ClaudeTerminal/Views/FileSidebarView.swift` (신규)

---

## Phase 12 — 세션별 Git 브랜치 표시

### 목표
탭바의 각 세션 탭에 현재 작업 디렉터리의 Git 브랜치 이름 표시.

### 현재 상태
- `SessionTab` 뷰에 연결 상태 dot, 세션 이름, 에이전트 수 badge만 있음
- `Session` 모델에 `workingDirectory: String?` 없음

### 구현 내용

**`Session.swift` 수정**

```swift
@Published var gitBranch: String? = nil
@Published var workingDirectory: String? = nil

func refreshGitBranch() {
    guard let cwd = workingDirectory else { return }
    Task.detached {
        let branch = try? await Self.readGitBranch(in: cwd)
        await MainActor.run { self.gitBranch = branch }
    }
}

private static func readGitBranch(in directory: String) async throws -> String? {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    proc.arguments = ["-C", directory, "rev-parse", "--abbrev-ref", "HEAD"]
    proc.currentDirectoryURL = URL(fileURLWithPath: directory)
    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError = Pipe()  // 오류 무시
    try proc.run()
    proc.waitUntilExit()
    guard proc.terminationStatus == 0 else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
}
```

PTY 시작 시 작업 디렉터리 감지: `PTYProcess`가 실행 경로 저장 → `Session.workingDirectory`에 전달.

브랜치 갱신 타이밍:
- 세션 생성 시 1회
- 5분마다 자동 갱신 (`Timer.scheduledTimer`)
- `Cmd+R` (수동 갱신)

**`SessionTabBar.swift` 수정**

`SessionTab` 내 세션 이름 아래에 브랜치 표시:
```swift
VStack(alignment: .leading, spacing: 2) {
    Text(session.name).font(.caption).bold()
    if let branch = session.gitBranch {
        HStack(spacing: 3) {
            Image(systemName: "arrow.triangle.branch").font(.system(size: 9))
            Text(branch).font(.system(size: 10)).foregroundColor(.secondary)
        }
    }
}
```

### 변경 파일
- `Sources/ClaudeTerminal/Models/Session.swift`
- `Sources/ClaudeTerminal/Views/SessionTabBar.swift`

---

## 전체 구현 순서

```
Phase 7 → Phase 12 → Phase 8 → Phase 9 → Phase 10 → Phase 11
(쉬움)    (쉬움)     (보통)    (보통)     (보통)      (보통)
```

이유:
- 7, 12는 기존 인프라 완전 활용, 새 파일 없음
- 8은 모델 변경이 크지 않고 UI 변경 최소
- 9, 10, 11은 새 View 파일 생성 + 모델 변경 동반

---

## 각 Phase 후 체크리스트

- [ ] `swift build` 성공
- [ ] `swift test` 통과 (기존 테스트 회귀 없음)
- [ ] 새 기능 유닛 테스트 작성
- [ ] 커밋 후 `git push -u origin claude/mac-terminal-agent-viz-WYmJB`
