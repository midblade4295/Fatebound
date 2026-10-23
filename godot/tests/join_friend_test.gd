extends SceneTree
# 0.31.120 (Kevin: watch a friend's match -- "make so it's a join match option"): the REAL server (port 8106, rooms of 3,
# at most 3) and the real app for Bob. 0.31.209 (Kevin: "Make it so players cannot join a match in progress. Every player
# can only join when the countdown is happening"): JOIN only while the friend's match is in its countdown (8 s here).
#   - Alice says hello: her friends' cards say she's in a match that can be joined ("jn")
#   - Bob's app: Friends shows Alice with JOIN; JOIN starts a match that goes into Alice's countdown -- her match, on her
#     side
#   - the countdown over: her card no longer says "jn" (Bob's app would show PLAYING, no JOIN)
#   - Cara (Alice's friend) asks to join her now: "playing" -- not into it; a lobby of her own instead
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
	OS.set_environment("SIEGE_LOBBY", "8")
	OS.set_environment("SIEGE_MAX_PLAYERS", "3")
	OS.set_environment("SIEGE_MAX_ROOMS", "3")
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

func _alice_pres(from: int) -> Array:
	# Cara's social socket: what she's been told of Alice since `from` (her card in "pres")
	var out := []
	var l: Array = inbox.sC
	for i in range(from, l.size()):
		var m: Dictionary = l[i]
		if str(m.get("k", "")) == "pres" and str(m.get("c", {}).get("pid", "")) == str(pids.A):
			out.append(m.c)
	return out

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
				_go("bob_app")
			elif t_phase > 10.0:
				check(false, "friends within 10 s")
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
				_go("bob_ready")
		"bob_ready":
			if app.social.online() and app.social.friends.any(func(f): return str(f.pid) == str(pids.A)):
				check(app.social.has_jn, "the server says friends' cards carry \"jn\"")
				open("pA")
				notes.pres_mark = (inbox.sC as Array).size()
				_go("alice")
			elif t_phase > 15.0:
				check(false, "Bob's app online with Alice in its friends within 15 s")
				_finish()
		"alice":
			send_once("pA", hello("Alice", "A"))
			var pres := _alice_pres(int(notes.pres_mark))
			if not got("pA", "lobby").is_empty() and not pres.is_empty() and str(pres[-1].st) == "match":
				check(int(pres[-1].get("jn", 0)) == 1, "Alice in her countdown: her friends' cards say she's in a match that can be joined (jn)")
				_go("bob_friends")
			elif t_phase > 10.0:
				check(false, "Alice in a lobby, her friends told, within 10 s (%s)" % str(pres))
				_finish()
		"bob_friends":
			var ok := false
			for f in app.social.friends:
				if str(f.pid) == str(pids.A) and app.social.can_join(f):
					ok = true
			if ok:
				app.profile.server_mode = true
				app.open_friends()
				var jb := _find(app.modal, func(n): return n is Button and str(n.get_meta("action_key", "")) == "friend_join_" + str(pids.A))
				check(app.modal is FriendsPanel and jb.size() == 1, "Bob's Friends: Alice in a match's countdown, with JOIN")
				if jb.size() == 1:
					(jb[0] as Button).pressed.emit()
				check(app.siege != null and str(app.siege.party_join) == str(pids.A), "JOIN starts a match aimed at Alice's")
				notes.pres_mark = (inbox.sC as Array).size()
				_go("bob_join")
			elif t_phase > 6.0:
				check(false, "Bob's app sees Alice's match can be joined within 6 s")
				_finish()
		"bob_join":
			if app.siege != null and app.siege.net_state == "playing" and app.siege.sim != null and not welcome("pA").is_empty():
				check(app.siege.net_match == int(welcome("pA").match), "Bob is in Alice's match (%d), from her countdown" % app.siege.net_match)
				check(str(app.siege.hud.player_id).left(1) == str(welcome("pA").you).left(1), "on Alice's side (%s, %s)" % [app.siege.hud.player_id, welcome("pA").you])
				_go("started")
			elif t_phase > 20.0:
				check(false, "Bob seated within 20 s (%s)" % (app.siege.net_state if app.siege != null else "no match"))
				_finish()
		"started":
			var pres := _alice_pres(int(notes.pres_mark))
			if not pres.is_empty() and str(pres[-1].st) == "match" and int(pres[-1].get("jn", 0)) == 0:
				check(true, "the countdown over: Alice's card no longer says jn (no JOIN into a match in progress)")
				var card: Dictionary = pres[-1]
				var friends_panel_join: bool = app.social.can_join(card)
				check(not friends_panel_join, "...so Bob's app would show PLAYING, not JOIN")
				open("pC")
				_go("cara")
			elif t_phase > 6.0:
				check(false, "Alice's card without jn once her match started, within 6 s (%s)" % str(pres))
				_finish()
		"cara":
			send_once("pC", hello("Cara", "C", str(pids.A)))
			if not got("pC", "lobby").is_empty() or not welcome("pC").is_empty():
				var jr := got("pC", "joinr")
				check(not jr.is_empty() and str(jr[0].why) == "playing", "Cara asks to join Alice while her match runs: \"playing\" (%s)" % str(jr))
				check(welcome("pC").is_empty() or int(welcome("pC").match) != int(welcome("pA").match), "...not put in it: a lobby of her own")
				open("pE")
				_go("eve")
			elif t_phase > 10.0:
				check(false, "Cara answered within 10 s")
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
