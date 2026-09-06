# Usage Report — Where Your Claude Code Spend Actually Goes

Companion code for the *Economics of Claude Code* follow-up on measuring
before optimizing.

## What it does

Reads the transcripts Claude Code already writes under `~/.claude/projects/`
and turns them into a report you can act on — with **zero Claude tokens**:

- **Desktop app vs terminal**, per human turn and per session: dollars, API
  calls per turn, prompt size per call, output per turn.
- **Cost decomposition**: cache reads vs cache writes vs output. (Spoiler: in
  agentic sessions it is mostly cache reads of a large context, many times per
  turn — not output.)
- **Cold resumes**: how many turns followed a >60-minute idle gap and what the
  full-context cache re-writes cost.
- **Delegation audit**: Agent calls per turn, how often an explicit `model`
  was passed, and what share of subagent dollars ran on opus/fable.
  Agent-team teammates are recognized and charged to the session that
  spawned them.
- **Headless `claude -p` jobs** run by plugins and automation, with the top
  spawners named — the part of the bill no session view shows you.
- **Week over week** trend and a **calibration** line against Claude Code's
  own `totalCostUSD` records where they exist.
- A **levers** section that only lists what the numbers actually support.

Two entry points:

- `/usage-report [days]` — run it now, report prints inline (default 28-day window).
- A `SessionStart` hook that refreshes the report **weekly** in a detached
  background process, so the check-in happens without you remembering to do it.

## What you get

| File | Purpose |
|---|---|
| `usage_scan.py` | Transcript scanner: per-session usage, de-duplicated by API response id; folds subagent transcripts into their parent; classifies desktop / terminal / teammate / headless |
| `usage_report.py` | Renders the markdown report; `--since`, `--out`, `--root`, `--quiet` |
| `hooks/sessionstart-usage-report.sh` | SessionStart hook: if the newest report is older than 7 days, regenerate in the background (lock-protected, notification on macOS) |
| `commands/usage-report.md` | `/usage-report` slash command |
| `settings-snippet.json` | The `hooks` block to merge into `~/.claude/settings.json` |
| `test.sh` | Fixture tests against a synthetic transcript tree |

Dependencies: `bash`, `python3` (stdlib only).

## Install

```bash
cd claude-cost-helpers/usage-report
./install.sh
```

Merge the printed `SessionStart` snippet into `~/.claude/settings.json` if you
want the weekly refresh; skip it if you only want `/usage-report` on demand.

## What you'll see

```
| metric                                   | desktop | terminal |
|------------------------------------------|---------|----------|
| sessions / human turns                   | 174 / 817 | 32 / 318 |
| $ per human turn                         | $10.49  | $5.79    |
| API calls per turn                       | 21.9    | 10.3     |
| prompt tokens per call                   | 331K    | 301K     |
| resumes after >60 min idle (count, per session, $) | 143, 0.82, $650 | 12, 0.38, $54 |
| Agent calls per turn / with explicit model | 0.47 / 98% | 0.41 / 96% |
| share of subagent $ on opus/fable        | 52%     | 73%      |
...
## Levers this data points at
- Desktop turns cost 1.8x terminal turns, driven by 22 vs 10 API calls per turn, not by prompt size.
- desktop: 143 resumes after >60 min idle cost ≈$650 in full cache re-writes — let idle-autosave write the handoff and start fresh instead.
```

## How it works

Every transcript line carries `entrypoint` (`cli`, `claude-desktop`,
`sdk-cli`) and every assistant line carries `message.usage` with the four
billable counters plus the cache-TTL breakdown (`cache_creation.ephemeral_1h_
input_tokens` / `ephemeral_5m_input_tokens`). One API response is written as
one line per content block, all with the same `message.id`, so usage is
de-duplicated by id. Subagent transcripts live under
`<project>/<sessionId>/…/*.jsonl` and are folded into the parent.

Classification: `sdk-cli` = headless; a `cli`/`claude-desktop` session with
zero human turns whose messages are `<teammate-message>` = agent-team teammate
(its cost is attributed to the interactive session with the same cwd that was
running when it started); everything else with human turns = interactive.
Human turns exclude system-generated user messages (`<task-notification>`,
`<command-name>`, …).

Pricing uses Anthropic API list rates with cache multipliers (reads 0.1× —
0.025× on Fable/Mythos 5.1 — 5-minute writes 1.25×, 1-hour writes 2×). On a subscription plan the meter
weights things differently, so treat the dollars as relative, not billable —
the *ratios* (desktop vs terminal, reads vs output, this week vs last) are the
point. The calibration line compares against Claude Code's own cost records
when transcripts contain them; on the author's machine it is 1.00.

## Configuration

| Var | Default | Meaning |
|---|---|---|
| `USAGE_REPORT_INTERVAL_DAYS` | `7` | Hook refresh cadence |
| `USAGE_REPORT_WINDOW_DAYS` | `28` | Window each report covers |
| `USAGE_REPORT_DIR` | `~/.claude/usage-reports` | Output directory |
| `USAGE_REPORT_NOTIFY` | `1` | macOS notification when a refresh lands |
| `USAGE_REPORT_DISABLE` | unset | Set to `1` to skip the hook entirely |

## Uninstall

```bash
./uninstall.sh
```

Then remove the `SessionStart` entry pointing at
`sessionstart-usage-report.sh` from `~/.claude/settings.json`. Generated
reports are kept.

## Why this exists

Every other helper in this repo warns at the moment a cost happens. None of
them answer the question that decides what to fix first: *where does the
money actually go?* The first run of this report on the author's own
transcripts (1,200 sessions, Jul–Sep 2026) overturned the working theory —
desktop-app sessions did cost ~2× terminal sessions per turn, but not because
delegation was missing (it was equal in both); because desktop turns made
twice as many full-context API calls and resumed cold contexts twice as often.
Two of the repo's own warnings turned out never to have reached the model
(see the idle-tax README). Measure first.

## Provenance

Written September 1, 2026 from the analysis scripts used for that finding,
generalized and given fixture tests. Everything is stdlib Python and bash.

## License

MIT. See LICENSE.
