# Auto-Persist — Continuous Session State, Zero Claude Tokens

Companion code for *The Economics of Claude Code, Part 1: The Idle Tax* (follow-up to the save-session pattern).

## What it does

Writes a minimal JSON + Markdown snapshot of your environment after **every Claude turn**, via a Stop hook. No Claude tokens consumed. No context re-read. When you return to a cold cache — or a dead session — you can answer "where did I leave off?" from a shell-written ground-truth file instead of asking Claude to recall from memory.

## Why this exists

`/save-session` works, but it has two costs the cost-helpers blog did not fully acknowledge:

1. **Token cost**: Claude has to read the context and synthesize a handoff. With a warm cache that is cheap; with a 200K-token session it is still real money.
2. **Activation cost**: You have to remember to run it before stepping away. You usually don't. Which means the cache expires, you come back, and the save-session you would have wanted never happened.

A Stop hook sidesteps both. It fires after every turn whether you remember or not, it runs in shell (no Claude involvement), and it captures the 80% of "where I left off" that is actually environmental rather than narrative: current branch, uncommitted files, recent edits, last commit.

The narrative "what was I thinking about" piece is what `/save-session` is for. This helper is the layer underneath — the ground-truth log a shell can answer without bothering Claude.

## What you get

| File | Purpose |
|---|---|
| `hooks/stop-auto-persist.sh` | Stop hook — writes `<sessionId>.json` + `<sessionId>.md` to `~/.claude/sessions/auto-state/` after every turn |
| `commands/last-state.md` | `/last-state` — prints the most recent auto-state file so you can restore environmental context without asking Claude to recall |
| `settings-snippet.json` | `hooks.Stop` entry to merge into `~/.claude/settings.json` |
| `install.sh` | Copies hook + command, creates state dir, prints settings snippet |
| `uninstall.sh` | Reverses the install; preserves existing auto-state files unless you ask otherwise |

Total install footprint: one Stop hook, one slash command, one JSON snippet. Zero dependencies beyond `bash`, `python3` (stdlib), and `git` — already present on macOS and any sane Linux.

## Install

```bash
cd auto-persist
./install.sh
```

The script creates `~/.claude/hooks/cost-helpers/auto-persist/`, copies the hook in, copies `/last-state` into `~/.claude/commands/`, creates `~/.claude/sessions/auto-state/`, and prints the JSON snippet to merge.

It does **not** auto-modify `settings.json`. Merge the `hooks.Stop` entry by hand.

## What the hook captures

After every Stop event, the hook writes two files keyed by session ID:

`~/.claude/sessions/auto-state/<sessionId>.json` (machine-readable):

```json
{
  "session_id": "abc123",
  "timestamp_iso": "2026-04-16T18:32:07Z",
  "timestamp_local": "2026-04-16 14:32:07 -0400",
  "epoch": 1744826327,
  "cwd": "/Users/alex/claude/blogs-presentations",
  "git": {
    "branch": "main",
    "last_commit_sha": "a1b2c3d",
    "last_commit_msg": "feat: effort-control helper",
    "staged": 0,
    "modified": 3,
    "untracked": 1,
    "ahead": 2,
    "behind": 0
  },
  "recent_files": [
    "/Users/alex/claude/blogs-presentations/companion-helpers/auto-persist/README.md",
    "..."
  ]
}
```

`~/.claude/sessions/auto-state/<sessionId>.md` (human-readable):

```markdown
# Auto-persisted session state

- **Session**: `abc123`
- **Last active**: 2026-04-16 14:32:07 -0400
- **CWD**: `/Users/alex/claude/blogs-presentations`
- **Git branch**: `main`
- **Last commit**: `a1b2c3d` — feat: effort-control helper
- **Uncommitted**: 0 staged, 3 modified, 1 untracked
- **Upstream**: 2 ahead, 0 behind

## Recently modified (last 30 min)

- `companion-helpers/auto-persist/README.md`
- `companion-helpers/auto-persist/install.sh`
...
```

Both files are rewritten in place on every Stop event. No history by default (that would grow without bound). If you want history, point the hook at a rotating log — see the "Extending" section.

## Why Stop, not SubagentStop

`SubagentStop` fires for every `Agent` tool invocation — noisy, fires mid-turn, and redundant with the main Stop event. `Stop` fires exactly once per main-session turn, which is exactly the granularity we want.

## How to use the output

**From inside a session**: `/last-state` — Claude reads the most recent auto-state Markdown and prints it. Costs one file Read, no synthesis. Much cheaper than `/save-session`'s summarize-everything pattern.

**From outside a session** (e.g., in a fresh terminal before opening Claude Code):

```bash
ls -lt ~/.claude/sessions/auto-state/
cat ~/.claude/sessions/auto-state/<most-recent-session>.md
```

Tells you which branch you were on, what was uncommitted, what files you were editing — enough to rehydrate your own mental model before opening Claude. This is often cheaper than any Claude-assisted resume.

