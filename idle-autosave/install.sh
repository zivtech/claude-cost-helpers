#!/bin/bash
# Install idle-autosave hooks to ~/.claude/hooks/cost-helpers/idle-autosave/
# Never modifies settings.json — prints the snippet for manual merge.
set -e

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.claude/hooks/cost-helpers/idle-autosave"
STAMP=$(date +%Y%m%d-%H%M%S)

mkdir -p "$DEST"

for f in stop-idle-autosave.sh idle-autosave-worker.sh; do
    if [ -f "$DEST/$f" ]; then
        cp "$DEST/$f" "$DEST/$f.bak.$STAMP"
        echo "Backed up existing $f -> $f.bak.$STAMP"
    fi
    cp "$SRC_DIR/hooks/$f" "$DEST/$f"
    chmod +x "$DEST/$f"
    echo "Installed $DEST/$f"
done

echo
echo "Now merge this into ~/.claude/settings.json (append to the existing hooks.Stop array):"
echo
cat "$SRC_DIR/settings-snippet.json"
