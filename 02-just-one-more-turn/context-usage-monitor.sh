#!/bin/bash
# Context Usage Monitor — warns when session context approaches the rot zone
#
# Context rot is what happens when a Claude Code session runs too long. As the
# context window fills, response quality degrades and cost per turn keeps
# climbing — you pay more for worse results. The problem is there's no native
# warning. Sessions that should have been split keep growing because "just one
# more turn" always feels justified in the moment.
#
# This hook fires on UserPromptSubmit and tracks turn count per session. It
# estimates total token usage (turns * configurable per-turn estimate) and warns
# when you approach or exceed a configurable threshold. The estimate is
# approximate — it is a floor based on turn count, not a ceiling. Actual usage
# depends on message length, tool output, and file reads.
#
# Part of: claude-cost-helpers / 02-just-one-more-turn
# Companion to: The Economics of Claude Code, Part 2: The "just one more turn" trap

INPUT=$(cat)

STATE_DIR="${HOME}/.claude/.session-state"
mkdir -p "$STATE_DIR" 2>/dev/null

# Extract session ID — dual fallback matches Helper 01 pattern
SESSION_ID=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('sessionId', d.get('session_id', 'unknown')))
except:
    print('unknown')
" 2>/dev/null)

USAGE_FILE="${STATE_DIR}/${SESSION_ID}.context-usage"

# Configuration — override via environment variables
TOKENS_PER_TURN="${CLAUDE_TOKENS_PER_TURN:-3000}"
CONTEXT_THRESHOLD="${CLAUDE_CONTEXT_THRESHOLD:-300000}"

# Append current timestamp as a new turn record
date +%s >> "$USAGE_FILE"

# Count turns (line count = turn count)
TURN_COUNT=$(wc -l < "$USAGE_FILE" | tr -d ' ')

# Estimate total tokens
EST_TOKENS=$((TURN_COUNT * TOKENS_PER_TURN))
EST_K=$((EST_TOKENS / 1000))

# Compute percentage of threshold
PCT=$(( (EST_TOKENS * 100) / CONTEXT_THRESHOLD ))

if [ "$PCT" -ge 100 ]; then
    # Past the threshold — strong warning
    cat <<EOF
{"continue": true, "additionalContext": "CONTEXT ROT ZONE (~${EST_K}k est): Context is past the rot zone (~${EST_K}k est). Quality and cost are both degrading. \`/split\` recommended.\n\nAt this size, each turn re-reads the full context. You are paying for tokens that are diluting rather than improving results.\n\nRun \`/split\` to save a handoff and continue in a clean session."}
EOF
elif [ "$PCT" -ge 90 ]; then
    # Approaching threshold — direct warning
    cat <<EOF
{"continue": true, "additionalContext": "CONTEXT WARNING (~${EST_K}k est): Context is getting heavy (~${EST_K}k est). Consider \`/split\` to start fresh with a handoff.\n\nResponse quality tends to degrade as the context window fills. Starting a new session now is cheaper and produces better results than continuing here."}
EOF
elif [ "$PCT" -ge 70 ]; then
    # Soft warning — heads-up, not urgent
    cat <<EOF
{"continue": true, "additionalContext": "CONTEXT HEADS-UP (~${EST_K}k est): Context is getting heavy (~${EST_K}k est). You're approaching the rot zone where quality degrades and cost per turn keeps climbing.\n\nNo action needed yet — but if this session runs much longer, consider \`/split\`."}
EOF
else
    # Below 70% — stay silent
    echo '{"continue": true, "suppressOutput": true}'
fi
