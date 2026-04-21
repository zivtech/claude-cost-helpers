#!/usr/bin/env python3
"""Passive hook logger for Codex companion-post evaluation."""

from __future__ import annotations

import hashlib
import json
import math
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def eval_dir() -> Path:
    configured = os.environ.get("CODEX_EVAL_DIR")
    if configured:
        return Path(configured).expanduser()
    return Path.home() / ".codex" / "evals" / "codex-companion"


def stable_json_length(value: Any) -> int:
    if value is None:
        return 0
    if isinstance(value, str):
        return len(value)
    try:
        return len(json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True))
    except TypeError:
        return len(str(value))


def preview(value: Any, limit: int = 120) -> str | None:
    if value is None:
        return None
    if not isinstance(value, str):
        try:
            value = json.dumps(value, sort_keys=True, ensure_ascii=True)
        except TypeError:
            value = str(value)
    value = value.replace("\n", "\\n")
    if len(value) <= limit:
        return value
    return value[:limit] + "..."


def short_hash(value: str | None) -> str | None:
    if not value:
        return None
    return hashlib.sha256(value.encode("utf-8")).hexdigest()[:12]


def build_record(payload: Dict[str, Any]) -> Dict[str, Any]:
    event = payload.get("hook_event_name")
    record: Dict[str, Any] = {
        "ts": utc_now(),
        "hook_event_name": event,
        "session_id": payload.get("session_id"),
        "turn_id": payload.get("turn_id"),
        "cwd": payload.get("cwd"),
        "model": payload.get("model"),
        "transcript_path": payload.get("transcript_path"),
    }

    if event == "SessionStart":
        record["source"] = payload.get("source")

    if event == "UserPromptSubmit":
        prompt = payload.get("prompt", "")
        record["prompt_chars"] = len(prompt)
        record["prompt_hash"] = short_hash(prompt)
        record["prompt_preview"] = preview(prompt, limit=80)

    if event == "PostToolUse":
        tool_name = payload.get("tool_name")
        tool_input = payload.get("tool_input") or {}
        tool_response = payload.get("tool_response")
        output_chars = stable_json_length(tool_response)
        record["tool_name"] = tool_name
        record["command"] = tool_input.get("command")
        record["command_hash"] = short_hash(tool_input.get("command"))
        record["tool_response_type"] = type(tool_response).__name__
        record["bash_output_chars"] = output_chars
        record["bash_output_est_tokens"] = int(math.ceil(output_chars / 4)) if output_chars else 0
        record["bash_output_preview"] = preview(tool_response, limit=160)

    if event == "Stop":
        last_message = payload.get("last_assistant_message")
        record["stop_hook_active"] = bool(payload.get("stop_hook_active"))
        record["last_assistant_chars"] = len(last_message) if isinstance(last_message, str) else 0
        record["last_assistant_hash"] = short_hash(last_message if isinstance(last_message, str) else None)
        record["last_assistant_preview"] = preview(last_message, limit=80)

    return record


def write_record(record: Dict[str, Any]) -> None:
    root = eval_dir()
    root.mkdir(parents=True, exist_ok=True)
    log_path = root / "events.jsonl"
    with log_path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, sort_keys=True) + "\n")


def stop_output() -> None:
    sys.stdout.write(json.dumps({"continue": True}))


def main() -> int:
    raw = sys.stdin.read()
    event = None
    try:
        payload = json.loads(raw) if raw.strip() else {}
        event = payload.get("hook_event_name")
        write_record(build_record(payload))
    except Exception as exc:  # fail open for evaluation logging
        root = eval_dir()
        root.mkdir(parents=True, exist_ok=True)
        with (root / "errors.log").open("a", encoding="utf-8") as handle:
            handle.write(f"{utc_now()} capture_event error: {exc}\n")
    finally:
        if event == "Stop":
            stop_output()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
