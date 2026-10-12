extends SceneTree
# 0.31.108 (Kevin: "make sure everything is verified by server so players can't edit gems ect"; "Always online"):
# the accounts the server keeps. REAL time (the second half runs the real server as its own process, port 8093).
#  1. server/eco_accounts.gd on its own: a new account takes in the phone's progress held to its limits (only
#     purchases Google confirmed count, and each for one account); ops replayed with the game's rules, a repeat skipped,
#     bad and unknown ops refused; VS BOTS results only against a ticket, not too soon, clamped, used once; a chest rolls
#     the same on the phone and the server; a purchase granted once across accounts; online looks only what's owned.
#  2. end to end: the app's EcoSync against the real server -- an account made, an edited save put back, a purchase in
#     the shop kept, a too-quick VS BOTS result refused and its rewards taken back, an online match paid by the
#     server's own count, a Google-confirmed purchase granted to the account (SIEGE_IAP_FAKE).
#   godot --headless --path godot -s res://tests/eco_server_test.gd
const Accounts = preload("res://server/eco_accounts.gd")
const Profile = preload("res://scripts/meta/profile.gd")
const Eco = preload("res://scripts/meta/economy.gd")
const Net = preload("res://scripts/siege/siege_net.gd")
const EcoSync = preload("res://scripts/meta/eco_sync.gd")

