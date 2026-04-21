# bash-output-watch

Status: experimental

Warns when a single Bash command or a series of Bash commands dump enough shell output into the session to become meaningful dead weight.

## Event

- `PostToolUse` on `Bash`

## Defaults

- per-call warning at `4000` estimated tokens
- cumulative warnings at `10000`, `25000`, and `50000` estimated tokens

## Environment overrides

- `CODEX_BASH_OUTPUT_WARN_TOKENS`
- `CODEX_BASH_OUTPUT_CUMULATIVE_TOKENS`

## Notes

- This helper intentionally says **Bash output** or **shell output**, not `all tool output`.
- It remains experimental until live interactive `PostToolUse` coverage is confirmed.
- Run `../capability-probe.sh` first to see whether your current runtime is observing Bash `PostToolUse`.
