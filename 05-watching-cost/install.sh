#!/bin/bash
# Watching Cost helper — installer
#
# Copies the hook + slash command into ~/.claude/, backing up anything it
# would overwrite. Does NOT auto-modify settings.json — prints the snippet
# you need to merge yourself.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
HOOK_DIR="${CLAUDE_DIR}/hooks/cost-helpers/watching-cost"
COMMANDS_DIR="${CLAUDE_DIR}/commands"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

echo ""
echo "Installing: Watching Cost helper"
echo "=================================="
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
cp "${SCRIPT_DIR}/output-size-monitor.sh" "${HOOK_DIR}/output-size-monitor.sh"
chmod +x "${HOOK_DIR}/output-size-monitor.sh"
echo "      → ${HOOK_DIR}/output-size-monitor.sh"

# 3. Install slash command (with backup if it already exists)
echo "[2/3] Installing slash commands..."
mkdir -p "$COMMANDS_DIR"
for cmd in to-file; do
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
echo "If your settings.json already has a PostToolUse array, append the"
echo "inner hook object to that array instead of overwriting."
echo ""

# 5. Verification instructions
echo "Verify the install"
echo "------------------"
echo "  1. Open a Claude Code session"
echo "  2. Ask Claude to read a large file (e.g., 'show me /etc/hosts')"
echo "  3. If the output is large enough, you'll see the output-size warning"
echo "  4. To test cumulative: run several large reads in the same session"
echo ""
echo "Tip: set CLAUDE_OUTPUT_THRESHOLD=100 in your shell to trigger the"
echo "per-call warning on small outputs while testing."
echo ""
echo "Done. See README.md for how it works and how to uninstall."
echo ""
