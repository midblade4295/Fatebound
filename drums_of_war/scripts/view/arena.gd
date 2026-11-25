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
const FIELD_HALF_L := 16.0
const FORD_X := 6.0
const WATER_Y := -0.12            # the water's surface; the grass is at 0
const DEEP := 1.15                # depth of the creek bed below the grass
const SHALLOW := 0.5              # ... at a ford
const BRIDGE_HALF_W := 1.45
const BRIDGE_HALF_L := 2.0
const BRIDGE_DECK := 0.62         # height of the bridge's roadway at its crown

const TREES := ["tree", "tree_oak", "tree_pine", "tree_birch"]

var _structure_spots: Array = []  # Vector2 (x, z) of each structure, for worn earth and clearings
var _rng: GsRng


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
	var far := _smooth(13.0, 22.0, absf(x)) + _smooth(19.0, 28.0, absf(z))
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
	var zs: Array = [-60.0, -40.0, -28.0, -20.0, -16.0, -12.0, -8.0, -5.0, -3.0, -2.0, -1.5, -1.3, -1.1, -0.9, -0.7, -0.5, -0.25,
			0.0, 0.25, 0.5, 0.7, 0.9, 1.1, 1.3, 1.5, 2.0, 3.0, 5.0, 8.0, 12.0, 16.0, 20.0, 28.0, 40.0, 60.0]
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
	mat.shader = Shader.new()
	mat.shader.code = """
shader_type spatial;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform vec2 worn[6];
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float n1 = texture(noise, wp.xz * 0.035).r;
	float n2 = texture(noise, wp.xz * 0.21 + vec2(0.37, 0.11)).r;
	float n3 = texture(noise, wp.xz * 0.9).r;
	float in_field = smoothstep(0.0, 0.7, 9.0 - abs(wp.x)) * smoothstep(0.0, 0.7, 16.0 - abs(wp.z));
	// The field: bright, soft mowing stripes, mottled so it is not a flat colour.
	float stripe = smoothstep(0.42, 0.58, fract(wp.z * 0.25));
	vec3 field = mix(vec3(0.33, 0.66, 0.19), vec3(0.42, 0.75, 0.24), stripe * 0.55 + (n2 - 0.5) * 0.7);
	field *= 0.9 + 0.2 * n1;
	// The meadow around it: deeper greens, patchy, flecked with wildflowers.
	vec3 meadow = mix(vec3(0.16, 0.42, 0.13), vec3(0.3, 0.58, 0.18), n1) * (0.85 + 0.3 * n2);
	float fleck = smoothstep(0.8, 0.84, n3) * (1.0 - in_field);
	meadow = mix(meadow, vec3(0.98, 0.92, 0.5), fleck * 0.55);
	vec3 col = mix(meadow, field, in_field);
	// Worn earth: the road over the bridge, the approaches to the fords, around the works.
	float path = (1.0 - smoothstep(0.6, 1.3, abs(wp.x))) * (1.0 - smoothstep(9.0, 13.5, abs(wp.z))) * 0.75;
	path = max(path, (1.0 - smoothstep(0.9, 1.9, abs(abs(wp.x) - 6.0))) * (1.0 - smoothstep(1.6, 3.6, abs(wp.z))) * 0.85);
	for (int i = 0; i < 6; i++) {
		path = max(path, (1.0 - smoothstep(1.5, 2.9, distance(wp.xz, worn[i]))) * 0.8);
	}
	path = clamp(path * (0.35 + 1.1 * n2), 0.0, 1.0);
	col = mix(col, vec3(0.55, 0.42, 0.26) * (0.85 + 0.3 * n3), path);
	// Banks of sand and gravel, then the darker bed under the water.
	float bank = smoothstep(-0.02, -0.22, wp.y);
	col = mix(col, vec3(0.78, 0.7, 0.5) * (0.82 + 0.36 * n3), bank);
	col = mix(col, vec3(0.3, 0.33, 0.27) * (0.8 + 0.4 * n3), smoothstep(-0.55, -1.05, wp.y));
	ALBEDO = pow(col, vec3(2.2));       // the colours above are written as seen on screen
	ROUGHNESS = 0.95;
}
"""
	mat.set_shader_parameter("noise", _noise(0.02, 7))
	var worn := PackedVector2Array()
	for i in 6:
		worn.append(_structure_spots[i] if i < _structure_spots.size() else Vector2(999, 999))
	mat.set_shader_parameter("worn", worn)
	ground.material_override = mat
	add_child(ground)


