extends SceneTree
# 0.31.27: bots waiting at their rally point (or anywhere) answer an archer shooting them from range: the one hit and
# its friends nearby go for him.
const Sim = preload("res://scripts/siege/siege_sim.gd")
func _init():
	var s = Sim.new()
	s.setup(8, 4)
	var raiders: Array = s.units.filter(func(x): return x.team == 1 and x.bot).slice(0, 4)
	var spot: Vector2 = s._rally_spot(raiders[0])
	for u in s.units:
		u.move = Vector2.ZERO
		if not raiders.has(u):
			u.bot = false
			u.pos = Sim.spawn(u.team)
	for k in raiders.size():
		var r: Dictionary = raiders[k]
		r.role = "raid"
		s._set_class(r, ["knight", "rogue", "barbarian", "mage"][k], false)
		r.pos = spot + Vector2(k * 1.2 - 1.8, 0.0)
	var me: Dictionary = s.by_id["you"]
	s._set_class(me, "ranger", false)
	me.pos = spot + Vector2(0.0, 11.0) * (1.0 if spot.y < 0.0 else -1.0)
	var d0: Array = raiders.map(func(r): return (r.pos as Vector2).distance_to(me.pos))
	for i in int(4.0 / Sim.TICK):
		if i % 12 == 0:
			s._damage(me, raiders[0], 6.0)            # an arrow from 11 m lands (the aim itself isn't what's tested)
		s.step()
		s.drain_events()
	var closer := 0
	for k in raiders.size():
		if not s.alive(raiders[k]) or (raiders[k].pos as Vector2).distance_to(me.pos) < float(d0[k]) - 2.0 or me.hp < me.max_hp:
			closer += 1
	var ok: bool = raiders[0].has("hurt_at") and closer >= 3
	print(("ANSWER_PASS %d of 4 waiting raiders came for the archer (or hit him) within 4 s" if ok else "ANSWER_FAIL only %d of 4 reacted") % closer)
	quit(0 if ok else 1)
