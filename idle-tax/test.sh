#!/bin/bash
# Fixture tests for cache-idle-timer.sh — exercises every state the hook can
# emit without a live Claude session. Run: ./test.sh (exit 0 = all pass).
#
# Each case builds a synthetic transcript whose last assistant message carries
# a usage block (TTL breakdown + cached context size) and a timestamp N seconds
# in the past, pipes a UserPromptSubmit payload through the hook, and asserts
# on the emitted JSON. Transcript lines use Claude Code's compact JSON
# (no spaces after separators), like the real files.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${HERE}/cache-idle-timer.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/idle-tax-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
SID="abcdef12-0000-0000-0000-000000000000"

# make_transcript <path> <age_seconds> <ttl: 1h|5m|none> <ctx_tokens> <model> [sidechain_tail=1]
make_transcript() {
    python3 - "$@" <<'PY'
import json, sys, time
from datetime import datetime, timezone
path, age, ttl, ctx, model = sys.argv[1], int(sys.argv[2]), sys.argv[3], int(sys.argv[4]), sys.argv[5]
side = len(sys.argv) > 6 and sys.argv[6] == "1"
def iso(t): return datetime.fromtimestamp(t, tz=timezone.utc).isoformat().replace("+00:00", "Z")
ts = iso(time.time() - age)
cc = {"ephemeral_5m_input_tokens": 0, "ephemeral_1h_input_tokens": 0}
if ttl == "1h": cc["ephemeral_1h_input_tokens"] = 1200
if ttl == "5m": cc["ephemeral_5m_input_tokens"] = 1200
usage = {"input_tokens": 3, "cache_creation_input_tokens": 1200, "cache_read_input_tokens": ctx - 1203, "output_tokens": 50}
if ttl != "none": usage["cache_creation"] = cc
rows = [
    {"type": "user", "timestamp": ts, "message": {"role": "user", "content": "hi"}},
    {"type": "assistant", "isSidechain": False, "timestamp": ts,
     "message": {"model": model, "usage": usage, "content": [{"type": "text", "text": "ok"}]}},
]
if side:  # a fresh subagent line AFTER the main-thread one must be ignored
    rows.append({"type": "assistant", "isSidechain": True, "timestamp": iso(time.time()),
                 "message": {"model": "claude-haiku-4-5", "usage": {"input_tokens": 1, "cache_read_input_tokens": 10,
                             "cache_creation": {"ephemeral_5m_input_tokens": 5, "ephemeral_1h_input_tokens": 0}}}})
with open(path, "w") as fh:
    for r in rows:
        fh.write(json.dumps(r, separators=(",", ":")) + "\n")
PY
}

# run_case <name> <transcript|""> <expect> [VAR=value ...]
#   expect = regex that must match stdout, or "!regex" that must NOT match.
run_case() {
    local name="$1" transcript="$2" expect="$3"; shift 3
    local home="$WORK/home-$RANDOM$RANDOM"; mkdir -p "$home/.claude/.session-state" "$home/.claude/sessions"
    local payload="{\"session_id\":\"$SID\"}"
    [ -n "$transcript" ] && payload="{\"session_id\":\"$SID\",\"transcript_path\":\"$transcript\"}"
    local out
    out=$(echo "$payload" | env HOME="$home" "$@" bash "$HOOK" 2>/dev/null)
    if ! printf '%s' "$out" | python3 -c 'import json,sys; json.loads(sys.stdin.read())' 2>/dev/null; then
        echo "FAIL  $name — output is not valid JSON: $out"; FAIL=$((FAIL+1)); return
    fi
    local ok=1
    if [ "${expect:0:1}" = "!" ]; then
        printf '%s' "$out" | grep -Eq "${expect:1}" && ok=0
    else
        printf '%s' "$out" | grep -Eq "$expect" || ok=0
    fi
    if [ "$ok" = 1 ]; then echo "pass  $name"; PASS=$((PASS+1)); else echo "FAIL  $name — expected /$expect/ in: $out"; FAIL=$((FAIL+1)); fi
}

T="$WORK/t.jsonl"

make_transcript "$T" 600 1h 300000 claude-fable-5
run_case "1h TTL, 10 min idle -> silent" "$T" '"suppressOutput": true'
run_case "1h TTL, 10 min idle -> no additionalContext" "$T" '!additionalContext'

make_transcript "$T" 3000 1h 300000 claude-fable-5
run_case "1h TTL, 50 min idle -> EXPIRES IN ~10 min" "$T" 'CACHE EXPIRES IN (9 min|10 min)'
run_case "1h TTL, 50 min idle -> hookSpecificOutput shape" "$T" '"hookEventName": "UserPromptSubmit"'
run_case "1h TTL, 50 min idle -> systemMessage present" "$T" '"systemMessage": "idle-tax'

