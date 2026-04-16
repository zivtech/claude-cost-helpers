#!/bin/bash
# Cache Idle Timer — warns when prompt cache has likely expired (5-min TTL)
#
# The Anthropic prompt cache has a 5-minute inactivity TTL. Every API call
# that hits the cached prefix resets the timer. When you walk away from a
# session for >5 minutes, the next message re-caches the entire conversation
# prefix at 1.25x base cost — a 12.5x price increase vs a cache hit.
#
# This hook fires on UserPromptSubmit (before the API call) so the user
# can choose to start a fresh session instead of paying the re-cache cost.
#
# Part of: claude-cost-helpers / 01-idle-tax
# Companion to: The Economics of Claude Code, Part 1: The Idle Tax

INPUT=$(cat)

STATE_DIR="${HOME}/.claude/.session-state"
mkdir -p "$STATE_DIR" 2>/dev/null

# Extract session ID
SESSION_ID=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('sessionId', d.get('session_id', 'unknown')))
except:
    print('unknown')
" 2>/dev/null)

ACTIVITY_FILE="${STATE_DIR}/${SESSION_ID}.last-activity"
NOW=$(date +%s)

if [ -f "$ACTIVITY_FILE" ]; then
    LAST_ACTIVITY=$(cat "$ACTIVITY_FILE")
    GAP=$((NOW - LAST_ACTIVITY))

    # Update the activity timestamp
    echo "$NOW" > "$ACTIVITY_FILE"

    # Find most recent handoff note for context
    LATEST_HANDOFF=""
    if [ -d "${HOME}/.claude/sessions" ]; then
        LATEST_HANDOFF=$(ls -t "${HOME}/.claude/sessions/"*-session.md 2>/dev/null | head -1)
    fi

    if [ "$GAP" -ge 300 ]; then
        # Cache is dead — full re-cache will happen
        MINUTES=$((GAP / 60))
        HANDOFF_HINT=""
        if [ -n "$LATEST_HANDOFF" ]; then
            HANDOFF_HINT="\n\nMost recent handoff note: $LATEST_HANDOFF\nList all: ls -lt ~/.claude/sessions/ | head -10"
        fi
        cat <<EOF
{"continue": true, "additionalContext": "CACHE EXPIRED ($MINUTES min idle): Your prompt cache has expired (5-min TTL). This message will re-cache your full conversation context at 1.25x base token cost. For a 100K-token Opus session, that is ~\$0.63 vs ~\$0.05 for a cache hit (12.5x premium).\n\nOptions:\n1. Continue here (accept the re-cache cost)\n2. /save-session and start fresh (cheaper if context is large)\n3. Next time, /save-session before stepping away for >3 minutes${HANDOFF_HINT}\n\nThis is informational — your message will proceed normally."}
EOF
    elif [ "$GAP" -ge 240 ]; then
        # Cache expiring soon — 1 minute left
        SECONDS_LEFT=$((300 - GAP))
        cat <<EOF
{"continue": true, "additionalContext": "CACHE WARNING (~${SECONDS_LEFT}s remaining): Your prompt cache will expire soon. If you are about to step away, consider /save-session first. Returning after cache expiry costs 12.5x more than a warm cache hit."}
EOF
    else
        echo '{"continue": true, "suppressOutput": true}'
    fi
else
    # First message in this session — just record the timestamp
    echo "$NOW" > "$ACTIVITY_FILE"
    echo '{"continue": true, "suppressOutput": true}'
fi
