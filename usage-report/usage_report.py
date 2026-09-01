#!/usr/bin/env python3
"""Usage Report — where your Claude Code spend actually goes, from local
transcripts. Zero Claude tokens. Read-only.

    usage_report.py [--since DAYS] [--out PATH] [--root DIR] [--quiet]

Compares interactive desktop-app vs terminal sessions per human turn and per
session, decomposes cost (cache reads / writes / output), prices long-idle
cache re-writes, audits delegation (Agent calls, explicit model params,
subagent model mix), tallies headless `claude -p` jobs by spawner, and shows a
week-over-week trend. Prices are Anthropic API list rates; subscription meters
weight differently, so use the ratios, not the dollars.
"""
from __future__ import annotations

import argparse
import collections
import datetime as dt
import os
import statistics as st
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from usage_scan import ROOT, classify, scan, sum_buckets  # noqa: E402

PRICE = {  # $/M input, $/M output — Anthropic list (2026-06)
    "fable": (10, 50), "mythos": (10, 50), "opus": (5, 25),
    "sonnet-5": (2, 10), "sonnet": (3, 15), "haiku": (1, 5),
}
UTC = dt.timezone.utc


def price(model):
    for key, p in PRICE.items():
        if key in model:
            return p
    return (0, 0)


def cost(model, b):
    pi, po = price(model)
    known = b["c5m"] + b["c1h"]
    writes = (b["c5m"] * 1.25 + b["c1h"] * 2.0 + max(0, b["cache_create"] - known) * 1.25) * pi
    return (b["input"] * pi + writes + b["cache_read"] * 0.1 * pi + b["output"] * po) / 1e6


def session_cost(s):
    return sum(cost(m, b) for m, b in s["main"].items()) + sum(cost(m, b) for m, b in s["sub"].items())


def fmt(n):
    n = float(n)
    return f"{n/1e6:.1f}M" if abs(n) >= 1e6 else (f"{n/1e3:.0f}K" if abs(n) >= 1e3 else f"{n:.0f}")


def med(xs):
    return st.median(xs) if xs else 0


def pct(a, b):
    return f"{100*a/b:.0f}%" if b else "n/a"


def in_window(s, start, end):
    return s["first_ts"] is not None and start <= s["first_ts"] < end


def attribute_teammates(sessions):
    """Return {lead_id: teammate_cost} by matching cwd prefix + time overlap."""
    leads = [s for s in sessions if classify(s).startswith("interactive") and s["human_turns"] > 0]
    out = collections.Counter()
    for t in (s for s in sessions if classify(s) == "teammate"):
        if not (t["first_ts"] and t["cwd"]):
            continue
        cands = [l for l in leads if l["cwd"] and l["first_ts"] and l["last_ts"]
                 and (t["cwd"].startswith(l["cwd"]) or l["cwd"].startswith(t["cwd"]))
                 and l["first_ts"] <= t["first_ts"] <= l["last_ts"] + dt.timedelta(minutes=5)]
        if cands:
            lead = max(cands, key=lambda l: l["first_ts"])
            out[lead["id"]] += session_cost(t)
    return out


def kpis(group, teammate_cost):
    """Aggregate one class of interactive sessions."""
    turns = sum(s["human_turns"] for s in group)
    main = sum_buckets(b for s in group for b in s["main"].values())
    sub = sum_buckets(b for s in group for b in s["sub"].values())
    main_c = sum(cost(m, b) for s in group for m, b in s["main"].items())
    sub_c = sum(cost(m, b) for s in group for m, b in s["sub"].items())
    team_c = sum(teammate_cost.get(s["id"], 0) for s in group)
    gt60 = sum_buckets(s["gap"]["gt60"] for s in group)
    calls = collections.Counter()
    for s in group:
        for m, b in s["main"].items():
            calls[m] += b["calls"]
    n = sum(calls.values()) or 1
    blend_in = sum(price(m)[0] * c for m, c in calls.items()) / n
    agents = [a for s in group for a in s["agent_calls"]]
    sub_by_model = collections.Counter()
    for s in group:
        for m, b in s["sub"].items():
            sub_by_model[m] += cost(m, b)
    prem = sum(v for m, v in sub_by_model.items() if "opus" in m or "fable" in m or "mythos" in m)
    per_sess = [session_cost(s) for s in group]
    comp = collections.Counter()
    for s in group:
        for m, b in s["main"].items():
            pi, po = price(m)
            comp["cache_read"] += b["cache_read"] * 0.1 * pi / 1e6
            comp["cache_write"] += (b["c5m"] * 1.25 + b["c1h"] * 2 + max(0, b["cache_create"] - b["c5m"] - b["c1h"]) * 1.25) * pi / 1e6
            comp["output"] += b["output"] * po / 1e6
            comp["input"] += b["input"] * pi / 1e6
    return dict(
        sessions=len(group), turns=turns, main_calls=main["calls"], sub_calls=sub["calls"],
        cost=main_c + sub_c + team_c, main_cost=main_c, sub_cost=sub_c, team_cost=team_c,
        cost_per_turn=(main_c + sub_c + team_c) / turns if turns else 0,
        calls_per_turn=main["calls"] / turns if turns else 0,
        prompt_per_call=sum(s["prompt_sum"] for s in group) / main["calls"] if main["calls"] else 0,
        out_per_turn=main["output"] / turns if turns else 0,
        cold_resumes=gt60["calls"], cold_cost=gt60["cache_create"] * 2 * blend_in / 1e6,
        cold_per_session=gt60["calls"] / len(group) if group else 0,
        agent_per_turn=len(agents) / turns if turns else 0,
        agent_model_pct=pct(sum(1 for a in agents if a.get("model")), len(agents)),
        premium_sub_share=pct(prem, sum(sub_by_model.values())),
        task_notifs=sum(s["task_notifications"] for s in group),
        compactions=sum(s["compactions"] for s in group),
        median_turns=med([s["human_turns"] for s in group]),
        median_cost=med(per_sess), mean_cost=st.mean(per_sess) if per_sess else 0,
        first_call=med([s["first_call_tokens"] for s in group if s["first_call_tokens"]]),
        efforts=dict(collections.Counter(e for s in group for e in s["efforts"])),
        modes=dict(collections.Counter(p for s in group for p in s["permission_modes"])),
        model_mix={m: c for m, c in calls.most_common(4)}, comp=comp,
        sub_by_model={m: round(v) for m, v in sub_by_model.most_common(4)},
    )


