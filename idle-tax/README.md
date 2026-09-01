# Idle Tax — Cache TTL Helper for Claude Code

Companion code for [*The Economics of Claude Code, Part 1: The Idle Tax*](https://zivtech.github.io/zivtech-demos/economics-of-claude/idle-tax.html).

## What it does

Warns you when Claude Code's prompt cache has gone cold (or is about to), and
prices the damage in your own numbers. Once the cache expires, your next
message re-writes the entire conversation prefix at a premium over the warm
hit you would otherwise have paid. There is no native warning for this. This
package adds one.

It also installs two slash commands you'll want when the warning fires:

- `/save-session` — capture the current session into a structured handoff file
- `/resume-session` — load the most recent handoff into a fresh session

## The TTL changed — read this if you installed before September 2026

The helper originally hardcoded Anthropic's 5-minute cache TTL and a 12.5×
cold-vs-warm premium (1.25× write vs 0.1× read). Claude Code sessions now
normally run on the **1-hour** TTL, written at **2×** input price — so the
premium for a cold resume is **20×** a warm hit, but it only bites after an
hour of quiet instead of five minutes. Sessions drop back to the 5-minute TTL
when an account is in usage overage, and other setups may still be on it.

v2 stops guessing. The hook reads the TTL that is *actually in effect* from
the last assistant message in the session transcript (`usage.cache_creation.
ephemeral_1h_input_tokens` vs `ephemeral_5m_input_tokens`), measures idle time
from that message's timestamp (the last API call, not your last prompt — a long
agentic turn is not idle time), and prices the re-cache from the real cached
context size and the real model.

Also fixed in v2: the pre-v2 hook emitted its warning as a top-level
`additionalContext` field, which Claude Code does not honor for
`UserPromptSubmit`. In 1,200 transcripts on the author's machine the warning
text never once reached the model. It now uses the documented
`hookSpecificOutput.additionalContext` (what Claude sees) plus `systemMessage`
(what you see — in the terminal *and* the desktop app).

## What you get

| File | Purpose |
|---|---|
| `cache-idle-timer.sh` | UserPromptSubmit hook. Detects the TTL and idle gap from the transcript; warns from 15 minutes before a 1-hour TTL expires (1 minute before a 5-minute one) and again once it has expired, with the dollar cost of the re-write |
| `commands/save-session.md` | `/save-session` — writes a structured handoff to `~/.claude/sessions/YYYY-MM-DD-<topic>-session.md` |
| `commands/resume-session.md` | `/resume-session` — loads the most recent handoff and orients you |
| `settings-snippet.json` | The `hooks` block to merge into `~/.claude/settings.json` |
| `install.sh` / `uninstall.sh` | Copy files into place with backups; print the snippet to merge |
| `test.sh` | Fixture tests for every state the hook can emit (no live session needed) |

Dependencies: `bash`, `python3` (stdlib), `date`.

## Install

```bash
git clone <this-repo> claude-cost-helpers
cd claude-cost-helpers/idle-tax
./install.sh
```

The script copies the hook to `~/.claude/hooks/cost-helpers/idle-tax/`, the
two slash commands to `~/.claude/commands/` (backing up existing ones), and
prints the JSON snippet to merge into `~/.claude/settings.json`. It does
**not** modify `settings.json` for you.

Pair it with [idle-autosave](../idle-autosave/) — that helper writes the
handoff *before* the cache dies, so the "start fresh" option this warning
offers is always free.

## What you'll see

Come back after 75 minutes to a 300K-token session on `claude-fable-5`:

```
idle-tax: CACHE EXPIRED (1h 15m idle, 1-hour TTL) — this turn re-writes
~300K cached tokens (≈$6.00, 20x a warm hit). Handoff available:
/resume-session in a fresh session is free.
```

and Claude sees:

