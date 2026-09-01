#!/bin/bash
# Fixture tests for usage_report.py — builds a fake ~/.claude/projects tree
# with one desktop session (with a subagent + a cold resume), one terminal
# session, one teammate session and one headless job, then asserts on the
# rendered markdown. Run: ./test.sh (exit 0 = all pass).

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/usage-report-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ROOT="$WORK/projects"

python3 - "$ROOT" <<'PY'
import json, os, sys
from datetime import datetime, timedelta, timezone
root = sys.argv[1]
now = datetime.now(tz=timezone.utc)
def iso(t): return t.isoformat().replace("+00:00", "Z")
def usage(cr, cc, out, ttl="1h"):
    return {"input_tokens": 2, "cache_creation_input_tokens": cc, "cache_read_input_tokens": cr, "output_tokens": out,
            "cache_creation": {"ephemeral_1h_input_tokens": cc if ttl == "1h" else 0, "ephemeral_5m_input_tokens": cc if ttl == "5m" else 0}}
def line(obj): return json.dumps(obj, separators=(",", ":")) + "\n"

def write(project, sid, rows, sub=None):
    d = os.path.join(root, project); os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, sid + ".jsonl"), "w") as fh:
        for r in rows: fh.write(line(r))
    if sub:
        sd = os.path.join(d, sid, "subagents"); os.makedirs(sd, exist_ok=True)
        with open(os.path.join(sd, "agent-1.jsonl"), "w") as fh:
            for r in sub: fh.write(line(r))

