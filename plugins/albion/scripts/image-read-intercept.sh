#!/usr/bin/env bash
set -euo pipefail

# Coexistence gate: this hook stays inert unless the session was launched by
# bin/albion, which exports ALBION_ACTIVE=1. This keeps Albion's enforcement
# from firing in stock Claude sessions even if the plugin is enabled globally.
[ -n "${ALBION_ACTIVE:-}" ] || exit 0

MAX_DESCRIPTION_CHARS=4000

log_image() {
  local message
  message="$1"

  printf '%s\n' "$message" >>"${ALBION_IMAGE_LOG:-/dev/null}" 2>/dev/null || true
}

fail_open() {
  log_image "$1"
  exit 0
}

on_error() {
  fail_open "image-read-intercept internal error; allowing non-emitted hook flow"
}

trap on_error ERR

resolve_script_dir() {
  local source_path
  local source_dir

  source_path="${BASH_SOURCE[0]}"
  while [ -h "$source_path" ]; do
    source_dir="$(cd -P "$(dirname "$source_path")" && pwd)"
    source_path="$(readlink "$source_path")"
    case "$source_path" in
      /*) ;;
      *) source_path="${source_dir}/${source_path}" ;;
    esac
  done

  cd -P "$(dirname "$source_path")" && pwd
}

parse_payload() {
  local payload
  payload="$1"

  ALBION_HOOK_PAYLOAD="$payload" python3 -c '
import json
import os
import sys

try:
    payload = json.loads(os.environ["ALBION_HOOK_PAYLOAD"])
except Exception:
    sys.exit(0)

if payload.get("tool_name") != "Read":
    sys.exit(0)

file_path = payload.get("tool_input", {}).get("file_path")
if not isinstance(file_path, str) or not file_path:
    sys.exit(0)

lower_path = file_path.lower()
supported = (".png", ".jpg", ".jpeg")
unsupported = (".gif", ".webp", ".bmp", ".tiff", ".svg")

if lower_path.endswith(supported):
    print(json.dumps({"action": "describe", "path": file_path}, separators=(",", ":")))
elif lower_path.endswith(unsupported):
    extension = lower_path.rsplit(".", 1)[-1]
    print(json.dumps({
        "action": "unsupported",
        "path": file_path,
        "extension": extension,
    }, separators=(",", ":")))
'
}

json_value() {
  local payload
  local field_name
  payload="$1"
  field_name="$2"

  python3 - "$payload" "$field_name" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
value = payload.get(sys.argv[2], "")
print(value, end="")
PY
}

cap_description() {
  local description
  description="$1"

  ALBION_DESCRIPTION="$description" ALBION_MAX_DESCRIPTION_CHARS="$MAX_DESCRIPTION_CHARS" python3 -c '
import os

description = os.environ["ALBION_DESCRIPTION"]
limit = int(os.environ["ALBION_MAX_DESCRIPTION_CHARS"])
marker = "\n[truncated to 4000 characters]"

if len(description) > limit:
    description = description[: max(0, limit - len(marker))] + marker

print(description, end="")
'
}

emit_deny() {
  local reason
  reason="$1"

  python3 - "$reason" <<'PY'
import json
import os
import re
import sys

reason = sys.argv[1]
for name, value in os.environ.items():
    if not value or len(value) < 4:
        continue
    if re.search(r"(TOKEN|SECRET|KEY|PASSWORD)", name, re.IGNORECASE):
        reason = reason.replace(value, "[REDACTED]")

print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }
}, separators=(",", ":")))
PY
}

vision_bin() {
  local script_dir
  local root_dir

  if [ -n "${ALBION_VISION_BIN:-}" ]; then
    printf '%s' "$ALBION_VISION_BIN"
    return
  fi

  script_dir="$(resolve_script_dir)"
  root_dir="$(cd "${script_dir}/../.." && pwd)"
  printf '%s/bin/albion-vision' "$root_dir"
}

describe_image() {
  local file_path
  local command_path
  file_path="$1"
  command_path="$(vision_bin)"

  if [ ! -x "$command_path" ]; then
    log_image "image-read-intercept: vision binary unavailable"
    return 1
  fi

  "$command_path" "$file_path" 2>/dev/null
}

main() {
  local input
  local decision
  local action
  local file_path
  local extension
  local description
  local reason

  input="$(cat)"
  decision="$(parse_payload "$input")"
  if [ -z "$decision" ]; then
    exit 0
  fi

  action="$(json_value "$decision" action)"
  file_path="$(json_value "$decision" path)"

  case "$action" in
    describe)
      if description="$(describe_image "$file_path")"; then
        description="$(cap_description "$description")"
        reason="Image read intercepted. Vision description of ${file_path}: ${description}
Raw image bytes were not loaded."
      else
        reason="Image read intercepted: no vision provider available for ${file_path}; do not guess image content.
Raw image bytes were not loaded."
      fi
      emit_deny "$reason"
      ;;
    unsupported)
      extension="$(json_value "$decision" extension)"
      reason="Image read intercepted: vision subsystem cannot describe ${file_path} (.${extension}); do not guess its content.
Raw image bytes were not loaded."
      emit_deny "$reason"
      ;;
    *)
      exit 0
      ;;
  esac
}

main "$@"
