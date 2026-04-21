#!/bin/bash
# Install the Codex bash-output-watch helper.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_DIR="${HOME}/.codex"
HOOKS_ROOT="${CODEX_DIR}/hooks/cost-helpers"
SHARED_DIR="${HOOKS_ROOT}/_shared"
HELPER_DIR="${HOOKS_ROOT}/bash-output-watch"
STATE_DIR="${CODEX_DIR}/.session-state"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

echo ""
echo "Installing: Codex bash-output-watch"
echo "==================================="
echo ""
echo "NOTE: bash-output-watch is currently experimental."
echo "      Install it only if you want to test PostToolUse Bash behavior on your Codex runtime."
echo ""

if [ ! -d "${CODEX_DIR}" ]; then
  echo "ERROR: ${CODEX_DIR} does not exist."
  echo "Run Codex once, then re-run this installer."
  exit 1
fi

mkdir -p "${SHARED_DIR}" "${HELPER_DIR}" "${STATE_DIR}"

if [ -f "${HELPER_DIR}/bash_output_watch.py" ]; then
  cp "${HELPER_DIR}/bash_output_watch.py" "${HELPER_DIR}/bash_output_watch.py.bak.${TIMESTAMP}"
fi

cp "${SCRIPT_DIR}/../_shared/hooklib.py" "${SHARED_DIR}/hooklib.py"
cp "${SCRIPT_DIR}/bash_output_watch.py" "${HELPER_DIR}/bash_output_watch.py"
chmod +x "${HELPER_DIR}/bash_output_watch.py"

echo "Installed:"
echo "  ${HELPER_DIR}/bash_output_watch.py"
echo "  ${SHARED_DIR}/hooklib.py"
echo ""
echo "Merge this into ~/.codex/hooks.json:"
echo ""
cat "${SCRIPT_DIR}/hooks.json"
echo ""
echo "State files will be written to ${STATE_DIR}"
echo ""