def render(sessions, since_days, now):
    start = now - dt.timedelta(days=since_days)
    win = [s for s in sessions.values() if in_window(s, start, now) and s["main_calls"] > 0]
    team_cost = attribute_teammates(win)
    groups = {c: [s for s in win if classify(s) == c and (c == "headless" or s["human_turns"] > 0)]
              for c in ("interactive-desktop", "interactive-cli", "headless")}
    k = {c: kpis(g, team_cost) for c, g in groups.items() if c != "headless"}
    lines = [f"# Claude Code usage report — last {since_days} days (to {now:%Y-%m-%d})", ""]
    lines.append(f"Sessions scanned: {len(win)} (desktop {len(groups['interactive-desktop'])}, "
                 f"terminal {len(groups['interactive-cli'])}, teammates {sum(1 for s in win if classify(s)=='teammate')}, "
                 f"headless {len(groups['headless'])}). Prices = API list; use ratios, not dollars.")
    lines += ["", "## Desktop app vs terminal (interactive sessions, teammate cost attributed to their lead)", "",
              "| metric | desktop | terminal |", "|---|---|---|"]
    rows = [("sessions / human turns", lambda x: f"{x['sessions']} / {x['turns']}"),
            ("$ per human turn", lambda x: f"${x['cost_per_turn']:.2f}"),
            ("API calls per turn", lambda x: f"{x['calls_per_turn']:.1f}"),
            ("prompt tokens per call", lambda x: fmt(x['prompt_per_call'])),
            ("output tokens per turn", lambda x: fmt(x['out_per_turn'])),
            ("$ per session (median / mean)", lambda x: f"${x['median_cost']:.2f} / ${x['mean_cost']:.2f}"),
            ("median turns per session", lambda x: f"{x['median_turns']:.0f}"),
            ("first-call prompt (system+tools+CLAUDE.md)", lambda x: fmt(x['first_call'])),
            ("resumes after >60 min idle (count, per session, $)", lambda x: f"{x['cold_resumes']}, {x['cold_per_session']:.2f}, ${x['cold_cost']:.0f}"),
            ("Agent calls per turn / with explicit model", lambda x: f"{x['agent_per_turn']:.2f} / {x['agent_model_pct']}"),
            ("delegation $ per turn (subagents + teammates)", lambda x: f"${(x['sub_cost']+x['team_cost'])/x['turns'] if x['turns'] else 0:.2f}"),
            ("share of subagent $ on opus/fable", lambda x: x['premium_sub_share']),
            ("background task-notification turns", lambda x: str(x['task_notifs'])),
            ("compactions", lambda x: str(x['compactions'])),
            ("effort values seen", lambda x: str(x['efforts'])),
            ("permission modes", lambda x: str(x['modes'])),
            ("main model calls", lambda x: str(x['model_mix'])),
            ("subagent $ by model", lambda x: str(x['sub_by_model']))]
    for label, f in rows:
        lines.append(f"| {label} | {f(k['interactive-desktop'])} | {f(k['interactive-cli'])} |")
    lines += ["", "## Where the main-thread dollars go", ""]
    for c, label in (("interactive-desktop", "desktop"), ("interactive-cli", "terminal")):
        comp = k[c]["comp"]; tot = sum(comp.values()) or 1
        lines.append(f"- {label}: " + ", ".join(f"{n} {pct(v, tot)}" for n, v in comp.most_common()) + f" (${tot:,.0f})")
    hl = groups["headless"]
    if hl:
        hc = sum(session_cost(s) for s in hl)
        spawners = collections.Counter(s["project"][:60] for s in hl)
        eff = collections.Counter(e for s in hl for e in s["efforts"])
        models = collections.Counter(m for s in hl for m in s["main"])
        lines += ["", "## Headless `claude -p` jobs (plugins, hooks, automation)", "",
                  f"- {len(hl)} jobs, ${hc:,.0f} total, ${hc/len(hl):.2f} each; effort {dict(eff)}; models {dict(models.most_common(3))}",
                  "- top spawners (transcript project dir): " + "; ".join(f"{p} ({n})" for p, n in spawners.most_common(3))]
    lines += ["", "## Week over week ($ per human turn, desktop / terminal; total $ incl. headless)", ""]
    for label, a, b in (("this week", now - dt.timedelta(days=7), now), ("previous week", now - dt.timedelta(days=14), now - dt.timedelta(days=7))):
        ws = [s for s in sessions.values() if in_window(s, a, b) and s["main_calls"] > 0]
        tc = attribute_teammates(ws)
        parts = []
        for c in ("interactive-desktop", "interactive-cli"):
            g = [s for s in ws if classify(s) == c and s["human_turns"] > 0]
            x = kpis(g, tc) if g else None
            parts.append(f"${x['cost_per_turn']:.2f} ({x['turns']} turns, {x['cold_resumes']} cold resumes)" if x else "—")
        lines.append(f"- {label}: {parts[0]} / {parts[1]}; total ${sum(session_cost(s) for s in ws):,.0f}")
    cal = [session_cost(s) / s["cost_state_usd"] for s in win if s.get("cost_state_usd") and s["cost_state_usd"] > 0.5]
    if cal:
        lines += ["", f"Calibration: this report / Claude Code's own `totalCostUSD` = {med(cal):.2f} (median over {len(cal)} sessions)."]
    lines += ["", "## Levers this data points at", ""] + levers(k, hl)
    return "\n".join(lines) + "\n"


