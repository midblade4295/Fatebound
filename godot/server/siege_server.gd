extends SceneTree
# Fatebound Siege dedicated server (headless Godot). Runs the same SiegeSim as offline play,
# authoritative, 16v16 with bots in every slot no human holds.
#
#   godot --headless --path <project> -s res://server/siege_server.gd
# Env: SIEGE_HOST (default 127.0.0.1 — keep it on loopback behind Caddy), SIEGE_PORT (8082),
#      SIEGE_MAX_PLAYERS (32: humans in one match room), SIEGE_MAX_ROOMS (4: matches at once, 0.31.119),
#      SIEGE_LOG (1 = log joins/leaves/match results to stdout),
#      SIEGE_LOBBY (seconds of the join countdown, default 20),
#      SIEGE_MIN_BUILD (oldest app build allowed online, e.g. 0.31.84; "off"/empty = no minimum). Without it the
#      server reads SIEGE_MIN_BUILD_FILE (default /etc/fatebound-siege/min_build, one line, e.g. "0.31.84") and
#      re-reads it every MIN_BUILD_RELOAD s (SIEGE_MIN_BUILD_RELOAD), so the minimum can be raised or lowered with no code change or restart.
#
# Minimum build (server 0.31.84-minbuild, Kevin: "Can you have the server put a update now message in game?"): an app
# whose hello says build (Diag.BUILD, e.g. "0.31.78-fatebound") older than the minimum is refused exactly like a client
# on an older protocol: bye {"why":"version","need":VERSION+1,...} + close 4001 "version:<VERSION+1>". The apps from
# vc32 (0.31.78) on read need > their protocol as "the server is newer" and show the full-screen "Update required"
# (UPDATE opens Google Play); vc31 and older show "Update the game to play online". A hello without a readable build
# (the probe without SIEGE_PROBE_BUILD, tools) is let in, so nothing that worked before is locked out by accident.
#
# 0.31.87 (Kevin: "make it so their titles show"; titles are earned in the app): a hello may name the player's title
# ("title": an id of Net.TITLES -- anything else is dropped, so nobody puts their own text over their head); "pn" carries
# "tt":{unit id: title id} beside the names and the lobby "tt" beside its names; the app joins them with the right
# punctuation. "st" {"heal"} tells each player the health they've healed (the Merciful title), at most once a second.
#
# 0.31.101 (Kevin: "I want players to see everything the other players are wearing"): a hello may carry "lk", the
# player's weapons and Forge stars per class (Net.clean_looks keeps only well-formed entries); "pn" carries
# "lk":{unit id: {class: entry}} beside the names and titles, and each app dresses those units from its own catalog.
#
# 0.31.86 (Kevin: "shows the player names on the battlefield above their heads. Only live players will show names."):
# {"t":"pn", "n":{unit id: name}} -- the seated players' names, sent to everyone in the match whenever a seat changes
# (join, leave, a new match). Bots aren't in it. Additive: older apps ignore it, so the protocol stays.
#
# 0.31.82 (Kevin: "when starting match have it countdown from 20 seconds and show players joining"; "players online
# in main menu"): a player who says hello waits in the lobby -- the first one starts a LOBBY_TIME countdown, everyone
# who arrives before it runs out joins with them, and the "lobby" message (every half second) tells the waiting
# players who is coming and how long is left. At zero they're seated: a new match if none is running (or only bots are
# left in it), else into the running one (in results, they go into the next one with everyone). A "status" message (no hello) is answered with
# the player counts (the asker then closes) -- the menu's "players online". Both are additive: an older app ignores
# "lobby" (it just waits for its welcome) and never asks for "status"; this app against an older server gets its
# welcome at once and no count (so the protocol version stays).
#
# 0.31.108 (Kevin: "make sure everything is verified by server so players can't edit gems ect"): the server keeps every
# player's account (server/eco_accounts.gd). "eco" (no hello, one per socket, like "iap"): a phone's ops replayed on
# its account, a VS BOTS ticket, the account back. "iap" with "acct"/"key": the confirmed purchase granted to that
# account here. A hello with "acct"/"key": the player's name, title and looks come from the account (nobody shows a
# weapon or title they don't own), and when the match ends the result is paid to the account from THIS server's count
# (server/match_ledger.gd), never the phone's. "ver" and "status" answer "eco":1 so the app knows. All additive: an
# older app keeps its own local economy until the minimum build is raised past it.
#
# 0.31.111 (Kevin: "Build a global chat and players can click a name and have option to add friend to a friends list.
# They can then group up and form a party. Also add the quick chat pings"): a socket whose first message is
# {"t":"so", "k":"hi", "acct", "key"} is a phone's social side (server/social.gd: chat, friends, parties) and stays
# open without a hello (it never counts as a player). A hello from an account in a party is seated on its party's team.
# {"t":"qc", "i"} in a match: a quick chat line (Net.QUICK_CHAT) to the player's side (or everyone), at most one every
# Net.QC_GAP s; "Need help!" / "Follow me!" call the nearest bots (sim.call_bots). "ver"/"status" answer "social":1.
# 0.31.134 (Crown War step 1): clans (server/clans.gd) on the same social socket; "pn" carries "ct":{unit id: clan tag}
# and the lobby "ct" beside its names, so the tag shows before a player's name; "ver"/"status" answer "clans":1.
# 0.31.135 (Crown War step 2): the war map (server/world.gd, on the social socket). A battle for a territory gets a room
# of its own (_war_room): never offered to ordinary matchmaking, waiting WAR_WAIT s for its first player, a WAR_LOBBY s
# countdown for the clan to gather, one match and no next one. A hello with "war": <battle id> is seated by house --
# the attackers' house on team 1, the holders' house on team 0 (world.side_for); anyone else is refused (bye "war_side",
# "war_gone", "war_full", "war_over", "war_twice": that account has a seat there already). Starting a battle spent the
# starter's attempt; another attacker of the attacking clan spends one when seated (world.seated). At the end
# world.battle_over gets the attackers' crowns (a defender's gate broken -- not the jail door --, a rescue, the win)
# and who of them is still there; each player gets {"t":"war", ...} with what the battle did. PLAY AGAIN after a
# battle: bye "war_over"; everyone on its results is let go after WAR_RESULTS_KEEP s, so the room closes. Battles
# never take the server's last room (matchmaking keeps it). Tests: SIEGE_WAR_LOBBY, SIEGE_WAR_WAIT, SIEGE_TEST_SCORE ("blue:red", set when
# SIEGE_TEST_MATCH_S ends a match).
#
# 0.31.118 (Kevin's spec, ANALYTICS_SPEC_FOR_CLAUDE.md -- self-hosted analytics, no SDK, no third party): a socket whose
# first message is {"t":"an", "acct", "key", "ev":[...]} hands over a batch of the phone's usage events
# (server/analytics.gd: checked against the account, kept in analytics/YYYY-MM-DD.jsonl in the state directory, answered
# {"t":"an", "ok":[ids]}; a key that doesn't open the account: 4005 "an", nothing written). The server writes what it
# knows itself: a hello with an account (session_online), the online match (start, finish, quit), verified purchases,
# chat/friends/parties (never the text), quick chat and the update screen -- none of them for an account that opted
# out ("an_off" in its hello or social "hi", or its opt_out event). "ver"/"status" answer "an":1, and only then does the
# phone send "an": the protocol stays 35 (an older server ignores "an", the phone keeps its queue).
#
# 0.31.119 (Kevin: "Do all" -- more than one match at a time): the server runs ROOMS, each its own match, lobby
# countdown and results screen, exactly as the one match ran before. SIEGE_MAX_PLAYERS is now the humans in ONE room
# (32 = 16v16, as before); SIEGE_MAX_ROOMS (default 4) how many rooms may run at once. A hello goes to its party's room
# when it has space, else the busiest room with space (players together rather than spread thin), else a new room;
# only when every room is full is it "full". A room with nobody in it for IDLE_STOP s closes. Match ids are unique
# across rooms ("match" in the welcome). "status" counts every room (+ "rooms"); the lobby message's "in_match" and
# "running" are its own room's, "online" the whole server's. Additive: the protocol stays 35, and an app sees no
# difference except that it isn't turned away.
#
# 0.31.119 (idle players): a seated player who gives no input (no movement, no attack/ability/block, no action, no quick
# chat) for IDLE_BOT s of live match time -- time dead, in the lobby, on the results screen or building the match on the
# phone (up to LOAD_GRACE s, until its first input message) doesn't count -- is played
# by a bot: their unit's bot flag goes on (every app sees it in the snapshots) and they get {"t":"idle", "on":true,
# "kick_in":s}. Any input hands the unit straight back ({"t":"idle", "on":false}). At IDLE_KICK s they're removed:
# bye {"why":"idle"} + close 4006 "idle"; the seat stays with the bot and the match pays them nothing.
#
# 0.31.119 (leaderboards): every paid online match adds to the account's week (server/leaderboard.gd). A socket whose
# first message is {"t":"lb", "acct", "key"} (no hello, like "eco") gets the week's board, the account's own row and its
# friends' rows; a key that doesn't open the account: 4007 "lb". "ver"/"status" answer "lb":1.
#
# 0.31.120 (Kevin: rejoin after a dropped connection): every welcome carries "rj", a secret token for that player's
# seat. When a seated player's socket drops mid-match (not a refusal, an idle removal, {"t":"leave"} or a clean close
# -- the app closes with 1000 "leave" when the player quits), the seat is HELD for REJOIN_HOLD s: a bot plays it, nobody else is seated on it, its
# match record (the ledger) is kept, and the match still pays it if it ends meanwhile. A hello with "rj" (and the same
# account) within that time goes straight back onto the same unit in the same match: welcome {"rejoin":true}, no lobby.
# A hello with the token of a socket the server still thinks is open (a phone that switched networks) takes that seat
# over and the old socket is closed. Additive: an older app never sends "rj" (its drop is held and simply runs out).
#
# 0.31.120 (Kevin: a friend in a match -- "make so it's a join match option"): a hello with "join": a friend's public id
# (social.gd's pid) goes into that friend's room -- their match, on their side while it has room -- when the two are
# friends and the room has space; otherwise the usual room, and {"t":"joinr", "ok":false, "why":"full"|"gone"} says why.
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Net = preload("res://scripts/siege/siege_net.gd")
const IapVerify = preload("res://server/iap_verify.gd")
const IapVerifyApple = preload("res://server/iap_verify_apple.gd")     # 0.31.131: App Store purchases (the iOS port)
const EcoAccounts = preload("res://server/eco_accounts.gd")
const MatchLedger = preload("res://server/match_ledger.gd")
const Social = preload("res://server/social.gd")
const Clans = preload("res://server/clans.gd")          # 0.31.134: Crown War step 1
const World = preload("res://server/world.gd")          # 0.31.135: Crown War step 2
const Map = preload("res://scripts/meta/war_map.gd")
const Analytics = preload("res://server/analytics.gd")
const Leaderboard = preload("res://server/leaderboard.gd")
const Referrals = preload("res://server/referrals.gd")
const DiagReports = preload("res://server/diag_reports.gd")

