#!/bin/bash
# Fixture tests for read-cost-monitor.sh — every branch, no live session.
# Run: ./test.sh (exit 0 = all pass).
#
# The first case is a compile check on purpose. This hook fails open, so a
# syntax error in the embedded python turns it into a permanently silent no-op
# that every behavioural test would still "pass" by expecting silence. Compile
# first, then assert behaviour.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${HERE}/hooks/read-cost-monitor.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/read-cost-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0

check() {
    local name="$1" out="$2" expect="$3"
    if ! printf '%s' "$out" | python3 -c 'import json,sys; json.loads(sys.stdin.read())' 2>/dev/null; then
        echo "FAIL  $name — output is not valid JSON: $out"; FAIL=$((FAIL+1)); return
    fi
    local ok=1
    if [ "${expect:0:1}" = "!" ]; then
        printf '%s' "$out" | grep -Eq "${expect:1}" && ok=0
    else
        printf '%s' "$out" | grep -Eq "$expect" || ok=0
    fi
    if [ "$ok" = 1 ]; then echo "pass  $name"; PASS=$((PASS+1))
    else echo "FAIL  $name — expected /$expect/ in: $out"; FAIL=$((FAIL+1)); fi
}

# --- The embedded python must compile; a fail-open no-op must not pass as silence. ---
if python3 - "$HOOK" <<'PY' 2>/dev/null
import sys
s = open(sys.argv[1]).read()
compile(s.split("PY=$(cat <<'PYEOF'")[1].split("PYEOF")[0], "hook", "exec")
PY
then echo "pass  embedded python compiles"; PASS=$((PASS+1))
else echo "FAIL  embedded python does NOT compile — hook would fail open and stay silent"; FAIL=$((FAIL+1)); fi

# transcript <path> <model> <ttl:1h|5m>
transcript() {
    python3 - "$@" <<'PY'
import json, sys
path, model, ttl = sys.argv[1], sys.argv[2], sys.argv[3]
cc = {"ephemeral_1h_input_tokens": 1200 if ttl == "1h" else 0,
      "ephemeral_5m_input_tokens": 1200 if ttl == "5m" else 0}
rows = [
    {"type": "assistant", "isSidechain": False,
     "message": {"model": model, "usage": {"cache_creation": cc}}},
    # a later subagent row must not be mistaken for the session model
    {"type": "assistant", "isSidechain": True, "message": {"model": "claude-haiku-4-5", "usage": {}}},
]
with open(path, "w") as fh:
    for r in rows:
        fh.write(json.dumps(r, separators=(",", ":")) + "\n")
PY
}

