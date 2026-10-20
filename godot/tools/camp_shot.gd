extends SceneTree
# Dev tool (0.31.194): Home's camp alone (camp_scene.gd, no menus over it), for looking at the scene itself.
#   Xvfb :98 & DISPLAY=:98 OUT=/tmp/camp.png godot --rendering-method mobile --resolution 360x780 --path godot \
#     -s res://tools/camp_shot.gd
# Env: OUT (the png), FRAMES (frames to wait, default 40), PLAY_TOP (PLAY's top, default 406), CALM=1 (reduce motion),
# SEQ=n (n shots, one every 4th frame: OUT_NN.png). (0.31.138-0.31.193: home_scene_shot.gd, the war room.)
const CampScene = preload("res://scripts/app/camp_scene.gd")
var scene
var n := 0
var frames := 40
var seq := 0
var out := "/tmp/camp.png"

func _init() -> void:
	if OS.has_environment("OUT"): out = OS.get_environment("OUT")
	if OS.has_environment("FRAMES"): frames = int(OS.get_environment("FRAMES"))
	if OS.has_environment("SEQ"): seq = int(OS.get_environment("SEQ"))
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(holder)
	scene = CampScene.new(OS.get_environment("CALM") == "1", false)
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(scene)

func _process(_d: float) -> bool:
	n += 1
	if n == 2:
		scene.place(float(OS.get_environment("PLAY_TOP")) if OS.has_environment("PLAY_TOP") else 406.0)
	if n >= frames:
		var i := n - frames
		if seq <= 0:
			root.get_texture().get_image().save_png(out)
			print("wrote ", out)
			return true
		if i % 4 == 0:
			var p := out.get_basename() + "_%02d.png" % (i / 4)
			root.get_texture().get_image().save_png(p)
			if i / 4 >= seq - 1:
				print("wrote ", seq, " shots")
				return true
	return false
