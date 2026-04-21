#!/bin/bash
# Codex helpers — local fixture tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "Running Codex helper fixture tests..."
echo ""

test_stop_snapshot() {
  local tmp_home
  tmp_home="$(mktemp -d)"
  mkdir -p "${tmp_home}/.codex"

  local output
  output=$(printf '%s' '{"hook_event_name":"Stop","session_id":"fixture-stop","cwd":"'"${REPO_ROOT}"'","transcript_path":"/tmp/fixture.jsonl","last_assistant_message":"hello world","stop_hook_active":false}' \
    | HOME="${tmp_home}" python3 "${SCRIPT_DIR}/stop-snapshot/stop_snapshot.py")

  OUTPUT="${output}" TMP_HOME="${tmp_home}" python3 - <<'PY'
import json, os
from pathlib import Path

payload = json.loads(os.environ["OUTPUT"])
assert payload == {"continue": True}

base = Path(os.environ["TMP_HOME"]) / ".codex" / "sessions" / "auto-state"
json_path = base / "fixture-stop.json"
md_path = base / "fixture-stop.md"
assert json_path.exists()
assert md_path.exists()
data = json.loads(json_path.read_text())
assert data["session_id"] == "fixture-stop"
assert data["cwd"]
assert data["last_assistant"]["hash"]
assert "fixture-stop" in md_path.read_text()
PY

  rm -rf "${tmp_home}"
  echo "PASS stop-snapshot"
}

test_turn_rot() {
  local tmp_home
  tmp_home="$(mktemp -d)"
  mkdir -p "${tmp_home}/.codex/.session-state"

  local output1 output2
  output1=$(printf '%s' '{"hook_event_name":"UserPromptSubmit","session_id":"fixture-turn","prompt":"hello"}' \
    | HOME="${tmp_home}" CODEX_TURN_ROT_WARN_TURNS=1 CODEX_TURN_ROT_HARD_TURNS=2 python3 "${SCRIPT_DIR}/turn-rot/turn_rot.py")
  output2=$(printf '%s' '{"hook_event_name":"UserPromptSubmit","session_id":"fixture-turn","prompt":"hello again"}' \
    | HOME="${tmp_home}" CODEX_TURN_ROT_WARN_TURNS=1 CODEX_TURN_ROT_HARD_TURNS=2 python3 "${SCRIPT_DIR}/turn-rot/turn_rot.py")

  OUTPUT1="${output1}" OUTPUT2="${output2}" python3 - <<'PY'
import json, os

soft = json.loads(os.environ["OUTPUT1"])
hard = json.loads(os.environ["OUTPUT2"])

assert soft["continue"] is True
assert "session growth" in soft["systemMessage"].lower()
assert hard["continue"] is True
assert "fresh session" in hard["systemMessage"].lower()
PY

  rm -rf "${tmp_home}"
  echo "PASS turn-rot"
}

test_bash_output_watch() {
  local tmp_home
  tmp_home="$(mktemp -d)"
  mkdir -p "${tmp_home}/.codex/.session-state"

  local payload='{"hook_event_name":"PostToolUse","session_id":"fixture-bash","tool_name":"Bash","tool_input":{"command":"printf test"},"tool_response":"XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"}'
  local output
  output=$(printf '%s' "${payload}" \
    | HOME="${tmp_home}" CODEX_BASH_OUTPUT_WARN_TOKENS=4 CODEX_BASH_OUTPUT_CUMULATIVE_TOKENS=8,12 python3 "${SCRIPT_DIR}/bash-output-watch/bash_output_watch.py")

  OUTPUT="${output}" python3 - <<'PY'
import json, os

data = json.loads(os.environ["OUTPUT"])
assert "Bash output" in data["systemMessage"]
assert data["hookSpecificOutput"]["hookEventName"] == "PostToolUse"
PY

  rm -rf "${tmp_home}"
  echo "PASS bash-output-watch"
}

test_reasoning_banner() {
  local tmp_home
  tmp_home="$(mktemp -d)"
  mkdir -p "${tmp_home}/.codex"
  cat > "${tmp_home}/.codex/config.toml" <<'EOF'
model = "gpt-5.4"
model_reasoning_effort = "xhigh"
EOF

  local output
  output=$(printf '%s' '{"hook_event_name":"SessionStart","session_id":"fixture-start","source":"startup","model":"gpt-5.4"}' \
    | HOME="${tmp_home}" python3 "${SCRIPT_DIR}/reasoning-hygiene-banner/reasoning_hygiene_banner.py")

  OUTPUT="${output}" python3 - <<'PY'
import json, os

data = json.loads(os.environ["OUTPUT"])
assert data["continue"] is True
assert "xhigh" in data["systemMessage"]
assert data["hookSpecificOutput"]["hookEventName"] == "SessionStart"
PY

  rm -rf "${tmp_home}"
  echo "PASS reasoning-hygiene-banner"
}

test_stop_snapshot
test_turn_rot
test_bash_output_watch
test_reasoning_banner

echo ""
echo "All Codex helper fixture tests passed."
