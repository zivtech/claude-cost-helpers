---
description: Show per-agent delegation result sizes and what carrying them costs this session, priced for the model and cache TTL the session is actually on. Computed locally, zero Claude tokens.
argument-hint: [--session SID] [--horizon N]
---

# Delegation Report

Run the report and show its output verbatim — the output IS the report. Do not
re-derive the numbers, re-price them, or read the transcript it was computed
from (that pulls megabytes into context for nothing).

!`python3 "$HOME/.claude/hooks/cost-helpers/delegation-cost/delegation_report.py" $ARGUMENTS`

After showing it, add exactly one line: the action the **Verdict** points to,
phrased as something to do on the next agent dispatch.

## Where the numbers come from

- **Result sizes:** `~/.claude/.session-state/<session_id>.delegation-agents`,
  written by the delegation-cost hook — one `tokens<TAB>time` line per agent
  result, tokens estimated at ~4 characters each.
- **Model, cache TTL, prefix size:** the last main-thread assistant message of
  the session transcript — its `model`, its `usage.cache_creation` breakdown
  (`ephemeral_1h_input_tokens > 0` means the 1-hour TTL) and its token counts.
  The same signals the hooks read; nothing is assumed.
- **Prices:** Anthropic list input prices per MTok (Fable/Mythos 5.1 $10,
  Opus 5 $5, Sonnet 5 $2, Haiku 4.5 $1); warm cache reads at 0.1x input
  (0.025x on Fable/Mythos 5.1); cache writes at 2x on the 1-hour TTL, 1.25x on
  the 5-minute one.

If the script is missing, re-run `delegation-cost/install.sh` from the
claude-cost-helpers checkout. Do not estimate the dollars by hand — the v1 of
this command did exactly that, with Opus-4-era rates, and was wrong by 4x.

## Why this helps

The delegation invoice (what each agent spent) is visible in `/usage`. The
delegation tax (what the parent pays to re-read the results on every later API
call) is not — and on current models it is often smaller than it feels. On
Fable 5.1, warm reads cost 0.025x input, so 13K tokens of agent results is a
third of a cent per call. The report says whether delegation is actually your
tax this session or whether the cost lives in the rest of the prefix, so you
constrain agents when it matters and stop worrying when it doesn't.