const RESTART_AFTER := 15.0          # seconds of results screen before the next match
const WAR_RESULTS_KEEP := 180.0      # 0.31.135: ... in a battle's room (there's no next match there)
const RESULTS_KEEP := 600.0          # 0.31.122: a player who stays on the results (PLAY AGAIN not pressed) is let go after this
const IDLE_STOP := 30.0              # no players for this long -> stop simulating (and the room closes)
const LOBBY_TIME := 20.0             # the join countdown (0.31.82)
const HELLO_TIMEOUT := 10.0
const IAP_TIMEOUT := 40.0              # a purchase check may take a token request and an API call
const REFUSE_CLOSE_DELAY := 0.25     # s between a "bye"/"ver" reply and closing the socket
const SERVER_BUILD := "0.31.141"      # this server's game version; the probe says it by default (identifies as current)
const MIN_BUILD_FILE := "/etc/fatebound-siege/min_build"
const MIN_BUILD_RELOAD := 10.0       # s between re-reads of the min-build file
const UPDATE_MSG := "A new version of Fatebound is out. Update now on Google Play to keep playing online."
const MAX_MSGS_PER_SEC := 90         # per client; beyond this, messages are dropped
const MAX_ROOMS := 4                 # 0.31.119: matches at once (SIEGE_MAX_ROOMS)
const IDLE_BOT := 45.0               # 0.31.119: s without input before a bot plays for them (SIEGE_IDLE_BOT)
const IDLE_KICK := 180.0             # ...and before they're removed (SIEGE_IDLE_KICK)
const CLOSE_IDLE := 4006
const WAR_LOBBY := 30.0              # 0.31.135: s a battle's room counts down for the clan to gather (SIEGE_WAR_LOBBY)
const WAR_WAIT := 90.0               # 0.31.135: s a battle's room waits for its first player (SIEGE_WAR_WAIT)
const REJOIN_HOLD := 60.0            # 0.31.120: s a dropped player's seat waits for them
const SILENT_DROP := 8.0             # 0.31.120: a seated phone that has sent nothing for this long is gone (its seat is held)
const LOAD_GRACE := 20.0             # s a phone may take to build the match before its idle time counts (until its first input)
const TICK := Sim.TICK

class Room:
	# 0.31.119: one match and its lobby (everything the server used to keep once)
	var id := 0
	var sim = null
	var match_id := 0
	var match_seed := 0
	var accum := 0.0
	var snap_accum := 0.0
	var ended_at := -1.0
	var empty_since := -1.0
	var pending_events: Array = []
	var wave_end := -1.0              # when the waiting players are seated (-1: nobody waiting)
	var lobby_clock := 0.0
	var names_dirty := false          # a seat changed: send the players' names (0.31.86)
	var paid_match := -1              # the match whose results went to the accounts
	var held := {}                    # 0.31.120: rejoin token -> a dropped player's seat ({"c": their client, "until", "drop_at"})
	var war := {}                     # 0.31.135: a battle's room: {"bid", "tid", "ah", "dh", "att_team", "def_team"} ({} = matchmaking)
	var war_made := 0.0
	var war_gate := false             # the attackers broke one of the defenders' gates (a crown)
	var war_done := false

var tcp := TCPServer.new()
var clients := {}                    # cid -> {ws, unit, name, hello, room, move, hold, joined_at, msgs, msg_clock}
var next_cid := 1
var rooms := {}                      # 0.31.119: room id -> Room
var next_room := 1
var match_counter := 0               # match ids, unique across rooms
var max_rooms := MAX_ROOMS
var host := "127.0.0.1"
var port := Net.DEFAULT_PORT
var max_players := 32                # humans in one room
var log_on := true
var lobby_time := LOBBY_TIME
var idle_stop := IDLE_STOP           # (tests: SIEGE_IDLE_STOP)
var rejoin_hold := REJOIN_HOLD       # (tests: SIEGE_REJOIN_HOLD)
var restart_after := RESTART_AFTER   # (tests: SIEGE_RESTART)
var results_keep := RESULTS_KEEP     # (tests: SIEGE_RESULTS_KEEP)
var idle_bot := IDLE_BOT
var idle_kick := IDLE_KICK
var iap = null                       # 0.31.90: Google Play purchase checks (server/iap_verify.gd)
var iap_apple = null                 # 0.31.131: App Store purchase checks (server/iap_verify_apple.gd)
var eco = null                       # 0.31.108: the accounts (server/eco_accounts.gd)
var social = null                    # 0.31.111: chat, friends, parties (server/social.gd)
var analytics = null                 # 0.31.118: usage statistics (server/analytics.gd)
var leaderboard = null               # 0.31.119: the week's best players (server/leaderboard.gd)
var referrals = null                 # 0.31.120: friend codes entered by new players (server/referrals.gd)
var diag_reports = null              # 0.31.120: SEND TO DEVELOPER (server/diag_reports.gd)
var world = null                     # 0.31.135: the war map (server/world.gd)
var war_lobby := WAR_LOBBY
var war_wait := WAR_WAIT
var test_score: Array = []           # tests only (SIEGE_TEST_SCORE): the score a SIEGE_TEST_MATCH_S match ends with
var boot_time := int(Time.get_unix_time_from_system())   # (with the match id: a match's id across restarts)
var test_match_s := 0.0              # tests only (SIEGE_TEST_MATCH_S): a match ends after this many seconds
var min_build := ""                  # "" = no minimum (see SIEGE_MIN_BUILD)
var min_build_env := false           # true: fixed by SIEGE_MIN_BUILD, the file is not read
var min_build_file := MIN_BUILD_FILE
var _min_build_clock := 0.0
var min_build_reload := MIN_BUILD_RELOAD

func _init() -> void:
	host = OS.get_environment("SIEGE_HOST") if OS.has_environment("SIEGE_HOST") else host
	if OS.has_environment("SIEGE_PORT"):
		port = int(OS.get_environment("SIEGE_PORT"))
	if OS.has_environment("SIEGE_MAX_PLAYERS"):
		max_players = clampi(int(OS.get_environment("SIEGE_MAX_PLAYERS")), 1, 32)
	if OS.has_environment("SIEGE_MAX_ROOMS"):
		max_rooms = clampi(int(OS.get_environment("SIEGE_MAX_ROOMS")), 1, 64)
	log_on = OS.get_environment("SIEGE_LOG") != "0"
	if OS.has_environment("SIEGE_LOBBY"):
		lobby_time = clampf(float(OS.get_environment("SIEGE_LOBBY")), 0.0, 120.0)
	if OS.has_environment("SIEGE_IDLE_STOP"):
		idle_stop = clampf(float(OS.get_environment("SIEGE_IDLE_STOP")), 0.5, 600.0)
	if OS.has_environment("SIEGE_REJOIN_HOLD"):
		rejoin_hold = clampf(float(OS.get_environment("SIEGE_REJOIN_HOLD")), 1.0, 600.0)
	if OS.has_environment("SIEGE_RESTART"):
		restart_after = clampf(float(OS.get_environment("SIEGE_RESTART")), 0.5, 600.0)
	if OS.has_environment("SIEGE_RESULTS_KEEP"):
		results_keep = clampf(float(OS.get_environment("SIEGE_RESULTS_KEEP")), 1.0, 3600.0)
	if OS.has_environment("SIEGE_IDLE_BOT"):
		idle_bot = clampf(float(OS.get_environment("SIEGE_IDLE_BOT")), 1.0, 3600.0)
	if OS.has_environment("SIEGE_IDLE_KICK"):
		idle_kick = clampf(float(OS.get_environment("SIEGE_IDLE_KICK")), idle_bot + 1.0, 7200.0)
	if OS.has_environment("SIEGE_TEST_MATCH_S"):
		test_match_s = float(OS.get_environment("SIEGE_TEST_MATCH_S"))
	if OS.has_environment("SIEGE_TEST_SCORE"):
		var sc := OS.get_environment("SIEGE_TEST_SCORE").split(":")
		if sc.size() == 2:
			test_score = [int(sc[0]), int(sc[1])]
	if OS.has_environment("SIEGE_WAR_LOBBY"):
		war_lobby = clampf(float(OS.get_environment("SIEGE_WAR_LOBBY")), 0.0, 300.0)
	if OS.has_environment("SIEGE_WAR_WAIT"):
		war_wait = clampf(float(OS.get_environment("SIEGE_WAR_WAIT")), 1.0, 3600.0)
	if OS.has_environment("SIEGE_MIN_BUILD"):
		min_build_env = true
		_set_min_build(OS.get_environment("SIEGE_MIN_BUILD"), "SIEGE_MIN_BUILD")
	else:
		if OS.has_environment("SIEGE_MIN_BUILD_FILE"):
			min_build_file = OS.get_environment("SIEGE_MIN_BUILD_FILE")
		if OS.has_environment("SIEGE_MIN_BUILD_RELOAD"):
			min_build_reload = clampf(float(OS.get_environment("SIEGE_MIN_BUILD_RELOAD")), 0.5, 3600.0)
		_reload_min_build()
	Engine.max_fps = 60              # headless would otherwise spin a core
	var err := tcp.listen(port, host)
	if err != OK:
		printerr("SIEGE_SERVER listen failed on %s:%d (%s)" % [host, port, error_string(err)])
		quit(1)
		return
	_log("SIEGE_SERVER listening on %s:%d (protocol %d, build %s, %d rooms of %d players, min build %s)" % [host, port, Net.VERSION,
		SERVER_BUILD, max_rooms, max_players, min_build if min_build != "" else "off"])
	iap = IapVerify.new()
	iap.log_fn = _log
	root.add_child.call_deferred(iap)
	_log("purchase checks: %s" % iap.describe())
	iap_apple = IapVerifyApple.new()
	iap_apple.log_fn = _log
	root.add_child.call_deferred(iap_apple)
	_log("purchase checks: %s" % iap_apple.describe())
	eco = EcoAccounts.new()
	eco.log_fn = _log
	_log("accounts: %d in %s" % [eco.count(), eco.dir])
	social = Social.new("", eco)
	social.log_fn = _log
	social.send_fn = func(cid: int, msg: Dictionary): _send(cid, msg)
	social.close_fn = func(cid: int):
		if clients.has(cid) and not clients[cid].has("close_at"):
			_send(cid, {"t":"so", "k":"bye", "why":"replaced"})
			_refuse(cid, 4003, "replaced")
	social.in_match_fn = func(acct: String) -> bool:
		for cid in clients:
			var c: Dictionary = clients[cid]
			if c.hello and str(c.get("acct", "")) == acct:
				return true
		return false
	social.clans = Clans.new(social.state, social)          # 0.31.134: clans ride the social socket
	world = World.new(social.state, social)                 # 0.31.135: the war map, on the social socket too
	world.room_fn = _war_room
	social.world = world
	_log("social: %d players known, %d clans, %d global chat lines kept; war map week %s, %d held" % [social.users.size(), social.clans.clans.size(),
		(social.hist.get("global", []) as Array).size(), world.week, world.owners.size()])
	analytics = Analytics.new()
	analytics.log_fn = _log
	social.event_fn = func(acct: String, ev: String, p: Dictionary): analytics.server_event(acct, ev, p)
	world.event_fn = func(acct: String, ev: String, p: Dictionary): analytics.server_event(acct, ev, p)
	_log("analytics: %s (%d accounts opted out)" % [analytics.dir, analytics.opted.size()])
	leaderboard = Leaderboard.new()
	leaderboard.log_fn = _log
	leaderboard.pay_fn = func(acct: String, week: String, rank: int, prize: Dictionary) -> bool:
		var ok: bool = eco.grant_prize(acct, week, rank, prize)
		if ok:
			_log("prize week %s: #%d %s (%d gems, %s chest, %s)" % [week, rank, acct, int(prize.get("gems", 0)), str(prize.get("chest", "")), str(prize.get("title", "-"))])
		return ok
	leaderboard.tag_fn = func(acct: String) -> String: return social.clans.tag_of_acct(acct)   # 0.31.134
	leaderboard.start()
	social.rank_fn = func(acct: String) -> int: return leaderboard.rank_of(acct)       # 0.31.120: the profile card
	referrals = Referrals.new()
	referrals.log_fn = _log
	diag_reports = DiagReports.new()
	diag_reports.log_fn = _log
	_log("leaderboard: week of %s, %d players" % [leaderboard.week, leaderboard.rows.size()])

