# Drupal AI Initiative — Skills Planning Evaluation

A reading of the Drupal AI initiative's 2026 plans through the cost-mechanics lens developed in this repo and in [`blog-meta-skills-cost.md`](blog-meta-skills-cost.md). Proposes five concrete changes to the planning, each grounded in a measured helper from this series.

## The sources

- [Drupal's AI roadmap for 2026](https://www.drupal.org/blog/drupals-ai-roadmap-for-2026) — the official AI Initiative Leadership Team plan. Names eight capabilities; one of them is "Context management" and another is "Background agents."
- [Dries Buytaert's companion post](https://dri.es/drupal-ai-roadmap-for-2026) — expands on the eight capabilities.
- [Proposal: First-class support for agent-skills, drupal.org/project/ai #3565489](https://www.drupal.org/project/ai/issues/3565489) — open issue in the AI module's queue proposing Drupal core / AI module support for the Claude Code agent-skills spec.
- [`ai_best_practices`](https://www.drupal.org/project/ai_best_practices) — the canonical AI-guidance repo that replaced the now-obsolete [`ai_skills`](https://www.drupal.org/project/ai_skills) project.
- [Agentic Skills project (obsolete)](https://www.drupal.org/project/ai_skills) — predecessor; shipped `drupal-coding-standards`, `drupal-issue-queue`, and `drupal-contribute-fix`.

## What's planned

The 2026 roadmap identifies eight capabilities: Page generation, Context management, Background agents, Design system integration, Content creation and discovery, Advanced governance, Intelligent website improvements, and one more (eight in total — the roadmap post lists them). Across all eight, there is no discussion of:

- Token budgets for skill bundles.
- Runtime loading strategy (preload, lazy-load, router).
- Cache-cost exposure for long editorial sessions.
- Subagent delegation as a context-isolation tool.
- Effort-level defaults for generative vs classification tasks.

The `ai_best_practices` project positions itself as a "CANONICAL place to put opinionated Drupal best practice guidance for AI agents (and their humans)." It is a knowledge repository organized through a README and CONTRIBUTING guide. It is not a runtime loader.

The obsolete `ai_skills` project shipped three skills organized in a `skills/` directory with a PHP-based validator for merge requests. Its skills had no explicit loading model — the assumption was each agent client would load them as it saw fit.

## Five gaps

### Gap 1 — No token-budget target for a canonical Drupal skill bundle

The measurements in [`blog-meta-skills-cost.md`](blog-meta-skills-cost.md) show that a four-skill a11y bundle can cost 41,649 tokens on turn 1. A canonical Drupal skill bundle covering the eight 2026 capabilities — content modeling, media, editorial workflow, search, multisite, decoupled, theme, governance — plus contrib-maintained extensions, can trivially exceed 100K tokens if each skill follows the preload-heavy pattern. That's a third of the rot zone spent on Drupal knowledge the session may never touch.

The `ai_best_practices` project should publish a **turn-1 token budget envelope**. A reasonable starting number: **≤10K tokens for the canonical bundle's stub layer**, **≤30K tokens per individual skill body** (with most skills under 5K). Skills exceeding the per-skill ceiling get flagged in CI the same way code style does.

### Gap 2 — No router pattern

`ai_best_practices` is a knowledge repo, not a runtime discovery layer. When an agent (Claude, Codex, Cursor, Drush-embedded assistant) launches a Drupal session, it has no canonical mechanism to say "load only the skills relevant to *this* prompt."

The `drupal-planner/SKILL.md` pattern in [`zivtech/drupal-meta-skills`](https://github.com/zivtech/drupal-meta-skills) — stubs that delegate to `.claude/agents/` — is a working example. The core idea is portable across agent clients because the stub is just YAML frontmatter and a hand-off directive.

**Proposal.** Adopt a stubs-first router pattern in `ai_best_practices`. Each skill ships a stub (name + description + handoff) alongside an optional agent file. A minimal `router.md` tells the agent client: "load stubs at startup; load a body only when the stub's description matches the current task." The router.md is 500 tokens of prose, reusable across all Drupal skills, and doesn't require any changes to Claude Code / Codex / Cursor themselves — those clients already honor the "frontmatter first, body on demand" contract.

### Gap 3 — No cache-cost awareness for long editorial sessions

Background agents, one of the eight 2026 capabilities, are by definition long-running. "AI that works without being prompted, responding to triggers and schedules" is the exact failure mode `idle-tax/` warns about: a background agent triggers once, sits idle 10 minutes, triggers again, and every "again" pays the 1.25× cold-cache premium.

**Proposal.** Specify that Drupal background-agent infrastructure:

1. Keeps per-agent prompt prefixes stable (cache-friendly).
2. Emits a cache-cold-exposure metric to the Drupal admin UI: minutes idle since last trigger, predicted next re-cache cost tier.
3. Offers a `drush ai:warm-cache <agent-id>` command for scheduled runs that want to pre-warm the cache just before an expected trigger window.

These mirror the `idle-tax/` helper's `/save-session` / `/resume-session` pattern, adapted for headless background runs.

### Gap 4 — No subagent-isolation discipline

Drupal contrib historically optimizes for composability at the module level. When that reflex transfers to skills, it manifests as "every module contributes its skills to the global skill pool." That is the preload-all pattern, scaled by the contrib catalog. It runs into the `subagent-isolation/` 50-file threshold almost immediately once a few modules install their own skill bundles.

**Proposal.** Make subagent delegation the default for any skill whose body exceeds ~3K tokens. This is a policy the `ai_best_practices` CONTRIBUTING guide can enforce. For skills smaller than 3K tokens, inline execution is fine. For larger skills, a `handoff: <agent-type>` directive in the stub is mandatory.

Contrib modules that ship their own skills should follow the same rule. A validator in `ai_best_practices` (and in the AI module's issue queue, per #3565489's first-class support proposal) can refuse skills that violate it, the same way Drupal core's coding-standards job refuses PRs with PSR-2 violations.

### Gap 5 — No effort-level guidance

Drupal governance and workflow tasks — enforcing an editorial approval, validating a taxonomy update, checking a config split — are classification or rule-based work. They do not need `xhigh` reasoning. Creative tasks — planning a content model, drafting a migration strategy, generating page layouts — do.

Without explicit guidance, agent clients default to their model's default effort level. For Opus 4.7 that's `xhigh`, which costs more for no benefit on the classification tasks.

**Proposal.** `ai_best_practices` ships an effort-level recommendation matrix:

| Task class | Recommended effort | Rationale |
|---|---|---|
| Routing / skill selection | `high` | Classification. |
| Governance checks (workflow state, access) | `high` | Rule-based. |
| Content creation / page generation | `xhigh` or `max` | Creative. |
| Context management (knowledge retrieval) | `high` | Retrieval is not reasoning. |
| Background agents (scheduled) | `high` | Volume favors cost. |
| Design system integration (component generation) | `xhigh` | Requires aesthetic judgment. |
| Intelligent website improvements (performance / a11y suggestions) | `xhigh` | Requires diagnosis. |

For sites using Claude Code, this dovetails with `effort-control/` — set `CLAUDE_CODE_EFFORT_LEVEL=high` at the shell level, escalate per-skill with `/deep` when a creative task genuinely warrants it.

## Summary

| Gap | Proposal | Helper that informs it |
|---|---|---|
| No token budget | Publish a turn-1 envelope (≤10K stubs, ≤30K per body) | `just-one-more-turn/` |
| No router pattern | Adopt stubs-first router in `ai_best_practices` | `watching-cost/` |
| No cache awareness for background agents | Per-agent cache metrics + `drush ai:warm-cache` | `idle-tax/` |
| No subagent-isolation policy | Mandatory handoff for skills >3K tokens | `subagent-isolation/` |
| No effort-level matrix | Publish task-class recommendations | `effort-control/` |

## Concrete next actions

If the user decides to surface any of this upstream:

1. **Open an issue on [`ai_best_practices`](https://www.drupal.org/project/ai_best_practices)** — "Propose token-budget envelope for canonical skill bundle." Cite `meta-router-analysis/benchmark/results.md` and [`blog-meta-skills-cost.md`](blog-meta-skills-cost.md).
2. **Comment on [#3565489](https://www.drupal.org/project/ai/issues/3565489)** — contribute the router + stubs-first pattern as the loading model for first-class agent-skills support.
3. **Offer the cost-helper hooks as an `ai_cost_insights` Drupal module** — a thin module that emits `UserPromptSubmit` / `PostToolUse`-equivalent events in the format this repo's helpers already understand. Makes cost mechanics work in Drupal's web-embedded agent sessions, not just in Claude Code terminal sessions.
4. **Seed the effort-level matrix** as a `docs/effort-levels.md` in `ai_best_practices`. Short document, big payoff.

This evaluation is a deliverable of this repo, not a drupal.org posting. Publishing it upstream is the user's decision.
