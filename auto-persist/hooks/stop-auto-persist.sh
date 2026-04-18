#!/bin/bash
# Stop Auto-Persist — continuous minimal session state, zero Claude tokens
#
# Fires on every Stop event (end of each Claude turn). Writes machine-readable
# JSON + human-readable Markdown snapshots of the current environment to
# ~/.claude/sessions/auto-state/<sessionId>.{json,md}
#
# The hook only inspects what a shell can see: cwd, git state, recent file
# mtimes, the hook's own JSON input. It never calls Claude, never reads the
# transcript, and never holds state in the session context.
#
# Why: /save-session costs real tokens because Claude has to read context and
# synthesize a handoff. Most of the time you just need "what was my git state
# and what files was I editing?" — a shell can answer that for free after
# every turn. When you come back, /last-state (or Claude reading the file
# directly) restores the environmental context without burning cache.
#
# Design constraints:
#   - Silent on success (Stop hooks fire after every turn; noise is intolerable)
#   - Fast (<1s) — core state writes first, recent files as best-effort second pass
#   - Fails open — any error logs to a debug file and exits 0
#   - Writes atomically (tmp file + mv) so partial reads never happen
#   - Injection-safe — values from the environment / git / filesystem are
#     passed to python via env vars, NEVER interpolated into python source
#
# Part of: claude-cost-helpers / auto-persist
# Companion to: The Economics of Claude Code, Part 1 (the save-session pattern)

set +e  # never block a Stop event

INPUT=$(cat 2>/dev/null || echo '{}')

STATE_DIR="${HOME}/.claude/sessions/auto-state"
DEBUG_LOG="${STATE_DIR}/.debug.log"
mkdir -p "$STATE_DIR" 2>/dev/null

# Parse the Stop hook's JSON input via a single python pass. We pass INPUT as
# an env var so nothing is interpolated into python source.
parsed=$(INPUT="$INPUT" python3 - <<'PYEOF' 2>>"$DEBUG_LOG"
import json, os, sys
raw = os.environ.get("INPUT", "{}")
try:
    d = json.loads(raw) if raw.strip() else {}
except Exception:
    d = {}
sid = d.get("session_id") or os.environ.get("CLAUDE_SESSION_ID") or "unknown"
cwd = d.get("cwd") or os.getcwd()
# Emit as two lines so shell can read them safely.
print(sid.replace("\n", " "))
print(cwd.replace("\n", " "))
PYEOF
)

SESSION_ID=$(echo "$parsed" | sed -n '1p')
CWD=$(echo "$parsed" | sed -n '2p')

# Guard against the "unknown" case — still write a file, just keyed generically.
: "${SESSION_ID:=unknown}"
: "${CWD:=$PWD}"

TIMESTAMP_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TIMESTAMP_LOCAL=$(date +"%Y-%m-%d %H:%M:%S %z")
EPOCH=$(date +%s)

# --- Git snapshot (best-effort; empty if not a git repo) -----------------
GIT_BRANCH=""
GIT_LAST_COMMIT_SHA=""
GIT_LAST_COMMIT_MSG=""
GIT_STAGED=0
GIT_MODIFIED=0
GIT_UNTRACKED=0
GIT_AHEAD=0
GIT_BEHIND=0

if git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1; then
    GIT_BRANCH=$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null)
    GIT_LAST_COMMIT_SHA=$(git -C "$CWD" rev-parse --short HEAD 2>/dev/null)
    GIT_LAST_COMMIT_MSG=$(git -C "$CWD" log -1 --pretty=%s 2>/dev/null)
    if GIT_STATUS=$(git -C "$CWD" status --porcelain 2>/dev/null); then
        GIT_STAGED=$(echo "$GIT_STATUS"  | grep -c '^[MADRC]')
        GIT_MODIFIED=$(echo "$GIT_STATUS" | grep -c '^.[MD]')
        GIT_UNTRACKED=$(echo "$GIT_STATUS" | grep -c '^??')
    fi
    if AHEAD_BEHIND=$(git -C "$CWD" rev-list --left-right --count '@{u}...HEAD' 2>/dev/null); then
        GIT_BEHIND=$(echo "$AHEAD_BEHIND" | awk '{print $1}')
        GIT_AHEAD=$(echo  "$AHEAD_BEHIND" | awk '{print $2}')
    fi
fi

# --- Write JSON state FIRST, then best-effort recent files ---------------
# The find/git-ls-files call can be slow on large repos and may exceed the
# 5-second hook timeout. Writing core state (git info, cwd, timestamps)
# before attempting file discovery ensures we always have useful output.
RECENT_FILES=""

# --- Write JSON state via python, passing ALL values through env vars ----
JSON_FINAL="${STATE_DIR}/${SESSION_ID}.json"
MD_FINAL="${STATE_DIR}/${SESSION_ID}.md"

AP_SESSION_ID="$SESSION_ID" \
AP_TS_ISO="$TIMESTAMP_ISO" \
AP_TS_LOCAL="$TIMESTAMP_LOCAL" \
AP_EPOCH="$EPOCH" \
AP_CWD="$CWD" \
AP_GIT_BRANCH="$GIT_BRANCH" \
AP_GIT_SHA="$GIT_LAST_COMMIT_SHA" \
AP_GIT_MSG="$GIT_LAST_COMMIT_MSG" \
AP_GIT_STAGED="$GIT_STAGED" \
AP_GIT_MODIFIED="$GIT_MODIFIED" \
AP_GIT_UNTRACKED="$GIT_UNTRACKED" \
AP_GIT_AHEAD="$GIT_AHEAD" \
AP_GIT_BEHIND="$GIT_BEHIND" \
AP_RECENT="$RECENT_FILES" \
AP_JSON_FINAL="$JSON_FINAL" \
AP_MD_FINAL="$MD_FINAL" \
python3 - <<'PYEOF' 2>>"$DEBUG_LOG"
import json, os

