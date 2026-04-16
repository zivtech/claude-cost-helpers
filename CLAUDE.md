# Claude Cost Helpers

## What this is

Local Claude Code hooks and slash commands that make cost mechanics visible. Each helper corresponds to one post in the *Economics of Claude Code* blog series. No platform dependency — pure bash + python3.

## Repo structure

```
├── README.md                        # Top-level overview + stubs for all 5 helpers
├── CLAUDE.md                        # This file
├── 01-idle-tax/                     # Helper 01: cache TTL idle detection (BUILT)
│   ├── cache-idle-timer.sh          # UserPromptSubmit hook
│   ├── commands/
│   │   ├── save-session.md          # /save-session slash command
│   │   └── resume-session.md        # /resume-session slash command
│   ├── settings-snippet.json        # Hook wiring for settings.json
│   ├── install.sh                   # Copies files, prints merge instructions
│   ├── uninstall.sh                 # Removes files, restores backups
│   ├── README.md                    # Helper-specific docs
│   └── LICENSE                      # MIT
├── 02-just-one-more-turn/           # Helper 02: context rot warning (STUBBED)
├── 03-subagent-isolation/           # Helper 03: file count warning (STUBBED)
├── 04-compact-gamble/               # Helper 04: pre-compact backup (STUBBED)
└── 05-watching-cost/                # Helper 05: output size warning (STUBBED)
```

## Conventions

- Each helper is self-contained in its own directory
- Every helper has: a hook script (bash), one or two slash commands (markdown), a settings snippet (JSON), install/uninstall scripts, README, and MIT LICENSE
- Hook scripts read JSON from stdin (Claude Code hook contract), write JSON to stdout
- Hooks are informational — they warn but never block (`"continue": true` always)
- State files go in `~/.claude/.session-state/` keyed by session ID
- Slash commands install to `~/.claude/commands/`
- Hooks install to `~/.claude/hooks/cost-helpers/<helper-name>/`
- Install scripts never auto-modify `settings.json` — they print the snippet for manual merge

## Building a new helper

Follow the pattern in `01-idle-tax/`. Checklist:

1. Hook script that reads stdin JSON, extracts `sessionId`, checks local state, outputs hook-contract JSON
2. Slash command(s) as `.md` files with YAML frontmatter (`description:` field)
3. `settings-snippet.json` with the correct event type and matcher
4. `install.sh` that copies files + backs up existing + prints settings snippet
5. `uninstall.sh` that removes files + restores backups
6. `README.md` explaining the problem, the fix, install, how it works, config, uninstall
7. `LICENSE` (MIT)
8. Test all three states (warm/warning/triggered) before shipping

## Testing hooks locally

```bash
# Simulate a cold cache (8 min idle)
STATE_DIR="$TMPDIR/test-state"
mkdir -p "$STATE_DIR"
STALE=$(($(date +%s) - 480))
echo "$STALE" > "$STATE_DIR/test-session.last-activity"
echo '{"sessionId":"test-session"}' | HOME="$TMPDIR/test-home" ./cache-idle-timer.sh
```

## Related repos

- **joyus-ai-internal** (`spec/011-*`, `spec/012-*`, `spec/013-*`) — platform specs that these helpers map to
- **blogs-presentations** (`blog-economics-01-idle-tax.md`) — the blog series these ship alongside

## Joyus AI relationship

These helpers work standalone — no Joyus dependency. For organizations, Joyus deploys and manages them at scale (canonical configs, policy enforcement, threshold tuning, telemetry aggregation). See the "Local Instrumentation Layer" sections in Specs 011/012/013.
