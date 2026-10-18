extends SceneTree
# 0.31.119 (Kevin: "Do all" -- 1. more than one match at a time): the REAL server (port 8102) with rooms of 3 players and at
# most 2 rooms (SIEGE_MAX_PLAYERS=3, SIEGE_MAX_ROOMS=2), real time.
#   - three players fill room 1 (one match); the fourth (A, in a party with B) opens room 2 (another match)
#   - one of room 1 leaves: room 1 is now the busier one, but B goes to A's room (the party first), on A's side
#   - the next two fill whichever room has space; the seventh is turned away as "full" (bye full, 4002) -- only now
#   - "status" counts every room (online 6, rooms 2, max 6); a room's names ("pn") are only its own players
#   - everyone leaves: the rooms close (SIEGE_IDLE_STOP=2 here)
#   godot --headless --path godot -s res://tests/match_rooms_test.gd
const Net = preload("res://scripts/siege/siege_net.gd")

var fails: Array = []
var port := 8102
var url := ""
var pid := -1
var phase := "boot"
var t_phase := 0.0
var socks := {}
var inbox := {}
var sent := {}
var accts := {}                          # "A"/"B" -> {acct, key}
var notes := {}

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _init() -> void:
	var state := OS.get_user_data_dir().path_join("rooms-srv-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(state)
	url = "ws://127.0.0.1:%d/" % port
	OS.set_environment("SIEGE_PORT", str(port))
	OS.set_environment("SIEGE_HOST", "127.0.0.1")
	OS.set_environment("SIEGE_LOBBY", "0.5")
	OS.set_environment("SIEGE_MAX_PLAYERS", "3")
	OS.set_environment("SIEGE_MAX_ROOMS", "2")
	OS.set_environment("SIEGE_IDLE_STOP", "2")
	OS.set_environment("STATE_DIRECTORY", state)
	OS.set_environment("SIEGE_MIN_BUILD", "off")
	pid = OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://server/siege_server.gd"])
	check(pid > 0, "server process started")

func _go(ph: String) -> void:
	phase = ph
	t_phase = 0.0

func open(name: String) -> void:
	var ws := WebSocketPeer.new()
	ws.inbound_buffer_size = 1 << 21
	ws.connect_to_url(url)
	socks[name] = ws
	inbox[name] = []
	sent.erase(name)

var closing: Array = []

func shut(name: String) -> void:
	# a clean leave, like the app's (0.31.120: no seat held): "leave", then a close polled until it's out
	var ws: WebSocketPeer = socks[name]
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.put_packet(Net.encode({"t":"leave"}))
	ws.close(1000, "leave")
	closing.append(ws)
	socks.erase(name)

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

func hello(name: String, who := "") -> Dictionary:
	var h := {"t":"hello", "v":Net.VERSION, "five":Net.FIVE, "name":name, "build":"0.31.119-fatebound"}
	if who != "":
		h["acct"] = accts[who].acct
		h["key"] = accts[who].key
	return h

func _process(delta: float) -> bool:
	t_phase += delta
	for ws in closing:
		ws.poll()
	for n in socks:
		var ws: WebSocketPeer = socks[n]
		ws.poll()
		while ws.get_available_packet_count() > 0:
			(inbox[n] as Array).append(Net.decode(ws.get_packet()))
	match phase:
		"boot":
			if t_phase > 2.5:
				open("eA")
				open("eB")
				_go("accounts")
		"accounts":
			send_once("eA", {"t":"eco", "v":Net.VERSION, "new":true})
			send_once("eB", {"t":"eco", "v":Net.VERSION, "new":true})
			if not got("eA", "eco").is_empty() and not got("eB", "eco").is_empty():
				for w in ["A", "B"]:
					var m: Dictionary = got("e" + w, "eco")[0]
					accts[w] = {"acct":str(m.acct), "key":str(m.key)}
				shut("eA")
				shut("eB")
				open("sA")
				open("sB")
				_go("party")
			elif t_phase > 10.0:
				check(false, "two accounts within 10 s")
				_finish()
		"party":
			send_once("sA", {"t":"so", "k":"hi", "v":Net.VERSION, "acct":accts.A.acct, "key":accts.A.key})
			send_once("sB", {"t":"so", "k":"hi", "v":Net.VERSION, "acct":accts.B.acct, "key":accts.B.key})
			var step := int(notes.get("ps", 0))
			var pidA := ""
			var pidB := ""
			for m in inbox.sA:
				if str(m.get("k", "")) == "me":
					pidA = str(m.pid)
			for m in inbox.sB:
				if str(m.get("k", "")) == "me":
					pidB = str(m.pid)
			if step == 0 and pidA != "" and pidB != "":
				say("sA", {"t":"so", "k":"add", "pid":pidB})
				notes.ps = 1
				notes.at = t_phase
			elif step == 1 and t_phase - float(notes.at) > 0.5:
				say("sB", {"t":"so", "k":"add", "pid":pidA})
				notes.ps = 2
				notes.at = t_phase
			elif step == 2 and t_phase - float(notes.at) > 0.5:
				say("sA", {"t":"so", "k":"invite", "pid":pidB})
				notes.ps = 3
				notes.at = t_phase
			elif step == 3 and t_phase - float(notes.at) > 0.5:
				var inv := (inbox.sB as Array).filter(func(m): return str(m.get("k", "")) == "inv")
				if not inv.is_empty():
					say("sB", {"t":"so", "k":"join", "party":str(inv[0].party)})
					notes.ps = 4
					notes.at = t_phase
			elif step == 4 and t_phase - float(notes.at) > 0.5:
				for x in ["X1", "X2", "X3"]:
					open(x)
				_go("fill1")
			elif t_phase > 15.0:
				check(false, "A and B in a party within 15 s (step %d)" % step)
				_finish()
		"fill1":
			for x in ["X1", "X2", "X3"]:
				send_once(x, hello(x))
			if not welcome("X1").is_empty() and not welcome("X2").is_empty() and not welcome("X3").is_empty():
				var m1 := int(welcome("X1").match)
				check(int(welcome("X2").match) == m1 and int(welcome("X3").match) == m1, "three players: one room, one match (%d)" % m1)
				notes.m1 = m1
				open("A")
				_go("room2")
			elif t_phase > 10.0:
				check(false, "the first three seated within 10 s")
				_finish()
		"room2":
			send_once("A", hello("Alpha", "A"))
			if not welcome("A").is_empty():
				var m2 := int(welcome("A").match)
				check(m2 != int(notes.m1), "the fourth opens a second room: another match (%d)" % m2)
				notes.m2 = m2
				shut("X1")
				_go("leave")
			elif t_phase > 10.0:
				check(false, "A seated within 10 s (%s)" % str(inbox.A.map(func(m): return m.t)))
				_finish()
		"leave":
			if t_phase > 0.8:
				open("B")
				_go("party_room")
		"party_room":
			send_once("B", hello("Bravo", "B"))
			if not welcome("B").is_empty():
				check(int(welcome("B").match) == int(notes.m2), "B goes to A's room (its party), not the busier room 1")
				check(str(welcome("B").you).left(1) == str(welcome("A").you).left(1), "...on A's side (%s, %s)" % [welcome("A").you, welcome("B").you])
				open("Y")
				_go("y")
			elif t_phase > 10.0:
				check(false, "B seated within 10 s")
				_finish()
		"y":
			send_once("Y", hello("Yankee"))
			if not welcome("Y").is_empty():
				notes.my = int(welcome("Y").match)
				open("Z")
				_go("z")
			elif t_phase > 10.0:
				check(false, "Y seated within 10 s")
				_finish()
		"z":
			send_once("Z", hello("Zulu"))
			if not welcome("Z").is_empty():
				var mz := int(welcome("Z").match)
				var my := int(notes.my)
				check(my != mz and [my, mz].has(int(notes.m1)) and [my, mz].has(int(notes.m2)), "the next two fill the space in each room")
				open("W")
				open("status")
				_go("full")
			elif t_phase > 10.0:
				check(false, "Z seated within 10 s")
				_finish()
		"full":
			send_once("W", hello("Whiskey"))
			send_once("status", {"t":"status"})
			var ws: WebSocketPeer = socks.W
			if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED and not got("status", "status").is_empty():
				var bye := got("W", "bye")
				check(not bye.is_empty() and str(bye[0].why) == "full" and ws.get_close_code() == 4002 and welcome("W").is_empty(),
					"the seventh, with every room full: \"full\" (%d)" % ws.get_close_code())
				var st: Dictionary = got("status", "status")[0]
				check(int(st.online) == 6 and int(st.rooms) == 2 and int(st.max) == 6 and int(st.in_match) == 6,
					"status counts every room: online %d, rooms %d, max %d, in match %d" % [int(st.online), int(st.get("rooms", -1)), int(st.max), int(st.in_match)])
				# names: each player sees only their own room's players
				var pn := got("A", "pn")
				var names: Array = (pn[pn.size() - 1].n as Dictionary).values() if not pn.is_empty() else []
				var room2_names := ["Player", "Player", "Yankee" if int(notes.my) == int(notes.m2) else "Zulu"]   # (an account's name is its own)
				names.sort()
				room2_names.sort()
				check(names == room2_names, "A's names are its own room's: %s" % str(names))
				for n in socks.keys():
					shut(n)
				open("status2")
				sent.erase("status2")
				_go("close")
			elif t_phase > 10.0:
				check(false, "W refused within 10 s")
				_finish()
		"close":
			if t_phase > 5.0:
				send_once("status2", {"t":"status"})
				if not got("status2", "status").is_empty():
					var st: Dictionary = got("status2", "status")[0]
					check(int(st.online) == 0 and int(st.rooms) == 0, "everyone gone: the rooms close (rooms %d)" % int(st.get("rooms", -1)))
					_finish()
				elif t_phase > 10.0:
					check(false, "a status answer after the rooms closed")
					_finish()
	return false

func _finish() -> void:
	if pid > 0:
		OS.kill(pid)
		OS.execute("kill", ["-9", str(pid)])
		pid = -1
	print("MATCH_ROOMS_PASS" if fails.is_empty() else "MATCH_ROOMS_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
