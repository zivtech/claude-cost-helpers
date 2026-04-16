---
description: Save session state and recommend starting fresh instead of compacting. A safer alternative to lossy compaction.
---

# Safe Compact

Compaction is a gamble. Claude decides what to keep and what to discard — and it does not tell you what it dropped. Before you let that happen, use this command to save your session and consider starting fresh instead.

## What this does

1. Runs the full `/save-session` flow to capture the current session into `~/.claude/sessions/YYYY-MM-DD-<topic>-session.md`
2. Prints a recommendation with the path of the saved file
3. Explains the economics so you can make an informed choice

## Step 1: Save the session

Run `/save-session` now. Follow its process completely — gather context, write all sections, show the file to the user for confirmation.

## Step 2: After saving, print this recommendation

```
Session saved to ~/.claude/sessions/<filename> — starting fresh is usually
cheaper than compacting. Run `/resume-session` in a new session to continue.
```

## Step 3: Explain the economics

Explain the tradeoff clearly:

**What compaction does:** Compaction summarizes your current session context and continues the same session on top of that summary. Claude decides what mattered. The original context is gone — replaced by a compressed version of it. This is lossy and irreversible.

**What starting fresh does:** You get a clean session with a cold (but small) cache. The handoff file carries the essentials: what worked, what didn't, the exact next step. You pay a small re-cache cost on the first message, then run cheaply on a lean context for the rest of the session.

**The math:** A long, compacted session that keeps re-caching a large summary costs more per message than a fresh session on a focused handoff. Compaction keeps a stale session alive; starting fresh resets the meter.

**When compaction might be right:** If you are in the middle of something that genuinely cannot survive a context break — mid-tool-call, mid-refactor with unsaved state — compaction may be the only option. Otherwise, fresh is almost always cheaper.

## Dependency

This command depends on `/save-session` from Helper 01 (Idle Tax). If `/save-session` is not installed, run `./install.sh` from `01-idle-tax/` first.
