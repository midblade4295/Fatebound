extends SceneTree
# 0.31.158 5V5 (scripts/siege/moba.gd, moba_vision.gd), Kevin: "Add a fog of war system like league of legends does
# it. Also the enemy camps seem to recharge health immediately if you get too far away. Make it so when a team kills the
# giant in middle, he will spawn on your side like a minion. Balance the minions better ... minions need to work like
# LoL ... check tower mechanics to work like league of legends" -- on the sim:
#  1. THE FOG: a side sees only what's in its heroes', minions', towers', wards' and castle's sight; a unit in a brush
#     patch is hidden from the other side unless one of theirs stands in the same patch; attacking shows you for 2 s;
#     wards (charges that come back, a lifetime, at most 3 each; bots put them in brush); bots and the auto-aim can't
#     pick out what their side doesn't see;
#  2. THE MINIONS: League's waves (3 melee, 3 casters; a siege minion every 3rd wave, every 2nd from 7:00, every wave
#     from 12:30; quicker waves later), each kind its own health and damage, a little stronger every 90 s, 60 % damage
#     to heroes, League's target priority (the call for help first, then minions before heroes), not what they can't
#     see; gold by kind;
#  3. THE TOWERS: League's targets (siege and super minions first, melee, casters, heroes last), a share of a minion's
#     health a shot by kind, Warming Up cooling off 5 s after the last hero shot, plates until 7:00, a broken gate stands
#     again after GATE_BACK;
#  4. THE CAMPS' PATIENCE: chased outside the leash they don't give up at once -- patience drains, then a soft reset
#     (walking home, healing a little a second, a blow from inside the leash brings them back), then a hard reset
#     (untouchable, quicker healing) -- no instant full heal;
#  5. THE BONE LORD MARCHES: slain, he rises for the slayers and walks the middle lane with their minions, a tower's shot
#     taking 5 % of him, towers and gates taking x3 from him, 150 gold for whoever finishes him.
#   godot --headless --path godot -s res://tests/moba_lol_test.gd
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Moba = preload("res://scripts/siege/moba.gd")
const Vision = preload("res://scripts/siege/moba_vision.gd")

const Q := Vector2(14.0, -20.0)               # open ground on red's side of the river (0.31.165: the Rift; was (28, -35))

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
	# no waves, no camps, no towers, every hero home and still
	s.moba.wave_at = INF
	for c in s.moba.camps:
		c.next = INF
		c.alive = false
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

func _tough(u: Dictionary) -> void:
	u.max_hp = 100000.0
	u.hp = 100000.0

func _add_minion(s, team: int, mk: String, p: Vector2, think := true) -> Dictionary:
	s.moba._mid += 1
	var id := "tm%d" % s.moba._mid
	var u: Dictionary = s._new_unit(id, team, think)
	u.cls = str(Moba.MINION_CLS[mk])
	u["minion"] = true
	u["mk"] = mk
	u["lane"] = 0
	u["wp"] = 1
	u["m_hp"] = float(Moba.MINION_KIND_HP[mk])
	u["m_dmg"] = float(Moba.MINION_KIND_DMG[mk])
	u["m_spd"] = 0.0
	u.max_hp = float(s.stat(u, "hp"))
	u.hp = u.max_hp
	u.pos = p
	s.units.append(u)
	s.by_id[id] = u
	return u

func _init() -> void:
	_fog()
	_minions()
	_towers()
	_camps()
	_lord()
	print("MOBA_LOL_FAIL " + str(fails) if not fails.is_empty() else "MOBA_LOL_PASS")
	quit(1 if not fails.is_empty() else 0)

