extends SceneTree
# Every objective must be reachable (with the enemy's gates broken): from each side's fountain, the enemy King, each of
# his keep's gates from inside, the middle of the field and both pits. (0.31.169: the 5v5's; until then the Siege's
# cells, hat stands and workshops.)
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Land = preload("res://scripts/siege/siege_land.gd")
const Keep = preload("res://scripts/siege/keep.gd")
func _init() -> void:
	var sim = Sim.new()
	sim.setup(5, 1)
	sim.setup_moba("knight", 1)
	for g in sim.gates: g.hp = 0.0; g.broken = true
	sim._update_gate_nav()
	for t in 2:
		var e := 1 - t
		var pairs := [[Sim.spawn(t), sim.moba.king_pos(e) + (Sim._m(e, Keep.gate_c(1)) - sim.moba.king_pos(e)).normalized() * 3.0, "fountain->enemy King"],
			[Sim.spawn(t), Vector2.ZERO, "fountain->mid field"], [Sim.spawn(t), Land.pit_c(0), "fountain->west pit"],
			[Sim.spawn(t), Land.pit_c(1), "fountain->east pit"]]
		for i in Keep.GATE_ANG.size():
			var gc: Vector2 = Sim._m(e, Keep.gate_c(i))
			pairs.append([Sim.spawn(t), gc + (Sim._m(e, Keep.C) - gc).normalized() * 2.0, "fountain->inside enemy gate %d" % i])
		for pair in pairs:
			var path: PackedVector2Array = sim.find_path(t, pair[0], pair[1])
			var end: Vector2 = path[path.size() - 1] if path.size() > 0 else pair[0]
			var miss: float = end.distance_to(pair[1])
			print("team %d %-30s %3d steps, ends %.2f m away" % [t, pair[2], path.size(), miss])
			assert(miss < 1.2, "unreachable: " + pair[2])
	print("SIEGE_REACH_PASS")
	quit(0)
