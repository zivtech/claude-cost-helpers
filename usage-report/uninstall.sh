#!/bin/bash
# Usage Report helper — uninstaller
#
# Removes the scripts, hook, and slash command. Restores any backed-up
# slash command. Leaves generated reports in ~/.claude/usage-reports/.

set -euo pipefail

CLAUDE_DIR="${HOME}/.claude"
HOOK_DIR="${CLAUDE_DIR}/hooks/cost-helpers/usage-report"
COMMANDS_DIR="${CLAUDE_DIR}/commands"

echo ""
echo "Uninstalling: Usage Report helper"
echo "================================="
echo ""

if [ -d "$HOOK_DIR" ]; then
    rm -rf "$HOOK_DIR"
    echo "  → removed ${HOOK_DIR}"
fi

dst="${COMMANDS_DIR}/usage-report.md"
if [ -f "$dst" ]; then
    rm "$dst"
    echo "  → removed /usage-report"
    latest_backup=$(ls -t "${dst}.bak."* 2>/dev/null | head -1 || true)
    if [ -n "$latest_backup" ]; then
        mv "$latest_backup" "$dst"
        echo "  → restored previous /usage-report from ${latest_backup##*/}"
    fi
fi

echo ""
echo "Now remove the SessionStart hook entry pointing at"
echo "  sessionstart-usage-report.sh"
echo "from ~/.claude/settings.json. Reports in ~/.claude/usage-reports/ were kept."
echo ""