# ---------------------------------------------------------------- 1. the fog
func _fog() -> void:
	var s = _new("knight", 41)
	_quiet(s)
	var v = s.moba.vision
	var b1: Dictionary = s.by_id["b1"]
	var r1: Dictionary = s.by_id["r1"]
	var you: Dictionary = s.by_id["you"]
	r1.pos = Q
	_run(s, 0.3)
	check(not s.moba.can_see(0, r1) and s.moba.can_see(1, r1), "a red hero far from blue's sight: blue doesn't see him (red does)")
	b1.pos = Q + Vector2(0, Vision.SIGHT_HERO - 1.5)
	_run(s, 0.3)
	check(s.moba.can_see(0, r1), "a blue hero within %.1f m: now blue does" % Vision.SIGHT_HERO)
	b1.pos = Q + Vector2(0, Vision.SIGHT_HERO + 1.5)
	_run(s, 0.3)
	check(not s.moba.can_see(0, r1), "...just past it: not")
	check(s.nearest_enemy(b1, 40.0).get("id", "") != "r1", "a bot can't pick out an enemy his side doesn't see")
	b1.pos = Q + Vector2(0, 8)
	_run(s, 0.3)
	check(s.nearest_enemy(b1, 40.0).get("id", "") == "r1", "...seen: he can")
	# brush
	var bp: Vector2 = -(Vision.BRUSH_BLUE[0][0] as Vector2)   # one of red's brush patches (0.31.216: the HoK map's)
	var bid: int = v.brush_at(bp)
	check(bid >= 0 and v.brush_at(bp + Vector2(0, 5)) < 0, "red's side has its brush patches (%d in all)" % v.brushes.size())
	r1.pos = bp
	b1.pos = bp + Vector2(0, 5)
	_run(s, 0.3)
	check(not s.moba.can_see(0, r1) and s.moba.can_see(1, b1), "the red hero in a brush patch, the blue one beside it: blue can't see in; red sees out")
	b1.pos = bp + Vector2(1, 0)
	_run(s, 0.3)
	check(s.moba.can_see(0, r1) and s.moba.can_see(1, b1), "...the blue one steps into the same patch: they see each other")
	# attacking shows you
	b1.pos = bp + Vector2(0, 5)
	_tough(b1)
	_run(s, 0.3)
	s._damage(r1, b1, 1.0)
	check(s.moba.can_see(0, r1), "the hidden red hero hits the blue one: he's shown")
	_run(s, Vision.REVEAL + 0.4)
	check(not s.moba.can_see(0, r1), "...for %.0f s" % Vision.REVEAL)
	# wards
	b1.pos = Sim.spawn(0)
	you.pos = bp + Vector2(-1, 0)
	check(int(you.ward_ch) == Vision.WARD_CHARGES, "every hero carries %d ward charges" % Vision.WARD_CHARGES)
	var evs := []
	check(s.act("you", "ward"), "WARD: one at your feet")
	evs.append_array(s.drain_events())
	check(v.wards.size() == 1 and int(v.wards[0].brush) == bid and evs.any(func(e): return e.k == "ward") and is_equal_approx(float(you.ward_ch), Vision.WARD_CHARGES - 1.0),
		"...in the brush patch, a charge used")
	you.pos = Sim.spawn(0)
	_run(s, 0.3)
	check(s.moba.can_see(0, r1), "you walk away: the ward still shows the red hero hiding in that patch")
	r1.pos = bp + Vector2(0, Vision.SIGHT_WARD + 4.0)
	_run(s, 0.3)
	check(not s.moba.can_see(0, r1), "...but not past its sight (%.0f m)" % Vision.SIGHT_WARD)
	r1.pos = bp
	evs = _run(s, Vision.WARD_LIFE)
	check(v.wards.is_empty() and evs.any(func(e): return e.k == "ward_gone") and not s.moba.can_see(0, r1), "%.0f s later the ward's gone" % Vision.WARD_LIFE)
	check(is_equal_approx(float(you.ward_ch), Vision.WARD_CHARGES), "...and the charge is back (%.0f s each)" % Vision.WARD_RECHARGE)
	you.ward_ch = 0.0
	check(not s.act("you", "ward"), "no charge: no ward")
	you.ward_ch = 10.0
	for i in Vision.WARD_MAX + 1:
		you.pos = Vector2(-20.0 + 3.0 * float(i), 40.0)
		s.act("you", "ward")
	var mine: Array = v.wards.filter(func(w): return str(w.owner) == "you")
	check(mine.size() == Vision.WARD_MAX and int(mine[0].id) != 2, "at most %d of your own: the oldest goes" % Vision.WARD_MAX)
	# bots ward brush
	var b2: Dictionary = s.by_id["b2"]
	b2.bot = true
	b2.ward_ch = 2.0
	b2.pos = bp
	v._bot_wards()
	check(v.wards.any(func(w): return str(w.owner) == "b2" and int(w.brush) == bid), "a bot in a brush patch with a charge wards it")
	# towers and castles see
	var t = _new("knight", 42)
	_quiet(t)
	var tw: Dictionary = t.moba.towers.filter(func(o): return int(o.team) == 0 and int(o.lane) == 0 and int(o.tier) == 1)[0]
	tw.dead = false
	var tr1: Dictionary = t.by_id["r1"]
	tr1.pos = (tw.p as Vector2) + Vector2(Vision.SIGHT_TOWER - 2.0, 0)
	_run(t, 0.3)
	var seen_t: bool = t.moba.can_see(0, tr1)
	tw.dead = true
	_run(t, 0.3)
	check(seen_t and not t.moba.can_see(0, tr1), "a tower sees %.1f m round it; fallen, it doesn't" % Vision.SIGHT_TOWER)
	tr1.pos = t.moba.king_pos(0) + Vector2(0, -(Vision.SIGHT_CASTLE - 3.0))
	_run(t, 0.3)
	check(t.moba.can_see(0, tr1), "the castle sees round the King")

