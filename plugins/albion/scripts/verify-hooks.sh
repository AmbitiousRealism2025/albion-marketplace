#!/usr/bin/env bash
set -euo pipefail

# The plugin root is the parent of this script's own directory (scripts/), which
# works in both layouts: dev (plugin/scripts/) and self-contained (<plugin>/scripts/).
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_JSON="${PLUGIN_ROOT}/hooks/hooks.json"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/albion-verify-hooks.XXXXXX")"
RUN_STDOUT=""
RUN_CODE=0

cleanup() {
  rm -rf "$TMP_DIR"
}

trap cleanup EXIT

fail_hook() {
  local hook_name
  local message
  hook_name="$1"
  message="$2"

  printf 'FAIL %s: %s\n' "$hook_name" "$message" >&2
  exit 1
}

assert_empty() {
  local hook_name
  local value
  local message
  hook_name="$1"
  value="$2"
  message="$3"

  if [ -n "$value" ]; then
    fail_hook "$hook_name" "${message}: got ${value}"
  fi
}

assert_contains() {
  local hook_name
  local haystack
  local needle
  local message
  hook_name="$1"
  haystack="$2"
  needle="$3"
  message="$4"

  case "$haystack" in
    *"$needle"*) ;;
    *) fail_hook "$hook_name" "${message}: expected substring ${needle}" ;;
  esac
}

assert_not_contains() {
  local hook_name
  local haystack
  local needle
  local message
  hook_name="$1"
  haystack="$2"
  needle="$3"
  message="$4"

  case "$haystack" in
    *"$needle"*) fail_hook "$hook_name" "${message}: unexpected substring ${needle}" ;;
  esac
}

json_field() {
  local payload
  local field_path
  payload="$1"
  field_path="$2"

  python3 - "$payload" "$field_path" <<'PY'
import json
import sys

value = json.loads(sys.argv[1])
for part in sys.argv[2].split("."):
    value = value[part]
print(value)
PY
}

hook_script() {
  local event_name
  local script_name
  event_name="$1"
  script_name="$2"

  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" python3 - "$HOOKS_JSON" "$event_name" "$script_name" <<'PY'
import json
import os
import sys

hooks_path, event_name, script_name = sys.argv[1:4]
with open(hooks_path, "r", encoding="utf-8") as handle:
    config = json.load(handle)

for entry in config.get("hooks", {}).get(event_name, []):
    for hook in entry.get("hooks", []):
        command = hook.get("command")
        if isinstance(command, str):
            command = [command]
        if not isinstance(command, list) or not command:
            continue
        executable = str(command[0]).replace(
            "${CLAUDE_PLUGIN_ROOT}",
            os.environ["CLAUDE_PLUGIN_ROOT"],
        )
        if executable.endswith("/" + script_name):
            print(executable)
            raise SystemExit(0)

print(f"configured command not found for {event_name} {script_name}", file=sys.stderr)
raise SystemExit(1)
PY
}

run_hook() {
  local hook_name
  local script_path
  local payload
  local state_dir
  local workbench_root
  local out_file
  local err_file
  hook_name="$1"
  script_path="$2"
  payload="$3"
  state_dir="$4"
  workbench_root="$5"
  out_file="${TMP_DIR}/${hook_name}.out"
  err_file="${TMP_DIR}/${hook_name}.err"
  mkdir -p "$state_dir" "$workbench_root"

  set +e
  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    ALBION_ACTIVE=1 \
    ALBION_STATE_DIR="$state_dir" \
    ALBION_WORKBENCH_ROOT="$workbench_root" \
    ALBION_GUARD_LOG="${TMP_DIR}/${hook_name}.guard.log" \
    ALBION_STRIKES_LOG="${TMP_DIR}/${hook_name}.strikes.log" \
    ALBION_SCRUBBER_LOG="${TMP_DIR}/${hook_name}.scrubber.log" \
    ALBION_GATE_LOG="${TMP_DIR}/${hook_name}.gate.log" \
    ALBION_MANIFEST_PATH="${TMP_DIR}/${hook_name}.completion-manifest.json" \
    ALBION_INJECT_LOG="${TMP_DIR}/${hook_name}.inject.log" \
    ALBION_IMAGE_LOG="${TMP_DIR}/${hook_name}.image.log" \
    ALBION_VISION_BIN="${ALBION_VISION_BIN:-}" \
    "$script_path" >"$out_file" 2>"$err_file" <<<"$payload"
  RUN_CODE=$?
  set -e

  RUN_STDOUT="$(cat "$out_file")"
}

