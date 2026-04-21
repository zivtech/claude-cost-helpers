# Conditional Codex Companion Post Brief

Status: blocked pending publication-gate evidence.

Do not use this brief for a public post until the empirical task suite in [task-suite.md](./task-suite.md) has produced enough evidence to pass the gate described in [README.md](./README.md).

## Use this brief only if all inputs exist

- completed compatibility matrix
- completed empirical task suite results
- final helper classification
- explicit list of claims that are proven in Codex
- explicit list of claims that remain analogy-only and must stay out of the post

## Audience

- developers already using Codex CLI/Desktop
- teams evaluating whether Claude-oriented workflow lessons transfer to Codex
- technical readers who want operational guidance, not product hype

## Core thesis

The post should be about Codex context economics and workflow design, not about proving that Codex is "the same as Claude."

The safe thesis is:

> Some of the invisible workflow costs discussed in the Claude series also appear in Codex, but the supporting surfaces and the right mitigations differ enough that the Codex version has to be measured and stated on its own terms.

## Required sections

1. What transferred from the Claude analysis
2. What did not transfer cleanly
3. What current Codex docs actually expose
4. Measured findings from Codex CLI/Desktop
5. Helper portability table
6. Where Codex differs from Claude
7. Caveats and open questions

## Required evidence blocks

- one table summarizing the helper portability verdicts
- one short section on Codex hooks limitations today
- one short section on prompt caching wording and why the Claude idle-tax framing was rewritten
- one section explicitly narrowing `watching-cost` to `Bash output` if that remains the documented surface

## Must-include caveats

- current Codex hooks are experimental
- current `PostToolUse` is documented as `Bash` only
- there is no documented `PreCompact` hook today
- prompt caching wording follows OpenAI docs and measured behavior, not Claude assumptions

## Claims to avoid

- "Codex hides costs from you"
- "Codex has the same 5-minute idle tax as Claude"
- "Every helper in this repo already has a Codex equivalent"
- "We proved energy use directly"

## Suggested title directions

- "What Transfers from Claude's Context Economics to Codex, and What Doesn't"
- "Codex Session Hygiene: The Workflow Patterns That Actually Hold Up"
- "Context Economics in Codex: Measured Patterns, Not Assumptions"

## Pre-publication review

Before drafting:

- run a plan or proposal critique against the evidence structure

Before publishing:

- run a research-communications fidelity review on the claim structure
- run a copy/content review on clarity, caveats, and audience fit
