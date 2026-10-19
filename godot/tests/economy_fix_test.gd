extends SceneTree
# 0.31.108 (Kevin: "I want you to fix everything" -- the economy review): the fixes, on the real tables and profile.
#  - a pass item already owned is swapped (another pass weapon of its rarity, else gold -- Embers until 0.31.184) and the
#    tier remembers it;
#  - from season 2 the premium gem tiers give gold (Embers until 0.31.184); season 1 is unchanged;
#  - Silver chests: a 30% chance of 5 gems; Wooden chests' items are rares; the Royal chest's legendary roll gains the
#    earlier passes' legendaries; earlier passes' weapons are sold in the Featured shop for gems (vaulted);
#  - reward chests wait for a slot instead of turning into gold; a match's chest still turns into gold when full;
#  - the Forge's gold doubled, the Hunter Arsenal 80 gems, the starter pack 500 gems / 300 Embers (0.31.184: 3,000 gold) /
#    an epic;
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
	var wooden_rar := {}
	for i in 2000:
		var r := Eco.roll_chest("silver", i, [], 0)
		if int(r.gems) > 0:
			with_gems += 1
			gem_amounts[int(r.gems)] = true
		var w := Eco.roll_chest("wooden", i, [], 0)
		if str(w.item) != "":
			wooden_rar[str(Eco.item(str(w.item)).rarity)] = true
	check(absf(with_gems / 2000.0 - 0.3) < 0.04 and gem_amounts.keys() == [5], "Silver: a 30%% chance of 5 gems (%.1f%%)" % (with_gems / 20.0))
	check(wooden_rar.keys() == ["rare"], "Wooden chest items are rares now (no more Sparkstick every time) %s" % str(wooden_rar.keys()))
	var leg1 := Eco.chest_pool("legendary", 1)
	var leg2 := Eco.chest_pool("legendary", 2)
	check(leg1 == ["crus_wpn_maul"] and leg2.size() > 1 and leg2.has("knight_wpn_oath"), "the Royal chest's legendary: Final Verdict in season 1, the season-1 pass legendaries join from season 2 (%d)" % leg2.size())
	# ---- vault
	check(Eco.item_price("knight_wpn_oath", S1).is_empty() and int(Eco.item_price("knight_wpn_oath", S2).get("gems", 0)) == Eco.VAULT_GEMS.legendary,
		"a season-1 pass weapon has no price in season 1, %d gems from season 2" % Eco.VAULT_GEMS.legendary)
	var vaulted_seen := false
	for w in 8:
		for id in Eco.shop_featured(S2 + w * 7 * 86400):
			if str(Eco.item(id).source) == "pass":
				vaulted_seen = true
	check(vaulted_seen and Eco.shop_featured(S1).size() == Eco.FEATURED_SLOTS, "vaulted pass weapons rotate through the Featured shop (%d slots)" % Eco.FEATURED_SLOTS)
	var s1feat: Array = Eco.shop_featured(S1)
	var all_shop := true
	for id in s1feat:
		all_shop = all_shop and str(Eco.item(id).source) == "shop"
	check(all_shop, "season 1's Featured shop has no pass weapon")
	# ---- pass: season 1 unchanged, gold from season 2 (0.31.184: the 60 Embers' 600 gold)
	check(Eco.pass_reward(1, 4, true) == {"gems": 60} and Eco.pass_reward(2, 4, true) == {"gold": Eco.PASS_GOLD_GEM_TIER},
		"premium tier 4: 60 gems in season 1, %d gold from season 2" % Eco.PASS_GOLD_GEM_TIER)
	# ---- pass: repeats swapped
	var p = fresh("swap", S2)
	check(int(p.d.pass.season) == 2, "a profile in season 2")
	for id in Eco.pass_items(1):
		if str(Eco.item(id).kind) == "weapon" and not p.d.owned.has(id):
			p.d.owned.append(id)                             # bought every season-1 pass weapon
	var tier_rep := -1
	var rep_id := ""
	for t in Eco.premium_item_tiers(2):
		var base := Eco.pass_reward(2, t, true)
		if base.has("item") and p.owns(str(base.item)):
			tier_rep = t
			rep_id = str(base.item)
			break
	check(tier_rep > 0, "season 2's premium track repeats a season-1 weapon (tier %d, %s)" % [tier_rep, rep_id])
	var got: Dictionary = p.pass_reward_for(tier_rep, true)
	check(got.get("swap", "") == rep_id and (got.has("gold") or (got.has("item") and not p.owns(str(got.item)) and str(Eco.item(str(got.item)).rarity) == str(Eco.item(rep_id).rarity))),
		"an owned pass item becomes another of its rarity, or gold: %s" % str(got))
	p.d.pass.premium = true
	p.d.pass.xp = Eco.PASS_TIERS * Eco.TIER_XP
	var e0 := int(p.d.gold)
	var res: Dictionary = p.claim_tier(tier_rep, true)
	check(bool(res.ok) and res.reward == got and (int(p.d.gold) > e0 or p.owns(str(got.get("item", "")))), "claiming it gives the swap")
	check(p.pass_reward_for(tier_rep, true) == got, "and the claimed tier keeps showing what it gave")
	var owns_all = fresh("swap2", S2)
	for id in Eco.pass_pool_weapons(2):
		owns_all.d.owned.append(id)
	var rr: Dictionary = owns_all.pass_reward_for(tier_rep, true)
	check(int(rr.get("gold", 0)) == int(Eco.DUPE_GOLD[str(Eco.item(rep_id).rarity)]), "owning every pass weapon: gold (%s)" % str(rr))
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
	check(Eco.forge_cost(3).gold == 8000 + 300 * Eco.EMBER_GOLD and int(Eco.PACKS.pack_hunter.gems) == 80, "Forge gold doubled (0.31.184: and its Embers in it); Hunter Arsenal 80 gems")
	check(int(Net.IAP.starter_pack.gems) == 500 and int(Net.IAP.starter_pack.get("gold", 0)) == 3000 and not Net.IAP.starter_pack.has("embers")
		and str(Net.IAP.starter_pack.weapon) == "epic", "starter pack: 500 gems, 3,000 gold (its 300 Embers), an epic")
	# ---- ops replay to the same profile
	var a = fresh("opa", S1)
	var b = fresh("opb", S1)
	a.d.gold = 50000
	a.d.gems = 2000
	a.d.chests.salt = 77
	b.d = b._normalized(a.d.duplicate(true))
	var log: Array = []
	a.on_op = func(op, args): log.append([op, args.duplicate(true)])
	var daily: Array = Eco.shop_daily(S1)
	a.buy(str(daily[0]))
	a.exchange("gold_s")
	a.add_chest("gold", {})
	a.on_op = Callable()
	b.add_chest("gold", {})
	a.on_op = func(op, args): log.append([op, args.duplicate(true)])
	a.start_unlock(0)
	a.skip_chest(0)
	a.open_chest(0)
	a.set_name("Midblade")
	a.equip(str(daily[0]))
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
	check(log.size() == 7 and same, "7 ops replayed (as JSON) give the same profile, chest roll included (%d ops; 0.31.184: no Embers to buy)" % log.size())
	check(not b.apply_op("buy", ["x".repeat(65)]).ok and not b.apply_op("claim_tier", ["1", true]).ok and not b.apply_op("grant_iap", ["gems_80", "t"]).ok,
		"long, mistyped and unlisted ops are refused")
	var me := {"kills":3, "cls":"knight", "pos":Vector2(1, 2), "path":PackedVector2Array(), "task":{"x":1}, "q":{"knight":{"t":70.0}}}
	var sm: Dictionary = Profile.slim_me(me)
	check(sm.has("kills") and sm.has("q") and not sm.has("pos") and not sm.has("path") and not sm.has("task"), "a match's op carries only what a result needs")
	print("ECONOMY_FIX_PASS" if fails.is_empty() else "ECONOMY_FIX_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
