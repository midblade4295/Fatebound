extends Node3D
## The 3D battlefield: arena, structures, regiments and effects, drawn from the rules engine's
## state every frame. It owns no rules. The battle screen feeds it the sim and its events and
## asks it to convert between field positions and screen positions.

const Sim = preload("res://scripts/sim/battle_sim.gd")
const Models = preload("res://scripts/view/models.gd")
const Arena = preload("res://scripts/view/arena.gd")
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
var arena: Arena
var field_rect_design := Rect2(22.0, 58.0, 496.0, 748.0)   # where the field must fit on screen; the battle screen sets it

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
var _lamps: Dictionary = {}
var _shake: float = 0.0            # 0..1, how hard the camera is being rattled
var _cam_base: Transform3D
var _hitstop_until: int = 0        # real-time milliseconds; 0 when time is running normally
var _lights: Array = []            # a small pool of lights for muzzle flashes
var _chunks: Array = []            # flung clods and splinters: {node, vel, age, life}
var _jolts: Dictionary = {}        # structure id -> how hard it is still shuddering
var _hit_flash: StandardMaterial3D
var _chunk_mesh: BoxMesh
var _ring_tex: GradientTexture2D
var _chimney_clock: float = 0.0


# ==========================================================================================
# Coordinates
# ==========================================================================================

func to_world(p: Vector2, height: float = 0.0) -> Vector3:
	if local_side == 0:
		return Vector3(p.x - Sim.FIELD_W * 0.5, height, Sim.FIELD_H * 0.5 - p.y)
	return Vector3(Sim.FIELD_W * 0.5 - p.x, height, p.y - Sim.FIELD_H * 0.5)


## Height of the ground a regiment stands on at a field position: 0 on grass, raised over the
## bridge, lowered where a ford is waded.
func ground_height(p: Vector2) -> float:
	var w := to_world(p)
	return Arena.standing_height(w.x, w.z)


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
	_build_contact_shadows()
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
	env.ambient_light_color = Color("a8bdf0")       # cool sky-blue fill in the shadows
	env.ambient_light_energy = 0.52
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.0      # the palette itself is already rich; grading keeps it calm
	env.adjustment_contrast = 1.09
	env.adjustment_brightness = 1.02
	# Bloom: muzzle flashes, glints on the water and the motes in the sunbeams all flare a little.
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 0.95
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()             # warm golden-hour key light
	sun.light_color = Color("ffd9a3")
	sun.light_energy = 1.25
	# Low in the east: long shadows fall across the field from the right-hand woods, and the
	# light still catches the sides of the figures that face the camera.
	sun.rotation_degrees = Vector3(-37.0, 58.0, 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 95.0
	sun.shadow_bias = 0.05
	sun.shadow_normal_bias = 1.4
	sun.shadow_blur = 2.2                # soft-edged shadows
	sun.shadow_opacity = 0.72            # never pitch black: the sky fills them
	add_child(sun)

	var rim := DirectionalLight3D.new()             # crisp cool rim from behind the field
	rim.light_color = Color("cfe6ff")
	rim.light_energy = 0.42
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
	_cam_base = camera.transform


func _build_arena() -> void:
	var spots: Array = []
	for s: Sim.Structure in sim.structures:
		var w := to_world(s.pos)
		spots.append(Vector2(w.x, w.z))
	arena = Arena.new()
	arena.name = "Arena"
	add_child(arena)
	arena.build(spots)

	for s: Sim.Structure in sim.structures:
		var node := _build_structure(s)
		node.position = to_world(s.pos)
		if s.side != local_side and s.kind != "hq":
			node.rotation.y = PI            # enemy guns point at you; both farmhouses show their porch
		add_child(node)
		_structures[s.id] = node
		_structure_dead[s.id] = false
		_add_blob(node, 7.4 if s.kind == "hq" else 5.6, 0.5)
		if s.kind == "hq":
			# Lamplight spilling from the farmhouse onto the grass in front of it.
			var lamp := OmniLight3D.new()
			lamp.light_color = Color("ffb964")
			lamp.light_energy = 2.2
			lamp.omni_range = 6.5
			lamp.omni_attenuation = 1.4
			lamp.shadow_enabled = false
			lamp.position = Vector3(0.0, 1.6, 2.6)
			node.add_child(lamp)
			_lamps[s.id] = lamp


## A white wash laid over a figure for an instant when it is struck.
func hit_flash_material() -> StandardMaterial3D:
	if _hit_flash == null:
		_hit_flash = StandardMaterial3D.new()
		_hit_flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_hit_flash.albedo_color = Color(1.0, 0.97, 0.9, 0.72)
		_hit_flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return _hit_flash


var _ring_material: ShaderMaterial = null


## The marker under a regiment: a crisp ring in the team colour over a faint fill.
func ring_material() -> ShaderMaterial:
	if _ring_material == null:
		_ring_material = ShaderMaterial.new()
		_ring_material.shader = Shader.new()
		_ring_material.shader.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, shadows_disabled, cull_disabled;
instance uniform vec3 colour : source_color = vec3(1.0);
instance uniform float pulse = 0.0;
void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float line = smoothstep(0.82, 0.87, d) * (1.0 - smoothstep(0.95, 1.0, d));
	float fill = 1.0 - smoothstep(0.84, 0.88, d);
	ALBEDO = mix(colour, vec3(1.0), pulse * 0.55);
	ALPHA = clamp(line * 0.95 + fill * (0.17 + 0.3 * pulse), 0.0, 1.0);
}
"""
	return _ring_material


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


const BLOB_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, shadows_disabled, cull_disabled;
uniform float strength = 0.5;
void fragment() {
	float d = length(UV - 0.5) * 2.0;
	ALBEDO = vec3(0.04, 0.035, 0.07);
	ALPHA = (1.0 - smoothstep(0.2, 1.0, d)) * strength;
}
"""

