# Cost-Aware Meta-Router v2 — Specification

This spec proposes seven upgrades to the meta-router pattern used in the `zivtech/drupal-meta-skills` and `zivtech/a11y-meta-skills` repos. Each upgrade maps to a cost mechanic already documented and shipped as a helper in this repo.

Baseline numbers come from `../benchmark/results.md`. Reductions listed below are the parent-context savings measured on the a11y-meta-skills bundle (the worst-case of the two) unless noted.

## The seven upgrades

### 1. Stubs-only at boot

**Problem.** A `SKILL.md` whose body contains the full skill protocol costs the parent session that body on turn 1, whether the skill is used or not. a11y-meta-skills preloads 41,649 tokens this way — 13.88% of the rot zone before the user says anything. drupal-meta-skills preloads 8,807 tokens for the same reason, which is cheap until a session installs a second or third meta-skill bundle.

**Mechanic.** `watching-cost/` — every byte in context is reprocessed on every subsequent turn.

**Change.** A `SKILL.md` becomes a stub. Frontmatter carries `name` and `description`; the body holds at most a routing rationale and a `handoff: <agent-subtype>` directive. The real protocol lives in a matching file under `.claude/agents/`. drupal-meta-skills already does this well (`drupal-planner/SKILL.md` is 2,124 tokens and delegates to `Agent(subagent_type="drupal-planner")`). a11y-meta-skills needs to migrate — the 17,716-token `a11y-planner/SKILL.md` should shrink to a ~200-token stub that delegates to the 9,300-token `a11y-planner.md` agent.

**Expected saving.** 41,249 → 403 parent-context tokens at turn 1 for a11y. 8,151 → 657 for drupal.

### 2. Subagent-isolated execution

**Problem.** Once the router picks a skill, naive implementations load the matched body into the parent context for the LLM to execute inline. That body then sits there for the rest of the session — even after the skill finishes — contributing to watching cost and file-count accumulation.

**Mechanic.** `subagent-isolation/` — the 50-file threshold is about contextual weight; every skill body loaded into the parent is permanent. A subagent gets its own context window.

**Change.** The stub's `handoff` action spawns an `Agent` tool call with `subagent_type=<name>`. The skill body lives inside that subagent's context. Only a short summary (≤500 tokens) returns to the parent. drupal-meta-skills already does this (`drupal-planner/SKILL.md` step 5). a11y-meta-skills currently executes inline.

**Expected saving.** Scenario C in `../benchmark/results.md` — 97% parent-context reduction for a11y, 81% for drupal at turn 10.

### 3. Cache-stable router prompt

**Problem.** If the router prompt itself changes inside a session (e.g. gets edited by the user, or rewrites itself based on new context), it invalidates the conversation-prefix cache, forcing every subsequent turn to re-cache at 1.25× base cost. With a 5-minute idle TTL, the router is the most re-cache-sensitive prompt in the session because it fires every turn.

**Mechanic.** `idle-tax/` — 300-second cache TTL, 12.5× premium on cold-cache messages. Anything at the top of the prompt stack should be treated as read-only for the session.

**Change.** The router prompt is declared stable. It is loaded once at session start and never rewritten. Skill stubs are appended in a deterministic order (alphabetical by name). Skill selection outputs a structured `route: <name>` line but does not modify the router itself.

**Expected saving.** Router prompt is ~500 tokens; a cold-cache hit on a 50K-token session is ~50K × (1.25 - 0.10) = 57.5K token-equivalents premium. Keeping the router stable prevents the router's ~500 tokens from becoming a repeated source of that penalty mid-session.

### 4. Rot-zone budget for stubs

**Problem.** Without a ceiling, skill authors drift toward longer `description` fields and richer routing tables, which inflates the stub table monotonically. In a world where a single session may install multiple meta-skill bundles, the stub table becomes a preloaded mini-bundle of its own.

**Mechanic.** `just-one-more-turn/` — 70% / 90% / 100% tiers at 210K / 270K / 300K tokens. The 70% soft warning is the effective turn-1 budget for skills plus all other overhead.

**Change.** Router v2 caps the preloaded-stub budget at 5K tokens (≈1.6% of the 300K rot zone), with the router prompt itself held at ≤1K tokens. For context: drupal-meta-skills today ships 657 stub tokens + a 2,124-token `drupal-planner/SKILL.md`. If that file's body shrinks per upgrade #1, the whole stub layer comes in under 1K tokens — ten times under budget. a11y-meta-skills at 403 stub tokens is already well under budget once its bodies move to agents.

