#!/usr/bin/env python3
"""Persist cheap Codex session state after every Stop event."""

from __future__ import annotations

import os
import sys
from pathlib import Path

SHARED_DIR = Path(__file__).resolve().parents[1] / "_shared"
if str(SHARED_DIR) not in sys.path:
    sys.path.insert(0, str(SHARED_DIR))

from hooklib import (  # noqa: E402
    append_debug,
    atomic_write_json,
    atomic_write_text,
    collect_git_state,
    collect_recent_files,
    codex_home,
    emit_message,
    local_now,
    load_payload,
    preview,
    record_hook_invocation,
    session_id,
    short_hash,
    utc_now,
)


HELPER = "stop-snapshot"
EVENT = "Stop"


def render_markdown(state: dict) -> str:
    git = state["git"]
    lines = [
        "# Stop snapshot",
        "",
        f"- **Session**: `{state['session_id']}`",
        f"- **Recorded**: {state['timestamp_local']}",
        f"- **CWD**: `{state['cwd']}`",
        f"- **Transcript**: `{state['transcript_path'] or 'unknown'}`",
    ]

    last = state["last_assistant"]
    if last["preview"]:
        lines.append(f"- **Last assistant preview**: `{last['preview']}`")

    if git["is_git_repo"]:
        lines.extend(
            [
                f"- **Git branch**: `{git['branch'] or 'unknown'}`",
                f"- **Last commit**: `{git['last_commit_sha'] or 'unknown'}` — {git['last_commit_msg'] or ''}",
                f"- **Uncommitted**: {git['staged']} staged, {git['modified']} modified, {git['untracked']} untracked",
            ]
        )
        if git["ahead"] or git["behind"]:
            lines.append(f"- **Upstream**: {git['ahead']} ahead, {git['behind']} behind")
    else:
        lines.append("- **Git**: _not a git repository_")

    recent_files = state.get("recent_files") or []
    if recent_files:
        lines.extend(["", "## Recent files", ""])
        lines.extend([f"- `{name}`" for name in recent_files])

    lines.extend(["", "---", "_Written by `stop-snapshot` on Codex `Stop` events._", ""])
    return "\n".join(lines)


def main() -> int:
    try:
        payload = load_payload()
        sid = session_id(payload)
        cwd = Path(payload.get("cwd") or os.getcwd()).expanduser()
        transcript_path = payload.get("transcript_path")
        last_message = payload.get("last_assistant_message")

        state = {
            "session_id": sid,
            "timestamp_iso": utc_now(),
            "timestamp_local": local_now(),
            "cwd": str(cwd),
            "transcript_path": transcript_path,
            "stop_hook_active": bool(payload.get("stop_hook_active")),
            "last_assistant": {
                "preview": preview(last_message, limit=80),
                "hash": short_hash(last_message),
                "chars": len(last_message) if isinstance(last_message, str) else 0,
            },
            "git": collect_git_state(cwd),
            "recent_files": collect_recent_files(cwd, limit=10),
        }

        output_dir = codex_home() / "sessions" / "auto-state"
        atomic_write_json(output_dir / f"{sid}.json", state)
        atomic_write_text(output_dir / f"{sid}.md", render_markdown(state))
        record_hook_invocation(
            HELPER,
            EVENT,
            payload,
            extra={
                "snapshot_json": str(output_dir / f"{sid}.json"),
                "snapshot_md": str(output_dir / f"{sid}.md"),
            },
        )
    except Exception as exc:
        append_debug(HELPER, f"error: {exc}")
    finally:
        emit_message(EVENT)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
