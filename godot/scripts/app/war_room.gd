extends Control
# 0.31.138 (Kevin: "Design a home screen that shows the camera overlooking the live map and then you can see the
# castles/land in the background. You'll see some heroes standing next to the map table looking at it"; he picked the
# war room concept): Home's war table in 3D, standing on the painted room's rug (home_scene.gd lays the painting and
# this out together). An oak table holding the live war map -- the war map's own land, sea, forests and Meshy
# miniatures (war_land_view.gd), each place in its holder's colour, battles pulsing -- with candles on its rim, and four
# heroes in the player's equipped looks standing round it studying the map: the Barbarian and the Mage beyond it, the
# Knight and the Ranger at its near corners (the concept's four; the Barbarian on the left, his axe clear of the
# Mage's staff). The table is an oval, longer away from you than across, so the land (12 x 18, north to south away
# from you as on the war map) fills it.
# One transparent SubViewport at physical resolution over the band of the painting the table and heroes take up,
# drawn every 2nd frame.
#
# Framing, in the painting's pixels (bg_war_room.webp is 1152 wide): this control covers the painting's rows FRAME.y
# to FRAME.end.y, all its width, and the table top's centre is its middle. PX_PER_M (the painting's pixels per metre at
# the table) and CAM_ELEV were fitted to the painted rug (507 x 256 px round its middle, 1352 down), and the table
# stands on it, its foot a little beyond the rug's middle.
const View = preload("res://scripts/siege/siege_view.gd")
const LandView = preload("res://scripts/app/war_land_view.gd")
const WoodShader = preload("res://scripts/app/war_room_wood.gdshader")

const PAINT_W := 1152.0
# 0.31.140 (Kevin: "The screen is cutoff where feet are"): the frame reaches 300 px further down (the near heroes'
# feet and the table's foot, behind the chests), the camera moved down to match (V_SHIFT) so the table still sits 600
# px down it
const FRAME := Rect2(0.0, 430.0, 1152.0, 1500.0)
const TABLE_ROW := 600.0               # the table top's centre, down the frame
const PX_PER_M := 268.6
const CAM_ELEV := 32.0
const CAM_FOV := 30.0                  # across the painting (KEEP_WIDTH)
const TOP_Y := 0.95                    # the table top (the map's sea level), metres off the floor
const MAP_OVAL := Vector2(8.0, 10.3)   # the map's oval in map units, across and away (the whole land is inside it)
const R_MAP := 1.58                    # the map's oval across (metres); away: MAP_OVAL's ratio longer
const RIM := 0.27                      # the rim's width round it
const HERO_SCALE := 0.95
# class, where round the table (degrees from the near side, toward the right), how far out from its edge (metres)
const SPOTS := [["barbarian", 206.0, 0.3], ["mage", 152.0, 0.34], ["knight", -37.0, 0.24], ["ranger", 37.0, 0.24]]
# candles on the rim: where round it (degrees), and each candle's [sideways, inward, height] in metres
const CANDLE_SPOTS := [-100.0, 100.0]
const CANDLES := [[0.0, 0.0, 0.24], [0.075, 0.035, 0.17], [-0.07, 0.03, 0.13]]

var viewport: SubViewport
var world: Node3D
var cam: Camera3D
var land: Node3D                       # the live map (war_land_view.gd); null if its pack is missing
var looks := {}
var calm := false                      # reduce motion: the candles' light holds still
var _built := {}
var _heroes: Node3D
var _lights: Array = []                # [OmniLight3D, base energy, phase]
var wicks: Array[Vector3] = []         # each candle's flame, in the room (home_scene.gd draws the flames over them)
var _clock := 0.0
var _frame := 0
var every := 2                         # the 3D draws every this many frames (the menus run at 60: the table at 30)

static func map_scale() -> float:
	return R_MAP / MAP_OVAL.x

static func oval(d := 0.0) -> Vector2:
	# the table's oval at `d` metres out from the map's edge: its radii across (x) and away (z)
	return Vector2(R_MAP, MAP_OVAL.y * map_scale()) + Vector2(d, d)

static func on_oval(deg: float, d := 0.0) -> Vector3:
	var a := deg_to_rad(deg)
	var o := oval(d)
	return Vector3(sin(a) * o.x, 0.0, cos(a) * o.y)

