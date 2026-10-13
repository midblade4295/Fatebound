extends SceneTree
# 0.31.120 (Kevin: referral codes -- "both get a Gold chest when the new player reaches level 5, server-checked").
#  1. server/referrals.gd with real accounts: a wrong key, an unknown code, your own code, a second code, a loop (the
#     friend entered yours), an account older than Eco.REF_DAYS or already at Eco.REF_LEVEL -- all refused; a good code
#     is taken (whatever its case, "#" or spaces). At level 5 both get a Gold chest and a note, once; a friend is rewarded
#     for at most Eco.REF_MAX players; kept across a restart; never an op a phone can send.
#  2. the REAL server (port 8107) and the real app for Bob, a new player: Friends > INVITE FRIENDS > the code of Alice
#     (who's been online) > REDEEM: the server takes it, Friends says so. The server restarts with Bob at level 5: Bob's
#     next sync brings the Gold chest and Home says FRIEND REWARD; Alice's account has hers.
#   godot --headless --path godot -s res://tests/referral_test.gd
const Referrals = preload("res://server/referrals.gd")
const Accounts = preload("res://server/eco_accounts.gd")
const Social = preload("res://server/social.gd")
const Profile = preload("res://scripts/meta/profile.gd")
const Eco = preload("res://scripts/meta/economy.gd")
const Net = preload("res://scripts/siege/siege_net.gd")
const App = preload("res://scripts/app/siege_app.gd")
const FriendsPanel = preload("res://scripts/app/friends_panel.gd")

class FakeSocial:
	var users := {}

var fails: Array = []
var port := 8107
var url := ""
var pid := -1
var sd := ""
var phase := "boot"
var t_phase := 0.0
var socks := {}
var inbox := {}
var sent := {}
var accts := {}
var notes := {}
var app

static func n_chests(ch: Dictionary) -> int:
	return (ch.slots as Array).size() + (ch.get("queue", []) as Array).size()

