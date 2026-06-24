#!/bin/bash
# Remove idle-autosave hooks and per-session state.
# Does not modify settings.json — remove the Stop hook entry manually.
set -e

DEST="$HOME/.claude/hooks/cost-helpers/idle-autosave"
STATE_DIR="$HOME/.claude/.session-state"

# Stop any live watchers.
pkill -f "idle-autosave-worker.sh" 2>/dev/null || true

rm -rf "$DEST"
rm -f "$STATE_DIR"/idle-autosave-*.pid "$STATE_DIR"/idle-autosave-*.last
echo "Removed $DEST and per-session idle-autosave state."
echo "Saved handoff notes in ~/.claude/sessions/ are kept."
echo
echo "Remember to remove the idle-autosave entries from hooks.Stop and hooks.SessionEnd in ~/.claude/settings.json."