# ---------------- minimum app build ----------------
# "0.31.78-fatebound" -> [0, 31, 78]; anything without a leading dotted number -> [] (unknown).
static func parse_build(b: String) -> Array:
	var head := b.strip_edges().split("-", true, 1)[0] if b.strip_edges() != "" else ""
	if head == "":
		return []
	var out := []
	for part in head.split("."):
		if not part.is_valid_int():
			return []
		out.append(part.to_int())
	return out

# -1 a < b, 0 equal, 1 a > b (missing parts count as 0: 0.31 == 0.31.0).
static func compare_builds(a: Array, b: Array) -> int:
	for i in maxi(a.size(), b.size()):
		var x: int = a[i] if i < a.size() else 0
		var y: int = b[i] if i < b.size() else 0
		if x != y:
			return -1 if x < y else 1
	return 0

# True only when both are readable and `build` is older than `minimum`. Unknown builds and "no minimum" pass.
static func build_too_old(build: String, minimum: String) -> bool:
	var m := parse_build(minimum)
	var b := parse_build(build)
	if m.is_empty() or b.is_empty():
		return false
	return compare_builds(b, m) < 0

func _set_min_build(v: String, src: String) -> void:
	v = v.strip_edges()
	if v.to_lower() in ["off", "none", "0"]:
		v = ""
	if v != "" and parse_build(v).is_empty():
		_log("min build: ignoring unreadable value '%s' from %s (kept %s)" % [v.left(40), src, min_build if min_build != "" else "off"])
		return
	if v == min_build:
		return
	min_build = v
	_log("min build %s (from %s)" % [min_build if min_build != "" else "off", src])
	if min_build != "" and build_too_old(SERVER_BUILD, min_build):
		_log("WARNING: min build %s is newer than this server (%s)" % [min_build, SERVER_BUILD])

func _reload_min_build() -> void:
	if min_build_env:
		return
	if not FileAccess.file_exists(min_build_file):
		_set_min_build("", min_build_file + " (missing)")
		return
	var f := FileAccess.open(min_build_file, FileAccess.READ)
	if f == null:
		return                       # unreadable right now: keep the last value
	_set_min_build(f.get_line(), min_build_file)

func _log(s: String) -> void:
	if log_on:
		print("[%s] %s" % [Time.get_datetime_string_from_system(true), s])

func _process(delta: float) -> bool:
	_accept()
	_poll_clients()
	_min_build_clock += delta
	if _min_build_clock >= min_build_reload:
		_min_build_clock = 0.0
		_reload_min_build()
	var ran := false
	for rid in rooms.keys():
		var r: Room = rooms[rid]
		_run_lobby(r, delta)
		if _run_match(r, delta):
			ran = true
		if r.names_dirty:
			r.names_dirty = false
			_send_names(r)
		_expire_holds(r)
		if r.sim == null and _room_humans(r) == 0:
			if not r.war.is_empty() and r.match_id == 0 and _now() - r.war_made < war_wait:
				continue                                 # 0.31.135: a battle's room waits for its first player
			rooms.erase(rid)                         # 0.31.119: nobody left and nothing running: the room closes
			_log("room %d closed (%d open)" % [rid, rooms.size()])
			if not r.war.is_empty() and world != null:
				world.battle_gone(str(r.war.bid))
	if ran:
		_stats_tick(delta)
	if social != null:
		social.tick(delta)
	if analytics != null:
		analytics.tick(delta)
	if leaderboard != null:
		leaderboard.tick(delta)
	return false

# ---------------- connections ----------------
func _accept() -> void:
	while tcp.is_connection_available():
		var conn := tcp.take_connection()
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = Net.MAX_PACKET
		ws.outbound_buffer_size = 1 << 20
		if ws.accept_stream(conn) != OK:
			continue
		clients[next_cid] = {"ws":ws, "unit":"", "name":"", "hello":false, "room":0, "move":Vector2.ZERO, "hold":false,
			"joined_at":Time.get_ticks_msec() / 1000.0, "msgs":0, "msg_clock":0.0}
		next_cid += 1

func _poll_clients() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for cid in clients.keys():
		if not clients.has(cid):
			continue                                   # (a rejoin took this one's seat this frame)
		var c: Dictionary = clients[cid]
		var ws: WebSocketPeer = c.ws
		ws.poll()
		var st := ws.get_ready_state()
		if st == WebSocketPeer.STATE_CLOSED:
			while ws.get_available_packet_count() > 0:      # (a "leave" can arrive together with the close)
				if str(Net.decode(ws.get_packet()).get("t", "")) == "leave":
					c.left = true
			# (a clean close -- the app's "leave" when the player quits, or any code 1000 -- holds nothing; a lost connection
			# has no close frame, 1006)
			_drop(cid, "left" if ws.get_close_reason() == "leave" or ws.get_close_code() == 1000 else "closed")
			continue
		if st != WebSocketPeer.STATE_OPEN:
			if now - float(c.joined_at) > HELLO_TIMEOUT:
				ws.close()
				_drop(cid, "handshake timeout")
			continue
		if c.has("close_at"):
			# A refusal ("bye" + close code) in progress: the bye goes out first, the close follows a moment later.
			# Closing in the same frame as the send lost the bye on the client (it only ever saw code 4001).
			while ws.get_available_packet_count() > 0:
				ws.get_packet()
			if now >= float(c.close_at):
				ws.close(int(c.close_code), str(c.close_reason))
				_drop(cid, str(c.close_reason))
			continue
		if not c.hello and not c.has("social") and now - float(c.joined_at) > (IAP_TIMEOUT if c.has("iap_busy") else HELLO_TIMEOUT):
			ws.close(4000, "no hello")
			_drop(cid, "no hello")
			continue
		if now - float(c.msg_clock) >= 1.0:
			c.msg_clock = now
			c.msgs = 0
		if c.hello and bool(c.get("got_in", false)) and not bool(c.get("queued", false)) and now - float(c.get("last_rx", now)) > SILENT_DROP:
			# 0.31.120: a phone that went quiet mid-match (lost its connection, or the app went to the background without a
			# close the server ever saw): close it and hold the seat, so it can come back
			ws.close(4008, "silent")
			_drop(cid, "silent")
			continue
		while ws.get_available_packet_count() > 0:
			var pkt := ws.get_packet()
			c.last_rx = now
			c.msgs += 1
			if c.msgs > MAX_MSGS_PER_SEC or pkt.size() > Net.MAX_PACKET:
				continue
			_handle(cid, Net.decode(pkt))

func _send(cid: int, msg: Dictionary) -> void:
	_send_raw(cid, Net.encode(msg, msg.get("t", "") in ["s", "eco", "iap", "an", "lb"]))      # (0.31.108: an account travels compressed; 0.31.118: and usage acks)

func _send_raw(cid: int, bytes: PackedByteArray) -> void:
	var c: Dictionary = clients.get(cid, {})
	if c.is_empty():
		return
	var ws: WebSocketPeer = c.ws
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.put_packet(bytes)

# Load stats (0.31.23): every STATS_EVERY s, how long the sim steps, the snapshot build and the sends took per second,
# and the bytes sent -- logged with SIEGE_STATS=1 (the net load test reads them). 0.31.119: all rooms together.
const STATS_EVERY := 5.0
var _st_step := 0
var _st_snap := 0
var _st_send := 0
var _st_bytes := 0
var _st_snaps := 0
var _st_clock := 0.0
var _st_frames := 0
var _st_frame_max := 0.0
func _stats_tick(delta: float) -> void:
	_st_clock += delta
	_st_frames += 1
	_st_frame_max = maxf(_st_frame_max, delta)
	if _st_clock < STATS_EVERY:
		return
	if OS.has_environment("SIEGE_STATS"):
		var n := _human_count()
		var units := 0
		for r in rooms.values():
			if r.sim != null:
				units += r.sim.units.size()
		var line := "SIEGE_STATS players=%d bots=%d rooms=%d step=%.1fms/s snapshot=%.1fms/s send=%.1fms/s kB/s=%.1f snaps/s=%.1f frames/s=%.1f worst_frame=%.0fms" % [
			n, maxi(0, units - n), rooms.size(), _st_step / 1000.0 / _st_clock, _st_snap / 1000.0 / _st_clock, _st_send / 1000.0 / _st_clock,
			_st_bytes / 1024.0 / _st_clock, _st_snaps / _st_clock, _st_frames / _st_clock, _st_frame_max * 1000.0]
		print(line)
		if OS.has_environment("SIEGE_STATS_FILE"):          # flushed per line (the load test reads it while we run)
			var f := FileAccess.open(OS.get_environment("SIEGE_STATS_FILE"), FileAccess.READ_WRITE if FileAccess.file_exists(OS.get_environment("SIEGE_STATS_FILE")) else FileAccess.WRITE)
			if f != null:
				f.seek_end()
				f.store_line(line)
				f.flush()
				f.close()
	_st_step = 0
	_st_snap = 0
	_st_send = 0
	_st_bytes = 0
	_st_snaps = 0
	_st_frames = 0
	_st_frame_max = 0.0
	_st_clock = 0.0

