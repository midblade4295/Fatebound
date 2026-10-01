extends SceneTree
# Map review shots (no HUD): the whole battlefield from above plus a few angled views.
#   Xvfb :9 & DISPLAY=:9 godot --rendering-method mobile --resolution 1600x1000 -s res://tools/map_overview.gd
# Writes /tmp/map_<name>.png. SHOTS env (comma list) picks a subset; OUT env changes the prefix.
const Mode = preload("res://scripts/siege/siege_mode.gd")
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Land = preload("res://scripts/siege/siege_land.gd")
var mode
var frames := 0
var shots := ["top", "blue_half", "island", "west", "east"]
var si := -1
var shot_at := -1
var prefix := "/tmp/map_"

func _init() -> void:
	if OS.has_environment("SHOTS"):
		shots = Array(OS.get_environment("SHOTS").split(","))
	if OS.has_environment("OUT"):
		prefix = OS.get_environment("OUT")
	mode = Mode.new()
	root.add_child(mode)
	RenderingServer.frame_post_draw.connect(func():
		if frames == shot_at and si >= 0 and si < shots.size():
			root.get_texture().get_image().save_png("%s%s.png" % [prefix, shots[si]])
			print("SHOT ", shots[si]))

func _cam(name: String) -> Array:
	var hl: float = Sim.HALF_L
	var hw: float = Sim.HALF_W
	match name:
		"top":
			# Straight down over the whole field (a tiny z offset keeps look_at well defined).
			return [Vector3(0.0, hl * 2.35, 0.6), Vector3(0.0, 0.0, 0.0)]
		"blue_half":
			return [Vector3(0.0, 62.0, hl * 0.5 + 34.0), Vector3(0.0, 0.0, hl * 0.42)]
		"island":
			return [Vector3(0.0, 26.0, 26.0), Vector3(0.0, 0.0, 1.0)]
		"west":
			return [Vector3(-hw * 0.2, 34.0, 44.0), Vector3(-hw * 0.6, 0.0, 18.0)]
		"east":
			return [Vector3(hw * 0.2, 34.0, 40.0), Vector3(hw * 0.75, 0.0, 12.0)]
		"red_half":
			return [Vector3(0.0, 62.0, -hl * 0.5 - 34.0), Vector3(0.0, 0.0, -hl * 0.42)]
	return [Vector3(0.0, 40.0, 40.0), Vector3.ZERO]

func _process(_delta: float) -> bool:
	frames += 1
	if frames == 3:
		mode.hud.diag = null
		mode.hud.visible = false
	mode._guard_clock = -1.0e9
	if frames == 4:
		mode.set_fps_cap(0)
	var k := frames - 6
	if k >= 0 and k % 7 == 0:
		si += 1
		if si >= shots.size():
			quit(0)
			return false
		var cam := _cam(str(shots[si]))
		mode.view.cam_override = cam
		if mode.view.camera != null:
			mode.view.camera.far = 600.0
		shot_at = frames + 5
	return false
