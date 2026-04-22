#!/bin/bash
# Starting Context Report — shows what's consuming base context at session start
#
# Every Claude Code session starts with a base token cost before you type a
# single character: CLAUDE.md files, memory, hooks, system prompt. If that
# base is already 40% of your context window, you have less runway before
# compaction or quality degradation kicks in.
#
# This hook fires on UserPromptSubmit. On the first turn of a session, it
# measures the size of known context contributors and reports the baseline.
# On subsequent turns, it stays silent.
#
# Part of: claude-cost-helpers / just-one-more-turn
# Companion to: The Economics of Claude Code, Part 2: The "just one more turn" trap

INPUT=$(cat)

STATE_DIR="${HOME}/.claude/.session-state"
mkdir -p "$STATE_DIR" 2>/dev/null

SESSION_ID=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('sessionId', d.get('session_id', 'unknown')))
except:
    print('unknown')
" 2>/dev/null)

REPORTED_FILE="${STATE_DIR}/${SESSION_ID}.context-reported"

if [ -f "$REPORTED_FILE" ]; then
    echo '{"continue": true, "suppressOutput": true}'
    exit 0
fi

touch "$REPORTED_FILE"

python3 -c "
import os, json, glob

home = os.path.expanduser('~')
items = []
total_chars = 0

def measure(path, label):
    global total_chars
    if os.path.isfile(path):
        size = os.path.getsize(path)
        tokens = size // 4
        total_chars += size
        items.append(f'{label}: ~{tokens:,} tokens')

measure(os.path.join(home, '.claude', 'CLAUDE.md'), 'Global CLAUDE.md')

for p in ['CLAUDE.md', '.claude/CLAUDE.md']:
    if os.path.isfile(p):
        measure(p, f'Project {p}')

memory_dir = os.path.join(home, '.claude', 'projects')
mem_total = 0
mem_count = 0
for root, dirs, files in os.walk(memory_dir):
    for f in files:
        if f.endswith('.md'):
            mem_total += os.path.getsize(os.path.join(root, f))
            mem_count += 1
if mem_count > 0:
    mem_tokens = mem_total // 4
    total_chars += mem_total
    items.append(f'Memory ({mem_count} files): ~{mem_tokens:,} tokens')

rules_dir = os.path.join(home, '.claude', 'rules')
rules_total = 0
rules_count = 0
if os.path.isdir(rules_dir):
    for root, dirs, files in os.walk(rules_dir):
        for f in files:
            if f.endswith('.md'):
                rules_total += os.path.getsize(os.path.join(root, f))
                rules_count += 1
if rules_count > 0:
    rules_tokens = rules_total // 4
    total_chars += rules_total
    items.append(f'Rules ({rules_count} files): ~{rules_tokens:,} tokens')

settings_path = os.path.join(home, '.claude', 'settings.json')
hook_count = 0
if os.path.isfile(settings_path):
    try:
        with open(settings_path) as sf:
            settings = json.load(sf)
        hooks = settings.get('hooks', {})
        for event_hooks in hooks.values():
            if isinstance(event_hooks, list):
                hook_count += len(event_hooks)
    except Exception:
        pass
if hook_count > 0:
    items.append(f'Hooks: {hook_count} configured')

total_tokens = total_chars // 4
total_k = total_tokens // 1000

if total_k < 1:
    print(json.dumps({'continue': True, 'suppressOutput': True}))
else:
    breakdown = ', '.join(items) if items else 'unknown'
    msg = f'STARTING CONTEXT (~{total_k}K tokens baseline): Your session starts with ~{total_k}K tokens of instructions and memory before any work begins. Breakdown: {breakdown}. This is your floor — every turn adds to it.'
    print(json.dumps({'continue': True, 'additionalContext': msg}))
" 2>/dev/null

if [ $? -ne 0 ]; then
    echo '{"continue": true, "suppressOutput": true}'
fi
