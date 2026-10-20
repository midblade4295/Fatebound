extends SceneTree
# 0.31.189 (Kevin: "Now check the gold and gem economy and make sure it's balanced"; his calls: "Frostbound for gold",
# a hero in "About 10 days" for a casual player). tools/economy_sim.gd played 16 weeks of four kinds of free player on
# the real code (light 2 matches a day 5 days a week, casual 3, regular 5, grinder 10): the numbers that came out of it.
#  1. Gold buys heroes at 25,000 (launch 50,000; a shard 15,000, melted 2,500) and, once they're yours, a Frostbound
#     outfit at 40,000 -- the heroes' own sets stay gems-only.
#  2. Profile.buy_skin_gold: only an outfit with a gold price; not without the gold; a locked hero's outfit brings him;
#     worn at once; the op replays to the same profile, and the server's account takes it.
#  3. The free gems: weekly orders 10-15 each, chests (no gems in a Wooden one, 25 % of 5 in a Silver, 10-15 in a Gold,
#     30-40 in a Royal), the quests' last step 100; the premium track's own tiers 260 gems, so with its chests it pays
#     back about half its 950 -- not the ~880 of 0.31.188. Fewer shards: one on the free track, two on the premium.
#  4. The gold per match: a win 150 + what was done, a loss 75; the first win of the day 150; no gold bonus per daily
#     order; the login week 950 gold.
#  5. The shop: a Frostbound card says "or 40K"; BUY asks gems or gold; gold buys it.
#   godot --headless --path godot -s res://tests/economy_balance_test.gd
const App = preload("res://scripts/app/siege_app.gd")
const Profile = preload("res://scripts/meta/profile.gd")
const Eco = preload("res://scripts/meta/economy.gd")
const Accounts = preload("res://server/eco_accounts.gd")

var fails: Array = []
var app
var frames := 0
var step := 0

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func fresh(tag: String) -> Profile:
	var p := Profile.new("user://econbal_%s_%d.json" % [tag, Time.get_ticks_usec()], "user://none_%d.json" % Time.get_ticks_usec())
	p.now_override = Eco.SIX_LAUNCH + 30 * 86400          # (after the six's launch price)
	p.load_or_create()
	return p

