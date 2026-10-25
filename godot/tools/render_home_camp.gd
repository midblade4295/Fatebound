extends SceneTree
# Home's camp as a 3D render of the game's own models (0.31.215, Kevin: "I want the home screen as good of quality as the
# clan screen. The home screen looks very AI generated." -> picked "Real 3D heroes in camp"). Until now Home's backdrop
# was a painting (tools/home_camp.py, gpt-image: six chibi champions round a fire). This builds the same idea from the
# game's real pieces and renders it with the desktop renderer (soft shadows, ambient occlusion, bloom):
#   - the castle at dusk: the Royal kit's gatehouse between two towers and its walls (scripts/siege/castle_kit.gd, the
#     blue side's), the keep's banners, firs and oaks of the 5v5 map either side (assets/meshy/foliage);
#   - the war camp in front of it: the War kit's tents, braziers, supplies and weapon rack; the Royal banners;
#   - the campfire: a ring of the forest kit's rocks round crossed logs, its light the scene's warm key;
#   - the heroes round it: the HD Knight, Barbarian, Mage and Stormcaller (tools/meshy_hd.py, from the game's own models)
#     and the King behind the fire;
#   - a dusk sky (indigo to a warm horizon); the stars, the fire's flames, embers and smoke, the braziers' and torches'
#     flicker are drawn live over it by scripts/app/camp_scene.gd.
# Writes assets/ui/v2/bg_camp.webp (1024 x 2048, as the painting was) and prints the points camp_scene.gd needs, in the
# picture's px (CAMP_POINTS {...}): the fire, its base, the lamps (braziers), the feet line, the sky and camp areas,
# the banners' cloth.
#   Xvfb :98 -screen 0 1280x1280x24 &
#   DISPLAY=:98 godot --rendering-method forward_plus --path godot -s res://tools/render_home_camp.gd
#   OUT=<png> (default /tmp/home_camp.png)  WEBP=res://assets/ui/v2/bg_camp.webp  SS=1.5 (supersampling)
#   (framing: CAM=x,y,z AIM=x,y,z FOV=deg)
const View = preload("res://scripts/siege/siege_view.gd")
const Stage = preload("res://scripts/siege/asset_cache.gd")
const CastleKit = preload("res://scripts/siege/castle_kit.gd")

const PAINT := Vector2i(1024, 2048)

var out := "/tmp/home_camp.png"
var ss := 1.5
var vp: SubViewport
var cam: Camera3D
var frames := 0
var rng := RandomNumberGenerator.new()
var points := {}
var _lamps3: Array = []                # brazier flames (3D) -> camp_scene LAMPS
var _banners3: Array = []              # [Node3D, size] -> cloth rects

func _initialize() -> void:
	out = OS.get_environment("OUT") if OS.has_environment("OUT") else out
	ss = _num("SS", ss)
	rng.seed = 215
	RenderingServer.directional_shadow_atlas_set_size(8192, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_ULTRA)
	RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_ULTRA)
	vp = SubViewport.new()
	vp.size = Vector2i(int(PAINT.x * ss), int(PAINT.y * ss))
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_8X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	_env()
	_lights()
	_ground()
	_castle()
	_camp()
	_campfire()
	_heroes()
	cam = Camera3D.new()
	cam.fov = _num("FOV", 48.0)
	cam.far = 400.0
	vp.add_child(cam)
	cam.look_at_from_position(_v3("CAM", Vector3(0.0, 1.75, 9.0)), _v3("AIM", Vector3(0.0, 0.6, -2.0)), Vector3.UP)

func _process(_d: float) -> bool:
	frames += 1
	if frames == 16:
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		img.resize(PAINT.x, PAINT.y, Image.INTERPOLATE_LANCZOS)
		img.save_png(out)
		print("HOME_CAMP_RENDER ", out)
		if OS.has_environment("WEBP"):
			var p := OS.get_environment("WEBP")
			img.save_webp(p, true, 0.92)
			print("HOME_CAMP_WEBP ", p)
		_points()
		quit(0)
	return false

func _num(k: String, dflt: float) -> float:
	return float(OS.get_environment(k)) if OS.has_environment(k) else dflt

func _v3(k: String, dflt: Vector3) -> Vector3:
	if not OS.has_environment(k):
		return dflt
	var p := OS.get_environment(k).split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2])) if p.size() == 3 else dflt

