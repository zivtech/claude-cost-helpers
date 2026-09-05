#!/bin/bash
# Delegation Result Monitor — warns when subagent results inflate context
#
# When a subagent finishes, its result lands in the parent session permanently.
# That result gets reprocessed on every subsequent turn. The subagent's own
# context is disposable. Its result is not. This hook tracks the accumulation
# and warns before the delegation tax outweighs the delegation benefit.
#
# Fires on PostToolUse with matcher ^Agent$. Measures the tool_response size,
# accumulates an estimated token count per session, and warns at:
#   - Per-result: >5,000 estimated tokens in a single agent result
#   - Cumulative 20K: first escalation — delegation results are adding up
#   - Cumulative 50K: second escalation — consider splitting the session
#   - Cumulative 100K: third escalation — the tax is real
#   - Cache cooling: the agent ran long enough that the parent's prompt cache
#     expired (or came within the lead time of expiring). TTL, cached context
#     size and model are read from the transcript, so the re-write is priced
#     with your numbers — nothing hardcoded (v2, September 2026).
#
# Part of: claude-cost-helpers / delegation-cost
# Companion to: The Economics of Claude Code, Part 6: The Delegation Tax

INPUT=$(cat)

STATE_DIR="${HOME}/.claude/.session-state"
mkdir -p "$STATE_DIR" 2>/dev/null

# Extract session ID, tool name, and measure tool_response length.
PYTHON_OUT=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    sid = d.get('session_id', d.get('sessionId', 'unknown'))
    tool = d.get('tool_name', d.get('toolName', 'Agent'))
    tr = d.get('tool_response', d.get('tool_result', d.get('tool_output', '')))
    if isinstance(tr, dict):
        tr = json.dumps(tr)
    elif not isinstance(tr, str):
        tr = str(tr) if tr else ''
    print(f'{sid}\t{len(tr)}\t{tool}')
except:
    print('unknown\t0\tAgent')
" 2>/dev/null)

SESSION_ID=$(echo "$PYTHON_OUT" | cut -f1)
CHAR_COUNT=$(echo "$PYTHON_OUT" | cut -f2)
TOOL_NAME=$(echo "$PYTHON_OUT" | cut -f3)

# Empty or null response — nothing to track
if [ -z "$CHAR_COUNT" ] || [ "$CHAR_COUNT" -eq 0 ] 2>/dev/null; then
    echo '{"continue": true, "suppressOutput": true}'
    exit 0
fi

# Estimate tokens: 1 token ~ 4 characters
CALL_TOKENS=$(( CHAR_COUNT / 4 ))

# Per-result threshold (default 5000 tokens = ~20000 chars)
PER_RESULT_THRESHOLD="${CLAUDE_DELEGATION_THRESHOLD:-5000}"

# Cumulative thresholds (default: 20000, 50000, 100000)
IFS=',' read -ra CUM_THRESHOLDS <<< "${CLAUDE_DELEGATION_CUMULATIVE_THRESHOLDS:-20000,50000,100000}"

# State files (separate namespace from watching-cost to avoid double-counting)
TOKENS_FILE="${STATE_DIR}/${SESSION_ID}.delegation-tokens"
WARNED_FILE="${STATE_DIR}/${SESSION_ID}.delegation-warned-at"
AGENTS_FILE="${STATE_DIR}/${SESSION_ID}.delegation-agents"

# Read current cumulative total
CUMULATIVE=0
if [ -f "$TOKENS_FILE" ]; then
    CUMULATIVE=$(cat "$TOKENS_FILE" 2>/dev/null || echo 0)
    [[ "$CUMULATIVE" =~ ^[0-9]+$ ]] || CUMULATIVE=0
fi

# Update cumulative total
NEW_CUMULATIVE=$(( CUMULATIVE + CALL_TOKENS ))
echo "$NEW_CUMULATIVE" > "$TOKENS_FILE"

# Track per-agent result sizes (append: tokens\ttimestamp)
echo "${CALL_TOKENS}	$(date +%H:%M:%S)" >> "$AGENTS_FILE"

# Read already-warned thresholds
WARNED_AT=""
if [ -f "$WARNED_FILE" ]; then
    WARNED_AT=$(cat "$WARNED_FILE" 2>/dev/null || echo "")
fi

