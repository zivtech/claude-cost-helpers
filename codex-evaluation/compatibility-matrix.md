# Compatibility Matrix

This matrix compares the current Claude-oriented helper claims and implementations in this repo against Codex CLI/Desktop surfaces documented by OpenAI as of 2026-04-20.

Evidence strength uses three levels:

- `high`: official Codex docs expose the needed surface directly
- `medium`: the concept is supported, but some implementation detail is inferred or partial
- `low`: the concept is plausible, but current Codex docs do not expose the needed signal directly

## Matrix

| Helper | Claude claim | Current repo implementation | Current Codex-documented equivalent | Evidence strength | Portability verdict | Notes |
|---|---|---|---|---|---|---|
| `idle-tax` | Cold cache after idle gap creates a large economic penalty and should trigger a warning before or at prompt submit. | `UserPromptSubmit` hook, `~/.claude/.session-state`, exact 5-minute framing, Claude handoff commands. | Codex has `UserPromptSubmit` hooks, and OpenAI docs describe in-memory prompt caching as generally 5-10 minutes of inactivity by default. | `medium` | `portable with redesign` | The helper shape transfers, but the exact Claude "5-minute idle tax" wording does not. Codex wording must be rewritten to reflect documented OpenAI caching behavior and measured runtime evidence. Sources: [hooks](https://developers.openai.com/codex/hooks), [prompt caching](https://developers.openai.com/api/docs/guides/prompt-caching) |
| `just-one-more-turn` | Long sessions accumulate dead context and should trigger split/fresh-session advice. | `UserPromptSubmit` hook based on estimated turn-count growth. | Codex has `UserPromptSubmit`; CLI exposes `/compact` and `/status`, which makes long-session evaluation and manual split guidance feasible. | `high` | `portable now` | The concept is generic to long-running agent sessions and does not depend on a Claude-only tool surface. Source: [CLI slash commands](https://developers.openai.com/codex/cli/slash-commands) |
| `subagent-isolation` | File-heavy exploration belongs in subagents because the parent should not carry all read content forever. | `PostToolUse` on `Read|Glob|Grep`, counting unique files touched in the parent session. | Codex supports `/agent` and subagents conceptually, but current `PostToolUse` only emits `Bash`; there is no documented `Read|Glob|Grep` hook surface today. | `low` | `not supportable today` | The article concept may still transfer, but the helper cannot currently be implemented with the same automatic detection model on documented Codex surfaces. Sources: [hooks](https://developers.openai.com/codex/hooks), [CLI slash commands](https://developers.openai.com/codex/cli/slash-commands) |
| `compact-gamble` | Pre-compact backup and curated handoff are safer than relying on lossy auto-compact. | `PreCompact` hook plus `/safe-compact`. | Codex CLI has `/compact`, but current docs do not expose a documented `PreCompact` hook. | `high` for manual compaction, `low` for automatic pre-compact interception | `not supportable today` | Manual guidance is possible, but the helper's automatic safety-net behavior is not documented as available in Codex today. Sources: [hooks](https://developers.openai.com/codex/hooks), [CLI slash commands](https://developers.openai.com/codex/cli/slash-commands) |
| `watching-cost` | Large tool outputs silently inflate carrying cost for the rest of the session and should trigger warnings. | `PostToolUse` on all tools, estimating output size and cumulative output burden. | Codex `PostToolUse` currently only emits `Bash`, but it does include `tool_response`, which is enough for a Bash-only output-size watcher. | `high` for Bash-only variant | `portable with redesign` | A Codex version must explicitly narrow its claim from "all tools" to "Bash output only" unless Codex broadens the hook surface later. Source: [hooks](https://developers.openai.com/codex/hooks) |
| `effort-control` | Hidden or sticky high-effort defaults need explicit defense and one-shot escalation. | Claude-specific env pinning and `SessionStart` banner. | Codex supports session model/reasoning choice via `/model`, and automations can explicitly choose model and reasoning effort. `SessionStart` hooks exist for passive reminders. | `medium` | `portable with redesign` | The helper should become model/reasoning hygiene for Codex, not a Claude-specific defense against an Anthropic default behavior. Sources: [CLI slash commands](https://developers.openai.com/codex/cli/slash-commands), [automations](https://developers.openai.com/codex/app/automations), [GPT-5.3-Codex](https://developers.openai.com/api/docs/models/gpt-5.3-codex), [GPT-5.2-Codex](https://developers.openai.com/api/docs/models/gpt-5.2-codex), [GPT-5.4](https://developers.openai.com/api/docs/models/gpt-5.4) |
| `auto-persist` | Persist low-cost environmental state after every turn so resumability does not depend on manual narrative handoffs. | `Stop` hook writes structured session state to disk. | Codex has `Stop` hooks and exposes `cwd`, `transcript_path`, `last_assistant_message`, and the session id in hook input. | `high` | `portable now` | This is the cleanest current portability story in the repo. Source: [hooks](https://developers.openai.com/codex/hooks) |

## Resulting Codex stance

### Portable now

- `just-one-more-turn`
- `auto-persist`

### Portable with redesign

- `idle-tax`
- `watching-cost`
- `effort-control`

### Not supportable today

- `subagent-isolation`
- `compact-gamble`

## Implication for a public post

The matrix is strong enough to justify a Codex evaluation effort.

The matrix is not, by itself, strong enough to justify a public post that says:

- Codex behaves the same way Claude does,
- Codex cost visibility is hidden in the same way,
- or every helper in this repo already has a clean Codex equivalent.

Those claims require empirical runtime evidence, which is what the harness and task suite in this package are for.