payload_for_command() {
  local session_id
  local command_text
  session_id="$1"
  command_text="$2"

  python3 - "$session_id" "$command_text" <<'PY'
import json
import sys

print(json.dumps({
    "session_id": sys.argv[1],
    "hook_event_name": "PreToolUse",
    "tool_name": "Bash",
    "tool_input": {"command": sys.argv[2]},
}, separators=(",", ":")))
PY
}

payload_for_read() {
  local session_id
  local file_path
  session_id="$1"
  file_path="$2"

  python3 - "$session_id" "$file_path" <<'PY'
import json
import sys

print(json.dumps({
    "session_id": sys.argv[1],
    "hook_event_name": "PreToolUse",
    "tool_name": "Read",
    "tool_input": {"file_path": sys.argv[2]},
}, separators=(",", ":")))
PY
}

post_payload() {
  local session_id
  local tool_name
  local file_path
  local response_json
  session_id="$1"
  tool_name="$2"
  file_path="$3"
  response_json="$4"

  python3 - "$session_id" "$tool_name" "$file_path" "$response_json" <<'PY'
import json
import sys

session_id, tool_name, file_path, response_json = sys.argv[1:5]
path_key = "notebook_path" if tool_name == "NotebookEdit" else "file_path"
print(json.dumps({
    "session_id": session_id,
    "hook_event_name": "PostToolUse",
    "tool_name": tool_name,
    "tool_input": {path_key: file_path},
    "tool_response": json.loads(response_json),
}, separators=(",", ":")))
PY
}

stop_payload() {
  local session_id
  session_id="$1"

  python3 - "$session_id" <<'PY'
import json
import sys

print(json.dumps({
    "session_id": sys.argv[1],
    "hook_event_name": "Stop",
    "stop_hook_active": False,
    "last_assistant_message": "Stopping now.",
    "background_tasks": [],
    "session_crons": [],
}, separators=(",", ":")))
PY
}

session_start_payload() {
  local session_id
  local source_name
  session_id="$1"
  source_name="$2"

  python3 - "$session_id" "$source_name" <<'PY'
import json
import sys

print(json.dumps({
    "session_id": sys.argv[1],
    "hook_event_name": "SessionStart",
    "source": sys.argv[2],
}, separators=(",", ":")))
PY
}

write_state_file() {
  local state_dir
  local session_id
  local state_json
  state_dir="$1"
  session_id="$2"
  state_json="$3"

  mkdir -p "$state_dir"
  python3 - "$state_dir/${session_id}.json" "$state_json" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
state = json.loads(sys.argv[2])
path.write_text(json.dumps(state, sort_keys=True) + "\n", encoding="utf-8")
PY
}

verify_pre_tool_guard() {
  local hook_name
  local script_path
  local state_dir
  local workbench_root
  local decision
  hook_name="pre-tool-guard"
  script_path="$(hook_script PreToolUse pre-tool-guard.sh)" || fail_hook "$hook_name" "not configured"
  state_dir="${TMP_DIR}/${hook_name}.state"
  workbench_root="${TMP_DIR}/${hook_name}.workbench"

  run_hook "$hook_name-deny" "$script_path" "$(payload_for_command guard-session 'rm -rf /')" "$state_dir" "$workbench_root"
  [ "$RUN_CODE" -eq 0 ] || fail_hook "$hook_name" "dangerous payload exited ${RUN_CODE}"
  decision="$(json_field "$RUN_STDOUT" "hookSpecificOutput.permissionDecision")" || fail_hook "$hook_name" "deny output is not valid JSON"
  [ "$decision" = "deny" ] || fail_hook "$hook_name" "dangerous Bash payload did not deny"
  assert_contains "$hook_name" "$RUN_STDOUT" "permissionDecisionReason" "deny output names a reason"

  run_hook "$hook_name-allow" "$script_path" "$(payload_for_command guard-session 'printf safe')" "$state_dir" "$workbench_root"
  [ "$RUN_CODE" -eq 0 ] || fail_hook "$hook_name" "safe payload exited ${RUN_CODE}"
  assert_empty "$hook_name" "$RUN_STDOUT" "safe Bash payload should be silent"
}