# ---------------- light ----------------
func _env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()           # dusk: deep indigo overhead, violet, a warm band low down
	sm.sky_top_color = Color("#070a26")
	sm.sky_horizon_color = Color("#7a3560")
	sm.sky_curve = 0.06
	sm.ground_horizon_color = Color("#2a1830")
	sm.ground_bottom_color = Color("#0a0812")
	sm.sun_angle_max = 0.0
	sm.sky_energy_multiplier = 1.0
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#4a5690")
	env.ambient_light_energy = _num("AMBIENT", 0.2) * View.VULKAN_AMBIENT
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = _num("EXPOSURE", 1.0) * View.VULKAN_EXPOSURE
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 0.6
	env.ssao_intensity = 1.6
	env.ssao_power = 1.5
	env.ssao_light_affect = 0.15
	env.glow_enabled = true                            # (the fires, the windows)
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true                             # dusk haze: the castle further off than the camp
	env.fog_light_color = Color("#2a2140")
	env.fog_density = _num("FOG", 0.004)
	env.fog_sky_affect = 0.0
	env.fog_height = 6.0
	env.fog_height_density = 0.15
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)

func _lights() -> void:
	var moon := DirectionalLight3D.new()               # the last of the dusk: cool, from behind left, high
	moon.light_color = Color("#9fb4ff")
	moon.light_energy = _num("MOON", 0.7)
	moon.rotation_degrees = Vector3(-38, 150, 0)
	moon.shadow_enabled = true
	moon.shadow_blur = 2.0
	moon.directional_shadow_max_distance = 40.0
	vp.add_child(moon)
	var front := DirectionalLight3D.new()              # a faint cool fill from the front, so faces aren't lost
	front.light_color = Color("#8ea0e0")
	front.light_energy = 0.18
	front.rotation_degrees = Vector3(-20, 8, 0)
	vp.add_child(front)

func _omni(at: Vector3, col: Color, energy: float, reach: float, shadows := false) -> OmniLight3D:
	var o := OmniLight3D.new()
	o.position = at
	o.light_color = col
	o.light_energy = energy
	o.omni_range = reach
	o.omni_attenuation = 1.2
	o.shadow_enabled = shadows
	o.shadow_blur = 1.5
	vp.add_child(o)
	return o

# ---------------- the ground ----------------
func _ground() -> void:
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(160, 160)
	g.mesh = pm
	var m := StandardMaterial3D.new()
	var tex: Texture2D = Stage.texture("res://assets/meshy/castle/floors/war_earth.jpg")
	m.albedo_texture = tex
	m.albedo_color = Color("#8a7660")
	m.uv1_scale = Vector3(40, 40, 1)
	m.roughness = 0.95
	g.material_override = m
	vp.add_child(g)
	# a paved road from the camp up to the gate (the court's stone)
	var court := MeshInstance3D.new()
	var cm := PlaneMesh.new()
	cm.size = Vector2(5, 22)
	court.mesh = cm
	var c := StandardMaterial3D.new()
	c.albedo_texture = Stage.texture("res://assets/meshy/castle/floors/royal_court.jpg")
	c.albedo_color = Color("#7c746c")
	c.uv1_scale = Vector3(1.5, 5, 1)
	c.roughness = 0.9
	court.material_override = c
	court.position = Vector3(0, 0.01, -22.0)
	vp.add_child(court)
	# grass tufts and pebbles about the camp
	for i in 70:
		var x := rng.randf_range(-14.0, 14.0)
		var z := rng.randf_range(-14.0, 6.0)
		if absf(x) < 3.2 and z > -5.0:
			continue
		_scene("res://assets/kaykit/forest/Grass_%d_%s_Color1.gltf" % [rng.randi_range(1, 2), ["A", "B", "C"][rng.randi() % 3]],
			Vector3(x, 0, z), rng.randf_range(0.8, 1.5), rng.randf() * 360.0)

func _scene(path: String, at: Vector3, s: float, turn := 0.0) -> Node3D:
	var packed: PackedScene = Stage.scene(path)
	if packed == null:
		print("HOME_CAMP_MISSING ", path)
		return null
	var n: Node3D = packed.instantiate()
	n.position = at
	n.scale = Vector3.ONE * s
	n.rotation_degrees.y = turn
	vp.add_child(n)
	return n

# ---------------- the castle ----------------
func _piece(model: String, at: Vector3, height: float, turn := 0.0) -> Node3D:
	var p := CastleKit.piece(model, 0)
	var size: Vector3 = p.get_meta("size")
	p.position = at
	p.rotation_degrees.y = turn
	p.scale = Vector3.ONE * (height / maxf(0.01, size.y))
	vp.add_child(p)
	return p