DESK = "11111111-1111-1111-1111-111111111111"
t0 = now - timedelta(hours=3)
rows = [{"type": "user", "entrypoint": "claude-desktop", "cwd": "/w/proj", "timestamp": iso(t0), "effort": "max", "message": {"role": "user", "content": "build the thing"}},
        {"type": "assistant", "entrypoint": "claude-desktop", "timestamp": iso(t0 + timedelta(seconds=5)),
         "message": {"id": "m1", "model": "claude-fable-5", "usage": usage(0, 60000, 500),
                     "content": [{"type": "tool_use", "name": "Agent", "input": {"subagent_type": "general-purpose", "model": "opus"}}]}},
        {"type": "user", "entrypoint": "claude-desktop", "timestamp": iso(t0 + timedelta(seconds=6)), "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "x", "content": "ok"}]}},
        {"type": "assistant", "entrypoint": "claude-desktop", "timestamp": iso(t0 + timedelta(seconds=9)),
         "message": {"id": "m2", "model": "claude-fable-5", "usage": usage(60000, 2000, 400), "content": [{"type": "text", "text": "done"}]}},
        # second human turn after a 2-hour idle -> cold resume (full re-write)
        {"type": "user", "entrypoint": "claude-desktop", "timestamp": iso(t0 + timedelta(hours=2)), "message": {"role": "user", "content": "continue"}},
        {"type": "assistant", "entrypoint": "claude-desktop", "timestamp": iso(t0 + timedelta(hours=2, seconds=8)),
         "message": {"id": "m3", "model": "claude-fable-5", "usage": usage(0, 62000, 300), "content": [{"type": "text", "text": "resumed"}]}},
        {"type": "user", "entrypoint": "claude-desktop", "timestamp": iso(t0 + timedelta(hours=2, seconds=9)), "message": {"role": "user", "content": "<task-notification>agent done</task-notification>"}},
        {"type": "cost-state", "totalCostUSD": 5.0}]
sub = [{"type": "assistant", "isSidechain": True, "entrypoint": "claude-desktop", "timestamp": iso(t0 + timedelta(seconds=7)),
        "message": {"id": "s1", "model": "claude-opus-5", "usage": usage(0, 20000, 800, "5m"), "content": [{"type": "text", "text": "sub"}]}}]
write("-w-proj", DESK, rows, sub)

CLI = "22222222-2222-2222-2222-222222222222"
t1 = now - timedelta(hours=1)
rows = [{"type": "user", "entrypoint": "cli", "cwd": "/w/proj", "timestamp": iso(t1), "message": {"role": "user", "content": "quick fix"}},
        {"type": "assistant", "entrypoint": "cli", "timestamp": iso(t1 + timedelta(seconds=4)),
         "message": {"id": "c1", "model": "claude-sonnet-5", "usage": usage(0, 50000, 200), "content": [{"type": "text", "text": "ok"}]}}]
write("-w-proj", CLI, rows)

TEAM = "33333333-3333-3333-3333-333333333333"
rows = [{"type": "user", "entrypoint": "cli", "cwd": "/w/proj/sub", "timestamp": iso(t1 + timedelta(seconds=10)), "message": {"role": "user", "content": "<teammate-message teammate_id=\"team-lead\">do work</teammate-message>"}},
        {"type": "assistant", "entrypoint": "cli", "timestamp": iso(t1 + timedelta(seconds=20)),
         "message": {"id": "t1", "model": "claude-sonnet-5", "usage": usage(0, 30000, 100), "content": [{"type": "text", "text": "ok"}]}}]
write("-w-proj-sub", TEAM, rows)

HEAD = "44444444-4444-4444-4444-444444444444"
rows = [{"type": "user", "entrypoint": "sdk-cli", "cwd": "/plugins/x", "timestamp": iso(t1), "effort": "max", "message": {"role": "user", "content": "classify this"}},
        {"type": "assistant", "entrypoint": "sdk-cli", "timestamp": iso(t1 + timedelta(seconds=3)),
         "message": {"id": "h1", "model": "claude-sonnet-5", "usage": usage(0, 40000, 5000), "content": [{"type": "text", "text": "yes"}]}}]
write("-plugins-x", HEAD, rows)
PY

OUT="$WORK/report.md"
if python3 "$HERE/usage_report.py" --root "$ROOT" --since 7 --out "$OUT" --quiet >/dev/null 2>"$WORK/err"; then
    echo "pass  report generates"; PASS=$((PASS+1))
else
    echo "FAIL  report generates: $(cat "$WORK/err")"; FAIL=$((FAIL+1)); exit 1
fi

check() {  # check <name> <regex>
    if grep -Eq -- "$2" "$OUT"; then echo "pass  $1"; PASS=$((PASS+1)); else echo "FAIL  $1 — /$2/ not found"; FAIL=$((FAIL+1)); fi
}
check "counts sessions by class"            'desktop 1, terminal 1, teammates 1, headless 1'
check "desktop: 2 human turns (notification excluded)" '\| sessions / human turns \| 1 / 2 \| 1 / 1 \|'
check "desktop: 3 API calls -> 1.5 per turn" '\| API calls per turn \| 1\.5 \| 1\.0 \|'
check "cold resume counted for desktop"      'resumes after >60 min idle \(count, per session, \$\) \| 1, 1\.00, \$[0-9]+ \| 0, 0\.00, \$0 \|'
check "agent call with explicit model"       'Agent calls per turn / with explicit model \| 0\.50 / 100% \| 0\.00 / n/a \|'
check "subagent spend attributed to opus"    "share of subagent \\\$ on opus/fable \| 100% \| n/a \|"
# teammate: sonnet, 30K tokens written on the 1h TTL = 30000 * 2.0 * $2/M = $0.12 (+ output), charged to the cli lead's single turn
check "teammate cost attributed to terminal lead" 'delegation \$ per turn \(subagents \+ teammates\) \| \$[0-9.]+ \| \$0\.1[0-9] \|'
check "task notification counted"            '\| background task-notification turns \| 1 \| 0 \|'
check "effort recorded"                      "effort values seen \| \{'max': 1\} \|"
check "headless job section"                 '1 jobs, \$[0-9]+ total'
check "headless spawner named"               '-plugins-x \(1\)'
check "calibration line uses cost-state"     'Calibration: this report / Claude Code'
check "levers: effort max flagged"           'Effort `max` is pinned'
check "levers: cold resume flagged"          'desktop: 1 resumes after >60 min idle'

# Desktop $ sanity: fable 1h writes 2x $10/M: 60000+2000+62000=124K*20=$2.48; reads 60K*1=$0.06; out 1200*50=$0.06;
# sub: opus 5m write 20K*1.25*5=$0.125 + out 800*25=$0.02 -> total ~$2.73
check "desktop dollars in expected range"    '\| \$ per session \(median / mean\) \| \$2\.[6-8][0-9] / \$2\.[6-8][0-9] \|'

# Read-multiplier: Fable/Mythos 5.1 price cache reads at 0.025x base input.
if python3 -c "
import sys; sys.path.insert(0, '$HERE')
from usage_report import cost
b = dict(calls=1, input=0, cache_create=0, cache_read=1_000_000, output=0, c5m=0, c1h=0)
assert abs(cost('claude-fable-5-1', b) - 0.25) < 1e-9, cost('claude-fable-5-1', b)
assert abs(cost('claude-fable-5', b) - 1.00) < 1e-9, cost('claude-fable-5', b)
"; then echo "pass  fable-5-1 reads priced at 0.025x, fable-5 at 0.1x"; PASS=$((PASS+1)); else echo "FAIL  read multiplier"; FAIL=$((FAIL+1)); fi

echo "----"; echo "passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ]
