#!/usr/bin/env python3
"""Surface current Codex model and configured reasoning defaults on SessionStart."""

from __future__ import annotations

import sys
from pathlib import Path

SHARED_DIR = Path(__file__).resolve().parents[1] / "_shared"
if str(SHARED_DIR) not in sys.path:
    sys.path.insert(0, str(SHARED_DIR))

from hooklib import (  # noqa: E402
    append_debug,
    codex_home,
    emit_message,
    load_payload,
    parse_top_level_config,
    record_hook_invocation,
)


HELPER = "reasoning-hygiene-banner"
EVENT = "SessionStart"


def main() -> int:
    message = None
    try:
        payload = load_payload()
        current_model = payload.get("model") or "unknown"
        config = parse_top_level_config(codex_home() / "config.toml")
        configured_model = config.get("model")
        configured_effort = config.get("model_reasoning_effort")

        if configured_effort == "xhigh":
            message = (
                f"Codex started on `{current_model}`. The top-level configured reasoning effort is `xhigh`"
                + (f" and the configured default model is `{configured_model}`." if configured_model else ".")
                + " Keep it if you want maximum reasoning depth; lower it when the session does not need that much compute."
            )
        elif configured_effort:
            message = (
                f"Codex started on `{current_model}`. The top-level configured reasoning effort is `{configured_effort}`"
                + (f" and the configured default model is `{configured_model}`." if configured_model else ".")
                + " Keep model and reasoning choices deliberate for the task at hand."
            )
        else:
            message = (
                f"Codex started on `{current_model}`. No top-level `model_reasoning_effort` was found in `~/.codex/config.toml`."
                " Keep model and reasoning choices deliberate for the task at hand."
            )
        record_hook_invocation(
            HELPER,
            EVENT,
            payload,
            message=message,
            extra={
                "current_model": current_model,
                "configured_model": configured_model,
                "configured_reasoning_effort": configured_effort,
            },
        )
    except Exception as exc:
        append_debug(HELPER, f"error: {exc}")
        message = None

    emit_message(EVENT, message)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
