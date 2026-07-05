#!/usr/bin/env bash
set -euo pipefail

# Coexistence gate: this hook stays inert unless the session was launched by
# bin/albion, which exports ALBION_ACTIVE=1. This keeps Albion's enforcement
# from firing in stock Claude sessions even if the plugin is enabled globally.
[ -n "${ALBION_ACTIVE:-}" ] || exit 0

python_source() {
  cat <<'PY'
import json
import os
import pathlib
import re
import stat
import sys
import tempfile

LOG_PATH = sys.argv[1]
TARGET_TOOLS = {"Write", "Edit", "NotebookEdit"}


def log_line(message):
    try:
        with open(LOG_PATH, "a", encoding="utf-8") as handle:
            handle.write(f"{message}\n")
    except OSError:
        pass


def mixed_classes(value):
    classes = 0
    classes += bool(re.search(r"[a-z]", value))
    classes += bool(re.search(r"[A-Z]", value))
    classes += bool(re.search(r"[0-9]", value))
    classes += bool(re.search(r"[^A-Za-z0-9]", value))
    return classes >= 2


def generic_replacement(match):
    value = match.group("value")
    if len(value) < 16 or not mixed_classes(value):
        return match.group(0), False
    return f"{match.group('prefix')}[REDACTED:generic_secret]", True


PATTERNS = [
    {
        "type": "private_key",
        "regex": re.compile(
            r"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"
        ),
        "replace": lambda match: ("[REDACTED:private_key]", True),
    },
    {
        "type": "aws_access_key",
        "regex": re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
        "replace": lambda match: ("[REDACTED:aws_access_key]", True),
    },
    {
        "type": "github_token",
        "regex": re.compile(
            r"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[0-9A-Za-z_]{22,})\b"
        ),
        "replace": lambda match: ("[REDACTED:github_token]", True),
    },
    {
        "type": "gitlab_token",
        "regex": re.compile(r"\bglpat-[0-9A-Za-z_-]{20,}\b"),
        "replace": lambda match: ("[REDACTED:gitlab_token]", True),
    },
    {
        "type": "google_api_key",
        "regex": re.compile(r"\bAIza[0-9A-Za-z_-]{35}\b"),
        "replace": lambda match: ("[REDACTED:google_api_key]", True),
    },
    {
        "type": "stripe_key",
        "regex": re.compile(r"\bsk_(?:live|test)_[0-9A-Za-z]{16,}\b"),
        "replace": lambda match: ("[REDACTED:stripe_key]", True),
    },
    {
        "type": "api_key",
        "regex": re.compile(r"\bsk-[A-Za-z0-9_-]{20,}\b"),
        "replace": lambda match: ("[REDACTED:api_key]", True),
    },
    {
        "type": "db_credential",
        "regex": re.compile(
            r"\b(?P<scheme>postgres|postgresql|mysql|mongodb|redis|amqp)://"
            r"(?P<user>[^:@/\s]+):(?P<password>[^@/\s]+)@"
        ),
        "replace": lambda match: (
            f"{match.group('scheme')}://{match.group('user')}:[REDACTED:db_credential]@",
            True,
        ),
    },
    {
        "type": "slack_token",
        "regex": re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{8,}\b"),
        "replace": lambda match: ("[REDACTED:slack_token]", True),
    },
    {
        "type": "bearer_token",
        "regex": re.compile(r"\bBearer[ \t]+[A-Za-z0-9._~+/=-]{40,}\b"),
        "replace": lambda match: ("[REDACTED:bearer_token]", True),
    },
    {
        "type": "jwt",
        "regex": re.compile(
            r"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b"
        ),
        "replace": lambda match: ("[REDACTED:jwt]", True),
    },
    {
        "type": "generic_secret",
        "regex": re.compile(
            r"(?i)(?<![A-Za-z0-9])(?P<prefix>(?:[A-Za-z0-9]+_)*(?:password|token|secret)\s*[:=]\s*)"
            r"(?P<value>[A-Za-z0-9_./+=:-]{16,})"
        ),
        "replace": generic_replacement,
    },
]


def scoped_path(payload):
    tool_name = payload.get("tool_name")
    if tool_name not in TARGET_TOOLS:
        return None

    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        return None

    path_key = "notebook_path" if tool_name == "NotebookEdit" else "file_path"
    file_path = tool_input.get(path_key)
    if not isinstance(file_path, str) or not file_path:
        return None

    path = pathlib.Path(file_path)
    if not path.is_absolute():
        cwd = payload.get("cwd")
        base = pathlib.Path(cwd) if isinstance(cwd, str) and cwd else pathlib.Path.cwd()
        path = base / path

    resolved = path.resolve(strict=False)
    if ".agent-workbench" not in resolved.parts:
        return None
    return resolved


def scrub_text(text):
    counts = {}
    next_text = text

    for entry in PATTERNS:
        secret_type = entry["type"]
        regex = entry["regex"]
        replacement = entry["replace"]

        def replace_match(match):
            new_value, changed = replacement(match)
            if changed:
                counts[secret_type] = counts.get(secret_type, 0) + 1
            return new_value

        next_text = regex.sub(replace_match, next_text)

    return next_text, counts


def atomic_write(path, original_stat, content):
    temp_name = None
    fd = None
    try:
        fd, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=str(path.parent))
        with os.fdopen(fd, "wb") as handle:
            fd = None
            handle.write(content)
        os.chmod(temp_name, stat.S_IMODE(original_stat.st_mode))
        os.replace(temp_name, path)
        temp_name = None
    finally:
        if fd is not None:
            os.close(fd)
        if temp_name is not None:
            try:
                os.unlink(temp_name)
            except OSError:
                pass


def main():
    raw_stdin = sys.stdin.read()
    try:
        payload = json.loads(raw_stdin)
    except json.JSONDecodeError:
        log_line("malformed stdin: invalid JSON")
        return

    if not isinstance(payload, dict):
        return

    path = scoped_path(payload)
    if path is None or not path.is_file():
        return

    try:
        original_stat = path.stat()
        original_bytes = path.read_bytes()
        original_text = original_bytes.decode("utf-8", "surrogateescape")
        scrubbed_text, counts = scrub_text(original_text)
        if not counts or scrubbed_text == original_text:
            return

        atomic_write(
            path,
            original_stat,
            scrubbed_text.encode("utf-8", "surrogateescape"),
        )

        type_list = [entry["type"] for entry in PATTERNS if counts.get(entry["type"])]
        total = sum(counts.values())
        message = (
            f"Redacted {total} secret-like value(s) in {path} "
            f"(types: {', '.join(type_list)}). "
            "Workbench files must not contain credentials."
        )
        print(
            json.dumps(
                {
                    "hookSpecificOutput": {
                        "hookEventName": "PostToolUse",
                        "additionalContext": message,
                    }
                },
                separators=(",", ":"),
            )
        )
    except Exception as exc:
        log_line(f"scrubber error: {exc.__class__.__name__}")


main()
PY
}

main() {
  local log_path
  log_path="${ALBION_SCRUBBER_LOG:-/dev/null}"

  if ! command -v python3 >/dev/null 2>&1; then
    printf 'scrubber error: python3 not found\n' >>"$log_path" 2>/dev/null || true
    return 0
  fi

  python3 -c "$(python_source)" "$log_path" || true
}

main "$@"
