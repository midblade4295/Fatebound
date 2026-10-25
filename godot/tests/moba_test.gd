extends SceneTree
# 0.31.155 5V5 (the test; scripts/siege/moba.gd), the rules on the sim:
#  1. the start: five heroes a side in their own classes (yours as picked; no Villagers, no hats on the stands), eleven
#     towers a side (0.31.165, the Rift: three a lane and two King towers in the keep; six until then), solid;
#  2. the waves: every 30 s from 15 s, each castle sends League's wave down each lane (0.31.158: 3 melee -- Knights --
#     and 3 casters -- Archers; the siege minions and super minions are moba_more_test's); they march toward the enemy;
#     a wave still alive when the next comes is caught up with (stacking);
#  3. the towers (League's rules): the nearest minion first; an enemy hero who hurts one of its heroes in range -> him
#     (call for help); heroes alone when no minion is in range; shots ramping on a hero (+50 % a shot, 3 times at most);
#     a minion loses 45 % (Knight) / 70 % of its health a shot; an inner tower can't be hurt while the outer stands; a
#     tower without the attackers' minions near takes a fifth (melee heroes x1.2); a gate can't be hurt while the third tower of the lane that
#     ends at it stands; the King towers while all the keep's gates stand (0.31.165);
#  4. levels: XP from minions dying near you, a level up offers 3 upgrades, a pick applies; bots pick by themselves;
#  5. a fallen hero: no hat, back as himself at his castle after 4 + 1.6 x level s; the castle heals; ACTION only for the
#     King;
#  6. (0.31.156) the Kings are the hearts: home on their thrones, untouchable while their King towers stand (0.31.165), then hit
#     and hitting back (a slam round him), healing when left alone; defeat one and the match is won; at time, the side
#     that did more to the other's King;
#  7. a whole match, bots on both sides: towers fall, levels climb, it ends.
#   godot --headless --path godot -s res://tests/moba_test.gd
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Moba = preload("res://scripts/siege/moba.gd")

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

func _minions(s, team := -1) -> Array:
	return s.units.filter(func(u): return bool(u.get("minion", false)) and s.alive(u) and (team < 0 or int(u.team) == team))

func _run(s, secs: float) -> Array:
	var evs := []
	for i in int(secs / Sim.TICK):
		s.step()
		evs.append_array(s.drain_events())
	return evs

func _clear_minions(s) -> void:
	for u in s.units.duplicate():
		if bool(u.get("minion", false)):
			s.units.erase(u)
			s.by_id.erase(u.id)

func _park_heroes(s) -> void:
	# every hero home and out of the way (bots stay put while we set a scene up)
	for u in s.units:
		if bool(u.get("hero", false)):
			u.bot = false
			u.pos = Sim.spawn(int(u.team))
			u.move = Vector2.ZERO

