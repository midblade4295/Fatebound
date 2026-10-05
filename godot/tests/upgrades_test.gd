extends SceneTree
# 0.31.32: the Assassin's Vanish, the Sniper's Piercing Shot, the Archmage's Meteor.
const Sim = preload("res://scripts/siege/siege_sim.gd")
var fails := []
func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok: fails.append(what)
func run(s, secs: float) -> void:
	for i in int(secs / Sim.TICK): s.step(); s.drain_events()
func fresh():
	var s = Sim.new()
	s.setup(8, 9)
	for u in s.units: u.bot = false; u.move = Vector2.ZERO; u.pos = Sim.spawn(u.team)
	return s
func _init():
	# --- Vanish
	var s = fresh()
	var a: Dictionary = s.units.filter(func(x): return x.team == 0 and x.id != "you")[0]
	s._set_class(a, "rogue", true)
	var foe: Dictionary = s.units.filter(func(x): return x.team == 1)[0]
	s._set_class(foe, "knight", false)
	a.pos = Vector2(0, 20); foe.pos = Vector2(0, 26)
	check(s.ability_of(a) == "vanish", "the Assassin's ability is Vanish")
	check(s.act(a.id, "ability") and s.vanished(a), "he vanishes")
	check(s.nearest_enemy(foe, 10.0).get("id", "") != a.id, "the enemy can't pick him out at 6 m")
	a.pos = Vector2(0, 25.0)
	var hp0: float = foe.hp
	s._damage(a, foe, 20.0)
	check(absf((hp0 - foe.hp) - 40.0) < 0.5 and not s.vanished(a), "his first strike from it does double (%.0f) and reveals him" % (hp0 - foe.hp))
	# --- Piercing Shot
	s = fresh()
	var sn: Dictionary = s.units.filter(func(x): return x.team == 0 and x.id != "you")[0]
	s._set_class(sn, "ranger", true)
	# a row clear of trees and rocks (they stop arrows) for the shot
	var row := 20.0
	for z in range(4, 40):
		var clear := not s._blocked_line(Vector2(-20, z), Vector2(4, z), 0)
		for ob in s.obstacles:
			if (ob.p as Vector2).distance_to(Sim.seg_closest(ob.p, Vector2(-20, z), Vector2(4, z))) < float(ob.r) + 0.4:
				clear = false
		if clear and Sim.water_depth(Vector2(-8, z)) <= 0.0:
			row = float(z)
			break
	sn.pos = Vector2(-20, row); sn.face = Sim.angle_of(Vector2(1, 0))
	var line: Array = s.units.filter(func(x): return x.team == 1).slice(0, 3)
	for k in 3:
		s._set_class(line[k], "knight", false)
		line[k].pos = Vector2(-12 + k * 6, row + (k % 2) * 0.2)
	var hps: Array = line.map(func(x): return x.hp)
	check(s.ability_of(sn) == "pierce" and s.act(sn.id, "ability"), "the Sniper draws a Piercing Shot")
	run(s, 2.0)
	var hits := 0
	for k in 3:
		if line[k].hp < hps[k] or not s.alive(line[k]): hits += 1
	check(hits == 3, "it went through all three in its path (%d)" % hits)
	# --- Meteor
	s = fresh()
	var am: Dictionary = s.units.filter(func(x): return x.team == 0 and x.id != "you")[0]
	s._set_class(am, "mage", true)
	am.pos = Vector2(0, 20)
	var grp: Array = s.units.filter(func(x): return x.team == 1).slice(0, 3)
	for k in 3:
		s._set_class(grp[k], "knight", false)
		grp[k].pos = Vector2(-1 + k, 29)
	am.face = Sim.angle_of(Vector2(0, 1))
	var h0: Array = grp.map(func(x): return x.hp)
	check(s.ability_of(am) == "meteor" and s.act(am.id, "ability"), "the Archmage calls a Meteor")
	run(s, 0.75)
	check(s.meteors.size() == 1 and grp[0].hp == h0[0], "a warning first: nothing hit yet")
	run(s, 1.2)
	var hurt := 0
	for k in 3:
		if grp[k].hp < h0[k] or not s.alive(grp[k]): hurt += 1
	check(hurt == 3, "the strike hit all three round the target (%d)" % hurt)
	var after: float = grp[1].hp
	run(s, 1.5)
	check(not s.alive(grp[1]) or grp[1].hp < after, "the ground burns")
	print("UPGRADES_PASS" if fails.is_empty() else "UPGRADES_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
