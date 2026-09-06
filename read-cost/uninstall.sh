#!/bin/bash
# Read Cost helper — uninstaller

set -euo pipefail

CLAUDE_DIR="${HOME}/.claude"
HOOK_DIR="${CLAUDE_DIR}/hooks/cost-helpers/read-cost"

echo ""
echo "Uninstalling: Read Cost helper"
echo "=============================="
echo ""

if [ -d "$HOOK_DIR" ]; then
    rm -rf "$HOOK_DIR"
    echo "[1/2] Removed ${HOOK_DIR}"
else
    echo "[1/2] Nothing to remove at ${HOOK_DIR}"
fi

echo "[2/2] Remove the hook block from settings.json yourself:"
echo ""
echo "      Open: ${CLAUDE_DIR}/settings.json"
echo "      Delete the hooks.PreToolUse entry whose matcher is \"^Read\$\""
echo "      and whose command points at cost-helpers/read-cost/."
echo ""
echo "Per-session state (safe to delete any time):"
echo "      rm -f ${CLAUDE_DIR}/.session-state/*.read-cost-warned"
echo ""
echo "Done."
echo ""
