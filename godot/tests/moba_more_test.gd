extends SceneTree
# 0.31.157 5V5 (scripts/siege/moba.gd), Kevin: "Build the other 3 mechanics now" -- the ultimates, the jungle, gold and
# the shop, on the sim:
#  1. ULTIMATES: none before level 6; at 6 each of the 12 heroes' own works (BULWARK halves damage near him, WAR CRY
#     quickens and hardens, EXECUTE blinks behind the weakest hero near and strikes hard, ARROW RAIN pours on a circle,
#     INFERNO burns and stuns round you, GRACE heals your side anywhere, JUDGMENT stuns enemies and heals allies near,
#     UNDYING keeps you at 1 health, FLURRY strikes enemy after enemy, DEADEYE flies the field and stuns, METEORS rains
#     six, LEGION raises four skeletons who crumble after 20 s); then it recharges; from level 9 it's stronger and back
#     sooner;
#  2. GOLD: 500 to start, a trickle every second from the first wave, the last hit on a minion, a knockout (and the
#     helpers' share), a tower (0.31.158, League's: the side's heroes near share the local gold -- more for the match's
#     first tower -- and everyone on the side gets the global);
#  3. THE SHOP: anywhere (0.31.217; only in your castle or while down until then) and its quick-buy; an item's stats count at once; a big item is built from the small
#     ones you own (they come off its price and leave your slots); one pair of boots; six slots; selling gives 70 % back;
#  4. THE JUNGLE: the camps come at 0:30 (the Bone Lord at 5:00), monsters of team 2 that stand still until hit; towers
#     and lane minions leave them alone; hit, the camp fights back -- while its target stays inside the leash -- and
#     walks home and heals when he's gone; a camp cleared: gold and XP, back after its time; the buff camps' big one
#     gives its buff (ARCANE: quicker recharges; EMBER: harder hits), which goes to whoever knocks its holder out; the
#     Bone Lord gives his killers' whole side gold and his blessing (their minions come out stronger) -- and (0.31.158)
#     marches for them down the middle lane; an enemy lane's high ground tower down: that lane's waves bring a super minion
#     (League's inhibitor);
#  5. whole matches, bots on both sides: they buy, use their ultimates, clear camps.
#   godot --headless --path godot -s res://tests/moba_more_test.gd
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Moba = preload("res://scripts/siege/moba.gd")

const P0 := Vector2(-30.0, 36.0)            # open ground on blue's side, away from the lanes

var fails: Array = []

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _new(hero: String, seed_value: int) -> Object:
	var s = Sim.new()
	s.setup(5, seed_value)
	s.setup_moba(hero, seed_value)
	return s

func _run(s, secs: float) -> Array:
	var evs := []
	for i in int(secs / Sim.TICK):
		s.step()
		evs.append_array(s.drain_events())
	return evs

func _quiet(s) -> void:
	# a scene to set up: no waves, no camps, no towers shooting, every hero home and still
	s.moba.wave_at = INF
	for c in s.moba.camps:
		c.next = INF
	for tw in s.moba.towers:
		tw.dead = true
	for u in s.units.duplicate():
		if bool(u.get("minion", false)) or u.has("mon"):
			s.units.erase(u)
			s.by_id.erase(u.id)
	for u in s.units:
		if bool(u.get("hero", false)):
			u.bot = false
			u.pos = Sim.spawn(int(u.team))
			u.move = Vector2.ZERO

func _to_level(s, u: Dictionary, lv: int) -> void:
	while int(u.level) < lv:
		s.moba.add_xp(u, s.moba.need(int(u.level)))
	u.picks = []
	s.moba._bot_learn(u)                        # (0.31.217: the skill points spent as a bot spends them -- R first)

func _tough(u: Dictionary) -> void:
	u.max_hp = 100000.0
	u.hp = 100000.0

