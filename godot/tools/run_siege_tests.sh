#!/usr/bin/env bash
# Runs every match + app test headless and checks each one's pass marker.
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
run siege_reach          SIEGE_REACH_PASS         120
run siege_land_check     SIEGE_LAND_PASS          120
run path_clear_test      PATH_CLEAR_PASS          120
run siege_mode_smoke     SIEGE_MODE_PASS          300 --fixed-fps 30
SEED=7 run siege_human_soak HUMAN_SOAK_DONE       300 --fixed-fps 30
run siege_diag_smoke     SIEGE_DIAG_PASS          150 --fixed-fps 30
run siege_guard_smoke    SIEGE_GUARD_PASS         120
run siege_logcat_filter  SIEGE_LOGCAT_FILTER_PASS 120
# Online: real server process + clients over WebSockets. Real time (no --fixed-fps), port 8092.
run parse_all            PARSE_ALL_PASS           120
run meta_economy_test    META_ECONOMY_PASS        120
# The app shell through its real buttons. REAL time (no --fixed-fps).
run app_flow_test        APP_FLOW_PASS            150
run app_scroll_test      APP_SCROLL_PASS          60
run net_interp_test      NET_INTERP_PASS          60
# 0.31.207 (Kevin: "The match keeps getting stutters"): the loading card shows every look once and clears it all; the
# lane minions' bodies from a pool, any other body BUILD_PER_FRAME a frame
run fx_warm_test         FX_WARM_PASS             120
# 0.31.208 (Kevin: the loading screen shows the joining players' heroes in their outfits): the screen, its states, the
# match's loading card
run loading_screen_test  LOADING_SCREEN_PASS      180
run minion_pool_test     MINION_POOL_PASS         240
# The online 5v5 (0.31.170): the snapshot protocol end to end against a server's 5v5 of bots (8 minutes of match, a hero
# swapped for a player's, a phone joining from a keyframe); then the real server (8121, stand-in old one on 8122) with
# phones and the game client -- heroes picked and owned, the mirrors agreeing, the 5v5's buttons, the end, the pay
run net_mirror_test      NET_MIRROR_PASS          600
run online_five_test     ONLINE_FIVE_PASS         240
run hammer_test          HAMMER_PASS              150
run match_audio_test     MATCH_AUDIO_PASS         280
run hero_assets_test     HERO_ASSETS_PASS         120
run tower_look_test      TOWER_LOOK_PASS          120
run foliage_test         FOLIAGE_PASS             120
run live_board_test      LIVE_BOARD_PASS          200
run names_aim_test       NAMES_AIM_PASS           200
run hud_top_test         HUD_TOP_PASS             200
run tower_rules_test     TOWER_RULES_PASS         400
run kill_rules_test      KILL_RULES_PASS          200
run kill_banner_test     KILL_BANNER_PASS         400
run recall_test          RECALL_PASS              300
run tutorial_test        TUTORIAL_PASS            400
run herald_intro_test    HERALD_INTRO_PASS        120
run priest_test          PRIEST_PASS              200
run multikill_test       MULTIKILL_PASS           60
run upgrades_test        UPGRADES_PASS            60
run chest_test           CHEST_PASS               60
run combo_test           COMBO_PASS               60
run net_load_test        NET_LOAD_PASS            120
# Match rooms (0.31.119): rooms of 3, at most 2 (real server on 8102)
run match_rooms_test     MATCH_ROOMS_PASS         120
# More rooms (0.31.209): the rooms step on worker threads, the cap by the cores, no room past the load limit (8141, 8142)
run rooms_load_test      ROOMS_LOAD_PASS          120
# Late joins (0.31.209, "Hybrid with 5min window"): a running match only when no countdown room can be had (8143)
run late_join_test       LATE_JOIN_PASS           120
# Idle players (0.31.119): a bot takes over, input gives it back, removal (real server on 8103 + the real client)
run idle_test            IDLE_PASS                120
# Rejoin after a dropped connection (0.31.120): real server on 8105 + the real client
run rejoin_test          REJOIN_PASS              120
# Friends > JOIN into a friend's match (0.31.120; out 0.31.164-0.31.169, back with the online 5v5): real server on 8106
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
# The iOS port (0.31.130): Platform, the store facades, billing_ios.gd / game_center.gd against doubles of
# GodotApplePlugins' StoreKit and Game Center, the app as an iPhone (and Android's words unchanged)
run ios_port_test        IOS_PORT_PASS            150
# Forced update: protocol mismatch -> Update screen / "Servers are updating" (real server on 8096, fake on 8097)
run version_gate_test    VERSION_GATE_PASS        120
# Server minimum app build: an outdated build is refused as "update required" (real servers on 8098/8099)
run min_build_test       MIN_BUILD_PASS           120
run boot_guard_test      BOOT_GUARD_PASS          60
run castle_kit_test      CASTLE_KIT_PASS          90
# Seated on either team (online): the stick follows the screen, your side drawn blue (0.31.85).
run side_view_test       SIDE_VIEW_PASS           120 --fixed-fps 30
# Earned titles (0.31.87): the table and its punctuation, earning, streaks, pass/shop/pack, healing counted.
run title_test           TITLE_PASS               60
run iap_test             IAP_PASS                 120
# App Store purchase checks (0.31.131): a stand-in Apple signs, the real helper checks, a fake App Store Server API
# answers; then the real server (8113) grants to accounts once (fake API on 8114)
run apple_iap_test       APPLE_IAP_PASS           150
# The account between phones (0.31.132): transfer codes, the Game Center link (a stand-in key server on 8117), deleting an
# account; server/eco_accounts.gd alone, then two phones against the real server (8116)
run account_move_test    ACCOUNT_MOVE_PASS        150
run preload_queue_test   PRELOAD_QUEUE_PASS       240
run outfits_test         OUTFITS_PASS             150
run economy_balance_test ECONOMY_BALANCE_PASS   120 --resolution 933x420
run league_iap_test      LEAGUE_IAP_PASS          120
run skins_test           SKINS_PASS               120
# The weekly sale (0.31.203): the featured three at 50/35/25 % off, buy_sale replayed on the server, its end, the shop
run weekly_sale_test     WEEKLY_SALE_PASS         150 --resolution 933x420
# The Armory and the Market's HEROES (0.31.204): only what you own in the Armory, heroes bought in the Market, the picker
run armory_market_test   ARMORY_MARKET_PASS       150 --resolution 933x420
run champions_test       CHAMPIONS_PASS           200
run content_test         CONTENT_PASS             120
# Class quests (0.31.97): the table, counting per class worn, claiming in order, the screens; and the in-match tracking.
run quest_test           QUEST_PASS               150 --resolution 933x420
run quest_track_test     QUEST_TRACK_PASS         120 --fixed-fps 30
# Weapon grips (0.31.104): bow strings on the archer's side, one-handers held at the end of the handle.
run weapon_grip_test     WEAPON_GRIP_PASS         120
# The Necromancer's glowing, smoking eyes (0.31.192).
run necro_eyes_test      NECRO_EYES_PASS          120
# Currency flies into the top bar's counters (0.31.105), and the Ember counter.
run reward_fly_test      REWARD_FLY_PASS          120 --fixed-fps 30 --resolution 933x420
# The shop's tiered pack art and the five gold offers (0.31.106).
run shop_packs_test      SHOP_PACKS_PASS          120 --resolution 933x420
# Siege Pass tier skips (0.31.107).
run tier_skip_test       TIER_SKIP_PASS           120 --resolution 933x420
run play_games_test      PLAY_GAMES_PASS          120 --resolution 933x420
# The server keeps the accounts (0.31.108): ops replayed, tickets, imports held, purchases once; end to end on port 8093.
run eco_server_test      ECO_SERVER_PASS          120
# The economy review's fixes (0.31.108): pass swaps, Silver gems, vault, waiting reward chests, prices, op replay.
run economy_fix_test     ECONOMY_FIX_PASS         60
# The menu sounds and the sliders at 100% by default (0.31.110).
run menu_sound_test      MENU_SOUND_PASS          60
# Home's "All Tied Up" title, the King swinging from the knot (0.31.113).
run title_logo_test      TITLE_LOGO_PASS          90
# 0.31.141: the title screen up first from the boot screen, the game loading behind it on a thread, put in after the
# slam; the match's script and the later windows load in the background queue, not with the game.
run boot_title_test      BOOT_TITLE_PASS          120
# Home's heroes in two rows, nobody reaching into anybody, clear of the medallions and PLAY; no ribbon (0.31.114).
# 0.31.138: Home is the war room -- the table and four heroes in 3D, the candles, sun, water and birds alive.
run home_camp_test       HOME_CAMP_PASS           90
# Floating menu icons move smoothly: no snapping to whole canvas pixels, and they float with their layout (0.31.116).
run menu_float_test      MENU_FLOAT_PASS          60
# Chat, friends, parties and quick chat (0.31.111): server/social.gd alone, then two phones against the real server.
run social_test          SOCIAL_PASS              150
run social_ui_test       SOCIAL_UI_PASS           200
# Clans (0.31.134): server/clans.gd through social.gd, then the app's CLAN window against the real
# server (8118) with a second phone: start a clan (gold taken), find, request, accept, clan chat, MANAGE, tags in the match.
run clans_test           CLANS_PASS               90
# 0.31.196: the crest, clan points, the week (Clan Chest, League), shard requests, 5-stacks, LFG
run clan_week_test       CLAN_WEEK_PASS           90
run clans_ui_test        CLANS_UI_PASS            240
# (0.31.169: Crown War's tests went with it -- the war map's battles were Siege matches)
# 0.31.155 5V5 (the test): heroes, waves (stacking), League's tower rules, gates behind towers, levels and picks, a
# hero's fall, whole bot matches; then the app -- Home's 5V5, the hero window, BATTLE, a level-up picked on the screen
run moba_test            MOBA_PASS                480
# 0.31.157: the 12 ultimates, gold (the trickle, last hits, knockouts and assists, towers), the shop (castle or down,
# building big items, one pair of boots, six slots, selling), the jungle (camps at 0:30, still until hit, leashed,
# rewards and respawn, the buffs and passing them on, the Bone Lord and his blessing), a whole bot match
run moba_more_test       MOBA_MORE_PASS           600
# 0.31.167: roles (two of the twelve each of the six) and kits -- W at 2, E at 3, their recharges, each of the 24 doing
# what it says, shields, slows, marks, poison, a fallen hero keeping nothing; the bots casting theirs
run moba_kits_test       MOBA_KITS_PASS           400
# 0.31.158: League's rules -- the fog of war (sight, brush, reveals, wards), the waves and minions' targets, the towers'
# targets, shares, Warming Up, plates, gates back up; the camps' patience and resets; the Bone Lord marching
run moba_lol_test        MOBA_LOL_PASS            300
run moba_ui_test         MOBA_UI_PASS             220
# 0.31.164 (Kevin: "5v5 only"): the 5v5's numbers on the hero, its rewards and challenges, Siege's swapped out, the server's clamp
run five_only_test        FIVE_ONLY_PASS           120
# 0.31.153: every script the server installs can load what it loads (the installer copies a list)
t0=$SECONDS
if timeout 60 python3 tools/test_server_files.py > /tmp/siege_test_server_files.log 2>&1 && grep -q SERVER_FILES_PASS /tmp/siege_test_server_files.log; then
  printf "PASS  %-22s %4ds\n" "server_files (py)" $((SECONDS - t0))
else
  printf "FAIL  %-22s %4ds  (log: %s)\n" "server_files (py)" $((SECONDS - t0)) /tmp/siege_test_server_files.log
  grep -m5 '^FAIL' /tmp/siege_test_server_files.log | sed 's/^/      /'
  fail=1
fi
# Usage statistics (0.31.118): the phone's queue, the server's files (and an older server on 8101), end to end against
# the real server on 8100 (the probe included), then the report on a fixture.
run analytics_client_test ANALYTICS_CLIENT_PASS   60
run analytics_server_test ANALYTICS_SERVER_PASS   90
run analytics_events_test ANALYTICS_EVENTS_PASS   150
run spend_tracking_test   SPEND_TRACKING_PASS     120     # 0.31.208, server: gold and gem spending (real server on 8133)
run heycatch_test         HEYCATCH_PASS           60      # 0.31.212: HeyCatch's batches, against a stand-in on 8141
run starter_offer_test   STARTER_OFFER_PASS      90      # 0.31.214: the Starter Pack on Home and its window
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
