#!/bin/bash
# Effort Pin Banner — confirms (or warns about) the CLAUDE_CODE_EFFORT_LEVEL pin
#
# Claude Code defaults to xhigh effort on current models (Opus 4.7 and later,
# the Claude 5 family). xhigh spends meaningfully more thinking tokens per turn
# than high — and effort also shapes how many tool calls a turn makes, which
# is the dominant cost term in agentic sessions. high is the documented
# minimum for intelligence-sensitive work. Pinning via CLAUDE_CODE_EFFORT_LEVEL
# is the only mechanism that survives the "first run on a new model family"
# override.
#
# The pin is inherited by everything Claude Code spawns from your settings:
# subagents, agent-team teammates, and headless `claude -p` jobs run by other
# plugins. A `max` pin therefore also runs every background classifier at max.
#
# Fires on SessionStart. Output uses the documented hook contract:
#   hookSpecificOutput.additionalContext -> visible to Claude for the session
#   systemMessage                        -> visible to you (CLI + desktop app)
# (The pre-v2 top-level `additionalContext` field was never injected for this
# event, so the old banner reached neither you nor the model.)
#
# Part of: claude-cost-helpers / effort-control

set +e

PINNED="${CLAUDE_CODE_EFFORT_LEVEL:-}"
SOURCE="CLAUDE_CODE_EFFORT_LEVEL"

# If the env var is empty, also check the root-level effortLevel field as
# a fallback (belt + suspenders configuration).
if [ -z "$PINNED" ] && [ -f "${HOME}/.claude/settings.json" ]; then
    PINNED=$(python3 -c "
import json, sys
try:
    with open('${HOME}/.claude/settings.json') as f:
        d = json.load(f)
    print(d.get('effortLevel', '') or '')
except Exception:
    print('')
" 2>/dev/null)
    if [ -n "$PINNED" ]; then
        SOURCE="settings.json effortLevel field (env var missing — less robust against the first-run-on-new-model override)"
    fi
fi

case "$PINNED" in
    low|medium|high)
        CONTEXT="EFFORT PINNED: ${PINNED} (via ${SOURCE}). Claude Code's default is xhigh; this session opts into cheaper reasoning. For a hard task this turn only, prepend 'ultrathink' or use /deep. For the rest of the session, run /effort xhigh or /effort max."
        MSG="effort-control: pinned to ${PINNED} (default xhigh). Escalate per turn with /deep."
        ;;
    xhigh|max)
        CONTEXT="EFFORT PIN NO-OP: CLAUDE_CODE_EFFORT_LEVEL=${PINNED} matches or exceeds Claude Code's default (xhigh), so the pin saves nothing — and because the env pin is inherited, every subagent, teammate, and headless claude -p job on this machine also runs at ${PINNED}. To get the documented savings set the env value to high (or xhigh for agentic coding) in ~/.claude/settings.json, and escalate per turn with /deep when a task needs it."
        MSG="effort-control: pin is ${PINNED} — at/above the xhigh default, inherited by all subagents and headless jobs. Set high to actually save."
        ;;
    auto)
        CONTEXT="EFFORT: auto (model default, xhigh on current models). The effort-control helper is installed but the pin is 'auto'. Set CLAUDE_CODE_EFFORT_LEVEL=high to opt into cheaper reasoning."
        MSG="effort-control: pin is 'auto' (= xhigh default). Set high to save."
        ;;
    "")
        CONTEXT="EFFORT PIN MISSING: CLAUDE_CODE_EFFORT_LEVEL is not set. The effort-control hook is running, but the env var that does the pinning is missing from ~/.claude/settings.json. Add: \"env\": { \"CLAUDE_CODE_EFFORT_LEVEL\": \"high\" }"
        MSG="effort-control: no effort pin found — running at the xhigh default."
        ;;
    *)
        CONTEXT="EFFORT PIN UNKNOWN: CLAUDE_CODE_EFFORT_LEVEL is '${PINNED}', not a recognized level. Valid: low, medium, high, xhigh, max, auto."
        MSG="effort-control: unrecognized effort value '${PINNED}'."
        ;;
esac

echo "[effort] ${PINNED:-unset} (via ${SOURCE})" >&2

CONTEXT="$CONTEXT" MSG="$MSG" python3 - <<'PYEOF'
import json, os
print(json.dumps({
    "continue": True,
    "suppressOutput": True,
    "systemMessage": os.environ["MSG"],
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": os.environ["CONTEXT"],
    },
}))
PYEOF
exit 0
