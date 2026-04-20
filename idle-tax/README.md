# Idle Tax — Cache TTL Helper for Claude Code

Companion code for [*The Economics of Claude Code, Part 1: The Idle Tax*](https://zivtech.github.io/zivtech-demos/economics-of-claude/idle-tax.html).

## What it does

Warns you when Claude Code's prompt cache has gone cold (or is about to). The Anthropic prompt cache has a 5-minute idle TTL. Once it expires, your next message has to re-cache the entire conversation prefix at 1.25× base token cost — about **12.5× more** than a warm-cache message would cost. There's no native warning for this. This package adds one.

It also installs two slash commands you'll want when the warning fires:

- `/save-session` — capture the current session into a structured handoff file
- `/resume-session` — load the most recent handoff into a fresh session

## What you get

| File | Purpose |
|---|---|
| `cache-idle-timer.sh` | Bash hook that runs on every user prompt. Checks how long since your last activity in this session. Warns at ~4 min (cache expiring), warns again at >5 min (cache dead). |
| `commands/save-session.md` | `/save-session` slash command — writes a structured handoff to `~/.claude/sessions/YYYY-MM-DD-<topic>-session.md` |
| `commands/resume-session.md` | `/resume-session` slash command — loads the most recent handoff and orients you |
| `settings-snippet.json` | The `hooks` block to merge into `~/.claude/settings.json` |
| `install.sh` | Copies files into place, backs up anything it overwrites, prints the snippet to merge |

Total install footprint: one script, two slash commands, one JSON snippet to merge. Zero dependencies beyond `bash`, `python3` (for JSON parsing — already present on macOS and most Linux), and `date`.

## Install

```bash
git clone <this-repo> claude-cost-helpers
cd claude-cost-helpers/idle-tax
./install.sh
```

The script:

1. Creates `~/.claude/hooks/cost-helpers/idle-tax/` and copies the hook in
2. Copies the two slash command files into `~/.claude/commands/` (backs up any existing `save-session.md` or `resume-session.md` first)
3. Prints the JSON snippet you need to merge into `~/.claude/settings.json` and the verification command

It does **not** automatically modify `settings.json` — JSON merging is the kind of thing where a one-liner gone wrong silently breaks your whole Claude Code config. Manual merge takes ten seconds and keeps you in control.

## What you'll see

After install, when you return to a session after >5 min idle, the next message you send will surface this in Claude's response context:

```
CACHE EXPIRED (8 min idle): Your prompt cache has expired (5-min TTL).
This message will re-cache your full conversation context at 1.25× base
token cost. For a 100K-token Opus session, that is ~$0.63 vs ~$0.05 for
a cache hit (12.5× premium).

Options:
1. Continue here (accept the re-cache cost)
2. /save-session and start fresh (cheaper if context is large)
3. Next time, /save-session before stepping away for >3 minutes
```

At ~4 min (one minute before cache death) you get a softer heads-up. Under 4 min, the hook stays quiet.

The warning is **informational, not blocking** — your prompt always proceeds. The point is to make the cost legible so you can choose, not to interrupt your work.

## How it works

The hook fires on every `UserPromptSubmit`. It records a timestamp per `sessionId` in `~/.claude/.session-state/<id>.last-activity`. Each new prompt:

1. Reads the previous timestamp
2. Computes the gap in seconds
3. Updates the timestamp to now
4. If gap ≥ 300s: emit the cache-expired warning
5. If gap ≥ 240s: emit the about-to-expire warning
6. Otherwise: stay silent

Output uses Claude Code's hook contract: `additionalContext` field surfaces the warning to Claude in the next turn, `continue: true` ensures the prompt proceeds normally.

## Configuration

The package ships with the 5-min TTL hardcoded because that's currently Anthropic's documented value. If Anthropic changes the TTL, edit `cache-idle-timer.sh` lines 43 and 53 (the `300` and `240` thresholds).

If you don't want the early warning at 4 min and only want the cache-expired alert at >5 min, comment out or delete the `elif` branch (lines 53–58).

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

If `install.sh` backed up existing slash command files (named `*.bak.YYYYMMDD-HHMMSS`), `uninstall.sh` restores them.

## Why this exists

Most of what makes Claude Code expensive isn't the prompts you write — it's the habits you don't think about. The idle tax is the most universal of those habits and the most invisible. Walk away for a few minutes, come back, type one more prompt: that single message just cost you 12× what it should have. Multiply across a normal workday and the bill diverges from the value you got.

The fix isn't "stop walking away from your computer." It's making the cost visible at the moment it happens, so you have a real choice: keep going (sometimes that's right) or save and start fresh (often cheaper at scale).

For the full story see [*The Economics of Claude Code, Part 1: The Idle Tax*](https://zivtech.github.io/zivtech-demos/economics-of-claude/idle-tax.html).

## Provenance

This is a productized version of hooks and slash commands the author has been running in his personal Claude Code config for months. The hook script is unchanged from the working version. The slash commands are unchanged from the working versions. Nothing here is new code — what's new is packaging it for sharing.

## License

GPL-3.0-or-later. See LICENSE.
