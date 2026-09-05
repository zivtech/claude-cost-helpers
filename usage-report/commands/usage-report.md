---
description: Generate the Claude Code usage report — desktop vs terminal cost per turn, cache economics, delegation audit, headless-job tally, week-over-week trend. Computed from local transcripts, zero Claude tokens.
argument-hint: [window-days (default 28)]
---

# Usage Report

Run the report generator and show its full output verbatim — the output IS the
report; do not summarize it, re-analyze it, or re-read the transcript files it
was computed from (that would pull megabytes into context for nothing).

!`python3 "$HOME/.claude/hooks/cost-helpers/usage-report/usage_report.py" --since "${ARGUMENTS:-28}"`

After showing it, offer exactly one line: the single biggest lever from the
"Levers" section, phrased as a next action.
