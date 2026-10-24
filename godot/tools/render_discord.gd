extends SceneTree
# Discord emojis and stickers (Kevin: "Make me a set of discord emojis and stickers"): the game's own heroes, rendered
# the way the game draws them (siege_view.gd make_body, its KayKit animations, the outfits' icon lighting) on a
# transparent background, for tools/discord_pack.py to cut, outline and caption:
#   bust_<hero>.png        640 x 640, head and shoulders (render_skin_icons.gd's framing), no weapons -- the emojis
#   pose_<id>.png          1024 x 1024, full body in one frame of an animation, his weapons -- the stickers
#   anim_<id>_NN.png       ...the same, NN frames across the animation -- the animated stickers
#   king.png               the King (on his throne, as in every keep)
#   Xvfb :98 -screen 0 1080x1920x24 &  DISPLAY=:98 godot --rendering-method mobile --path godot -s res://tools/render_discord.gd
#   OUT_DIR=<dir> (default /tmp/fb_discord)  ONLY=id1,id2
const View = preload("res://scripts/siege/siege_view.gd")
const Stage = preload("res://scripts/siege/asset_cache.gd")
const Champions = preload("res://scripts/meta/champions.gd")

const BUST := 640
const POSE := 1024
# render_skin_icons.gd's bust framing (camera, aim), a touch further back so hats, plumes and antlers fit
const BUST_FRAME := {"mage": [Vector3(0.0, 1.8, 3.45), Vector3(0, 1.6, 0)], "knight": [Vector3(0.0, 1.68, 3.1), Vector3(0, 1.48, 0)],
	"barbarian": [Vector3(0.0, 1.72, 3.3), Vector3(0, 1.52, 0)], "archmage": [Vector3(0.0, 1.8, 3.45), Vector3(0, 1.6, 0)],
	"crusader": [Vector3(0.0, 1.68, 3.1), Vector3(0, 1.48, 0)], "necromancer": [Vector3(0.0, 1.7, 3.4), Vector3(0, 1.5, 0)],
	"berserker": [Vector3(0.0, 1.66, 3.3), Vector3(0, 1.46, 0)], "golem": [Vector3(0.0, 1.95, 3.2), Vector3(0, 1.66, 0)],
	"dragoon": [Vector3(0.0, 1.66, 2.95), Vector3(0, 1.48, 0)], "duelist": [Vector3(0.0, 1.62, 3.0), Vector3(0, 1.42, 0)],
	"stormcaller": [Vector3(0.0, 1.62, 3.0), Vector3(0, 1.42, 0)], "musketeer": [Vector3(0.0, 1.78, 3.4), Vector3(0, 1.56, 0)],
	"druid": [Vector3(0.0, 1.9, 3.75), Vector3(0, 1.64, 0)]}
# the stickers' poses: hero, outfit ("" his own), animation, where in it (0..1 of its length), turn (degrees), and
# for an animated one how many frames across [a, b] of it
const POSES := [
	{"id":"golem_smash", "hero":"golem", "anim":"m/Melee_2H_Attack_Chop", "at":0.42, "turn":-28.0, "frames":18, "a":0.0, "b":1.0},
	{"id":"stormcaller_cast", "hero":"stormcaller", "skin":"stormcaller_stormforged", "anim":"r/Ranged_Magic_Shoot", "at":0.35, "turn":-30.0},
	{"id":"barbarian_chop", "hero":"barbarian", "anim":"m/Melee_2H_Attack_Chop", "at":0.40, "turn":-25.0},
	{"id":"dragoon_jump", "hero":"dragoon", "anim":"mb/Jump_Full_Short", "at":0.45, "turn":-20.0, "frames":20, "a":0.0, "b":1.0},
	{"id":"musketeer_run", "hero":"musketeer", "anim":"mb/Running_A", "at":0.25, "turn":-55.0, "frames":16, "a":0.0, "b":1.0},
	{"id":"necromancer_raise", "hero":"necromancer", "anim":"r/Ranged_Magic_Raise", "at":0.6, "turn":-15.0},
	{"id":"priest_raise", "hero":"priest", "anim":"r/Ranged_Magic_Summon", "at":0.55, "turn":-15.0},
	{"id":"mage_spell", "hero":"mage", "anim":"r/Ranged_Magic_Spellcasting", "at":0.3, "turn":-25.0, "frames":16, "a":0.0, "b":1.0},
	{"id":"rogue_sneak", "hero":"rogue", "anim":"ma/Sneaking", "at":0.3, "turn":-40.0},
	{"id":"knight_block", "hero":"knight", "anim":"m/Melee_Blocking", "at":0.5, "turn":-20.0},
	{"id":"druid_grass", "hero":"druid", "anim":"g/Interact", "at":0.5, "turn":-20.0},
	{"id":"duelist_stab", "hero":"duelist", "anim":"m/Melee_1H_Attack_Stab", "at":0.38, "turn":-35.0},
	{"id":"crusader_down", "hero":"crusader", "anim":"g/Death_A_Pose", "at":0.0, "turn":-10.0},
	{"id":"archmage_think", "hero":"archmage", "anim":"g/Idle_B", "at":0.3, "turn":-15.0},
	{"id":"minion", "hero":"minion_melee", "anim":"m/Melee_1H_Attack_Slice_Diagonal", "at":0.35, "turn":-25.0},
]

