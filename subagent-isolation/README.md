# Subagent Isolation — File Count Monitor for Claude Code

Companion code for *The Economics of Claude Code, Part 3: The agent that read 200 files*.

## What it does

Warns you when a single session has read too many unique files. Every file Claude reads is appended to the context window permanently — the content doesn't go away between turns. At 50+ files, you are carrying significant dead weight on every subsequent turn: file contents that were useful once, now just inflating token count and pushing the cost of each API call higher.

The fix is subagent isolation: delegate file-heavy work to an `Agent` tool call so those files live in a fresh context window. Only the summary comes back to your main session.

This package adds a file count warning so you know when you've crossed the threshold, and a `/delegate` slash command to make the handoff easy.

## What you get

| File | Purpose |
|---|---|
| `file-count-monitor.sh` | Bash hook that runs after every `Read`, `Glob`, or `Grep` call. Tracks unique file paths per session in `~/.claude/.session-state/`. Warns at 50 files, re-warns every 25 files after that. |
| `commands/delegate.md` | `/delegate` slash command — guides you through wrapping a task in an `Agent` tool call with `run_in_background: true` |
| `settings-snippet.json` | The `hooks` block to merge into `~/.claude/settings.json` |
| `install.sh` | Copies files into place, backs up anything it overwrites, prints the snippet to merge |

Total install footprint: one script, one slash command, one JSON snippet to merge. Zero dependencies beyond `bash`, `python3` (for JSON parsing — already present on macOS and most Linux), `sort`, and `wc`.

## Install

```bash
git clone <this-repo> claude-cost-helpers
cd claude-cost-helpers/subagent-isolation
./install.sh
```

The script:

1. Creates `~/.claude/hooks/cost-helpers/subagent-isolation/` and copies the hook in
2. Copies the slash command file into `~/.claude/commands/` (backs up any existing `delegate.md` first)
3. Prints the JSON snippet you need to merge into `~/.claude/settings.json`

It does **not** automatically modify `settings.json` — JSON merging is the kind of thing where a one-liner gone wrong silently breaks your whole Claude Code config. Manual merge takes ten seconds and keeps you in control.

## What you'll see

After install, when a session crosses 50 unique files read, the next `Read`, `Glob`, or `Grep` call will surface this in Claude's response context:

```
FILE COUNT WARNING (52 unique files): This session has read 52 unique files.
The context is getting heavy with file content. Consider using the `Agent`
tool to delegate file-heavy work — subagents get their own context window
and only return a summary.

Try: /delegate to offload the next research or audit task to a subagent.

This is informational — your work will proceed normally.
```

Every 25 files after that (at 75, 100, 125, ...) you get a follow-up warning with the updated count. Under the threshold, the hook stays completely silent.

The warning is **informational, not blocking** — your prompt always proceeds. The point is to make the cost legible so you can choose to delegate, not to interrupt your work.

## How it works

The hook fires on every `PostToolUse` event for `Read`, `Glob`, and `Grep`. It:

1. Extracts the session ID and tool name from the hook JSON payload
2. For `Read`: captures `file_path` from `tool_input`
3. For `Glob` and `Grep`: parses absolute paths out of `tool_response`
4. Appends discovered paths to `~/.claude/.session-state/<id>.files-accessed` (one per line)
5. Counts unique paths via `sort -u | wc -l`
6. Checks against the threshold and the last-warned-at count
7. Emits a warning via `additionalContext` if the threshold is crossed and enough new files have been read since the last warning

Output uses Claude Code's hook contract: `additionalContext` surfaces the warning in the next turn, `continue: true` ensures the operation proceeds normally.

## Configuration

Two thresholds are configurable via environment variables — set them in your shell profile or in `~/.claude/settings.json` under `env`:

| Variable | Default | Meaning |
|---|---|---|
| `CLAUDE_FILE_THRESHOLD` | `50` | Unique file count that triggers the first warning |
| `CLAUDE_FILE_WARN_INTERVAL` | `25` | How many additional files must be read before re-warning |

To lower the threshold for testing:

```bash
CLAUDE_FILE_THRESHOLD=5 CLAUDE_FILE_WARN_INTERVAL=3 ./file-count-monitor.sh
```

Or set them permanently in `~/.claude/settings.json`:

```json
{
  "env": {
    "CLAUDE_FILE_THRESHOLD": "10",
    "CLAUDE_FILE_WARN_INTERVAL": "5"
  }
}
```

## Uninstall

```bash
./uninstall.sh
```

Or manually:

```bash
rm -rf ~/.claude/hooks/cost-helpers/subagent-isolation
rm ~/.claude/commands/delegate.md
# Then remove the PostToolUse hook block from ~/.claude/settings.json
```

If `install.sh` backed up an existing `delegate.md` (named `*.bak.YYYYMMDD-HHMMSS`), `uninstall.sh` restores it.

## Why this exists

Reading many files isn't a mistake — it's often exactly what the task requires. The mistake is doing it in the main session when a subagent could do it instead. Every file read into the main context stays there for the life of the session, growing the cost of every subsequent turn even when that file content is no longer relevant.

Subagent isolation is the structural fix: spin up a fresh context, do the heavy reading there, get back a summary. The main session stays lean. The cost of the subagent's file reading doesn't compound into every turn that follows.

This hook makes the problem visible at the moment it becomes expensive, so you can decide when to delegate rather than discovering the bloat after the fact via a surprising invoice.

For the full story see *The Economics of Claude Code, Part 3: The agent that read 200 files*.

## Provenance

This is a productized version of a monitoring pattern the author runs in his personal Claude Code config. The file path tracking logic and threshold-based warning approach are taken directly from working personal tooling. What's new is packaging it for sharing and adding the `/delegate` command to close the loop from warning to action.

## License

GPL-3.0-or-later. See LICENSE.
