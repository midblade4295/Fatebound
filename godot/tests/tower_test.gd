extends SceneTree
# Towers (0.30.1): capture points only -- nobody climbs them (Kevin), nobody respawns at them; workers drop
# resources at a tower their team holds; capturing counts the units on the ground round it.
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Land = preload("res://scripts/siege/siege_land.gd")
var fails := []

func check(ok: bool, what: String) -> void:
	if not ok:
		fails.append(what)
		print("FAIL ", what)
	else:
		print("ok   ", what)

func _fresh() -> Object:
	var s = Sim.new()
	s.setup(6, 5)
	for u in s.units:
		u.bot = false
		u.move = Vector2.ZERO
		u.pos = Sim.spawn(u.team) + Vector2(randf_range(-6, 6), 0)
	return s

func _unit(s, team: int, cls: String, k := 0) -> Dictionary:
	var u: Dictionary = s.units.filter(func(x): return x.team == team)[k]
	s._set_class(u, cls, false)
	u.max_hp = float(s.stat(u, "hp"))
	u.hp = u.max_hp
	return u

func _init() -> void:
	var s = _fresh()
	var op: Dictionary = s.outposts[0]
	op.owner = 0
	op.prog = 1.0
	var tp: Vector2 = op.p
	var near := Land.OUTPOST_TOWER_R + 0.8
	var r := _unit(s, 0, "ranger", 0)
	r.pos = tp + Vector2(near, 0)
	var m := _unit(s, 0, "mage", 1)
	m.pos = tp + Vector2(-near, 0)
	check(s.context_action(r) != "tower_up" and s.context_action(m) != "tower_up", "no CLIMB button at a tower")
	s.act(r.id, "interact")
	s.act(m.id, "interact")
	for i in 3: s.step()
	check(int(r.tower) < 0 and int(m.tower) < 0, "nobody gets onto a tower")
	check(r.pos.distance_to(tp) >= Land.OUTPOST_TOWER_R, "the tower is solid (%.2f m from its centre)" % r.pos.distance_to(tp))
	# capture from the ground
	var caps := 0
	for u in s.units:
		if u.team == 1 and caps < 3:
			s._set_class(u, "knight", false)
			u.hp = 999.0
			u.max_hp = 999.0
			u.pos = tp + Vector2(cos(caps * 2.1), sin(caps * 2.1)) * (Land.OUTPOST_TOWER_R + 1.0)
			caps += 1
	r.pos = Sim.spawn(0)
	m.pos = Sim.spawn(0)
	var t0: float = s.time
	while int(op.owner) != 1 and s.time - t0 < 40.0:
		s.step()
	check(int(op.owner) == 1, "the enemy captures it by standing round it")
	# no respawn at towers
	s = _fresh()
	for o in s.outposts:
		o.owner = 0
		o.prog = 1.0
	var raider: Dictionary = s.units.filter(func(u): return u.team == 0)[3]
	raider.role = "raid"
	raider.bot = true
	s._kill(raider, raider)
	raider.respawn_at = s.time
	for i in 2: s.step()
	check(raider.pos.distance_to(Sim.spawn(0)) < 10.0, "respawn at the castle even with every tower held")
	# workers drop resources at a tower we hold
	var w := _unit(s, 0, "worker", 4)
	var top: Dictionary = s.outposts[0]
	w.pos = (top.p as Vector2) + Vector2(Land.OUTPOST_TOWER_R + 0.6, 0)
	w.load = {"kind":"wood", "n":5}
	var wood0: int = int(s.stock[0].wood)
	for i in 2: s.step()
	check(int(s.stock[0].wood) >= wood0 + 5 and int(w.load.n) == 0, "a worker's load is banked at the tower")
	# not every tower on a plateau
	var high := 0
	for o in s.outposts:
		if Sim.height_at(o.p) > Land.LEDGE_H - 0.1:
			high += 1
	check(high > 0 and high < s.outposts.size(), "%d of %d towers on raised ground" % [high, s.outposts.size()])
	print("TOWER_PASS" if fails.is_empty() else "TOWER_FAIL %d" % fails.size())
	quit()
