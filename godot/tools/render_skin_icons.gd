extends SceneTree
# Renders one bust icon per skin (and per class default) to assets/ui/skins/<id>.png, using the
# same character builder, idle animation and tint as the game, so the icon is exactly what you get.
#   Xvfb :98 -screen 0 480x1000x24 & DISPLAY=:98 godot --rendering-method mobile --path godot \
#     -s res://tools/render_skin_icons.gd        (ONLY=id1,id2 to render a subset)
const View = preload("res://scripts/siege/siege_view.gd")
const Eco = preload("res://scripts/meta/economy.gd")
const SIZE := 320
const BUST_FRAME := {"mage": [Vector3(0.0, 1.8, 3.45), Vector3(0, 1.6, 0)], "knight": [Vector3(0.0, 1.68, 3.1), Vector3(0, 1.48, 0)],
	"barbarian": [Vector3(0.0, 1.72, 3.3), Vector3(0, 1.52, 0)],
	"archmage": [Vector3(0.0, 1.8, 3.45), Vector3(0, 1.6, 0)], "crusader": [Vector3(0.0, 1.68, 3.1), Vector3(0, 1.48, 0)],
	"necromancer": [Vector3(0.0, 1.7, 3.4), Vector3(0, 1.5, 0)], "berserker": [Vector3(0.0, 1.66, 3.3), Vector3(0, 1.46, 0)]}

var vp: SubViewport
var cam3: Camera3D
var holder: Node3D
var only: Array = []

func _initialize() -> void:
	if OS.has_environment("ONLY"):
		only = OS.get_environment("ONLY").split(",")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/ui/skins"))
	vp = SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#cfd6ea")
	var vk := RenderingServer.get_current_rendering_method() != "gl_compatibility"
	env.ambient_light_energy = 0.55 * (View.VULKAN_AMBIENT if vk else 1.0)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.85 * (View.VULKAN_EXPOSURE if vk else 1.0)
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
	rim.omni_range = 6.0
	rim.position = Vector3(1.9, 2.2, -1.6)
	vp.add_child(rim)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(0.0, 1.62, 3.0)
	vp.add_child(cam)
	cam.transform = Transform3D(Basis.looking_at(Vector3(0, 1.42, 0) - cam.position, Vector3.UP), cam.position)
	cam3 = cam
	holder = Node3D.new()
	vp.add_child(holder)
	_run()

func _run() -> void:
	var jobs: Array = []
	for cls in Eco.CLASSES + Eco.UP_CLASSES:
		jobs.append(["default_" + cls, cls, ""])
	for id in Eco.CATALOG:
		var it: Dictionary = Eco.CATALOG[id]
		if it.kind == "skin":
			jobs.append([id, str(it["class"]), str(it.tint)])
		elif it.kind == "weapon" and (Eco.UP_CLASSES.has(str(it["class"])) or only.has(id) or not FileAccess.file_exists("res://assets/ui/icons/%s.png" % id)):      # (0.31.76: or named in ONLY -- re-render a base class's)
			jobs.append([id, str(it["class"]), "", str(it.get("r", "")), str(it.get("l", ""))])      # 0.31.38: weapon icons
	for ucls in Eco.CLASSES + Eco.UP_CLASSES:                # (0.31.65: base classes' default gear too)
		jobs.append(["wdefault_" + ucls, ucls, "", "-", "-"])
	for job in jobs:
		if not only.is_empty() and not only.has(job[0]):
			continue
		for c in holder.get_children():
			c.queue_free()
		var cosmetic := {"r": "", "l": ""}                  # busts show the outfit, not the gear
		var weapon_job: bool = job.size() > 3
		if weapon_job:
			cosmetic = {}                                   # the class's own gear ("-") or the item's
			if str(job[3]) != "-":
				cosmetic = {"r": job[3], "l": job[4]}
		if job[2] != "":
			cosmetic["tint"] = job[2]
		var body_key := str(Eco.UP_LOOK.get(job[1], job[1]))
		var made: Dictionary = View.make_body(body_key, cosmetic)
		var body: Node3D = made.body
		holder.add_child(body)
		body.rotation.y = deg_to_rad(-18.0)
		var idle: String = str(View.LOOKS.get(body_key, View.LOOKS.knight).idle)
		var cam: Camera3D = cam3
		var cpos := Vector3(0.0, 1.15, 4.4) if weapon_job else Vector3(0.0, 1.62, 3.0)       # whole figure for gear
		var aim := Vector3(0, 0.95, 0) if weapon_job else Vector3(0, 1.42, 0)
		if str(job[1]) in BUST_FRAME and not weapon_job:   # (0.31.80: the Mage's pointed hat, the Knight's plume, the bear head; 0.31.81: the new upgrades)
			cpos = BUST_FRAME[str(job[1])][0]
			aim = BUST_FRAME[str(job[1])][1]
		elif str(job[1]) == "archmage":                  # (0.31.55: the wizard's tall hat -- pull back and up)
			cpos = Vector3(0.0, 1.45, 5.6) if weapon_job else Vector3(0.0, 2.0, 3.9)
			aim = Vector3(0, 1.2, 0) if weapon_job else Vector3(0, 1.72, 0)
		elif str(job[1]) == "worker":                    # (0.31.76: the farmer's straw hat -- a little back and up)
			cpos = Vector3(0.0, 1.3, 5.0) if weapon_job else Vector3(0.0, 1.85, 3.5)
			aim = Vector3(0, 1.08, 0) if weapon_job else Vector3(0, 1.6, 0)
		cam.transform = Transform3D(Basis.looking_at(aim - cpos, Vector3.UP), cpos)
		if made.player.has_animation(idle):
			made.player.play(idle)
			made.player.seek(0.35, true)
		for i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		var out_path: String = "res://assets/ui/skins/%s.png" % job[0]
		if weapon_job:
			out_path = "res://assets/ui/icons/%s.png" % (str(job[0]).replace("wdefault_", "default_"))
		img.save_png(ProjectSettings.globalize_path(out_path))
		print("SKIN_DONE ", job[0])
	print("SKINS_ALL_DONE")
	quit(0)
