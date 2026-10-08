#!/usr/bin/env bash
# Runs every Siege + app test headless and checks each one's pass marker.
# Usage (from the repo root or godot/):  GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64 godot/tools/run_siege_tests.sh [--quick]
#   --quick  : 2 simulation seeds instead of 6 (about 1 min instead of 3)
# Exit code 0 only if every test printed its marker with no SCRIPT ERROR.
set -uo pipefail

GODOT="${GODOT:-godot}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"          # .../godot
cd "$HERE"
QUICK=0
[ "${1:-}" = "--quick" ] && QUICK=1

if ! "$GODOT" --version >/dev/null 2>&1; then
  echo "Godot not found. Set GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64" >&2
  exit 2
fi

# First run on a fresh checkout: import assets once (creates godot/.godot/).
if [ ! -d .godot/imported ]; then
  echo "Importing assets (first run)..."
  timeout 600 "$GODOT" --headless --editor --path . --import >/dev/null 2>&1 || true
fi

fail=0
run() {   # run <name> <marker> <timeout> [extra godot args...]
  local name="$1" marker="$2" tmo="$3"; shift 3
  local log="/tmp/siege_test_${name}.log"
  local t0=$SECONDS
  timeout "$tmo" "$GODOT" --headless "$@" --path . -s "tests/${name}.gd" >"$log" 2>&1
  local errs; errs=$(grep -c 'SCRIPT ERROR' "$log")
  if grep -q "$marker" "$log" && [ "$errs" -eq 0 ]; then
    printf "PASS  %-22s %4ds\n" "$name" $((SECONDS - t0))
  else
    printf "FAIL  %-22s %4ds  (log: %s)\n" "$name" $((SECONDS - t0)) "$log"
    grep -m3 -A2 'SCRIPT ERROR\|Assertion' "$log" | sed 's/^/      /'
    fail=1
  fi
}

if [ $QUICK -eq 1 ]; then export SEEDS=11,22; export NO_RESCUE_CHECK=1; fi
run siege_sim_smoke      SIEGE_SIM_PASS           600
run siege_reach          SIEGE_REACH_PASS         120
run siege_land_check     SIEGE_LAND_PASS          120
run siege_mode_smoke     SIEGE_MODE_PASS          300 --fixed-fps 30
SEED=7 run siege_human_soak HUMAN_SOAK_DONE       300 --fixed-fps 30
run siege_diag_smoke     SIEGE_DIAG_PASS          150 --fixed-fps 30
run siege_guard_smoke    SIEGE_GUARD_PASS         120
run siege_logcat_filter  SIEGE_LOGCAT_FILTER_PASS 120
# Online: real server process + clients over WebSockets. Real time (no --fixed-fps), port 8092.
run siege_net_smoke      SIEGE_NET_PASS           150
run parse_all            PARSE_ALL_PASS           120
run meta_economy_test    META_ECONOMY_PASS        120
# The Siege app shell through its real buttons. REAL time (no --fixed-fps).
run app_flow_test        APP_FLOW_PASS            150
run app_scroll_test      APP_SCROLL_PASS          60
run tutorial_test        TUTORIAL_PASS            120
run net_interp_test      NET_INTERP_PASS          60
run knight_ai_test       KNIGHT_AI_PASS           90
run tower_test           TOWER_PASS               150
run hammer_test          HAMMER_PASS              150
run match_audio_test     MATCH_AUDIO_PASS         280
run items_test           ITEMS_PASS               290
run priest_test          PRIEST_PASS              200
run stands_test          STANDS_PASS              200
run bomb_test            BOMB_TEST_PASS           200
run digest_test          DIGEST_PASS              60
run answer_test          ANSWER_PASS              60
run launcher_test        LAUNCHER_PASS            60
run multikill_test       MULTIKILL_PASS           60
run announce_test        ANNOUNCE_PASS            120  --fixed-fps 60
run upgrades_test        UPGRADES_PASS            60
run blast_nodes_test     BLAST_NODES_PASS         60
run chest_test           CHEST_PASS               60
run combo_test           COMBO_PASS               60
run net_load_test        NET_LOAD_PASS            120
run boot_guard_test      BOOT_GUARD_PASS          60
run outpost_look_test    OUTPOST_LOOK_PASS        90
run castle_kit_test      CASTLE_KIT_PASS          90
# The app's staged match start (0.31.78): the card first, the world built behind it over frames.
FB_STAGED_START=1 FB_FORCE_WARMUP=1 run staged_start_test STAGED_START_PASS 240 --fixed-fps 30
# The human soak must never stall the game thread.
if ! grep -q 'stalls=0' /tmp/siege_test_siege_human_soak.log; then
  echo "FAIL  siege_human_soak reported stalls"; fail=1
fi

[ $fail -eq 0 ] && echo "ALL SIEGE TESTS PASSED" || echo "SOME TESTS FAILED"
exit $fail
