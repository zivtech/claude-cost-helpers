# a11y-meta-skills — Refactored (router-v2 demo)

A concrete router-v2 port of [`zivtech/a11y-meta-skills`](https://github.com/zivtech/a11y-meta-skills). Not a fork and not a drop-in replacement — it exists here so the `C. Optimized` scenario in `../../benchmark/results.md` is backed by an actual implementation instead of a simulation.

## What changed

Each of the four skills now has:

- A **stub `SKILL.md`** (127–269 tokens): frontmatter carried over from the upstream file (name, description, license, metadata), a 3–5 line `Route` / `Use when` / `Do not use when` block, and a `Agent(subagent_type="<name>", ...)` handoff.
- An **agent file** under `.claude/agents/<name>.md` with the full protocol. Existing agents (`a11y-planner.md`, `a11y-critic.md`) were copied from the upstream bundle unchanged. The agents for `a11y-test` and `perspective-audit` are new — their bodies were moved verbatim from the upstream SKILL.md files, so no protocol content was lost.

## Size delta

From `../../benchmark/results.md`:

| File | Upstream tokens | Refactored tokens | Δ |
|---|---:|---:|---:|
| `a11y-planner/SKILL.md` | 17,821 | 258 | -99% |
| `a11y-critic/SKILL.md` | 13,912 | 269 | -98% |
| `a11y-test/SKILL.md` | 8,112 | 229 | -97% |
| `perspective-audit/SKILL.md` | 1,804 | 209 | -88% |
| `.claude/agents/a11y-planner.md` | 9,279 | 9,279 | 0% (copied) |
| `.claude/agents/a11y-critic.md` | 9,279 | 9,247 | 0% (copied) |
| `.claude/agents/a11y-test.md` | — | 8,094 | new (moved) |
| `.claude/agents/perspective-audit.md` | — | 1,772 | new (moved) |

Turn-10 parent context (the effective cost of installing the bundle and invoking one skill): **42,149 → 1,465 tokens (-96.5%)**.

## Why it lives in this repo

Modifying `zivtech/a11y-meta-skills` upstream is out of scope for this PR. The refactor ships here as:

1. A measurement artifact — `scenarios.py` discovers and measures it alongside the upstream bundles.
2. A working template for anyone porting a similar bundle. The diff of any upstream SKILL.md against its refactored counterpart is the recipe.
3. An empirical validation of the `C. Optimized` simulation. The refactored bundle's `A. As-implemented` row lands within 4% of the simulated C row for the upstream bundle — so the simulation is trustworthy for predicting the outcome of a router-v2 port on other bundles.

## Not included

- Top-level repo files (`AGENTS.md`, `CLAUDE.md`, `README.md`, `CONTRIBUTING.md`, `evals/`, `templates/`, `docs/`). Those are unchanged by router-v2 and out of scope for a measurement demo.
- The `perspective-audit/references/` directory (`arrm-perspective-mapping.md`, `perspectives.md`). These are reference material the agent can read from disk on demand; they don't affect the SKILL.md-vs-agent split this demo illustrates.

## License

The four SKILL.md stubs in this directory are original to this repo, GPL-3.0-or-later (matching the rest of `claude-cost-helpers`). The agent files copied from the upstream bundle retain their Apache-2.0 license and original frontmatter.
