#!/bin/bash
# Idle Autosave Worker — detached from the Stop hook; survives the hook's
# 5s timeout and even the session ending (so a /clear right after the last
# turn still gets its handoff a few minutes later).
#
# Flow:
#   1. Sleep in short polls. If the transcript mtime changes, the session is
#      active again — stand down silently (the next Stop re-arms a watcher).
#   2. After IDLE_AUTOSAVE_DELAY seconds of quiet, extract the conversation
#      tail from the transcript JSONL and ask `claude -p --model haiku` for a
#      structured handoff note (~$0.01; input capped at 24K chars).
#   3. On any CLI failure, fall back to a deterministic excerpt — a worse
#      handoff is still better than none.
#   4. Write atomically to ~/.claude/sessions/<date>-idle-autosave-<sid>-session.md
#      — the same glob /resume-session loads and the idle-tax hook surfaces.
#
# Config (env):
#   IDLE_AUTOSAVE_DELAY       seconds of quiet before saving (default 240)
#   IDLE_AUTOSAVE_POLL        poll interval seconds (default 15)
#   IDLE_AUTOSAVE_MIN_BYTES   skip transcripts smaller than this (default 10000)
#   IDLE_AUTOSAVE_MAX_CHARS   cap on extracted transcript text (default 24000)
#   IDLE_AUTOSAVE_NOTIFY      1 = macOS notification on save (default 1)
#   IDLE_AUTOSAVE_CLAUDE_BIN  override path to the claude CLI
#
# Part of: claude-cost-helpers / idle-autosave

set +e

SESSION_ID="$1"
TRANSCRIPT="$2"
CWD="$3"

DELAY="${IDLE_AUTOSAVE_DELAY:-240}"
POLL="${IDLE_AUTOSAVE_POLL:-15}"
MIN_BYTES="${IDLE_AUTOSAVE_MIN_BYTES:-10000}"
MAX_CHARS="${IDLE_AUTOSAVE_MAX_CHARS:-24000}"
NOTIFY="${IDLE_AUTOSAVE_NOTIFY:-1}"

STATE_DIR="${HOME}/.claude/.session-state"
SESSIONS_DIR="${HOME}/.claude/sessions"
MARKER="${STATE_DIR}/idle-autosave-${SESSION_ID}.last"
PID_FILE="${STATE_DIR}/idle-autosave-${SESSION_ID}.pid"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [${SESSION_ID:0:8}] $*"; }

[ -n "$SESSION_ID" ] && [ -f "$TRANSCRIPT" ] || exit 0

# Self-clean our PID file on exit (covers hard kills where SessionEnd never
# fires, so .pid files stop accumulating). Only remove it if it still points
# at us — a later Stop may have re-armed a new watcher and overwritten it.
trap '[ "$(cat "$PID_FILE" 2>/dev/null)" = "$$" ] && rm -f "$PID_FILE" 2>/dev/null' EXIT

mtime() { stat -f %m "$TRANSCRIPT" 2>/dev/null || stat -c %Y "$TRANSCRIPT" 2>/dev/null; }

START_MTIME=$(mtime)
SIZE=$(wc -c < "$TRANSCRIPT" 2>/dev/null | tr -d ' ')

if [ -z "$SIZE" ] || [ "$SIZE" -lt "$MIN_BYTES" ]; then
    log "skip: transcript ${SIZE:-0}B < ${MIN_BYTES}B (trivial session)"
    exit 0
fi

# Dedupe: this exact transcript state was already handed off.
if [ -f "$MARKER" ] && [ "$(cat "$MARKER" 2>/dev/null)" = "${START_MTIME}:${SIZE}" ]; then
    log "skip: transcript unchanged since last handoff"
    exit 0
fi

# --- Wait out the idle window; stand down on any activity ----------------
ELAPSED=0
while [ "$ELAPSED" -lt "$DELAY" ]; do
    sleep "$POLL"
    ELAPSED=$((ELAPSED + POLL))
    NOW_MTIME=$(mtime)
    [ -z "$NOW_MTIME" ] && exit 0   # transcript vanished (session purged)
    if [ "$NOW_MTIME" != "$START_MTIME" ]; then
        log "activity detected after ${ELAPSED}s — standing down"
        exit 0
    fi
done

# --- Idle confirmed: build the handoff ------------------------------------
mkdir -p "$SESSIONS_DIR" 2>/dev/null
OUT="${SESSIONS_DIR}/$(date +%Y-%m-%d)-idle-autosave-${SESSION_ID:0:8}-session.md"
TMP="${OUT}.tmp"

