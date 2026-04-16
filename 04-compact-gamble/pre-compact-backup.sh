#!/bin/bash
# Pre-Compact Backup — saves a marker before compaction and urges context preservation
#
# The PreCompact hook fires before Claude Code compacts the conversation context.
# Compaction is lossy: Claude summarizes what it thinks matters and discards the
# rest. There is no recovery if something critical gets dropped.
#
# This hook does two things:
#   1. Writes a metadata marker file so you know exactly when a compact happened
#   2. Injects additionalContext asking Claude to summarize key context before
#      the compact proceeds — that summary survives into the compacted session
#
# What this hook CANNOT do: access conversation content, file states, or
# decisions. Those live in Claude's context, not in the hook environment.
# The real value here is the additionalContext message that prompts Claude
# to preserve what matters before compaction runs.
#
# Part of: claude-cost-helpers / 04-compact-gamble
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

cat <<EOF
{"continue": true, "additionalContext": "PRE-COMPACT BACKUP: Compaction is about to run. ${MARKER_NOTE} Compaction is lossy — Claude decides what to keep. If something critical gets dropped, you can reference this marker to know when the compact happened.\n\nIMPORTANT: Before this compact proceeds, please briefly summarize: (1) what we were working on, (2) key decisions made, (3) current state of files, (4) the next step. This will be preserved in the compacted context.\n\nConsider: starting fresh with /save-session is often cheaper than compacting. Compaction keeps a stale session alive; a fresh session starts with a clean, warm cache."}
EOF
