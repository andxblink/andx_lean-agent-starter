#!/usr/bin/env bash
set -euo pipefail

real_mkdir="__REAL_MKDIR__"
race_target="__RACE_TARGET__"

if [[ $# -eq 1 && "$1" == "$race_target" ]]; then
  "$real_mkdir" "$race_target"
  printf '%s\n' "claimed by racer" > "$race_target/racer-sentinel.txt"
  exit 1
fi

exec "$real_mkdir" "$@"
