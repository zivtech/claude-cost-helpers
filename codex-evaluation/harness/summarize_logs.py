#!/usr/bin/env python3
"""Summarize passive Codex evaluation logs."""

from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, Iterable, List


def default_log_path() -> Path:
    return Path.home() / ".codex" / "evals" / "codex-companion" / "events.jsonl"


def parse_ts(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def load_records(path: Path) -> List[Dict[str, Any]]:
    records: List[Dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            records.append(json.loads(line))
    return records


def session_summary(records: Iterable[Dict[str, Any]]) -> Dict[str, Any]:
    prompts: List[datetime] = []
    models = set()
    sources = set()
    event_counts: Counter[str] = Counter()
    bash_calls = 0
    bash_chars = 0
    bash_tokens = 0

    for record in records:
        event = record.get("hook_event_name", "unknown")
        event_counts[event] += 1
        model = record.get("model")
        if model:
            models.add(model)
        source = record.get("source")
        if source:
            sources.add(source)
        if event == "UserPromptSubmit" and record.get("ts"):
            prompts.append(parse_ts(record["ts"]))
        if event == "PostToolUse" and record.get("tool_name") == "Bash":
            bash_calls += 1
            bash_chars += int(record.get("bash_output_chars", 0) or 0)
            bash_tokens += int(record.get("bash_output_est_tokens", 0) or 0)

    prompts.sort()
    gaps = []
    for left, right in zip(prompts, prompts[1:]):
        gaps.append(int((right - left).total_seconds()))

    return {
        "models": sorted(models),
        "sources": sorted(sources),
        "event_counts": dict(event_counts),
        "prompt_count": len(prompts),
        "max_idle_gap_seconds": max(gaps) if gaps else 0,
        "avg_idle_gap_seconds": int(sum(gaps) / len(gaps)) if gaps else 0,
        "idle_gaps_over_300": sum(1 for gap in gaps if gap >= 300),
        "idle_gaps_over_600": sum(1 for gap in gaps if gap >= 600),
        "bash_calls": bash_calls,
        "bash_output_chars": bash_chars,
        "bash_output_est_tokens": bash_tokens,
    }


def render_markdown(summaries: Dict[str, Dict[str, Any]], records: List[Dict[str, Any]]) -> str:
    event_counts = Counter(record.get("hook_event_name", "unknown") for record in records)
    lines = [
        "# Codex Evaluation Summary",
        "",
        f"Sessions analyzed: {len(summaries)}",
        f"Events analyzed: {len(records)}",
        "",
        "## Event counts",
        "",
    ]
    for event_name, count in sorted(event_counts.items()):
        lines.append(f"- `{event_name}`: {count}")
    lines.extend(
        [
            "",
            "## Per-session summary",
            "",
            "| Session | Models | Prompts | Max gap s | Gaps >=300s | Bash calls | Bash est tokens | Starts |",
            "|---|---|---:|---:|---:|---:|---:|---|",
        ]
    )

    for session_id, summary in sorted(summaries.items()):
        lines.append(
            "| {session} | {models} | {prompts} | {max_gap} | {gaps_300} | {bash_calls} | {bash_tokens} | {sources} |".format(
                session=session_id,
                models=", ".join(summary["models"]) or "-",
                prompts=summary["prompt_count"],
                max_gap=summary["max_idle_gap_seconds"],
                gaps_300=summary["idle_gaps_over_300"],
                bash_calls=summary["bash_calls"],
                bash_tokens=summary["bash_output_est_tokens"],
                sources=", ".join(summary["sources"]) or "-",
            )
        )

    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Summarize Codex evaluation hook logs.")
    parser.add_argument("--log", default=str(default_log_path()), help="Path to the events.jsonl log")
    parser.add_argument("--json", action="store_true", help="Emit machine-readable JSON instead of Markdown")
    args = parser.parse_args()

    log_path = Path(args.log).expanduser()
    if not log_path.exists():
        parser.error(f"log file not found: {log_path}")

    records = load_records(log_path)
    grouped: Dict[str, List[Dict[str, Any]]] = defaultdict(list)
    for record in records:
        grouped[record.get("session_id") or "unknown"].append(record)

    summaries = {session_id: session_summary(session_records) for session_id, session_records in grouped.items()}

    if args.json:
        print(json.dumps({"sessions": summaries, "event_count": len(records)}, indent=2, sort_keys=True))
    else:
        print(render_markdown(summaries, records))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
