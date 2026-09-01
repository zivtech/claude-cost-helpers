#!/bin/bash
# Usage Report helper — installer
#
# Copies the report scripts + SessionStart hook + slash command into
# ~/.claude/, backing up anything it would overwrite. Does NOT auto-modify
# settings.json — prints the snippet you need to merge yourself.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
HOOK_DIR="${CLAUDE_DIR}/hooks/cost-helpers/usage-report"
COMMANDS_DIR="${CLAUDE_DIR}/commands"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

echo ""
echo "Installing: Usage Report helper"
echo "==============================="
echo ""

if [ ! -d "$CLAUDE_DIR" ]; then
    echo "ERROR: ${CLAUDE_DIR} does not exist."
    echo "Install Claude Code first, run it once, then re-run this installer."
    exit 1
fi

echo "[1/3] Installing scripts + hook..."
mkdir -p "$HOOK_DIR"
for f in usage_report.py usage_scan.py; do
    cp "${SCRIPT_DIR}/${f}" "${HOOK_DIR}/${f}"
    echo "      → ${HOOK_DIR}/${f}"
done
if [ -f "${HOOK_DIR}/sessionstart-usage-report.sh" ]; then
    cp "${HOOK_DIR}/sessionstart-usage-report.sh" "${HOOK_DIR}/sessionstart-usage-report.sh.bak.${TIMESTAMP}"
    echo "      → backed up existing hook"
fi
cp "${SCRIPT_DIR}/hooks/sessionstart-usage-report.sh" "${HOOK_DIR}/sessionstart-usage-report.sh"
chmod +x "${HOOK_DIR}/sessionstart-usage-report.sh" "${HOOK_DIR}/usage_report.py"
echo "      → ${HOOK_DIR}/sessionstart-usage-report.sh"

echo "[2/3] Installing slash command..."
mkdir -p "$COMMANDS_DIR"
dst="${COMMANDS_DIR}/usage-report.md"
if [ -f "$dst" ]; then
    cp "$dst" "${dst}.bak.${TIMESTAMP}"
    echo "      → backed up existing /usage-report to ${dst##*/}.bak.${TIMESTAMP}"
fi
cp "${SCRIPT_DIR}/commands/usage-report.md" "$dst"
echo "      → /usage-report installed"

echo "[3/3] Settings.json snippet (merge manually)"
echo ""
echo "      Open: ${CLAUDE_DIR}/settings.json"
echo "      Add the following \"hooks\" block (merge with any existing hooks):"
echo ""
echo "----------------------------------------"
cat "${SCRIPT_DIR}/settings-snippet.json"
echo "----------------------------------------"
echo ""
echo "The SessionStart hook is optional — it only refreshes the report weekly."
echo "Without it, run /usage-report whenever you want a fresh one."
echo ""
echo "Verify the install"
echo "------------------"
echo "  1. Start a new Claude Code session and run /usage-report"
echo "  2. The report prints inline and is saved under ~/.claude/usage-reports/"
echo ""
echo "Done. See README.md for what the numbers mean."
echo ""