func _init() -> void:
	# ---- 1. what gold buys
	var t := Eco.SIX_LAUNCH + 30 * 86400
	var prices_ok := Eco.HERO_PRICES.values().all(func(g): return int(g) == 25000) and Eco.LAUNCH_GOLD == 50000
	check(prices_ok and Eco.hero_price("golem", t) == {"gold": 25000, "gems": 450} and Eco.shard_unlock_gold("golem", t) == 15000
		and Eco.shard_melt_gold("golem", t) == 2500, "a hero 25,000 gold or 450 gems (launch 50,000 / 600); a shard 15,000, melted 2,500")
	var frost_gold := true
	var sets_gems_only := true
	for id in Eco.SKINS:
		var sk: Dictionary = Eco.SKINS[id]
		if str(sk.line) == "frost":
			frost_gold = frost_gold and int(sk.get("gold", 0)) == 40000 and int(sk.gems) == 390
		else:
			sets_gems_only = sets_gems_only and not sk.has("gold") and int(sk.gems) == 750
	check(frost_gold and sets_gems_only, "every Frostbound outfit 390 gems or 40,000 gold; the heroes' own sets 750 gems, no gold")
	# ---- 2. buying one with gold
	var p := fresh("gold")
	p.d.gold = 39999
	check(not bool(p.buy_skin_gold("golem_frost").ok), "39,999 gold: not enough")
	check(not bool(p.buy_skin_gold("golem_geode").ok) and str(p.buy_skin_gold("golem_geode").get("error", "")) == "Not for gold",
		"a hero's own set isn't sold for gold")
	p.d.gold = 50000
	var r: Dictionary = p.buy_skin_gold("golem_frost")
	check(bool(r.ok) and bool(r.hero) and p.owns_skin("golem_frost") and p.owns_hero("golem") and p.worn_skin("golem") == "golem_frost"
		and int(p.d.gold) == 10000, "40,000 gold: the Frostbound Golem, the Golem with it, worn at once")
	check(not bool(p.buy_skin_gold("golem_frost").ok) and int(p.d.gold) == 10000, "...once")
	var a := fresh("opa")
	var b := fresh("opb")
	a.d.gold = 90000
	b.d = b._normalized(a.d.duplicate(true))
	var log: Array = []
	a.on_op = func(op, args): log.append([op, args.duplicate(true)])
	a.buy_skin_gold("mage_frost")
	a.buy_skin_gold("knight_frost")
	for e in log:
		b.apply_op(str(e[0]), JSON.parse_string(JSON.stringify(e[1])))
	check(log.size() == 2 and b.d.skins == a.d.skins and b.d.skin_on == a.d.skin_on and int(b.d.gold) == int(a.d.gold) and int(a.d.gold) == 10000,
		"buy_skin_gold replays to the same profile")
	var tmp := OS.get_user_data_dir().path_join("econbal-srv-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	var acc = Accounts.new(tmp)
	var made: Dictionary = acc.handle({"t":"eco", "new":true})
	var e2: Dictionary = acc.open(str(made.acct), str(made.key))
	e2.p.d.gold = 45000
	e2.p.save()
	var sr: Dictionary = acc.handle({"t":"eco", "acct":str(made.acct), "key":str(made.key), "ops":[{"s":1, "op":"buy_skin_gold", "a":["druid_frost"]}]})
	check(bool(sr.results[0].ok) and (sr.profile.skins as Array).has("druid_frost") and int(sr.profile.gold) == 5000, "the server's account takes it (%s)" % str(sr.results))
	# ---- 3. the free gems
	var weekly_ok := true
	for id in Eco.CHALLENGES:
		var c: Dictionary = Eco.CHALLENGES[id]
		if str(c.span) == "weekly":
			weekly_ok = weekly_ok and int(c.get("gems", 0)) >= 10 and int(c.get("gems", 0)) <= 15
	check(weekly_ok, "weekly orders 10-15 gems each (25-40 until 0.31.189)")
	var mean := {}
	for k in Eco.CHESTS:
		var c: Dictionary = Eco.CHESTS[k]
		mean[k] = float(c.gems_chance) * (float(c.gems[0]) + float(c.gems[1])) * 0.5
	check(mean.wooden == 0.0 and is_equal_approx(mean.silver, 1.25) and is_equal_approx(mean.gold, 12.5) and is_equal_approx(mean.royal, 35.0),
		"gems a chest, on average: Wooden 0, Silver 1.25, Gold 12.5, Royal 35 (%s)" % str(mean))
	var prem_gems := 0
	var prem_gold_chests := 0
	var prem_royal := 0
	var free_shards := 0
	var prem_shards := 0
	for tier in range(1, Eco.PASS_TIERS + 1):
		var pr := Eco.pass_reward(2, tier, true)
		prem_gems += int(pr.get("gems", 0))
		prem_gold_chests += 1 if str(pr.get("chest", "")) == "gold" else 0
		prem_royal += 1 if str(pr.get("chest", "")) == "royal" else 0
		prem_shards += 1 if pr.has("shard") else 0
		free_shards += 1 if Eco.pass_reward(2, tier, false).has("shard") else 0
	var payback: float = prem_gems + prem_gold_chests * float(mean.gold) + prem_royal * float(mean.royal)
	check(prem_gems == 260 and payback > 400.0 and payback < 520.0, "the premium track: %d gems on its tiers, ~%d with its chests -- about half its %d" % [prem_gems, int(payback), Eco.PREMIUM_COST])
	check(free_shards == 1 and prem_shards == 2, "hero shards on the pass: one free, two premium (were three and three)")
	check(Eco.QUEST_FINAL == {"gems": 100, "chest": "royal"}, "a quest's last step: 100 gems and a Royal chest")
	# ---- 4. gold per match
	var win := Eco.match_rewards({"kills": 5, "towers": 1, "lh": 40}, true, false, false, false)
	var loss := Eco.match_rewards({}, false, false, false, false)
	var first := Eco.match_rewards({}, true, false, false, true)
	check(int(win.gold) == 150 + 15 + 25 + 40 and int(loss.gold) == 75 and int(first.gold) == 150 + 150 and Eco.DAILY_GOLD == 0,
		"a win 150 + what was done (%d), a loss 75, the first win of the day +150, no gold bonus per daily order" % int(win.gold))
	var week := 0
	for rw in Eco.LOGIN_REWARDS:
		week += int(rw.get("gold", 0))
	check(week == 950, "the login week: 950 gold (was 1,550)")
	# ---- 5. the shop
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:1")
	var base := "user://econbal-ui-%d" % Time.get_ticks_usec()
	app = App.new()
	app.profile_path = base + "-profile.json"
	app.legacy_path = base + "-none.json"
	root.add_child(app)

func btn(key: String) -> Button:
	for c in app.find_children("*", "Button", true, false):
		if str(c.get_meta("action_key", "")) == key and (c as Control).is_visible_in_tree() and not c.is_queued_for_deletion():
			return c
	return null

func has_text(node: Node, s: String) -> bool:
	for c in node.find_children("*", "Label", true, false):
		if (c as Label).text.contains(s) and (c as Control).is_visible_in_tree() and not c.is_queued_for_deletion():
			return true
	return false

func _process(_d: float) -> bool:
	frames += 1
	if frames < 8:
		return false
	var p = app.profile
	match step:
		0:
			p.d.gold = 45000
			p.d.gems = 0
			p.d.tutorial_done = true
			app.show_tab("shop")
		1:
			var bb := btn("skin_buy_rogue_frost")
			check(bb != null and not bb.disabled and has_text(app, "or 40K") and btn("skin_buy_rogue_velvet") != null and btn("skin_buy_rogue_velvet").disabled,
				"the shop: a Frostbound card says \"or 40K\" and can be bought with gold alone; a set (gems only) can't")
			if bb != null:
				bb.pressed.emit()
		2:
			var bg := btn("modal_gold")
			var bm := btn("modal_yes")
			check(app.modal != null and bg != null and not bg.disabled and bm != null and bm.disabled and has_text(app.modal, "390 gems or 40,000 gold"),
				"BUY asks: 390 gems (not enough) or 40,000 gold")
			if bg != null:
				bg.pressed.emit()
		3:
			check(p.owns_skin("rogue_frost") and int(p.d.gold) == 5000 and p.worn_skin("rogue") == "rogue_frost", "bought with gold, worn")
			print("ECONOMY_BALANCE_PASS" if fails.is_empty() else "ECONOMY_BALANCE_FAIL %s" % str(fails))
			quit(0 if fails.is_empty() else 1)
	step += 1
	return false