static func cam_dist() -> float:
	return (PAINT_W * 0.5) / (PX_PER_M * tan(deg_to_rad(CAM_FOV) * 0.5))

static func v_shift() -> float:
	# the camera's move along its own up (Camera3D.v_offset) that puts the table top's centre TABLE_ROW down the frame
	return -(FRAME.size.y * 0.5 - TABLE_ROW) / PX_PER_M

static func row_of(p: Vector3) -> float:
	# where a point of the room lands down this control's frame (painting px from its top), by the camera's own sums
	var e := deg_to_rad(CAM_ELEV)
	var dir := Vector3(0.0, sin(e), cos(e))
	var cam_up := Vector3(0.0, cos(e), -sin(e))
	var v := p - (Vector3(0.0, TOP_Y, 0.0) + dir * cam_dist() + cam_up * v_shift())
	var depth := v.dot(-dir)
	var up := v.dot(cam_up)
	return FRAME.size.y * 0.5 - up / depth * (PAINT_W * 0.5) / tan(deg_to_rad(CAM_FOV) * 0.5)

static func near_row() -> float:
	# the map's near shore (the table's lip nearest you)
	return row_of(Vector3(0.0, TOP_Y, oval().y))

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	# 0.31.142 (Kevin: "Getting freezes during it now", the title screen): no MSAA. A transparent SubViewport with MSAA
	# needs pipelines Godot's pre-compilation doesn't make, so its first frame compiled them on the spot, every start
	# (8 "draw" compiles here; on Kevin's S21 Home's first frame took 4.5 s). The room is drawn at the screen's own
	# pixel density (_resize), where the edges hold up without it; FXAA greyed the transparent edges.
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE   # (then every 2nd frame while seen: _process)
	add_child(viewport)
	var tex := TextureRect.new()
	tex.texture = viewport.get_texture()
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_SCALE
	tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pm := CanvasItemMaterial.new()
	pm.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA   # (the 3D's soft edges come out premultiplied)
	tex.material = pm
	add_child(tex)
	world = Node3D.new()
	viewport.add_child(world)
	_build_scene()
	resized.connect(_resize)
	_resize()
	_rebuild()

func _resize() -> void:
	var logical := get_viewport().get_visible_rect().size
	var window := Vector2(DisplayServer.window_get_size())
	var ratio := 1.0
	if logical.x > 0 and window.x > 0:
		ratio = clampf(window.x / logical.x, 1.0, 3.0)
	viewport.size = Vector2i(maxi(64, int(size.x * ratio)), maxi(64, int(size.y * ratio)))

# ---------------- the room ----------------
func _build_scene() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#b49ab8")
	env.ambient_light_energy = 0.42 * View.VULKAN_AMBIENT
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.92 * View.VULKAN_EXPOSURE
	env.tonemap_white = 3.0
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	# warm room light from the front (the candles and lamps behind the viewer) -- the one that casts shadows
	var key := DirectionalLight3D.new()
	key.light_color = Color("#ffd6a0")
	key.light_energy = 1.15
	key.rotation_degrees = Vector3(-52.0, -24.0, 0.0)
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 9.0
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	world.add_child(key)
	# the dusk through the window behind: a cool violet rim, and the low sun's orange from the left beyond
	var dusk := DirectionalLight3D.new()
	dusk.light_color = Color("#a98cff")
	dusk.light_energy = 0.6
	dusk.rotation_degrees = Vector3(-28.0, 168.0, 0.0)
	world.add_child(dusk)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("#ffa060")
	sun.light_energy = 0.8
	sun.rotation_degrees = Vector3(-12.0, -150.0, 0.0)
	world.add_child(sun)
	_build_table()
	_build_candles()
	_heroes = Node3D.new()
	world.add_child(_heroes)
	cam = Camera3D.new()
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.fov = CAM_FOV
	cam.near = 0.5
	cam.far = 40.0
	var dir := Vector3(0.0, sin(deg_to_rad(CAM_ELEV)), cos(deg_to_rad(CAM_ELEV)))
	var at := Vector3(0.0, TOP_Y, 0.0)
	cam.transform = Transform3D(Basis.looking_at(-dir, Vector3.UP), at + dir * cam_dist())
	cam.v_offset = v_shift()
	world.add_child(cam)
	cam.current = true

