#!/bin/bash
# Idle Autosave Worker — detached from the Stop hook; survives the hook's
# 5s timeout and even the session ending (so a hard-killed session still
# gets its handoff).
#
# Flow:
#   1. Detect the prompt-cache TTL in effect for this session by reading the
#      last main-thread assistant message's usage block in the transcript:
#      ephemeral_1h_input_tokens > 0 -> 1-hour TTL, otherwise 5-minute TTL.
#      The idle window is TTL minus a lead time (default 15 min before a 1h
#      TTL expires = 45 min of quiet; 1 min before a 5m TTL = 4 min).
#   2. Sleep in short polls. If the transcript mtime changes, the session is
#      active again — stand down silently (the next Stop re-arms a watcher).
#   3. After the idle window, extract the conversation tail from the
#      transcript JSONL and ask a minimal headless `claude -p` for a
#      structured handoff note. The call is stripped to the bone: haiku,
#      effort low, no tools, no MCP, no skills, no user settings, a one-line
#      system prompt, no session persistence — about 250 input tokens and
#      ~$0.002 per handoff (measured), versus ~$0.18 with the default system
#      prompt loaded.
#   4. On any CLI failure, fall back to a deterministic excerpt — a worse
#      handoff is still better than none.
#   5. Write atomically to ~/.claude/sessions/<date>-idle-autosave-<sid>-session.md
#      — the same glob /resume-session loads and the idle-tax hook surfaces.
#
# Config (env):
#   IDLE_AUTOSAVE_DELAY       seconds of quiet before saving; default "auto"
#                             (TTL minus IDLE_AUTOSAVE_LEAD)
#   IDLE_AUTOSAVE_LEAD        seconds before cache expiry to save (default 900
#                             for a 1h TTL, 60 for a 5m TTL)
#   IDLE_AUTOSAVE_POLL        poll interval seconds (default 15)
#   IDLE_AUTOSAVE_MIN_BYTES   skip transcripts smaller than this (default 10000)
#   IDLE_AUTOSAVE_MAX_CHARS   cap on extracted transcript text (default 24000)
#   IDLE_AUTOSAVE_MODEL       model alias for the handoff call (default haiku)
#   IDLE_AUTOSAVE_EFFORT      effort for the handoff call (default low)
#   IDLE_AUTOSAVE_NOTIFY      1 = macOS notification on save (default 1)
#   IDLE_AUTOSAVE_CLAUDE_BIN  override path to the claude CLI
#
# Part of: claude-cost-helpers / idle-autosave

set +e

SESSION_ID="$1"
TRANSCRIPT="$2"
CWD="$3"

DELAY_CFG="${IDLE_AUTOSAVE_DELAY:-auto}"
POLL="${IDLE_AUTOSAVE_POLL:-15}"
MIN_BYTES="${IDLE_AUTOSAVE_MIN_BYTES:-10000}"
MAX_CHARS="${IDLE_AUTOSAVE_MAX_CHARS:-24000}"
MODEL="${IDLE_AUTOSAVE_MODEL:-haiku}"
EFFORT="${IDLE_AUTOSAVE_EFFORT:-low}"
NOTIFY="${IDLE_AUTOSAVE_NOTIFY:-1}"

STATE_DIR="${IDLE_AUTOSAVE_STATE_DIR:-${HOME}/.claude/.session-state}"
SESSIONS_DIR="${IDLE_AUTOSAVE_SESSIONS_DIR:-${HOME}/.claude/sessions}"
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

# --- Detect the cache TTL and derive the idle window ----------------------
# Reads the last main-thread assistant usage block (same rule idle-tax uses).
TTL=$(IA_TRANSCRIPT="$TRANSCRIPT" python3 - <<'PYEOF' 2>/dev/null
import json, os
path = os.environ["IA_TRANSCRIPT"]
size = os.path.getsize(path)
block, buf, pos, scanned, ttl = 256 * 1024, b"", size, 0, 300
with open(path, "rb") as fh:
    while pos > 0 and scanned < 16 * 1024 * 1024 and ttl == 300:
        step = min(block, pos); pos -= step
        fh.seek(pos); buf = fh.read(step) + buf; scanned += step
        lines = buf.split(b"\n"); buf = lines[0]
        for line in reversed(lines[1:]):
            if b"assistant" not in line or b"usage" not in line:
                continue
            try:
                d = json.loads(line)
            except Exception:
                continue
            if d.get("isSidechain"):
                continue
            u = (d.get("message") or {}).get("usage")
            if not u:
                continue
            cc = u.get("cache_creation") or {}
            ttl = 3600 if (cc.get("ephemeral_1h_input_tokens") or 0) > 0 else 300
            pos = 0
            break
print(ttl)
PYEOF
)
TTL="${TTL:-300}"
if [ "$DELAY_CFG" = "auto" ]; then
    if [ "$TTL" -ge 3600 ]; then LEAD="${IDLE_AUTOSAVE_LEAD:-900}"; else LEAD="${IDLE_AUTOSAVE_LEAD:-60}"; fi
    DELAY=$((TTL - LEAD))
    [ "$DELAY" -lt 60 ] && DELAY=60