# Count agents that have returned results this session
AGENT_COUNT=0
if [ -f "$AGENTS_FILE" ]; then
    AGENT_COUNT=$(wc -l < "$AGENTS_FILE" | tr -d ' ')
fi

# Cache-cooling check — did the parent's prompt cache expire (or come close)
# while this agent ran?
#
# A foreground Agent blocks the parent, so the parent's cache entry ages for the
# whole run; if the run outlasts the TTL, the call that consumes this result
# re-writes the entire prefix (2x input price on the 1-hour TTL, 1.25x on the
# 5-minute one). TTL-aware (v2): reads the LAST main-thread assistant message in
# the transcript — the one that dispatched this agent — and uses
#   usage.cache_creation.ephemeral_1h_input_tokens > 0  -> 1-hour TTL
#   otherwise                                           -> 5-minute TTL
# and measures the gap from THAT message's timestamp (the parent's last API
# call), not from your last prompt, so a long turn before the dispatch is never
# counted as idle. v1 hardcoded a 240 s threshold against idle-tax's prompt
# timestamp: on the 1-hour TTL that flagged a 17-minute agent as "cache went
# cold". (The row timestamp is the end of that response, so the true cache age
# is slightly larger — immaterial next to the 15-minute lead on the 1-hour TTL.)
#
# One warning per dispatch: parallel agents launched from one turn share a
# dispatch row, so the first result to cross a level (near/expired) warns and
# the rest stay quiet. Env knobs, same names as idle-tax:
#   CACHE_TTL_SECONDS    force the TTL (3600 or 300) instead of detecting it
#   CACHE_WARN_SECONDS   near-expiry lead (default 900 on 1h, 60 on 5m)
# Without a transcript_path the check only runs if CACHE_TTL_SECONDS is set,
# using idle-tax's prompt timestamp as an upper bound on the gap.
CACHE_WARNING=$(INPUT="$INPUT" STATE_DIR="$STATE_DIR" python3 - <<'PYEOF'
import json, os, sys, time
from datetime import datetime

try:
    d = json.loads(os.environ.get("INPUT") or "{}")
except Exception:
    d = {}
sid = d.get("session_id") or d.get("sessionId") or "unknown"
transcript = d.get("transcript_path") or ""
state_dir = os.environ["STATE_DIR"]
now = time.time()

PRICE_IN = [  # $/M input tokens, matched by substring, first hit wins
    ("fable", 10.0), ("mythos", 10.0), ("opus", 5.0),
    ("sonnet-5", 2.0), ("sonnet", 3.0), ("haiku", 1.0),
]


def price_for(model):
    for key, p in PRICE_IN:
        if key in (model or ""):
            return p
    return 5.0


def read_mult(model):
    # Claude Fable 5.1 / Mythos 5.1 read cache at 0.025x base input; others 0.1x.
    m = model or ""
    return 0.025 if ("fable-5-1" in m or "mythos-5-1" in m) else 0.1


def trace(note):
    sys.stderr.write(f"[delegation-cost] {note}\n")


def last_assistant(path, max_scan=16 * 1024 * 1024):
    """Return (timestamp_epoch, model, usage) of the last main-thread assistant
    message, scanning the transcript backwards in blocks."""
    try:
        size = os.path.getsize(path)
    except OSError:
        return None
    block = 256 * 1024
    with open(path, "rb") as fh:
        pos = size
        buf = b""
        scanned = 0
        while pos > 0 and scanned < max_scan:
            step = min(block, pos)
            pos -= step
            fh.seek(pos)
            buf = fh.read(step) + buf
            scanned += step
            lines = buf.split(b"\n")
            buf = lines[0]  # possibly partial first line; keep for next round
            for line in reversed(lines[1:]):
                if b'assistant' not in line or b'usage' not in line:
                    continue
                try:
                    obj = json.loads(line)
                except Exception:
                    continue
                if obj.get("isSidechain"):
                    continue
                msg = obj.get("message") or {}
                usage = msg.get("usage")
                if not usage:
                    continue
                ts = obj.get("timestamp")
                try:
                    epoch = datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
                except Exception:
                    epoch = None
                return epoch, msg.get("model") or "", usage
    return None


def fmt_tokens(n):
    return f"{n/1e6:.1f}M" if n >= 1e6 else f"{n/1e3:.0f}K"


def fmt_gap(sec):
    if sec < 60:
        return f"{int(sec)}s"
    m = int(sec // 60)
    return f"{m//60}h {m%60:02d}m" if m >= 60 else f"{m} min"


forced = os.environ.get("CACHE_TTL_SECONDS")
forced = int(forced) if forced and forced.isdigit() else None

info = last_assistant(transcript) if transcript and os.path.exists(transcript) else None
if info and info[0]:
    last_epoch, model, usage = info
    cc = usage.get("cache_creation") or {}
    ttl = 3600 if (cc.get("ephemeral_1h_input_tokens") or 0) > 0 else 300
    ctx = ((usage.get("cache_read_input_tokens") or 0)
           + (usage.get("cache_creation_input_tokens") or 0)
           + (usage.get("input_tokens") or 0))
    gap = now - last_epoch
    source = "transcript"
elif forced:
    # No transcript: idle-tax's prompt timestamp bounds the gap from above, and
    # that is only meaningful when the caller has told us the TTL.
    try:
        with open(os.path.join(state_dir, f"{sid}.last-activity")) as fh:
            last_epoch = float(fh.read().strip())
    except Exception:
        trace("no transcript and no .last-activity; skipping cache check")
        sys.exit(0)
    model, ctx, ttl, gap = "", 0, forced, now - last_epoch
    source = "prompt-timestamp fallback"
else:
    trace("no transcript_path; set CACHE_TTL_SECONDS to run the cache check without one")
    sys.exit(0)

if forced:
    ttl = forced
lead_default = 900 if ttl >= 3600 else 60
try:
    lead = int(os.environ.get("CACHE_WARN_SECONDS") or lead_default)
except ValueError:
    lead = lead_default
if gap < max(0, ttl - lead):
    trace(f"cache warm ({int(gap)}s agent run of {ttl}s TTL, via {source})")
    sys.exit(0)

# One warning per dispatch row; a higher level (expired > near) may follow a lower one.
level = 2 if gap >= ttl else 1
dedupe = os.path.join(state_dir, f"{sid}.delegation-cache-warned")
try:
    prev_epoch, prev_level = open(dedupe).read().split()
    if int(float(prev_epoch)) == int(last_epoch) and int(prev_level) >= level:
        trace("already warned for this dispatch")
        sys.exit(0)
except Exception:
    pass
try:
    with open(dedupe, "w") as fh:
        fh.write(f"{int(last_epoch)} {level}")
except OSError:
    pass

p = price_for(model)
rm = read_mult(model)
write_mult = 2.0 if ttl >= 3600 else 1.25
ratio = write_mult / rm
ttl_label = "1-hour" if ttl >= 3600 else "5-minute"
if ctx:
    cold = ctx * p * write_mult / 1e6
    warm = ctx * p * rm / 1e6
    rewrite = f"re-writes ~{fmt_tokens(ctx)} cached tokens, about ${cold:.2f} vs ${warm:.2f} warm ({ratio:g}x)"
else:
    rewrite = f"re-writes the full prefix ({ratio:g}x a warm hit)"
price_note = f"Cache writes cost {write_mult:g}x input price on the {ttl_label} TTL."

# First line is what you see (systemMessage, cut at 200 chars); the rest is for Claude.
if level == 2:
    head = f"PARENT CACHE EXPIRED while this agent ran ({fmt_gap(gap)} of a {ttl_label} TTL)"
    first = f"{head}: the call that consumes this result {rewrite}."
    body = (f"{price_note} Nothing to save on this one. Next time an agent may outlast the TTL: "
            "(1) dispatch it with run_in_background so the parent keeps making calls and its cache stays warm, "
            "(2) split the work into shorter agents, or (3) /save-session before dispatching so resuming fresh is free.")
else:
    head = f"PARENT CACHE CAME WITHIN {fmt_gap(ttl - gap)} OF EXPIRING while this agent ran ({fmt_gap(gap)} of a {ttl_label} TTL)"
    first = f"{head}. An agent that outlasts the TTL {rewrite}."
    body = (f"{price_note} This call refreshes the cache. For agents that may run this long, "
            "use run_in_background so the parent keeps its cache warm, or split the work into shorter agents.")
print(first + "\n" + body)
PYEOF
)

# Collect warning messages
WARNINGS=""

# Cache-warming warning goes first — it's the most actionable
if [ -n "$CACHE_WARNING" ]; then
    WARNINGS="$CACHE_WARNING"
fi

# Per-result warning
FILE_WRITE_THRESHOLD="${CLAUDE_DELEGATION_FILE_THRESHOLD:-8000}"
if [ "$CALL_TOKENS" -ge "$FILE_WRITE_THRESHOLD" ]; then
    CALL_K=$(( CALL_TOKENS / 1000 ))
    RESULT_MSG="That agent returned ~${CALL_K}K tokens — too large for inline results. Next time, ask the agent to write its findings to a file and return only a summary. This keeps the delegation benefit without the delegation tax."
elif [ "$CALL_TOKENS" -ge "$PER_RESULT_THRESHOLD" ]; then
    CALL_K=$(( CALL_TOKENS / 1000 ))
    RESULT_MSG="That agent returned ~${CALL_K}K tokens now sitting in context. Every future message reprocesses it. Consider: (1) tighter prompt constraints ('report in under 200 words'), (2) writing findings to a file instead of returning inline, (3) splitting the session after synthesizing."
fi
if [ -n "${RESULT_MSG:-}" ]; then
    if [ -n "$WARNINGS" ]; then
        WARNINGS="${WARNINGS}\n\n${RESULT_MSG}"
    else
        WARNINGS="$RESULT_MSG"
    fi
fi

# Cumulative threshold warnings (each fires only once per session)
for THRESHOLD in "${CUM_THRESHOLDS[@]}"; do
    if echo "$WARNED_AT" | grep -qw "$THRESHOLD"; then
        continue
    fi

    if [ "$NEW_CUMULATIVE" -ge "$THRESHOLD" ] && [ "$CUMULATIVE" -lt "$THRESHOLD" ]; then
        case "$THRESHOLD" in
            20000)
                CUM_MSG="Delegation results in this session: ~20K tokens. The tax is building — every turn reprocesses all of it. Consider tighter agent prompts going forward."
                ;;
            50000)
                CUM_MSG="Delegation results: ~50K tokens. The carrying cost is significant. Consider \`/split\` or writing future agent results to files instead of returning inline."
                ;;
            100000)
                CUM_MSG="Delegation results: ~100K tokens. The delegation tax exceeds the delegation benefit at this point. A fresh session would save real money."
                ;;
            *)
                CUM_MSG="Delegation results: ~$(( THRESHOLD / 1000 ))K tokens accumulated in this session."
                ;;
        esac

        if [ -n "$WARNED_AT" ]; then
            WARNED_AT="${WARNED_AT},${THRESHOLD}"
        else
            WARNED_AT="${THRESHOLD}"
        fi
        echo "$WARNED_AT" > "$WARNED_FILE"

        if [ -n "$WARNINGS" ]; then
            WARNINGS="${WARNINGS}\n\n${CUM_MSG}"
        else
            WARNINGS="$CUM_MSG"
        fi
    fi
