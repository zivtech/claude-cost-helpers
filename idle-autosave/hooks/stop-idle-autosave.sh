#!/bin/bash
# Idle Autosave — arms a detached watcher on every Stop event. If the session
# then stays quiet for the idle window (default 240s, inside the 5-min cache
# TTL), the watcher writes a real handoff note to ~/.claude/sessions/.
#
# Why: the idle-tax hook warns at RETURN time — after the cache has already
# expired and the re-cache cost is unavoidable. This hook acts at IDLE time:
# by the moment the cache dies, a handoff note already exists, so "start
# fresh" is always a safe answer to the idle-tax prompt. The companion
# worker (idle-autosave-worker.sh) generates the note with a cheap headless
# `claude -p --model haiku` call, falling back to a deterministic transcript
# excerpt if the CLI is unavailable.
#
# Design constraints (match auto-persist):
#   - Returns in milliseconds: all waiting happens in the detached worker
#   - Never blocks a Stop event; fails open
#   - One watcher per session: each Stop kills the previous watcher,
#     so the idle timer always measures quiet since the LAST turn
#   - Recursion-guarded: the worker's headless claude call fires this hook
#     too; CLAUDE_IDLE_AUTOSAVE_CHILD short-circuits it
#
# Part of: claude-cost-helpers / idle-autosave

set +e  # never block a Stop event

# Recursion guard — the worker's headless `claude -p` run fires hooks too.
if [ -n "$CLAUDE_IDLE_AUTOSAVE_CHILD" ]; then
    exit 0
fi

INPUT=$(cat 2>/dev/null || echo '{}')

parsed=$(INPUT="$INPUT" python3 - <<'PYEOF' 2>/dev/null
import json, os
raw = os.environ.get("INPUT", "{}")
try:
    d = json.loads(raw) if raw.strip() else {}
except Exception:
    d = {}
print((d.get("session_id") or d.get("sessionId") or "unknown").replace("\n", " "))
print((d.get("transcript_path") or "").replace("\n", " "))
print((d.get("cwd") or os.getcwd()).replace("\n", " "))
PYEOF
)

SESSION_ID=$(echo "$parsed" | sed -n '1p')
TRANSCRIPT=$(echo "$parsed" | sed -n '2p')
CWD=$(echo "$parsed" | sed -n '3p')

# Nothing to watch without a real transcript.
if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ] || [ "$SESSION_ID" = "unknown" ]; then
    exit 0
fi

STATE_DIR="${HOME}/.claude/.session-state"
mkdir -p "$STATE_DIR" 2>/dev/null
PID_FILE="${STATE_DIR}/idle-autosave-${SESSION_ID}.pid"
LOG_FILE="${STATE_DIR}/idle-autosave.log"

# Re-arm: kill the previous watcher for this session, if it is really ours.
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$OLD_PID" ] && ps -p "$OLD_PID" -o command= 2>/dev/null | grep -q "idle-autosave-worker"; then
        kill "$OLD_PID" 2>/dev/null
    fi
fi

WORKER="$(cd "$(dirname "$0")" && pwd)/idle-autosave-worker.sh"
if [ ! -x "$WORKER" ]; then
    exit 0
fi

nohup "$WORKER" "$SESSION_ID" "$TRANSCRIPT" "$CWD" </dev/null >>"$LOG_FILE" 2>&1 &
echo $! > "$PID_FILE"

echo "[idle-autosave] watcher armed (${IDLE_AUTOSAVE_DELAY:-240}s idle window)" >&2
exit 0
