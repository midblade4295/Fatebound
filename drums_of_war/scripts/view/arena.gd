extends Node3D
## The battlefield's scenery: sculpted ground with a real creek channel, water, grass, woods.
##
## Everything here is decoration and is laid out in world space with the field centred on the
## origin: the field is 18 wide (x) and 32 long (z), the creek runs along x at z = 0, the bridge
## is at x = 0 and the fords at x = -6 and x = 6. The layout is symmetric, so it does not care
## which side is the local player's. The rules know nothing about any of it.

const Models = preload("res://scripts/view/models.gd")
const GsRng = preload("res://scripts/sim/sim_rng.gd")

const FIELD_HALF_W := 9.0
const FIELD_HALF_L := 18.0
const FORD_X := 6.0
const WATER_Y := -0.12            # the water's surface; the grass is at 0
const DEEP := 1.15                # depth of the creek bed below the grass
const SHALLOW := 0.5              # ... at a ford
const BRIDGE_HALF_W := 1.45
const BRIDGE_HALF_L := 2.0
const BRIDGE_DECK := 0.62         # height of the bridge's roadway at its crown

const TREES := ["tree", "tree_oak", "tree_pine", "tree_birch"]

# Autumn leaf colours, as seen on screen. Weighted toward the warm ones; a few trees stay green.
const LEAVES := [Color("c8291a"), Color("e2531a"), Color("f08a1c"), Color("f6c22e"), Color("9c4420"),
		Color("d9a62a"), Color("b9c43a"), Color("3f7a2a"), Color("e06a1e"), Color("f2b12a")]

var _structure_spots: Array = []  # Vector2 (x, z) of each structure, for worn earth and clearings
var _rng: GsRng
var _shade_casters: Array = []    # every still mesh that shades the ground: trees, bushes, fences, logs
var _bake_view: SubViewport
var _bake_proxies: Array = []
var _bake_rows: Array = []        # world position -> baked-shade texture coordinates
var _bake_draws: int = 0
var _live_casters: Array = []     # trees that go back to casting live shadows if the bake cannot be made
var _ground_mat: ShaderMaterial
var _extras: Array = []           # falling leaves and motes: pretty, and the first to go on a slow device


# ==========================================================================================
# The shape of the ground
# ==========================================================================================

static func _smooth(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func ford_weight(x: float) -> float:
	return maxf(1.0 - _smooth(1.3, 2.0, absf(x + FORD_X)), 1.0 - _smooth(1.3, 2.0, absf(x - FORD_X)))


## Height of the ground at a world position: 0 on the grass, negative in the creek channel,
## gently rolling beyond the woods.
static func height(x: float, z: float) -> float:
	var channel := lerpf(DEEP, SHALLOW, ford_weight(x)) * (1.0 - _smooth(0.55, 1.3, absf(z)))
	var far := _smooth(13.0, 22.0, absf(x)) + _smooth(21.0, 30.0, absf(z))
	var roll := (sin(x * 0.21 + 1.3) * cos(z * 0.17) + sin(x * 0.11 - z * 0.13)) * 0.45 * minf(far, 1.0)
	return roll * (1.0 - _smooth(1.5, 0.6, absf(z))) - channel


## Height a soldier stands at: the bridge's roadway, the bed of a ford, or the grass.
static func standing_height(x: float, z: float) -> float:
	if absf(x) < BRIDGE_HALF_W and absf(z) < BRIDGE_HALF_L:
		var t := z / BRIDGE_HALF_L
		return BRIDGE_DECK * (1.0 - t * t)
	return maxf(height(x, z), -SHALLOW)


# ==========================================================================================
# Building
# ==========================================================================================

func build(structure_spots: Array) -> void:
	_structure_spots = structure_spots
	_rng = GsRng.new(1861)
	_build_ground()
	_build_water()
	_build_bridge_and_stones()
	_build_grass()
	_build_woods()
	_build_fences()
	_build_harvest()
	_build_leaves()
	_build_light_effects()


const SHADE_LAYER := 1 << 9       # render layer seen only by the shade bake's camera

## The woods never move and neither does the sun, so their shadow on the ground is drawn once
## instead of every frame. begin_shade_bake() poses a black copy of every tree, bush and fence
## in front of a camera that looks along the sunlight; a few frames later finish_shade_bake()
## keeps that picture as a texture, which the ground shader darkens itself with, and throws
## the copies away. The sun's live shadow map is then left with only what moves or matters up
## close: the troops, the buildings and the bridge.
func begin_shade_bake(sun_dir: Vector3) -> void:
	if DisplayServer.get_name() == "headless" or _bake_view != null:
		return
	var black := StandardMaterial3D.new()
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	black.albedo_color = Color.BLACK
	for mi: MeshInstance3D in _shade_casters:
		if not is_instance_valid(mi) or mi.mesh == null:
			continue
		var proxy := MeshInstance3D.new()
		proxy.mesh = mi.mesh
		proxy.material_override = black
		proxy.layers = SHADE_LAYER
		proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(proxy)
		proxy.global_transform = mi.global_transform
		_bake_proxies.append(proxy)
	_bake_view = SubViewport.new()
	_bake_view.size = Vector2i(1024, 1024)
	_bake_view.msaa_3d = Viewport.MSAA_4X
	_bake_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_bake_view)
	var cam := Camera3D.new()
	_bake_view.add_child(cam)
	var centre := Vector3(0.0, 0.0, -2.0)
	var dir := sun_dir.normalized()
	cam.look_at_from_position(centre - dir * 90.0, centre, Vector3.UP)
	# Wide enough to take in the whole wood and everything it can shade.
	var right := cam.global_basis.x
	var up := cam.global_basis.y
	var reach := 1.0
	for x: float in [-27.0, 27.0]:
		for y: float in [-1.5, 9.0]:
			for z: float in [-32.0, 27.0]:
				var rel := Vector3(x, y, z) - cam.global_position
				reach = maxf(reach, maxf(absf(rel.dot(right)), absf(rel.dot(up))))
	var span := reach * 2.0 + 2.0
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = span
	cam.near = 1.0
	cam.far = 220.0
	cam.cull_mask = SHADE_LAYER
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.WHITE
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	cam.environment = env
	cam.current = true
	# Texture coordinates of a world point: across is the camera's right, down is minus its up.
	var eye := cam.global_position
	_bake_rows = [Vector4(right.x, right.y, right.z, -eye.dot(right)) / span + Vector4(0, 0, 0, 0.5),
			Vector4(-up.x, -up.y, -up.z, eye.dot(up)) / span + Vector4(0, 0, 0, 0.5)]
	# Read the picture back only once frames have really been drawn (a window that is not yet
	# on screen draws nothing, and the texture would still be blank).
	_bake_draws = 0
	RenderingServer.frame_post_draw.connect(_on_bake_frame_drawn)


