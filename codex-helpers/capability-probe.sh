#!/bin/bash
# Probe current runtime support for Codex helper hooks.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SMOKE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-capability-probe.XXXXXX")"
LOG_DIR="${SMOKE_DIR}/hook-logs"

echo "Running supported smoke probe..."
CODEX_HELPER_SMOKE_DIR="${SMOKE_DIR}" ./codex-helpers/live-smoke.sh > "${SMOKE_DIR}/live-smoke.out"

if [ -f "${LOG_DIR}/invocations.jsonl" ]; then
  echo ""
  echo "Capability summary from live smoke:"
  python3 "${SCRIPT_DIR}/summarize-capabilities.py" "${LOG_DIR}/invocations.jsonl"
else
  echo ""
  echo "No invocation log found in ${LOG_DIR}."
fi

echo ""
echo "Full smoke output:"
cat "${SMOKE_DIR}/live-smoke.out"
