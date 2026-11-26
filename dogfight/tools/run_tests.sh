#!/usr/bin/env bash
# Runs every headless test and checks each one's pass marker.
#   GODOT=/path/to/godot tools/run_tests.sh [--strict]
# --strict also promotes the static-typing warnings to errors for the run
# (untyped/inferred declarations, unsafe access, unused variables, ...).
# Exit code 0 only if every test passed with no script errors.
set -uo pipefail

GODOT="${GODOT:-godot}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE"

if ! "$GODOT" --version >/dev/null 2>&1; then
  echo "Godot not found. Set GODOT=/path/to/Godot_v4.x-stable_linux.x86_64" >&2
  exit 2
fi

cleanup() { [ -n "${STRICT_CFG:-}" ] && rm -f override.cfg; }
trap cleanup EXIT
if [ "${1:-}" = "--strict" ]; then
  if [ -e override.cfg ]; then echo "override.cfg already exists; move it away first." >&2; exit 2; fi
  STRICT_CFG=1
  cat > override.cfg <<'CFG'
[debug]
gdscript/warnings/untyped_declaration=2
gdscript/warnings/inferred_declaration=2
gdscript/warnings/unsafe_property_access=2
gdscript/warnings/unsafe_method_access=2
gdscript/warnings/unsafe_call_argument=2
gdscript/warnings/unused_variable=2
gdscript/warnings/unused_parameter=2
gdscript/warnings/unused_signal=2
gdscript/warnings/shadowed_variable=2
gdscript/warnings/shadowed_variable_base_class=2
gdscript/warnings/integer_division=2
gdscript/warnings/narrowing_conversion=2
CFG
fi

# First run on a fresh checkout: build the script class cache (.godot/).
if [ ! -d .godot ]; then
  timeout 300 "$GODOT" --headless --path . --import >/dev/null 2>&1 || true
fi

fail=0
run() {   # run <name> <marker> <timeout> <scene> [user args...]
  local name="$1" marker="$2" tmo="$3" scene="$4"; shift 4
  local log; log="$(mktemp -t "dogfight_${name}.XXXXXX.log")"
  local t0=$SECONDS
  timeout "$tmo" "$GODOT" --headless --fixed-fps 60 --path . "$scene" -- "$@" >"$log" 2>&1
  local errs; errs=$(grep -c 'SCRIPT ERROR\|^ERROR' "$log")
  if grep -q "$marker" "$log" && [ "$errs" -eq 0 ]; then
    printf "PASS  %-24s %3ds\n" "$name" $((SECONDS - t0)); rm -f "$log"
  else
    printf "FAIL  %-24s %3ds  (log: %s)\n" "$name" $((SECONDS - t0)) "$log"
    grep -m6 'FAIL\|SCRIPT ERROR\|^ERROR' "$log" | sed 's/^/      /'
    fail=1
  fi
}

run progression        PROGRESSION_OK  120 res://tests/TestProgression.tscn
run player_flow        PLAYER_FLOW_OK  180 res://tests/TestPlayerFlow.tscn
for seed in 1 7 42; do
  run "match_sim_seed_$seed" MATCH_SIM_OK 300 res://tests/TestMatchSim.tscn "seed=$seed"
done
# Menus: load, run two seconds, and (lobby) hand over to the arena.
run_scene() {   # run_scene <name> <frames> <scene>
  local name="$1" frames="$2" scene="$3"
  local log; log="$(mktemp -t "dogfight_${name}.XXXXXX.log")"
  timeout 120 "$GODOT" --headless --fixed-fps 60 --quit-after "$frames" --path . "$scene" >"$log" 2>&1
  if [ "$(grep -c 'SCRIPT ERROR\|^ERROR' "$log")" -eq 0 ]; then
    printf "PASS  %-24s\n" "$name"; rm -f "$log"
  else
    printf "FAIL  %-24s (log: %s)\n" "$name" "$log"; grep -m6 'SCRIPT ERROR\|^ERROR' "$log" | sed 's/^/      /'; fail=1
  fi
}
run_scene hangar_loads   120 res://scenes/menu/MainMenu.tscn
run_scene lobby_to_arena 700 res://scenes/lobby/MatchLobby.tscn

[ "$fail" -eq 0 ] && echo "ALL PASSED" || echo "SOME TESTS FAILED"
exit "$fail"
