extends SceneTree
# 0.31.208, server (Kevin: "Gold and gem spending: buying heroes, outfits or the pass with in-game currency to have
# tracking system for server"): every gold or gem an account spends is written to the server's usage statistics as a
# "spend" (server/eco_accounts.gd spend_props -> server/analytics.gd), with what it bought and what it cost.
#  1. server/eco_accounts.gd and server/analytics.gd in this process, wired as siege_server.gd wires them, one account:
#     a hero for gold, a hero for gems, an outfit for gems that brings its hero, a rare outfit for gold, an outfit on
#     this week's sale, the premium pass, a tier skip, a chest skip -- one spend each, the amounts the balances moved,
#     what was left, the level, the build the ops came from; a buy it can't afford, an op sent again, a shard melted
#     (gold in) and an outfit worn: no spend; the server's own gold for a clan (pay_gold): a spend; an account that
#     turned the statistics off: nothing. No line has the account's key or name.
#  2. the REAL server (its own process, port 8133): a new account (its progress taken in) buys a hero over the "eco"
#     socket -- the spend is in the day's statistics file.
#   godot --headless --path godot -s res://tests/spend_tracking_test.gd
const EcoAccounts = preload("res://server/eco_accounts.gd")
const Analytics = preload("res://server/analytics.gd")
const Eco = preload("res://scripts/meta/economy.gd")
const Net = preload("res://scripts/siege/siege_net.gd")
const Diag = preload("res://scripts/siege/siege_diag.gd")

const BUILD := "0.31.208-fatebound"
const NAME := "Quokka Spendthrift"

var fails: Array = []
var port := 8133
var pid := -1
var srv_state := ""
var phase := "local"
var t_phase := 0.0
var ws: WebSocketPeer
var inbox: Array = []
var acct2 := ""
var key2 := ""

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func spends_in(state: String, acct := "") -> Array:
	var out := []
	var da := DirAccess.open(state.path_join("analytics"))
	if da == null:
		return out
	for fn in da.get_files():
		if not fn.ends_with(".jsonl"):
			continue
		for ln in FileAccess.get_file_as_string(state.path_join("analytics").path_join(fn)).split("\n", false):
			var v: Variant = JSON.parse_string(ln)
			if v is Dictionary and str(v.get("ev", "")) == "spend" and (acct == "" or str(v.get("acct", "")) == acct):
				out.append(v)
	return out

func raw_lines(state: String) -> String:
	var s := ""
	var da := DirAccess.open(state.path_join("analytics"))
	if da != null:
		for fn in da.get_files():
			if fn.ends_with(".jsonl"):
				s += FileAccess.get_file_as_string(state.path_join("analytics").path_join(fn))
	return s

