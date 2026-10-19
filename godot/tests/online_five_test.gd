extends SceneTree
# 0.31.170 (the online 5v5, step 2 of the plan): the REAL server (port 8121) and phones, real time.
#  1. The server says it has the online 5v5 ("five":1 in "status", "ver", the lobby and the welcome); an app from before
#     it is refused as too old (bye "version" one ahead, close 4001 -- its Update screen).
#  2. Heroes: Alice bought a sold hero (an op the server replays) and plays it; Bob asks for it without owning it and
#     plays his seat's own hero; Carl (no account) asks for one of this week's free heroes (0.31.185, the rotation) and
#     gets it; no side has a hero twice. (The sold hero: the first not free this week, so the test holds any week.)
#  3. Every phone's mirror, brought up from its keyframe and the snapshots after it, holds exactly what every other
#     phone's does at the same snapshot (units coming and going, every key the snapshot carries, towers, Kings, gates,
#     camps, zones, traps, wards, projectiles); Erin, who comes in mid-match, too.
#  4. Alice's buttons through the server: an item bought in her keep and sold back, a ward, bad arguments ignored, her
#     stick moves her.
#  5. The real game client (SiegeMode) as the Archmage: its hero, its view, its WARD and SHOP buttons through the server.
#  6. The match ends on every phone with the same winner, and Alice's account is paid by the server.
#  7. A server from before the online 5v5 (a stand-in on 8122 answering the lobby without "five"): the client leaves on
#     its own and says why (exit_note "no_five"), for Home to start a match against bots instead.
#   godot --headless --path godot -s res://tests/online_five_test.gd
const Mode = preload("res://scripts/siege/siege_mode.gd")
const Net = preload("res://scripts/siege/siege_net.gd")
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Profile = preload("res://scripts/meta/profile.gd")
const Eco = preload("res://scripts/meta/economy.gd")
var SOLD := ""                         # a sold hero not free this week (0.31.185)
var FREE := ""                         # one of this week's free ones

