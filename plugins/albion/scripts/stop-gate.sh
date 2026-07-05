#!/usr/bin/env bash
set -euo pipefail

# Coexistence gate: this hook stays inert unless the session was launched by
# bin/albion, which exports ALBION_ACTIVE=1. This keeps Albion's enforcement
# from firing in stock Claude sessions even if the plugin is enabled globally.
[ -n "${ALBION_ACTIVE:-}" ] || exit 0

log_line() {
  local message
  message="$1"
  (printf '%s\n' "$message" >>"${ALBION_GATE_LOG:-/dev/null}") 2>/dev/null || true
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
  local payload
  payload="$1"

  ALBION_HOOK_PAYLOAD="$payload" python3 -c '
import json
import os

try:
    payload = json.loads(os.environ["ALBION_HOOK_PAYLOAD"])
except Exception as error:
    print(f"PARSE_ERROR\tinvalid json: {error}")
    raise SystemExit(0)

if not isinstance(payload, dict):
    print("PARSE_ERROR\tpayload is not an object")
    raise SystemExit(0)

session_id = payload.get("session_id")
if not isinstance(session_id, str) or session_id == "":
    print("PARSE_ERROR\tmissing session_id")
    raise SystemExit(0)

stop_hook_active = payload.get("stop_hook_active") is True
last_assistant_message = payload.get("last_assistant_message")
if not isinstance(last_assistant_message, str):
    last_assistant_message = ""

background_tasks = payload.get("background_tasks")
session_crons = payload.get("session_crons")
has_background = (
    isinstance(background_tasks, list) and len(background_tasks) > 0
) or (
    isinstance(session_crons, list) and len(session_crons) > 0
)

print(session_id)
print("true" if stop_hook_active else "false")
print("true" if has_background else "false")
print(json.dumps(last_assistant_message))
'
}

build_reason() {
  local state_json
  local workbench_root
  local stop_hook_active
  local last_assistant_message_json
  state_json="$1"
  workbench_root="$2"
  stop_hook_active="$3"
  last_assistant_message_json="$4"

  ALBION_STATE_JSON="$state_json" python3 - "$workbench_root" "$stop_hook_active" "$last_assistant_message_json" <<'PY'
from __future__ import annotations

import json
import math
import os
import re
import sys
import unicodedata
from pathlib import Path

workbench_root = Path(sys.argv[1])
stop_hook_active = sys.argv[2] == "true"
last_assistant_message = json.loads(sys.argv[3])

try:
    state = json.loads(os.environ.get("ALBION_STATE_JSON", "{}"))
except json.JSONDecodeError:
    state = {}
if not isinstance(state, dict):
    state = {}


def open_task_count(value: object, default: int = 0) -> int:
    try:
        if isinstance(value, bool):
            return default
        if isinstance(value, int):
            return value
        if isinstance(value, float):
            if math.isfinite(value) and value >= 1:
                return int(value)
            return default
        if isinstance(value, str):
            stripped = value.strip()
            if re.fullmatch(r"[+-]?\d+", stripped):
                return int(stripped, 10)
    except (OverflowError, ValueError):
        return default
    return default


def string_value(value: object) -> str:
    return value if isinstance(value, str) else ""


def normalized_status(value: object) -> str:
    return string_value(value).strip().lower()


def task_is_nontrivial(task_text: str) -> bool:
    stripped = task_text.strip()
    if stripped == "":
        return False
    lowered = stripped.lower()
    trivial_markers = (
        r"(?m)^\s*trivial\s*:\s*true\s*$",
        r"(?m)^\s*non-?trivial\s*:\s*false\s*$",
        r"(?m)^\s*(complexity|tier)\s*:\s*trivial\s*$",
    )
    return not any(re.search(pattern, lowered) for pattern in trivial_markers)


def is_empty_verification(text: str) -> bool:
    visible_text = "".join(ch for ch in text if unicodedata.category(ch) != "Cf")
    return visible_text.strip() == ""


def empty_verification_tasks(root: Path) -> list[str]:
    fable_root = root / "fable-mode"
    if not fable_root.is_dir():
        return []

    missing: list[str] = []
    for task_dir in sorted(path for path in fable_root.iterdir() if path.is_dir()):
        task_file = task_dir / "task.md"
        try:
            task_text = task_file.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        if not task_is_nontrivial(task_text):
            continue

        verification_file = task_dir / "verification.md"
        try:
            verification_text = verification_file.read_text(encoding="utf-8", errors="replace")
        except OSError:
            verification_text = ""
        if is_empty_verification(verification_text):
            missing.append(task_dir.name)
    return missing


tasks = state.get("tasks")
open_tasks = open_task_count(tasks.get("open") if isinstance(tasks, dict) else None)

last_test = state.get("last_test")
last_test_failed = isinstance(last_test, dict) and normalized_status(last_test.get("status")) in {
    "fail",
    "failed",
    "error",
    "errored",
}
last_test_command = string_value(last_test.get("command") if isinstance(last_test, dict) else None)

missing_verification = empty_verification_tasks(workbench_root)

reasons: list[str] = []
if open_tasks > 0:
    label = "task" if open_tasks == 1 else "tasks"
    reasons.append(f"{open_tasks} open {label}")

if not stop_hook_active:
    if last_test_failed:
        if last_test_command:
            reasons.append(f"last test run failed: `{last_test_command}`")
        else:
            reasons.append("last test run failed")
    if missing_verification:
        if len(missing_verification) == 1:
            reasons.append(
                f"verification.md missing or empty for workbench task `{missing_verification[0]}`"
            )
        else:
            task_names = ", ".join(f"`{name}`" for name in missing_verification)
            reasons.append(f"verification.md missing or empty for workbench tasks: {task_names}")

claim_pattern = re.compile(r"\b(done|complete|completed|fixed|passing)\b|all tests pass", re.IGNORECASE)
if (
    not stop_hook_active
    and claim_pattern.search(last_assistant_message)
    and (last_test_failed or missing_verification)
):
    reasons.append("last assistant message claimed completion while test or verification state is unresolved")

print("; ".join(reasons))
PY
}