# ---------------------------------------------------------------- 2. the minions
func _minions() -> void:
	var s = _new("knight", 43)
	var m = s.moba
	var t0: float = s.time
	check(m.wave_kinds(0, 0, 1) == ["melee", "melee", "melee", "caster", "caster", "caster"], "a wave: 3 melee, 3 casters (%s)" % str(m.wave_kinds(0, 0, 1)))
	check(m.wave_kinds(0, 0, 3) == ["melee", "melee", "melee", "siege", "caster", "caster", "caster"] and not m.wave_kinds(0, 0, 4).has("siege"),
		"every 3rd wave brings a siege minion")
	s.time = Moba.MID_AT + 1.0
	check(m.wave_kinds(0, 0, 4) == ["melee", "melee", "siege", "caster", "caster", "caster"] and not m.wave_kinds(0, 0, 5).has("siege"),
		"from %d:%02d every 2nd (2 melee with it)" % [int(Moba.MID_AT) / 60, int(Moba.MID_AT) % 60])
	s.time = Moba.LATE_AT + 1.0
	check(m.wave_kinds(0, 0, 5).has("siege") and m.wave_kinds(0, 0, 6).has("siege"), "from %d:%02d every wave" % [int(Moba.LATE_AT) / 60, int(Moba.LATE_AT) % 60])
	check(not m.wave_kinds(0, 0, 1).has("priest") and not Moba.MINION_CLS.values().has("priest"), "no Priests in the waves")
	s.time = t0
	# wave timing
	_quiet(s)
	s.time = Moba.MID_AT + 2.0
	m.wave_at = s.time
	s.step()
	check(is_equal_approx(m.wave_at - (Moba.MID_AT + 2.0), Moba.WAVE_EVERY_MID), "from %d:%02d a wave every %.0f s" % [int(Moba.MID_AT) / 60, int(Moba.MID_AT) % 60, Moba.WAVE_EVERY_MID])
	# kinds, sizes, upgrades
	var s2 = _new("knight", 44)
	_quiet(s2)
	s2.time = 200.0
	s2.moba.waves = 2
	s2.moba.wave_at = s2.time
	s2.step()
	var w: Array = s2.units.filter(func(u): return bool(u.get("minion", false)) and int(u.team) == 0 and int(u.lane) == 0)
	var up := 1.0 + Moba.MINION_UP * 2.0
	var ok := w.size() == 7
	for u in w:
		ok = ok and is_equal_approx(float(u.m_hp), float(Moba.MINION_KIND_HP[str(u.mk)]) * up) and str(u.cls) == str(Moba.MINION_CLS[str(u.mk)])
	var sg: Array = w.filter(func(u): return str(u.mk) == "siege")
	check(ok and sg.size() == 1 and is_equal_approx(float(sg[0].get("mscale", 1.0)), float(Moba.MINION_KIND_SCALE.siege)),
		"wave 3 at 3:20: each kind its own health, +%d %% (two 90 s upgrades), the siege minion a little bigger" % int(Moba.MINION_UP * 200.0))
	var mel: Dictionary = w.filter(func(u): return str(u.mk) == "melee")[0]
	var cas: Dictionary = w.filter(func(u): return str(u.mk) == "caster")[0]
	check(float(sg[0].max_hp) > float(mel.max_hp) and float(mel.max_hp) > float(cas.max_hp) * 0.7, "siege > melee > casters (%d / %d / %d)" % [int(sg[0].max_hp), int(mel.max_hp), int(cas.max_hp)])
	# 60 % to heroes
	var b1: Dictionary = s2.by_id["b1"]
	var rm: Dictionary = _add_minion(s2, 1, "melee", b1.pos + Vector2(1, 0), false)
	check(is_equal_approx(float(s2.moba.mod_damage(rm, b1, 100.0)), 100.0 * Moba.MINION_VS_HERO), "a minion's blow on a hero: %d %%" % int(Moba.MINION_VS_HERO * 100.0))
	# targets
	var t = _new("knight", 45)
	_quiet(t)
	var X := Vector2(-30.0, 36.0)
	var bm: Dictionary = _add_minion(t, 0, "melee", X)
	var red_m: Dictionary = _add_minion(t, 1, "melee", X + Vector2(4, 0), false)
	var tr1: Dictionary = t.by_id["r1"]
	var tb1: Dictionary = t.by_id["b1"]
	_tough(tr1)
	_tough(tb1)
	tr1.pos = X + Vector2(0, 2)
	_run(t, 0.5)
	check(str(bm.get("mt", "")) == str(red_m.id), "a red minion and a nearer red hero: the minion goes for the minion")
	tb1.pos = X + Vector2(0, -5)
	t._damage(tr1, tb1, 1.0)
	_run(t, 0.3)
	check(str(bm.get("mt", "")) == "r1", "the red hero hurts a blue hero near: it turns on him (call for help)")
	tr1.pos = Sim.spawn(1)
	tb1.pos = Sim.spawn(0)
	t.units.erase(red_m)
	t.by_id.erase(red_m.id)
	bm.mt = ""
	bm.mt_pri = 9
	var hid_m: Dictionary = _add_minion(t, 1, "caster", Vector2.ZERO, false)
	var bp := Vector2(-14.0, 11.0)                        # one of blue's brush patches (0.31.165: the Rift's)
	bm.pos = bp + Vector2(0, 4.5)
	hid_m.pos = bp
	_run(t, 0.5)
	check(str(bm.get("mt", "")) != str(hid_m.id), "a red minion hidden in a brush patch: the blue minion beside it doesn't see it to hit")
	# gold by kind
	check(is_equal_approx(t.moba.minion_gold(bm), 21.0) and is_equal_approx(t.moba.minion_gold(hid_m), 14.0), "a last hit: melee 21 gold, caster 14 (League's)")

