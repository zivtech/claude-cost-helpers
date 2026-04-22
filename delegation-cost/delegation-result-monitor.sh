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

# Collect warning messages
WARNINGS=""

# Per-result warning
FILE_WRITE_THRESHOLD="${CLAUDE_DELEGATION_FILE_THRESHOLD:-8000}"
if [ "$CALL_TOKENS" -ge "$FILE_WRITE_THRESHOLD" ]; then
    CALL_K=$(( CALL_TOKENS / 1000 ))
    WARNINGS="That agent returned ~${CALL_K}K tokens — too large for inline results. Next time, ask the agent to write its findings to a file and return only a summary. This keeps the delegation benefit without the delegation tax."
elif [ "$CALL_TOKENS" -ge "$PER_RESULT_THRESHOLD" ]; then
    CALL_K=$(( CALL_TOKENS / 1000 ))
    WARNINGS="That agent returned ~${CALL_K}K tokens now sitting in context. Every future message reprocesses it. Consider: (1) tighter prompt constraints ('report in under 200 words'), (2) writing findings to a file instead of returning inline, (3) splitting the session after synthesizing."
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
    WARNINGS_JSON=$(echo -e "$WARNINGS" | python3 -c "
import sys, json
print(json.dumps(sys.stdin.read().rstrip()))
" 2>/dev/null)
    echo "{\"continue\": true, \"additionalContext\": ${WARNINGS_JSON}}"
else
    echo '{"continue": true, "suppressOutput": true}'
fi