static func lathe(profile: PackedVector2Array, base := Vector2.ZERO, segs := 96) -> ArrayMesh:
	# a ring turned from a profile of (out, height) points round an oval of radii `base` (x across, z away; zero: a
	# circle round the middle); UV.x goes round, UV.y along the profile. The profile runs so that its outside is on its
	# left going along it (the normal: (-dy, dr)).
	var n := profile.size()
	var vn: Array[Vector2] = []
	for i in n:
		var t := Vector2.ZERO
		if i > 0:
			t += (profile[i] - profile[i - 1]).normalized()
		if i < n - 1:
			t += (profile[i + 1] - profile[i]).normalized()
		vn.append(Vector2(-t.y, t.x).normalized())
	var lens := [0.0]
	for i in range(1, n):
		lens.append(float(lens[-1]) + profile[i].distance_to(profile[i - 1]))
	var total: float = maxf(0.001, float(lens[-1]))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in segs + 1:
		var a := TAU * float(s) / float(segs)
		for i in n:
			var p := profile[i]
			var rx := base.x + p.x
			var rz := base.y + p.x
			var out := Vector2(sin(a) * maxf(rz, 0.001), cos(a) * maxf(rx, 0.001)).normalized()   # (the oval's normal)
			st.set_normal(Vector3(vn[i].x * out.x, vn[i].y, vn[i].x * out.y).normalized())
			st.set_uv(Vector2(float(s) / float(segs), float(lens[i]) / total))
			st.add_vertex(Vector3(rx * sin(a), p.y, rz * cos(a)))
	for s in segs:
		for i in n - 1:
			var a0 := s * n + i
			var b0 := (s + 1) * n + i
			st.add_index(a0)
			st.add_index(b0)
			st.add_index(a0 + 1)
			st.add_index(a0 + 1)
			st.add_index(b0)
			st.add_index(b0 + 1)
	return st.commit()

static func tube(r: float, at: Vector2, sides := 8) -> PackedVector2Array:
	# a small round profile (a band's section) round `at` (out, height)
	var p := PackedVector2Array()
	for i in sides + 1:
		var a := -TAU * float(i) / float(sides)
		p.append(at + Vector2(cos(a), sin(a)) * r)
	return p

