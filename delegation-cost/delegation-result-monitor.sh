#!/bin/bash
# Delegation Result Monitor — warns when subagent results inflate context,
# priced for the model and cache TTL the session is actually on.
#
# When a subagent finishes, its result lands in the parent session permanently
# and is re-read on every subsequent API call. The subagent's own context is
# disposable. Its result is not. This hook tracks the accumulation and warns on:
#
#   - Per-result size: one agent result over 5,000 estimated tokens (over
#     8,000: "have it write to a file"), with its warm price per call.
#   - Cumulative cost: the projected warm carrying cost of ALL agent results
#     over the next N API calls (default 20) crosses $0.25, then $1, then $3.
#     Dollar thresholds, not token thresholds: the same tokens cost 4x less to
#     carry on Fable 5.1 (0.025x reads) than on Fable 5 (0.1x), so a token
#     threshold that is right for one model is noise or silence on the other.
#     Advice is routed by the results' share of the cached prefix: a large
#     share means "constrain the agents"; a small share means "the rest of the
#     prefix is the bigger lever".
#   - Cache cooling: the agent ran long enough that the parent's prompt cache
#     expired (or came within the lead time of expiring). See the block below.
#   Without a transcript (no model, no TTL) the cumulative check falls back to
#   raw token thresholds (20K/50K/100K) with unpriced wording.
#
# v1 (to September 2026) asserted conclusions in prose: "the delegation tax
# exceeds the delegation benefit", "a fresh session would save real money",
# "3 agents is a lot of delegation weight". None of them computed anything; on
# Fable 5.1 the first two were false at the thresholds that fired them and the
# third fired on every parallel fan-out. Prices change and the math improves;
# every number in a message here is computed from the price table below, and
# a message never claims more than its number supports.
#
# Pricing (Anthropic list, 2026-06; keep identical across helpers, enforced by
# ../pricing-parity.sh): input $/MTok by model family; cache reads at 0.1x
# input (0.025x on Fable/Mythos 5.1); cache writes at 2x input on the 1-hour
# TTL, 1.25x on the 5-minute one.
#
# Output (documented PostToolUse contract): hookSpecificOutput.additionalContext
# for Claude, a one-line systemMessage for you, suppressOutput on clean runs.
#
# Config (env, e.g. settings.json "env" block):
#   CLAUDE_DELEGATION_THRESHOLD              per-result tokens (5000)
#   CLAUDE_DELEGATION_FILE_THRESHOLD         per-result "write to a file" (8000)
#   CLAUDE_DELEGATION_COST_THRESHOLDS        dollars over the horizon (0.25,1,3)
#   CLAUDE_DELEGATION_HORIZON                API calls to project over (20)
#   CLAUDE_DELEGATION_CUMULATIVE_THRESHOLDS  unpriced fallback tokens (20000,50000,100000)
#   CACHE_TTL_SECONDS / CACHE_WARN_SECONDS   as in idle-tax (see below)
#
# Part of: claude-cost-helpers / delegation-cost
# Companion to: The Economics of Claude Code, Part 6: The Delegation Tax

set +e  # informational hook: never block

STATE_DIR="${HOME}/.claude/.session-state"
mkdir -p "$STATE_DIR" 2>/dev/null

