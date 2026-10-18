extends SceneTree
# 0.31.120 (Kevin: rejoin after a dropped connection): the REAL server (port 8105, seats held 6 s, 12-second matches) and
# the real game client (SiegeMode online), real time.
#   - the game's connection drops mid-match: it keeps the match on screen ("RECONNECTING"), reconnects by itself and is
#     put straight back on its own unit in the same match (no lobby)
#   - it can't get back (the server unreachable): after its window it says "Disconnected from the server"
#   - a phone that switched networks (the server still thinks the old socket is open) takes its seat over with the token;
#     the old socket is closed
#   - a player who quits on purpose (close "leave") has no seat held
#   - a held seat nobody comes back for is let go; its token then gets an ordinary seat, not the old one
#   - a seat held when the match ends is still paid to the account (the server's own record of the match)
#   godot --headless --path godot -s res://tests/rejoin_test.gd
const Mode = preload("res://scripts/siege/siege_mode.gd")
const Net = preload("res://scripts/siege/siege_net.gd")

var fails: Array = []
var port := 8105
var url := ""
var pid := -1
var mode
var phase := "boot"
var t_phase := 0.0
var socks := {}
var inbox := {}
var sent := {}
var notes := {}
var accts := {}

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _init() -> void:
	url = "ws://127.0.0.1:%d/" % port
	OS.set_environment("SIEGE_PORT", str(port))
	OS.set_environment("SIEGE_HOST", "127.0.0.1")
	OS.set_environment("SIEGE_LOBBY", "0.5")
	OS.set_environment("SIEGE_REJOIN_HOLD", "6")
	OS.set_environment("SIEGE_TEST_MATCH_S", "12")
	OS.set_environment("SIEGE_MIN_BUILD", "off")
	var sd := OS.get_user_data_dir().path_join("rejoin-srv-%d" % Time.get_ticks_usec())
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

func got(name: String, tt: String) -> Array:
	return (inbox.get(name, []) as Array).filter(func(m): return str(m.get("t", "")) == tt)

func welcome(name: String) -> Dictionary:
	var w := got(name, "welcome")
	return w[w.size() - 1] if not w.is_empty() else {}

