#!/bin/bash
# Post-Compact Verification — reminds Claude to verify constraints after compaction
#
# Compaction is lossy. Claude summarizes the conversation and discards the
# original. Critical constraints — architectural decisions, file state,
# naming conventions, task boundaries — can silently drop out. This hook
# fires on UserPromptSubmit after a compact has occurred and reminds Claude
# to verify that key constraints survived.
#
# Works in tandem with pre-compact-backup.sh, which writes a .compact-pending
# flag before compaction runs. This hook checks for the flag, injects
# verification context, and removes the flag so it only fires once.
#
# Part of: claude-cost-helpers / compact-gamble
# Companion to: The Economics of Claude Code, Part 4: The Compact Gamble

INPUT=$(cat)

STATE_DIR="${HOME}/.claude/.session-state"

SESSION_ID=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('sessionId', d.get('session_id', 'unknown')))
except:
    print('unknown')
" 2>/dev/null)

PENDING_FILE="${STATE_DIR}/${SESSION_ID}.compact-pending"

if [ ! -f "$PENDING_FILE" ]; then
    echo '{"continue": true, "suppressOutput": true}'
    exit 0
fi

COMPACT_TIME=$(cat "$PENDING_FILE" 2>/dev/null || echo "unknown")
rm -f "$PENDING_FILE" 2>/dev/null

cat <<EOF
{"continue": true, "additionalContext": "POST-COMPACT CHECK: A compaction ran at ${COMPACT_TIME}. Context was summarized and the original discarded. Before continuing, verify: (1) re-read any CLAUDE.md or config files that were driving decisions, (2) confirm the current task and next step match what you remember, (3) check that file paths and branch state are still accurate. If anything feels uncertain, say so — it is better to re-read a file than to act on a compacted summary that dropped a constraint."}
EOF
