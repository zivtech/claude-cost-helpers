# stop-snapshot

Status: supported

Writes a cheap machine-readable and human-readable session snapshot on every Codex `Stop` event.

## Event

- `Stop`

## What it captures

- `cwd`
- `transcript_path`
- last assistant preview/hash
- git branch and basic dirty-state counts when available
- a short recent-files list

## Output

- `~/.codex/sessions/auto-state/<session_id>.json`
- `~/.codex/sessions/auto-state/<session_id>.md`

## Install

```bash
cd codex-helpers/stop-snapshot
./install.sh
```

Then merge [hooks.json](./hooks.json) into `~/.codex/hooks.json`.