def _int(name):
    try:
        return int(os.environ.get(name, "0") or 0)
    except ValueError:
        return 0

def _str_or_none(name):
    v = os.environ.get(name, "")
    return v if v else None

recent_raw = os.environ.get("AP_RECENT", "")
recent = [line for line in recent_raw.splitlines() if line.strip()]

state = {
    "session_id": os.environ.get("AP_SESSION_ID", "unknown"),
    "timestamp_iso": os.environ.get("AP_TS_ISO", ""),
    "timestamp_local": os.environ.get("AP_TS_LOCAL", ""),
    "epoch": _int("AP_EPOCH"),
    "cwd": os.environ.get("AP_CWD", ""),
    "git": {
        "branch": _str_or_none("AP_GIT_BRANCH"),
        "last_commit_sha": _str_or_none("AP_GIT_SHA"),
        "last_commit_msg": _str_or_none("AP_GIT_MSG"),
        "staged": _int("AP_GIT_STAGED"),
        "modified": _int("AP_GIT_MODIFIED"),
        "untracked": _int("AP_GIT_UNTRACKED"),
        "ahead": _int("AP_GIT_AHEAD"),
        "behind": _int("AP_GIT_BEHIND"),
    },
    "recent_files": recent,
}

json_final = os.environ["AP_JSON_FINAL"]
md_final = os.environ["AP_MD_FINAL"]

json_tmp = json_final + ".tmp"
md_tmp = md_final + ".tmp"

# JSON
with open(json_tmp, "w") as f:
    json.dump(state, f, indent=2)
os.replace(json_tmp, json_final)

# Markdown
lines = []
lines.append("# Auto-persisted session state")
lines.append("")
lines.append(f"- **Session**: `{state['session_id']}`")
lines.append(f"- **Last active**: {state['timestamp_local']}")
lines.append(f"- **CWD**: `{state['cwd']}`")
g = state["git"]
if g["branch"]:
    lines.append(f"- **Git branch**: `{g['branch']}`")
    msg = g["last_commit_msg"] or ""
    lines.append(f"- **Last commit**: `{g['last_commit_sha']}` — {msg}")
    lines.append(
        f"- **Uncommitted**: {g['staged']} staged, {g['modified']} modified, "
        f"{g['untracked']} untracked"
    )
    if g["ahead"] or g["behind"]:
        lines.append(f"- **Upstream**: {g['ahead']} ahead, {g['behind']} behind")
else:
    lines.append("- **Git**: _not a git repo_")
if recent:
    lines.append("")
    lines.append("## Recently modified (last 30 min)")
    lines.append("")
    for f_ in recent:
        lines.append(f"- `{f_}`")
lines.append("")
lines.append("---")
lines.append("_Auto-updated on every Stop event by `auto-persist`. No Claude tokens consumed._")
lines.append("")

with open(md_tmp, "w") as f:
    f.write("\n".join(lines))
os.replace(md_tmp, md_final)
PYEOF

# --- Best-effort: discover recently-modified files and update state ------
# This runs AFTER the core state is already written. If the hook times out
# here, we still have git info + cwd + timestamps from the write above.
if git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1; then
    # Fast path: git-tracked modified + untracked files (respects .gitignore)
    RECENT_FILES=$(git -C "$CWD" ls-files -m -o --exclude-standard 2>/dev/null | head -10)
else
    # Fallback: bounded find for non-git directories
    RECENT_FILES=$(find "$CWD" -maxdepth 3 -type f -mmin -30 \
        -not -path '*/.git/*' \
        -not -path '*/node_modules/*' \
        -not -path '*/.omc/*' \
        -not -path '*/dist/*' \
        -not -path '*/build/*' \
        -not -path '*/.next/*' \
        -not -path '*/.cache/*' \
        -not -path '*/__pycache__/*' \
        -not -name '*.log' \
        2>/dev/null | head -10)
fi

# Re-write state with recent files if we got any
if [ -n "$RECENT_FILES" ]; then
    AP_RECENT="$RECENT_FILES" \
    AP_JSON_FINAL="$JSON_FINAL" \
    AP_MD_FINAL="$MD_FINAL" \
    python3 - <<'PYEOF' 2>>"$DEBUG_LOG"
import json, os

recent_raw = os.environ.get("AP_RECENT", "")
recent = [line for line in recent_raw.splitlines() if line.strip()]
if not recent:
    raise SystemExit(0)

json_final = os.environ["AP_JSON_FINAL"]
md_final = os.environ["AP_MD_FINAL"]

# Update JSON
try:
    with open(json_final, "r") as f:
        state = json.load(f)
    state["recent_files"] = recent
    json_tmp = json_final + ".tmp"
    with open(json_tmp, "w") as f:
        json.dump(state, f, indent=2)
    os.replace(json_tmp, json_final)
except Exception:
    pass

# Append to Markdown
try:
    with open(md_final, "r") as f:
        content = f.read()
    marker = "---\n_Auto-updated"
    if marker in content:
        before = content.split(marker)[0]
        lines = [before.rstrip()]
        lines.append("")
        lines.append("## Recently modified")
        lines.append("")
        for rf in recent:
            lines.append(f"- `{rf}`")
        lines.append("")
        lines.append("---")
        lines.append("_Auto-updated on every Stop event by `auto-persist`. No Claude tokens consumed._")
        lines.append("")
        md_tmp = md_final + ".tmp"
        with open(md_tmp, "w") as f:
            f.write("\n".join(lines))
        os.replace(md_tmp, md_final)
except Exception:
    pass
PYEOF
fi

exit 0
