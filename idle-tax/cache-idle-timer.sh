#!/bin/bash
# Cache Idle Timer — warns when the prompt cache has expired (or is about to).
#
# TTL-aware (v2). Claude Code sessions now normally run on Anthropic's 1-hour
# prompt-cache TTL; they drop to the 5-minute TTL when the account is in usage
# overage, and older/other setups may still be on 5 minutes. Instead of
# hardcoding either, this hook reads the LAST assistant message in the session
# transcript and uses its `usage.cache_creation` breakdown:
#
#   ephemeral_1h_input_tokens > 0  -> 1-hour TTL is in effect
#   otherwise                      -> assume the 5-minute TTL (conservative)
#
# It also measures idle time from that message's timestamp — i.e. from the last
# API call — not from your last prompt, so a long agentic turn is never
# mistaken for idle time. And it prices the re-cache from the real cached
# context size and the real model, so the number you see is your number.
#
# Cold-cache economics (Anthropic list prices):
#   warm hit          : 0.1x  input price
#   re-write, 5m TTL  : 1.25x input price   (12.5x a warm hit)
#   re-write, 1h TTL  : 2.0x  input price   (20x a warm hit)
#
# Output uses the documented hook contract for UserPromptSubmit:
#   hookSpecificOutput.additionalContext  -> what Claude sees this turn
#   systemMessage                         -> what YOU see (CLI and desktop app)
# (The pre-v2 top-level `additionalContext` field is not honored for this
# event, so the old warning never reached the model. See README.)
#
# Fallback: if the hook input has no transcript_path (older Claude Code), it
# falls back to the original per-prompt timestamp file and a 5-minute TTL.
#
# Config (env, e.g. settings.json "env" block):
#   CACHE_TTL_SECONDS    force a TTL instead of detecting it (300 or 3600)
#   CACHE_WARN_SECONDS   lead time before expiry to start warning
#                        (default: 900 for a 1h TTL, 60 for a 5m TTL)
#   IDLE_TAX_QUIET=1     omit the user-facing systemMessage (context only)
#
# Part of: claude-cost-helpers / idle-tax
# Companion to: The Economics of Claude Code, Part 1: The Idle Tax

set +e  # informational hook: never block a prompt

INPUT=$(cat 2>/dev/null || echo '{}')
STATE_DIR="${HOME}/.claude/.session-state"
SESSIONS_DIR="${HOME}/.claude/sessions"
mkdir -p "$STATE_DIR" 2>/dev/null

INPUT="$INPUT" STATE_DIR="$STATE_DIR" SESSIONS_DIR="$SESSIONS_DIR" python3 - <<'PYEOF'
import glob, json, os, sys, time
from datetime import datetime, timezone

raw = os.environ.get("INPUT", "{}")
try:
    d = json.loads(raw) if raw.strip() else {}
except Exception:
    d = {}
sid = d.get("session_id") or d.get("sessionId") or "unknown"
transcript = d.get("transcript_path") or ""
state_dir = os.environ["STATE_DIR"]
sessions_dir = os.environ["SESSIONS_DIR"]
now = time.time()

PRICE_IN = [  # $/M input tokens, matched by substring, first hit wins
    ("fable", 10.0), ("mythos", 10.0), ("opus", 5.0),
    ("sonnet-5", 2.0), ("sonnet", 3.0), ("haiku", 1.0),
]


def price_for(model):
    for key, p in PRICE_IN:
        if key in (model or ""):
            return p
    return 5.0


def emit(obj):
    sys.stdout.write(json.dumps(obj) + "\n")


def silent(note):
    sys.stderr.write(f"[idle-tax] {note}\n")
    emit({"continue": True, "suppressOutput": True})


def last_assistant(path, max_scan=16 * 1024 * 1024):
    """Return (timestamp_epoch, model, usage) of the last main-thread assistant
    message, scanning the transcript backwards in blocks."""
    try:
        size = os.path.getsize(path)
    except OSError:
        return None
    block = 256 * 1024
    with open(path, "rb") as fh:
        pos = size
        buf = b""
        scanned = 0
        while pos > 0 and scanned < max_scan:
            step = min(block, pos)
            pos -= step
            fh.seek(pos)
            buf = fh.read(step) + buf
            scanned += step
            lines = buf.split(b"\n")
            buf = lines[0]  # possibly partial first line; keep for next round
            for line in reversed(lines[1:]):
                if b'assistant' not in line or b'usage' not in line:
                    continue
                try:
                    obj = json.loads(line)
                except Exception:
                    continue
                if obj.get("isSidechain"):
                    continue
                msg = obj.get("message") or {}
                usage = msg.get("usage")
                if not usage:
                    continue
                ts = obj.get("timestamp")
                try:
                    epoch = datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
                except Exception:
                    epoch = None
                return epoch, msg.get("model") or "", usage
    return None


def fmt_tokens(n):
    return f"{n/1e6:.1f}M" if n >= 1e6 else f"{n/1e3:.0f}K"


