#!/bin/bash
# File Count Monitor — warns when too many files are read into a single session
#
# Every file Claude reads gets appended to the context window permanently.
# At 50+ unique files, you are carrying significant dead weight — file contents
# that were useful once but now just inflate token count on every subsequent
# turn. The fix is subagent isolation: delegate file-heavy work to an Agent
# call so those files live in a fresh context and only the summary comes back.
#
# This hook fires on PostToolUse for Read, Glob, and Grep. It tracks unique
# file paths per session and warns when the count crosses the threshold.
#
# Part of: claude-cost-helpers / 03-subagent-isolation
# Companion to: The Economics of Claude Code, Part 3: The agent that read 200 files

INPUT=$(cat)

STATE_DIR="${HOME}/.claude/.session-state"
mkdir -p "$STATE_DIR" 2>/dev/null

# Threshold and re-warn interval (configurable via env vars)
THRESHOLD="${CLAUDE_FILE_THRESHOLD:-50}"
WARN_INTERVAL="${CLAUDE_FILE_WARN_INTERVAL:-25}"

# Extract session ID, tool name, tool input, and tool response — then append
# any file paths discovered to the session's files-accessed log.
EXTRACT=$(echo "$INPUT" | python3 -c "
import sys, json, os

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)

session_id = d.get('sessionId', d.get('session_id', 'unknown'))
tool_name  = d.get('tool_name', '')
tool_input = d.get('tool_input', {}) or {}
tool_response = d.get('tool_response', d.get('tool_result', d.get('tool_output', ''))) or ''

paths = []

if tool_name == 'Read':
    fp = tool_input.get('file_path', '')
    if fp:
        paths.append(fp)
elif tool_name in ('Glob', 'Grep'):
    # tool_response is a string of newline-separated output lines
    resp_str = tool_response if isinstance(tool_response, str) else str(tool_response)
    for line in resp_str.splitlines():
        line = line.strip()
        if line.startswith('/'):
            paths.append(line)

print(session_id)
for p in paths:
    print(p)
" 2>/dev/null)

if [ -z "$EXTRACT" ]; then
    echo '{"continue": true, "suppressOutput": true}'
    exit 0
fi

SESSION_ID=$(echo "$EXTRACT" | head -1)
FILE_PATHS=$(echo "$EXTRACT" | tail -n +2)

ACCESSED_FILE="${STATE_DIR}/${SESSION_ID}.files-accessed"
WARNED_FILE="${STATE_DIR}/${SESSION_ID}.files-warned-at"

# Append newly discovered paths to the session log
if [ -n "$FILE_PATHS" ]; then
    echo "$FILE_PATHS" >> "$ACCESSED_FILE"
fi

# Count unique files accessed so far
if [ ! -f "$ACCESSED_FILE" ]; then
    echo '{"continue": true, "suppressOutput": true}'
    exit 0
fi

UNIQUE_COUNT=$(sort -u "$ACCESSED_FILE" | wc -l | tr -d ' ')

# Read last-warned-at count (0 if file doesn't exist)
LAST_WARNED=0
if [ -f "$WARNED_FILE" ]; then
    LAST_WARNED=$(cat "$WARNED_FILE")
fi

# Determine whether to warn
SINCE_LAST_WARN=$((UNIQUE_COUNT - LAST_WARNED))

if [ "$UNIQUE_COUNT" -ge "$THRESHOLD" ] && [ "$SINCE_LAST_WARN" -ge "$WARN_INTERVAL" ]; then
    # Update the warned-at file
    echo "$UNIQUE_COUNT" > "$WARNED_FILE"

    if [ "$LAST_WARNED" -eq 0 ]; then
        # First warning
        cat <<EOF
{"continue": true, "additionalContext": "FILE COUNT WARNING (${UNIQUE_COUNT} unique files): This session has read ${UNIQUE_COUNT} unique files. The context is getting heavy with file content. Consider using the \`Agent\` tool to delegate file-heavy work — subagents get their own context window and only return a summary.\n\nTry: /delegate to offload the next research or audit task to a subagent.\n\nThis is informational — your work will proceed normally."}
EOF
    else
        # Subsequent warning
        cat <<EOF
{"continue": true, "additionalContext": "FILE COUNT WARNING (${UNIQUE_COUNT} unique files): This session has now read ${UNIQUE_COUNT} unique files. Context bloat is compounding — each turn now carries all of that file content. Delegating remaining file-heavy tasks to subagents via the \`Agent\` tool will keep this session lean.\n\nTry: /delegate to offload the next research or audit task to a subagent.\n\nThis is informational — your work will proceed normally."}
EOF
    fi
else
    echo '{"continue": true, "suppressOutput": true}'
fi
