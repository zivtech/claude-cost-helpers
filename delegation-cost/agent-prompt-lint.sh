#!/bin/bash
# Agent Prompt Lint — PreToolUse(Agent) checks before the agent is dispatched
#
# Two things are cheap to get right at dispatch and impossible to fix after:
#
#   1. Output size. A prompt that says "report in under 200 words" produces a
#      200-word result. A prompt with no constraint produces whatever the agent
#      feels like — often 2,000+ words that land in your context permanently.
#
#   2. Worker model. An Agent call with no `model` inherits the default
#      subagent model. For scan/search/summarize work — where the agent reads a
#      lot and decides little — that is the session model's $/MTok paying for
#      Haiku's job. `model` is the one lever that works per-Agent-call.
#
# Effort is deliberately NOT linted here: the Agent tool has no effort
# parameter, and CLAUDE_CODE_EFFORT_LEVEL from settings.json env outranks agent
# frontmatter `effort:`, so an in-process subagent cannot be de-escalated at the
# call site. That is an effort-control concern (see ../effort-control).
#
# Fires on PreToolUse for Agent. Never blocks — a block would cost an extra
# round trip at full prefix, which is more than either warning saves.
#
# Part of: claude-cost-helpers / delegation-cost
# Companion to: The Economics of Claude Code, Part 6: The Delegation Tax

# The hook's stdin (the PreToolUse JSON) flows straight into python via stdin —
# never through an env var or argv, matching delegation-result-monitor.sh.
PY=$(cat <<'PYEOF'
import json, os, re, sys

# ---- Pricing (keep identical across helpers; ../pricing-parity.sh checks) ----
# This hook only prices input tokens; read_mult/write_mult are carried so the
# table is a full, parity-checked copy rather than a partial one that can drift.
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
    sys.stderr.write(f"[delegation-cost] {note}\n")


QUIET = {"continue": True, "suppressOutput": True}

try:
    d = json.load(sys.stdin)
except Exception:
    emit(QUIET); sys.exit(0)

ti = d.get("tool_input", {}) or {}
prompt = ti.get("prompt", "") or ""
model_arg = (ti.get("model") or "").strip()
if not prompt:
    emit(QUIET); sys.exit(0)

low = prompt.lower()

# ---- Check 1: output length constraint -------------------------------------
CONSTRAINT = [
    r"under \d+ words", r"fewer than \d+ words", r"in under \d+ words",
    r"max(imum)? \d+ words", r"\d+ words (or )?(less|max|limit)",
    r"keep.{0,20}(short|brief|terse|concise)",
    r"(short|brief|terse|concise) (response|report|summary|answer|output)",
    r"one (sentence|paragraph|line)", r"report in under",
    r"under \d+ (lines|sentences)",
]
has_constraint = any(re.search(p, low) for p in CONSTRAINT)

# ---- Check 2: read-heavy delegation dispatched with no model ----------------
# Require BOTH a read verb and a breadth signal. A narrow "read config.py and
# tell me the port" is not worth a warning; "scan every test file" is.
READ_VERB = (r"\b(read|scan|search|grep|find|locate|explore|audit|survey|"
             r"inventory|catalog|enumerate|list|summari[sz]e|extract|trace|map)\b")
BREADTH = (r"\b(all|every|each|across|entire|whole|codebase|repo|repository|"
           r"director(y|ies)|folders?|tree|files)\b")
read_heavy = bool(re.search(READ_VERB, low) and re.search(BREADTH, low))


def session_model(path):
    """Last main-thread assistant model in the transcript, or None."""
    if not path or not os.path.exists(path):
        return None
    try:
        with open(path, "rb") as fh:
            fh.seek(0, os.SEEK_END)
            size = fh.tell()
            back = min(size, 400_000)
            fh.seek(size - back)
            lines = fh.read().decode("utf-8", "replace").splitlines()
    except OSError:
        return None
    for line in reversed(lines):
        if '"model"' not in line:
            continue
        try:
            row = json.loads(line)
        except Exception:
            continue
        if row.get("isSidechain"):
            continue
        m = (row.get("message") or {}).get("model")
        if m:
            return m
    return None


warnings, headlines = [], []

if not has_constraint:
    headlines.append("no output-length constraint — the result sits in your context permanently")
    warnings.append(
        "This agent prompt has no output length constraint. Without one, the agent may "
        "return thousands of tokens that sit in your context permanently. Consider adding "
        'something like: "report in under 200 words" or "keep it brief".')

if read_heavy and not model_arg:
    sm = session_model(d.get("transcript_path"))
    haiku = price_for("haiku")
    if sm and price_for(sm) > haiku:
        ratio = price_for(sm) / haiku
        headlines.append(
            f'read-heavy agent with no model — inherits {sm} (${price_for(sm):g}/MTok in) '
            f'vs Haiku 4.5 ${haiku:g} ({ratio:g}x)')
        warnings.append(
            f"This Agent call looks read-heavy but sets no `model`, so it inherits the default "
            f"subagent model. Every token it reads is priced at ${price_for(sm):g}/M on {sm}; on "
            f"Haiku 4.5 the same reading is ${haiku:g}/M — {ratio:g}x less. Pass "
            f'`model: "haiku"` for scan/search/summarize work, and keep the stronger model only '
            f"when the task needs judgment rather than reading.\n\n"
            f"Effort cannot be fixed here: the Agent tool has no effort parameter and "
            f"CLAUDE_CODE_EFFORT_LEVEL from settings.json env outranks agent frontmatter, so an "
            f"in-process subagent runs at the session's pinned level regardless. See effort-control.")
    elif not sm:
        headlines.append(
            f"read-heavy agent with no model — Haiku 4.5 reads at ${haiku:g}/MTok")
        warnings.append(
            f"This Agent call looks read-heavy but sets no `model`, so it inherits the default "
            f"subagent model. Haiku 4.5 reads at ${haiku:g}/M input tokens — the cheapest per "
            f'token the agent reads. Pass `model: "haiku"` for scan/search/summarize work, and '
            f"keep the stronger model only when the task needs judgment rather than reading.")

if not warnings:
    emit(QUIET); sys.exit(0)

text = "\n\n".join(warnings)
trace("; ".join(headlines))
emit({"continue": True, "suppressOutput": True,
      "systemMessage": "delegation-cost: " + "; ".join(headlines),
      "hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": text}})
PYEOF
)

python3 -c "$PY"
# python3 missing or crashed before emitting: fail open with a valid response.
if [ "$?" -ne 0 ]; then
    echo '{"continue": true, "suppressOutput": true}'
fi
exit 0
