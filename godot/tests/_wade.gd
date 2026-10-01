extends SceneTree
const Mode = preload("res://scripts/siege/siege_mode.gd")
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Land = preload("res://scripts/siege/siege_land.gd")
var mode
var frames := 0
var walkers := {}
func _init() -> void:
	mode = Mode.new()
	mode.hq_gfx = true
	root.add_child(mode)
	RenderingServer.frame_post_draw.connect(func():
		for f in [40, 62, 90]:
			if frames == f: root.get_texture().get_image().save_png("/tmp/wade_%d.png" % f))
func _process(d: float) -> bool:
	frames += 1
	mode._guard_clock = -1.0e9
	var s = mode.sim
	var me: Dictionary = s.by_id[mode.hud.player_id]
	if frames == 3:
		mode.hud.visible = false
		for u in s.units: u.bot = false; u.move = Vector2.ZERO; u.pos = Vector2(-30, -50)
		var crew: Array = s.units.filter(func(x): return x.team == 0)
		var c := Land.river_c(10.0)
		for k in 4:
			var u: Dictionary = crew[k]
			s._set_class(u, ["knight", "barbarian", "ranger", "rogue"][k], false)
			u.pos = Vector2(7.5 + k * 1.7, c - 4.6 - (k % 2) * 0.8)
			walkers[u.id] = Vector2(0.0, 1.0)
		var runner: Dictionary = crew[4]
		s._set_class(runner, "mage", false)
		runner.pos = Vector2(2.0, c + 0.2)
		walkers[runner.id] = Vector2(1.0, 0.0)
		mode.view.cam_override = [Vector3(10.0, 11.0, c + 9.5), Vector3(9.5, -0.6, c - 0.3)]
	for id in walkers:
		var u: Dictionary = s.by_id[id]
		if s.alive(u): u.move = walkers[id]
	if frames > 92: quit(0)
	return false
