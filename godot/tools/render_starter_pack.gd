extends SceneTree
# The Starter Pack's picture (0.31.214, Kevin: "Show the starter pack on the front page and make sure it's eye-catching
# and has pretty graphics that doesn't look like AI made it"): a 3D render, the way the app icon is made
# (tools/render_app_icon.gd) -- the game's own gold chest (assets/ui/v2/chests/gold.scn, its lid thrown open) heaped
# with gold coins, blue gems on the pile and spilling onto the ground in front, and a Hero Token (a purple enamel
# medallion, a gold rim, a gold star) leaning on its side: what the pack holds (gems, gold, a Hero Token). The coins,
# gems and token are built here (their shapes are code: a coin is a milled disc, a gem a brilliant cut -- table, crown,
# girdle, pavilion -- with flat facets); lit like a product shot: a warm key with soft shadows, a cool fill, a gold
# light inside the chest so the heap glows, two rims; ambient occlusion between the coins; a shadow-only ground (its
# shadows are the picture's only ground). Clear background, the card behind it is the game's UI.
#   Xvfb :98 -screen 0 1280x1280x24 &
#   DISPLAY=:98 godot --rendering-method forward_plus --path godot -s res://tools/render_starter_pack.gd
#   OUT=<png> (default /tmp/starter_pack.png)  W=1600 H=1340  SEED=7  (framing: CAM=x,y,z AIM=x,y,z FOV=deg)
#   WEBP=<path>: also the game's copy -- cropped to what's drawn (a small margin), WEBP_W wide (default 1024), lossy q90
#   (the game's: WEBP=res://assets/ui/v2/offer/starter_pack.webp)
#   SHOT=gems | gold | token: the window's three icons instead, in the same light (W=H=800, WEBP_W=256):
#   res://assets/ui/v2/offer/<shot>.webp
const View = preload("res://scripts/siege/siege_view.gd")

var out := "/tmp/starter_pack.png"
var w := 1600
var h := 1340
var vp: SubViewport
var rng := RandomNumberGenerator.new()
var frames := 0
var gold_mat: StandardMaterial3D
var gem_mats: Array = []

func _initialize() -> void:
	out = OS.get_environment("OUT") if OS.has_environment("OUT") else out
	w = int(_num("W", w))
	h = int(_num("H", h))
	rng.seed = int(_num("SEED", 7))
	RenderingServer.directional_shadow_atlas_set_size(8192, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_ULTRA)
	RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_ULTRA)
	vp = SubViewport.new()
	vp.size = Vector2i(w, h)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_8X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	_env()
	_lights()
	_materials()
	var cam := Camera3D.new()
	vp.add_child(cam)
	match OS.get_environment("SHOT"):
		"gems":                                    # three gems, the big one in front
			_gem(Vector3(-0.17, 0.0, -0.1), 0.3, gem_mats[1], 18.0)
			_gem(Vector3(0.2, 0.0, -0.06), 0.26, gem_mats[2], 22.0)
			_gem(Vector3(0.0, 0.0, 0.16), 0.36, gem_mats[0], 12.0)
			cam.fov = 24.0
			cam.look_at_from_position(Vector3(0.0, 1.05, 1.9), Vector3(0.0, 0.1, 0.0), Vector3.UP)
		"gold":                                    # three stacks and a few loose coins
			var xfs := []
			for st in [[Vector3(-0.1, 0, -0.08), 7], [Vector3(0.11, 0, -0.04), 5], [Vector3(0.0, 0, 0.14), 3]]:
				for i in int(st[1]):
					var b := Basis(Vector3.UP, rng.randf() * TAU)
					xfs.append(Transform3D(b, (st[0] as Vector3) + Vector3(rng.randf_range(-0.008, 0.008), 0.017 + i * 0.033, rng.randf_range(-0.008, 0.008))))
			for at in [Vector3(-0.28, 0.014, 0.05), Vector3(0.29, 0.014, 0.1), Vector3(-0.15, 0.014, 0.3), Vector3(0.19, 0.014, 0.31)]:
				xfs.append(_tilted(at, 14.0))
			_coins(xfs)
			cam.fov = 24.0
			cam.look_at_from_position(Vector3(0.0, 0.95, 1.55), Vector3(0.0, 0.1, 0.0), Vector3.UP)
		"token":                                   # the Hero Token, upright, a little turned
			_token(Vector3(0.0, -0.27, 0.0), -14.0)
			cam.fov = 22.0
			cam.look_at_from_position(Vector3(0.0, 0.35, 1.6), Vector3(0.0, 0.0, 0.0), Vector3.UP)
		_:
			_chest()
			_heap()
			_spill()
			_token(Vector3(0.8, 0.0, 0.86), -18.0)
			_ground()
			cam.fov = _num("FOV", 25.0)
			cam.look_at_from_position(_v3("CAM", Vector3(0.0, 2.85, 6.5)), _v3("AIM", Vector3(0.0, 0.8, 0.25)), Vector3.UP)

