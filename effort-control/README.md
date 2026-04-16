# Effort Control — Defang the Opus 4.7 `xhigh` Default

Companion code for *The Economics of Claude Code, Part 6: The Effort Tax* (or as a rider on Part 1).

## What it does

Pins Claude Code's effort level to `high` via the `CLAUDE_CODE_EFFORT_LEVEL` environment variable so Opus 4.7 does not silently spend `xhigh` tokens on every turn. Adds a SessionStart banner so you know the pin is active, and a `/deep` slash command for one-shot escalation when a task genuinely needs deeper reasoning.

## Why this exists

On April 16, 2026, Anthropic shipped Opus 4.7. Its new default effort level is `xhigh` for all plans and providers. From the [model config docs](https://code.claude.com/docs/en/model-config):

> "When you first run Opus 4.7, Claude Code applies `xhigh` even if you previously set a different effort level for Opus 4.6 or Sonnet 4.6. Run `/effort` again to choose a different level after switching."

Two consequences:

1. Settings like `"effortLevel": "high"` at the root of `~/.claude/settings.json` get **overridden** the first time a user runs 4.7.
2. Cold-cache resumes cost **more** on 4.7 than they did on 4.6, because every turn spends `xhigh` reasoning budget by default.

The fix is the environment variable — `CLAUDE_CODE_EFFORT_LEVEL` takes precedence over every other mechanism (per-session `/effort`, `effortLevel` field, model default). Set it once, it survives model switches, new sessions, and the "first run on new model family" override.

## What you get

| File | Purpose |
|---|---|
| `settings-snippet.json` | `env` block + root `effortLevel` field to merge into `~/.claude/settings.json` (belt + suspenders) |
| `hooks/effort-pin-banner.sh` | SessionStart hook — prints a one-line banner confirming the pin is active and how to escalate |
| `commands/deep.md` | `/deep <task>` — wraps the next turn in `ultrathink` for one-shot deeper reasoning without changing session effort |
| `install.sh` | Copies hook + command into `~/.claude/`, backs up existing files, prints the settings snippet to merge |
| `uninstall.sh` | Reverses the install and restores any backed-up files |

Total install footprint: one SessionStart hook, one slash command, one JSON snippet to merge. Zero dependencies beyond `bash` and `python3` (for JSON parsing — already present on macOS and most Linux).

## Install

```bash
cd effort-control
./install.sh
```

The script:

1. Creates `~/.claude/hooks/cost-helpers/effort-control/` and copies the hook in
2. Copies the `/deep` slash command into `~/.claude/commands/` (backs up any existing `deep.md` first)
3. Prints the JSON snippet you need to merge into `~/.claude/settings.json`

It does **not** auto-modify `settings.json`. The env block in your settings is load-bearing — a merge gone wrong breaks your whole Claude Code config. Manual merge takes ten seconds.

## The three-layer pin

The snippet configures three mechanisms at once:

```json
{
  "env": {
    "CLAUDE_CODE_EFFORT_LEVEL": "high"
  },
  "effortLevel": "high",
  "hooks": {
    "SessionStart": [ ... ]
  }
}
```

1. **`env.CLAUDE_CODE_EFFORT_LEVEL`** — the highest-precedence setting. Defeats the "first run on new model family" override. This is the load-bearing one.
2. **`effortLevel` at root** — belt to the env var's suspenders. Catches any code path that reads the settings field directly.
3. **SessionStart hook** — surfaces the pin so you know it's active. Without this, you could forget the pin is in place and wonder why heavy tasks feel underpowered.

## What you'll see

After install, every new session opens with a banner like:

```
EFFORT PINNED: high (via CLAUDE_CODE_EFFORT_LEVEL).
Opus 4.7 defaults to xhigh; you are opting into cheaper reasoning.
For a hard task this turn only, prepend `ultrathink` or use /deep.
For the rest of the session, run /effort xhigh or /effort max.
```

If the pin isn't active for some reason (e.g. you have `ANTHROPIC_MODEL` set to a non-supporting model, or the env block was edited out), the banner warns you.

## Effort cheat sheet

| Command / mechanism | Scope | Effect |
|---|---|---|
| `CLAUDE_CODE_EFFORT_LEVEL=high` in env | All sessions | Pins `high` — the default for this helper |
| `/effort xhigh` | Current session | Temporarily escalate to 4.7's native default |
| `/effort max` | Current session | Maximum reasoning budget — use sparingly, prone to overthinking |
| `/deep <task>` | One turn only | Prepends `ultrathink` so Claude reasons harder on this one message |
| `ultrathink` in prompt | One turn only | Same as `/deep` — just more verbose |
| `/effort auto` | Current session | Reset to the model's native default (`xhigh` on 4.7) |

`high` is the documented minimum for intelligence-sensitive work. For most coding tasks it is within ~5–10% of `xhigh` quality while spending meaningfully fewer thinking tokens per turn. Escalate deliberately, not by default.

## How the SessionStart hook works

The hook fires once per new session. It reads `CLAUDE_CODE_EFFORT_LEVEL` from its process environment (Claude Code injects settings-file env vars into hook processes). It emits a one-line banner via the hook's `additionalContext` field so Claude sees it in the first turn and can surface it to you if relevant.

If the env var is missing or set to `xhigh`/`max`/`auto`, the hook emits a different warning instead — flagging that the pin is off and you are back on the default.

The hook is **informational, not blocking**. Your session always starts normally.

## Uninstall

```bash
./uninstall.sh
```

Or manually:

```bash
rm -rf ~/.claude/hooks/cost-helpers/effort-control
rm ~/.claude/commands/deep.md
# Then remove CLAUDE_CODE_EFFORT_LEVEL from the env block in ~/.claude/settings.json
# And remove the SessionStart hook entry that points to effort-pin-banner.sh
```

If `install.sh` backed up an existing `deep.md`, `uninstall.sh` restores it.

## When NOT to pin

Pinning `high` is a default, not a policy. Unpin (or override per-session with `/effort xhigh`) when:

- You're doing architecture-heavy work where the extra reasoning materially helps
- You're running a long-horizon agent where token cost is secondary to correctness
- You're benchmarking 4.7's native behavior

For everyday coding, `high` is the right default on 4.7. `xhigh` is the right default when the task warrants it, not when the model picker warrants it.

## Why this is a separate helper (not a rider on idle-tax)

The idle-tax helper is about **cache mechanics** — cold prefixes cost 12.5× warm ones. The effort-control helper is about **per-turn reasoning cost** — `xhigh` spends meaningfully more thinking tokens than `high` on the same prompt. They're orthogonal costs, layered on top of each other. A cold-cache resume at `xhigh` effort is the worst case; a warm-cache turn at `high` is the best case. Pinning effort narrows the worst case.

For the full story, see *The Economics of Claude Code, Part 1: The Idle Tax* and the 4.7 addendum covering the effort default change.

## Provenance

Written April 16, 2026, the day Opus 4.7 shipped, after confirming in a live session that `effortLevel: "high"` at the root of `settings.json` was being overridden by 4.7's first-run rule. The env var mechanism is from Anthropic's model-config docs. The SessionStart banner is new — there is no native "effort is pinned" affordance beyond the statusline effort indicator, which is easy to miss.

## License

GPL-3.0-or-later. See LICENSE.
