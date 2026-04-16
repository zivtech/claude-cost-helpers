#!/bin/bash
# Output Size Monitor — warns when tool output inflates context cost
#
# Every byte of tool output that lands in context is reprocessed on every
# subsequent API call for the rest of the session. A 10,000-line file read,
# a full test suite dump, a verbose build log — each one sits in the token
# window permanently, costing you on every future message until you start
# fresh. This hook tracks that accumulation and warns before it gets out of
# hand.
#
# Fires on PostToolUse (after every tool call). Measures the tool_response
# size, accumulates an estimated token count per session, and warns at:
#   - Per-call: >5,000 estimated tokens in a single response
#   - Cumulative 25K: first escalation — this is getting expensive
#   - Cumulative 50K: second escalation — consider splitting the session
#   - Cumulative 100K: third escalation — real money is being burned
#
# Part of: claude-cost-helpers / watching-cost
# Companion to: The Economics of Claude Code, Part 5: The watching cost

INPUT=$(cat)

STATE_DIR="${HOME}/.claude/.session-state"
mkdir -p "$STATE_DIR" 2>/dev/null

# Extract session ID and measure tool_response length in a single python3 call.
# tool_response may be a string, dict (e.g. {"stdout":...,"stderr":...}), or null.
# We convert everything to a string before measuring.
PYTHON_OUT=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    sid = d.get('session_id', d.get('sessionId', 'unknown'))
    tr = d.get('tool_response', d.get('tool_result', d.get('tool_output', '')))
    if isinstance(tr, dict):
        tr = json.dumps(tr)
    elif not isinstance(tr, str):
        tr = str(tr) if tr else ''
    print(f'{sid}\t{len(tr)}')
except:
    print('unknown\t0')
" 2>/dev/null)

SESSION_ID=$(echo "$PYTHON_OUT" | cut -f1)
CHAR_COUNT=$(echo "$PYTHON_OUT" | cut -f2)

# Empty or null response — nothing to track
if [ -z "$CHAR_COUNT" ] || [ "$CHAR_COUNT" -eq 0 ] 2>/dev/null; then
    echo '{"continue": true, "suppressOutput": true}'
    exit 0
fi

# Estimate tokens: 1 token ≈ 4 characters
CALL_TOKENS=$(( CHAR_COUNT / 4 ))

# Per-call threshold (default 5000 tokens = ~20000 chars)
PER_CALL_THRESHOLD="${CLAUDE_OUTPUT_THRESHOLD:-5000}"

# Cumulative thresholds (default: 25000, 50000, 100000)
IFS=',' read -ra CUM_THRESHOLDS <<< "${CLAUDE_OUTPUT_CUMULATIVE_THRESHOLDS:-25000,50000,100000}"

# State files
TOKENS_FILE="${STATE_DIR}/${SESSION_ID}.output-tokens"
WARNED_FILE="${STATE_DIR}/${SESSION_ID}.output-warned-at"

# Read current cumulative total
CUMULATIVE=0
if [ -f "$TOKENS_FILE" ]; then
    CUMULATIVE=$(cat "$TOKENS_FILE" 2>/dev/null || echo 0)
    # Guard against non-numeric content
    [[ "$CUMULATIVE" =~ ^[0-9]+$ ]] || CUMULATIVE=0
fi

# Update cumulative total
NEW_CUMULATIVE=$(( CUMULATIVE + CALL_TOKENS ))
echo "$NEW_CUMULATIVE" > "$TOKENS_FILE"

# Read already-warned thresholds
WARNED_AT=""
if [ -f "$WARNED_FILE" ]; then
    WARNED_AT=$(cat "$WARNED_FILE" 2>/dev/null || echo "")
fi

# Collect warning messages
WARNINGS=""

# Per-call warning
if [ "$CALL_TOKENS" -ge "$PER_CALL_THRESHOLD" ]; then
    CALL_K=$(( CALL_TOKENS / 1000 ))
    WARNINGS="That tool returned ~${CALL_K}k tokens of output now sitting in context. Every future message in this session will reprocess it. Consider: (1) redirecting long output to a file with \`/to-file\`, (2) using a subagent for output-heavy work, (3) being specific about what you need (e.g., 'show me lines 40-60' instead of 'show me the file')."
fi

# Cumulative threshold warnings (each fires only once per session)
for THRESHOLD in "${CUM_THRESHOLDS[@]}"; do
    # Already warned at this threshold?
    if echo "$WARNED_AT" | grep -qw "$THRESHOLD"; then
        continue
    fi

    # Did we just cross it?
    if [ "$NEW_CUMULATIVE" -ge "$THRESHOLD" ] && [ "$CUMULATIVE" -lt "$THRESHOLD" ]; then
        case "$THRESHOLD" in
            25000)
                CUM_MSG="Cumulative tool output in this session: ~25K tokens. This 'watching cost' is reprocessed on every message. Consider using \`/to-file\` for large outputs going forward."
                ;;
            50000)
                CUM_MSG="Cumulative tool output: ~50K tokens. Context is getting expensive. Consider \`/split\` or start a fresh session to avoid carrying this weight forward."
                ;;
            100000)
                CUM_MSG="Cumulative tool output: ~100K tokens. This session is carrying significant dead weight. A fresh session would save real money."
                ;;
            *)
                CUM_MSG="Cumulative tool output: ~$(( THRESHOLD / 1000 ))K tokens accumulated in this session."
                ;;
        esac

        # Append to warned list
        if [ -n "$WARNED_AT" ]; then
            WARNED_AT="${WARNED_AT},${THRESHOLD}"
        else
            WARNED_AT="${THRESHOLD}"
        fi
        echo "$WARNED_AT" > "$WARNED_FILE"

        # Combine with per-call warning if both fired
        if [ -n "$WARNINGS" ]; then
            WARNINGS="${WARNINGS}\n\n${CUM_MSG}"
        else
            WARNINGS="$CUM_MSG"
        fi
    fi
done

# Output the result
if [ -n "$WARNINGS" ]; then
    # Escape for JSON: replace backslashes, double-quotes, and newlines
    WARNINGS_JSON=$(echo -e "$WARNINGS" | python3 -c "
import sys, json
print(json.dumps(sys.stdin.read().rstrip()))
" 2>/dev/null)
    echo "{\"continue\": true, \"additionalContext\": ${WARNINGS_JSON}}"
else
    echo '{"continue": true, "suppressOutput": true}'
fi
