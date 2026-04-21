# Empirical Task Suite

This suite is designed to collect Codex CLI/Desktop evidence against the same broad questions raised by the Claude blog series without assuming that Codex behaves identically.

Use the passive harness in [harness/README.md](./harness/README.md) while running these tasks.

## Evidence rules

- Verify product capability claims against current OpenAI docs before interpreting a result.
- Treat the harness logs as primary evidence for session lifecycle timing, session ids, and model ids.
- Treat `codex exec --json` logs as primary evidence for per-turn usage and command-output size in non-interactive runs.
- Treat `/status` captures as primary evidence for context usage where the hook payload does not expose it.
- Treat reasoning effort as a manual note unless you have an authoritative runtime surface that records it directly.
- Do not generalize from one run. Capture at least one positive and one negative case for each publishable claim.
- For non-interactive `exec` runs, prefer [harness/parse_exec_json.py](./harness/parse_exec_json.py) to extract usage and command-output lengths.

## Standard runtime settings

Use these model defaults unless a scenario says otherwise:

- baseline coding/control runs: `gpt-5.3-codex` at `medium`
- difficult comparison or synthesis runs: `gpt-5.2-codex` at `high`
- meta-synthesis and recommendation: `gpt-5.4` at `high`

Sources:

- [GPT-5.3-Codex](https://developers.openai.com/api/docs/models/gpt-5.3-codex)
- [GPT-5.2-Codex](https://developers.openai.com/api/docs/models/gpt-5.2-codex)
- [GPT-5.4](https://developers.openai.com/api/docs/models/gpt-5.4)

## Scenario 1: Idle-gap probe

### Goal

Check whether Codex shows materially different behavior after short vs long inactivity windows and whether any public framing should use exact-minute language.

### Steps

1. Start a clean session in the same repo.
2. Ask a small, deterministic prompt that causes minimal tool use.
3. Record `/status`.
4. Wait about 2 minutes and send a second prompt with the same broad prefix.
5. Record `/status`.
6. Wait about 7-10 minutes and send a third prompt with the same broad prefix.
7. Record `/status` again.

### Positive case

The longer-gap run shows evidence of cooler cache behavior or materially different latency/cost/context handling than the short-gap run.

### Negative case

The short-gap and long-gap runs are operationally similar enough that a strong idle-tax thesis would be overstated.

### Evidence to keep

- harness `UserPromptSubmit` timestamps
- model id from hook payloads
- `/status` captures before the second and third prompt
- manual note on visible latency or changed runtime behavior

### Interpretation rule

If Codex behavior does not materially support an exact-minute claim, the public thesis must be rewritten around "idle gaps can cool the cache" instead of a Claude-style exact penalty claim.

## Scenario 2: Long-session accumulation

### Goal

Measure whether long sessions show meaningful context growth and whether fresh-session resets improve the workflow economics story.

### Steps

1. Start a clean session.
2. Perform 10-15 controlled turns in the same thread, each asking Codex to inspect or reason about a small, real repo change or file subset.
3. Record `/status` every 3-4 turns.
4. End the task.
5. Start a fresh session with a short handoff and repeat a smaller continuation task.
6. Record `/status` again.

### Positive case

Context usage and turn count climb materially in the long session, and the fresh session clearly resets the working surface.

### Negative case

Context growth is too small or too opaque to support a strong long-session economics claim in Codex.

### Evidence to keep

- harness `UserPromptSubmit` counts
- `/status` captures at checkpoints
- manual handoff size and final continuation notes

### Interpretation rule

This scenario is mainly about context accumulation, not about proving any exact pricing delta.

## Scenario 3: Parent vs subagent exploration

### Goal

Test whether subagent/delegation patterns appear to preserve parent-session focus and context better than broad parent-only exploration.

### Steps

1. Create a direct-exploration run: ask the parent session to survey a broad repo area and summarize findings.
2. Record `/status` before and after.
3. Create a second run where the same broad survey is delegated to a subagent or separate agent thread.
4. Record `/status` before and after in the parent.

### Positive case

The delegated path keeps the parent session materially leaner or cleaner to continue working in.

### Negative case

Current Codex surfaces do not expose enough difference to support an automatic helper or a strong public claim.

### Evidence to keep

- `/status` captures from the parent session
- manual note on what ran in the parent vs the delegated thread
- harness logs for prompt counts and any bash-output burden

### Interpretation rule

Because current Codex docs do not expose `Read|Glob|Grep` hook events, this scenario can support an article claim only if the observed difference is obvious enough to survive without an automatic detector.

## Scenario 4: Manual compaction behavior

### Goal

Evaluate whether Codex manual compaction creates a fidelity risk worth writing about, given that there is no documented `PreCompact` hook.

### Steps

1. Run a session long enough to create a meaningful amount of context.
2. Add 2-3 explicit constraints that can be checked later.
3. Run `/compact`.
4. Continue the task and see whether the constraints are preserved.
5. In a separate control run, start a fresh session with a curated handoff instead of compaction.

### Positive case

The compacted run loses fidelity or becomes less trustworthy than the curated handoff run.

### Negative case

Manual compaction is good enough that the stronger "compact gamble" framing would need to be softened.

### Evidence to keep

- pre-compact note listing the constraints
- post-compact continuation behavior
- `/status` snapshots before and after compaction
- curated handoff control result

### Interpretation rule

Even if a fidelity risk exists, it does not justify a Codex helper claim unless Codex exposes a documented pre-compact interception surface in the future.

## Scenario 5: Bash output carrying cost

### Goal

Measure the part of "watching cost" that Codex can currently expose directly: large `Bash` output landing in the session.

### Steps

1. Run a verbose bash-producing task through Codex.
2. Capture the `PostToolUse` event in the harness.
3. In a second run, ask Codex to redirect or filter the same command's output.
4. Compare bash-output chars/tokens and downstream `/status` context usage.

### Positive case

The verbose run produces materially larger `Bash` output and a visibly heavier session than the filtered or redirected run.

### Negative case

The difference is too small or too hard to observe to support a meaningful public claim.

### Evidence to keep

- harness `PostToolUse` records with `bash_output_chars` and estimated tokens
- command text
- `/status` captures after the verbose and filtered runs

### Interpretation rule

Any public helper claim must say "Bash output" or "shell output" unless Codex broadens `PostToolUse` beyond `Bash`.

## Minimum evidence needed before a post

Do not draft a public Codex companion post until the task suite yields:

- one positive and one negative case for idle-gap behavior
- one positive case showing meaningful long-session accumulation
- one positive or one conclusive negative case for delegated exploration
- one compaction comparison result
- one positive and one negative case for Bash output carrying cost

If the suite produces mixed results, use that as the backbone for a comparison post or internal memo instead of forcing a stronger thesis than the data supports.
