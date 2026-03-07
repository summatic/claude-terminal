# ClaudeTerminal

macOS 네이티브 터미널 앱 — Claude Code의 멀티세션과 서브에이전트 자동 분할 시각화를 지원합니다.

## 주요 기능

| 기능 | 설명 |
|------|------|
| **멀티세션** | tmux처럼 독립적인 세션 탭 전환 (Cmd+T, Cmd+1~9) |
| **자동 분할** | Claude Code가 `Task` 툴로 서브에이전트 생성 시 화면 자동 분할 |
| **에이전트 시각화** | 에이전트별 색상 도트·상태 애니메이션 (thinking/writing/running/done) |
| **원격 서버 연동** | SSH 서버에서 실행 중인 Claude Code도 연동 가능 |

---

## 아키텍처

```
┌──────────────────────────────────────────────────────────┐
│                  ClaudeTerminal.app                      │
│                                                          │
│  AppState (@MainActor)                                   │
│  ├── [Session]  ←→  PaneLayout (Binary Split Tree)       │
│  │     └── [AgentPane]  ←→  PTYProcess (POSIX PTY)       │
│  │                                                       │
│  ├── IPCServer   ← Unix Socket ← 로컬 훅 스크립트         │
│  └── WebSocketEventServer ← HTTP POST ← 서버 훅          │
│                                                          │
│  SwiftUI Views                                           │
│  └── ContentView → SessionTabBar + PaneSplitView         │
│        └── AgentPaneView → TerminalViewRepresentable     │
│              └── SwiftTerm (ANSI 터미널 에뮬레이터)       │
└──────────────────────────────────────────────────────────┘
```

### 레이아웃 엔진: 이진 분할 트리

```
PaneLayout
  ├── .leaf(AgentPane)          — 단일 패인
  ├── .hsplit(left, right, ratio)  — 가로 분할 [A | B]
  └── .vsplit(top, bottom, ratio)  — 세로 분할 [A / B]
```

서브에이전트 생성 시 자동 분할 알고리즘:
- **짝수 깊이** → 가로 분할 (좌우)
- **홀수 깊이** → 세로 분할 (상하)

### 에이전트 이벤트 흐름

```
[Claude Code] → PreToolUse Hook (tool_name="Task")
                      │
             hook-notify.py 실행
                      │
       ┌──────────────┴──────────────┐
  로컬 │                             │ 원격
  Unix Socket                  HTTP POST
  + HMAC-SHA256               + Bearer Token
  /tmp/../ipc-{pid}.sock      localhost:9901
       │                             │
       └──────────────┬──────────────┘
                      ▼
             IPCServer / WebSocketEventServer
                      │
             AppState.handleHookEvent()
                      │
             withAnimation { layout.splitting() }
                      ▼
             새 AgentPane 자동 생성 + PTY 실행
```

---

## 빌드

**요구사항:** macOS 13+, Xcode 15+, Swift 5.9+

```bash
cd tools/claude-terminal

# 의존성 가져오기 (SwiftTerm)
swift package resolve

# 빌드
swift build

# 테스트 실행
swift test

# Xcode로 열기
open Package.swift
```

---

## 훅 스크립트 설치

Claude Code가 서브에이전트를 생성할 때 앱에 알림을 보내는 훅 스크립트를 설치합니다.

### 1. 스크립트 복사

```bash
cp Sources/ClaudeTerminal/Resources/hook-notify.py ~/.claude/hooks/notify-terminal.py
chmod +x ~/.claude/hooks/notify-terminal.py
```

### 2. Claude Code 훅 설정

