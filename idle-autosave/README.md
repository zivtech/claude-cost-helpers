# idle-autosave

Automatic handoff notes when you walk away. A Stop hook arms a detached
watcher after every Claude turn; if the session then stays quiet until just
before its prompt cache expires, the watcher writes a structured handoff note
to `~/.claude/sessions/` — the same place `/save-session` writes and
`/resume-session` reads.

## The problem

The idle-tax hook warns you at **return** time: by the time you see
"CACHE EXPIRED", the re-cache cost is already unavoidable and the only
cheap option — starting fresh — requires a handoff note you forgot to
write before stepping away.

This helper closes that loop by acting at **idle** time. When you come
back to a cold session, the handoff already exists, so "start fresh" is
always a safe answer. The idle-tax warning links to it (it prefers this
session's own idle-autosave note).

## TTL-aware timing (v2)

The idle window is derived from the prompt-cache TTL the session is actually
running on, read from the last assistant message in the transcript:

| TTL in effect | Window of quiet before saving | Why |
|---|---|---|
| 1 hour (Claude Code's normal case) | **45 minutes** (`3600 − 900`) | the note exists 15 minutes before the cache dies |
| 5 minutes (usage overage, older setups) | **4 minutes** (`300 − 60`) | one minute before the cliff |

v1 hardcoded 4 minutes for a 5-minute TTL. On the 1-hour TTL that fired a
handoff during every coffee break — dead output — so v2 reads the TTL instead
of assuming it.

## How it works

1. **`stop-idle-autosave.sh`** (Stop hook) fires after every Claude turn of
   an interactive session. It kills the previous watcher for the session and
   spawns a fresh detached one — so the timer always measures quiet since the
   *last* turn. Returns in milliseconds; all waiting happens out of process.
   Headless and eval child sessions are skipped (see Edge cases).
2. **`idle-autosave-worker.sh`** detects the TTL, then polls the transcript
   mtime. Any activity → it stands down silently. After the window it extracts
   the conversation tail (capped at 24K chars; subagent and system-generated
   lines skipped) and asks a **minimal** headless `claude -p` for a structured
   handoff: what we were doing, current state, what worked/failed, exact next
   step. On exit it removes its own `.pid` file.
3. If the CLI is missing, times out (120s), fails, or answers with an auth
   error, it falls back to a deterministic transcript excerpt plus a pointer
   to the auto-persist state file. A worse handoff still beats none.
4. The note is written atomically to
   `~/.claude/sessions/<date>-idle-autosave-<sid>-session.md`, then a macOS
   notification confirms it, naming the session (`session <id> · HH:MM:SS`)
   and cwd.
5. **`sessionend-idle-autosave.sh`** (SessionEnd hook) fires when a session
   ends cleanly. It kills that session's armed watcher and removes its state.

Idle autosave fires when you **walk away**, not when you **end** a session.
A clean `/clear`, `/exit`, or logout cancels the watcher — run `/save-session`
if you want a note on a clean exit. Sessions that die without a SessionEnd
event (terminal closed, crash) still get their one handoff.

It works the same in the terminal and in the Claude Code desktop app — both
run the `Stop`/`SessionEnd` hooks from `~/.claude/settings.json`.

## What it costs

The handoff call is stripped to the bone: `--model haiku --effort low
--tools "" --strict-mcp-config --disable-slash-commands --setting-sources ""
--no-session-persistence --system-prompt "<one line>"`. Measured on the
author's machine: **~250 input tokens, ~$0.002 per handoff, under 10
seconds**. The same call with Claude Code's default system prompt (agents,
skills, MCP schemas, CLAUDE.md) cost $0.18 — with 85 agents and 200 skills
installed, the default prompt was 91K tokens. Nothing in the note needs any of
that.

It does not fire on trivial sessions (transcript under 10KB), does not
re-fire for an unchanged transcript, and fires at most once per idle period.
Active sessions cost nothing but a `stat` poll every 15s.

## Install

```bash
./install.sh
```

Then merge `settings-snippet.json` into `~/.claude/settings.json` (it
registers a `hooks.Stop` entry and a `hooks.SessionEnd` entry). Start a new
session to pick up the hooks. Check `~/.claude/.session-state/idle-autosave.log`
for `armed: 1-hour cache TTL detected, saving after 2700s of quiet`.

## Config (env vars, e.g. in settings.json `env` block)

| Var | Default | Meaning |
|---|---|---|
| `IDLE_AUTOSAVE_DELAY` | `auto` | Seconds of quiet before saving. `auto` = TTL − lead (2700 on the 1-hour TTL, 240 on the 5-minute one). A number overrides detection. |
| `IDLE_AUTOSAVE_LEAD` | `900` (1h) / `60` (5m) | Seconds before cache expiry to save |
| `IDLE_AUTOSAVE_POLL` | `15` | Poll interval (seconds) |
| `IDLE_AUTOSAVE_MIN_BYTES` | `10000` | Skip transcripts smaller than this |
| `IDLE_AUTOSAVE_MAX_CHARS` | `24000` | Cap on extracted transcript text |
| `IDLE_AUTOSAVE_MODEL` | `haiku` | Model alias for the handoff call |
| `IDLE_AUTOSAVE_EFFORT` | `low` | Effort for the handoff call (the global `CLAUDE_CODE_EFFORT_LEVEL` pin is bypassed because user settings are not loaded) |
| `IDLE_AUTOSAVE_NOTIFY` | `1` | macOS notification on save (0 to disable) |
| `IDLE_AUTOSAVE_CLAUDE_BIN` | auto | Override path to the claude CLI |
| `IDLE_AUTOSAVE_STATE_DIR` / `IDLE_AUTOSAVE_SESSIONS_DIR` | `~/.claude/.session-state` / `~/.claude/sessions` | Override locations (used by tests) |
| `CLAUDE_IDLE_AUTOSAVE_DISABLE` | unset | Set to `1` in any spawner/automation to skip idle-autosave for the sessions it launches (child `claude` runs inherit it) |

## Deliberate omissions

- **No slash command.** `/resume-session` is the consumer and already
  exists (idle-tax helper).
- **No always-on timer daemon.** The watcher exists only between a Stop
  event and the next activity; each Stop replaces the previous one; an ended
  session is cleaned by the SessionEnd hook; the worker removes its own `.pid`.
- **Recursion guard.** The worker's headless call skips user settings (so no
  hooks), and `CLAUDE_IDLE_AUTOSAVE_CHILD=1` short-circuits both hooks anyway.

