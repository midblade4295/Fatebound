extends SceneTree
# Forces ~30 fps with a real per-frame delay; the thermal guard must drop the cap to 30. Then the same with
# Auto 30 FPS switched off (Round 31): the cap must stay at 60.
const Mode = preload("res://scripts/siege/siege_mode.gd")
var mode
var start := 0
var phase := 1
func _init() -> void:
	mode = Mode.new()
	root.add_child(mode)
	start = Time.get_ticks_msec()
func _process(delta: float) -> bool:
	OS.delay_msec(30)
	if Time.get_ticks_msec() - start > 7000:
		if phase == 1:
			assert(mode.guard_tripped, "guard did not trip")
			assert(Engine.max_fps == 30)
			print("guard on: tripped, max_fps=", Engine.max_fps)
			mode.free()                  # leave now: on leaving it restores the old cap, which must happen first
			mode = Mode.new()
			mode.auto_fps = false
			root.add_child(mode)
			start = Time.get_ticks_msec()
			phase = 2
		else:
			assert(not mode.guard_tripped, "the guard tripped with Auto 30 FPS off")
			assert(Engine.max_fps == 60, "max_fps changed with Auto 30 FPS off (%d)" % Engine.max_fps)
			print("guard off: did not trip, max_fps=", Engine.max_fps)
			print("SIEGE_GUARD_PASS max_fps=", Engine.max_fps)
			mode.queue_free()
			quit(0)
	return false
