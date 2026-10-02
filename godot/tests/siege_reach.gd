extends SceneTree
# Every objective must be reachable over the stairs and platforms (with enemy gates broken).
const Sim = preload("res://scripts/siege/siege_sim.gd")
func _init() -> void:
	var sim = Sim.new()
	sim.setup(16, 1)
	for g in sim.gates: g.hp = 0.0; g.broken = true
	sim._update_gate_nav()
	for t in 2:
		for pair in [[Sim.spawn(t), Sim.cell(t), "spawn->enemy cell"], [Sim.cell(t), Sim.throne(t), "enemy cell->own throne"],
				[Sim.spawn(t), Sim._c(t, Sim.HAT_HALL), "spawn->hat stands"], [Sim.spawn(t), Sim.workshop(t), "spawn->workshop"],
				[Sim.spawn(t), Vector2(0.0, 3.6), "spawn->island (north landing)"], [Sim.spawn(t), Vector2(0.0, -3.6), "spawn->island (south landing)"], [Sim.spawn(t), Vector2(-27.5, 25.0), "spawn->tower on the west ledge"], [Sim.spawn(t), Vector2(20.5, 17.0), "spawn->open ground west of the east rise"], [Sim.spawn(t), Vector2(38.0, 22.0), "spawn->east rise beside its tower"]]:
			var path: PackedVector2Array = sim.find_path(t, pair[0], pair[1])
			var end: Vector2 = path[path.size() - 1] if path.size() > 0 else pair[0]
			var miss: float = end.distance_to(pair[1])
			print("team %d %-24s %2d steps, ends %.2f m away" % [t, pair[2], path.size(), miss])
			assert(miss < 1.2, "unreachable: " + pair[2])
	print("SIEGE_REACH_PASS")
	quit(0)
