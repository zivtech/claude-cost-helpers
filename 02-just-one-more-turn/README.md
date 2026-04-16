# Just One More Turn — Context Usage Monitor for Claude Code

Companion code for *The Economics of Claude Code, Part 2: The "just one more turn" trap*.

## What it does

Warns you when your Claude Code session context has grown large enough to degrade response quality and inflate cost. As a session accumulates turns, the context window fills — and every subsequent turn pays to re-read all of it. Eventually you hit the rot zone: each turn costs more and produces worse results than a fresh session would. There's no native warning for this. This package adds one.

It also installs a slash command for when the warning fires:

- `/split` — save the current session as a structured handoff and prepare to continue in a clean context

**Note on what is tracked:** This hook tracks turn count only — one line appended per `UserPromptSubmit` event. It does not measure actual token usage, tool output size, or file read volume. The token estimate is turns × a configurable per-turn constant (default 3000). Treat the estimate as a rough floor, not a precise ceiling. Actual usage for heavy sessions (many file reads, long tool outputs) will be higher.

## What you get

| File | Purpose |
|---|---|
| `context-usage-monitor.sh` | Bash hook that runs on every user prompt. Appends a timestamp to a per-session turn log. Estimates token usage from turn count and warns at configurable thresholds. |
| `commands/split.md` | `/split` slash command — estimates context size, runs `/save-session`, and instructs you to continue in a fresh session. |
| `settings-snippet.json` | The `hooks` block to merge into `~/.claude/settings.json` |
| `install.sh` | Copies files into place, backs up anything it overwrites, prints the snippet to merge |
| `uninstall.sh` | Removes files, restores backups, prints the settings.json cleanup instructions |

Total install footprint: one script, one slash command, one JSON snippet to merge. Zero dependencies beyond `bash`, `python3` (for JSON parsing — already present on macOS and most Linux), and `date`.

**Dependency:** `/split` calls `/save-session` from Helper 01 (Idle Tax). Install Helper 01 first, or follow the manual fallback instructions in `commands/split.md`.

## Install

```bash
git clone <this-repo> claude-cost-helpers
cd claude-cost-helpers/02-just-one-more-turn
./install.sh
```

The script:

1. Creates `~/.claude/hooks/cost-helpers/just-one-more-turn/` and copies the hook in
2. Copies the `/split` slash command into `~/.claude/commands/` (backs up any existing `split.md` first)
3. Prints the JSON snippet you need to merge into `~/.claude/settings.json` and verification instructions

It does **not** automatically modify `settings.json` — JSON merging is the kind of thing where a one-liner gone wrong silently breaks your whole Claude Code config. Manual merge takes ten seconds and keeps you in control.

## What you'll see

After install, as your session accumulates turns, the hook surfaces warnings in Claude's response context:

**At ~70% of threshold (soft warning):**
```
CONTEXT HEADS-UP (~210k est): Context is getting heavy (~210k est). You're
approaching the rot zone where quality degrades and cost per turn keeps climbing.

No action needed yet — but if this session runs much longer, consider /split.
```

**At ~90% of threshold:**
```
CONTEXT WARNING (~270k est): Context is getting heavy (~270k est). Consider
/split to start fresh with a handoff.

Response quality tends to degrade as the context window fills. Starting a new
session now is cheaper and produces better results than continuing here.
```

**At 100%+ of threshold:**
```
CONTEXT ROT ZONE (~300k est): Context is past the rot zone (~300k est). Quality
and cost are both degrading. /split recommended.

At this size, each turn re-reads the full context. You are paying for tokens
that are diluting rather than improving results.

Run /split to save a handoff and continue in a clean session.
```

Under 70%, the hook stays silent.

All warnings are **informational, not blocking** — your prompt always proceeds. The point is to make the cost visible so you can choose, not to interrupt your work.

## How it works

The hook fires on every `UserPromptSubmit`. It appends the current Unix timestamp as a new line to `~/.claude/.session-state/<sessionId>.context-usage`. The line count equals the turn count for this session.

Each invocation:

1. Appends a timestamp (recording the new turn)
2. Counts lines in the state file (= total turns)
3. Estimates tokens: `turn_count × CLAUDE_TOKENS_PER_TURN`
4. Computes percentage of `CLAUDE_CONTEXT_THRESHOLD`
5. Emits the appropriate warning tier via `additionalContext`, or stays silent below 70%

Output uses Claude Code's hook contract: `additionalContext` surfaces the warning to Claude in the next turn, `continue: true` ensures the prompt proceeds normally.

## Configuration

| Environment variable | Default | Description |
|---|---|---|
| `CLAUDE_TOKENS_PER_TURN` | `3000` | Estimated tokens per turn. Increase for sessions with heavy tool use or large file reads. |
| `CLAUDE_CONTEXT_THRESHOLD` | `300000` | Token count at which context rot warnings begin (100% tier). 70% and 90% tiers scale from this value. |

Set these in your shell profile or prepend them when testing:

```bash
# Lower threshold for testing (triggers after ~3 turns)
CLAUDE_CONTEXT_THRESHOLD=9000 \
  ~/.claude/hooks/cost-helpers/just-one-more-turn/context-usage-monitor.sh \
  <<< '{"sessionId":"test-session"}'
```

To reset a session's turn counter (e.g., after splitting):

```bash
rm ~/.claude/.session-state/<sessionId>.context-usage
```

## Uninstall

```bash
./uninstall.sh
```

Or manually:

```bash
rm -rf ~/.claude/hooks/cost-helpers/just-one-more-turn
rm ~/.claude/commands/split.md
# Then remove the UserPromptSubmit hook block from ~/.claude/settings.json
```

If `install.sh` backed up an existing `split.md` (named `split.md.bak.YYYYMMDD-HHMMSS`), `uninstall.sh` restores it.

## Why this exists

The idle tax (Helper 01) hits you when you walk away. Context rot hits you when you stay. Both are invisible by default — you only notice in the bill.

The "just one more turn" trap is seductive because each individual turn feels justified. The fix isn't to stop working in long sessions. It's to know when the session has crossed the line from productive to expensive, and to have a frictionless way out: save the state, open a fresh window, keep going.

For the full story see *The Economics of Claude Code, Part 2: The "just one more turn" trap*.

## Provenance

This is a productized version of hooks the author has been running in his personal Claude Code config. The turn-tracking approach is intentionally simple — it is a floor estimate, not a precise measurement. The goal is a useful signal, not a perfect meter.

## License

MIT. See LICENSE.
