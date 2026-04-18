#!/bin/bash
# Effort Pin Banner — confirms (or warns about) the CLAUDE_CODE_EFFORT_LEVEL pin
#
# Opus 4.7 defaults to xhigh effort. xhigh spends meaningfully more thinking
# tokens per turn than high. high is the documented minimum for intelligence-
# sensitive work. Pinning via CLAUDE_CODE_EFFORT_LEVEL is the only mechanism
# that survives the "first run on new model family" override.
#
# This hook fires on SessionStart and confirms the pin is active. If the env
# var is missing, set to xhigh/max/auto, or set to an invalid value, the hook
# emits a warning so the user knows they are back on the model default.
#
# Part of: claude-cost-helpers / effort-control
# Companion to: The Economics of Claude Code, Part 6 (or Part 1 4.7 addendum)

# Read the pinned effort level from the process env. Claude Code injects
# settings.json env vars into hook process environments.
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
        # Pin is active and at or below the model default. Banner confirms it.
        cat <<EOF
{"continue": true, "additionalContext": "EFFORT PINNED: ${PINNED} (via ${SOURCE}).\nOpus 4.7 defaults to xhigh; you are opting into cheaper reasoning.\nFor a hard task this turn only, prepend 'ultrathink' or use /deep.\nFor the rest of the session, run /effort xhigh or /effort max."}
EOF
        ;;
    xhigh|max)
        # Pin is set but to a value at or above the model default — no cost
        # savings vs unpinned. Flag it as a no-op.
        cat <<EOF
{"continue": true, "additionalContext": "EFFORT PIN NO-OP: pinned to ${PINNED}, which matches or exceeds the Opus 4.7 default (xhigh). The pin is not saving you any reasoning tokens. To get the documented savings, set CLAUDE_CODE_EFFORT_LEVEL=high in ~/.claude/settings.json env block."}
EOF
        ;;
    auto)
        # Explicitly opting back into the model default.
        cat <<EOF
{"continue": true, "additionalContext": "EFFORT: auto (model default, currently xhigh on Opus 4.7). The effort-control helper is installed but the pin is set to 'auto'. Set CLAUDE_CODE_EFFORT_LEVEL=high to opt into cheaper reasoning."}
EOF
        ;;
    "")
        # Pin is missing — helper is installed but env var was not set.
        cat <<EOF
{"continue": true, "additionalContext": "EFFORT PIN MISSING: CLAUDE_CODE_EFFORT_LEVEL is not set. The effort-control helper hook is running, but the env var that does the actual pinning is missing from ~/.claude/settings.json. Add: \"env\": { \"CLAUDE_CODE_EFFORT_LEVEL\": \"high\" }"}
EOF
        ;;
    *)
        # Unknown value — log it but don't fail.
        cat <<EOF
{"continue": true, "additionalContext": "EFFORT PIN UNKNOWN: CLAUDE_CODE_EFFORT_LEVEL is set to '${PINNED}', which is not a recognized effort level. Valid: low, medium, high, xhigh, max, auto."}
EOF
        ;;
esac
