extends SceneTree
# Renders the currency art from the Meshy models (0.31.105, Kevin: "Make new meshy models for gold, diamonds and ember"
# -- his picks from the concept sheets: gold C, diamonds B, embers B):
#   assets/ui/currency/coin, coins_s, coins_m, coins_l   one coin, a stack, a stack and a pile, a hoard
#   assets/ui/currency/gem, gems                         one diamond, three
#   assets/ui/currency/ember, embers                     one ember (the top bar's counter), three
#   assets/ui/currency/{coin,gem,ember}_spin.png         16 frames of the piece turning, for the pieces that fly into
#                                                        the counters (scripts/app/reward_fly.gd)
# The models (Meshy image-to-3D, textures 1024) live OUTSIDE the Godot project, in art_sources/currency, so they never
# reach the APK; they are read at run time with GLTFDocument. The embers' glow is added afterwards by
# tools/currency_glow.py (a soft orange halo round each ember).
#   Xvfb :98 & DISPLAY=:98 godot --rendering-driver vulkan --path godot -s res://tools/render_currency_icons.gd
const SIZE := 320
const FRAME := 128
const FRAMES := 16
var SRC := ""
var vp: SubViewport
var holder: Node3D
var cam: Camera3D
var models := {}           # name -> the normalised model (a template to duplicate)

func _initialize() -> void:
	SRC = ProjectSettings.globalize_path("res://").path_join("../art_sources/currency/").simplify_path()
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
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_color = Color("#fff4dc")
	key.light_energy = 2.3
	key.rotation_degrees = Vector3(-48, -32, 0)
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color("#ffe2a8")
	rim.light_energy = 1.5
	rim.rotation_degrees = Vector3(-20, 150, 0)
	vp.add_child(rim)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color("#c9d8ff")
	fill.light_energy = 0.55
	fill.rotation_degrees = Vector3(-10, 60, 0)
	vp.add_child(fill)
	cam = Camera3D.new()
	cam.fov = 26.0
	vp.add_child(cam)
	holder = Node3D.new()
	vp.add_child(holder)
	for n in ["coin", "gem", "ember"]:
		models[n] = _load(n)
	_run()

