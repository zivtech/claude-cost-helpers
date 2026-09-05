#!/usr/bin/env python3
"""Delegation report: what carrying this session's agent results costs, priced
for the model and cache TTL the session is actually on. Zero Claude tokens.

Backs the /delegation-report slash command. Reads two local files:

  ~/.claude/.session-state/<sid>.delegation-agents
      written by delegation-result-monitor.sh: one "tokens<TAB>time" line per
      agent result (tokens estimated at ~4 chars each)
  ~/.claude/projects/*/<sid>.jsonl
      the session transcript; its LAST main-thread assistant message gives the
      model, the cache TTL in effect (usage.cache_creation.ephemeral_1h_input_tokens
      > 0 -> 1-hour, else 5-minute) and the cached prefix size

Pricing (Anthropic list, September 2026): input $/MTok by model family; warm
cache reads at 0.1x input (0.025x on Claude Fable/Mythos 5.1); cache writes at
2x input on the 1-hour TTL, 1.25x on the 5-minute one. Same table as the hooks.

v1 of the slash command asked Claude to multiply by a hardcoded $1.50/MTok
"warm" and a made-up $5/MTok "blended" rate: Opus-4-era numbers, wrong by 4x
in either direction on current models, and computed in-context every time.

Usage: delegation_report.py [--session SID] [--horizon N]
                            [--state-dir DIR] [--transcript PATH]
                            [--model ID] [--ttl SECONDS]
"""
import argparse
import glob
import json
import os
import sys
from datetime import datetime

PRICE_IN = [  # $/M input tokens, matched by substring, first hit wins
    ("fable", 10.0), ("mythos", 10.0), ("opus", 5.0),
    ("sonnet-5", 2.0), ("sonnet", 3.0), ("haiku", 1.0),
]
BIG_RESULT = 5000  # tokens; matches the hook's per-result threshold


def price_for(model):
    for key, p in PRICE_IN:
        if key in (model or ""):
            return p
    return 5.0


def read_mult(model):
    m = model or ""
    return 0.025 if ("fable-5-1" in m or "mythos-5-1" in m) else 0.1


def last_assistant(path, max_scan=16 * 1024 * 1024):
    """(timestamp_epoch, model, usage) of the last main-thread assistant
    message, scanning the transcript backwards in blocks."""
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


def fmt_tokens(n):
    return f"{n/1e6:.1f}M" if n >= 1e6 else f"{n/1e3:.0f}K"


def money(x):
    if x >= 0.1:
        return f"${x:.2f}"
    if x >= 0.01:
        return f"${x:.3f}"
    return f"${x:.4f}"


def read_results(path):
    rows = []
    with open(path) as fh:
        for line in fh:
            parts = line.rstrip("\n").split("\t")
            if parts and parts[0].strip().isdigit():
                rows.append((int(parts[0]), parts[1] if len(parts) > 1 else ""))
    return rows


def find_state_file(state_dir, sid):
    if sid:
        p = os.path.join(state_dir, f"{sid}.delegation-agents")
        return p if os.path.exists(p) else None
    cands = glob.glob(os.path.join(state_dir, "*.delegation-agents"))
    return max(cands, key=os.path.getmtime) if cands else None


