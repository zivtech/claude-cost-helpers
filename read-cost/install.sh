#!/bin/bash
# Read Cost helper — installer
#
# Copies the PreToolUse hook into ~/.claude/. Does NOT auto-modify
# settings.json — prints the snippet for you to merge yourself.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
HOOK_DIR="${CLAUDE_DIR}/hooks/cost-helpers/read-cost"

echo ""
echo "Installing: Read Cost helper"
echo "============================"
echo ""

if [ ! -d "$CLAUDE_DIR" ]; then
    echo "ERROR: ${CLAUDE_DIR} does not exist."
    echo "Install Claude Code first, run it once, then re-run this installer."
    exit 1
fi

echo "[1/2] Installing PreToolUse hook..."
mkdir -p "$HOOK_DIR"
cp "${SCRIPT_DIR}/hooks/read-cost-monitor.sh" "${HOOK_DIR}/read-cost-monitor.sh"
chmod +x "${HOOK_DIR}/read-cost-monitor.sh"
echo "      -> ${HOOK_DIR}/read-cost-monitor.sh"

echo "[2/2] Settings.json snippet (merge manually)"
echo ""
echo "      Open: ${CLAUDE_DIR}/settings.json"
echo "      Merge the 'hooks.PreToolUse' entry into your existing array."
echo ""
echo "----------------------------------------"
cat "${SCRIPT_DIR}/settings-snippet.json"
echo "----------------------------------------"
echo ""
echo "Verify the install"
echo "------------------"
echo "  ./test.sh                 # 30 fixture cases, exit 0 = all pass"
echo "  Then read a large file in a session. If it would cost more than"
echo "  \$0.15 to carry, you get a one-line warning before the read lands."
echo ""
echo "  Silence is normal: on the author's transcripts this fires on ~9% of"
echo "  reads on Opus and ~12% on Fable. If it never fires, your reads are"
echo "  small or your model is cheap — both are the answer working."
echo ""
echo "Done. See README.md for how it works and how to uninstall."
echo ""