func _init() -> void:
	# --- 1. the start
	var s = _new("archmage", 77)
	var hs: Array = s.units.filter(func(u): return bool(u.get("hero", false)))
	check(s.units.size() == 10 and hs.size() == 10 and s.units.all(func(u): return u.cls != "villager"), "five heroes a side, no Villagers")
	var me: Dictionary = s.by_id["you"]
	check(me.cls == "mage" and me.up and str(me.hid) == "archmage" and is_equal_approx(float(me.max_hp), 75.0 * 1.15 * Moba.HERO_HP),
		"you: the Archmage (%d health: the class's x1.15 x%.1f)" % [int(me.max_hp), Moba.HERO_HP])
	var blue: Array = s.units.filter(func(u): return int(u.team) == 0).map(func(u): return str(u.hid))
	check(blue.size() == 5 and blue.all(func(h): return blue.count(h) == 1), "no two heroes the same on a side (%s)" % str(blue))
	# (0.31.217, Honor of Kings: three towers a lane, no King towers -- 0.31.165-216 two King towers in the keep too)
	check(s.moba.towers.size() == 18 and s.moba.towers.filter(func(t): return int(t.team) == 0).size() == 9
		and s.moba.towers.filter(func(t): return int(t.tier) == 4).is_empty()
		and s.obstacles.filter(func(o): return str(o.kind) == "moba_tower").size() == 18, "nine towers a side (three a lane), solid")
	var paired := true
	for tw in s.moba.towers:
		if int(tw.team) != 0:
			continue
		var twin = s.moba.towers.filter(func(o): return int(o.team) == 1 and (o.p as Vector2).is_equal_approx(-(tw.p as Vector2)))
		paired = paired and twin.size() == 1 and int(twin[0].tier) == int(tw.tier) \
			and int(twin[0].lane) == (2 - int(tw.lane) if int(tw.lane) >= 0 else -1)
	check(paired, "red's towers are blue's, mirrored")
	# --- 2. the waves
	_run(s, 14.8)
	check(_minions(s).is_empty(), "no minions before 0:15")
	_run(s, 0.4)
	var w1: Array = _minions(s, 0)
	var comp := {}
	for u in w1:
		comp["%d:%s" % [int(u.lane), u.cls]] = int(comp.get("%d:%s" % [int(u.lane), u.cls], 0)) + 1
	check(w1.size() == 18 and _minions(s, 1).size() == 18 and comp.get("0:knight", 0) == 3 and comp.get("1:ranger", 0) == 3 and comp.get("2:knight", 0) == 3
		and not comp.has("0:priest") and not comp.has("1:priest") and not comp.has("2:priest"),
		"at 0:15 each castle sends 18: per lane 3 melee (Knights), 3 casters (Archers), no Priests (%s)" % str(comp))
	check(w1.all(func(u): return (u.pos as Vector2).distance_to(s.moba.wp(0, int(u.lane), 0)) < 6.0), "...from their own gate")
	var z0: float = w1.map(func(u): return float(u.pos.y)).reduce(func(a, b): return a + b) / float(w1.size())
	_run(s, 6.0)
	var z1: float = w1.map(func(u): return float(u.pos.y)).reduce(func(a, b): return a + b) / float(w1.size())
	check(z1 < z0 - 15.0, "they march toward the enemy (blue: z %.0f -> %.0f)" % [z0, z1])
	# stacking: in an ordinary match, waves that meet stop to fight, and the next wave walks up to them -- one side's
	# minions of two waves together in a lane (more than one wave's 4 within 8 m of each other) at some point
	var sk = _new("knight", 31)
	sk.by_id["you"].bot = true
	var most := 0
	for i in int(150.0 / Sim.TICK):
		sk.step()
		sk.drain_events()
		if i % 30 != 0:
			continue
		for team in 2:
			for lane in 3:
				var ms: Array = _minions(sk, team).filter(func(u): return int(u.lane) == lane)
				for a in ms:
					var n := 0
					for b in ms:
						if (a.pos as Vector2).distance_to(b.pos) <= 8.0:
							n += 1
					most = maxi(most, n)
	check(most > 6, "waves stack: a wave still fighting when the next comes is joined by it (%d of one side's minions together)" % most)
	# --- 3. the towers
	var t = _new("knight", 5)
	_park_heroes(t)
	_clear_minions(t)
	var tw: Dictionary = t.moba.towers.filter(func(o): return int(o.team) == 1 and int(o.lane) == 0 and int(o.tier) == 1)[0]
	var twp: Vector2 = tw.p
	t.moba.wave_at = INF
	var m: Dictionary = _add_minion(t, 0, "knight", twp + Vector2(0, 5))
	var bh: Dictionary = t.by_id["b1"]
	var rh: Dictionary = t.by_id["r1"]
	bh.pos = twp + Vector2(4, 1)
	rh.pos = twp + Vector2(-3, -2)
	var shots := []
	for e in _run(t, 1.0):
		if e.k == "tshot" and int(e.tw) == int(tw.id):
			shots.append(e)
	check(not shots.is_empty() and str(shots[0].id) == str(m.id), "a hero and a minion in range: the tower shoots the minion")
	check(absf(float(m.hp) - float(m.max_hp) * (1.0 - 0.45)) < 1.0, "...a Knight minion loses 45%% a shot (%d of %d)" % [int(m.hp), int(m.max_hp)])
	t._damage(bh, rh, 5.0)
	shots = []
	for e in _run(t, 1.0):
		if e.k == "tshot" and int(e.tw) == int(tw.id):
			shots.append(e)
	check(not shots.is_empty() and str(shots[0].id) == "b1", "the blue hero hurts a red hero under the red tower: it turns on him (call for help)")
	shots = []
	var hp_before := float(bh.hp)
	bh.hp = 100000.0
	bh.max_hp = 100000.0
	for e in _run(t, 4.2):
		if e.k == "tshot" and int(e.tw) == int(tw.id):
			shots.append(int(e.ramp))
	check(shots.size() >= 4 and (shots.slice(0, 4) == [1, 2, 3, 3] or shots.slice(0, 4) == [0, 1, 2, 3]), "shots on a hero ramp up, 3 times at most (%s)" % str(shots))
	_clear_minions(t)
	_park_heroes(t)
	# alone: heroes only when no minion's in range
	bh.pos = twp + Vector2(3, 3)
	tw.target = ""
	shots = []
	for e in _run(t, Moba.TOWER_EVERY + 0.3):
		if e.k == "tshot" and int(e.tw) == int(tw.id):
			shots.append(str(e.id))
	check(not shots.is_empty() and shots[0] == "b1", "no minion in range: it shoots the hero")
	_park_heroes(t)
	# tier order, backdoor
	var inner: Dictionary = t.moba.towers.filter(func(o): return int(o.team) == 1 and int(o.lane) == 0 and int(o.tier) == 2)[0]
	var ihp := float(inner.hp)
	t.moba.hit_tower(bh, int(inner.id), 100.0)
	check(float(inner.hp) == ihp, "the inner tower can't be hurt while the outer stands")
	var ohp := float(tw.hp)
	t.moba.hit_tower(bh, int(tw.id), 100.0)
	var bm: float = t.moba.tower_mult(bh)
	check(is_equal_approx(bm, Moba.MELEE_VS_TOWER), "a melee hero hits towers x%.1f (League: +20 %%)" % bm)
	check(is_equal_approx(float(tw.hp), ohp - 100.0 * Moba.BACKDOOR * bm), "the outer tower without our minions near: a fifth of the damage (%.0f)" % (ohp - float(tw.hp)))
	_add_minion(t, 0, "ranger", twp + Vector2(0, 8))
	ohp = float(tw.hp)
	t.moba.hit_tower(bh, int(tw.id), 100.0)
	check(is_equal_approx(float(tw.hp), ohp - 100.0 * bm), "...with our minion near: all of it")
	# 0.31.217 (Honor of Kings): the gates stand open; a lane's three towers, then the King
	check(t.open_gates and t.gates.all(func(g): return not t.gate_blocks(g)), "the keeps' gates stand open to everyone")
	var third: Dictionary = t.moba.towers.filter(func(o): return int(o.team) == 1 and int(o.lane) == 0 and int(o.tier) == 3)[0]
	var thp := float(third.hp)
	t.moba.hit_tower(bh, int(tw.id), 100000.0)
	t.moba.hit_tower(bh, int(inner.id), 100000.0)
	check(bool(tw.dead) and bool(inner.dead) and not t.moba.king_open(1), "outer, then inner tower down; their King still shut")
	t.moba.hit_tower(bh, int(third.id), 100000.0)
	check(bool(third.dead) and thp > 0.0 and t.moba.king_open(1), "...the third (high ground) down: their King is open")
	check(t.moba.towers_down(1) == 3, "three of red's towers down")
	# --- 4. levels
	var l = _new("knight", 9)
	var you: Dictionary = l.by_id["you"]
	var dmg1 := float(l.stat(you, "dmg"))
	l.moba.add_xp(you, Moba.XP_BASE + 1.0)
	check(int(you.level) == 2 and (you.picks as Array).size() == 1 and (you.picks[0] as Array).size() == 3, "a level: 3 upgrades offered")
	check(float(l.stat(you, "dmg")) > dmg1, "...and a little more damage")
	var offer: Array = you.picks[0]
	var k := str(offer[0])
	check(l.act("you", "pick", 0) and int(you.ups.get(k, 0)) == 1 and (you.picks as Array).is_empty(), "a pick (%s) applies" % k)
	var bot: Dictionary = l.by_id["b2"]
	l.moba.add_xp(bot, Moba.XP_BASE * 3.0)
	check(int(bot.level) >= 2 and (bot.picks as Array).is_empty() and not (bot.ups as Dictionary).is_empty(), "bots pick by themselves")
	_clear_minions(l)
	_park_heroes(l)
	var mn: Dictionary = _add_minion(l, 1, "ranger", you.pos + Vector2(2, 0))
	var xp0 := float(you.xp)
	l._kill(you, mn)
	check(float(you.xp) > xp0, "an enemy minion dying near you: XP (+%.0f)" % (float(you.xp) - xp0))
	# --- 5. falling, the castle, ACTION
	var cls0 := str(you.cls)
	you.pos = Vector2(0, 5)
	l._kill({}, you)
	check(you.cls == cls0, "a hero falls: he stays a %s" % cls0)
	var wait := Moba.RESPAWN_BASE + Moba.RESPAWN_LVL * float(int(you.level))
	check(is_equal_approx(float(you.respawn_at) - l.time, wait), "back in %.1f s (level %d)" % [wait, int(you.level)])
	_run(l, wait + 0.2)
	check(l.alive(you) and you.cls == cls0 and Sim.in_castle(you.pos, 0), "...back as himself, in his castle")
	you.hp = you.max_hp * 0.3
	var h0 := float(you.hp)
	_run(l, 2.0)
	check(float(you.hp) > h0 + you.max_hp * 0.09, "his castle heals him")
	# --- 6. the Kings
	var kk = _new("knight", 13)
	_park_heroes(kk)
	_clear_minions(kk)
	kk.moba.wave_at = INF
	check(kk.oracles[0].state == "home" and (kk.oracles[1].pos as Vector2).is_equal_approx(Sim.throne(1)) and float(kk.moba.kings[1].hp) == Moba.KING_HP
		and kk.obstacles.filter(func(o): return str(o.kind) == "moba_king").size() == 2, "each King home on his throne, %d health, solid" % int(Moba.KING_HP))
	var att: Dictionary = kk.by_id["b1"]
	att.hp = 1.0e6
	att.max_hp = 1.0e6
	kk.moba.hit_king(att, 1, 300.0)
	check(float(kk.moba.kings[1].hp) == Moba.KING_HP and not kk.moba.king_open(1), "while every lane of his stands he can't be hurt")
	# (0.31.217: a lane's three towers, then the King -- Honor of Kings' crystal; his two King towers until then)
	for tier in [1, 2]:
		var tw2: Dictionary = kk.moba.towers.filter(func(o): return int(o.team) == 1 and int(o.lane) == 2 and int(o.tier) == tier)[0]
		kk.moba.hit_tower(att, int(tw2.id), 100000.0)
	kk.moba.hit_king(att, 1, 300.0)
	check(not kk.moba.king_open(1) and float(kk.moba.kings[1].hp) == Moba.KING_HP, "a lane's outer and inner towers down: still not")
	var hg: Dictionary = kk.moba.towers.filter(func(o): return int(o.team) == 1 and int(o.lane) == 2 and int(o.tier) == 3)[0]
	kk.moba.hit_tower(att, int(hg.id), 100000.0)
	kk.moba.hit_king(att, 1, 300.0)
	check(kk.moba.king_open(1) and float(kk.moba.kings[1].hp) == Moba.KING_HP - 300.0, "its high ground tower down: he takes the hit")
	att.pos = kk.moba.king_pos(1) + Vector2(2.0, 0.0)
	var hp0 := float(att.hp)
	var slams := 0
	for e in _run(kk, 2.0):
		if e.k == "king_slam" and int(e.team) == 1:
			slams += 1
	check(slams >= 1 and float(att.hp) < hp0, "he hits back: a slam round him (%d)" % slams)
	att.pos = Sim.spawn(0)
	var kh := float(kk.moba.kings[1].hp)
	_run(kk, Moba.KING_QUIET + 2.0)
	check(float(kk.moba.kings[1].hp) > kh, "left alone, he heals")
	check(kk.moba.tiebreak() == 0, "at time: the side that did more to the other's King wins")
	att.pos = kk.moba.king_pos(1) + Vector2(2.0, 0.0)
	kk.moba.hit_king(att, 1, Moba.KING_HP)
	_run(kk, 0.2)
	check(bool(kk.moba.kings[1].dead) and kk.ended and kk.winner == 0 and kk.end_reason == "king" and kk.score[0] == 1, "their King defeated: the match is won")
	# --- 7. whole matches
	var n := int(OS.get_environment("MATCHES")) if OS.has_environment("MATCHES") else 1
	for mi in n:
		var sm = _new(Moba.HERO_ORDER[mi % Moba.HERO_ORDER.size()], 2000 + mi)
		sm.by_id["you"].bot = true
		var t0 := Time.get_ticks_msec()
		var gates_down := 0
		var peak := 0
		while not sm.ended:
			sm.step()
			for e in sm.drain_events():
				if e.k == "gate_broken":
					gates_down += 1
			if int(sm.time * 30.0) % 300 == 0:
				peak = maxi(peak, sm.units.size())
		var lv: Array = sm.units.filter(func(u): return bool(u.get("hero", false))).map(func(u): return int(u.level))
		print("  match %d: %.0f s, winner %d (%s), Kings %d%%/%d%%, hero KOs %s, towers down %d/%d, gates down %d, levels %s, most units %d, %d ms" % [mi,
			sm.time, sm.winner, sm.end_reason, int(sm.moba.king_frac(0) * 100.0), int(sm.moba.king_frac(1) * 100.0), str(sm.kills), sm.moba.towers_down(0),
			sm.moba.towers_down(1), gates_down, str(lv), peak, Time.get_ticks_msec() - t0])
		if mi == 0:
			check(sm.ended and sm.moba.towers_down(0) + sm.moba.towers_down(1) >= 2 and lv.max() >= 6 and peak < 10 + 2 * Moba.MINION_CAP + 37 + 12 + 1,
				"a whole match: towers fall (%d), heroes reach level %d, minions stay under the cap (%d units at most, with the jungle's 37 and LEGIONs)" % [sm.moba.towers_down(0) + sm.moba.towers_down(1), lv.max(), peak])
	print("MOBA_PASS" if fails.is_empty() else "MOBA_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)

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
