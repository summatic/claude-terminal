#!/usr/bin/env python3
"""
ClaudeTerminal Hook Notification Script
Install this to ~/.claude/hooks/notify-terminal.py

Configure in ~/.claude/settings.json:
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

For REMOTE servers, set the CLAUDE_TERMINAL_REMOTE=1 env var and
configure CLAUDE_TERMINAL_HOST (IP of your Mac) and CLAUDE_TERMINAL_WS_PORT.
"""

import sys
import json
import socket
import struct
import os
import time
from datetime import datetime, timezone

# ── Configuration ──────────────────────────────────────────────────────────────

PID_FILE = os.path.expanduser("~/.claude-terminal.pid")
TIMEOUT_SECONDS = 0.3  # Non-blocking: don't delay Claude Code if app is unavailable

# Remote mode (server → Mac)
IS_REMOTE = os.environ.get("CLAUDE_TERMINAL_REMOTE", "") == "1"
REMOTE_HOST = os.environ.get("CLAUDE_TERMINAL_HOST", "localhost")
REMOTE_WS_PORT = int(os.environ.get("CLAUDE_TERMINAL_WS_PORT", "9901"))

# ── Read hook context from stdin ───────────────────────────────────────────────

def read_stdin_json():
    try:
        raw = sys.stdin.read()
        return json.loads(raw) if raw.strip() else {}
    except Exception:
        return {}


# ── Map Claude Code hook context to ClaudeTerminal event ──────────────────────

def build_event(hook_data: dict) -> dict:
    hook_type = os.environ.get("CLAUDE_HOOK_TYPE", "PreToolUse")
    tool_name = hook_data.get("tool_name", "")
    tool_input = hook_data.get("tool_input", {})
    session_id = hook_data.get("session_id", "")
    agent_id = hook_data.get("agent_id", session_id)
    parent_agent_id = hook_data.get("parent_agent_id")

    event = {
        "type": hook_type,
        "agentID": agent_id,
        "parentAgentID": parent_agent_id,
        "sessionID": session_id,
        "toolName": tool_name,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }

    if tool_name == "Task":
        event["taskDescription"] = tool_input.get("description", "")

    if tool_name in ("Write", "Edit", "NotebookEdit"):
        event["filePath"] = tool_input.get("file_path", "")
        event["fileOperation"] = "write"

    if tool_name == "Read":
        event["filePath"] = tool_input.get("file_path", "")
        event["fileOperation"] = "read"

    return event


# ── Local IPC: Unix domain socket ─────────────────────────────────────────────

def send_local(event_json: bytes) -> bool:
    try:
        with open(PID_FILE) as f:
            socket_path = f.read().strip()
    except FileNotFoundError:
        return False  # App not running

    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
            sock.settimeout(TIMEOUT_SECONDS)
            sock.connect(socket_path)

            # Send length-prefixed message
            length = struct.pack(">I", len(event_json))
            sock.sendall(length + event_json)

            # Read response (ignore content)
            sock.recv(1024)
        return True
    except Exception:
        return False


# ── Remote IPC: HTTP POST to WebSocket server ─────────────────────────────────

def send_remote(event_json: bytes) -> bool:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(TIMEOUT_SECONDS)
            sock.connect((REMOTE_HOST, REMOTE_WS_PORT))

            body = event_json
            request = (
                f"POST /hook HTTP/1.1\r\n"
                f"Host: {REMOTE_HOST}:{REMOTE_WS_PORT}\r\n"
                f"Content-Type: application/json\r\n"
                f"Content-Length: {len(body)}\r\n"
                f"Connection: close\r\n"
                f"\r\n"
            ).encode() + body

            sock.sendall(request)
            sock.recv(1024)  # Read HTTP response
        return True
    except Exception:
        return False


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    hook_data = read_stdin_json()
    event = build_event(hook_data)
    event_json = json.dumps(event).encode("utf-8")

    if IS_REMOTE:
        send_remote(event_json)
    else:
        send_local(event_json)

    # Always exit 0 — never block Claude Code
    sys.exit(0)


if __name__ == "__main__":
    main()
