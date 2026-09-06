#!/bin/bash
# Read Cost Monitor — prices a file read BEFORE it lands in context
#
# Every other helper in this repo warns after the tokens have arrived:
# watching-cost measures tool_response, subagent-isolation counts files already
# read. By then the cache write is paid and the content is in the prefix for
# the rest of the session. This hook fires on PreToolUse for Read — at the
# decision point, while a range read or a delegation is still an option.
#
# It never blocks. A PreToolUse block would deny the call and force Claude to
# emit another tool call, and that extra turn re-reads the whole cached prefix:
# at a 200K prefix on Opus 5 that is ~$0.10, more than the warning can save on
# any file this repo has measured. Warning costs nothing — the Read proceeds in
# the same turn.
#
# The gate is dollars, not lines. The same file costs 5x more to carry on Fable
# than on Sonnet, so a line- or token-threshold that is right for one model is
# noise or silence on the other. Model and cache TTL are read from the session
# transcript, so the figure is this session's figure.
#
# Part of: claude-cost-helpers / read-cost
# Companion to: The Economics of Claude Code

PY=$(cat <<'PYEOF'
import json, os, sys

# ---- Pricing (keep identical across helpers; ../pricing-parity.sh checks) ----
PRICE_IN = [  # $/M input tokens, matched by substring, first hit wins
    ("fable", 10.0), ("mythos", 10.0), ("opus", 5.0),
    ("sonnet-5", 2.0), ("sonnet", 3.0), ("haiku", 1.0),
]


def price_for(model):
    for key, p in PRICE_IN:
        if key in (model or ""):
            return p
    return 5.0


def read_mult(model):
    # Claude Fable 5.1 / Mythos 5.1 read cache at 0.025x base input; others 0.1x.
    m = model or ""
    return 0.025 if ("fable-5-1" in m or "mythos-5-1" in m) else 0.1


def write_mult(ttl):
    return 2.0 if ttl >= 3600 else 1.25


def emit(obj):
    sys.stdout.write(json.dumps(obj) + "\n")


def trace(note):
    sys.stderr.write(f"[read-cost] {note}\n")


def env_float(name, default):
    try:
        return float(os.environ.get(name) or default)
    except ValueError:
        return default


def env_int(name, default):
    try:
        return int(os.environ.get(name) or default)
    except ValueError:
        return default


QUIET = {"continue": True, "suppressOutput": True}
THRESHOLD = env_float("CLAUDE_READ_COST_THRESHOLD", 0.15)   # dollars
HORIZON = env_int("CLAUDE_READ_COST_HORIZON", 20)           # remaining API calls
MAX_WARNINGS = env_int("CLAUDE_READ_COST_MAX_WARNINGS", 5)  # per session

try:
    d = json.load(sys.stdin)
except Exception:
    emit(QUIET); sys.exit(0)

if d.get("tool_name") != "Read":
    emit(QUIET); sys.exit(0)

ti = d.get("tool_input", {}) or {}
path = ti.get("file_path") or ""
if not path or not os.path.isfile(path):
    emit(QUIET); sys.exit(0)

try:
    total_bytes = os.path.getsize(path)
except OSError:
    emit(QUIET); sys.exit(0)

# A bounded read costs only its slice. Scale by the share of lines requested so
# `Read(offset=, limit=)` is never warned about as if it pulled the whole file.
total_lines = 0
if total_bytes < 10 * 1024 * 1024:   # don't walk a huge file just to count lines
    try:
        with open(path, "rb") as fh:
            total_lines = sum(1 for _ in fh)
    except OSError:
        total_lines = 0

limit = ti.get("limit")
bounded = False
if isinstance(limit, int) and limit > 0 and total_lines > limit:
    total_bytes = int(total_bytes * (limit / total_lines))
    bounded = True

# chars/4, the estimator used by watching-cost and just-one-more-turn. Read's
# line-number prefixes add tokens, so this under-counts — deliberately, so the
# hook stays quiet rather than over-warning.
tokens = total_bytes // 4
if tokens <= 0:
    emit(QUIET); sys.exit(0)


def session_state(tpath):
    """(model, ttl_seconds) from the last main-thread assistant message."""
    if not tpath or not os.path.exists(tpath):
        return None, 3600
    try:
        with open(tpath, "rb") as fh:
            fh.seek(0, os.SEEK_END)
            size = fh.tell()
            fh.seek(size - min(size, 400_000))
            lines = fh.read().decode("utf-8", "replace").splitlines()
    except OSError:
        return None, 3600
    for line in reversed(lines):
        if '"model"' not in line:
            continue
        try:
            row = json.loads(line)
        except Exception:
            continue
        if row.get("isSidechain"):
            continue
        msg = row.get("message") or {}
        model = msg.get("model")
        if not model:
            continue
        cc = (msg.get("usage") or {}).get("cache_creation") or {}
        ttl = 3600
        if cc.get("ephemeral_5m_input_tokens") and not cc.get("ephemeral_1h_input_tokens"):
            ttl = 300
        return model, ttl
    return None, 3600


model, ttl = session_state(d.get("transcript_path"))
price = price_for(model)
write_cost = tokens * price * write_mult(ttl) / 1e6
carry_cost = tokens * price * read_mult(model) * HORIZON / 1e6
total = write_cost + carry_cost

if total < THRESHOLD:
    emit(QUIET); sys.exit(0)

# One warning per file per session, capped — a warning you learn to ignore is
# worse than no warning.
sid = d.get("session_id", d.get("sessionId", "unknown"))
state_dir = os.environ.get("CLAUDE_STATE_DIR") or os.path.join(
    os.path.expanduser("~"), ".claude", ".session-state")
seen_path = os.path.join(state_dir, f"{sid}.read-cost-warned")
seen = []
try:
    os.makedirs(state_dir, exist_ok=True)
    if os.path.exists(seen_path):
        seen = [l for l in open(seen_path).read().splitlines() if l]
except OSError:
    pass
if path in seen or len(seen) >= MAX_WARNINGS:
    emit(QUIET); sys.exit(0)
try:
    with open(seen_path, "a") as fh:
        fh.write(path + "\n")
except OSError:
    pass

# Cost scales with the share of lines read, so a real line count gives a real ratio.
if total_lines > 400:
    share = 200 / total_lines
    range_advice = (f"200 of this file's {total_lines:,} lines is ~{share:.0%} of the cost "
                    f"(~${total * share:.2f}).")
else:
    range_advice = "Reading only the lines you need costs proportionally less."

name = os.path.basename(path)
ttl_label = "1-hour" if ttl >= 3600 else "5-minute"
model_label = model or "the session model"
scope = f"lines {ti.get('offset') or 1}-{(ti.get('offset') or 1) + limit - 1} of " if bounded else ""
kb = total_bytes / 1024

head = (f"{name} is ~{tokens:,} tokens — reading it costs ~${total:.2f} on "
        f"{model_label} (${write_cost:.2f} cache write + ${carry_cost:.2f} over the next "
        f"{HORIZON} calls). Read a range, grep, or delegate to haiku.")

body = (
    f"ABOUT TO READ {scope}{path} — ~{tokens:,} tokens ({kb:,.0f} KB).\n\n"
    f"On {model_label} with a {ttl_label} cache TTL that is ~${total:.2f}: "
    f"${write_cost:.2f} to write it into the cached prefix, plus ~${carry_cost:.2f} to "
    f"re-read it across the next {HORIZON} API calls. It stays in context for the rest of "
    f"the session, so the carry figure grows if the session runs longer than {HORIZON} calls "
    f"and shrinks if it ends sooner.\n\n"
    f"If you do not need the whole file:\n"
    f"- Read a range — `Read(file_path=..., offset=N, limit=M)`. {range_advice}\n"
    f"- Grep for what you need instead of reading the file.\n"
    f"- Delegate to a subagent with `model: \"haiku\"` if this is scan/summarize work — the "
    f"file lands in the subagent's context, not yours, and Haiku reads at $1/MTok.\n\n"
    f"Reading it anyway is fine. This is informational and the read proceeds now.")

trace(head)
emit({"continue": True, "suppressOutput": True,
      "systemMessage": "read-cost: " + head,
      "hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": body}})
PYEOF
)

python3 -c "$PY"
# python3 missing or crashed before emitting: fail open with a valid response.
if [ "$?" -ne 0 ]; then
    echo '{"continue": true, "suppressOutput": true}'
fi
exit 0
