#!/bin/bash
# Delegation Cost helper — installer
#
# Copies the hook + slash command into ~/.claude/, backing up anything it
# would overwrite. Does NOT auto-modify settings.json — prints the snippet
# you need to merge yourself.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
HOOK_DIR="${CLAUDE_DIR}/hooks/cost-helpers/delegation-cost"
COMMANDS_DIR="${CLAUDE_DIR}/commands"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

echo ""
echo "Installing: Delegation Cost helper"
echo "===================================="
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
cp "${SCRIPT_DIR}/delegation-result-monitor.sh" "${HOOK_DIR}/delegation-result-monitor.sh"
chmod +x "${HOOK_DIR}/delegation-result-monitor.sh"
echo "      -> ${HOOK_DIR}/delegation-result-monitor.sh"
cp "${SCRIPT_DIR}/agent-prompt-lint.sh" "${HOOK_DIR}/agent-prompt-lint.sh"
chmod +x "${HOOK_DIR}/agent-prompt-lint.sh"
echo "      -> ${HOOK_DIR}/agent-prompt-lint.sh"

# 3. Install slash command (with backup if it already exists)
echo "[2/3] Installing slash commands..."
mkdir -p "$COMMANDS_DIR"
for cmd in delegation-report; do
    src="${SCRIPT_DIR}/commands/${cmd}.md"
    dst="${COMMANDS_DIR}/${cmd}.md"
    if [ -f "$dst" ]; then
        backup="${dst}.bak.${TIMESTAMP}"
        cp "$dst" "$backup"
        echo "      -> backed up existing /${cmd} to ${backup##*/}"
    fi
    cp "$src" "$dst"
    echo "      -> /${cmd} installed"
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
echo "If your settings.json already has PreToolUse or PostToolUse arrays,"
echo "append the inner hook objects to those arrays instead of overwriting."
echo ""
echo "Note: if you also use the watching-cost helper, both will fire on"
echo "Agent results (watching-cost matches all tools). This is expected —"
echo "watching-cost tracks total tool output, delegation-cost tracks agent"
echo "results specifically. They use separate state files and thresholds."
echo ""

# 5. Verification instructions
echo "Verify the install"
echo "------------------"
echo "  1. Open a Claude Code session"
echo "  2. Ask Claude to spawn a research agent (e.g., 'explore the codebase')"
echo "  3. When the agent returns, you'll see a delegation-cost note"
echo "  4. Run /delegation-report to see accumulated result sizes"
echo ""
echo "Tip: set CLAUDE_DELEGATION_THRESHOLD=100 in your shell to trigger"
echo "the per-result warning on small agent results while testing."
echo ""
echo "Done. See README.md for how it works and how to uninstall."
echo ""