# Extract readable conversation tail from the transcript JSONL.
EXTRACT=$(IA_TRANSCRIPT="$TRANSCRIPT" IA_MAX="$MAX_CHARS" python3 - <<'PYEOF' 2>/dev/null
import json, os
path = os.environ["IA_TRANSCRIPT"]
cap = int(os.environ.get("IA_MAX", "24000"))
rows = []
with open(path, errors="replace") as f:
    for line in f:
        try:
            d = json.loads(line)
        except Exception:
            continue
        m = d.get("message") or {}
        role = m.get("role") or d.get("type")
        if role not in ("user", "assistant"):
            continue
        c = m.get("content")
        if isinstance(c, str):
            text = c
        elif isinstance(c, list):
            text = " ".join(
                b.get("text", "") for b in c
                if isinstance(b, dict) and b.get("type") == "text"
            )
        else:
            text = ""
        text = text.strip()
        if text:
            rows.append(f"{role.upper()}: {text}")
out, total = [], 0
for r in reversed(rows):          # newest first, then restore order
    out.append(r[:4000])
    total += len(out[-1])
    if total > cap:
        break
print("\n\n".join(reversed(out)))
PYEOF
)

# Deterministic header (zero tokens).
GIT_LINE=""
if git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1; then
    BRANCH=$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null)
    SHA=$(git -C "$CWD" rev-parse --short HEAD 2>/dev/null)
    DIRTY=$(git -C "$CWD" status --porcelain 2>/dev/null | grep -c .)
    GIT_LINE="- **Git**: \`${BRANCH}\` @ \`${SHA}\`, ${DIRTY} dirty files"
fi

# Rich body via headless haiku; bounded at 120s; fail open to deterministic.
BODY=""
CLAUDE_BIN="${IDLE_AUTOSAVE_CLAUDE_BIN:-$(command -v claude 2>/dev/null || echo "$HOME/.local/bin/claude")}"
if [ -x "$CLAUDE_BIN" ] && [ -n "$EXTRACT" ]; then
    PROMPT="Below is the extracted tail of a coding-session transcript. Write a concise markdown handoff note for resuming this work in a fresh session. Sections: '## What we were doing', '## Current state' (files touched, key decisions), '## What worked / what failed', '## Next step' (exact and actionable). Under 350 words. Output only the markdown, no preamble.

TRANSCRIPT:
"
    BODY_FILE=$(mktemp "${TMPDIR:-/tmp}/idle-autosave.XXXXXX")
    (
        printf '%s%s' "$PROMPT" "$EXTRACT" \
            | CLAUDE_IDLE_AUTOSAVE_CHILD=1 "$CLAUDE_BIN" -p --model haiku \
            > "$BODY_FILE" 2>/dev/null
    ) &
    CLAUDE_PID=$!
    WAITED=0
    while kill -0 "$CLAUDE_PID" 2>/dev/null && [ "$WAITED" -lt 120 ]; do
        sleep 5
        WAITED=$((WAITED + 5))
    done
    if kill -0 "$CLAUDE_PID" 2>/dev/null; then
        kill "$CLAUDE_PID" 2>/dev/null
        log "claude -p timed out after 120s — using fallback"
    fi
    wait "$CLAUDE_PID" 2>/dev/null
    BODY=$(cat "$BODY_FILE" 2>/dev/null)
    rm -f "$BODY_FILE"
fi

{
    echo "# Handoff (idle-autosave)"
    echo
    echo "- **Session**: \`${SESSION_ID}\`"
    echo "- **Saved**: $(date '+%Y-%m-%d %H:%M:%S %z') after ${DELAY}s idle"
    echo "- **CWD**: \`${CWD}\`"
    [ -n "$GIT_LINE" ] && echo "$GIT_LINE"
    echo
    if [ -n "$BODY" ]; then
        echo "$BODY"
    else
        echo "## Transcript tail (deterministic fallback — claude CLI unavailable or failed)"
        echo
        echo '```'
        echo "$EXTRACT" | tail -c 4000
        echo '```'
        echo
        echo "Environmental state: \`~/.claude/sessions/auto-state/${SESSION_ID}.md\`"
    fi
    echo
    echo "---"
    echo "_Written automatically by idle-autosave after ${DELAY}s of inactivity. Resume with /resume-session._"
} > "$TMP" && mv "$TMP" "$OUT"

echo "${START_MTIME}:${SIZE}" > "$MARKER"
log "handoff written: $OUT $([ -n "$BODY" ] && echo '(haiku)' || echo '(fallback)')"

if [ "$NOTIFY" = "1" ] && command -v osascript >/dev/null 2>&1; then
    # Pass dynamic text as argv (not interpolated into AppleScript) so a cwd
    # with spaces/quotes can't break or inject. The subtitle disambiguates
    # bursts: N ended sessions each fire their own identifiable banner instead
    # of an anonymous, repeated-looking nag.
    osascript \
        -e 'on run argv' \
        -e 'display notification (item 1 of argv) with title "Claude idle-autosave" subtitle (item 2 of argv)' \
        -e 'end run' \
        "Handoff saved for $(basename "$CWD" 2>/dev/null) — starting fresh is free" \
        "session ${SESSION_ID:0:8} · $(date '+%H:%M:%S')" >/dev/null 2>&1
fi

exit 0
