#!/usr/bin/env python3
"""
ClaudeTerminal Hook Notification Script
Install: cp hook-notify.py ~/.claude/hooks/notify-terminal.py

Configure ~/.claude/settings.json:
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Task",
      "hooks": [{"type": "command", "command": "python3 ~/.claude/hooks/notify-terminal.py"}]
    }],
    "PostToolUse": [{
      "matcher": ".*",
      "hooks": [{"type": "command", "command": "python3 ~/.claude/hooks/notify-terminal.py"}]
    }]
  }
}

For REMOTE servers, set environment variables:
  CLAUDE_TERMINAL_REMOTE=1
  CLAUDE_TERMINAL_HOST=127.0.0.1  (always use SSH tunnel, see below)
  CLAUDE_TERMINAL_WS_PORT=9901
  CLAUDE_TERMINAL_TOKEN=<bearer token from app>

SSH tunnel (required for remote mode; app binds to localhost only):
  ssh -R 9901:localhost:9901 user@server
"""

import sys
import json
import socket
import struct
import hmac
import hashlib
import os
import re
from datetime import datetime, timezone

# ── Configuration ──────────────────────────────────────────────────────────────

PID_FILE = os.path.expanduser("~/.claude-terminal.pid")
TIMEOUT_SECONDS = 0.3  # Non-blocking

# Remote mode — only via SSH tunnel (app binds to 127.0.0.1)
IS_REMOTE = os.environ.get("CLAUDE_TERMINAL_REMOTE", "") == "1"
REMOTE_HOST = os.environ.get("CLAUDE_TERMINAL_HOST", "127.0.0.1")
REMOTE_WS_PORT = int(os.environ.get("CLAUDE_TERMINAL_WS_PORT", "9901"))
REMOTE_TOKEN = os.environ.get("CLAUDE_TERMINAL_TOKEN", "")

# ── Input Validation ───────────────────────────────────────────────────────────

# Valid hostname/IP pattern (prevents header injection)
_SAFE_HOST_RE = re.compile(r'^[a-zA-Z0-9.\-]{1,253}$')

def validate_host(host: str) -> str:
    """Validate host is a safe hostname or IP. Raises ValueError if not."""
    if not _SAFE_HOST_RE.match(host):
        raise ValueError(f"Unsafe REMOTE_HOST: {host!r}")
    return host

def sanitize_string(s: str, max_len: int = 4096) -> str:
    """Remove control characters and truncate."""
    cleaned = re.sub(r'[\x00-\x1f\x7f]', '', s)
    return cleaned[:max_len]

# ── Read hook context ──────────────────────────────────────────────────────────

def read_stdin_json() -> dict:
    try:
        raw = sys.stdin.read()
        return json.loads(raw) if raw.strip() else {}
    except Exception:
        return {}

# ── Build event ───────────────────────────────────────────────────────────────

def build_event(hook_data: dict) -> dict:
    hook_type = os.environ.get("CLAUDE_HOOK_TYPE", "PreToolUse")
    tool_name = hook_data.get("tool_name", "")
    tool_input = hook_data.get("tool_input", {})
    session_id = hook_data.get("session_id", "")
    agent_id = hook_data.get("agent_id", session_id)
    parent_agent_id = hook_data.get("parent_agent_id")

    event = {
        "type": hook_type,
        "agentID": sanitize_string(str(agent_id), 256),
        "parentAgentID": sanitize_string(str(parent_agent_id), 256) if parent_agent_id else None,
        "sessionID": sanitize_string(str(session_id), 256),
        "toolName": sanitize_string(str(tool_name), 128),
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }

    if tool_name == "Task":
        event["taskDescription"] = sanitize_string(
            str(tool_input.get("description", "")), 4096
        )

    if tool_name in ("Write", "Edit", "NotebookEdit"):
        event["filePath"] = sanitize_string(str(tool_input.get("file_path", "")), 4096)
        event["fileOperation"] = "write"

    if tool_name == "Read":
        event["filePath"] = sanitize_string(str(tool_input.get("file_path", "")), 4096)
        event["fileOperation"] = "read"

    return event

