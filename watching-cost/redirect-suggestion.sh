#!/bin/bash
# Redirect Suggestion — nudges when a known-verbose command dumps output into context
#
# Some commands are predictably verbose: recursive greps, finds across large
# trees, full file listings, log tails. When their output is large, it sits
# in context permanently. Redirecting to a file (`> results.txt`) and then
# reading selectively is almost always cheaper.
#
# This hook fires on PostToolUse for Bash. It checks the command against
# known-verbose patterns and if the output exceeds a threshold, suggests
# redirection. Lighter than the CI suggestion hook — this is for everyday
# commands, not test/build runs.
#
# Part of: claude-cost-helpers / watching-cost
# Companion to: The Economics of Claude Code, Part 5: The watching cost

INPUT=$(cat)

PYTHON_OUT=$(echo "$INPUT" | python3 -c "
import sys, json, re

try:
    d = json.load(sys.stdin)
except Exception:
    print('skip')
    sys.exit(0)

ti = d.get('tool_input', {}) or {}
cmd = ti.get('command', '')
tr = d.get('tool_response', d.get('tool_result', d.get('tool_output', '')))
if isinstance(tr, dict):
    tr = json.dumps(tr)
elif not isinstance(tr, str):
    tr = str(tr) if tr else ''

# Already redirected? Skip.
if re.search(r'>\s*\S+', cmd) or '| head' in cmd or '| tail' in cmd:
    print('skip')
    sys.exit(0)

verbose_patterns = [
    (r'\bfind\s+', 'find'),
    (r'\bgrep\s+-r', 'grep -r'),
    (r'\brg\s+', 'ripgrep'),
    (r'\bls\s+-[^\s]*R', 'ls -R'),
    (r'\btail\s+-f', 'tail -f'),
    (r'\bcat\s+', 'cat'),
    (r'\bcurl\s+', 'curl'),
    (r'\bdocker\s+logs', 'docker logs'),
    (r'\bkubectl\s+logs', 'kubectl logs'),
    (r'\bjournalctl\b', 'journalctl'),
]

matched = None
for pattern, name in verbose_patterns:
    if re.search(pattern, cmd):
        matched = name
        break

if not matched:
    print('skip')
    sys.exit(0)

char_count = len(tr)
tokens = char_count // 4
print(f'{matched}\t{tokens}')
" 2>/dev/null)

if [ -z "$PYTHON_OUT" ] || [ "$PYTHON_OUT" = "skip" ]; then
    echo '{"continue": true, "suppressOutput": true}'
    exit 0
fi

CMD_NAME=$(echo "$PYTHON_OUT" | cut -f1)
TOKENS=$(echo "$PYTHON_OUT" | cut -f2)

REDIRECT_THRESHOLD="${CLAUDE_REDIRECT_THRESHOLD:-3000}"

if [ "$TOKENS" -ge "$REDIRECT_THRESHOLD" ]; then
    TOKENS_K=$(( TOKENS / 1000 ))
    MSG="That ${CMD_NAME} dumped ~${TOKENS_K}K tokens into context. Next time, consider redirecting to a file (\`> \$TMPDIR/results.txt\`) and reading selectively, or piping through \`head\`/\`grep\` to grab only what you need."
    MSG_JSON=$(echo "$MSG" | python3 -c "import sys,json;print(json.dumps(sys.stdin.read().rstrip()))" 2>/dev/null)
    echo "{\"continue\": true, \"additionalContext\": ${MSG_JSON}}"
else
    echo '{"continue": true, "suppressOutput": true}'
fi
