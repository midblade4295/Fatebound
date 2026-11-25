extends Node3D
## The 3D battlefield: arena, structures, regiments and effects, drawn from the rules engine's
## state every frame. It owns no rules. The battle screen feeds it the sim and its events and
## asks it to convert between field positions and screen positions.

const Sim = preload("res://scripts/sim/battle_sim.gd")
const Models = preload("res://scripts/view/models.gd")
const Drill = preload("res://scripts/view/musket_drill.gd").Drill

const COL_BLUE := Color("2456c9")
const COL_RED := Color("c81e3a")
const COL_GRASS_A := Color("74cc4e")
const COL_GRASS_B := Color("67bf45")
const COL_MEADOW := Color("4f9d3a")
const COL_CREEK := Color("3fa9f5")
const COL_CREEK_LIGHT := Color("bfe6ff")
const COL_FORD := Color("8fd0f7")
const COL_STONE := Color("b9b2a3")
const COL_WOOD := Color("9a6a3c")
const COL_BRASS := Color("f2b632")
const COL_SMOKE := Color("fff8ec")

const SOLDIER_SPACING := 0.95
const MAX_PUFFS := 220

var sim: Sim
var local_side: int = 0
var camera: Camera3D
var field_rect_design := Rect2(2.0, 50.0, 536.0, 758.0)   # where the field must fit on the 540 x 960 screen

var _regiments: Dictionary = {}       # regiment id -> RegimentView
var _structures: Dictionary = {}      # structure id -> Node3D
var _structure_dead: Dictionary = {}
var _leaving: Array = []              # soldiers playing their fall after their regiment is gone
var _puffs: Array = []                # {pos, vel, age, life, size}
var _puff_mesh: MultiMeshInstance3D
var _flashes: Array = []              # {node, age, life}
var _materials: Dictionary = {}
var _time: float = 0.0
var cheering_side: int = -1      # the winners, once the match is over


# ==========================================================================================
# Coordinates
# ==========================================================================================

func to_world(p: Vector2, height: float = 0.0) -> Vector3:
	if local_side == 0:
		return Vector3(p.x - Sim.FIELD_W * 0.5, height, Sim.FIELD_H * 0.5 - p.y)
	return Vector3(Sim.FIELD_W * 0.5 - p.x, height, p.y - Sim.FIELD_H * 0.5)


## Height of the ground a regiment stands on at a field position: 0 on grass, raised over the
## bridge, lowered where a ford is waded.
func ground_height(_p: Vector2) -> float:
	return 0.0


func dir_to_world(d: Vector2) -> Vector3:
	return Vector3(d.x, 0.0, -d.y) if local_side == 0 else Vector3(-d.x, 0.0, d.y)


## Field position (and height above the ground) to a position on the 540 x 960 design screen.
func project(p: Vector2, height: float = 0.0) -> Vector2:
	# Camera3D works in the viewport's visible rect, which in this project's stretch mode is
	# already the 540 x 960 design space, so no further conversion is needed.
	return camera.unproject_position(to_world(p, height))


## Design-screen position to the field position under it.
func pick(design_pos: Vector2) -> Vector2:
	var from := camera.project_ray_origin(design_pos)
	var dir := camera.project_ray_normal(design_pos)
	if absf(dir.y) < 0.0001:
		return Vector2(-1, -1)
	var hit := from + dir * (-from.y / dir.y)
	if local_side == 0:
		return Vector2(hit.x + Sim.FIELD_W * 0.5, Sim.FIELD_H * 0.5 - hit.z)
	return Vector2(Sim.FIELD_W * 0.5 - hit.x, hit.z + Sim.FIELD_H * 0.5)


# ==========================================================================================
# Setup
# ==========================================================================================

func _ready() -> void:
	_build_environment()
	_build_arena()
	_build_puffs()
	get_viewport().size_changed.connect(fit_camera)
	fit_camera()


func _mat(colour: Color, roughness: float = 0.85, unshaded: bool = false) -> StandardMaterial3D:
	var key := "%s|%.2f|%s" % [colour.to_html(), roughness, unshaded]
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = colour
		m.roughness = roughness
		if colour.a < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if unshaded:
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_materials[key] = m
	return _materials[key]