else
    DELAY="$DELAY_CFG"
fi
TTL_LABEL=$([ "$TTL" -ge 3600 ] && echo "1-hour" || echo "5-minute")
log "armed: ${TTL_LABEL} cache TTL detected, saving after ${DELAY}s of quiet"

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
        if d.get("isSidechain"):
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
        if text and not text.startswith("<"):
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

# Rich body via a minimal headless call; bounded at 120s; fail open.
BODY=""
CLAUDE_BIN="${IDLE_AUTOSAVE_CLAUDE_BIN:-$(command -v claude 2>/dev/null || echo "$HOME/.local/bin/claude")}"
if [ -x "$CLAUDE_BIN" ] && [ -n "$EXTRACT" ]; then
    SYSTEM_PROMPT="You write concise markdown handoff notes so a coding session can be resumed in a fresh context. Output only markdown, no preamble."
    PROMPT="Below is the extracted tail of a coding-session transcript. Write a handoff note for resuming this work. Sections: '## What we were doing', '## Current state' (files touched, key decisions), '## What worked / what failed', '## Next step' (exact and actionable). Under 350 words.

TRANSCRIPT:
"
    BODY_FILE=$(mktemp "${TMPDIR:-/tmp}/idle-autosave.XXXXXX")

    # run_claude [env -u VAR ...] — one bounded attempt; result lands in BODY.
    run_claude() {
        (
            # CLAUDE_CODE_EFFORT_LEVEL outranks --effort, and hooks inherit the
            # session's env (typically the user's global pin) — override it so
            # the handoff really runs at $EFFORT.
            printf '%s%s' "$PROMPT" "$EXTRACT" \
                | env "$@" CLAUDE_CODE_EFFORT_LEVEL="$EFFORT" CLAUDE_IDLE_AUTOSAVE_CHILD=1 CLAUDE_SMART_INTERNAL=1 "$CLAUDE_BIN" -p \
                    --model "$MODEL" --effort "$EFFORT" \
                    --tools "" --strict-mcp-config --disable-slash-commands \
                    --setting-sources "" --no-session-persistence \
                    --system-prompt "$SYSTEM_PROMPT" \
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
            log "claude -p timed out after 120s"
        fi
        wait "$CLAUDE_PID" 2>/dev/null
        BODY=$(cat "$BODY_FILE" 2>/dev/null)
    }
    # An auth/API failure comes back on stdout as prose, not as a non-zero
    # exit — never let "Not logged in" become the handoff body.
    looks_bad() {
        [ "${#BODY}" -lt 120 ] || printf '%s' "$BODY" | grep -qiE 'not logged in|please run /login|api key is invalid|failed to authenticate|api error: 4[0-9][0-9]'
    }

    run_claude
    if looks_bad && [ -n "${ANTHROPIC_API_KEY:-}" ]; then
        # A tool-scoped or stale ANTHROPIC_API_KEY in the hook environment
        # shadows the interactive login. Retry once with it unset so the
        # CLI falls back to the same OAuth/keychain auth the session uses.
        log "handoff call failed with ANTHROPIC_API_KEY set — retrying with the key unset"
        run_claude -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN
    fi
    if looks_bad; then
        log "handoff call unusable ($(printf '%s' "$BODY" | head -c 80 | tr '\n' ' ')) — using fallback"
        BODY=""
    fi
    rm -f "$BODY_FILE"
fi

{
    echo "# Handoff (idle-autosave)"
    echo
    echo "- **Session**: \`${SESSION_ID}\`"
    echo "- **Saved**: $(date '+%Y-%m-%d %H:%M:%S %z') after ${DELAY}s idle (${TTL_LABEL} cache TTL)"
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
log "handoff written: $OUT $([ -n "$BODY" ] && echo "(${MODEL})" || echo '(fallback)')"

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
