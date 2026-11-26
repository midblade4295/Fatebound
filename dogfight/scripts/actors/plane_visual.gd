class_name PlaneVisual
extends Node3D
## Builds a chunky, toy-like plane out of primitive meshes and owns every
## cosmetic effect on it (propeller, muzzle flashes, damage smoke, nitro glow).
##
## Nothing in here affects gameplay, so the whole node can be swapped for a
## real authored model later: keep build(), gun_offsets() and the set_*/flash_*
## methods and PlaneActor will not notice.
##
## Local axes: -Z is the nose, +X the right wing, +Y up.

## Everything is scaled up a little so planes stay readable at gun range.
const VISUAL_SCALE: float = 1.3
const SKIN_COLOR: Color = Color("f2c79a")
const LEATHER_COLOR: Color = Color("6b4423")
const GUNMETAL_COLOR: Color = Color("2b2f36")
const MUZZLE_FLASH_TIME: float = 0.05

static var _unit_sphere: SphereMesh
static var _unit_cylinder: CylinderMesh
static var _unit_box: BoxMesh
static var _particle_mesh: SphereMesh

var _propeller: Node3D
var _prop_disc: MeshInstance3D
var _muzzle_flashes: Array[MeshInstance3D] = []
var _muzzle_timers: Array[float] = []
var _nitro_flames: Array[MeshInstance3D] = []
var _damage_smoke: CPUParticles3D
var _fire_particles: CPUParticles3D
var _screen_smoke: CPUParticles3D
var _gun_offsets: Array[Vector3] = []
var _prop_speed: float = 40.0


func _process(delta: float) -> void:
	if _propeller != null:
		_propeller.rotate_z(_prop_speed * delta)
	for index: int in range(_muzzle_flashes.size()):
		if _muzzle_timers[index] > 0.0:
			_muzzle_timers[index] -= delta
			if _muzzle_timers[index] <= 0.0:
				_muzzle_flashes[index].visible = false


