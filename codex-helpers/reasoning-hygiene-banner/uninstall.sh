#!/bin/bash
# Uninstall the Codex reasoning-hygiene-banner helper.

set -euo pipefail

CODEX_DIR="${HOME}/.codex"
HELPER_DIR="${CODEX_DIR}/hooks/cost-helpers/reasoning-hygiene-banner"

echo ""
echo "Uninstalling: Codex reasoning-hygiene-banner"
echo "============================================"
echo ""

rm -rf "${HELPER_DIR}"

echo "Removed ${HELPER_DIR}"
echo "Do not forget to remove the SessionStart hook entry from ~/.codex/hooks.json."
echo ""