var fails: Array = []
var port := 8121
var fake_port := 8122
var pid := -1
var phase := "boot"
var t_phase := 0.0
var t_all := 0.0
var socks := {}                          # name -> {ws, first, sent, msgs, sim, welcome, draft_hid, tm, n}
var accts := {}
var notes := {}
var compares := 0
var mismatches := 0
var mode
var mode_exited := false
var old_mode
var old_exited := false
var fake: TCPServer
var fake_peers: Array = []

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _init() -> void:
	var now := int(Time.get_unix_time_from_system())
	FREE = str(Eco.free_heroes(now)[0])
	var sold: Array = Eco.HERO_PRICES.keys().filter(func(h): return not Eco.free_heroes(now).has(h))
	sold.sort()
	SOLD = str(sold[0])
	var sd := OS.get_user_data_dir().path_join("five-srv-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(sd)
	OS.set_environment("SIEGE_PORT", str(port))
	OS.set_environment("SIEGE_HOST", "127.0.0.1")
	OS.set_environment("SIEGE_LOBBY", "1.5")
	OS.set_environment("SIEGE_TEST_MATCH_S", "40")
	OS.set_environment("SIEGE_IDLE_BOT", "600")
	OS.set_environment("SIEGE_IDLE_KICK", "900")
	OS.set_environment("STATE_DIRECTORY", sd)
	OS.set_environment("SIEGE_MIN_BUILD", "off")
	pid = OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://server/siege_server.gd"])
	check(pid > 0, "server process started")

func _go(p: String) -> void:
	phase = p
	t_phase = 0.0

func _open(name: String, first: Dictionary) -> void:
	var ws := WebSocketPeer.new()
	ws.inbound_buffer_size = 1 << 21
	ws.connect_to_url("ws://127.0.0.1:%d" % port)
	socks[name] = {"ws":ws, "first":first, "sent":false, "msgs":[], "sim":null, "welcome":{}, "draft_hid":"", "tm":-1.0, "n":0,
		"dialed":Time.get_ticks_msec() / 1000.0}

func _got(name: String, kind: String) -> Array:
	return (socks.get(name, {}).get("msgs", []) as Array).filter(func(m): return str(m.get("t", "")) == kind)

func _send(name: String, msg: Dictionary) -> void:
	var ws: WebSocketPeer = socks[name].ws
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.put_packet(Net.encode(msg))

func _me(name: String) -> Dictionary:
	var c: Dictionary = socks.get(name, {})
	if c.is_empty() or c.sim == null:
		return {}
	return c.sim.by_id.get(str(c.welcome.get("you", "")), {})

var _keep_clock := 0.0

func _poll() -> void:
	for n in socks:
		var c: Dictionary = socks[n]
		var ws: WebSocketPeer = c.ws
		ws.poll()
		var now_s := Time.get_ticks_msec() / 1000.0
		if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED and not bool(c.sent) and now_s - float(c.dialed) > 0.5:
			c.dialed = now_s                       # (the server may not be listening yet)
			ws.connect_to_url("ws://127.0.0.1:%d" % port)
			continue
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN and not bool(c.sent):
			ws.put_packet(Net.encode(c.first))
			c.sent = true
		while ws.get_available_packet_count() > 0:
			var m := Net.decode(ws.get_packet())
			match str(m.get("t", "")):
				"welcome":
					c.welcome = m
					var s = Sim.new()
					s.setup(int(m.get("team_size", 5)), int(m.get("seed", 1)), -1)
					s.setup_moba("", int(m.get("seed", 1)))
					c.draft_hid = str(s.by_id.get(str(m.get("you", "")), {}).get("hid", ""))
					c.sim = s
				"s":
					if c.sim != null:
						if c.n == 0:
							c.kf = bool(m.get("kf", false))
						Net.apply(c.sim, m, "")
						c.tm = float(m.get("tm", -1.0))
						c.n = int(c.n) + 1
						m = {"t":"s", "tm":m.get("tm"), "e":m.get("e", [])}      # (kept small)
			(c.msgs as Array).append(m)
	# the mirrors at the same snapshot must agree
	var names := socks.keys().filter(func(n): return socks[n].sim != null and int(socks[n].n) > 0 and str(n) != "alice")
	var a: Dictionary = socks.get("alice", {})
	if not a.is_empty() and a.sim != null and int(a.n) > 0:
		for n in names:
			var b: Dictionary = socks[n]
			if float(b.tm) == float(a.tm) and int(b.welcome.get("match", -1)) == int(a.welcome.get("match", -2)):
				compares += 1
				_compare(a.sim, b.sim, "%s vs alice t=%.2f" % [n, a.tm])

func _compare(x, y, at: String) -> void:
	var before := mismatches
	if x.units.size() != y.units.size():
		_mis("%s: %d units vs %d" % [at, y.units.size(), x.units.size()])
		return
	for i in x.units.size():
		var ux: Dictionary = x.units[i]
		var uy: Dictionary = y.units[i]
		if str(ux.id) != str(uy.id):
			_mis("%s: unit %d %s vs %s" % [at, i, uy.id, ux.id])
			return
		for k in ux:
			if Net._client_key(str(k)) and not Net.FAST_KEYS.has(k):
				continue
			var vx: Variant = ux[k]
			var vy: Variant = uy.get(k, null)
			if k == "pos":
				vx = ux.get("net_to", ux.pos)
				vy = uy.get("net_to", uy.pos)
			if typeof(vx) != typeof(vy) or vx != vy:
				_mis("%s: %s.%s %s vs %s" % [at, ux.id, k, str(vy), str(vx)])
		for k in uy:
			if not ux.has(k) and not Net._client_key(str(k)):
				_mis("%s: %s has %s, alice's hasn't" % [at, uy.id, k])
	var ox: Array = Net._objs(x)
	var oy: Array = Net._objs(y)
	for j in ox.size():
		if str(ox[j][1]) != str(oy[j][1]):
			_mis("%s: %s differ" % [at, ox[j][0]])
	var bx := Net._blobs(x)
	var by := Net._blobs(y)
	for k in bx:
		if str(bx[k]) != str(by.get(k)):
			_mis("%s: %s differ" % [at, k])
	var px: Array = x.projectiles.filter(func(p): return not bool(p.get("ghost", false))).map(func(p): return [p.id, p.kind, p.net_to, p.get("big", false)])
	var py: Array = y.projectiles.filter(func(p): return not bool(p.get("ghost", false))).map(func(p): return [p.id, p.kind, p.net_to, p.get("big", false)])
	if px != py:
		_mis("%s: projectiles differ (%d vs %d)" % [at, py.size(), px.size()])
	if x.score != y.score or x.kills != y.kills or x.ended != y.ended or x.winner != y.winner:
		_mis("%s: score/kills/end differ" % at)
	if mismatches > before and mismatches <= 12:
		pass

func _mis(why: String) -> void:
	mismatches += 1
	if mismatches <= 12:
		print("MISMATCH ", why)

func _hello(name: String, extra: Dictionary) -> Dictionary:
	var h := {"t":"hello", "v":Net.VERSION, "five":Net.FIVE, "name":name, "build":"0.31.170-fatebound", "pred":false, "ask_next":true}
	h.merge(extra, true)
	return h

func _process(delta: float) -> bool:
	t_phase += delta
	t_all += delta
	_poll()
	_fake_tick()
	_keep_clock += delta                     # (a seated phone sends its inputs all the time: a silent one is let go after 8 s)
	if _keep_clock >= 0.5 and phase != "walk":
		_keep_clock = 0.0
		for n in ["alice", "bob", "carl", "erin"]:
			if socks.has(n) and socks[n].sim != null:
				_send(n, {"t":"in", "m":Vector2.ZERO, "h":false, "b":false})
	if t_all > 170.0:
		check(false, "finished within 170 s (stuck in %s)" % phase)
		_finish()
		return true
	match phase:
		"boot":
			if t_phase > 2.0:
				var imp := Profile.defaults()
				imp.name = "Alice"
				imp.gold = 5000
				_open("eco_alice", {"t":"eco", "v":Net.VERSION, "new":true, "import":imp})
				var imp2 := Profile.defaults()
				imp2.name = "Bob"
				_open("eco_bob", {"t":"eco", "v":Net.VERSION, "new":true, "import":imp2})
				_open("status", {"t":"status"})
				_open("ver", {"t":"ver", "v":Net.VERSION})
				var old := _hello("OldApp", {})
				old.erase("five")
				_open("old", old)
				_go("accounts")
		"accounts":
			for n in ["alice", "bob"]:
				var e := _got("eco_" + n, "eco")
				if not e.is_empty() and not accts.has(n):
					accts[n] = {"acct":str(e[0].acct), "key":str(e[0].key)}
			if accts.size() == 2 and not notes.has("bought"):
				notes.bought = true
				_open("eco_buy", {"t":"eco", "v":Net.VERSION, "acct":accts.alice.acct, "key":accts.alice.key,
					"ops":[{"s":1, "op":"buy_hero", "a":[SOLD]}]})
			var eb := _got("eco_buy", "eco")
			if not eb.is_empty():
				var res: Array = eb[0].get("results", [])
				check(bool(eb[0].get("ok", false)) and not res.is_empty() and bool(res[0].get("ok", false))
					and (eb[0].get("profile", {}).get("heroes", []) as Array).has(SOLD), "Alice bought the %s on the server (%s)" % [SOLD, str(res)])
				var st := _got("status", "status")
				var vr := _got("ver", "ver")
				check(not st.is_empty() and int(st[0].get("five", 0)) == Net.FIVE, "status says five:1")
				check(not vr.is_empty() and int(vr[0].get("five", 0)) == Net.FIVE, "ver says five:1")
				var ob := _got("old", "bye")
				var ows: WebSocketPeer = socks.old.ws
				check(not ob.is_empty() and str(ob[0].why) == "version" and int(ob[0].need) == Net.VERSION + 1
					and Net.version_verdict(int(ob[0].need)) == "update", "an app without the online 5v5 is refused as too old: its Update screen (%s)" % str(ob))
				check(_got("old", "welcome").is_empty() and _got("old", "lobby").is_empty(), "...and never seated")
				notes.old_code = ows.get_close_code()
				_go("play")
			elif t_phase > 15.0:
				check(false, "accounts within 15 s")
				_finish()
		"play":
			_open("alice", _hello("Alice", {"acct":accts.alice.acct, "key":accts.alice.key, "hero":SOLD}))
			_open("bob", _hello("Bob", {"acct":accts.bob.acct, "key":accts.bob.key, "hero":SOLD}))
			_open("carl", _hello("Carl", {"hero":FREE}))
			mode = Mode.new()
			mode.online = true
			mode.net_url = "ws://127.0.0.1:%d/fatebound/siege/ws" % port
			mode.player_name = "Mona"
			mode.moba_hero = "archmage"
			mode.exited.connect(func(): mode_exited = true)
			root.add_child(mode)
			_go("seated")
		"seated":
			var lob := _got("alice", "lobby")
			if not lob.is_empty() and not notes.has("lobby_five"):
				notes.lobby_five = true
				check(int(lob[0].get("five", 0)) == Net.FIVE, "the lobby says five:1")
			var all_in: bool = ["alice", "bob", "carl"].all(func(n): return socks[n].sim != null and int(socks[n].n) >= 3)
			if all_in and mode.net_state == "playing" and mode.sim != null and not _mode_me().is_empty():
				var wa: Dictionary = socks.alice.welcome
				check(int(wa.get("five", 0)) == Net.FIVE, "the welcome says five:1")
				check(bool(socks.alice.kf) and bool(socks.bob.kf) and bool(socks.carl.kf), "each phone's first snapshot is a keyframe")
				check(str(wa.hero) == SOLD and str(_me("alice").get("hid", "")) == SOLD, "Alice plays the hero she bought (welcome %s, mirror %s)" % [wa.hero, _me("alice").get("hid", "")])
				var wb: Dictionary = socks.bob.welcome
				check(str(wb.hero) == str(socks.bob.draft_hid) and str(_me("bob").get("hid", "")) == str(wb.hero),
					"Bob asked for it without owning it: he plays his seat's own hero (%s)" % wb.hero)
				check(str(socks.carl.welcome.hero) == FREE and str(_me("carl").get("hid", "")) == FREE, "Carl (no account) plays %s, free this week" % FREE)
				check(str(mode.sim.by_id[mode.hud.player_id].get("hid", "")) == "archmage", "the game client plays the Archmage it picked")
				for t in 2:
					var hids: Array = socks.alice.sim.units.filter(func(u): return bool(u.get("hero", false)) and int(u.team) == t).map(func(u): return str(u.hid))
					var uniq := {}
					for h in hids:
						uniq[h] = true
					check(hids.size() == 5 and uniq.size() == 5, "side %d: five heroes, none twice (%s)" % [t, str(hids)])
				notes.alice_p0 = _me("alice").pos
				notes.gold0 = float(_me("alice").get("gold", 0.0))
				# Alice in her keep at the start: buys boots; bad arguments are ignored
				_send("alice", {"t":"in", "m":Vector2.ZERO, "a":"shop_buy", "arg":"boots"})
				_send("alice", {"t":"in", "m":Vector2.ZERO, "a":"shop_buy", "arg":123})
				_send("alice", {"t":"in", "m":Vector2.ZERO, "a":"pick", "arg":9})
				_send("alice", {"t":"in", "m":Vector2.ZERO, "a":"spell", "arg":"x"})
				_send("alice", {"t":"in", "m":Vector2.ZERO, "a":"nuke", "arg":null})
				# the game client's buttons
				notes.mode_gold0 = float(_mode_me().get("gold", 0.0))
				mode._on_action("shop_buy:boots")
				mode._on_action("ward")
				_go("bought")
			elif t_phase > 25.0:
				check(false, "everyone seated within 25 s (mode %s)" % str(mode.net_state))
				_finish()
		"bought":
			var me := _me("alice")
			var mm := _mode_me()
			var items: Array = me.get("items", [])
			var ward_ok: bool = socks.alice.sim.moba.vision.wards.any(func(w): return str(w.owner) == str(mode.hud.player_id))
			if items.has("boots") and (mm.get("items", []) as Array).has("boots") and ward_ok and t_phase > 1.0:
				check(float(me.gold) < float(notes.gold0), "Alice's boots, bought in her keep: on every phone, gold down (%.0f -> %.0f)" % [notes.gold0, me.gold])
				check(str(socks.bob.sim.by_id[str(socks.alice.welcome.you)].get("items", [])) == str(items), "Bob's phone shows Alice's boots too")
				check(true, "the game client's SHOP and WARD went through the server (its boots, its ward on Alice's phone)")
				_send("alice", {"t":"in", "m":Vector2.ZERO, "a":"shop_sell", "arg":0})
				_send("alice", {"t":"in", "m":Vector2.ZERO, "a":"ward"})
				_go("sold")
			elif t_phase > 6.0:
				check(false, "the buys and the ward within 6 s (alice items %s, client items %s, ward %s)" % [str(items), str(mm.get("items", [])), str(ward_ok)])
				_go("sold")
		"sold":
			var me2 := _me("alice")
			var wards_a: Array = socks.alice.sim.moba.vision.wards.filter(func(w): return str(w.owner) == str(socks.alice.welcome.you))
			if (me2.get("items", []) as Array).is_empty() and not wards_a.is_empty():
				check(true, "Alice sold them back and placed a ward (on her phone: %s)" % str(wards_a[0].p))
				check(socks.carl.sim.moba.vision.wards.any(func(w): return str(w.owner) == str(socks.alice.welcome.you)), "...on Carl's phone too")
				notes.walk_from = me2.pos
				_go("walk")
			elif t_phase > 6.0:
				check(false, "sold and warded within 6 s (items %s, wards %d)" % [str(me2.get("items", [])), wards_a.size()])
				_go("walk")
		"walk":
			notes.walk_clock = float(notes.get("walk_clock", 0.0)) + delta
			if float(notes.walk_clock) >= 0.1:
				notes.walk_clock = 0.0
				_send("alice", {"t":"in", "m":Vector2(0, -1) if int(_me("alice").team) == 0 else Vector2(0, 1), "h":false, "b":false})
			if t_phase > 2.0:
				_send("alice", {"t":"in", "m":Vector2.ZERO})
				var moved: float = (_me("alice").pos as Vector2).distance_to(notes.walk_from)
				check(moved > 3.0, "Alice's stick moves her on her phone (%.1f m)" % moved)
				_open("erin", _hello("Erin", {"hero":"priest"}))
				_go("erin")
		"erin":
			if socks.erin.sim != null and int(socks.erin.n) >= 5:
				check(bool(socks.erin.kf), "Erin comes in mid-match: a keyframe first")
				check(str(_me("erin").get("hid", "")) != "", "...seated on a hero (%s)" % str(_me("erin").get("hid", "")))
				_go("match")
			elif t_phase > 15.0:
				check(false, "Erin seated within 15 s")
				_go("match")
		"match":
			if socks.alice.sim.ended and not notes.has("ended_at"):
				notes.ended_at = t_phase
			var ended: bool = socks.alice.sim.ended
			if ended and ["bob", "carl", "erin"].all(func(n): return socks[n].sim != null and socks[n].sim.ended) \
					and (mode.sim.ended or t_phase - float(notes.get("ended_at", t_phase)) > 3.0):
				var w := int(socks.alice.sim.winner)
				check(["bob", "carl", "erin"].all(func(n): return int(socks[n].sim.winner) == w), "the match ends on every phone with the same winner (%d)" % w)
				check(mode.sim != null and mode.sim.ended and int(mode.sim.winner) == w, "...and on the game client (%s, %s at %.1f s)" % [str(mode.sim.ended),
					mode.net_state, mode.sim.time])
				check(socks.alice.sim.units.size() > 10, "minions marched (%d units at the end)" % socks.alice.sim.units.size())
				_go("paid")
			elif t_phase > 60.0:
				check(false, "the match ended within 60 s")
				_go("paid")
		"paid":
			if t_phase > 1.5 and not notes.has("pulled"):
				notes.pulled = true
				_open("eco_after", {"t":"eco", "v":Net.VERSION, "acct":accts.alice.acct, "key":accts.alice.key, "ops":[]})
			var ea := _got("eco_after", "eco")
			if not ea.is_empty():
				var stt: Dictionary = ea[0].get("profile", {}).get("stats", {})
				check(int(stt.get("matches", 0)) == 1, "the server paid Alice's account for the online match (matches %d)" % int(stt.get("matches", 0)))
				check(compares >= 100 and mismatches == 0, "every phone's mirror agreed with Alice's at the same snapshot (%d comparisons, %d mismatches)" % [compares, mismatches])
				_old_server()
				_go("old")
			elif t_phase > 12.0:
				check(false, "the account answered within 12 s")
				_old_server()
				_go("old")
		"old":
			if old_exited and old_mode != null:
				check(old_mode.exit_note == "no_five" and old_mode.replay_hero == "druid",
					"a server without the online 5v5: the client leaves on its own (note %s, replay %s) -- Home starts a match against bots" % [old_mode.exit_note, old_mode.replay_hero])
				_finish()
			elif t_phase > 15.0:
				check(false, "left the old server within 15 s (state %s, note %s)" % [str(old_mode.net_state), str(old_mode.exit_note)])
				_finish()
	return false

func _mode_me() -> Dictionary:
	return mode.sim.by_id.get(mode.hud.player_id, {}) if mode != null and mode.sim != null else {}

# ---------------- a server from before the online 5v5 (a stand-in) ----------------
func _old_server() -> void:
	fake = TCPServer.new()
	check(fake.listen(fake_port, "127.0.0.1") == OK, "the stand-in old server listens on %d" % fake_port)
	old_mode = Mode.new()
	old_mode.online = true
	old_mode.net_url = "ws://127.0.0.1:%d/" % fake_port
	old_mode.player_name = "Olly"
	old_mode.moba_hero = "druid"
	old_mode.exited.connect(func(): old_exited = true)
	root.add_child(old_mode)

func _fake_tick() -> void:
	if fake == null:
		return
	while fake.is_connection_available():
		var ws := WebSocketPeer.new()
		ws.accept_stream(fake.take_connection())
		fake_peers.append({"ws":ws, "said":false})
	for p in fake_peers:
		var ws: WebSocketPeer = p.ws
		ws.poll()
		while ws.get_available_packet_count() > 0:
			var m := Net.decode(ws.get_packet())
			if str(m.get("t", "")) == "hello" and not bool(p.said):
				p.said = true
				# (0.31.169's server: the same protocol, a lobby without "five")
				ws.put_packet(Net.encode({"t":"lobby", "left":10.0, "wait":20.0, "names":["Olly"], "tt":[""], "ct":[""], "in_match":0,
					"online":1, "slots":10, "running":false, "match":0, "me":0}))

func _finish() -> void:
	if pid > 0:
		OS.kill(pid)
		OS.execute("kill", ["-9", str(pid)])
		pid = -1
	print("ONLINE_FIVE_PASS" if fails.is_empty() else "ONLINE_FIVE_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
