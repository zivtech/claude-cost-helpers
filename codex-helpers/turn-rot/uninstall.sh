#!/bin/bash
# Uninstall the Codex turn-rot helper.

set -euo pipefail

CODEX_DIR="${HOME}/.codex"
HELPER_DIR="${CODEX_DIR}/hooks/cost-helpers/turn-rot"

echo ""
echo "Uninstalling: Codex turn-rot"
echo "============================"
echo ""

rm -rf "${HELPER_DIR}"

echo "Removed ${HELPER_DIR}"
echo "Do not forget to remove the UserPromptSubmit hook entry from ~/.codex/hooks.json."
echo ""
