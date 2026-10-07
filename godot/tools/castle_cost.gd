extends SceneTree
# What the castles cost to draw: primitives, draw calls and frame time at a few game-camera views, with the Meshy
# castle kits (0.31.74) or (KITS=0) the KayKit castle. Lavapipe's times are CPU rasterisation: compare, don't read
# them as phone milliseconds.
#   Xvfb :98 & DISPLAY=:98 godot --path godot --rendering-method mobile --resolution 960x540 -s res://tools/castle_cost.gd
const Mode = preload("res://scripts/siege/siege_mode.gd")
const Sim = preload("res://scripts/siege/siege_sim.gd")
const View = preload("res://scripts/siege/siege_view.gd")
var mode
var frames := 0
var views := []
var vi := -1
var acc := {}
var t0 := 0

func _init() -> void:
	View.CASTLE_KITS = OS.get_environment("KITS") != "0"
	mode = Mode.new()
	root.add_child(mode)
	for t in 2:
		var c: Vector2 = Sim._c(t, Vector2(0.0, 14.0))
		var b: Vector2 = Sim._c(t, Vector2(0.0, 40.0))
		var f: Vector2 = Sim._c(t, Vector2(0.0, -12.0))
		views.append(["own%d" % t, [Vector3(b.x, 38.0, b.y), Vector3(c.x, 0.0, c.y)]])
		views.append(["front%d" % t, [Vector3(f.x, 38.0, f.y), Vector3(c.x, 0.0, c.y)]])

func _process(_d: float) -> bool:
	frames += 1
	if frames == 3:
		mode.hud.visible = false
		mode.set_fps_cap(0)
	mode._guard_clock = -1.0e9
	if frames < 20:
		return false
	var k := (frames - 20) % 40
	if k == 0:
		vi += 1
		if vi >= views.size():
			var out := []
			for v in acc:
				out.append("%s prims %d draws %d ms %.1f" % [v, acc[v][0], acc[v][1], acc[v][2]])
			print("COST kits=%s | %s" % [View.CASTLE_KITS, " | ".join(out)])
			quit(0)
			return false
		mode.view.cam_override = views[vi][1]
	elif k == 20:
		t0 = Time.get_ticks_usec()
	elif k == 39:
		var ms := (Time.get_ticks_usec() - t0) / 19000.0
		acc[views[vi][0]] = [RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), ms]
	return false
