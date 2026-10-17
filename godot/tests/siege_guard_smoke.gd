extends SceneTree
# Round 32: Siege is hard-locked at 30 fps (no fps options). Forced down to ~20 fps with a real per-frame delay,
# the guard's remaining step must drop the 3D resolution to 75 %; the cap stays 30 throughout.
# 0.31.162: the cap is 60 (Kevin, to see how high each resolution goes) and the guard's step is only at a 30 cap: forced
# down to ~20 fps, the cap stays 60 and the resolution stays at 100 %.
const Mode = preload("res://scripts/siege/siege_mode.gd")
var mode
var start := 0
func _init() -> void:
	mode = Mode.new()
	root.add_child(mode)
	start = Time.get_ticks_msec()
func _process(delta: float) -> bool:
	OS.delay_msec(48)
	if Time.get_ticks_msec() - start > 1500:
		assert(Engine.max_fps == 60, "Siege runs at a 60 fps cap (%d)" % Engine.max_fps)
		assert(Engine.physics_ticks_per_second == 60, "physics at the cap's rate (%d)" % Engine.physics_ticks_per_second)
	if Time.get_ticks_msec() - start > 12000:          # (a slow first start can reset the 5-in-a-row count)
		assert(not mode.guard_tripped and absf(mode.render_scale - 1.0) < 0.01, "under ~20 fps the 3D resolution stays 100%% (scale %.2f)" % mode.render_scale)
		assert(Engine.max_fps == 60)
		print("SIEGE_GUARD_PASS max_fps=", Engine.max_fps, " render_scale=", mode.render_scale)
		mode.queue_free()
		quit(0)
	return false