## (Re)builds the model for [param data] in [param team] colours.
func build(data: PlaneData, team: Teams.Id) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_muzzle_flashes.clear()
	_muzzle_timers.clear()
	_nitro_flames.clear()
	_gun_offsets.clear()
	_ensure_shared_meshes()
	scale = Vector3.ONE * VISUAL_SCALE

	var length: float = data.fuselage_length
	var radius: float = data.fuselage_radius
	var span: float = data.wing_span
	var chord: float = data.wing_chord
	var team_color: Color = Teams.color_of(team)
	var team_dark: Color = Teams.dark_color_of(team)
	var body: ShaderMaterial = ToonMaterials.toon(data.body_color)
	var camo: ShaderMaterial = ToonMaterials.toon(data.camo_color)
	var belly: ShaderMaterial = ToonMaterials.toon(data.belly_color)
	var team_paint: ShaderMaterial = ToonMaterials.toon(team_color)
	var along_z: Basis = Basis(Vector3.RIGHT, PI * 0.5)  # Stands a Y-axis mesh along Z.

	# --- Fuselage: fat capsule up front, tapering cone to the tail -----------
	var body_mesh: CapsuleMesh = CapsuleMesh.new()
	body_mesh.radius = radius
	body_mesh.height = length * 0.72
	body_mesh.radial_segments = 16
	body_mesh.rings = 6
	_add_part("Fuselage", body_mesh, body, Transform3D(along_z, Vector3(0.0, 0.0, -length * 0.12)))
	_add_part("Belly", body_mesh, belly, Transform3D(along_z.scaled(Vector3(0.9, 0.9, 0.93)), Vector3(0.0, -radius * 0.2, -length * 0.12)))
	var tail_mesh: CylinderMesh = CylinderMesh.new()
	tail_mesh.top_radius = radius * 0.32
	tail_mesh.bottom_radius = radius * 0.93
	tail_mesh.height = length * 0.52
	tail_mesh.radial_segments = 16
	tail_mesh.rings = 1
	_add_part("TailCone", tail_mesh, body, Transform3D(along_z, Vector3(0.0, 0.0, length * 0.36)))
	var band_mesh: CylinderMesh = CylinderMesh.new()
	band_mesh.top_radius = radius * 0.72
	band_mesh.bottom_radius = radius * 0.8
	band_mesh.height = length * 0.07
	band_mesh.radial_segments = 16
	band_mesh.rings = 1
	_add_part("TeamBand", band_mesh, team_paint, Transform3D(along_z, Vector3(0.0, 0.0, length * 0.27)))

	# --- Nose, spinner and the oversized propeller ---------------------------
	_add_part("Cowl", _unit_cylinder, ToonMaterials.toon(data.nose_color),
			Transform3D(along_z.scaled(Vector3(radius * 2.06, radius * 2.06, length * 0.14)), Vector3(0.0, 0.0, -length * 0.4)))
	_add_part("Spinner", _unit_sphere, team_paint,
			Transform3D(Basis.from_scale(Vector3(radius * 0.95, radius * 0.95, radius * 1.5)), Vector3(0.0, 0.0, -length * 0.5)))
	_propeller = Node3D.new()
	_propeller.name = "Propeller"
	_propeller.position = Vector3(0.0, 0.0, -length * 0.53)
	add_child(_propeller)
	var blade_length: float = radius * 2.5
	for blade: int in range(data.prop_blades):
		var blade_basis: Basis = Basis(Vector3.BACK, TAU * float(blade) / float(data.prop_blades))
		var blade_transform: Transform3D = Transform3D(
				blade_basis * Basis.from_scale(Vector3(radius * 0.5, blade_length, 0.14)),
				blade_basis * Vector3(0.0, blade_length * 0.5, 0.0))
		_add_part("Blade%d" % blade, _unit_box, ToonMaterials.toon(GUNMETAL_COLOR), blade_transform, _propeller)
	_prop_disc = _add_part("PropBlur", _unit_cylinder, ToonMaterials.prop_blur(),
			Transform3D(along_z.scaled(Vector3(blade_length * 2.05, blade_length * 2.05, 0.04)), Vector3.ZERO), _propeller)
	_prop_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# --- Wings: one stubby elliptical slab, camo blotches, team wingtips -----
	var wing_y: float = -radius * 0.38
	var wing_z: float = -length * 0.1
	var wing_thickness: float = radius * 0.3
	_add_part("Wing", _unit_cylinder, body,
			Transform3D(Basis.from_scale(Vector3(span, wing_thickness, chord * 1.1)), Vector3(0.0, wing_y, wing_z)))
	_add_part("WingBelly", _unit_cylinder, belly,
			Transform3D(Basis.from_scale(Vector3(span * 0.97, wing_thickness, chord * 1.04)), Vector3(0.0, wing_y - 0.05, wing_z)))
	for side: float in [-1.0, 1.0]:
		_add_part("Camo", _unit_cylinder, camo,
				Transform3D(Basis.from_scale(Vector3(span * 0.2, wing_thickness * 1.06, chord * 0.55)), Vector3(side * span * 0.12, wing_y, wing_z + side * chord * 0.14)))
		_add_part("WingTip", _unit_sphere, team_paint,
				Transform3D(Basis.from_scale(Vector3(span * 0.2, wing_thickness * 1.25, chord * 0.72)), Vector3(side * span * 0.415, wing_y, wing_z)))
		# Roundel: team ring, white middle, dark team centre.
		var roundel_pos: Vector3 = Vector3(side * span * 0.27, wing_y + wing_thickness * 0.5, wing_z)
		var roundel_size: float = chord * 0.62
		_add_part("RoundelOuter", _unit_cylinder, team_paint, Transform3D(Basis.from_scale(Vector3(roundel_size, 0.05, roundel_size)), roundel_pos))
		_add_part("RoundelMid", _unit_cylinder, ToonMaterials.toon(Color.WHITE), Transform3D(Basis.from_scale(Vector3(roundel_size * 0.66, 0.07, roundel_size * 0.66)), roundel_pos))
		_add_part("RoundelCore", _unit_cylinder, ToonMaterials.toon(team_dark), Transform3D(Basis.from_scale(Vector3(roundel_size * 0.33, 0.09, roundel_size * 0.33)), roundel_pos))
		# Wing gun barrel + its muzzle flash.
		var gun_pos: Vector3 = Vector3(side * span * 0.2, wing_y, wing_z - chord * 0.55)
		_add_part("Gun", _unit_cylinder, ToonMaterials.toon(GUNMETAL_COLOR),
				Transform3D(along_z.scaled(Vector3(0.22, 0.22, 1.1)), gun_pos))
		var muzzle_pos: Vector3 = gun_pos + Vector3(0.0, 0.0, -0.75)
		_gun_offsets.append(muzzle_pos * VISUAL_SCALE)
		var flash: MeshInstance3D = _add_part("MuzzleFlash", _unit_sphere, ToonMaterials.unlit(Color(1.0, 0.86, 0.3), true),
				Transform3D(Basis.from_scale(Vector3(0.75, 0.75, 2.0)), muzzle_pos + Vector3(0.0, 0.0, -0.7)))
		flash.visible = false
		flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_muzzle_flashes.append(flash)
		_muzzle_timers.append(0.0)
		# Nitro exhaust streak along the cowl.
		var flame: MeshInstance3D = _add_part("NitroFlame", _unit_sphere, ToonMaterials.unlit(Color(0.35, 0.85, 1.0), true),
				Transform3D(Basis.from_scale(Vector3(0.45, 0.45, 3.4)), Vector3(side * radius * 0.95, radius * 0.1, -length * 0.12)))
		flame.visible = false
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_nitro_flames.append(flame)

	# --- Tail: stabiliser + a tall team-coloured fin -------------------------
	_add_part("Stabiliser", _unit_cylinder, body,
			Transform3D(Basis.from_scale(Vector3(span * 0.4, wing_thickness * 0.7, chord * 0.62)), Vector3(0.0, radius * 0.1, length * 0.52)))
	var fin_basis: Basis = Basis(Vector3.BACK, PI * 0.5) * Basis.from_scale(Vector3(radius * 1.9, 0.26, chord * 0.75))
	_add_part("Fin", _unit_cylinder, team_paint, Transform3D(fin_basis, Vector3(0.0, radius * 0.78, length * 0.54)))

	# --- Cockpit: glass canopy over a pilot with cap and goggles -------------
	var canopy_scale: Vector3 = Vector3(radius * 1.15, radius * 1.3, radius * (2.5 if data.bubble_canopy else 2.0))
	var cockpit: Vector3 = Vector3(0.0, radius * 0.72, -length * 0.05)
	var canopy: MeshInstance3D = _add_part("Canopy", _unit_sphere, ToonMaterials.glass(), Transform3D(Basis.from_scale(canopy_scale), cockpit))
	canopy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var head: Vector3 = cockpit + Vector3(0.0, radius * 0.1, 0.0)
	_add_part("PilotHead", _unit_sphere, ToonMaterials.toon(SKIN_COLOR), Transform3D(Basis.from_scale(Vector3.ONE * radius * 0.66), head))
	_add_part("PilotCap", _unit_sphere, ToonMaterials.toon(LEATHER_COLOR),
			Transform3D(Basis.from_scale(Vector3(radius * 0.72, radius * 0.6, radius * 0.72)), head + Vector3(0.0, radius * 0.1, radius * 0.06)))
	_add_part("Goggles", _unit_box, ToonMaterials.toon(GUNMETAL_COLOR),
			Transform3D(Basis.from_scale(Vector3(radius * 0.6, radius * 0.2, radius * 0.16)), head + Vector3(0.0, radius * 0.05, -radius * 0.3)))
	for side: float in [-1.0, 1.0]:
		_add_part("Lens", _unit_sphere, ToonMaterials.toon(Color("9fe8ff"), 0.6),
				Transform3D(Basis.from_scale(Vector3.ONE * radius * 0.2), head + Vector3(side * radius * 0.15, radius * 0.05, -radius * 0.37)))
	_add_part("Scarf", _unit_cylinder, team_paint,
			Transform3D(Basis.from_scale(Vector3(radius * 0.6, radius * 0.16, radius * 0.6)), head + Vector3(0.0, -radius * 0.3, 0.0)))

	_build_particles(length, radius)