func _drop(cid: int, why: String) -> void:
	var c: Dictionary = clients.get(cid, {})
	if c.is_empty():
		return
	var r := _room_of(c)
	var sim = r.sim if r != null else null
	if sim != null and c.unit != "" and sim.by_id.has(c.unit):
		var u: Dictionary = sim.by_id[c.unit]
		u.bot = true                   # a bot takes the slot back over
		u.move = Vector2.ZERO
		u.net_driven = false
		r.names_dirty = true           # (their name goes off the battlefield)
	var hold: bool = r != null and sim != null and not sim.ended and c.hello and not bool(c.get("queued", false)) and c.unit != "" \
		and sim.by_id.has(c.unit) and str(c.get("rj", "")) != "" and not bool(c.get("left", false)) and why in ["closed", "handshake timeout", "silent"]
	if hold:
		# 0.31.120: the seat waits for them (a bot plays it meanwhile); match_quit only if they don't come back
		var keep := c.duplicate()
		keep.erase("ws")
		r.held[str(c.rj)] = {"c":keep, "until":_now() + rejoin_hold, "drop_at":_now()}
		_log("hold %s's seat %s for %.0f s (room %d)" % [c.name, c.unit, rejoin_hold, r.id])
	elif c.hello and c.has("acct") and analytics != null and sim != null and not sim.ended and c.unit != "" \
			and not bool(c.get("queued", false)) and sim.by_id.has(c.unit) and c.has("seated_at"):
		# 0.31.118: left a match before it ended
		analytics.server_event(str(c.acct), "match_quit", {"match":str(c.get("match_key", "")), "mode":"online",
			"quit_at_s":int(_now() - float(c.seated_at)), "class":class_of(sim.by_id[c.unit]), "class0":str(c.get("class0", ""))},
			str(c.get("build", "")))
	if c.hello:
		_log("leave %s (%s) unit=%s room=%d players=%d" % [c.name, why, c.unit, int(c.get("room", 0)), _human_count() - 1])
	clients.erase(cid)
	if social != null:
		if c.has("social"):
			social.drop(cid)
		if c.hello and c.has("acct"):
			social.acct_changed(str(c.acct))      # (their friends see them leave the match)

func _human_count() -> int:
	var n := 0
	for cid in clients:
		if clients[cid].hello:
			n += 1
	return n

# ---------------- rooms (0.31.119) ----------------
func _room_of(c: Dictionary) -> Room:
	return rooms.get(int(c.get("room", 0)), null)

func _members(r: Room) -> Array:
	# the room's players (seated or waiting)
	var out := []
	for cid in clients:
		var c: Dictionary = clients[cid]
		if c.hello and int(c.get("room", 0)) == r.id:
			out.append(cid)
	return out

func _room_humans(r: Room) -> int:
	return _members(r).size()

func _pick_room(party: String) -> Room:
	# the party's room (while it has space), else the busiest room with space, else a new one; null = every room is full
	if party != "":
		for cid in clients:
			var o: Dictionary = clients[cid]
			if o.hello and str(o.get("party", "")) == party:
				var pr := _room_of(o)
				if pr != null and pr.war.is_empty() and _room_humans(pr) + pr.held.size() < max_players:
					return pr
	var best: Room = null
	var best_n := -1
	for r in rooms.values():
		if not (r as Room).war.is_empty():
			continue                                     # 0.31.135: a battle's room is for its two houses only
		var n: int = _room_humans(r) + r.held.size()
		if n < max_players and n > best_n:
			best = r
			best_n = n
	if best != null:
		return best
	if rooms.size() >= max_rooms:
		return null
	var nr := Room.new()
	nr.id = next_room
	next_room += 1
	rooms[nr.id] = nr
	_log("room %d opened (%d open)" % [nr.id, rooms.size()])
	return nr

