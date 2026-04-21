# Live Codex Evaluation Results

Date: 2026-04-20

Environment:

- local runtime: `codex-cli 0.114.0`
- authenticated Codex home: `~/.codex`
- repo-local hooks file: `.codex/hooks.json`
- per-run feature flag: `--enable codex_hooks`
- evaluation model for live probes: `gpt-5.4-mini` with `model_reasoning_effort="low"`

## Executive result

The original "no live Codex evidence" risk is now resolved.

The live results support a narrower Codex post, not a one-to-one mirror of the Claude series.

Measured Codex-supported claims:

1. Long sessions accumulate materially more input context than a fresh session with a short handoff.
2. Large Bash output is directly measurable and is a credible Codex analog for a narrowed `watching-cost` story.
3. The idle-gap thesis must be rewritten for Codex. In the observed `exec`/`resume` path, a >5 minute gap did **not** produce a visible cached-input collapse.

## Important runtime finding

### `codex exec --json` is the strongest evidence surface for non-interactive measurement

The most useful evidence came from `codex exec --json` and `codex exec resume --json`:

- `input_tokens`
- `cached_input_tokens`
- `output_tokens`
- `command_execution.aggregated_output`

This is stronger than the passive hook harness for non-interactive measurement.

### Hooks were only partially observed in non-interactive runs

Observed in non-interactive `exec` mode:

- `SessionStart`
- `Stop`

Not observed in the local hook log during those same runs:

- `UserPromptSubmit`
- `PostToolUse`

That means the harness is useful, but the package should explicitly separate:

- hook evidence,
- from `exec --json` evidence.

## Scenario A: Idle-gap probe

Method:

- one initial `codex exec`
- one same-session `codex exec resume` after 30 seconds
- one same-session `codex exec resume` after 360 seconds
- same model and same broad prompt shape across all three turns

Results:

| Turn | Input tokens | Cached input tokens | Cached ratio |
|---|---:|---:|---:|
| Turn 1 | 36,747 | 36,224 | 98.58% |
| Turn 2, 30s gap | 73,520 | 72,448 | 98.54% |
| Turn 3, 360s gap | 110,321 | 108,672 | 98.51% |

Interpretation:

- The observed `exec`/`resume` path did **not** show a Claude-style cliff after a >5 minute gap.
- This does **not** prove that idle gaps never matter in Codex.
- It does prove that the Claude "5-minute idle tax" framing is not portable 1:1 into a Codex post.

Safe public wording:

- "idle gaps can change cache economics and should be measured in Codex on their own terms"

Unsafe public wording:

- "Codex has the same 5-minute idle tax as Claude"

## Scenario B: Bash-output carrying cost

Method:

- verbose run: one Bash command prints 16,000 `X` characters directly to the session
- filtered run: one Bash command writes the same data to a file, then a second Bash command prints only the byte count

Command-output measurements from `exec --json`:

### Verbose

- command output chars: `16,001`

### Filtered

- file-write command output chars: `0`
- `wc -c` command output chars: `35`

Interpretation:

- This is strong evidence for a narrowed Codex `watching-cost` helper concept on **Bash output**.
- The meaningful comparison is command-output size, not total turn usage, because the filtered run used two commands and more instruction text.

Safe public wording:

- "large Bash output is measurable dead weight in Codex CLI workflows"

Unsafe public wording:

- "all tool output in Codex is equally hookable and measurable"

## Scenario C: Long-session accumulation vs fresh handoff

Method:

- four trivial same-session turns in one thread
- then one fresh session with a short handoff prompt

Results:

| Run | Input tokens | Cached input tokens |
|---|---:|---:|
| Turn 1 | 36,746 | 2,432 |
| Turn 2 | 73,515 | 38,656 |
| Turn 3 | 110,308 | 41,088 |
| Turn 4 | 147,126 | 77,824 |
| Fresh handoff session | 36,757 | 36,224 |

Interpretation:

- Same-session input cost grows materially as the conversation accumulates.
- A fresh session with a short handoff resets the working surface dramatically.
- This is enough evidence to support a Codex version of `just-one-more-turn`, framed around session growth and fresh-session hygiene instead of exact pricing multipliers.

## Config-driven reasoning finding

The global local runtime config on this machine currently includes:

- `model = "gpt-5.4"`
- `model_reasoning_effort = "xhigh"`

That makes the old Claude `effort-control` story non-portable as written.

What is supportable for Codex is:

- explicit model/reasoning hygiene,
- not a Claude-specific env-pin defense.

## Updated publication recommendation

### Supportable now

A narrowed Codex post or comparison post that focuses on:

- long-session accumulation,
- Bash-output carrying cost,
- explicit model/reasoning hygiene,
- and the need to measure cache behavior in Codex rather than assume the Claude story transfers.

The repository now also has a concrete implementation lane under `codex-helpers/` for the narrowed subset:

- `stop-snapshot`
- `reasoning-hygiene-banner`
- `turn-rot` (experimental)
- `bash-output-watch` (experimental)

Operational default recommendation:

- install `stop-snapshot` and `reasoning-hygiene-banner` by default
- opt into `turn-rot` and `bash-output-watch` only when you are explicitly testing the hook coverage of your Codex runtime
- use the Codex lane's `capability-probe.sh` to summarize what the current runtime is actually observing before enabling experimental helpers

### Not supportable now

A post claiming:

- the same exact idle-tax story,
- automatic file-read/subagent detection parity,
- automatic pre-compact safety parity,
- or a full Codex helper suite equivalent to the Claude helper set.

## Remaining limitations

- the reproducible `codex-helpers/live-smoke.sh` run confirms `SessionStart` and `Stop` invocations in non-interactive `exec` mode
- that same smoke run still does not show `UserPromptSubmit` or `PostToolUse` firing in the non-interactive `exec` path on this runtime
- `turn-rot` and `bash-output-watch` therefore remain experimental pending interactive confirmation
- no authoritative reasoning-effort telemetry was exposed in the hook payloads
- non-Bash tool output still lacks a documented hook surface
- local runtime noise remains from:
  - a state DB migration warning
  - an invalid OAuth refresh token on at least one MCP server (`notion`)

Those warnings did not block the successful evaluation runs, but they are operational noise worth isolating in future sessions.
