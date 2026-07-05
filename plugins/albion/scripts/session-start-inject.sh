#!/usr/bin/env bash
set -euo pipefail

# Coexistence gate: this hook stays inert unless the session was launched by
# bin/albion, which exports ALBION_ACTIVE=1. This keeps Albion's enforcement
# from firing in stock Claude sessions even if the plugin is enabled globally.
[ -n "${ALBION_ACTIVE:-}" ] || exit 0

BUDGET_CHARS=8999

log_message() {
  local message
  message="$1"

  printf '%s\n' "$message" >>"${ALBION_INJECT_LOG:-/dev/null}" 2>/dev/null || true
}

script_dir() {
  python3 -c 'from pathlib import Path; import sys; print(Path(sys.argv[1]).resolve().parent)' "${BASH_SOURCE[0]}"
}

parse_payload() {
  python3 - "$1" <<'PY'
import json
import sys

try:
    payload = json.loads(sys.argv[1])
except Exception as error:
    print(f"malformed SessionStart payload: {error}", file=sys.stderr)
    raise SystemExit(1)

session_id = payload.get("session_id")
source = payload.get("source", "unknown")
if not isinstance(session_id, str) or not session_id:
    print("SessionStart payload missing session_id", file=sys.stderr)
    raise SystemExit(1)
if not isinstance(source, str) or not source:
    source = "unknown"

print(session_id)
print(source)
PY
}

build_output() {
  local source_name
  local workbench_root
  local state_json
  source_name="$1"
  workbench_root="$2"
  state_json="$3"

  python3 - "$source_name" "$workbench_root" "$state_json" "$BUDGET_CHARS" <<'PY'
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

source_name = sys.argv[1]
workbench_root = Path(sys.argv[2])
raw_state = sys.argv[3]
budget = int(sys.argv[4])

try:
    state = json.loads(raw_state)
except json.JSONDecodeError:
    state = {}
if not isinstance(state, dict):
    state = {}

SECRET_LINE_PATTERNS = [
    re.compile(r"AKIA[0-9A-Z]{16}"),
    re.compile(r"sk-[A-Za-z0-9_-]{20,}"),
    re.compile(r"gh[pousr]?_[A-Za-z0-9]{20,}"),
    re.compile(r"\bBearer\s+[A-Za-z0-9._~+/=-]{20,}", re.IGNORECASE),
]
PRIVATE_KEY_BEGIN = re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")
PRIVATE_KEY_END = re.compile(r"-----END [A-Z ]*PRIVATE KEY-----")


def sanitize_content(text: str) -> str:
    sanitized: list[str] = []
    in_private_key = False
    for line in text.splitlines():
        if in_private_key:
            if PRIVATE_KEY_END.search(line):
                in_private_key = False
            continue
        if PRIVATE_KEY_BEGIN.search(line):
            in_private_key = True
            continue
        if any(pattern.search(line) for pattern in SECRET_LINE_PATTERNS):
            continue
        sanitized.append(line)
    return "\n".join(sanitized)


def compact_json(value: object) -> str:
    if isinstance(value, str):
        return value
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def workbench_dirs() -> list[Path]:
    fable_root = workbench_root / "fable-mode"
    if not fable_root.is_dir():
        return []
    dirs = [path for path in fable_root.iterdir() if path.is_dir()]
    return sorted(dirs, key=lambda path: (path.stat().st_mtime_ns, path.name), reverse=True)


def state_lines() -> list[str]:
    lines: list[str] = []
    strikes = state.get("strikes")
    if isinstance(strikes, dict):
        for name in sorted(strikes):
            value = strikes[name]
            if isinstance(value, int) and not isinstance(value, bool) and value >= 2:
                lines.append(f"Open strike: strikes.{name}={value}.")
    if "last_test" in state:
        lines.append(f"Last test: {compact_json(state['last_test'])}.")
    tasks = state.get("tasks")
    if isinstance(tasks, dict) and "open" in tasks:
        lines.append(f"Open tasks: tasks.open={compact_json(tasks['open'])}.")
    return lines


class ContextBuilder:
    def __init__(self, limit: int) -> None:
        self.limit = limit
        self.parts: list[str] = []

    def text(self) -> str:
        return "".join(self.parts).rstrip() + "\n"

    def remaining(self) -> int:
        return self.limit - len("".join(self.parts))

    def append_line(self, line: str) -> bool:
        addition = f"{line}\n"
        if len(addition) > self.remaining():
            return False
        self.parts.append(addition)
        return True

    def append_file_section(self, heading: str, path: Path) -> bool:
        try:
            raw_content = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            return False

        content = sanitize_content(raw_content).rstrip()
        prefix = f"\n{heading} ({path}):\n"
        full_block = f"{prefix}{content}\n"
        if len(full_block) <= self.remaining():
            self.parts.append(full_block)
            return True

        marker = f"\n…[truncated; full content: {path}]\n"
        available = self.remaining() - len(prefix) - len(marker)
        if available <= 0:
            return False
        self.parts.append(f"{prefix}{content[:available].rstrip()}{marker}")
        return True


dirs = workbench_dirs()
latest_dir = dirs[0] if dirs else None
meaningful_state_lines = state_lines()

if latest_dir is None and not meaningful_state_lines:
    raise SystemExit(0)

builder = ContextBuilder(budget)
builder.append_line(f"Albion state re-injected (source: {source_name}).")

if latest_dir is not None:
    builder.append_line(f"Latest workbench task: {latest_dir.name} ({latest_dir}).")
    task_file = latest_dir / "task.md"
    state_map_file = latest_dir / "state-map.md"
    if task_file.is_file():
        builder.append_file_section("task.md", task_file)
    if state_map_file.is_file():
        builder.append_file_section("state-map.md", state_map_file)

for line in meaningful_state_lines:
    builder.append_line(line)

if len(dirs) > 1:
    other_names = ", ".join(path.name for path in dirs[1:])
    builder.append_line(f"Other workbench tasks present: {other_names}.")

context = builder.text()
if len(context) > budget:
    raise SystemExit(0)

json.dump(
    {
        "hookSpecificOutput": {
            "hookEventName": "SessionStart",
            "additionalContext": context,
        }
    },
    sys.stdout,
    separators=(",", ":"),
)
sys.stdout.write("\n")
PY
}