## Muzzle positions in PlaneActor space (already scaled).
func gun_offsets() -> Array[Vector3]:
	return _gun_offsets


func flash_muzzle(index: int) -> void:
	if index < 0 or index >= _muzzle_flashes.size():
		return
	_muzzle_flashes[index].visible = true
	_muzzle_timers[index] = MUZZLE_FLASH_TIME


## 0 = idle spin, 1 = full throttle.
func set_throttle(ratio: float) -> void:
	_prop_speed = lerpf(28.0, 62.0, clampf(ratio, 0.0, 1.5))


## Barrel-roll angle (radians) applied on top of the actor's own bank.
func set_roll_angle(angle: float) -> void:
	rotation.z = angle


func set_damage_state(hp_ratio: float, burning: bool) -> void:
	if _damage_smoke != null:
		_damage_smoke.emitting = hp_ratio < 0.5
	if _fire_particles != null:
		_fire_particles.emitting = burning or hp_ratio < 0.25


func set_boosting(active: bool) -> void:
	for flame: MeshInstance3D in _nitro_flames:
		flame.visible = active


func set_smoke_screen(active: bool) -> void:
	if _screen_smoke != null:
		_screen_smoke.emitting = active


func stop_effects() -> void:
	set_damage_state(1.0, false)
	set_boosting(false)
	set_smoke_screen(false)
	for flash: MeshInstance3D in _muzzle_flashes:
		flash.visible = false