verify_image_read_intercept() {
  local hook_name
  local script_path
  local state_dir
  local workbench_root
  local missing_vision_bin
  local decision
  local reason
  hook_name="image-read-intercept"
  script_path="$(hook_script PreToolUse image-read-intercept.sh)" || fail_hook "$hook_name" "not configured"
  state_dir="${TMP_DIR}/${hook_name}.state"
  workbench_root="${TMP_DIR}/${hook_name}.workbench"
  missing_vision_bin="${TMP_DIR}/${hook_name}.missing-vision"

  ALBION_VISION_BIN="$missing_vision_bin" run_hook "$hook_name-deny" "$script_path" "$(payload_for_read image-session "${TMP_DIR}/example.png")" "$state_dir" "$workbench_root"
  [ "$RUN_CODE" -eq 0 ] || fail_hook "$hook_name" "image payload exited ${RUN_CODE}"
  decision="$(json_field "$RUN_STDOUT" "hookSpecificOutput.permissionDecision")" || fail_hook "$hook_name" "image output is not valid JSON"
  [ "$decision" = "deny" ] || fail_hook "$hook_name" "image Read payload did not deny"
  reason="$(json_field "$RUN_STDOUT" "hookSpecificOutput.permissionDecisionReason")" || fail_hook "$hook_name" "image deny reason missing"
  assert_contains "$hook_name" "$reason" "no vision provider available for ${TMP_DIR}/example.png" "image deny should include degrade note"
  assert_contains "$hook_name" "$reason" "Raw image bytes were not loaded." "image deny should note raw bytes were blocked"

  ALBION_VISION_BIN="$missing_vision_bin" run_hook "$hook_name-noop" "$script_path" "$(payload_for_read image-session "${TMP_DIR}/notes.py")" "$state_dir" "$workbench_root"
  [ "$RUN_CODE" -eq 0 ] || fail_hook "$hook_name" "non-image no-op exited ${RUN_CODE}"
  assert_empty "$hook_name" "$RUN_STDOUT" "non-image Read payload should be silent"
}

verify_post_tool_strikes() {
  local hook_name
  local script_path
  local state_dir
  local workbench_root
  local payload
  local context
  hook_name="post-tool-strikes"
  script_path="$(hook_script PostToolUse post-tool-strikes.sh)" || fail_hook "$hook_name" "not configured"
  state_dir="${TMP_DIR}/${hook_name}.state"
  workbench_root="${TMP_DIR}/${hook_name}.workbench"
  payload="$(post_payload strikes-session Edit src/parser.ts '{"is_error":true}')"

  run_hook "$hook_name-first" "$script_path" "$payload" "$state_dir" "$workbench_root"
  [ "$RUN_CODE" -eq 0 ] || fail_hook "$hook_name" "first failure exited ${RUN_CODE}"
  assert_empty "$hook_name" "$RUN_STDOUT" "first failure should be silent"

  run_hook "$hook_name-second" "$script_path" "$payload" "$state_dir" "$workbench_root"
  [ "$RUN_CODE" -eq 0 ] || fail_hook "$hook_name" "second failure exited ${RUN_CODE}"
  context="$(json_field "$RUN_STDOUT" "hookSpecificOutput.additionalContext")" || fail_hook "$hook_name" "second failure output is not valid JSON"
  assert_contains "$hook_name" "$context" "Strike 2 of 3 on Edit:src/parser.ts" "second failure should inject strike context"

  run_hook "$hook_name-noop" "$script_path" "$(post_payload strikes-clean Read README.md '{"success":true}')" "${TMP_DIR}/${hook_name}.noop.state" "$workbench_root"
  [ "$RUN_CODE" -eq 0 ] || fail_hook "$hook_name" "success no-op exited ${RUN_CODE}"
  assert_empty "$hook_name" "$RUN_STDOUT" "successful payload should be silent"
}

