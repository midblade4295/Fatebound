extends SceneTree
# Towers (0.26.0): archers and mages of the holding team climb them and shoot from the top; melee
# can't reach them there, arrows can; losing the tower throws them off; nobody respawns at a tower;
# workers drop resources at a tower their team holds; bots climb when a fight comes near.
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
	var list: Array = s.units.filter(func(u): return u.team == team)
	var u: Dictionary = list[k]
	s._set_class(u, cls, false)
	u.max_hp = float(s.stat(u, "hp"))
	u.hp = u.max_hp
	return u

func _steps(s, n: int) -> void:
	for i in n:
		s.step()

func _init() -> void:
	# --- who can climb ---
	var s = _fresh()
	var op: Dictionary = s.outposts[0]
	op.owner = 0
	op.prog = 1.0
	var tp: Vector2 = op.p
	var r := _unit(s, 0, "ranger", 0)
	r.pos = tp + Vector2(2.6, 0)
	var k := _unit(s, 0, "knight", 1)
	k.pos = tp + Vector2(-2.6, 0)
	var m := _unit(s, 0, "mage", 2)
	m.pos = tp + Vector2(0, 2.6)
	check(s.context_action(r) == "tower_up", "a ranger at our tower is offered CLIMB (got %s)" % s.context_action(r))
	check(s.context_action(k) != "tower_up" and s.tower_to_enter(k).is_empty(), "a knight can't climb")
	check(s.act(r.id, "interact") and int(r.tower) == int(op.id), "the ranger climbs")
	check(s.act(m.id, "interact") and int(m.tower) == int(op.id), "the mage climbs")
	_steps(s, 3)
	check(r.pos.distance_to(tp) < 1.0 and m.pos.distance_to(tp) < 1.0 and r.pos.distance_to(m.pos) > 0.5, "both stand on the top, apart")
	check(s.context_action(r) == "tower_down", "on top the button says CLIMB DOWN")
	r.move = Vector2(1, 0)
	_steps(s, 10)
	check(r.pos.distance_to(tp) < 1.0, "the stick doesn't walk it off the top")
	r.move = Vector2.ZERO
	check(not s._dodge(r), "no dodging off the top")
	# an enemy tower can't be climbed
	var er := _unit(s, 1, "ranger", 0)
	er.pos = tp + Vector2(2.6, 0.5)
	check(s.tower_to_enter(er).is_empty(), "the enemy can't climb our tower")
	# --- melee can't reach the top; arrows can ---
	var ek := _unit(s, 1, "knight", 1)
	ek.pos = tp + Vector2(0.0, -2.3)
	ek.face = s.angle_of(tp - ek.pos)
	var hp0: float = r.hp
	var hm0: float = m.hp
	s._melee(ek, 2.5, -2.0, 50.0)
	check(r.hp == hp0 and m.hp == hm0, "a knight's swing doesn't reach the top")
	check(s.nearest_enemy(ek, 6.0).is_empty() or int(s.nearest_enemy(ek, 6.0).tower) < 0, "melee units don't target the top")
	er.pos = tp + Vector2(8.0, 0.0)
	er.face = s.angle_of(r.pos - er.pos)
	s._shoot(er, er.face, 15.0, 0.0, 22.0, 11.0)
	_steps(s, 20)
	check(r.hp < hp0 or m.hp < hm0, "an enemy arrow hits someone on the top (towers don't stop arrows)")
	# --- shooting from the top: longer reach, flies over walls ---
	var far := _unit(s, 1, "barbarian", 2)
	far.pos = tp + Vector2(0.0, 13.2)
	far.hp = 500.0
	far.max_hp = 500.0
	ek.pos = Sim.spawn(1)
	er.pos = Sim.spawn(1) + Vector2(2, 0)
	r.state = "idle"
	r.stun = 0.0
	var hb: float = far.hp
	check(s._start_attack(r, "attack"), "the ranger shoots from the top")
	_steps(s, 40)
	check(far.hp < hb, "it hits a target 13 m away (beyond a ranger's 11 m on the ground)")
	m.state = "idle"
	check(not s._start_attack(m, "ability"), "no mage nova up there")
	# --- losing the tower throws them off ---
	for u in s.units:
		if u.team == 0 and int(u.tower) < 0:
			u.pos = Sim.spawn(0)
	var caps := 0
	for u in s.units:
		if u.team == 1 and caps < 3:
			s._set_class(u, "knight", false)
			u.hp = 999.0
			u.max_hp = 999.0
			u.pos = tp + Vector2(cos(caps * 2.1), sin(caps * 2.1)) * 3.2
			caps += 1
	var t0: float = s.time
	while int(op.owner) == 0 and s.time - t0 < 30.0:
		s.step()
	check(int(op.owner) != 0, "the enemy captures the tower from the ground while our archers are on top")
	check(int(r.tower) < 0 and int(m.tower) < 0 and (op.occ as Array).is_empty(), "everyone on it is thrown off")
	check(r.pos.distance_to(tp) >= Land.OUTPOST_TOWER_R, "thrown down beside it, not inside it")
	# --- no respawn at towers ---
	s = _fresh()
	for o in s.outposts:
		o.owner = 0
		o.prog = 1.0
	var raider: Dictionary = s.units.filter(func(u): return u.team == 0)[3]
	raider.role = "raid"
	raider.bot = true
	s._kill(raider, raider)
	raider.respawn_at = s.time
	_steps(s, 2)
	check(raider.pos.distance_to(Sim.spawn(0)) < 10.0, "a raider respawns at the castle even with every tower held (%.1f m from spawn)" % raider.pos.distance_to(Sim.spawn(0)))
	# --- workers drop resources at a tower we hold ---
	var w := _unit(s, 0, "worker", 4)
	var top: Dictionary = s.outposts[0]
	w.pos = (top.p as Vector2) + Vector2(2.6, 0)
	w.load = {"kind":"wood", "n":5}
	var wood0: int = int(s.stock[0].wood)
	_steps(s, 2)
	check(int(s.stock[0].wood) >= wood0 + 5 and int(w.load.n) == 0, "a worker's load is banked at the tower")
	# --- bots climb when a fight comes near ---
	s = _fresh()
	var bop: Dictionary = s.outposts[0]
	bop.owner = 0
	bop.prog = 1.0
	var br := _unit(s, 0, "ranger", 0)
	br.bot = true
	br.role = "defend"
	br.pos = (bop.p as Vector2) + Vector2(6.0, 0.0)
	var foe := _unit(s, 1, "knight", 0)
	foe.pos = (bop.p as Vector2) + Vector2(0.0, 12.0)
	var climbed := false
	for i in 300:
		s.step()
		if int(br.tower) >= 0:
			climbed = true
			break
	check(climbed, "a ranger bot climbs our tower when an enemy comes near")
	if fails.is_empty():
		print("TOWER_PASS")
	else:
		print("TOWER_FAIL %d" % fails.size())
	quit()
