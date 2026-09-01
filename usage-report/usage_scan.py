#!/usr/bin/env python3
"""Scan Claude Code transcripts (~/.claude/projects/**/*.jsonl) into per-session
usage records. Pure stdlib; read-only; no Claude tokens.

Each transcript line carries `entrypoint` ("cli", "claude-desktop", "sdk-cli"),
and each assistant line carries `message.usage` with the four billable
counters plus a cache-TTL breakdown. Subagent transcripts live under
`<project>/<sessionId>/…/*.jsonl` and are folded into their parent session.

Usage is de-duplicated by `message.id` (one API response is written as one
line per content block, all carrying the same usage).
"""
from __future__ import annotations

import collections
import datetime as dt
import json
import os
import re

ROOT = os.path.expanduser("~/.claude/projects")
UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
SKIP_DIRS = {"vercel-plugin", "memory"}
GAP_5M, GAP_60M = 300, 3600


def bucket():
    return dict(calls=0, input=0, cache_create=0, cache_read=0, output=0, c5m=0, c1h=0)


def add_usage(b, u):
    b["calls"] += 1
    b["input"] += u.get("input_tokens") or 0
    b["cache_create"] += u.get("cache_creation_input_tokens") or 0
    b["cache_read"] += u.get("cache_read_input_tokens") or 0
    b["output"] += u.get("output_tokens") or 0
    cc = u.get("cache_creation") or {}
    b["c5m"] += cc.get("ephemeral_5m_input_tokens") or 0
    b["c1h"] += cc.get("ephemeral_1h_input_tokens") or 0


def sum_buckets(bs):
    t = bucket()
    for b in bs:
        for k in t:
            t[k] += b.get(k, 0)
    return t


def new_session(sid, project):
    return dict(
        id=sid, project=project, entrypoint=None, cwd=None, versions=set(),
        first_ts=None, last_ts=None, permission_modes=set(), efforts=set(),
        main=collections.defaultdict(bucket), sub=collections.defaultdict(bucket),
        human_turns=0, teammate_msgs=0, task_notifications=0, compactions=0,
        agent_calls=[], seen_ids=set(), prompt_sum=0, first_call_tokens=None,
        gap=dict(lt5=bucket(), b5_60=bucket(), gt60=bucket(), first=bucket()),
        _last_assistant=None, _last_user=None, cost_state_usd=None,
    )


def parse_ts(s):
    try:
        return dt.datetime.fromisoformat(s.replace("Z", "+00:00"))
    except Exception:
        return None


def user_text(msg):
    c = (msg or {}).get("content")
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        if any(isinstance(x, dict) and x.get("type") == "tool_result" for x in c):
            return None
        return " ".join(x.get("text", "") for x in c if isinstance(x, dict) and x.get("type") == "text")
    return None


def handle_user(s, d, ts, is_sub):
    if is_sub or d.get("isSidechain"):
        return
    if d.get("isCompactSummary"):
        s["compactions"] += 1
        return
    if d.get("isMeta"):
        return
    text = user_text(d.get("message"))
    if not text or not text.strip():
        return
    if text.startswith("<teammate-message"):
        s["teammate_msgs"] += 1
    elif text.startswith("<task-notification"):
        s["task_notifications"] += 1
    elif not text.startswith("<"):
        s["human_turns"] += 1
    if ts:
        s["_last_user"] = ts


def handle_assistant(s, d, ts, is_sub):
    m = d.get("message") or {}
    model = m.get("model") or "unknown"
    is_sub = is_sub or bool(d.get("isSidechain"))
    for blk in m.get("content") or []:
        if isinstance(blk, dict) and blk.get("type") == "tool_use" and not is_sub:
            if blk.get("name") in ("Agent", "Task"):
                inp = blk.get("input") or {}
                s["agent_calls"].append(dict(subagent_type=inp.get("subagent_type"), model=inp.get("model")))
    u = m.get("usage")
    mid = m.get("id") or d.get("requestId") or d.get("uuid")
    if not u or mid in s["seen_ids"]:
        return
    s["seen_ids"].add(mid)
    if is_sub:
        add_usage(s["sub"][model], u)
        return
    add_usage(s["main"][model], u)
    prompt = (u.get("input_tokens") or 0) + (u.get("cache_creation_input_tokens") or 0) + (u.get("cache_read_input_tokens") or 0)
    s["prompt_sum"] += prompt
    if s["first_call_tokens"] is None:
        s["first_call_tokens"] = prompt
        key = "first"
    else:
        key = "first"
        la, lu = s["_last_assistant"], s["_last_user"]
        if la and lu and lu >= la:
            g = (lu - la).total_seconds()
            key = "lt5" if g < GAP_5M else ("b5_60" if g < GAP_60M else "gt60")
        elif la:
            key = "lt5"
    add_usage(s["gap"][key], u)
    if ts:
        s["_last_assistant"] = ts