emit_block() {
  local reason
  reason="$1"

  python3 - "$reason" <<'PY'
import json
import sys

reason = sys.argv[1]
print(json.dumps({"decision": "block", "reason": reason}, separators=(",", ":")))
PY
}

reset_block_counter() {
  local session_id
  session_id="$1"

  if ! albion_state_set "$session_id" gate.blocks 0 >/dev/null 2>&1; then
    log_line "stop-gate: failed to reset gate.blocks for ${session_id}"
  fi
}

write_completion_manifest() {
  local session_id
  local state_json
  local workbench_root
  local manifest_path
  session_id="$1"
  state_json="$2"
  workbench_root="$3"
  manifest_path="${ALBION_MANIFEST_PATH:-$PWD/.albion/completion-manifest.json}"

  if ! ALBION_STATE_JSON="$state_json" python3 - "$session_id" "$workbench_root" "$manifest_path" <<'PY' 2>>"${ALBION_GATE_LOG:-/dev/null}"
from __future__ import annotations

import json
import math
import os
import re
import sys
import tempfile
import unicodedata
from datetime import datetime, timezone
from pathlib import Path

session_id = sys.argv[1]
workbench_root = Path(sys.argv[2])
manifest_path = Path(sys.argv[3])

try:
    state = json.loads(os.environ.get("ALBION_STATE_JSON", "{}"))
except json.JSONDecodeError:
    state = {}
if not isinstance(state, dict):
    state = {}


def open_task_count(value: object, default: int = 0) -> int:
    try:
        if isinstance(value, bool):
            return default
        if isinstance(value, int):
            return value
        if isinstance(value, float):
            if math.isfinite(value) and value >= 1:
                return int(value)
            return default
        if isinstance(value, str):
            stripped = value.strip()
            if re.fullmatch(r"[+-]?\d+", stripped):
                return int(stripped, 10)
    except (OverflowError, ValueError):
        return default
    return default


def string_value(value: object) -> str:
    return value if isinstance(value, str) else ""


def normalized_status(value: object) -> str:
    return string_value(value).strip().lower()


def task_is_nontrivial(task_text: str) -> bool:
    stripped = task_text.strip()
    if stripped == "":
        return False
    lowered = stripped.lower()
    trivial_markers = (
        r"(?m)^\s*trivial\s*:\s*true\s*$",
        r"(?m)^\s*non-?trivial\s*:\s*false\s*$",
        r"(?m)^\s*(complexity|tier)\s*:\s*trivial\s*$",
    )
    return not any(re.search(pattern, lowered) for pattern in trivial_markers)


def is_empty_verification(text: str) -> bool:
    visible_text = "".join(ch for ch in text if unicodedata.category(ch) != "Cf")
    return visible_text.strip() == ""


def workbench_tasks(root: Path) -> list[dict[str, object]]:
    fable_root = root / "fable-mode"
    if not fable_root.is_dir():
        return []

    tasks: list[dict[str, object]] = []
    for task_dir in sorted(path for path in fable_root.iterdir() if path.is_dir()):
        task_file = task_dir / "task.md"
        try:
            task_text = task_file.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        if not task_is_nontrivial(task_text):
            continue

        verification_file = task_dir / "verification.md"
        try:
            verification_text = verification_file.read_text(encoding="utf-8", errors="replace")
        except OSError:
            verification_text = ""
        tasks.append(
            {
                "slug": task_dir.name,
                "verification_present": not is_empty_verification(verification_text),
            }
        )
    return tasks


tasks_state = state.get("tasks")
last_test = state.get("last_test")
last_test_status = (
    normalized_status(last_test.get("status")) if isinstance(last_test, dict) else ""
)
manifest = {
    "schema": "albion-completion-manifest/v1",
    "session_id": session_id,
    "written_at": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
    "status": "complete",
    "last_test": last_test_status if last_test_status in {"pass", "fail"} else "unknown",
    "workbench_tasks": workbench_tasks(workbench_root),
    "open_task_count": open_task_count(tasks_state.get("open") if isinstance(tasks_state, dict) else None),
}

manifest_path.parent.mkdir(parents=True, exist_ok=True)
with tempfile.NamedTemporaryFile(
    "w",
    encoding="utf-8",
    dir=str(manifest_path.parent),
    prefix=f".{manifest_path.name}.",
    suffix=".tmp",
    delete=False,
) as handle:
    temp_path = Path(handle.name)
    json.dump(manifest, handle, sort_keys=True, separators=(",", ":"))
    handle.write("\n")
try:
    temp_path.replace(manifest_path)
except Exception:
    try:
        temp_path.unlink()
    except OSError:
        pass
    raise
PY
  then
    log_line "stop-gate: failed to write completion manifest for ${session_id}"
  fi
}

