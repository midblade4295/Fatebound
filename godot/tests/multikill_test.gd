extends SceneTree
# 0.31.29: kills by one player each within MULTI_WINDOW of the last chain up -- DOUBLE, TRIPLE, QUADRA, PENTA,
# LEGENDARY; a gap resets it; friendly kills don't count; the Herald has a line for each.
const Sim = preload("res://scripts/siege/siege_sim.gd")
var fails := []
func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok: fails.append(what)
func _init():
	var s = Sim.new()
	s.setup(8, 6)
	for u in s.units: u.bot = false; u.move = Vector2.ZERO
	var me: Dictionary = s.by_id["you"]
	var foes: Array = s.units.filter(func(x): return x.team == 1)
	var names := []
	for k in 6:
		s._kill(me, foes[k])
		for e in s.drain_events():
			if e.k == "multikill": names.append(str(e.name))
		s.time += 1.0
	check(names == ["DOUBLE KILL", "TRIPLE KILL", "QUADRA KILL", "PENTA KILL", "LEGENDARY"], "six kills a second apart: %s" % str(names))
	check(int(me.get("best_multi", 0)) == 6, "best multi-kill kept (%d)" % int(me.get("best_multi", 0)))
	s.time += Sim.MULTI_WINDOW + 0.5
	s._kill(me, foes[6])
	var got := false
	for e in s.drain_events():
		if e.k == "multikill": got = true
	check(not got, "after a %.0f s gap the chain starts again" % (Sim.MULTI_WINDOW + 0.5))
	var ally: Dictionary = s.units.filter(func(x): return x.team == 0 and x.id != "you")[0]
	s._kill(me, ally)
	var friendly := false
	for e in s.drain_events():
		if e.k == "multikill": friendly = true
	check(not friendly, "killing a friend doesn't count")
	for n in ["double", "triple", "quadra", "penta", "legendary"]:
		check(ResourceLoader.exists("res://assets/vo/herald/mk_%s.ogg" % n), "the Herald's '%s' line is in the game" % n)
	print("MULTIKILL_PASS" if fails.is_empty() else "MULTIKILL_FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
