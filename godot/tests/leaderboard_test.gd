extends SceneTree
# 0.31.119 (Kevin: "Do all" -- 4. leaderboards).
#  1. server/leaderboard.gd on its own: weeks start Monday 00:00 UTC; a match's points (0.31.170, the 5v5's: KO 20, tower,
#     gate and King damage 1 per 10, a win +100; towers counted for the TW column); best first; your row and your friends' rows; no account id in an
#     answer; kept on disk; a new week keeps last week's top 3 and starts empty.
#  2. end to end (the real server, port 8104, 4-second matches): an online match paid to an account puts it on the board;
#     {"t":"lb"} with its key answers it (its row marked, its friends' rows), "status" says "lb":1, a wrong key gets
#     4007 and nothing.
#  3. the app: (0.31.164-169: no RANKS on Home; 0.31.170, the online 5v5: RANKS again) the LEADERBOARD window with the
#     player's row, the FRIENDS tab.
#   godot --headless --path godot -s res://tests/leaderboard_test.gd
const Leaderboard = preload("res://server/leaderboard.gd")
const LbFetch = preload("res://scripts/meta/lb_fetch.gd")
const App = preload("res://scripts/app/siege_app.gd")
const Profile = preload("res://scripts/meta/profile.gd")
const Net = preload("res://scripts/siege/siege_net.gd")
const LeaderboardPanel = preload("res://scripts/app/leaderboard_panel.gd")

const MON := 1791763200                 # 2026-10-12 00:00 UTC, a Monday