func _on_bake_frame_drawn() -> void:
	_bake_draws += 1
	if _bake_draws >= 3:
		RenderingServer.frame_post_draw.disconnect(_on_bake_frame_drawn)
		finish_shade_bake()


func finish_shade_bake() -> void:
	if _bake_view == null:
		return
	var img: Image = _bake_view.get_texture().get_image()
	for proxy: Node in _bake_proxies:
		proxy.queue_free()
	_bake_proxies.clear()
	_bake_view.queue_free()
	_bake_view = null
	# A good bake is mostly open sky (white) with the woods in black. Anything else (no picture,
	# or a blank one) is not used, and the nearer trees cast live shadows instead.
	var good := img != null and not img.is_empty() and _ground_mat != null
	if good:
		var probe: Image = img.duplicate()
		probe.resize(8, 8, Image.INTERPOLATE_BILINEAR)
		var sum := 0.0
		for y in 8:
			for x in 8:
				sum += probe.get_pixel(x, y).r
		good = sum / 64.0 > 0.45 and sum / 64.0 < 0.98
	if not good:
		for mi: MeshInstance3D in _live_casters:
			if is_instance_valid(mi):
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		return
	if OS.has_environment("BAKE_DUMP"):
		img.save_png(OS.get_environment("BAKE_DUMP"))
	img.convert(Image.FORMAT_L8)
	img.resize(512, 512, Image.INTERPOLATE_CUBIC)       # the shrink also softens the shadows' edges
	img.generate_mipmaps()
	_ground_mat.set_shader_parameter("shade_tex", ImageTexture.create_from_image(img))
	_ground_mat.set_shader_parameter("shade_u", _bake_rows[0])
	_ground_mat.set_shader_parameter("shade_v", _bake_rows[1])


## The ground without its moving cloud shadow, dappled light and pebbles: three fewer texture
## reads on every pixel of grass.
func set_plain_ground(on: bool) -> void:
	if _ground_mat != null:
		_ground_mat.set_shader_parameter("plain", on)


func set_extras(on: bool) -> void:
	for node: Node3D in _extras:
		node.visible = on


func _leaf_colour() -> Color:
	return LEAVES[_rng.range_i(0, LEAVES.size() - 1)]


## A small leaf-shaped mask: white inside a pointed oval, clear outside.
func _leaf_texture() -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var u := (x + 0.5) / 8.0 - 1.0
			var v := (y + 0.5) / 8.0 - 1.0
			var inside := (u * u) / 0.32 + (v * v) / 0.9 <= 1.0
			img.set_pixel(x, y, Color(1, 1, 1, 1.0 if inside else 0.0))
	return ImageTexture.create_from_image(img)


func _noise(frequency: float, seed_value: int, normal_map: bool = false) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = frequency
	n.seed = seed_value
	n.fractal_octaves = 3
	var t := NoiseTexture2D.new()
	t.width = 256
	t.height = 256
	t.seamless = true
	t.noise = n
	t.generate_mipmaps = true
	t.as_normal_map = normal_map
	t.bump_strength = 7.0
	return t


