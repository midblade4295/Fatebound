extends SceneTree
# Armory Reforged icons (0.31.93): the weapon itself, posed like the concept sheets Kevin approved -- the shield (or
# off-hand piece) upright behind, the main weapon diagonal in front -- for every catalog weapon (and class starter)
# made of Meshy pieces ("mw/..."). Writes assets/ui/icons/<id>.png (default_<cls>.png for a starter), 320 px,
# transparent. The same models and lights as the game.
#   Xvfb :98 & DISPLAY=:98 godot --rendering-method mobile --path godot -s res://tools/render_weapon_icons.gd
#   (ONLY=id1,id2 for a subset; a starter is "default_<cls>")
const View = preload("res://scripts/siege/siege_view.gd")
const Eco = preload("res://scripts/meta/economy.gd")
const WeaponPose = preload("res://scripts/app/weapon_pose.gd")
const SIZE := 320

var vp: SubViewport
var cam: Camera3D
var holder: Node3D
var only: Array = []

func _initialize() -> void:
	if OS.has_environment("ONLY"):
		only = OS.get_environment("ONLY").split(",")
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
	env.ambient_light_energy = 0.6 * View.VULKAN_AMBIENT
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.85 * View.VULKAN_EXPOSURE
	env.tonemap_white = 3.0
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_color = Color("#fff0d6")
	key.light_energy = 1.3
	key.rotation_degrees = Vector3(-28, -30, 0)
	vp.add_child(key)
	var rim := OmniLight3D.new()
	rim.light_color = Color("#9cc6ff")
	rim.light_energy = 1.6
	rim.omni_range = 8.0
	rim.position = Vector3(2.2, 2.0, -2.0)
	vp.add_child(rim)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	vp.add_child(cam)
	holder = Node3D.new()
	vp.add_child(holder)
	_run()

static func jobs() -> Array:
	# [icon id, right-hand file, left-hand file]
	var out := []
	for cls in Eco.STARTER_NAMES:
		var look: Dictionary = View.LOOKS.get(cls, {})
		out.append(["default_" + cls, str(look.get("r", "")), str(look.get("l", ""))])
	for id in Eco.CATALOG:
		var it: Dictionary = Eco.CATALOG[id]
		if str(it.get("kind", "")) == "weapon" and (str(it.get("r", "")).begins_with("mw/") or str(it.get("l", "")).begins_with("mw/")):
			out.append([str(id), str(it.get("r", "")), str(it.get("l", ""))])
	return out

func _run() -> void:
	for job in jobs():
		if not only.is_empty() and not only.has(job[0]):
			continue
		for c in holder.get_children():
			holder.remove_child(c)
			c.queue_free()
		var shown := Node3D.new()
		holder.add_child(shown)
		WeaponPose.compose(shown, str(job[1]), str(job[2]))
		cam.size = 2.2
		cam.transform = Transform3D(Basis.IDENTITY, Vector3(0, 0, 6))
		for i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("res://assets/ui/icons/%s.png" % job[0]))
		print("ICON_DONE ", job[0])
	print("ICONS_ALL_DONE")
	quit(0)
