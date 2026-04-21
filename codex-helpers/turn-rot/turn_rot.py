#!/usr/bin/env python3
"""Warn when a Codex session keeps growing turn after turn."""

from __future__ import annotations

import os
import sys
from pathlib import Path

SHARED_DIR = Path(__file__).resolve().parents[1] / "_shared"
if str(SHARED_DIR) not in sys.path:
    sys.path.insert(0, str(SHARED_DIR))

from hooklib import (  # noqa: E402
    append_debug,
    emit_message,
    load_payload,
    read_int,
    record_hook_invocation,
    session_id,
    session_state_dir,
    write_text,
)


HELPER = "turn-rot"
EVENT = "UserPromptSubmit"


def env_int(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name) or default)
    except ValueError:
        return default


def main() -> int:
    try:
        payload = load_payload()
        sid = session_id(payload)
        state_dir = session_state_dir()
        count_file = state_dir / f"{sid}.turn-count"
        warned_file = state_dir / f"{sid}.turn-rot-warned"

        soft_warn = env_int("CODEX_TURN_ROT_WARN_TURNS", 30)
        hard_warn = max(env_int("CODEX_TURN_ROT_HARD_TURNS", 50), soft_warn)

        turn_count = read_int(count_file, 0) + 1
        write_text(count_file, f"{turn_count}\n")

        warned = set()
        if warned_file.exists():
            warned = {part for part in warned_file.read_text().strip().split(",") if part}

        message = None
        if turn_count >= hard_warn and "hard" not in warned:
            warned.add("hard")
            message = (
                f"This session has reached {turn_count} turns. Long Codex sessions get harder to manage "
                "as stale context accumulates. Consider starting a fresh session with a short handoff."
            )
        elif turn_count >= soft_warn and "soft" not in warned:
            warned.add("soft")
            message = (
                f"This session has reached {turn_count} turns. Session growth is becoming material; keep an eye "
                "on stale context and use fresh-session hygiene if the task boundary has shifted."
            )

        if warned:
            write_text(warned_file, ",".join(sorted(warned)) + "\n")
        record_hook_invocation(
            HELPER,
            EVENT,
            payload,
            message=message,
            extra={
                "turn_count": turn_count,
                "soft_warn_turns": soft_warn,
                "hard_warn_turns": hard_warn,
            },
        )
    except Exception as exc:
        append_debug(HELPER, f"error: {exc}")
        message = None
    emit_message(EVENT, message)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
