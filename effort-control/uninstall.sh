#!/bin/bash
# Effort Control helper — uninstaller
#
# Removes the SessionStart hook and /deep slash command. Restores any
# *.bak.* files left by install.sh. Does NOT auto-modify settings.json —
# prints what to remove.

set -euo pipefail

CLAUDE_DIR="${HOME}/.claude"
HOOK_DIR="${CLAUDE_DIR}/hooks/cost-helpers/effort-control"
COMMANDS_DIR="${CLAUDE_DIR}/commands"

echo ""
echo "Uninstalling: Effort Control helper"
echo "==================================="
echo ""

# 1. Remove the hook
if [ -d "$HOOK_DIR" ]; then
    rm -rf "$HOOK_DIR"
    echo "      → removed ${HOOK_DIR}"
fi

# Clean up empty parent dirs without nuking unrelated content
rmdir "${CLAUDE_DIR}/hooks/cost-helpers" 2>/dev/null || true

# 2. Remove /deep slash command and restore backup if it exists
dst="${COMMANDS_DIR}/deep.md"
if [ -f "$dst" ]; then
    rm "$dst"
    echo "      → removed /deep"
fi

latest_backup="$(ls -t "${COMMANDS_DIR}/deep.md.bak."* 2>/dev/null | head -1 || true)"
if [ -n "$latest_backup" ]; then
    cp "$latest_backup" "$dst"
    echo "      → restored /deep from ${latest_backup##*/}"
fi

# 3. Settings reminder
echo ""
echo "Manual cleanup needed"
echo "---------------------"
echo "Open: ${CLAUDE_DIR}/settings.json"
echo ""
echo "Remove from the 'env' block:"
echo "  \"CLAUDE_CODE_EFFORT_LEVEL\": \"high\""
echo ""
echo "Remove from the root (if present):"
echo "  \"effortLevel\": \"high\""
echo ""
echo "Remove the SessionStart hook entry that points to:"
echo "  \$HOME/.claude/hooks/cost-helpers/effort-control/effort-pin-banner.sh"
echo ""
echo "After removing the env var, your next session will revert to the model"
echo "default effort level (xhigh on Opus 4.7)."
echo ""
echo "Done."
echo ""