func _box(parent: Node3D, size: Vector3, pos: Vector3, colour: Color, shadow: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _mat(colour)
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _cyl(parent: Node3D, radius: float, height: float, pos: Vector3, colour: Color, top_radius: float = -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.height = height
	mesh.radial_segments = 14
	mesh.rings = 1
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _mat(colour)
	parent.add_child(mi)
	return mi


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("8ecbff")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("a9d3ff")       # cool sky-blue fill in the shadows
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.04
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()             # warm golden-hour key light
	sun.light_color = Color("ffdca6")
	sun.light_energy = 1.05
	sun.rotation_degrees = Vector3(-44.0, 32.0, 0.0)      # from behind the camera's right shoulder, so the faces you see are lit
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 70.0
	sun.shadow_bias = 0.06
	add_child(sun)

	var rim := DirectionalLight3D.new()             # crisp cool rim from behind the field
	rim.light_color = Color("cfe6ff")
	rim.light_energy = 0.35
	rim.rotation_degrees = Vector3(-30.0, 168.0, 0.0)     # from beyond the far end, back toward the camera
	rim.shadow_enabled = false
	add_child(rim)

	camera = Camera3D.new()
	camera.fov = 26.0
	camera.near = 1.0
	camera.far = 200.0
	add_child(camera)
	camera.make_current()


## Places the camera so the whole field sits inside field_rect_design, whatever the window size.
func fit_camera() -> void:
	if camera == null or not is_inside_tree():
		return
	var pitch := deg_to_rad(50.0)
	var back := Vector3(0.0, sin(pitch), cos(pitch))
	var dist := 60.0
	var look_z := 0.0
	var hw := Sim.FIELD_W * 0.5
	var hh := Sim.FIELD_H * 0.5
	var pts := [Vector3(-hw, 0, hh), Vector3(hw, 0, hh), Vector3(-hw, 0, -hh), Vector3(hw, 0, -hh),
			Vector3(0, 5.2, -hh + 2.5)]
	for step in 14:
		camera.look_at_from_position(Vector3(0, 0, look_z) + back * dist, Vector3(0, 0, look_z), Vector3.UP)
		var box := Rect2()
		for i in pts.size():
			var s: Vector2 = camera.unproject_position(pts[i])
			box = Rect2(s, Vector2.ZERO) if i == 0 else box.expand(s)
		if box.size.x < 1.0 or box.size.y < 1.0:
			break
		var scale_by := minf(field_rect_design.size.x / box.size.x, field_rect_design.size.y / box.size.y)
		dist /= lerpf(1.0, scale_by, 0.85)
		# Move the look point along the field until the box is centred vertically.
		var here := camera.unproject_position(Vector3(0, 0, look_z)).y
		var there := camera.unproject_position(Vector3(0, 0, look_z + 1.0)).y
		var per_unit := there - here
		if absf(per_unit) > 0.01:
			look_z += clampf((field_rect_design.get_center().y - box.get_center().y) / per_unit * -1.0, -4.0, 4.0) * 0.8
	camera.look_at_from_position(Vector3(0, 0, look_z) + back * dist, Vector3(0, 0, look_z), Vector3.UP)


func _build_arena() -> void:
	var arena := Node3D.new()
	arena.name = "Arena"
	add_child(arena)

	# Meadow all around, then the mown field with its stripes.
	var meadow := MeshInstance3D.new()
	var meadow_mesh := PlaneMesh.new()
	meadow_mesh.size = Vector2(90.0, 110.0)
	meadow.mesh = meadow_mesh
	meadow.position = Vector3(0, -0.02, 0)
	meadow.material_override = _mat(COL_MEADOW, 0.95)
	arena.add_child(meadow)

	var field := MeshInstance3D.new()
	var field_mesh := PlaneMesh.new()
	field_mesh.size = Vector2(Sim.FIELD_W, Sim.FIELD_H)
	field.mesh = field_mesh
	var grass := ShaderMaterial.new()
	grass.shader = Shader.new()
	grass.shader.code = """
shader_type spatial;
uniform vec3 a : source_color;
uniform vec3 b : source_color;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float stripe = step(0.5, fract(wp.z * 0.25));
	float edge = smoothstep(0.0, 0.5, min(9.0 - abs(wp.x), 16.0 - abs(wp.z)));
	ALBEDO = mix(a, b, stripe) * mix(0.82, 1.0, edge);
	ROUGHNESS = 0.92;
}
"""
	grass.set_shader_parameter("a", COL_GRASS_A)
	grass.set_shader_parameter("b", COL_GRASS_B)
	field.material_override = grass
	arena.add_child(field)

	# The creek runs the full width of the view, not just the field.
	var creek_len := (Sim.CREEK_Y1 - Sim.CREEK_Y0)
	var creek_z := to_world(Vector2(0, (Sim.CREEK_Y0 + Sim.CREEK_Y1) * 0.5)).z
	var creek := MeshInstance3D.new()
	var creek_mesh := PlaneMesh.new()
	creek_mesh.size = Vector2(90.0, creek_len)
	creek.mesh = creek_mesh
	creek.position = Vector3(0, 0.03, creek_z)
	var water := ShaderMaterial.new()
	water.shader = Shader.new()
	water.shader.code = """
shader_type spatial;
uniform vec3 deep : source_color;
uniform vec3 light : source_color;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float w = sin(wp.x * 2.6 + TIME * 1.4 + sin(wp.z * 5.0 + TIME) * 1.3) * 0.5 + 0.5;
	float w2 = sin(wp.x * 5.1 - TIME * 0.9 + wp.z * 3.0) * 0.5 + 0.5;
	ALBEDO = mix(deep, light, smoothstep(0.86, 1.0, w) * 0.3 + smoothstep(0.93, 1.0, w2) * 0.18);
	ROUGHNESS = 0.25;
	SPECULAR = 0.6;
}
"""
	water.set_shader_parameter("deep", COL_CREEK)
	water.set_shader_parameter("light", COL_CREEK_LIGHT)
	creek.material_override = water
	arena.add_child(creek)
	# Banks
	for sign_z in [-1.0, 1.0]:
		_box(arena, Vector3(90.0, 0.08, 0.22), Vector3(0, 0.02, creek_z + sign_z * (creek_len * 0.5 + 0.08)), Color("d9c9a0"), false)

	for c: Dictionary in Sim.CROSSINGS:
		var cx := to_world(Vector2(float(c["x"]), 0)).x
		var half := float(c["half"])
		if bool(c["ford"]):
			var ford := MeshInstance3D.new()
			var fm := PlaneMesh.new()
			fm.size = Vector2(half * 2.0, creek_len + 0.3)
			ford.mesh = fm
			ford.position = Vector3(cx, 0.045, creek_z)
			ford.material_override = _mat(Color(COL_FORD, 0.7), 0.6)
			arena.add_child(ford)
			for k in 9:
				var pebble := MeshInstance3D.new()
				var pm := SphereMesh.new()
				pm.radius = 0.11 + 0.04 * (k % 3)
				pm.height = pm.radius * 1.1
				pm.radial_segments = 8
				pm.rings = 4
				pebble.mesh = pm
				pebble.position = Vector3(cx + sin(k * 1.7) * (half - 0.25), 0.05, creek_z + sin(k * 2.4) * creek_len * 0.4)
				pebble.material_override = _mat(Color("e8e2d2"))
				arena.add_child(pebble)
		else:
			var bridge := Models.make("bridge", 0)
			if bridge != null:
				Models.fit_footprint(bridge, half * 2.0 + 0.5, creek_len + 1.4)
				bridge.position = Vector3(cx, 0.0, creek_z)
				arena.add_child(bridge)
			else:
				_box(arena, Vector3(half * 2.0, 0.34, creek_len + 1.0), Vector3(cx, 0.1, creek_z), COL_STONE)
				for sx in [-1.0, 1.0]:
					_box(arena, Vector3(0.24, 0.5, creek_len + 1.0), Vector3(cx + sx * (half - 0.12), 0.42, creek_z), COL_STONE.darkened(0.12))

	# Scenery along both edges: trees, a wheat patch and fences. Never on the field itself.
	var spots := [[-10.6, -13.0, 1.0], [10.7, -9.0, 1.15], [-10.9, -3.5, 0.9], [10.6, 4.5, 1.0],
			[-10.5, 9.5, 1.1], [10.9, 13.0, 0.95], [-11.3, 15.2, 1.2], [11.2, -15.0, 1.05], [-10.4, 3.2, 0.8]]
	for s: Array in spots:
		_add_tree(arena, Vector3(s[0], 0, s[1]), s[2])
	_box(arena, Vector3(2.2, 0.5, 5.0), Vector3(11.4, 0.25, -3.0), Color("f0c444"))        # wheat
	_box(arena, Vector3(2.2, 0.5, 4.0), Vector3(-11.4, 0.25, 6.4), Color("f0c444"))
	for z in [-12.0, -6.0, 6.0, 12.0]:
		for sx in [-1.0, 1.0]:
			_add_fence(arena, Vector3(sx * 9.45, 0, z))

	for s: Sim.Structure in sim.structures:
		var node := _build_structure(s)
		node.position = to_world(s.pos)
		if s.side != local_side and s.kind != "hq":
			node.rotation.y = PI            # enemy guns point at you; both farmhouses show their porch
		arena.add_child(node)
		_structures[s.id] = node
		_structure_dead[s.id] = false


func _add_tree(parent: Node3D, pos: Vector3, scale_by: float) -> void:
	var tree := Models.make("tree", 0)
	if tree != null:
		Models.fit_height(tree, 2.6 * scale_by)
		tree.position = pos
		tree.rotation.y = pos.z * 1.7
		parent.add_child(tree)
		return
	var t := Node3D.new()
	t.position = pos
	t.scale = Vector3.ONE * scale_by
	_cyl(t, 0.22, 0.9, Vector3(0, 0.45, 0), COL_WOOD.darkened(0.2), 0.16)
	for b: Array in [[0.0, 1.5, 0.0, 0.95], [0.45, 1.25, 0.2, 0.62], [-0.4, 1.3, -0.25, 0.66], [0.05, 2.05, 0.05, 0.6]]:
		var blob := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = b[3]
		sm.height = b[3] * 1.8
		sm.radial_segments = 12
		sm.rings = 6
		blob.mesh = sm
		blob.position = Vector3(b[0], b[1], b[2])
		blob.material_override = _mat(Color("3f9a3c") if b[3] > 0.7 else Color("4eac45"))
		t.add_child(blob)
	parent.add_child(t)


func _add_fence(parent: Node3D, pos: Vector3) -> void:
	var fence := Models.make("fence", 0)
	if fence != null:
		Models.fit_footprint(fence, 0.3, 3.4)
		fence.position = pos
		parent.add_child(fence)
		return
	for k in 3:
		_box(parent, Vector3(0.14, 0.62, 0.14), pos + Vector3(0, 0.31, (k - 1) * 1.5), COL_WOOD)
	for h in [0.26, 0.5]:
		_box(parent, Vector3(0.08, 0.09, 3.3), pos + Vector3(0, h, 0), COL_WOOD.lightened(0.1))


func team_colour(side: int) -> Color:
	return COL_BLUE if side == local_side else COL_RED


func _build_structure(s: Sim.Structure) -> Node3D:
	var team := 0 if s.side == local_side else 1
	var root := Node3D.new()
	var col := team_colour(s.side)
	var made: Node3D = Models.make("farmhouse" if s.kind == "hq" else "battery", team)
	if made != null:
		if s.kind == "hq":
			Models.fit_footprint(made, 4.4, 4.4)
		else:
			Models.fit_footprint(made, 3.3, 3.3)
		root.add_child(made)
		return root
	if made == null:
		root.scale = Vector3.ONE * 1.25
	if s.kind == "hq":
		_box(root, Vector3(3.0, 1.5, 2.3), Vector3(0, 0.75, 0), Color("d9b98a"))
		var roof := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(3.5, 1.2, 2.7)
		roof.mesh = prism
		roof.position = Vector3(0, 2.1, 0)
		roof.material_override = _mat(col)
		root.add_child(roof)
		_box(root, Vector3(0.45, 1.1, 0.45), Vector3(0.9, 2.3, -0.4), COL_STONE)
		_box(root, Vector3(0.5, 0.9, 0.08), Vector3(0, 0.45, -1.17), COL_WOOD.darkened(0.2))
		_cyl(root, 0.05, 2.2, Vector3(-1.1, 2.6, 0.6), COL_WOOD.darkened(0.3))
		_box(root, Vector3(0.9, 0.5, 0.04), Vector3(-0.62, 3.4, 0.6), col)
	else:
		for k in 12:
			var a := TAU * k / 12.0
			if absf(angle_difference(a, -PI * 0.5)) < 0.45:
				continue                    # the embrasure the gun fires through
			var post := _cyl(root, 0.26, 0.85, Vector3(cos(a) * 1.05, 0.42, sin(a) * 1.05), COL_WOOD)
			post.rotation.y = a
		_cyl(root, 1.0, 0.12, Vector3(0, 0.06, 0), Color("c9b48a"))
		var barrel := _cyl(root, 0.17, 1.3, Vector3(0, 0.62, -0.75), COL_BRASS, 0.13)
		barrel.rotation.x = -PI * 0.5
		for sx in [-1.0, 1.0]:
			var wheel := _cyl(root, 0.36, 0.1, Vector3(sx * 0.36, 0.36, -0.2), COL_WOOD.darkened(0.3))
			wheel.rotation.z = PI * 0.5
		_box(root, Vector3(1.5, 0.06, 1.2), Vector3(0, 1.5, 0.25), col)
		for corner: Array in [[-0.7, -0.3], [0.7, -0.3], [-0.7, 0.8], [0.7, 0.8]]:
			_cyl(root, 0.04, 1.5, Vector3(corner[0], 0.75, corner[1]), COL_WOOD.darkened(0.3))
	return root


func _build_puffs() -> void:
	_puff_mesh = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 12
	sphere.rings = 6
	mm.mesh = sphere
	mm.instance_count = MAX_PUFFS
	mm.visible_instance_count = 0
	_puff_mesh.multimesh = mm
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 1.0
	m.emission_enabled = true
	m.emission = Color("fff3e0")
	m.emission_energy_multiplier = 0.35
	_puff_mesh.material_override = m
	_puff_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_puff_mesh)


# ==========================================================================================
# Per-frame sync
# ==========================================================================================

func reset(new_sim: Sim) -> void:
	sim = new_sim
	for id in _regiments.keys():
		_regiments[id].root.queue_free()
	_regiments.clear()
	for e: Dictionary in _leaving:
		e["node"].queue_free()
	_leaving.clear()
	_puffs.clear()
	for f: Dictionary in _flashes:
		f["node"].queue_free()
	_flashes.clear()
	for s: Sim.Structure in sim.structures:
		if _structures.has(s.id):
			var node: Node3D = _structures[s.id]
			node.scale = Vector3.ONE
			node.position.y = 0.0
			_structure_dead[s.id] = false
	cheering_side = -1


func _process(delta: float) -> void:
	if sim == null:
		return
	_time += delta
	var seen := {}
	for r: Sim.Regiment in sim.regiments:
		seen[r.id] = true
		if not _regiments.has(r.id):
			_regiments[r.id] = RegimentView.new(self, r)
		_regiments[r.id].sync(r, delta)
	for id in _regiments.keys():
		if not seen.has(id):
			_regiments[id].release()
			_regiments.erase(id)
	for s: Sim.Structure in sim.structures:
		if s.dead and not _structure_dead.get(s.id, false):
			_structure_dead[s.id] = true
		if _structure_dead.get(s.id, false):
			var node: Node3D = _structures[s.id]
			node.scale.y = lerpf(node.scale.y, 0.22, 1.0 - exp(-6.0 * delta))
	_update_leaving(delta)
	_update_puffs(delta)
	_update_flashes(delta)


func _update_leaving(delta: float) -> void:
	for e: Dictionary in _leaving:
		e["age"] = float(e["age"]) + delta
		var node: Node3D = e["node"]
		var t := float(e["age"])
		if not bool(e["animated"]):
			node.rotation.x = lerpf(node.rotation.x, -PI * 0.5, 1.0 - exp(-9.0 * delta))
		if t > 1.1:
			node.position.y -= delta * 0.6
	var keep: Array = []
	for e: Dictionary in _leaving:
		if float(e["age"]) < 1.9:
			keep.append(e)
		else:
			e["node"].queue_free()
	_leaving = keep


func drop_soldier(node: Node3D, animated: bool) -> void:
	var at := node.global_transform
	node.get_parent().remove_child(node)
	add_child(node)
	node.global_transform = at
	_leaving.append({"node": node, "age": 0.0, "animated": animated})


# --- Effects --------------------------------------------------------------------------------

func puff(field_pos: Vector2, height: float, size: float, life: float) -> void:
	if _puffs.size() >= MAX_PUFFS:
		_puffs.pop_front()
	var w := to_world(field_pos, height)
	_puffs.append({"pos": w, "vel": Vector3(0.35 + sin(w.z * 3.1) * 0.15, 0.32 + cos(w.x * 2.3) * 0.1, 0.0),
			"age": 0.0, "life": life, "size": size})


func _update_puffs(delta: float) -> void:
	var mm := _puff_mesh.multimesh
	var keep: Array = []
	for p: Dictionary in _puffs:
		p["age"] = float(p["age"]) + delta
		if float(p["age"]) < float(p["life"]):
			p["pos"] = Vector3(p["pos"]) + Vector3(p["vel"]) * delta
			keep.append(p)
	_puffs = keep
	mm.visible_instance_count = _puffs.size()
	for i in _puffs.size():
		var p: Dictionary = _puffs[i]
		var t := float(p["age"]) / float(p["life"])
		var grow := float(p["size"]) * (0.55 + 1.1 * (1.0 - pow(1.0 - t, 2.0)))
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * grow), p["pos"]))
		mm.set_instance_color(i, Color(COL_SMOKE, 0.95 * (1.0 - t * t)))