# mkfile <path> <lines> <line_width>
mkfile() { python3 -c "
import sys; open(sys.argv[1],'w').write(('z'*int(sys.argv[3])+'\n')*int(sys.argv[2]))" "$1" "$2" "$3"; }

# run <state> <file> <transcript|\"\"> [offset] [limit] [ENV=v ...]
run() {
    local state="$1" file="$2" t="$3" off="${4:-}" lim="${5:-}"
    if [ $# -gt 5 ]; then shift 5; else shift $#; fi
    python3 - "$file" "$t" "$off" "$lim" <<'PY' | env CLAUDE_STATE_DIR="$WORK/$state" "$@" bash "$HOOK" 2>/dev/null
import json, sys
f, t, off, lim = sys.argv[1:5]
d = {"session_id": "s1", "hook_event_name": "PreToolUse", "tool_name": "Read",
     "tool_input": {"file_path": f}}
if t: d["transcript_path"] = t
if off: d["tool_input"]["offset"] = int(off)
if lim: d["tool_input"]["limit"] = int(lim)
print(json.dumps(d))
PY
}

TO="$WORK/opus.jsonl";   transcript "$TO" claude-opus-5   1h
TF="$WORK/fable.jsonl";  transcript "$TF" claude-fable-5-1 1h
TS="$WORK/sonnet.jsonl"; transcript "$TS" claude-sonnet-5  1h
T5="$WORK/opus5m.jsonl"; transcript "$T5" claude-opus-5   5m

BIG="$WORK/big.py";   mkfile "$BIG" 1500 79     # 120,000 B -> ~30,000 tok
SMALL="$WORK/small.py"; mkfile "$SMALL" 40 79   #   3,200 B ->    ~800 tok

# --- Pricing: 30,000 tok on Opus 5, 1h TTL, horizon 20 ---
# write 30000*5*2.0/1e6 = $0.30; carry 30000*5*0.1*20/1e6 = $0.30; total $0.60
o=$(run st1 "$BIG" "$TO")
check "opus 1h: 30K tok -> \$0.60 total"          "$o" 'costs ~\$0\.60 on claude-opus-5'
check "opus 1h: splits write vs carry"            "$o" '\$0\.30 cache write \+ \$0\.30 over the next 20 calls'
check "opus 1h: names the TTL in the body"        "$o" '1-hour cache TTL'
check "opus 1h: PreToolUse channel"               "$o" '"hookEventName": "PreToolUse"'
check "opus 1h: never blocks"                     "$o" '"continue": true'
check "opus 1h: real line-share ratio, not invented" "$o" "200 of this file's 1,500 lines is ~13% of the cost \(~\\\$0\.08\)"
check "opus 1h: offers haiku delegation"          "$o" 'model: ..haiku.*Haiku reads at \$1/MTok'
check "opus 1h: states the horizon assumption"    "$o" 'grows if the session runs longer than 20 calls'
check "opus 1h: ignores sidechain model rows"     "$o" '!haiku-4-5'

# --- Same file, same tokens, different model: the dollar gate re-prices. ---
# Fable 5.1: write 30000*10*2.0/1e6 = $0.60; carry 30000*10*0.025*20/1e6 = $0.15; total $0.75
o=$(run st2 "$BIG" "$TF")
check "fable 5.1: 0.025x reads -> \$0.75 (\$0.60 + \$0.15)" "$o" 'costs ~\$0\.75 on claude-fable-5-1.*\$0\.60 cache write \+ \$0\.15 over'
# Sonnet 5: write 30000*2*2.0/1e6 = $0.12; carry 30000*2*0.1*20/1e6 = $0.12; total $0.24
o=$(run st3 "$BIG" "$TS")
check "sonnet 5: cheaper carry -> \$0.24"          "$o" 'costs ~\$0\.24 on claude-sonnet-5'
# 5-minute TTL writes at 1.25x: 30000*5*1.25/1e6 = $0.1875 -> $0.19
o=$(run st4 "$BIG" "$T5")
check "opus 5m TTL: write drops to 1.25x"          "$o" '\$0\.19 cache write'
check "opus 5m TTL: body names the 5-minute TTL"   "$o" '5-minute cache TTL'

# --- Gate is dollars: the same file is silent on a cheap model at a high threshold. ---
o=$(run st5 "$BIG" "$TS" "" "" CLAUDE_READ_COST_THRESHOLD=0.30)
check "dollar gate: \$0.24 on sonnet < \$0.30 threshold -> silent" "$o" '"suppressOutput": true'
check "dollar gate: silent means no context injected"             "$o" '!additionalContext'
o=$(run st6 "$BIG" "$TO" "" "" CLAUDE_READ_COST_THRESHOLD=0.30)
check "dollar gate: \$0.60 on opus > \$0.30 threshold -> fires"    "$o" 'costs ~\$0\.60'

# --- Bounded reads pay only for their slice. ---
o=$(run st7 "$BIG" "$TO" 1 100)
check "bounded: 100 of 1500 lines -> under threshold, silent" "$o" '"suppressOutput": true'
o=$(run st8 "$BIG" "$TO" 1 1400)
check "bounded: 1400 of 1500 lines -> still fires"            "$o" 'costs ~\$0\.5'
check "bounded: names the range it priced"                    "$o" 'ABOUT TO READ lines 1-1400 of'

# --- Noise control. ---
o=$(run st9 "$BIG" "$TO"); o=$(run st9 "$BIG" "$TO")
check "dedup: same file twice in a session -> second is silent" "$o" '"suppressOutput": true'
mkfile "$WORK/a.py" 1500 79; mkfile "$WORK/b.py" 1500 79; mkfile "$WORK/c.py" 1500 79
o=$(run st10 "$BIG" "$TO"); o=$(run st10 "$WORK/a.py" "$TO"); o=$(run st10 "$WORK/b.py" "$TO")
check "cap: 3rd distinct file still warns (cap 5)" "$o" 'costs ~\$0\.60'
o=$(run st10 "$WORK/c.py" "$TO" "" "" CLAUDE_READ_COST_MAX_WARNINGS=3)
check "cap: 4th file with cap=3 -> silent"         "$o" '"suppressOutput": true'
o=$(run st11 "$SMALL" "$TO")
check "small file -> silent"                       "$o" '"suppressOutput": true'

# --- Env overrides. ---
o=$(run st12 "$BIG" "$TO" "" "" CLAUDE_READ_COST_HORIZON=100)
# carry 30000*5*0.1*100/1e6 = $1.50; total $1.80
check "horizon=100 -> carry \$1.50, total \$1.80" "$o" 'costs ~\$1\.80.*\$0\.30 cache write \+ \$1\.50 over the next 100 calls'

# --- Robustness: everything here must fail open, never crash. ---
o=$(run st13 "$WORK/does-not-exist.py" "$TO")
check "missing file -> silent"        "$o" '"suppressOutput": true'
o=$(run st14 "$BIG" "$WORK/no-transcript.jsonl")
check "no transcript -> defaults to opus price, still fires" "$o" 'costs ~\$0\.60 on the session model'
o=$(printf '{"tool_name":"Grep","tool_input":{"pattern":"x"}}' | bash "$HOOK" 2>/dev/null)
check "non-Read tool -> silent"       "$o" '"suppressOutput": true'
o=$(printf 'not json' | bash "$HOOK" 2>/dev/null)
check "malformed stdin -> valid JSON" "$o" '"continue": true'
o=$(run st15 "$WORK" "$TO")
check "directory as file_path -> silent" "$o" '"suppressOutput": true'

echo "----"; echo "passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ]