# ---------------- messages ----------------
func _handle(cid: int, msg: Dictionary) -> void:
	var c: Dictionary = clients[cid]
	if c.has("close_at"):
		return
	match str(msg.get("t", "")):
		"ver":
			# Version check (0.31.73, the "Update required" screen): the menu asks which protocol the server speaks
			# without joining a match. Older servers ignore this message (and drop the socket after HELLO_TIMEOUT),
			# so the client treats no answer as "unknown" and checks again on connect.
			if c.hello:
				return
			_send(cid, {"t":"ver", "v":Net.VERSION, "build":SERVER_BUILD, "min_build":min_build, "eco":1, "social":1, "an":1, "lb":1, "ref":1, "diag":1, "move":1, "clans":1})
			_refuse(cid, 1000, "ver")
		"hello":
			if c.hello or c.has("social"):
				return
			if int(msg.get("v", -1)) != Net.VERSION:
				# "need" = the protocol this server speaks; the close reason carries it too ("version:35") in case
				# the bye is lost. Old clients only look at why/the code, so both additions are backward compatible.
				_send(cid, {"t":"bye", "why":"version", "need":Net.VERSION})
				_refuse(cid, Net.CLOSE_VERSION, "version:%d" % Net.VERSION)
				_log("refused %s: protocol %d, server %d" % [str(msg.get("name", "?")).left(20), int(msg.get("v", -1)), Net.VERSION])
				return
			var build := str(msg.get("build", ""))
			if build_too_old(build, min_build):
				# Same protocol, but an app older than the minimum: refuse it as if the server were one protocol ahead,
				# which is what makes the vc32+ app show its full-screen "Update required" (Net.version_verdict "update").
				var need := Net.VERSION + 1
				_send(cid, {"t":"bye", "why":"version", "need":need, "min_build":min_build, "msg":UPDATE_MSG})
				_refuse(cid, Net.CLOSE_VERSION, "version:%d" % need)
				if analytics != null and eco != null and msg.has("acct") and not bool(msg.get("an_off", false)) \
						and not eco.open(str(msg.get("acct", "")), str(msg.get("key", ""))).is_empty():
					analytics.server_event(str(msg.acct), "update_screen", {"from_build":build, "need":min_build}, build)
				_log("refused %s: build %s older than min build %s" % [str(msg.get("name", "?")).left(20), build.left(30), min_build])
				return
			if str(msg.get("rj", "")) != "" and _rejoin(cid, msg):
				return                                         # 0.31.120: back on their seat
			var name := clean_name(str(msg.get("name", "Player")))
			var tid := str(msg.get("title", ""))
			var title := tid if Net.TITLES.has(tid) else ""
			var looks: Dictionary = Net.clean_looks(msg.get("lk", {}))  # 0.31.101: what they wear, for everyone to see
			var acct := ""
			var party := ""
			if msg.has("acct") and eco != null:
				# 0.31.108: an account -- its own name, title and looks (owned only), and the match is paid to it
				var w: Dictionary = eco.wear(str(msg.get("acct", "")), str(msg.get("key", "")))
				if not w.is_empty():
					acct = str(msg.acct)
					name = clean_name(str(w.name))
					title = str(w.title)
					looks = w.looks
					if social != null:
						party = social.party_for(acct)    # 0.31.111: seated with their party
			var r: Room = null
			var join_acct := ""
			var jp := str(msg.get("join", ""))
			var war_bid := str(msg.get("war", ""))
			var war_team := -1
			if war_bid != "":
				# 0.31.135: a battle on the war map -- its own room, on the side of the player's house
				var why := "war_gone"
				var wr := _war_room_of(war_bid)
				if acct == "" or world == null:
					why = "war_side"
				elif wr != null:
					var side: String = world.side_for(Social.pid_of(acct), war_bid)
					if wr.war_done or (wr.sim == null and wr.match_id != 0) or str(world.battles.get(war_bid, {}).get("state", "over")) == "over":
						why = "war_over"
					elif side == "":
						why = "war_side"
					elif _war_has_acct(wr, acct):
						why = "war_twice"                     # (one seat an account: a second phone or socket can't fill the side)
					else:
						var wt := int(wr.war.att_team) if side == "att" else int(wr.war.def_team)
						if _war_side_n(wr, wt) >= Net.TEAM_SIZE:
							why = "war_full"
						else:
							r = wr
							war_team = wt
				if r == null:
					_send(cid, {"t":"bye", "why":why})
					_refuse(cid, 4005, why)
					_log("refused %s for battle %s: %s" % [name, war_bid, why])
					return
			if jp != "" and acct != "" and social != null and war_bid == "":
				# 0.31.120: into a friend's match (Friends > JOIN)
				var why := "gone"
				var me_pid := Social.pid_of(acct)
				if social.users.has(jp) and social.users.has(me_pid) and (social.users[me_pid].get("friends", []) as Array).has(jp):
					var ta := str(social.users[jp].acct)
					for ocid in clients:
						var o: Dictionary = clients[ocid]
						if o.hello and str(o.get("acct", "")) == ta:
							var tr := _room_of(o)
							if tr != null and tr.war.is_empty() and _room_humans(tr) + tr.held.size() < max_players:
								r = tr
								join_acct = ta
							elif tr != null:
								why = "full"
							break
				if r == null:
					_send(cid, {"t":"joinr", "ok":false, "why":why})
			if r == null:
				r = _pick_room(party)
			if r == null:
				_send(cid, {"t":"bye", "why":"full"})
				_refuse(cid, 4002, "full")
				_log("refused %s: every room is full (%d rooms, %d players)" % [name, rooms.size(), _human_count()])
				return
			c.hello = true
			c.room = r.id
			if war_team >= 0:
				c.war_bid = war_bid
				c.war_team = war_team
			c.rj = Crypto.new().generate_random_bytes(8).hex_encode()   # 0.31.120: this player's rejoin token
			c.name = name
			c.title = title
			c.looks = looks
			if join_acct != "":
				c.join_acct = join_acct                       # (seated on their side when it has room)
			if acct != "":
				c.acct = acct
				c.party = party
				if social != null:
					social.acct_changed(acct)
			c.build = build.left(40)
			if c.has("acct") and analytics != null:
				# 0.31.118: a player on the server today (unless they opted out of usage statistics)
				analytics.set_opt_out(c.acct, bool(msg.get("an_off", false)))
				analytics.server_event(c.acct, "session_online", {}, c.build)
			c.pred = bool(msg.get("pred", false))         # the phone moves its own unit (0.18.4)
			c.ask_next = bool(msg.get("ask_next", false))  # 0.31.122: the phone says when it wants the next match (PLAY AGAIN)
			c.queued = true                                # 0.31.82: into the lobby; seated when the countdown ends
			if r.wave_end < 0.0:
				r.wave_end = _now() + (war_lobby if not r.war.is_empty() and r.sim == null else lobby_time)
			_log("queue %s (room %d, seated in %.0f s, players %d)" % [c.name, r.id, r.wave_end - _now(), _human_count()])
			r.lobby_clock = 1.0                            # tell everyone waiting at once
		"leave":
			# 0.31.120: the player quit the match on purpose -- don't hold the seat when the socket closes
			c.left = true
		"again":
			# 0.31.122 (Kevin: "make it so the game doesn't automatically put player back in a new game because they could be
			# looking at score card"): PLAY AGAIN on the results. While the results are up: into the next match when it
			# starts; once it's running (they stayed on the scores): seated in it now.
			var ra := _room_of(c)
			if not c.hello or ra == null or bool(c.get("queued", false)) or c.has("close_at"):
				return
			if not ra.war.is_empty():
				_send(cid, {"t":"bye", "why":"war_over"})       # 0.31.135: a battle is played once
				_refuse(cid, 1000, "war_over")
				return
			c.erase("results_at")
			if ra.sim != null and ra.sim.ended:
				c.again = true
			elif not bool(c.get("after", false)) and c.unit != "" and ra.sim != null and ra.sim.by_id.has(c.unit):
				return                                     # (already playing)
			else:
				c.after = false
				c.erase("again")
				if ra.sim == null:
					_new_match(ra)
				_seat(ra, cid)
		"status":
			# 0.31.82: the menu's "players online" -- answered without a hello; the asker closes (or we do in 2 s: a
			# close right behind the answer can reach the phone in the same read, and the WebSocket drops the answer)
			if not c.hello:
				_send(cid, _status())
				_refuse(cid, 1000, "status")
				c.close_at = _now() + 2.0         # (the refusal path closes it; 2 s rather than REFUSE_CLOSE_DELAY)
		"so":
			# 0.31.111: a phone's social side (server/social.gd) -- "hi" first, then chat, friends and parties
			if c.hello or social == null:
				return
			if c.has("social"):
				social.handle(cid, msg)
			elif str(msg.get("k", "")) == "hi":
				if social.hello(cid, msg):
					c.social = true
					if analytics != null:
						analytics.set_opt_out(str(msg.get("acct", "")), bool(msg.get("an_off", false)))
				else:
					_refuse(cid, 4004, "social")
		"qc":
			# 0.31.111: a quick chat line in a match, to the player's side ("Good game!" to everyone)
			var r := _room_of(c)
			if not c.hello or r == null or r.sim == null or c.unit == "" or not r.sim.by_id.has(c.unit) or bool(c.get("queued", false)):
				return
			var qi := int(msg.get("i", -1))
			if qi < 0 or qi >= Net.QUICK_CHAT.size() or _now() - float(c.get("qc_at", -99.0)) < Net.QC_GAP:
				return
			c.qc_at = _now()
			_active(r, cid)
			var q: Dictionary = Net.QUICK_CHAT[qi]
			var qteam := int(r.sim.by_id[c.unit].team)
			if bool(q.get("call", false)) and not r.sim.ended:
				r.sim.call_bots(c.unit)
			if c.has("acct") and analytics != null:
				analytics.server_event(c.acct, "quick_chat", {"i":qi}, str(c.get("build", "")))
			var qmsg := {"t":"qc", "u":c.unit, "i":qi}
			for ocid in _members(r):
				var o: Dictionary = clients[ocid]
				if not bool(o.get("queued", false)) and o.unit != "" and r.sim.by_id.has(o.unit) \
						and (bool(q.get("all", false)) or int(r.sim.by_id[o.unit].team) == qteam):
					_send(ocid, qmsg)
		"eco":
			# 0.31.108: a phone's account -- its ops, a ticket, the account as it stands. One per socket, no hello.
			if c.hello or c.has("eco_done") or c.has("social") or eco == null:
				return
			c.eco_done = true
			var eop := str(msg.get("op", ""))
			if eop in ["link_new", "link_use", "delete", "gc"]:
				_eco_op(cid, eop, msg)                 # 0.31.132: the account between phones (the iOS port)
				return
			var t0 := Time.get_ticks_usec()
			var out: Dictionary = eco.handle(msg)
			if referrals != null and bool(out.get("ok", false)) and referrals.check(str(out.get("acct", "")), eco) > 0:
				out = eco.handle({"t":"eco", "acct":str(out.acct), "key":str(msg.get("key", "")), "ops":[]})    # (with the chest in it)
			_send(cid, out)
			_refuse(cid, 1000, "eco")
			c.close_at = _now() + 2.0
			if not bool(out.get("ok", false)) or bool(msg.get("new", false)) or not (out.get("results", []) as Array).is_empty() or out.has("ticket"):
				_log("eco %s: %s%d ops%s (%.1f ms)" % [str(out.get("acct", "?")), "NEW " if bool(msg.get("new", false)) else "",
					(out.get("results", []) as Array).size(), "" if bool(out.get("ok", false)) else " " + str(out.get("why", "")),
					(Time.get_ticks_usec() - t0) / 1000.0])
		"an":
			# 0.31.118: a batch of the phone's usage events (server/analytics.gd). One per socket, no hello.
			if c.hello or c.has("an_done") or c.has("social") or analytics == null:
				return
			c.an_done = true
			var aout: Dictionary = analytics.handle(msg, eco)
			if aout.is_empty():
				_refuse(cid, 4005, "an")                       # (the key doesn't open the account: nothing written)
				return
			_send(cid, aout)
			_refuse(cid, 1000, "an")
			c.close_at = _now() + 2.0
		"lb":
			# 0.31.119: the week's leaderboard for an account (its row and its friends'). One per socket, no hello.
			if c.hello or c.has("lb_done") or c.has("social") or leaderboard == null or eco == null:
				return
			c.lb_done = true
			var lacct := str(msg.get("acct", ""))
			if lacct == "" or eco.open(lacct, str(msg.get("key", ""))).is_empty():
				_refuse(cid, 4007, "lb")
				return
			_send(cid, leaderboard.answer(lacct, social.friend_accts(lacct) if social != null else []))
			_refuse(cid, 1000, "lb")
			c.close_at = _now() + 2.0
		"ref":
			# 0.31.120: a new player enters a friend's code (server/referrals.gd). One per socket, no hello.
			if c.hello or c.has("ref_done") or c.has("social") or referrals == null or eco == null:
				return
			c.ref_done = true
			_send(cid, referrals.claim(str(msg.get("acct", "")), str(msg.get("key", "")), str(msg.get("code", "")), eco, social))
			_refuse(cid, 1000, "ref")
			c.close_at = _now() + 2.0
		"diag":
			# 0.31.120: SEND TO DEVELOPER -- the player sends the game's log (server/diag_reports.gd). One per socket, no hello.
			if c.hello or c.has("diag_done") or c.has("social") or diag_reports == null:
				return
			c.diag_done = true
			_send(cid, diag_reports.handle(msg, eco, (c.ws as WebSocketPeer).get_connected_host()))
			_refuse(cid, 1000, "diag")
			c.close_at = _now() + 2.0
		"iap":
			# 0.31.90: a phone asks whether a Google Play purchase is real before it grants it. No hello (a purchase is
			# not a player); one question per socket; the answer goes back and the socket closes.
			if c.hello or c.has("iap_busy") or iap == null:
				return
			c.iap_busy = true
			var product := str(msg.get("product", ""))
			var token := str(msg.get("token", ""))
			var acct := str(msg.get("acct", ""))
			var akey := str(msg.get("key", ""))
			if str(msg.get("store", "google")) == "apple":
				_iap_apple(cid, product, str(msg.get("jws", "")), acct, akey)   # 0.31.131 (no "store": Google, as before)
				return
			iap.verify(product, token, func(res: Dictionary):
				if not clients.has(cid):
					return
				var out := res.duplicate()
				out["t"] = "iap"
				out["product"] = product
				out["token"] = token
				if eco != null and (bool(res.get("ok", false)) or str(res.get("why", "")) == "used"):
					if acct != "":
						# 0.31.108: granted here, to the account (once per token, whichever account asks)
						var g: Dictionary = eco.grant_purchase(acct, akey, product, token, str(res.get("why", "")) == "used")
						out["granted"] = g
						if bool(g.get("ok", false)) and not bool(g.get("again", false)) and analytics != null:
							analytics.server_event(acct, "purchase_verified", {"product":product, "test":bool(res.get("test", false)), "store":"google"})
						if bool(res.get("ok", false)) and not bool(g.get("ok", false)):
							out["ok"] = false
							out["why"] = str(g.get("why", "bad"))
					elif bool(res.get("ok", false)):
						eco.note_verified(token)          # (an older app grants it itself)
				_send(cid, out)
				_refuse(cid, 1000, "iap")
				clients[cid].close_at = _now() + 2.0
				_log("purchase %s: %s%s" % [product, "ok" if bool(res.get("ok", false)) else str(res.get("why", "")),
					" (test)" if bool(res.get("test", false)) else ""]))
		"in":
			var r := _room_of(c)
			if not c.hello or r == null or r.sim == null or c.unit == "":
				return
			var m: Variant = msg.get("m", Vector2.ZERO)
			if m is Vector2 and is_finite(m.x) and is_finite(m.y):
				c.move = (m as Vector2).limit_length(1.0)
			c.hold = bool(msg.get("h", false))
			c.bhold = bool(msg.get("b", false))
			c.khold = bool(msg.get("k", false))                # 0.31.61: the Crusader's held block
			var cp: Variant = msg.get("p", null)
			if cp is Vector2 and is_finite(cp.x) and is_finite(cp.y):
				c.cpos = cp
				c.cface = float(msg.get("f", 0.0))
				c.cpos_new = true
				c.cpos_rx = Time.get_ticks_msec() / 1000.0
			var a: String = str(msg.get("a", ""))
			if not bool(c.get("got_in", false)):
				c.got_in = true                                # the phone has the match up: idle time counts from here
				c.idle_s = maxf(float(c.get("idle_s", 0.0)), 0.0)
			if (c.move as Vector2).length() > 0.15 or c.hold or c.bhold or c.khold or a != "":
				_active(r, cid)                                # 0.31.119: a real input (not just the phone's position)
			if bool(c.get("idle", false)):
				return                                         # (a bot plays for them until they do something)
			if a != "" and a in Net.ACTIONS:
				var arg: Variant = msg.get("arg", null)
				if a == "buy":
					arg = str(arg) if str(arg) in Sim.UPGRADES else ""
				else:
					arg = null
				r.sim.act(c.unit, a, arg)