make_transcript "$T" 4500 1h 300000 claude-fable-5
run_case "1h TTL, 75 min idle -> EXPIRED" "$T" 'CACHE EXPIRED \(1h 15m idle, 1-hour TTL\)'
run_case "1h TTL, 75 min idle -> 20x at fable price (\$6.00 vs \$0.30)" "$T" '\$6\.00 vs \$0\.30 for a warm hit \(20x\)'
run_case "IDLE_TAX_QUIET=1 -> no systemMessage" "$T" '!systemMessage' IDLE_TAX_QUIET=1
run_case "IDLE_TAX_QUIET=1 -> context still injected" "$T" 'CACHE EXPIRED' IDLE_TAX_QUIET=1

make_transcript "$T" 480 5m 100000 claude-opus-5
run_case "5m TTL, 8 min idle -> EXPIRED, 12.5x at opus price" "$T" 'CACHE EXPIRED \(8 min idle, 5-minute TTL\).*\$0\.62 vs \$0\.05 for a warm hit \(12\.5x\)'

make_transcript "$T" 200 5m 100000 claude-opus-5
run_case "5m TTL, 3m20s idle -> silent (warn lead is 60s)" "$T" '"suppressOutput": true'

make_transcript "$T" 250 5m 100000 claude-opus-5
run_case "5m TTL, 4m10s idle -> EXPIRES IN ~50s" "$T" 'CACHE EXPIRES IN (4|5)[0-9]s'

make_transcript "$T" 4500 none 300000 claude-sonnet-5
run_case "no TTL breakdown -> assume 5m TTL, EXPIRED" "$T" 'CACHE EXPIRED.*5-minute TTL'

make_transcript "$T" 4500 1h 300000 claude-fable-5 1
run_case "fresh sidechain line after main -> still EXPIRED (ignored)" "$T" 'CACHE EXPIRED'

make_transcript "$T" 4500 1h 300000 claude-fable-5
run_case "CACHE_TTL_SECONDS=7200 override -> silent at 75 min" "$T" '"suppressOutput": true' CACHE_TTL_SECONDS=7200
run_case "CACHE_WARN_SECONDS=3000 -> warns at 75 min? no: expired" "$T" 'CACHE EXPIRED' CACHE_WARN_SECONDS=3000

make_transcript "$T" 900 1h 300000 claude-fable-5
run_case "CACHE_WARN_SECONDS=3000 -> EXPIRES IN at 15 min idle" "$T" 'CACHE EXPIRES IN 4[45] min' CACHE_WARN_SECONDS=3000

# Fallback path: no transcript_path in payload.
home="$WORK/home-fb"; mkdir -p "$home/.claude/.session-state"
echo $(( $(date +%s) - 480 )) > "$home/.claude/.session-state/$SID.last-activity"
out=$(echo "{\"session_id\":\"$SID\"}" | HOME="$home" bash "$HOOK" 2>/dev/null)
if printf '%s' "$out" | grep -q 'CACHE EXPIRED (8 min idle, 5-minute TTL)'; then echo "pass  fallback: stale .last-activity, no transcript -> EXPIRED"; PASS=$((PASS+1)); else echo "FAIL  fallback: $out"; FAIL=$((FAIL+1)); fi
run_case "fallback: first prompt -> silent" "" '"suppressOutput": true'
run_case "missing transcript file -> falls back, first prompt silent" "$WORK/does-not-exist.jsonl" '"suppressOutput": true'

# Handoff surfacing: this session's idle-autosave note is preferred over a newer generic one.
home="$WORK/home-ho"; mkdir -p "$home/.claude/.session-state" "$home/.claude/sessions"
touch "$home/.claude/sessions/2026-09-01-idle-autosave-abcdef12-session.md"; sleep 1
touch "$home/.claude/sessions/2026-09-01-other-session.md"
make_transcript "$T" 4500 1h 300000 claude-fable-5
out=$(echo "{\"session_id\":\"$SID\",\"transcript_path\":\"$T\"}" | HOME="$home" bash "$HOOK" 2>/dev/null)
if printf '%s' "$out" | grep -q 'idle-autosave-abcdef12-session.md (saved'; then echo "pass  handoff: session's own idle-autosave note surfaced"; PASS=$((PASS+1)); else echo "FAIL  handoff: $out"; FAIL=$((FAIL+1)); fi

# Robustness: garbage transcript still yields valid JSON.
printf 'not json\n{"type":"assistant"' > "$T"
run_case "corrupt transcript -> valid silent JSON" "$T" '"continue": true'

echo "----"; echo "passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ]