func _init() -> void:
	_local()
	# 2. the real server
	srv_state = OS.get_user_data_dir().path_join("spend-srv-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(srv_state)
	OS.set_environment("SIEGE_PORT", str(port))
	OS.set_environment("SIEGE_HOST", "127.0.0.1")
	OS.set_environment("STATE_DIRECTORY", srv_state)
	pid = OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://server/siege_server.gd"])
	check(pid > 0, "2. server process started")
	phase = "boot"

# ---------------- 1. in this process ----------------
func _local() -> void:
	var state := OS.get_user_data_dir().path_join("spend-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(state)
	var eco = EcoAccounts.new(state)
	var an = Analytics.new(state)
	eco.spend_fn = func(acct: String, p: Dictionary, build: String): an.server_event(acct, "spend", p, build)
	var made: Dictionary = eco.handle({"t":"eco", "new":true, "import":{}})
	var acct := str(made.acct)
	var key := str(made.key)
	var e: Dictionary = eco.open(acct, key)
	var p = e.p
	p.d.name = NAME
	p.d.gold = 200000
	p.d.gems = 20000
	p.add_chest("gold", {})
	var chest_id := int(p.d.chests.slots[0].id)
	p.save()
	var now := int(Time.get_unix_time_from_system())
	# an outfit on this week's sale, not one of the others bought here
	var sale_id := ""
	var sale_week := 0
	for id in Eco.SKINS:
		if id in ["stormcaller_stormforged", "mage_frost"]:
			continue
		var o := Eco.skin_offer(str(id), now)
		if int(o.off) > 0:
			sale_id = str(id)
			sale_week = int(o.week)
			break
	check(sale_id != "", "1. an outfit on this week's sale (%s)" % sale_id)
	var steps := [
		["buy_hero", ["golem"]], ["buy_hero_gems", ["dragoon"]], ["buy_skin", ["stormcaller_stormforged"]],
		["buy_skin_gold", ["mage_frost"]], ["buy_sale", [sale_id, sale_week, false]], ["buy_premium", []],
		["skip_tiers", []], ["skip_chest", [chest_id]],
	]
	var before: Array = []
	var s := 0
	for st in steps:
		s += 1
		before.append([int(p.d.gold), int(p.d.gems), int(p.skip_offer().tiers)])
		var r: Dictionary = eco.handle({"t":"eco", "build":BUILD, "acct":acct, "key":key, "ops":[{"s":s, "op":st[0], "a":st[1]}]})
		check(bool(r.ok) and bool(r.results[0].ok), "1. %s accepted" % str(st[0]))
		before[before.size() - 1].append(int(p.d.gold))
		before[before.size() - 1].append(int(p.d.gems))
	an.flush()
	var sp := spends_in(state, acct)
	check(sp.size() == steps.size(), "1. one spend per buy (%d of %d)" % [sp.size(), steps.size()])
	var want_cat := {"buy_hero":"hero", "buy_hero_gems":"hero", "buy_skin":"outfit", "buy_skin_gold":"outfit", "buy_sale":"outfit",
		"buy_premium":"pass", "skip_tiers":"pass", "skip_chest":"chest"}
	var want_item := {"buy_hero":"golem", "buy_hero_gems":"dragoon", "buy_skin":"stormcaller_stormforged", "buy_skin_gold":"mage_frost",
		"buy_sale":sale_id, "buy_premium":"premium", "skip_tiers":"tiers", "skip_chest":"gold"}
	for i in mini(sp.size(), steps.size()):
		var l: Dictionary = sp[i]
		var q: Dictionary = l.p
		var op := str(steps[i][0])
		var b: Array = before[i]
		var dg: int = int(b[0]) - int(b[3])
		var dm: int = int(b[1]) - int(b[4])
		check(str(q.op) == op and str(q.cat) == str(want_cat[op]) and str(q.item) == str(want_item[op]),
			"1. %s: cat %s, item %s" % [op, str(q.get("cat", "")), str(q.get("item", ""))])
		check(int(q.gold) == dg and int(q.gems) == dm and (dg > 0 or dm > 0),
			"1. %s: cost %d gold %d gems (the balances moved %d / %d)" % [op, int(q.get("gold", -1)), int(q.get("gems", -1)), dg, dm])
		check(int(q.gold_left) == int(b[3]) and int(q.gems_left) == int(b[4]) and int(q.lvl) >= 1, "1. %s: what was left (%d gold, %d gems)" % [op, int(q.get("gold_left", -1)), int(q.get("gems_left", -1))])
		check(str(l.src) == "s" and str(l.b) == BUILD and str(l.acct) == acct, "1. %s: the server's, the ops' build, the account" % op)
		match op:
			"buy_hero":
				check(int(q.gold) == int(Eco.hero_price("golem", now).gold) and int(q.gems) == 0, "1. the Golem for his gold price")
			"buy_hero_gems":
				check(int(q.gems) == int(Eco.hero_price("dragoon", now).gems) and int(q.gold) == 0, "1. the Dragoon for his gem price")
			"buy_skin":
				check(bool(q.get("hero", false)) and int(q.gems) == int(Eco.SKINS["stormcaller_stormforged"].gems), "1. Stormforged at full gems, the Stormcaller with it (hero)")
			"buy_skin_gold":
				check(not bool(q.get("hero", true)) and int(q.gold) == int(Eco.SKINS["mage_frost"].gold), "1. Frostbound Mage for gold (the Mage was already everyone's)")
			"buy_sale":
				check(int(q.get("off", 0)) > 0 and int(q.gems) < int(Eco.SKINS[sale_id].gems), "1. the sale: %d%% off (%d of %d gems)" % [int(q.get("off", 0)), int(q.gems), int(Eco.SKINS[sale_id].gems)])
			"buy_premium":
				check(int(q.gems) == Eco.PREMIUM_COST and q.has("season"), "1. the premium pass (%d gems, season %s)" % [int(q.gems), str(q.get("season", "?"))])
			"skip_tiers":
				check(int(q.get("n", 0)) == int(b[2]) and int(q.gems) == int(b[2]) * Eco.TIER_SKIP_GEMS, "1. a tier skip: %d tiers" % int(q.get("n", 0)))
			"skip_chest":
				check(int(q.gems) > 0 and int(q.gold) == 0, "1. a gold chest's skip (%d gems)" % int(q.gems))
	# no spend: a buy it can't afford, an op sent again, gold coming in, an outfit worn
	p.d.gems = 0
	p.d.shards.append("musketeer")
	p.save()
	var r2: Dictionary = eco.handle({"t":"eco", "build":BUILD, "acct":acct, "key":key, "ops":[
		{"s":s + 1, "op":"buy_hero_gems", "a":["duelist"]}, {"s":s, "op":"skip_chest", "a":[chest_id]},
		{"s":s + 2, "op":"melt_shard", "a":["musketeer"]}, {"s":s + 3, "op":"wear_skin", "a":["stormcaller", ""]}]})
	check(not bool(r2.results[0].ok) and bool(r2.results[1].get("dup", false)) and bool(r2.results[2].ok) and bool(r2.results[3].ok),
		"1. can't afford / sent again / melted / worn: as expected")
	an.flush()
	check(spends_in(state, acct).size() == steps.size(), "1. ...and none of them a spend")
	# the server's own: a clan's gold
	var g0 := int(p.d.gold)
	check(eco.pay_gold(acct, 1500, "clan"), "1. a clan paid for (pay_gold)")
	an.flush()
	var all := spends_in(state, acct)
	var last: Dictionary = all.back() if not all.is_empty() else {}
	check(all.size() == steps.size() + 1 and str(last.get("p", {}).get("cat", "")) == "clan" and int(last.p.gold) == 1500
		and int(last.p.gold_left) == g0 - 1500, "1. the clan's gold: a spend (cat clan, 1500 gold)")
	# statistics off: nothing
	var made2: Dictionary = eco.handle({"t":"eco", "new":true, "import":{}})
	var e2: Dictionary = eco.open(str(made2.acct), str(made2.key))
	e2.p.d.gold = 90000
	e2.p.save()
	an.set_opt_out(str(made2.acct), true)
	var r3: Dictionary = eco.handle({"t":"eco", "build":BUILD, "acct":str(made2.acct), "key":str(made2.key), "ops":[{"s":1, "op":"buy_hero", "a":["druid"]}]})
	an.flush()
	check(bool(r3.results[0].ok) and spends_in(state, str(made2.acct)).is_empty(), "1. an account with the statistics off: bought, nothing written")
	var raw := raw_lines(state)
	check(raw.find(key) < 0 and raw.find(NAME) < 0 and raw.find(str(made2.key)) < 0, "1. no key or name in any line")
	an.close()

# ---------------- 2. the real server ----------------
func _say(msg: Dictionary) -> void:
	ws.put_packet(Net.encode(msg))

func _process(delta: float) -> bool:
	t_phase += delta
	if ws != null:
		ws.poll()
		while ws.get_available_packet_count() > 0:
			inbox.append(Net.decode(ws.get_packet()))
	match phase:
		"boot":
			if t_phase > 2.5:
				ws = WebSocketPeer.new()
				ws.connect_to_url("ws://127.0.0.1:%d/" % port)
				inbox = []
				phase = "new"
				t_phase = 0.0
		"new":
			if ws.get_ready_state() == WebSocketPeer.STATE_OPEN and t_phase < 50.0 and not has_meta("sent_new"):
				set_meta("sent_new", true)
				_say({"t":"eco", "v":Net.VERSION, "build":Diag.BUILD, "new":true, "import":{"gold":60000, "stats":{"matches":60}}})
			var got := inbox.filter(func(m): return str(m.get("t", "")) == "eco")
			if not got.is_empty():
				acct2 = str(got[0].get("acct", ""))
				key2 = str(got[0].get("key", ""))
				check(acct2 != "" and int(got[0].profile.gold) >= int(Eco.hero_price("golem", int(Time.get_unix_time_from_system())).gold), "2. a new account with its gold taken in (%d)" % int(got[0].get("profile", {}).get("gold", 0)))
				ws.close()
				ws = WebSocketPeer.new()
				ws.connect_to_url("ws://127.0.0.1:%d/" % port)
				inbox = []
				phase = "buy"
				t_phase = 0.0
			elif t_phase > 20.0:
				check(false, "2. the server answered the new account")
				_finish()
		"buy":
			if ws.get_ready_state() == WebSocketPeer.STATE_OPEN and not has_meta("sent_buy"):
				set_meta("sent_buy", true)
				_say({"t":"eco", "v":Net.VERSION, "build":Diag.BUILD, "acct":acct2, "key":key2, "ops":[{"s":1, "op":"buy_hero", "a":["golem"]}]})
			var got := inbox.filter(func(m): return str(m.get("t", "")) == "eco")
			if not got.is_empty():
				check(bool(got[0].ok) and bool((got[0].results as Array)[0].ok), "2. the Golem bought over the eco socket")
				phase = "look"
				t_phase = 0.0
			elif t_phase > 20.0:
				check(false, "2. the server answered the buy")
				_finish()
		"look":
			var sp := spends_in(srv_state, acct2)
			if not sp.is_empty() or t_phase > 6.0:
				var q: Dictionary = sp[0].p if not sp.is_empty() else {}
				check(sp.size() == 1 and str(q.get("cat", "")) == "hero" and str(q.get("item", "")) == "golem"
					and int(q.get("gold", 0)) == int(Eco.hero_price("golem", int(Time.get_unix_time_from_system())).gold)
					and str(sp[0].get("b", "")) == Diag.BUILD,
					"2. the real server wrote the spend (hero golem, %d gold, build %s)" % [int(q.get("gold", 0)), str(sp[0].get("b", "")) if not sp.is_empty() else "-"])
				_finish()
	return false

func _finish() -> void:
	if pid > 0:
		OS.kill(pid)
		pid = -1
	print("SPEND_TRACKING_PASS" if fails.is_empty() else "SPEND_TRACKING_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