def fmt_gap(sec):
    if sec < 60:
        return f"{int(sec)}s"
    m = int(sec // 60)
    return f"{m//60}h {m%60:02d}m" if m >= 60 else f"{m} min"


def fmt_ratio(r):
    return f"{r:g}x"


def newest_handoff(sid):
    """Prefer this session's idle-autosave note, else the newest handoff."""
    own = sorted(glob.glob(os.path.join(sessions_dir, f"*-idle-autosave-{sid[:8]}-session.md")),
                 key=os.path.getmtime, reverse=True)
    any_ = sorted(glob.glob(os.path.join(sessions_dir, "*-session.md")),
                  key=os.path.getmtime, reverse=True)
    for cand in own + any_:
        age = now - os.path.getmtime(cand)
        return cand, age
    return None, None


# ---- Gap + TTL detection -----------------------------------------------------
activity_file = os.path.join(state_dir, f"{sid}.last-activity")
prev_prompt = None
try:
    prev_prompt = float(open(activity_file).read().strip())
except Exception:
    pass
try:
    with open(activity_file, "w") as fh:
        fh.write(str(int(now)))
except OSError:
    pass

info = last_assistant(transcript) if transcript and os.path.exists(transcript) else None
if info and info[0]:
    last_epoch, model, usage = info
    cc = usage.get("cache_creation") or {}
    c1h = cc.get("ephemeral_1h_input_tokens") or 0
    ttl = 3600 if c1h > 0 else 300
    ctx = ((usage.get("cache_read_input_tokens") or 0)
           + (usage.get("cache_creation_input_tokens") or 0)
           + (usage.get("input_tokens") or 0))
    gap = now - last_epoch
    source = "transcript"
else:
    if prev_prompt is None:
        silent("first prompt, recording timestamp")
        sys.exit(0)
    model, ctx, ttl = "", 0, 300
    gap = now - prev_prompt
    source = "prompt-timestamp fallback (no transcript_path)"

forced = os.environ.get("CACHE_TTL_SECONDS")
if forced and forced.isdigit():
    ttl = int(forced)
lead_default = 900 if ttl >= 3600 else 60
try:
    lead = int(os.environ.get("CACHE_WARN_SECONDS") or lead_default)
except ValueError:
    lead = lead_default
warn_at = max(0, ttl - lead)

if gap < warn_at:
    silent(f"cache warm ({int(gap)}s idle of {ttl}s TTL, via {source})")
    sys.exit(0)

# ---- Pricing -----------------------------------------------------------------
p = price_for(model)
write_mult = 2.0 if ttl >= 3600 else 1.25
warm = ctx * p * 0.1 / 1e6
cold = ctx * p * write_mult / 1e6
ratio = write_mult / 0.1
ttl_label = "1-hour" if ttl >= 3600 else "5-minute"
ctx_label = f"~{fmt_tokens(ctx)} cached tokens" if ctx else "the full conversation prefix"
model_label = model or "current model"
handoff, handoff_age = newest_handoff(sid)
handoff_line = (f"Latest handoff note: {handoff} (saved {fmt_gap(handoff_age)} ago)"
                if handoff else "No handoff note exists yet.")

quiet = os.environ.get("IDLE_TAX_QUIET") == "1"

if gap >= ttl:
    cost_line = (f"re-writes {ctx_label} for {model_label} at {write_mult}x input price: "
                 f"about ${cold:.2f} vs ${warm:.2f} for a warm hit ({fmt_ratio(ratio)})."
                 if ctx else f"re-caches the full prefix at {write_mult}x input price ({fmt_ratio(ratio)} a warm hit).")
    head = f"CACHE EXPIRED ({fmt_gap(gap)} idle, {ttl_label} TTL)"
    context = (
        f"{head}: this prompt {cost_line}\n"
        f"{handoff_line}\n"
        "Options: (1) continue here and accept the re-cache; "
        "(2) if the context is stale or large, /save-session (or use the handoff above) "
        "and continue in a fresh session with /resume-session; "
        "(3) next time, /save-session before stepping away for more than the TTL.\n"
        "This is informational — the prompt proceeds normally."
    )
    system_msg = (f"idle-tax: {head} — this turn re-writes {ctx_label} "
                  f"(≈${cold:.2f}, {fmt_ratio(ratio)} a warm hit). "
                  + ("Handoff available: /resume-session in a fresh session is free."
                     if handoff else "No handoff note yet — /save-session if you plan to restart."))
    sys.stderr.write(f"[idle-tax] {head}\n")
else:
    left = ttl - gap
    head = f"CACHE EXPIRES IN {fmt_gap(left)} ({fmt_gap(gap)} idle of {ttl_label} TTL)"
    context = (
        f"{head}. {ctx_label} for {model_label} would cost about ${cold:.2f} to re-warm "
        f"(vs ${warm:.2f} warm, {fmt_ratio(ratio)}).\n"
        f"{handoff_line}\n"
        "If you are about to step away, /save-session now (or rely on idle-autosave) "
        "so starting fresh later is free."
    )
    system_msg = f"idle-tax: {head} — ${cold:.2f} to re-warm {ctx_label}."
    sys.stderr.write(f"[idle-tax] {head}\n")

out = {
    "continue": True,
    "suppressOutput": True,
    "hookSpecificOutput": {
        "hookEventName": "UserPromptSubmit",
        "additionalContext": context,
    },
}
if not quiet:
    out["systemMessage"] = system_msg
emit(out)
PYEOF

# python3 missing or crashed: fail open with a silent, valid response.
if [ "${PIPESTATUS[0]:-0}" -ne 0 ]; then
    echo '{"continue": true, "suppressOutput": true}'
fi
exit 0