var fails: Array = []
var port := 8104
var pid := -1
var phase := "boot"
var t_phase := 0.0
var raw := {}
var accts := {}
var notes := {}
var app
var shots := ""

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _init() -> void:
	shots = OS.get_environment("SHOT_DIR") if DisplayServer.get_name() != "headless" else ""
	_part1()
	var sd := OS.get_user_data_dir().path_join("lb-srv-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(sd)
	OS.set_environment("SIEGE_PORT", str(port))
	OS.set_environment("SIEGE_HOST", "127.0.0.1")
	OS.set_environment("SIEGE_LOBBY", "0.5")
	OS.set_environment("SIEGE_TEST_MATCH_S", "4")
	OS.set_environment("STATE_DIRECTORY", sd)
	OS.set_environment("SIEGE_MIN_BUILD", "off")
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:%d" % port)
	pid = OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://server/siege_server.gd"])
	check(pid > 0, "server process started")

# ---------------- 1. the board on its own ----------------
func _part1() -> void:
	check(Leaderboard.week_of(MON) == "2026-10-12" and Leaderboard.week_of(MON + 7 * 86400 - 1) == "2026-10-12"
		and Leaderboard.week_of(MON + 7 * 86400) == "2026-10-19" and Leaderboard.week_of(MON - 1) == "2026-10-05",
		"weeks start Monday 00:00 UTC (%s)" % Leaderboard.week_of(MON + 3 * 86400))
	check(Leaderboard.week_end(MON + 100000) == MON + 7 * 86400, "...and end the next Monday")
	check(Leaderboard.points_of({"kills":5, "gate_dmg":200.0, "towers":2, "rescues":1}, true) == 100 + 20 + 100,
		"a match's points: KO 20, tower/gate/King damage 1 per 10, a win +100 (Siege's rescues count nothing)")
	var dir := OS.get_user_data_dir().path_join("lbtest-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(dir)
	var lb = Leaderboard.new(dir, MON + 3600)
	lb.add_match("a".repeat(20), "Alice", "title_victor", {"kills":5, "towers":1}, true)         # 200
	lb.add_match("b".repeat(20), "Bob", "", {"kills":10}, false)                                   # 200
	lb.add_match("c".repeat(20), "Cara", "", {"kills":1}, false)                                   # 20
	lb.add_match("b".repeat(20), "Bob", "", {"kills":10, "gate_dmg":1000.0, "towers":2}, true)    # +400 = 600
	var ans: Dictionary = lb.answer("a".repeat(20), ["b".repeat(20), "z".repeat(20)])
	var top: Array = ans.top
	check(top.size() == 3 and str(top[0].name) == "Bob" and int(top[0].pts) == 600 and int(top[0].w) == 1 and int(top[0].m) == 2
		and int(top[0].tw) == 2 and int(top[1].tw) == 1
		and str(top[1].name) == "Alice" and bool(top[1].get("you", false)) and int(top[1].rank) == 2, "best first, your row marked: %s" % str(top.map(func(r): return [r.name, r.pts])))
	check(int(ans.me.rank) == 2 and str(ans.me.title) == "title_victor" and int(ans.players) == 3, "your own row (rank 2, your title)")
	check(ans.friends.size() == 2 and str(ans.friends[0].name) == "Bob" and str(ans.friends[1].name) == "Alice", "friends: you and your friends on the board, best first")
	check(not JSON.stringify(ans).contains("aaaaaaaaaa") and not JSON.stringify(ans).contains("bbbbbbbbbb"), "no account id in the answer")
	check((lb.answer("d".repeat(20), []).me as Dictionary).is_empty(), "not on the board: no row")
	lb.save_now()
	var lb2 = Leaderboard.new(dir, MON + 7200)
	check(lb2.rows.size() == 3 and int(lb2.rows["b".repeat(20)].pts) == 600, "kept on disk")
	lb2.now_override = MON + 7 * 86400 + 60
	var a2: Dictionary = lb2.answer("a".repeat(20), [])
	check(str(a2.week) == "2026-10-19" and int(a2.players) == 0 and (a2.last as Array).size() == 3 and str(a2.last[0].name) == "Bob" and int(a2.last[0].pts) == 600,
		"a new week: last week's top 3 kept, the board empty")

# ---------------- 2 + 3 ----------------
func _ws(name: String, first: Dictionary) -> void:
	var ws := WebSocketPeer.new()
	ws.inbound_buffer_size = 1 << 21
	ws.connect_to_url("ws://127.0.0.1:%d" % port)
	raw[name] = {"ws":ws, "first":first, "sent":false, "msgs":[]}

func _got(name: String, kind: String) -> Array:
	return (raw.get(name, {}).get("msgs", []) as Array).filter(func(m): return str(m.get("t", "")) == kind)

func _go(p: String) -> void:
	phase = p
	t_phase = 0.0

func _find(node: Node, pred: Callable) -> Array:
	var out := []
	if pred.call(node):
		out.append(node)
	for c in node.get_children():
		out.append_array(_find(c, pred))
	return out

func _btn(key: String) -> Button:
	var l := _find(app, func(n): return n is Button and str(n.get_meta("action_key", "")) == key and (n as Control).is_visible_in_tree())
	return l[0] if not l.is_empty() else null

func _shot(name: String) -> void:
	if shots == "":
		return
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(shots.path_join(name + ".png"))

func _process(delta: float) -> bool:
	t_phase += delta
	for n in raw:
		var r: Dictionary = raw[n]
		var ws: WebSocketPeer = r.ws
		ws.poll()
		var now_s := Time.get_ticks_msec() / 1000.0
		if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED and not bool(r.sent) and now_s - float(r.get("dialed", 0.0)) > 0.5:
			# 0.31.145: the server (its own process) may not be listening yet on a slow machine -- dial again
			r.dialed = now_s
			ws.connect_to_url("ws://127.0.0.1:%d" % port)
			continue
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN and not bool(r.sent):
			ws.put_packet(Net.encode(r.first))
			r.sent = true
		while ws.get_available_packet_count() > 0:
			(r.msgs as Array).append(Net.decode(ws.get_packet()))
	match phase:
		"boot":
			if t_phase > 2.0:
				for n in ["alice", "bob"]:
					var imp := Profile.defaults()
					imp.name = n.capitalize()
					_ws("eco_" + n, {"t":"eco", "v":Net.VERSION, "new":true, "import":imp})
				_ws("status", {"t":"status"})
				_go("accounts")
		"accounts":
			for n in ["alice", "bob"]:
				var e := _got("eco_" + n, "eco")
				if not e.is_empty() and not accts.has(n):
					accts[n] = {"acct":str(e[0].acct), "key":str(e[0].key)}
			if accts.size() == 2 and not _got("status", "status").is_empty():
				check(int(_got("status", "status")[0].get("lb", 0)) == 1, "status says lb:1")
				_ws("so_a", {"t":"so", "k":"hi", "v":Net.VERSION, "acct":accts.alice.acct, "key":accts.alice.key})
				_ws("so_b", {"t":"so", "k":"hi", "v":Net.VERSION, "acct":accts.bob.acct, "key":accts.bob.key})
				_go("friends")
			elif t_phase > 10.0:
				check(false, "accounts within 10 s")
				_finish()
		"friends":
			var step := int(notes.get("fs", 0))
			var me_a := (raw.so_a.msgs as Array).filter(func(m): return str(m.get("k", "")) == "me")
			var me_b := (raw.so_b.msgs as Array).filter(func(m): return str(m.get("k", "")) == "me")
			if step == 0 and not me_a.is_empty() and not me_b.is_empty():
				(raw.so_a.ws as WebSocketPeer).put_packet(Net.encode({"t":"so", "k":"add", "pid":str(me_b[0].pid)}))
				notes.fs = 1
				notes.at = t_phase
				notes.pid_a = str(me_a[0].pid)
			elif step == 1 and t_phase - float(notes.at) > 0.5:
				(raw.so_b.ws as WebSocketPeer).put_packet(Net.encode({"t":"so", "k":"add", "pid":str(notes.pid_a)}))
				notes.fs = 2
				notes.at = t_phase
			elif step == 2 and t_phase - float(notes.at) > 0.5:
				_ws("play_a", {"t":"hello", "v":Net.VERSION, "five":Net.FIVE, "name":"x", "build":"0.31.119-fatebound", "acct":accts.alice.acct, "key":accts.alice.key})
				_go("match")
			elif t_phase > 10.0:
				check(false, "friends within 10 s")
				_finish()
		"match":
			var ended := false
			for m in _got("play_a", "s"):
				for e in m.get("e", []):
					ended = ended or str(e.get("k", "")) == "end"
			if ended:
				(raw.play_a.ws as WebSocketPeer).close()
				_go("paid")
			elif t_phase > 20.0:
				check(false, "the online match ended within 20 s")
				_finish()
		"paid":
			if t_phase > 1.0 and not notes.has("fetching"):
				notes.fetching = true
				LbFetch.start(root, "ws://127.0.0.1:%d" % port, accts.alice.acct, accts.alice.key, func(r): notes.ans = r)
				LbFetch.start(root, "ws://127.0.0.1:%d" % port, accts.alice.acct, "f".repeat(64), func(r): notes.bad = r)
			if notes.has("ans") and notes.has("bad"):
				var a: Dictionary = notes.ans
				var top: Array = a.get("top", [])
				check(str(a.get("t", "")) == "lb" and top.size() == 1 and str(top[0].name) == "Alice" and int(top[0].m) == 1 and bool(top[0].get("you", false)),
					"the online match put Alice on the board (%s)" % str(top))
				check(int(a.me.get("rank", 0)) == 1 and (a.friends as Array).size() == 1 and str(a.friends[0].name) == "Alice",
					"her own row; her friend Bob hasn't played, so the friends tab is just her")
				check((notes.bad as Dictionary).is_empty(), "a wrong key: nothing")
				_go("app")
			elif t_phase > 15.0:
				check(false, "leaderboard answers within 15 s")
				_finish()
		"app":
			var base := "user://lbtest-app-%d" % Time.get_ticks_usec()
			var p = Profile.new(base + "-profile.json", base + "-none.json")
			p.load_or_create()
			p.d.name = "Alice"
			p.d.account = {"id":accts.alice.acct, "key":accts.alice.key, "seq":0}
			p.d.tutorial_done = true
			p.save()
			app = App.new()
			app.profile_path = base + "-profile.json"
			app.legacy_path = base + "-none.json"
			root.add_child(app)
			app.size = Vector2(420, 933)
			_go("home")
		"home":
			if t_phase > 1.0:
				# 0.31.170 (the online 5v5): RANKS on Home again (0.31.164-169 had none -- no online matches to count)
				check(not _find(app, func(n): return str(n.name) == "FirstWinTag").is_empty(), "the first win of the day is a tag on PLAY")
				_btn("home_menu").pressed.emit()          # 0.31.194: RANKS is in the top bar's menu
				check(_btn("side_ranks") != null and _btn("side_first_win") == null, "Home's menu: RANKS (the week's board of online matches)")
				_btn("side_ranks").pressed.emit()
				check(app.modal is LeaderboardPanel, "the LEADERBOARD window opens")
				_go("panel")
		"panel":
			var rows := _find(app.modal, func(n): return str(n.name).begins_with("LbRow") and n.has_meta("rank"))
			if not rows.is_empty():
				check(rows.size() == 1 and bool(rows[0].get_meta("you")) and int(rows[0].get_meta("rank")) == 1, "the window: her row, rank 1, marked")
				var labels := _find(rows[0], func(n): return n is Label).map(func(l): return (l as Label).text)
				check(labels.has("Alice  (you)") and labels.has("1"), "with her name and numbers: %s" % str(labels))
				_shot("leaderboard_week")
				_btn("lb_tab_friends").pressed.emit()
				_go("friends_tab")
			elif t_phase > 12.0:
				check(false, "the window filled within 12 s (data %s)" % str(app.modal.data if app.modal is LeaderboardPanel else "?"))
				_finish()
		"friends_tab":
			if t_phase > 0.3:
				var rows := _find(app.modal, func(n): return str(n.name).begins_with("LbRow") and n.has_meta("rank"))
				check(app.modal.tab == "friends" and rows.size() == 1 and _btn("lb_friends") != null, "FRIENDS tab: her row and a FRIENDS button")
				_shot("leaderboard_friends")
				_finish()
	return false

func _finish() -> void:
	if pid > 0:
		OS.kill(pid)
		OS.execute("kill", ["-9", str(pid)])
		pid = -1
	print("LEADERBOARD_PASS" if fails.is_empty() else "LEADERBOARD_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
