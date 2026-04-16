#!/bin/bash
# Idle Tax helper — installer
#
# Copies the hook + slash commands into ~/.claude/, backing up anything it
# would overwrite. Does NOT auto-modify settings.json — prints the snippet
# you need to merge yourself.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
HOOK_DIR="${CLAUDE_DIR}/hooks/cost-helpers/idle-tax"
COMMANDS_DIR="${CLAUDE_DIR}/commands"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

echo ""
echo "Installing: Idle Tax helper"
echo "============================"
echo ""

# 1. Sanity check — ~/.claude/ should exist (Claude Code creates it)
if [ ! -d "$CLAUDE_DIR" ]; then
    echo "ERROR: ${CLAUDE_DIR} does not exist."
    echo "Install Claude Code first, run it once, then re-run this installer."
    exit 1
fi

# 2. Install the hook
echo "[1/3] Installing hook script..."
mkdir -p "$HOOK_DIR"
cp "${SCRIPT_DIR}/cache-idle-timer.sh" "${HOOK_DIR}/cache-idle-timer.sh"
chmod +x "${HOOK_DIR}/cache-idle-timer.sh"
echo "      → ${HOOK_DIR}/cache-idle-timer.sh"

# 3. Install slash commands (with backup if they already exist)
echo "[2/3] Installing slash commands..."
mkdir -p "$COMMANDS_DIR"
for cmd in save-session resume-session; do
    src="${SCRIPT_DIR}/commands/${cmd}.md"
    dst="${COMMANDS_DIR}/${cmd}.md"
    if [ -f "$dst" ]; then
        backup="${dst}.bak.${TIMESTAMP}"
        cp "$dst" "$backup"
        echo "      → backed up existing /${cmd} to ${backup##*/}"
    fi
    cp "$src" "$dst"
    echo "      → /${cmd} installed"
done

# 4. Print the settings snippet for manual merge
echo "[3/3] Settings.json snippet (merge manually)"
echo ""
echo "      Open: ${CLAUDE_DIR}/settings.json"
echo "      Add the following \"hooks\" block (merge with any existing hooks):"
echo ""
echo "----------------------------------------"
cat "${SCRIPT_DIR}/settings-snippet.json"
echo "----------------------------------------"
echo ""
echo "If your settings.json already has a UserPromptSubmit array, append the"
echo "inner hook object to that array instead of overwriting."
echo ""

# 5. Verification instructions
echo "Verify the install"
echo "------------------"
echo "  1. Open a NEW Claude Code session"
echo "  2. Send any message (this records the activity timestamp)"
echo "  3. Wait 5+ minutes"
echo "  4. Send another message"
echo "  5. You should see CACHE EXPIRED in Claude's response context"
echo ""
echo "Done. See README.md for how it works and how to uninstall."
echo ""
