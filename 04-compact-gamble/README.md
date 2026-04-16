# Compact Gamble — Pre-Compact Safety Net for Claude Code

Companion code for *The Economics of Claude Code, Part 4: The Compact Gamble*.

## The problem

When Claude Code's context window fills up, it offers to compact — summarize the session and continue on the summary. The problem: compaction is lossy. Claude decides what to keep. You don't get to review what was dropped. There's no recovery if a critical decision, file state, or error message gets discarded in the summary.

The other problem: compaction is often the wrong economic choice. Keeping a large, stale session alive via repeated compaction costs more per message than starting fresh with a lean handoff. You're paying to extend a session that a clean restart would beat.

## What it does

This helper installs a `PreCompact` hook that fires before every compaction event. It does two things:

**1. Writes a metadata marker file** to `~/.claude/sessions/` so you have a permanent record of when each compact happened. If you later realize you lost something, the marker tells you exactly when — and you can cross-reference the timestamp against your git history or notes.

**2. Injects a prompt into Claude's context** asking it to summarize the key context before the compact runs. That summary becomes part of what survives into the compacted session. Without this, Claude picks what to keep with no guidance from you.

**Important:** The hook writes a metadata marker, not a full session save. The hook script runs in bash and cannot access your conversation content — that lives in Claude's context. The real value is the `additionalContext` message that instructs Claude to preserve what matters before compaction executes.

## What you get

| File | Purpose |
|---|---|
| `pre-compact-backup.sh` | Bash hook that fires on `PreCompact`. Writes a timestamped marker file and prompts Claude to summarize context before the compact runs. |
| `commands/safe-compact.md` | `/safe-compact` slash command — saves the session via `/save-session` and explains why starting fresh is usually cheaper than compacting. |
| `settings-snippet.json` | The `hooks` block to merge into `~/.claude/settings.json` |
| `install.sh` | Copies files into place, backs up anything it overwrites, prints the snippet to merge |

Total install footprint: one script, one slash command, one JSON snippet to merge. Zero dependencies beyond `bash`, `python3` (already present on macOS and most Linux), and `date`.

## Install

```bash
cd claude-cost-helpers/04-compact-gamble
./install.sh
```

The script:

1. Creates `~/.claude/hooks/cost-helpers/compact-gamble/` and copies the hook in
2. Copies the slash command file into `~/.claude/commands/` (backs up any existing `safe-compact.md` first)
3. Prints the JSON snippet you need to merge into `~/.claude/settings.json` and the verification steps

It does **not** automatically modify `settings.json` — JSON merging is the kind of thing where a one-liner gone wrong silently breaks your whole Claude Code config. Manual merge takes ten seconds and keeps you in control.

**Dependency:** `/safe-compact` calls `/save-session` from Helper 01 (Idle Tax). Install that helper first if you want the full flow.

## What you'll see

When compaction triggers (manually or automatically), Claude will receive this context before the compact runs:

```
PRE-COMPACT BACKUP: Compaction is about to run. A marker has been saved to
~/.claude/sessions/<session-id>-pre-compact-YYYYMMDD-HHMMSS.md. Compaction
is lossy — Claude decides what to keep. If something critical gets dropped,
you can reference this marker to know when the compact happened.

IMPORTANT: Before this compact proceeds, please briefly summarize: (1) what
we were working on, (2) key decisions made, (3) current state of files,
(4) the next step. This will be preserved in the compacted context.

Consider: starting fresh with /save-session is often cheaper than compacting.
Compaction keeps a stale session alive; a fresh session starts with a clean,
warm cache.
```

Claude will produce the summary before compaction runs, and that summary gets folded into the compacted context. The marker file gives you an external timestamp record independent of Claude's memory.

## How it works

The hook fires on every `PreCompact` event. It:

1. Extracts `sessionId` (with `session_id` fallback) and `trigger` from the hook payload
2. Creates `~/.claude/sessions/` if it doesn't exist
3. Writes a marker file named `<sessionId>-pre-compact-<timestamp>.md`
4. Outputs a `{"continue": true, "additionalContext": "..."}` response

The `additionalContext` field injects the warning and summary request into Claude's next turn — which happens to be the turn immediately before compaction executes. Claude reads the request, writes the summary, and then the compact runs with that summary already in context.

Output always includes `"continue": true` — the hook is informational and never blocks compaction.

## Configuration

The hook has no user-configurable thresholds. It fires on every `PreCompact` event unconditionally.

The marker files accumulate in `~/.claude/sessions/`. They're small (under 1KB each). If you want to clean up old ones:

```bash
# Remove markers older than 30 days
find ~/.claude/sessions -name '*-pre-compact-*.md' -mtime +30 -delete
```

## Uninstall

```bash
./uninstall.sh
```

Or manually:

```bash
rm -rf ~/.claude/hooks/cost-helpers/compact-gamble
rm ~/.claude/commands/safe-compact.md
# Then remove the PreCompact hook block from ~/.claude/settings.json
```

If `install.sh` backed up an existing slash command file (named `*.bak.YYYYMMDD-HHMMSS`), `uninstall.sh` restores it.

## Why this exists

Compaction feels safe because it keeps the session going. In practice it's a bet: you're trusting Claude's summarization to preserve everything that matters, with no visibility into what got dropped and no way to recover it. Sometimes that bet pays off. Sometimes you realize three messages later that a critical constraint was lost in the summary, and you spend the next hour rediscovering it.

This helper doesn't eliminate that risk — it makes it visible and gives Claude a chance to act on it. The marker file is cheap insurance. The summary prompt turns a passive lossy process into an active one.

The deeper recommendation is `/safe-compact`: save the session and start fresh. That's almost always the right move economically and for context hygiene. But when you're going to compact anyway, this makes it as safe as it can be.

For the full analysis see *The Economics of Claude Code, Part 4: The Compact Gamble*.

## Provenance

This is a productized version of a hook the author runs in his personal Claude Code config. The pattern of injecting summary prompts via `additionalContext` before destructive operations is battle-tested across months of daily use. What's new is packaging it for sharing and documenting the economics clearly.

## License

MIT. See LICENSE.
