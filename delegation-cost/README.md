# Delegation Cost — Agent Result Monitor for Claude Code

Companion code for [*The Economics of Claude Code, Part 6: The Delegation Tax*](https://zivtech.github.io/zivtech-demos/economics-of-claude/delegation-tax.html).

## What it does

Tracks how much subagent result data is accumulating in your parent session's context — and warns you before the delegation tax exceeds the delegation benefit. When a subagent finishes, its result lands in the parent context permanently. That result gets reprocessed on every subsequent API call for the rest of the session. The subagent's own context is disposable. Its result is not.

This hook fires after every `Agent` tool use, measures the result size, accumulates a running estimate per session, and surfaces warnings at three levels:

- **Per-result**: when a single agent returns more than ~5,000 tokens
- **Cumulative**: escalating warnings at 20K, 50K, and 100K tokens of accumulated agent results
- **Cache cooling**: when the agent ran long enough that the parent's prompt cache expired (or came within the lead time of expiring). A foreground agent blocks the parent, so the parent's cache ages for the whole run; if the run outlasts the TTL, the call that consumes the result re-writes the entire prefix. The TTL in effect (1-hour or 5-minute), the cached context size and the model are read from the session transcript, so the dollar figure is your figure.

It also installs one slash command:

- `/delegation-report` — shows per-agent result sizes and what carrying them costs *this* session: priced from the model and cache TTL read from the transcript, computed locally by `delegation_report.py` (zero Claude tokens), with a verdict on whether delegation is actually your tax

## What you get

| File | Purpose |
|---|---|
| `delegation-result-monitor.sh` | Bash hook that fires on every `PostToolUse` matching `^Agent$`. Measures result size, accumulates per-session totals, warns when thresholds are crossed. |
| `delegation_report.py` | Computes the `/delegation-report`: reads the per-agent state file plus the transcript's last main-thread assistant message (model, TTL, prefix size) and prices warm carrying cost per API call, the results' share of a cold re-write, and a verdict |
| `commands/delegation-report.md` | `/delegation-report` slash command — runs `delegation_report.py` inline and shows its output verbatim |
| `settings-snippet.json` | The `hooks` block to merge into `~/.claude/settings.json` |
| `install.sh` | Copies files into place, backs up anything it overwrites, prints the snippet to merge |
| `test.sh` | Fixture tests — synthetic transcripts for every cache state (warm / near-expiry / expired on both TTLs, fallback, one-warning-per-dispatch) plus the size thresholds. `./test.sh`, exit 0 = all pass |

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

**Cache-cooling warning** (the agent outran the parent's prompt cache):

```
PARENT CACHE EXPIRED while this agent ran (1h 15m of a 1-hour TTL): the call
that consumes this result re-writes ~300K cached tokens, about $6.00 vs $0.30
warm (20x).
Cache writes cost 2x input price on the 1-hour TTL. Nothing to save on this
one. Next time an agent may outlast the TTL: (1) dispatch it with
run_in_background so the parent keeps making calls and its cache stays warm,
(2) split the work into shorter agents, or (3) /save-session before
dispatching so resuming fresh is free.
```

A softer variant fires when the run came within the lead time of the TTL (15 minutes on the 1-hour TTL, 1 minute on the 5-minute one): the cache is refreshed by the call that consumes the result, but the next agent that long will not be so lucky. One warning per dispatch — parallel agents launched from one turn share a dispatch row, so the first result to cross a level warns and the rest stay quiet.

On the 1-hour TTL this warning should be rare: an agent has to run for 45+ minutes to trigger it. If it fires often, that is the signal — not the noise.

**`/delegation-report`** (computed, not estimated):

```
## Delegation Report — claude-fable-5-1, 1-hour TTL

| # | Time     | Result size | Warm read per API call |
|---|----------|-------------|------------------------|
| 1 | 14:32:10 | ~3K tokens  | $0.0007                |
| 2 | 14:35:41 | ~8K tokens  | $0.0020                |
| 3 | 14:41:02 | ~2K tokens  | $0.0005                |

**Total:** ~13K tokens from 3 agent results, 1 of them over 5K — 4% of the ~300K-token cached prefix.
**Warm carrying cost:** $0.0032 per API call (cache read at 0.025x input), ~$0.065 over the next 20 API calls. Every tool call is a call, not just every message.
**Cold exposure:** if the cache lapses once (an agent or an idle gap outlasting the 1-hour TTL), the whole prefix re-writes for $6.00; these results' share is $0.26, 80x their warm read (2x input).

**Verdict:** delegation is not your tax here: 4% of the prefix at $0.0032 per call. If this session feels expensive, it is the other 96%: /save-session or /split for context size, not for agent results.
```

v1 of the command had Claude multiply by a hardcoded $1.50/MTok warm rate and a made-up $5/MTok "blended" rate — Opus-4-era numbers computed in-context. On Fable 5.1 the warm rate is $0.25/MTok; on Opus 5 it is $0.50. The report now reads the model and TTL from the transcript and does the arithmetic outside the model.

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
8. Runs the cache-cooling check: reads the **last main-thread assistant message** in `transcript_path` — the one that dispatched this agent — scanning the file backwards in blocks. Its `usage.cache_creation` breakdown says which TTL is in effect (`ephemeral_1h_input_tokens > 0` → 1-hour, otherwise 5-minute), its token counts give the cached context size, its `model` gives the price, and its timestamp is the parent's last API call. The gap from that timestamp to now is how long the cache has aged. Nothing is hardcoded and nothing depends on another helper's state file; a fresh subagent row is skipped (`isSidechain`). A `<session_id>.delegation-cache-warned` file keeps it to one warning per dispatch row.
9. Outputs hook-contract JSON: warnings reach Claude via `hookSpecificOutput.additionalContext` (the documented `PostToolUse` channel) and reach you via a one-line `systemMessage`; clean runs emit `suppressOutput: true`.

The hook is designed to be fast — two `python3` calls, a tail read of the transcript, a few small state files. It should complete well within the 5-second timeout.

## Configuration

| Environment variable | Default | What it controls |
|---|---|---|
| `CLAUDE_DELEGATION_THRESHOLD` | `5000` | Per-result token threshold. Set lower (e.g. `100`) to test the hook on small agent results. |
| `CLAUDE_DELEGATION_CUMULATIVE_THRESHOLDS` | `20000,50000,100000` | Comma-separated list of cumulative thresholds. Customize to taste. |
| `CLAUDE_DELEGATION_FILE_THRESHOLD` | `8000` | Per-result size at which the warning switches from "tighten the prompt" to "have the agent write findings to a file". |
| `CACHE_TTL_SECONDS` | *(detected)* | Force the cache TTL (`3600` or `300`) instead of reading it from the transcript. Same knob as idle-tax. Also the only way the check runs when the hook input has no `transcript_path` (older Claude Code); it then falls back to idle-tax's prompt timestamp, an upper bound on the gap. |
| `CACHE_WARN_SECONDS` | `900` on the 1-hour TTL, `60` on the 5-minute one | Lead time before TTL expiry at which the softer "came within N of expiring" warning fires. |

Set these in your shell profile or in `~/.claude/settings.json` under `env`. (`CLAUDE_CACHE_COLD_THRESHOLD`, v1's fixed 240-second knob, is gone — the TTL is read, not assumed.)

## The cache TTL changed (September 2026)

v1 of the cache check assumed Anthropic's 5-minute prompt-cache TTL (a fixed 240-second threshold) and measured idle time from idle-tax's `.last-activity` file, i.e. from your last *prompt*. Claude Code sessions now normally run on the **1-hour** TTL (written at 2× input price, so a cold call is 20× a warm hit rather than 12.5×) and drop back to 5 minutes only in usage overage. On the 1-hour TTL the old check produced exactly the dead output this repo exists to avoid: "cache likely went cold (~17 min idle)" after a turn that was ten minutes of work plus a seven-minute agent, when the cache had 43 minutes left. v2 reads the TTL and the real last-call timestamp from the transcript, prices the re-write from the real context size and model, and no longer depends on idle-tax being installed. If you installed before September 2026, re-run `./install.sh`.

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