var out_dir := "/tmp/fb_discord"
var only: Array = []
var vp: SubViewport
var cam: Camera3D
var holder: Node3D

func _initialize() -> void:
	out_dir = OS.get_environment("OUT_DIR") if OS.has_environment("OUT_DIR") else out_dir
	if OS.has_environment("ONLY"):
		only = OS.get_environment("ONLY").split(",")
	DirAccess.make_dir_recursive_absolute(out_dir)
	vp = SubViewport.new()
	vp.size = Vector2i(POSE, POSE)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := Environment.new()                      # (render_skin_icons.gd's light: the outfits' icons)
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#cfd6ea")
	env.ambient_light_energy = 0.55 * View.VULKAN_AMBIENT
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.85 * View.VULKAN_EXPOSURE
	env.tonemap_white = 3.0
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_color = Color("#fff0d6")
	key.light_energy = 1.25
	key.rotation_degrees = Vector3(-30, -35, 0)
	vp.add_child(key)
	var rim := OmniLight3D.new()
	rim.light_color = Color("#9cc6ff")
	rim.light_energy = 1.4
	rim.omni_range = 8.0
	rim.position = Vector3(2.2, 2.6, -2.0)
	vp.add_child(rim)
	cam = Camera3D.new()
	cam.fov = 30.0
	vp.add_child(cam)
	holder = Node3D.new()
	vp.add_child(holder)
	_run()

func _want(id: String) -> bool:
	return only.is_empty() or only.has(id)

func _clear() -> void:
	for c in holder.get_children():
		holder.remove_child(c)
		c.queue_free()

func _look(pos: Vector3, aim: Vector3) -> void:
	cam.transform = Transform3D(Basis.looking_at(aim - pos, Vector3.UP), pos)

func _shot(path: String) -> void:
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(out_dir.path_join(path))
	print("DISCORD_DONE ", path)

func _run() -> void:
	# ---- the busts (emojis)
	vp.size = Vector2i(BUST, BUST)
	for hero in Champions.ORDER:
		if not _want("bust_" + str(hero)):
			continue
		_clear()
		var made: Dictionary = View.make_body(str(hero), {"r": "", "l": ""})
		holder.add_child(made.body)
		(made.body as Node3D).rotation.y = deg_to_rad(-14.0)
		var fr: Array = BUST_FRAME.get(str(hero), [Vector3(0.0, 1.62, 3.0), Vector3(0, 1.42, 0)])
		var back: Vector3 = (fr[0] - fr[1]) * 1.12 + fr[1]
		_look(back, fr[1] + Vector3(0, 0.04, 0))
		var idle: String = str(View.LOOKS.get(str(hero), View.LOOKS.knight).idle)
		if made.player.has_animation(idle):
			made.player.play(idle)
			made.player.seek(0.35, true)
		await _shot("bust_%s.png" % hero)
	# ---- the poses (stickers): full body, his weapons
	vp.size = Vector2i(POSE, POSE)
	for p in POSES:
		if not _want(str(p.id)):
			continue
		_clear()
		var cos := {}
		if str(p.get("skin", "")) != "":
			cos["skin"] = str(p.skin)
		var made: Dictionary = View.make_body(str(p.hero), cos)
		var body: Node3D = made.body
		holder.add_child(body)
		body.rotation.y = deg_to_rad(float(p.turn))
		_look(Vector3(0.0, 1.15, 6.4), Vector3(0.0, 1.05, 0.0))
		var pl: AnimationPlayer = made.player
		var an := str(p.anim)
		if not pl.has_animation(an):
			print("DISCORD_NO_ANIM ", p.id, " ", an)
			continue
		var length: float = pl.get_animation(an).length
		pl.play(an)
		pl.speed_scale = 0.0
		pl.seek(length * float(p.at), true)
		await _shot("pose_%s.png" % p.id)
		var n := int(p.get("frames", 0))
		for i in n:
			var tt: float = lerpf(float(p.a), float(p.b), float(i) / float(n)) * length
			pl.seek(tt, true)
			await _shot("anim_%s_%02d.png" % [p.id, i])
	# ---- the King on his throne
	if _want("king"):
		_clear()
		var packed := Stage.scene("res://assets/kings/king_blue_fat.glb")
		if packed != null:
			var m: Node3D = packed.instantiate()
			m.scale = Vector3.ONE * (View.KING_HEIGHT / 1.9)
			m.rotation.y = deg_to_rad(-20.0)
			holder.add_child(m)
			_look(Vector3(0.0, 1.5, 7.2), Vector3(0.0, 1.3, 0.0))
			await _shot("king.png")
	print("DISCORD_ALL_DONE")
	quit(0)
