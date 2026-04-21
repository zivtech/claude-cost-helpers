# Codex Evaluation Harness

This harness logs Codex hook payloads to disk so the Codex companion-post evaluation can be grounded in runtime evidence instead of analogy.

It is intentionally passive:

- it does not block prompts,
- it does not rewrite tool output,
- it does not inject additional context,
- and it does not change agent behavior.

## What it captures

- `SessionStart`: session id, model, startup source
- `UserPromptSubmit`: prompt timing, prompt size, prompt preview hash
- `PostToolUse` on `Bash`: shell command, output size, rough token estimate, short output preview
- `Stop`: last-assistant-message size, transcript path, stop metadata

## Observed runtime note

In local testing with `codex-cli 0.114.0`, repo-local hooks fired reliably for `SessionStart` and `Stop` during `codex exec` and `codex exec resume` runs.

In those same non-interactive runs, `UserPromptSubmit` and `PostToolUse` were not observed in the hook log even when Bash commands clearly executed in the JSON event stream. Because of that:

- use hook logs for lifecycle timing and session metadata,
- and use `codex exec --json` logs for usage and command-output evidence in non-interactive evaluation runs.

This may be a runtime limitation, a mode difference, or a version-specific behavior. Treat it as observed evidence, not a product-wide guarantee.

## What it does not capture

- non-Bash tool output
- authoritative reasoning-effort values from the hook payload
- direct prompt-cache hit/miss numbers
- direct billing or energy telemetry

Those missing pieces should be recorded manually where needed in the task suite.

## Files

- [hooks.json.example](./hooks.json.example): example hook config for repo-local Codex evaluation.
- [capture_event.py](./capture_event.py): passive event logger.
- [summarize_logs.py](./summarize_logs.py): aggregate JSONL logs into a readable session summary.
- [parse_exec_json.py](./parse_exec_json.py): extract usage and command-output lengths from `codex exec --json` logs.

## Install

### 1. Enable hooks

Current Codex docs say hooks are behind a feature flag in `~/.codex/config.toml`:

```toml
[features]
codex_hooks = true
```

Source: [Codex hooks](https://developers.openai.com/codex/hooks)

### 2. Add a repo-local hooks file

Copy this example to a repo-local `.codex/hooks.json` in the workspace you want to evaluate:

```bash
mkdir -p .codex
cp codex-evaluation/harness/hooks.json.example .codex/hooks.json
```

Repo-local hooks are preferable for the evaluation because they keep the measurement surface narrow and avoid editing global user config beyond the feature flag.

### 3. Run Codex from the workspace being evaluated

Start or resume Codex in the target repo, then run the scenarios from [../task-suite.md](../task-suite.md).

### 4. Summarize the results

```bash
python3 codex-evaluation/harness/summarize_logs.py
```

For `codex exec --json` output:

```bash
python3 codex-evaluation/harness/parse_exec_json.py /path/to/exec-run.jsonl
```

You can also point the summarizer at a specific log file:

```bash
python3 codex-evaluation/harness/summarize_logs.py --log ~/.codex/evals/codex-companion/events.jsonl
```

## Output location

By default, the harness writes to:

```text
~/.codex/evals/codex-companion/events.jsonl
```

Override with `CODEX_EVAL_DIR` if needed.

## Privacy note

The harness stores only short previews and hashes for user prompts and assistant messages. It stores the full Bash command text because the command itself is usually necessary to interpret shell-output-size measurements. If that is too permissive for a given evaluation, edit the logger before use.
