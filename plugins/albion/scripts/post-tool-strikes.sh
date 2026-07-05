#!/usr/bin/env bash
set -euo pipefail

# Coexistence gate: this hook stays inert unless the session was launched by
# bin/albion, which exports ALBION_ACTIVE=1. This keeps Albion's enforcement
# from firing in stock Claude sessions even if the plugin is enabled globally.
[ -n "${ALBION_ACTIVE:-}" ] || exit 0

log_line() {
  local message
  message="$1"
  (printf '%s\n' "$message" >>"${ALBION_STRIKES_LOG:-/dev/null}") 2>/dev/null || true
}

resolved_script_dir() {
  local source_path
  local dir_path
  local link_target
  source_path="${BASH_SOURCE[0]}"

  while [ -L "$source_path" ]; do
    dir_path="$(cd -P "$(dirname "$source_path")" && pwd)"
    link_target="$(readlink "$source_path")"
    case "$link_target" in
      /*) source_path="$link_target" ;;
      *) source_path="${dir_path}/${link_target}" ;;
    esac
  done

  cd -P "$(dirname "$source_path")" && pwd
}

parse_payload() {
  python3 -c '
import json
import re
import shlex
import sys
from datetime import datetime, timezone


def walk(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)


def explicit_failure(response):
    for obj in walk(response):
        if obj.get("is_error") is True:
            return True
        if obj.get("success") is False:
            return True
    return False


def bash_failure(response):
    if not isinstance(response, dict):
        return False
    stderr = response.get("stderr")
    if not isinstance(stderr, str) or stderr == "":
        return False
    exit_code = response.get("exit_code")
    interrupted = response.get("interrupted")
    if isinstance(exit_code, int) and not isinstance(exit_code, bool) and exit_code != 0:
        return True
    return interrupted is True


def first_command_token(command):
    if not isinstance(command, str):
        return ""
    try:
        parts = shlex.split(command)
    except ValueError:
        parts = command.split()
    return parts[0] if parts else ""


def strip_leading_env_assignments(command):
    remainder = command.strip()
    quote = chr(39)
    assignment_pattern = (
        r"^[A-Za-z_][A-Za-z0-9_]*=(?:"
        + quote
        + "[^"
        + quote
        + "]*"
        + quote
        + r"|\"[^\"]*\"|[^ \t;&|]+)[ \t]+"
    )
    while True:
        match = re.match(assignment_pattern, remainder)
        if match is None:
            return remainder
        remainder = remainder[match.end():].lstrip()


def strip_test_prefixes(command):
    if not isinstance(command, str):
        return ""
    remainder = command.strip()
    while True:
        original = remainder
        remainder = strip_leading_env_assignments(remainder)
        match = re.match(r"^cd[ \t]+[^;&|]+&&[ \t]*", remainder)
        if match is not None:
            remainder = remainder[match.end():].lstrip()
            continue
        if remainder == original:
            return remainder


def command_tokens(command):
    try:
        return shlex.split(command)
    except ValueError:
        return command.split()


def path_segment_matches(path, pattern):
    return any(re.fullmatch(pattern, segment) for segment in path.split("/"))


def is_test_command(command):
    stripped = strip_test_prefixes(command)
    tokens = command_tokens(stripped)
    if not tokens:
        return False

    first = tokens[0]
    second = tokens[1] if len(tokens) > 1 else ""
    third = tokens[2] if len(tokens) > 2 else ""

    if first == "tests/run.sh":
        return True
    if first == "bash" and second == "tests/run.sh":
        return True

    # Module-form invocations are unambiguous test runs (first live bench run
    # used python -m unittest and slipped past the original list).
    if first in {"python", "python3"} and second == "-m" and third in {"unittest", "pytest"}:
        return True

    if first in {"bash", "sh", "python", "python3"} and second:
        return path_segment_matches(second, r"run_tests?\.py") or path_segment_matches(
            second, r"test_[^ /]+\.(sh|py)"
        )

    if first == "pytest":
        return True
    if first in {"npm", "yarn", "pnpm", "go", "cargo"} and second == "test":
        return True
    if first == "make" and second in {"test", "check"}:
        return True
    return False


def last_test_value(command, failed):
    return json.dumps(
        {
            "status": "fail" if failed else "pass",
            "command": command[:200],
            "at": datetime.now(timezone.utc)
            .replace(microsecond=0)
            .isoformat()
            .replace("+00:00", "Z"),
        },
        separators=(",", ":"),
    )


def normalize(operation):
    normalized = operation.replace(":", "__")
    normalized = re.sub(r"[^A-Za-z0-9_]+", "_", normalized)
    normalized = normalized.strip("_")
    return normalized or "unknown"


try:
    payload = json.load(sys.stdin)
except Exception as error:
    print(f"PARSE_ERROR\tinvalid json: {error}")
    raise SystemExit(0)

if not isinstance(payload, dict):
    print("PARSE_ERROR\tpayload is not an object")
    raise SystemExit(0)

session_id = payload.get("session_id")
tool_name = payload.get("tool_name")
tool_input = payload.get("tool_input")
tool_response = payload.get("tool_response")

if not isinstance(session_id, str) or session_id == "":
    print("PARSE_ERROR\tmissing session_id")
    raise SystemExit(0)
if not isinstance(tool_name, str) or tool_name == "":
    print("PARSE_ERROR\tmissing tool_name")
    raise SystemExit(0)
if not isinstance(tool_input, dict):
    print("PARSE_ERROR\tmissing tool_input")
    raise SystemExit(0)

target = ""
file_path = tool_input.get("file_path")
if isinstance(file_path, str) and file_path != "":
    target = file_path
elif tool_name == "Bash":
    target = first_command_token(tool_input.get("command"))

operation = f"{tool_name}:{target}" if target else tool_name
failed = explicit_failure(tool_response) or (tool_name == "Bash" and bash_failure(tool_response))
command = tool_input.get("command") if tool_name == "Bash" else None
test_value = last_test_value(command, failed) if is_test_command(command) else ""

print(session_id)
print(f"strikes.{normalize(operation)}")
print(operation)
print("fail" if failed else "success")
print(test_value)
'
}

json_context() {
  local context
  context="$1"
  python3 -c '
import json
import sys

context = sys.argv[1]
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PostToolUse",
        "additionalContext": context,
    },
}, separators=(",", ":")))
' "$context"
}

truncated_operation() {
  local operation
  operation="$1"
  if [ "${#operation}" -gt 240 ]; then
    printf '%s...\n' "${operation:0:240}"
  else
    printf '%s\n' "$operation"
  fi
}

emit_context() {
  local count
  local operation
  local display_operation
  local context
  count="$1"
  operation="$2"
  display_operation="$(truncated_operation "$operation")"

  context="Strike ${count} of 3 on ${display_operation}: the same change has now failed twice."
  if [ "$count" -ge 3 ]; then
    context="${context} Before retrying, record the contradiction (counterexamples log) and shrink the next step to the smallest falsifiable check; revert is the escalation after repeated counterexample loops."
  fi

  json_context "$context"
}

run_hook() {
  local script_dir
  local _cand
  local state_lib
  local parsed
  local session_id
  local state_key
  local operation
  local status
  local last_test
  local count
  local existing_count

  script_dir="$(resolved_script_dir)"
  # Find state-lib.sh in either layout: bundled inside a self-contained plugin
  # (<root>/state) or the dev/clone layout (<repo>/state, one level higher).
  state_lib=""
  for _cand in "${script_dir}/../state/state-lib.sh" "${script_dir}/../../state/state-lib.sh"; do
    if [ -f "$_cand" ]; then state_lib="$_cand"; break; fi
  done
  if [ -z "$state_lib" ]; then
    log_line "post-tool-strikes: missing state-lib.sh under ${script_dir}"
    return 0
  fi

  # shellcheck source=state/state-lib.sh
  . "$state_lib"

  if ! parsed="$(parse_payload)"; then
    log_line "post-tool-strikes: payload parser failed"
    return 0
  fi

  case "$parsed" in
    PARSE_ERROR$'\t'*)
      log_line "post-tool-strikes: ${parsed#*$'\t'}"
      return 0
      ;;
  esac

  session_id="$(printf '%s\n' "$parsed" | sed -n '1p')"
  state_key="$(printf '%s\n' "$parsed" | sed -n '2p')"
  operation="$(printf '%s\n' "$parsed" | sed -n '3p')"
  status="$(printf '%s\n' "$parsed" | sed -n '4p')"
  last_test="$(printf '%s\n' "$parsed" | sed -n '5p')"

  if [ "$last_test" != "" ]; then
    if ! albion_state_set "$session_id" last_test "$last_test" >/dev/null 2>&1; then
      log_line "post-tool-strikes: failed to set last_test for ${session_id}"
    fi
  fi

  if [ "$status" = "success" ]; then
    if ! existing_count="$(albion_state_get "$session_id" "$state_key" __albion_missing__ 2>/dev/null)"; then
      log_line "post-tool-strikes: failed to read ${state_key} for ${session_id}"
      return 0
    fi
    if [ "$existing_count" = "__albion_missing__" ]; then
      return 0
    fi
    if ! albion_state_del "$session_id" "$state_key" >/dev/null 2>&1; then
      log_line "post-tool-strikes: failed to delete ${state_key} for ${session_id}"
    fi
    return 0
  fi

  if [ "$status" != "fail" ]; then
    log_line "post-tool-strikes: unknown parsed status ${status}"
    return 0
  fi

  if ! count="$(albion_state_incr "$session_id" "$state_key" 2>/dev/null)"; then
    log_line "post-tool-strikes: failed to increment ${state_key} for ${session_id}"
    return 0
  fi

  if [ "$count" -ge 2 ]; then
    emit_context "$count" "$operation"
  fi
}

run_hook "$@" || log_line "post-tool-strikes: unexpected hook failure"
exit 0