**Expected saving.** Caps turn-1 overhead at 5K tokens regardless of bundle count. Keeps the 210K soft-rot warning from firing solely on preloaded skill overhead.

### 5. Effort floor for routing

**Problem.** Classification is a cheap task. Spending `xhigh` reasoning on it wastes tokens. Opus 4.7's `xhigh` default means the router runs at maximum reasoning every turn unless explicitly pinned down.

**Mechanic.** `effort-control/` — `CLAUDE_CODE_EFFORT_LEVEL=high` environment variable (highest-precedence effort pin).

**Change.** The router's system-prompt declares "this is a classification task; do not reason beyond picking a route and writing one sentence of justification." Bundles that ship a hook can also verify `CLAUDE_CODE_EFFORT_LEVEL=high` at session start via `effort-pin-banner.sh` and warn if it's missing. Skills that need `xhigh` reasoning (e.g. the a11y-planner protocol itself) get escalated inside their subagent, not at the router layer.

**Expected saving.** The effort-level premium is not counted in our token benchmark (it affects compute cost per token, not token count), but `effort-control/` documents it as a meaningful delta on Opus 4.7.

### 6. Auto-persist last-routed skill

**Problem.** Re-running the router on every turn is wasteful when the user is clearly continuing in the same domain. The router consumes tokens to decide "yes, still drupal-planner" turn after turn.

**Mechanic.** `auto-persist/` — Stop hook writes session state to shell, ~500-token resume vs ~50K cold read.

**Change.** On every Stop event, the auto-persist hook writes `last_routed_skill: <name>` into `~/.claude/sessions/auto-state/<sessionId>.json`. On the next UserPromptSubmit, the router reads the previous route and skips itself if the new prompt's embedding/keyword overlap with the last skill's `description` exceeds a threshold (naive: any keyword match, substring). When skipped, the router adds "continuing in <name>" to `additionalContext` instead of re-running.

**Expected saving.** Router is ~500 tokens; skipping it on 4 of 5 turns saves ~2K tokens per 5-turn sequence. Cumulative for long same-domain sessions.

### 7. Post-compact stub rehydration

**Problem.** Compaction is lossy. The stub table is exactly the kind of stable boilerplate that compaction is likeliest to drop. When it does, the next router call fails silently: the router cannot route to skills whose stubs it has forgotten.

**Mechanic.** `compact-gamble/` — PreCompact hook exists precisely because compaction silently discards context.

**Change.** Router v2 ships a PreCompact hook that emits `additionalContext` reminding Claude to preserve the stub table verbatim, and a PostCompact verification hook (per commit `79e859e` in this repo — "post-compact constraint verification hook") that re-reads the stub table after compaction. If it can't find the stubs in context, it injects them again from the canonical stub file.

**Expected saving.** Prevents router failure entirely in post-compaction turns. The alternative (broken router) silently falls back to the LLM's own routing instinct, which is worse and less auditable.

## Summary table

| # | Upgrade | Helper | Primary metric improved |
|---|---|---|---|
| 1 | Stubs-only at boot | `watching-cost/` | Turn-1 parent context |
| 2 | Subagent-isolated execution | `subagent-isolation/` | Steady-state parent context |
| 3 | Cache-stable router prompt | `idle-tax/` | Cache-cold resilience |
| 4 | Rot-zone budget for stubs | `just-one-more-turn/` | Turn-1 ceiling |
| 5 | Effort floor | `effort-control/` | Per-turn compute cost |
| 6 | Auto-persist last-routed skill | `auto-persist/` | Router amortization |
| 7 | Post-compact stub rehydration | `compact-gamble/` | Survivability after compaction |

## Rollout order

1. Upgrade #1 (stubs-only) is the single highest-value change for bundles that aren't already there. Do it first.
2. Upgrade #2 (subagent execution) only pays off once #1 is in place — a skill body still in the SKILL.md defeats subagent isolation.
3. Upgrade #4 (budget) is a policy, not code. Add it to the bundle's `CONTRIBUTING.md` as a hard cap on stub size.
4. Upgrades #3, #5, #6, #7 are defense in depth. Land them as hooks in the bundle's `.claude/hooks/` directory; they are independent of each other and can be merged in any order.

## Non-goals

- Dynamic skill fetching over the network. All stubs and agents ship with the bundle; routing is purely local.
- Replacing Claude's native skill discovery. The router complements it; the router's job is to constrain context footprint, not to be the only entry point.
- Measurement replacing the `char/4` estimator with tiktoken. The approximation is consistent with the rest of this repo and the relative differences it reports are robust.
