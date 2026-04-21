# Codex Companion Post Evaluation

Prepared on 2026-04-20 for evaluating whether the Claude-oriented cost helpers in this repo should become a Codex CLI/Desktop companion post and, eventually, a Codex-native helper set.

## Current recommendation

Do not publish a one-to-one Codex mirror of the Claude series.

A narrower Codex post is now supportable if it stays inside the measured evidence collected in [results/2026-04-20-live-evaluation.md](./results/2026-04-20-live-evaluation.md):

- long-session accumulation is real and observable,
- Bash output can create measurable carrying-cost pressure,
- and the idle-gap thesis must be rewritten for Codex rather than copied from Claude.

What is still not supportable is a stronger claim that Codex has the same exact cost mechanics, hook surfaces, or helper portability story as Claude Code.

The current implemented Codex subset now lives under [../codex-helpers/README.md](../codex-helpers/README.md).

## What is in this package

- [reality-audit.md](./reality-audit.md): short memo on repo inconsistencies, official Codex surfaces, and the current go/no-go recommendation.
- [compatibility-matrix.md](./compatibility-matrix.md): helper-by-helper portability table.
- [task-suite.md](./task-suite.md): fixed task suite for gathering empirical evidence in Codex CLI/Desktop.
- [helper-feasibility.md](./helper-feasibility.md): Codex-native re-spec for each helper and the smallest viable Codex helper set.
- [implementation-plan.md](./implementation-plan.md): phased implementation plan for the supportable Codex helper subset.
- [companion-post-brief.md](./companion-post-brief.md): conditional brief template to use only after the publication gate passes.
- [results/2026-04-20-live-evaluation.md](./results/2026-04-20-live-evaluation.md): first live Codex measurements and the revised publication recommendation.
- [harness/README.md](./harness/README.md): passive evaluation harness for Codex hooks.

This directory remains the source of truth for:

- what the Codex helpers are allowed to claim,
- what is still deferred,
- and why the implemented Codex lane is narrower than the Claude lane.

## Evaluation gate

Only publish a Codex companion post if both conditions are met:

1. At least 2-3 helper patterns are empirically shown to be portable or cleanly redesignable for Codex.
2. The public-facing claims are backed by Codex evidence collected with the harness in this package, not by analogy to Claude Code.

Right now, the safe public artifact is a comparison-style Codex post that explicitly distinguishes:

- what is proven in Codex,
- what only transfers conceptually,
- and what is not supportable on current Codex surfaces.

## Grounding sources

- [Codex hooks](https://developers.openai.com/codex/hooks)
- [AGENTS.md discovery](https://developers.openai.com/codex/guides/agents-md)
- [Codex CLI slash commands](https://developers.openai.com/codex/cli/slash-commands)
- [Codex app automations](https://developers.openai.com/codex/app/automations)
- [OpenAI prompt caching](https://developers.openai.com/api/docs/guides/prompt-caching)
- [GPT-5.3-Codex model page](https://developers.openai.com/api/docs/models/gpt-5.3-codex)
- [GPT-5.2-Codex model page](https://developers.openai.com/api/docs/models/gpt-5.2-codex)
- [GPT-5.4 model page](https://developers.openai.com/api/docs/models/gpt-5.4)

## Local runtime notes

These artifacts were prepared against the local runtime available in this workspace on 2026-04-20:

- `codex-cli 0.114.0`
- active Codex home at `~/.codex`

Those local notes are supportive evidence only. Official OpenAI docs remain the source of truth for capability claims.
