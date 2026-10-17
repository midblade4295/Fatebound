extends SceneTree
# 0.31.165: review shots of the Rift in a 5v5 (no HUD, no fog): the whole field from above and a few angled views.
#   Xvfb :98 & DISPLAY=:98 godot --rendering-method mobile --resolution 900x1600 --path godot -s res://tools/rift_shots.gd
# Writes <OUT><name>.png (OUT default /tmp/rift_). SHOTS env (comma list) picks a subset. A shot named "play_<x>_<y>"
# is the match's own camera following you, standing at (x, y). 0.31.166: the Grave Wyrm is up from the start (not 3:00)
# and you stand by its pit for the "wyrm_*" shots (your side sees it); "wyrm_breath" is taken as its soul-fire pours.
const Mode = preload("res://scripts/siege/siege_mode.gd")
const Sim = preload("res://scripts/siege/siege_sim.gd")
var mode
var frames := 0
var shots := ["top", "blue_keep", "mid_river", "lord_pit", "wyrm_pit", "west_jungle", "east_jungle", "play_0_60", "play_-46_20",
	"play_-24_46", "play_0_88"]
var si := -1
var shot_at := -1
var prefix := "/tmp/rift_"
var next_at := 42
var wait_view := -1.0                     # (a shot waiting on the view's clock rather than frames)

func _init() -> void:
	OS.set_environment("SIEGE_URL", "ws://127.0.0.1:1")
	if OS.has_environment("SHOTS"):
		shots = Array(OS.get_environment("SHOTS").split(","))
	if OS.has_environment("OUT"):
		prefix = OS.get_environment("OUT")
	mode = Mode.new()
	mode.moba_hero = "knight"
	mode.match_seed = 4401
	root.add_child(mode)
	RenderingServer.frame_post_draw.connect(func():
		if frames == shot_at and si >= 0 and si < shots.size():
			root.get_texture().get_image().save_png("%s%s.png" % [prefix, shots[si]])
			print("SHOT ", shots[si]))

func _cam(name: String) -> Array:
	var hl: float = Sim.HALF_L
	match name:
		"top":
			return [Vector3(0.0, hl * 2.3, 0.6), Vector3(0.0, 0.0, 0.0)]
		"blue_half":
			return [Vector3(0.0, 95.0, 118.0), Vector3(0.0, 0.0, 48.0)]
		"red_half":
			return [Vector3(0.0, 95.0, -118.0), Vector3(0.0, 0.0, -48.0)]
		"river":
			return [Vector3(0.0, 70.0, 52.0), Vector3(0.0, 0.0, 0.0)]
		"blue_keep":
			return [Vector3(0.0, 30.0, 70.0), Vector3(0.0, 0.0, 94.0)]
		"mid_river":
			return [Vector3(0.0, 30.0, 26.0), Vector3(0.0, 0.0, 2.0)]
		"lord_pit":
			return [Vector3(-26.0, 22.0, 18.0), Vector3(-26.0, 0.0, -3.9)]
		"wyrm_pit":
			return [Vector3(26.0, 22.0, 26.0), Vector3(26.0, 0.0, 3.9)]
		"wyrm_close", "wyrm_breath":
			return [Vector3(18.0, 8.0, 17.0), Vector3(26.0, 1.5, 4.5)]
		"west_jungle":
			return [Vector3(-24.0, 40.0, 72.0), Vector3(-24.0, 0.0, 40.0)]
		"east_jungle":
			return [Vector3(24.0, 40.0, 72.0), Vector3(24.0, 0.0, 40.0)]
	return []

func _process(_delta: float) -> bool:
	frames += 1
	if mode.sim == null or not mode._build_queue.is_empty():
		return false
	if frames < 40:
		return false
	if frames == 40:
		mode.hud.visible = false
		mode.view.fog_on = false
		for camp in mode.sim.moba.camps:
			if str(camp.kind) == "wyrm":
				camp.next = mode.sim.time               # up now (0.31.166)
		for nm in shots:
			if str(nm).begins_with("wyrm"):
				(mode.sim.by_id["you"] as Dictionary).pos = Vector2(21.0, 11.5)     # (where your side sees it)
		wait_view = float(mode.view._time) + 2.4        # (risen out of its pit before the first shot)
		frames = 41
	if wait_view >= 0.0:
		if float(mode.view._time) < wait_view:
			shot_at = frames + 1
			next_at = frames + 3
			return false
		wait_view = -1.0
	if frames >= next_at:
		si += 1
		if si >= shots.size():
			quit(0)
			return false
		var nm := str(shots[si])
		if nm.begins_with("play_"):
			var xy := nm.substr(5).split("_")
			mode.view.cam_override = []
			var me: Dictionary = mode.sim.by_id["you"]
			me.pos = Vector2(float(xy[0]), float(xy[1]))
		else:
			mode.view.cam_override = _cam(nm)
			if mode.view.camera != null:
				mode.view.camera.far = 700.0
			if nm.begins_with("wyrm"):
				(mode.sim.by_id["you"] as Dictionary).pos = Vector2(21.0, 11.5)
			if nm == "wyrm_breath":
				var wy: Dictionary = mode.sim.moba._wyrm_unit()
				if not wy.is_empty():
					var bd: Vector2 = mode.sim.dir_of(float(wy.face))      # the way it faces
					mode.view.on_event({"k":"wyrm_breath", "id":wy.id, "pos":wy.pos, "dir":bd, "n":0})
					wait_view = float(mode.view._time) + 0.75
		shot_at = frames + 7
		next_at = frames + 9
	return false
