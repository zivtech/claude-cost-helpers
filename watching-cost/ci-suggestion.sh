#!/bin/bash
# CI Suggestion — nudges when test/build output bloats the context
#
# Long test suites and verbose builds dump thousands of lines into the
# context window where they sit permanently. The same work in CI produces
# a pass/fail result and a link — not 10K tokens of dead weight.
#
# This hook fires on PostToolUse for Bash. It checks whether the command
# looks like a test or build invocation, and if the output exceeds a
# threshold, suggests running it in CI next time.
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

# Detect test/build commands
test_patterns = [
    r'\bnpm\s+test\b', r'\bnpm\s+run\s+test\b', r'\bnpx\s+(jest|vitest|mocha|cypress)\b',
    r'\byarn\s+test\b', r'\bpnpm\s+test\b', r'\bbun\s+test\b',
    r'\bpytest\b', r'\bpython.*\bunittest\b', r'\btox\b',
    r'\bphpunit\b', r'\bddev\s+exec\s+phpunit\b',
    r'\bcargo\s+test\b', r'\bgo\s+test\b', r'\bmake\s+test\b',
    r'\brspec\b', r'\bbundle\s+exec\s+rspec\b',
]
build_patterns = [
    r'\bnpm\s+run\s+build\b', r'\bnpx\s+tsc\b', r'\bnpx\s+next\s+build\b',
    r'\byarn\s+build\b', r'\bpnpm\s+build\b',
    r'\bcargo\s+build\b', r'\bgo\s+build\b',
    r'\bmake\b(?!\s+test)', r'\bcmake\b',
]

is_test = any(re.search(p, cmd) for p in test_patterns)
is_build = any(re.search(p, cmd) for p in build_patterns)

if not is_test and not is_build:
    print('skip')
    sys.exit(0)

char_count = len(tr)
tokens = char_count // 4
kind = 'test' if is_test else 'build'
print(f'{kind}\t{tokens}')
" 2>/dev/null)

if [ -z "$PYTHON_OUT" ] || [ "$PYTHON_OUT" = "skip" ]; then
    echo '{"continue": true, "suppressOutput": true}'
    exit 0
fi

KIND=$(echo "$PYTHON_OUT" | cut -f1)
TOKENS=$(echo "$PYTHON_OUT" | cut -f2)

CI_THRESHOLD="${CLAUDE_CI_SUGGESTION_THRESHOLD:-10000}"

if [ "$TOKENS" -ge "$CI_THRESHOLD" ]; then
    TOKENS_K=$(( TOKENS / 1000 ))
    if [ "$KIND" = "test" ]; then
        MSG="That test run dumped ~${TOKENS_K}K tokens into context. Consider running tests in CI instead — you get a pass/fail result without carrying the full output in every future turn."
    else
        MSG="That build dumped ~${TOKENS_K}K tokens into context. Consider running builds in CI or redirecting output to a file. The build log is useful once, but it costs you on every turn after."
    fi
    MSG_JSON=$(echo "$MSG" | python3 -c "import sys,json;print(json.dumps(sys.stdin.read().rstrip()))" 2>/dev/null)
    echo "{\"continue\": true, \"additionalContext\": ${MSG_JSON}}"
else
    echo '{"continue": true, "suppressOutput": true}'
fi
