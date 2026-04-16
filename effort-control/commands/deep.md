---
description: One-shot deep reasoning — prepends 'ultrathink' to the next turn so Claude reasons harder on this single message without changing session effort.
---

# Deep

Use this when you have a single hard task that warrants more reasoning than your pinned effort level (`high`) provides — a tricky bug, an architecture decision, a tangled refactor — but you do not want to escalate the whole session to `xhigh` or `max`.

## What this command does

This is a one-turn escalation. It tells Claude to apply `ultrathink`-level reasoning to the user's request that follows. From the [model config docs](https://code.claude.com/docs/en/model-config):

> "For one-off deep reasoning without changing your session setting, include 'ultrathink' in your prompt. This adds an in-context instruction telling the model to reason more on that turn; it does not change the effort level sent to the API."

It does NOT change `CLAUDE_CODE_EFFORT_LEVEL` or the session's `/effort` setting. It does NOT persist. It is an in-context reasoning nudge for the next turn only.

## When to use it

- Hard bug whose root cause you cannot see
- Architecture choice with non-obvious tradeoffs
- Code review on a security-sensitive diff
- Refactor where the wrong move would cascade

## When NOT to use it

- Simple file edits, lookups, or trivial questions — `high` is plenty
- Long-running agentic work — set `/effort xhigh` for the session instead
- Every prompt — defeats the point of pinning effort

## How to invoke

Type `/deep` followed by the task description. Examples:

```
/deep why does this test fail intermittently when run in parallel
/deep should this entity use a config or content entity, given that admins edit it daily
/deep refactor this 800-line controller into something testable without breaking the public API
```

## Process

When invoked, treat the rest of the user's message (or, if they sent only `/deep`, the next message they send) as a request that warrants `ultrathink`-level reasoning. Apply deeper analysis than you would for a routine prompt:

1. Surface non-obvious considerations before diving into a solution
2. State competing approaches with explicit tradeoffs
3. Name what you are NOT certain about
4. If the request is ambiguous, ask one clarifying question before reasoning further

If the user sent only `/deep` with no task, ask: "What do you want me to think deeply about?" Then apply `ultrathink` reasoning to whatever they reply with.

## Notes

- This is a slash command shim around the `ultrathink` keyword. The mechanism is identical — `/deep <task>` and `ultrathink. <task>` produce the same behavior.
- The slash command exists for ergonomics: one keystroke (`/d` + Tab) is cheaper than typing `ultrathink.` and remembering to add the period.
- Companion to the `effort-control` cost helper. Pin effort to `high` as your default; escalate per-task with `/deep` or per-session with `/effort`.
