# Reality Audit

## Purpose

Determine whether the current Claude Cost Helpers repo can support a strict-evidence Codex companion post for Codex CLI/Desktop.

## Executive summary

The repository is now intentionally split into three layers:

- the main shipping helper code and installers are still Claude-oriented,
- a narrowed Codex implementation lane now lives under `codex-helpers/`,
- the Codex evidence and planning package lives under `codex-evaluation/`,
- and current Codex docs still expose only part of the surface a full Codex helper suite would need.

That means the right immediate move is not a one-to-one public Codex mirror of the Claude series. The right move is:

1. document the compatibility gap precisely,
2. collect Codex evidence with a passive harness,
3. then decide whether the post should be a true Codex companion post or a narrower comparison piece.

## Repo state that matters

The repo no longer needs to pretend it is already a Codex helper suite.

### Claude-oriented public artifacts

The public-facing README and helper READMEs/scripts still target Claude-specific paths and events, including:

- `~/.claude`
- `settings.json`
- `PreCompact`
- `PostToolUse` on `Read|Glob|Grep`
- Claude-specific environment and effort language

### Codex-oriented implementation and evaluation lanes

The Codex-specific work is now split intentionally:

- `codex-helpers/` contains the implemented narrowed subset
- `codex-evaluation/` contains:

- compatibility analysis,
- live measurements,
- and an implementation plan for a narrower Codex-native subset.

### Why this blocks a public post today

A public Codex post with a strict evidence bar still cannot treat the remaining differences as cosmetic. Current Codex docs use `~/.codex`, `hooks.json`, and an experimental hooks surface whose current runtime is narrower than the original Claude helper design assumes. Any post that papers over that gap would overstate portability.

## Official Codex surfaces relevant to this evaluation

### Hooks

Current Codex hooks are documented as experimental and discovered from `~/.codex/hooks.json` or `<repo>/.codex/hooks.json`. Current documented event support matters here:

- `SessionStart`, `UserPromptSubmit`, and `Stop` are available.
- `PreToolUse` and `PostToolUse` currently only emit `Bash`.
- There is no documented `PreCompact`.
- There is no documented `Read`, `Glob`, or `Grep` tool hook surface today.

Source: [Codex hooks](https://developers.openai.com/codex/hooks)

### AGENTS.md layering

Codex reads `AGENTS.md` from `~/.codex` and then layers project guidance from the repo root down toward the current working directory.

Source: [AGENTS.md discovery](https://developers.openai.com/codex/guides/agents-md)

### CLI/Desktop controls

Codex CLI exposes built-in `/model`, `/compact`, `/agent`, and `/status` commands. Those are useful for evaluation because they let the tester control model choice, compact manually, inspect agent threads, and record context usage.

Source: [Codex CLI slash commands](https://developers.openai.com/codex/cli/slash-commands)

### Automations

Codex app automations can explicitly choose model and reasoning effort, which matters for any future operationalized evaluation or recurring measurements.

Source: [Codex app automations](https://developers.openai.com/codex/app/automations)

### Prompt caching

OpenAI docs describe in-memory prompt cache retention as generally lasting 5-10 minutes of inactivity, with optional extended retention up to 24 hours on supported models. That is close enough to motivate an idle-gap evaluation, but not close enough to reuse Claude's exact "5-minute idle tax" framing without measurement.

Source: [Prompt caching](https://developers.openai.com/api/docs/guides/prompt-caching)

## Helper classification

The current docs-only classification is:

- `portable now`: `just-one-more-turn`, `auto-persist`
- `portable with redesign`: `idle-tax`, `watching-cost`, `effort-control`
- `not supportable today`: `subagent-isolation`, `compact-gamble`

See [compatibility-matrix.md](./compatibility-matrix.md) for the helper-by-helper breakdown.

## Smallest viable Codex helper set

If the repo eventually grows a true Codex helper lane, the smallest credible set is:

1. long-session awareness via `UserPromptSubmit`
2. passive stop-state persistence via `Stop`
3. bash-output carrying-cost warnings via `PostToolUse` on `Bash`
4. optional idle-gap awareness via `UserPromptSubmit`, but only after the idle-gap thesis is measured in Codex and the wording is rewritten around Codex's documented cache model

## Publication gate status

The gate is **partially passed for a narrowed post**.

Why:

- We now have live Codex evidence for long-session accumulation, Bash-output carrying cost, and the need to rewrite the idle-gap claim.
- We still do not have support for a one-to-one Claude mirror, especially around exact idle-gap penalty language, automatic file-read detection, or automatic pre-compact safety.

See [results/2026-04-20-live-evaluation.md](./results/2026-04-20-live-evaluation.md).

## Recommendation

Use this repo package as the evidence base.

The current best public artifact is a comparison post or a tightly scoped Codex companion post that says:

- "what transfers from Claude to Codex,"
- "what breaks on current Codex hook surfaces,"
- and "what would need to change before a true Codex helper suite exists."

Do not publish a post that implies:

- the same exact idle-tax story,
- the same helper coverage,
- or the same hookability across tools.

If a draft is started, it should be promoted from the conditional brief in [companion-post-brief.md](./companion-post-brief.md) and reviewed against the measured caveats first.
