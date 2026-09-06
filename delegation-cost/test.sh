#!/bin/bash
# Fixture tests for delegation-result-monitor.sh — exercises every state the
# cache-cooling check can emit, plus the size thresholds, without a live Claude
# session. Run: ./test.sh (exit 0 = all pass).
#
# Each case builds a synthetic transcript whose last main-thread assistant
# message (the "dispatch" row) carries a usage block (TTL breakdown + cached
# context size), a model and a timestamp N seconds in the past, pipes a
# PostToolUse(Agent) payload through the hook, and asserts on the emitted JSON.
# Transcript lines use Claude Code's compact JSON, like the real files.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${HERE}/delegation-result-monitor.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/delegation-cost-test.XXXXXX")
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
    {"type": "user", "timestamp": ts, "message": {"role": "user", "content": "explore the codebase"}},
    {"type": "assistant", "isSidechain": False, "timestamp": ts,
     "message": {"model": model, "usage": usage,
                 "content": [{"type": "tool_use", "id": "toolu_01", "name": "Agent", "input": {"prompt": "explore"}}]}},
]
if side:  # a fresh subagent line AFTER the dispatch row must be ignored
    rows.append({"type": "assistant", "isSidechain": True, "timestamp": iso(time.time()),
                 "message": {"model": "claude-haiku-4-5", "usage": {"input_tokens": 1, "cache_read_input_tokens": 10,
                             "cache_creation": {"ephemeral_5m_input_tokens": 5, "ephemeral_1h_input_tokens": 0}}}})
with open(path, "w") as fh:
    for r in rows:
        fh.write(json.dumps(r, separators=(",", ":")) + "\n")
PY
}

# payload <transcript|""> <response_chars>  -> PostToolUse(Agent) stdin JSON
payload() {
    python3 - "$SID" "$1" "$2" <<'PY'
import json, sys
sid, t, n = sys.argv[1], sys.argv[2], int(sys.argv[3])
d = {"session_id": sid, "hook_event_name": "PostToolUse", "tool_name": "Agent",
     "tool_input": {"prompt": "explore", "subagent_type": "Explore"}, "tool_response": "x" * n}
if t: d["transcript_path"] = t
print(json.dumps(d))
PY
}

# check <name> <out> <expect>   expect = regex that must match, or "!regex" that must NOT match.
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
    if [ "$ok" = 1 ]; then echo "pass  $name"; PASS=$((PASS+1)); else echo "FAIL  $name — expected /$expect/ in: $out"; FAIL=$((FAIL+1)); fi
}

# run_case <name> <transcript|""> <response_chars> <expect> [VAR=value ...]   (fresh HOME per case)
run_case() {
    local name="$1" transcript="$2" chars="$3" expect="$4"; shift 4
    local home="$WORK/home-$RANDOM$RANDOM"; mkdir -p "$home/.claude/.session-state"
    local out
    out=$(payload "$transcript" "$chars" | env HOME="$home" "$@" bash "$HOOK" 2>/dev/null)
    check "$name" "$out" "$expect"
}

T="$WORK/t.jsonl"

# --- The v1 false positive: 17 minutes on the 1-hour TTL is warm. ---
make_transcript "$T" 1020 1h 300000 claude-fable-5-1
run_case "1h TTL, agent ran 17 min -> silent" "$T" 400 '"suppressOutput": true'
run_case "1h TTL, agent ran 17 min -> no cache warning" "$T" 400 '!CACHE'
run_case "1h TTL, agent ran 17 min -> no additionalContext" "$T" 400 '!additionalContext'

