#!/usr/bin/env bash
# Godot can return exit 0 for a script parse failure. Never mistake that for a
# passing scene/network test; preserve the complete diagnostic log on failure.
set -euo pipefail

if [[ $# -eq 0 ]]; then
  printf 'Usage: bash tools/run-godot-check.sh GODOT [arguments...]\n' >&2
  exit 2
fi
check_directory=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/corgi-godot-check.XXXXXX")
check_log="$check_directory/output.log"
"$@" 2>&1 | tee "$check_log"
if LC_ALL=C grep -Eq 'ERROR:|Parse Error|Failed to load script' "$check_log"; then
  printf 'Godot reported an error despite its exit status. Log: %s\n' "$check_log" >&2
  exit 1
fi