```
CACHE EXPIRED (1h 15m idle, 1-hour TTL): this prompt re-writes ~300K cached
tokens for claude-fable-5 at 2.0x input price: about $6.00 vs $0.30 for a
warm hit (20x).
Latest handoff note: ~/.claude/sessions/2026-09-01-idle-autosave-ab12cd34-session.md (saved 31 min ago)
Options: (1) continue here and accept the re-cache; (2) if the context is
stale or large, /save-session (or use the handoff above) and continue in a
fresh session with /resume-session; (3) next time, /save-session before
stepping away for more than the TTL.
This is informational — the prompt proceeds normally.
```

At 45–60 minutes idle (on the 1-hour TTL) you get a softer
`CACHE EXPIRES IN 12 min` heads-up. Under that, the hook stays silent.

The warning is **informational, not blocking** — your prompt always proceeds.

## How it works

On every `UserPromptSubmit` the hook:

1. Reads `transcript_path` from the hook input and scans the transcript
   backwards for the last main-thread assistant message (subagent lines are
   skipped).
2. Takes its timestamp (idle gap = now − last API call), its `usage` block
   (cached context = `cache_read + cache_creation + input`) and its model.
3. Picks the TTL: 3600s if `ephemeral_1h_input_tokens > 0`, else 300s.
4. Emits nothing if the gap is under `TTL − lead`; an *expires-in* heads-up
   between there and the TTL; *expired* beyond it. Both carry the priced
   re-write (`context × input price × 2.0` for the 1h TTL, `× 1.25` for 5m,
   vs `× 0.1` warm) and point at the newest handoff note — preferring this
   session's own idle-autosave note if one exists.
5. Falls back to the original per-prompt timestamp file (and a 5-minute TTL)
   if the hook input has no `transcript_path`.

Output: `{"continue": true, "suppressOutput": true, "systemMessage": …,
"hookSpecificOutput": {"hookEventName": "UserPromptSubmit",
"additionalContext": …}}`.

## Configuration

| Var | Default | Meaning |
|---|---|---|
| `CACHE_TTL_SECONDS` | detected | Force a TTL (300 or 3600) instead of reading it from the transcript |
| `CACHE_WARN_SECONDS` | 900 (1h TTL) / 60 (5m TTL) | Lead time before expiry at which the heads-up starts |
| `IDLE_TAX_QUIET` | unset | Set to `1` to omit the user-facing `systemMessage` (Claude still gets the context) |

Prices are Anthropic list rates per model family (fable/opus/sonnet/haiku);
unknown models are priced as opus. Edit `PRICE_IN` in the script if the
table drifts.

## Testing

```bash
./test.sh
```

Builds synthetic transcripts for each state (warm, expiring, expired, 1h and
5m TTLs, fallback, sidechain noise, corrupt file) and asserts on the emitted
JSON. All cases must pass before shipping a change.

## Uninstall

```bash
./uninstall.sh
```

Or manually:

```bash
rm -rf ~/.claude/hooks/cost-helpers/idle-tax
rm ~/.claude/commands/save-session.md ~/.claude/commands/resume-session.md
# Then remove the UserPromptSubmit hook block from ~/.claude/settings.json
```

## Why this exists

Most of what makes Claude Code expensive isn't the prompts you write — it's
the habits you don't think about. Walking away from a big session and coming
back to it is the most universal of those habits, and the cost is invisible:
on the 1-hour TTL a 300K-token Fable session costs about six dollars to wake
up, and on the author's machine that happened roughly once per desktop-app
session.

The fix isn't "stop walking away." It's making the cost visible at the moment
it happens, with a handoff already written, so the cheap choice is a real
choice.

## Provenance

v1 (spring 2026) productized a hook the author had run for months, with the
5-minute TTL hardcoded. v2 (September 1, 2026) followed a transcript analysis
of 1,200 sessions that showed 99.7% of cache writes were on the 1-hour TTL,
that the cliff had moved to 60 minutes, and that the v1 warning had never
reached the model because of its output shape. Every number in this README
comes from that analysis.

## License

GPL-3.0-or-later. See LICENSE.