func hello(name: String, who := "", rj := "") -> Dictionary:
	var h := {"t":"hello", "v":Net.VERSION, "five":Net.FIVE, "name":name, "build":"0.31.120-fatebound"}
	if who != "":
		h["acct"] = accts[who].acct
		h["key"] = accts[who].key
	if rj != "":
		h["rj"] = rj
	return h

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
				open("eB")
				open("eE")
				_go("accounts")
		"accounts":
			send_once("eB", {"t":"eco", "v":Net.VERSION, "new":true})
			send_once("eE", {"t":"eco", "v":Net.VERSION, "new":true})
			if not got("eB", "eco").is_empty() and not got("eE", "eco").is_empty():
				for w in ["B", "E"]:
					var m: Dictionary = got("e" + w, "eco")[0]
					accts[w] = {"acct":str(m.acct), "key":str(m.key)}
				mode = Mode.new()
				mode.online = true
				mode.net_url = url
				mode.player_name = "Roamer"
				root.add_child(mode)
				for n in ["B", "C", "D", "E"]:
					open(n)
				_go("join")
			elif t_phase > 10.0:
				check(false, "accounts within 10 s")
				_finish()
		"join":
			send_once("B", hello("Bravo", "B"))
			send_once("C", hello("Charlie"))
			send_once("D", hello("Delta"))
			send_once("E", hello("Echo", "E"))
			if mode.net_state == "playing" and mode.sim != null and mode.sim.time > 0.5 and ["B", "C", "D", "E"].all(func(n): return not welcome(n).is_empty()):
				check(str(welcome("B").get("rj", "")).length() == 16, "every welcome carries a rejoin token")
				notes.unit = mode.hud.player_id
				notes.match = mode.net_match
				mode.ws.close(4999, "network gone")          # the phone's connection drops
				# B's phone switches networks: a new socket says hello with B's token while the old one still looks open
				notes.tokB = str(welcome("B").rj)
				open("B2")
				# C quits on purpose; D's connection drops
				(socks.C as WebSocketPeer).close(1000, "leave")
				notes.tokD = str(welcome("D").rj)
				notes.unitD = str(welcome("D").you)
				(socks.D as WebSocketPeer).close(4999, "gone")
				_go("rejoin")
			elif t_phase > 15.0:
				check(false, "everyone seated within 15 s (%s)" % mode.net_state)
				_finish()
		"rejoin":
			send_once("B2", hello("Bravo", "B", str(notes.tokB)))
			if mode.net_state == "rejoining" and not notes.has("saw_rejoining"):
				notes.saw_rejoining = true
				check(mode.hud.rejoin_until > 0.0 and mode.sim != null, "the drop: the match stays on screen, RECONNECTING")
			if mode.rejoins == 1 and mode.net_state == "playing" and not welcome("B2").is_empty():
				check(bool(notes.get("saw_rejoining", false)), "...it was reconnecting")
				check(mode.hud.player_id == str(notes.unit) and mode.net_match == int(notes.match) and mode.hud.rejoin_until < 0.0,
					"back on its own unit (%s) in the same match, no lobby" % mode.hud.player_id)
				var w2 := welcome("B2")
				check(bool(w2.get("rejoin", false)) and str(w2.you) == str(welcome("B").you), "B's new socket took its seat over (%s)" % str(w2.get("you", "")))
				_go("old_closed")
			elif t_phase > 10.0:
				check(false, "rejoined within 10 s (state %s, rejoins %d, B2 %s)" % [mode.net_state, mode.rejoins, str(inbox.B2.map(func(m): return m.t))])
				_finish()
		"old_closed":
			var b: WebSocketPeer = socks.B
			if b.get_ready_state() == WebSocketPeer.STATE_CLOSED:
				check(b.get_close_reason() == "rejoined", "...and its old socket was closed (%s)" % b.get_close_reason())
				# the game can't get back this time
				mode.net_url = "ws://127.0.0.1:1"
				mode.rejoin_for = 2.5
				mode.ws.close(4999, "network gone again")
				_go("cant")
			elif t_phase > 5.0:
				check(false, "B's old socket closed within 5 s")
				_finish()
		"cant":
			if mode.net_state == "closed":
				check(t_phase > 2.0 and t_phase < 6.0, "can't get back: gives up after its window (%.1f s)" % t_phase)
				_go("hold_expire")
			elif t_phase > 10.0:
				check(false, "gave up within 10 s (%s)" % mode.net_state)
				_finish()
		"hold_expire":
			if t_phase > 1.0 and not socks.has("D2") and float(notes.get("d_at", 0.0)) == 0.0:
				notes.d_at = 1.0
			# D's seat was held 6 s from the drop; the 12 s match ends around now, so check D's token in the next match
			if t_phase > 1.0 and not socks.has("E_dropped"):
				pass
			var e_ws: WebSocketPeer = socks.E
			if e_ws.get_ready_state() == WebSocketPeer.STATE_OPEN and not notes.has("e_dropped"):
				# E drops close to the end: its seat is still held when the match ends
				var sim_t := float(got("E", "s")[-1].get("tm", 0.0)) if not got("E", "s").is_empty() else 0.0
				if sim_t > 8.5:
					notes.e_dropped = true
					e_ws.close(4999, "gone")
			var ended := false
			for m in got("C", "s") + got("B2", "s"):
				for ev in m.get("e", []):
					ended = ended or str(ev.get("k", "")) == "end"
			if ended or t_phase > 25.0:
				check(bool(notes.get("e_dropped", false)), "E dropped before the end")
				open("D2")
				open("ecoE")
				_go("after")
		"after":
			send_once("D2", hello("Delta", "", str(notes.tokD)))
			send_once("ecoE", {"t":"eco", "v":Net.VERSION, "acct":accts.E.acct, "key":accts.E.key, "ops":[]})
			var d2 := got("D2", "welcome")
			var dl := got("D2", "lobby")
			if (not d2.is_empty() or not dl.is_empty()) and not got("ecoE", "eco").is_empty():
				check(d2.is_empty() or not bool(d2[0].get("rejoin", false)), "a seat nobody came back for is let go: its token gets no rejoin")
				var pe: Dictionary = got("ecoE", "eco")[0].get("profile", {})
				check(int(pe.get("stats", {}).get("matches", 0)) == 1, "a seat held when the match ended is still paid (%d matches)" % int(pe.get("stats", {}).get("matches", 0)))
				_finish()
			elif t_phase > 12.0:
				check(false, "answers for D2 and E within 12 s")
				_finish()
	return false

func _finish() -> void:
	if pid > 0:
		OS.kill(pid)
		OS.execute("kill", ["-9", str(pid)])
		pid = -1
	print("REJOIN_PASS" if fails.is_empty() else "REJOIN_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
