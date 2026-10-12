extends SceneTree
# 0.31.111 (Kevin: "Build a global chat and players can click a name and have option to add friend to a friends list.
# They can then group up and form a party. Also add the quick chat pings"). REAL time for part 2 (the server runs as
# its own process, port 8094).
#  1. server/social.gd on its own (fake sockets): the word filter; hello needs the account's key; global chat to
#     everyone, the rate limits, repeats, muted.txt; requests, accepting, declining, unfriending; a block hides chat
#     and swallows requests; reports land in reports.jsonl; invites only to online friends, joining, party chat, the
#     leader's PLAY reaching the others, leaving / kicking, a party of one ending, invites running out, a member away
#     for 3 minutes leaving; social.json kept and read back.
#  2. end to end: two phones' Social nodes (scripts/meta/social.gd) against the real server -- accounts, friends,
#     a party, "go", both match sockets seated on ONE team, a friend shown "in a match", quick chat to the side (and
#     its 2-second limit), "Good game!" to everyone.
#   godot --headless --path godot -s res://tests/social_test.gd
const Social = preload("res://server/social.gd")
const ClientSocial = preload("res://scripts/meta/social.gd")
const Profile = preload("res://scripts/meta/profile.gd")
const Net = preload("res://scripts/siege/siege_net.gd")
const Sim = preload("res://scripts/siege/siege_sim.gd")

var fails: Array = []

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

class FakeEco:
	var accts := {}
	func add(id: String, key: String, name: String) -> void:
		accts[id] = {"key":key, "name":name}
	func open(id: String, key: String) -> Dictionary:
		return {"id":id} if accts.has(id) and str(accts[id].key) == key else {}
	func public_of(id: String) -> Dictionary:
		return {"name":str(accts[id].name), "title":""} if accts.has(id) else {}

var inbox := {}                          # socket id -> [messages]
var closed := []

func got(cid: int, k: String) -> Array:
	return (inbox.get(cid, []) as Array).filter(func(m): return str(m.get("k", "")) == k)

func last(cid: int, k: String) -> Dictionary:
	var l := got(cid, k)
	return l[l.size() - 1] if not l.is_empty() else {}

func clear() -> void:
	inbox = {}

func _init() -> void:
	_part1()
	_start_server()

