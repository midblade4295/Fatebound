extends SceneTree
# Fatebound Siege dedicated server (headless Godot). Runs the same SiegeSim as offline play,
# authoritative, 16v16 with bots in every slot no human holds.
#
#   godot --headless --path <project> -s res://server/siege_server.gd
# Env: SIEGE_HOST (default 127.0.0.1 — keep it on loopback behind Caddy), SIEGE_PORT (8082),
#      SIEGE_MAX_PLAYERS (32), SIEGE_LOG (1 = log joins/leaves/match results to stdout),
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
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Net = preload("res://scripts/siege/siege_net.gd")
const IapVerify = preload("res://server/iap_verify.gd")

const RESTART_AFTER := 15.0          # seconds of results screen before the next match
const IDLE_STOP := 30.0              # no players for this long -> stop simulating
const LOBBY_TIME := 20.0             # the join countdown (0.31.82)
const HELLO_TIMEOUT := 10.0
const IAP_TIMEOUT := 40.0              # a purchase check may take a token request and an API call
const REFUSE_CLOSE_DELAY := 0.25     # s between a "bye"/"ver" reply and closing the socket
const SERVER_BUILD := "0.31.95"      # this server's game version; the probe says it by default (identifies as current)
const MIN_BUILD_FILE := "/etc/fatebound-siege/min_build"
const MIN_BUILD_RELOAD := 10.0       # s between re-reads of the min-build file
const UPDATE_MSG := "A new version of Fatebound is out. Update now on Google Play to keep playing online."
const MAX_MSGS_PER_SEC := 90         # per client; beyond this, messages are dropped
const TICK := Sim.TICK

var tcp := TCPServer.new()
var clients := {}                    # cid -> {ws, unit, name, hello, move, hold, joined_at, msgs, msg_clock}
var next_cid := 1
var sim = null
var match_id := 0
var match_seed := 0
var _accum := 0.0
var _snap_accum := 0.0
var _ended_at := -1.0
var _empty_since := -1.0
var _pending_events: Array = []
var host := "127.0.0.1"
var port := Net.DEFAULT_PORT
var max_players := 32
var log_on := true
var lobby_time := LOBBY_TIME
var wave_end := -1.0                 # when the waiting players are seated (-1: nobody waiting)
var _lobby_clock := 0.0
var _names_dirty := false            # a seat changed: send the players' names (0.31.86)
var iap = null                       # 0.31.90: Google Play purchase checks (server/iap_verify.gd)
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
	log_on = OS.get_environment("SIEGE_LOG") != "0"
	if OS.has_environment("SIEGE_LOBBY"):
		lobby_time = clampf(float(OS.get_environment("SIEGE_LOBBY")), 0.0, 120.0)
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
	_log("SIEGE_SERVER listening on %s:%d (protocol %d, build %s, max %d players, min build %s)" % [host, port, Net.VERSION,
		SERVER_BUILD, max_players, min_build if min_build != "" else "off"])
	iap = IapVerify.new()
	iap.log_fn = _log
	root.add_child.call_deferred(iap)
	_log("purchase checks: %s" % iap.describe())

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
	_run_lobby(delta)
	_run_match(delta)
	if _names_dirty:
		_names_dirty = false
		_send_names()
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
		clients[next_cid] = {"ws":ws, "unit":"", "name":"", "hello":false, "move":Vector2.ZERO, "hold":false,
			"joined_at":Time.get_ticks_msec() / 1000.0, "msgs":0, "msg_clock":0.0}
		next_cid += 1

func _poll_clients() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for cid in clients.keys():
		var c: Dictionary = clients[cid]
		var ws: WebSocketPeer = c.ws
		ws.poll()
		var st := ws.get_ready_state()
		if st == WebSocketPeer.STATE_CLOSED:
			_drop(cid, "closed")
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
		if not c.hello and now - float(c.joined_at) > (IAP_TIMEOUT if c.has("iap_busy") else HELLO_TIMEOUT):
			ws.close(4000, "no hello")
			_drop(cid, "no hello")
			continue
		if now - float(c.msg_clock) >= 1.0:
			c.msg_clock = now
			c.msgs = 0
		while ws.get_available_packet_count() > 0:
			var pkt := ws.get_packet()
			c.msgs += 1
			if c.msgs > MAX_MSGS_PER_SEC or pkt.size() > Net.MAX_PACKET:
				continue
			_handle(cid, Net.decode(pkt))

