extends SceneTree
# 0.31.185 (Kevin: "I want the same IAP system as league of legends"): heroes the way League sells champions.
#  1. Prices: each sold hero 2,000 gold OR 450 gems (gold is earned only -- the gem -> gold packs are gone); a new hero
#     at his launch price (4,000 / 600) for 14 days, then his own; the profile buys with either.
#  2. The free rotation: 2 sold heroes a week (Monday 00:00 UTC), every one of them in turn over three weeks, a launching
#     one left out; a free one plays like your own (can_play_hero), but isn't yours.
#  3. Hero shards: Royal chests always hold one (Gold 30 %, Silver 10 %, Wooden none -- the odds say so), rolled after
#     the rest so an old roll's gold, gems and weapon are as they were; a shard unlocks its hero for 60 % of the gold, or
#     melts for 20 %.
#  4. The pass: free tiers 5, 15, 25 a shard of a hero not owned yet (the claimed tier keeps the hero it gave); premium
#     tier 1 a Hero Token (the first premium weapon on tier 2 now); the token unlocks any locked hero.
#  5. The ops replay to the same profile (the server's copy), and an unknown one ("exchange") is refused.
#   godot --headless --path godot -s res://tests/league_iap_test.gd
const Profile = preload("res://scripts/meta/profile.gd")
const Eco = preload("res://scripts/meta/economy.gd")
var fails: Array = []
const T0 := 1792800000                 # 2026-10-24 00:00 UTC (a Saturday)

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func fresh(tag: String) -> Profile:
	var p := Profile.new("user://league_%s_%d.json" % [tag, Time.get_ticks_usec()], "user://none_%d.json" % Time.get_ticks_usec())
	p.now_override = T0
	p.load_or_create()
	return p

