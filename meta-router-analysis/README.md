# Meta-Router Analysis

Research artifacts on meta-skill loading strategy — preload vs router+lazy vs router+lazy+subagent — grounded in measurements of two real public meta-skill bundles.

## Not a helper

The eight siblings in this repo (`idle-tax/`, `just-one-more-turn/`, `subagent-isolation/`, `compact-gamble/`, `watching-cost/`, `delegation-cost/`, `effort-control/`, `auto-persist/`) follow the helper pattern: hook script, slash commands, settings snippet, install.sh, uninstall.sh. This directory does not. It ships measurements, a spec, a blog post, and an evaluation. No hook, no slash command, no install. It's a reading, not a tool.

## What's here

```
meta-router-analysis/
├── README.md                      # this file
├── benchmark/
│   ├── count_tokens.py            # char/4 estimator (matches watching-cost + just-one-more-turn)
│   ├── scenarios.py               # preload / lazy / lazy+subagent comparison driver
│   └── results.md                 # benchmark output + per-file measurements
├── improvements/
│   └── router-v2-spec.md          # seven upgrades mapping this repo's helpers to the router
├── blog-meta-skills-cost.md       # blog post for the Economics of Claude Code series
└── drupal-ai-evaluation.md        # Drupal AI initiative gap analysis + proposals
```

## Reproducing the benchmark

```bash
cd meta-router-analysis/benchmark
python3 scenarios.py --markdown
```

The script clones [zivtech/drupal-meta-skills](https://github.com/zivtech/drupal-meta-skills) and [zivtech/a11y-meta-skills](https://github.com/zivtech/a11y-meta-skills) into `/tmp/meta-skills-bench/` (override with `--cache-dir`), measures every `SKILL.md` file, and prints the tables cited in `results.md` and the blog post. Zero dependencies beyond `python3`, `git`, and internet access to reach GitHub.

To measure individual files:

```bash
python3 benchmark/count_tokens.py <path/to/SKILL.md> [...]
```

## Headline numbers

From `benchmark/results.md` — comparing three scenarios per bundle:

- **F. Flattened (straw-man)** — every SKILL.md body and every agent body preloaded.
- **A. As-implemented** — what the bundle does today.
- **C. Optimized (router-v2)** — SKILL.md files reduced to frontmatter stubs; router + subagent.

| Bundle | F (straw-man) | A (today) | C (optimized) | A vs F | C vs A |
|---|---:|---:|---:|---:|---:|
| drupal-meta-skills | 54,630 | 9,307 | 1,657 (simulated) | saves 83% | saves 82% more |
| a11y-meta-skills (upstream) | 60,175 | 42,149 | 1,403 (simulated) | saves 30% | saves 97% more |
| **a11y-meta-skills (refactored, empirical)** | **29,357** | **1,465** | 1,410 (simulated) | **saves 95%** | negligible |

drupal-meta-skills already does most of the work — its SKILL.md files act as routers that delegate to agent bodies via subagent. a11y-meta-skills keeps its agents on disk but duplicates the full protocol inline in SKILL.md, so most of the weight still preloads.

A concrete router-v2 port of the a11y bundle lives at [`refactored/a11y-meta-skills/`](refactored/a11y-meta-skills/). Its empirical turn-10 parent context is **1,465 tokens** — a 96.5% reduction against the upstream bundle's 42,149, and within 4% of the simulated C-scenario prediction.

Thresholds used:

- **Rot zone** — 300,000 tokens (`just-one-more-turn/` default).
- **Subagent-isolation warning** — 50 unique files (`subagent-isolation/` default).
- **Cache TTL** — 300 seconds (`idle-tax/`, Anthropic prompt cache).
- **Effort pin** — `CLAUDE_CODE_EFFORT_LEVEL=high` (`effort-control/`).

## How to read these files

- Start with `blog-meta-skills-cost.md` — the narrative, accessible to anyone familiar with Claude Code.
- Drill into `benchmark/results.md` for per-file numbers and strategy breakdown.
- Read `improvements/router-v2-spec.md` when you want to build or refactor your own meta-skill bundle.
- Read `drupal-ai-evaluation.md` if you care about the Drupal AI initiative's 2026 roadmap and where cost-aware skills fit into it.

## Scope

**In scope.** Measuring real public bundles. Proposing portable upgrades that work across agent clients (Claude Code, Codex, Cursor) because they only change how skills are packaged, not how clients load them. Informing the Drupal AI initiative's planning.

**Out of scope.** Modifying the measured bundles themselves — the spec is the input to that work, the rollout is separate. Filing issues on drupal.org — that is a maintainer decision. Replacing the `char/4` estimator with tiktoken — the relative differences are robust, and zero-dependency reproducibility matters more than ±15% accuracy on absolute counts.

## License

GPL-3.0-or-later, matching the rest of this repo. See `../LICENSE` (each helper ships its own copy).
