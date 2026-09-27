extends SceneTree
# Forces ~30 fps with a real per-frame delay; the thermal guard must drop the cap to 30.
const Mode = preload("res://scripts/siege/siege_mode.gd")
var mode
var start := 0
func _init() -> void:
	mode = Mode.new()
	root.add_child(mode)
	start = Time.get_ticks_msec()
func _process(delta: float) -> bool:
	OS.delay_msec(30)
	if Time.get_ticks_msec() - start > 7000:
		assert(mode.guard_tripped, "guard did not trip")
		assert(Engine.max_fps == 30)
		print("SIEGE_GUARD_PASS max_fps=", Engine.max_fps)
		mode.queue_free()
		quit(0)
	return false
