extends SceneTree
# 0.31.120 (Kevin: player profile card -- tap a name: level, title, wins, favourite class and weapon).
#  1. eco_accounts.stats_of: the class played most (stats.main_<cls>), wins with it, the outfit worn on that hero ("sk";
#     0.31.188 -- it was the weapon won most with and its stars, until the Forge went); level and lifetime numbers;
#     nothing private (no ids, keys, gold, gems, purchases)
#  2. the REAL server (port 8108, accounts and this week's leaderboard written before it starts) and the real app for Bob:
#     RANKS > tap Alice's row: her card fills in from the server (Knight, the outfit, LEVEL 12, #1 this week) with ADD
#     FRIEND; Carl blocked Bob: his card shows nothing; what goes over the wire has only the card's fields
#   godot --headless --path godot -s res://tests/profile_card_test.gd
const Accounts = preload("res://server/eco_accounts.gd")
const Leaderboard = preload("res://server/leaderboard.gd")
const Social = preload("res://server/social.gd")
const Profile = preload("res://scripts/meta/profile.gd")
const Eco = preload("res://scripts/meta/economy.gd")
const Net = preload("res://scripts/siege/siege_net.gd")
const App = preload("res://scripts/app/siege_app.gd")

const CARD_KEYS := ["t", "k", "pid", "ok", "n", "tt", "rank", "lv", "m", "w", "r", "ko", "bs", "since", "cls", "cm", "cw", "sk", "ct", "tw"]   # (0.31.134: "ct", the clan tag; 0.31.188: "sk" for the weapon's wpn/wr/ws/wc/ww)

