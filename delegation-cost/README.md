# Delegation Cost — Agent Result Monitor for Claude Code

Companion code for [*The Economics of Claude Code, Part 6: The Delegation Tax*](https://zivtech.github.io/zivtech-demos/economics-of-claude/delegation-tax.html).

## What it does

Tracks how much subagent result data is accumulating in your parent session's context — and warns you before the delegation tax exceeds the delegation benefit. When a subagent finishes, its result lands in the parent context permanently. That result gets reprocessed on every subsequent API call for the rest of the session. The subagent's own context is disposable. Its result is not.

This hook fires after every `Agent` tool use, measures the result size, accumulates a running estimate per session, and surfaces warnings at two levels:

- **Per-result**: when a single agent returns more than ~5,000 tokens
- **Cumulative**: escalating warnings at 20K, 50K, and 100K tokens of accumulated agent results

It also installs one slash command:

- `/delegation-report` — shows per-agent result sizes and estimated carrying cost for the session

## What you get

| File | Purpose |
|---|---|
| `delegation-result-monitor.sh` | Bash hook that fires on every `PostToolUse` matching `^Agent$`. Measures result size, accumulates per-session totals, warns when thresholds are crossed. |
| `commands/delegation-report.md` | `/delegation-report` slash command — shows per-agent breakdown of result sizes and carrying cost estimates |
| `settings-snippet.json` | The `hooks` block to merge into `~/.claude/settings.json` |
| `install.sh` | Copies files into place, backs up anything it overwrites, prints the snippet to merge |

Total install footprint: one script, one slash command, one JSON snippet to merge. Zero dependencies beyond `bash`, `python3` (for JSON parsing — already present on macOS and most Linux), and `date`.

## Install

```bash
git clone <this-repo> claude-cost-helpers
cd claude-cost-helpers/delegation-cost
./install.sh
```

The script:

1. Creates `~/.claude/hooks/cost-helpers/delegation-cost/` and copies the hook in
2. Copies the slash command file into `~/.claude/commands/` (backs up any existing `delegation-report.md` first)
3. Prints the JSON snippet you need to merge into `~/.claude/settings.json` and the verification steps

It does **not** automatically modify `settings.json` — JSON merging is the kind of thing where a one-liner gone wrong silently breaks your whole Claude Code config. Manual merge takes ten seconds and keeps you in control.

## What you'll see

**Per-result warning** (single large agent result):

```
That agent returned ~8K tokens now sitting in context. Every future message
reprocesses it. Consider: (1) tighter prompt constraints ('report in under
200 words'), (2) writing findings to a file instead of returning inline,
(3) splitting the session after synthesizing.
```

**Cumulative warning** (accumulated across multiple agent results):

```
Delegation results in this session: ~20K tokens. The tax is building —
every turn reprocesses all of it. Consider tighter agent prompts going forward.
```

```
Delegation results: ~50K tokens. The carrying cost is significant. Consider
`/split` or writing future agent results to files instead of returning inline.
```

```
Delegation results: ~100K tokens. The delegation tax exceeds the delegation
benefit at this point. A fresh session would save real money.
```

Each cumulative threshold fires **only once** per session. If both a per-result and a cumulative warning trigger on the same agent return, they are combined into a single message. All warnings are **informational, not blocking** — your work always proceeds.

## How it works

The hook fires on every `PostToolUse` matching `^Agent$`. It:

1. Calls `python3` once to extract `session_id` and measure `tool_response` length. The `tool_response` field may be a string, a dict, or null — the script handles all three.
2. Estimates tokens as `char_count / 4` (a reasonable approximation for typical agent output).
3. Reads the cumulative total from `~/.claude/.session-state/<session_id>.delegation-tokens` (defaults to 0 if missing).
4. Adds the current result's estimate and writes the new total back.
5. Appends a per-agent entry to `~/.claude/.session-state/<session_id>.delegation-agents` (used by `/delegation-report`).
6. Checks the per-result threshold.
7. Checks each cumulative threshold, consulting `~/.claude/.session-state/<session_id>.delegation-warned-at` to ensure each fires only once.
8. Outputs hook-contract JSON: `additionalContext` for warnings, `suppressOutput: true` for clean runs.

The hook is designed to be fast — a single `python3` call, two small file reads, one or two writes. It should complete well within the 5-second timeout.

## Configuration

| Environment variable | Default | What it controls |
|---|---|---|
| `CLAUDE_DELEGATION_THRESHOLD` | `5000` | Per-result token threshold. Set lower (e.g. `100`) to test the hook on small agent results. |
| `CLAUDE_DELEGATION_CUMULATIVE_THRESHOLDS` | `20000,50000,100000` | Comma-separated list of cumulative thresholds. Customize to taste. |

Set these in your shell profile or in `~/.claude/settings.json` under `env`.

## Relationship to watching-cost

If you install both `watching-cost` and `delegation-cost`, both hooks will fire on Agent results — `watching-cost` matches all tools (`.*`), while `delegation-cost` matches only `^Agent$`. This is by design:

- **watching-cost** tracks total tool output (builds, file reads, greps, *and* agent results)
- **delegation-cost** tracks agent results specifically, with delegation-aware thresholds and messaging

They use separate state files (`*.output-tokens` vs `*.delegation-tokens`) and separate cumulative thresholds (25K/50K/100K vs 20K/50K/100K). The warnings don't conflict. If you want to avoid both firing on the same agent result, you can change watching-cost's matcher from `.*` to exclude Agent — but in practice, the dual signal is useful: one tells you about total context weight, the other tells you specifically about delegation tax.

## Uninstall

```bash
./uninstall.sh
```

Or manually:

```bash
rm -rf ~/.claude/hooks/cost-helpers/delegation-cost
rm ~/.claude/commands/delegation-report.md
# Then remove the PostToolUse hook block from ~/.claude/settings.json
```

If `install.sh` backed up an existing `delegation-report.md` (named `*.bak.YYYYMMDD-HHMMSS`), `uninstall.sh` restores it.

## Why this exists

Delegation is the right pattern — it keeps file reads and heavy exploration out of the parent context (Part 3). But every subagent result that lands in the parent stays there permanently. A research swarm that dispatches 5 agents can easily return 25K tokens of combined results. Over 20 subsequent turns, that's 500K tokens of reprocessing. The invoice (what the agents spent) is visible. The tax (what you pay to carry their results) is not.

The fix is behavioral: constrain what comes back ("report in under 200 words"), write heavy findings to files instead of returning inline, and split sessions after heavy delegation rounds. This hook makes the accumulation visible so you can make that call at the moment it matters.

For the full story see [*The Economics of Claude Code, Part 6: The Delegation Tax*](https://zivtech.github.io/zivtech-demos/economics-of-claude/delegation-tax.html).

## Provenance

This is a productized version of patterns the author observed while using multi-agent workflows extensively. The threshold numbers (5K per-result, 20K/50K/100K cumulative) are based on observed delegation patterns where carrying cost became the dominant cost factor. They are defaults, not laws — see Configuration above.

## License

GPL-3.0-or-later. See LICENSE.