# --- Near expiry (lead 15 min on the 1-hour TTL). ---
make_transcript "$T" 3000 1h 300000 claude-fable-5
run_case "1h TTL, 50 min -> CAME WITHIN ~10 min OF EXPIRING" "$T" 400 'PARENT CACHE CAME WITHIN (9|10) min OF EXPIRING while this agent ran \(50 min of a 1-hour TTL\)'
run_case "1h TTL, 50 min -> hookSpecificOutput PostToolUse" "$T" 400 '"hookEventName": "PostToolUse"'
run_case "1h TTL, 50 min -> systemMessage carries the cache line" "$T" 400 '"systemMessage": "delegation-cost: PARENT CACHE CAME WITHIN'
run_case "1h TTL, 50 min -> systemMessage is a whole sentence (fits 200 chars)" "$T" 400 '"systemMessage": "delegation-cost: [^"]*\)\."'

# --- Expired. ---
make_transcript "$T" 4500 1h 300000 claude-fable-5
run_case "1h TTL, 75 min -> EXPIRED" "$T" 400 'PARENT CACHE EXPIRED while this agent ran \(1h 15m of a 1-hour TTL\)'
run_case "1h TTL, 75 min -> priced 20x at fable (\$6.00 vs \$0.30)" "$T" 400 '\$6\.00 vs \$0\.30 warm \(20x\)'
run_case "1h TTL, 75 min -> names the 2x write price" "$T" 400 'Cache writes cost 2x input price on the 1-hour TTL'
run_case "1h TTL, 75 min -> advises run_in_background" "$T" 400 'run_in_background'
run_case "1h TTL, 75 min -> systemMessage is a whole sentence (fits 200 chars)" "$T" 400 '"systemMessage": "delegation-cost: [^"]*\)\."'

make_transcript "$T" 4500 1h 300000 claude-fable-5-1
run_case "Fable 5.1 reads at 0.025x -> \$6.00 vs ~\$0.08 (80x)" "$T" 400 '\$6\.00 vs \$0\.0[78] warm \(80x\)'

# --- 5-minute TTL (usage overage). ---
make_transcript "$T" 480 5m 100000 claude-opus-5
run_case "5m TTL, 8 min -> EXPIRED, 12.5x at opus (\$0.62 vs \$0.05)" "$T" 400 'PARENT CACHE EXPIRED while this agent ran \(8 min of a 5-minute TTL\).*\$0\.62 vs \$0\.05 warm \(12\.5x\)'
make_transcript "$T" 180 5m 100000 claude-opus-5
run_case "5m TTL, 3 min -> silent (lead is 60s)" "$T" 400 '!CACHE'
make_transcript "$T" 250 5m 100000 claude-opus-5
run_case "5m TTL, 4m10s -> CAME WITHIN ~50s OF EXPIRING" "$T" 400 'PARENT CACHE CAME WITHIN (4|5)[0-9]s OF EXPIRING'

make_transcript "$T" 480 none 300000 claude-sonnet-5
run_case "no TTL breakdown -> assume 5m (conservative), EXPIRED" "$T" 400 'PARENT CACHE EXPIRED.*5-minute TTL'

make_transcript "$T" 4500 1h 300000 claude-fable-5 1
run_case "fresh sidechain line after dispatch row -> ignored, still EXPIRED" "$T" 400 'PARENT CACHE EXPIRED'

# --- Env overrides, same knobs as idle-tax. ---
make_transcript "$T" 4500 1h 300000 claude-fable-5
run_case "CACHE_TTL_SECONDS=7200 -> silent at 75 min" "$T" 400 '!CACHE' CACHE_TTL_SECONDS=7200
make_transcript "$T" 900 1h 300000 claude-fable-5
run_case "CACHE_WARN_SECONDS=3000 -> near warning at 15 min (~45 min left)" "$T" 400 'PARENT CACHE CAME WITHIN 4[45] min' CACHE_WARN_SECONDS=3000

