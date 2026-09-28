extends SceneTree
const Sim = preload("res://scripts/siege/siege_sim.gd")
func _init() -> void:
	var s = Sim.new()
	s.setup(16, 11)
	s.by_id["you"].bot = true
	s.profile = true
	var t0 := Time.get_ticks_msec()
	var ticks := int(180.0 / Sim.TICK)
	for i in ticks: s.step()
	var total := Time.get_ticks_msec() - t0
	print("180 s sim: %d ms total, %.2f ms/tick" % [total, float(total) / ticks])
	var keys: Array = s.prof.keys()
	keys.sort_custom(func(a, b): return int(s.prof[a]) > int(s.prof[b]))
	for k in keys:
		if k == "replans": print("  replans: %d (%.1f/s)" % [s.prof[k], float(s.prof[k]) / 180.0])
		else: print("  %-12s %6.2f ms/tick" % [k, float(s.prof[k]) / 1000.0 / ticks])
	quit(0)
