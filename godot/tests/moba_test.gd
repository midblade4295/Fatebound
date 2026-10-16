extends SceneTree
# 0.31.155 5V5 (the test; scripts/siege/moba.gd), the rules on the sim:
#  1. the start: five heroes a side in their own classes (yours as picked; no Villagers, no hats on the stands), six
#     towers a side beside the lanes, solid;
#  2. the waves: every 30 s from 15 s, each castle sends 1 Knight, 2 Archers, 1 Priest down each lane; they march toward
#     the enemy; a wave still alive when the next comes is caught up with (stacking);
#  3. the towers (League's rules): the nearest minion first; an enemy hero who hurts one of its heroes in range -> him
#     (call for help); heroes alone when no minion is in range; shots ramping on a hero (+40 % a shot, 3 times at most);
#     a minion loses 45 % (Knight) / 70 % of its health a shot; an inner tower can't be hurt while the outer stands; a
#     tower without the attackers' minions near takes a third; a gate can't be hurt while an inner tower of a lane that
#     leads to it stands;
#  4. levels: XP from minions dying near you, a level up offers 3 upgrades, a pick applies; bots pick by themselves;
#  5. a fallen hero: no hat, back as himself at his castle after 4 + 1.6 x level s; the castle heals; ACTION only for the
#     King;
#  6. a whole match, bots on both sides: towers fall, levels climb, it ends.
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
	check(s.stands.all(func(st): return int(st.stock) == 0) and s.hats.is_empty(), "the hat stands are empty")
	check(s.moba.towers.size() == 12 and s.moba.towers.filter(func(t): return int(t.team) == 0).size() == 6
		and s.obstacles.filter(func(o): return str(o.kind) == "moba_tower").size() == 12, "six towers a side, solid")
	var paired := true
	for tw in s.moba.towers:
		if int(tw.team) != 0:
			continue
		var twin = s.moba.towers.filter(func(o): return int(o.team) == 1 and int(o.lane) == 2 - int(tw.lane) and int(o.tier) == int(tw.tier))
		paired = paired and twin.size() == 1 and (twin[0].p as Vector2).is_equal_approx(-(tw.p as Vector2))
	check(paired, "red's towers are blue's, mirrored")
	# --- 2. the waves
	_run(s, 14.8)
	check(_minions(s).is_empty(), "no minions before 0:15")
	_run(s, 0.4)
	var w1: Array = _minions(s, 0)
	var comp := {}
	for u in w1:
		comp["%d:%s" % [int(u.lane), u.cls]] = int(comp.get("%d:%s" % [int(u.lane), u.cls], 0)) + 1
	check(w1.size() == 12 and _minions(s, 1).size() == 12 and comp.get("0:knight", 0) == 1 and comp.get("1:ranger", 0) == 2 and comp.get("2:priest", 0) == 1,
		"at 0:15 each castle sends 12: per lane 1 Knight, 2 Archers, 1 Priest")
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
	check(most > Moba.WAVE.size(), "waves stack: a wave still fighting when the next comes is joined by it (%d of one side's minions together)" % most)
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
	for e in _run(t, 1.0):
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
	check(is_equal_approx(float(tw.hp), ohp - 100.0 * Moba.BACKDOOR), "the outer tower without our minions near: a third of the damage (%.0f)" % (ohp - float(tw.hp)))
	_add_minion(t, 0, "ranger", twp + Vector2(0, 8))
	ohp = float(tw.hp)
	t.moba.hit_tower(bh, int(tw.id), 100.0)
	check(is_equal_approx(float(tw.hp), ohp - 100.0), "...with our minion near: all of it")
	# gates
	var red_gate: Dictionary = {}
	for g in t.gates:
		if int(g.team) == 1 and str(g.get("kind", "")) != "jail" and (g.c as Vector2).distance_to(t.moba.wp(0, 0, Moba.LANES[0].size() - 1)) < 6.0:
			red_gate = g
	var ghp := float(red_gate.hp)
	t._damage_gate(bh, red_gate, 200.0)
	check(not red_gate.is_empty() and float(red_gate.hp) == ghp, "their gate at the end of the west lane can't be hurt while its inner tower stands")
	t.moba.hit_tower(bh, int(tw.id), 100000.0)
	t.moba.hit_tower(bh, int(inner.id), 100000.0)
	check(bool(tw.dead) and bool(inner.dead), "outer, then inner tower down")
	t._damage_gate(bh, red_gate, 200.0)
	check(float(red_gate.hp) == ghp - 200.0, "...now the gate takes damage")
	check(t.moba.towers_down(1) == 2, "two of red's towers down")
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
	check(l.hats.is_empty() and you.cls == cls0, "a hero falls: no hat drops, he stays a %s" % cls0)
	var wait := Moba.RESPAWN_BASE + Moba.RESPAWN_LVL * float(int(you.level))
	check(is_equal_approx(float(you.respawn_at) - l.time, wait), "back in %.1f s (level %d)" % [wait, int(you.level)])
	_run(l, wait + 0.2)
	check(l.alive(you) and you.cls == cls0 and Sim.in_castle(you.pos, 0), "...back as himself, in his castle")
	you.hp = you.max_hp * 0.3
	var h0 := float(you.hp)
	_run(l, 2.0)
	check(float(you.hp) > h0 + you.max_hp * 0.09, "his castle heals him")
	var st: Dictionary = l.stands.filter(func(x): return int(x.team) == 0)[0]
	you.pos = st.p
	check(l.context_action(you) == "" and not l.act("you", "interact") and not l.act("you", "hat_swap"), "at a hat stand: nothing to take")
	# --- 6. whole matches
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
		print("  match %d: %.0f s, winner %d (%s), score %s, hero KOs %s, towers down %d/%d, gates down %d, levels %s, most units %d, %d ms" % [mi,
			sm.time, sm.winner, sm.end_reason, str(sm.score), str(sm.kills), sm.moba.towers_down(0), sm.moba.towers_down(1), gates_down, str(lv), peak,
			Time.get_ticks_msec() - t0])
		if mi == 0:
			check(sm.ended and sm.moba.towers_down(0) + sm.moba.towers_down(1) >= 2 and lv.max() >= 6 and peak < 10 + 2 * Moba.MINION_CAP + 1,
				"a whole match: towers fall (%d), heroes reach level %d, minions stay under the cap (%d units at most)" % [sm.moba.towers_down(0) + sm.moba.towers_down(1), lv.max(), peak])
	print("MOBA_PASS" if fails.is_empty() else "MOBA_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)

func _add_minion(s, team: int, cls: String, p: Vector2) -> Dictionary:
	s.moba._mid += 1
	var id := "tm%d" % s.moba._mid
	var u: Dictionary = s._new_unit(id, team, false, "raid")
	u.cls = cls
	u["minion"] = true
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
