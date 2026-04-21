#!/bin/bash
# Install the Codex reasoning-hygiene-banner helper.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_DIR="${HOME}/.codex"
HOOKS_ROOT="${CODEX_DIR}/hooks/cost-helpers"
SHARED_DIR="${HOOKS_ROOT}/_shared"
HELPER_DIR="${HOOKS_ROOT}/reasoning-hygiene-banner"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

echo ""
echo "Installing: Codex reasoning-hygiene-banner"
echo "=========================================="
echo ""

if [ ! -d "${CODEX_DIR}" ]; then
  echo "ERROR: ${CODEX_DIR} does not exist."
  echo "Run Codex once, then re-run this installer."
  exit 1
fi

mkdir -p "${SHARED_DIR}" "${HELPER_DIR}"

if [ -f "${HELPER_DIR}/reasoning_hygiene_banner.py" ]; then
  cp "${HELPER_DIR}/reasoning_hygiene_banner.py" "${HELPER_DIR}/reasoning_hygiene_banner.py.bak.${TIMESTAMP}"
fi

cp "${SCRIPT_DIR}/../_shared/hooklib.py" "${SHARED_DIR}/hooklib.py"
cp "${SCRIPT_DIR}/reasoning_hygiene_banner.py" "${HELPER_DIR}/reasoning_hygiene_banner.py"
chmod +x "${HELPER_DIR}/reasoning_hygiene_banner.py"

echo "Installed:"
echo "  ${HELPER_DIR}/reasoning_hygiene_banner.py"
echo "  ${SHARED_DIR}/hooklib.py"
echo ""
echo "Merge this into ~/.codex/hooks.json:"
echo ""
cat "${SCRIPT_DIR}/hooks.json"
echo ""
