# Codex-Native Helper Feasibility

This document re-specs each helper against current Codex CLI/Desktop surfaces and defines the smallest viable Codex helper set that can be defended with current documentation and the planned evidence harness.

## Smallest viable Codex helper set

### Recommended now

1. `turn-rot`
2. `stop-snapshot`
3. `bash-output-watch`
4. `reasoning-hygiene-banner`

### Conditional follow-up

5. `idle-gap-awareness`

### Hold

6. `subagent-boundary-watch`
7. `compact-safety`

## Helper-by-helper re-spec

## `idle-tax` -> `idle-gap-awareness`

### Codex surface

- `UserPromptSubmit`
- local state files under `~/.codex`

### What it can claim

- idle gaps may reduce cache reuse
- Codex sessions benefit from keeping repeated prefixes stable
- a fresh session may be better than dragging stale context forward

### What it must not claim without measurement

- exact 5-minute expiration for Codex CLI/Desktop
- exact 12.5x penalty language
- that Codex hides the same billing mechanics as Claude

### MVP acceptance criteria

- records the last prompt timestamp per session
- warns on long inactivity windows
- wording cites OpenAI's documented 5-10 minute default in-memory caching behavior
- post language is updated after empirical task-suite results

## `just-one-more-turn` -> `turn-rot`

### Codex surface

- `UserPromptSubmit`
- optional manual `/status` checks

### What it can claim

- long-running sessions accumulate more history
- accumulated history can make a session harder to manage
- a fresh session with a curated handoff can be cleaner than continuing indefinitely

### What it must not claim without measurement

- specific cost multipliers in Codex
- exact context-rot thresholds as universal truths

### MVP acceptance criteria

- tracks turn count or similar lightweight session-growth signal
- warns without blocking
- frames thresholds as operational guidance, not pricing guarantees

## `subagent-isolation` -> `subagent-boundary-watch`

### Codex surface

- conceptually: `/agent`
- operationally: no documented `Read|Glob|Grep` hook surface today

### What it can claim

- none automatically today

### What it must not claim

- automatic detection of file-heavy exploration
- file-count-based warnings equivalent to the Claude helper

### Current status

Not supportable today as a true helper on documented Codex surfaces.

### Future trigger to revisit

Revisit only if Codex exposes hookable file-read or search tool events, or an authoritative per-agent/thread telemetry surface.

## `compact-gamble` -> `compact-safety`

### Codex surface

- manual `/compact`
- no documented `PreCompact` hook today

### What it can claim

- manual compaction should be tested against curated fresh-session handoffs

### What it must not claim

- automatic pre-compact safety net
- documented Codex support for a `PreCompact` hook

### Current status

Not supportable today as an automatic helper.

### Future trigger to revisit

Revisit only if Codex documents a `PreCompact` or equivalent interception surface.

## `watching-cost` -> `bash-output-watch`

### Codex surface

- `PostToolUse` on `Bash`
- `tool_response`

### What it can claim

- large `Bash` output lands in the session and can make the session heavier
- filtered or redirected shell output is safer for long runs than verbose shell dumps

### What it must not claim

- all-tool coverage
- visibility into non-Bash Codex tool outputs on current documented surfaces

### MVP acceptance criteria

- estimates `Bash` output size from `tool_response`
- logs cumulative bash output per session
- uses the phrase "Bash output" or "shell output" consistently

## `effort-control` -> `reasoning-hygiene-banner`

### Codex surface

- `SessionStart`
- `/model`
- explicit model/reasoning settings for automations

### What it can claim

- users should be deliberate about model choice and reasoning effort
- session-start reminders can reinforce that habit
- recurring automations should pin model and effort explicitly when reproducibility matters

### What it must not claim

- that Codex has the same hidden default-effort behavior as Claude
- that a specific environment-variable defense is required

### MVP acceptance criteria

- session-start reminder or checklist
- docs-grounded language around choosing model and reasoning effort deliberately
- automation examples that pin model and effort explicitly

## `auto-persist` -> `stop-snapshot`

### Codex surface

- `Stop`
- `cwd`
- `transcript_path`
- `last_assistant_message`

### What it can claim

- low-cost session-state persistence is possible at the end of each turn
- environmental state can be captured without requiring a narrative save command every time

### What it must not claim without measurement

- exact token savings
- exact cost avoidance amounts

### MVP acceptance criteria

- writes machine-readable session snapshots on `Stop`
- does not block or alter session behavior
- makes resume-state inspection cheap and repeatable

## Publication language guardrails

If a Codex post is eventually published, it should use:

- "context economics"
- "session hygiene"
- "prompt-cache reuse"
- "Bash output carrying cost"
- "current documented Codex surfaces"

It should avoid:

- "Codex hides costs from you"
- "Codex has the same idle tax as Claude"
- "all tools behave this way in Codex"
- "this helper set already works in Codex"

## Current recommendation

The repo should talk about a Codex helper lane only in these terms:

- four helpers are implemented or implementable in the current narrowed lane,
- one remains conditional on stronger evidence,
- two are blocked by current documented Codex hook coverage,
- and any post stronger than that needs empirical evidence first.
