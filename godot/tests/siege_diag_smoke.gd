extends SceneTree
const Mode = preload("res://scripts/siege/siege_mode.gd")
const Diag = preload("res://scripts/siege/siege_diag.gd")
var mode
var frames := 0
func _init() -> void:
	mode = Mode.new()
	root.add_child(mode)
func _process(delta: float) -> bool:
	frames += 1
	if frames == 2: mode.sim.by_id["you"].bot = true
	if frames == 150:
		mode.diag.mark("test block")
		OS.delay_msec(3500)   # simulate a hang on the main thread
	if frames == 160:
		push_error("diag capture test")
	if frames == 250:
		OS.delay_msec(700)  # let the watchdog tick after recovery
	if frames == 260:
		mode.queue_free()
	if frames == 265:
		var text := Diag.read_logs()
		assert(text.contains("SESSION"))
		assert(text.contains("STAT fps="))
		assert(text.contains("STALL") and text.contains("test block"))
		assert(text.contains("RECOVERED"))
		assert(text.contains("diag capture test"))
		print("SIEGE_DIAG_PASS")
		quit(0)
	return false