# ── Rate Limit Event (Phase 9) ────────────────────────────────────────────────

def build_rate_limit_event(hook_data: dict) -> dict | None:
    """
    레이트 리밋 해제 시각이 환경변수에 설정된 경우 RateLimited 이벤트를 반환합니다.

    사용 예) Claude Code 래퍼 스크립트에서:
      export CLAUDE_RATE_LIMIT_RESET_AT="2026-03-07T16:30:00Z"
      python3 ~/.claude/hooks/notify-terminal.py
    """
    reset_at = os.environ.get("CLAUDE_RATE_LIMIT_RESET_AT", "").strip()
    if not reset_at:
        return None

    session_id = hook_data.get("session_id", "")
    return {
        "type": "RateLimited",
        "agentID": sanitize_string(str(session_id), 256) or "system",
        "sessionID": sanitize_string(str(session_id), 256),
        "rateLimitResetAt": sanitize_string(reset_at, 64),
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }

# ── Local IPC: Unix socket + HMAC authentication ───────────────────────────────

def read_pid_file() -> tuple[str, str]:
    """Returns (socket_path, hmac_key_hex) from ~/.claude-terminal.pid"""
    with open(PID_FILE) as f:
        lines = f.read().strip().splitlines()
    if len(lines) < 2:
        raise ValueError("PID file missing HMAC key")
    return lines[0], lines[1]

def sign_payload(payload_json: str, key_hex: str) -> str:
    """Compute HMAC-SHA256(payload, key) and return as hex."""
    key = bytes.fromhex(key_hex)
    return hmac.new(key, payload_json.encode("utf-8"), hashlib.sha256).hexdigest()

def send_local(event: dict) -> bool:
    try:
        socket_path, hmac_key_hex = read_pid_file()
    except FileNotFoundError:
        return False  # App not running
    except Exception:
        return False

    payload_json = json.dumps(event)
    signature = sign_payload(payload_json, hmac_key_hex)
    wrapper = json.dumps({"signature": signature, "payload": payload_json})
    message = wrapper.encode("utf-8")

    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
            sock.settimeout(TIMEOUT_SECONDS)
            sock.connect(socket_path)
            # Length-prefix framing
            sock.sendall(struct.pack(">I", len(message)) + message)
            sock.recv(1024)  # Response ignored
        return True
    except Exception:
        return False

# ── Remote IPC: HTTP POST to WebSocket server via SSH tunnel ──────────────────

def send_remote(event: dict) -> bool:
    if not REMOTE_TOKEN:
        print("[hook-notify] CLAUDE_TERMINAL_TOKEN not set", file=sys.stderr)
        return False

    try:
        host = validate_host(REMOTE_HOST)
    except ValueError as e:
        print(f"[hook-notify] {e}", file=sys.stderr)
        return False

    body = json.dumps(event).encode("utf-8")
    request = (
        f"POST /hook HTTP/1.1\r\n"
        f"Host: {host}:{REMOTE_WS_PORT}\r\n"
        f"Content-Type: application/json\r\n"
        f"Content-Length: {len(body)}\r\n"
        f"Authorization: Bearer {REMOTE_TOKEN}\r\n"
        f"Connection: close\r\n"
        f"\r\n"
    ).encode() + body

    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(TIMEOUT_SECONDS)
            sock.connect((host, REMOTE_WS_PORT))
            sock.sendall(request)
            sock.recv(1024)
        return True
    except Exception:
        return False

# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    hook_data = read_stdin_json()
    event = build_event(hook_data)

    # 레이트 리밋 이벤트 (Phase 9) — 한 번만 빌드
    rate_limit_event = build_rate_limit_event(hook_data)

    if IS_REMOTE:
        send_remote(event)
        if rate_limit_event:
            send_remote(rate_limit_event)
    else:
        send_local(event)
        if rate_limit_event:
            send_local(rate_limit_event)

    # Always exit 0 — never block Claude Code
    sys.exit(0)


if __name__ == "__main__":
    main()