var fails: Array = []
var port := 8108
var url := ""
var pid := -1
var sd := ""
var phase := "boot"
var t_phase := 0.0
var socks := {}
var inbox := {}
var sent := {}
var who := {}
var notes := {}
var app

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _init() -> void:
	url = "ws://127.0.0.1:%d" % port
	sd = OS.get_user_data_dir().path_join("card-srv-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(sd)
	# --- 1. the numbers, on accounts the server will use
	var acc = Accounts.new(sd)
	for n in ["Alice", "Bob", "Carl"]:
		var a: Dictionary = acc.handle({"t":"eco", "new":true})
		who[n] = {"acct":str(a.acct), "key":str(a.key)}
		var e: Dictionary = acc._load(str(a.acct))
		e.p.d.name = n
		e.p.save()
	var ae: Dictionary = acc._load(who.Alice.acct)
	var d: Dictionary = ae.p.d
	d.level = 12
	d.stats.matches = 40
	d.stats.wins = 25
	d.stats.rescues = 7
	d.stats["towers"] = 11
	d.stats.kills = 160
	d.stats.best_streak = 6
	d.stats["main_knight"] = 22
	d.stats["win_knight"] = 15
	d.stats["main_mage"] = 18
	d.skins = ["knight_lion", "mage_frost"]
	d.skin_on = {"knight": "knight_lion", "mage": "mage_frost"}
	d.gold = 4321
	d.gems = 99
	ae.p.save()
	var s: Dictionary = acc.stats_of(who.Alice.acct)
	check(str(s.get("cls", "")) == "knight" and int(s.cm) == 22 and int(s.cw) == 15, "the class she plays most: Knight, 22 matches, 15 won")
	check(str(s.get("sk", "")) == "knight_lion" and not s.has("wpn"), "the outfit she wears on her Knight (%s)" % str(s.get("sk", "")))
	check(int(s.lv) == 12 and int(s.m) == 40 and int(s.w) == 25 and int(s.r) == 7 and int(s.ko) == 160 and int(s.bs) == 6 and int(s.since) > 0
		and int(s.get("tw", -1)) == 11, "level, matches, wins, rescues (older apps), knockouts, best streak, since, towers")
	check(s.keys().all(func(k): return CARD_KEYS.has(str(k))), "nothing else: %s" % str(s.keys()))
	var fresh: Dictionary = acc.stats_of(who.Bob.acct)
	check(str(fresh.cls) == "" and not fresh.has("sk") and int(fresh.lv) == 1, "a new account: no class or outfit yet")
	check(acc.stats_of("0".repeat(20)).is_empty(), "no account: nothing")
	# this week's board with Alice on it
	var lb = Leaderboard.new(sd)
	lb.add_match(who.Alice.acct, "Alice", "", {"kills":10, "rescues":1}, true)
	lb.save_now()
	OS.set_environment("SIEGE_PORT", str(port))
	OS.set_environment("SIEGE_HOST", "127.0.0.1")
	OS.set_environment("STATE_DIRECTORY", sd)
	OS.set_environment("SIEGE_MIN_BUILD", "off")
	OS.set_environment("SIEGE_URL", url)
	pid = OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://server/siege_server.gd"])
	check(pid > 0, "server process started")

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

func say(name: String, msg: Dictionary) -> void:
	(socks[name] as WebSocketPeer).put_packet(Net.encode(msg))

func so(name: String, k: String) -> Array:
	return (inbox.get(name, []) as Array).filter(func(m): return str(m.get("t", "")) == "so" and str(m.get("k", "")) == k)

func _find(node: Node, pred: Callable) -> Array:
	var out := []
	if pred.call(node):
		out.append(node)
	for c in node.get_children():
		out.append_array(_find(c, pred))
	return out

func _labels(n: Node) -> Array:
	return n.find_children("*", "Label", true, false).filter(func(l): return (l as Label).is_visible_in_tree()).map(func(l): return str((l as Label).text))

func _card() -> Node:
	var c := _find(app, func(n): return n.has_meta("name_card") and not n.is_queued_for_deletion())
	return c[0] if not c.is_empty() else null

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
				open("sA")
				open("sC")
				_go("social")
		"social":
			send_once("sA", {"t":"so", "k":"hi", "v":Net.VERSION, "acct":who.Alice.acct, "key":who.Alice.key})
			send_once("sC", {"t":"so", "k":"hi", "v":Net.VERSION, "acct":who.Carl.acct, "key":who.Carl.key})
			if not so("sA", "me").is_empty() and not so("sC", "me").is_empty() and not notes.has("blocked"):
				notes.pidA = str(so("sA", "me")[0].pid)
				notes.pidC = str(so("sC", "me")[0].pid)
				notes.pidB = Social.pid_of(who.Bob.acct)
				notes.blocked = true
				t_phase = 0.0
			elif notes.has("blocked") and t_phase > 0.3 and not notes.has("bobapp"):
				# Bob has to be known to the server before Carl can block him: his app connects first
				var base := "user://cardtest-%d" % Time.get_ticks_usec()
				var p = Profile.new(base + "-profile.json", base + "-none.json")
				p.load_or_create()
				p.d.name = "Bob"
				p.d.account = {"id":who.Bob.acct, "key":who.Bob.key, "seq":0}
				p.d.tutorial_done = true
				p.server_mode = true
				p.save()
				app = App.new()
				app.profile_path = base + "-profile.json"
				app.legacy_path = base + "-none.json"
				root.add_child(app)
				app.social.set_active(true)
				notes.bobapp = true
			elif notes.has("bobapp") and app.social.online() and not notes.has("carl_blocks"):
				say("sC", {"t":"so", "k":"block", "pid":notes.pidB})
				for i in Social.PROF_BURST + 1:
					say("sA", {"t":"so", "k":"prof", "pid":notes.pidB})
				notes.carl_blocks = true
				t_phase = 0.0
			elif notes.has("carl_blocks") and t_phase > 0.6:
				var pb := so("sA", "prof")
				check(not pb.is_empty() and bool(pb[0].ok) and str(pb[0].n) == "Bob" and int(pb[0].lv) == 1, "Alice asks for Bob's card: his numbers")
				if not pb.is_empty():
					check((pb[0] as Dictionary).keys().all(func(k): return CARD_KEYS.has(str(k))) and not pb[0].has("acct") and not pb[0].has("gold"),
						"...only the card's fields over the wire: %s" % str((pb[0] as Dictionary).keys()))
				check(pb.size() == Social.PROF_BURST + 1 and str(pb[-1].get("why", "")) == "busy" and pb.slice(0, -1).all(func(m): return bool(m.ok)),
					"%d asks in a row: the last one \"busy\"" % (Social.PROF_BURST + 1))
				app.open_leaderboard()
				_go("ranks")
			elif t_phase > 15.0:
				check(false, "everyone online within 15 s (%s, app %s)" % [str(notes), str(app.social.state) if app != null else "-"])
				_finish()
		"ranks":
			var tap := _find(app.modal, func(n): return n is Button and str(n.get_meta("action_key", "")) == "lb_card_1")
			if not tap.is_empty():
				(tap[0] as Button).pressed.emit()
				var c := _card()
				check(c != null and _labels(c).has("Alice"), "RANKS: Alice's row opens her card")
				_go("alice_card")
			elif t_phase > 12.0:
				check(false, "the leaderboard with Alice's row within 12 s (%s)" % str(_labels(app.modal).slice(0, 12)))
				_finish()
		"alice_card":
			var c := _card()
			var txt := _labels(c) if c != null else []
			if txt.has("LEVEL"):
				check(txt.has("Knight") and txt.any(func(t): return t.contains("22 matches") and t.contains("15 won")), "the class she plays most")
				check(txt.has("Wears Lionguard Knight") and not txt.has("★★"), "the outfit she wears (no weapon, no stars)")
				var i := txt.find("LEVEL")
				check(i > 0 and txt[i - 1] == "12" and txt.has("25") and txt.has("63%") and txt.has("160") and txt.has("6"), "level 12, 25 wins, 63% win rate, 160 knockouts, best streak 6")
				check(txt.any(func(t): return t.contains("#1 this week") and t.contains("40 matches")), "#1 this week, 40 matches")
				check(not _find(c, func(n): return n is Button and str(n.get_meta("action_key", "")) == "card_add").is_empty(), "...and ADD FRIEND")
				check(not txt.any(func(t): return t.contains("4321") or t.contains("99 gems")), "no gold or gems")
				(_find(c, func(n): return n is Button and str(n.get_meta("action_key", "")) == "card_close")[0] as Button).pressed.emit()
				app.close_modal()
				var SocialUI = load("res://scripts/app/social_ui.gd")
				SocialUI.name_card(app, app, {"pid":notes.pidC, "n":"Carl"})
				_go("carl_card")
			elif t_phase > 8.0:
				check(false, "Alice's card filled in within 8 s (%s)" % str(txt))
				_finish()
		"carl_card":
			var c := _card()
			var txt := _labels(c) if c != null else []
			if txt.has("No profile to show"):
				check(not txt.has("LEVEL"), "Carl blocked Bob: his card shows no numbers")
				_finish()
			elif t_phase > 8.0:
				check(false, "Carl's card answered within 8 s (%s)" % str(txt))
				_finish()
	return false

func _finish() -> void:
	if pid > 0:
		OS.kill(pid)
		OS.execute("kill", ["-9", str(pid)])
		pid = -1
	print("PROFILE_CARD_PASS" if fails.is_empty() else "PROFILE_CARD_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