func _castle() -> void:
	var z := -32.0
	_piece("royal_gatehouse", Vector3(0, 0, z), 10.0)
	_piece("royal_tower", Vector3(-11.5, 0, z + 0.5), 12.0)
	_piece("royal_tower", Vector3(11.5, 0, z + 0.5), 12.0)
	for x in [-6.4, 6.4, -17.5, 17.5]:
		_piece("royal_wall", Vector3(x, 0, z), 6.0)
	_piece("royal_tower", Vector3(-23.0, 0, z + 2.0), 10.0)
	_piece("royal_tower", Vector3(23.0, 0, z + 2.0), 10.0)
	# torches either side of the gate
	for x in [-3.6, 3.6]:
		_piece("war_brazier", Vector3(x, 0, z + 3.2), 1.6)
		_lamps3.append(Vector3(x, 1.6 * 0.95, z + 3.2))
		_omni(Vector3(x, 1.9, z + 3.6), Color("#ff9a45"), 2.2, 6.0)
	# the woods either side, darker further off
	for i in 16:
		var side := -1.0 if i % 2 == 0 else 1.0
		var x := side * rng.randf_range(13.0, 30.0)
		var zz := rng.randf_range(-36.0, -10.0)
		var kind: String = ["tree_fir", "tree_oak", "tree_fir", "tree_mossy"][rng.randi() % 4]
		_scene("res://assets/meshy/foliage/%s.glb" % kind, Vector3(x, 0, zz), rng.randf_range(2.6, 4.2), rng.randf() * 360.0)

# ---------------- the camp ----------------
func _camp() -> void:
	_piece("war_tent", Vector3(-3.5, 0, -7.6), 3.2, 35.0)
	_piece("war_tent", Vector3(3.6, 0, -7.9), 3.2, -35.0)
	_piece("war_supplies", Vector3(-3.4, 0, -3.6), 1.3, 70.0)
	_piece("war_weapon_rack", Vector3(3.5, 0, -3.9), 1.7, -60.0)
	for x in [-2.6, 2.6]:
		var b := _piece("royal_banner", Vector3(x, 0, -8.6), 4.6, 0.0)
		_banners3.append(b)
	for x in [-2.9, 2.9]:
		_piece("war_brazier", Vector3(x, 0, -4.4), 1.4)
		_lamps3.append(Vector3(x, 1.4 * 0.95, -4.4))
		_omni(Vector3(x, 1.7, -4.1), Color("#ff9a45"), 2.4, 6.0)

# ---------------- the campfire ----------------
func _campfire() -> void:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color("#77706a")
	stone.roughness = 0.92
	for i in 12:                                       # (a ring of rounded stones)
		var a := TAU * i / 12.0 + rng.randf_range(-0.08, 0.08)
		var st := MeshInstance3D.new()
		var sp := SphereMesh.new()
		var r := rng.randf_range(0.12, 0.16)
		sp.radius = r
		sp.height = r * 1.3
		st.mesh = sp
		st.material_override = stone
		st.position = Vector3(cos(a) * 0.68, r * 0.42, sin(a) * 0.68)
		st.rotation = Vector3(rng.randf_range(-0.2, 0.2), rng.randf() * TAU, rng.randf_range(-0.2, 0.2))
		st.scale = Vector3(rng.randf_range(1.0, 1.35), 1.0, rng.randf_range(0.9, 1.2))
		vp.add_child(st)
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color("#4a2e1a")
	bark.roughness = 0.95
	for i in 4:
		var log := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.075
		cm.bottom_radius = 0.09
		cm.height = 0.95
		log.mesh = cm
		log.material_override = bark
		var a := TAU * i / 4.0 + 0.4
		log.rotation = Vector3(deg_to_rad(62), a, 0)
		log.position = Vector3(cos(a) * 0.14, 0.24, sin(a) * 0.14)
		vp.add_child(log)
	var coals := MeshInstance3D.new()                  # the bed of embers, glowing
	var sm := SphereMesh.new()
	sm.radius = 0.45
	sm.height = 0.24
	coals.mesh = sm
	var em := StandardMaterial3D.new()
	em.albedo_color = Color("#3a1606")
	em.emission_enabled = true
	em.emission = Color("#ff6a1a")
	em.emission_energy_multiplier = 2.4
	coals.material_override = em
	coals.position = Vector3(0, 0.02, 0)
	vp.add_child(coals)
	_omni(Vector3(0, 1.0, 0.2), Color("#ff8c3a"), _num("FIRE", 9.0), 11.0, true)     # the fire: the camp's key light
	_omni(Vector3(0, 0.4, 1.2), Color("#ff7a2a"), 1.6, 5.0)                          # (its glow low on the ground)
	points["fire3"] = Vector3(0, 0.9, 0)
	points["fire_base3"] = Vector3(0, 0.25, 0.35)

