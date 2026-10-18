extends SceneTree
# 0.31.174 (Kevin: "There's a lot of paths that go through unpassable walls"): no dirt path on the Rift runs under a
# wall the 5v5's sim stops units at -- a ridge's rocks or trees, a pit's rim, the field's edge, a keep's ring wall
# (its gates are the ways through) -- in the baked mask the terrain draws (tools/path_audit.gd's check; run that tool
# for the map and the list). And every trail is walkable along its whole centre line.
#   godot --headless --path godot -s res://tests/path_clear_test.gd
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Land = preload("res://scripts/siege/siege_land.gd")
const Audit = preload("res://tools/path_audit.gd")

func _init() -> void:
	var fails := []
	var sim = Sim.new()
	sim.setup(5, 1)
	sim.setup_moba("knight", 1)
	var res: Dictionary = Audit.audit(sim)
	for line in res.lines:
		print(line)
	if not res.lines.is_empty():
		fails.append("dirt under %d walls (%.1f m2)" % [res.lines.size(), res.area])
	print(("ok   " if res.lines.is_empty() else "FAIL ") + "no path under a wall (%.0f m2 of dirt checked)" % res.dirt)
	var blocked := 0
	var where := []
	for pl in Land.trails():
		for q in pl:
			if sim._blocked_point(q, 0, Sim.UNIT_R) or Land.river_off(q) < 0.0:
				blocked += 1
				if where.size() < 4:
					where.append(str(q))
	print(("ok   " if blocked == 0 else "FAIL ") + "every trail walkable along its centre, out of the water (%d points blocked %s)" % [blocked, " ".join(where)])
	if blocked > 0:
		fails.append("trail points blocked")
	print("PATH_CLEAR_%s" % ("PASS" if fails.is_empty() else "FAIL %s" % str(fails)))
	quit(0 if fails.is_empty() else 1)