verify_workbench_scrubber() {
  local hook_name
  local script_path
  local state_dir
  local workbench_root
  local target_path
  local outside_path
  local context
  local content
  hook_name="workbench-scrubber"
  script_path="$(hook_script PostToolUse workbench-scrubber.sh)" || fail_hook "$hook_name" "not configured"
  state_dir="${TMP_DIR}/${hook_name}.state"
  workbench_root="${TMP_DIR}/${hook_name}.project/.agent-workbench"
  target_path="${workbench_root}/fable-mode/task/notes.md"
  mkdir -p "$(dirname "$target_path")"
  printf 'token=Abcdef1234567890\n' >"$target_path"

  run_hook "$hook_name-redact" "$script_path" "$(post_payload scrub-session Write "$target_path" '{"success":true}')" "$state_dir" "$workbench_root"
  [ "$RUN_CODE" -eq 0 ] || fail_hook "$hook_name" "redaction payload exited ${RUN_CODE}"
  context="$(json_field "$RUN_STDOUT" "hookSpecificOutput.additionalContext")" || fail_hook "$hook_name" "redaction output is not valid JSON"
  assert_contains "$hook_name" "$context" "Redacted 1 secret-like value" "redaction should emit notice"
  content="$(cat "$target_path")"
  assert_contains "$hook_name" "$content" "[REDACTED:generic_secret]" "secret should be redacted on disk"
  assert_not_contains "$hook_name" "$content" "Abcdef1234567890" "raw secret should be removed"

  outside_path="${TMP_DIR}/${hook_name}.outside.md"
  printf 'token=Abcdef1234567890\n' >"$outside_path"
  run_hook "$hook_name-noop" "$script_path" "$(post_payload scrub-session Write "$outside_path" '{"success":true}')" "$state_dir" "$workbench_root"
  [ "$RUN_CODE" -eq 0 ] || fail_hook "$hook_name" "outside path exited ${RUN_CODE}"
  assert_empty "$hook_name" "$RUN_STDOUT" "non-workbench write should be silent"
  assert_contains "$hook_name" "$(cat "$outside_path")" "Abcdef1234567890" "non-workbench file should be untouched"
}

verify_stop_gate() {
  local hook_name
  local script_path
  local state_dir
  local workbench_root
  local reason
  hook_name="stop-gate"
  script_path="$(hook_script Stop stop-gate.sh)" || fail_hook "$hook_name" "not configured"
  state_dir="${TMP_DIR}/${hook_name}.state"
  workbench_root="${TMP_DIR}/${hook_name}.workbench"
  write_state_file "$state_dir" stop-session '{"tasks":{"open":1}}'

  run_hook "$hook_name-block" "$script_path" "$(stop_payload stop-session)" "$state_dir" "$workbench_root"
  [ "$RUN_CODE" -eq 0 ] || fail_hook "$hook_name" "block payload exited ${RUN_CODE}"
  reason="$(json_field "$RUN_STDOUT" "reason")" || fail_hook "$hook_name" "block output is not valid JSON"
  assert_contains "$hook_name" "$reason" "1 open task" "open task should block Stop"

  run_hook "$hook_name-clean" "$script_path" "$(stop_payload stop-clean)" "${TMP_DIR}/${hook_name}.clean.state" "$workbench_root"
  [ "$RUN_CODE" -eq 0 ] || fail_hook "$hook_name" "clean payload exited ${RUN_CODE}"
  assert_empty "$hook_name" "$RUN_STDOUT" "clean Stop payload should be silent"
}

verify_session_start_inject() {
  local hook_name
  local script_path
  local state_dir
  local workbench_root
  local context
  hook_name="session-start-inject"
  script_path="$(hook_script SessionStart session-start-inject.sh)" || fail_hook "$hook_name" "not configured"
  state_dir="${TMP_DIR}/${hook_name}.state"
  workbench_root="${TMP_DIR}/${hook_name}.workbench"
  mkdir -p "${workbench_root}/fable-mode/active-task"
  printf 'Primary task body.\n' >"${workbench_root}/fable-mode/active-task/task.md"
  write_state_file "$state_dir" inject-session '{"tasks":{"open":1}}'

  run_hook "$hook_name-context" "$script_path" "$(session_start_payload inject-session compact)" "$state_dir" "$workbench_root"
  [ "$RUN_CODE" -eq 0 ] || fail_hook "$hook_name" "context payload exited ${RUN_CODE}"
  context="$(json_field "$RUN_STDOUT" "hookSpecificOutput.additionalContext")" || fail_hook "$hook_name" "context output is not valid JSON"
  assert_contains "$hook_name" "$context" "Albion state re-injected (source: compact)." "context should echo source"
  assert_contains "$hook_name" "$context" "Primary task body." "context should include workbench task"

  run_hook "$hook_name-empty" "$script_path" "$(session_start_payload inject-empty startup)" "${TMP_DIR}/${hook_name}.empty.state" "${TMP_DIR}/${hook_name}.empty.workbench"
  [ "$RUN_CODE" -eq 0 ] || fail_hook "$hook_name" "empty payload exited ${RUN_CODE}"
  assert_empty "$hook_name" "$RUN_STDOUT" "empty SessionStart should be silent"
}

main() {
  verify_pre_tool_guard
  verify_image_read_intercept
  verify_post_tool_strikes
  verify_workbench_scrubber
  verify_stop_gate
  verify_session_start_inject
  printf 'PASS hook verification: 6 configured hook entries exercised\n'
}

main "$@"
