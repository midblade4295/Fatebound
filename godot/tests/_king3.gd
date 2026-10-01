extends SceneTree
const Mode = preload("res://scripts/siege/siege_mode.gd")
var mode
var frames := 0
var t0 := 0
func _init() -> void:
	t0 = Time.get_ticks_msec()
	mode = Mode.new()
	root.add_child(mode)
func _process(d: float) -> bool:
	frames += 1
	if frames in [1, 2, 5, 20]:
		print("frame %d at %d ms" % [frames, Time.get_ticks_msec() - t0])
	if frames == 20:
		var n: Dictionary = mode.view.oracle_nodes[0]
		print("king stages: ", (n.stages as Array).size(), " visible stage ", n.stage)
		quit(0)
	return false