func _wood(trim := 0.0, rounds := 10.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WoodShader
	m.set_shader_parameter("grain_tex", LandView.noise_tex(0.02, 11 if trim == 0.0 else 5))
	m.set_shader_parameter("trim", trim)
	m.set_shader_parameter("rounds", rounds)
	return m

func _mesh(mesh: Mesh, mat: Material, pos := Vector3.ZERO, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	return mi

func _build_table() -> void:
	var oak := _wood()
	var base := oval()
	# the rim: a raised lip round the map, the broad top, a rounded edge and a deep apron (out from the map's oval)
	var rim := PackedVector2Array([
		Vector2(0.0, -0.09), Vector2(0.0, 0.05), Vector2(0.018, 0.075), Vector2(0.05, 0.085), Vector2(RIM - 0.06, 0.085),
		Vector2(RIM - 0.02, 0.072), Vector2(RIM, 0.04), Vector2(RIM + 0.01, -0.02), Vector2(RIM + 0.012, -0.14),
		Vector2(RIM - 0.01, -0.17), Vector2(RIM - 0.02, -0.21), Vector2(RIM - 0.08, -0.23), Vector2(-0.7, -0.23)])
	for i in rim.size():
		rim[i].y += TOP_Y
	_mesh(lathe(rim, base), oak)
	# the column and its foot (mostly behind the near heroes)
	var foot := PackedVector2Array([
		Vector2(0.32, TOP_Y - 0.17), Vector2(0.28, TOP_Y - 0.26), Vector2(0.22, TOP_Y - 0.36), Vector2(0.22, 0.32),
		Vector2(0.3, 0.22), Vector2(0.55, 0.12), Vector2(0.8, 0.06), Vector2(0.82, 0.0), Vector2(0.0, 0.0)])
	_mesh(lathe(foot, Vector2.ZERO, 48), _wood(0.0, 4.0))
	# gilt bands: round the map's lip and round the apron
	var gilt := _wood(1.0, 14.0)
	_mesh(lathe(tube(0.018, Vector2(0.02, TOP_Y + 0.078)), base, 128), gilt, Vector3.ZERO, false)
	_mesh(lathe(tube(0.016, Vector2(RIM + 0.012, TOP_Y - 0.03)), base, 128), gilt, Vector3.ZERO, false)
	_mesh(lathe(tube(0.012, Vector2(RIM + 0.004, TOP_Y - 0.165)), base, 128), gilt, Vector3.ZERO, false)
	# iron-and-gilt plates round the apron
	var plate := StandardMaterial3D.new()
	plate.albedo_color = Color("#6b5131")
	plate.metallic = 0.8
	plate.roughness = 0.35
	for i in 12:
		var deg := 360.0 * (float(i) + 0.5) / 12.0
		var bm := BoxMesh.new()
		bm.size = Vector3(0.16, 0.11, 0.02)
		var p := on_oval(deg, RIM + 0.02)
		var mi := _mesh(bm, plate, p + Vector3(0.0, TOP_Y - 0.09, 0.0), false)
		var a := deg_to_rad(deg)
		mi.rotation.y = atan2(sin(a) * oval(RIM).y, cos(a) * oval(RIM).x)
	# the bed under the map (deep water where the land's sea is deepest)
	var bed := CylinderMesh.new()
	bed.top_radius = 1.0
	bed.bottom_radius = 1.0
	bed.height = 0.02
	bed.radial_segments = 96
	var bm2 := StandardMaterial3D.new()
	bm2.albedo_color = Color("#0b2036")
	var bmi := _mesh(bed, bm2, Vector3(0.0, TOP_Y - 0.08, 0.0), false)
	bmi.scale = Vector3(base.x, 1.0, base.y)
	# the shadow on the rug
	var sh := _blob(1.0, 0.62)
	sh.scale = Vector3(oval(RIM).x * 2.5, 1.0, oval(RIM).y * 2.5)
	world.add_child(sh)
	# the live map
	if ResourceLoader.exists(LandView.LAND + "land.glb"):
		land = LandView.new()
		land.disc = MAP_OVAL
		land.sea_size = MAP_OVAL.y * 2.1
		land.scale = Vector3.ONE * map_scale()
		land.position = Vector3(0.0, TOP_Y, 0.0)
		world.add_child(land)
		land.build(0.0055, 0.1)
		land.placed()
		for gi in land.find_children("*", "GeometryInstance3D", true, false):
			(gi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # (the heroes' and the table's are enough)
		# (smaller than on the war map: finer waves, a soft sheen, deeper colours; the houses' colours stronger)
		land.sea_mat.set_shader_parameter("wave_scale", 2.6)
		land.sea_mat.set_shader_parameter("spec", 0.18)
		land.sea_mat.set_shader_parameter("rough", 0.42)
		land.sea_mat.set_shader_parameter("glow", 0.04)
		land.sea_mat.set_shader_parameter("shallow", Color(0.2, 0.55, 0.6))
		land.sea_mat.set_shader_parameter("deep", Color(0.05, 0.19, 0.36))
		land.sea_mat.set_shader_parameter("far", Color(0.04, 0.12, 0.26))
		if land.land_mat != null:
			land.land_mat.set_shader_parameter("tint", 0.3)

func _blob(size: float, alpha: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.orientation = PlaneMesh.FACE_Y
	m.mesh = q
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var g := Gradient.new()
	g.set_color(0, Color(0.04, 0.02, 0.06, alpha))
	g.set_color(1, Color(0.04, 0.02, 0.06, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	mat.albedo_texture = gt
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.position.y = 0.006
	return m

func _build_candles() -> void:
	var wax := StandardMaterial3D.new()
	wax.albedo_color = Color("#e8cf9f")
	wax.roughness = 0.6
	wax.emission_enabled = true
	wax.emission = Color("#ffb25a")
	wax.emission_energy_multiplier = 0.12
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color("#b8883a")
	brass.metallic = 0.85
	brass.roughness = 0.3
	var k := 0
	for deg in CANDLE_SPOTS:
		var a := deg_to_rad(float(deg))
		var base := on_oval(float(deg), RIM * 0.5) + Vector3(0.0, TOP_Y + 0.085, 0.0)
		var side := Vector3(cos(a), 0.0, -sin(a))          # along the rim
		var inward := -Vector3(sin(a), 0.0, cos(a))
		var dish := CylinderMesh.new()
		dish.top_radius = 0.13
		dish.bottom_radius = 0.1
		dish.height = 0.02
		_mesh(dish, brass, base + Vector3(0.0, 0.01, 0.0), false)
		for c in CANDLES:
			var h := float(c[2])
			var cm := CylinderMesh.new()
			cm.top_radius = 0.032
			cm.bottom_radius = 0.035
			cm.height = h
			cm.radial_segments = 14
			var p: Vector3 = base + side * float(c[0]) + inward * float(c[1])
			_mesh(cm, wax, p + Vector3(0.0, 0.02 + h * 0.5, 0.0))
			wicks.append(p + Vector3(0.0, 0.02 + h + 0.035, 0.0))
		var o := OmniLight3D.new()
		o.light_color = Color("#ffb55e")
		o.light_energy = 1.6
		o.omni_range = 2.6
		o.omni_attenuation = 1.4
		o.position = base + Vector3(0.0, 0.35, 0.0) + inward * 0.1
		world.add_child(o)
		_lights.append([o, o.light_energy, 1.7 * k])
		k += 1

# ---------------- the heroes ----------------
func set_looks(d: Dictionary) -> void:
	looks = d
	if is_inside_tree():
		_rebuild()

func _rebuild() -> void:
	if _heroes == null:
		return
	var i := 0
	for spot in SPOTS:
		var cls: String = spot[0]
		var look: Dictionary = looks.get(cls, {})
		var key := str(look)
		var slot: Node3D = _built.get(cls, {}).get("node", null)
		if slot != null and str(_built[cls].key) == key:
			i += 1
			continue
		if slot != null:
			slot.queue_free()
		var pos := on_oval(float(spot[1]), RIM + float(spot[2]))
		slot = Node3D.new()
		slot.position = pos
		slot.rotation.y = atan2(-pos.x, -pos.z)          # facing the table's middle
		_heroes.add_child(slot)
		slot.add_child(_blob(1.5, 0.55))
		var made: Dictionary = View.make_body(cls, look)
		if not made.is_empty():
			var body: Node3D = made.body
			body.scale = Vector3.ONE * HERO_SCALE
			slot.add_child(body)
			var player: AnimationPlayer = made.player
			var idle: String = str(View.LOOKS.get(cls, View.LOOKS.knight).idle)
			if player != null and player.has_animation(idle):
				player.play(idle)
				player.seek(fmod(0.41 * i, maxf(0.1, player.get_animation(idle).length)), true)
		_built[cls] = {"node": slot, "key": key}
		i += 1

# ---------------- the war ----------------
func table_center() -> Vector2:
	# 0.31.147: the map's middle on the screen (Home's PLAY pushes the view in on it: siege_app._zoom_into_table)
	if cam != null and cam.is_inside_tree() and viewport.size.x > 0:
		var p := cam.unproject_position(Vector3(0.0, TOP_Y, 0.0)) * (size / Vector2(viewport.size))
		return get_global_transform() * p
	return get_global_transform() * Vector2(size.x * 0.5, size.y * TABLE_ROW / FRAME.size.y)

func paint(war: Dictionary) -> void:
	if land != null:
		land.paint(war)

func flame_points() -> Array:
	# each candle's flame in this control's pixels (home_scene.gd draws the flames there)
	var out := []
	if cam == null or viewport.size.x <= 0:
		return out
	var k := size / Vector2(viewport.size)
	for w in wicks:
		out.append(cam.unproject_position(w) * k)
	return out

func _process(delta: float) -> void:
	_clock += delta
	_frame += 1
	if is_visible_in_tree() and _frame % maxi(1, every) == 0:
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if land != null:
		land.step(delta)
	if calm:
		return
	for l in _lights:
		var o: OmniLight3D = l[0]
		var ph: float = l[2]
		var f := 0.86 + 0.08 * sin(_clock * 7.3 + ph) + 0.05 * sin(_clock * 13.1 + ph * 2.0) + 0.04 * sin(_clock * 2.2 + ph)
		o.light_energy = float(l[1]) * f
