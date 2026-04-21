# Codex Helpers

Codex-native helper lane for the subset of workflow helpers that current Codex CLI/Desktop surfaces can support without overstating parity with the Claude-first helper set in the rest of this repository.

## Status

| Helper | Event | Status | Notes |
|---|---|---|---|
| `stop-snapshot` | `Stop` | Supported | Strongest current Codex portability story. |
| `reasoning-hygiene-banner` | `SessionStart` | Supported | Config/model hygiene, not Claude-specific effort defense. |
| `turn-rot` | `UserPromptSubmit` | Experimental | Implemented, but interactive event coverage still needs live confirmation. |
| `bash-output-watch` | `PostToolUse` on `Bash` | Experimental | Implemented for Bash output only. |
| `idle-gap-awareness` | `UserPromptSubmit` | Deferred | Needs stronger Codex-specific idle-gap evidence. |
| `subagent-boundary-watch` | n/a | Deferred | Blocked by missing file/search telemetry. |
| `compact-safety` | n/a | Deferred | Blocked by missing pre-compact interception surface. |

## Why this lane exists

The repo root remains Claude-first. This directory is where Codex-native work lands while the helper set is still narrower than the Claude implementation set.

The supporting evidence and design rationale live under [../codex-evaluation/README.md](../codex-evaluation/README.md).

## Requirements

1. Codex CLI/Desktop with `~/.codex/` already created.
2. Codex hooks enabled in `~/.codex/config.toml`:

```toml
[features]
codex_hooks = true
```

Source: [Hooks – Codex | OpenAI Developers](https://developers.openai.com/codex/hooks)

## Install

### Install all Codex helpers

```bash
cd codex-helpers
./install-all.sh
```

By default, `install-all.sh` installs only the live-backed supported helpers:

- `stop-snapshot`
- `reasoning-hygiene-banner`

To include the experimental helpers too:

```bash
cd codex-helpers
CODEX_HELPERS_INCLUDE_EXPERIMENTAL=1 ./install-all.sh
```

### Install one helper

```bash
cd codex-helpers/stop-snapshot && ./install.sh
cd codex-helpers/reasoning-hygiene-banner && ./install.sh
```

Experimental helpers can still be installed individually:

```bash
cd codex-helpers/turn-rot && ./install.sh
cd codex-helpers/bash-output-watch && ./install.sh
```

Each installer copies its script into `~/.codex/hooks/cost-helpers/<helper>/`, copies the shared runtime into `~/.codex/hooks/cost-helpers/_shared/`, and prints a `hooks.json` snippet for manual merge.

## Fixture tests

Run the non-mutating fixture checks from the repo root:

```bash
cd codex-helpers
./run-fixture-tests.sh
```

## Live smoke test

Run a reproducible live smoke test for current runtime behavior:

```bash
cd codex-helpers
./live-smoke.sh
```

This script:

- installs a temporary repo-local `.codex/hooks.json`
- runs three `codex exec` probes
- writes per-hook invocation evidence to a temporary `invocations.jsonl`
- restores any prior repo-local hooks file on exit

## Capability probe

Run the higher-level runtime summary:

```bash
cd codex-helpers
./capability-probe.sh
```

This wraps the smoke test and emits a helper-status summary from the observed invocation log.

## Live verification notes

- `stop-snapshot` and `reasoning-hygiene-banner` are expected to work in `codex exec` runs.
- `turn-rot` and `bash-output-watch` are implemented but remain experimental until interactive event coverage is confirmed live.
- `bash-output-watch` intentionally only talks about **Bash output** or **shell output**.
- The helpers also write invocation summaries when `CODEX_HELPER_LOG_DIR` is set, which is useful when transcript-visible developer messages are inconsistent.
- The current `live-smoke.sh` result on this runtime confirms `SessionStart` and `Stop` invocations in `codex exec`, but still does not show `UserPromptSubmit` or `PostToolUse` firing in that non-interactive path.
- Use `capability-probe.sh` before opting into experimental helpers on a new runtime.

## Supported hooks snippet

Merge the supported helper entries into `~/.codex/hooks.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.codex/hooks/cost-helpers/reasoning-hygiene-banner/reasoning_hygiene_banner.py",
            "timeout": 10,
            "statusMessage": "Checking Codex reasoning defaults..."
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.codex/hooks/cost-helpers/stop-snapshot/stop_snapshot.py",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

Experimental additions, if you opt in:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.codex/hooks/cost-helpers/turn-rot/turn_rot.py",
            "timeout": 10,
            "statusMessage": "Checking session growth..."
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.codex/hooks/cost-helpers/bash-output-watch/bash_output_watch.py",
            "timeout": 10,
            "statusMessage": "Reviewing Bash output size..."
          }
        ]
      }
    ]
  }
}
```
