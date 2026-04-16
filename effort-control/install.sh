#!/bin/bash
# Effort Control helper — installer
#
# Copies the SessionStart hook + /deep slash command into ~/.claude/, backing
# up anything it would overwrite. Does NOT auto-modify settings.json — prints
# the snippet you need to merge yourself.
#
# The env block in your settings.json is load-bearing. A merge gone wrong
# breaks all of Claude Code, not just this helper. Manual merge keeps you
# in control.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
HOOK_DIR="${CLAUDE_DIR}/hooks/cost-helpers/effort-control"
COMMANDS_DIR="${CLAUDE_DIR}/commands"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

echo ""
echo "Installing: Effort Control helper"
echo "================================="
echo ""

# 1. Sanity check — ~/.claude/ should exist (Claude Code creates it)
if [ ! -d "$CLAUDE_DIR" ]; then
    echo "ERROR: ${CLAUDE_DIR} does not exist."
    echo "Install Claude Code first, run it once, then re-run this installer."
    exit 1
fi

# 2. Install the SessionStart hook
echo "[1/3] Installing SessionStart hook..."
mkdir -p "$HOOK_DIR"
cp "${SCRIPT_DIR}/hooks/effort-pin-banner.sh" "${HOOK_DIR}/effort-pin-banner.sh"
chmod +x "${HOOK_DIR}/effort-pin-banner.sh"
echo "      → ${HOOK_DIR}/effort-pin-banner.sh"

# 3. Install /deep slash command (with backup if it already exists)
echo "[2/3] Installing /deep slash command..."
mkdir -p "$COMMANDS_DIR"
src="${SCRIPT_DIR}/commands/deep.md"
dst="${COMMANDS_DIR}/deep.md"
if [ -f "$dst" ]; then
    backup="${dst}.bak.${TIMESTAMP}"
    cp "$dst" "$backup"
    echo "      → backed up existing /deep to ${backup##*/}"
fi
cp "$src" "$dst"
echo "      → /deep installed"

# 4. Print the settings snippet for manual merge
echo "[3/3] Settings.json snippet (merge manually)"
echo ""
echo "      Open: ${CLAUDE_DIR}/settings.json"
echo "      Merge the following blocks:"
echo "        - 'env.CLAUDE_CODE_EFFORT_LEVEL' into your existing 'env' block"
echo "        - 'effortLevel' at root (belt + suspenders)"
echo "        - 'hooks.SessionStart' inner hook into your existing array"
echo ""
echo "----------------------------------------"
cat "${SCRIPT_DIR}/settings-snippet.json"
echo "----------------------------------------"
echo ""
echo "WHY THE ENV VAR MATTERS:"
echo "  CLAUDE_CODE_EFFORT_LEVEL takes precedence over every other mechanism"
echo "  (per-session /effort, the root effortLevel field, the model default)."
echo "  The 'first run on new model family' rule (e.g. switching to Opus 4.7)"
echo "  overrides /effort and effortLevel BUT NOT the env var. This is the only"
echo "  mechanism that survives a model switch."
echo ""

# 5. Verification instructions
echo "Verify the install"
echo "------------------"
echo "  1. Open a NEW Claude Code session (env vars only load at startup)"
echo "  2. The session should open with a banner: 'EFFORT PINNED: high...'"
echo "  3. Confirm via /effort — should show 'high' as the active level"
echo "  4. Statusline should show 'with high effort' next to the model name"
echo ""
echo "  If the banner says 'EFFORT PIN MISSING', the env block edit did not"
echo "  take effect. Check that CLAUDE_CODE_EFFORT_LEVEL is inside the 'env'"
echo "  object in ~/.claude/settings.json (NOT at the root)."
echo ""
echo "Done. See README.md for how it works and how to uninstall."
echo ""