func _build_ground() -> void:
	# A grid that is fine across the creek, where the channel is cut, and coarse elsewhere.
	var zs: Array = [-60.0, -40.0, -30.0, -22.0, -18.0, -13.0, -8.0, -5.0, -3.0, -2.0, -1.5, -1.3, -1.1, -0.9, -0.7, -0.5, -0.25,
			0.0, 0.25, 0.5, 0.7, 0.9, 1.1, 1.3, 1.5, 2.0, 3.0, 5.0, 8.0, 13.0, 18.0, 22.0, 30.0, 40.0, 60.0]
	var xs: Array = []
	var x := -48.0
	while x <= 48.01:
		xs.append(x)
		x += 0.5 if absf(x) < 9.0 else (1.0 if absf(x) < 20.0 else 4.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for zi in zs.size() - 1:
		for xi in xs.size() - 1:
			var corners: Array = []
			for c: Array in [[0, 0], [1, 0], [1, 1], [0, 1]]:
				var px: float = xs[xi + c[0]]
				var pz: float = zs[zi + c[1]]
				corners.append(Vector3(px, height(px, pz), pz))
			for tri: Array in [[0, 1, 2], [0, 2, 3]]:
				for idx: int in tri:
					st.add_vertex(corners[idx])
	st.index()
	st.generate_normals()
	var ground := MeshInstance3D.new()
	ground.mesh = st.commit()
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/ground.gdshader")
	mat.set_shader_parameter("noise", _noise(0.02, 7))
	var worn := PackedVector2Array()
	for i in 6:
		worn.append(_structure_spots[i] if i < _structure_spots.size() else Vector2(999, 999))
	mat.set_shader_parameter("worn", worn)
	ground.material_override = mat
	_ground_mat = mat
	add_child(ground)


func _build_water() -> void:
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(96.0, 2.9)
	water.mesh = plane
	water.position = Vector3(0.0, WATER_Y, 0.0)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/river.gdshader")
	mat.set_shader_parameter("wave_a", _noise(0.035, 11, true))
	mat.set_shader_parameter("wave_b", _noise(0.06, 23, true))
	mat.set_shader_parameter("foam_noise", _noise(0.05, 31))
	mat.set_shader_parameter("shallow_col", Color("74bfe8"))
	mat.set_shader_parameter("deep_col", Color("3d8fd4"))
	mat.set_shader_parameter("swirl_col", Color("c4e8fb"))
	mat.set_shader_parameter("sky_col", Color("cfe9ff"))
	mat.set_shader_parameter("surface", WATER_Y)
	mat.set_shader_parameter("deep", DEEP)
	mat.set_shader_parameter("shallow", SHALLOW)
	mat.set_shader_parameter("bridge_half", BRIDGE_HALF_W + 0.25)
	water.material_override = mat
	add_child(water)


func _colour_mat(colour: Color, roughness: float = 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = roughness
	return m


func _build_bridge_and_stones() -> void:
	var bridge := Models.make("bridge", 0)
	if bridge != null:
		Models.fit_footprint(bridge, BRIDGE_HALF_W * 2.0 + 0.5, BRIDGE_HALF_L * 2.0)
		add_child(bridge)
	else:
		var deck := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(BRIDGE_HALF_W * 2.0, 0.3, BRIDGE_HALF_L * 2.0)
		deck.mesh = box
		deck.position.y = 0.3
		deck.material_override = _colour_mat(Color("b9b2a3"))
		add_child(deck)
	# Stepping stones and gravel bars at the fords, a few boulders in the deep water.
	var stone := SphereMesh.new()
	stone.radius = 0.5
	stone.height = 0.6
	stone.radial_segments = 10
	stone.rings = 5
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = stone
	var spots: Array = []
	for side: float in [-1.0, 1.0]:
		for i in 22:
			var px := side * FORD_X + _rng.range_f(-1.5, 1.5)
			var pz := _rng.range_f(-1.15, 1.15)
			spots.append([Vector3(px, height(px, pz) + 0.04, pz), _rng.range_f(0.22, 0.52)])
	for i in 16:
		var px2 := _rng.range_f(-22.0, 22.0)
		if absf(absf(px2) - FORD_X) < 2.2 or absf(px2) < 2.0:
			continue
		var pz2 := _rng.range_f(-0.9, 0.9)
		spots.append([Vector3(px2, height(px2, pz2) + 0.25, pz2), _rng.range_f(0.6, 1.2)])
	mm.instance_count = spots.size()
	for i in spots.size():
		var size: float = spots[i][1]
		var b := Basis.from_euler(Vector3(0, _rng.range_f(0.0, TAU), 0)).scaled(Vector3(size, size * 0.7, size * 0.85))
		mm.set_instance_transform(i, Transform3D(b, spots[i][0]))
	var stones := MultiMeshInstance3D.new()
	stones.multimesh = mm
	stones.material_override = _colour_mat(Color("9a978c"), 0.7)
	add_child(stones)
	# Boulders on the banks, but only beyond the field: nothing here may look like an obstacle.
	_scatter_model("rocks", [Vector3(-12.5, 0, 1.6), Vector3(11.8, 0, -1.8), Vector3(-10.6, 0, -1.9), Vector3(10.4, 0, 1.8),
			Vector3(-15.5, 0, -2.2), Vector3(15.8, 0, 2.0)], 1.5, 2.3)


## Places copies of a generated model, each turned and sized a little differently.
func _scatter_model(model: String, where: Array, min_size: float, max_size: float) -> void:
	if not Models.has_model(model):
		return
	for p: Vector3 in where:
		var node := Models.make(model, 0)
		var size := _rng.range_f(min_size, max_size)
		Models.fit_footprint(node, size, size)
		node.position = Vector3(p.x, height(p.x, p.z) - 0.05, p.z)
		node.rotation.y = _rng.range_f(0.0, TAU)
		add_child(node)
		for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.lod_bias = 0.6
			_shade_casters.append(mi)


# --- Grass ---------------------------------------------------------------------------------

func _blade_mesh() -> ArrayMesh:
	# One tuft: seven tapering blades fanned out from a point. Vertex colour red is the height
	# along the blade (0 at the root, 1 at the tip); the shader uses it for colour and sway.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 7:
		var a := TAU * i / 7.0 + (i % 2) * 0.4
		var out := Vector3(cos(a), 0, sin(a))
		var across := Vector3(-out.z, 0, out.x) * 0.024
		var tall := 0.34 + 0.12 * ((i * 5) % 3)
		var root := out * 0.05
		var mid := out * 0.12 + Vector3(0, tall * 0.55, 0)
		var tip := out * 0.24 + Vector3(0, tall, 0)
		for tri: Array in [[root - across, 0.0, root + across, 0.0, mid + across * 0.7, 0.55],
				[root - across, 0.0, mid + across * 0.7, 0.55, mid - across * 0.7, 0.55],
				[mid - across * 0.7, 0.55, mid + across * 0.7, 0.55, tip, 1.0]]:
			for v in 3:
				st.set_color(Color(tri[v * 2 + 1], 0, 0))
				st.set_normal(Vector3.UP)
				st.add_vertex(tri[v * 2])
	return st.commit()


func _clear_of_structures(x: float, z: float, margin: float) -> bool:
	for spot: Vector2 in _structure_spots:
		if spot.distance_to(Vector2(x, z)) < margin:
			return false
	return true


func _build_grass() -> void:
	var tufts: Array = []      # [position, size, colour]
	# Short and sparse on the field, so the troops stay readable.
	for i in 230:
		var x := _rng.range_f(-FIELD_HALF_W, FIELD_HALF_W)
		var z := _rng.range_f(-FIELD_HALF_L, FIELD_HALF_L)
		if absf(z) < 2.4 or not _clear_of_structures(x, z, 2.3) or (absf(x) < 1.0 and absf(z) < 12.0):
			continue
		tufts.append([Vector3(x, 0, z), _rng.range_f(0.4, 0.62), Color(0.3, 0.5, 0.14).lerp(Color(0.38, 0.56, 0.18), _rng.next_f())])
	# Grass grows in clumps, not evenly: a couple of dozen loose patches of slightly longer tufts.
	for patch in 26:
		var cx := _rng.range_f(-FIELD_HALF_W + 1.0, FIELD_HALF_W - 1.0)
		var cz := _rng.range_f(-FIELD_HALF_L + 1.0, FIELD_HALF_L - 1.0)
		for i in _rng.range_i(5, 9):
			var x := cx + _rng.range_f(-1.1, 1.1)
			var z := cz + _rng.range_f(-0.9, 0.9)
			if absf(z) < 2.4 or not _clear_of_structures(x, z, 2.3) or (absf(x) < 1.0 and absf(z) < 12.0):
				continue
			tufts.append([Vector3(x, 0, z), _rng.range_f(0.45, 0.8), Color(0.3, 0.5, 0.14).lerp(Color(0.44, 0.6, 0.2), _rng.next_f())])
	# Thicker clumps where the pasture meets the creek's banks.
	for i in 90:
		var x := _rng.range_f(-FIELD_HALF_W, FIELD_HALF_W)
		if absf(absf(x) - FORD_X) < 1.9 or absf(x) < 1.9:
			continue
		var z := _rng.range_f(1.7, 2.5) * (1.0 if _rng.next_f() < 0.5 else -1.0)
		tufts.append([Vector3(x, height(x, z), z), _rng.range_f(0.9, 1.5), Color(0.26, 0.46, 0.12).lerp(Color(0.4, 0.58, 0.18), _rng.next_f())])
	# Tall and thick in the meadow all round it.
	for i in 6400:
		var x := _rng.range_f(-21.0, 21.0)
		var z := _rng.range_f(-29.0, 24.0)
		if absf(x) < FIELD_HALF_W + 0.2 and absf(z) < FIELD_HALF_L + 0.2:
			continue
		if absf(z) < 1.5:
			continue
		# Seen from above, the ground under the woods is hidden by the canopy: no grass there.
		if absf(x) > 12.2 or z < -22.5:
			continue
		tufts.append([Vector3(x, height(x, z), z), _rng.range_f(1.1, 2.1), Color(0.42, 0.54, 0.21).lerp(Color(0.74, 0.68, 0.3), _rng.next_f() * _rng.next_f())])
	# Reeds along both banks, away from the crossings.
	for i in 300:
		var x := _rng.range_f(-24.0, 24.0)
		if absf(absf(x) - FORD_X) < 2.0 or absf(x) < 1.9:
			continue
		var z := _rng.range_f(1.25, 1.75) * (1.0 if _rng.next_f() < 0.5 else -1.0)
		tufts.append([Vector3(x, height(x, z), z), _rng.range_f(1.3, 2.2), Color(0.4, 0.55, 0.18).lerp(Color(0.74, 0.66, 0.28), _rng.next_f())])
	# Two patches of ripe wheat beyond the fences.
	for patch: Array in [[11.6, -5.0, 1.5, 3.2], [-11.7, 7.0, 1.5, 2.8]]:
		for i in 700:
			var x: float = patch[0] + _rng.range_f(-patch[2], patch[2])
			var z: float = patch[1] + _rng.range_f(-patch[3], patch[3])
			tufts.append([Vector3(x, height(x, z), z), _rng.range_f(2.0, 2.6), Color(0.98, 0.8, 0.28).lerp(Color(0.9, 0.68, 0.2), _rng.next_f())])

	# One mesh would be drawn whole even when most of it is off screen, so the tufts are sorted
	# into a grid of patches and each patch is its own mesh: what the camera cannot see is
	# skipped, which on a phone is most of the meadow.
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = """
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
varying float along;
varying vec3 tint;
void vertex() {
	along = COLOR.r;
	tint = INSTANCE_CUSTOM.rgb;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float gust = sin(TIME * 1.7 + w.x * 0.8 + w.z * 1.1) * 0.5 + sin(TIME * 3.3 + w.x * 2.1 - w.z * 0.7) * 0.2;
	VERTEX.x += gust * 0.12 * along * along;
	VERTEX.z += gust * 0.06 * along * along;
}
void fragment() {
	ALBEDO = pow(tint * mix(0.72, 1.12, along), vec3(2.2));
	ROUGHNESS = 0.9;
}
"""
	var blade := _blade_mesh()
	var patches: Dictionary = {}
	for tuft: Array in tufts:
		var at: Vector3 = tuft[0]
		var key := Vector2i(int(floor(at.x / 7.0)), int(floor(at.z / 9.0)))
		if not patches.has(key):
			patches[key] = []
		patches[key].append(tuft)
	for key: Vector2i in patches:
		var members: Array = patches[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = blade
		mm.instance_count = members.size()
		for i in members.size():
			var size: float = members[i][1]
			var b := Basis.from_euler(Vector3(0, _rng.range_f(0.0, TAU), 0)).scaled(Vector3(size, size, size))
			mm.set_instance_transform(i, Transform3D(b, members[i][0]))
			mm.set_instance_custom_data(i, members[i][2])
		var grass := MultiMeshInstance3D.new()
		grass.multimesh = mm
		grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		grass.material_override = mat
		add_child(grass)

	# Wildflowers: small bright heads standing in the meadow grass.
	var head := SphereMesh.new()
	head.radius = 0.09
	head.height = 0.12
	head.radial_segments = 6
	head.rings = 3
	var fm := MultiMesh.new()
	fm.transform_format = MultiMesh.TRANSFORM_3D
	fm.use_colors = true
	fm.mesh = head
	var flowers: Array = []
	for i in 520:
		var x := _rng.range_f(-22.0, 22.0)
		var z := _rng.range_f(-27.0, 23.0)
		if (absf(x) < FIELD_HALF_W + 0.3 and absf(z) < FIELD_HALF_L + 0.3) or absf(z) < 1.6:
			continue
		flowers.append(Vector3(x, height(x, z) + _rng.range_f(0.35, 0.6), z))
	# A few low daisies and buttercups out in the pasture itself.
	for i in 70:
		var x := _rng.range_f(-FIELD_HALF_W, FIELD_HALF_W)
		var z := _rng.range_f(-FIELD_HALF_L, FIELD_HALF_L)
		if absf(z) < 2.4 or not _clear_of_structures(x, z, 2.6) or absf(x) < 1.2:
			continue
		flowers.append(Vector3(x, 0.1, z))
	fm.instance_count = flowers.size()
	var petals := [Color("fff6d8"), Color("ffd84a"), Color("ff8fb0"), Color("b79cff"), Color("ffffff")]
	for i in flowers.size():
		fm.set_instance_transform(i, Transform3D(Basis(), flowers[i]))
		fm.set_instance_color(i, petals[_rng.range_i(0, petals.size() - 1)])
	var flower_node := MultiMeshInstance3D.new()
	flower_node.multimesh = fm
	flower_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var flower_mat := StandardMaterial3D.new()
	flower_mat.vertex_color_use_as_albedo = true
	flower_mat.roughness = 0.8
	flower_node.material_override = flower_mat
	add_child(flower_node)


# --- Woods ---------------------------------------------------------------------------------

const FOLIAGE_SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform float y_min;
uniform float y_size;
instance uniform vec3 leaf_col = vec3(0.1, 0.3, 0.03);
instance uniform float sway = 0.0;
void vertex() {
	float h = clamp((VERTEX.y - y_min) / y_size, 0.0, 1.0);
	float w = smoothstep(0.3, 1.0, h);
	float t = TIME * 1.25 + sway;
	VERTEX.x += sin(t + VERTEX.y * 3.0 / y_size) * 0.018 * y_size * w;
	VERTEX.z += cos(t * 0.8 + VERTEX.x * 2.0 / y_size) * 0.014 * y_size * w;
}
void fragment() {
	vec3 tex = texture(albedo_tex, UV).rgb;
	// Wherever the model's own texture is leafy green, paint the leaf colour in, keeping the
	// texture's light and shade. Bark, stone and wood are left as they are.
	float leafy = smoothstep(0.03, 0.14, tex.g - max(tex.r * 0.75, tex.b));
	float lum = dot(tex, vec3(0.35, 0.55, 0.1));
	ALBEDO = mix(tex, leaf_col * (0.3 + lum * 1.7), leafy);
	ROUGHNESS = 0.9;
}
"""

var _foliage_shader: Shader = null
var _foliage_mats: Dictionary = {}


## A tree or bush from a generated model, with leaves that stir and its own shade of green.
func _plant(model: String, pos: Vector3, tall: float, shadow: bool = true, detail: float = 0.6) -> bool:
	var node := Models.make(model, 0)
	if node == null:
		return false
	Models.fit_height(node, tall)
	node.position = pos
	node.rotation.y = _rng.range_f(0.0, TAU)
	if _foliage_shader == null:
		_foliage_shader = Shader.new()
		_foliage_shader.code = FOLIAGE_SHADER
	var leaf := _leaf_colour().lerp(_leaf_colour(), _rng.next_f() * 0.35)
	if model == "tree_pine":
		leaf = Color("2f5f2c").lerp(Color("3f7434"), _rng.next_f())       # evergreens stay green
	elif model == "bush" and _rng.next_f() < 0.45:
		leaf = Color("4d7d2c").lerp(Color("7c9a34"), _rng.next_f())
	var shade := _rng.range_f(0.8, 1.05)
	var tint := Vector3(pow(leaf.r, 2.2), pow(leaf.g, 2.2), pow(leaf.b, 2.2)) * shade
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or mi.mesh.get_surface_count() == 0:
			continue
		var base := mi.mesh.surface_get_material(0)
		if not (base is BaseMaterial3D) or (base as BaseMaterial3D).albedo_texture == null:
			continue
		if not _foliage_mats.has(model):
			var box := mi.mesh.get_aabb()
			var mat := ShaderMaterial.new()
			mat.shader = _foliage_shader
			mat.set_shader_parameter("albedo_tex", (base as BaseMaterial3D).albedo_texture)
			mat.set_shader_parameter("y_min", box.position.y)
			mat.set_shader_parameter("y_size", box.size.y)
			_foliage_mats[model] = mat
		mi.material_override = _foliage_mats[model]
		# The woods' shadow on the ground is baked (see begin_shade_bake), so no tree is drawn
		# into the live shadow map.
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_shade_casters.append(mi)
		if shadow:
			_live_casters.append(mi)
		mi.lod_bias = detail              # trees behind the front rank are half hidden: fewer triangles
		mi.set_instance_shader_parameter("leaf_col", tint)
		mi.set_instance_shader_parameter("sway", _rng.range_f(0.0, TAU))
	add_child(node)
	return true


func _stand_in_tree(pos: Vector3, tall: float) -> void:
	var t := Node3D.new()
	t.position = pos
	t.scale = Vector3.ONE * (tall / 2.6)
	var trunk := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.bottom_radius = 0.22
	cyl.top_radius = 0.16
	cyl.height = 0.9
	trunk.mesh = cyl
	trunk.position.y = 0.45
	trunk.material_override = _colour_mat(Color("6b4a2a"))
	t.add_child(trunk)
	for b: Array in [[0.0, 1.5, 0.0, 0.95], [0.45, 1.25, 0.2, 0.62], [-0.4, 1.3, -0.25, 0.66], [0.05, 2.05, 0.05, 0.6]]:
		var blob := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = b[3]
		sm.height = b[3] * 1.8
		sm.radial_segments = 12
		sm.rings = 6
		blob.mesh = sm
		blob.position = Vector3(b[0], b[1], b[2])
		blob.material_override = _colour_mat(Color("3f9a3c") if b[3] > 0.7 else Color("4eac45"))
		t.add_child(blob)
	add_child(t)


func _build_woods() -> void:
	var kinds: Array = []
	for model: String in TREES:
		if Models.has_model(model):
			kinds.append(model)
	# Deep woods down both flanks, three and four ranks back, thinning to nothing at the water.
	var spots: Array = []     # [x, z, height]
	for side: float in [-1.0, 1.0]:
		var z := -29.0
		while z < 22.5:
			for rank in 4:
				var px := side * (10.9 + rank * 2.5 + _rng.range_f(-0.5, 0.7))
				var pz := z + _rng.range_f(-1.0, 1.0) + rank * 0.7
				if absf(pz) < 2.4:
					continue
				# Keep the nearest rank low so it frames the field without hiding it.
				# The sun is in the east: only the nearer ranks on that side throw shadow onto
				# anything in view, so only they are drawn into the shadow map.
				spots.append([px, pz, _rng.range_f(3.6, 4.6) + rank * 0.9, side > 0.0 and rank < 2, rank])
			z += _rng.range_f(2.3, 3.1)
	# A wall of trees behind the far headquarters; nothing tall at the near end.
	var x := -9.5
	while x < 9.6:
		for rank in 3:
			spots.append([x + _rng.range_f(-0.7, 0.7), -21.6 - rank * 2.4 + _rng.range_f(-0.5, 0.5), _rng.range_f(4.2, 5.4) + rank * 0.6, rank == 0, rank])
		x += _rng.range_f(2.2, 3.0)
	for s: Array in spots:
		var pos := Vector3(s[0], height(s[0], s[1]) - 0.05, s[1])
		var planted := false
		if not kinds.is_empty():
			var model: String = kinds[_rng.range_i(0, kinds.size() - 1)]
			var tall: float = s[2] * (1.25 if model == "tree_pine" else 1.0)
			planted = _plant(model, pos, tall, s[3], 0.65 if int(s[4]) == 0 else 0.4)
		if not planted:
			_stand_in_tree(pos, s[2])
	# Bushes and undergrowth between the trunks and along the fences, logs here and there.
	var has_bush := Models.has_model("bush")
	for i in 44:
		var bx := _rng.range_f(9.9, 16.0) * (1.0 if _rng.next_f() < 0.5 else -1.0)
		var bz := _rng.range_f(-27.0, 23.0)
		if absf(bz) < 2.0:
			continue
		if has_bush:
			_plant("bush", Vector3(bx, height(bx, bz) - 0.03, bz), _rng.range_f(0.8, 1.4), false)
	for i in 12:
		var bx2 := _rng.range_f(-9.0, 9.0)
		var bz2 := _rng.range_f(19.4, 22.5)
		if has_bush:
			_plant("bush", Vector3(bx2, height(bx2, bz2) - 0.03, bz2), _rng.range_f(0.8, 1.3), false)
	_scatter_model("log", [Vector3(10.4, 0, -9.5), Vector3(-10.5, 0, 12.5), Vector3(-10.3, 0, -15.0), Vector3(10.6, 0, 17.5)], 1.6, 2.2)
	_scatter_model("rocks", [Vector3(-10.2, 0, -6.5), Vector3(10.1, 0, 9.2), Vector3(-9.9, 0, 19.3), Vector3(9.8, 0, -19.5)], 1.2, 1.8)


func _build_fences() -> void:
	for z: float in [-15.6, -12.0, -8.4, -4.8, 4.8, 8.4, 12.0, 15.6]:
		for side: float in [-1.0, 1.0]:
			var fence := Models.make("fence", 0)
			if fence == null:
				return
			Models.fit_footprint(fence, 0.4, 3.5)
			fence.position = Vector3(side * 9.55, 0.0, z)
			add_child(fence)
			for mi: MeshInstance3D in fence.find_children("*", "MeshInstance3D", true, false):
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.lod_bias = 0.6
				_shade_casters.append(mi)


# --- Harvest ---------------------------------------------------------------------------------

func _build_harvest() -> void:
	# Pumpkins by the fences and hay bales beside the wheat: cheap shapes, but they say autumn.
	var body := SphereMesh.new()
	body.radius = 0.32
	body.height = 0.5
	body.radial_segments = 10
	body.rings = 5
	var pm := MultiMesh.new()
	pm.transform_format = MultiMesh.TRANSFORM_3D
	pm.mesh = body
	var spots: Array = []
	for cluster: Array in [[10.2, -11.5], [-10.3, -7.5], [10.3, 4.0], [-10.2, 10.5], [10.4, 14.5], [-10.4, -15.0]]:
		for i in _rng.range_i(2, 4):
			spots.append([Vector3(cluster[0] + _rng.range_f(-0.5, 0.5), 0.2, cluster[1] + _rng.range_f(-0.8, 0.8)), _rng.range_f(0.7, 1.3)])
	pm.instance_count = spots.size()
	for i in spots.size():
		var size: float = spots[i][1]
		pm.set_instance_transform(i, Transform3D(Basis.from_euler(Vector3(0, _rng.range_f(0.0, TAU), 0)).scaled(Vector3.ONE * size),
				spots[i][0] * Vector3(1, size, 1)))
	var pumpkins := MultiMeshInstance3D.new()
	pumpkins.multimesh = pm
	pumpkins.material_override = _colour_mat(Color("f08214"), 0.6)
	add_child(pumpkins)

	var bale := CylinderMesh.new()
	bale.top_radius = 0.55
	bale.bottom_radius = 0.55
	bale.height = 0.8
	bale.radial_segments = 14
	for b: Array in [[11.9, -1.2, 0.3], [12.6, -8.8, 1.2], [-11.9, 3.4, 0.9], [-12.7, 10.6, 0.1], [11.4, -9.6, 2.0]]:
		var mi := MeshInstance3D.new()
		mi.mesh = bale
		mi.rotation = Vector3(0, b[2], PI * 0.5)
		mi.position = Vector3(b[0], 0.55, b[1])
		mi.material_override = _colour_mat(Color("e3bd4f"), 0.95)
		add_child(mi)


# --- Leaves ----------------------------------------------------------------------------------

func _build_leaves() -> void:
	var leaf_tex := _leaf_texture()
	# Fallen leaves: thick under the trees, a scattering blown onto the edges of the field.
	var lying := StandardMaterial3D.new()
	lying.albedo_texture = leaf_tex
	lying.vertex_color_use_as_albedo = true
	lying.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	lying.cull_mode = BaseMaterial3D.CULL_DISABLED
	lying.roughness = 0.9
	var flat := PlaneMesh.new()
	flat.size = Vector2(0.24, 0.24)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = flat
	var spots: Array = []
	for i in 2600:
		var x := _rng.range_f(-22.0, 22.0)
		var z := _rng.range_f(-29.0, 23.0)
		var on_field := absf(x) < FIELD_HALF_W and absf(z) < FIELD_HALF_L
		if on_field:
			# Only near the edges, and thinning quickly toward the middle.
			var from_edge := minf(FIELD_HALF_W - absf(x), FIELD_HALF_L - absf(z))
			if from_edge > 2.6:
				if _rng.next_f() > 0.06:
					continue                # a rare leaf blown out onto the lawn
			elif _rng.next_f() > 0.4:
				continue
		if absf(z) < 1.45:
			continue
		spots.append(Vector3(x, height(x, z) + 0.03, z))
	mm.instance_count = spots.size()
	for i in spots.size():
		var size := _rng.range_f(0.7, 1.4)
		var b := Basis.from_euler(Vector3(_rng.range_f(-0.25, 0.25), _rng.range_f(0.0, TAU), _rng.range_f(-0.25, 0.25))).scaled(Vector3.ONE * size)
		mm.set_instance_transform(i, Transform3D(b, spots[i]))
		mm.set_instance_color(i, _leaf_colour())
	var litter := MultiMeshInstance3D.new()
	litter.multimesh = mm
	litter.material_override = lying
	litter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(litter)

	# Falling leaves: a slow drift across the whole field, spinning as they come down.
	var falling := StandardMaterial3D.new()
	falling.albedo_texture = leaf_tex
	falling.vertex_color_use_as_albedo = true
	falling.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	falling.cull_mode = BaseMaterial3D.CULL_DISABLED
	falling.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	falling.roughness = 0.9
	var quad := QuadMesh.new()
	quad.size = Vector2(0.3, 0.3)
	quad.material = falling
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	ramp.colors = PackedColorArray([LEAVES[0], LEAVES[2], LEAVES[3], LEAVES[1], LEAVES[5]])
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.08, 0.85, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var p := CPUParticles3D.new()
	p.mesh = quad
	p.amount = 70
	p.lifetime = 6.5
	p.preprocess = 6.5
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(13.0, 0.6, 21.0)
	p.position = Vector3(-1.0, 6.5, -1.0)
	p.direction = Vector3(0.5, -1.0, 0.1)
	p.spread = 22.0
	p.gravity = Vector3(0.22, -0.16, 0.05)
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 1.0
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.angular_velocity_min = -140.0
	p.angular_velocity_max = 140.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.3
	p.color_initial_ramp = ramp
	p.color_ramp = fade
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	_extras.append(p)


# --- Light -----------------------------------------------------------------------------------

func _build_light_effects() -> void:
	# Motes in the sunlight: tiny bright specks drifting over the grass.
	var speck := StandardMaterial3D.new()
	speck.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	speck.albedo_color = Color(1.0, 0.92, 0.7)
	speck.vertex_color_use_as_albedo = true
	speck.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	speck.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	speck.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var dot := QuadMesh.new()
	dot.size = Vector2(0.09, 0.09)
	dot.material = speck
	var glow := Gradient.new()
	glow.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
	glow.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)])
	var motes := CPUParticles3D.new()
	motes.mesh = dot
	motes.amount = 60
	motes.lifetime = 7.0
	motes.preprocess = 7.0
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	motes.emission_box_extents = Vector3(11.0, 1.4, 17.0)
	motes.position = Vector3(0.0, 2.4, 0.0)
	motes.direction = Vector3(1.0, 0.3, 0.2)
	motes.spread = 60.0
	motes.gravity = Vector3(0.03, 0.02, 0.0)
	motes.initial_velocity_min = 0.05
	motes.initial_velocity_max = 0.25
	motes.color_ramp = glow
	motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(motes)
	_extras.append(motes)
