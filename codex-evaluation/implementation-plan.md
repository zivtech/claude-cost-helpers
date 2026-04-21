# Codex Helper Implementation Plan

This plan covers the **supportable Codex-native subset** identified by the evaluation package. It does not attempt to port every Claude helper.

## Goal

Implement the smallest credible Codex helper lane in this repository without overstating parity with the existing Claude helper set.

## Scope

### In scope

- `turn-rot`
- `stop-snapshot`
- `bash-output-watch`
- `reasoning-hygiene-banner`

### Conditional follow-up

- `idle-gap-awareness`

### Explicit non-goals for now

- `subagent-boundary-watch`
- `compact-safety`

Those stay out until Codex exposes stronger documented surfaces for file/tool telemetry or pre-compact interception.

## Repository layout

Implement Codex-native helpers in a separate top-level lane so the current Claude helpers stay intact:

```text
codex-helpers/
├── README.md
├── install-all.sh
├── turn-rot/
├── stop-snapshot/
├── bash-output-watch/
└── reasoning-hygiene-banner/
```

Each Codex helper should mirror the existing repo pattern:

- one hook script
- optional command markdown where Codex behavior supports it
- one `hooks.json` snippet instead of a Claude `settings.json` snippet
- install/uninstall scripts
- helper-specific README

Use `~/.codex/` paths, not `~/.claude/`.

## Shared implementation rules

- Fail open: every hook must return `{"continue": true}` where the event contract requires it.
- Prefer repo-local `.codex/hooks.json` snippets for evaluation and examples; document any required global feature flags separately.
- Keep all claims Codex-specific and evidence-backed.
- Do not claim coverage for non-Bash tool output unless Codex documents it.
- Keep Claude and Codex helper naming close enough to compare, but not so close that unsupported parity is implied.

## Phase 1: `stop-snapshot`

### Why first

It has the strongest current Codex support and the cleanest portability story.

### Deliverables

- `codex-helpers/stop-snapshot/hook/stop-snapshot.py` or `.sh`
- `codex-helpers/stop-snapshot/install.sh`
- `codex-helpers/stop-snapshot/uninstall.sh`
- `codex-helpers/stop-snapshot/hooks.json`
- `codex-helpers/stop-snapshot/README.md`

### Behavior

- Run on `Stop`
- Write machine-readable and human-readable session state to a Codex path such as:
  - `~/.codex/sessions/auto-state/<session_id>.json`
  - `~/.codex/sessions/auto-state/<session_id>.md`
- Capture:
  - `cwd`
  - transcript path
  - last assistant message preview/hash
  - branch and local git state when available

### Acceptance criteria

- Works from hook stdin alone plus local git inspection
- Silent on success
- Does not require narrative synthesis from the model

## Phase 2: `turn-rot`

### Why second

The live evaluation supports long-session accumulation strongly enough to implement a warning helper without depending on unsupported pricing claims.

### Deliverables

- `codex-helpers/turn-rot/context-usage-monitor.py` or `.sh`
- optional command doc for fresh-session handoff guidance
- install/uninstall/scripts/docs

### Behavior

- Run on `UserPromptSubmit`
- Track turn count or lightweight session-growth state in `~/.codex/.session-state/`
- Warn when the session crosses configurable thresholds

### Required wording

The helper should talk about:

- session growth
- stale context
- fresh-session hygiene

It should not talk about:

- exact pricing multipliers
- a universal Codex rot threshold

### Acceptance criteria

- Thresholds configurable by env vars
- Warning language matches the Codex evidence package
- Fresh-session guidance points to a curated handoff workflow, not Claude-specific commands

## Phase 3: `bash-output-watch`

### Why third

The live evaluation showed a clean measurable difference between dumping large Bash output into the session and redirecting it to a file.

### Deliverables

- `codex-helpers/bash-output-watch/output-size-monitor.py` or `.sh`
- optional helper doc for output redirection patterns
- install/uninstall/scripts/docs

### Behavior

- Run on `PostToolUse` for `Bash`
- Estimate `tool_response` size
- Track cumulative Bash-output burden by session
- Warn on:
  - per-call large output
  - cumulative Bash-output growth

### Required wording

Always say:

- `Bash output`
- or `shell output`

Never say:

- `all tool output`

### Acceptance criteria

- Uses only documented Codex `Bash` event data
- Makes redirection and filtered-output suggestions concrete
- Keeps thresholds configurable

## Phase 4: `reasoning-hygiene-banner`

### Why fourth

The local runtime already surfaced a real configuration issue: global `model_reasoning_effort = "xhigh"` is easy to leave on without explicit intent.

### Deliverables

- `codex-helpers/reasoning-hygiene-banner/session-start-check.py` or `.sh`
- `README.md`
- install/uninstall/scripts

### Behavior

- Run on `SessionStart`
- Inspect effective local config where practical
- Provide a lightweight reminder when model or reasoning defaults are high-cost by default

### Required wording

This helper is about:

- deliberate model choice
- deliberate reasoning-effort choice

It is not about:

- defending against a Claude-specific hidden default

### Acceptance criteria

- Safe if config fields are missing
- Does not pretend to know hidden runtime values it cannot observe
- Uses language aligned with the Codex evaluation package

## Phase 5: `idle-gap-awareness` (conditional)

### Gate

Do not implement until you have stronger evidence from interactive Codex sessions or additional `exec`/`resume` experiments showing a real and durable idle-gap signal worth acting on.

### Current status

The live `exec`/`resume` measurement showed high cached-input ratios even after a >5 minute gap, so the Claude helper logic does not port cleanly.

### If implemented later

- keep the wording soft
- cite Codex/OpenAI cache behavior, not Claude behavior
- avoid exact penalty claims

## Test plan

For each helper:

1. unit-style local stdin fixture tests for cold/warm/threshold cases
2. one live Codex run using the passive evaluation harness
3. one failure-path check to confirm fail-open behavior

For the Codex helper lane as a whole:

1. verify the `hooks.json` snippets are valid JSON
2. run at least one `codex exec --json` scenario per helper where applicable
3. document observed runtime quirks separately from intended design

## Release gates

Do not describe this repository as shipping Codex helpers until at least:

1. `stop-snapshot` is implemented and tested
2. `turn-rot` is implemented and tested
3. `bash-output-watch` is implemented and tested
4. the top-level README includes a distinct Codex section with accurate support boundaries

At that point, reassess whether a dedicated `codex-cost-helpers` repo is warranted.

## Repo split trigger

Create `codex-cost-helpers` only when all of these are true:

- at least 3 Codex helpers are implemented
- each has its own README/install path
- the top-level Codex README no longer depends on Claude framing to make sense
- the measured claims in `codex-evaluation/results/` are sufficient for a standalone public README
