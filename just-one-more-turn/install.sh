#!/bin/bash
# Just One More Turn helper — installer
#
# Copies the hook + slash command into ~/.claude/, backing up anything it
# would overwrite. Does NOT auto-modify settings.json — prints the snippet
# you need to merge yourself.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
HOOK_DIR="${CLAUDE_DIR}/hooks/cost-helpers/just-one-more-turn"
COMMANDS_DIR="${CLAUDE_DIR}/commands"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

echo ""
echo "Installing: Just One More Turn helper"
echo "======================================="
echo ""

# 1. Sanity check — ~/.claude/ should exist (Claude Code creates it)
if [ ! -d "$CLAUDE_DIR" ]; then
    echo "ERROR: ${CLAUDE_DIR} does not exist."
    echo "Install Claude Code first, run it once, then re-run this installer."
    exit 1
fi

# 2. Install the hook
echo "[1/3] Installing hook scripts..."
mkdir -p "$HOOK_DIR"
cp "${SCRIPT_DIR}/context-usage-monitor.sh" "${HOOK_DIR}/context-usage-monitor.sh"
chmod +x "${HOOK_DIR}/context-usage-monitor.sh"
echo "      → ${HOOK_DIR}/context-usage-monitor.sh"
cp "${SCRIPT_DIR}/starting-context-report.sh" "${HOOK_DIR}/starting-context-report.sh"
chmod +x "${HOOK_DIR}/starting-context-report.sh"
echo "      → ${HOOK_DIR}/starting-context-report.sh"

# 3. Install slash commands (with backup if they already exist)
echo "[2/3] Installing slash commands..."
mkdir -p "$COMMANDS_DIR"
for cmd in split; do
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
echo "  2. Send messages until you exceed the warning threshold"
echo "     (default: 70% of 300k tokens = ~70 turns at 3k tokens/turn)"
echo "  3. You should see the context heads-up in Claude's response context"
echo ""
echo "To test immediately with a lower threshold:"
echo "  CLAUDE_CONTEXT_THRESHOLD=9000 ${HOOK_DIR}/context-usage-monitor.sh <<< '{\"sessionId\":\"test\"}'"
echo ""
echo "Done. See README.md for how it works and how to uninstall."
echo ""