func _init() -> void:
	_ultimates()
	_gold()
	_shop()
	_jungle()
	_wyrm()
	_matches()
	print("MOBA_MORE_PASS" if fails.is_empty() else "MOBA_MORE_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)

# ---------------------------------------------------------------- 1. ultimates
func _ult_scene(hero: String) -> Array:
	var s = _new(hero, 41)
	_quiet(s)
	var me: Dictionary = s.by_id["you"]
	_to_level(s, me, 6)
	me.pos = P0
	me.face = s.angle_of(Vector2(0, -1))
	return [s, me]

func _ultimates() -> void:
	# none before ULT_LEVEL; learnt with a skill point from then (0.31.217, Honor of Kings: level 4; 6 on its own until then)
	var s0 = _new("knight", 3)
	_quiet(s0)
	var y0: Dictionary = s0.by_id["you"]
	var evs := []
	while int(y0.level) < Moba.ULT_LEVEL - 1:
		s0.moba.add_xp(y0, s0.moba.need(int(y0.level)))
	check(not s0.act("you", "learn", "r") and not s0.act("you", "ult") and s0.moba.ult_rank(y0) == 0, "no ultimate before level %d" % Moba.ULT_LEVEL)
	s0.moba.add_xp(y0, s0.moba.need(int(y0.level)))
	s0.drain_events()
	check(s0.act("you", "learn", "r"), "level %d: a point on the ultimate" % Moba.ULT_LEVEL)
	evs.append_array(s0.drain_events())
	check(evs.any(func(e): return e.k == "ult_ready" and str(e.id) == "you") and s0.moba.ult_rank(y0) == 1, "...it's ready")
	# BULWARK
	var r: Array = _ult_scene("knight")
	var s = r[0]
	var me: Dictionary = r[1]
	var ally: Dictionary = s.by_id["b1"]
	var foe: Dictionary = s.by_id["r1"]
	ally.pos = P0 + Vector2(3, 0)
	foe.pos = P0 + Vector2(0, -3)
	_tough(ally)
	check(s.act("you", "ult") and float(me.ult_cd) > 0.0, "BULWARK cast; it recharges (%.0f s)" % float(me.ult_cd))
	var h := float(ally.hp)
	s._damage(foe, ally, 100.0)
	check(is_equal_approx(h - float(ally.hp), 100.0 * (1.0 - Moba.BULWARK_DR)), "BULWARK: an ally near takes half (%.0f of 100)" % (h - float(ally.hp)))
	check(not s.act("you", "ult"), "...and not again until it's back")
	# WAR CRY
	r = _ult_scene("barbarian")
	s = r[0]
	me = r[1]
	var w0 := float(s.stat(me, "windup"))
	var d0 := float(s.moba.mod_damage(me, s.by_id["r1"], 100.0))
	s.act("you", "ult")
	check(float(s.stat(me, "windup")) < w0 * 0.8 and float(s.moba.mod_damage(me, s.by_id["r1"], 100.0)) > d0 * 1.2, "WAR CRY: quicker swings, harder hits")
	# EXECUTE
	r = _ult_scene("rogue")
	s = r[0]
	me = r[1]
	var weak: Dictionary = s.by_id["r2"]
	var strong: Dictionary = s.by_id["r3"]
	weak.pos = P0 + Vector2(6, 2)                               # (0.31.158: out of the brush patch at (-22, 33.5))
	strong.pos = P0 + Vector2(-3, -1)
	weak.hp = float(weak.max_hp) * 0.6
	var wh := float(weak.hp)
	var exp_dmg := float(s.stat(me, "dmg")) * Moba.EXECUTE_DMG + Moba.EXECUTE_MISSING * (float(weak.max_hp) - wh)
	s.moba.vision._update()                                    # (0.31.158: the fog -- what blue sees, with them moved)
	s.act("you", "ult")
	check((me.pos as Vector2).distance_to(weak.pos) < 2.0 and (not s.alive(weak) or wh - float(weak.hp) >= exp_dmg * 0.95),
		"EXECUTE: behind the weakest hero near (not the nearest), a heavy strike (%.0f)" % minf(wh, wh - float(weak.hp)))
	# ARROW RAIN
	r = _ult_scene("ranger")
	s = r[0]
	me = r[1]
	foe = s.by_id["r1"]
	foe.pos = P0 + Vector2(0, -9)
	_tough(foe)
	s.act("you", "ult")
	var fh := float(foe.hp)
	_run(s, 2.8)
	check(s.moba.rains.is_empty() and fh - float(foe.hp) >= float(s.stat(me, "dmg")) * Moba.RAIN_DMG * float(Moba.RAIN_TICKS) * 0.9,
		"ARROW RAIN on the hero in reach: %d volleys (%.0f)" % [Moba.RAIN_TICKS, fh - float(foe.hp)])
	# INFERNO
	r = _ult_scene("mage")
	s = r[0]
	me = r[1]
	var near: Dictionary = s.by_id["r1"]
	var far: Dictionary = s.by_id["r2"]
	near.pos = P0 + Vector2(5, 0)
	far.pos = P0 + Vector2(12, 0)
	_tough(near)
	_tough(far)
	s.act("you", "ult")
	check(float(near.hp) < 100000.0 and float(near.stun) > 0.5 and float(far.hp) == 100000.0, "INFERNO: inside its ring hurt and stunned, outside not")
	# GRACE
	r = _ult_scene("priest")
	s = r[0]
	me = r[1]
	var hurt: Dictionary = s.by_id["b2"]
	hurt.pos = Vector2(20, -30)                                 # far away
	hurt.hp = float(hurt.max_hp) * 0.2
	s.act("you", "ult")
	check(absf(float(hurt.hp) - float(hurt.max_hp) * (0.2 + Moba.GRACE_HEAL)) < 1.0, "GRACE: an ally across the field healed by a third")
	# JUDGMENT
	r = _ult_scene("crusader")
	s = r[0]
	me = r[1]
	foe = s.by_id["r1"]
	ally = s.by_id["b1"]
	foe.pos = P0 + Vector2(3, 0)
	ally.pos = P0 + Vector2(-3, 0)
	_tough(foe)
	ally.hp = float(ally.max_hp) * 0.5
	s.act("you", "ult")
	check(float(foe.stun) > 1.0 and float(foe.hp) < 100000.0 and float(ally.hp) > float(ally.max_hp) * 0.6, "JUDGMENT: the enemy near stunned and hurt, the ally near healed")
	# UNDYING
	r = _ult_scene("berserker")
	s = r[0]
	me = r[1]
	s.act("you", "ult")
	s._damage(s.by_id["r1"], me, 1.0e6)
	check(s.alive(me) and float(me.hp) >= 1.0, "UNDYING: a killing blow leaves him at 1")
	_run(s, Moba.UNDYING_TIME + 0.5)
	s._damage(s.by_id["r1"], me, 1.0e6)
	check(not s.alive(me), "...not after it's over")
	# FLURRY
	r = _ult_scene("assassin")
	s = r[0]
	me = r[1]
	var tg := []
	for i in 3:
		var o: Dictionary = s.by_id["r%d" % (i + 1)]
		o.pos = P0 + Vector2(-6.0 + 6.0 * i, -4.0)
		_tough(o)
		tg.append(o)
	s.act("you", "ult")
	_run(s, 1.2)
	check(tg.all(func(o): return float(o.hp) < 100000.0) and not me.has("dance"), "FLURRY: three enemies near struck in turn")
	# DEADEYE
	r = _ult_scene("sniper")
	s = r[0]
	me = r[1]
	foe = s.by_id["r1"]
	foe.pos = Vector2(-20.0, 15.0)                             # (0.31.158: in your sight -- the fog; 0.31.165: open
	me.pos = Vector2(-20.0, 28.0)                              # ground on the Rift)
	me.face = 0.0                                              # facing away: it turns to the hero
	_tough(foe)
	s.moba.vision._update()
	s.act("you", "ult")
	var pj: Array = s.projectiles.filter(func(p): return str(p.owner) == "you" and bool(p.get("big", false)))
	var reach := float(pj[0].life) * Moba.DEADEYE_SPEED if not pj.is_empty() else 0.0
	var stunned := false
	for i in int(1.0 / Sim.TICK):
		s.step()
		stunned = stunned or float(foe.stun) > 0.0
	check(reach >= 70.0 and float(foe.hp) < 100000.0 and stunned,
		"DEADEYE: across the field to the hero you see 13 m off, stunning him")
	# METEORS
	r = _ult_scene("archmage")
	s = r[0]
	me = r[1]
	foe = s.by_id["r1"]
	foe.pos = P0 + Vector2(0, -8)
	_tough(foe)
	s.act("you", "ult")
	check(s.meteors.size() == Moba.STORM_N, "METEORS: %d called down" % s.meteors.size())
	_run(s, 3.0)
	check(float(foe.hp) < 100000.0 - float(s.stat(me, "dmg")) * Moba.STORM_DMG, "...on the hero in reach (%.0f)" % (100000.0 - float(foe.hp)))
	# LEGION
	r = _ult_scene("necromancer")
	s = r[0]
	me = r[1]
	foe = s.by_id["r1"]
	foe.pos = P0 + Vector2(0, -5)
	_tough(foe)
	s.act("you", "ult")
	var zs: Array = s.units.filter(func(u): return bool(u.get("summon", false)))
	check(zs.size() == Moba.LEGION_N and zs.all(func(u): return int(u.team) == 0 and str(u.look) == "skel_minion"), "LEGION: four skeletons rise on his side")
	_run(s, 4.0)
	check(float(foe.hp) < 100000.0, "...and fight the enemy near")
	var gold_r := float(foe.gold)
	_run(s, Moba.LEGION_TIME)
	check(s.units.filter(func(u): return bool(u.get("summon", false)) and s.alive(u)).is_empty() and float(foe.gold) - gold_r < 50.0,
		"...crumbling after 20 s (no gold for their fall)")
	# rank 2
	r = _ult_scene("mage")
	s = r[0]
	me = r[1]
	_to_level(s, me, Moba.ULT_RANK2)
	s.act("you", "ult")
	check(s.moba.ult_rank(me) == 2 and is_equal_approx(float(me.ult_cd), float(Moba.ULTS.mage.cd) * Moba.RANK2_CD), "level %d: rank II, back sooner (%.0f s)" % [Moba.ULT_RANK2, float(me.ult_cd)])

# ---------------------------------------------------------------- 2. gold
func _gold() -> void:
	var s = _new("knight", 5)
	var me: Dictionary = s.by_id["you"]
	check(int(me.gold) == Moba.GOLD_START, "%d gold to start" % Moba.GOLD_START)
	_quiet(s)
	s.moba.wave_at = INF
	_run(s, Moba.WAVE_FIRST + 10.0)
	check(absf(float(me.gold) - Moba.GOLD_START - 10.0 * Moba.GOLD_PASSIVE) < 1.0, "a trickle from the first wave on (+%.0f in 10 s)" % (float(me.gold) - Moba.GOLD_START))
	# a last hit
	var m: Dictionary = _add_minion(s, 1, "knight", me.pos + Vector2(2, 0))
	var g0 := float(me.gold)
	s._damage(me, m, 1.0e6)
	check(is_equal_approx(float(me.gold) - g0, float(Moba.GOLD_MINION.melee)), "the last hit on a melee minion: +%d" % int(Moba.GOLD_MINION.melee))
	var m2: Dictionary = _add_minion(s, 1, "ranger", me.pos + Vector2(2, 0))
	g0 = float(me.gold)
	s._damage(s.by_id["b1"], m2, 10.0)
	s._kill({"team":0, "id":"tower3", "pos":Vector2.ZERO}, m2)
	check(float(me.gold) == g0, "a minion a tower finished: nothing for the hero who only watched")
	# a knockout and the helpers
	var foe: Dictionary = s.by_id["r1"]
	var helper: Dictionary = s.by_id["b1"]
	foe.pos = P0
	me.pos = P0 + Vector2(1, 0)
	helper.pos = Vector2(-30, 10)                               # far, but he hit him a moment ago
	s._damage(helper, foe, 5.0)
	var gm := float(me.gold)
	var gh := float(helper.gold)
	s._damage(me, foe, 1.0e6)
	check(is_equal_approx(float(me.gold) - gm, float(Moba.GOLD_HERO)) and is_equal_approx(float(helper.gold) - gh, float(Moba.GOLD_ASSIST)),
		"a knockout: +%d for him, +%d for the one who helped" % [Moba.GOLD_HERO, Moba.GOLD_ASSIST])
	# a tower
	var tw: Dictionary = s.moba.towers.filter(func(t): return int(t.team) == 1 and int(t.tier) == 1)[0]
	for t2 in s.moba.towers:
		t2.dead = false                                         # (_quiet felled them: this is the match's first)
	for hid in s.moba.heroes[0]:
		s.by_id[hid].pos = P0                                   # (all of blue far from the tower)
	var b3: Dictionary = s.by_id["b3"]
	b3.pos = (tw.p as Vector2) + Vector2(0, 4)                # ...but one standing by it
	var g1 := float(me.gold)
	var g2 := float(s.by_id["b2"].gold)
	var g3 := float(b3.gold)
	s.moba.hit_tower(me, int(tw.id), 1.0e6)
	var glob := float(Moba.GOLD_TOWER_GLOBAL[1])
	var loc := float(Moba.GOLD_TOWER_LOCAL + Moba.GOLD_FIRST_TOWER) / 2.0
	check(bool(tw.dead) and is_equal_approx(float(me.gold) - g1, glob + loc) and is_equal_approx(float(b3.gold) - g3, glob + loc)
		and is_equal_approx(float(s.by_id["b2"].gold) - g2, glob),
		"the first tower: +%d for everyone, +%d more each for the blow and the one near (local, shared)" % [int(glob), int(loc)])

# ---------------------------------------------------------------- 3. the shop
func _shop() -> void:
	var s = _new("knight", 6)
	_quiet(s)
	var me: Dictionary = s.by_id["you"]
	me.gold = 5000.0
	me.pos = P0
	# 0.31.217 (Honor of Kings): anywhere -- out in the lane too (only in your castle or while down until then)
	var dmg0 := float(s.stat(me, "dmg"))
	check(s.moba.can_shop(me) and s.moba.next_buys(me, 2) == ["boots", "ruby"], "the quick-buy: the Knight's list's first two (%s)" % str(s.moba.next_buys(me, 2)))
	check(s.act("you", "shop_buy", "sword") and int(me.gold) == 5000 - 350 and is_equal_approx(float(s.stat(me, "dmg")), dmg0 * 1.12),
		"out in the lane: a Long Sword (-350 gold, +12 % damage)")
	check(s.moba.price(me, "bloodthirster") == 1900 - 350, "the Bloodthirster costs %d with the sword you own" % s.moba.price(me, "bloodthirster"))
	s.act("you", "shop_buy", "bloodthirster")
	check(me.items == ["bloodthirster"] and int(me.gold) == 5000 - 1900, "...bought: the sword went into it")
	check(s.act("you", "shop_buy", "boots") and not s.act("you", "shop_buy", "boots") and s.moba.buy_why(me, "boots") == "boots", "one pair of boots")
	check(s.act("you", "shop_buy", "greaves") and me.items.count("boots") == 0 and me.items.has("greaves"), "...the Greaves are built from them")
	var hp0 := float(me.max_hp)
	s.act("you", "shop_buy", "cloth")
	var h := float(me.hp)
	s._damage(s.by_id["r1"], me, 100.0)
	check(is_equal_approx(h - float(me.hp), 100.0 * (1.0 - 0.10)), "Cloth Armor: 10 % less damage taken")
	me.gold = 10000.0
	for id in ["ruby", "dagger", "tome"]:
		s.act("you", "shop_buy", id)
	check(me.items.size() == Moba.ITEM_SLOTS and float(me.max_hp) > hp0 and s.moba.buy_why(me, "fang") == "full", "six slots, then no room")
	var g := float(me.gold)
	check(s.act("you", "shop_sell", 0) and is_equal_approx(float(me.gold) - g, float(int(1900.0 * Moba.SELL_BACK))) and not me.items.has("bloodthirster"),
		"selling the Bloodthirster: %d back" % int(1900.0 * Moba.SELL_BACK))
	me.pos = P0
	s._kill({}, me)
	check(s.act("you", "shop_buy", "fang"), "down, anywhere: you can shop")
	# bots buy on their own when home
	var b: Dictionary = s.by_id["b1"]
	b.bot = true
	b.pos = Sim.spawn(0)
	b.gold = 1000.0
	_run(s, 1.2)
	check(not (b.items as Array).is_empty(), "a bot at home buys (%s)" % str(b.items))

# ---------------------------------------------------------------- 4. the jungle
func _jungle() -> void:
	var s = _new("knight", 8)
	check(s.moba.camps.size() == 14 and s.moba.camps.filter(func(c): return str(c.kind) == "lord").size() == 1
		and s.moba.camps.filter(func(c): return str(c.kind) == "wyrm").size() == 1,
		"fourteen camps: six a side, the Bone Lord and the Grave Wyrm (0.31.166; 0.31.165's Rift thirteen, nine until then)")
	var mirrored := true
	for c in s.moba.camps:
		if int(c.side) == 0:
			mirrored = mirrored and s.moba.camps.any(func(o): return int(o.side) == 1 and str(o.kind) == str(c.kind) and (o.p as Vector2).is_equal_approx(-(c.p as Vector2)))
	check(mirrored, "red's camps are blue's, mirrored")
	_run(s, Moba.CAMP_FIRST - 0.5)
	check(s.units.filter(func(u): return u.has("mon")).is_empty(), "no camps before 0:30")
	_run(s, 1.0)
	var mons: Array = s.units.filter(func(u): return u.has("mon"))
	check(mons.size() == 36 and mons.all(func(u): return int(u.team) == 2) and not s.moba.camps.filter(func(c): return str(c.kind) == "lord")[0].alive,
		"at 0:30 the twelve camps (36 skeletons, team 2); the Lord and the Wyrm not yet")
	# a scene: no waves, heroes home
	var j = _new("knight", 9)
	j.moba.wave_at = INF
	for u in j.units:
		if bool(u.get("hero", false)):
			u.bot = false
			u.pos = Sim.spawn(int(u.team))
	for c in j.moba.camps:
		c.next = INF
	var camp: Dictionary = j.moba.camps.filter(func(c): return str(c.kind) == "pack" and int(c.side) == 0)[0]
	j.moba._spawn_camp(camp)
	var mobs: Array = j.moba.camp_live(camp)
	var at0: Array = mobs.map(func(m): return m.pos)
	_run(j, 4.0)
	check(mobs.all(func(m): return (m.pos as Vector2).distance_to(at0[mobs.find(m)]) < 0.3), "left alone, they stand still")
	# lane minions and towers leave them alone
	var lm: Dictionary = _add_minion(j, 1, "knight", (camp.p as Vector2) + Vector2(1.5, 0))
	lm.bot = true
	var mh := float(mobs[0].hp)
	_run(j, 2.0)
	check(float(mobs[0].hp) == mh and str(camp.target) == "", "an enemy minion beside them: no fight")
	j.units.erase(lm)
	j.by_id.erase(lm.id)
	# hit, they fight back; leashed, they go home and heal
	var me: Dictionary = j.by_id["you"]
	me.pos = (camp.p as Vector2) + Vector2(0, 2.5)
	me.max_hp = 5000.0
	me.hp = 5000.0
	j._damage(me, mobs[0], 30.0)
	check(str(camp.target) == "you", "hit: the camp turns on you")
	_run(j, 3.0)
	check(float(me.hp) < 5000.0, "...and hits back (%.0f)" % (5000.0 - float(me.hp)))
	me.pos = (camp.p as Vector2) + Vector2(0, Moba.LEASH + 6.0)
	_run(j, 10.0)
	check(str(camp.target) == "" and mobs.all(func(m): return (m.pos as Vector2).distance_to(m.home) < 1.0 and float(m.hp) >= float(m.max_hp) - 0.5),
		"you leave the leash: their patience runs out, they walk home and heal")
	# cleared: gold, XP, back after its time
	me.pos = (camp.p as Vector2) + Vector2(0, 2.5)
	var g0 := float(me.gold)
	var x0 := float(me.xp) + 1000.0 * float(int(me.level))
	var evs := []
	for m in mobs:
		j._damage(me, m, 1.0e6)
		evs.append_array(j.drain_events())
	var want := 0.0
	for m in mobs:
		want += float(Moba.MONSTERS[str(m.mkind)].gold)
	check(not bool(camp.alive) and evs.any(func(e): return e.k == "camp_clear") and is_equal_approx(float(me.gold) - g0, want)
		and float(me.xp) + 1000.0 * float(int(me.level)) > x0, "the camp cleared: +%d gold, XP" % int(want))
	_run(j, float(Moba.CAMP_KINDS.pack.respawn) + 0.5)
	check(bool(camp.alive) and j.moba.camp_live(camp).size() == 3, "back %d s later" % int(Moba.CAMP_KINDS.pack.respawn))
	# the buff camps
	var arc: Dictionary = j.moba.camps.filter(func(c): return str(c.kind) == "arcane" and int(c.side) == 0)[0]
	j.moba._spawn_camp(arc)
	me.pos = (arc.p as Vector2) + Vector2(0, 2.5)
	var big: Dictionary = j.moba.camp_live(arc)[0]
	j._damage(me, big, 1.0e6)
	check(j.moba.has_buff(me, "arcane"), "the Arcane Wraith down: ARCANE on you")
	_to_level(j, me, 6)
	me.ult_cd = 30.0
	me.cd_ability = 6.0
	_run(j, 1.0)
	check(float(me.ult_cd) < 30.0 - 1.2 and float(me.cd_ability) < 6.0 - 1.2, "...the ultimate and the ability recharge faster")
	var foe: Dictionary = j.by_id["r1"]
	foe.pos = me.pos
	j._damage(foe, me, 1.0e6)
	check(j.moba.has_buff(foe, "arcane") and not j.moba.has_buff(me, "arcane"), "knocked out: whoever did it takes it")
	var emb: Dictionary = j.moba.camps.filter(func(c): return str(c.kind) == "ember" and int(c.side) == 1)[0]
	j.moba._spawn_camp(emb)
	foe.pos = (emb.p as Vector2) + Vector2(0, -2.5)
	var d0 := float(j.moba.mod_damage(foe, me, 100.0))
	j._damage(foe, j.moba.camp_live(emb)[0], 1.0e6)
	check(j.moba.has_buff(foe, "ember") and float(j.moba.mod_damage(foe, me, 100.0)) > d0 * 1.15, "the Ember Brute down: EMBER, harder hits")
	# the Bone Lord
	var lc: Dictionary = j.moba.camps.filter(func(c): return str(c.kind) == "lord")[0]
	check(float(Moba.LORD_FIRST) == 300.0, "the Bone Lord rises at 5:00")
	j.moba._spawn_camp(lc)
	var lord: Dictionary = j.moba.camp_live(lc)[0]
	check((lord.pos as Vector2).is_equal_approx(Moba.BOSS_P) and float(lord.max_hp) > 2500.0, "...on the island (%d health)" % int(lord.max_hp))
	me = j.by_id["you"]
	j._respawn(me)
	me.pos = Moba.BOSS_P + Vector2(0, 3)
	me.max_hp = 1.0e5
	me.hp = 1.0e5
	var slam := false
	j._damage(me, lord, 10.0)
	for e in _run(j, Moba.LORD_SLAM_EVERY + 1.0):
		slam = slam or e.k == "lord_slam"
	check(slam and float(me.hp) < 1.0e5, "he fights back, slamming round him")
	var golds := []
	for hid in j.moba.heroes[0]:
		golds.append(float(j.by_id[hid].gold))
	j._damage(me, lord, 1.0e7)
	var all_paid := true
	for i in j.moba.heroes[0].size():
		all_paid = all_paid and is_equal_approx(float(j.by_id[j.moba.heroes[0][i]].gold) - golds[i], float(Moba.MONSTERS.lord.gold))
	check(all_paid and j.moba.has_buff(me, "lord"), "the Bone Lord down: +%d gold for every hero of the side, his blessing" % int(Moba.MONSTERS.lord.gold))
	j.moba.wave_at = j.time
	_run(j, 0.2)
	var newm: Array = j.units.filter(func(u): return bool(u.get("minion", false)) and not bool(u.get("summon", false)) and not bool(u.get("lordling", false)) and int(u.team) == 0 and j.alive(u))
	var up := 1.0 + Moba.MINION_UP * floorf(float(j.time) / Moba.MINION_UP_EVERY)
	check(not newm.is_empty() and newm.all(func(u): return is_equal_approx(float(u.m_hp), float(Moba.MINION_KIND_HP[str(u.mk)]) * up * Moba.LORD_MINION)), "...their minions come out stronger")
	# their high ground tower in a lane down -> that lane's minions come out super (0.31.217, Honor of Kings; League's
	# inhibitor -- the gate at the lane's end -- until then)
	var sp = _new("knight", 12)
	sp.moba.wave_at = INF
	var rg: Dictionary = sp.moba.towers.filter(func(o): return int(o.team) == 1 and int(o.lane) == 0 and int(o.tier) == 3)[0]
	rg.dead = true
	sp.moba.wave_at = sp.time
	_run(sp, 0.2)
	var w0: Array = sp.units.filter(func(u): return bool(u.get("minion", false)) and int(u.team) == 0 and int(u.lane) == 0)
	var w1: Array = sp.units.filter(func(u): return bool(u.get("minion", false)) and int(u.team) == 0 and int(u.lane) == 2)
	var sup0: Array = w0.filter(func(u): return bool(u.get("super", false)))
	check(not rg.is_empty() and sup0.size() == 1 and str(sup0[0].mk) == "super" and str(sup0[0].cls) == "barbarian"
		and is_equal_approx(float(sup0[0].m_hp), float(Moba.MINION_KIND_HP.super)) and w0.size() == 7 and not w0.any(func(u): return str(u.mk) == "siege")
		and w1.all(func(u): return not bool(u.get("super", false))),
		"their west high ground tower down: that lane's waves bring a super minion (in place of the siege one), the east lane's don't")

# ---------------------------------------------------------------- 4b. the Grave Wyrm (0.31.166)
func _hide(h: Dictionary) -> float:
	# a hero's health over what his level alone gives (no upgrades or items in these scenes): his side's Hide
	return float(h.m_hp) / (Moba.HERO_HP * (1.0 + Moba.LEVEL_GROW * float(int(h.level) - 1)))

func _wyrm() -> void:
	var s = _new("knight", 15)
	var wcs: Array = s.moba.camps.filter(func(c): return str(c.kind) == "wyrm")
	var wc: Dictionary = wcs[0]
	check(wcs.size() == 1 and int(wc.side) == -1 and float(Moba.WYRM_FIRST) == 180.0 and float(wc.next) == float(Moba.WYRM_FIRST),
		"one Grave Wyrm, nobody's, first up at 3:00")
	check((Moba.WYRM_P as Vector2).is_equal_approx(-(Moba.BOSS_P as Vector2)) and (wc.p as Vector2).is_equal_approx(Moba.WYRM_P),
		"...in the east pit, the Bone Lord's mirrored")
	_quiet(s)
	s.moba._spawn_camp(wc)
	var wy: Dictionary = s.moba.camp_live(wc)[0]
	check((wy.pos as Vector2).is_equal_approx(Moba.WYRM_P) and str(wy.look) == "wyrm" and int(wy.team) == 2 and float(wy.max_hp) > 1000.0,
		"it rises (%d health)" % int(wy.max_hp))
	# its soul-fire: a cone at whoever it's fighting
	var me: Dictionary = s.by_id["you"]
	me.pos = Moba.WYRM_P + Vector2(0, 3)
	_tough(me)
	var mate: Dictionary = s.by_id["b1"]
	mate.pos = Moba.WYRM_P + Vector2(0.8, 4.5)
	_tough(mate)
	var behind: Dictionary = s.by_id["b2"]
	behind.pos = Moba.WYRM_P + Vector2(0, -5.0)
	_tough(behind)
	s._damage(me, wy, 10.0)
	var breath := {}
	for e in _run(s, Moba.WYRM_BREATH_EVERY + 1.0):
		if e.k == "wyrm_breath":
			breath = e
	check(not breath.is_empty() and int(breath.n) >= 2 and float(me.hp) < float(me.max_hp) and float(mate.hp) < float(mate.max_hp)
		and float(behind.hp) == float(behind.max_hp),
		"every %d s its soul-fire: the cone toward you burns you and the ally beside you (%d), not the one behind it" % [int(Moba.WYRM_BREATH_EVERY), int(breath.get("n", 0))])
	# League's leash: the one it's after walks out of it -- it turns on the other still at it (no reset, no healing)
	s._damage(mate, wy, 10.0)
	s._damage(me, wy, 10.0)
	var hp1 := float(wy.hp)
	me.pos = Moba.WYRM_P + Vector2(0, Moba.WYRM_LEASH + 4.0)
	_run(s, 1.0)
	check(str(wc.target) == "b1" and str(wc.reset) == "" and float(wy.hp) <= hp1, "you walk out of its leash: it turns on your ally still at it, and doesn't heal")
	me.pos = Moba.WYRM_P + Vector2(0, 3)
	# down: the slaying side's heroes, gold, XP, and a stack of WYRM'S HIDE for good
	var g0 := {}
	var e0 := {}
	for t in 2:
		for hid in s.moba.heroes[t]:
			g0[hid] = float(s.by_id[hid].gold)
			e0[hid] = int(s.by_id[hid].get("epics", 0))
	s._damage(me, wy, 1.0e7)
	var evs: Array = s.drain_events()
	var paid := true
	var hide := true
	for t in 2:
		for hid in s.moba.heroes[t]:
			var h: Dictionary = s.by_id[hid]
			if t == 0:
				paid = paid and is_equal_approx(float(h.gold) - g0[hid], float(Moba.MONSTERS.wyrm.gold)) and int(h.epics) == e0[hid] + 1
				hide = hide and is_equal_approx(_hide(h), 1.0 + Moba.WYRM_HIDE)          # (the XP may have levelled him)
			else:
				paid = paid and float(h.gold) == g0[hid]
				hide = hide and is_equal_approx(_hide(h), 1.0)
	check(int(s.moba.wyrm_stacks[0]) == 1 and int(s.moba.wyrm_stacks[1]) == 0 and evs.any(func(e): return e.k == "wyrm_down" and int(e.team) == 0 and int(e.stacks) == 1),
		"the Wyrm down by blue: a stack of WYRM'S HIDE for blue")
	check(paid and hide, "...every blue hero +%d gold and +%d %% max health (an epic each); red nothing" % [int(Moba.MONSTERS.wyrm.gold), int(Moba.WYRM_HIDE * 100.0)])
	check(not bool(wc.alive) and absf(float(wc.next) - s.time - Moba.WYRM_BACK) < 0.2 and float(Moba.WYRM_BACK) == 180.0, "...back 3:00 later")
	# the Hide stacks to WYRM_STACKS
	for i in 5:
		s.moba._spawn_camp(wc)
		s._damage(me, s.moba.camp_live(wc)[0], 1.0e9)
		s.drain_events()
	var full := true
	for hid in s.moba.heroes[0]:
		full = full and is_equal_approx(_hide(s.by_id[hid]), 1.0 + Moba.WYRM_HIDE * Moba.WYRM_STACKS)
	check(int(s.moba.wyrm_stacks[0]) == Moba.WYRM_STACKS and Moba.WYRM_STACKS == 4 and full, "...up to %d stacks (+%d %%), no more" % [Moba.WYRM_STACKS, int(Moba.WYRM_HIDE * Moba.WYRM_STACKS * 100.0)])
	var b3: Dictionary = s.by_id["b3"]
	var r0 := float(b3.m_hp)
	_to_level(s, b3, int(b3.level) + 2)
	check(float(b3.m_hp) > r0 * 1.05 and is_equal_approx(_hide(b3), 1.0 + Moba.WYRM_HIDE * Moba.WYRM_STACKS),
		"...and it stays through levels")
	var foe: Dictionary = s.by_id["r1"]
	foe.pos = Moba.WYRM_P + Vector2(0, -3)
	s.moba._spawn_camp(wc)
	s._damage(foe, s.moba.camp_live(wc)[0], 1.0e9)
	s.drain_events()
	check(int(s.moba.wyrm_stacks[1]) == 1, "red's kill: red's own stack")
	# bots: a side with three up and not outnumbered goes for it (not past the cap)
	var w = _new("knight", 16)
	_quiet(w)
	for tw in w.moba.towers:
		tw.dead = false                                 # (keeps shut: no King runs)
	var wc2: Dictionary = w.moba.camps.filter(func(c): return str(c.kind) == "wyrm")[0]
	w.moba._spawn_camp(wc2)
	var wy2: Dictionary = w.moba.camp_live(wc2)[0]
	var k := 0
	for hid in w.moba.heroes[0]:
		var h: Dictionary = w.by_id[hid]
		if hid == "you":
			continue
		h.bot = true
		h.pos = Moba.WYRM_P + Vector2(-6.0 + 3.0 * k, 13.0)
		k += 1
	_run(w, 6.0)
	check(bool(w.moba.wyrm_go[0]) and float(wy2.hp) < float(wy2.max_hp), "bots: three or more up and not outnumbered, they go for the Wyrm (%.0f%% left)" % (100.0 * float(wy2.hp) / float(wy2.max_hp)))
	w.moba.wyrm_stacks[0] = Moba.WYRM_STACKS
	w.moba._boss_call()
	check(not bool(w.moba.wyrm_go[0]), "...but not once their Hide is full")

# ---------------------------------------------------------------- 5. whole matches
func _matches() -> void:
	var n := int(OS.get_environment("MATCHES")) if OS.has_environment("MATCHES") else 1
	for mi in n:
		var sm = _new(Moba.HERO_ORDER[(mi * 5 + 3) % Moba.HERO_ORDER.size()], 3100 + mi)
		sm.by_id["you"].bot = true
		var ults := {}
		var clears := 0
		var buys := 0
		var lord := 0
		var wyrm := 0
		var t0 := Time.get_ticks_msec()
		while not sm.ended:
			sm.step()
			for e in sm.drain_events():
				match str(e.k):
					"ult": ults[str(e.ult)] = int(ults.get(str(e.ult), 0)) + 1
					"camp_clear": clears += 1
					"buy": buys += 1
					"lord_down": lord += 1
					"wyrm_down": wyrm += 1
		var items: Array = sm.units.filter(func(u): return bool(u.get("hero", false))).map(func(u): return (u.items as Array).size())
		print("  match %d: %.0f s, winner %d (%s), Kings %d%%/%d%%, KOs %s, towers %d/%d, camps cleared %d, Lord %d, Wyrm %d (Hide %s), items bought %d %s, ultimates %s, %d ms" % [mi,
			sm.time, sm.winner, sm.end_reason, int(sm.moba.king_frac(0) * 100.0), int(sm.moba.king_frac(1) * 100.0), str(sm.kills), sm.moba.towers_down(0),
			sm.moba.towers_down(1), clears, lord, wyrm, str(sm.moba.wyrm_stacks), buys, str(items), str(ults), Time.get_ticks_msec() - t0])
		if mi == 0:
			check(buys >= 10 and items.all(func(k): return k >= 1), "a whole match: every hero bought items (%d buys)" % buys)
			check(ults.size() >= 3, "...the bots used their ultimates (%d kinds)" % ults.size())
			check(clears >= 6, "...the junglers cleared camps (%d)" % clears)

func _add_minion(s, team: int, cls: String, p: Vector2) -> Dictionary:
	s.moba._mid += 1
	var id := "tm%d" % s.moba._mid
	var u: Dictionary = s._new_unit(id, team, false)
	u.cls = cls
	u["minion"] = true
	u["mk"] = {"knight":"melee", "ranger":"caster", "mage":"siege", "barbarian":"super"}.get(cls, "melee")     # (0.31.158)
	u["lane"] = 0
	u["wp"] = 1
	u["m_hp"] = Moba.MINION_HP
	u["m_dmg"] = Moba.MINION_DMG
	u["m_spd"] = 0.0
	u.max_hp = float(s.stat(u, "hp"))
	u.hp = u.max_hp
	u.pos = p
	s.units.append(u)
	s.by_id[id] = u
	return u