func _eco_op(cid: int, op: String, msg: Dictionary) -> void:
	# 0.31.132 (the iOS port, IOS_PORT_SPEC_FOR_CLAUDE.md §4, §6), one per socket like any "eco":
	#   link_new  {acct, key}        -> {code, ttl}: Settings > MOVE TO ANOTHER PHONE
	#   link_use  {code}             -> {acct, key, seq, profile}: the other phone's ENTER A CODE (Android <-> iPhone)
	#   gc        {acct?, key?, gc:{id, url, sig, salt, ts}, relink?} -> Game Center player linked / found ("other")
	#   delete    {acct, key}        -> the account deleted (and forgotten by chat, friends and the leaderboard)
	var acct := str(msg.get("acct", ""))
	var akey := str(msg.get("key", ""))
	var finish := func(out: Dictionary) -> void:
		if not clients.has(cid):
			return
		_send(cid, out)
		_refuse(cid, 1000, "eco")
		clients[cid].close_at = _now() + 2.0
		_log("eco %s: %s %s" % [acct if acct != "" else str(out.get("acct", "-")), op,
			"ok" + (" " + str(out.get("gc", "")) if out.has("gc") else "") if bool(out.get("ok", false)) else str(out.get("why", ""))])
	match op:
		"link_new":
			finish.call(eco.link_new(acct, akey))
		"link_use":
			var addr := (clients[cid].ws as WebSocketPeer).get_connected_host()
			finish.call(eco.link_use(str(msg.get("code", "")), addr))
		"delete":
			var out: Dictionary = eco.delete_account(acct, akey)
			if bool(out.get("ok", false)):
				if social != null:
					social.forget(acct)
				if leaderboard != null:
					leaderboard.forget(acct)
				if analytics != null:
					analytics.set_opt_out(acct, true)    # (nothing more is recorded; what is there ages out in 90 days)
			finish.call(out)
		"gc":
			if iap_apple == null:
				finish.call({"t":"eco", "ok":false, "op":"gc", "why":"off"})
				return
			var g: Variant = msg.get("gc", {})
			var relink := bool(msg.get("relink", false))
			iap_apple.verify_gc(g, func(ok: bool, why: String):
				if not ok:
					finish.call({"t":"eco", "ok":false, "op":"gc", "why":why})
					return
				finish.call(eco.gc_link(acct, akey, str((g as Dictionary).get("id", "")), relink)))

func _iap_apple(cid: int, product: String, jws: String, acct: String, akey: String) -> void:
	# 0.31.131 (the iOS port): an App Store purchase -- Apple's signed transaction checked (server/iap_verify_apple.gd),
	# then granted to the account exactly like a Google one: once per ledger token ("apple:<transaction>"), never to
	# another account. The answer goes back and the socket closes, as for Google.
	if iap_apple == null:
		return
	iap_apple.verify(product, jws, acct, func(res: Dictionary):
		if not clients.has(cid):
			return
		var out := res.duplicate()
		out["t"] = "iap"
		out["product"] = product
		out["store"] = "apple"
		var token := str(res.get("token", ""))
		if eco != null and bool(res.get("ok", false)) and token != "":
			if acct != "":
				var g: Dictionary = eco.grant_purchase(acct, akey, product, token, false)
				out["granted"] = g
				if bool(g.get("ok", false)) and not bool(g.get("again", false)) and analytics != null:
					analytics.server_event(acct, "purchase_verified", {"product":product, "test":bool(res.get("test", false)), "store":"apple"})
				if not bool(g.get("ok", false)):
					out["ok"] = false
					out["why"] = str(g.get("why", "bad"))
			else:
				eco.note_verified(token)
		_send(cid, out)
		_refuse(cid, 1000, "iap")
		clients[cid].close_at = _now() + 2.0
		_log("purchase %s (Apple): %s%s" % [product, "ok" if bool(out.get("ok", false)) else str(out.get("why", "")),
			" (test)" if bool(res.get("test", false)) else ""]))

func _refuse(cid: int, code: int, reason: String) -> void:
	# Close a little after the last message so it reaches the client before the close frame.
	var c: Dictionary = clients[cid]
	c.close_at = Time.get_ticks_msec() / 1000.0 + REFUSE_CLOSE_DELAY
	c.close_code = code
	c.close_reason = reason

func _seat(r: Room, cid: int) -> void:
	# Take over a bot on the team with fewer humans (blue on ties).
	var sim = r.sim
	var c: Dictionary = clients[cid]
	var humans := [0, 0]
	for other in _members(r):
		var oc: Dictionary = clients[other]
		if other != cid and oc.unit != "" and sim.by_id.has(oc.unit):
			humans[sim.by_id[oc.unit].team] += 1
	var team := 0 if humans[0] <= humans[1] else 1
	var pa := str(c.get("party", ""))
	if c.has("war_team"):
		team = int(c.war_team)                         # 0.31.135: a battle: the side of their house
		pa = ""
	if pa != "":
		# 0.31.111: a party plays on one side -- the side a member already holds a seat on (while it has room)
		for other in _members(r):
			var oc: Dictionary = clients[other]
			if other != cid and str(oc.get("party", "")) == pa and oc.unit != "" and sim.by_id.has(oc.unit):
				var pt := int(sim.by_id[oc.unit].team)
				if humans[pt] < Net.TEAM_SIZE:
					team = pt
				break
	var ja := str(c.get("join_acct", "")) if not c.has("war_team") else ""
	if ja != "":
		# 0.31.120: joined a friend's match -- their side, while it has room
		for other in _members(r):
			var oc: Dictionary = clients[other]
			if other != cid and str(oc.get("acct", "")) == ja and oc.unit != "" and sim.by_id.has(oc.unit):
				var jt := int(sim.by_id[oc.unit].team)
				if humans[jt] < Net.TEAM_SIZE:
					team = jt
				break
	var seat := ""
	for u in sim.units:
		if u.team == team and u.bot and not _unit_taken(r, u.id):
			seat = u.id
			break
	if seat == "" and not c.has("war_team"):
		for u in sim.units:
			if u.bot and not _unit_taken(r, u.id):
				seat = u.id
				break
	if seat == "" and c.has("war_team"):
		_send(cid, {"t":"bye", "why":"war_full"})
		_refuse(cid, 4005, "war_full")
		return
	c.unit = seat
	c.queued = false
	c.move = Vector2.ZERO
	c.idle = false
	c.idle_s = -LOAD_GRACE                 # (counts from the phone's first input message, or after the grace)
	c.got_in = false
	if seat != "":
		sim.by_id[seat].bot = false
		if c.has("acct"):
			c.ledger = MatchLedger.new()          # 0.31.108: counted from here (a bot held the seat before)
			c.ledger.start(sim.by_id[seat])
			c.seated_at = _now()                  # 0.31.118: the match as the player had it, for the statistics
			c.class0 = class_of(sim.by_id[seat])
			c.match_key = match_key(r)
			if analytics != null:
				analytics.server_event(c.acct, "match_start", {"match":c.match_key, "mode":"online", "class":c.class0}, str(c.get("build", "")))
			if c.has("war_team") and int(c.war_team) == int(r.war.get("att_team", 1)) and world != null:
				c.war_scores = world.seated(str(c.war_bid), Social.pid_of(str(c.acct)), str(c.acct), str(c.name))   # 0.31.135
	_send(cid, {"t":"welcome", "v":Net.VERSION, "you":seat, "match":r.match_id, "seed":r.match_seed,
		"team_size":Net.TEAM_SIZE, "players":_room_humans(r), "rj":str(c.get("rj", ""))})
	r.names_dirty = true
	# The first snapshot right away so the client can build its view.
	_send(cid, Net.snapshot(sim, seat, []))
	_log("join %s -> %s (room %d, match %d, players %d)" % [c.name, seat, r.id, r.match_id, _room_humans(r)])

func _unit_taken(r: Room, id: String) -> bool:
	for cid in _members(r):
		if clients[cid].unit == id:
			return true
	for k in r.held:                                   # 0.31.120: a held seat waits for its player
		if str(r.held[k].c.get("unit", "")) == id:
			return true
	return false

# ---------------- player names (0.31.86) ----------------
static func clean_name(s: String) -> String:
	# What the battlefield shows over a player: no control characters, at most 20 letters, never empty.
	var out := ""
	for ch in s:
		if ch.unicode_at(0) >= 32 and ch.unicode_at(0) != 127:
			out += ch
	out = out.strip_edges().left(20)
	return out if out != "" else "Player"

func _seated(r: Room) -> Array:
	# the room's players holding a seat in its match
	var out := []
	if r.sim == null:
		return out
	for cid in _members(r):
		var c: Dictionary = clients[cid]
		if not bool(c.get("queued", false)) and c.unit != "" and r.sim.by_id.has(c.unit):
			out.append(cid)
	return out

func player_names(r: Room) -> Dictionary:
	var out := {}
	for cid in _seated(r):
		out[clients[cid].unit] = clients[cid].name
	return out

func player_titles(r: Room) -> Dictionary:
	var out := {}
	for cid in _seated(r):
		if str(clients[cid].get("title", "")) != "":
			out[clients[cid].unit] = str(clients[cid].title)
	return out

func player_tags(r: Room) -> Dictionary:
	# 0.31.134: unit id -> clan tag for each seated player in a clan
	var out := {}
	if social == null or social.clans == null:
		return out
	for cid in _seated(r):
		var ct: String = social.clans.tag_of_acct(str(clients[cid].get("acct", "")))
		if ct != "":
			out[clients[cid].unit] = ct
	return out

func player_looks(r: Room) -> Dictionary:
	# 0.31.101: unit id -> {class: "weapon id|stars|element"} for each seated player who wears something
	var out := {}
	for cid in _seated(r):
		if not (clients[cid].get("looks", {}) as Dictionary).is_empty():
			out[clients[cid].unit] = clients[cid].looks
	return out

func _send_names(r: Room) -> void:
	var msg := {"t":"pn", "n":player_names(r), "tt":player_titles(r), "lk":player_looks(r), "ct":player_tags(r)}
	for cid in _members(r):
		var c: Dictionary = clients[cid]
		if not bool(c.get("queued", false)) and c.unit != "":
			_send(cid, msg)

# ---------------- lobby (0.31.82) ----------------
func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _queued(r: Room) -> Array:
	var out := []
	for cid in _members(r):
		if bool(clients[cid].get("queued", false)):
			out.append(cid)
	return out

func _seated_count(r: Room) -> int:
	var n := 0
	for cid in _members(r):
		var c: Dictionary = clients[cid]
		if not bool(c.get("queued", false)) and c.unit != "":
			n += 1
	return n

func _run_lobby(r: Room, delta: float) -> void:
	if r.wave_end < 0.0:
		return
	var waiting := _queued(r)
	if waiting.is_empty():
		r.wave_end = -1.0                      # they all left (or the restart seated them)
		return
	var now := _now()
	if not r.war.is_empty() and (r.war_done or (r.sim == null and r.match_id != 0)):
		for cid in waiting:                           # 0.31.135: the battle is over -- no next one
			_send(cid, {"t":"bye", "why":"war_over"})
			_refuse(cid, 1000, "war_over")
		r.wave_end = -1.0
		return
	if r.sim != null and r.sim.ended:
		# the results screen is up: they go into the next match with everyone (the restart seats them)
		var restart := (r.ended_at if r.ended_at >= 0.0 else now) + restart_after
		r.wave_end = maxf(r.wave_end, restart)
	elif now >= r.wave_end:
		if r.war.is_empty() and (r.sim == null or _seated_count(r) == 0):
			_new_match(r)                      # (a bots-only match left running by players who quit: a fresh one)
		elif not r.war.is_empty() and r.sim == null:
			_new_match(r)                      # 0.31.135: the battle starts (once: a running one is joined as it is)
			if world != null:
				world.started(str(r.war.bid))
		for cid in waiting:
			_seat(r, cid)
		r.wave_end = -1.0
		return
	r.lobby_clock += delta
	if r.lobby_clock >= 0.5:
		r.lobby_clock = 0.0
		_send_lobby(r, waiting)

