extends SceneTree
# The Crusader (0.30.5): the Knight's upgrade. Its ability throws a hammer that passes through enemies, comes back
# to the thrower and hits each enemy going out and coming back; no swinging while it's out; not from a tower deck.
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Land = preload("res://scripts/siege/siege_land.gd")
var fails := []

func check(ok: bool, what: String) -> void:
	if not ok:
		fails.append(what)
		print("FAIL ", what)
	else:
		print("ok   ", what)

func _init() -> void:
	var s = Sim.new()
	s.setup(6, 5)
	for u in s.units:
		u.bot = false
		u.move = Vector2.ZERO
		u.pos = Sim.spawn(u.team) + Vector2(randf_range(-6, 6), 0)
	var mine: Array = s.units.filter(func(u): return u.team == 0)
	var theirs: Array = s.units.filter(func(u): return u.team == 1)
	var c: Dictionary = mine[0]
	s._set_class(c, "knight", true)
	var k: Dictionary = mine[1]
	s._set_class(k, "knight", false)
	check(s.ability_of(c) == "hammer" and s.ability_of(k) == "block", "the Crusader throws a hammer; the Knight still blocks")
	check(str(Sim.UPGRADE_NAME["knight"]) == "Crusader", "the Knight's upgrade is called the Crusader")
	var base := Vector2(-6.0, 22.0)
	c.pos = base
	c.face = s.angle_of(Vector2(1, 0))
	var e1: Dictionary = theirs[0]
	var e2: Dictionary = theirs[1]
	for e in [e1, e2]:
		s._set_class(e, "barbarian", false)
		e.max_hp = 500.0
		e.hp = 500.0
	e1.pos = base + Vector2(3.5, 0.0)
	e2.pos = base + Vector2(7.0, 0.0)
	check(s.act(c.id, "ability"), "the Crusader throws")
	check(not s._start_attack(c, "attack"), "no swinging while the hammer is out")
	var gone := false
	for i in 120:
		s.step()
		e1.pos = base + Vector2(3.5, 0.0)
		e2.pos = base + Vector2(7.0, 0.0)
		if s.projectiles.filter(func(p): return str(p.kind) == "hammer").is_empty():
			gone = true
			break
	var dmg := float(s.stat(c, "dmg"))
	check(gone and int(c.get("hammer_out", -1)) < 0, "the hammer comes back to the thrower")
	check(e1.hp <= 500.0 - 1.5 * dmg and e2.hp <= 500.0 - 1.5 * dmg,
		"both lined-up enemies are hit going out and coming back (lost %.0f and %.0f of a %.0f-damage swing x2)" % [500.0 - e1.hp, 500.0 - e2.hp, dmg])
	check(not s.act(c.id, "ability"), "then it's on cooldown")
	c.state = "idle"
	check(s._start_attack(c, "attack"), "and the Crusader can swing again")
	# returns to where the thrower is now
	c.cd_ability = 0.0
	c.state = "idle"
	for i in 10: s.step()
	c.pos = base
	c.face = s.angle_of(Vector2(1, 0))
	e1.pos = Sim.spawn(1)
	e2.pos = Sim.spawn(1)
	s.act(c.id, "ability")
	var back := false
	for i in 150:
		s.step()
		c.pos = base + Vector2(0.0, -4.0)
		if int(c.get("hammer_out", -1)) < 0:
			back = true
			break
	check(back, "it finds the thrower after they've moved")
	# not from a tower deck
	var op: Dictionary = s.outposts[0]
	op.owner = 0
	op.prog = 1.0
	c.cd_ability = 0.0
	c.state = "idle"
	c.pos = (op.p as Vector2) + Vector2(Land.OUTPOST_TOWER_R + 0.8, 0)
	s.act(c.id, "interact")
	check(int(c.tower) >= 0 and not s.act(c.id, "ability"), "no hammer from a tower's deck")
	# bots throw at a line of enemies
	var s2 = Sim.new()
	s2.setup(6, 7)
	for u in s2.units:
		u.bot = false
		u.pos = Sim.spawn(u.team) + Vector2(randf_range(-6, 6), 0)
	var b: Dictionary = s2.units.filter(func(u): return u.team == 0)[0]
	s2._set_class(b, "knight", true)
	b.bot = true
	b.pos = base
	var t2: Array = s2.units.filter(func(u): return u.team == 1)
	t2[0].pos = base + Vector2(4.0, 0.0)
	t2[1].pos = base + Vector2(6.5, 0.2)
	var threw := false
	for i in 60:
		s2.step()
		if int(b.get("hammer_out", -1)) >= 0:
			threw = true
			break
	check(threw, "a Crusader bot throws at two enemies in a line")
	print("HAMMER_PASS" if fails.is_empty() else "HAMMER_FAIL %d" % fails.size())
	quit()
