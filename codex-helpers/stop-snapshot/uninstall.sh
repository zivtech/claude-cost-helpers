#!/bin/bash
# Uninstall the Codex stop-snapshot helper.

set -euo pipefail

CODEX_DIR="${HOME}/.codex"
HELPER_DIR="${CODEX_DIR}/hooks/cost-helpers/stop-snapshot"

echo ""
echo "Uninstalling: Codex stop-snapshot"
echo "================================="
echo ""

rm -rf "${HELPER_DIR}"

echo "Removed ${HELPER_DIR}"
echo "Do not forget to remove the Stop hook entry from ~/.codex/hooks.json."
echo ""
