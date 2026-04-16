---
name: split
description: Save current session and split — start fresh to avoid context rot and rising costs. Use when context is heavy (300K+ tokens estimated) or response quality is degrading. Part of claude-cost-helpers (02-just-one-more-turn).
---

# Split Session

You have reached a point where continuing in this session is likely more expensive than starting fresh. This command saves the current session state and prepares you to continue in a clean context.

## Process

### Step 1: Estimate current context size

Check the context-usage state file to get a turn count, then compute a token estimate:

```bash
SESSION_STATE_FILE="${HOME}/.claude/.session-state/${sessionId}.context-usage"
if [ -f "$SESSION_STATE_FILE" ]; then
    TURN_COUNT=$(wc -l < "$SESSION_STATE_FILE")
    EST_TOKENS=$((TURN_COUNT * 3000))
    echo "Turns tracked: $TURN_COUNT"
    echo "Estimated tokens: $EST_TOKENS (~$((EST_TOKENS / 1000))k)"
else
    echo "No context-usage state file found for this session."
fi
```

Report the result to the user: "This session has approximately ~Nk estimated tokens."

### Step 2: Save the session

Run the `/save-session` flow with a description that includes the estimated token count:

Use the description: `context-split at ~Nk estimated tokens`

This creates a structured handoff file at `~/.claude/sessions/YYYY-MM-DD-context-split-at-Nk-session.md` capturing everything needed to resume.

**Dependency note:** `/split` depends on `/save-session` from Helper 01 (Idle Tax). If `/save-session` is not available, manually capture the following before opening a new session:
- What you are building and current goal
- Files modified and their state
- What has and has not worked
- The single most important next step

### Step 3: Instruct the user

Print the following after the session file is saved:

```
Session saved. Open a fresh Claude Code session and run `/resume-session` to continue.

The fresh session will have a clean context window — lower cost per turn, better
response quality, and no accumulated context rot. Your handoff file contains
everything needed to pick up exactly where this session left off.
```

## Notes

- The token estimate is approximate. It is based on turn count multiplied by a configurable per-turn estimate (default 3000 tokens). Actual token usage depends on message length, tool output size, and file reads — the estimate is a floor, not a ceiling.
- Starting fresh does not mean losing work. The handoff file preserves full state.
- If the session is not yet at a natural stopping point, finish the current task first, then split.

## Companion Hook

This skill is part of the **Just One More Turn** helper (02-just-one-more-turn). The companion hook (`context-usage-monitor.sh`) automatically warns when your context approaches the rot zone. Install the hook for automatic warnings: `cd 02-just-one-more-turn && ./install.sh`