done

# Swarm warning — fires once when 3+ agents have returned results
SWARM_WARNED_FILE="${STATE_DIR}/${SESSION_ID}.delegation-swarm-warned"
if [ "$AGENT_COUNT" -ge 3 ] && [ ! -f "$SWARM_WARNED_FILE" ]; then
    touch "$SWARM_WARNED_FILE"
    SWARM_MSG="${AGENT_COUNT} agents have returned results this session. That's a lot of delegation weight in one context. Consider \`/save-session\` and continuing fresh."
    if [ -n "$WARNINGS" ]; then
        WARNINGS="${WARNINGS}\n\n${SWARM_MSG}"
    else
        WARNINGS="$SWARM_MSG"
    fi
fi

# Output the result
if [ -n "$WARNINGS" ]; then
    # Claude gets the full text via hookSpecificOutput (the documented channel
    # for PostToolUse); you get the first line via systemMessage.
    echo -e "$WARNINGS" | python3 -c "
import sys, json
text = sys.stdin.read().rstrip()
print(json.dumps({'continue': True, 'suppressOutput': True,
                  'systemMessage': 'delegation-cost: ' + text.splitlines()[0][:200],
                  'hookSpecificOutput': {'hookEventName': 'PostToolUse', 'additionalContext': text}}))
" 2>/dev/null || echo '{"continue": true, "suppressOutput": true}'
else
    echo '{"continue": true, "suppressOutput": true}'
fi
