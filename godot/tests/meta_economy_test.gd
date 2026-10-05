extends SceneTree
# Economy + profile: migration, rewards, levels, pass, premium, shop, equip, challenges, rollover,
# persistence, corrupt profile, catalog integrity.
const Eco = preload("res://scripts/meta/economy.gd")
const Profile = preload("res://scripts/meta/profile.gd")

var fails := []
func check(ok: bool, what: String) -> void:
	if ok: print("ok   ", what)
	else:
		fails.append(what); print("FAIL ", what)

func fresh(tag: String, legacy: Dictionary = {}) -> Profile:
	# (0.31.36: ticks since start repeat from run to run, so an old run's profile could be picked up -- a left-over
	# first win made "first win of the day" fail now and then in the suite. Wall-clock ms + a random number now.)
	randomize()
	var base := "user://meta-test-%s-%d-%d" % [tag, int(Time.get_unix_time_from_system() * 1000.0), randi()]
	if not legacy.is_empty():
		var f := FileAccess.open(base + "-legacy.json", FileAccess.WRITE)
		f.store_string(JSON.stringify(legacy)); f.close()
	var p := Profile.new(base + "-profile.json", base + "-legacy.json")
	p.now_override = 1791000000          # 2026-10-03 (season 1, a Saturday)
	p.load_or_create()
	return p

