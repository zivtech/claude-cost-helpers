# The Meta-Skill Tax: What Preloading Costs, What Routing Saves

*Part of [The Economics of Claude Code](https://zivtech.github.io/zivtech-demos/economics-of-claude/) series. Companion code: [zivtech/claude-cost-helpers](https://github.com/zivtech/claude-cost-helpers).*

Claude Code's [skills feature](https://code.claude.com/docs/en/skills) is one of the more useful primitives to land this year. A skill is a folder with a `SKILL.md` file; Claude reads the frontmatter at startup, and the rest of the body when the skill seems relevant.

That "reads the rest of the body when relevant" line is doing a lot of work. How much? Enough that a bundle of four well-written skills can quietly eat 14% of your rot-zone budget before you've typed a single character. This post measures exactly how much, on two real public bundles, and proposes seven upgrades grounded in the cost mechanics the rest of this series has documented.

## The shape of a skill bundle

A meta-skill bundle is a set of related skills shipped as one coherent package. Two real-world examples, both public on GitHub:

- **[zivtech/drupal-meta-skills](https://github.com/zivtech/drupal-meta-skills)** — eight skills. A top-level `drupal-planner` that routes to focused sub-planners for content-model, taxonomy, theme, search, and canvas, plus a critic and a config executor.
- **[zivtech/a11y-meta-skills](https://github.com/zivtech/a11y-meta-skills)** — four skills. A WCAG-grade planner, a critic, a test protocol, and a perspective-audit tool.

These are real. They are installed on real developer machines. They are what this post measures.

## Measurement

Reproducible via `meta-router-analysis/benchmark/scenarios.py` in this repo. The script clones both bundles, counts tokens in every `SKILL.md` using the same `char/4` estimator that `watching-cost/` and `just-one-more-turn/` already use, and computes three loading strategies:

- **A. Preload all.** Every `SKILL.md` body sits in the parent session from turn 1.
- **B. Router + lazy.** Only frontmatter stubs at turn 1. One matched skill's body loads into the parent when the router picks it.
- **C. Router + lazy + subagent.** Stubs at turn 1. Matched skill runs in a delegated `Agent` call — its body never touches the parent.

The rot-zone threshold comes from `just-one-more-turn/` (300,000 tokens default). The file-count threshold comes from `subagent-isolation/` (50 unique files). The cache TTL comes from `idle-tax/` (5 minutes, 12.5× penalty on cold-cache turns).

## The numbers

### drupal-meta-skills

| Scenario | Turn-1 parent | Turn-10 parent | % of 300K rot |
|---|---:|---:|---:|
| Preload all | 8,807 | 8,807 | 2.94% |
| Router + lazy | 1,157 | 1,944 | 0.65% |
| Router + lazy + subagent | 1,157 | 1,657 | 0.55% |

### a11y-meta-skills

| Scenario | Turn-1 parent | Turn-10 parent | % of 300K rot |
|---|---:|---:|---:|
| Preload all | 41,649 | 41,649 | 13.88% |
| Router + lazy | 903 | 14,710 | 4.90% |
| Router + lazy + subagent | 903 | 1,403 | 0.47% |

### Headline

Router + subagent reduces turn-1 parent context by **87%** for drupal-meta-skills and **98%** for a11y-meta-skills. At turn 10, after the user has invoked exactly one skill, the reductions are **81%** and **97%**.

## Why the two bundles diverge

drupal-meta-skills and a11y-meta-skills look superficially similar, but their `SKILL.md` files do very different things.

**drupal-meta-skills' `drupal-planner/SKILL.md`** is 2,124 tokens. It contains routing logic (a keyword→sub-planner table), a "use when / don't use when" block, a companion-skills list, and a `Steps` section whose step 5 reads:

```
Route to planner agent: Delegate planning to the drupal-planner agent.
Agent(subagent_type="drupal-planner", model="opus", prompt=<planning_prompt>)
```

The planner's real protocol — 32,947 characters of it — lives in `.claude/agents/drupal-planner.md`. The `SKILL.md` is a stub that hands off to a subagent. This is the router + lazy + subagent pattern in production.

**a11y-meta-skills' `a11y-planner/SKILL.md`** is 17,716 tokens. The frontmatter is 105 tokens. The other 17,611 tokens are the full planner protocol, loaded inline. There *is* an `a11y-planner.md` agent file (37,227 chars) — but the `SKILL.md` contains its own full protocol alongside it. Install the bundle, open a session, and 17K tokens of planner protocol is in your parent context whether you're planning accessibility this hour or fixing a CI failure.

This is not a critique of a11y-meta-skills. It is a description of what "preload-all" looks like in real code. Every bundle starts this way. The question is when it becomes a problem.

## When preload starts hurting

Preload is fine when:

1. The bundle is small (drupal-meta-skills' 8,807 preload tokens is <3% of the rot zone).
2. The session uses every skill frequently.
3. The session is short enough that cache-cold events don't dominate.

Preload starts hurting when:

1. The bundle is large enough that the 70% soft-rot warning fires earlier (210K budget; a 41K preload eats 20% of the headroom on turn 1).
2. The session uses one or two skills out of many, which is the default case for most sessions.
3. The session goes idle for >5 minutes. Then the 1.25× re-cache premium applies to every preloaded skill byte. For a 41K-token preload, that's a meaningful cold-cache tax on each TTL expiry.

## Seven upgrades

Each of this repo's helpers corresponds to a cost mechanic. All seven land on the router pattern:

1. **Stubs-only at boot** — `SKILL.md` carries `name` + `description` + a handoff directive. The protocol moves to `.claude/agents/<name>.md`. Mechanic: `watching-cost/`.
2. **Subagent-isolated execution** — the handoff spawns an `Agent` call. Skill body never hits the parent. Mechanic: `subagent-isolation/`.
3. **Cache-stable router prompt** — router never rewrites itself mid-session. Keeps the conversation prefix stable and cache-friendly. Mechanic: `idle-tax/`.
4. **Rot-zone budget for stubs** — cap preloaded stub table at 5K tokens (~1.6% of rot zone). Policy, enforced in `CONTRIBUTING.md`. Mechanic: `just-one-more-turn/`.
5. **Effort floor for the router** — classification is not `xhigh` work. Pin to `high`. Mechanic: `effort-control/`.
6. **Auto-persist last-routed skill** — Stop hook writes the last route; next turn's router can no-op if the domain hasn't changed. Mechanic: `auto-persist/`.
7. **Post-compact stub rehydration** — verify the stub table survived compaction; re-inject if not. Mechanic: `compact-gamble/`.

The full spec with per-upgrade rationale and expected savings is in `meta-router-analysis/improvements/router-v2-spec.md`.

## What you can steal today

This repo ships seven standalone helpers. Each has its own blog post; each installs independently. The ones most directly relevant to anyone writing or using skills:

- [`subagent-isolation/`](../subagent-isolation/) — warns when your session has read >50 unique files. If you're using skills that read a lot of files, you want this.
- [`watching-cost/`](../watching-cost/) — warns when tool output accumulates past 25K / 50K / 100K tokens. Skills whose bodies bleed into tool output (reading other skill files, examining config) light this up fast.
- [`just-one-more-turn/`](../just-one-more-turn/) — warns as you approach the rot zone. Preloaded skill bundles get you there faster than you'd expect.
- [`idle-tax/`](../idle-tax/) — warns when your prompt cache is about to go cold. Pairs with `/save-session` for graceful handoff.

None of these care what your skills look like. They measure behavior, not structure. Install the ones that matter and let the thresholds surface the problems.

## A note on meta-skill repos

Zivtech maintains several Claude Code meta-skill bundles:

- Public: [`drupal-planner`](https://github.com/zivtech/drupal-planner), [`drupal-critic`](https://github.com/zivtech/drupal-critic), [`react-critic`](https://github.com/zivtech/react-critic), [`harsh-critic`](https://github.com/zivtech/harsh-critic), [`hr-compliance`](https://github.com/zivtech/hr-compliance).
- Public bundles measured above: [`drupal-meta-skills`](https://github.com/zivtech/drupal-meta-skills), [`a11y-meta-skills`](https://github.com/zivtech/a11y-meta-skills).

The improvements in this post will land in the public bundles first, and roll through the single-skill repos as each one is touched. If you're writing your own meta-skill bundle, the spec in `meta-router-analysis/improvements/router-v2-spec.md` is the checklist.

## Reproducing the benchmark

```bash
git clone https://github.com/zivtech/claude-cost-helpers
cd claude-cost-helpers/meta-router-analysis/benchmark
python3 scenarios.py --markdown
```

The script clones the two bundles into `/tmp/meta-skills-bench/`, measures every `SKILL.md`, and prints the same tables this post cites. No dependencies beyond `python3`, `git`, and an internet connection to reach GitHub.

## What's next

- The companion piece, [`meta-router-analysis/drupal-ai-evaluation.md`](drupal-ai-evaluation.md), looks at Drupal's 2026 AI roadmap through this lens and proposes concrete changes to the `ai_best_practices` project and the draft agent-skills issue.
- If you build skills and want this series to measure your bundle, open an issue on [`claude-cost-helpers`](https://github.com/zivtech/claude-cost-helpers) with the repo URL.

The meta-skill tax is real, it's measurable, and it's almost entirely avoidable. The router-and-subagent pattern is not new; what's new is having numbers for when it matters.
