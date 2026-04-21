#!/bin/bash
# Install the Codex turn-rot helper.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_DIR="${HOME}/.codex"
HOOKS_ROOT="${CODEX_DIR}/hooks/cost-helpers"
SHARED_DIR="${HOOKS_ROOT}/_shared"
HELPER_DIR="${HOOKS_ROOT}/turn-rot"
STATE_DIR="${CODEX_DIR}/.session-state"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

echo ""
echo "Installing: Codex turn-rot"
echo "=========================="
echo ""
echo "NOTE: turn-rot is currently experimental."
echo "      Install it only if you want to test UserPromptSubmit behavior on your Codex runtime."
echo ""

if [ ! -d "${CODEX_DIR}" ]; then
  echo "ERROR: ${CODEX_DIR} does not exist."
  echo "Run Codex once, then re-run this installer."
  exit 1
fi

mkdir -p "${SHARED_DIR}" "${HELPER_DIR}" "${STATE_DIR}"

if [ -f "${HELPER_DIR}/turn_rot.py" ]; then
  cp "${HELPER_DIR}/turn_rot.py" "${HELPER_DIR}/turn_rot.py.bak.${TIMESTAMP}"
fi

cp "${SCRIPT_DIR}/../_shared/hooklib.py" "${SHARED_DIR}/hooklib.py"
cp "${SCRIPT_DIR}/turn_rot.py" "${HELPER_DIR}/turn_rot.py"
chmod +x "${HELPER_DIR}/turn_rot.py"

echo "Installed:"
echo "  ${HELPER_DIR}/turn_rot.py"
echo "  ${SHARED_DIR}/hooklib.py"
echo ""
echo "Merge this into ~/.codex/hooks.json:"
echo ""
cat "${SCRIPT_DIR}/hooks.json"
echo ""
echo "State files will be written to ${STATE_DIR}"
echo ""
