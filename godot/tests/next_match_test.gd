extends SceneTree
# 0.31.122 (Kevin: "make it so the game doesn't automatically put player back in a new game because they could be looking
# at score card or something"): the REAL server (port 8110; 12-second matches, the next one 2 s after, results kept 10 s)
# and the real game client (SiegeMode online), real time.
#   - when the match ends the game stays on its results: the server starts the next match for an older app (O, no
#     "ask_next") but not for the game, nor for P2/P3 (they ask for it); they get no snapshots of it either
#   - PLAY AGAIN after the next match started: the game is seated in it at once; so is P3 ("again")
#   - P2 never presses it: let go after the results time ("bye done"), back to Home
#   - nobody wants another match (O left): none starts; P3's PLAY AGAIN starts it, and the game, still on its results,
#     joins when it presses PLAY AGAIN
#   godot --headless --path godot -s res://tests/next_match_test.gd
const Mode = preload("res://scripts/siege/siege_mode.gd")
const Net = preload("res://scripts/siege/siege_net.gd")

var fails: Array = []
var port := 8110
var url := ""
var pid := -1
var mode
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
	url = "ws://127.0.0.1:%d/" % port
	OS.set_environment("SIEGE_PORT", str(port))
	OS.set_environment("SIEGE_HOST", "127.0.0.1")
	OS.set_environment("SIEGE_LOBBY", "0.5")
	OS.set_environment("SIEGE_TEST_MATCH_S", "12")
	OS.set_environment("SIEGE_RESTART", "2")
	OS.set_environment("SIEGE_RESULTS_KEEP", "10")
	OS.set_environment("SIEGE_MIN_BUILD", "off")
	var sd := OS.get_user_data_dir().path_join("next-srv-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(sd)
	OS.set_environment("STATE_DIRECTORY", sd)
	pid = OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://server/siege_server.gd"])
	check(pid > 0, "server process started")

func _go(p: String) -> void:
	phase = p
	t_phase = 0.0

func open(name: String) -> void:
	var ws := WebSocketPeer.new()
	ws.inbound_buffer_size = 1 << 21
	ws.connect_to_url(url)
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

func say(name: String, msg: Dictionary) -> void:
	(socks[name] as WebSocketPeer).put_packet(Net.encode(msg))

func got(name: String, tt: String) -> Array:
	return (inbox.get(name, []) as Array).filter(func(m): return str(m.get("t", "")) == tt)

func welcome(name: String) -> Dictionary:
	var w := got(name, "welcome")
	return w[w.size() - 1] if not w.is_empty() else {}

func hello(name: String, ask: bool) -> Dictionary:
	var h := {"t":"hello", "v":Net.VERSION, "name":name, "build":"0.31.122-fatebound"}
	if ask:
		h["ask_next"] = true
	return h

func _results_up() -> bool:
	return mode.hud.result_panel != null and is_instance_valid(mode.hud.result_panel)

func _process(delta: float) -> bool:
	t_phase += delta
	for n in socks:
		var ws: WebSocketPeer = socks[n]
		ws.poll()
		while ws.get_available_packet_count() > 0:
			(inbox[n] as Array).append(Net.decode(ws.get_packet()))
	match phase:
		"boot":
			if t_phase > 2.0:
				mode = Mode.new()
				mode.online = true
				mode.net_url = url
				mode.player_name = "Gamer"
				root.add_child(mode)
				_go("game_in")
		"game_in":
			# the game first (it takes a few seconds to build its match), then the others into the same match
			if mode.net_state == "playing" and mode.sim != null:
				for n in ["O", "P2", "P3"]:
					open(n)
				_go("m1")
			elif t_phase > 20.0:
				check(false, "the game in a match within 20 s (%s)" % mode.net_state)
				_finish()
		"m1":
			send_once("O", hello("Oldie", false))
			send_once("P2", hello("Pat", true))
			send_once("P3", hello("Pia", true))
			if mode.net_state == "playing" and mode.sim != null and ["O", "P2", "P3"].all(func(n): return not welcome(n).is_empty()):
				notes.m1 = mode.net_match
				check(["O", "P2", "P3"].all(func(n): return int(welcome(n).match) == int(notes.m1)), "everyone in match %d" % int(notes.m1))
				check(bool(mode._hello().get("ask_next", false)), "the game's hello asks for the next match itself")
				_go("end1")
			elif t_phase > 15.0:
				check(false, "everyone seated within 15 s (%s)" % mode.net_state)
				_finish()
		"end1":
			if mode.sim != null and mode.sim.ended and _results_up():
				_go("restart1")
			elif t_phase > 20.0:
				check(false, "match %d ended with the results up within 20 s" % int(notes.m1))
				_finish()
		"restart1":
			if int(welcome("O").get("match", -1)) != int(notes.m1) and not welcome("O").is_empty():
				notes.m2 = int(welcome("O").match)
				check(true, "the older app (no ask_next) is put in the next match by itself, as before (%d)" % int(notes.m2))
				_go("stay")
			elif t_phase > 10.0:
				check(false, "the next match started within 10 s of the end")
				_finish()
		"stay":
			if t_phase > 0.6 and not notes.has("mark"):
				notes.mark = (inbox.P2 as Array).size()
			if t_phase > 2.5:
				check(mode.net_match == int(notes.m1) and _results_up() and mode.sim.ended, "the game stays on its results (no new match)")
				check(int(welcome("P2").match) == int(notes.m1) and int(welcome("P3").match) == int(notes.m1), "nor are P2 and P3 put in it")
				var later: Array = (inbox.P2 as Array).slice(int(notes.mark))
				check(not later.any(func(m): return str(m.get("t", "")) == "s"), "...and they get no snapshots of it (%d messages)" % later.size())
				mode.hud.replay_requested.emit()                 # PLAY AGAIN
				say("P3", {"t":"again"})
				_go("again1")
		"again1":
			if mode.net_match == int(notes.m2) and mode.net_state == "playing" and int(welcome("P3").get("match", -1)) == int(notes.m2):
				check(mode.again_sent == 1 and not _results_up(), "PLAY AGAIN: the game is seated in the running match %d at once (%.1f s)" % [int(notes.m2), t_phase])
				check(true, "...and so is P3")
				_go("done")
			elif t_phase > 6.0:
				check(false, "seated after PLAY AGAIN within 6 s (game %d, P3 %d)" % [mode.net_match, int(welcome("P3").get("match", -1))])
				_finish()
		"done":
			var p2: WebSocketPeer = socks.P2
			if p2.get_ready_state() == WebSocketPeer.STATE_CLOSED:
				var bye := got("P2", "bye")
				check(not bye.is_empty() and str(bye[-1].why) == "done" and p2.get_close_code() == 1000,
					"P2 never pressed it: let go after the results time (bye done, %d)" % p2.get_close_code())
				(socks.O as WebSocketPeer).put_packet(Net.encode({"t":"leave"}))
				(socks.O as WebSocketPeer).close(1000, "leave")
				_go("end2")
			elif t_phase > 15.0:
				check(false, "P2 let go within 15 s")
				_finish()
		"end2":
			if mode.sim != null and mode.sim.ended and _results_up() and mode.net_match == int(notes.m2):
				_go("nobody")
			elif t_phase > 20.0:
				check(false, "match %d ended within 20 s" % int(notes.m2))
				_finish()
		"nobody":
			if t_phase > 3.5:
				check(mode.net_match == int(notes.m2) and int(welcome("P3").match) == int(notes.m2) and _results_up(),
					"nobody pressed PLAY AGAIN: no new match")
				say("P3", {"t":"again"})
				_go("p3_new")
		"p3_new":
			if int(welcome("P3").match) > int(notes.m2):
				notes.m3 = int(welcome("P3").match)
				check(true, "P3's PLAY AGAIN starts match %d" % int(notes.m3))
				_go("p3_new_wait")
			elif t_phase > 6.0:
				check(false, "P3 seated in a new match within 6 s")
				_finish()
		"p3_new_wait":
			if t_phase > 1.0:
				check(mode.net_match == int(notes.m2) and _results_up(), "the game is still on its results")
				mode.hud.replay_requested.emit()
				_go("join3")
		"join3":
			if mode.net_match == int(notes.m3) and mode.net_state == "playing":
				check(mode.again_sent == 2, "its PLAY AGAIN: into P3's match %d" % int(notes.m3))
				_finish()
			elif t_phase > 6.0:
				check(false, "the game joined match %d within 6 s (%d)" % [int(notes.get("m3", -1)), mode.net_match])
				_finish()
	return false

func _finish() -> void:
	if pid > 0:
		OS.kill(pid)
		OS.execute("kill", ["-9", str(pid)])
		pid = -1
	print("NEXT_MATCH_PASS" if fails.is_empty() else "NEXT_MATCH_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
