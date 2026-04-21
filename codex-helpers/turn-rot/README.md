# turn-rot

Status: experimental

Warns when a Codex session grows long enough that stale context is likely to become a workflow problem.

## Event

- `UserPromptSubmit`

## Defaults

- soft warning at `30` turns
- hard warning at `50` turns

## Environment overrides

- `CODEX_TURN_ROT_WARN_TURNS`
- `CODEX_TURN_ROT_HARD_TURNS`

## Notes

- This helper talks about session growth and fresh-session hygiene only.
- It intentionally avoids exact pricing or idle-tax claims.
- It remains experimental until `UserPromptSubmit` coverage is confirmed live in interactive Codex sessions.
- Run `../capability-probe.sh` first to see whether your current runtime is observing `UserPromptSubmit`.