# --- Fallback: no transcript_path in the payload. ---
home="$WORK/home-fb"; mkdir -p "$home/.claude/.session-state"
echo $(( $(date +%s) - 1020 )) > "$home/.claude/.session-state/$SID.last-activity"
out=$(payload "" 400 | HOME="$home" bash "$HOOK" 2>/dev/null)
check "fallback: stale .last-activity (17 min), no transcript, TTL unknown -> no cache warning" "$out" '!CACHE'
out=$(payload "" 400 | HOME="$home" CACHE_TTL_SECONDS=300 bash "$HOOK" 2>/dev/null)
check "fallback: same + CACHE_TTL_SECONDS=300 -> EXPIRED, unpriced" "$out" 'PARENT CACHE EXPIRED.*re-writes the full prefix \(12\.5x a warm hit\)'
out=$(payload "" 400 | HOME="$WORK/home-fb-empty" CACHE_TTL_SECONDS=300 bash "$HOOK" 2>/dev/null)
check "fallback: forced TTL but no .last-activity -> silent, valid JSON" "$out" '!CACHE'

# --- One warning per dispatch row (parallel agents from one turn). ---
home="$WORK/home-dd"; mkdir -p "$home/.claude/.session-state"
make_transcript "$T" 4500 1h 300000 claude-fable-5
out1=$(payload "$T" 400 | HOME="$home" bash "$HOOK" 2>/dev/null)
out2=$(payload "$T" 400 | HOME="$home" bash "$HOOK" 2>/dev/null)
check "dedupe: first result of the dispatch warns" "$out1" 'PARENT CACHE EXPIRED'
check "dedupe: second result of the same dispatch stays quiet" "$out2" '!CACHE'

