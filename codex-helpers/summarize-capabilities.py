#!/usr/bin/env python3
"""Summarize Codex helper capability evidence from invocation logs and smoke outputs."""

from __future__ import annotations

import json
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Dict, List


def load_invocations(path: Path) -> List[Dict[str, Any]]:
    if not path.exists():
        return []
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return rows


def summarize(rows: List[Dict[str, Any]]) -> Dict[str, Any]:
    by_helper = defaultdict(list)
    by_event = Counter()
    for row in rows:
        by_helper[row.get("helper", "unknown")].append(row)
        by_event[row.get("hook_event_name", "unknown")] += 1

    helper_summary = {}
    for helper, items in sorted(by_helper.items()):
        helper_summary[helper] = {
            "count": len(items),
            "events": sorted({item.get("hook_event_name") for item in items if item.get("hook_event_name")}),
            "messages_emitted": sum(1 for item in items if item.get("message_emitted")),
        }

    status = {
        "reasoning-hygiene-banner": "proven" if helper_summary.get("reasoning-hygiene-banner", {}).get("count") else "not-observed",
        "stop-snapshot": "proven" if helper_summary.get("stop-snapshot", {}).get("count") else "not-observed",
        "turn-rot": "proven" if helper_summary.get("turn-rot", {}).get("count") else "not-observed",
        "bash-output-watch": "proven" if helper_summary.get("bash-output-watch", {}).get("count") else "not-observed",
    }

    return {
        "total_invocations": len(rows),
        "events": dict(by_event),
        "helpers": helper_summary,
        "status": status,
    }


def render(summary: Dict[str, Any]) -> str:
    lines = [
        "# Codex Helper Capability Summary",
        "",
        f"Total hook invocations observed: {summary['total_invocations']}",
        "",
        "## Event counts",
        "",
    ]
    for name, count in sorted(summary["events"].items()):
        lines.append(f"- `{name}`: {count}")

    lines.extend(["", "## Helper status", ""])
    for helper, status in summary["status"].items():
        lines.append(f"- `{helper}`: {status}")

    lines.extend(["", "## Helper details", ""])
    for helper, details in summary["helpers"].items():
        lines.append(
            f"- `{helper}`: {details['count']} invocation(s), events={', '.join(details['events']) or 'none'}, "
            f"messages_emitted={details['messages_emitted']}"
        )

    lines.extend(
        [
            "",
            "## Interpretation",
            "",
            "- `proven` means this helper was observed invoking on the current runtime in the tested path.",
            "- `not-observed` means the helper did not invoke in the tested path; that is evidence of a runtime gap, not proof the hook can never work elsewhere.",
        ]
    )
    return "\n".join(lines)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: summarize-capabilities.py /path/to/invocations.jsonl", file=sys.stderr)
        return 2

    path = Path(sys.argv[1]).expanduser()
    summary = summarize(load_invocations(path))
    print(render(summary))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
