extends SceneTree
# 0.31.179 (Kevin: "make sure only basic attacks damage towers and that they only damage while inside the towers damage
# range"):
#  - basic attacks only: an Archer's VOLLEY, a Barbarian's SPIN, a Ranger's PIERCE, a Golem's QUAKE at an open tower
#    leave it whole; his basic shot and the Barbarian's swing hurt it;
#  - the King, though, any ability (Kevin: "Kings should still get damaged by any ability"): VOLLEY, SPIN, QUAKE,
#    BOULDER, INFERNO, the Archmage's storm, a powder keg, a fan of knives, a Duelist's lunge -- not while his towers
#    stand;
#  - from inside its range only (where it would shoot you: TOWER_RANGE to your edge): a Musketeer's ball from 12.3 m
#    does nothing -- "too far" on his screen, not on another's -- and from 9 m it lands;
#  - a player's attack doesn't turn to a tower he can't hurt from where he stands;
#  - the bots and minions walk in: a Musketeer bot sent at a tower from 12 m closes in before he shoots, and shoots
#    from inside it; a 5v5 of bots still brings towers down.
#   godot --headless --path godot -s res://tests/tower_rules_test.gd
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Moba = preload("res://scripts/siege/moba.gd")
const Hud = preload("res://scripts/siege/siege_hud.gd")
var fails := []

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

static func _fresh(hero: String, seed_v: int):
	var s = Sim.new()
	s.setup(5, seed_v)
	s.setup_moba(hero, seed_v)
	return s

static func _tower(s, team: int, tier: int, lane: int) -> Dictionary:
	for tw in s.moba.towers:
		if int(tw.team) == team and int(tw.tier) == tier and int(tw.lane) == lane:
			return tw
	return {}

static func _clear(s, me: Dictionary) -> void:
	for u in s.units:
		if u != me:
			u.pos = Vector2(-50.0, -100.0) if int(u.team) == 1 else Vector2(50.0, 100.0)
			u.move = Vector2.ZERO

# me placed `dist` m from red's outer mid tower (on the blue side), facing it; returns the tower
static func _at_tower(s, me: Dictionary, dist: float) -> Dictionary:
	var tw := _tower(s, 1, 1, 1)
	me.pos = (tw.p as Vector2) + Vector2(0, 1) * dist
	me.face = Sim.angle_of(Vector2(0, -1))
	me.move = Vector2.ZERO
	_clear(s, me)
	return tw

# you `dist` m from red's King, facing him, at level 18 (every spell and the ultimate), his towers down if `open`
static func _king_case(hero: String, seed_v: int, dist: float, open: bool) -> Dictionary:
	var s = _fresh(hero, seed_v)
	var me: Dictionary = s.by_id["you"]
	me.level = 18
	if open:
		for t2 in s.moba.towers:
			if int(t2.team) == 1 and int(t2.tier) == 4:
				t2.dead = true
	var kp: Vector2 = s.moba.king_pos(1)
	var side := 1.0 if kp.y < 0.0 else -1.0
	me.pos = kp + Vector2(0, side) * dist
	me.face = Sim.angle_of(kp - (me.pos as Vector2))
	me.move = Vector2.ZERO
	_clear(s, me)
	return {"s": s, "me": me}

static func _cast(s, me: Dictionary, what: String) -> void:
	match what:
		"spin":
			me.cd_ability = 0.0
			s._start_attack(me, "ability", false)
		"inferno", "storm":
			me.ult_cd = 0.0
			s.moba.ult(me)
		"quake":
			s.moba.kits.spell(me, "e")
		"boulder", "buckshot", "thrust":
			s.moba.kits.spell(me, "q")
		"keg":
			s.moba.kits.spell(me, "w")
		"knives":
			s.moba.kits.spell(me, "e")

static func _run(s, n: int, me: Dictionary, hold := true) -> Array:
	var evs := []
	for i in n:
		if hold:
			me.move = Vector2.ZERO
			me.hp = float(me.max_hp)
		s.step()
		evs.append_array(s.drain_events())
	return evs

