#!/bin/bash
# Usage Report — weekly refresh on SessionStart.
#
# If the newest report in ~/.claude/usage-reports/ is older than
# USAGE_REPORT_INTERVAL_DAYS (default 7), regenerate it in a detached
# background process (the scan takes a few seconds over multi-GB transcript
# trees; a SessionStart hook must return immediately). Zero Claude tokens —
# the report is computed from local transcript files only.
#
# Config (env, e.g. settings.json "env" block):
#   USAGE_REPORT_INTERVAL_DAYS  refresh cadence (default 7)
#   USAGE_REPORT_WINDOW_DAYS    window the report covers (default 28)
#   USAGE_REPORT_DIR            output dir (default ~/.claude/usage-reports)
#   USAGE_REPORT_DISABLE=1      skip entirely
#   USAGE_REPORT_NOTIFY=1       macOS notification when the refresh lands
#
# Part of: claude-cost-helpers / usage-report

set +e
INPUT=$(cat 2>/dev/null)  # unused; SessionStart payload

silent() { echo '{"continue": true, "suppressOutput": true}'; exit 0; }

[ "${USAGE_REPORT_DISABLE:-0}" = "1" ] && silent
# Headless / child sessions must not trigger refreshes.
case "$CLAUDE_CODE_ENTRYPOINT" in *sdk*|*print*|*cron*|*action*|*mcp*) silent ;; esac
[ -n "$CLAUDE_IDLE_AUTOSAVE_CHILD" ] && silent

HERE="$(cd "$(dirname "$0")" && pwd)"
# Installed layout is flat (script beside the hook); repo layout keeps the
# hook under hooks/ one level below the scripts.
SCRIPT="$HERE/usage_report.py"
[ -f "$SCRIPT" ] || SCRIPT="$HERE/../usage_report.py"
[ -f "$SCRIPT" ] || silent

REPORT_DIR="${USAGE_REPORT_DIR:-$HOME/.claude/usage-reports}"
INTERVAL="${USAGE_REPORT_INTERVAL_DAYS:-7}"
WINDOW="${USAGE_REPORT_WINDOW_DAYS:-28}"
mkdir -p "$REPORT_DIR" 2>/dev/null

NEWEST=$(ls -t "$REPORT_DIR"/*.md 2>/dev/null | head -1)
if [ -n "$NEWEST" ]; then
    NOW=$(date +%s)
    MTIME=$(stat -f %m "$NEWEST" 2>/dev/null || stat -c %Y "$NEWEST" 2>/dev/null)
    AGE_DAYS=$(( (NOW - ${MTIME:-0}) / 86400 ))
    [ "$AGE_DAYS" -lt "$INTERVAL" ] && silent
fi

# Refresh detached; a lock dir prevents parallel session starts from racing.
# A lock older than 10 minutes is stale (a killed refresh) and is reclaimed.
LOCK="$REPORT_DIR/.refresh.lock"
if [ -d "$LOCK" ]; then
    LOCK_AGE=$(( $(date +%s) - $(stat -f %m "$LOCK" 2>/dev/null || stat -c %Y "$LOCK" 2>/dev/null || echo 0) ))
    [ "$LOCK_AGE" -gt 600 ] && rmdir "$LOCK" 2>/dev/null
fi
if ! mkdir "$LOCK" 2>/dev/null; then
    silent  # another session already kicked off the refresh
fi

nohup bash -c '
    REPORT_DIR="$1"; SCRIPT="$2"; WINDOW="$3"
    OUT=$(python3 "$SCRIPT" --since "$WINDOW" --quiet 2>>"$REPORT_DIR/.refresh.log")
    rmdir "$REPORT_DIR/.refresh.lock" 2>/dev/null
    if [ -n "$OUT" ] && [ "${USAGE_REPORT_NOTIFY:-1}" = "1" ] && command -v osascript >/dev/null 2>&1; then
        osascript -e "on run argv" \
                  -e "display notification (item 1 of argv) with title \"Claude usage report\"" \
                  -e "end run" \
                  "Weekly usage report refreshed — /usage-report to view" >/dev/null 2>&1
    fi
' _ "$REPORT_DIR" "$SCRIPT" "$WINDOW" </dev/null >/dev/null 2>&1 &

MSG="usage-report: the weekly usage report is being refreshed in the background (${REPORT_DIR}). View it with /usage-report."
MSG="$MSG" python3 - <<'PYEOF'
import json, os
print(json.dumps({"continue": True, "suppressOutput": True,
                  "systemMessage": os.environ["MSG"]}))
PYEOF
exit 0
