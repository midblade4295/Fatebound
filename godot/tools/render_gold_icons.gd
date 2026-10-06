extends SceneTree
# Renders the gold currency icons (assets/ui/currency/coin, coins_s, coins_m, coins_l) from the Quaternius
# Fantasy Props MegaKit coin models (CC0) -- 0.31.49, Kevin: "a new model for the gold itself".
#   Xvfb :98 & DISPLAY=:98 godot --rendering-method mobile --path godot -s res://tools/render_gold_icons.gd
const SIZE := 320
const DIR := "res://assets/models/gold/"
var vp: SubViewport
var holder: Node3D
var cam: Camera3D

func _initialize() -> void:
	vp = SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_8X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#fff1d6")
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.18
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_color = Color("#fff4dc")
	key.light_energy = 2.4
	key.rotation_degrees = Vector3(-48, -32, 0)
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color("#ffd27a")
	rim.light_energy = 1.6
	rim.rotation_degrees = Vector3(-20, 150, 0)
	vp.add_child(rim)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color("#c9d8ff")
	fill.light_energy = 0.5
	fill.rotation_degrees = Vector3(-10, 60, 0)
	vp.add_child(fill)
	cam = Camera3D.new()
	cam.fov = 26.0
	vp.add_child(cam)
	holder = Node3D.new()
	vp.add_child(holder)
	_run()

func _add(model: String, pos := Vector3.ZERO, rot_deg := Vector3.ZERO, sc := 1.0) -> void:
	var n: Node3D = (load(DIR + model + ".gltf") as PackedScene).instantiate()
	n.position = pos
	n.rotation_degrees = rot_deg
	n.scale = Vector3.ONE * sc
	holder.add_child(n)
	# the gold is in the vertex colours ("MI_Trim_Metal_Vertex" multiplies the trim texture by them); Godot's import
	# leaves them off, which made the coins silver
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		for si in m3.mesh.get_surface_count():
			var mat := m3.get_active_material(si)
			if mat is StandardMaterial3D and str(mat.resource_name).contains("Vertex"):
				var mm := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				mm.vertex_color_use_as_albedo = true
				mm.vertex_color_is_srgb = not model.begins_with("Coin")     # the coins' gold is linear, the pouch's leather sRGB
				m3.set_surface_override_material(si, mm)

func _fit(pitch_deg: float, yaw_deg: float, margin: float) -> void:
	var box := AABB()
	var first := true
	for mi in holder.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	var c := box.get_center()
	var r := box.size.length() * 0.5
	var dist := r / sin(deg_to_rad(cam.fov * 0.5)) * margin
	var dir := Vector3(0, 0, 1).rotated(Vector3.RIGHT, deg_to_rad(-pitch_deg)).rotated(Vector3.UP, deg_to_rad(yaw_deg))
	var eye := c + dir * dist
	cam.transform = Transform3D(Basis.looking_at(c - eye, Vector3.UP), eye)

func _shot(name: String) -> void:
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://assets/ui/currency/%s.png" % name))
	print("GOLD_ICON ", name)
	for c in holder.get_children():
		c.queue_free()
	await process_frame

func _run() -> void:
	# one coin, stood up on its edge and turned so its face catches the light
	_add("Coin", Vector3.ZERO, Vector3(-14, -34, 8))
	_fit(12.0, -10.0, 0.98)
	await _shot("coin")
	# a small pile
	_add("Coin_Pile")
	_fit(32.0, -24.0, 0.86)
	await _shot("coins_s")
	# a bigger pile with a coin leaning on it
	_add("Coin_Pile_2", Vector3.ZERO, Vector3(0, 25, 0))
	_add("Coin_Pile", Vector3(0.03, 0.0, -0.03), Vector3(0, 70, 0))
	_fit(30.0, -24.0, 0.7)
	await _shot("coins_m")
	# the big stash: a hoard of piles and stacks (the MegaKit pouch's pale leather read as a bag of flour)
	_add("Coin_Pile_2", Vector3.ZERO, Vector3(0, 10, 0))
	_add("Coin_Pile_2", Vector3(-0.09, 0.0, 0.05), Vector3(0, 130, 0))
	_add("Coin_Pile", Vector3(0.08, 0.0, 0.05), Vector3(0, -30, 0))
	_add("Coin_Pile", Vector3(-0.01, 0.0, -0.07), Vector3(0, 80, 0))
	_add("Coin_Pile", Vector3(0.03, 0.06, 0.0), Vector3(0, 20, 0))
	_fit(30.0, -22.0, 0.66)
	await _shot("coins_l")
	print("GOLD_ICONS_DONE")
	quit(0)
