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
# Match rooms (0.31.119): rooms of 3, at most 2 (real server on 8102)
run match_rooms_test     MATCH_ROOMS_PASS         120
# Idle players (0.31.119): a bot takes over, input gives it back, removal (real server on 8103 + the real client)
run idle_test            IDLE_PASS                120
# Rejoin after a dropped connection (0.31.120): real server on 8105 + the real client
run rejoin_test          REJOIN_PASS              120
# Join a friend's match from Friends (0.31.120): real server on 8106 + the real app
run join_friend_test     JOIN_FRIEND_PASS         150
# End-of-match MVP strip and scoreboard (0.31.119)
run scoreboard_test      SCOREBOARD_PASS          60
# Weekly leaderboard (0.31.119): the board, the server (8104), the RANKS window
run leaderboard_test     LEADERBOARD_PASS         150
run lb_prizes_test       LB_PRIZES_PASS           90
run referral_test        REFERRAL_PASS            150
# Player profile card (0.31.120): stats_of, the real server (8108), RANKS > a row > the card
run profile_card_test    PROFILE_CARD_PASS        150
# SEND TO DEVELOPER (0.31.120): diag_reports.gd, fitting the log, the real server (8109) + Settings, diag_reports.py
run diag_send_test       DIAG_SEND_PASS           120
# Kill feed and vibration (0.31.120): the HUD feed, siege_mode haptics, Settings > VIBRATION
run kill_feed_test       KILL_FEED_PASS           90
# The next match only after PLAY AGAIN (0.31.122): real server (8110) + the real client; older apps as before
run next_match_test      NEXT_MATCH_PASS          150
# Discord link + its one-time gem reward (0.31.124)
run discord_test         DISCORD_PASS             60
# Daily login reward (0.31.119): the calendar, the server's replay, the card on Home and in ORDERS
run daily_reward_test    DAILY_REWARD_PASS        90
# Chest-ready notifications (0.31.119): notify.gd with a fake of the Android plugin, the app's ask and Settings
run notify_test          NOTIFY_PASS              90
# Google Play Games achievements (0.31.119): the list, what's sent and when (a fake of the plugin)
run achievements_test    ACHIEVEMENTS_PASS        60
# Forced update: protocol mismatch -> Update screen / "Servers are updating" (real server on 8096, fake on 8097)
run version_gate_test    VERSION_GATE_PASS        120
# Server minimum app build: an outdated build is refused as "update required" (real servers on 8098/8099)
run min_build_test       MIN_BUILD_PASS           120
run boot_guard_test      BOOT_GUARD_PASS          60
run outpost_look_test    OUTPOST_LOOK_PASS        90
run castle_kit_test      CASTLE_KIT_PASS          90
# Seated on either team (online): the stick follows the screen, your side drawn blue (0.31.85).
run side_view_test       SIDE_VIEW_PASS           120 --fixed-fps 30
# Earned titles (0.31.87): the table and its punctuation, earning, streaks, pass/shop/pack, healing counted.
run title_test           TITLE_PASS               60
run iap_test             IAP_PASS                 120
run preload_queue_test   PRELOAD_QUEUE_PASS       240
run forge_test           FORGE_PASS               120
run content_test         CONTENT_PASS             120
# The shop's tap-to-preview (0.31.96): real taps on every card, then buy / cancel / equip / an Arsenal from the preview.
run shop_preview_test    SHOP_PREVIEW_PASS        150 --resolution 420x933
# Class quests (0.31.97): the table, counting per class worn, claiming in order, the screens; and the in-match tracking.
run quest_test           QUEST_PASS               150 --resolution 420x933
run quest_track_test     QUEST_TRACK_PASS         120 --fixed-fps 30
run weapon_fx_test       WEAPON_FX_PASS           120 --fixed-fps 30
run shared_looks_test    SHARED_LOOKS_PASS        90
# Weapon grips (0.31.104): bow strings on the archer's side, one-handers held at the end of the handle.
run weapon_grip_test     WEAPON_GRIP_PASS         120
# Currency flies into the top bar's counters (0.31.105), and the Ember counter.
run reward_fly_test      REWARD_FLY_PASS          120 --fixed-fps 30 --resolution 420x933
# The shop's tiered pack art and the five gold offers (0.31.106).
run shop_packs_test      SHOP_PACKS_PASS          120 --resolution 420x933
# Siege Pass tier skips (0.31.107).
run tier_skip_test       TIER_SKIP_PASS           120 --resolution 420x933
run play_games_test      PLAY_GAMES_PASS          120 --resolution 420x933
# The server keeps the accounts (0.31.108): ops replayed, tickets, imports held, purchases once; end to end on port 8093.
run eco_server_test      ECO_SERVER_PASS          120
# The economy review's fixes (0.31.108): pass swaps, Silver gems, vault, waiting reward chests, prices, op replay.
run economy_fix_test     ECONOMY_FIX_PASS         60
# The menu sounds and the sliders at 100% by default (0.31.110).
run menu_sound_test      MENU_SOUND_PASS          60
# Home's "All Tied Up" title, the King swinging from the knot (0.31.113).
run title_logo_test      TITLE_LOGO_PASS          90
# Home's heroes in two rows, nobody reaching into anybody, clear of the medallions and PLAY; no ribbon (0.31.114).
run home_heroes_test     HOME_HEROES_PASS         90
# Floating menu icons move smoothly: no snapping to whole canvas pixels, and they float with their layout (0.31.116).
run menu_float_test      MENU_FLOAT_PASS          60
# Chat, friends, parties and quick chat (0.31.111): server/social.gd alone, then two phones against the real server.
run social_test          SOCIAL_PASS              150
run social_ui_test       SOCIAL_UI_PASS           200
# Usage statistics (0.31.118): the phone's queue, the server's files (and an older server on 8101), end to end against
# the real server on 8100 (the probe included), then the report on a fixture.
run analytics_client_test ANALYTICS_CLIENT_PASS   60
run analytics_server_test ANALYTICS_SERVER_PASS   90
run analytics_events_test ANALYTICS_EVENTS_PASS   150
t0=$SECONDS
if timeout 120 python3 tools/test_analytics_report.py > /tmp/siege_test_analytics_report.log 2>&1 && grep -q ANALYTICS_REPORT_PASS /tmp/siege_test_analytics_report.log; then
  printf "PASS  %-22s %4ds\n" "analytics_report (py)" $((SECONDS - t0))
else
  printf "FAIL  %-22s %4ds  (log: %s)\n" "analytics_report (py)" $((SECONDS - t0)) /tmp/siege_test_analytics_report.log
  grep -m5 '^FAIL\|Error' /tmp/siege_test_analytics_report.log | sed 's/^/      /'
  fail=1
fi
# The app's staged match start (0.31.78): the card first, the world built behind it over frames.
FB_STAGED_START=1 FB_FORCE_WARMUP=1 run staged_start_test STAGED_START_PASS 240 --fixed-fps 30
# The human soak must never stall the game thread.
if ! grep -q 'stalls=0' /tmp/siege_test_siege_human_soak.log; then
  echo "FAIL  siege_human_soak reported stalls"; fail=1
fi

[ $fail -eq 0 ] && echo "ALL SIEGE TESTS PASSED" || echo "SOME TESTS FAILED"
exit $fail