## Edge cases

- **Laptop sleep**: sleep pauses the watcher's clock; the handoff fires on
  wake. Late but harmless — the transcript-unchanged check still holds.
- **Multiple parallel sessions**: watchers are keyed by session id; each
  session gets its own timer and its own handoff file.
- **Hard-killed sessions**: a closed terminal or crash skips SessionEnd, so
  the watcher still fires its one handoff, labelled with the session id.
- **Headless & eval child sessions**: a workflow or eval that spawns `claude`
  with a scratch cwd (under `/tmp`, `/private/tmp`, or a `*/scratchpad/*`
  dir), or that exports `CLAUDE_IDLE_AUTOSAVE_DISABLE=1`, or runs under a
  non-interactive `CLAUDE_CODE_ENTRYPOINT` (print/sdk/cron/action/mcp), is
  skipped at arm time. cwd is the reliable signal; env vars are inherited by
  every subprocess and can't tell interactive from headless on their own.
- **A stale `ANTHROPIC_API_KEY` in the hook environment** shadows the
  interactive login and makes the headless call fail. The worker detects an
  auth-shaped answer and retries once with the key unset before falling back.
- **Repeated idles in one session**: same-day handoffs for one session
  overwrite the same file — freshest state wins, no file spam.

## Uninstall

```bash
./uninstall.sh
```

Then remove the idle-autosave entries from `hooks.Stop` and
`hooks.SessionEnd` in `~/.claude/settings.json`. Saved handoffs are kept.