func flash(field_pos: Vector2, height: float, size: float) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = size * 0.5
	sm.height = size
	sm.radial_segments = 10
	sm.rings = 5
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color("ff8a1f")
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = to_world(field_pos, height)
	add_child(mi)
	_flashes.append({"node": mi, "age": 0.0, "life": 0.14, "mat": m})


func tracer(from: Vector2, to: Vector2, wide: bool) -> void:
	var a := to_world(from, 0.7)
	var b := to_world(to, 0.5)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5 if wide else 0.12, 0.12, a.distance_to(b))
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.95, 0.8, 0.85)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.look_at_from_position((a + b) * 0.5, b, Vector3.UP)
	_flashes.append({"node": mi, "age": 0.0, "life": 0.2, "mat": m})


func _update_flashes(delta: float) -> void:
	var keep: Array = []
	for f: Dictionary in _flashes:
		f["age"] = float(f["age"]) + delta
		var t := float(f["age"]) / float(f["life"])
		if t >= 1.0:
			f["node"].queue_free()
			continue
		var m: StandardMaterial3D = f["mat"]
		m.albedo_color.a = 1.0 - t
		keep.append(f)
	_flashes = keep


## Called by the battle screen for each rules event.
func on_event(e: Dictionary) -> void:
	var pos: Vector2 = e.get("pos", Vector2.ZERO)
	match e["type"]:
		"volley":
			var dir: Vector2 = (Vector2(e["to"]) - pos).normalized()
			var across := Vector2(-dir.y, dir.x)
			var men := mini(int(e.get("men", 4)), 6)
			for i in men:
				var at := pos + across * ((i - (men - 1) * 0.5) * SOLDIER_SPACING) + dir * 0.55
				puff(at, 0.75, 0.42, 2.4)
				puff(at + dir * 0.3, 0.9, 0.3, 1.8)
			flash(pos + dir * 0.6, 0.75, 0.7)
			for id in _regiments:
				var rv: RegimentView = _regiments[id]
				if rv.last_pos.distance_to(pos) < 0.05:
					rv.fire_kick()
		"cannon", "canister":
			var to: Vector2 = e["to"]
			var d2: Vector2 = (to - pos).normalized()
			for i in 6:
				puff(pos + d2 * (0.7 + 0.28 * i), 0.8 + 0.06 * i, 0.85 - 0.08 * i, 3.0)
			flash(pos + d2 * 0.8, 0.8, 1.2)
			tracer(pos + d2 * 0.8, to, e["type"] == "canister")
		"destroyed":
			for i in 14:
				puff(pos + Vector2(cos(i * 0.9), sin(i * 0.9)) * 0.9, 0.6 + 0.12 * (i % 4), 1.1, 3.4)
		"destroyed_regiment":
			puff(pos, 0.5, 0.6, 1.4)
		"over":
			cheering_side = int(e["winner"])


