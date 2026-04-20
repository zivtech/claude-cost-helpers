---
description: Show per-agent delegation result sizes and estimated carrying cost for the current session.
---

# Delegation Report

Show how much context weight is coming from subagent results in this session.

## Process

1. Find the current session's delegation tracking file at `~/.claude/.session-state/<session_id>.delegation-agents`
2. If the file doesn't exist, report: "No delegation results tracked in this session."
3. If it exists, read the file. Each line is: `<tokens>\t<timestamp>` — one entry per agent result.
4. Report a table:

```
## Delegation Report

| # | Time  | Result size | Carrying cost (20 turns, warm) |
|---|-------|-------------|-------------------------------|
| 1 | 14:32 | ~3K tokens  | $0.09                         |
| 2 | 14:35 | ~8K tokens  | $0.24                         |
| 3 | 14:41 | ~2K tokens  | $0.06                         |

**Total delegation results:** ~13K tokens
**Estimated carrying cost** (20 turns at $1.50/MTok): $0.39
**With cold-cache turns** (20 turns at blended $5/MTok): $1.30

Tip: results over 5K tokens benefit most from tighter prompt constraints
("report in under 200 words") or writing findings to a file.
```

5. Calculate carrying cost as: `total_tokens × 20 turns × rate / 1,000,000`
   - Warm cache rate: $1.50/MTok
   - Blended rate (assumes some cold turns): $5.00/MTok

## Why this helps

The delegation invoice (what each agent spent) is visible in `/usage`. The delegation tax (what the parent pays to carry the results) is invisible. This report makes the tax visible so you can decide whether to constrain future agent output, split the session, or switch to file-based handoffs.
