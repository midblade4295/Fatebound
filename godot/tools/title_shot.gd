extends SceneTree
# Dev tool (0.31.139): the title screen (title_screen.gd) alone, a frame every few -- the title's flight, the slam, TAP TO
# START.   Xvfb :98 & DISPLAY=:98 OUT=/tmp/title godot --rendering-method mobile --fixed-fps 30 --resolution 420x933 \
#            --path godot -s res://tools/title_shot.gd
# Env: OUT (a folder: title_NN.png), AT (comma list of frames to shoot, default 3,8,14,15,17,20,30,60), CALM=1.
const TitleScreen = preload("res://scripts/app/title_screen.gd")
var ts
var n := 0
var out := "/tmp/title"
var at: Array = [3, 8, 14, 15, 17, 20, 30, 60]

func _init() -> void:
	if OS.has_environment("OUT"): out = OS.get_environment("OUT")
	if OS.has_environment("AT"): at = Array(OS.get_environment("AT").split(",")).map(func(x): return int(x))
	DirAccess.make_dir_recursive_absolute(out)
	ts = TitleScreen.new(null, OS.get_environment("CALM") == "1")
	root.add_child(ts)

func _process(_d: float) -> bool:
	n += 1
	if n in at:
		root.get_texture().get_image().save_png("%s/title_%02d.png" % [out, n])
	return n >= int(at.max()) + 1
