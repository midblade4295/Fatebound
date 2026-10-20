extends SceneTree
# 0.31.108 (Kevin: "I want you to fix everything" -- the economy review): the fixes, on the real tables and profile.
#  - (until 0.31.188, the pass's weapons: one already owned was swapped; the pass holds no cosmetics now)
#  - from season 2 the premium gem tiers give gold (Embers until 0.31.184); season 1 is unchanged;
#  - Silver chests: a chance of gems (0.31.188: 40% of 5-10, no weapons in any chest -- they were Wooden rares, Royal
#    legendaries, and vaulted pass weapons sold in the Featured shop until then);
#  - reward chests wait for a slot instead of turning into gold; a match's chest still turns into gold when full;
#  - the starter pack 500 gems / 300 Embers (0.31.184: 3,000 gold) / an epic (0.31.188: a Hero Token; the Forge and the
#    Arsenals are gone);
#  - ops replay to the same profile (what the server relies on), and a match's op carries only what a result needs.
#   godot --headless --path godot -s res://tests/economy_fix_test.gd
const Profile = preload("res://scripts/meta/profile.gd")
const Eco = preload("res://scripts/meta/economy.gd")
const Net = preload("res://scripts/siege/siege_net.gd")

var fails: Array = []
const S1 := 1791000000                      # 2026-10-03: season 1
var S2 := Eco.SEASON_EPOCH + Eco.SEASON_DAYS * 86400 + 3 * 86400

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func fresh(tag: String, at: int):
	var p = Profile.new("user://ecofix-%s-%d.json" % [tag, Time.get_ticks_usec()], "user://none.json")
	p.now_override = at
	p.load_or_create()
	return p

func _init() -> void:
	# ---- chests
	var with_gems := 0
	var gem_amounts := {}
	for i in 2000:
		var r := Eco.roll_chest("silver", i)
		if int(r.gems) > 0:
			with_gems += 1
			gem_amounts[int(r.gems)] = true
	var amounts: Array = gem_amounts.keys()
	amounts.sort()
	check(absf(with_gems / 2000.0 - 0.25) < 0.04 and amounts == [5], "Silver: a 25%% chance of 5 gems (%.1f%%; 0.31.189 -- 0.31.188 40%% of 5-10, before it 30%% of 5)" % (with_gems / 20.0))
	# ---- pass: season 1 unchanged, gold from season 2 (0.31.184: the 60 Embers' 600 gold)
	check(Eco.pass_reward(1, 4, true) == {"gems": 60} and Eco.pass_reward(2, 4, true) == {"gold": Eco.PASS_GOLD_GEM_TIER},
		"premium tier 4: 60 gems in season 1, %d gold from season 2" % Eco.PASS_GOLD_GEM_TIER)
	# ---- reward chests wait
	var q = fresh("queue", S1)
	for i in Eco.CHEST_SLOTS:
		q.add_chest("wooden", {})
	var out := {}
	q.add_chest("royal", out, true)
	check(q.chests_waiting() == 1 and bool(out.chests[0].get("queued", false)), "a reward chest with the slots full waits for a slot")
	var gold0 := int(q.d.gold)
	q.add_chest("silver", {})
	check(int(q.d.gold) == gold0 + int(Eco.CHEST_FULL_GOLD.silver) and q.chests_waiting() == 1, "a match's chest with the slots full still turns into gold")
	q.start_unlock(0)
	q.now_override += 3600
	q.open_chest(0)
	check(q.chests_waiting() == 0 and str(q.chests()[q.chests().size() - 1].kind) == "royal", "opening a chest lets the waiting Royal chest in")
	var lv = fresh("level", S1)
	for i in Eco.CHEST_SLOTS:
		lv.add_chest("wooden", {})
	lv.d.level = 9
	var lo := {"levels":[], "tiers":[], "chests":[]}
	lv._add_xp(Eco.level_xp(9), lo)
	check(int(lv.d.level) == 10 and lv.chests_waiting() == 1, "the level-10 Royal chest is kept, not turned into 700 gold")
	# ---- prices
	check(int(Net.IAP.starter_pack.gems) == 500 and int(Net.IAP.starter_pack.get("gold", 0)) == 3000 and not Net.IAP.starter_pack.has("embers")
		and int(Net.IAP.starter_pack.get("token", 0)) == 1 and not Net.IAP.starter_pack.has("weapon"), "starter pack: 500 gems, 3,000 gold (its 300 Embers), a Hero Token (0.31.188, was an epic)")
	# ---- ops replay to the same profile
	var a = fresh("opa", S1)
	var b = fresh("opb", S1)
	a.d.gold = 50000
	a.d.gems = 2000
	a.d.chests.salt = 77
	b.d = b._normalized(a.d.duplicate(true))
	var log: Array = []
	a.on_op = func(op, args): log.append([op, args.duplicate(true)])
	a.buy_skin("knight_frost")
	a.add_chest("gold", {})
	a.on_op = Callable()
	b.add_chest("gold", {})
	a.on_op = func(op, args): log.append([op, args.duplicate(true)])
	a.start_unlock(0)
	a.skip_chest(0)
	a.open_chest(0)
	a.set_name("Midblade")
	a.wear_skin("knight", "")
	for o in log:
		b.apply_op(str(o[0]), JSON.parse_string(JSON.stringify(o[1])))      # (as JSON, the way it travels)
	var da: Dictionary = a.d.duplicate(true)
	var db: Dictionary = b.d.duplicate(true)
	for d in [da, db]:
		d.erase("history")
		d.erase("skins_refunded")                     # (normalizing marks the old skin refund done)
		d.cloud = {}
	var same := JSON.stringify(da, "", true) == JSON.stringify(db, "", true)
	if not same:
		for k in da:
			if JSON.stringify(da[k], "", true) != JSON.stringify(db.get(k), "", true):
				print("  differs: %s\n    a %s\n    b %s" % [k, JSON.stringify(da[k], "", true).left(300), JSON.stringify(db.get(k), "", true).left(300)])
		for k in db:
			if not da.has(k):
				print("  only in b: %s = %s" % [k, str(db[k]).left(200)])
	check(log.size() == 6 and same, "6 ops replayed (as JSON) give the same profile, chest roll included (%d ops; 0.31.184: no Embers to buy, 0.31.185: no gold for gems, 0.31.188: an outfit, not a weapon)" % log.size())
	check(not b.apply_op("buy_skin", ["x".repeat(65)]).ok and not b.apply_op("buy", ["knight_frost"]).ok and not b.apply_op("claim_tier", ["1", true]).ok and not b.apply_op("grant_iap", ["gems_80", "t"]).ok,
		"long, mistyped and unlisted ops are refused")
	var me := {"kills":3, "cls":"knight", "pos":Vector2(1, 2), "path":PackedVector2Array(), "task":{"x":1}, "q":{"knight":{"t":70.0}}}
	var sm: Dictionary = Profile.slim_me(me)
	check(sm.has("kills") and sm.has("q") and not sm.has("pos") and not sm.has("path") and not sm.has("task"), "a match's op carries only what a result needs")
	print("ECONOMY_FIX_PASS" if fails.is_empty() else "ECONOMY_FIX_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