func _send_lobby(r: Room, waiting: Array) -> void:
	var names := []
	var titles := []
	var tags := []
	for cid in waiting:
		names.append(clients[cid].name)
		titles.append(str(clients[cid].get("title", "")))
		tags.append(social.clans.tag_of_acct(str(clients[cid].get("acct", ""))) if social != null and social.clans != null else "")
	var msg := {"t":"lobby", "left":maxf(0.0, r.wave_end - _now()), "wait":war_lobby if not r.war.is_empty() and r.sim == null else lobby_time,
		"names":names, "tt":titles, "ct":tags,
		"in_match":_seated_count(r), "online":_human_count(), "slots":Net.TEAM_SIZE * 2,
		"running":r.sim != null and not r.sim.ended and _seated_count(r) > 0, "match":r.match_id}   # (running: they join it)
	if not r.war.is_empty():
		msg["war"] = {"tid":str(r.war.tid), "name":Map.name_of(str(r.war.tid)), "ah":str(r.war.ah), "dh":str(r.war.dh)}   # 0.31.135
	for i in waiting.size():
		msg["me"] = i
		_send(waiting[i], msg)

func _status() -> Dictionary:
	var in_match := 0
	var waiting := 0
	var lobby := -1.0
	var running := false
	for r in rooms.values():
		in_match += _seated_count(r)
		waiting += _queued(r).size()
		if r.wave_end >= 0.0:
			var left := maxf(0.0, r.wave_end - _now())
			lobby = left if lobby < 0.0 else minf(lobby, left)
		if r.sim != null and not r.sim.ended:
			running = true
	return {"t":"status", "v":Net.VERSION, "online":_human_count(), "in_match":in_match, "waiting":waiting,
		"lobby":lobby, "running":running, "slots":Net.TEAM_SIZE * 2, "max":max_players * max_rooms, "rooms":rooms.size(),
		"build":SERVER_BUILD, "min_build":min_build, "eco":1, "social":1, "an":1, "lb":1, "ref":1, "diag":1, "clans":1,
		"chatting":social.online.size() if social != null else 0}

# ---------------- statistics (0.31.118) ----------------
func match_key(r: Room) -> String:
	return "%d-%d" % [boot_time, r.match_id]

static func class_of(u: Dictionary) -> String:
	# the class a unit plays, its upgrade marked ("knight", "knight+")
	return str(u.get("cls", "")) + ("+" if bool(u.get("up", false)) else "")

func _team_humans(r: Room, team: int) -> int:
	var n := 0
	for cid in _seated(r):
		if int(r.sim.by_id[clients[cid].unit].team) == team:
			n += 1
	return n

# ---------------- paying a match (0.31.108) ----------------
func _ledger_events(r: Room, evs: Array) -> void:
	for cid in _members(r):
		var c: Dictionary = clients[cid]
		if c.has("ledger"):
			for e in evs:
				c.ledger.on_event(e)

func _ledger_track(r: Room, delta: float) -> void:
	if r.sim == null or r.sim.ended:
		return
	for cid in _members(r):
		var c: Dictionary = clients[cid]
		if c.has("ledger") and c.unit != "" and r.sim.by_id.has(c.unit) and str(c.ledger.uid) == c.unit:
			c.ledger.track(r.sim.by_id[c.unit], delta)

func _pay_match(r: Room) -> void:
	# the match is over: every seated account gets its result, from this server's own count
	if eco == null or r.paid_match == r.match_id:
		return
	r.paid_match = r.match_id
	var sim = r.sim
	var payees := []
	for cid in _members(r):
		payees.append(clients[cid])
	for k in r.held:
		payees.append(r.held[k].c)                     # 0.31.120: dropped a moment ago: still paid for the match
	for c in payees:
		if not c.has("acct") or not c.has("ledger") or c.unit == "" or not sim.by_id.has(c.unit) or str(c.ledger.uid) != c.unit:
			continue
		var u: Dictionary = sim.by_id[c.unit]
		var me: Dictionary = c.ledger.me(u)
		var won: bool = sim.winner == int(u.team)
		var draw: bool = sim.winner == -1
		var res: Dictionary = eco.apply_online(str(c.acct), me, won, draw)
		c.erase("ledger")
		if leaderboard != null:
			leaderboard.add_match(str(c.acct), str(c.name), str(c.get("title", "")), me, won)     # 0.31.119
		if referrals != null:
			referrals.check(str(c.acct), eco)                 # 0.31.120: level 5 with a friend's code
		if analytics != null:
			analytics.server_event(str(c.acct), "match_finish", {"match":str(c.get("match_key", match_key(r))), "mode":"online",
				"dur_s":int(_now() - float(c.get("seated_at", _now()))), "result":"win" if won else ("draw" if draw else "loss"),
				"team_n":_team_humans(r, int(u.team)), "class":class_of(u), "class0":str(c.get("class0", ""))}, str(c.get("build", "")))
		_log("paid %s (%s): %s, %d gold" % [str(c.acct), c.name, "win" if won else ("draw" if draw else "loss"), int(res.get("rewards", {}).get("gold", 0))])

# ---------------- rejoin (0.31.120) ----------------
func _rejoin(cid: int, msg: Dictionary) -> bool:
	# a hello with a rejoin token: back onto the held seat (or take over a seat whose old socket hasn't closed yet)
	var rj := str(msg.get("rj", ""))
	var found: Dictionary = {}
	var room: Room = null
	for ocid in clients.keys():                       # the old socket still looks open (the phone changed networks)
		var o: Dictionary = clients[ocid]
		if ocid != cid and o.hello and str(o.get("rj", "")) == rj and not bool(o.get("queued", false)):
			var orr := _room_of(o)
			if orr != null and orr.sim != null and not orr.sim.ended and o.unit != "" and orr.sim.by_id.has(o.unit):
				var keep := o.duplicate()
				keep.erase("ws")
				found = keep
				room = orr
				clients.erase(ocid)                   # (silently: no hold, no quit -- it's the same player)
				(o.ws as WebSocketPeer).close(1000, "rejoined")
			break
	if found.is_empty():
		for rr in rooms.values():
			if rr.held.has(rj):
				if rr.sim != null and not rr.sim.ended and float(rr.held[rj].until) >= _now():
					found = rr.held[rj].c
					room = rr
				rr.held.erase(rj)
				break
	if found.is_empty():
		return false
	if found.has("acct") and str(msg.get("acct", "")) != str(found.acct):
		return false                                  # (a token with someone else's account: not theirs)
	var c: Dictionary = clients[cid]
	for k in found:
		if not k in ["ws", "joined_at", "msgs", "msg_clock", "last_rx", "close_at", "close_code", "close_reason"]:
			c[k] = found[k]
	c.hello = true
	c.queued = false
	c.left = false
	c.move = Vector2.ZERO
	c.idle = false
	c.idle_s = -LOAD_GRACE
	c.got_in = false
	c.erase("close_at")
	c.erase("task_hash")
	var u: Dictionary = room.sim.by_id[c.unit]
	u.bot = false
	room.names_dirty = true
	_send(cid, {"t":"welcome", "v":Net.VERSION, "you":c.unit, "match":room.match_id, "seed":room.match_seed,
		"team_size":Net.TEAM_SIZE, "players":_room_humans(room), "rj":rj, "rejoin":true})
	_send(cid, Net.snapshot(room.sim, c.unit, []))
	if social != null and c.has("acct"):
		social.acct_changed(str(c.acct))
	_log("rejoin %s -> %s (room %d, match %d)" % [c.name, c.unit, room.id, room.match_id])
	return true

func _expire_holds(r: Room) -> void:
	for k in r.held.keys():
		var h: Dictionary = r.held[k]
		if float(h.until) >= _now() and r.sim != null and not r.sim.ended:
			continue
		r.held.erase(k)
		var c: Dictionary = h.c
		if r.sim != null and not r.sim.ended and c.has("acct") and analytics != null and c.has("seated_at") and r.sim.by_id.has(c.unit):
			analytics.server_event(str(c.acct), "match_quit", {"match":str(c.get("match_key", "")), "mode":"online",
				"quit_at_s":int(float(h.drop_at) - float(c.seated_at)), "class":class_of(r.sim.by_id[c.unit]), "class0":str(c.get("class0", ""))},
				str(c.get("build", "")))
		_log("seat %s of %s let go (room %d)" % [str(c.get("unit", "")), str(c.get("name", "")), r.id])

# ---------------- idle players (0.31.119) ----------------
func _active(r: Room, cid: int) -> void:
	var c: Dictionary = clients[cid]
	c.idle_s = 0.0
	if bool(c.get("idle", false)):
		c.idle = false
		if r.sim != null and c.unit != "" and r.sim.by_id.has(c.unit):
			r.sim.by_id[c.unit].bot = false                # theirs again
		_send(cid, {"t":"idle", "on":false})
		_log("back %s (room %d)" % [c.name, r.id])

func _idle_tick(r: Room, delta: float) -> void:
	# live match time without input: a bot at idle_bot s, removed at idle_kick s
	var sim = r.sim
	if sim == null or sim.ended:
		return
	for cid in _members(r):
		var c: Dictionary = clients[cid]
		if bool(c.get("queued", false)) or c.unit == "" or not sim.by_id.has(c.unit) or c.has("close_at"):
			continue
		var u: Dictionary = sim.by_id[c.unit]
		if u.state == "dead":
			continue                                     # (waiting to respawn isn't idling)
		c.idle_s = float(c.get("idle_s", 0.0)) + delta
		if c.idle_s >= idle_kick:
			_send(cid, {"t":"bye", "why":"idle", "msg":"You were removed for being idle."})
			_refuse(cid, CLOSE_IDLE, "idle")
			c.erase("ledger")                            # (nothing paid for this match)
			_log("removed %s for being idle (room %d)" % [c.name, r.id])
		elif c.idle_s >= idle_bot and not bool(c.get("idle", false)):
			c.idle = true
			u.bot = true
			u.move = Vector2.ZERO
			u.net_driven = false
			_send(cid, {"t":"idle", "on":true, "kick_in":idle_kick - c.idle_s})
			_log("idle %s: a bot plays for them (room %d)" % [c.name, r.id])

# ---------------- match loop ----------------
func _new_match(r: Room) -> void:
	match_counter += 1
	r.match_id = match_counter
	r.match_seed = randi() & 0x7fffffff
	r.sim = Sim.new()
	r.sim.setup(Net.TEAM_SIZE, r.match_seed, -1)      # no local human; every unit starts as a bot
	r.accum = 0.0
	r.snap_accum = 0.0
	r.ended_at = -1.0
	r.pending_events.clear()
	r.held.clear()                                    # (a seat in the last match is no seat in this one)
	_log("match %d start (room %d, seed %d)" % [r.match_id, r.id, r.match_seed])

