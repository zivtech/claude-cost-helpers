#!/usr/bin/env python3
"""Warn when Bash output becomes large enough to weigh down a Codex session."""

from __future__ import annotations

import os
import sys
from pathlib import Path

SHARED_DIR = Path(__file__).resolve().parents[1] / "_shared"
if str(SHARED_DIR) not in sys.path:
    sys.path.insert(0, str(SHARED_DIR))

from hooklib import (  # noqa: E402
    append_debug,
    coerce_text,
    emit_message,
    estimate_tokens,
    load_payload,
    read_int,
    record_hook_invocation,
    session_id,
    session_state_dir,
    write_text,
)


HELPER = "bash-output-watch"
EVENT = "PostToolUse"


def parse_thresholds() -> list[int]:
    raw = os.environ.get("CODEX_BASH_OUTPUT_CUMULATIVE_TOKENS", "10000,25000,50000")
    values = []
    for part in raw.split(","):
        part = part.strip()
        if not part:
            continue
        try:
            values.append(int(part))
        except ValueError:
            continue
    return values or [10000, 25000, 50000]


def main() -> int:
    message = None
    try:
        payload = load_payload()
        if payload.get("tool_name") != "Bash":
            emit_message(EVENT, None)
            return 0

        sid = session_id(payload)
        state_dir = session_state_dir()
        cumulative_file = state_dir / f"{sid}.bash-output-tokens"
        warned_file = state_dir / f"{sid}.bash-output-warned"

        response_text = coerce_text(payload.get("tool_response"))
        call_tokens = estimate_tokens(response_text)
        if call_tokens <= 0:
            emit_message(EVENT, None)
            return 0

        per_call_threshold = int(os.environ.get("CODEX_BASH_OUTPUT_WARN_TOKENS", "4000"))
        cumulative_thresholds = parse_thresholds()

        current_total = read_int(cumulative_file, 0)
        new_total = current_total + call_tokens
        write_text(cumulative_file, f"{new_total}\n")

        warned = set()
        if warned_file.exists():
            warned = {part for part in warned_file.read_text().strip().split(",") if part}

        messages = []
        if call_tokens >= per_call_threshold:
            messages.append(
                f"This Bash command returned about {call_tokens} estimated tokens of shell output. "
                "Prefer redirecting or filtering Bash output when you only need the result summary."
            )

        for threshold in cumulative_thresholds:
            marker = str(threshold)
            if marker in warned:
                continue
            if current_total < threshold <= new_total:
                warned.add(marker)
                messages.append(
                    f"Cumulative Bash output for this session is now about {new_total} estimated tokens. "
                    "That shell output can weigh down later turns; consider starting a fresh session or "
                    "redirecting future command output to files."
                )

        if warned:
            write_text(warned_file, ",".join(sorted(warned, key=int)) + "\n")

        if messages:
            message = "\n\n".join(messages)
        record_hook_invocation(
            HELPER,
            EVENT,
            payload,
            message=message,
            extra={
                "call_tokens": call_tokens,
                "cumulative_tokens": new_total,
                "per_call_threshold": per_call_threshold,
                "cumulative_thresholds": cumulative_thresholds,
            },
        )
    except Exception as exc:
        append_debug(HELPER, f"error: {exc}")
        message = None

    emit_message(EVENT, message)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