`~/.claude/settings.json` 편집:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Task",
        "hooks": [
          {
            "type": "command",
            "command": "python3 ~/.claude/hooks/notify-terminal.py"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": ".*",
        "hooks": [
          {
            "type": "command",
            "command": "python3 ~/.claude/hooks/notify-terminal.py"
          }
        ]
      }
    ]
  }
}
```

### 3. 앱 실행

앱을 실행하면 자동으로 다음이 생성됩니다:
- `~/Library/Application Support/ClaudeTerminal/ipc-{pid}.sock` (mode 0600)
- `~/.claude-terminal.pid` — 소켓 경로 + HMAC 키 (mode 0600)

이후 Claude Code에서 서브에이전트가 생성될 때마다 화면이 자동 분할됩니다.

---

## 원격 서버 연동

서버에서 실행 중인 Claude Code를 연동하려면 SSH 터널을 사용합니다.

### 1. SSH 터널 설정

Mac에서:
```bash
# 서버의 9901 포트를 Mac의 9901로 포워딩
ssh -R 9901:localhost:9901 user@your-server.com
```

### 2. 서버 환경 변수 설정

서버에서:
```bash
export CLAUDE_TERMINAL_REMOTE=1
export CLAUDE_TERMINAL_HOST=127.0.0.1   # SSH 터널 경유
export CLAUDE_TERMINAL_WS_PORT=9901
export CLAUDE_TERMINAL_TOKEN=<앱에서 표시되는 토큰>
```

Bearer 토큰은 앱 실행 시 생성되며, Preferences 창 또는 콘솔 로그에서 확인합니다.

### 3. 서버에 훅 스크립트 설치

```bash
# 서버에 스크립트 복사
scp Sources/ClaudeTerminal/Resources/hook-notify.py user@server:~/.claude/hooks/
ssh user@server "chmod +x ~/.claude/hooks/notify-terminal.py"
```

서버의 `~/.claude/settings.json` 동일하게 설정.

---

## 키보드 단축키

| 단축키 | 동작 |
|--------|------|
| `Cmd+T` | 새 로컬 세션 |
| `Cmd+Shift+T` | 새 원격 세션 (SSH) |
| `Cmd+W` | 현재 세션 닫기 |
| `Cmd+1` ~ `Cmd+9` | 세션 전환 |
| `Cmd+D` | 현재 패인 가로 분할 |
| `Cmd+Shift+D` | 현재 패인 세로 분할 |
| `Cmd+Shift+K` | 현재 패인 닫기 |

---

## 보안 모델

| 레이어 | 보안 조치 |
|--------|----------|
| **로컬 IPC** | Unix Socket, mode 0600, HMAC-SHA256 서명 필수 |
| **원격 이벤트** | loopback 전용 바인딩, 32바이트 Bearer 토큰, constant-time 비교 |
| **파일 경로** | 절대경로 필수, `..` 거부, `/etc/` `/usr/` 등 시스템 경로 차단 |
| **URL 열기** | `http`/`https` 스킴만 허용 (`file://`, `javascript:` 차단) |
| **SSH 연결** | 포트 1–65535 범위 검증, 호스트 제어문자 거부 |
| **PTY 정리** | `deinit`에서 FD 해제 + 자식 프로세스 종료 보장 |

---

## 파일 구조

```
tools/claude-terminal/
├── Package.swift                        # SPM 패키지 정의 (SwiftTerm 의존성)
├── README.md                            # 이 파일
├── Sources/ClaudeTerminal/
│   ├── ClaudeTerminalApp.swift          # @main 진입점, 키보드 단축키
│   ├── AppState.swift                   # 앱 전체 상태 관리 (@MainActor)
│   ├── Validation.swift                 # 보안 검증 함수 (경로, 포트, 호스트, URL)
│   ├── Models/
│   │   ├── AgentEvent.swift             # HookEvent, AgentInfo, AgentStatus, AgentColor
│   │   ├── PaneLayout.swift             # 이진 분할 트리, AgentPane, ConnectionType
│   │   └── Session.swift                # 세션 (탭 단위), 자동 분할 로직
│   ├── Terminal/
│   │   ├── PTYProcess.swift             # POSIX PTY 래퍼 (posix_openpt)
│   │   └── IPCServer.swift              # Unix Socket + WebSocket 서버
│   ├── Views/
│   │   ├── ContentView.swift            # 루트 뷰, 세션 전환, 원격 연결 시트
│   │   ├── SessionTabBar.swift          # 상단 세션 탭바
│   │   ├── PaneSplitView.swift          # 재귀 레이아웃 렌더러
│   │   ├── AgentPaneView.swift          # 패인 헤더 + 터미널 + 상태 도트
│   │   ├── AgentStatusBar.swift         # 하단 에이전트 상태 바
│   │   └── TerminalViewRepresentable.swift  # SwiftTerm NSViewRepresentable
│   └── Resources/
│       └── hook-notify.py               # 훅 스크립트 (로컬/원격 모드)
└── Tests/ClaudeTerminalTests/
    ├── LayoutTests.swift                 # 레이아웃 엔진 테스트
    ├── SecurityValidationTests.swift     # 보안 검증 테스트 (Path/Port/Host/URL)
    ├── DataHexTests.swift               # HMAC 키·Bearer 토큰 인코딩 테스트
    ├── HookEventTests.swift             # HookEvent Codable 테스트
    └── SessionPaneTests.swift           # 세션·패인·에이전트 테스트
```

---

## 구현 단계 (로드맵)

- [x] **Phase 1** — PTY + 단일 터미널 패인
- [x] **Phase 2** — 멀티세션 탭바 + 레이아웃 엔진
- [x] **Phase 3** — 훅 연동 + 자동 분할
- [x] **Phase 4** — 원격 SSH 세션 + WebSocket 서버
- [ ] **Phase 5** — 파일트리 사이드바 + 개미 애니메이션
- [ ] **Phase 6** — 설정 창, 온보딩, 앱 배포

---

## 의존성

| 패키지 | 버전 | 용도 |
|--------|------|------|
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | ≥ 1.2.0 | ANSI/VT100 터미널 에뮬레이터 |
| Apple CryptoKit | (내장) | HMAC-SHA256 서명 |
| Apple Network | (내장) | NWListener (Unix Socket / TCP) |