# ==========================================================================================
# Regiments
# ==========================================================================================

class RegimentView extends RefCounted:
	var world: Node3D
	var root: Node3D
	var ring: MeshInstance3D
	var soldiers: Array = []          # Node3D per man
	var mounts: Array = []            # per soldier: the part that bobs (horse, body) for stand-ins
	var gun: Node3D = null
	var arm: String
	var team: int
	var card_id: String
	var last_pos: Vector2
	var shown_pos: Vector2
	var shown_dir: Vector3
	var kick: float = 0.0
	var anim: String = ""
	var uses_model: bool = false
	var phase: float = 0.0
	var fire_hold: float = 0.0
	var moving_for: float = 0.0

	func _init(w: Node3D, r: Sim.Regiment) -> void:
		world = w
		arm = r.arm
		card_id = r.card_id
		team = 0 if r.side == w.local_side else 1
		root = Node3D.new()
		w.add_child(root)
		shown_pos = r.pos
		last_pos = r.pos
		shown_dir = w.dir_to_world(r.facing)
		phase = r.id * 1.37
		ring = MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 1.7 if arm != "cavalry" else 2.0
		disc.bottom_radius = disc.top_radius
		disc.height = 0.02
		disc.radial_segments = 28
		ring.mesh = disc
		ring.position.y = 0.06
		ring.material_override = w._mat(Color(w.team_colour(r.side), 0.38), 1.0, true)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(ring)
		if arm == "artillery":
			gun = Models.make("cannon", team)
			if gun != null:
				Models.fit_height(gun, 1.8)
			else:
				gun = Models.stand_in_cannon(w)
			root.add_child(gun)
		for i in r.men_max:
			var s: Node3D = Models.make_soldier(card_id, arm, team, w)
			root.add_child(s)
			soldiers.append(s)
		uses_model = soldiers.size() > 0 and soldiers[0].has_meta("player")

	## The regiment has left the rules: its remaining men fall, then the node goes.
	func release() -> void:
		for s: Node3D in soldiers:
			_fall(s)
		soldiers.clear()
		root.queue_free()

	func _fall(s: Node3D) -> void:
		if uses_model:
			Models.play(s, "death_forward" if (soldiers.size() + int(phase * 3.0)) % 2 == 0 else "death", true)
		if s.has_meta("drill"):
			s.get_meta("drill").snap_drill(Drill.DROPPED)
		world.drop_soldier(s, uses_model)

	## A volley has just gone off: muskets are level at that instant, then kick.
	func fire_kick() -> void:
		kick = 1.0
		fire_hold = 0.34
		for i in soldiers.size():
			var s: Node3D = soldiers[i]
			if s.has_meta("drill"):
				var d = s.get_meta("drill")
				d.snap_drill(Drill.AIM)
				d.set_drill(Drill.RECOIL, 0.05 + 0.02 * i)

	func _offsets(r: Sim.Regiment, n: int) -> Array:
		var out: Array = []
		var sp: float = world.SOLDIER_SPACING
		if arm == "cavalry":
			for i in n:
				out.append(Vector3((i - (n - 1) * 0.5) * 1.5, 0, 0))
		elif arm == "artillery":
			for i in n:
				out.append(Vector3((i - (n - 1) * 0.5) * 1.0, 0, 1.5))
		elif r.formation == "rout":
			for i in n:
				out.append(Vector3(sin(i * 12.99 + r.id) * 1.0, 0, cos(i * 78.23 + r.id * 2.0) * 1.0))
		elif r.formation == "square":
			for i in n:
				var v := Vector2.from_angle(TAU * i / n + PI * 0.25)
				v = v / maxf(absf(v.x), absf(v.y)) * 1.0
				out.append(Vector3(v.x, 0, v.y))
		elif bool(r.def.get("loose", false)):
			for i in n:
				out.append(Vector3((i - (n - 1) * 0.5) * 1.35, 0, (i % 2) * 0.8))
		elif r.formation == "column":
			for i in n:
				out.append(Vector3((i % 2 - 0.5) * sp, 0, (i / 2) * sp - (n / 4.0) * sp))
		else:
			var cols := int(ceil(n / 2.0))
			for i in n:
				out.append(Vector3((i % cols - (cols - 1) * 0.5) * sp, 0, (i / cols) * sp))
		return out

	func sync(r: Sim.Regiment, delta: float) -> void:
		# Losses: the surplus men fall where they stand.
		while soldiers.size() > maxi(r.men, 0):
			_fall(soldiers.pop_back())
		var k := 1.0 - exp(-16.0 * delta)
		var moved := r.pos.distance_to(last_pos)
		last_pos = r.pos
		shown_pos = shown_pos.lerp(r.pos, k)
		root.position = world.to_world(shown_pos, world.ground_height(shown_pos))
		var want: Vector3 = world.dir_to_world(r.facing)
		shown_dir = shown_dir.slerp(want, 1.0 - exp(-9.0 * delta)) if shown_dir.length() > 0.01 and want.length() > 0.01 else want
		if shown_dir.length() > 0.01:
			root.rotation.y = atan2(-shown_dir.x, -shown_dir.z)
		ring.visible = r.state != Sim.ST_ROUT
		kick = maxf(0.0, kick - delta * 4.0)
		fire_hold = maxf(0.0, fire_hold - delta)
		# The rules tick 20 times a second, so "moved this frame" flickers; smooth it.
		moving_for = minf(moving_for + delta, 0.3) if moved > 0.0005 else maxf(moving_for - delta, 0.0)
		var moving := moving_for > 0.08
		var routed := r.state == Sim.ST_ROUT
		var won: bool = world.cheering_side == r.side

		# What the body does, and what the musket does.
		var clip := "idle_calm"
		var drill := Drill.PORT
		if routed:
			clip = "panic"
			drill = Drill.NONE
		elif won:
			clip = "cheer"
		elif r.in_melee and arm != "cavalry":
			drill = Drill.CHARGE
		elif r.state == Sim.ST_SQUARE or r.state == Sim.ST_FORMING:
			clip = "kneel"
			drill = Drill.CHARGE
		elif moving:
			clip = "run" if arm == "cavalry" else "march"
			drill = Drill.SHOULDER
		elif r.reload > 0.0 and r.def.has("reload"):
			var since := float(r.def["reload"]) - r.reload
			if since < 0.32:
				drill = Drill.RECOIL
			elif r.reload < 0.55:
				drill = Drill.AIM            # coming up to the shoulder for the next volley
			else:
				drill = Drill.LOAD
		if uses_model and clip != anim:
			anim = clip
			for s: Node3D in soldiers:
				Models.play(s, anim, false)

		var offs := _offsets(r, soldiers.size())
		var t: float = world._time
		for i in soldiers.size():
			var s: Node3D = soldiers[i]
			var target: Vector3 = offs[i]
			s.position = s.position.lerp(Vector3(target.x, s.position.y, target.z), 1.0 - exp(-7.0 * delta))
			# In a square every man faces outward.
			var face := 0.0
			if r.formation == "square":
				face = atan2(-target.x, -target.z)
			s.rotation.y = lerp_angle(s.rotation.y, face, 1.0 - exp(-8.0 * delta))
			if s.has_meta("drill"):
				var d = s.get_meta("drill")
				if fire_hold <= 0.0:
					d.set_drill(drill, 0.04 * i + 0.03 * ((i * 7 + int(phase)) % 3))
				d.jab = (0.5 + 0.5 * sin(t * 8.0 + i * 1.7)) if r.in_melee else 0.0
			if s.has_meta("gallop"):
				# Mounted models: the shader works the legs; the whole figure pitches a little.
				var g: float = s.get_meta("gallop_now", 0.0)
				g = lerpf(g, 1.0 if (moving or routed) else 0.0, 1.0 - exp(-6.0 * delta))
				s.set_meta("gallop_now", g)
				for mi: MeshInstance3D in s.get_meta("gallop"):
					mi.set_instance_shader_parameter("gallop", g)
				s.rotation.x = kick * 0.1
			elif not uses_model:
				# Stand-in figures move like toys: hop when marching, rock back when firing.
				var hop := 0.0
				if moving:
					var speed := 15.0 if arm == "cavalry" else 11.0
					hop = absf(sin(t * speed + phase + i * 0.9)) * (0.16 if arm == "cavalry" else 0.08)
				s.position.y = lerpf(s.position.y, hop, 1.0 - exp(-20.0 * delta))
				s.rotation.x = kick * 0.28 + (0.12 * sin(t * 15.0 + phase + i) if moving and arm == "cavalry" else 0.0)
		if gun != null:
			gun.position.z = kick * 0.22
