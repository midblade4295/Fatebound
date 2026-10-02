extends SceneTree
# Towers (0.30.2): any class of the holding team climbs (only archers/mages attack from the top); melee can't reach
# the top, arrows can; capture from the ground throws them off; no respawns at towers; workers drop resources there.
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
	var k := _unit(s, 0, "knight", 1)
	k.pos = tp + Vector2(-near, 0)
	check(s.context_action(r) == "tower_up" and s.context_action(k) == "tower_up", "CLIMB offered to any class at a tower we hold")
	var er := _unit(s, 1, "ranger", 0)
	er.pos = tp + Vector2(0, near)
	check(s.tower_to_enter(er).is_empty(), "the enemy can't climb our tower")
	check(s.act(r.id, "interact") and s.act(k.id, "interact") and int(r.tower) >= 0 and int(k.tower) >= 0, "the ranger and the knight climb")
	for i in 3: s.step()
	check(r.pos.distance_to(tp) < 1.0 and k.pos.distance_to(tp) < 1.0, "both stand on the top")
	check(not s._start_attack(k, "attack") and not s._block(k), "the knight can't fight from up there (no bow)")
	er.pos = tp + Vector2(0, 8.0)
	var ek := _unit(s, 1, "knight", 1)
	ek.pos = tp + Vector2(0, -(Land.OUTPOST_TOWER_R + 0.5))
	ek.face = s.angle_of(tp - ek.pos)
	var h0: float = r.hp + k.hp
	s._melee(ek, 2.5, -2.0, 50.0)
	check(r.hp + k.hp == h0, "a sword can't reach the top")
	var far := _unit(s, 1, "barbarian", 2)
	far.pos = tp + Vector2(13.0, 0.0)
	far.hp = 500.0
	far.max_hp = 500.0
	ek.pos = Sim.spawn(1)
	er.pos = Sim.spawn(1)
	r.state = "idle"
	check(s._start_attack(r, "attack"), "the ranger shoots from the top")
	for i in 40: s.step()
	check(far.hp < 500.0, "and hits 13 m out (beyond 11 m on the ground)")
	er.pos = tp + Vector2(8.0, 0.0)
	er.face = s.angle_of(r.pos - er.pos)
	var hr: float = r.hp + k.hp
	s._shoot(er, er.face, 15.0, 0.0, 33.0, 11.0)
	for i in 20: s.step()
	check(r.hp + k.hp < hr, "enemy arrows still hit people on the top")
	# losing the tower throws them off
	far.pos = Sim.spawn(1)
	er.pos = Sim.spawn(1)
	var caps := 0
	for u in s.units:
		if u.team == 1 and caps < 3:
			s._set_class(u, "knight", false)
			u.hp = 999.0
			u.max_hp = 999.0
			u.pos = tp + Vector2(cos(caps * 2.1), sin(caps * 2.1)) * (Land.OUTPOST_TOWER_R + 1.0)
			caps += 1
	for u in s.units:
		if u.team == 0 and int(u.tower) < 0:
			u.pos = Sim.spawn(0)
	var t0: float = s.time
	while int(op.owner) == 0 and s.time - t0 < 40.0:
		s.step()
	check(int(op.owner) != 0 and int(r.tower) < 0 and int(k.tower) < 0, "capturing it from the ground throws everyone off")
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
	var w := _unit(s, 0, "worker", 4)
	var top: Dictionary = s.outposts[0]
	w.pos = (top.p as Vector2) + Vector2(Land.OUTPOST_TOWER_R + 0.6, 0)
	w.load = {"kind":"wood", "n":5}
	var wood0: int = int(s.stock[0].wood)
	for i in 2: s.step()
	check(int(s.stock[0].wood) >= wood0 + 5 and int(w.load.n) == 0, "a worker's load is banked at the tower")
	var high := 0
	for o in s.outposts:
		if Sim.height_at(o.p) > 1.0:
			high += 1
	check(high > 0 and high < s.outposts.size(), "%d of %d towers on raised ground" % [high, s.outposts.size()])
	print("TOWER_PASS" if fails.is_empty() else "TOWER_FAIL %d" % fails.size())
	quit()