static func has_kind(ch: Dictionary, kind: String) -> bool:
	for c in ch.slots:
		if str(c.get("kind", "")) == kind:
			return true
	for k in ch.get("queue", []):
		if str(k) == kind:
			return true
	return false

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _init() -> void:
	_unit()
	url = "ws://127.0.0.1:%d" % port
	sd = OS.get_user_data_dir().path_join("ref-srv-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(sd)
	OS.set_environment("SIEGE_PORT", str(port))
	OS.set_environment("SIEGE_HOST", "127.0.0.1")
	OS.set_environment("STATE_DIRECTORY", sd)
	OS.set_environment("SIEGE_MIN_BUILD", "off")
	OS.set_environment("SIEGE_URL", url)
	_server()

func _server() -> void:
	pid = OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://server/siege_server.gd"])
	check(pid > 0, "server process started")

func _kill() -> void:
	if pid > 0:
		OS.kill(pid)
		OS.execute("kill", ["-9", str(pid)])
		pid = -1

# ---------------- 1. the rules ----------------
func _new(acc, name: String) -> Dictionary:
	var a: Dictionary = acc.handle({"t":"eco", "new":true})
	var e: Dictionary = acc._load(str(a.acct))
	e.p.d.name = name
	e.p.save()
	return {"acct":str(a.acct), "key":str(a.key)}

func _unit() -> void:
	var tmp := OS.get_user_data_dir().path_join("ref-unit-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	var acc = Accounts.new(tmp)
	var soc := FakeSocial.new()
	var who := {}
	for n in ["Alice", "Newbie", "Other", "Late", "High", "Max"]:
		who[n] = _new(acc, n)
		soc.users[Social.pid_of(str(who[n].acct))] = {"acct":str(who[n].acct), "name":n}
	var code := func(n: String) -> String: return Social.pid_of(str(who[n].acct))
	var ref = Referrals.new(tmp)
	var nb: Dictionary = who.Newbie
	check(str(ref.claim(nb.acct, "0".repeat(64), code.call("Alice"), acc, soc).why) == "auth", "a wrong key: refused")
	check(str(ref.claim(nb.acct, nb.key, "ffffffffff", acc, soc).why) == "code", "a code nobody has: refused")
	check(str(ref.claim(nb.acct, nb.key, code.call("Newbie"), acc, soc).why) == "self", "your own code: refused")
	var r: Dictionary = ref.claim(nb.acct, nb.key, " #" + str(code.call("Alice")).to_upper() + " ", acc, soc)
	check(bool(r.ok) and str(r.name) == "Alice" and str(acc._load(nb.acct).p.d.referral.by) == "Alice",
		"Alice's code (in capitals, with # and spaces): taken, the account says so")
	check(str(ref.claim(nb.acct, nb.key, code.call("Other"), acc, soc).why) == "done", "a second code: refused")
	check(str(ref.claim(who.Alice.acct, who.Alice.key, code.call("Newbie"), acc, soc).why) == "loop", "Alice entering Newbie's (who entered hers): refused")
	acc.now_override = int(Time.get_unix_time_from_system()) + (Eco.REF_DAYS + 1) * 86400
	check(str(ref.claim(who.Late.acct, who.Late.key, code.call("Alice"), acc, soc).why) == "late", "an account %d+ days old: refused" % (Eco.REF_DAYS + 1))
	acc.now_override = -1
	var he: Dictionary = acc._load(who.High.acct)
	he.p.d.level = Eco.REF_LEVEL
	he.p.save()
	check(str(ref.claim(who.High.acct, who.High.key, code.call("Alice"), acc, soc).why) == "late", "already level %d: refused" % Eco.REF_LEVEL)
	# level 5
	check(ref.check(nb.acct, acc) == 0, "below level %d: nothing yet" % Eco.REF_LEVEL)
	var ne: Dictionary = acc._load(nb.acct)
	var nchests := n_chests(ne.p.d.chests)
	var ae: Dictionary = acc._load(who.Alice.acct)
	var achests := n_chests(ae.p.d.chests)
	ne.p.d.level = Eco.REF_LEVEL
	ne.p.save()
	check(ref.check(nb.acct, acc) == 2, "level %d: two chests" % Eco.REF_LEVEL)
	ne = acc._load(nb.acct)
	ae = acc._load(who.Alice.acct)
	var nnow := n_chests(ne.p.d.chests)
	var anow := n_chests(ae.p.d.chests)
	check(nnow == nchests + 1 and anow == achests + 1, "a chest each (%d->%d, %d->%d)" % [nchests, nnow, achests, anow])
	check(str(ne.p.d.referral.notes[0].kind) == "joined" and str(ne.p.d.referral.notes[0].name) == "Alice"
		and str(ae.p.d.referral.notes[0].kind) == "friend" and str(ae.p.d.referral.notes[0].name) == "Newbie",
		"the notes: Newbie joined with Alice's code; Alice's friend Newbie")
	check(has_kind(ne.p.d.chests, Eco.REF_CHEST), "a %s chest" % Eco.REF_CHEST)
	check(ref.check(nb.acct, acc) == 0, "...once")
	# the cap
	check(bool(ref.claim(who.Max.acct, who.Max.key, code.call("Alice"), acc, soc).ok), "Max enters Alice's code too")
	ref.count[who.Alice.acct] = Eco.REF_MAX
	var me: Dictionary = acc._load(who.Max.acct)
	me.p.d.level = Eco.REF_LEVEL
	me.p.save()
	var before := (acc._load(who.Alice.acct).p.d.referral.notes as Array).size()
	check(ref.check(who.Max.acct, acc) == 1 and (acc._load(who.Alice.acct).p.d.referral.notes as Array).size() == before,
		"Alice already rewarded for %d: Max gets his, Alice nothing more" % Eco.REF_MAX)
	var ref2 = Referrals.new(tmp)
	check(ref2.by.has(nb.acct) and ref2.paid.has(nb.acct) and int(ref2.count.get(who.Alice.acct, 0)) == Eco.REF_MAX, "kept across a restart")
	check(not Profile.OPS.has("grant_referral") and not Profile.OPS.has("referral"), "not an op a phone can send")
	var back: Dictionary = acc.handle({"t":"eco", "acct":nb.acct, "key":nb.key, "ops":[]})
	check(str(back.profile.referral.by) == "Alice" and (back.profile.referral.notes as Array).size() == 1, "...and the phone gets it with its account")

# ---------------- 2. the server and the app ----------------
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

func _find(node: Node, pred: Callable) -> Array:
	var out := []
	if pred.call(node):
		out.append(node)
	for c in node.get_children():
		out.append_array(_find(c, pred))
	return out

func _labels(n: Node) -> Array:
	return n.find_children("*", "Label", true, false).map(func(l): return str((l as Label).text))

func _profile_file(id: String) -> String:
	return sd.path_join("accounts").path_join(id + ".json")

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
				for w in ["A", "B"]:
					open("e" + w)
				open("ver")
				_go("accounts")
		"accounts":
			for w in ["A", "B"]:
				var imp := Profile.defaults()
				imp.name = {"A":"Alice", "B":"Bob"}[w]
				send_once("e" + w, {"t":"eco", "v":Net.VERSION, "new":true, "import":imp})
			send_once("ver", {"t":"ver", "v":Net.VERSION})
			for w in ["A", "B"]:
				if not got("e" + w, "eco").is_empty() and not accts.has(w):
					var m: Dictionary = got("e" + w, "eco")[0]
					accts[w] = {"acct":str(m.acct), "key":str(m.key)}
			if accts.size() == 2 and not got("ver", "ver").is_empty():
				check(int(got("ver", "ver")[0].get("ref", 0)) == 1, "the server says it takes referral codes")
				open("sA")
				_go("alice_online")
			elif t_phase > 10.0:
				check(false, "accounts within 10 s")
				_finish()
		"alice_online":
			send_once("sA", {"t":"so", "k":"hi", "v":Net.VERSION, "acct":accts.A.acct, "key":accts.A.key})
			for m in inbox["sA"]:
				if str(m.get("k", "")) == "me":
					notes.pidA = str(m.pid)
			if notes.has("pidA"):
				var base := "user://reftest-%d" % Time.get_ticks_usec()
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
			elif t_phase > 10.0:
				check(false, "Alice online within 10 s")
				_finish()
		"bob_friends":
			if app.social.online() and t_phase > 0.5:
				app.open_friends()
				var txt := _labels(app.modal)
				var fields := _find(app.modal, func(n): return n is LineEdit)
				var rb := _find(app.modal, func(n): return n is Button and str(n.get_meta("action_key", "")) == "ref_redeem")
				check(app.modal is FriendsPanel and txt.has("INVITE FRIENDS") and rb.size() == 1 and fields.size() == 2,
					"Bob's Friends: INVITE FRIENDS, with a code field and REDEEM (%s, %d fields, %d buttons, %s)" % [str(app.modal), fields.size(), rb.size(), str(txt.slice(0, 8))])
				if rb.size() == 1:
					(app.modal._ref as LineEdit).text = "#" + str(notes.pidA).to_upper()
					(rb[0] as Button).pressed.emit()
				_go("bob_redeem")
			elif t_phase > 15.0:
				check(false, "Bob's app online within 15 s")
				_finish()
		"bob_redeem":
			if str(app.profile.d.referral.get("by", "")) != "" and t_phase > 0.5:
				var txt := _labels(app.modal)
				check(str(app.profile.d.referral.by) == "Alice" and txt.any(func(t): return t.contains("You joined with Alice's code")),
					"REDEEM: the server takes Alice's code; Friends says so")
				check(_find(app.modal, func(n): return n is Button and str(n.get_meta("action_key", "")) == "ref_redeem").is_empty(), "...and the field is gone")
				_go("bob_level")
			elif t_phase > 10.0:
				check(false, "the code taken within 10 s")
				_finish()
		"bob_level":
			# the server restarts with Bob at level 5 (as a match would have got him there)
			if t_phase > 2.5 and not notes.has("restarted"):
				_kill()
				OS.delay_msec(300)
				var path := _profile_file(accts.B.acct)
				var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
				check(v is Dictionary and str(v.referral.by) == "Alice", "the server saved Bob's referral")
				if v is Dictionary:
					v.level = Eco.REF_LEVEL
					var f := FileAccess.open(path, FileAccess.WRITE)
					f.store_string(JSON.stringify(v))
					f.close()
				_server()
				notes.restarted = true
				t_phase = 0.0
			elif notes.has("restarted") and t_phase > 2.5:
				app.close_modal()
				app._daily_offered = Eco.day_key(app.profile.now())          # (not the daily reward card)
				app.daily_auto = true
				app.show_tab("home")
				app.eco_sync.start()
				_go("bob_reward")
		"bob_reward":
			if app.modal != null and is_instance_valid(app.modal) and _labels(app.modal).has("FRIEND REWARD"):
				var txt := _labels(app.modal)
				check(txt.any(func(t): return t.contains("Alice's code") and t.contains("Gold Chest")), "Bob's sync: Home says FRIEND REWARD (%s)" % str(txt.slice(0, 3)))
				check(has_kind(app.profile.d.chests, Eco.REF_CHEST) and str(app.profile.d.referral.notes[0].kind) == "joined", "Bob's Gold chest")
				app.close_modal()
				open("eA2")
				_go("alice")
			elif t_phase > 15.0:
				check(false, "the reward within 15 s (level %d, notes %s)" % [int(app.profile.d.level), str(app.profile.d.referral.notes)])
				_finish()
		"alice":
			send_once("eA2", {"t":"eco", "v":Net.VERSION, "acct":accts.A.acct, "key":accts.A.key, "ops":[]})
			if not got("eA2", "eco").is_empty():
				var pr: Dictionary = got("eA2", "eco")[0].profile
				check(has_kind(pr.chests, Eco.REF_CHEST) and str(pr.referral.notes[0].kind) == "friend" and str(pr.referral.notes[0].name) == "Bob",
					"Alice's account: a Gold chest, \"Bob reached level 5 with your code\"")
				check(App.referral_text(pr.referral.notes).contains("Bob reached level %d with your code" % Eco.REF_LEVEL), "...which Home will say")
				_finish()
			elif t_phase > 10.0:
				check(false, "Alice's account within 10 s")
				_finish()
	return false

func _finish() -> void:
	_kill()
	print("REFERRAL_PASS" if fails.is_empty() else "REFERRAL_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
