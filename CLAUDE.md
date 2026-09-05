# Claude Cost Helpers

## What this is

Local Claude Code hooks and slash commands that make cost mechanics visible. Each helper corresponds to one post in the *Economics of Claude Code* blog series. No platform dependency — pure bash + python3.

## Dead Output

**What dead looks like in this repo:**
- Hooks that fire warnings users have learned to ignore. If the idle-tax timer warns on every session start and users don't change their behavior, the warning is dead — it's noise, not signal. The threshold is wrong or the message doesn't connect cost to action.
- Slash commands that save state nobody resumes from. If `/save-session` writes a handoff file that the next session's `/resume-session` doesn't actually load, the save was dead ritual — it felt productive but produced nothing usable.
- Cost warnings that report numbers without context. "This session has used 150K tokens" means nothing to a user who doesn't know what 150K tokens costs or what the alternative would have cost. The warning needs to connect to a decision the user can make right now.
- New helpers built to the checklist (hook, command, snippet, install, README, LICENSE) without testing whether they actually change user behavior. A perfectly packaged helper that doesn't make cost mechanics visible is dead tooling.

Three rules:
- **Name it when you see it.** If a hook, command, or helper is dead — running without changing behavior — say so. The whole point of this repo is to make invisible costs visible. If they stay invisible, the tool failed.
- **Friction is the job.** If a new helper follows the pattern perfectly but doesn't address a real cost mechanic from the blog series, push back. If a warning threshold is set so conservatively it never fires, or so aggressively it always fires, flag it.
- **Watch for rank erosion.** Blog post insight → hook implementation → user-facing message loses nuance at each step. If the warning message doesn't convey the insight from the blog post that motivated the helper, the message is too flat to drive behavior change.

## Repo structure

```
├── README.md                        # Top-level overview + combined settings snippet
├── CLAUDE.md                        # This file
├── idle-tax/                    # cache TTL idle detection
│   ├── cache-idle-timer.sh         # UserPromptSubmit hook
│   ├── commands/
│   │   ├── save-session.md         # /save-session slash command
│   │   └── resume-session.md       # /resume-session slash command
│   ├── settings-snippet.json, install.sh, uninstall.sh, README.md, LICENSE
├── just-one-more-turn/          # context rot warning
│   ├── context-usage-monitor.sh    # UserPromptSubmit hook
│   ├── commands/split.md           # /split slash command
│   ├── settings-snippet.json, install.sh, uninstall.sh, README.md, LICENSE
├── subagent-isolation/          # file count warning
│   ├── file-count-monitor.sh       # PostToolUse hook (Read/Glob/Grep)
│   ├── commands/delegate.md        # /delegate slash command
│   ├── settings-snippet.json, install.sh, uninstall.sh, README.md, LICENSE
├── compact-gamble/              # pre-compact safety net
│   ├── pre-compact-backup.sh       # PreCompact hook
│   ├── commands/safe-compact.md    # /safe-compact slash command
│   ├── settings-snippet.json, install.sh, uninstall.sh, README.md, LICENSE
├── watching-cost/               # output size warning
│   ├── output-size-monitor.sh      # PostToolUse hook (all tools)
│   ├── commands/to-file.md         # /to-file slash command
│   ├── settings-snippet.json, install.sh, uninstall.sh, README.md, LICENSE
├── effort-control/              # Opus 4.7 xhigh default defense
│   ├── hooks/effort-pin-banner.sh  # SessionStart hook
│   ├── commands/deep.md            # /deep slash command
│   ├── settings-snippet.json, install.sh, uninstall.sh, README.md, LICENSE
├── auto-persist/                # continuous session state, zero Claude tokens
│   ├── hooks/stop-auto-persist.sh  # Stop hook
│   ├── commands/last-state.md      # /last-state slash command
│   ├── settings-snippet.json, install.sh, uninstall.sh, README.md, LICENSE
├── delegation-cost/             # agent result size tracking + TTL-aware cache-cooling check
│   ├── delegation-result-monitor.sh # PostToolUse hook (Agent)
│   ├── test.sh                      # fixture tests (synthetic transcripts, every cache state)
│   ├── settings-snippet.json, install.sh, uninstall.sh, README.md, LICENSE
├── idle-autosave/               # automatic handoff notes on session idle
│   ├── hooks/stop-idle-autosave.sh        # Stop hook — arms detached watcher
│   ├── hooks/idle-autosave-worker.sh      # watcher: TTL-aware idle window (45 min on the 1h TTL), minimal haiku handoff (~$0.002)
│   ├── hooks/sessionend-idle-autosave.sh  # SessionEnd hook — cancels watcher + cleans state
│   ├── settings-snippet.json, install.sh, uninstall.sh, README.md, LICENSE
│   └── (no slash command on purpose — /resume-session is the consumer)
└── usage-report/                # where the spend goes, from local transcripts (zero tokens)
    ├── usage_scan.py                      # transcript scanner (per-session usage, classification)
    ├── usage_report.py                    # markdown report: desktop vs terminal, cache economics, delegation, headless jobs, week-over-week
    ├── hooks/sessionstart-usage-report.sh # SessionStart hook — weekly background refresh
    ├── commands/usage-report.md           # /usage-report slash command
    ├── test.sh                            # fixture tests (synthetic transcript tree)
    ├── settings-snippet.json, install.sh, uninstall.sh, README.md, LICENSE
```

