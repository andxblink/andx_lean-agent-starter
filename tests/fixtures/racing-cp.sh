#!/usr/bin/env bash
set -euo pipefail

real_cp="__REAL_CP__"
race_target="__RACE_TARGET__"

if [[ "$#" -eq 3 && "$1" == "-R" && "${!#}" == "." &&
      "$(pwd -P)" == "$race_target" ]]; then
  mv "$race_target" "$race_target.claimed"
  mkdir "$race_target"
  printf '%s\n' "replacement must survive" > "$race_target/racer-sentinel.txt"
  exec "$real_cp" "$@"
fi

exec "$real_cp" "$@"
