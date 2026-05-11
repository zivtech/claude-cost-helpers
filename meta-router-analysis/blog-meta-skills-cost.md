# The Meta-Skill Tax: What the Router Already Saves, What's Still on the Table

*Part of [The Economics of Claude Code](https://zivtech.github.io/zivtech-demos/economics-of-claude/) series. Companion code: [zivtech/claude-cost-helpers](https://github.com/zivtech/claude-cost-helpers).*

A meta-skill bundle is a set of related skills shipped together — a planner, a critic, an executor, and whatever sub-planners they route between. Two patterns compete for how it gets loaded into your session:

1. **Flatten everything into context.** Every skill's body and every agent's body is preloaded at turn 1. Simple to reason about. Expensive.
2. **Route and delegate.** A `SKILL.md` acts as a router; the full protocol lives in a matching `.claude/agents/<name>.md` file that only loads when an `Agent(subagent_type=...)` call spawns it. Cheaper, but only if the `SKILL.md` stays a router instead of silently growing into the whole protocol.

This post measures two real public bundles in both states — their default-branch "before" and a public router-v2 "after" branch — plus a simulated third strategy. All numbers come from [`benchmark/results.md`](benchmark/results.md), reproducible with `python3 scenarios.py --markdown`.

## The two bundles

- **[zivtech/drupal-meta-skills](https://github.com/zivtech/drupal-meta-skills)** — eight skills, eight matching agents. `drupal-planner/SKILL.md` is a 2,124-token router that delegates to `Agent(subagent_type="drupal-planner")`. The 8,214-token agent body lives in `.claude/agents/drupal-planner.md` and never touches the parent.
- **[zivtech/a11y-meta-skills](https://github.com/zivtech/a11y-meta-skills)** — four skills, two matching agents in the `main` branch. The agents exist, but `a11y-planner/SKILL.md` is 17,716 tokens of full planner protocol loaded inline.

Same bundle idea. Different discipline about where the body lives.

Each bundle has a public refactor branch:

- `zivtech/drupal-meta-skills` — branch `router-v2-trim` — a surgical patch that removes `Companion_Skills`, `Tool_Usage`, `References`, and `Final_Checklist` sections from every SKILL.md. Agents untouched.
- `zivtech/a11y-meta-skills` — branch `router-v2-refactor` — moves each SKILL.md's full protocol into a matching agent file; SKILL.md shrinks to a 200-token stub.

## The three scenarios

| | F. Flattened (straw-man) | A. As-implemented | C. Optimized (simulated) |
|---|---|---|---|
| SKILL.md bodies | Preloaded | Preloaded | Stubs only |
| Agent bodies | Preloaded alongside | On disk, loaded via subagent | On disk, loaded via subagent |
| Router | None | Inside each SKILL.md | Top-of-stack prompt with stub table |

## drupal-meta-skills: validated, then tightened

| Scenario | Before — turn-10 | After (router-v2-trim) — turn-10 | % of 300K rot (after) |
|---|---:|---:|---:|
| F. Flattened | 54,630 | 51,714 | 17.24% |
| A. As-implemented | **9,307** | **6,391** | **2.13%** |
| C. Optimized (simulated) | 1,657 | 1,657 | 0.55% |

drupal-meta-skills' default state already saves 83% vs the flattened straw-man because its SKILL.md files act as routers that delegate to agents. The `router-v2-trim` branch shaves another **31%** off the as-implemented row — 9,307 → 6,391 tokens — by removing sections from each SKILL.md that duplicate agent work. A vs F savings improve from 83% to 88%.

Specifically, the trim drops these section types from every SKILL.md:

- `Companion_Skills` — long lists of related skills with versions. Useful once; preloading every turn is wasteful.
- `Tool_Usage` — implementation-level tool choice guidance. Belongs in the agent.
- `References` — agent loads them on demand.
- `Final_Checklist` — post-planning validation belongs in the agent, not the router.

The bundle's agent files are untouched. The routing contract is unchanged. Existing callers of `Agent(subagent_type="drupal-planner")` continue to get the full protocol.

## a11y-meta-skills: where the wins were on the table

| Scenario | Before — turn-10 | After (router-v2-refactor) — turn-10 | % of 300K rot (after) |
|---|---:|---:|---:|
| F. Flattened | 60,175 | 29,357 | 9.79% |
| A. As-implemented | **42,149** | **1,465** | **0.49%** |
| C. Optimized (simulated) | 1,403 | 1,410 | 0.47% |

a11y-meta-skills' default state only saved 30% vs the straw-man — most of its weight sat in SKILL.md, not in agents. Install the bundle, open a session, and **41,649 tokens of accessibility-planning protocol sat in the parent context before anything was typed** (14% of the rot zone).

The `router-v2-refactor` branch:

1. Shrinks each SKILL.md to a frontmatter-delegation stub (a11y-planner: 17,821 → 258 tokens, -99%).
2. Adds new agent files for `a11y-test` and `perspective-audit` populated with the moved SKILL.md bodies.
3. Leaves the existing `a11y-planner.md` and `a11y-critic.md` agents alone (they already had the protocol).

No accessibility content was removed. It moved verbatim from preloaded SKILL.md bodies to on-demand agent files. The result: **96.5% reduction in parent context at turn 10** (42,149 → 1,465 tokens), and **98% reduction in cold-cache volatile tokens** (41,649 → 965 per TTL expiry).

The empirical "after" measurement lands at 1,465 tokens — within 4% of the simulated `C. Optimized` row (1,410 tokens). The simulator was a trustworthy predictor.

## Why the gap

The `SKILL.md` contract says "frontmatter at startup; body on demand." Agent clients implement that faithfully — once a bundle is installed, Claude Code reads every SKILL.md's full body into the parent session. The clients can't second-guess intent; they treat the body as the skill.

That contract is fine *if you treat SKILL.md as a router*. It's expensive if you treat SKILL.md as the whole skill.

drupal-meta-skills (`main`) treats SKILL.md as a router. `drupal-planner/SKILL.md` ends with:

```
Route to planner agent: Delegate planning to the drupal-planner agent.
Agent(subagent_type="drupal-planner", model="opus", prompt=<planning_prompt>)
```

The real 8,214-token protocol lives in `.claude/agents/drupal-planner.md`. It only loads when the router decides to spawn the subagent.

a11y-meta-skills (`main`) treated SKILL.md as the whole skill. `a11y-planner/SKILL.md` contained 916 lines of inline WAI-ARIA protocol. The `a11y-planner.md` agent existed next to it, but the SKILL.md didn't delegate to it — both files were parallel copies. The parent context carried all 17,716 tokens for the life of the session.

The `router-v2-refactor` branch closes that gap: SKILL.md becomes a stub that says "delegate to `a11y-planner` agent", and the agent body lives only on disk until spawned.

## The router's job, re-stated

A well-formed `SKILL.md` does four things and stops:

1. Declares `name` + `description` in frontmatter.
2. Lists routing signals (keywords, task types) that suggest this skill.
3. Names the agent to delegate to.
4. Calls `Agent(subagent_type=<name>)` with the user's prompt.

Anything longer than that belongs in the agent file. If you find yourself writing protocol inside a SKILL.md — "here's how to validate a field definition", "here's the WCAG 2.2 SC list", "here's the Drush invocation to sync config" — that's the agent body, not the router.

## Seven upgrades (router-v2)

The full spec is in [`improvements/router-v2-spec.md`](improvements/router-v2-spec.md). Each upgrade maps to a cost mechanic shipped in this repo:

1. **Stubs-only at boot** — `SKILL.md` carries frontmatter + handoff. Protocol moves to `.claude/agents/`. Mechanic: `watching-cost/`. Shipped: `a11y-meta-skills@router-v2-refactor`, partially `drupal-meta-skills@router-v2-trim`.
2. **Subagent-isolated execution** — handoff spawns `Agent`. Mechanic: `subagent-isolation/`. Already in `drupal-meta-skills`; new in `a11y-meta-skills@router-v2-refactor` for `a11y-test` and `perspective-audit`.
3. **Cache-stable router prompt** — router never rewrites itself. Mechanic: `idle-tax/`.
4. **Rot-zone budget for stubs** — hard cap at 5K tokens. Mechanic: `just-one-more-turn/`.
5. **Effort floor for the router** — classification is `high`, not `xhigh`. Mechanic: `effort-control/`.
6. **Auto-persist last-routed skill** — skip the router when the domain hasn't changed. Mechanic: `auto-persist/`.
7. **Post-compact stub rehydration** — re-inject the stub table after compaction. Mechanic: `compact-gamble/`.

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

The script clones both bundles at both refs (4 checkouts total) into `/tmp/meta-skills-bench/`, measures every SKILL.md and agent file, and prints the tables cited above. No dependencies beyond `python3`, `git`, and an internet connection to reach GitHub.

## What's next

- [`drupal-ai-evaluation.md`](drupal-ai-evaluation.md) — applies these findings to Drupal's 2026 AI roadmap and proposes changes to the `ai_best_practices` project and the draft agent-skills issue.
- The `router-v2-refactor` and `router-v2-trim` branches are open in their respective repos. Reviews welcome.

The headline is empirical now, not just predicted. The router-and-subagent pattern works (`drupal-meta-skills@main`: -83% vs straw-man). When it's not applied, the gap is recoverable in a single patch (`a11y-meta-skills@router-v2-refactor`: -96.5%). The open question on any meta-skill bundle is whether its `SKILL.md` files are routers or protocols. If they're protocols, the savings are sitting right there.
