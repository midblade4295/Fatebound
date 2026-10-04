extends SceneTree
# The bomb (0.31.19): one per workshop, picked up and thrown, the throw lights the fuse, the blast kills everyone in
# range (friends too), takes half a door's health and all of a jail door's, and the workshop makes the next one later.
const Sim = preload("res://scripts/siege/siege_sim.gd")

func _fail(m: String) -> void:
	print("BOMB_TEST_FAIL ", m)
	quit(1)

func _run(s, secs: float) -> void:
	for i in int(secs / Sim.TICK):
		s.step()
		s.drain_events()

func _init():
	var s = Sim.new()
	s.setup(4, 7)
	for u in s.units:
		u.bot = false
		u.move = Vector2.ZERO
	if not s.bombs[0].is_empty():
		_fail("a bomb before BOMB_FIRST"); return
	_run(s, Sim.BOMB_FIRST + 0.2)
	if s.bombs[0].is_empty() or s.bombs[1].is_empty() or s.bombs[0].state != "ready":
		_fail("no bomb at each workshop after BOMB_FIRST"); return
	# pick it up
	var me: Dictionary = s.units.filter(func(x): return x.team == 0)[0]
	me.pos = s.bombs[0].p + Vector2(0.5, 0.0)
	if s.context_action(me) != "bomb_pick":
		_fail("ACTION next to the bomb is %s, not bomb_pick" % s.context_action(me)); return
	s.act(me.id, "interact")
	if s.bombs[0].state != "carried" or not me.bomb_held or s.context_action(me) != "bomb_throw":
		_fail("not carried after the pick-up"); return
	# only one per team: nothing new appears while it's out
	_run(s, 2.0)
	if s.bombs[0].state != "carried":
		_fail("the carried bomb changed state"); return
	# set a scene: me near the enemy gate, an ally and two enemies where it will land, the gate in reach
	var gate: Dictionary = s.gates.filter(func(g): return g.team == 1 and str(g.get("kind", "")) != "jail")[0]
	var spot: Vector2 = gate.c + Vector2(0.0, 2.0) if gate.c.y < 0 else gate.c - Vector2(0.0, 2.0)
	me.pos = spot + Vector2(0.0, Sim.BOMB_THROW) * signf(spot.y if spot.y != 0 else 1.0)
	me.face = Sim.angle_of(spot - me.pos)
	var ally: Dictionary = s.units.filter(func(x): return x.team == 0 and x.id != me.id)[0]
	var foes: Array = s.units.filter(func(x): return x.team == 1).slice(0, 2)
	ally.pos = spot + Vector2(1.0, 0.0)
	foes[0].pos = spot + Vector2(-1.0, 0.5)
	foes[1].pos = spot + Vector2(0.0, -1.2)
	var far: Dictionary = s.units.filter(func(x): return x.team == 1)[2]
	far.pos = spot + Vector2(Sim.BOMB_R + 3.0, 0.0)
	var hp0: float = gate.hp
	s.act(me.id, "interact")
	if s.bombs[0].state != "flying" or me.bomb_held:
		_fail("not thrown"); return
	_run(s, Sim.BOMB_FLIGHT + 0.1)
	if s.bombs[0].state != "lit":
		_fail("not lit on the ground after the flight (%s)" % s.bombs[0].state); return
	var landed: Vector2 = s.bombs[0].p
	for u in [ally, foes[0], foes[1], far]:
		u.pos = landed + ((u.pos as Vector2) - spot)      # keep the scene round where it really landed
	_run(s, Sim.BOMB_FUSE)
	if not s.bombs[0].is_empty():
		_fail("didn't go off after the fuse"); return
	for u in [ally, foes[0], foes[1]]:
		if s.alive(u):
			_fail("%s (team %d) survived inside the blast" % [u.id, u.team]); return
	if not s.alive(far):
		_fail("a unit outside the blast died"); return
	if landed.distance_to(Sim.seg_closest(landed, gate.a, gate.b)) > Sim.BOMB_R:
		_fail("test setup: the bomb landed %.1f m from the gate" % landed.distance_to(Sim.seg_closest(landed, gate.a, gate.b))); return
	if absf((hp0 - gate.hp) - gate.max_hp * 0.5) > 1.0:
		_fail("the gate lost %.0f, not half of %.0f" % [hp0 - gate.hp, gate.max_hp]); return
	# the jail door: all of it
	var jail: Dictionary = s.gates.filter(func(g): return g.team == 1 and str(g.get("kind", "")) == "jail")[0]
	s.bomb_next[0] = s.time
	_run(s, 0.2)
	s.bombs[0].p = jail.c + Vector2(0.0, 1.0)
	s.bombs[0].state = "lit"
	s.bombs[0].lit_at = s.time
	_run(s, Sim.BOMB_FUSE + 0.1)
	if not jail.broken or jail.hp > 0.0:
		_fail("the jail door wasn't destroyed (hp %.0f)" % jail.hp); return
	# the next one comes BOMB_RESPAWN after
	if not s.bombs[0].is_empty():
		_fail("a new bomb straight away"); return
	_run(s, Sim.BOMB_RESPAWN + 0.2)
	if s.bombs[0].is_empty():
		_fail("no new bomb after BOMB_RESPAWN"); return
	# a carrier who dies drops it (unlit)
	var c2: Dictionary = s.units.filter(func(x): return x.team == 0 and s.alive(x))[0]
	c2.pos = s.bombs[0].p
	s.act(c2.id, "interact")
	s._kill({}, c2)
	_run(s, 0.1)
	if s.bombs[0].state != "loose" or c2.get("bomb_held", false):
		_fail("dropped bomb is %s" % s.bombs[0].state); return
	print("BOMB_TEST_PASS gate -%.0f%%, jail destroyed, 3 in the blast dead (friend and foes), 1 outside alive" % [100.0 * 0.5])
	quit(0)
