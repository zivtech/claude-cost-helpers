#!/bin/bash
# Codex helpers — install all currently supported/experimental Codex helpers.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "Installing: Codex helpers"
echo "========================="
echo ""

FAILED=()
SUPPORTED=(stop-snapshot reasoning-hygiene-banner)
EXPERIMENTAL=(turn-rot bash-output-watch)
INSTALL_EXPERIMENTAL="${CODEX_HELPERS_INCLUDE_EXPERIMENTAL:-0}"

echo "Supported helpers:"
for helper in "${SUPPORTED[@]}"; do
    echo "  - ${helper}"
done
echo ""

if [ "${INSTALL_EXPERIMENTAL}" = "1" ]; then
    echo "Experimental helpers enabled via CODEX_HELPERS_INCLUDE_EXPERIMENTAL=1:"
    for helper in "${EXPERIMENTAL[@]}"; do
        echo "  - ${helper}"
    done
    echo ""
else
    echo "Experimental helpers are skipped by default."
    echo "Set CODEX_HELPERS_INCLUDE_EXPERIMENTAL=1 to install them."
    echo ""
fi

for helper in "${SUPPORTED[@]}"; do
    HELPER_DIR="${SCRIPT_DIR}/${helper}"
    if [ -d "$HELPER_DIR" ] && [ -x "${HELPER_DIR}/install.sh" ]; then
        echo "─────────────────────────────────────────────"
        echo ""
        (cd "$HELPER_DIR" && ./install.sh)
        echo ""
    else
        echo "SKIP: ${helper} (not found or install.sh not executable)"
        FAILED+=("$helper")
    fi
done

if [ "${INSTALL_EXPERIMENTAL}" = "1" ]; then
for helper in "${EXPERIMENTAL[@]}"; do
    HELPER_DIR="${SCRIPT_DIR}/${helper}"
    if [ -d "$HELPER_DIR" ] && [ -x "${HELPER_DIR}/install.sh" ]; then
        echo "─────────────────────────────────────────────"
        echo ""
        (cd "$HELPER_DIR" && ./install.sh)
        echo ""
    else
        echo "SKIP: ${helper} (not found or install.sh not executable)"
        FAILED+=("$helper")
    fi
done
fi

echo "═════════════════════════════════════════════"
echo ""

if [ ${#FAILED[@]} -gt 0 ]; then
    echo "WARNING: The following helpers were skipped:"
    for f in "${FAILED[@]}"; do
        echo "  - $f"
    done
    echo ""
fi

echo "SUPPORTED HOOKS SNIPPET"
echo "======================="
echo ""
echo "Merge the following into ~/.codex/hooks.json:"
echo ""
cat <<'COMBINED'
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.codex/hooks/cost-helpers/reasoning-hygiene-banner/reasoning_hygiene_banner.py",
            "timeout": 10,
            "statusMessage": "Checking Codex reasoning defaults..."
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.codex/hooks/cost-helpers/stop-snapshot/stop_snapshot.py",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
COMBINED
echo ""
if [ "${INSTALL_EXPERIMENTAL}" = "1" ]; then
echo "EXPERIMENTAL HOOKS SNIPPET"
echo "=========================="
echo ""
cat <<'EXPERIMENTAL'
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.codex/hooks/cost-helpers/turn-rot/turn_rot.py",
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
            "command": "$HOME/.codex/hooks/cost-helpers/bash-output-watch/bash_output_watch.py",
            "timeout": 10,
            "statusMessage": "Reviewing Bash output size..."
          }
        ]
      }
    ]
  }
}
EXPERIMENTAL
echo ""
fi
echo "Do not forget the feature flag in ~/.codex/config.toml:"
echo ""
echo "  [features]"
echo "  codex_hooks = true"
echo ""