def handle_line(s, d, is_sub):
    if d.get("entrypoint") and not s["entrypoint"]:
        s["entrypoint"] = d["entrypoint"]
    if d.get("version"):
        s["versions"].add(d["version"])
    if d.get("cwd") and not s["cwd"]:
        s["cwd"] = d["cwd"]
    if d.get("permissionMode"):
        s["permission_modes"].add(d["permissionMode"])
    if d.get("effort"):
        s["efforts"].add(str(d["effort"]))
    t = d.get("type")
    if t == "cost-state" and isinstance(d.get("totalCostUSD"), (int, float)):
        s["cost_state_usd"] = d["totalCostUSD"]
        return
    ts = parse_ts(d["timestamp"]) if d.get("timestamp") else None
    if ts:
        if not s["first_ts"] or ts < s["first_ts"]:
            s["first_ts"] = ts
        if not s["last_ts"] or ts > s["last_ts"]:
            s["last_ts"] = ts
    if t == "system" and d.get("subtype") == "compact_boundary":
        s["compactions"] += 1
    elif t == "user":
        handle_user(s, d, ts, is_sub)
    elif t == "assistant":
        handle_assistant(s, d, ts, is_sub)


def iter_files(root):
    """Yield (path, session_id, project, is_sub_file)."""
    for project in sorted(os.listdir(root)):
        pdir = os.path.join(root, project)
        if not os.path.isdir(pdir):
            continue
        for dirpath, dirnames, filenames in os.walk(pdir):
            dirnames[:] = [x for x in dirnames if x not in SKIP_DIRS]
            for fn in filenames:
                if not fn.endswith(".jsonl"):
                    continue
                rel = os.path.relpath(os.path.join(dirpath, fn), pdir).split(os.sep)
                if len(rel) == 1:
                    sid, is_sub = rel[0][:-6], False
                else:
                    sid, is_sub = rel[0], True
                if UUID_RE.match(sid):
                    yield os.path.join(dirpath, fn), sid, project, is_sub


def scan(root=ROOT, since=None):
    """Return {session_id: record}. `since` (aware datetime) skips files whose
    mtime is older — cheap pre-filter; the report applies the exact window."""
    sessions = {}
    for path, sid, project, is_sub in iter_files(root):
        if since is not None:
            try:
                if dt.datetime.fromtimestamp(os.path.getmtime(path), tz=dt.timezone.utc) < since:
                    continue
            except OSError:
                continue
        s = sessions.get(sid)
        if s is None:
            s = sessions[sid] = new_session(sid, project)
        try:
            with open(path, "rb") as fh:
                for raw in fh:
                    try:
                        d = json.loads(raw)
                    except Exception:
                        continue
                    if isinstance(d, dict):
                        handle_line(s, d, is_sub)
        except OSError:
            continue
    for s in sessions.values():
        for k in ("seen_ids", "_last_assistant", "_last_user"):
            s.pop(k, None)
        s["main"], s["sub"] = dict(s["main"]), dict(s["sub"])
        s["main_calls"] = sum(b["calls"] for b in s["main"].values())
    return sessions


def classify(s):
    """interactive-desktop | interactive-cli | teammate | headless | other."""
    ep = s["entrypoint"] or ""
    if ep == "sdk-cli":
        return "headless"
    if ep in ("cli", "claude-desktop") and s["human_turns"] == 0 and s["teammate_msgs"] > 0:
        return "teammate"
    if ep == "claude-desktop":
        return "interactive-desktop"
    if ep == "cli":
        return "interactive-cli"
    return "other"
