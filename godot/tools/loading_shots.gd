extends SceneTree
# 0.31.208: the loading screen (scripts/siege/loading_screen.gd) in its states, as PNGs in SHOT_DIR -- for looking at it
# without a server: connecting (your hero alone), the lobby as players join (their heroes in their outfits), a full
# lobby (two rows), an older server's lobby (names only: shadows), the loading card, and a join caught mid-drop.
#   Xvfb :97 & DISPLAY=:97 godot --rendering-method mobile --resolution 420x933 --path godot -s res://tools/loading_shots.gd
const Loading = preload("res://scripts/siege/loading_screen.gd")

var dir := "user://loading_shots"
var ls
var t := 0.0
var step := 0
var plan: Array = []

func _init() -> void:
	if OS.has_environment("SHOT_DIR"):
		dir = OS.get_environment("SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(dir)
	ls = Loading.new()
	ls.my_hero = "knight"
	ls.my_skin = "knight_lion"
	ls.my_name = "[ROSE] Kevin the Bold"
	root.add_child(ls)
	var three := {"t":"lobby", "left":14.0, "wait":20.0, "names":["Kevin", "Mara", "Ozzy"], "tt":["", "", ""], "ct":["ROSE", "", ""],
		"hr":["knight", "stormcaller", "golem"], "sk":["knight_lion", "stormcaller_stormforged", ""], "me":0, "online":3, "slots":10, "running":false}
	var seven := three.duplicate(true)
	seven.names = ["Kevin", "Mara", "Ozzy", "Bea", "Thorn", "Lux", "Grim"]
	seven.tt = ["", "", "", "", "", "", ""]
	seven.ct = ["ROSE", "", "", "", "", "", ""]
	seven.hr = ["knight", "stormcaller", "golem", "duelist", "berserker", "druid", "necromancer"]
	seven.sk = ["knight_lion", "stormcaller_stormforged", "", "duelist_rose", "", "druid_blossom", ""]
	seven.online = 7
	seven.left = 6.0
	var old := {"t":"lobby", "left":12.0, "wait":20.0, "names":["Kevin", "Mara", "Ozzy"], "tt":["", "", ""], "ct":["", "", ""], "me":0, "online":3, "slots":10, "running":false}
	plan = [
		[2.0, func(): pass, "1_connecting"],
		[0.1, func(): ls.update({"t":"lobby", "left":18.0, "wait":20.0, "names":["Kevin"], "tt":[""], "ct":["ROSE"], "hr":["knight"], "sk":["knight_lion"], "me":0, "online":1, "slots":10, "running":false}), ""],
		[1.0, func(): ls.update(three), ""],
		[0.15, func(): pass, "2a_joining"],
		[0.12, func(): pass, "2b_joining"],
		[0.15, func(): pass, "2c_joining"],
		[0.3, func(): pass, "2d_joining"],
		[2.0, func(): pass, "3_lobby_three"],
		[0.1, func(): ls.update(seven), ""],
		[2.5, func(): pass, "4_lobby_seven"],
		[0.1, func(): ls.loading(), ""],
		[1.0, func(): pass, "5_loading"],
		[0.1, func():
			root.remove_child(ls)
			ls.queue_free()
			ls = Loading.new()
			ls.my_hero = "mage"
			ls.my_name = "Kevin"
			root.add_child(ls), ""],
		[0.1, func(): ls.update(old), ""],
		[2.0, func(): pass, "6_older_server"],
	]

func _process(delta: float) -> bool:
	t += delta
	if step >= plan.size():
		print("LOADING_SHOTS done -> ", ProjectSettings.globalize_path(dir))
		quit(0)
		return false
	var p: Array = plan[step]
	if t >= float(p[0]):
		if str(p[2]) != "":
			var img := root.get_viewport().get_texture().get_image()
			img.save_png(dir + "/" + str(p[2]) + ".png")
			print("shot ", p[2])
		(p[1] as Callable).call()
		t = 0.0
		step += 1
	return false