func _init() -> void:
	# ---- catalog integrity ----
	var models_ok := true
	for id in Eco.CATALOG:
		var it: Dictionary = Eco.CATALOG[id]
		if it.kind == "weapon":
			for hand in ["r", "l"]:
				var m := str(it.get(hand, ""))
				var mpath := ("res://assets/kaykit/bits/%s.gltf" % m.substr(5)) if m.begins_with("bits/") else ("res://assets/kaykit/weapons/%s.gltf" % m)
				if m != "" and not FileAccess.file_exists(mpath):
					models_ok = false; print("   missing model ", m, " for ", id)
		if it.kind == "skin" and not Color.html_is_valid(str(it.tint)):
			models_ok = false
		if it.kind != "title" and not (Eco.CLASSES + Eco.UP_CLASSES).has(str(it["class"])):        # (0.31.38: upgraded classes too)
			models_ok = false
	check(models_ok, "every catalog weapon model exists, skins have valid tints, classes valid")
	var items := Eco.pass_items(1)
	var uniq := {}
	for i in items: uniq[i] = true
	var want := Eco.PASS_FREE_ITEMS + Eco.PASS_PREMIUM_ITEMS
	check(items.size() == want and uniq.size() == want, "season pass has %d distinct cosmetics" % want)
	# Packs: price covers only what isn't owned; a fully owned pack can't be bought.
	var pk: Dictionary = Eco.PACKS["pack_warlord"]
	var full := Eco.pack_price("pack_warlord", [])
	var half := Eco.pack_price("pack_warlord", [pk.items[0]])
	check(full == int(pk.gems) and half > 0 and half < full and Eco.pack_price("pack_warlord", pk.items) == 0,
		"pack price: full %d, one item owned %d, all owned 0" % [full, half])
	for pid in Eco.PACKS:
		for id in Eco.PACKS[pid].items:
			check(not Eco.item(id).is_empty(), "pack %s item %s exists" % [pid, id])
	var pass_valid := true
	for tier in range(1, Eco.PASS_TIERS + 1):
		for prem in [false, true]:
			var r := Eco.pass_reward(1, tier, prem)
			if r.is_empty() or (r.has("item") and not Eco.CATALOG.has(r.item)): pass_valid = false
	check(pass_valid, "all 60 pass rewards are valid")
	check(Eco.shop_daily(1791000000).size() == Eco.DAILY_SLOTS and Eco.shop_featured(1791000000).size() == Eco.FEATURED_SLOTS, "shop rotations are full")
	check(Eco.shop_daily(1791000000) == Eco.shop_daily(1791000000 + 3600), "daily shop stable within a day")
	check(Eco.week_key(1791000000) == "2026-09-28", "week starts Monday (%s)" % Eco.week_key(1791000000))

	# ---- migration ----
	var legacy := {"gold":500, "tokens":40, "owned":[0, 2, 5], "chests":[{"k":1}, {"k":2}], "level":12, "xp":30, "cap":57}
	var p := fresh("mig", legacy)
	check(p.d.gold == 500 + 2 * 250 + 2 * 150 and p.d.gems == 40 and p.d.level == 12, "legacy migrated: gold %d gems %d level %d" % [p.d.gold, p.d.gems, p.d.level])
	var raw := FileAccess.get_file_as_string(p.legacy_path)
	check(JSON.parse_string(raw).gold == 500, "legacy save left untouched on disk")
	check(not p.import_legacy(legacy).ok, "second legacy import refused")
	var p_none := fresh("none")
	check(p_none.d.gold == 0 and p_none.d.migration.from == "none", "no legacy save -> clean profile")

	# ---- persistence + corrupt profile ----
	var reload := Profile.new(p.path, p.legacy_path)
	reload.now_override = p.now_override
	reload.load_or_create()
	check(reload.d.gold == p.d.gold and reload.d.migration.from == "legacy", "profile round-trips through disk (no re-migration)")
	var cf := FileAccess.open(p.path, FileAccess.WRITE); cf.store_string("{not json"); cf.close()
	var broken := Profile.new(p.path, "user://no-such-legacy.json")
	broken.now_override = p.now_override
	broken.load_or_create()
	check(FileAccess.file_exists(p.path + ".corrupt") and broken.d.gold == 0 and broken.last_error != "", "corrupt profile kept as .corrupt, fresh profile started")

	# ---- match rewards, first win, levels, challenges ----
	var q := fresh("match")
	var me := {"team":0, "cls":"knight", "rescues":2, "kills":12, "gathered":30, "gate_dmg":650.0, "fed":2, "lifts":2}
	var gold0: int = q.d.gold
	var res := q.apply_match(me, true, false, false)
	var rw: Dictionary = res.rewards
	check(res.first_win and q.d.gold >= gold0 + int(rw.gold), "win paid %d gold incl. first win of the day" % int(rw.gold))
	var sum := 0
	for ln in rw.lines: sum += int(ln.gold)
	check(sum == int(rw.gold), "reward lines add up to the total")
	var res2 := q.apply_match(me, true, false, true)
	check(not res2.first_win, "first-win bonus only once per day")
	check(res2.rewards.lines.any(func(l): return str(l.label).begins_with("Online bonus")), "online bonus line present online")
	check(q.d.level >= 2 and not res.levels.is_empty() or not res2.levels.is_empty(), "levels gained (level %d)" % q.d.level)
	check(q.d.stats.matches == 2 and q.d.stats.wins == 2 and q.d.stats.rescues == 4, "lifetime stats updated")
	var progressed := false
	for c in q.d.challenges.daily:
		if int(c.progress) > 0: progressed = true
	check(progressed, "daily challenges progressed from matches")

	# ---- challenges claim ----
	var z := fresh("chal")
	z.d.challenges.daily[0].progress = int(Eco.CHALLENGES[z.d.challenges.daily[0].id].goal)
	var xp0 := int(z.d.pass.xp)
	check(z.claim_challenge("daily", 0).ok and int(z.d.pass.xp) > xp0, "completed challenge claims pass XP")
	check(not z.claim_challenge("daily", 0).ok, "challenge can't be claimed twice")
	var first_id: String = z.d.challenges.daily[1].id
	check(z.reroll_daily(1) and z.d.challenges.daily[1].id != first_id and not z.reroll_daily(2), "one daily reroll per day")

	# ---- pass + premium ----
	var s := fresh("pass")
	s.d.pass.xp = 7 * Eco.TIER_XP + 10
	check(s.pass_tier() == 7, "pass tier from XP")
	check(s.claim_tier(1, false).ok and not s.claim_tier(1, false).ok, "free tier claimed once")
	check(not s.claim_tier(8, false).ok, "locked tier can't be claimed")
	check(not s.claim_tier(1, true).ok, "premium tier needs the premium pass")
	check(not s.buy_premium().ok, "premium needs gems")
	s.d.gems = Eco.PREMIUM_COST + 5
	check(s.buy_premium().ok and s.d.gems == 5 and s.claim_tier(6, true).ok, "premium bought and premium tier 6 claimed")
	check(s.owns(Eco.pass_items(1)[Eco.PASS_FREE_ITEMS + 1]), "premium tier 6 cosmetic owned")
	var s2 := Profile.new(s.path, s.legacy_path)
	s2.now_override = s.now_override
	s2.load_or_create()
	check(not s2.claim_tier(1, false).ok and not s2.claim_tier(6, true).ok and s2.d.pass.premium, "claimed tiers and premium survive a reload (no double claim)")
	var all := s.claim_all()
	check(all.size() == 7 + 7 - 2, "claim all got the remaining %d rewards" % all.size())

	# ---- shop + equip ----
	var b := fresh("shop")
	var daily := Eco.shop_daily(b.now())
	var target: String = daily[0]
	var price := Eco.item_price(target)
	check(not b.buy(target).ok, "can't buy without gold")
	b.d.gold = 99999
	check(b.buy(target).ok and b.owns(target) and not b.buy(target).ok, "bought %s once" % target)
	var not_today := ""
	for id in Eco.CATALOG:
		if Eco.CATALOG[id].source == "shop" and not daily.has(id) and not Eco.shop_featured(b.now()).has(id):
			not_today = id; break
	check(not_today == "" or not b.buy(not_today).ok, "items outside today's rotation can't be bought")
	check(b.equip(target).ok, "equip owned item")
	var it := Eco.item(target)
	var look := b.look_for(str(it.get("class", "knight")))
	check(it.kind == "title" or not look.is_empty(), "equipped look reaches the battle view (%s)" % str(look))
	check(not b.equip("knight_wpn_tower").ok or b.owns("knight_wpn_tower"), "can't equip unowned items")
	b.d.gems = 200
	check(b.exchange("gold_m").ok and b.d.gems == 80, "gems -> gold exchange")

	# ---- rollover ----
	var r := fresh("roll")
	var day0: String = r.d.challenges.day
	r.now_override += 86400
	r.refresh()
	check(r.d.challenges.day != day0, "new day rolls new daily challenges")
	r.d.pass.xp = 5000
	r.now_override = Eco.season_ends(1) + 10
	r.refresh()
	check(int(r.d.pass.season) == 2 and int(r.d.pass.xp) == 0, "new season resets the pass")

	# ---- 0.31.38: the upgraded classes' cosmetics ----
	var up := fresh("upcos")
	up.d.gold = 10000
	check(Eco.cosmetic_class("knight", true) == "crusader" and Eco.cosmetic_class("knight", false) == "knight" and Eco.cosmetic_class("worker", true) == "worker", "an upgraded Knight dresses from the Crusader slot")
	up.d.owned.append("crus_wpn_warhammer")          # (buying depends on the day's rotation; tested above)
	check(bool(up.equip("crus_wpn_warhammer").get("ok", false)), "a Crusader weapon owned and equipped")
	check(str(up.look_for("crusader").get("r", "")) == "bits/hammer_A" and not up.look_for("knight").has("r"), "it arms the Crusader, not the plain Knight")
	var upcount := 0
	for cid in Eco.CATALOG:
		if Eco.UP_CLASSES.has(str(Eco.CATALOG[cid].get("class", ""))):
			upcount += 1
	check(upcount == 18, "18 upgraded-class weapons (3 for each of 6 classes, 0.31.40): %d" % upcount)
	# ---- 0.31.39: weapons only -- no skins; bought skins refunded once ----
	var skins := 0
	for cid in Eco.CATALOG:
		if str(Eco.CATALOG[cid].kind) == "skin":
			skins += 1
	check(skins == 0, "no skins left in the catalog")
	var rf := fresh("refund")
	var rawsave := rf.d.duplicate(true)
	rawsave.owned = ["knight_skin_royal", "knight_skin_gilded", "knight_wpn_greatsword"]
	rawsave.erase("skins_refunded")
	rawsave.gold = 100
	rawsave.gems = 10
	var after := rf._normalized(rawsave)
	check(int(after.gold) == 100 + 1200 and int(after.gems) == 10 + 400 and after.owned == ["knight_wpn_greatsword"], "an old save's bought skins come back as their price (gold %d, gems %d)" % [int(after.gold), int(after.gems)])
	var again := rf._normalized(after)
	check(int(again.gold) == int(after.gold) and int(again.gems) == int(after.gems), "and only once")
	var lk := up.look_for("knight")
	check(not lk.has("tint"), "no tints reach the battle")
	print("META_ECONOMY_PASS" if fails.is_empty() else "META_ECONOMY_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