# ---------------------------------------------------------------- 3. the towers
func _towers() -> void:
	var t = _new("knight", 46)
	_quiet(t)
	var tw: Dictionary = t.moba.towers.filter(func(o): return int(o.team) == 1 and int(o.lane) == 0 and int(o.tier) == 1)[0]
	tw.dead = false
	var twp: Vector2 = tw.p
	var mel: Dictionary = _add_minion(t, 0, "melee", twp + Vector2(0, 3), false)
	var sie: Dictionary = _add_minion(t, 0, "siege", twp + Vector2(0, 8), false)
	var cas: Dictionary = _add_minion(t, 0, "caster", twp + Vector2(0, 2), false)
	var shots := []
	for i in int((Moba.TOWER_EVERY + 0.2) / Sim.TICK):
		t.step()
		for e in t.drain_events():
			if e.k == "tshot":
				shots.append(str(e.id))
		if not shots.is_empty():
			break
	_run(t, Moba.TOWER_FLIGHT + 0.1)                      # (the shot lands; the next is TOWER_EVERY off)
	check(not shots.is_empty() and shots[0] == str(sie.id), "a caster, a melee and a siege minion in reach: the tower shoots the siege one first")
	check(absf(float(sie.hp) - float(sie.max_hp) * (1.0 - float(Moba.TOWER_PCT.siege))) < 1.0, "...%d %% of its health a shot" % int(Moba.TOWER_PCT.siege * 100.0))
	t.units.erase(sie)
	t.by_id.erase(sie.id)
	tw.target = ""
	shots = []
	for e in _run(t, Moba.TOWER_EVERY + 0.1):
		if e.k == "tshot":
			shots.append(str(e.id))
	check(not shots.is_empty() and shots[0] == str(mel.id), "then the melee one (before the nearer caster)")
	var sup: Dictionary = _add_minion(t, 0, "super", twp + Vector2(2, 2), false)
	sup.hp = sup.max_hp
	tw.target = ""
	for e in _run(t, Moba.TOWER_EVERY * 2.0 + 0.4):
		pass
	var lost := 1.0 - float(sup.hp) / float(sup.max_hp)
	check(lost > 0.0 and lost < 0.11, "a super minion: %d %% a shot (%.0f %% lost)" % [int(Moba.TOWER_PCT.super * 100.0), lost * 100.0])
	# Warming Up cools off
	for u in t.units.duplicate():
		if bool(u.get("minion", false)):
			t.units.erase(u)
			t.by_id.erase(u.id)
	var bh: Dictionary = t.by_id["b1"]
	_tough(bh)
	bh.pos = twp + Vector2(3, 3)
	tw.target = ""
	var ramps := []
	for e in _run(t, Moba.TOWER_EVERY * 2.0 + 0.2):
		if e.k == "tshot":
			ramps.append(int(e.ramp))
	bh.pos = Sim.spawn(0)
	_run(t, Moba.TOWER_RAMP_COOL + 0.5)
	bh.pos = twp + Vector2(3, 3)
	var after := []
	for e in _run(t, Moba.TOWER_EVERY + 0.2):
		if e.k == "tshot":
			after.append(int(e.ramp))
	check(ramps.size() >= 2 and int(ramps[1]) >= 1 and not after.is_empty() and int(after[0]) == 0,
		"Warming Up: the shots on a hero ramp (%s), and cool off %.0f s after the last (%s)" % [str(ramps), Moba.TOWER_RAMP_COOL, str(after)])
	# plates
	bh.pos = Sim.spawn(0)
	var you: Dictionary = t.by_id["you"]
	you.pos = twp + Vector2(0, 5)
	_add_minion(t, 0, "melee", twp + Vector2(0, 6), false)
	var hp0 := float(tw.hp)
	var g0 := float(you.gold)
	var evs := []
	t.moba.hit_tower(you, int(tw.id), (float(tw.max_hp) / float(Moba.PLATES) + 2.0) / t.moba.tower_mult(you))
	evs = t.drain_events()
	check(int(tw.get("plates", 0)) == 1 and evs.any(func(e): return e.k == "plate") and is_equal_approx(float(you.gold) - g0, float(Moba.GOLD_PLATE)),
		"a fifth of an outer tower's health down before 7:00: a plate falls, +%d gold for you near it" % Moba.GOLD_PLATE)
	t.time = Moba.PLATES_UNTIL + 1.0
	t.moba.hit_tower(you, int(tw.id), (float(tw.max_hp) / float(Moba.PLATES) + 2.0) / t.moba.tower_mult(you))
	check(int(tw.get("plates", 0)) == 1 and float(tw.hp) < hp0, "after 7:00 no more plates")
	# a broken gate stands again
	var g = _new("knight", 47)
	_quiet(g)
	var rg: Dictionary = g.moba._gate_at(1, g.moba.wp(0, 0, Moba.LANES[0].size() - 1))
	rg.broken = true
	rg.hp = 0.0
	rg["broken_at"] = g.time
	g._update_gate_nav()
	evs = _run(g, Moba.GATE_BACK - 2.0)
	check(bool(rg.broken), "a broken gate stays down ...")
	evs = _run(g, 3.0)
	check(not bool(rg.broken) and float(rg.hp) == float(rg.max_hp) and evs.any(func(e): return e.k == "gate_rebuilt"),
		"...and stands again %d s later (League's inhibitor)" % int(Moba.GATE_BACK))