# ---------------- the war map's battles (0.31.135) ----------------
func _war_room(b: Dictionary) -> int:
	# world.gd: a room for a battle (0: every room is busy). Battles never take the last room: matchmaking keeps one.
	var war_n := 0
	for r in rooms.values():
		war_n += int(not (r as Room).war.is_empty())
	if rooms.size() >= max_rooms or war_n >= maxi(1, max_rooms - 1):
		return 0
	var nr := Room.new()
	nr.id = next_room
	next_room += 1
	nr.war = {"bid":str(b.bid), "tid":str(b.tid), "ah":str(b.ah), "dh":str(b.dh), "att_team":1, "def_team":0}
	nr.war_made = _now()
	rooms[nr.id] = nr
	_log("room %d opened for battle %s (%s attacks %s, held by %s)" % [nr.id, str(b.bid), str(b.ah), str(b.tid), str(b.dh) if str(b.dh) != "" else "nobody"])
	return nr.id

func _war_room_of(bid: String) -> Room:
	for r in rooms.values():
		if str((r as Room).war.get("bid", "")) == bid:
			return r
	return null

func _war_has_acct(r: Room, acct: String) -> bool:
	for cid in _members(r):
		if str(clients[cid].get("acct", "")) == acct:
			return true
	for k in r.held:
		if str(r.held[k].c.get("acct", "")) == acct:
			return true
	return false

func _war_side_n(r: Room, team: int) -> int:
	var n := 0
	for cid in _members(r):
		if int(clients[cid].get("war_team", -1)) == team:
			n += 1
	return n

func _war_events(r: Room, evs: Array) -> void:
	# a gate of the defenders broken (not their jail door): the attackers' gate crown
	if r.war.is_empty() or r.war_gate:
		return
	for e in evs:
		if str(e.get("k", "")) == "gate_broken" and int(e.get("team", -1)) == int(r.war.def_team):
			for g in r.sim.gates:
				if str(g.id) == str(e.get("gate", "")) and str(g.get("kind", "")) != "jail":
					r.war_gate = true

func _war_over(r: Room) -> void:
	# the battle ended: its points to the clan's bar (world.gd), and each player hears what it did
	if r.war.is_empty() or r.war_done or world == null or r.sim == null:
		return
	r.war_done = true
	var sim = r.sim
	var att := int(r.war.att_team)
	var present := []
	var payees := []
	for cid in _members(r):
		payees.append(clients[cid])
	for k in r.held:
		payees.append(r.held[k].c)
	for c in payees:
		if c.has("acct") and str(c.get("unit", "")) != "" and sim.by_id.has(c.unit) and int(sim.by_id[c.unit].team) == att:
			present.append(Social.pid_of(str(c.acct)))
	var tid := str(r.war.tid)
	var res: Dictionary = world.battle_over(str(r.war.bid), {"won":sim.winner == att, "gate":r.war_gate, "king":int(sim.score[att]) > 0, "present":present})
	var held: bool = not res.values().any(func(x): return bool(x.get("took", false)))
	for cid in _members(r):
		var c: Dictionary = clients[cid]
		if not c.has("acct"):
			continue
		var pid := Social.pid_of(str(c.acct))
		if res.has(pid):
			var m: Dictionary = (res[pid] as Dictionary).duplicate()
			m["t"] = "war"
			_send(cid, m)
		elif int(c.get("war_team", -1)) == int(r.war.def_team):
			_send(cid, {"t":"war", "tid":tid, "name":Map.name_of(tid), "def":true, "held":held})
		elif int(c.get("war_team", -1)) == att:
			_send(cid, {"t":"war", "tid":tid, "name":Map.name_of(tid), "helped":true, "won":sim.winner == att})

func _results_tick(r: Room) -> void:
	# 0.31.122: a player left on the results (PLAY AGAIN never pressed) for results_keep seconds goes back to the menu
	var now := _now()
	var keep := results_keep if r.war.is_empty() else minf(results_keep, WAR_RESULTS_KEEP)
	for cid in _members(r):
		var c: Dictionary = clients[cid]
		if c.has("results_at") and not c.has("close_at") and now - float(c.results_at) > keep:
			c.erase("results_at")
			_send(cid, {"t":"bye", "why":"done"})
			_refuse(cid, 1000, "done")
			_log("%s left on the results for %.0f s: let go (room %d)" % [c.name, keep, r.id])

func _run_match(r: Room, delta: float) -> bool:
	# -> true when the room's match ran this frame
	_results_tick(r)
	var humans: int = _members(r).filter(func(cid): return not bool(clients[cid].get("after", false))).size() + r.held.size()
	# (a held seat keeps the match going for its player; one still on the last match's results doesn't -- 0.31.122)
	if humans == 0:
		if r.sim != null:
			if r.empty_since < 0.0:
				r.empty_since = Time.get_ticks_msec() / 1000.0
			elif Time.get_ticks_msec() / 1000.0 - r.empty_since > idle_stop:
				_log("match %d stopped (room %d, no players)" % [r.match_id, r.id])
				r.sim = null
		return false
	r.empty_since = -1.0
	if r.sim == null:
		return false
	var sim = r.sim
	if sim.ended:
		if r.ended_at < 0.0:
			r.ended_at = Time.get_ticks_msec() / 1000.0
			_log("match %d end (room %d) winner=%d reason=%s score=%s" % [r.match_id, r.id, sim.winner, sim.end_reason, str(sim.score)])
			_pay_match(r)
			_war_over(r)
			for cid in _members(r):                       # 0.31.122: their results are up until they say otherwise
				# (0.31.135: in a battle's room everyone's are -- there's no next match, and the room must close)
				if (bool(clients[cid].get("ask_next", false)) or not r.war.is_empty()) and not bool(clients[cid].get("queued", false)):
					clients[cid].results_at = r.ended_at
		elif r.war.is_empty() and Time.get_ticks_msec() / 1000.0 - r.ended_at > restart_after:
			# The next match. 0.31.122: an app that asks for it (ask_next) goes in only once its player pressed PLAY AGAIN;
			# the others stay on their results. Older apps and players waiting in the lobby go in as before. Nobody wants
			# it yet: no new match until somebody does.
			var mem := _members(r)
			var go := mem.filter(func(cid): return not bool(clients[cid].get("ask_next", false)) or bool(clients[cid].get("again", false)) \
				or bool(clients[cid].get("queued", false)))
			if not go.is_empty():
				_new_match(r)
				for cid in mem:
					clients[cid].unit = ""
					if not go.has(cid):
						clients[cid].after = true             # (on the results: no snapshots of the new match)
				for cid in go:
					clients[cid].erase("again")
					clients[cid].after = false
					_seat(r, cid)
				return true
	_idle_tick(r, delta)
	# Apply held inputs, then step at a fixed 30 Hz.
	for cid in _members(r):
		var c: Dictionary = clients[cid]
		if c.unit != "" and sim.by_id.has(c.unit) and not bool(c.get("idle", false)) and not c.has("close_at"):
			sim.set_move(c.unit, c.move)
			var ub: Dictionary = sim.by_id[c.unit]
			# Client-side prediction: take the phone's position when it's plausible (speed x time
			# since the last accepted report, not in a wall); otherwise keep ours and the phone snaps.
			# ...but only while positions keep arriving: after 0.3 s without one (packet loss, a stalled
			# phone) the server moves the unit from its inputs again instead of freezing it.
			var now_rx := Time.get_ticks_msec() / 1000.0
			ub.net_driven = bool(c.get("pred", false)) and now_rx - float(c.get("cpos_rx", -10.0)) < 0.3
			if ub.net_driven and bool(c.get("cpos_new", false)):
				c.cpos_new = false
				var now_s := Time.get_ticks_msec() / 1000.0
				if sim.accept_client_pos(ub, c.cpos, float(c.cface), now_s - float(c.get("cpos_t", now_s - 0.05))):
					c.cpos_t = now_s
					c.pos_ok = int(c.get("pos_ok", 0)) + 1
				else:
					c.pos_rejected = int(c.get("pos_rejected", 0)) + 1
			if bool(c.get("bhold", false)) and sim.ability_of(ub) == "block":
				sim.act(c.unit, "ability")
			if bool(c.get("khold", false)):
				sim.act(c.unit, "block")
			if c.hold:
				var u: Dictionary = sim.by_id[c.unit]
				if sim.can_act(u) and not u.carrying:
					sim.act(c.unit, "attack")
	r.accum = minf(r.accum + delta, TICK * 6)
	var t_step := Time.get_ticks_usec()
	while r.accum >= TICK and not sim.ended:
		r.accum -= TICK
		sim.step(TICK)
		var evs: Array = sim.drain_events()
		_ledger_events(r, evs)
		_war_events(r, evs)
		r.pending_events.append_array(evs)
		_ledger_track(r, TICK)
		if test_match_s > 0.0 and sim.time >= test_match_s and not sim.ended:
			if not test_score.is_empty():
				sim.score = test_score.duplicate()
			sim._finish("time")
	_st_step += Time.get_ticks_usec() - t_step
	if sim.ended:
		var evs2: Array = sim.drain_events()
		_ledger_events(r, evs2)
		_war_events(r, evs2)
		r.pending_events.append_array(evs2)
		_pay_match(r)
		_war_over(r)
	r.snap_accum += delta
	if r.snap_accum >= 1.0 / Net.SNAP_HZ:
		r.snap_accum = minf(r.snap_accum - 1.0 / Net.SNAP_HZ, 1.0 / Net.SNAP_HZ)
		var events := r.pending_events
		r.pending_events = []
		var t_snap := Time.get_ticks_usec()
		var base := Net.snapshot(sim, "", events)      # built once, shared by every player
		_st_snap += Time.get_ticks_usec() - t_snap
		var t_send := Time.get_ticks_usec()
		# 0.31.23: encoded and compressed ONCE and sent to everyone; each player's private bit (their task) goes in its
		# own small "m" message, only when it changes. Before, every player's copy was encoded and compressed separately.
		var bytes := Net.encode(base, true)
		for cid in _members(r):
			var c: Dictionary = clients[cid]
			if bool(c.get("queued", false)) or bool(c.get("after", false)):
				continue                               # (still in the lobby: no match to show yet; 0.31.122: or still on the last one's results)
			_send_raw(cid, bytes)
			_st_bytes += bytes.size()
			var me: Dictionary = sim.by_id.get(c.unit, {})
			if not me.is_empty():
				var th := hash(me.task)
				if int(c.get("task_hash", -1)) != th:
					c.task_hash = th
					_send(cid, {"t":"m", "task":me.task.duplicate(true)})
				# 0.31.87: the health they've healed, for the Merciful title (at most once a second, when it changed)
				var healed := int(me.get("healed", 0.0))
				if healed != int(c.get("heal_sent", 0)) and _now() - float(c.get("heal_at", -10.0)) >= 1.0:
					c.heal_sent = healed
					c.heal_at = _now()
					_send(cid, {"t":"st", "heal":healed})
		_st_send += Time.get_ticks_usec() - t_send
		_st_snaps += 1
	return true