func _build_water() -> void:
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(96.0, 2.9)
	water.mesh = plane
	water.position = Vector3(0.0, WATER_Y, 0.0)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	# The depth of water at any point is worked out from the same channel shape the ground mesh
	# uses, so the shallows, the fords and the foam line need no depth texture.
	mat.shader.code = """
shader_type spatial;
render_mode blend_mix, cull_back, specular_schlick_ggx;
uniform sampler2D wave_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D wave_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D foam_noise : filter_linear_mipmap, repeat_enable;
uniform vec3 shallow_col : source_color;
uniform vec3 deep_col : source_color;
uniform vec3 sky_col : source_color;
uniform float surface;
uniform float deep;
uniform float shallow;
varying vec3 wp;
float bed(vec2 p) {
	float ford = max(1.0 - smoothstep(1.3, 2.0, abs(p.x + 6.0)), 1.0 - smoothstep(1.3, 2.0, abs(p.x - 6.0)));
	return mix(deep, shallow, ford) * (1.0 - smoothstep(0.55, 1.3, abs(p.y)));
}
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float depth = max(0.0, bed(wp.xz) + surface);
	float d01 = clamp(depth / 0.95, 0.0, 1.0);
	vec2 flow = vec2(TIME * 0.2, 0.0);
	vec3 na = texture(wave_a, wp.xz * 0.21 - flow * 0.55 + vec2(0.0, TIME * 0.025)).rgb;
	vec3 nb = texture(wave_b, wp.xz * 0.46 - flow).rgb;
	NORMAL_MAP = mix(na, nb, 0.5);
	NORMAL_MAP_DEPTH = 1.1 + 0.8 * (1.0 - d01);       // choppier over the shallows
	vec3 col = mix(shallow_col, deep_col, smoothstep(0.0, 1.0, d01));
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	col = mix(col, sky_col, fres * 0.55);
	// Foam where the water runs thin: the line along each bank and the riffles over the fords.
	float fn = texture(foam_noise, wp.xz * 0.55 - flow * 1.6).r;
	float fn2 = texture(foam_noise, wp.xz * 1.3 - flow * 2.4 + vec2(0.4, 0.2)).r;
	float edge = (1.0 - smoothstep(0.02, 0.2, depth)) * smoothstep(0.32, 0.6, fn + 0.25);
	float riffle = (1.0 - smoothstep(0.24, 0.46, depth)) * smoothstep(0.56, 0.7, fn) * smoothstep(0.4, 0.6, fn2);
	float foam = clamp(edge * 0.9 + riffle * 0.8, 0.0, 1.0);
	ALBEDO = mix(col, vec3(1.0), foam);
	ALPHA = clamp(mix(0.42, 0.94, d01) + foam * 0.5, 0.0, 1.0) * smoothstep(0.0, 0.035, depth);
	ROUGHNESS = mix(0.05, 0.45, foam);
	SPECULAR = 0.85;
	METALLIC = 0.15;
}
"""
	mat.set_shader_parameter("wave_a", _noise(0.035, 11, true))
	mat.set_shader_parameter("wave_b", _noise(0.06, 23, true))
	mat.set_shader_parameter("foam_noise", _noise(0.05, 31))
	mat.set_shader_parameter("shallow_col", Color("58c6c0"))
	mat.set_shader_parameter("deep_col", Color("1d5f8f"))
	mat.set_shader_parameter("sky_col", Color("cfe9ff"))
	mat.set_shader_parameter("surface", WATER_Y)
	mat.set_shader_parameter("deep", DEEP)
	mat.set_shader_parameter("shallow", SHALLOW)
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
	_scatter_model("rocks", [Vector3(-12.5, 0, 1.6), Vector3(11.8, 0, -1.8), Vector3(-3.2, 0, 1.75), Vector3(3.4, 0, -1.7),
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


# --- Grass ---------------------------------------------------------------------------------

func _blade_mesh() -> ArrayMesh:
	# One tuft: seven tapering blades fanned out from a point. Vertex colour red is the height
	# along the blade (0 at the root, 1 at the tip); the shader uses it for colour and sway.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 9:
		var a := TAU * i / 9.0 + (i % 2) * 0.4
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
	for i in 1500:
		var x := _rng.range_f(-FIELD_HALF_W, FIELD_HALF_W)
		var z := _rng.range_f(-FIELD_HALF_L, FIELD_HALF_L)
		if absf(z) < 1.6 or not _clear_of_structures(x, z, 2.3) or (absf(x) < 1.0 and absf(z) < 12.0):
			continue
		tufts.append([Vector3(x, 0, z), _rng.range_f(0.4, 0.7), Color(0.36, 0.7, 0.2).lerp(Color(0.44, 0.78, 0.25), _rng.next_f())])
	# Tall and thick in the meadow all round it.
	for i in 8500:
		var x := _rng.range_f(-24.0, 24.0)
		var z := _rng.range_f(-27.0, 22.0)
		if absf(x) < FIELD_HALF_W + 0.2 and absf(z) < FIELD_HALF_L + 0.2:
			continue
		if absf(z) < 1.5:
			continue
		tufts.append([Vector3(x, height(x, z), z), _rng.range_f(1.1, 2.1), Color(0.2, 0.5, 0.15).lerp(Color(0.38, 0.66, 0.2), _rng.next_f())])
	# Reeds along both banks, away from the crossings.
	for i in 520:
		var x := _rng.range_f(-24.0, 24.0)
		if absf(absf(x) - FORD_X) < 2.0 or absf(x) < 1.9:
			continue
		var z := _rng.range_f(1.25, 1.75) * (1.0 if _rng.next_f() < 0.5 else -1.0)
		tufts.append([Vector3(x, height(x, z), z), _rng.range_f(1.7, 2.9), Color(0.3, 0.5, 0.16).lerp(Color(0.5, 0.62, 0.2), _rng.next_f())])
	# Two patches of ripe wheat beyond the fences.
	for patch: Array in [[11.6, -5.0, 1.5, 3.2], [-11.7, 7.0, 1.5, 2.8]]:
		for i in 700:
			var x: float = patch[0] + _rng.range_f(-patch[2], patch[2])
			var z: float = patch[1] + _rng.range_f(-patch[3], patch[3])
			tufts.append([Vector3(x, height(x, z), z), _rng.range_f(2.0, 2.6), Color(0.98, 0.8, 0.28).lerp(Color(0.9, 0.68, 0.2), _rng.next_f())])

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _blade_mesh()
	mm.instance_count = tufts.size()
	for i in tufts.size():
		var size: float = tufts[i][1]
		var b := Basis.from_euler(Vector3(0, _rng.range_f(0.0, TAU), 0)).scaled(Vector3(size, size, size))
		mm.set_instance_transform(i, Transform3D(b, tufts[i][0]))
		mm.set_instance_custom_data(i, tufts[i][2])
	var grass := MultiMeshInstance3D.new()
	grass.multimesh = mm
	grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = """
shader_type spatial;
render_mode cull_disabled;
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
	ALBEDO = pow(tint * mix(0.55, 1.1, along), vec3(2.2));
	ROUGHNESS = 0.9;
}
"""
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
		var z := _rng.range_f(-25.0, 21.0)
		if (absf(x) < FIELD_HALF_W + 0.3 and absf(z) < FIELD_HALF_L + 0.3) or absf(z) < 1.6:
			continue
		flowers.append(Vector3(x, height(x, z) + _rng.range_f(0.35, 0.6), z))
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
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform float y_min;
uniform float y_size;
instance uniform vec3 tint = vec3(1.0);
instance uniform float sway = 0.0;
void vertex() {
	float h = clamp((VERTEX.y - y_min) / y_size, 0.0, 1.0);
	float w = smoothstep(0.3, 1.0, h);
	float t = TIME * 1.25 + sway;
	VERTEX.x += sin(t + VERTEX.y * 3.0 / y_size) * 0.018 * y_size * w;
	VERTEX.z += cos(t * 0.8 + VERTEX.x * 2.0 / y_size) * 0.014 * y_size * w;
}
void fragment() {
	ALBEDO = texture(albedo_tex, UV).rgb * tint;
	ROUGHNESS = 0.9;
}
"""

var _foliage_shader: Shader = null
var _foliage_mats: Dictionary = {}


## A tree or bush from a generated model, with leaves that stir and its own shade of green.
func _plant(model: String, pos: Vector3, tall: float) -> bool:
	var node := Models.make(model, 0)
	if node == null:
		return false
	Models.fit_height(node, tall)
	node.position = pos
	node.rotation.y = _rng.range_f(0.0, TAU)
	if _foliage_shader == null:
		_foliage_shader = Shader.new()
		_foliage_shader.code = FOLIAGE_SHADER
	var shade := _rng.range_f(0.5, 0.82)
	var tint := Vector3(shade * _rng.range_f(0.8, 0.98), shade, shade * _rng.range_f(0.9, 1.15))
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
		mi.set_instance_shader_parameter("tint", tint)
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
		var z := -27.0
		while z < 20.5:
			for rank in 4:
				var px := side * (10.9 + rank * 2.5 + _rng.range_f(-0.5, 0.7))
				var pz := z + _rng.range_f(-1.0, 1.0) + rank * 0.7
				if absf(pz) < 2.4:
					continue
				# Keep the nearest rank low so it frames the field without hiding it.
				spots.append([px, pz, _rng.range_f(3.6, 4.6) + rank * 0.9])
			z += _rng.range_f(2.3, 3.1)
	# A wall of trees behind the far headquarters; nothing tall at the near end.
	var x := -9.5
	while x < 9.6:
		for rank in 3:
			spots.append([x + _rng.range_f(-0.7, 0.7), -19.6 - rank * 2.4 + _rng.range_f(-0.5, 0.5), _rng.range_f(4.2, 5.4) + rank * 0.6])
		x += _rng.range_f(2.2, 3.0)
	for s: Array in spots:
		var pos := Vector3(s[0], height(s[0], s[1]) - 0.05, s[1])
		var planted := false
		if not kinds.is_empty():
			var model: String = kinds[_rng.range_i(0, kinds.size() - 1)]
			var tall: float = s[2] * (1.25 if model == "tree_pine" else 1.0)
			planted = _plant(model, pos, tall)
		if not planted:
			_stand_in_tree(pos, s[2])
	# Bushes and undergrowth between the trunks and along the fences, logs here and there.
	var has_bush := Models.has_model("bush")
	for i in 70:
		var bx := _rng.range_f(9.9, 20.0) * (1.0 if _rng.next_f() < 0.5 else -1.0)
		var bz := _rng.range_f(-25.0, 21.0)
		if absf(bz) < 2.0:
			continue
		if has_bush:
			_plant("bush", Vector3(bx, height(bx, bz) - 0.03, bz), _rng.range_f(0.8, 1.4))
	for i in 12:
		var bx2 := _rng.range_f(-9.0, 9.0)
		var bz2 := _rng.range_f(17.2, 20.5)
		if has_bush:
			_plant("bush", Vector3(bx2, height(bx2, bz2) - 0.03, bz2), _rng.range_f(0.8, 1.3))
	_scatter_model("log", [Vector3(10.4, 0, -9.5), Vector3(-10.5, 0, 12.5), Vector3(-10.3, 0, -14.0), Vector3(10.6, 0, 16.0)], 1.6, 2.2)
	_scatter_model("rocks", [Vector3(-10.2, 0, -6.5), Vector3(10.1, 0, 9.2), Vector3(-9.9, 0, 17.4), Vector3(9.8, 0, -17.6)], 1.2, 1.8)


func _build_fences() -> void:
	for z: float in [-13.2, -9.6, -6.0, 6.0, 9.6, 13.2]:
		for side: float in [-1.0, 1.0]:
			var fence := Models.make("fence", 0)
			if fence == null:
				return
			Models.fit_footprint(fence, 0.4, 3.5)
			fence.position = Vector3(side * 9.55, 0.0, z)
			add_child(fence)