# ---------------------------------------------------------------- 4. the camps' patience
func _camps() -> void:
	var j = _new("knight", 48)
	_quiet(j)
	var camp: Dictionary = j.moba.camps.filter(func(c): return str(c.kind) == "pack" and int(c.side) == 0)[0]
	j.moba._spawn_camp(camp)
	var mobs: Array = j.moba.camp_live(camp)
	var me: Dictionary = j.by_id["you"]
	_tough(me)
	me.pos = (camp.p as Vector2) + Vector2(0, 2.5)
	var mob: Dictionary = mobs[0]
	j._damage(me, mob, float(mob.max_hp) * 0.5)
	var hurt := float(mob.hp)
	check(str(camp.target) == "you", "hit: the camp turns on you")
	me.pos = (camp.p as Vector2) + Vector2(0, Moba.LEASH + 1.0)
	_run(j, 1.0)
	check(str(camp.reset) == "" and str(camp.target) == "you" and float(mob.hp) <= hurt + 1.0 and float(camp.patience) < 1.0,
		"a step outside the leash: they don't give up at once (patience %.2f), no healing" % float(camp.patience))
	var pat := float(camp.patience)
	me.pos = (camp.p as Vector2) + Vector2(0, 2.5)
	_run(j, 1.0)
	check(float(camp.patience) > pat, "back inside: patience comes back (%.2f)" % float(camp.patience))
	me.pos = (camp.p as Vector2) + Vector2(0, Moba.LEASH + 8.0)
	var soft_at := -1.0
	for i in int(4.0 / Sim.TICK):
		j.step()
		j.drain_events()
		if str(camp.reset) == "soft":
			soft_at = j.time
			break
	check(soft_at > 0.0, "far outside: patience runs out within a few seconds -- they turn for home")
	var h0 := float(mob.hp)
	_run(j, 1.0)
	var frac := float(mob.hp) / float(mob.max_hp)
	check(float(mob.hp) > h0 and frac < 0.7, "...healing a little a second, not all at once (%d %% after 1 s)" % int(frac * 100.0))
	me.pos = (camp.p as Vector2) + Vector2(0, 2.0)
	j._damage(me, mob, 1.0)
	check(str(camp.reset) == "" and str(camp.target) == "you", "a blow from inside the leash while they walk home: they fight again")
	me.pos = (camp.p as Vector2) + Vector2(0, Moba.LEASH + 8.0)
	var hard := false
	for i in int((4.0 + Moba.SOFT_RESET) / Sim.TICK):
		j.step()
		for e in j.drain_events():
			hard = hard or (e.k == "camp_reset" and bool(e.get("hard", false)))
		if hard:
			break
	check(hard and str(camp.reset) == "hard", "%.0f s of that and the hard reset" % Moba.SOFT_RESET)
	check(float(j.moba.mod_damage(me, mob, 100.0)) == 0.0, "...when nothing hurts them")
	_run(j, 1.0 / Moba.HARD_HEAL + 2.0)
	check(str(camp.reset) == "" and mobs.all(func(u): return float(u.hp) >= float(u.max_hp) - 0.5), "...till they're home and whole")

