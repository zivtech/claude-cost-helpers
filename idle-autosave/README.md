# idle-autosave

Automatic handoff notes when you walk away. A Stop hook arms a detached
watcher after every Claude turn; if the session then stays quiet for 4
minutes (just inside the 5-minute prompt-cache TTL), the watcher writes a
structured handoff note to `~/.claude/sessions/` — the same place
`/save-session` writes and `/resume-session` reads.

## The problem

The idle-tax hook warns you at **return** time: by the time you see
"CACHE EXPIRED", the re-cache cost is already unavoidable and the only
cheap option — starting fresh — requires a handoff note you forgot to
write before stepping away.

This helper closes that loop by acting at **idle** time. When you come
back to a cold session, the handoff already exists, so "start fresh" is
always a safe answer. The idle-tax warning even links to it (it surfaces
the most recent `*-session.md` automatically).

## How it works

1. **`stop-idle-autosave.sh`** (Stop hook) fires after every Claude turn.
   It kills the previous watcher for the session and spawns a fresh
   detached one — so the timer always measures quiet since the *last*
   turn. Returns in milliseconds; all waiting happens out of process.
2. **`idle-autosave-worker.sh`** polls the transcript mtime. Any activity →
   it stands down silently. After 240s of quiet it extracts the
   conversation tail from the transcript JSONL (capped at 24K chars) and
   asks `claude -p --model haiku` for a structured handoff: what we were
   doing, current state, what worked/failed, exact next step. On exit it
   removes its own `.pid` file, so watcher state never accumulates.
3. If the CLI is missing, times out (120s), or fails, it falls back to a
   deterministic transcript excerpt plus a pointer to the auto-persist
   state file. A worse handoff still beats none.
4. The note is written atomically to
   `~/.claude/sessions/<date>-idle-autosave-<sid>-session.md`, then a
   macOS notification confirms it. The notification names the session
   (`session <id> · HH:MM:SS`) and cwd, so a burst of saves reads as
   several distinct sessions, not one repeated nag.
5. **`sessionend-idle-autosave.sh`** (SessionEnd hook) fires when a session
   ends cleanly. It kills that session's armed watcher and removes its
   state, so ending a session never leaves a watcher behind.

Idle autosave fires when you **walk away** (go quiet), not when you
**end** a session. A clean `/clear`, `/exit`, or logout cancels the armed
watcher via the SessionEnd hook — deliberately ending a session no longer
spawns a delayed handoff you didn't ask for; run `/save-session` if you
want a note on a clean exit. Sessions that die *without* a SessionEnd event
(terminal closed, crash, SIGKILL) still get their one handoff a few minutes
later — now labelled with the session id so it's obviously from the old
session, not a live one nagging you.

## What it costs

One haiku call per fired idle event: ~6K input tokens (capped), a few
hundred output — about **$0.01 per handoff**. It does not fire on trivial
sessions (transcript under 10KB), does not re-fire for an unchanged
transcript, and fires at most once per idle period. Active sessions cost
nothing but a `stat` poll every 15s.

## Install

```bash
./install.sh
```

Then merge `settings-snippet.json` into `~/.claude/settings.json` (it
registers a `hooks.Stop` entry and a `hooks.SessionEnd` entry). Restart or
start a new session to pick up the hooks.

## Config (env vars, e.g. in settings.json `env` block)

| Var | Default | Meaning |
|---|---|---|
| `IDLE_AUTOSAVE_DELAY` | `240` | Seconds of quiet before saving. Kept just inside the 5-min prompt-cache TTL on purpose: the whole benefit is that a handoff exists *before* you return to a cold cache, so raising it well past the TTL undercuts the point. |
| `IDLE_AUTOSAVE_POLL` | `15` | Poll interval (seconds) |
| `IDLE_AUTOSAVE_MIN_BYTES` | `10000` | Skip transcripts smaller than this |
| `IDLE_AUTOSAVE_MAX_CHARS` | `24000` | Cap on extracted transcript text |
| `IDLE_AUTOSAVE_NOTIFY` | `1` | macOS notification on save (0 to disable) |
| `IDLE_AUTOSAVE_CLAUDE_BIN` | auto | Override path to the claude CLI |

## Deliberate omissions

- **No slash command.** `/resume-session` is the consumer and already
  exists (idle-tax helper). A command here would be checklist filler.
- **No always-on timer daemon.** The watcher exists only between a Stop
  event and the next activity. An active session never accumulates watchers
  (each Stop replaces the previous one); an *ended* session is cleaned by
  the SessionEnd hook; and the worker removes its own `.pid` on exit. State
  never piles up.
- **Recursion guard.** The worker's headless claude call fires Stop and
  SessionEnd hooks too; `CLAUDE_IDLE_AUTOSAVE_CHILD=1` short-circuits both
  so the summarizer never summarizes (or cleans up after) itself.

## Edge cases

- **Laptop sleep**: sleep pauses the watcher's clock; the handoff fires on
  wake. Late but harmless — the transcript-unchanged check still holds.
- **Multiple parallel sessions**: watchers are keyed by session id; each
  session gets its own timer and its own handoff file. Earlier versions
  leaked here — the last watcher of every *ended* session was orphaned,
  leaving a stale `.pid` per session and firing a delayed handoff +
  notification for sessions you had already closed. The SessionEnd hook and
  the worker's self-cleaning `.pid` trap fix that.
- **Hard-killed sessions**: a closed terminal or crash skips SessionEnd, so
  the watcher still fires its one handoff. It no longer leaks a `.pid` (the
  worker self-cleans on exit) and the notification is labelled with the
  session id.
- **Repeated idles in one session**: same-day handoffs for one session
  overwrite the same file — freshest state wins, no file spam.

## Uninstall

```bash
./uninstall.sh
```

Then remove the idle-autosave entries from `hooks.Stop` and
`hooks.SessionEnd` in `~/.claude/settings.json`. Saved handoffs are kept.
