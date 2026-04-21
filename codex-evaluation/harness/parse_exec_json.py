#!/usr/bin/env python3
"""Extract usage and command-output facts from codex exec JSONL logs."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any, Dict, List


def parse(path: Path) -> Dict[str, Any]:
    thread_id = None
    usage = None
    commands: List[Dict[str, Any]] = []
    messages: List[str] = []

    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.startswith("{"):
            continue
        obj = json.loads(line)
        item = obj.get("item", {})

        if obj.get("type") == "thread.started":
            thread_id = obj.get("thread_id")
        elif obj.get("type") == "turn.completed":
            usage = obj.get("usage")
        elif obj.get("type") == "item.completed" and item.get("type") == "command_execution":
            output = item.get("aggregated_output", "") or ""
            commands.append(
                {
                    "command": item.get("command"),
                    "exit_code": item.get("exit_code"),
                    "output_chars": len(output),
                    "output_preview": output[:120].replace("\n", "\\n") + ("..." if len(output) > 120 else ""),
                }
            )
        elif obj.get("type") == "item.completed" and item.get("type") == "agent_message":
            text = item.get("text")
            if isinstance(text, str):
                messages.append(text)

    return {
        "thread_id": thread_id,
        "usage": usage,
        "command_count": len(commands),
        "commands": commands,
        "final_message": messages[-1] if messages else None,
    }


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: parse_exec_json.py /path/to/exec-run.jsonl", file=sys.stderr)
        return 2

    path = Path(sys.argv[1]).expanduser()
    if not path.exists():
        print(f"log file not found: {path}", file=sys.stderr)
        return 2

    print(json.dumps(parse(path), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