func _process(_d: float) -> bool:
	frames += 1
	if frames == 12:
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		img.save_png(out)
		print("STARTER_PACK_RENDER %s %dx%d" % [out, img.get_width(), img.get_height()])
		if OS.has_environment("WEBP"):
			var r := _solid_rect(img, 12).grow(int(w * 0.012)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
			var c := img.get_region(r)
			var tw := int(_num("WEBP_W", 1024))
			c.resize(tw, int(round(float(c.get_height()) * tw / c.get_width())), Image.INTERPOLATE_LANCZOS)
			var path := OS.get_environment("WEBP")
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
			c.save_webp(path, true, 0.9)
			print("STARTER_PACK_WEBP %s %dx%d" % [path, c.get_width(), c.get_height()])
		quit(0)
	return false

func _solid_rect(img: Image, min_a: int) -> Rect2i:
	# what's drawn, leaving out the faintest edge of the ground's shadow (alpha under min_a of 255)
	var data := img.get_data()
	var iw := img.get_width()
	var ih := img.get_height()
	var x0 := iw
	var y0 := ih
	var x1 := -1
	var y1 := -1
	for y in ih:
		var row := y * iw * 4
		for x in iw:
			if data[row + x * 4 + 3] >= min_a:
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
				y0 = mini(y0, y)
				y1 = maxi(y1, y)
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1) if x1 >= 0 else Rect2i(Vector2i.ZERO, img.get_size())

func _num(k: String, dflt: float) -> float:
	return float(OS.get_environment(k)) if OS.has_environment(k) else dflt

func _v3(k: String, dflt: Vector3) -> Vector3:
	if not OS.has_environment(k):
		return dflt
	var p := OS.get_environment(k).split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2])) if p.size() == 3 else dflt

# ---------------- the studio ----------------
func _env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#d8d2c8")
	env.ambient_light_energy = _num("AMBIENT", 0.38) * View.VULKAN_AMBIENT
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = _num("EXPOSURE", 0.72) * View.VULKAN_EXPOSURE
	env.tonemap_white = 3.0
	env.ssao_enabled = true                          # (between the coins, under the gems, the chest's bands)
	env.ssao_radius = 0.25
	env.ssao_intensity = 1.8
	env.ssao_power = 1.5
	env.ssao_detail = 0.7
	env.ssao_light_affect = 0.2
	var sky := Sky.new()                             # (what the gold and the gems reflect: a warm room, a bright window)
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("#fff6e6")
	sm.sky_horizon_color = Color("#9a6630")
	sm.ground_horizon_color = Color("#3a2412")
	sm.ground_bottom_color = Color("#120a05")
	sm.sky_curve = 0.25
	sm.sun_angle_max = 0.0
	sky.sky_material = sm
	env.sky = sky
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)

