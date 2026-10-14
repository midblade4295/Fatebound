extends SceneTree
# Dev tool (0.31.138): Home's war room alone (home_scene.gd, no menus over it), for looking at the scene itself.
#   Xvfb :98 & DISPLAY=:98 OUT=/tmp/home.png godot --rendering-method mobile --resolution 420x933 --path godot \
#     -s res://tools/home_scene_shot.gd
# Env: OUT (the png), FRAMES (frames to wait, default 40), PLAY_TOP (PLAY's top, default 517), CALM=1 (reduce motion),
# WAR=1 (a war on the table: the houses' land and two battles), SEQ=n (n shots, one every 4th frame: OUT_NN.png).
const HomeScene = preload("res://scripts/app/home_scene.gd")
const Eco = preload("res://scripts/meta/economy.gd")
var scene
var n := 0
var frames := 40
var seq := 0
var out := "/tmp/home_scene.png"

func _init() -> void:
	if OS.has_environment("OUT"): out = OS.get_environment("OUT")
	if OS.has_environment("FRAMES"): frames = int(OS.get_environment("FRAMES"))
	if OS.has_environment("SEQ"): seq = int(OS.get_environment("SEQ"))
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(holder)
	scene = HomeScene.new(OS.get_environment("CALM") == "1", false)
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(scene)

func _process(_d: float) -> bool:
	n += 1
	if n == 2:
		scene.place(float(OS.get_environment("PLAY_TOP")) if OS.has_environment("PLAY_TOP") else 517.0)
		var looks := {}
		for c in Eco.CLASSES:
			looks[c] = {}
		scene.set_looks(looks)
		if OS.get_environment("WAR") == "1":
			var terr := {}
			for id in ["home_lions", "mill", "tower", "quarry", "ford", "marsh"]:
				terr[id] = {"h": "lions"}
			for id in ["home_stags", "pass", "abbey", "mine", "cliffs"]:
				terr[id] = {"h": "stags"}
			for id in ["home_ravens", "fen", "port", "forge", "woods"]:
				terr[id] = {"h": "ravens"}
			terr["tower"]["b"] = "b1"
			terr["woods"]["b"] = "b2"
			scene.paint_war({"terr": terr})
	if n == frames:
		print("flames: ", scene.room.flame_points() if scene.room != null else [])
		for f in scene._flames:
			if f.table >= 0: print(f.table, " ", f.core.position, " ", f.core.get_global_rect(), " ", f.core.modulate, " vis ", f.core.is_visible_in_tree())
	if n >= frames:
		var i := n - frames
		if seq <= 0 or i % 4 == 0:
			var path := out if seq <= 0 else out.replace(".png", "_%02d.png" % (i / 4))
			root.get_texture().get_image().save_png(path)
			if seq <= 0 or i / 4 >= seq - 1:
				quit()
	return false