run_hook() {
  local payload
  local script_dir
  local state_lib
  local parsed
  local session_id
  local stop_hook_active
  local has_background
  local last_assistant_message_json
  local workbench_root
  local state_json
  local reason
  local existing_blocks
  local next_blocks
  local _cand

  payload="$(cat || true)"
  script_dir="$(resolved_script_dir)" || {
    log_line "stop-gate: cannot resolve hook path"
    return 0
  }
  # Find state-lib.sh in either layout: bundled inside a self-contained plugin
  # (<root>/state) or the dev/clone layout (<repo>/state, one level higher).
  state_lib=""
  for _cand in "${script_dir}/../state/state-lib.sh" "${script_dir}/../../state/state-lib.sh"; do
    if [ -f "$_cand" ]; then state_lib="$_cand"; break; fi
  done
  if [ -z "$state_lib" ]; then
    log_line "stop-gate: missing state-lib.sh under ${script_dir}"
    return 0
  fi

  # shellcheck disable=SC1090
  . "$state_lib"

  if ! parsed="$(parse_payload "$payload")"; then
    log_line "stop-gate: payload parser failed"
    return 0
  fi
  case "$parsed" in
    PARSE_ERROR$'\t'*)
      log_line "stop-gate: ${parsed#*$'\t'}"
      return 0
      ;;
  esac

  session_id="$(printf '%s\n' "$parsed" | sed -n '1p')"
  stop_hook_active="$(printf '%s\n' "$parsed" | sed -n '2p')"
  has_background="$(printf '%s\n' "$parsed" | sed -n '3p')"
  last_assistant_message_json="$(printf '%s\n' "$parsed" | sed -n '4,$p')"

  if [ "$has_background" = "true" ]; then
    reset_block_counter "$session_id"
    return 0
  fi

  workbench_root="${ALBION_WORKBENCH_ROOT:-$PWD/.agent-workbench}"
  if ! state_json="$(albion_state_dump "$session_id" 2>>"${ALBION_GATE_LOG:-/dev/null}")"; then
    log_line "stop-gate: failed to read state for ${session_id}"
    return 0
  fi

  if ! reason="$(build_reason "$state_json" "$workbench_root" "$stop_hook_active" "$last_assistant_message_json" 2>>"${ALBION_GATE_LOG:-/dev/null}")"; then
    log_line "stop-gate: failed to evaluate gate state for ${session_id}"
    return 0
  fi

  if [ "$reason" = "" ]; then
    reset_block_counter "$session_id"
    write_completion_manifest "$session_id" "$state_json" "$workbench_root"
    return 0
  fi

  if ! existing_blocks="$(albion_state_get "$session_id" gate.blocks 0 2>>"${ALBION_GATE_LOG:-/dev/null}")"; then
    log_line "stop-gate: failed to read gate.blocks for ${session_id}"
    return 0
  fi
  case "$existing_blocks" in
    ''|*[!0-9]*)
      log_line "stop-gate: non-integer gate.blocks for ${session_id}: ${existing_blocks}"
      return 0
      ;;
  esac

  if [ "$existing_blocks" -ge 3 ]; then
    printf 'Albion stop gate yielded after 3 consecutive blocks; unresolved state remains: %s\n' "$reason" >&2
    return 0
  fi

  if ! next_blocks="$(albion_state_incr "$session_id" gate.blocks 2>>"${ALBION_GATE_LOG:-/dev/null}")"; then
    log_line "stop-gate: failed to increment gate.blocks for ${session_id}"
    return 0
  fi
  case "$next_blocks" in
    ''|*[!0-9]*)
      log_line "stop-gate: non-integer increment result for ${session_id}: ${next_blocks}"
      return 0
      ;;
  esac

  emit_block "$reason"
}

run_hook "$@" || log_line "stop-gate: unexpected hook failure"
exit 0