home="$WORK/home-esc"; mkdir -p "$home/.claude/.session-state"
epoch=$(python3 -c '
import json, sys
from datetime import datetime
rows = [json.loads(l) for l in open(sys.argv[1])]
ts = [r for r in rows if r.get("type") == "assistant"][0]["timestamp"]
print(int(datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()))' "$T")
echo "$epoch 1" > "$home/.claude/.session-state/$SID.delegation-cache-warned"
out=$(payload "$T" 400 | HOME="$home" bash "$HOOK" 2>/dev/null)
check "dedupe: near already warned for this dispatch, now expired -> escalates" "$out" 'PARENT CACHE EXPIRED'

# --- Size thresholds still work, and combine with the cache line. ---
make_transcript "$T" 600 1h 300000 claude-fable-5
run_case "per-result: 24K chars -> ~6K tokens warning" "$T" 24000 'That agent returned ~6K tokens now sitting in context'
run_case "per-result: 24K chars at 10 min -> no cache noise" "$T" 24000 '!CACHE'
run_case "per-result: 40K chars -> too large for inline results" "$T" 40000 'too large for inline results'
make_transcript "$T" 4500 1h 300000 claude-fable-5
run_case "expired + per-result -> both delivered, cache line is the systemMessage" "$T" 24000 '"systemMessage": "delegation-cost: PARENT CACHE EXPIRED.*That agent returned ~6K tokens'

# --- Robustness. ---
run_case "empty tool_response -> silent" "$T" 0 '^\{"continue": true, "suppressOutput": true\}$'
run_case "missing transcript file -> valid JSON, no cache warning" "$WORK/does-not-exist.jsonl" 400 '!CACHE'
printf 'not json\n{"type":"assistant"' > "$T"
run_case "corrupt transcript -> valid JSON, no cache warning" "$T" 400 '!CACHE'

# --- /delegation-report script: numbers from the session's real model + TTL. ---
REPORT="${HERE}/delegation_report.py"
# rcheck <name> <out> <expect>  (like check, but flattens newlines so regexes can span lines; no JSON check)
rcheck() {
    local name="$1" out="$2" expect="$3" ok=1 flat
    flat=$(printf '%s' "$out" | tr '\n' ' ')
    if [ "${expect:0:1}" = "!" ]; then
        printf '%s' "$flat" | grep -Eq "${expect:1}" && ok=0
    else
        printf '%s' "$flat" | grep -Eq "$expect" || ok=0
    fi
    if [ "$ok" = 1 ]; then echo "pass  $name"; PASS=$((PASS+1)); else echo "FAIL  $name — expected /$expect/ in: $flat"; FAIL=$((FAIL+1)); fi
}
sdir="$WORK/state-rep"; mkdir -p "$sdir"
out=$(python3 "$REPORT" --state-dir "$sdir" 2>&1)
rcheck "report: no state file -> nothing tracked" "$out" 'No delegation results tracked'

printf '3000\t14:32:10\n8000\t14:35:41\n2000\t14:41:02\n' > "$sdir/$SID.delegation-agents"
make_transcript "$T" 60 1h 300000 claude-fable-5-1
out=$(python3 "$REPORT" --state-dir "$sdir" --session "$SID" --transcript "$T" 2>&1)
rcheck "report: header names model + TTL" "$out" 'claude-fable-5-1, 1-hour TTL'
rcheck "report: totals, big-result count, share of prefix" "$out" '~13K tokens from 3 agent results, 1 of them over 5K.*4% of the ~300K-token cached prefix'
rcheck "report: warm per call on 5.1 (0.025x)" "$out" '\$0\.003[23] per API call \(cache read at 0\.025x input\)'
rcheck "report: 20-call horizon" "$out" '\$0\.06[45] over the next 20 API calls'
rcheck "report: cold whole prefix \$6.00, share \$0.26, 80x" "$out" 'whole prefix re-writes for \$6\.00; these results. share is \$0\.26, 80x their warm read \(2x input\)'
rcheck "report: verdict says delegation is not the tax" "$out" 'Verdict:\*\* delegation is not your tax here: 4% of the prefix'
rcheck "report: no stale \$1.50 / \$5 rates" "$out" '!\$1\.50|\$5\.00/MTok|blended'
out=$(python3 "$REPORT" --state-dir "$sdir" --transcript "$T" --horizon 50 2>&1)
rcheck "report: --session omitted -> newest state file; --horizon honored" "$out" '~13K tokens.*over the next 50 API calls'

printf '40000\t09:00:00\n20000\t09:20:00\n' > "$sdir/$SID.delegation-agents"
make_transcript "$T" 60 5m 100000 claude-opus-5
out=$(python3 "$REPORT" --state-dir "$sdir" --session "$SID" --transcript "$T" 2>&1)
rcheck "report: 5m TTL at opus -> 12.5x, 60% share, heavy verdict" "$out" 'claude-opus-5, 5-minute TTL.*60% of the ~100K.*12\.5x their warm read \(1\.25x input\).*Verdict:\*\* agent results are a heavy share'
rcheck "report: opus warm per call \$0.03" "$out" '\$0\.030 per API call \(cache read at 0\.1x input\)'

out=$(python3 "$REPORT" --state-dir "$sdir" --session "$SID" --transcript "$WORK/none.jsonl" 2>&1)
rcheck "report: no transcript, no override -> sizes only + how to price" "$out" '\(unpriced\).*~60K tokens from 2 agent results.*--model <id> --ttl'
rcheck "report: no transcript -> no dollar figures" "$out" '!\$[0-9]'
out=$(python3 "$REPORT" --state-dir "$sdir" --session "$SID" --transcript "$WORK/none.jsonl" --model claude-sonnet-5 --ttl 3600 2>&1)
rcheck "report: --model/--ttl override prices without a transcript" "$out" 'claude-sonnet-5, 1-hour TTL.*\$0\.012 per API call.*these results re-write for \$0\.24, 20x their warm read'

# --- Cumulative: dollar-gated, priced for the model; the same tokens fire later on Fable 5.1. ---
cum_run() {  # cum_run <home> <transcript|""> <chars> -> hook stdout (state accumulates in <home>)
    payload "$2" "$3" | HOME="$1" bash "$HOOK" 2>/dev/null
}
home="$WORK/home-cum5"; mkdir -p "$home/.claude/.session-state"
make_transcript "$T" 60 1h 300000 claude-fable-5
o1=$(cum_run "$home" "$T" 40000); o2=$(cum_run "$home" "$T" 40000); o3=$(cum_run "$home" "$T" 40000)
check "cumulative (fable-5): 10K tokens -> \$0.20 over 20 calls, under \$0.25, quiet" "$o1" '!Delegation results:'
check "cumulative (fable-5): 20K tokens -> \$0.40 over 20 calls, priced line" "$o2" 'Delegation results: ~20K tokens from 2 agents, 7% of the ~300K-token prefix\. Carrying them costs ~\$0\.020 per API call on claude-fable-5 \(warm\), ~\$0\.40 over the next 20 calls; a cold re-write of them is \$0\.40\.'
check "cumulative (fable-5): small share -> advice points at the rest of the prefix" "$o2" 'the other 93% of the prefix is the bigger lever'
check "cumulative (fable-5): \$0.25 fired once -> 30K tokens (\$0.60) quiet" "$o3" '!Delegation results:'
check "no swarm warning at 3 agents" "$o3" '!agents have returned results'
check "per-result carries its own warm price" "$o3" 'That agent returned ~10K tokens \(~\$0\.010 per API call on claude-fable-5, warm\)'

home="$WORK/home-cum51"; mkdir -p "$home/.claude/.session-state"
make_transcript "$T" 60 1h 300000 claude-fable-5-1
for i in 1 2 3 4; do o=$(cum_run "$home" "$T" 48000); done
check "cumulative (fable-5-1): 48K tokens -> \$0.24 at 0.025x reads, still quiet (20K fired on fable-5)" "$o" '!Delegation results:'
o=$(cum_run "$home" "$T" 48000)
check "cumulative (fable-5-1): 60K tokens -> \$0.30 over 20 calls, fires with 5.1 numbers" "$o" 'Delegation results: ~60K tokens from 5 agents, 20% of the ~300K-token prefix\. Carrying them costs ~\$0\.015 per API call on claude-fable-5-1 \(warm\), ~\$0\.30 over the next 20 calls; a cold re-write of them is \$1\.20\.'

home="$WORK/home-share"; mkdir -p "$home/.claude/.session-state"
make_transcript "$T" 60 1h 60000 claude-opus-5
o=$(cum_run "$home" "$T" 40000); o=$(cum_run "$home" "$T" 40000); o=$(cum_run "$home" "$T" 40000)
check "cumulative (opus-5, 60K prefix): 30K = 50% share -> 'leading share' advice" "$o" 'Delegation results: ~30K tokens from 3 agents, 50% of the ~60K-token prefix.*leading share of what every call re-reads'

home="$WORK/home-big"; mkdir -p "$home/.claude/.session-state"
make_transcript "$T" 60 1h 300000 claude-fable-5
o=$(cum_run "$home" "$T" 800000)
check "800K-char result (stdin, not env) -> one result crossing all thresholds -> one message" "$o" 'Delegation results: ~200K tokens from 1 agent, .*~\$4\.00 over the next 20 calls'
o=$(cum_run "$home" "$T" 400)
check "all thresholds marked -> next result quiet" "$o" '!Delegation results:'

o=$(cum_run "$WORK/home-big" "$T" 40000 CLAUDE_DELEGATION_COST_THRESHOLDS=10)
home="$WORK/home-env"; mkdir -p "$home/.claude/.session-state"
o=$(payload "$T" 40000 | HOME="$home" CLAUDE_DELEGATION_COST_THRESHOLDS=0.05 CLAUDE_DELEGATION_HORIZON=100 bash "$HOOK" 2>/dev/null)
check "env: COST_THRESHOLDS=0.05, HORIZON=100 -> 10K tokens fires (\$1.00 over 100 calls)" "$o" 'Delegation results: ~10K tokens from 1 agent.*~\$1\.00 over the next 100 calls'

home="$WORK/home-unp"; mkdir -p "$home/.claude/.session-state"
o=$(payload "" 40000 | HOME="$home" bash "$HOOK" 2>/dev/null); o=$(payload "" 40000 | HOME="$home" bash "$HOOK" 2>/dev/null)
check "cumulative unpriced (no transcript): 20K tokens -> token-threshold fallback" "$o" 'Delegation results: ~20K tokens from 2 agents \(unpriced: no transcript'
check "cumulative unpriced: no dollar claims" "$o" '!\$[0-9]'

# --- agent-prompt-lint.sh (PreToolUse): output constraint + worker model. ---
LINT="${HERE}/agent-prompt-lint.sh"

# lint_model <path> <model>  -> transcript whose last main-thread assistant used <model>
lint_model() {
    python3 - "$1" "$2" <<'PYL'
import json, sys
path, model = sys.argv[1], sys.argv[2]
rows = [
    {"type": "user", "message": {"role": "user", "content": "go"}},
    {"type": "assistant", "isSidechain": False,
     "message": {"model": model, "usage": {"input_tokens": 3, "cache_read_input_tokens": 200000}}},
    # a later sidechain row must NOT be mistaken for the session model
    {"type": "assistant", "isSidechain": True, "message": {"model": "claude-haiku-4-5", "usage": {"input_tokens": 1}}},
]
with open(path, "w") as fh:
    for r in rows:
        fh.write(json.dumps(r, separators=(",", ":")) + "\n")
PYL
}

# lint <prompt> [model] [transcript]  -> run the lint hook, echo its stdout
lint() {
    python3 - "$1" "${2:-}" "${3:-}" <<'PYL' | bash "$LINT" 2>/dev/null
import json, sys
prompt, model, t = sys.argv[1], sys.argv[2], sys.argv[3]
d = {"session_id": "abcdef12-0000-0000-0000-000000000000", "hook_event_name": "PreToolUse",
     "tool_name": "Agent", "tool_input": {"prompt": prompt, "subagent_type": "Explore"}}
if model: d["tool_input"]["model"] = model
if t: d["transcript_path"] = t
print(json.dumps(d))
PYL
}

L="$WORK/lint.jsonl"
lint_model "$L" claude-opus-5

# Both warnings fire, and the model line is priced from the table (5.0 / 1.0 = 5x).
o=$(lint "Scan all test files in the repo and summarize coverage gaps" "" "$L")
check "lint: unconstrained + modelless -> both warnings" "$o" 'no output-length constraint.*read-heavy agent with no model'
check "lint: prices the inherited model from the transcript" "$o" 'inherits claude-opus-5 \(\$5/MTok in\) vs Haiku 4.5 \$1 \(5x\)'
check "lint: computes, never asserts — ratio is in the sentence" "$o" 'the same reading is \$1/M .*5x less'
check "lint: recommends the one lever that works per call" "$o" 'Pass .model: ..haiku'
check "lint: names the effort negative space" "$o" 'Agent tool has no effort parameter'
check "lint: PreToolUse hookSpecificOutput channel" "$o" '"hookEventName": "PreToolUse"'
check "lint: never blocks" "$o" '"continue": true'

# Sidechain rows must not be read as the session model (haiku would silence it).
check "lint: ignores sidechain rows when reading session model" "$o" '!Haiku 4.5 reads at'

# Explicit model set -> respect the caller's choice, no model warning.
o=$(lint "Scan all test files in the repo and summarize coverage gaps" haiku "$L")
check "lint: model set -> no model warning" "$o" '!read-heavy agent with no model'
check "lint: model set -> constraint warning still fires" "$o" 'no output-length constraint'

# Both fixed -> silent.
o=$(lint "Scan all files across the repo. Report in under 200 words." haiku "$L")
check "lint: constrained + model -> silent" "$o" '"suppressOutput": true'
check "lint: constrained + model -> no additionalContext" "$o" '!additionalContext'

# Narrow read (no breadth signal) must not fire the model warning — noise control.
o=$(lint "Read config.py and tell me the port. Keep it brief." "" "$L")
check "lint: narrow read -> no model warning" "$o" '!read-heavy'
check "lint: narrow read + brief -> fully silent" "$o" '"suppressOutput": true'

# A haiku session has nothing to downgrade to.
lint_model "$L" claude-haiku-4-5
o=$(lint "Scan every directory for TODO comments. Report in under 100 words." "" "$L")
check "lint: session already on haiku -> no model warning" "$o" '!read-heavy agent with no model'

# Fable 5.1 session: 10.0 / 1.0 = 10x, straight from the shared table.
lint_model "$L" claude-fable-5-1
o=$(lint "Scan all test files in the repo. Report in under 50 words." "" "$L")
check "lint: fable 5.1 -> 10x ratio from the price table" "$o" 'inherits claude-fable-5-1 \(\$10/MTok in\) vs Haiku 4.5 \$1 \(10x\)'

# No transcript -> still warns, but claims no ratio it cannot compute.
o=$(lint "Search every directory for TODO comments. Report in under 100 words." "" "")
check "lint: no transcript -> warns with haiku absolute price" "$o" 'Haiku 4.5 reads at \$1/MTok'
check "lint: no transcript -> no invented ratio" "$o" '!MTok in\) vs'

# Robustness: empty prompt, malformed JSON, missing transcript file.
o=$(lint "" "" "")
check "lint: empty prompt -> silent" "$o" '"suppressOutput": true'
o=$(printf 'not json' | bash "$LINT" 2>/dev/null)
check "lint: malformed stdin -> fails open with valid JSON" "$o" '"continue": true'
o=$(lint "Scan all files in the repo" "" "$WORK/does-not-exist.jsonl")
check "lint: missing transcript file -> falls back, no crash" "$o" 'Haiku 4.5 reads at \$1/MTok'

# --- /delegation-report: same session under another delegator. ---
printf '3000\t14:32:10\n8000\t14:35:41\n2000\t14:41:02\n' > "$sdir/$SID.delegation-agents"
make_transcript "$T" 60 1h 300000 claude-fable-5-1
out=$(python3 "$REPORT" --state-dir "$sdir" --session "$SID" --transcript "$T" 2>&1)
rcheck "compare: this session first, then Opus 5 and 4.8 rows" "$out" 'claude-fable-5-1 \(this session\) \| \$0\.25 \| \$0\.003[23] \| \$6\.00 \| 80x.*claude-opus-5 \| \$0\.50 \| \$0\.0065 \| \$3\.00 \| 20x.*claude-opus-4-8 \| \$0\.50 \| \$0\.0065 \| \$3\.00 \| 20x'
rcheck "compare: finding — 0.5x warm, 2x cold vs Opus" "$out" 'Finding:\*\* against an Opus 5 or Opus 4.8 delegator, claude-fable-5-1 carries these results at 0\.5x the warm cost per call and re-writes the prefix at 2x the cold cost'
rcheck "compare: one lapse = ~1,846 warm calls here vs ~462 on Opus" "$out" 'One cache lapse here costs as much as 1,8[0-9][0-9] API calls of carrying these results warm \(Opus: 46[0-9]\)'
rcheck "compare: relative penalty 4x, lever moved" "$out" 'a cache lapse on claude-fable-5-1 is 4x as punishing as on Opus: the lever moved from trimming agent results to keeping the cache warm'
rcheck "compare: tokenizer caveat present" "$out" 'Opus 4.7\+ and Fable share a tokenizer'
make_transcript "$T" 60 1h 300000 claude-opus-5
out=$(python3 "$REPORT" --state-dir "$sdir" --session "$SID" --transcript "$T" 2>&1)
rcheck "compare: on Opus -> finding describes the move to Fable 5.1 (0.5x warm, 2x cold)" "$out" 'Finding:\*\* this session is at Opus pricing\. A Fable 5.1 delegator would carry these results at 0\.5x the warm cost per call and re-write the prefix at 2x the cold cost'
out=$(python3 "$REPORT" --state-dir "$sdir" --session "$SID" --transcript "$WORK/none.jsonl" --model claude-sonnet-5 --ttl 3600 2>&1)
rcheck "compare: no prefix known -> warm comparison only, cold n/a" "$out" 'claude-sonnet-5 \(this session\) \| \$0\.20 \| \$0\.0026 \| n/a \| 20x.*carries these results at 0\.4x the warm cost per call\.'

echo "----"; echo "passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ]
