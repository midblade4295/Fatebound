extends SceneTree
# Renders one bust icon per skin (and per class default) to assets/ui/skins/<id>.png, using the
# same character builder, idle animation and tint as the game, so the icon is exactly what you get.
#   Xvfb :98 -screen 0 480x1000x24 & DISPLAY=:98 godot --rendering-method mobile --path godot \
#     -s res://tools/render_skin_icons.gd        (ONLY=id1,id2 to render a subset)
const View = preload("res://scripts/siege/siege_view.gd")
const Eco = preload("res://scripts/meta/economy.gd")
const SIZE := 320

var vp: SubViewport
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
	cam.look_at(Vector3(0, 1.42, 0), Vector3.UP)
	holder = Node3D.new()
	vp.add_child(holder)
	_run()

func _run() -> void:
	var jobs: Array = []
	for cls in Eco.CLASSES:
		jobs.append(["default_" + cls, cls, ""])
	for id in Eco.CATALOG:
		var it: Dictionary = Eco.CATALOG[id]
		if it.kind == "skin":
			jobs.append([id, str(it["class"]), str(it.tint)])
	for job in jobs:
		if not only.is_empty() and not only.has(job[0]):
			continue
		for c in holder.get_children():
			c.queue_free()
		var cosmetic := {"r": "", "l": ""}                  # busts show the outfit, not the gear
		if job[2] != "":
			cosmetic["tint"] = job[2]
		var made: Dictionary = View.make_body(job[1], cosmetic)
		var body: Node3D = made.body
		holder.add_child(body)
		body.rotation.y = deg_to_rad(-18.0)
		var idle: String = str(View.LOOKS.get(job[1], View.LOOKS.knight).idle)
		if made.player.has_animation(idle):
			made.player.play(idle)
			made.player.seek(0.35, true)
		for i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("res://assets/ui/skins/%s.png" % job[0]))
		print("SKIN_DONE ", job[0])
	print("SKINS_ALL_DONE")
	quit(0)
