extends SceneTree
const Mode = preload("res://scripts/siege/siege_mode.gd")
var mode
var frames := 0
func _init() -> void:
	mode = Mode.new()
	mode.size = Vector2(420, 780)
	root.add_child(mode)
func _process(delta: float) -> bool:
	frames += 1
	if frames == 2:
		mode.sim.by_id["you"].bot = true
	if frames == 5400 or (mode.sim.ended and frames > 10):
		var s = mode.sim
		var alive: int = s.units.filter(func(u): return u.state != "dead").size()
		var actors: int = mode.view.actors.size()
		var classes := {}
		for u in s.units: classes[u.cls] = classes.get(u.cls, 0) + 1
		print("SIEGE_MODE_PASS t=%.1f actors=%d alive=%d classes=%s score=%s kills=%s" % [s.time, actors, alive, str(classes), str(s.score), str(s.kills)])
		quit(0)
	return false