func _lights() -> void:
	var key := DirectionalLight3D.new()              # warm, high, from the front left
	key.light_color = Color("#fff0d8")
	key.light_energy = _num("KEY", 1.5)
	key.rotation_degrees = Vector3(-52, -34, 0)
	key.shadow_enabled = true
	key.shadow_blur = 2.0
	key.shadow_bias = 0.015
	key.shadow_normal_bias = 1.0
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key.directional_shadow_max_distance = 8.0
	vp.add_child(key)
	var fill := DirectionalLight3D.new()             # cool, from the right
	fill.light_color = Color("#bcd4ff")
	fill.light_energy = 0.35
	fill.rotation_degrees = Vector3(-15, 58, 0)
	vp.add_child(fill)
	var glow := OmniLight3D.new()                    # the heap's own glow, just over it in the chest
	glow.light_color = Color("#ffc65a")
	glow.light_energy = _num("GLOW", 2.4)
	glow.omni_range = 1.6
	glow.omni_attenuation = 1.4
	glow.position = Vector3(0.0, 1.35, 0.05)
	vp.add_child(glow)
	var spark := OmniLight3D.new()                   # a cool light near the camera: the gems' facets flash
	spark.light_color = Color("#e6f2ff")
	spark.light_energy = _num("SPARK", 2.2)
	spark.omni_range = 8.0
	spark.position = Vector3(1.2, 3.2, 4.4)
	spark.light_specular = 2.0
	vp.add_child(spark)
	var rim_l := OmniLight3D.new()                   # rims: warm behind left, blue behind right
	rim_l.light_color = Color("#ffb45a")
	rim_l.light_energy = 6.0
	rim_l.omni_range = 5.0
	rim_l.position = Vector3(-2.2, 2.0, -2.0)
	vp.add_child(rim_l)
	var rim_r := OmniLight3D.new()
	rim_r.light_color = Color("#8cc8ff")
	rim_r.light_energy = 5.0
	rim_r.omni_range = 5.0
	rim_r.position = Vector3(2.3, 1.6, -1.8)
	vp.add_child(rim_r)

func _materials() -> void:
	gold_mat = StandardMaterial3D.new()
	gold_mat.albedo_color = Color("#ffb22a")
	gold_mat.metallic = 1.0
	gold_mat.roughness = 0.3
	gold_mat.metallic_specular = 0.6
	for col in ["#1d5cff", "#2b78ff", "#1440d8"]:  # (the game's gem is blue: three of its shades)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(col)
		m.metallic = 0.9                          # (its reflections take its blue: deep facets, bright ones)
		m.roughness = 0.06
		m.metallic_specular = 0.8
		m.emission_enabled = true
		m.emission = Color(col).darkened(0.5)
		m.emission_energy_multiplier = 1.0
		gem_mats.append(m)

# ---------------- the chest ----------------
func _chest() -> void:
	var c: Node3D = (load("res://assets/ui/v2/chests/gold.scn") as PackedScene).instantiate()
	vp.add_child(c)
	var lid: Node3D = c.get_node("Lid")
	lid.rotation_degrees.x = -_num("LID", 112.0)    # thrown open, back past upright
	var floor_ := MeshInstance3D.new()               # (the chest is a shell: a dark floor under the heap)
	var bm := BoxMesh.new()
	bm.size = Vector3(1.5, 0.05, 1.22)
	floor_.mesh = bm
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color("#2a1708")
	dm.roughness = 0.9
	floor_.material_override = dm
	floor_.position = Vector3(0, 0.56, 0)
	vp.add_child(floor_)

# ---------------- coins ----------------
func _coin_mesh() -> Mesh:
	# a milled disc: a slight bevel on each face's edge
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 40
	var r := 0.085
	var r2 := 0.074
	var t := 0.011
	var tb := 0.016
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var p0 := Vector3(cos(a0), 0, sin(a0))
		var p1 := Vector3(cos(a1), 0, sin(a1))
		for s in [1.0, -1.0]:
			# face (inner, raised) and its bevel ring
			st.add_vertex(Vector3(0, tb * s, 0))
			if s > 0:
				st.add_vertex(p1 * r2 + Vector3(0, tb * s, 0))
				st.add_vertex(p0 * r2 + Vector3(0, tb * s, 0))
			else:
				st.add_vertex(p0 * r2 + Vector3(0, tb * s, 0))
				st.add_vertex(p1 * r2 + Vector3(0, tb * s, 0))
			var q := [p0 * r2 + Vector3(0, tb * s, 0), p1 * r2 + Vector3(0, tb * s, 0), p1 * r + Vector3(0, t * s, 0), p0 * r + Vector3(0, t * s, 0)]
			if s > 0:
				_quad(st, q[0], q[1], q[2], q[3])
			else:
				_quad(st, q[1], q[0], q[3], q[2])
		# the milled edge
		_quad(st, p0 * r + Vector3(0, t, 0), p1 * r + Vector3(0, t, 0), p1 * r + Vector3(0, -t, 0), p0 * r + Vector3(0, -t, 0))
	st.generate_normals()
	return st.commit()

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)

