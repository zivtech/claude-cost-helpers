#!/bin/bash
# Idle Autosave — SessionEnd cleanup. Kills THIS session's armed idle watcher
# and removes its state files when the session ends gracefully (/clear, /exit,
# logout, prompt-input-exit), so a watcher never fires a "handoff saved"
# notification for a session you have already closed.
#
# Why this exists: the Stop hook's per-session re-arm only ever kills the SAME
# session's *previous* watcher. So the LAST watcher of every session you stop
# touching is orphaned and fires ~IDLE_AUTOSAVE_DELAY seconds later. Across
# many sessions (and workflow/eval child sessions) that produced bursts of
# identical "Claude idle-autosave" notifications and an unbounded pile of
# .pid files in ~/.claude/.session-state/.
#
# Belt-and-suspenders: the worker also removes its own .pid file on exit
# (covers hard kills / SIGKILL where SessionEnd never fires).
#
# Fails open; returns in milliseconds; never blocks session teardown.
#
# Part of: claude-cost-helpers / idle-autosave

set +e

# Recursion guard — the worker's headless `claude -p` run can end and fire
# SessionEnd too; never let a child clean up its parent's watcher.
if [ -n "$CLAUDE_IDLE_AUTOSAVE_CHILD" ]; then
    exit 0
fi

INPUT=$(cat 2>/dev/null || echo '{}')

SESSION_ID=$(INPUT="$INPUT" python3 - <<'PYEOF' 2>/dev/null
import json, os
raw = os.environ.get("INPUT", "{}")
try:
    d = json.loads(raw) if raw.strip() else {}
except Exception:
    d = {}
print((d.get("session_id") or d.get("sessionId") or "unknown").replace("\n", " "))
PYEOF
)

if [ -z "$SESSION_ID" ] || [ "$SESSION_ID" = "unknown" ]; then
    exit 0
fi

STATE_DIR="${HOME}/.claude/.session-state"
PID_FILE="${STATE_DIR}/idle-autosave-${SESSION_ID}.pid"
MARKER="${STATE_DIR}/idle-autosave-${SESSION_ID}.last"

# Kill the armed watcher for this session, but only if it is really ours.
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$OLD_PID" ] && ps -p "$OLD_PID" -o command= 2>/dev/null | grep -q "idle-autosave-worker"; then
        kill "$OLD_PID" 2>/dev/null
    fi
    rm -f "$PID_FILE" 2>/dev/null
fi

# Drop the dedupe marker too; a fresh resume of this id starts clean.
rm -f "$MARKER" 2>/dev/null

exit 0