func _add_part(part_name: String, mesh: Mesh, material: Material, part_transform: Transform3D, parent: Node3D = self) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = part_name
	instance.mesh = mesh
	instance.material_override = material
	instance.transform = part_transform
	parent.add_child(instance, true)
	return instance


func _build_particles(length: float, radius: float) -> void:
	_damage_smoke = _make_trail("DamageSmoke", Color(0.16, 0.16, 0.18, 0.8), 28, 1.1, 1.2, 4.5)
	_damage_smoke.position = Vector3(0.0, radius * 0.2, -length * 0.3)
	_fire_particles = _make_trail("EngineFire", Color(1.0, 0.55, 0.12, 0.95), 18, 0.35, 0.9, 2.2)
	_fire_particles.position = Vector3(0.0, radius * 0.2, -length * 0.32)
	_screen_smoke = _make_trail("SmokeScreen", Color(0.93, 0.95, 1.0, 0.85), 48, 2.6, 3.0, 12.0)
	_screen_smoke.position = Vector3(0.0, 0.0, length * 0.5)


func _make_trail(trail_name: String, color: Color, amount: int, lifetime: float, start_scale: float, end_scale: float) -> CPUParticles3D:
	var particles: CPUParticles3D = CPUParticles3D.new()
	particles.name = trail_name
	particles.emitting = false
	particles.amount = amount
	particles.lifetime = lifetime
	particles.local_coords = false  # Puffs stay behind in the world.
	particles.mesh = _particle_mesh
	particles.direction = Vector3.BACK
	particles.spread = 14.0
	particles.gravity = Vector3(0.0, 1.5, 0.0)
	particles.initial_velocity_min = 3.0
	particles.initial_velocity_max = 7.0
	particles.scale_amount_min = start_scale
	particles.scale_amount_max = start_scale * 1.4
	var grow: Curve = Curve.new()
	grow.add_point(Vector2(0.0, 1.0))
	grow.add_point(Vector2(1.0, end_scale / start_scale))
	particles.scale_amount_curve = grow
	var fade: Gradient = Gradient.new()
	fade.set_color(0, color)
	fade.set_color(1, Color(color.r, color.g, color.b, 0.0))
	particles.color_ramp = fade
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particles.material_override = material
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(particles)
	return particles


static func _ensure_shared_meshes() -> void:
	if _unit_sphere != null:
		return
	_unit_sphere = SphereMesh.new()
	_unit_sphere.radius = 0.5
	_unit_sphere.height = 1.0
	_unit_sphere.radial_segments = 16
	_unit_sphere.rings = 8
	_unit_cylinder = CylinderMesh.new()
	_unit_cylinder.top_radius = 0.5
	_unit_cylinder.bottom_radius = 0.5
	_unit_cylinder.height = 1.0
	_unit_cylinder.radial_segments = 20
	_unit_cylinder.rings = 1
	_unit_box = BoxMesh.new()
	_particle_mesh = SphereMesh.new()
	_particle_mesh.radius = 0.5
	_particle_mesh.height = 1.0
	_particle_mesh.radial_segments = 8
	_particle_mesh.rings = 4
