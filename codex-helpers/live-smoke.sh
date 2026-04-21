#!/bin/bash
# Live smoke test for Codex helper runtime behavior.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORKTREE_HOOKS_DIR="${REPO_ROOT}/.codex"
HOOKS_FILE="${WORKTREE_HOOKS_DIR}/hooks.json"
HOOKS_BACKUP=""
SMOKE_DIR="${CODEX_HELPER_SMOKE_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/codex-helper-smoke.XXXXXX")}"
LOG_DIR="${SMOKE_DIR}/hook-logs"
mkdir -p "${WORKTREE_HOOKS_DIR}" "${LOG_DIR}"

cleanup() {
  if [ -n "${HOOKS_BACKUP}" ] && [ -f "${HOOKS_BACKUP}" ]; then
    mv "${HOOKS_BACKUP}" "${HOOKS_FILE}"
  else
    rm -f "${HOOKS_FILE}"
  fi
}
trap cleanup EXIT

if [ -f "${HOOKS_FILE}" ]; then
  HOOKS_BACKUP="${HOOKS_FILE}.bak.$(date +%Y%m%d-%H%M%S)"
  cp "${HOOKS_FILE}" "${HOOKS_BACKUP}"
fi

cat > "${HOOKS_FILE}" <<JSON
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume",
        "hooks": [
          {
            "type": "command",
            "command": "env CODEX_HELPER_LOG_DIR=${LOG_DIR} python3 \"${REPO_ROOT}/codex-helpers/reasoning-hygiene-banner/reasoning_hygiene_banner.py\"",
            "timeout": 10,
            "statusMessage": "Checking Codex reasoning defaults..."
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "env CODEX_HELPER_LOG_DIR=${LOG_DIR} CODEX_TURN_ROT_WARN_TURNS=1 CODEX_TURN_ROT_HARD_TURNS=2 python3 \"${REPO_ROOT}/codex-helpers/turn-rot/turn_rot.py\"",
            "timeout": 10,
            "statusMessage": "Checking session growth..."
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "env CODEX_HELPER_LOG_DIR=${LOG_DIR} CODEX_BASH_OUTPUT_WARN_TOKENS=4 CODEX_BASH_OUTPUT_CUMULATIVE_TOKENS=8,12 python3 \"${REPO_ROOT}/codex-helpers/bash-output-watch/bash_output_watch.py\"",
            "timeout": 10,
            "statusMessage": "Reviewing Bash output size..."
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "env CODEX_HELPER_LOG_DIR=${LOG_DIR} python3 \"${REPO_ROOT}/codex-helpers/stop-snapshot/stop_snapshot.py\"",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
JSON

BASE_ARGS=(
  --enable codex_hooks
  -c suppress_unstable_features_warning=true
  -c 'mcp_servers.notion.enabled=false'
  -c 'mcp_servers.playwright.enabled=false'
  -c 'mcp_servers.stitch.enabled=false'
  -c 'mcp_servers.pencil.enabled=false'
  -c model='"gpt-5.4-mini"'
  -c model_reasoning_effort='"low"'
  --json
  -C "${REPO_ROOT}"
)

SESSION_OUT="${SMOKE_DIR}/supported.jsonl"
TURN_OUT="${SMOKE_DIR}/turnrot.jsonl"
BASH_OUT="${SMOKE_DIR}/bashwatch.jsonl"

codex exec "${BASE_ARGS[@]}" 'Reply with EXACTLY SMOKE_SUPPORTED_OK.' > "${SESSION_OUT}"
codex exec "${BASE_ARGS[@]}" 'Reply with EXACTLY SMOKE_TURNROT_OK.' > "${TURN_OUT}"
codex exec "${BASE_ARGS[@]}" "Use bash once. Run this exact command and then reply EXACTLY SMOKE_BASHWATCH_OK:
python3 - <<'PY'
print('X'*32)
PY" > "${BASH_OUT}"

echo "Smoke log dir: ${LOG_DIR}"
echo ""
echo "=== Hook invocations ==="
if [ -f "${LOG_DIR}/invocations.jsonl" ]; then
  cat "${LOG_DIR}/invocations.jsonl"
else
  echo "No invocation log found."
fi
echo ""
echo "=== Supported helper exec output ==="
cat "${SESSION_OUT}"
echo ""
echo "=== Turn-rot exec output ==="
cat "${TURN_OUT}"
echo ""
echo "=== Bash-output-watch exec output ==="
cat "${BASH_OUT}"