var fails: Array = []
var port := 8093
var pid := -1
var state2 := ""
var phase := "boot"
var t := 0.0
var t_phase := 0.0
var p                                   # the phone's profile (part 2)
var sync
var raw: WebSocketPeer
var raw_sent := false
var raw_msgs: Array = []
var notes := {}
var gold_before := 0
var matches_before := 0

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _init() -> void:
	_part1()
	state2 = OS.get_user_data_dir().path_join("ecotest-srv-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(state2)
	OS.set_environment("SIEGE_PORT", str(port))
	OS.set_environment("SIEGE_HOST", "127.0.0.1")
	OS.set_environment("SIEGE_LOBBY", "0.5")
	OS.set_environment("SIEGE_TEST_MATCH_S", "6")
	OS.set_environment("SIEGE_IAP_FAKE", "1")
	OS.set_environment("STATE_DIRECTORY", state2)
	OS.set_environment("SIEGE_MIN_BUILD", "off")
	pid = OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://server/siege_server.gd"])
	check(pid > 0, "server process started")

# ---------------- 1. the accounts on their own ----------------
func _part1() -> void:
	var tmp := OS.get_user_data_dir().path_join("ecotest-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	var lf := FileAccess.open(tmp.path_join("iap_ledger.jsonl"), FileAccess.WRITE)
	lf.store_line(JSON.stringify({"at":1, "p":"gems_500", "tok":Accounts.token_hash("tok-old-purchase-1"), "order":"GPA.1", "v":"ok"}))
	lf.close()
	var acc = Accounts.new(tmp)
	var now := 1791000000
	acc.now_override = now
	check(acc.tokens.get(Accounts.token_hash("tok-old-purchase-1"), "x") == "", "a purchase Google confirmed for an older app is known, not yet anyone's")
	# --- a phone that edited its save: 50,000 gems, a quest legendary without the quest, a made-up purchase
	var src := Profile.defaults()
	src.gems = 50000
	src.gold = 999999
	src.embers = 99999
	src.level = 90
	src.stats.matches = 10
	src.owned = ["knight_wpn_greatsword", "knight_wpn_kingsguard", "mage_wpn_wand"]
	src.iap.done = [{"t":"tok-old-purchase-1", "p":"gems_500", "at":1}, {"t":"tok-made-up-2", "p":"gems_6500", "at":1}]
	var a: Dictionary = acc.handle({"t":"eco", "new":true, "import":src})
	var id := str(a.get("acct", ""))
	var key := str(a.get("key", ""))
	var sp: Dictionary = a.get("profile", {})
	check(bool(a.ok) and Accounts.valid_id(id) and key.length() == 64 and not sp.has("account"), "a new account: an id and a key (only its hash kept)")
	var meta_txt := FileAccess.get_file_as_string(tmp.path_join("accounts/%s.meta.json" % id))
	check(not meta_txt.contains(key) and meta_txt.contains(key.sha256_text()), "the key itself is never written down")
	check(int(sp.gems) == 500 + 300 + 12 * 10, "gems held to 10 matches' worth + the confirmed purchase: %d" % int(sp.gems))
	check(int(sp.gold) == 5000 + 900 * 10 and int(sp.embers) == 200 + 400 and int(sp.level) == 3 + 5,
		"gold, Embers and level held too (%d, %d, %d)" % [int(sp.gold), int(sp.embers), int(sp.level)])
	check(sp.owned.has("knight_wpn_greatsword") and not sp.owned.has("knight_wpn_kingsguard"), "owned kept, but no quest legendary without its quest")
	check(str(acc.tokens.get(Accounts.token_hash("tok-old-purchase-1"), "")) == id and int(sp.iap.n) == 1, "the confirmed purchase is this account's now; the made-up one is dropped")
	var b: Dictionary = acc.handle({"t":"eco", "new":true, "import":src})
	check(int(b.profile.gems) == 300 + 12 * 10, "a second account can't count the same purchase (%d)" % int(b.profile.gems))
	check(not bool(acc.handle({"t":"eco", "acct":id, "key":"0".repeat(64)}).ok), "a wrong key gets nothing")
	# --- ops, replayed with the game's rules
	var e: Dictionary = acc.open(id, key)
	var buy_id := ""
	for d_id in Eco.shop_daily(now):
		if Eco.item_price(d_id, now).has("gold") and not e.p.owns(d_id):
			buy_id = d_id
			break
	var g0 := int(e.p.d.gold)
	var r: Dictionary = acc.handle({"t":"eco", "acct":id, "key":key, "ops":[{"s":1, "op":"buy", "a":[buy_id]}]})
	check(bool(r.results[0].ok) and r.profile.owned.has(buy_id) and int(r.profile.gold) == g0 - int(Eco.item_price(buy_id).gold),
		"a purchase in the shop is made on the server's copy (%s)" % buy_id)
	r = acc.handle({"t":"eco", "acct":id, "key":key, "ops":[{"s":1, "op":"buy", "a":[buy_id]}]})
	check(bool(r.results[0].get("dup", false)) and int(r.profile.gold) == g0 - int(Eco.item_price(buy_id).gold), "the same op sent again is done once")
	r = acc.handle({"t":"eco", "acct":id, "key":key, "ops":[{"s":2, "op":"exchange", "a":["gold_xxl"]}, {"s":3, "op":"buy", "a":[123]},
		{"s":4, "op":"grant_iap", "a":["gems_6500", "tok-x"]}, {"s":5, "op":"match", "a":[{"kills":3}, true, false]}]})
	var errs := []
	for x in r.results:
		errs.append(str(x.error) if not bool(x.ok) else "ok")
	check(errs == ["Not enough gems", "bad args", "unknown op", "no ticket"] and int(r.profile.gems) == int(sp.gems),
		"refused: an exchange without the gems, a malformed op, a purchase grant, a match without a ticket %s" % str(errs))
	# --- VS BOTS: a ticket, not too soon, clamped, once
	r = acc.handle({"t":"eco", "acct":id, "key":key, "ticket":true})
	var tk := str(r.get("ticket", ""))
	var big := {"kills":99999, "rescues":99, "gathered":5000, "gate_dmg":1e9, "fed":500, "cls":"knight", "cls_main":"knight",
		"kills_cls":{"knight":99999}, "q":{"knight":{"t":99999.0, "kills":99999, "rescues":99, "gates":99999}}}
	r = acc.handle({"t":"eco", "acct":id, "key":key, "ops":[{"s":6, "op":"match", "tk":tk, "a":[big, true, false]}]})
	check(tk != "" and str(r.results[0].error) == "too short", "a result 0 s after its ticket is refused")
	acc.now_override = now + 400
	var k0 := int(r.profile.stats.kills)
	var m0 := int(r.profile.stats.matches)
	r = acc.handle({"t":"eco", "acct":id, "key":key, "ops":[{"s":7, "op":"match", "tk":tk, "a":[big, true, false]}]})
	var kills_got := int(r.profile.stats.kills) - k0
	check(bool(r.results[0].ok) and int(r.profile.stats.matches) == m0 + 1 and kills_got > 0 and kills_got <= 80 and int(r.profile.stats.rescues) <= 5,
		"400 s later it counts, held to what a match that long can hold (%d knockouts)" % kills_got)
	r = acc.handle({"t":"eco", "acct":id, "key":key, "ops":[{"s":8, "op":"match", "tk":tk, "a":[big, true, false]}]})
	check(str(r.results[0].error) == "no ticket", "a ticket pays once")
	# --- a chest rolls the same on the phone and on the server
	e = acc.open(id, key)
	e.p.d.chests.slots.clear()
	e.p.add_chest("gold", {})
	e.p.save()
	var cid := int(e.p.d.chests.slots[0].id)
	var phone = Profile.new(tmp.path_join("phone.json"), "")
	phone.now_override = acc.now_override
	phone.d = phone._normalized(Accounts.public_profile(e.p.d))
	phone.start_unlock(0)
	phone.now_override += 9 * 3600
	var pr: Dictionary = phone.open_chest(0)
	r = acc.handle({"t":"eco", "acct":id, "key":key, "ops":[{"s":9, "op":"start_unlock", "a":[cid]}]})
	acc.now_override += 9 * 3600
	r = acc.handle({"t":"eco", "acct":id, "key":key, "ops":[{"s":10, "op":"open_chest", "a":[cid]}]})
	check(bool(r.results[0].ok) and int(r.profile.gold) == int(phone.d.gold) and int(r.profile.gems) == int(phone.d.gems)
		and r.profile.owned == phone.d.owned, "the phone's chest roll is the server's (%s)" % str(pr.get("item", "")))
	# --- purchases: once, one account
	var g1: Dictionary = acc.grant_purchase(id, key, "gems_80", "tok-new-purchase-1")
	var g2: Dictionary = acc.grant_purchase(id, key, "gems_80", "tok-new-purchase-1")
	var g3: Dictionary = acc.grant_purchase(str(b.acct), str(b.key), "gems_80", "tok-new-purchase-1")
	check(bool(g1.ok) and int(g1.gems) == 80 and bool(g2.get("again", false)) and str(g3.get("why", "")) == "used",
		"a purchase: granted once, again = nothing more, another account = refused")
	check(str(acc.grant_purchase(id, key, "gems_80", "tok-consumed-elsewhere", true).get("why", "")) == "used",
		"a pack Google says was used up, unknown here, isn't granted again")
	# --- online looks: owned only
	e = acc.open(id, key)
	e.p.d.title = "title_legend"
	var w: Dictionary = acc.wear(id, key)
	check(str(w.title) == "" and str(w.name) != "", "online, a title not owned isn't shown")
	# --- the clamp on its own
	var cm: Dictionary = Accounts.clamp_me({"kills":-5, "rescues":"x", "cls":"../../etc", "kills_cls":{"knight":50, "mage":50}, "q":{"bogus":{}}}, 200)
	check(int(cm.kills) == 0 and int(cm.rescues) == 0 and str(cm.cls) == "villager" and (cm.kills_cls as Dictionary).values().all(func(v): return int(v) == 0)
		and (cm.q as Dictionary).is_empty(), "nonsense in a claim is zeroed")

# ---------------- 2. end to end ----------------
func _go(ph: String) -> void:
	phase = ph
	t_phase = 0.0

func _process(delta: float) -> bool:
	t += delta
	t_phase += delta
	if raw != null:
		raw.poll()
		while raw.get_available_packet_count() > 0:
			raw_msgs.append(Net.decode(raw.get_packet()))
	match phase:
		"boot":
			if t_phase > 2.5:
				p = Profile.new("user://ecotest-phone-%d.json" % Time.get_ticks_usec(), "user://none.json")
				p.load_or_create()
				p.d.stats.matches = 20
				p.d.gold = 6000
				p.d.gems = 12345
				p.save()
				sync = EcoSync.new()
				sync.url = "ws://127.0.0.1:%d/" % port
				sync.auto_start = false
				sync.setup(p)
				sync.rejected.connect(func(op, err): notes["rejected"] = "%s:%s" % [op, err])
				root.add_child(sync)
				sync.start()
				_go("account")
		"account":
			if sync.enabled and sync._req.is_empty():
				check(int(p.d.gems) == 300 + 12 * 20 and bool(p.server_mode), "the phone has an account; its gems are the server's (%d)" % int(p.d.gems))
				p.d.gems = 99999                       # an edited save
				p.save()
				sync.pull()
				_go("tamper")
			elif t_phase > 15.0:
				check(false, "an account within 15 s")
				_finish()
		"tamper":
			if t_phase > 0.3 and sync._req.is_empty() and not sync._want:
				check(int(p.d.gems) == 300 + 12 * 20, "an edited save is put back by the next answer (%d)" % int(p.d.gems))
				var buy_id := ""
				for d_id in Eco.shop_daily(p.now()):
					if Eco.item_price(d_id, p.now()).has("gold") and not p.owns(d_id) and int(Eco.item_price(d_id).gold) <= int(p.d.gold):
						buy_id = d_id
						break
				notes["buy"] = buy_id
				var ok: bool = bool(p.buy(buy_id).ok)
				check(ok and sync.pending() == 1, "a shop purchase is made at once and waits to go up")
				_go("bought")
		"bought":
			if t_phase > 0.5 and sync.pending() == 0 and sync._req.is_empty():
				check(p.owns(str(notes.buy)) and sync.online, "the server kept the purchase (%s)" % str(notes.buy))
				gold_before = int(p.d.gold)
				sync.request_ticket(func(tk): notes["ticket"] = tk)
				_go("ticket")
		"ticket":
			if notes.has("ticket"):
				check(str(notes.ticket) != "" and sync.ticket == str(notes.ticket), "a VS BOTS ticket from the server")
				var me := {"cls":"knight", "cls_main":"knight", "kills":12, "rescues":1, "gathered":10, "fed":0, "gate_dmg":300.0, "lifts":0}
				p.apply_match(me, true, false, false)       # straight away: far too soon for a real match
				check(int(p.d.gold) > gold_before, "the phone shows the match's rewards at once")
				_go("too_soon")
		"too_soon":
			if t_phase > 0.3 and sync.pending() == 0 and sync._req.is_empty():
				check(int(p.d.gold) == gold_before and str(notes.get("rejected", "")) == "match:too short",
					"the server refused it: the rewards are taken back (%s)" % str(notes.get("rejected", "")))
				matches_before = int(p.d.stats.matches)
				raw = WebSocketPeer.new()
				raw.connect_to_url("ws://127.0.0.1:%d/" % port)
				_go("online")
		"online":
			if not raw_sent and raw.get_ready_state() == WebSocketPeer.STATE_OPEN:
				raw.put_packet(Net.encode({"t":"hello", "v":Net.VERSION, "name":"Edited Name", "build":"0.31.108-fatebound",
					"title":"title_legend", "acct":str(p.d.account.id), "key":str(p.d.account.key)}))
				raw_sent = true
			var ended := false
			for m in raw_msgs:
				if str(m.get("t", "")) == "pn":
					notes["pn"] = m
				if str(m.get("t", "")) == "s" and m.has("e"):
					for ev in m.e:
						if str(ev.get("k", "")) == "end":
							ended = true
			raw_msgs.clear()
			if ended:
				var pn: Dictionary = notes.get("pn", {})
				check(not (pn.get("tt", {}) as Dictionary).values().has("title_legend"), "online: the title the account doesn't own isn't shown")
				raw.close()
				sync.pull()
				_go("paid")
			elif t_phase > 30.0:
				check(false, "the online match ended within 30 s")
				_finish()
		"paid":
			if t_phase > 0.5 and sync._req.is_empty() and not sync._want:
				var h: Array = p.d.history
				check(int(p.d.stats.matches) == matches_before + 1 and not h.is_empty() and bool(h[0].online),
					"the online match was paid to the account by the server (%d matches)" % int(p.d.stats.matches))
				raw = WebSocketPeer.new()
				raw.inbound_buffer_size = 1 << 21
				raw.connect_to_url("ws://127.0.0.1:%d/" % port)
				raw_sent = false
				gold_before = int(p.d.gems)
				_go("iap")
		"iap":
			if not raw_sent and raw.get_ready_state() == WebSocketPeer.STATE_OPEN:
				raw.put_packet(Net.encode({"t":"iap", "v":Net.VERSION, "product":"gems_80", "token":"tok-e2e-purchase-0001",
					"acct":str(p.d.account.id), "key":str(p.d.account.key)}))
				raw_sent = true
			for m in raw_msgs:
				if str(m.get("t", "")) == "iap":
					var g: Dictionary = m.get("granted", {})
					check(bool(m.ok) and bool(g.get("ok", false)) and int(g.get("profile", {}).get("gems", 0)) == gold_before + 80,
						"a confirmed purchase is granted to the account by the server (+80 gems)")
					_finish()
			raw_msgs.clear()
			if t_phase > 20.0:
				check(false, "a purchase answer within 20 s")
				_finish()
	return false

func _finish() -> void:
	if pid > 0:
		OS.kill(pid)
		OS.execute("kill", ["-9", str(pid)])
		pid = -1
	print("ECO_SERVER_PASS" if fails.is_empty() else "ECO_SERVER_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