def levers(k, headless):
    out = []
    d, c = k["interactive-desktop"], k["interactive-cli"]
    if "max" in d["efforts"] or "max" in c["efforts"]:
        out.append("- Effort `max` is pinned: it is inherited by subagents, teammates and headless jobs. `high`/`xhigh` cuts thinking *and* tool calls per turn.")
    for label, x in (("desktop", d), ("terminal", c)):
        if x["cold_per_session"] >= 0.3:
            out.append(f"- {label}: {x['cold_resumes']} resumes after >60 min idle cost ≈${x['cold_cost']:.0f} in full cache re-writes — let idle-autosave write the handoff and start fresh instead.")
    for label, x in (("desktop", d), ("terminal", c)):
        share = x["premium_sub_share"]
        if share not in ("n/a",) and int(share.rstrip("%")) >= 30:
            out.append(f"- {label}: {share} of subagent spend runs on opus/fable — default subagents to sonnet/haiku unless the task needs more.")
    if d["turns"] and c["turns"] and d["cost_per_turn"] > 1.5 * c["cost_per_turn"]:
        out.append(f"- Desktop turns cost {d['cost_per_turn']/c['cost_per_turn']:.1f}x terminal turns, driven by {d['calls_per_turn']:.0f} vs {c['calls_per_turn']:.0f} API calls per turn, not by prompt size ({fmt(d['prompt_per_call'])} vs {fmt(c['prompt_per_call'])} per call).")
    if headless:
        hc = sum(session_cost(s) for s in headless)
        if hc >= 25:
            out.append(f"- Headless jobs cost ${hc:,.0f} this window; route classifier-style jobs to a cheaper model / local endpoint and effort low.")
    return out or ["- Nothing stands out in this window."]


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--since", type=int, default=28, help="window in days (default 28)")
    ap.add_argument("--out", default=None, help="write the markdown report here (default ~/.claude/usage-reports/<date>.md)")
    ap.add_argument("--root", default=ROOT, help="transcript root (default ~/.claude/projects)")
    ap.add_argument("--quiet", action="store_true", help="print only the path of the written report")
    args = ap.parse_args(argv)
    now = dt.datetime.now(UTC)
    since = now - dt.timedelta(days=args.since + 1)
    sessions = scan(args.root, since=since)
    report = render(sessions, args.since, now)
    out = args.out or os.path.expanduser(f"~/.claude/usage-reports/{now:%Y-%m-%d}.md")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w") as fh:
        fh.write(report)
    print(out if args.quiet else report + f"\nSaved: {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
