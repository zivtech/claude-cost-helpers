#!/bin/bash
# Auto-Persist helper — uninstaller
#
# Removes the Stop hook and /last-state slash command. Restores any
# *.bak.* files left by install.sh. Does NOT auto-modify settings.json —
# prints what to remove. Does NOT delete the auto-state directory by default
# (those files might still be useful as a log).

set -euo pipefail

CLAUDE_DIR="${HOME}/.claude"
HOOK_DIR="${CLAUDE_DIR}/hooks/cost-helpers/auto-persist"
COMMANDS_DIR="${CLAUDE_DIR}/commands"
STATE_DIR="${CLAUDE_DIR}/sessions/auto-state"

echo ""
echo "Uninstalling: Auto-Persist helper"
echo "================================="
echo ""

# 1. Remove the hook
if [ -d "$HOOK_DIR" ]; then
    rm -rf "$HOOK_DIR"
    echo "      → removed ${HOOK_DIR}"
fi
rmdir "${CLAUDE_DIR}/hooks/cost-helpers" 2>/dev/null || true

# 2. Remove /last-state slash command and restore backup if it exists
dst="${COMMANDS_DIR}/last-state.md"
if [ -f "$dst" ]; then
    rm "$dst"
    echo "      → removed /last-state"
fi

latest_backup="$(ls -t "${COMMANDS_DIR}/last-state.md.bak."* 2>/dev/null | head -1 || true)"
if [ -n "$latest_backup" ]; then
    cp "$latest_backup" "$dst"
    echo "      → restored /last-state from ${latest_backup##*/}"
fi

# 3. State dir — preserve by default, offer to clear
if [ -d "$STATE_DIR" ]; then
    file_count=$(find "$STATE_DIR" -maxdepth 1 -type f | wc -l | tr -d ' ')
    echo ""
    echo "      ${STATE_DIR}"
    echo "      contains ${file_count} auto-state files. NOT deleted."
    echo "      To remove them: rm -rf ${STATE_DIR}"
fi

# 4. Settings reminder
echo ""
echo "Manual cleanup needed"
echo "---------------------"
echo "Open: ${CLAUDE_DIR}/settings.json"
echo ""
echo "Remove the Stop hook entry that points to:"
echo "  \$HOME/.claude/hooks/cost-helpers/auto-persist/stop-auto-persist.sh"
echo ""
echo "Done."
echo ""