main() {
  local payload
  local resolved_script_dir
  local state_lib
  local _cand
  local parsed
  local session_id
  local source_name
  local state_json
  local workbench_root

  payload="$(cat || true)"
  resolved_script_dir="$(script_dir)" || {
    log_message "cannot resolve hook path"
    return 0
  }
  # Find state-lib.sh in either layout: bundled inside a self-contained plugin
  # (<root>/state) or the dev/clone layout (<repo>/state, one level higher).
  state_lib=""
  for _cand in "${resolved_script_dir}/../state/state-lib.sh" "${resolved_script_dir}/../../state/state-lib.sh"; do
    if [ -f "$_cand" ]; then state_lib="$_cand"; break; fi
  done
  if [ -z "$state_lib" ]; then
    log_message "missing state library under ${resolved_script_dir}"
    return 0
  fi

  # shellcheck disable=SC1090
  . "$state_lib"

  if ! parsed="$(parse_payload "$payload" 2>>"${ALBION_INJECT_LOG:-/dev/null}")"; then
    return 0
  fi
  session_id="$(printf '%s\n' "$parsed" | sed -n '1p')"
  source_name="$(printf '%s\n' "$parsed" | sed -n '2p')"
  workbench_root="${ALBION_WORKBENCH_ROOT:-$PWD/.agent-workbench}"

  if ! state_json="$(albion_state_dump "$session_id" 2>>"${ALBION_INJECT_LOG:-/dev/null}")"; then
    state_json="{}"
  fi

  build_output "$source_name" "$workbench_root" "$state_json" 2>>"${ALBION_INJECT_LOG:-/dev/null}" || true
}

main "$@"
