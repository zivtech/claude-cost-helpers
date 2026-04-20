# Watching Cost — Output Size Monitor for Claude Code

Companion code for [*The Economics of Claude Code, Part 5: The Watching Cost*](https://zivtech.github.io/zivtech-demos/economics-of-claude/watching-cost.html).

## What it does

Tracks how much tool output is accumulating in your Claude Code context window — and warns you before it becomes expensive. Every byte of tool output that appears in the conversation sits there permanently: every subsequent API call in the session reprocesses it in full. A 10,000-line test run, a verbose build log, a full file read — each one adds to the "watching cost" you pay on every future message until you start fresh.

This hook fires after every tool use, measures the response size, accumulates a running estimate per session, and surfaces warnings at two levels:

- **Per-call**: when a single tool response exceeds ~5,000 tokens
- **Cumulative**: escalating warnings at 25K, 50K, and 100K tokens of accumulated output

It also installs one slash command:

- `/to-file` — run a command and redirect its output to a temp file, keeping large output out of context entirely

## What you get

| File | Purpose |
|---|---|
| `output-size-monitor.sh` | Bash hook that fires on every `PostToolUse`. Measures `tool_response` size, accumulates per-session totals, warns when thresholds are crossed. |
| `commands/to-file.md` | `/to-file` slash command — runs a command and captures output to `/tmp/`, returning only a path, line count, and head/tail preview |
| `settings-snippet.json` | The `hooks` block to merge into `~/.claude/settings.json` |
| `install.sh` | Copies files into place, backs up anything it overwrites, prints the snippet to merge |

Total install footprint: one script, one slash command, one JSON snippet to merge. Zero dependencies beyond `bash`, `python3` (for JSON parsing — already present on macOS and most Linux), and `date`.

## Install

```bash
git clone <this-repo> claude-cost-helpers
cd claude-cost-helpers/watching-cost
./install.sh
```

The script:

1. Creates `~/.claude/hooks/cost-helpers/watching-cost/` and copies the hook in
2. Copies the slash command file into `~/.claude/commands/` (backs up any existing `to-file.md` first)
3. Prints the JSON snippet you need to merge into `~/.claude/settings.json` and the verification steps

It does **not** automatically modify `settings.json` — JSON merging is the kind of thing where a one-liner gone wrong silently breaks your whole Claude Code config. Manual merge takes ten seconds and keeps you in control.

## What you'll see

**Per-call warning** (single large response):

```
That tool returned ~12k tokens of output now sitting in context. Every future
message in this session will reprocess it. Consider: (1) redirecting long
output to a file with `/to-file`, (2) using a subagent for output-heavy work,
(3) being specific about what you need (e.g., 'show me lines 40-60' instead
of 'show me the file').
```

**Cumulative warning** (accumulated across multiple tool calls):

```
Cumulative tool output in this session: ~25K tokens. This 'watching cost' is
reprocessed on every message. Consider using `/to-file` for large outputs
going forward.
```

```
Cumulative tool output: ~50K tokens. Context is getting expensive. Consider
`/split` or start a fresh session to avoid carrying this weight forward.
```

```
Cumulative tool output: ~100K tokens. This session is carrying significant
dead weight. A fresh session would save real money.
```

Each cumulative threshold fires **only once** per session. If both a per-call and a cumulative warning trigger on the same tool use, they are combined into a single message. All warnings are **informational, not blocking** — your work always proceeds.

## How it works

The hook fires on every `PostToolUse`. It:

1. Calls `python3` once to extract `session_id` and measure `tool_response` length. The `tool_response` field may be a string, a dict (e.g. `{"stdout": "...", "stderr": "..."}` for Bash), or null — the script handles all three.
2. Estimates tokens as `char_count / 4` (a reasonable approximation for typical tool output).
3. Reads the cumulative total from `~/.claude/.session-state/<session_id>.output-tokens` (defaults to 0 if missing).
4. Adds the current call's estimate and writes the new total back.
5. Checks the per-call threshold.
6. Checks each cumulative threshold, consulting `~/.claude/.session-state/<session_id>.output-warned-at` to ensure each fires only once.
7. Outputs hook-contract JSON: `additionalContext` for warnings, `suppressOutput: true` for clean runs.

The hook is designed to be fast — a single `python3` call, two small file reads, one write. It should complete well within the 5-second timeout.

## Configuration

| Environment variable | Default | What it controls |
|---|---|---|
| `CLAUDE_OUTPUT_THRESHOLD` | `5000` | Per-call token threshold. Set lower (e.g. `100`) to test the hook on small outputs. |
| `CLAUDE_OUTPUT_CUMULATIVE_THRESHOLDS` | `25000,50000,100000` | Comma-separated list of cumulative thresholds. Customize to taste. |

Set these in your shell profile or in `~/.claude/settings.json` under `env`.

## Uninstall

```bash
./uninstall.sh
```

Or manually:

```bash
rm -rf ~/.claude/hooks/cost-helpers/watching-cost
rm ~/.claude/commands/to-file.md
# Then remove the PostToolUse hook block from ~/.claude/settings.json
```

If `install.sh` backed up an existing `to-file.md` (named `*.bak.YYYYMMDD-HHMMSS`), `uninstall.sh` restores it.

## Why this exists

The prompt cache gets most of the attention in Claude Code cost discussions. But there's a second, quieter cost driver: the output you've already seen. Every tool call that returns a large response adds to the context window. That context doesn't go anywhere — it rides along on every subsequent API call for the life of the session, being tokenized and billed each time.

The fix isn't "don't read files" or "don't run tests." It's knowing when you've accumulated enough that a fresh session would be cheaper than continuing. The warning is designed to give you that signal at the moment it matters — not in a post-mortem cost review.

For the full story see [*The Economics of Claude Code, Part 5: The Watching Cost*](https://zivtech.github.io/zivtech-demos/economics-of-claude/watching-cost.html).

## Provenance

This is a productized version of hooks the author has been running in his personal Claude Code config. The threshold numbers (5K per-call, 25K/50K/100K cumulative) are based on observed session patterns where context bloat became the dominant cost factor. They are defaults, not laws — see Configuration above.

## License

GPL-3.0-or-later. See LICENSE.