**For fleet visibility** (Joyus AI tie-in): every auto-state file is a one-shot telemetry point. Aggregating across a team gives you "where is each developer's work sitting right now?" without any platform-level instrumentation. A cron that scrapes `~/.claude/sessions/auto-state/*.json` produces a live directory of in-flight work across N engineers. See the Joyus tie-in section below.

## What the hook does NOT do

- **Does not read the transcript.** The Stop hook input includes `transcript_path`, but reading it on every turn would be slow and pointless — the transcript is for Claude, not for shell tooling.
- **Does not fabricate a narrative.** If you want "what was I thinking about?", use `/save-session`. Auto-persist is environmental, not narrative.
- **Does not attempt `git diff`.** A diff on every turn is expensive on large repos and usually redundant with `git status`. If you want the diff, run it yourself.
- **Does not touch your session context.** The hook writes files outside the session; nothing it does shows up in Claude's context window unless you explicitly Read the file via `/last-state`.

## Cost math

Assume a warm-cache, mid-weight session that runs 40 turns before cache expiry.

- **Without this helper**: you forgot to `/save-session` before stepping away. Cache expires. Resume requires either (a) a cold-cache read of the whole transcript to re-orient, or (b) a fresh session with no handoff. Cost: 50K+ tokens cold-read, or lost context.
- **With this helper**: 40 turns × ~200ms of shell work = ~8 seconds of CPU, zero Claude tokens. You resume by reading one Markdown file (~500 tokens). Net savings: ~49.5K tokens per dropped session.

Scaled to a team of 20 engineers each losing one session to cache expiry per day: ~20M tokens/month avoided. That is not life-changing, but it is real, and it shows up on the bill.

The more durable value is the **behavior change**: you stop relying on your own memory to hit `/save-session` at the right moment. The hook does it, every turn, without asking.

## Extending

The default hook is deliberately minimal. Common extensions:

**Keep history** — add a timestamped sibling file per turn:

```bash
cp "$MD_FINAL" "${STATE_DIR}/archive/${SESSION_ID}-$(date +%Y%m%d-%H%M%S).md"
```

Then periodically `find ~/.claude/sessions/auto-state/archive -mtime +14 -delete`.

**Add test status** — if your repo has a fast test command, append its exit code:

```bash
if [ -f package.json ]; then
    TEST_STATUS=$(npm test --silent >/dev/null 2>&1 && echo "passing" || echo "failing")
fi
```

Be careful — Stop hooks have a default 5s timeout. Running `npm test` on every turn is a bad idea. Only do this if you have a genuinely fast check.

**Capture the last user message** — if you want a narrative breadcrumb, parse the `transcript_path` from the hook input and extract the last user turn. This adds real cost (JSON parsing a potentially huge transcript) — prefer `/save-session` for narrative.

## Joyus AI tie-in

The pattern here — a shell writing structured, machine-readable session telemetry on every turn without touching the session context — is the local-single-user version of the Joyus platform's session-telemetry spec.

- **Single user, this helper**: `~/.claude/sessions/auto-state/*.json` is a one-shot log of where every session ended up.
- **Fleet, Joyus**: same JSON shape, posted to a platform endpoint on every Stop event. Rolled up into a dashboard that shows all in-flight work across a team, detects stalled sessions, and attributes cost to specific working states.

Building this as a local helper first is deliberate — the platform version is an aggregation layer, not a different mechanism. If the local hook works, the fleet version is a one-line change (replace `mv $TMP $FINAL` with `curl -X POST ... --data-binary @$TMP`). Every user who installs this helper has already been practicing the pattern the platform will roll up.

For `joyus-ai-internal`: this is a useful evidence point for the "organizational knowledge should be first-class" thesis. Environmental state from every session *is* organizational knowledge — where work sat, for how long, across whom — and a Stop hook is the minimum viable capture surface.

## Uninstall

```bash
./uninstall.sh
```

Or manually:

```bash
rm -rf ~/.claude/hooks/cost-helpers/auto-persist
rm ~/.claude/commands/last-state.md
# Then remove the Stop hook entry from ~/.claude/settings.json
```

The state directory (`~/.claude/sessions/auto-state/`) is preserved by default — the files might still be useful as a log even after uninstall. Delete it manually if you want.

## Why this is a separate helper (not a rider on idle-tax)

The idle-tax helper is about **awareness and manual action**: the hook warns you that the cache is cold; `/save-session` gives you the remedy but requires you to run it.

The auto-persist helper is about **automatic action**: the Stop hook persists environmental state without requiring any user behavior. It does not replace `/save-session` — narrative summaries still need Claude — but it removes the most common failure mode of idle-tax, which is "I forgot to save before walking away."

Install both. They compose: idle-tax tells you what happened; auto-persist gives you the receipts regardless.

## Provenance

Written April 16, 2026, during the same session that produced the effort-control helper. The triggering observation: `/save-session` costs tokens and requires you to remember, which means it fails exactly when you need it most (stepping away, context heavy, attention elsewhere). The Stop hook pattern was proposed as a follow-on helper during the same conversation.

## License

GPL-3.0-or-later. See LICENSE.
