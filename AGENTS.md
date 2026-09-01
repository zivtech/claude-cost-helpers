# Claude Cost Helpers

## Positioning note

This repository's primary shipping helper code is **Claude Code-first**, with a limited Codex-native lane.

- The implemented hook installers and helper directories target `~/.claude/`.
- A narrowed Codex helper lane now exists under [codex-helpers/](./codex-helpers/).
- The Codex evaluation, live measurements, and support boundaries live under [codex-evaluation/](./codex-evaluation/).
- Do not describe the Codex material as a full parity suite with the Claude helpers. It is a narrower subset with explicit support boundaries.

## What this is

Local Claude Code hooks and slash commands that make cost mechanics visible. Each helper corresponds to one post in the *Economics of Claude Code* blog series. No platform dependency — pure bash + python3.

## Repo structure

```
├── README.md                        # Top-level overview + combined settings snippet
├── AGENTS.md                        # This file
├── codex-evaluation/               # Codex CLI/Desktop evaluation, evidence, and planning
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
└── auto-persist/                # continuous session state, zero Claude tokens
    ├── hooks/stop-auto-persist.sh  # Stop hook
    ├── commands/last-state.md      # /last-state slash command
    ├── settings-snippet.json, install.sh, uninstall.sh, README.md, LICENSE
```

## Conventions

- Each helper is self-contained in its own directory
- Every helper has: a hook script (bash), one or two slash commands (markdown), a settings snippet (JSON), install/uninstall scripts, README, and GPL-3.0-or-later LICENSE
- Hook scripts read JSON from stdin (Claude Code hook contract), write JSON to stdout
- Hooks are informational — they warn but never block (`"continue": true` always)
- State files go in `~/.claude/.session-state/` keyed by session ID
- Slash commands install to `~/.claude/commands/`
- Hooks install to `~/.claude/hooks/cost-helpers/<helper-name>/`
- Install scripts never auto-modify `settings.json` — they print the snippet for manual merge

## Codex evaluation package

The `codex-evaluation/` tree is intentionally separate from the shipping Claude helper set and the narrower `codex-helpers/` implementation lane.

- It contains compatibility analysis, live Codex measurements, and a phased implementation plan.
- It explains why the current Codex helper lane is narrower than the Claude lane.
- It must not be treated as proof that the existing Claude helpers already work in Codex.
- Any further Codex implementation work should follow the evidence and non-goals in `codex-evaluation/`, not the Claude installer assumptions below.

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
| `PostToolUse` | `session_id`, `tool_name`, `tool_input` (object), `tool_response` (string or object) |
| `PreCompact` | `session_id`, `trigger` ("auto" or "manual") |
| `SessionStart` | `session_id`, `transcript_path`, `cwd` (+ env vars injected from settings.json `env` block) |
| `Stop` | `session_id`, `cwd`, `transcript_path` |

All hooks use `session_id` (snake_case). Use dual fallback `d.get('sessionId', d.get('session_id', 'unknown'))` for safety. PostToolUse tool response field is `tool_response` — use fallback chain: `tool_response` → `tool_result` → `tool_output`.

## Hook output contract

- **What Claude sees**: `{"hookSpecificOutput": {"hookEventName": "<Event>", "additionalContext": "..."}}` — supported for `UserPromptSubmit`, `SessionStart`, `PreToolUse`, `PostToolUse`, `Stop`; **not** `PreCompact`/`SessionEnd`.
- **What the user sees**: top-level `"systemMessage": "..."` (terminal and desktop app). One line, number + action.
- A top-level `additionalContext` field is **not honored** by Claude Code — the pre-September-2026 helpers shipped that way and their warnings never reached the model. `stderr` is a trace, not a delivery channel. Always `"continue": true`, and `"suppressOutput": true` when emitting a message.

## Testing hooks locally

```bash
# Fixture suites (synthetic transcripts, every state, no live session):
./idle-tax/test.sh
./usage-report/test.sh

# One-off: run any hook against a real transcript
echo '{"session_id":"<sid>","transcript_path":"$HOME/.claude/projects/<proj>/<sid>.jsonl"}' \
  | bash idle-tax/cache-idle-timer.sh
```

## Related repos

- **joyus-ai-internal** (`spec/011-*`, `spec/012-*`, `spec/013-*`) — platform specs that these helpers map to
- **blogs-presentations** (`blog-economics-idle-tax.md`) — the blog series these ship alongside

## Joyus AI relationship

These helpers work standalone — no Joyus dependency. For organizations, Joyus deploys and manages them at scale (canonical configs, policy enforcement, threshold tuning, telemetry aggregation). See the "Local Instrumentation Layer" sections in Specs 011/012/013.
