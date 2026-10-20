extends SceneTree
# Economy + profile: migration, rewards, levels, pass, premium, shop, equip, challenges, rollover,
# persistence, corrupt profile, catalog integrity. (0.31.188: the catalog is titles only -- outfits are the cosmetics;
# outfits_test has them.)
const Eco = preload("res://scripts/meta/economy.gd")
const View = preload("res://scripts/siege/siege_view.gd")
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
	var titles_only := true
	for id in Eco.CATALOG:
		titles_only = titles_only and str(Eco.CATALOG[id].kind) == "title" and str(id).begins_with("title_")
	check(titles_only and Eco.CATALOG.size() > 5, "the catalog is titles only (0.31.188: no weapons, no packs) -- %d" % Eco.CATALOG.size())
	var pass_valid := true
	for tier in range(1, Eco.PASS_TIERS + 1):
		for prem in [false, true]:
			var r := Eco.pass_reward(1, tier, prem)
			if r.is_empty() or r.has("item"): pass_valid = false
			for k in r:
				if not (k in ["gold", "gems", "chest", "shard", "token"]): pass_valid = false
	check(pass_valid, "all 60 pass rewards are valid: gold, gems, chests, shards and the token -- no items")
	check(Eco.pass_reward(1, 30, true) == {"chest": "royal", "gems": 150}, "premium tier 30: a Royal chest and 150 gems")
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
	var ch0: int = s.chests().size() + s.chests_waiting()
	check(s.buy_premium().ok and s.d.gems == 5 and s.claim_tier(3, true).ok, "premium bought and premium tier 3 claimed")
	check(s.chests().size() + s.chests_waiting() == ch0 + 1, "premium tier 3: a Gold chest (0.31.188; it was a weapon)")
	var s2 := Profile.new(s.path, s.legacy_path)
	s2.now_override = s.now_override
	s2.load_or_create()
	check(not s2.claim_tier(1, false).ok and not s2.claim_tier(3, true).ok and s2.d.pass.premium, "claimed tiers and premium survive a reload (no double claim)")
	var all := s.claim_all()
	check(all.size() == 7 + 7 - 2, "claim all got the remaining %d rewards" % all.size())

	# ---- shop + equip (0.31.188: outfits for gems; titles to equip) ----
	var b := fresh("shop")
	check(not b.buy_skin("knight_frost").ok, "can't buy an outfit without gems")
	b.d.gems = 5000
	check(b.buy_skin("knight_frost").ok and b.owns_skin("knight_frost") and not b.buy_skin("knight_frost").ok, "bought the Frostbound Knight once")
	check(b.look_for("knight") == {"skin": "knight_frost"} and b.look_for("mage").is_empty(), "the outfit worn reaches the battle view (%s)" % str(b.look_for("knight")))
	check(not b.has_method("buy") and not b.OPS.has("buy") and not b.OPS.has("buy_pack") and not b.OPS.has("forge"), "no weapons to buy or forge")
	b.d.owned.append("title_squire")
	check(b.equip("title_squire").ok and str(b.d.title) == "title_squire", "an earned title is worn")
	check(not b.equip("title_legend").ok, "can't equip a title not earned")
	check(not b.has_method("exchange") and not b.OPS.has("exchange"), "no gems -> gold exchange (0.31.185, League's way)")

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

	# ---- 0.31.38: the upgraded classes dress from their own slot ----
	check(Eco.cosmetic_class("knight", true) == "crusader" and Eco.cosmetic_class("knight", false) == "knight" and Eco.cosmetic_class("worker", true) == "worker", "an upgraded Knight dresses from the Crusader slot")
	var rf := fresh("refund")
	var rawsave := rf.d.duplicate(true)
	rawsave.owned = ["knight_skin_royal", "knight_skin_gilded", "knight_wpn_greatsword", "title_squire"]
	rawsave.erase("skins_refunded")
	rawsave.gold = 100
	rawsave.gems = 10
	var after := rf._normalized(rawsave)
	check(int(after.gold) == 100 + 1200 and int(after.gems) == 10 + 400 and after.owned == ["title_squire"], "an old save's bought skins come back as their price (gold %d, gems %d); 0.31.188: its weapons go, no refund" % [int(after.gold), int(after.gems)])
	var again := rf._normalized(after)
	check(int(again.gold) == int(after.gold) and int(again.gems) == int(after.gems), "and only once")
	print("META_ECONOMY_PASS" if fails.is_empty() else "META_ECONOMY_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
