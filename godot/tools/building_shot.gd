extends SceneTree
# Close-ups of a hat-shop building in a real match view (no HUD), both teams.
#   Xvfb :98 & DISPLAY=:98 godot --path godot --rendering-method mobile --resolution 1280x960 -s res://tools/building_shot.gd
# CLS env picks the class (default knight); OUT env the file prefix (default /tmp/bld_). Writes <prefix><shot>.png.
const Mode = preload("res://scripts/siege/siege_mode.gd")
const Sim = preload("res://scripts/siege/siege_sim.gd")
const Castle = preload("res://scripts/siege/siege_castle.gd")
var mode
var frames := 0
var shots := ["blue_front", "blue_game", "blue_back", "red_front"]
var si := -1
var shot_at := -1
var prefix := "/tmp/bld_"
var cls := "knight"

func _init() -> void:
	if OS.has_environment("OUT"):
		prefix = OS.get_environment("OUT")
	if OS.has_environment("CLS"):
		cls = OS.get_environment("CLS")
	if OS.has_environment("SHOTS"):
		shots = Array(OS.get_environment("SHOTS").split(","))
	mode = Mode.new()
	root.add_child(mode)
	RenderingServer.frame_post_draw.connect(func():
		if frames == shot_at and si >= 0 and si < shots.size():
			root.get_texture().get_image().save_png("%s%s.png" % [prefix, shots[si]])
			print("SHOT ", shots[si]))

func _cam(name: String) -> Array:
	var shop: Dictionary = Castle.HAT_SHOPS[Sim.HAT_CLASSES.find(cls)]
	var t := 1 if name.begins_with("red") else 0
	var b: Vector2 = Sim._c(t, shop.b)
	var door: Vector2 = Sim._c(t, shop.door)
	var out := (door - b).normalized()                  # the way the door faces
	var side := Vector2(-out.y, out.x)
	var c := Vector3(b.x, Sim.height_at(b) + 1.8, b.y)
	var o3 := Vector3(out.x, 0.0, out.y)
	var s3 := Vector3(side.x, 0.0, side.y)
	match name.substr(name.find("_") + 1):
		"front":
			return [c + o3 * 8.5 + s3 * 4.0 + Vector3(0, 2.6, 0), c]
		"game":
			return [c + o3 * 9.0 + s3 * 2.0 + Vector3(0, 13.0, 0), c - Vector3(0, 1.0, 0)]
		"back":
			return [c - o3 * 7.0 + s3 * 5.0 + Vector3(0, 5.0, 0), c + Vector3(0, 1.0, 0)]
		"backclose":
			return [c - o3 * 4.2 + s3 * 3.0 + Vector3(0, 2.6, 0), c + Vector3(0, 1.4, 0)]
	return [c + Vector3(8, 6, 8), c]

func _process(_delta: float) -> bool:
	frames += 1
	if frames == 3:
		mode.hud.diag = null
		mode.hud.visible = false
	mode._guard_clock = -1.0e9
	if OS.has_environment("FLAGS") and mode.sim != null:   # both teams own this class's hat upgrade (flag shows)
		for t in 2:
			mode.sim.levels[t]["hat_" + cls] = 1
	if frames == 4:
		mode.set_fps_cap(0)

	var k := frames - 20
	if k >= 0 and k % 9 == 0:
		si += 1
		if si >= shots.size():
			quit(0)
			return false
		mode.view.cam_override = _cam(str(shots[si]))
		shot_at = frames + 6
	return false
