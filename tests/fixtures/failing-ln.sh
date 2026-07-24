#!/usr/bin/env bash
set -euo pipefail

real_ln="__REAL_LN__"
fail_target="__FAIL_TARGET__"

if [[ "$#" -eq 3 && "$1" == "-s" && "$3" == "$fail_target" ]]; then
  exit 1
fi

exec "$real_ln" "$@"