# The hook's stdin (the PostToolUse JSON, possibly hundreds of KB of agent
# result) flows straight into python via stdin — never through an env var or
# argv, which cap out around 1 MB and would fail silently on a big result.
PY=$(cat <<'PYEOF'
import json, os, sys, time
from datetime import datetime

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
    sys.stderr.write(f"[delegation-cost] {note}\n")


def env_int(name, default):
    try:
        return int(os.environ.get(name) or default)
    except ValueError:
        return default


def env_list(name, default, cast):
    raw = os.environ.get(name)
    if not raw:
        return default
    try:
        return [cast(x) for x in raw.split(",") if x.strip()]
    except ValueError:
        return default


def fmt_tokens(n):
    return f"{n/1e6:.1f}M" if n >= 1e6 else f"{n/1e3:.0f}K"


def fmt_gap(sec):
    if sec < 60:
        return f"{int(sec)}s"
    m = int(sec // 60)
    return f"{m//60}h {m%60:02d}m" if m >= 60 else f"{m} min"


def money(x):
    if x >= 0.1:
        return f"${x:.2f}"
    if x >= 0.01:
        return f"${x:.3f}"
    return f"${x:.4f}"


def plural(n, word):
    return f"{n} {word}{'' if n == 1 else 's'}"


def last_assistant(path, max_scan=16 * 1024 * 1024):
    """(timestamp_epoch, model, usage) of the last main-thread assistant
    message — the row that dispatched this agent — scanning backwards in blocks."""
    try:
        size = os.path.getsize(path)
    except OSError:
        return None
    block = 256 * 1024
    with open(path, "rb") as fh:
        pos, buf, scanned = size, b"", 0
        while pos > 0 and scanned < max_scan:
            step = min(block, pos)
            pos -= step
            fh.seek(pos)
            buf = fh.read(step) + buf
            scanned += step
            lines = buf.split(b"\n")
            buf = lines[0]
            for line in reversed(lines[1:]):
                if b"assistant" not in line or b"usage" not in line:
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


def read_int(path):
    try:
        with open(path) as fh:
            v = fh.read().strip()
        return int(v) if v.isdigit() else 0
    except OSError:
        return 0


def main():
    try:
        d = json.loads(sys.stdin.read() or "{}")
    except Exception:
        d = {}
    sid = d.get("session_id") or d.get("sessionId") or "unknown"
    transcript = d.get("transcript_path") or ""
    tr = d.get("tool_response", d.get("tool_result", d.get("tool_output", "")))
    if isinstance(tr, (dict, list)):
        tr = json.dumps(tr)
    elif not isinstance(tr, str):
        tr = str(tr) if tr else ""
    if not tr:
        emit({"continue": True, "suppressOutput": True})
        return
    state_dir = os.environ["STATE_DIR"]
    now = time.time()
    call_tokens = len(tr) // 4  # ~4 chars per token

    # ---- State: cumulative total, per-agent log, once-only markers ----------
    def sf(suffix):
        return os.path.join(state_dir, f"{sid}.delegation-{suffix}")
    cumulative = read_int(sf("tokens"))
    new_cumulative = cumulative + call_tokens
    try:
        with open(sf("tokens"), "w") as fh:
            fh.write(str(new_cumulative))
        with open(sf("agents"), "a") as fh:
            fh.write(f"{call_tokens}\t{time.strftime('%H:%M:%S')}\n")
    except OSError:
        pass
    try:
        with open(sf("agents")) as fh:
            agent_count = sum(1 for _ in fh)
    except OSError:
        agent_count = 1
    warned = set()
    try:
        with open(sf("warned-at")) as fh:
            warned = {x for x in fh.read().replace("\n", ",").split(",") if x}
    except OSError:
        pass

    # ---- Dispatch row: model, TTL in effect, prefix size, last API call ------
    forced_ttl = os.environ.get("CACHE_TTL_SECONDS")
    forced_ttl = int(forced_ttl) if forced_ttl and forced_ttl.isdigit() else None
    info = last_assistant(transcript) if transcript and os.path.exists(transcript) else None
    model, ttl, ctx, last_epoch, gap, gap_source = "", None, 0, None, None, None
    if info and info[0]:
        last_epoch, model, usage = info
        cc = usage.get("cache_creation") or {}
        ttl = 3600 if (cc.get("ephemeral_1h_input_tokens") or 0) > 0 else 300
        ctx = ((usage.get("cache_read_input_tokens") or 0)
               + (usage.get("cache_creation_input_tokens") or 0)
               + (usage.get("input_tokens") or 0))
        gap, gap_source = now - last_epoch, "transcript"
    elif forced_ttl:
        # No transcript: idle-tax's prompt timestamp bounds the gap from above,
        # and that is only meaningful when the caller has told us the TTL.
        try:
            with open(os.path.join(state_dir, f"{sid}.last-activity")) as fh:
                last_epoch = float(fh.read().strip())
            gap, gap_source = now - last_epoch, "prompt-timestamp fallback"
        except Exception:
            trace("no transcript and no .last-activity; skipping cache check")
    else:
        trace("no transcript_path; cumulative check unpriced, cache check needs CACHE_TTL_SECONDS")
    if forced_ttl:
        ttl = forced_ttl
    priced = bool(model and ttl)   # model known -> everything below is priced
    p, rm = price_for(model), read_mult(model)  # defaults (opus price, 0.1x) when model unknown
    warnings = []

    # ---- 1. Cache cooling ----------------------------------------------------
    # A foreground Agent blocks the parent, so the parent's cache entry ages for
    # the whole run; if the run outlasts the TTL, the call that consumes this
    # result re-writes the entire prefix. TTL-aware: the dispatch row's
    # usage.cache_creation says which TTL is in effect, and the gap is measured
    # from ITS timestamp (the parent's last API call), not from your last
    # prompt. v1 hardcoded 240 s against idle-tax's prompt timestamp; on the
    # 1-hour TTL that flagged a 17-minute agent as "cache went cold". The TTL
    # clock runs from the START of that request (generation time counts), so
    # the true cache age is a little larger than this gap — immaterial next to
    # the 15-minute lead on the 1-hour TTL. One warning per dispatch row:
    # parallel agents from one turn share a row, so the first result to cross a
    # level (near/expired) warns and the rest stay quiet.
    if gap is not None and ttl:
        lead_default = 900 if ttl >= 3600 else 60
        lead = env_int("CACHE_WARN_SECONDS", lead_default)
        if gap < max(0, ttl - lead):
            trace(f"cache warm ({int(gap)}s agent run of {ttl}s TTL, via {gap_source})")
        else:
            level = 2 if gap >= ttl else 1
            dedupe = sf("cache-warned")
            skip = False
            try:
                with open(dedupe) as fh:
                    prev_epoch, prev_level = fh.read().split()
                skip = int(float(prev_epoch)) == int(last_epoch) and int(prev_level) >= level
            except Exception:
                pass
            if skip:
                trace("already warned for this dispatch")
            else:
                try:
                    with open(dedupe, "w") as fh:
                        fh.write(f"{int(last_epoch)} {level}")
                except OSError:
                    pass
                wm = write_mult(ttl)
                ratio = wm / rm
                ttl_label = "1-hour" if ttl >= 3600 else "5-minute"
                if ctx:
                    # Two decimals here, as in idle-tax: the cold figure is the point.
                    rewrite = (f"re-writes ~{fmt_tokens(ctx)} cached tokens, about "
                               f"${ctx * p * wm / 1e6:.2f} vs ${ctx * p * rm / 1e6:.2f} warm ({ratio:g}x)")
                else:
                    rewrite = f"re-writes the full prefix ({ratio:g}x a warm hit)"
                price_note = f"Cache writes cost {wm:g}x input price on the {ttl_label} TTL."
                if level == 2:
                    head = f"PARENT CACHE EXPIRED while this agent ran ({fmt_gap(gap)} of a {ttl_label} TTL)"
                    warnings.append(
                        f"{head}: the call that consumes this result {rewrite}.\n"
                        f"{price_note} Nothing to save on this one. Next time an agent may outlast the TTL: "
                        "(1) dispatch it with run_in_background so the parent keeps making calls and its cache stays warm, "
                        "(2) split the work into shorter agents, or (3) /save-session before dispatching so resuming fresh is free.")
                else:
                    head = (f"PARENT CACHE CAME WITHIN {fmt_gap(ttl - gap)} OF EXPIRING while this agent ran "
                            f"({fmt_gap(gap)} of a {ttl_label} TTL)")
                    warnings.append(
                        f"{head}. An agent that outlasts the TTL {rewrite}.\n"
                        f"{price_note} This call refreshes the cache. For agents that may run this long, "
                        "use run_in_background so the parent keeps its cache warm, or split the work into shorter agents.")

    # ---- 2. Per-result size --------------------------------------------------
    per_thr = env_int("CLAUDE_DELEGATION_THRESHOLD", 5000)
    file_thr = env_int("CLAUDE_DELEGATION_FILE_THRESHOLD", 8000)
    if call_tokens >= per_thr:
        k = call_tokens // 1000
        price_clause = f" (~{money(call_tokens * p * rm / 1e6)} per API call on {model}, warm)" if priced else ""
        if call_tokens >= file_thr:
            warnings.append(
                f"That agent returned ~{k}K tokens{price_clause} — too large for inline results. Next time, ask the agent "
                "to write its findings to a file and return only a summary. This keeps the delegation benefit without "
                "the delegation tax.")
        else:
            warnings.append(
                f"That agent returned ~{k}K tokens now sitting in context{price_clause}. Every future API call re-reads it. "
                "Consider: (1) tighter prompt constraints ('report in under 200 words'), (2) writing findings to a file "
                "instead of returning inline, (3) splitting the session after synthesizing.")

    # ---- 3. Cumulative carrying cost -----------------------------------------
    # Priced: the warm read of every agent result so far, per API call, projected
    # over a horizon; gated in dollars so the same tokens fire at different
    # points on models with different read prices. Once per threshold.
    if priced:
        horizon = env_int("CLAUDE_DELEGATION_HORIZON", 20)
        per_call = new_cumulative * p * rm / 1e6
        proj = per_call * horizon
        crossed = [t for t in env_list("CLAUDE_DELEGATION_COST_THRESHOLDS", [0.25, 1.0, 3.0], float)
                   if f"usd{t:g}" not in warned and proj >= t]
        if crossed:
            warned.update(f"usd{t:g}" for t in crossed)
            share = (new_cumulative / ctx) if ctx else None
            share_txt = f", {share*100:.0f}% of the ~{fmt_tokens(ctx)}-token prefix" if share is not None else ""
            cold = new_cumulative * p * write_mult(ttl) / 1e6
            head = (f"Delegation results: ~{fmt_tokens(new_cumulative)} tokens from {plural(agent_count, 'agent')}{share_txt}. "
                    f"Carrying them costs ~{money(per_call)} per API call on {model} (warm), ~{money(proj)} over the next "
                    f"{horizon} calls; a cold re-write of them is {money(cold)}.")
            if share is not None and share < 0.25:
                advice = (f"Trimming them saves at most that; the other {100 - share*100:.0f}% of the prefix is the bigger "
                          "lever (/save-session or /split for context size).")
            else:
                advice = ("They are a leading share of what every call re-reads: cap the next agents' output "
                          "('report in under 200 words') or have them write findings to a file and return a summary.")
            warnings.append(head + " " + advice)
    else:
        crossed = [t for t in env_list("CLAUDE_DELEGATION_CUMULATIVE_THRESHOLDS", [20000, 50000, 100000], int)
                   if f"tok{t}" not in warned and new_cumulative >= t]
        if crossed:
            warned.update(f"tok{t}" for t in crossed)
            warnings.append(
                f"Delegation results: ~{fmt_tokens(new_cumulative)} tokens from {plural(agent_count, 'agent')} "
                "(unpriced: no transcript to read the model and TTL from). Every API call re-reads them; cap agent "
                "output ('report in under 200 words') or have agents write findings to files.")
    if warned:
        try:
            with open(sf("warned-at"), "w") as fh:
                fh.write(",".join(sorted(warned)))
        except OSError:
            pass

    # ---- Output --------------------------------------------------------------
    if warnings:
        text = "\n\n".join(warnings)
        emit({"continue": True, "suppressOutput": True,
              "systemMessage": "delegation-cost: " + text.splitlines()[0][:200],
              "hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": text}})
    else:
        emit({"continue": True, "suppressOutput": True})


try:
    main()
except Exception as exc:  # fail open, never block
    trace(f"error: {exc!r}")
    emit({"continue": True, "suppressOutput": True})
PYEOF
)

STATE_DIR="$STATE_DIR" python3 -c "$PY"
# python3 missing or crashed before emitting: fail open with a valid response.
if [ "$?" -ne 0 ]; then
    echo '{"continue": true, "suppressOutput": true}'
fi
exit 0