func _send(cid: int, msg: Dictionary) -> void:
	_send_raw(cid, Net.encode(msg, msg.get("t", "") == "s"))

func _send_raw(cid: int, bytes: PackedByteArray) -> void:
	var c: Dictionary = clients.get(cid, {})
	if c.is_empty():
		return
	var ws: WebSocketPeer = c.ws
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.put_packet(bytes)

# Load stats (0.31.23): every STATS_EVERY s, how long the sim steps, the snapshot build and the sends took per second,
# and the bytes sent -- logged with SIEGE_STATS=1 (the net load test reads them).
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
		var line := "SIEGE_STATS players=%d bots=%d step=%.1fms/s snapshot=%.1fms/s send=%.1fms/s kB/s=%.1f snaps/s=%.1f frames/s=%.1f worst_frame=%.0fms" % [
			n, sim.units.size() - n if sim != null else 0, _st_step / 1000.0 / _st_clock, _st_snap / 1000.0 / _st_clock, _st_send / 1000.0 / _st_clock,
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
	if sim != null and c.unit != "" and sim.by_id.has(c.unit):
		var u: Dictionary = sim.by_id[c.unit]
		u.bot = true                   # a bot takes the slot back over
		u.move = Vector2.ZERO
		u.net_driven = false
		_names_dirty = true            # (their name goes off the battlefield)
	if c.hello:
		_log("leave %s (%s) unit=%s players=%d" % [c.name, why, c.unit, _human_count() - 1])
	clients.erase(cid)

func _human_count() -> int:
	var n := 0
	for cid in clients:
		if clients[cid].hello:
			n += 1
	return n

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
			_send(cid, {"t":"ver", "v":Net.VERSION, "build":SERVER_BUILD, "min_build":min_build})
			_refuse(cid, 1000, "ver")
		"hello":
			if c.hello:
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
				_log("refused %s: build %s older than min build %s" % [str(msg.get("name", "?")).left(20), build.left(30), min_build])
				return
			if _human_count() >= max_players:
				_send(cid, {"t":"bye", "why":"full"})
				_refuse(cid, 4002, "full")
				return
			c.hello = true
			c.name = clean_name(str(msg.get("name", "Player")))
			var tid := str(msg.get("title", ""))
			c.title = tid if Net.TITLES.has(tid) else ""
			c.pred = bool(msg.get("pred", false))         # the phone moves its own unit (0.18.4)
			c.queued = true                                # 0.31.82: into the lobby; seated when the countdown ends
			if wave_end < 0.0:
				wave_end = _now() + lobby_time
			_log("queue %s (seated in %.0f s, players %d)" % [c.name, wave_end - _now(), _human_count()])
			_lobby_clock = 1.0                             # tell everyone waiting at once
		"status":
			# 0.31.82: the menu's "players online" -- answered without a hello; the asker closes (or we do in 2 s: a
			# close right behind the answer can reach the phone in the same read, and the WebSocket drops the answer)
			if not c.hello:
				_send(cid, _status())
				_refuse(cid, 1000, "status")
				c.close_at = _now() + 2.0         # (the refusal path closes it; 2 s rather than REFUSE_CLOSE_DELAY)
		"iap":
			# 0.31.90: a phone asks whether a Google Play purchase is real before it grants it. No hello (a purchase is
			# not a player); one question per socket; the answer goes back and the socket closes.
			if c.hello or c.has("iap_busy") or iap == null:
				return
			c.iap_busy = true
			var product := str(msg.get("product", ""))
			var token := str(msg.get("token", ""))
			iap.verify(product, token, func(res: Dictionary):
				if not clients.has(cid):
					return
				var out := res.duplicate()
				out["t"] = "iap"
				out["product"] = product
				out["token"] = token
				_send(cid, out)
				_refuse(cid, 1000, "iap")
				clients[cid].close_at = _now() + 2.0
				_log("purchase %s: %s%s" % [product, "ok" if bool(res.get("ok", false)) else str(res.get("why", "")),
					" (test)" if bool(res.get("test", false)) else ""]))
		"in":
			if not c.hello or sim == null or c.unit == "":
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
			if a != "" and a in Net.ACTIONS:
				var arg: Variant = msg.get("arg", null)
				if a == "buy":
					arg = str(arg) if str(arg) in Sim.UPGRADES else ""
				else:
					arg = null
				sim.act(c.unit, a, arg)

func _refuse(cid: int, code: int, reason: String) -> void:
	# Close a little after the last message so it reaches the client before the close frame.
	var c: Dictionary = clients[cid]
	c.close_at = Time.get_ticks_msec() / 1000.0 + REFUSE_CLOSE_DELAY
	c.close_code = code
	c.close_reason = reason

func _seat(cid: int) -> void:
	# Take over a bot on the team with fewer humans (blue on ties).
	var c: Dictionary = clients[cid]
	var humans := [0, 0]
	for other in clients:
		var oc: Dictionary = clients[other]
		if other != cid and oc.hello and oc.unit != "" and sim.by_id.has(oc.unit):
			humans[sim.by_id[oc.unit].team] += 1
	var team := 0 if humans[0] <= humans[1] else 1
	var seat := ""
	for u in sim.units:
		if u.team == team and u.bot and not _unit_taken(u.id):
			seat = u.id
			break
	if seat == "":
		for u in sim.units:
			if u.bot and not _unit_taken(u.id):
				seat = u.id
				break
	c.unit = seat
	c.queued = false
	c.move = Vector2.ZERO
	if seat != "":
		sim.by_id[seat].bot = false
	_send(cid, {"t":"welcome", "v":Net.VERSION, "you":seat, "match":match_id, "seed":match_seed,
		"team_size":Net.TEAM_SIZE, "players":_human_count()})
	_names_dirty = true
	# The first snapshot right away so the client can build its view.
	_send(cid, Net.snapshot(sim, seat, []))
	_log("join %s -> %s (match %d, players %d)" % [c.name, seat, match_id, _human_count()])

func _unit_taken(id: String) -> bool:
	for cid in clients:
		if clients[cid].unit == id:
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

func player_names() -> Dictionary:
	var out := {}
	for cid in clients:
		var c: Dictionary = clients[cid]
		if c.hello and not bool(c.get("queued", false)) and c.unit != "" and sim != null and sim.by_id.has(c.unit):
			out[c.unit] = c.name
	return out

func player_titles() -> Dictionary:
	var out := {}
	for cid in clients:
		var c: Dictionary = clients[cid]
		if c.hello and not bool(c.get("queued", false)) and c.unit != "" and str(c.get("title", "")) != "" \
				and sim != null and sim.by_id.has(c.unit):
			out[c.unit] = str(c.title)
	return out

func _send_names() -> void:
	var msg := {"t":"pn", "n":player_names(), "tt":player_titles()}
	for cid in clients:
		var c: Dictionary = clients[cid]
		if c.hello and not bool(c.get("queued", false)) and c.unit != "":
			_send(cid, msg)

# ---------------- lobby (0.31.82) ----------------
func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _queued() -> Array:
	var out := []
	for cid in clients:
		if clients[cid].hello and bool(clients[cid].get("queued", false)):
			out.append(cid)
	return out

func _seated_count() -> int:
	var n := 0
	for cid in clients:
		var c: Dictionary = clients[cid]
		if c.hello and not bool(c.get("queued", false)) and c.unit != "":
			n += 1
	return n

func _run_lobby(delta: float) -> void:
	if wave_end < 0.0:
		return
	var waiting := _queued()
	if waiting.is_empty():
		wave_end = -1.0                        # they all left (or the restart seated them)
		return
	var now := _now()
	if sim != null and sim.ended:
		# the results screen is up: they go into the next match with everyone (the restart seats them)
		var restart := (_ended_at if _ended_at >= 0.0 else now) + RESTART_AFTER
		wave_end = maxf(wave_end, restart)
	elif now >= wave_end:
		if sim == null or _seated_count() == 0:
			_new_match()                       # (a bots-only match left running by players who quit: a fresh one)
		for cid in waiting:
			_seat(cid)
		wave_end = -1.0
		return
	_lobby_clock += delta
	if _lobby_clock >= 0.5:
		_lobby_clock = 0.0
		_send_lobby(waiting)

func _send_lobby(waiting: Array) -> void:
	var names := []
	var titles := []
	for cid in waiting:
		names.append(clients[cid].name)
		titles.append(str(clients[cid].get("title", "")))
	var msg := {"t":"lobby", "left":maxf(0.0, wave_end - _now()), "wait":lobby_time, "names":names, "tt":titles,
		"in_match":_seated_count(), "online":_human_count(), "slots":Net.TEAM_SIZE * 2,
		"running":sim != null and not sim.ended and _seated_count() > 0, "match":match_id}   # (running: they join it)
	for i in waiting.size():
		msg["me"] = i
		_send(waiting[i], msg)

func _status() -> Dictionary:
	return {"t":"status", "v":Net.VERSION, "online":_human_count(), "in_match":_seated_count(), "waiting":_queued().size(),
		"lobby":maxf(0.0, wave_end - _now()) if wave_end >= 0.0 else -1.0, "running":sim != null and not sim.ended,
		"slots":Net.TEAM_SIZE * 2, "max":max_players, "build":SERVER_BUILD, "min_build":min_build}

# ---------------- match loop ----------------
func _new_match() -> void:
	match_id += 1
	match_seed = randi() & 0x7fffffff
	sim = Sim.new()
	sim.setup(Net.TEAM_SIZE, match_seed, -1)      # no local human; every unit starts as a bot
	_accum = 0.0
	_snap_accum = 0.0
	_ended_at = -1.0
	_pending_events.clear()
	_log("match %d start (seed %d)" % [match_id, match_seed])

func _run_match(delta: float) -> void:
	var humans := _human_count()
	if humans == 0:
		if sim != null:
			if _empty_since < 0.0:
				_empty_since = Time.get_ticks_msec() / 1000.0
			elif Time.get_ticks_msec() / 1000.0 - _empty_since > IDLE_STOP:
				_log("match %d stopped (no players)" % match_id)
				sim = null
		return
	_empty_since = -1.0
	if sim == null:
		return
	if sim.ended:
		if _ended_at < 0.0:
			_ended_at = Time.get_ticks_msec() / 1000.0
			_log("match %d end winner=%d reason=%s score=%s" % [match_id, sim.winner, sim.end_reason, str(sim.score)])
		elif Time.get_ticks_msec() / 1000.0 - _ended_at > RESTART_AFTER:
			_new_match()
			for cid in clients:
				if clients[cid].hello:
					clients[cid].unit = ""
			for cid in clients:
				if clients[cid].hello:
					_seat(cid)
			return
	# Apply held inputs, then step at a fixed 30 Hz.
	for cid in clients:
		var c: Dictionary = clients[cid]
		if c.hello and c.unit != "" and sim.by_id.has(c.unit):
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
	_accum = minf(_accum + delta, TICK * 6)
	var t_step := Time.get_ticks_usec()
	while _accum >= TICK and not sim.ended:
		_accum -= TICK
		sim.step(TICK)
		_pending_events.append_array(sim.drain_events())
	_st_step += Time.get_ticks_usec() - t_step
	if sim.ended:
		_pending_events.append_array(sim.drain_events())
	_snap_accum += delta
	if _snap_accum >= 1.0 / Net.SNAP_HZ:
		_snap_accum = minf(_snap_accum - 1.0 / Net.SNAP_HZ, 1.0 / Net.SNAP_HZ)
		var events := _pending_events
		_pending_events = []
		var t_snap := Time.get_ticks_usec()
		var base := Net.snapshot(sim, "", events)      # built once, shared by every player
		_st_snap += Time.get_ticks_usec() - t_snap
		var t_send := Time.get_ticks_usec()
		# 0.31.23: encoded and compressed ONCE and sent to everyone; each player's private bit (their task) goes in its
		# own small "m" message, only when it changes. Before, every player's copy was encoded and compressed separately.
		var bytes := Net.encode(base, true)
		for cid in clients:
			var c: Dictionary = clients[cid]
			if not c.hello or bool(c.get("queued", false)):
				continue                               # (still in the lobby: no match to show yet)
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
	_stats_tick(delta)
