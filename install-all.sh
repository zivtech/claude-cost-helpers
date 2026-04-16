#!/bin/bash
# Claude Cost Helpers — install all helpers
#
# Runs each helper's install.sh in sequence, then prints the combined
# settings.json snippet for manual merge. Backs up existing files.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "Installing: All Claude Cost Helpers"
echo "===================================="
echo ""

FAILED=()

for helper in idle-tax just-one-more-turn subagent-isolation compact-gamble watching-cost effort-control auto-persist; do
    HELPER_DIR="${SCRIPT_DIR}/${helper}"
    if [ -d "$HELPER_DIR" ] && [ -x "${HELPER_DIR}/install.sh" ]; then
        echo "─────────────────────────────────────────────"
        echo ""
        (cd "$HELPER_DIR" && ./install.sh)
        echo ""
    else
        echo "SKIP: ${helper} (not found or install.sh not executable)"
        FAILED+=("$helper")
    fi
done

echo "═════════════════════════════════════════════"
echo ""

if [ ${#FAILED[@]} -gt 0 ]; then
    echo "WARNING: The following helpers were skipped:"
    for f in "${FAILED[@]}"; do
        echo "  - $f"
    done
    echo ""
fi

echo "COMBINED SETTINGS SNIPPET"
echo "========================="
echo ""
echo "Each helper printed its own snippet above. If you are installing all"
echo "helpers, use this combined block instead (merge into ~/.claude/settings.json):"
echo ""
echo "────────────────────────────────────────────────────────────────────"
cat <<'COMBINED'
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/cost-helpers/idle-tax/cache-idle-timer.sh",
            "timeout": 5,
            "statusMessage": "Checking cache freshness..."
          }
        ]
      },
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/cost-helpers/just-one-more-turn/context-usage-monitor.sh",
            "timeout": 5,
            "statusMessage": "Checking context usage..."
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "^(Read|Glob|Grep)$",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/cost-helpers/subagent-isolation/file-count-monitor.sh",
            "timeout": 5
          }
        ]
      },
      {
        "matcher": ".*",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/cost-helpers/watching-cost/output-size-monitor.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "PreCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/cost-helpers/compact-gamble/pre-compact-backup.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/cost-helpers/effort-control/effort-pin-banner.sh",
            "timeout": 5,
            "statusMessage": "Checking effort pin..."
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/cost-helpers/auto-persist/stop-auto-persist.sh",
            "timeout": 5
          }
        ]
      }
    ]
  },
  "env": {
    "CLAUDE_CODE_EFFORT_LEVEL": "high"
  },
  "effortLevel": "high"
}
COMBINED
echo "────────────────────────────────────────────────────────────────────"
echo ""
echo "Note: the PostToolUse array has two entries with different matchers."
echo "The file-count monitor only fires on Read/Glob/Grep, while the"
echo "output-size monitor fires on all tools."
echo ""
echo "Done. See each helper's README.md for details."
echo ""
