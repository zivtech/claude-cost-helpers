#!/bin/bash
# Just One More Turn helper — uninstaller
#
# Removes the hook and slash command. Restores any *.bak.* files left by
# install.sh. Does NOT auto-modify settings.json — prints what to remove.

set -euo pipefail

CLAUDE_DIR="${HOME}/.claude"
HOOK_DIR="${CLAUDE_DIR}/hooks/cost-helpers/just-one-more-turn"
COMMANDS_DIR="${CLAUDE_DIR}/commands"

echo ""
echo "Uninstalling: Just One More Turn helper"
echo "========================================"
echo ""

# 1. Remove the hook
if [ -d "$HOOK_DIR" ]; then
    rm -rf "$HOOK_DIR"
    echo "      → removed ${HOOK_DIR}"
fi

# Clean up empty parent dirs without nuking unrelated content
rmdir "${CLAUDE_DIR}/hooks/cost-helpers" 2>/dev/null || true

# 2. Remove slash commands and restore backups if they exist
for cmd in split; do
    dst="${COMMANDS_DIR}/${cmd}.md"
    if [ -f "$dst" ]; then
        rm "$dst"
        echo "      → removed /${cmd}"
    fi

    # Look for the most recent backup and restore it
    latest_backup="$(ls -t "${COMMANDS_DIR}/${cmd}.md.bak."* 2>/dev/null | head -1 || true)"
    if [ -n "$latest_backup" ]; then
        cp "$latest_backup" "$dst"
        echo "      → restored /${cmd} from ${latest_backup##*/}"
    fi
done

# 3. Settings reminder
echo ""
echo "Manual cleanup needed"
echo "---------------------"
echo "Open: ${CLAUDE_DIR}/settings.json"
echo "Remove the UserPromptSubmit hook entry that points to:"
echo "  \$HOME/.claude/hooks/cost-helpers/just-one-more-turn/context-usage-monitor.sh"
echo ""
echo "Done."
echo ""
