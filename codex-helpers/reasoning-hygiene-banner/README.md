# reasoning-hygiene-banner

Status: supported

Surfaces the current session model and the top-level configured reasoning effort at Codex `SessionStart`.

## Event

- `SessionStart`

## What it does

- reads the current model from the hook payload where available
- inspects `~/.codex/config.toml` for top-level `model` and `model_reasoning_effort`
- uses stronger wording only when the configured default effort is `xhigh`

## Notes

- This is about deliberate model and reasoning hygiene in Codex.
- It is not a Codex port of the Claude-specific hidden-default-effort story.