func _load(n: String) -> Node3D:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(SRC.path_join(n + ".glb"), st) != OK:
		push_error("no model " + n)
		quit(1)
	var scene: Node3D = doc.generate_scene(st)
	var box := AABB()
	var first := true
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).transform * (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
		_material(n, mi as MeshInstance3D)
	var wrap := Node3D.new()
	wrap.add_child(scene)
	var s := 1.0 / maxf(box.size[box.get_longest_axis_index()], 0.001)
	scene.scale = Vector3.ONE * s
	scene.position = -box.get_center() * s
	return wrap

func _material(n: String, m: MeshInstance3D) -> void:
	for si in m.mesh.get_surface_count():
		var src := m.mesh.surface_get_material(si) as StandardMaterial3D
		if src == null:
			continue
		var mat := src.duplicate() as StandardMaterial3D
		match n:
			"coin":
				mat.metallic = 0.3
				mat.roughness = 0.34
				mat.metallic_specular = 0.8
			"gem":
				mat.metallic = 0.0
				mat.roughness = 0.28
				mat.metallic_specular = 0.45
				mat.rim_enabled = true
				mat.rim = 0.25
				mat.rim_tint = 0.6
				mat.albedo_color = Color(0.62, 0.82, 1.0)
			"ember":
				# the rock a little darker; the molten cracks added on top, unlit (an emission texture came out as
				# plain white emission here)
				mat.roughness = 0.85
				mat.albedo_color = Color(0.42, 0.4, 0.4)
				var hot := StandardMaterial3D.new()
				hot.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				hot.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
				hot.albedo_texture = _hot(mat.albedo_texture)
				hot.albedo_color = Color(2.2, 1.6, 1.1)
				mat.next_pass = hot
		m.set_surface_override_material(si, mat)

func _hot(tex: Texture2D) -> Texture2D:
	# the molten cracks only: the orange-yellow texels, by how red and how little blue they are
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.resize(512, 512)
	img.convert(Image.FORMAT_RGB8)
	var out := Image.create(512, 512, false, Image.FORMAT_RGB8)
	for y in 512:
		for x in 512:
			var c := img.get_pixel(x, y)
			var k := smoothstep(0.55, 0.85, c.r) * smoothstep(0.3, 0.55, c.r - c.b)
			out.set_pixel(x, y, Color(c.r * k, c.g * k, c.b * k))
	return ImageTexture.create_from_image(out)

func _add(n: String, pos := Vector3.ZERO, rot_deg := Vector3.ZERO, sc := 1.0) -> Node3D:
	var m: Node3D = (models[n] as Node3D).duplicate()
	m.position = pos
	m.rotation_degrees = rot_deg
	m.scale = Vector3.ONE * sc
	holder.add_child(m)
	return m

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

func _grab() -> Image:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	return vp.get_texture().get_image()

func _shot(name: String) -> void:
	var img: Image = await _grab()
	img.save_png(ProjectSettings.globalize_path("res://assets/ui/currency/%s.png" % name))
	print("CURRENCY_ICON ", name)
	_clear()

func _clear() -> void:
	for c in holder.get_children():
		holder.remove_child(c)
		c.queue_free()

func _spin(n: String, tilt: Vector3, axis: Vector3, pitch: float) -> void:
	# FRAMES views of one piece turning once about axis, in a strip
	vp.size = Vector2i(FRAME, FRAME)
	var strip := Image.create(FRAME * FRAMES, FRAME, false, Image.FORMAT_RGBA8)
	var spin := Node3D.new()
	holder.add_child(spin)
	var piece: Node3D = (models[n] as Node3D).duplicate()
	piece.rotation_degrees = tilt
	spin.add_child(piece)
	# frame the piece's whole turn: fit on its bounding sphere
	cam.transform = Transform3D(Basis.looking_at(Vector3(0, -sin(deg_to_rad(pitch)), -cos(deg_to_rad(pitch))), Vector3.UP),
		Vector3(0, sin(deg_to_rad(pitch)), cos(deg_to_rad(pitch))) * (0.62 / sin(deg_to_rad(cam.fov * 0.5))))
	for f in FRAMES:
		spin.basis = Basis(axis.normalized(), TAU * f / FRAMES)
		var img: Image = await _grab()
		img.convert(Image.FORMAT_RGBA8)
		strip.blit_rect(img, Rect2i(0, 0, FRAME, FRAME), Vector2i(f * FRAME, 0))
	strip.save_png(ProjectSettings.globalize_path("res://assets/ui/currency/%s_spin.png" % n))
	print("CURRENCY_SPIN ", n)
	_clear()
	vp.size = Vector2i(SIZE, SIZE)

func _run() -> void:
	# ---- gold: the coin's face is its Z
	_add("coin", Vector3.ZERO, Vector3(-8, -28, 6))
	_fit(10.0, -8.0, 0.64)
	await _shot("coin")
	for i in 4:                                        # a short stack, slightly uneven
		_add("coin", Vector3(randf_range(-0.03, 0.03), i * 0.235, randf_range(-0.03, 0.03)), Vector3(90 + randf_range(-3, 3), randf_range(0, 360), randf_range(-3, 3)))
	_fit(26.0, -18.0, 0.8)
	await _shot("coins_s")
	seed(7)
	for i in 5:                                        # a stack ...
		_add("coin", Vector3(-0.32 + randf_range(-0.02, 0.02), i * 0.235, randf_range(-0.02, 0.02)), Vector3(90 + randf_range(-4, 4), randf_range(0, 360), 0))
	for p in [Vector3(0.3, 0.12, 0.1), Vector3(0.62, 0.12, -0.15), Vector3(0.42, 0.32, -0.05), Vector3(0.25, 0.12, -0.42)]:
		_add("coin", p, Vector3(90 + randf_range(-25, 25), randf_range(0, 360), randf_range(-20, 20)))
	_add("coin", Vector3(0.05, 0.42, 0.32), Vector3(-15, 20, 0))      # ... and one leaning on the pile
	_fit(24.0, -18.0, 0.78)
	await _shot("coins_m")
	seed(11)
	var heap := []                                     # a hoard: rings of coins round a mound, more on top
	for ring in [[0.0, 1, 0.9], [0.32, 6, 0.62], [0.62, 10, 0.32], [0.9, 13, 0.1]]:
		for k in int(ring[1]):
			var a := TAU * k / float(ring[1]) + randf() * 0.4
			heap.append([Vector3(cos(a) * float(ring[0]), float(ring[2]), sin(a) * float(ring[0])), Vector3(90 + randf_range(-35, 35), randf_range(0, 360), randf_range(-30, 30))])
	for h in heap:
		_add("coin", h[0], h[1])
	_add("coin", Vector3(-0.15, 0.95, 0.6), Vector3(-20, -15, 5))
	_add("coin", Vector3(0.75, 0.55, 0.55), Vector3(-30, 35, -8))
	_fit(26.0, -18.0, 0.72)
	await _shot("coins_l")
	# ---- diamonds: the table is +Y
	_add("gem", Vector3.ZERO, Vector3(4, -18, 0))
	_fit(6.0, 0.0, 0.74)
	await _shot("gem")
	_add("gem", Vector3(-0.28, 0.0, 0.0), Vector3(8, -20, -14), 1.0)
	_add("gem", Vector3(0.48, -0.16, 0.2), Vector3(-6, 30, 18), 0.72)
	_add("gem", Vector3(0.18, -0.28, 0.62), Vector3(18, 10, 4), 0.55)
	_fit(14.0, 0.0, 0.8)
	await _shot("gems")
	# ---- embers
	_add("ember", Vector3.ZERO, Vector3(0, -20, 0))
	_fit(14.0, 0.0, 0.76)
	await _shot("ember")
	_add("ember", Vector3(-0.42, 0.0, 0.0), Vector3(0, 30, 0), 0.9)
	_add("ember", Vector3(0.42, 0.0, 0.05), Vector3(0, -40, 10), 0.85)
	_add("ember", Vector3(0.0, 0.62, -0.05), Vector3(10, 80, 0), 0.82)
	_fit(14.0, 0.0, 0.8)
	await _shot("embers")
	# ---- the pieces that fly into the counters, turning
	await _spin("coin", Vector3(0, 0, 0), Vector3.UP, 8.0)
	await _spin("gem", Vector3(6, 0, 0), Vector3.UP, 8.0)
	await _spin("ember", Vector3(0, 0, 0), Vector3(0.4, 1.0, 0.25), 10.0)
	print("CURRENCY_ICONS_DONE")
	quit(0)