var _blob_shader: Shader = null
var _contact: MultiMeshInstance3D


func _blob_material(strength: float) -> ShaderMaterial:
	if _blob_shader == null:
		_blob_shader = Shader.new()
		_blob_shader.code = BLOB_SHADER
	var m := ShaderMaterial.new()
	m.shader = _blob_shader
	m.set_shader_parameter("strength", strength)
	return m


## A soft dark patch on the ground under something, standing in for ambient occlusion (the
## mobile renderer has no screen-space AO). It is what makes a figure look planted.
func _add_blob(parent: Node3D, size: float, strength: float) -> void:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	mi.mesh = plane
	mi.position.y = 0.035
	mi.material_override = _blob_material(strength)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## One patch under every soldier and gun, all drawn in a single pass and moved each frame.
func _build_contact_shadows() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.0, 1.0)
	mm.mesh = plane
	mm.instance_count = 220
	mm.visible_instance_count = 0
	_contact = MultiMeshInstance3D.new()
	_contact.multimesh = mm
	_contact.material_override = _blob_material(0.55)
	_contact.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_contact)


func _update_contact_shadows() -> void:
	var mm := _contact.multimesh
	var n := 0
	for id in _regiments:
		var rv: RegimentView = _regiments[id]
		var size := 2.3 if rv.arm == "cavalry" else 1.25
		var y: float = rv.root.position.y + 0.045
		for s: Node3D in rv.soldiers:
			if n >= mm.instance_count:
				break
			var at := s.global_position
			mm.set_instance_transform(n, Transform3D(Basis().scaled(Vector3(size, 1.0, size)), Vector3(at.x, y, at.z)))
			n += 1
		if rv.gun != null and n < mm.instance_count:
			var g := rv.gun.global_position
			mm.set_instance_transform(n, Transform3D(Basis().scaled(Vector3(2.6, 1.0, 2.6)), Vector3(g.x, y, g.z)))
			n += 1
	mm.visible_instance_count = n


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
	# Each puff is a ball that fades out toward its edge and is lit from above: bright on top,
	# a cool grey underneath. Overlapping balls then read as one soft billow, not as discs.
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, shadows_disabled;
varying float fade;
varying vec3 tint;
void vertex() { fade = COLOR.a; tint = COLOR.rgb; }
void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	vec3 up = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	float lit = clamp(up.y * 0.55 + 0.5 + up.x * 0.2, 0.0, 1.0);
	ALBEDO = mix(vec3(0.5, 0.5, 0.6), vec3(1.0, 0.97, 0.9), lit) * tint;
	ALPHA = fade * smoothstep(0.02, 0.62, facing);
}
"""
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
	_shake = 0.0
	_hitstop_until = 0
	Engine.time_scale = 1.0
	for c: Dictionary in _chunks:
		c["node"].queue_free()
	_chunks.clear()
	_jolts.clear()


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
	# Chimney smoke from each farmhouse still standing.
	_chimney_clock -= delta
	if _chimney_clock <= 0.0:
		_chimney_clock = 0.55
		for s: Sim.Structure in sim.structures:
			if s.kind == "hq" and not s.dead:
				var w: Vector3 = _structures[s.id].position + Vector3(-1.05, 5.0, -0.5)
				_puffs.append({"pos": w, "vel": Vector3(0.45, 0.7, 0.0), "age": 0.0, "life": 3.2, "size": 0.55})
	for id in _lamps:
		_lamps[id].visible = not _structure_dead.get(id, false)
	_update_impact(delta)
	_update_contact_shadows()
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
		var vel: Vector3 = e["vel"]
		if vel.length_squared() > 0.0001:
			node.position += vel * delta
			e["vel"] = vel * exp(-3.5 * delta)
		if t > 1.1:
			node.position.y -= delta * 0.6
	var keep: Array = []
	for e: Dictionary in _leaving:
		if float(e["age"]) < 1.9:
			keep.append(e)
		else:
			e["node"].queue_free()
	_leaving = keep


## A man leaves his regiment and falls. impulse throws the body along the blow that felled him.
func drop_soldier(node: Node3D, animated: bool, impulse: Vector3 = Vector3.ZERO) -> void:
	var at := node.global_transform
	node.get_parent().remove_child(node)
	add_child(node)
	node.global_transform = at
	if node.has_meta("meshes"):
		for mi: MeshInstance3D in node.get_meta("meshes"):
			if is_instance_valid(mi):
				mi.material_overlay = null
	_leaving.append({"node": node, "age": 0.0, "animated": animated, "vel": impulse})


# --- Impact: shake, hit-stop, flashes of light, flung debris ---------------------------------

## Rattles the camera. amount is 0..1; the strongest recent shake wins.
func shake(amount: float) -> void:
	_shake = minf(1.0, maxf(_shake, amount))


## Freezes the action for a few hundredths of a second so a heavy blow registers.
func hitstop(milliseconds: int) -> void:
	Engine.time_scale = 0.06
	_hitstop_until = maxi(_hitstop_until, Time.get_ticks_msec() + milliseconds)


func _light_flash(at: Vector3, energy: float, reach: float, life: float) -> void:
	var light: OmniLight3D = null
	for l: Dictionary in _lights:
		if float(l["age"]) >= float(l["life"]):
			light = l["node"]
			l["age"] = 0.0
			l["life"] = life
			l["energy"] = energy
			break
	if light == null:
		if _lights.size() >= 5:
			return
		light = OmniLight3D.new()
		light.light_color = Color("ffb35a")
		light.shadow_enabled = false
		add_child(light)
		_lights.append({"node": light, "age": 0.0, "life": life, "energy": energy})
	light.position = at
	light.omni_range = reach
	light.light_energy = energy
	light.visible = true


## Flings clods of earth or splinters of wood from a point, in roughly one direction.
func debris(field_pos: Vector2, count: int, colour: Color, toward: Vector3 = Vector3.ZERO, height: float = 0.2) -> void:
	if _chunk_mesh == null:
		_chunk_mesh = BoxMesh.new()
		_chunk_mesh.size = Vector3(0.16, 0.12, 0.2)
	var origin := to_world(field_pos, height)
	for i in count:
		if _chunks.size() >= 70:
			return
		var mi := MeshInstance3D.new()
		mi.mesh = _chunk_mesh
		mi.material_override = _mat(colour.darkened(0.25 * randf()))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = origin + Vector3(randf_range(-0.4, 0.4), 0.0, randf_range(-0.4, 0.4))
		mi.scale = Vector3.ONE * randf_range(0.6, 1.6)
		mi.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		add_child(mi)
		var vel := Vector3(randf_range(-2.2, 2.2), randf_range(3.5, 7.0), randf_range(-2.2, 2.2)) + toward * randf_range(1.5, 4.0)
		_chunks.append({"node": mi, "vel": vel, "age": 0.0, "life": randf_range(0.6, 1.0)})


## An expanding ring on the ground: the shock of a gun going off or a charge going home.
func ring_burst(field_pos: Vector2, radius: float, colour: Color, life: float = 0.32) -> void:
	if _ring_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.66, 0.84, 0.94, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.3), Color(1, 1, 1, 0)])
		_ring_tex = GradientTexture2D.new()
		_ring_tex.gradient = g
		_ring_tex.fill = GradientTexture2D.FILL_RADIAL
		_ring_tex.fill_from = Vector2(0.5, 0.5)
		_ring_tex.fill_to = Vector2(1.0, 0.5)
		_ring_tex.width = 128
		_ring_tex.height = 128
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(radius * 2.0, radius * 2.0)
	mi.mesh = plane
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = _ring_tex
	m.albedo_color = colour
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = to_world(field_pos, ground_height(field_pos) + 0.09)
	mi.scale = Vector3.ONE * 0.15
	add_child(mi)
	_flashes.append({"node": mi, "age": 0.0, "life": life, "mat": m, "grow": true})


func _update_impact(delta: float) -> void:
	if _hitstop_until > 0 and Time.get_ticks_msec() >= _hitstop_until:
		_hitstop_until = 0
		Engine.time_scale = 1.0
	# Camera shake: a fast jitter in the camera's own plane, dying away.
	_shake = maxf(0.0, _shake - delta * 2.4)
	if camera != null:
		var power := _shake * _shake * 0.85
		var t := _time * 47.0
		camera.transform = _cam_base
		if power > 0.0005:
			camera.position += _cam_base.basis.x * (sin(t) + sin(t * 2.3)) * 0.5 * power \
					+ _cam_base.basis.y * (cos(t * 1.7) + sin(t * 3.1)) * 0.5 * power
	for l: Dictionary in _lights:
		l["age"] = float(l["age"]) + delta
		var k := 1.0 - float(l["age"]) / float(l["life"])
		var node: OmniLight3D = l["node"]
		node.visible = k > 0.0
		node.light_energy = float(l["energy"]) * maxf(k, 0.0)
	var keep: Array = []
	for c: Dictionary in _chunks:
		c["age"] = float(c["age"]) + delta
		var mi: MeshInstance3D = c["node"]
		if float(c["age"]) >= float(c["life"]):
			mi.queue_free()
			continue
		var vel: Vector3 = c["vel"]
		vel.y -= 18.0 * delta
		mi.position += vel * delta
		if mi.position.y < 0.05:
			mi.position.y = 0.05
			vel = Vector3(vel.x * 0.4, -vel.y * 0.3, vel.z * 0.4)
		mi.rotation += Vector3(7.0, 5.0, 3.0) * delta
		c["vel"] = vel
		keep.append(c)
	_chunks = keep
	for id in _jolts.keys():
		var j: float = _jolts[id] - delta * 3.5
		var node3: Node3D = _structures[id]
		if j <= 0.0 or _structure_dead.get(id, false):
			_jolts.erase(id)
			node3.rotation.x = 0.0
			node3.rotation.z = 0.0
		else:
			_jolts[id] = j
			node3.rotation.z = sin(_time * 55.0) * 0.035 * j
			node3.rotation.x = cos(_time * 43.0) * 0.025 * j


# --- Effects --------------------------------------------------------------------------------

func puff(field_pos: Vector2, height: float, size: float, life: float, colour: Color = COL_SMOKE) -> void:
	if _puffs.size() >= MAX_PUFFS:
		_puffs.pop_front()
	var w := to_world(field_pos, height)
	_puffs.append({"pos": w, "vel": Vector3(0.35 + sin(w.z * 3.1) * 0.15, 0.32 + cos(w.x * 2.3) * 0.1, 0.0),
			"age": 0.0, "life": life, "size": size, "col": colour})


## A burst of kicked-up dust where something struck the ground.
func dust(field_pos: Vector2, amount: int, size: float) -> void:
	for i in amount:
		var off := Vector2(randf_range(-0.5, 0.5), randf_range(-0.5, 0.5))
		puff(field_pos + off, 0.25 + 0.2 * randf(), size * randf_range(0.7, 1.2), randf_range(0.7, 1.2), Color(0.78, 0.66, 0.46))


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
		mm.set_instance_color(i, Color(p.get("col", COL_SMOKE), 0.95 * (1.0 - t * t)))


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


func tracer(from: Vector2, to: Vector2, wide: bool, thickness: float = 0.12, life: float = 0.2) -> void:
	var a := to_world(from, 0.7)
	var b := to_world(to, 0.5)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5 if wide else thickness, thickness, a.distance_to(b))
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.95, 0.8, 0.85)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.look_at_from_position((a + b) * 0.5, b, Vector3.UP)
	_flashes.append({"node": mi, "age": 0.0, "life": life, "mat": m})


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
		if f.has("grow"):
			(f["node"] as Node3D).scale = Vector3.ONE * lerpf(0.15, 1.0, 1.0 - pow(1.0 - t, 3.0))
		keep.append(f)
	_flashes = keep


func _regiment_at(field_pos: Vector2, slack: float = 0.25) -> RegimentView:
	for id in _regiments:
		var rv: RegimentView = _regiments[id]
		if rv.last_pos.distance_to(field_pos) < slack:
			return rv
	return null


func _is_structure_at(field_pos: Vector2) -> bool:
	for s: Sim.Structure in sim.structures:
		if s.pos.distance_to(field_pos) < 0.05:
			return true
	return false


## Called by the battle screen for each rules event.
func on_event(e: Dictionary) -> void:
	var pos: Vector2 = e.get("pos", Vector2.ZERO)
	match e["type"]:
		"volley":
			var target: Vector2 = e["to"]
			var dir: Vector2 = (target - pos).normalized()
			var across := Vector2(-dir.y, dir.x)
			var men := mini(int(e.get("men", 4)), 6)
			for i in men:
				var at := pos + across * ((i - (men - 1) * 0.5) * SOLDIER_SPACING) + dir * 0.75
				puff(at, 1.5, 0.5, 2.4)
				puff(at + dir * 0.4, 1.65, 0.36, 1.8)
				flash(at, 1.5, 0.55)
				# A streak from each musket to its mark, gone in a blink.
				tracer(at, target + across * randf_range(-0.7, 0.7), false, 0.05, 0.09)
			_light_flash(to_world(pos + dir * 0.9, 1.6), 5.0, 5.5, 0.12)
			shake(0.07)
			var firing := _regiment_at(pos, 0.05)
			if firing != null:
				firing.fire_kick()
		"cannon", "canister":
			var to: Vector2 = e["to"]
			var d2: Vector2 = (to - pos).normalized()
			var from_works := _is_structure_at(pos)
			for i in 8:
				puff(pos + d2 * (1.0 + 0.32 * i), 1.0 + 0.08 * i, 1.1 - 0.09 * i, 3.2)
			flash(pos + d2 * 1.1, 1.0, 1.9)
			_light_flash(to_world(pos + d2 * 1.2, 1.4), 11.0, 11.0, 0.18)
			ring_burst(pos + d2 * 0.6, 2.6, Color(1, 0.95, 0.8, 0.9), 0.3)
			shake(0.16 if from_works else 0.36)
			if e["type"] == "canister":
				var side := Vector2(-d2.y, d2.x)
				for k in 7:
					tracer(pos + d2 * 1.1, to + side * (k - 3) * 0.45, false, 0.07, 0.12)
			else:
				tracer(pos + d2 * 1.1, to, false, 0.16, 0.16)
				# Roundshot skips along the ground, kicking up earth at each bounce.
				var reach := pos.distance_to(to)
				var along := 3.0
				while along < reach:
					var bounce := pos + d2 * along
					if not Sim.in_creek(bounce.y):
						dust(bounce, 2, 0.7)
						debris(bounce, 2, Color("6b5233"), dir_to_world(d2))
					along += randf_range(2.4, 3.6)
			var gunner := _regiment_at(pos, 0.05)
			if gunner != null:
				gunner.kick = 1.0
		"hit":
			var struck: RegimentView = _regiments.get(e["id"])
			var amount := float(e["amount"])
			if struck != null:
				struck.take_hit(e["from"], amount, float(e["of"]))
			if amount >= 40.0:
				dust(pos, 2 if amount < 120.0 else 4, 0.6 if amount < 120.0 else 0.9)
				debris(pos, 2 if amount < 120.0 else 5, Color("6b5233"), dir_to_world((pos - Vector2(e["from"])).normalized()))
			if amount >= 120.0:
				shake(0.2)
		"struct_hit":
			_jolts[e["id"]] = 1.0
			var heavy := float(e["amount"]) >= 60.0
			debris(pos, 5 if heavy else 2, Color("8a5a2e"), Vector3.ZERO, 1.2)
			dust(pos, 3 if heavy else 1, 0.8)
			if heavy:
				shake(0.22)
		"charge":
			shake(0.5)
			hitstop(70)
			ring_burst(pos, 3.4, Color(1, 1, 1, 0.9), 0.35)
			dust(pos, 9, 1.0)
			debris(pos, 8, Color("6b5233"))
		"repelled":
			shake(0.24)
			ring_burst(pos, 2.4, Color(1.0, 0.9, 0.5, 0.9), 0.28)
			for i in 5:
				flash(pos + Vector2(randf_range(-0.8, 0.8), randf_range(-0.8, 0.8)), 1.3, 0.3)
		"destroyed":
			shake(0.85)
			hitstop(110)
			ring_burst(pos, 6.0, Color(1.0, 0.85, 0.55, 0.95), 0.5)
			_light_flash(to_world(pos, 2.0), 14.0, 14.0, 0.3)
			debris(pos, 18, Color("8a5a2e"), Vector3.ZERO, 1.5)
			dust(pos, 8, 1.3)
			for i in 14:
				puff(pos + Vector2(cos(i * 0.9), sin(i * 0.9)) * 0.9, 0.6 + 0.12 * (i % 4), 1.1, 3.4)
		"destroyed_regiment":
			dust(pos, 4, 0.9)
		"over":
			cheering_side = int(e["winner"])
		"rally":
			var rallied := _regiment_at(pos)
			if rallied != null:
				rallied.pulse = 1.0


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
	var pulse: float = 0.0            # the ring flares when the regiment arrives or rallies
	var flash_time: float = 0.0       # the figures flash white for an instant when struck
	var hit_hold: float = 0.0         # while the flinch clip plays
	var struck_dir: Vector3 = Vector3.ZERO
	var struck_power: float = 0.0
	var struck_age: float = 9.0
	var flash_was_on: bool = false
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
		var disc := PlaneMesh.new()
		var radius := 1.75 if arm != "cavalry" else 2.1
		disc.size = Vector2(radius * 2.0, radius * 2.0)
		ring.mesh = disc
		ring.position.y = 0.07
		ring.material_override = w.ring_material()
		ring.set_instance_shader_parameter("colour", w.team_colour(r.side))
		ring.set_instance_shader_parameter("pulse", 1.0)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(ring)
		pulse = 1.0
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
		for s: Node3D in soldiers:
			s.set_meta("meshes", s.find_children("*", "MeshInstance3D", true, false))

	## The regiment has left the rules: its remaining men fall, then the node goes.
	func release() -> void:
		for s: Node3D in soldiers:
			_fall(s)
		soldiers.clear()
		root.queue_free()

	func _fall(s: Node3D) -> void:
		# A man felled by a heavy blow in the last instant is thrown along it.
		var thrown := struck_age < 0.25 and struck_power > 0.55
		if uses_model:
			if thrown and Models.has_clip(s, "knockback"):
				Models.play(s, "knockback", true)
			else:
				Models.play(s, "death_forward" if (soldiers.size() + int(phase * 3.0)) % 2 == 0 else "death", true)
		if s.has_meta("drill"):
			s.get_meta("drill").snap_drill(Drill.DROPPED)
		var impulse := Vector3.ZERO
		if struck_age < 0.25:
			impulse = struck_dir * (1.2 + 4.5 * struck_power) * randf_range(0.6, 1.1)
		world.drop_soldier(s, uses_model, impulse)

	## A blow has landed: the men flash white, are shoved back along it, and flinch.
	func take_hit(from: Vector2, amount: float, max_hp: float) -> void:
		var power := clampf(amount / maxf(70.0, max_hp * 0.4), 0.15, 1.0)
		var away := last_pos - from
		struck_dir = world.dir_to_world(away.normalized()) if away.length() > 0.01 else Vector3.ZERO
		struck_power = power
		struck_age = 0.0
		flash_time = 0.09
		var local := root.global_transform.basis.inverse() * struck_dir
		for s: Node3D in soldiers:
			s.position += local * (0.12 + 0.34 * power) * randf_range(0.5, 1.0)
			s.rotation.x = -0.3 * power * randf_range(0.5, 1.0) * signf(local.z if absf(local.z) > 0.1 else 1.0)
			s.rotation.z = randf_range(-0.22, 0.22) * power
		if uses_model and power > 0.3 and hit_hold <= 0.0 and fire_hold <= 0.0 and Models.has_clip(soldiers[0] if not soldiers.is_empty() else null, "hit"):
			hit_hold = 0.5
			for s: Node3D in soldiers:
				Models.play(s, "hit", true)
			anim = "hit"

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
		pulse = maxf(0.0, pulse - delta * 1.4)
		ring.set_instance_shader_parameter("pulse", pulse)
		kick = maxf(0.0, kick - delta * 4.0)
		fire_hold = maxf(0.0, fire_hold - delta)
		struck_age += delta
		hit_hold = maxf(0.0, hit_hold - delta)
		if flash_time > 0.0 or flash_was_on:
			flash_time -= delta
			var on := flash_time > 0.0
			if on != flash_was_on:
				flash_was_on = on
				for s: Node3D in soldiers:
					for mi: MeshInstance3D in s.get_meta("meshes", []):
						if is_instance_valid(mi):
							mi.material_overlay = world.hit_flash_material() if on else null
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
		if uses_model and clip != anim and hit_hold <= 0.0:
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
			if uses_model:
				# Recover from the shove of a hit.
				s.rotation.x = lerpf(s.rotation.x, 0.0, 1.0 - exp(-9.0 * delta))
				s.rotation.z = lerpf(s.rotation.z, 0.0, 1.0 - exp(-9.0 * delta))
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
