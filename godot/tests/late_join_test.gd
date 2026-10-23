extends SceneTree
# 0.31.209 (Kevin: "Hybrid with 5min window"): the REAL server (port 8143; one room of 4 at most, 14-second matches, the
# next one 1 s after, a join window of 5 s), real time. A running match takes a player only when no room can take them
# in its countdown, and only in its first SIEGE_JOIN_WINDOW s of match time.
#   - P1 (an older app: the next match by itself) and P2 (asks for it) in match 1; it ends; match 2 starts with P1
#   - P2's PLAY AGAIN while match 2 runs, and no second room allowed: seated in match 2 at once (no lobby)
#   - P3's hello while match 2 is young: seated in it at once too
#   - P4's hello once match 2 is past the window (a seat still free): "full" (bye full, 4002)
#   godot --headless --path godot -s res://tests/late_join_test.gd
const Net = preload("res://scripts/siege/siege_net.gd")

var fails: Array = []
var port := 8143
var pid := -1
var phase := "boot"
var t_phase := 0.0
var socks := {}
var inbox := {}
var sent := {}
var notes := {}

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _init() -> void:
	var sd := OS.get_user_data_dir().path_join("late-srv-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(sd)
	for kv in [["SIEGE_PORT", str(port)], ["SIEGE_HOST", "127.0.0.1"], ["SIEGE_LOBBY", "1"], ["SIEGE_MAX_PLAYERS", "4"],
			["SIEGE_MAX_ROOMS", "1"], ["SIEGE_TEST_MATCH_S", "14"], ["SIEGE_RESTART", "1"], ["SIEGE_JOIN_WINDOW", "5"],
			["SIEGE_IDLE_BOT", "600"], ["SIEGE_IDLE_KICK", "900"], ["STATE_DIRECTORY", sd], ["SIEGE_MIN_BUILD", "off"]]:
		OS.set_environment(kv[0], kv[1])
	OS.unset_environment("SIEGE_LOAD_LIMIT")
	pid = OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://server/siege_server.gd"])
	check(pid > 0, "server process started")

func _go(p: String) -> void:
	phase = p
	t_phase = 0.0

func open(name: String) -> void:
	var ws := WebSocketPeer.new()
	ws.inbound_buffer_size = 1 << 21
	ws.connect_to_url("ws://127.0.0.1:%d" % port)
	socks[name] = ws
	inbox[name] = []
	sent.erase(name)

func send_once(name: String, msg: Dictionary) -> bool:
	if sent.has(name):
		return true
	var ws: WebSocketPeer = socks[name]
	if ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	ws.put_packet(Net.encode(msg))
	sent[name] = true
	return true

func got(name: String, tt: String) -> Array:
	return (inbox.get(name, []) as Array).filter(func(m): return str(m.get("t", "")) == tt)

func welcome(name: String) -> Dictionary:
	var w := got(name, "welcome")
	return w[w.size() - 1] if not w.is_empty() else {}

func hello(name: String, ask: bool) -> Dictionary:
	var h := {"t":"hello", "v":Net.VERSION, "five":Net.FIVE, "name":name, "build":"0.31.209-fatebound", "pred":false}
	if ask:
		h["ask_next"] = true
	return h

var _in_clock := 0.0

func _process(delta: float) -> bool:
	t_phase += delta
	_in_clock += delta
	var keep := _in_clock >= 0.5
	if keep:
		_in_clock = 0.0
	for n in socks:
		var ws: WebSocketPeer = socks[n]
		ws.poll()
		while ws.get_available_packet_count() > 0:
			var m := Net.decode(ws.get_packet())
			if str(m.get("t", "")) == "s":
				m = {"t":"s"}                                 # (kept small)
			(inbox[n] as Array).append(m)
		if keep and not welcome(n).is_empty() and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			ws.put_packet(Net.encode({"t":"in", "m":Vector2.ZERO, "h":false, "b":false}))
	match phase:
		"boot":
			if t_phase > 2.5:
				open("P1")
				open("P2")
				_go("m1")
		"m1":
			send_once("P1", hello("Pone", false))
			send_once("P2", hello("Ptwo", true))
			if not welcome("P1").is_empty() and not welcome("P2").is_empty():
				notes.m1 = int(welcome("P1").match)
				check(int(welcome("P2").match) == int(notes.m1), "P1 and P2 in match %d" % int(notes.m1))
				_go("m2")
			elif t_phase > 10.0:
				check(false, "P1 and P2 seated within 10 s")
				_finish()
		"m2":
			# match 1 ends at 14 s; the next starts 1 s later with P1 (no ask_next)
			if int(welcome("P1").match) != int(notes.m1):
				notes.m2 = int(welcome("P1").match)
				notes.p2_lobbies = got("P2", "lobby").size()
				(socks.P2 as WebSocketPeer).put_packet(Net.encode({"t":"again"}))
				open("P3")
				_go("late")
			elif t_phase > 25.0:
				check(false, "match 2 started within 25 s")
				_finish()
		"late":
			send_once("P3", hello("Pthree", true))
			if int(welcome("P2").get("match", -1)) == int(notes.m2) and int(welcome("P3").get("match", -1)) == int(notes.m2):
				check(got("P2", "lobby").size() == int(notes.p2_lobbies),
					"P2's PLAY AGAIN with match 2 running and no second room allowed: seated in it at once (%.1f s, no lobby)" % t_phase)
				check(got("P3", "lobby").is_empty(), "P3's hello while match 2 is young: seated in it at once too")
				_go("window")
			elif t_phase > 4.0:
				check(false, "P2 and P3 late-joined match %d within 4 s (P2 %d, P3 %d)" % [int(notes.m2), int(welcome("P2").get("match", -1)),
					int(welcome("P3").get("match", -1))])
				_finish()
		"window":
			if t_phase > 6.5 and not socks.has("P4"):
				open("P4")                                    # (match 2 is past its 5 s window now, not yet at its 14 s end)
			if socks.has("P4"):
				send_once("P4", hello("Pfour", true))
				var ws: WebSocketPeer = socks.P4
				if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
					var bye := got("P4", "bye")
					check(not bye.is_empty() and str(bye[0].why) == "full" and ws.get_close_code() == 4002 and welcome("P4").is_empty(),
						"P4's hello once match 2 is past the join window, a seat still free: \"full\" (%d)" % ws.get_close_code())
					_finish()
				elif not welcome("P4").is_empty() or not got("P4", "lobby").is_empty() or t_phase > 12.0:
					check(false, "P4 refused (welcome %s, lobby %d)" % [str(welcome("P4")), got("P4", "lobby").size()])
					_finish()
	return false

func _finish() -> void:
	if pid > 0:
		OS.kill(pid)
		OS.execute("kill", ["-9", str(pid)])
		pid = -1
	print("LATE_JOIN_PASS" if fails.is_empty() else "LATE_JOIN_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
