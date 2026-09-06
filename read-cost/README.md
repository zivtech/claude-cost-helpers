# Read Cost — price a file read before it lands in context

## The problem

Every other helper in this repo warns *after* the tokens have arrived. `watching-cost` measures `tool_response` once the output is back. `subagent-isolation` counts files already read. By the time either fires, the cache write is paid and the content sits in the prefix for the rest of the session.

There is exactly one moment when a range read, a grep, or a delegation is still free: before the `Read` executes. This hook fires there.

## What it does

Fires on `PreToolUse` for `Read`. Stats the target file, estimates its token count, prices what pulling it into context costs *this* session — model and cache TTL read from the transcript — and warns when that crosses a dollar threshold.

```
read-cost: routes.ts is ~30,000 tokens — reading it costs ~$0.60 on
claude-opus-5 ($0.30 cache write + $0.30 over the next 20 calls).
Read a range, grep, or delegate to haiku.
```

The full message reaching Claude names the alternatives with real numbers: what 200 of the file's lines would cost instead, and that a `model: "haiku"` subagent reads at $1/MTok into its own context rather than yours.

## It never blocks — deliberately

The obvious design is to deny the read and force a cheaper path. That inverts the economics.

A `PreToolUse` block denies the tool call, so Claude must emit *another* assistant message with a different call. That extra turn re-reads the entire cached prefix. Measured across 2,331 local transcripts, the median cached prefix is 203,816 tokens on Opus and 263,072 on Fable — so one extra round trip costs **$0.10 on Opus, $0.066 on Fable**, before the replacement call does any work.

Against that, shunting a 350-line (~3,500 token) file away from Opus saves about $0.058. **The block spends $0.10 to save $0.058.** Break-even is a prefix of roughly 116K tokens; real sessions run well past it. On Opus at the median prefix, blocking only pays above ~5,800 tokens — and only 14% of observed reads are even that large.

A warning costs nothing. The `Read` proceeds in the same turn; the hook just makes the price visible while the alternative is still on the table.

## The gate is dollars, not lines

A line or token threshold tuned for one model is noise or silence on another — the same file costs 5x more to carry on Fable than on Sonnet. So the threshold is `$0.15` of *this session's* money:

```
cost = tokens x price_in x (write_mult(ttl) + read_mult(model) x horizon)
```

At the default `$0.15` threshold and a 20-call horizon, measured against 3,491 real reads:

| Session model | Fires on | Equivalent size |
|---|---:|---:|
| Opus 5 (1h TTL) | 8.9% of reads | >= 7,500 tok |
| Fable 5.1 (1h TTL) | 12.0% of reads | >= 6,000 tok |
| Sonnet 5 (1h TTL) | ~0% of reads | >= 18,750 tok |

Roughly one read in ten on the expensive models, near-silence on Sonnet. That asymmetry *is* the dollar gate working: carrying a file on Sonnet genuinely costs less, so it genuinely warrants less interruption. If you want it audible on Sonnet, lower `CLAUDE_READ_COST_THRESHOLD`.

## Install

```bash
cd read-cost && ./install.sh
```

Then merge the printed block into `~/.claude/settings.json` and restart Claude Code.

## What you get

| File | Purpose |
|---|---|
| `hooks/read-cost-monitor.sh` | The `PreToolUse` hook. Stats the file, prices it from the transcript's model + TTL, warns past the dollar threshold. Never blocks. |
| `settings-snippet.json` | The `hooks` block to merge into `~/.claude/settings.json` |
| `install.sh` / `uninstall.sh` | Copy into place / remove; neither touches `settings.json` |
| `test.sh` | 30 fixture cases — pricing on four model/TTL combinations, the dollar gate, bounded reads, dedup, caps, env overrides, fail-open robustness. `./test.sh`, exit 0 = all pass |

No slash command, on purpose. The two things this hook recommends already have consumers: `/delegate` (subagent-isolation) and `/to-file` (watching-cost). A third command that duplicated them would be ritual, not tooling.

## Configuration

| Env var | Default | Meaning |
|---|---|---|
| `CLAUDE_READ_COST_THRESHOLD` | `0.15` | Dollars. Below this, silent. |
| `CLAUDE_READ_COST_HORIZON` | `20` | API calls assumed remaining, for the carry half of the estimate. Matches `delegation-cost`. |
| `CLAUDE_READ_COST_MAX_WARNINGS` | `5` | Per session. A warning you learn to ignore is worse than no warning. |

Each file warns at most once per session.

## How the estimate can be wrong

Stated plainly, because a cost helper that hides its error bars is worse than none:

- **The horizon is an assumption, not a measurement.** The carry half assumes ~20 more API calls. Read something in the last five turns of a session and the real carry is a quarter of the figure; read it at the start of a long session and the figure is low. The message says so. This is the single largest source of error.
- **Tokens are estimated at chars/4.** `Read` adds line-number prefixes, so the true context cost is *higher* than shown. The hook under-warns rather than over-warns.
- **Compaction can evict the content early**, which also makes the carry half an overestimate.
- **It only sees `Read`.** `cat`/`head`/`tail` through `Bash`, and large `Grep` results, pull just as much into context and are not covered. Parsing shell commands reliably is a bigger job than this hook is; `watching-cost` catches those after the fact.
- **It cannot know whether you needed the file.** Reading 30,000 tokens you actually use is a good trade. The hook prices the read; it does not judge it.

## Uninstall

```bash
cd read-cost && ./uninstall.sh
rm -f ~/.claude/.session-state/*.read-cost-warned
```

Then delete the `hooks.PreToolUse` entry matching `^Read$` from `~/.claude/settings.json`.

## Provenance

Prompted by [*Portal by Spotify cut my Claude Code token usage by 90%*](https://engineering.atspotify.com/2026/9/portal-by-spotify-cut-my-claude-code-token-usage-by-90), which routes large reads to a cheap worker model via blocking `PreToolUse` hooks. The intervention point is the good idea and this helper takes it. The blocking is the part that does not survive the prefix math above, and the article's headline 90% is measured as `digest_tokens / file_tokens` — a ratio that is ~90% by construction and says nothing about whether the session got cheaper.

## License

MIT — see `LICENSE`.
