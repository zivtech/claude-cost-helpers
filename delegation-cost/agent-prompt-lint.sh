#!/bin/bash
# Agent Prompt Lint — nudges when an agent prompt lacks output length constraints
#
# The single most effective way to control the delegation tax is to constrain
# agent output size at the source. A prompt that says "report in under 200
# words" produces a 200-word result. A prompt with no constraint produces
# whatever the agent feels like — often 2,000+ words that land in your
# context permanently.
#
# This hook fires on PreToolUse for Agent. It checks the prompt field for
# output length constraint patterns. If none are found, it injects a
# reminder as additionalContext — the agent still runs, but you see the nudge.
#
# Part of: claude-cost-helpers / delegation-cost
# Companion to: The Economics of Claude Code, Part 6: The Delegation Tax

INPUT=$(cat)

PROMPT=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    ti = d.get('tool_input', {}) or {}
    print(ti.get('prompt', ''))
except:
    print('')
" 2>/dev/null)

if [ -z "$PROMPT" ]; then
    echo '{"continue": true, "suppressOutput": true}'
    exit 0
fi

HAS_CONSTRAINT=$(echo "$PROMPT" | python3 -c "
import sys, re
prompt = sys.stdin.read().lower()
patterns = [
    r'under \d+ words',
    r'fewer than \d+ words',
    r'in under \d+ words',
    r'max(imum)? \d+ words',
    r'\d+ words (or )?(less|max|limit)',
    r'keep.{0,20}(short|brief|terse|concise)',
    r'(short|brief|terse|concise) (response|report|summary|answer|output)',
    r'one (sentence|paragraph|line)',
    r'report in under',
    r'under \d+ (lines|sentences)',
]
for p in patterns:
    if re.search(p, prompt):
        print('yes')
        sys.exit(0)
print('no')
" 2>/dev/null)

if [ "$HAS_CONSTRAINT" = "yes" ]; then
    echo '{"continue": true, "suppressOutput": true}'
else
    echo '{"continue": true, "additionalContext": "This agent prompt has no output length constraint. Without one, the agent may return thousands of tokens that sit in your context permanently. Consider adding something like: \"report in under 200 words\" or \"keep it brief\"."}'
fi