Top-level `skills/` holds the skills-registry variants of the slash commands
(`npx skills add zivtech/claude-cost-helpers`); keep them in sync with the
per-helper `commands/*.md`.

## Conventions

- Each helper is self-contained in its own directory
- Every helper has: a hook script (bash), one or two slash commands (markdown), a settings snippet (JSON), install/uninstall scripts, README, and GPL-3.0-or-later LICENSE
- Hook scripts read JSON from stdin (Claude Code hook contract), write JSON to stdout
- Hooks are informational — they warn but never block (`"continue": true` always)
- State files go in `~/.claude/.session-state/` keyed by session ID
- Slash commands install to `~/.claude/commands/`
- Hooks install to `~/.claude/hooks/cost-helpers/<helper-name>/`
- Install scripts never auto-modify `settings.json` — they print the snippet for manual merge

## Building a new helper

Follow the pattern in `idle-tax/`. Checklist:

1. Hook script that reads stdin JSON, extracts `session_id` (with `sessionId` fallback), checks local state, outputs hook-contract JSON
2. Slash command(s) as `.md` files with YAML frontmatter (`description:` field)
3. `settings-snippet.json` with the correct event type and matcher
4. `install.sh` that copies files + backs up existing + prints settings snippet
5. `uninstall.sh` that removes files + restores backups
6. `README.md` explaining the problem, the fix, install, how it works, config, uninstall
7. `LICENSE` (GPL-3.0-or-later)
8. Test all three states (warm/warning/triggered) before shipping

## Hook contract fields

| Event | Key fields in stdin JSON |
|---|---|
| `UserPromptSubmit` | `session_id`, `transcript_path`, `cwd`, `prompt` |
| `PostToolUse` | `session_id`, `transcript_path`, `cwd`, `tool_name`, `tool_input` (object), `tool_response` (string or object) |
| `PreCompact` | `session_id`, `trigger` ("auto" or "manual") |
| `SessionStart` | `session_id`, `transcript_path`, `cwd` (+ env vars injected from settings.json `env` block) |
| `Stop` | `session_id`, `cwd`, `transcript_path` |
| `SessionEnd` | `session_id`, `cwd`, `reason` |

All hooks use `session_id` (snake_case). Use dual fallback `d.get('sessionId', d.get('session_id', 'unknown'))` for safety. PostToolUse tool response field is `tool_response` — use fallback chain: `tool_response` → `tool_result` → `tool_output`.

## Hook output contract (read before writing a warning)

Two channels, use both:

- **What Claude sees**: `{"hookSpecificOutput": {"hookEventName": "<Event>", "additionalContext": "..."}}`. Supported for `UserPromptSubmit`, `SessionStart`, `PreToolUse`, `PostToolUse`, `Stop`. **Not** for `PreCompact` or `SessionEnd` — those hooks cannot inject context, don't pretend they can.
- **What the user sees**: top-level `"systemMessage": "..."` — surfaced in the terminal *and* the desktop app. Keep it to one line with the number and the action.

A top-level `additionalContext` field is **not honored** by Claude Code. Every helper shipped that way until September 2026, and in 1,200 transcripts not one of those warnings reached the model — the textbook dead output this file warns about. `stderr` lines (`[idle-tax] …`) are fine as a terminal trace but are not a delivery channel. Always include `"continue": true` and, when you emit a message, `"suppressOutput": true` so stdout JSON isn't echoed twice.

The transcript is the ground truth for cost mechanics: `usage.cache_creation.ephemeral_1h_input_tokens` vs `ephemeral_5m_input_tokens` tells you which cache TTL a session is on; the last assistant message's timestamp is the real "last activity". Read it (backwards, in blocks) instead of hardcoding TTLs or trusting prompt timestamps.

## Testing hooks locally

```bash
# Fixture suites (synthetic transcripts, every state, no live session):
./idle-tax/test.sh
./delegation-cost/test.sh
./usage-report/test.sh

# One-off: run any hook against a real transcript
echo '{"session_id":"<sid>","transcript_path":"$HOME/.claude/projects/<proj>/<sid>.jsonl"}' \
  | bash idle-tax/cache-idle-timer.sh

# Idle-autosave worker end to end (short window, no notification):
IDLE_AUTOSAVE_DELAY=20 IDLE_AUTOSAVE_POLL=5 IDLE_AUTOSAVE_NOTIFY=0 \
IDLE_AUTOSAVE_SESSIONS_DIR=/tmp/ia IDLE_AUTOSAVE_STATE_DIR=/tmp/ia \
  bash idle-autosave/hooks/idle-autosave-worker.sh <sid> <transcript.jsonl> <cwd>
```

New or changed hook → add a fixture case before shipping. A hook without a test that proves its warning is delivered is presumed dead.

## Related repos

- **joyus-ai-internal** (`spec/011-*`, `spec/012-*`, `spec/013-*`) — platform specs that these helpers map to
- **blogs-presentations** (`blog-economics-idle-tax.md`) — the blog series these ship alongside

## Joyus AI relationship

These helpers work standalone — no Joyus dependency. For organizations, Joyus deploys and manages them at scale (canonical configs, policy enforcement, threshold tuning, telemetry aggregation). See the "Local Instrumentation Layer" sections in Specs 011/012/013.
