# Meta-Router Analysis

Research artifacts on meta-skill loading strategy — preload vs router+lazy vs router+lazy+subagent — grounded in empirical measurements of two real public meta-skill bundles before and after a router-v2 refactor.

## Not a helper

The eight siblings in this repo (`idle-tax/`, `just-one-more-turn/`, `subagent-isolation/`, `compact-gamble/`, `watching-cost/`, `delegation-cost/`, `effort-control/`, `auto-persist/`) follow the helper pattern: hook script, slash commands, settings snippet, install.sh, uninstall.sh. This directory does not. It ships measurements, a spec, a blog post, and an evaluation. No hook, no slash command, no install. It's a reading, not a tool.

## What's here

```
meta-router-analysis/
├── README.md                      # this file
├── benchmark/
│   ├── count_tokens.py            # char/4 estimator (matches watching-cost + just-one-more-turn)
│   ├── scenarios.py               # clones each bundle at before/after refs and runs F/A/C comparison
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

The script clones four checkouts into `/tmp/meta-skills-bench/` (override with `--cache-dir`):

| Bundle | Ref | Role |
|---|---|---|
| [zivtech/drupal-meta-skills](https://github.com/zivtech/drupal-meta-skills) | `main` | before |
| [zivtech/drupal-meta-skills](https://github.com/zivtech/drupal-meta-skills) | `router-v2-trim` | after (surgical trim) |
| [zivtech/a11y-meta-skills](https://github.com/zivtech/a11y-meta-skills) | `main` | before |
| [zivtech/a11y-meta-skills](https://github.com/zivtech/a11y-meta-skills) | `router-v2-refactor` | after (full router-v2 port) |

Zero dependencies beyond `python3`, `git`, and internet access to reach GitHub. To measure individual files:

```bash
python3 benchmark/count_tokens.py <path/to/SKILL.md> [...]
```

## Headline numbers

From `benchmark/results.md` — three scenarios per bundle, two refs per bundle:

- **F. Flattened (straw-man)** — every SKILL.md body and every agent body preloaded.
- **A. As-implemented** — what the bundle does at the measured ref.
- **C. Optimized (simulated)** — SKILL.md files reduced to frontmatter stubs; router + subagent.

| Bundle | F | A | A vs F | Δ vs other ref |
|---|---:|---:|---:|---:|
| drupal-meta-skills @ main | 54,630 | 9,307 | 83% | — |
| drupal-meta-skills @ router-v2-trim | 51,714 | **6,391** | **88%** | -31% on A |
| a11y-meta-skills @ main | 60,175 | 42,149 | 30% | — |
| a11y-meta-skills @ router-v2-refactor | 29,357 | **1,465** | **95%** | **-96.5% on A** |

drupal-meta-skills already implemented the router-to-agent pattern on `main` and saves 83% vs the straw-man. The `router-v2-trim` branch tightens that to 88% by removing implementation-detail sections from each SKILL.md. a11y-meta-skills on `main` saved only 30% vs the straw-man because its SKILL.md files duplicated the full protocol inline; the `router-v2-refactor` branch moves the protocol into agents and saves 95%.

The empirical "after" measurements land within 4% of the simulated C scenario for the same bundle — validating the simulator as a predictor for any bundle not yet refactored.

Thresholds used:

- **Rot zone** — 300,000 tokens (`just-one-more-turn/` default).
- **Subagent-isolation warning** — 50 unique files (`subagent-isolation/` default).
- **Cache TTL** — 300 seconds (`idle-tax/`, Anthropic prompt cache). *Update 2026-09-01: Claude Code sessions now normally run on the 1-hour TTL (see `idle-tax/README.md`). The per-event volatile-token math below is unchanged; only the frequency of cold-cache events drops.*
- **Effort pin** — `CLAUDE_CODE_EFFORT_LEVEL=high` (`effort-control/`).

## How to read these files

- Start with `blog-meta-skills-cost.md` — the narrative, accessible to anyone familiar with Claude Code.
- Drill into `benchmark/results.md` for per-file numbers and strategy breakdown.
- Read `improvements/router-v2-spec.md` when you want to build or refactor your own meta-skill bundle.
- Read `drupal-ai-evaluation.md` if you care about the Drupal AI initiative's 2026 roadmap and where cost-aware skills fit into it.

## Scope

**In scope.** Measuring real public bundles. Proposing portable upgrades that work across agent clients (Claude Code, Codex, Cursor) because they only change how skills are packaged, not how clients load them. Informing the Drupal AI initiative's planning.

**Out of scope.** Filing issues on drupal.org — that is a maintainer decision. Replacing the `char/4` estimator with tiktoken — the relative differences are robust, and zero-dependency reproducibility matters more than ±15% accuracy on absolute counts.

## License

GPL-3.0-or-later, matching the rest of this repo. See `../LICENSE` (each helper ships its own copy).