# ---------------- the heroes ----------------
func _hd(path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(path), st) != OK:
		print("HOME_CAMP_NO_HD ", path)
		return null
	var m: Node3D = doc.generate_scene(st)
	var box := AABB()
	var first := true
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	var fit := {"height": View.KING_HEIGHT, "bottom": 0.0, "x": 0.0, "z": 0.0}
	var jp := ProjectSettings.globalize_path(path.get_base_dir().path_join(path.get_file().replace("_hd.glb", "_views.json")))
	if FileAccess.file_exists(jp):
		var j = JSON.parse_string(FileAccess.get_file_as_string(jp))
		if j is Dictionary:
			fit.merge(j, true)
	var k := float(fit.height) / box.size.y
	var r := Node3D.new()
	m.scale = Vector3.ONE * k
	m.position = Vector3(-box.get_center().x * k, -box.position.y * k, -box.get_center().z * k)
	r.add_child(m)
	vp.add_child(r)
	return r

func _hero(name: String, at: Vector3, turn: float) -> void:
	points["feet_" + name] = at
	if OS.get_environment("NOHD") == "1":             # (framing: a 2 m capsule for each)
		var c := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.height = 2.6 if name == "king" else 2.0
		cm.radius = 0.45
		c.mesh = cm
		c.position = at + Vector3(0, cm.height * 0.5, 0)
		vp.add_child(c)
		return
	var path := "res://../art_sources/app_icon/king_hd/king_hd.glb" if name == "king" else "res://../art_sources/store_heroes/%s/%s_hd.glb" % [name, name]
	var h := _hd(path)
	if h != null:
		h.position = at
		h.rotation_degrees.y = turn
		points["feet_" + name] = at

func _heroes() -> void:
	# round the fire, facing out to us a little turned to it; the King behind the fire
	# (a V: the King at the back behind the fire, two either side of it, two nearest us out at the sides, cut by the
	# picture's edges as a painter would frame them)
	# (on the picture, as fractions of its half-width: the King 0, the middle pair +-0.43, the front pair +-0.8 -- each
	# a little in front of the one inside it, so all five show)
	_hero("king", Vector3(0.05, 0, -2.6), 0.0)
	_hero("mage", Vector3(-1.0, 0, -1.6), 22.0)
	_hero("stormcaller", Vector3(1.02, 0, -1.65), -22.0)
	_hero("knight", Vector3(-1.44, 0, 1.0), 42.0)
	_hero("barbarian", Vector3(1.46, 0, 1.0), -42.0)

# ---------------- what camp_scene.gd needs ----------------
func _px(p: Vector3) -> Vector2:
	var v := cam.unproject_position(p)
	return v / ss

func _points() -> void:
	var out_p := {}
	out_p["fire"] = _px(points.fire3)
	out_p["fire_base"] = _px(points.fire_base3)
	var lamps := []
	for l in _lamps3:
		lamps.append(_px(l))
	out_p["lamps"] = lamps
	var feet := 0.0
	for k in points:
		if str(k).begins_with("feet_"):
			feet = maxf(feet, _px(points[k]).y)
	out_p["feet_y"] = feet
	out_p["horizon_y"] = _px(Vector3(0, 0, -60)).y
	var cloth := []
	for b in _banners3:
		var n: Node3D = b
		var size: Vector3 = n.get_meta("size")
		var s := n.scale.x
		# the cloth hangs from about the top 20% down to 70% of the banner's height, its width about 70% of it
		var a := _px(n.position + Vector3(-size.x * s * 0.33, size.y * s * 0.92, 0))
		var c := _px(n.position + Vector3(size.x * s * 0.33, size.y * s * 0.35, 0))
		cloth.append([a.x, a.y, c.x, c.y])
	out_p["banners"] = cloth
	print("CAMP_POINTS ", JSON.stringify(out_p))
