#!/usr/bin/env python3
"""Watchdog for OpenCode subagent sessions tracked on the Kanban board.

Reads `kanban-board.json`, finds In Progress cards with a linked session, and
checks two signals per session:

1. the session's `time.updated` (thinking/streaming activity), and
2. whether any tool in the session's message history is still `running`.

A session is considered stuck when it has a running-free history, has not
updated for `--threshold-minutes`, and therefore cannot be waiting on a tool.
On the first detection it sends a desktop notification and, with
`--notify-chat`, injects a prompt into the parent session.

The script is safe to run every minute: it keeps per-session alert state in
`/tmp/opencode/subagent-watchdog.json` and never repeats an alert for the same
episode more than once an hour. It uses `opencode api`, which authenticates via
the local service file, so no secret is stored here.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parents[2]
BOARD = REPO / "kanban-board.json"
STATE = Path("/tmp/opencode/subagent-watchdog.json")
OPENCODE = shutil.which("opencode") or "/home/lucas/.opencode/bin/opencode"
ALERT_COOLDOWN_MS = 60 * 60 * 1000


def load_board() -> list[dict[str, Any]]:
    try:
        data = json.loads(BOARD.read_text())
    except (OSError, json.JSONDecodeError) as error:
        print(f"watchdog: cannot read {BOARD}: {error}", file=sys.stderr)
        return []
    return [
        task
        for task in data.get("tasks", [])
        if task.get("categoryID") == "inprogress" and task.get("sessionID")
    ]


def api_json(path: str) -> Any | None:
    try:
        result = subprocess.run(
            [OPENCODE, "api", "GET", path],
            capture_output=True,
            text=True,
            timeout=20,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        print(f"watchdog: api {path} failed: {error}", file=sys.stderr)
        return None
    if result.returncode != 0:
        print(f"watchdog: api {path} exit {result.returncode}", file=sys.stderr)
        return None
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError:
        return None
    return payload.get("data", payload)


def has_running_tool(session_id: str) -> bool:
    messages = api_json(f"/api/session/{session_id}/message")
    if messages is None:
        return False

    def walk(value: Any) -> bool:
        if isinstance(value, dict):
            state = value.get("state")
            if isinstance(state, dict) and state.get("status") == "running":
                return True
            return any(walk(item) for item in value.values())
        if isinstance(value, list):
            return any(walk(item) for item in value)
        return False

    return walk(messages)


def notify(title: str, body: str) -> None:
    try:
        subprocess.run(
            ["notify-send", "-a", "Tarkov Companion", "-u", "critical", title, body],
            check=False,
            timeout=10,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        print(f"watchdog: notify-send failed: {error}", file=sys.stderr)


def notify_chat(parent: str, prompt: str) -> None:
    log_path = Path("/tmp/opencode/subagent-watchdog-chat.log")
    try:
        with log_path.open("ab") as log:
            subprocess.Popen(
                [OPENCODE, "run", "-s", parent, "--agent", "build", "--prompt", prompt],
                stdout=log,
                stderr=log,
                start_new_session=True,
            )
    except OSError as error:
        print(f"watchdog: cannot notify chat: {error}", file=sys.stderr)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--threshold-minutes", type=int, default=15)
    parser.add_argument("--parent-session")
    parser.add_argument("--notify-chat", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    tasks = load_board()
    if not tasks:
        print("watchdog: no in-progress sessions")
        return 0

    state: dict[str, dict[str, Any]] = {}
    if STATE.exists():
        try:
            state = json.loads(STATE.read_text())
        except (OSError, json.JSONDecodeError):
            state = {}

    now = int(time.time() * 1000)
    threshold_ms = args.threshold_minutes * 60 * 1000
    active_ids: set[str] = set()
    stuck = 0

    for task in tasks:
        session_id = str(task["sessionID"])
        title = str(task.get("title", task.get("id", session_id)))
        active_ids.add(session_id)

        session = api_json(f"/api/session/{session_id}")
        if not session:
            print(f"UNKNOWN {title} ({session_id}): session not found")
            continue

        time_info = session.get("time") or {}
        updated = int(time_info.get("updated") or 0)
        age_ms = max(0, now - updated)
        running = has_running_tool(session_id)
        is_stuck = not running and age_ms >= threshold_ms
        label = "STUCK" if is_stuck else "active"
        print(
            f"{label:6} {title} | {age_ms / 60000:.1f}m since update"
            f" | running_tool={str(running).lower()} | {session_id}"
        )

        if not is_stuck:
            state.pop(session_id, None)
            continue

        stuck += 1
        previous = state.get(session_id) or {}
        last_alert = int(previous.get("alerted_at") or 0)
        if now - last_alert < ALERT_COOLDOWN_MS:
            continue

        minutes = age_ms // 60000
        body = f"{title} has not updated for {minutes}m and no tool is running."
        if args.dry_run:
            print(f"would alert: {body}")
        else:
            notify("Subagent may be stuck", body)
            if args.notify_chat and args.parent_session:
                notify_chat(
                    args.parent_session,
                    "[subagent-watchdog] "
                    f"{body} Session {session_id}, card {task.get('id')}. "
                    "Investigate its last message and either wake it with a follow-up or take over. "
                    "Do not repeat this alert for one hour.",
                )
            state[session_id] = {"alerted_at": now, "title": title}

    for session_id in list(state):
        if session_id not in active_ids:
            state.pop(session_id, None)

    if not args.dry_run:
        STATE.parent.mkdir(parents=True, exist_ok=True)
        STATE.write_text(json.dumps(state, indent=2) + "\n")

    print(f"watchdog: {len(tasks)} active, {stuck} stuck")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
