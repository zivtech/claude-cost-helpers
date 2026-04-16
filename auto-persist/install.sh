#!/bin/bash
# Auto-Persist helper — installer
#
# Copies the Stop hook + /last-state slash command into ~/.claude/, backing
# up anything it would overwrite. Does NOT auto-modify settings.json — prints
# the snippet you need to merge yourself.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
HOOK_DIR="${CLAUDE_DIR}/hooks/cost-helpers/auto-persist"
COMMANDS_DIR="${CLAUDE_DIR}/commands"
STATE_DIR="${CLAUDE_DIR}/sessions/auto-state"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

echo ""
echo "Installing: Auto-Persist helper"
echo "==============================="
echo ""

# 1. Sanity check
if [ ! -d "$CLAUDE_DIR" ]; then
    echo "ERROR: ${CLAUDE_DIR} does not exist."
    echo "Install Claude Code first, run it once, then re-run this installer."
    exit 1
fi

# 2. Install the Stop hook
echo "[1/4] Installing Stop hook..."
mkdir -p "$HOOK_DIR"
cp "${SCRIPT_DIR}/hooks/stop-auto-persist.sh" "${HOOK_DIR}/stop-auto-persist.sh"
chmod +x "${HOOK_DIR}/stop-auto-persist.sh"
echo "      → ${HOOK_DIR}/stop-auto-persist.sh"

# 3. Create the state directory so the first turn doesn't need to mkdir
echo "[2/4] Creating auto-state directory..."
mkdir -p "$STATE_DIR"
echo "      → ${STATE_DIR}"

# 4. Install /last-state slash command (with backup if it already exists)
echo "[3/4] Installing /last-state slash command..."
mkdir -p "$COMMANDS_DIR"
src="${SCRIPT_DIR}/commands/last-state.md"
dst="${COMMANDS_DIR}/last-state.md"
if [ -f "$dst" ]; then
    backup="${dst}.bak.${TIMESTAMP}"
    cp "$dst" "$backup"
    echo "      → backed up existing /last-state to ${backup##*/}"
fi
cp "$src" "$dst"
echo "      → /last-state installed"

# 5. Print the settings snippet for manual merge
echo "[4/4] Settings.json snippet (merge manually)"
echo ""
echo "      Open: ${CLAUDE_DIR}/settings.json"
echo "      Merge the Stop hook entry into your existing 'hooks.Stop' array"
echo "      (or create the 'Stop' key if it does not exist yet)."
echo ""
echo "----------------------------------------"
cat "${SCRIPT_DIR}/settings-snippet.json"
echo "----------------------------------------"
echo ""
echo "WHAT THE HOOK DOES:"
echo "  After every Claude turn, writes git state + cwd + recent files to"
echo "  ${STATE_DIR}/<sessionId>.{json,md}"
echo "  Zero Claude tokens. Fully automatic. Silent on success."
echo ""
echo "WHY STOP (NOT SubagentStop):"
echo "  SubagentStop fires for every Agent invocation — too noisy. Stop fires"
echo "  once per main-session turn, which is exactly what we want."
echo ""

# 6. Verification instructions
echo "Verify the install"
echo "------------------"
echo "  1. Open a NEW Claude Code session (hooks load at startup)"
echo "  2. Send any message, wait for Claude to finish responding"
echo "  3. Check: ls -lt ${STATE_DIR} — should show <sessionId>.json and .md"
echo "  4. cat the .md file — should show git state + recent files"
echo "  5. Run /last-state in-session — Claude should print the same file"
echo ""
echo "  If no files appear:"
echo "    - Check ${STATE_DIR}/.debug.log for errors"
echo "    - Confirm settings.json merge took effect (restart Claude Code)"
echo "    - Confirm the hook is executable: ls -l ${HOOK_DIR}/*.sh"
echo ""
echo "Done. See README.md for how it works and how to uninstall."
echo ""
