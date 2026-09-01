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

for helper in idle-tax just-one-more-turn subagent-isolation compact-gamble watching-cost delegation-cost effort-control auto-persist idle-autosave usage-report; do
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
      },
      {
        "matcher": "^Agent$",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/cost-helpers/delegation-cost/delegation-result-monitor.sh",
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
          },
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/cost-helpers/usage-report/sessionstart-usage-report.sh",
            "timeout": 10,
            "statusMessage": "Checking usage-report freshness..."
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
          },
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/cost-helpers/idle-autosave/stop-idle-autosave.sh",
            "timeout": 5,
            "statusMessage": "Arming idle autosave..."
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/cost-helpers/idle-autosave/sessionend-idle-autosave.sh",
            "timeout": 5,
            "statusMessage": "Cleaning up idle watcher..."
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
echo "Note: the PostToolUse array has three entries with different matchers."
echo "The file-count monitor fires on Read/Glob/Grep, the output-size"
echo "monitor fires on all tools, and the delegation monitor fires on Agent."
echo "Stop runs auto-persist then idle-autosave; SessionEnd cancels the idle"
echo "watcher; SessionStart runs the effort banner and the weekly usage report."
echo ""
echo "Done. See each helper's README.md for details."
echo ""
echo "═════════════════════════════════════════════"
echo ""
echo "ECOSYSTEM TOOLS (optional, complementary)"
echo "=========================================="
echo ""
echo "These helpers are sensors — they warn you about cost patterns."
echo "The tools below prevent the problems our hooks detect:"
echo ""
echo "  # Bash output compression (60-90% reduction, prevents watching-cost bloat)"
echo "  brew install rtk-ai/tap/rtk"
echo ""
echo "  # Smart file reads (95%+ compression, prevents subagent-isolation bloat)"
echo "  npx @anthropic-ai/claude-code mcp add token-optimizer-mcp -- npx -y token-optimizer-mcp"
echo ""
echo "  # Progressive compaction (richer version of compact-gamble)"
echo "  claude plugin install alexgreensh/token-optimizer"
echo ""
echo "Our hooks and these tools are independent — install any combination."
echo ""