def find_transcript(sid):
    hits = glob.glob(os.path.expanduser(f"~/.claude/projects/*/{sid}.jsonl"))
    return max(hits, key=os.path.getmtime) if hits else None


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--session", help="session id (default: newest *.delegation-agents file)")
    ap.add_argument("--horizon", type=int, default=20, help="API calls to project the carrying cost over (default 20)")
    ap.add_argument("--state-dir", default=os.path.expanduser("~/.claude/.session-state"))
    ap.add_argument("--transcript", help="transcript path (default: ~/.claude/projects/*/<sid>.jsonl)")
    ap.add_argument("--model", help="override the model read from the transcript")
    ap.add_argument("--ttl", type=int, help="override the cache TTL in seconds (3600 or 300)")
    a = ap.parse_args()

    sf = find_state_file(os.path.expanduser(a.state_dir), a.session)
    rows = read_results(sf) if sf else []
    if not rows:
        print("No delegation results tracked in this session.")
        return 0
    sid = os.path.basename(sf)[: -len(".delegation-agents")]
    total = sum(t for t, _ in rows)
    big = sum(1 for t, _ in rows if t >= BIG_RESULT)

    transcript = a.transcript or find_transcript(sid)
    info = last_assistant(transcript) if transcript and os.path.exists(transcript) else None
    model, ttl, ctx = a.model, a.ttl, 0
    if info:
        _, t_model, usage = info
        model = model or t_model
        cc = usage.get("cache_creation") or {}
        ttl = ttl or (3600 if (cc.get("ephemeral_1h_input_tokens") or 0) > 0 else 300)
        ctx = ((usage.get("cache_read_input_tokens") or 0)
               + (usage.get("cache_creation_input_tokens") or 0)
               + (usage.get("input_tokens") or 0))

    out = []
    if not (model and ttl):
        out.append(f"## Delegation Report — session {sid[:8]} (unpriced)")
        out.append("")
        out.append("| # | Time | Result size |")
        out.append("|---|------|-------------|")
        for i, (t, when) in enumerate(rows, 1):
            out.append(f"| {i} | {when} | ~{fmt_tokens(t)} tokens |")
        out.append("")
        out.append(f"**Total:** ~{fmt_tokens(total)} tokens from {len(rows)} agent results"
                   + (f", {big} of them over {BIG_RESULT//1000}K." if big else "."))
        out.append("Pricing needs the session transcript and none was found for this session; "
                   "re-run with --model <id> --ttl 3600|300 to price by hand.")
        print("\n".join(out))
        return 0

    p, rm = price_for(model), read_mult(model)
    wm = 2.0 if ttl >= 3600 else 1.25
    ttl_label = "1-hour" if ttl >= 3600 else "5-minute"
    per_call = total * p * rm / 1e6
    ratio = wm / rm
    cold_share = total * p * wm / 1e6
    share = (total / ctx) if ctx else None

    out.append(f"## Delegation Report — {model}, {ttl_label} TTL")
    out.append("")
    out.append("| # | Time | Result size | Warm read per API call |")
    out.append("|---|------|-------------|------------------------|")
    for i, (t, when) in enumerate(rows, 1):
        out.append(f"| {i} | {when} | ~{fmt_tokens(t)} tokens | {money(t * p * rm / 1e6)} |")
    out.append("")
    total_line = f"**Total:** ~{fmt_tokens(total)} tokens from {len(rows)} agent results"
    if big:
        total_line += f", {big} of them over {BIG_RESULT//1000}K"
    if share is not None:
        total_line += f" — {share*100:.0f}% of the ~{fmt_tokens(ctx)}-token cached prefix"
    out.append(total_line + ".")
    out.append(f"**Warm carrying cost:** {money(per_call)} per API call (cache read at {rm:g}x input), "
               f"~{money(per_call * a.horizon)} over the next {a.horizon} API calls. "
               "Every tool call is a call, not just every message.")
    if ctx:
        out.append(f"**Cold exposure:** if the cache lapses once (an agent or an idle gap outlasting the {ttl_label} TTL), "
                   f"the whole prefix re-writes for {money(ctx * p * wm / 1e6)}; these results' share is "
                   f"{money(cold_share)}, {ratio:g}x their warm read ({wm:g}x input).")
    else:
        out.append(f"**Cold exposure:** if the cache lapses once (an agent or an idle gap outlasting the {ttl_label} TTL), "
                   f"these results re-write for {money(cold_share)}, {ratio:g}x their warm read ({wm:g}x input).")
    out.append("")
    if share is not None and share < 0.10 and per_call < 0.01:
        out.append(f"**Verdict:** delegation is not your tax here: {share*100:.0f}% of the prefix at {money(per_call)} per call. "
                   f"If this session feels expensive, it is the other {100 - share*100:.0f}%: /save-session or /split "
                   "for context size, not for agent results.")
    elif total >= 50000 or (share is not None and share >= 0.25):
        out.append("**Verdict:** agent results are a heavy share of what every call re-reads. Constrain the next agents "
                   "('report in under 200 words', or write findings to a file and return a summary) and /save-session "
                   "once you have synthesized what they returned.")
    else:
        out.append("**Verdict:** moderate. Results over 5K tokens benefit most from 'report in under 200 words' "
                   "or writing findings to a file and returning a summary.")
    print("\n".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
