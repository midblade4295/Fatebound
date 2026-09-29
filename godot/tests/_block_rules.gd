extends SceneTree
const Sim = preload("res://scripts/siege/siege_sim.gd")
func _init() -> void:
	var s = Sim.new()
	s.setup(4, 3)
	for u in s.units: u.bot = false; u.move = Vector2.ZERO; u.pos = Vector2(0, -20) if u.team == 1 else Vector2(0, 20)
	var k: Dictionary = s.by_id["you"]
	s._set_class(k, "knight", false)
	k.pos = Vector2(0, 0); k.face = Sim.angle_of(Vector2(0, -1))      # facing -z
	var ally: Dictionary = s.units.filter(func(x): return x.team == 0 and x.id != "you")[0]
	ally.pos = Vector2(0, 1.5)                                          # behind the knight
	var foe: Dictionary = s.units.filter(func(x): return x.team == 1)[0]
	s._set_class(foe, "barbarian", false)
	foe.pos = Vector2(0, -1.6)                                          # in front
	var h0: float = k.hp
	var a0: float = ally.hp
	s.act("you", "ability")
	s._blockers = s.units.filter(func(x): return s.blocking(x))
	s._damage(foe, k, 30.0)
	print("front hit on blocking knight: hp %.0f -> %.0f" % [h0, k.hp])
	s._damage(foe, ally, 30.0)
	print("hit on ally behind the shield: hp %.0f -> %.0f" % [a0, ally.hp])
	foe.pos = Vector2(0, 2.8)                                           # now behind both
	s._damage(foe, k, 10.0)
	print("hit on the knight from behind: hp %.0f -> %.0f" % [h0, k.hp])
	# Projectile into the shield.
	foe.pos = Vector2(0, -8)
	s.projectiles.append({"id":99, "team":1, "owner":foe.id, "pos":Vector2(0, -3), "vel":Vector2(0, 18), "life":2.0, "dmg":20.0, "aoe":0.0, "gate_mult":1.0})
	for i in 8:
		s.act("you", "ability"); s.step(Sim.TICK)
	print("projectile still flying: %s, knight hp %.0f, ally hp %.0f" % [s.projectiles.any(func(p): return p.id == 99), k.hp, ally.hp])
	# Whirlwind.
	var bz: Dictionary = s.units.filter(func(x): return x.team == 0 and x.id != "you")[1]
	s._set_class(bz, "barbarian", true)
	bz.pos = Vector2(10, 0); bz.cd_ability = 0.0
	var f1: Dictionary = s.units.filter(func(x): return x.team == 1)[1]
	f1.pos = Vector2(11.5, 0); f1.hp = 500; f1.max_hp = 500
	foe.pos = Vector2(8.6, 0.5); foe.hp = 500; foe.max_hp = 500
	print("ability_of berserker: ", s.ability_of(bz), " act -> ", s.act(bz.id, "ability"))
	var t0: float = s.time
	var start_pos: Vector2 = bz.pos
	bz.move = Vector2(0, 1)
	var hits := 0
	while s.whirling(bz):
		s.step(Sim.TICK)
		for e in s.drain_events():
			if e.k == "hit" and e.get("by", "") == bz.id: hits += 1
		foe.pos = bz.pos + Vector2(-1.2, 0); f1.pos = bz.pos + Vector2(1.4, 0)
	print("whirl lasted %.2f s, hits %d, moved %.1f m, cd %.1f" % [s.time - t0, hits, bz.pos.distance_to(start_pos), bz.cd_ability])
	quit(0)
