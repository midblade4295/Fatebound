extends SceneTree
# 0.31.120 (Kevin: watch a friend's match -- "make so it's a join match option"): the REAL server (port 8106, rooms of 3,
# at most 2) and the real app for Bob.
#   - Cara (Alice's friend) asks to join Alice while Alice's match is full: "full", and she's put in the other match
#   - Bob's app: Friends shows Alice "in a match" with JOIN; JOIN starts a match that goes into Alice's room -- her match,
#     on her side -- even though the other room is busier (the usual pick)
#   - Eve, not Alice's friend, asking to join her: refused ("gone"), the usual room
#   godot --headless --path godot -s res://tests/join_friend_test.gd
const App = preload("res://scripts/app/siege_app.gd")
const Profile = preload("res://scripts/meta/profile.gd")
const Net = preload("res://scripts/siege/siege_net.gd")
const FriendsPanel = preload("res://scripts/app/friends_panel.gd")

var fails: Array = []
var port := 8106
var url := ""
var pid := -1
var phase := "boot"
var t_phase := 0.0
var socks := {}
var inbox := {}
var sent := {}
var accts := {}
var pids := {}
var notes := {}
var closing: Array = []
var app

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _init() -> void:
	url = "ws://127.0.0.1:%d" % port
	var sd := OS.get_user_data_dir().path_join("join-srv-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(sd)
	OS.set_environment("SIEGE_PORT", str(port))
	OS.set_environment("SIEGE_HOST", "127.0.0.1")
	OS.set_environment("SIEGE_LOBBY", "0.5")
	OS.set_environment("SIEGE_MAX_PLAYERS", "3")
	OS.set_environment("SIEGE_MAX_ROOMS", "2")
	OS.set_environment("STATE_DIRECTORY", sd)
	OS.set_environment("SIEGE_MIN_BUILD", "off")
	OS.set_environment("SIEGE_URL", url)
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

func shut(name: String) -> void:
	var ws: WebSocketPeer = socks[name]
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

func hello(name: String, who := "", join := "") -> Dictionary:
	var h := {"t":"hello", "v":Net.VERSION, "five":Net.FIVE, "name":name, "build":"0.31.120-fatebound"}
	if who != "":
		h["acct"] = accts[who].acct
		h["key"] = accts[who].key
	if join != "":
		h["join"] = join
	return h

func _find(node: Node, pred: Callable) -> Array:
	var out := []
	if pred.call(node):
		out.append(node)
	for c in node.get_children():
		out.append_array(_find(c, pred))
	return out

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
			if t_phase > 2.0:
				for w in ["A", "B", "C", "E"]:
					var imp := Profile.defaults()
					imp.name = {"A":"Alice", "B":"Bob", "C":"Cara", "E":"Eve"}[w]
					open("e" + w)
					send_once("e" + w, {"t":"eco", "v":Net.VERSION, "new":true, "import":imp})
				_go("accounts")
		"accounts":
			for w in ["A", "B", "C", "E"]:
				send_once("e" + w, {"t":"eco", "v":Net.VERSION, "new":true})
				if not got("e" + w, "eco").is_empty() and not accts.has(w):
					var m: Dictionary = got("e" + w, "eco")[0]
					accts[w] = {"acct":str(m.acct), "key":str(m.key)}
			if accts.size() == 4:
				for w in ["A", "B", "C"]:
					open("s" + w)
				_go("friends")
			elif t_phase > 10.0:
				check(false, "accounts within 10 s")
				_finish()
		"friends":
			for w in ["A", "B", "C"]:
				send_once("s" + w, {"t":"so", "k":"hi", "v":Net.VERSION, "acct":accts[w].acct, "key":accts[w].key})
				for m in inbox["s" + w]:
					if str(m.get("k", "")) == "me":
						pids[w] = str(m.pid)
			var st := int(notes.get("fs", 0))
			if st == 0 and pids.size() == 3:
				say("sA", {"t":"so", "k":"add", "pid":pids.B})
				say("sA", {"t":"so", "k":"add", "pid":pids.C})
				notes.fs = 1
				notes.at = t_phase
			elif st == 1 and t_phase - float(notes.at) > 0.6:
				say("sB", {"t":"so", "k":"add", "pid":pids.A})
				say("sC", {"t":"so", "k":"add", "pid":pids.A})
				notes.fs = 2
				notes.at = t_phase
			elif st == 2 and t_phase - float(notes.at) > 0.6:
				shut("sB")                                   # (Bob's app has its own social connection)
				for n in ["pA", "X1", "X2", "Z1"]:
					open(n)
				_go("fill")
			elif t_phase > 10.0:
				check(false, "friends within 10 s")
				_finish()
		"fill":
			send_once("pA", hello("Alice", "A"))
			if not welcome("pA").is_empty():
				send_once("X1", hello("X1"))
				send_once("X2", hello("X2"))
			if not welcome("X2").is_empty() and not welcome("X1").is_empty():
				send_once("Z1", hello("Z1"))
			if not welcome("Z1").is_empty():
				check(int(welcome("X1").match) == int(welcome("pA").match) and int(welcome("Z1").match) != int(welcome("pA").match),
					"Alice's match full (Alice, X1, X2); Z1 in the other one")
				open("pC")
				_go("cara")
			elif t_phase > 12.0:
				check(false, "the rooms filled within 12 s")
				_finish()
		"cara":
			send_once("pC", hello("Cara", "C", str(pids.A)))
			if not welcome("pC").is_empty():
				var jr := got("pC", "joinr")
				check(not jr.is_empty() and str(jr[0].why) == "full" and int(welcome("pC").match) == int(welcome("Z1").match),
					"Cara asks to join Alice while her match is full: full, put in the other match")
				shut("X1")
				shut("X2")
				_go("bob_app")
			elif t_phase > 10.0:
				check(false, "Cara seated within 10 s")
				_finish()
		"bob_app":
			if t_phase > 0.8:
				var base := "user://jointest-%d" % Time.get_ticks_usec()
				var p = Profile.new(base + "-profile.json", base + "-none.json")
				p.load_or_create()
				p.d.name = "Bob"
				p.d.account = {"id":accts.B.acct, "key":accts.B.key, "seq":0}
				p.d.tutorial_done = true
				p.server_mode = true
				p.save()
				app = App.new()
				app.profile_path = base + "-profile.json"
				app.legacy_path = base + "-none.json"
				root.add_child(app)
				app.social.set_active(true)
				_go("bob_friends")
		"bob_friends":
			var ok := false
			if app.social.online():
				for f in app.social.friends:
					if str(f.pid) == str(pids.A) and str(f.st) == "match":
						ok = true
			if ok:
				app.profile.server_mode = true
				app.open_friends()
				var jb := _find(app.modal, func(n): return n is Button and str(n.get_meta("action_key", "")) == "friend_join_" + str(pids.A))
				check(app.modal is FriendsPanel and jb.size() == 1, "Bob's Friends: Alice is in a match, with JOIN")
				if jb.size() == 1:
					(jb[0] as Button).pressed.emit()
				check(app.siege != null and str(app.siege.party_join) == str(pids.A), "JOIN starts a match aimed at Alice's")
				_go("bob_join")
			elif t_phase > 15.0:
				check(false, "Bob's app sees Alice in a match within 15 s")
				_finish()
		"bob_join":
			if app.siege != null and app.siege.net_state == "playing" and app.siege.sim != null:
				check(app.siege.net_match == int(welcome("pA").match), "Bob is in Alice's match (%d), not the busier one" % app.siege.net_match)
				check(str(app.siege.hud.player_id).left(1) == str(welcome("pA").you).left(1), "on Alice's side (%s, %s)" % [app.siege.hud.player_id, welcome("pA").you])
				open("pE")
				_go("eve")
			elif t_phase > 30.0:
				check(false, "Bob seated within 30 s (%s)" % (app.siege.net_state if app.siege != null else "no match"))
				_finish()
		"eve":
			send_once("pE", hello("Eve", "E", str(pids.A)))
			if not welcome("pE").is_empty() or not got("pE", "lobby").is_empty():
				var jr := got("pE", "joinr")
				check(not jr.is_empty() and str(jr[0].why) == "gone", "Eve (not Alice's friend) can't join her: refused")
				_finish()
			elif t_phase > 10.0:
				check(false, "Eve answered within 10 s")
				_finish()
	return false

func _finish() -> void:
	if pid > 0:
		OS.kill(pid)
		OS.execute("kill", ["-9", str(pid)])
		pid = -1
	print("JOIN_FRIEND_PASS" if fails.is_empty() else "JOIN_FRIEND_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
