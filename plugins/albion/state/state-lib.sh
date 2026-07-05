#!/usr/bin/env bash

albion_state_lib_dir() {
  cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

albion_state_cli() {
  printf '%s/albion-state\n' "$(albion_state_lib_dir)"
}

albion_state_file() {
  local session_id
  local state_dir
  session_id="$1"
  state_dir="${ALBION_STATE_DIR:-.albion/state}"
  printf '%s/%s.json\n' "$state_dir" "$session_id"
}

albion_state_get() {
  local session_id
  local key
  local state_file
  session_id="$1"
  key="$2"
  state_file="$(albion_state_file "$session_id")" || return
  if [ "$#" -ge 3 ]; then
    "$(albion_state_cli)" get --file "$state_file" --key "$key" --default "$3"
  else
    "$(albion_state_cli)" get --file "$state_file" --key "$key"
  fi
}

albion_state_set() {
  local session_id
  local key
  local value
  local state_file
  session_id="$1"
  key="$2"
  value="$3"
  state_file="$(albion_state_file "$session_id")" || return
  "$(albion_state_cli)" set --file "$state_file" --key "$key" --value "$value"
}

albion_state_incr() {
  local session_id
  local key
  local state_file
  session_id="$1"
  key="$2"
  state_file="$(albion_state_file "$session_id")" || return
  if [ "$#" -ge 3 ]; then
    "$(albion_state_cli)" incr --file "$state_file" --key "$key" --value "$3"
  else
    "$(albion_state_cli)" incr --file "$state_file" --key "$key"
  fi
}

albion_state_del() {
  local session_id
  local key
  local state_file
  session_id="$1"
  key="$2"
  state_file="$(albion_state_file "$session_id")" || return
  "$(albion_state_cli)" del --file "$state_file" --key "$key"
}

albion_state_dump() {
  local session_id
  local state_file
  session_id="$1"
  state_file="$(albion_state_file "$session_id")" || return
  "$(albion_state_cli)" dump --file "$state_file"
}
