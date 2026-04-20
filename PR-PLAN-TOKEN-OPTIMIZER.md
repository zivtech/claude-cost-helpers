# PR Plan: Cold-Cache Detection for alexgreensh/token-optimizer

*Prepared 2026-04-20. Do not open PR until Alex reviews.*

## The Gap

token-optimizer (476 stars, Python, 78+ releases) has 6 hooks:
- SessionStart, SessionEnd, PreCompact, PostCompact, PreToolUse, PostToolUse

It does **not** have a UserPromptSubmit hook. Their Quality Nudges fire on context quality degradation (15+ point drop or <60 score), but they have no awareness of the 5-minute prompt cache TTL. When a user returns after an idle gap, there's no warning that the next turn will be 12.5x more expensive due to cache expiration.

## What We'd Contribute

A new `UserPromptSubmit` hook that:
1. Reads a timestamp file written by their existing SessionEnd or PostToolUse hook (or writes its own via a companion PostToolUse addition)
2. On each user prompt submission, checks elapsed time since last API activity
3. If >5 minutes: emits a Quality Nudge-style warning: "Cache expired (~{N} min idle). This turn will re-cache the full context at input rates ($15/MTok vs $1.50/MTok). Consider: save session and start fresh if context is stale."
4. If >3 minutes but <5: soft heads-up: "Cache expiring soon. Submit within {remaining}s to stay warm."

## Integration Points

- Fits their existing Quality Nudge pattern (inject advice via `additionalContext`)
- Uses their hook contract (fail-open, `continue: true`)
- Our `cache-idle-timer.sh` is the reference implementation (Bash). Their plugin is Python — we'd port the logic.
- The timestamp tracking could piggyback on their existing `PostToolUse` archive hook or `SessionStart` restore

## Key Design Decisions

1. **Timestamp source**: Write `~/.claude/.cache-timer` on every API response (via PostToolUse), read on UserPromptSubmit. Simple, no shared state.
2. **Warning style**: Match their Quality Nudge format so it feels native, not bolted on.
3. **Thresholds**: Configurable via env vars (same pattern as our helpers): `CACHE_TTL_SECONDS=300`, `CACHE_WARN_SECONDS=180`
4. **No blocking**: Informational only. User's prompt always proceeds.

## License Concern

token-optimizer uses **PolyForm Noncommercial 1.0.0** — not a standard OSS license. This means:
- We can contribute code to their repo (they own the project)
- But we can't fork and redistribute commercially
- Our helpers are GPL-3.0 — the PR would be a contribution under their license, not ours
- **Action**: Review PolyForm NC terms before submitting. If the license is a concern, we can instead document the integration pattern and let them implement it.

## Files to Create/Modify

```
token-optimizer/
├── hooks/
│   └── user_prompt_submit.py   # NEW — cache idle detection
├── config.py                    # ADD cache TTL constants
└── README.md                    # ADD section on cache-freshness monitoring
```

## Next Steps

1. [ ] Alex reviews this plan
2. [ ] Check PolyForm NC implications for Zivtech contributing
3. [ ] Fork repo locally, implement in Python
4. [ ] Test with real idle gaps (easy: wait 6 minutes between prompts)
5. [ ] Open PR with clear description linking to our blog series for context
