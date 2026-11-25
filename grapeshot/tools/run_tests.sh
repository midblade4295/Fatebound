#!/usr/bin/env bash
# Runs every Grapeshot test headless and checks each one's pass marker.
# Usage:  GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64 grapeshot/tools/run_tests.sh
# Exit code 0 only if every test printed its marker with no script errors.
set -uo pipefail

GODOT="${GODOT:-godot}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE"

if ! "$GODOT" --version >/dev/null 2>&1; then
  echo "Godot not found. Set GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64" >&2
  exit 2
fi

fail=0
run() {   # run <name> <marker> <timeout> [extra godot args...]
  local name="$1" marker="$2" tmo="$3"; shift 3
  local log="${TMPDIR:-/tmp}/grapeshot_test_${name}.log"
  local t0=$SECONDS
  timeout "$tmo" "$GODOT" --headless "$@" --path . -s "tests/${name}.gd" >"$log" 2>&1
  local errs; errs=$(grep -c 'SCRIPT ERROR\|Parse Error' "$log")
  if grep -q "$marker" "$log" && [ "$errs" -eq 0 ]; then
    printf "PASS  %-18s %3ds\n" "$name" $((SECONDS - t0))
  else
    printf "FAIL  %-18s %3ds  (log: %s)\n" "$name" $((SECONDS - t0)) "$log"
    grep -m6 'FAIL\|SCRIPT ERROR\|Parse Error' "$log" | sed 's/^/      /'
    fail=1
  fi
}

run parse_all       GRAPESHOT_PARSE_PASS 60
run rules_test      GRAPESHOT_RULES_PASS 120
run bot_match_test  GRAPESHOT_BOTS_PASS  300
run app_smoke_test  GRAPESHOT_APP_PASS   180 --fixed-fps 30
exit $fail