# ---------------------------------------------------------------- 5. the Bone Lord marches
func _lord() -> void:
	var j = _new("knight", 49)
	_quiet(j)
	var lc: Dictionary = j.moba.camps.filter(func(c): return str(c.kind) == "lord")[0]
	j.moba._spawn_camp(lc)
	var lord: Dictionary = j.moba.camp_live(lc)[0]
	var me: Dictionary = j.by_id["you"]
	me.pos = Moba.BOSS_P + Vector2(0, 3)
	j._damage(me, lord, 1.0e7)
	var evs: Array = j.drain_events()
	var lu: Array = j.units.filter(func(u): return bool(u.get("lordling", false)))
	check(evs.any(func(e): return e.k == "lord_march" and int(e.team) == 0) and lu.size() == 1 and int(lu[0].team) == 0 and int(lu[0].lane) == 1
		and j.alive(lu[0]) and bool(lu[0].minion), "blue slays the Bone Lord: he rises for blue, a minion of the middle lane")
	if lu.is_empty():
		return
	var L: Dictionary = lu[0]
	check((L.pos as Vector2).distance_to(j.moba.wp(0, 1, 0)) < 5.0 and float(L.max_hp) > 1000.0, "...out of blue's castle (%d health)" % int(L.max_hp))
	check(is_equal_approx(j.moba.tower_mult(L), Moba.LORD_SIEGE) and is_equal_approx(j.moba._tower_pct(L), float(Moba.TOWER_PCT.lord)),
		"towers take x%.0f from him, and a tower's shot takes %d %% of him" % [Moba.LORD_SIEGE, int(Moba.TOWER_PCT.lord * 100.0)])
	var p0: Vector2 = L.pos
	_run(j, 8.0)
	check((L.pos as Vector2).distance_to(p0) > 4.0 and (L.pos as Vector2).distance_to(j.moba.wp(0, 1, Moba.LANES[1].size() - 1)) < p0.distance_to(j.moba.wp(0, 1, Moba.LANES[1].size() - 1)),
		"he marches down the lane toward red")
	var r1: Dictionary = j.by_id["r1"]
	r1.pos = (L.pos as Vector2) + Vector2(1, 0)
	var g0 := float(r1.gold)
	j._damage(r1, L, 1.0e7)
	check(not j.alive(L) and is_equal_approx(float(r1.gold) - g0, 150.0), "red finishes him: +150 gold")
