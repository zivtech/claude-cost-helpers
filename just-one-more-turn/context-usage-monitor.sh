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
# Output uses the documented hook contract for UserPromptSubmit:
#   hookSpecificOutput.additionalContext -> what Claude sees this turn
#   systemMessage                        -> what YOU see (CLI and desktop app)
#
# Part of: claude-cost-helpers / just-one-more-turn
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
echo "[context] turn ${TURN_COUNT}, ~${EST_K}K est (${PCT}%)" >&2

emit() {  # emit <systemMessage> <additionalContext>
    MSG="$1" CONTEXT="$2" python3 - <<'PYEOF'
import json, os
print(json.dumps({
    "continue": True,
    "suppressOutput": True,
    "systemMessage": os.environ["MSG"],
    "hookSpecificOutput": {"hookEventName": "UserPromptSubmit",
                           "additionalContext": os.environ["CONTEXT"]},
}))
PYEOF
}

if [ "$PCT" -ge 100 ]; then
    # Past the threshold — strong warning
    echo "[context] rot zone (~${EST_K}k est)" >&2
    emit "just-one-more-turn: CONTEXT ROT ZONE (~${EST_K}k est) — /split recommended." \
         "CONTEXT ROT ZONE (~${EST_K}k est): Context is past the rot zone (~${EST_K}k est). Quality and cost are both degrading. \`/split\` recommended.

At this size, each turn re-reads the full context. You are paying for tokens that are diluting rather than improving results.

Run \`/split\` to save a handoff and continue in a clean session."
elif [ "$PCT" -ge 90 ]; then
    # Approaching threshold — direct warning
    echo "[context] warning (~${EST_K}k est)" >&2
    emit "just-one-more-turn: CONTEXT WARNING (~${EST_K}k est) — consider /split." \
         "CONTEXT WARNING (~${EST_K}k est): Context is getting heavy (~${EST_K}k est). Consider \`/split\` to start fresh with a handoff.

Response quality tends to degrade as the context window fills. Starting a new session now is cheaper and produces better results than continuing here."
elif [ "$PCT" -ge 70 ]; then
    # Soft warning — heads-up, not urgent
    echo "[context] heads-up (~${EST_K}k est)" >&2
    emit "just-one-more-turn: context heads-up (~${EST_K}k est) — approaching the rot zone." \
         "CONTEXT HEADS-UP (~${EST_K}k est): Context is getting heavy (~${EST_K}k est). You're approaching the rot zone where quality degrades and cost per turn keeps climbing.

No action needed yet — but if this session runs much longer, consider \`/split\`."
else
    # Below 70% — stay silent
    echo '{"continue": true, "suppressOutput": true}'
fi
