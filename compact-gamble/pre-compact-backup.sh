#!/bin/bash
# Pre-Compact Backup — saves a marker before compaction and urges context preservation
#
# The PreCompact hook fires before Claude Code compacts the conversation context.
# Compaction is lossy: Claude summarizes what it thinks matters and discards the
# rest. There is no recovery if something critical gets dropped.
#
# This hook does two things:
#   1. Writes a metadata marker file so you know exactly when a compact happened
#   2. Surfaces a systemMessage so you can still choose /save-session + fresh
#      session instead of gambling on the compaction
#
# What this hook CANNOT do: access conversation content, file states, or
# decisions — or inject context into the compaction (PreCompact has no
# additionalContext channel). The post-compact-verify hook does the
# Claude-facing part on the next prompt.
#
# Part of: claude-cost-helpers / compact-gamble
# Companion to: The Economics of Claude Code, Part 4: The Compact Gamble

INPUT=$(cat)

SESSIONS_DIR="${HOME}/.claude/sessions"
mkdir -p "$SESSIONS_DIR" 2>/dev/null

# Extract session ID (dual fallback: camelCase and snake_case)
SESSION_ID=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('sessionId', d.get('session_id', 'unknown')))
except:
    print('unknown')
" 2>/dev/null)

# Extract trigger if available ("manual" or "auto")
TRIGGER=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('trigger', 'unknown'))
except:
    print('unknown')
" 2>/dev/null)

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
ISO_TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# If session ID is unknown, use a UUID-based filename
if [ "$SESSION_ID" = "unknown" ]; then
    FILENAME="unknown-$(python3 -c 'import uuid; print(uuid.uuid4().hex[:8])')-pre-compact-${TIMESTAMP}.md"
else
    FILENAME="${SESSION_ID}-pre-compact-${TIMESTAMP}.md"
fi

MARKER_FILE="${SESSIONS_DIR}/${FILENAME}"

# Write the marker file (wrap in conditional to handle disk-full gracefully)
if cat > "$MARKER_FILE" 2>/dev/null <<MARKER
# Pre-Compact Marker

**Session:** ${SESSION_ID}
**Timestamp:** ${ISO_TIMESTAMP}
**Trigger:** ${TRIGGER}

This marker was created automatically before a compaction event. If you lost
context after this compact, start a fresh session and reference this timestamp
to understand when the loss occurred.

To avoid this in the future, use \`/save-session\` before compaction and
\`/resume-session\` in a fresh session.
MARKER
then
    MARKER_NOTE="A marker has been saved to ~/.claude/sessions/${FILENAME}."
else
    MARKER_NOTE="WARNING: Could not write marker file (disk full?)."
fi

# Write a compact-pending flag for post-compact verification
STATE_DIR="${HOME}/.claude/.session-state"
mkdir -p "$STATE_DIR" 2>/dev/null
echo "$ISO_TIMESTAMP" > "${STATE_DIR}/${SESSION_ID}.compact-pending" 2>/dev/null

# PreCompact hooks cannot inject context (Claude Code honors
# hookSpecificOutput.additionalContext for UserPromptSubmit, SessionStart,
# PreToolUse, PostToolUse and Stop — not PreCompact). The pre-v2 version of
# this hook emitted a top-level additionalContext that was never delivered.
# What a PreCompact hook CAN do is tell you: systemMessage is surfaced on
# every platform. The post-compact-verify hook (UserPromptSubmit) carries the
# instruction to Claude on the first prompt after the compaction.
cat <<EOF
{"continue": true, "suppressOutput": true, "systemMessage": "compact-gamble: compaction is about to run. ${MARKER_NOTE} Compaction is lossy; if you would rather not gamble, cancel and /save-session, then continue in a fresh session (clean, warm cache)."}
EOF