func _coins(xfs: Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _coin_mesh()
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = gold_mat
	vp.add_child(mmi)

func _tilted(pos: Vector3, max_tilt: float) -> Transform3D:
	var b := Basis(Vector3.UP, rng.randf() * TAU)
	b = Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), deg_to_rad(rng.randf_range(0, max_tilt))) * b
	return Transform3D(b, pos)

func _heap_h(x: float, z: float) -> float:
	# the heap's top: a dome over the chest's mouth, highest a little back of the middle
	var u := x / 0.78
	var v := (z + 0.05) / 0.66
	return 0.66 + 0.30 * maxf(0.0, 1.0 - u * u - v * v)

func _heap() -> void:
	var xfs := []
	for layer in 3:
		for i in 260:
			var x := rng.randf_range(-0.74, 0.74)
			var z := rng.randf_range(-0.6, 0.6)
			var y := _heap_h(x, z) - layer * 0.035 + rng.randf_range(-0.012, 0.012)
			xfs.append(_tilted(Vector3(x, y, z), 38.0))
	_coins(xfs)
	# gems on the heap
	var spots := [Vector3(-0.34, 0.0, 0.08), Vector3(0.16, 0.0, -0.14), Vector3(0.48, 0.0, 0.22), Vector3(-0.02, 0.0, 0.36),
		Vector3(-0.58, 0.0, -0.22)]
	for i in spots.size():
		var s: Vector3 = spots[i]
		_gem(Vector3(s.x, _heap_h(s.x, s.z) + 0.03, s.z), rng.randf_range(0.26, 0.32), gem_mats[i % gem_mats.size()], 28.0)

func _spill() -> void:
	# over the front lip and down the front, then a little heap on the ground in front
	var xfs := []
	for i in 7:                                    # (a few tipping over the front lip)
		var x := rng.randf_range(-0.6, 0.6)
		xfs.append(_tilted(Vector3(x, 0.70 + rng.randf_range(0.0, 0.03), 0.66 + rng.randf_range(0.0, 0.06)), 55.0))
	for i in 70:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * 0.42
		var x := -0.12 + cos(a) * d * 1.4
		var z := 1.05 + sin(a) * d * 0.55
		var y := 0.012 + maxf(0.0, 0.09 - d * 0.2) * rng.randf()
		xfs.append(_tilted(Vector3(x, y, z), 25.0))
	_coins(xfs)
	_gem(Vector3(-0.66, 0.12, 1.0), 0.3, gem_mats[1], 35.0)
	_gem(Vector3(0.26, 0.1, 1.24), 0.24, gem_mats[0], 45.0)
	_gem(Vector3(-1.02, 0.08, 0.6), 0.2, gem_mats[2], 50.0)

# ---------------- gems ----------------
func _gem_mesh() -> Mesh:
	# a brilliant cut, 8 sides: the table, the crown's facets, the girdle, the pavilion to its point
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)                          # (flat facets)
	var n := 8
	var tr := 0.55
	var ty := 0.32
	var gr := 1.0
	var gy := 0.0
	var py := -0.95
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var am := (a0 + a1) * 0.5
		var t0 := Vector3(cos(a0) * tr, ty, sin(a0) * tr)
		var t1 := Vector3(cos(a1) * tr, ty, sin(a1) * tr)
		var g0 := Vector3(cos(a0) * gr, gy, sin(a0) * gr)
		var g1 := Vector3(cos(a1) * gr, gy, sin(a1) * gr)
		var gm := Vector3(cos(am) * gr * 1.02, gy + 0.08, sin(am) * gr * 1.02)
		# table
		st.add_vertex(Vector3(0, ty, 0))
		st.add_vertex(t1)
		st.add_vertex(t0)
		# crown: two facets a side (the kite split)
		st.add_vertex(t0)
		st.add_vertex(t1)
		st.add_vertex(gm)
		st.add_vertex(t0)
		st.add_vertex(gm)
		st.add_vertex(g0)
		st.add_vertex(t1)
		st.add_vertex(g1)
		st.add_vertex(gm)
		# pavilion
		st.add_vertex(g0)
		st.add_vertex(gm)
		st.add_vertex(Vector3(0, py, 0))
		st.add_vertex(gm)
		st.add_vertex(g1)
		st.add_vertex(Vector3(0, py, 0))
	st.generate_normals()
	return st.commit()

