#!/usr/bin/env python3
"""Shared utilities for Codex helper hooks."""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List


def load_payload() -> Dict[str, Any]:
    raw = sys.stdin.read()
    if not raw.strip():
        return {}
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {}


def codex_home() -> Path:
    return Path.home() / ".codex"


def session_state_dir() -> Path:
    return codex_home() / ".session-state"


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def session_id(payload: Dict[str, Any]) -> str:
    value = payload.get("session_id") or payload.get("sessionId") or "unknown"
    return str(value)


def short_hash(value: str | None, length: int = 12) -> str | None:
    if not value:
        return None
    return hashlib.sha256(value.encode("utf-8")).hexdigest()[:length]


def preview(value: Any, limit: int = 120) -> str | None:
    if value is None:
        return None
    text = coerce_text(value)
    if len(text) <= limit:
        return text
    return text[:limit] + "..."


def coerce_text(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return value
    try:
        return json.dumps(value, sort_keys=True, ensure_ascii=True)
    except TypeError:
        return str(value)


def estimate_tokens(text: str) -> int:
    if not text:
        return 0
    return (len(text) + 3) // 4


def read_int(path: Path, default: int = 0) -> int:
    try:
        return int(path.read_text().strip())
    except Exception:
        return default


def write_text(path: Path, text: str) -> None:
    ensure_dir(path.parent)
    path.write_text(text, encoding="utf-8")


def atomic_write_text(path: Path, text: str) -> None:
    ensure_dir(path.parent)
    with tempfile.NamedTemporaryFile("w", delete=False, dir=str(path.parent), encoding="utf-8") as handle:
        handle.write(text)
        tmp = Path(handle.name)
    os.replace(tmp, path)


def atomic_write_json(path: Path, data: Dict[str, Any]) -> None:
    atomic_write_text(path, json.dumps(data, indent=2, sort_keys=True) + "\n")


def append_debug(helper_name: str, message: str) -> None:
    debug_path = codex_home() / "hooks" / "cost-helpers" / f"{helper_name}.debug.log"
    ensure_dir(debug_path.parent)
    with debug_path.open("a", encoding="utf-8") as handle:
        handle.write(f"{utc_now()} {message}\n")


def helper_log_dir() -> Path:
    configured = os.environ.get("CODEX_HELPER_LOG_DIR")
    if configured:
        return Path(configured).expanduser()
    return codex_home() / "hooks" / "cost-helpers" / "_shared"


def record_hook_invocation(
    helper_name: str,
    event_name: str,
    payload: Dict[str, Any],
    message: str | None = None,
    extra: Dict[str, Any] | None = None,
) -> None:
    record: Dict[str, Any] = {
        "ts": utc_now(),
        "helper": helper_name,
        "hook_event_name": event_name,
        "session_id": session_id(payload),
        "model": payload.get("model"),
        "tool_name": payload.get("tool_name"),
        "source": payload.get("source"),
        "message_emitted": bool(message),
        "message_preview": preview(message, limit=120),
    }
    if extra:
        record.update(extra)

    log_dir = helper_log_dir()
    ensure_dir(log_dir)
    log_path = log_dir / "invocations.jsonl"
    with log_path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, sort_keys=True) + "\n")


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def local_now() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def emit_message(event_name: str, message: str | None = None) -> None:
    if event_name == "Stop":
        payload: Dict[str, Any] = {"continue": True}
        if message:
            payload["systemMessage"] = message
        print(json.dumps(payload))
        return

    if not message:
        return

    payload = {
        "systemMessage": message,
        "hookSpecificOutput": {
            "hookEventName": event_name,
            "additionalContext": message,
        },
    }
    if event_name in {"SessionStart", "UserPromptSubmit"}:
        payload["continue"] = True
    print(json.dumps(payload))


def parse_top_level_config(path: Path) -> Dict[str, str]:
    result: Dict[str, str] = {}
    if not path.exists():
        return result

    scalar = re.compile(r'^\s*([A-Za-z0-9_]+)\s*=\s*(.+?)\s*$')
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        match = scalar.match(line)
        if not match:
            continue
        key, raw_value = match.groups()
        raw_value = raw_value.split("#", 1)[0].strip()
        if raw_value.startswith('"') and raw_value.endswith('"'):
            value = raw_value[1:-1]
        else:
            value = raw_value
        result.setdefault(key, value)
    return result


def run_git(cwd: Path, args: List[str]) -> str | None:
    try:
        completed = subprocess.run(
            ["git", "-C", str(cwd), *args],
            check=True,
            capture_output=True,
            text=True,
        )
        return completed.stdout.strip()
    except Exception:
        return None


def is_git_repo(cwd: Path) -> bool:
    return run_git(cwd, ["rev-parse", "--git-dir"]) is not None


def collect_git_state(cwd: Path) -> Dict[str, Any]:
    if not is_git_repo(cwd):
        return {
            "branch": None,
            "last_commit_sha": None,
            "last_commit_msg": None,
            "staged": 0,
            "modified": 0,
            "untracked": 0,
            "ahead": 0,
            "behind": 0,
            "is_git_repo": False,
        }

    status = run_git(cwd, ["status", "--porcelain"]) or ""
    staged = 0
    modified = 0
    untracked = 0
    for line in status.splitlines():
        if not line:
            continue
        if line.startswith("??"):
            untracked += 1
            continue
        x = line[0]
        y = line[1]
        if x != " ":
            staged += 1
        if y != " ":
            modified += 1

    ahead = behind = 0
    counts = run_git(cwd, ["rev-list", "--left-right", "--count", "@{u}...HEAD"])
    if counts:
        try:
            behind, ahead = [int(part) for part in counts.split()]
        except ValueError:
            ahead = behind = 0

    return {
        "branch": run_git(cwd, ["rev-parse", "--abbrev-ref", "HEAD"]),
        "last_commit_sha": run_git(cwd, ["rev-parse", "--short", "HEAD"]),
        "last_commit_msg": run_git(cwd, ["log", "-1", "--pretty=%s"]),
        "staged": staged,
        "modified": modified,
        "untracked": untracked,
        "ahead": ahead,
        "behind": behind,
        "is_git_repo": True,
    }


def collect_recent_files(cwd: Path, limit: int = 10) -> List[str]:
    if is_git_repo(cwd):
        tracked = run_git(cwd, ["ls-files", "-m", "-o", "--exclude-standard"]) or ""
        files = [line.strip() for line in tracked.splitlines() if line.strip()]
        return files[:limit]

    excluded = {".git", "node_modules", ".cache", "__pycache__", ".next", "dist", "build"}
    seen: List[tuple[float, str]] = []
    for root, dirs, files in os.walk(cwd):
        dirs[:] = [name for name in dirs if name not in excluded]
        for name in files:
            path = Path(root) / name
            try:
                stat = path.stat()
            except OSError:
                continue
            seen.append((stat.st_mtime, os.path.relpath(path, cwd)))
    seen.sort(reverse=True)
    return [item[1] for item in seen[:limit]]