func _init() -> void:
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:1")
	# ---- basic attacks only
	var s = _fresh("ranger", 61)
	var me: Dictionary = s.by_id["you"]
	var tw := _at_tower(s, me, 7.0)
	var hp0 := float(tw.hp)
	me.cd_ability = 0.0
	check(s._start_attack(me, "ability", false), "an Archer's VOLLEY loosed at the tower, 7 m")
	_run(s, 60, me)
	check(float(tw.hp) == hp0, "...it stands whole (%.0f)" % float(tw.hp))
	s._start_attack(me, "attack", false)
	_run(s, 60, me)
	check(float(tw.hp) < hp0, "his basic shot hurts it (%.0f -> %.0f)" % [hp0, float(tw.hp)])
	s = _fresh("barbarian", 62)
	me = s.by_id["you"]
	tw = _at_tower(s, me, Moba.TOWER_R + 1.0)
	hp0 = float(tw.hp)
	me.cd_ability = 0.0
	check(s._start_attack(me, "ability", false), "a Barbarian's SPIN beside it")
	_run(s, 40, me)
	check(float(tw.hp) == hp0, "...it stands whole")
	s._start_attack(me, "attack", false)
	_run(s, 40, me)
	check(float(tw.hp) < hp0, "his swing hurts it (%.0f -> %.0f)" % [hp0, float(tw.hp)])
	s = _fresh("sniper", 63)
	me = s.by_id["you"]
	tw = _at_tower(s, me, 7.0)
	hp0 = float(tw.hp)
	s._pierce_shot(me, float(s.stat(me, "dmg")))
	_run(s, 60, me)
	check(float(tw.hp) == hp0, "a Ranger's PIERCE through it: whole")
	# a golem's QUAKE beside an open tower: whole
	s = _fresh("golem", 70)
	me = s.by_id["you"]
	me.level = 18
	tw = _at_tower(s, me, Moba.TOWER_R + 1.0)
	hp0 = float(tw.hp)
	check(s.moba.kits.spell(me, "e"), "a Golem's QUAKE beside it")
	_run(s, 10, me)
	check(float(tw.hp) == hp0, "...it stands whole")
	# ---- the Kings: any ability (0.31.179, Kevin: "Kings should still get damaged by any ability")
	var k := _king_case("ranger", 71, 6.0, true)
	k.me.cd_ability = 0.0
	s = k.s
	var k0 := float(s.moba.kings[1].hp)
	s._start_attack(k.me, "ability", false)
	_run(s, 50, k.me)
	var k1 := float(s.moba.kings[1].hp)
	s._start_attack(k.me, "attack", false)
	_run(s, 50, k.me)
	var k2 := float(s.moba.kings[1].hp)
	check(k1 < k0 and k2 < k1, "the King: an Archer's VOLLEY hurts him, and a basic shot (%.0f, %.0f, %.0f)" % [k0, k1, k2])
	for c in [["barbarian", "spin", 2.2], ["golem", "quake", 2.4], ["golem", "boulder", 7.0], ["mage", "inferno", 2.5],
			["archmage", "storm", 6.0], ["musketeer", "keg", 6.0], ["assassin", "knives", 2.6], ["duelist", "thrust", 3.0]]:
		k = _king_case(str(c[0]), 72, float(c[2]), true)
		s = k.s
		k0 = float(s.moba.kings[1].hp)
		_cast(s, k.me, str(c[1]))
		_run(s, 120, k.me)
		check(float(s.moba.kings[1].hp) < k0, "...%s %s's %s (%.0f -> %.0f)" % ["an" if "aeiou".contains(str(c[0]).left(1)) else "a", str(c[0]), str(c[1]).to_upper(), k0, float(s.moba.kings[1].hp)])
	k = _king_case("golem", 73, 2.4, false)
	s = k.s
	k0 = float(s.moba.kings[1].hp)
	_cast(s, k.me, "quake")
	_run(s, 20, k.me)
	check(float(s.moba.kings[1].hp) == k0, "a QUAKE at him while his towers stand: nothing (he's guarded)")
	# ---- from inside its range only
	s = _fresh("musketeer", 65)
	me = s.by_id["you"]
	tw = _at_tower(s, me, Moba.TOWER_RANGE + Sim.UNIT_R + 0.35)
	hp0 = float(tw.hp)
	s._start_attack(me, "attack", false)
	var evs := _run(s, 70, me)
	var far := false
	for e in evs:
		far = far or (str(e.k) == "tower_far" and str(e.get("by", "")) == "you")
	check(float(tw.hp) == hp0 and far, "a Musketeer's ball from %.1f m (out of its range): nothing, and \"too far\"" % (me.pos as Vector2).distance_to(tw.p))
	var hud = Hud.new()
	hud.sim = s
	hud.player_id = "you"
	root.add_child(hud)
	hud._toast = ""
	hud.on_event({"k": "tower_far", "tw": int(tw.id), "by": "b3"})
	var other_quiet: bool = hud._toast == ""
	hud.on_event({"k": "tower_far", "tw": int(tw.id), "by": "you"})
	check(other_quiet and str(hud._toast).begins_with("Too far"), "\"Too far\" on his screen only (\"%s\")" % hud._toast)
	me.pos = (tw.p as Vector2) + Vector2(0, 1) * 9.0
	s._start_attack(me, "attack", false)
	_run(s, 70, me)
	check(float(tw.hp) < hp0, "...from 9 m it lands (%.0f -> %.0f)" % [hp0, float(tw.hp)])
	# ---- the aim
	s = _fresh("musketeer", 66)
	me = s.by_id["you"]
	tw = _at_tower(s, me, Moba.TOWER_RANGE + 0.8)
	me.face = Sim.angle_of(Vector2(1, 0))
	s._start_attack(me, "attack")
	check(Sim.dir_of(me.face).dot(Vector2(1, 0)) > 0.98, "out of its range, a player's attack doesn't turn to the tower")
	s = _fresh("musketeer", 67)
	me = s.by_id["you"]
	tw = _at_tower(s, me, 9.0)
	me.face = Sim.angle_of(Vector2(1, 0))
	s._start_attack(me, "attack")
	check(Sim.dir_of(me.face).dot(((tw.p as Vector2) - (me.pos as Vector2)).normalized()) > 0.98, "inside it, it does")
	# ---- bots walk in
	s = _fresh("musketeer", 68)
	me = s.by_id["you"]
	me.bot = true
	tw = _at_tower(s, me, 12.0)
	hp0 = float(tw.hp)
	var closest := INF
	var shot_from := []
	for i in 150:
		s.moba._hit_structure(me, tw)
		if str(me.state) == "wind" and shot_from.is_empty():
			shot_from.append((me.pos as Vector2).distance_to(tw.p))
		me.hp = float(me.max_hp)
		s.step()
		s.drain_events()
		closest = minf(closest, (me.pos as Vector2).distance_to(tw.p))
	check(not shot_from.is_empty() and float(shot_from[0]) <= Moba.TOWER_RANGE + Sim.UNIT_R and float(tw.hp) < hp0,
		"a Musketeer bot sent at it from 12 m walks in and shoots from inside its range (%s m; %.0f -> %.0f)" % [str(shot_from), hp0, float(tw.hp)])
	# a bots' 5v5: towers still fall
	s = _fresh("knight", 69)
	s.by_id["you"].bot = true
	while s.time < 600.0 and not s.ended:
		s.step()
		s.drain_events()
	var down: int = s.moba.towers_down(0) + s.moba.towers_down(1)
	check(down >= 2, "10:00 of a bots' 5v5: towers down %d" % down)
	print("TOWER_RULES_%s" % ("PASS" if fails.is_empty() else "FAIL %s" % str(fails)))
	quit(0 if fails.is_empty() else 1)