var _gm: Mesh = null

func _gem(pos: Vector3, size: float, mat: Material, tilt: float) -> void:
	if _gm == null:
		_gm = _gem_mesh()
	var mi := MeshInstance3D.new()
	mi.mesh = _gm
	mi.material_override = mat
	var xf := _tilted(Vector3.ZERO, tilt)
	xf.basis = xf.basis.scaled(Vector3.ONE * size * 0.5)
	xf.origin = pos + Vector3(0, size * 0.25, 0)
	mi.transform = xf
	vp.add_child(mi)

# ---------------- the Hero Token ----------------
func _token(at: Vector3, turn: float) -> void:
	var t := Node3D.new()
	vp.add_child(t)
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.24
	cm.bottom_radius = 0.24
	cm.height = 0.05
	cm.radial_segments = 64
	disc.mesh = cm
	var em := StandardMaterial3D.new()
	em.albedo_color = Color("#7b3fe0")
	em.metallic = 0.25
	em.roughness = 0.22
	em.clearcoat_enabled = true
	em.clearcoat = 0.8
	disc.material_override = em
	t.add_child(disc)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.215
	tm.outer_radius = 0.275
	tm.rings = 64
	tm.ring_segments = 16
	ring.mesh = tm
	ring.material_override = gold_mat
	t.add_child(ring)
	var star := MeshInstance3D.new()
	star.mesh = _star_mesh(0.15, 0.065, 0.03)
	var sm2: StandardMaterial3D = gold_mat.duplicate()
	sm2.cull_mode = BaseMaterial3D.CULL_DISABLED
	star.material_override = sm2
	star.position = Vector3(0, 0.025, 0)
	t.add_child(star)
	# stood on its edge, leaning back against the chest, turned to the camera (its own shot: upright)
	t.rotation_degrees = Vector3(72.0 if OS.get_environment("SHOT") != "token" else 90.0, turn, 0.0)
	t.position = at + Vector3(0, 0.27, 0)

func _star_mesh(ro: float, ri: float, depth: float) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var pts := []
	for i in 10:
		var a := -PI * 0.5 + TAU * i / 10.0
		var r := ro if i % 2 == 0 else ri
		pts.append(Vector3(cos(a) * r, 0, sin(a) * r))
	var top := Vector3(0, depth, 0)
	for i in 10:
		var p0: Vector3 = pts[i]
		var p1: Vector3 = pts[(i + 1) % 10]
		st.add_vertex(top)                        # (a low pyramid: each point's two facets catch the light)
		st.add_vertex(p1)
		st.add_vertex(p0)
	st.generate_normals()
	return st.commit()

# ---------------- the ground: shadows only ----------------
func _ground() -> void:
	# a soft dark pool under it all (an unlit quad on the ground, darkest under the chest)
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(3.6, 2.3)
	g.mesh = pm
	var sh := Shader.new()
	sh.code = "shader_type spatial;\nrender_mode unshaded, blend_mix, depth_draw_never, cull_disabled;\nvoid fragment() {\n\tvec2 d = (UV - vec2(0.5, 0.46)) * vec2(2.0, 2.0);\n\tfloat r = length(d);\n\tALBEDO = vec3(0.06, 0.03, 0.01);\n\tALPHA = 0.8 * pow(clamp(1.0 - r, 0.0, 1.0), 1.25);\n}\n"
	var m := ShaderMaterial.new()
	m.shader = sh
	g.material_override = m
	g.position = Vector3(-0.05, 0.002, 0.62)
	vp.add_child(g)
