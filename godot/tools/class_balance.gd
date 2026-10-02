extends SceneTree
# Per-class combat numbers from full 16v16 bot matches (0.31.4): run several seeds, add up Sim.class_stats, print a table.
#   SEEDS=11,22,33 godot --headless --path godot -s res://tools/class_balance.gd
const Sim = preload("res://scripts/siege/siege_sim.gd")
func _init() -> void:
	var seeds := (OS.get_environment("SEEDS") if OS.has_environment("SEEDS") else "11,22,33").split(",")
	var tot := {}
	for sd in seeds:
		var s = Sim.new()
		s.setup(16, int(sd))
		while s.time < 720.0 and s.winner < 0:
			s.step()
		for k in s.class_stats:
			if not tot.has(k):
				tot[k] = {"dmg":0.0, "taken":0.0, "kills":0.0, "deaths":0.0, "time":0.0}
			for f in tot[k]:
				tot[k][f] = float(tot[k][f]) + float(s.class_stats[k][f])
		print("seed %s done: %.0f s, score %s" % [sd, s.time, str(s.score)])
	print("%-12s %8s %9s %9s %6s %6s %6s %9s" % ["class", "min alive", "dmg/min", "taken/min", "kills", "deaths", "K/D", "kills/min"])
	var keys := tot.keys()
	keys.sort_custom(func(a, b): return float(tot[a].dmg) / maxf(1.0, float(tot[a].time)) > float(tot[b].dmg) / maxf(1.0, float(tot[b].time)))
	for k in keys:
		var t: Dictionary = tot[k]
		var mins := float(t.time) / 60.0
		print("%-12s %8.1f %9.1f %9.1f %6d %6d %6.2f %9.2f" % [k, mins, float(t.dmg) / maxf(mins, 0.01), float(t.taken) / maxf(mins, 0.01),
			int(t.kills), int(t.deaths), float(t.kills) / maxf(1.0, float(t.deaths)), float(t.kills) / maxf(mins, 0.01)])
	print("BALANCE_DONE")
	quit()