func _init() -> void:
	# ---- 0. 0.31.187 (Kevin: "Make the champions the higher price since they are new"): the six launched together on
	# 2026-10-19 -- their launch price for 14 days; the free rotation goes on with them (too few would be left without)
	var six: Dictionary = Eco.HERO_LAUNCH.duplicate()
	var L := Eco.SIX_LAUNCH
	check(six.size() == 6 and six.keys().all(func(h): return Eco.HERO_PRICES.has(h) and int(six[h]) == L)
		and Eco.hero_price("golem", L + 86400) == {"gold": 4000, "gems": 600} and Eco.hero_price("druid", L + 14 * 86400 - 1).gold == 4000
		and Eco.hero_price("golem", L + 14 * 86400) == {"gold": 2000, "gems": 450}, "the six: 4,000 gold or 600 gems from 2026-10-19 for 14 days, then 2,000 / 450")
	Eco.HERO_LAUNCH.clear()
	var plain: Array = Eco.free_heroes(L + 86400)
	Eco.HERO_LAUNCH.merge(six)
	check(Eco.free_heroes(L + 86400).size() == 2 and Eco.free_heroes(L + 86400) == plain,
		"...the free rotation still has two while they launch -- the same two a server without the launch picks")
	var lp := fresh("launch")
	lp.now_override = L + 86400
	lp.d.gold = 3000
	var locked6 := ""
	for h in ["golem", "dragoon", "duelist", "stormcaller", "musketeer", "druid"]:
		if not Eco.free_heroes(L + 86400).has(h) and locked6 == "":
			locked6 = h
	check(not bool(lp.buy_hero(locked6).ok) and lp.hero_price(locked6).gold == 4000, "3,000 gold isn't enough for a launching hero (%s)" % locked6)
	lp.d.gold = 4000
	check(bool(lp.buy_hero(locked6).ok) and int(lp.d.gold) == 0 and lp.owns_hero(locked6), "...4,000 is")
	Eco.HERO_LAUNCH.clear()                   # (the rest: the prices after the launch)
	# ---- 1. prices
	check(Eco.hero_price("golem", T0) == {"gold": 2000, "gems": 450} and Eco.hero_price("knight", T0).is_empty(),
		"a sold hero: 2,000 gold or 450 gems; the twelve old ones aren't sold")
	Eco.HERO_LAUNCH["druid"] = T0 - 3 * 86400
	check(Eco.hero_price("druid", T0) == {"gold": Eco.LAUNCH_GOLD, "gems": Eco.LAUNCH_GEMS} and Eco.launching("druid", T0)
		and Eco.hero_price("druid", T0 + 12 * 86400) == {"gold": 2000, "gems": 450}, "a new hero: launch price for 14 days, then his own")
	var rot_launch := []
	for w in 6:
		rot_launch.append_array(Eco.free_heroes(T0 + w * 7 * 86400))
	check(not Eco.free_heroes(T0).has("druid"), "...and not in the free rotation while launching")
	Eco.HERO_LAUNCH.erase("druid")
	var p := fresh("buy")
	p.d.gold = 1000
	p.d.gems = 1000
	var locked := ""
	for h in ["golem", "dragoon", "duelist", "stormcaller", "musketeer", "druid"]:
		if not Eco.free_heroes(T0).has(h) and locked == "":
			locked = h
	check(not bool(p.buy_hero(locked).ok) and bool(p.buy_hero_gems(locked).ok) and p.owns_hero(locked) and int(p.d.gems) == 550
		and int(p.d.gold) == 1000, "not enough gold -- 450 gems instead: %s is yours" % locked)
	check(not bool(p.buy_hero_gems(locked).ok), "...once")
	# ---- 2. the free rotation
	var seen := {}
	var weeks_ok := true
	for w in 3:
		var f: Array = Eco.free_heroes(T0 + w * 7 * 86400)
		weeks_ok = weeks_ok and f.size() == 2 and f[0] != f[1]
		for h in f:
			seen[h] = true
	check(weeks_ok and seen.size() == 6, "two free a week, all six in turn over three weeks (%s)" % str(seen.keys()))
	var day0 := int(floor(T0 / 86400.0))
	var mon0 := (day0 - ((day0 + 3) % 7) + 7) * 86400          # the next Monday 00:00 UTC (1970-01-01 was a Thursday)
	check(Eco.free_heroes(mon0 - 1) == Eco.free_heroes(T0) and Eco.free_heroes(mon0) != Eco.free_heroes(T0),
		"the rotation turns at Monday 00:00 UTC")
	var q := fresh("free")
	var fr: String = Eco.free_heroes(T0)[0]
	check(q.can_play_hero(fr) and not q.owns_hero(fr) and q.can_play_hero("knight"), "a free one plays (%s), but isn't owned" % fr)
	q.now_override = T0 + 21 * 86400
	var gone := Eco.free_heroes(q.now()).has(fr) == false
	check(gone == not q.can_play_hero(fr), "...the week after, only if he's free again")
	# ---- 3. hero shards
	var all_owned: Array = Eco.chest_pool("epic") + Eco.chest_pool("legendary") + Eco.chest_pool("rare") + Eco.chest_pool("common")
	var royal_shards := 0
	var gold_shards := 0
	var wooden_shards := 0
	for i in 300:
		if str(Eco.roll_chest("royal", 1000 + i, all_owned, 0).shard) != "":
			royal_shards += 1
		if str(Eco.roll_chest("gold", 2000 + i, all_owned, 0).shard) != "":
			gold_shards += 1
		if str(Eco.roll_chest("wooden", 3000 + i, all_owned, 0).shard) != "":
			wooden_shards += 1
	check(royal_shards == 300 and gold_shards > 60 and gold_shards < 120 and wooden_shards == 0,
		"shards: every Royal chest, ~30 %% of Gold (%d/300), no Wooden" % gold_shards)
	check(Eco.chest_odds("royal").contains("a hero shard") and Eco.chest_odds("gold").contains("30% chance of a hero shard")
		and not Eco.chest_odds("wooden").contains("shard"), "the odds say so")
	var r1 := Eco.roll_chest("gold", 777, [], 3)
	var keys_same := r1.has("gold") and r1.has("gems") and r1.has("item") and r1.has("pity")
	check(keys_same, "a roll still has its gold, gems, weapon and pity")
	var s := fresh("shard")
	s.d.gold = 5000
	s.d.shards = [locked, locked]
	check(s.shards_of(locked) == 2 and bool(s.use_shard(locked).ok) and s.owns_hero(locked) and int(s.d.gold) == 5000 - 1200
		and s.shards_of(locked) == 1, "a shard: %s for 1,200 gold (60 %%)" % locked)
	check(not bool(s.use_shard(locked).ok) and bool(s.melt_shard(locked).ok) and int(s.d.gold) == 3800 + 400 and s.shards_of(locked) == 0,
		"a shard of a hero you own melts for 400 gold (20 %)")
	# ---- 4. the pass
	check(Eco.pass_reward(1, 5, false) == {"shard": ""} and Eco.pass_reward(1, 15, false) == {"shard": ""} and Eco.pass_reward(1, 25, false) == {"shard": ""},
		"free tiers 5, 15, 25: a hero shard")
	check(Eco.pass_reward(1, 1, true) == {"token": 1} and Eco.premium_item_tiers(1)[0] == 2 and Eco.pass_reward(1, 2, true).has("item"),
		"premium tier 1: a Hero Token; the first premium weapon on tier 2")
	var t := fresh("pass")
	t.d.heroes = ["golem", "dragoon", "duelist", "stormcaller", "musketeer"]
	var want: Dictionary = t.pass_reward_for(5, false)
	check(want == {"shard": "druid"}, "the pass shard: the one hero not owned yet (%s)" % str(want))
	t.d.pass.xp = Eco.PASS_TIERS * Eco.TIER_XP
	t.d.pass.premium = true
	var c1: Dictionary = t.claim_tier(5, false)
	check(bool(c1.ok) and c1.reward == {"shard": "druid"} and t.shards_of("druid") == 1, "claimed: a Druid shard")
	t.d.heroes.append("druid")
	check(t.pass_reward_for(5, false) == {"shard": "druid"}, "...and the claimed tier keeps showing the Druid")
	t.d.heroes.erase("druid")
	var c2: Dictionary = t.claim_tier(1, true)
	check(bool(c2.ok) and int(t.d.tokens) == 1, "premium tier 1 claimed: a Hero Token")
	check(bool(t.use_token("druid").ok) and t.owns_hero("druid") and int(t.d.tokens) == 0 and not bool(t.use_token("golem").ok),
		"the token unlocks the Druid; no token left")
	# ---- 5. ops replay to the same profile; the gold packs are gone
	var a := fresh("opa")
	var b := fresh("opb")
	a.d.gold = 9000
	a.d.gems = 2000
	a.d.shards = ["golem", "druid"]
	a.d.tokens = 1
	b.d = b._normalized(a.d.duplicate(true))
	var log: Array = []
	a.on_op = func(op, args): log.append([op, args.duplicate(true)])
	a.buy_hero_gems("dragoon")
	a.use_shard("golem")
	a.melt_shard("druid")
	a.use_token("duelist")
	a.buy_hero("musketeer")
	for e in log:
		b.apply_op(str(e[0]), JSON.parse_string(JSON.stringify(e[1])))
	check(log.size() == 5 and JSON.stringify(a.d.heroes) == JSON.stringify(b.d.heroes) and int(a.d.gold) == int(b.d.gold)
		and int(a.d.gems) == int(b.d.gems) and JSON.stringify(a.d.shards) == JSON.stringify(b.d.shards) and int(a.d.tokens) == int(b.d.tokens),
		"5 ops replayed give the same heroes, gold, gems, shards and tokens (%s)" % str(a.d.heroes))
	check(not bool(b.apply_op("exchange", ["gold_xxl"]).get("ok", true)) and not Profile.OPS.has("exchange") and not ("EXCHANGE" in Eco),
		"gems no longer buy gold: no exchange op, no gold packs")
	var bad := fresh("bad")
	bad.d.shards = ["golem", "knight", 5, "druid"]
	bad.d.tokens = -3
	var n: Dictionary = bad._normalized(bad.d)
	check(n.shards == ["golem", "druid"] and int(n.tokens) == 0, "a damaged save: only real heroes' shards, no negative tokens")
	Eco.HERO_LAUNCH.merge(six)
	print("LEAGUE_IAP_%s" % ("PASS" if fails.is_empty() else "FAIL %s" % str(fails)))
	quit(0 if fails.is_empty() else 1)
