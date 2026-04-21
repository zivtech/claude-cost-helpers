#!/bin/bash
# Uninstall the Codex bash-output-watch helper.

set -euo pipefail

CODEX_DIR="${HOME}/.codex"
HELPER_DIR="${CODEX_DIR}/hooks/cost-helpers/bash-output-watch"

echo ""
echo "Uninstalling: Codex bash-output-watch"
echo "====================================="
echo ""

rm -rf "${HELPER_DIR}"

echo "Removed ${HELPER_DIR}"
echo "Do not forget to remove the PostToolUse Bash hook entry from ~/.codex/hooks.json."
echo ""
