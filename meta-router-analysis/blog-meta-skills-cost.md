# The Meta-Skill Tax: What the Router Already Saves, What's Still on the Table

*Part of [The Economics of Claude Code](https://zivtech.github.io/zivtech-demos/economics-of-claude/) series. Companion code: [zivtech/claude-cost-helpers](https://github.com/zivtech/claude-cost-helpers).*

A meta-skill bundle is a set of related skills shipped together — a planner, a critic, an executor, and whatever sub-planners they route between. Two patterns compete for how it gets loaded into your session:

1. **Flatten everything into context.** Every skill's body and every agent's body is preloaded at turn 1. Simple to reason about. Expensive.
2. **Route and delegate.** A `SKILL.md` acts as a router; the full protocol lives in a matching `.claude/agents/<name>.md` file that only loads when an `Agent(subagent_type=...)` call spawns it. Cheaper, but only if the `SKILL.md` stays a router instead of silently growing into the whole protocol.

This post measures two real public bundles under both patterns plus a third — what they'd cost if refactored to the stubs-first router pattern described in [`router-v2-spec.md`](improvements/router-v2-spec.md). The numbers come from [`benchmark/results.md`](benchmark/results.md), reproducible with `python3 scenarios.py --markdown`.

## The two bundles

- **[zivtech/drupal-meta-skills](https://github.com/zivtech/drupal-meta-skills)** — eight skills, eight matching agents. `drupal-planner/SKILL.md` is a 2,124-token router that delegates to `Agent(subagent_type="drupal-planner")`. The 8,214-token agent body lives in `.claude/agents/drupal-planner.md` and never touches the parent.
- **[zivtech/a11y-meta-skills](https://github.com/zivtech/a11y-meta-skills)** — four skills, two matching agents. The agents exist, but `a11y-planner/SKILL.md` is 17,716 tokens of full planner protocol loaded inline.

Same bundle idea. Different discipline about where the body lives.

## The three scenarios

| | F. Flattened (straw-man) | A. As-implemented | C. Optimized (router-v2) |
|---|---|---|---|
| SKILL.md bodies | Preloaded | Preloaded (today's behavior) | Stubs only |
| Agent bodies | Preloaded alongside | On disk, loaded via subagent | On disk, loaded via subagent |
| Router | None | Inside each SKILL.md | Top-of-stack prompt with stub table |

## drupal-meta-skills: already doing most of it right

| Scenario | Turn-1 parent | Turn-10 parent | % of 300K rot |
|---|---:|---:|---:|
| F. Flattened | 54,630 | 54,630 | 18.21% |
| A. As-implemented | 8,807 | 9,307 | 3.10% |
| C. Optimized | 1,157 | 1,657 | 0.55% |

drupal-meta-skills' existing pattern — SKILL.md as router, agents loaded lazily in subagent — **saves 83% of parent context at turn 10 vs the flattened straw-man**. That's the headline validation: the router+subagent pattern, when applied, works.

The remaining 82% (from 9,307 down to 1,657 tokens) is available by shrinking the SKILL.md files themselves. Today each one carries a routing table, "use when / don't use when" guidance, and a companion-skills list inline. Pulling all of that into the agent body and leaving only frontmatter in the SKILL.md would cut parent context another 7,650 tokens. Not essential for a bundle this size, but it matters once you install two or three meta-skill bundles in one session.

## a11y-meta-skills: where the wins are still on the table

| Scenario | Turn-1 parent | Turn-10 parent | % of 300K rot |
|---|---:|---:|---:|
| F. Flattened | 60,175 | 60,175 | 20.06% |
| A. As-implemented | 41,649 | 42,149 | 14.05% |
| C. Optimized (simulated) | 903 | 1,403 | 0.47% |

a11y-meta-skills has agents on disk — so in principle it could follow the drupal pattern. In practice it doesn't: `a11y-planner/SKILL.md` contains the full WAI-ARIA planning protocol (17,716 tokens) rather than delegating to the `a11y-planner.md` agent (9,279 tokens). Install the bundle, open a session, and **41,649 tokens of accessibility-planning protocol sit in your parent context before you've said a word** — 14% of the rot zone spent on skills the session may never invoke.

The A-vs-F number captures the consequence: the bundle only saves 30% over the straw-man, because most of the weight is in SKILL.md rather than agents.

## a11y-meta-skills, actually refactored

Rather than leave the optimization as a simulation, [`refactored/a11y-meta-skills/`](refactored/a11y-meta-skills/) ships a concrete router-v2 port of the bundle. Each of the four SKILL.md files was reduced to a ~200-token frontmatter-delegation stub; existing agents were copied unchanged; new agents for `a11y-test` and `perspective-audit` were generated from their original SKILL.md bodies.

Running the same benchmark against the refactored bundle:

| Scenario | Turn-1 parent | Turn-10 parent | % of 300K rot |
|---|---:|---:|---:|
| F. Flattened | 29,357 | 29,357 | 9.79% |
| A. As-implemented (router-v2 live) | 965 | 1,465 | 0.49% |
| C. Optimized (simulated) | 910 | 1,410 | 0.47% |

The refactored bundle's **A row is what the upstream bundle's C row was predicting**. Empirical 1,465 tokens vs simulated 1,410 tokens — within 4%. The simulation was a trustworthy estimate.

Against the upstream a11y-meta-skills:

- Turn 10 parent context: **42,149 → 1,465 tokens (-96.5%)**.
- Cold-cache volatile tokens: **41,649 → 965 (-98%)** per TTL expiry.
- Even the F straw-man is cheaper: 60,175 → 29,357 tokens (-51%), because the refactor eliminates the SKILL.md-plus-agent duplication that inflated the original straw-man.

No accessibility content was lost. It moved from SKILL.md (preloaded into parent context when the bundle is installed) to agent files (loaded only when a subagent is spawned).

## Why the gap

The `SKILL.md` contract says "frontmatter at startup; body on demand." Agent clients implement that faithfully — once a bundle is installed, Claude Code reads every SKILL.md's full body into the parent session. The clients can't second-guess intent; they treat the body as the skill.

That contract is fine *if you treat SKILL.md as a router*. It's expensive if you treat SKILL.md as the whole skill.

drupal-meta-skills treats it as a router. `drupal-planner/SKILL.md` ends on step 5:

```
Route to planner agent: Delegate planning to the drupal-planner agent.
Agent(subagent_type="drupal-planner", model="opus", prompt=<planning_prompt>)
```

The real 8,214-token protocol lives in `.claude/agents/drupal-planner.md`. It only loads when the router decides to spawn the subagent. The parent context stays at 2,124 tokens for this skill.

a11y-meta-skills treats SKILL.md as the whole skill. `a11y-planner/SKILL.md` contains 916 lines of inline WAI-ARIA protocol. The `a11y-planner.md` agent file exists next to it, but the SKILL.md doesn't delegate to it — both files exist as parallel copies. The parent context carries all 17,716 tokens of the inline version for the life of the session.

## The router's job, re-stated

A well-formed `SKILL.md` does four things and stops:

1. Declares `name` + `description` in frontmatter.
2. Lists routing signals (keywords, task types) that suggest this skill.
3. Names the agent to delegate to.
4. Calls `Agent(subagent_type=<name>)` with the user's prompt.

Anything longer than that belongs in the agent file. If you find yourself writing protocol inside a SKILL.md — "here's how to validate a field definition", "here's the WCAG 2.2 SC list", "here's the Drush invocation to sync config" — that's the agent body, not the router.

## Seven upgrades (router-v2)

The full spec is in [`improvements/router-v2-spec.md`](improvements/router-v2-spec.md). Each upgrade maps to a cost mechanic shipped in this repo:

1. **Stubs-only at boot** — `SKILL.md` carries frontmatter + handoff. Protocol moves to `.claude/agents/`. Mechanic: `watching-cost/`.
2. **Subagent-isolated execution** — handoff spawns `Agent`. Mechanic: `subagent-isolation/`.
3. **Cache-stable router prompt** — router never rewrites itself. Mechanic: `idle-tax/`.
4. **Rot-zone budget for stubs** — hard cap at 5K tokens. Mechanic: `just-one-more-turn/`.
5. **Effort floor for the router** — classification is `high`, not `xhigh`. Mechanic: `effort-control/`.
6. **Auto-persist last-routed skill** — skip the router when the domain hasn't changed. Mechanic: `auto-persist/`.
7. **Post-compact stub rehydration** — re-inject the stub table after compaction. Mechanic: `compact-gamble/`.

Drupal-meta-skills has most of #1 and #2 today. a11y-meta-skills needs #1 first — moving protocol from SKILL.md to agents — and the rest follows.

## What you can steal today

This repo ships seven standalone helpers. Each installs independently. The ones most directly relevant to anyone installing or writing skills:

- [`subagent-isolation/`](../subagent-isolation/) — warns when you've read >50 unique files.
- [`watching-cost/`](../watching-cost/) — warns when tool output accumulates past 25K / 50K / 100K tokens.
- [`just-one-more-turn/`](../just-one-more-turn/) — warns as you approach the rot zone.
- [`idle-tax/`](../idle-tax/) — warns when your prompt cache is about to go cold.

None of these care what your skills look like. They measure behavior. Install the ones that matter and let the thresholds surface the problems.

## Reproducing the benchmark

```bash
git clone https://github.com/zivtech/claude-cost-helpers
cd claude-cost-helpers/meta-router-analysis/benchmark
python3 scenarios.py --markdown
```

The script clones both bundles into `/tmp/meta-skills-bench/`, measures every SKILL.md and agent file, and prints the tables cited above. No dependencies beyond `python3`, `git`, and an internet connection to reach GitHub.

## What's next

- [`drupal-ai-evaluation.md`](drupal-ai-evaluation.md) — applies these findings to Drupal's 2026 AI roadmap and proposes changes to the `ai_best_practices` project and the draft agent-skills issue.
- If you build a meta-skill bundle and want to know where yours lands on the F/A/C axis, point `scenarios.py` at your repo's `.claude/skills/` and `.claude/agents/` directories.

The headline is a reversal of what you'd expect. It's not that the router pattern *could* save tokens — `drupal-meta-skills` proves it already does, 83% vs the inlined straw-man. The open question is whether your bundle's SKILL.md files are routers or protocols. If they're protocols, there's typically 97% of the turn-1 weight still to recover.
