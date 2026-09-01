---
name: usage-report
description: Generate the Claude Code usage report — desktop vs terminal cost per turn, cache economics, delegation audit, headless-job tally, week-over-week trend. Computed from local transcripts, zero Claude tokens. Use when the user asks where their Claude Code spend goes, wants to compare desktop vs terminal usage, or types /usage-report.
---

# Usage Report

Run the report generator and show its full output verbatim — the output IS the
report. Do not summarize it, re-analyze it, or read the transcript files it was
computed from (that pulls megabytes into context for nothing).

```bash
python3 "$HOME/.claude/hooks/cost-helpers/usage-report/usage_report.py" --since "${1:-28}"
```

If the script is missing, tell the user to run `usage-report/install.sh` from
the claude-cost-helpers repo. After showing the report, offer exactly one line:
the single biggest lever from its "Levers" section, phrased as a next action.