# ---------------- 1. social.gd on its own ----------------
func _part1() -> void:
	# --- the filter
	check(Social.clean_text("fuck you") == "**** you", "a bad word becomes stars: %s" % Social.clean_text("fuck you"))
	check(Social.clean_text("Sh1t happens!!") == "***** happens!!" or Social.clean_text("Sh1t happens!!").begins_with("****"), "l33t spelling too: %s" % Social.clean_text("Sh1t happens!!"))
	check(Social.clean_text("fuuuuck") == "*******" or Social.clean_text("fuuuuck").begins_with("***"), "stretched letters too")
	check(Social.clean_text("join www.free-gems.com now") == "join ******** now" or not Social.clean_text("join www.free-gems.com now").contains("free"), "links are masked: %s" % Social.clean_text("join www.free-gems.com now"))
	check(Social.clean_text("the class assassin passes the grass") == "the class assassin passes the grass", "ordinary words stay")
	check(Social.clean_text("a​b\nc") == "a b c" and Social.clean_text("x".repeat(300)).length() == Social.CHAT_MAX, "hidden characters out, at most %d" % Social.CHAT_MAX)
	check(Social.clean_name("  ") == "Player" and Social.clean_name("BigShitLord") != "BigShitLord", "names are filtered too")
	# --- three players
	var dir := OS.get_user_data_dir().path_join("socialtest-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(dir)
	var eco := FakeEco.new()
	var ids := []
	for n in ["Alice", "Bob", "Cara"]:
		var id := ("%020x" % (ids.size() + 1))
		eco.add(id, "k".repeat(64), n)
		ids.append(id)
	var s = Social.new(dir, eco)
	s.now_override = 1791000000
	s.send_fn = func(cid, msg):
		var l: Array = inbox.get(cid, [])
		l.append(msg)
		inbox[cid] = l
	s.close_fn = func(cid): closed.append(cid)
	var matching := {}
	s.in_match_fn = func(acct): return matching.has(acct)
	check(not s.hello(9, {"k":"hi", "acct":ids[0], "key":"x".repeat(64)}) and str(last(9, "bye").get("why", "")) == "auth", "a wrong key is turned away")
	check(s.hello(1, {"k":"hi", "acct":ids[0], "key":"k".repeat(64)}) and s.hello(2, {"k":"hi", "acct":ids[1], "key":"k".repeat(64)}) \
		and s.hello(3, {"k":"hi", "acct":ids[2], "key":"k".repeat(64)}), "three players in")
	var A := Social.pid_of(ids[0])
	var B := Social.pid_of(ids[1])
	var C := Social.pid_of(ids[2])
	check(str(last(1, "me").get("pid", "")) == A and A.length() == 10 and not A.contains(ids[0]), "each has a public id (not their account id): %s" % A)
	# --- global chat
	clear()
	s.handle(1, {"k":"chat", "ch":"global", "x":"hello  fuck everyone"})
	var m2: Dictionary = last(2, "chat").get("m", {})
	check(str(m2.get("x", "")) == "hello **** everyone" and str(m2.get("n", "")) == "Alice" and not last(3, "chat").is_empty() and not last(1, "chat").is_empty(),
		"a global line reaches everyone, filtered, with the sender's name: %s" % str(m2.get("x", "")))
	clear()
	s.handle(1, {"k":"chat", "ch":"global", "x":"again"})
	check(got(2, "chat").is_empty() and bool(last(1, "note").get("bad", false)), "too soon after the last line: refused")
	s.tick(1.5)
	clear()
	s.handle(1, {"k":"chat", "ch":"global", "x":"hello fuck everyone"})
	check(got(2, "chat").is_empty() and str(last(1, "note").get("x", "")).contains("just said"), "the same line twice: refused")
	for i in 6:
		s.tick(1.3)
		s.handle(1, {"k":"chat", "ch":"global", "x":"line %d" % i})
	check(str(last(1, "note").get("x", "")).contains("Slow down"), "6 lines in 20 s, the 7th waits")
	var f := FileAccess.open(dir.path_join("muted.txt"), FileAccess.WRITE)
	f.store_string("# muted\n%s\n" % B)
	f.close()
	s.tick(Social.MUTE_RELOAD)
	clear()
	s.handle(2, {"k":"chat", "ch":"global", "x":"hi"})
	check(got(1, "chat").is_empty() and str(last(2, "note").get("x", "")).contains("can't chat"), "a player in muted.txt can't chat")
	DirAccess.remove_absolute(dir.path_join("muted.txt"))
	s.tick(Social.MUTE_RELOAD)
	# --- friends
	clear()
	s.handle(1, {"k":"add", "pid":B})
	check(str(last(2, "req").get("from", {}).get("n", "")) == "Alice" and _pids(last(1, "friends"), "rout").has(B) and _pids(last(2, "friends"), "rin").has(A),
		"a friend request: Bob sees it, Alice sees it sent")
	clear()
	s.handle(2, {"k":"add", "pid":A})
	check(_pids(last(1, "friends"), "friends").has(B) and _pids(last(2, "friends"), "friends").has(A) and str(last(1, "note").get("x", "")).contains("accepted"),
		"Bob adds Alice back: friends, and she's told")
	var card: Dictionary = (last(1, "friends").get("friends", []) as Array)[0]
	check(str(card.st) == "online", "a friend online shows online")
	clear()
	matching[ids[1]] = true
	s.acct_changed(ids[1])
	check(str(last(1, "pres").get("c", {}).get("st", "")) == "match", "a friend in a match shows in a match")
	matching.erase(ids[1])
	s.acct_changed(ids[1])
	s.handle(1, {"k":"add", "pid":C})
	clear()
	s.handle(3, {"k":"decline", "pid":A})
	check(not _pids(last(1, "friends"), "rout").has(C) and not _pids(last(3, "friends"), "rin").has(A), "a declined request goes from both lists")
	s.handle(1, {"k":"add", "pid":"ffffffffff"})
	check(str(last(1, "note").get("x", "")).contains("No player"), "an unknown friend code: no player")
	# --- block
	clear()
	s.handle(3, {"k":"block", "pid":A})
	s.tick(2.0)
	s.handle(1, {"k":"chat", "ch":"global", "x":"can cara see this"})
	check(got(3, "chat").is_empty() and not got(2, "chat").is_empty(), "a blocked player's lines never reach the one who blocked them")
	clear()
	s.handle(1, {"k":"add", "pid":C})
	check(got(3, "req").is_empty() and _pids(last(1, "friends"), "rout").has(C), "a request to someone who blocked you looks sent but never arrives")
	s.handle(1, {"k":"unfriend", "pid":C})
	# --- report
	s.handle(3, {"k":"report", "pid":A, "why":"language"})
	var rep_txt := FileAccess.get_file_as_string(dir.path_join("reports.jsonl"))
	check(rep_txt.contains("\"about\":\"%s\"" % A) and rep_txt.contains("can cara see this") and rep_txt.contains("language"), "a report lands in reports.jsonl with their last lines")
	# --- parties
	clear()
	s.handle(1, {"k":"invite", "pid":C})
	check(str(last(1, "note").get("x", "")).contains("only invite friends") and got(3, "inv").is_empty(), "only friends can be invited")
	s.handle(1, {"k":"invite", "pid":B})
	var inv: Dictionary = last(2, "inv")
	var pa := str(inv.get("party", ""))
	check(pa != "" and str(inv.get("from", {}).get("n", "")) == "Alice" and (last(1, "party").get("party", {}).get("pending", []) as Array).size() == 1,
		"Alice invites Bob: he gets it, her party shows him pending")
	check(s.party_for(ids[0]) == pa, "a party starts with the first invite")
	clear()
	s.handle(2, {"k":"join", "party":pa})
	var pb: Dictionary = last(2, "party").get("party", {})
	check((pb.get("members", []) as Array).size() == 2 and str(pb.leader) == A and s.party_for(ids[1]) == pa, "Bob joins: two in the party, Alice leads")
	check(str(last(1, "chat").get("m", {}).get("x", "")).contains("joined"), "the party is told in its chat")
	clear()
	s.tick(2.0)
	s.handle(2, {"k":"chat", "ch":"party", "x":"ready"})
	check(str(last(1, "chat").get("m", {}).get("ch", "")) == "party" and got(3, "chat").is_empty(), "party chat stays in the party")
	clear()
	s.handle(2, {"k":"play"})
	check(got(1, "go").is_empty(), "only the leader starts")
	s.handle(1, {"k":"play"})
	check(str(last(2, "go").get("party", "")) == pa and got(1, "go").is_empty(), "the leader's PLAY sends Bob into the match")
	clear()
	s.handle(1, {"k":"kick", "pid":B})
	check((last(2, "party").get("party", {}) as Dictionary).is_empty() and (last(1, "party").get("party", {}) as Dictionary).is_empty() and s.party_for(ids[0]) == "",
		"kicked: Bob is out, and a party of one is no party")
	s.handle(1, {"k":"invite", "pid":B})
	var pa2 := str(last(2, "inv").get("party", ""))
	s.tick(Social.INVITE_LIFE + 1.0)
	clear()
	s.handle(2, {"k":"join", "party":pa2})
	check(s.party_for(ids[0]) == "" and s.party_for(ids[1]) == "" and str(last(2, "note").get("x", "")).contains("run out"), "an invite runs out after %d s" % int(Social.INVITE_LIFE))
	s.handle(1, {"k":"invite", "pid":B})
	s.handle(2, {"k":"join", "party":str(last(2, "inv").get("party", ""))})
	check(s.party_for(ids[1]) != "", "a new party")
	s.drop(2)
	s.tick(60.0)
	check(s.party_for(ids[1]) != "", "away a minute: still in the party")
	s.tick(Social.PARTY_GRACE)
	check(s.party_for(ids[1]) == "" and s.party_for(ids[0]) == "", "away %d s: out of the party (and the party of one is gone)" % int(Social.PARTY_GRACE))
	# --- kept
	s.save_now()
	var s2 = Social.new(dir, eco)
	check((s2.users[A].friends as Array).has(B) and (s2.users[C].blocked as Array).has(A) and s2.by_acct.get(ids[0], "") == A, "friends and blocks are kept in social.json")

func _pids(msg: Dictionary, k: String) -> Array:
	return (msg.get(k, []) as Array).map(func(c): return str(c.pid))

# ---------------- 2. end to end ----------------
var port := 8094
var server_pid := -1
var state_dir := ""
var phase := "boot"
var t := 0.0
var t_phase := 0.0
var raw := {}                             # name -> {ws, sent, msgs}
var accts := {}                           # name -> [acct, key]
var phones := {}                          # name -> Social node
var notes := {}
var units := {}

func _start_server() -> void:
	state_dir = OS.get_user_data_dir().path_join("socialtest-srv-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(state_dir)
	OS.set_environment("SIEGE_PORT", str(port))
	OS.set_environment("SIEGE_HOST", "127.0.0.1")
	OS.set_environment("SIEGE_LOBBY", "1.0")
	OS.set_environment("STATE_DIRECTORY", state_dir)
	OS.set_environment("SIEGE_MIN_BUILD", "off")
	server_pid = OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://server/siege_server.gd"])
	check(server_pid > 0, "server process started")

func _ws(name: String, first: Dictionary) -> void:
	var ws := WebSocketPeer.new()
	ws.inbound_buffer_size = 1 << 21
	ws.connect_to_url("ws://127.0.0.1:%d" % port)
	raw[name] = {"ws":ws, "sent":false, "first":first, "msgs":[]}

func _poll_raw() -> void:
	for n in raw:
		var r: Dictionary = raw[n]
		var ws: WebSocketPeer = r.ws
		ws.poll()
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN and not bool(r.sent):
			ws.put_packet(Net.encode(r.first))
			r.sent = true
		while ws.get_available_packet_count() > 0:
			(r.msgs as Array).append(Net.decode(ws.get_packet()))

func _raw_got(name: String, t_: String) -> Array:
	return (raw.get(name, {}).get("msgs", []) as Array).filter(func(m): return str(m.get("t", "")) == t_)

func _phone(name: String) -> void:
	var p = Profile.new("user://socialtest-%s-%d.json" % [name, Time.get_ticks_usec()], "user://none.json")
	p.load_or_create()
	p.d.account = {"id":accts[name][0], "key":accts[name][1], "seq":0}
	var sn = ClientSocial.new()
	sn.url = "ws://127.0.0.1:%d" % port
	sn.setup(p)
	sn.note.connect(func(x, _bad, _pop): notes[name] = x)
	root.add_child(sn)
	sn.set_active(true)
	phones[name] = sn

func _go(next: String) -> void:
	phase = next
	t_phase = 0.0

func _process(delta: float) -> bool:
	t += delta
	t_phase += delta
	_poll_raw()
	if t > 90.0:
		check(false, "timed out in phase %s" % phase)
		return _finish()
	match phase:
		"boot":
			if t_phase > 1.5:
				for n in ["alice", "bob"]:
					var imp := Profile.defaults()
					imp.name = n.capitalize()
					_ws("eco_" + n, {"t":"eco", "v":Net.VERSION, "new":true, "import":imp})
				_go("accounts")
		"accounts":
			var done := true
			for n in ["alice", "bob"]:
				var e := _raw_got("eco_" + n, "eco")
				if e.is_empty():
					done = false
				elif not accts.has(n):
					accts[n] = [str(e[0].acct), str(e[0].key)]
			if done:
				check(accts.size() == 2, "two accounts made on the server")
				_phone("alice")
				_phone("bob")
				_go("online")
		"online":
			if phones.alice.online() and phones.bob.online():
				check(str(phones.alice.me.n) == "Alice" and str(phones.bob.me.pid).length() == 10, "both phones' social side is up, with their names")
				phones.alice.say("global", "hello there")
				_go("chat")
			elif t_phase > 10.0:
				check(false, "social sides came up")
				return _finish()
		"chat":
			if phones.bob.lines.global.size() >= 1:
				var l: Dictionary = phones.bob.lines.global[-1]
				check(str(l.x) == "hello there" and str(l.n) == "Alice" and int(phones.bob.unread.global) == 1, "Alice's line reaches Bob (unread 1)")
				phones.alice.add(str(phones.bob.me.pid))
				_go("request")
		"request":
			if not phones.bob.rin.is_empty():
				check(phones.bob.relation(str(phones.alice.me.pid)) == "asked" and phones.bob.attention() == 1, "Bob sees Alice's request (Home badge 1)")
				phones.bob.add(str(phones.alice.me.pid))
				_go("friends")
		"friends":
			if phones.alice.relation(str(phones.bob.me.pid)) == "friend" and phones.bob.relation(str(phones.alice.me.pid)) == "friend":
				check(true, "friends on both phones")
				phones.alice.invite(str(phones.bob.me.pid))
				_go("invite")
		"invite":
			if not phones.bob.invites.is_empty():
				var pa: String = phones.bob.invites.keys()[0]
				phones.bob.join(pa)
				_go("party")
		"party":
			if phones.alice.party_size() == 2 and phones.bob.party_size() == 2:
				check(phones.alice.is_leader() and not phones.bob.is_leader(), "a party of two, Alice leads")
				phones.alice.play()
				_go("go")
		"go":
			if phones.bob.party_play != "":
				check(phones.bob.party_play == str(phones.alice.party.id), "Bob's phone is told to follow Alice into the match")
				for n in ["alice", "bob"]:
					_ws("match_" + n, {"t":"hello", "v":Net.VERSION, "name":n, "build":"0.31.111-fatebound", "pred":false,
						"acct":accts[n][0], "key":accts[n][1], "party":phones.alice.party.id})
				_go("seated")
		"seated":
			for n in ["alice", "bob"]:
				var w := _raw_got("match_" + n, "welcome")
				if not w.is_empty():
					units[n] = str(w[0].you)
			if units.size() == 2:
				check(units.alice != "" and units.bob != "" and units.alice[0] == units.bob[0], "the party is seated on ONE side: %s and %s" % [units.alice, units.bob])
				_go("presence")
		"presence":
			var bc: Dictionary = phones.alice.card_of(str(phones.bob.me.pid))
			if str(bc.get("st", "")) == "match":
				check(true, "Alice sees Bob in a match")
				(raw.match_alice.ws as WebSocketPeer).put_packet(Net.encode({"t":"qc", "i":4}))
				_go("qc")
			elif t_phase > 5.0:
				check(false, "a friend in a match shows in a match (%s)" % str(bc))
				_go("qc_skip")
		"qc":
			var q := _raw_got("match_bob", "qc")
			if not q.is_empty():
				check(str(q[0].u) == units.alice and int(q[0].i) == 4, "Alice's \"Need help!\" reaches Bob with her unit")
				(raw.match_alice.ws as WebSocketPeer).put_packet(Net.encode({"t":"qc", "i":0}))
				_go("qc_gap")
		"qc_gap":
			if t_phase > 1.0:
				check(_raw_got("match_bob", "qc").size() == 1, "a second quick chat within %.0f s is dropped" % Net.QC_GAP)
				_go("qc_wait")
		"qc_wait":
			if t_phase > Net.QC_GAP + 0.3:
				(raw.match_alice.ws as WebSocketPeer).put_packet(Net.encode({"t":"qc", "i":7}))
				_go("gg")
		"gg":
			var q2 := _raw_got("match_bob", "qc")
			if q2.size() >= 2:
				check(int(q2[-1].i) == 7, "\"Good game!\" goes through after the gap")
				return _finish()
			elif t_phase > 5.0:
				check(false, "a later quick chat goes through")
				return _finish()
		"qc_skip":
			return _finish()
	return false

func _finish() -> bool:
	if server_pid > 0:
		OS.kill(server_pid)
	# (a quick sanity check of the sim's bot call, offline)
	var sim = Sim.new()
	sim.setup(Net.TEAM_SIZE, 7, 0)
	for i in 30:
		sim.step(Sim.TICK)
	for id in ["b1", "b4", "b5", "b6", "b7"]:
		sim.by_id[id].cls = "knight"          # (at the start everyone is a villager on the way to a hat)
	var n: int = sim.call_bots("you")
	var called := 0
	for u in sim.units:
		if u.has("call"):
			called += 1
	check(n == called and n == Sim.CALL_BOTS, "\"Need help!\" calls the %d nearest free bots (%d came)" % [Sim.CALL_BOTS, n])
	var far := {}
	for u in sim.units:
		if u.has("call") and (far.is_empty() or (u.pos as Vector2).distance_to(sim.by_id["you"].pos) > (far.pos as Vector2).distance_to(sim.by_id["you"].pos)):
			far = u
	sim.by_id["you"].pos += Vector2(0, -8)                # the caller walks off: the bots follow
	var d0: float = (far.pos as Vector2).distance_to(sim.by_id["you"].pos)
	for i in 90:
		sim.step(Sim.TICK)
	var d1: float = (far.pos as Vector2).distance_to(sim.by_id["you"].pos)
	check(d1 < d0 - 2.0 or d1 < 3.5, "a called bot comes to the caller (%.1f m -> %.1f m)" % [d0, d1])
	print("SOCIAL_PASS" if fails.is_empty() else "SOCIAL_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
	return true
