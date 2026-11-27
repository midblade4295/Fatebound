class_name PlaneVisual
extends Node3D
## The plane you see: the Blender model (tools/blender/spitfire_stylized.py),
## repainted per plane and team, with every cosmetic effect on it.
##
## The model is a tree of separate pieces, one per PlaneActor.Part (wing
## panels, tips, flaps, ailerons, tail, fin, rudder, elevators, engine ...).
## This script:
##  - swings the hinged control surfaces to follow the stick,
##  - spins the propeller (and stops it when the engine dies),
##  - folds the undercarriage legs up into the wings and back down,
##  - trails smoke from damaged parts and fire from burning ones,
##  - and, when a part is destroyed, unbolts that piece from the model and
##    lets it fall away as debris, together with everything attached to it.
##
## Nothing in here affects gameplay, with one exception that is deliberate:
## PlaneHitboxes reads the pieces' bounding boxes from this node, so the shape
## that gets hit is the shape that is drawn.
##
## Local axes: -Z is the nose, +X the right wing, +Y up.

const MODEL: PackedScene = preload("res://assets/models/spitfire_stylized.glb")
## Wingspan of the model in its own units; PlaneData.wing_span scales it.
const MODEL_WING_SPAN: float = 7.2
## The model's propeller radius and spinner length, in model units.
const MODEL_PROP_RADIUS: float = 1.85
const MODEL_SPINNER_LENGTH: float = 1.0
## Everything is scaled up a little so planes stay readable at gun range.
const VISUAL_SCALE: float = 1.3

## Model node for each PlaneActor.Part, in Part order.
const PART_NODES: Array[StringName] = [
	&"Fuselage", &"Engine", &"WingL", &"WingR", &"WingTipL", &"WingTipR",
	&"Tail", &"Fin", &"Rudder", &"FlapL", &"FlapR", &"AileronL", &"AileronR",
	&"ElevatorL", &"ElevatorR",
]
## Pieces that have no Part of their own but are hit as part of another.
const EXTRA_HIT_NODES: Dictionary[StringName, int] = {
	&"CanopyMesh": PlaneActor.Part.FUSELAGE,
	&"StabiliserL": PlaneActor.Part.TAIL,
	&"StabiliserR": PlaneActor.Part.TAIL,
}
## Parts that trail smoke when damaged (and keep smoking from the stump once gone).
const SMOKING_PARTS: Array[PlaneActor.Part] = [
	PlaneActor.Part.ENGINE, PlaneActor.Part.FUSELAGE, PlaneActor.Part.LEFT_WING,
	PlaneActor.Part.RIGHT_WING, PlaneActor.Part.TAIL,
]
## A control surface sits in a notch cut out of its parent panel, but a
## bounding box cannot have a notch. So each parent's box is cut short at the
## front of the surface behind it: [parent piece, surface piece].
const NOTCHED_PIECES: Array[Array] = [
	[&"WingL", &"FlapL"], [&"WingR", &"FlapR"], [&"WingTipL", &"AileronL"], [&"WingTipR", &"AileronR"],
	[&"Fin", &"Rudder"], [&"StabiliserL", &"ElevatorL"], [&"StabiliserR", &"ElevatorR"],
]
## One box round a tapering or curved piece would cover a lot of empty air,
## so these pieces are measured in slices along an axis (0 = X, 1 = Y, 2 = Z)
## and get one box per slice: [axis, number of slices].
const SLICED_PIECES: Dictionary[StringName, Array] = {
	&"Fuselage": [2, 3], &"Engine": [2, 2], &"Tail": [2, 4],
	&"WingL": [0, 2], &"WingR": [0, 2], &"WingTipL": [0, 3], &"WingTipR": [0, 3],
	&"StabiliserL": [0, 2], &"StabiliserR": [0, 2], &"Fin": [1, 3], &"Rudder": [1, 2],
}
const MUZZLE_NODES: Array[StringName] = [&"MuzzleL", &"MuzzleR"]
## Main undercarriage legs (left, right) and the tail wheel.
const GEAR_NODES: Array[StringName] = [&"GearL", &"GearR"]
const TAIL_WHEEL_NODE: StringName = &"TailWheel"
## How far each leg swings outward to lie under its wing.
const GEAR_RETRACT_ANGLE: float = deg_to_rad(86.0)
## Big pieces cast shadows; small ones are not worth the draw calls on a phone.
const SHADOW_CASTERS: Array[StringName] = [&"Fuselage", &"Engine", &"Tail", &"WingL", &"WingR", &"WingTipL", &"WingTipR"]

const GUNMETAL_COLOR: Color = Color("2b2f36")
const WOOD_COLOR: Color = Color("b5713a")
const SKIN_COLOR: Color = Color("f2c79a")
const LEATHER_COLOR: Color = Color("6b4423")
const MUZZLE_FLASH_TIME: float = 0.05
## Full-stick deflection of each control surface, and flaps fully dropped.
const AILERON_MAX: float = deg_to_rad(24.0)
const ELEVATOR_MAX: float = deg_to_rad(26.0)
const RUDDER_MAX: float = deg_to_rad(28.0)
const FLAP_MAX: float = deg_to_rad(32.0)
## How quickly the surfaces follow the stick (1/s).
const CONTROL_RESPONSE: float = 14.0

static var _unit_sphere: SphereMesh
static var _unit_cylinder: CylinderMesh
static var _particle_mesh: SphereMesh

var _data: PlaneData
var _team: Teams.Id = Teams.Id.TEAM_BLUE
var _model: Node3D
## The model node for each Part, or null once it has been shot off.
var _pieces: Array[Node3D] = []
## Each piece's undeflected orientation, so control angles are applied on top.
var _rest_bases: Array[Basis] = []
var _any_detached: bool = false
var _propeller: Node3D
var _prop_disc: MeshInstance3D
var _muzzle_flashes: Array[MeshInstance3D] = []
var _muzzle_timers: Array[float] = []
var _gun_offsets: Array[Vector3] = []
var _nitro_flames: Array[MeshInstance3D] = []
## Smoke emitter per Part (null where a part does not smoke).
var _part_smoke: Array[CPUParticles3D] = []
var _engine_fire: CPUParticles3D
var _fuel_fire: CPUParticles3D
var _screen_smoke: CPUParticles3D
var _control_target: Vector3 = Vector3.ZERO
var _control_shown: Vector3 = Vector3.ZERO
var _prop_speed: float = 40.0
var _prop_target: float = 40.0
var _gear: Array[Node3D] = []
var _gear_rest: Array[Basis] = []
var _gear_deploy: float = -1.0


func _process(delta: float) -> void:
	# The propeller spools up and winds down rather than snapping.
	_prop_speed = lerpf(_prop_speed, _prop_target, 1.0 - exp(-2.5 * delta))
	if _propeller != null:
		_propeller.rotate_z(_prop_speed * delta)
	if _prop_disc != null:
		_prop_disc.visible = _prop_speed > 16.0
	for index: int in range(_muzzle_flashes.size()):
		if _muzzle_timers[index] > 0.0:
			_muzzle_timers[index] -= delta
			if _muzzle_timers[index] <= 0.0 and is_instance_valid(_muzzle_flashes[index]):
				_muzzle_flashes[index].visible = false
	_animate_controls(delta)


## (Re)builds the model for [param data] in [param team] colours.
func build(data: PlaneData, team: Teams.Id) -> void:
	_data = data
	_team = team
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_pieces.clear()
	_rest_bases.clear()
	_muzzle_flashes.clear()
	_muzzle_timers.clear()
	_gun_offsets.clear()
	_nitro_flames.clear()
	_part_smoke.clear()
	_any_detached = false
	_control_shown = Vector3.ZERO
	_gear.clear()
	_gear_rest.clear()
	_ensure_shared_meshes()

	_model = MODEL.instantiate() as Node3D
	_model.name = "Model"
	_model.scale = Vector3.ONE * model_scale()
	add_child(_model)
	_paint(_model)

	for node_name: StringName in PART_NODES:
		var piece: Node3D = _model.find_child(node_name, true, false) as Node3D
		_pieces.append(piece)
		_rest_bases.append(piece.basis if piece != null else Basis.IDENTITY)

	for node_name: StringName in GEAR_NODES:
		var leg: Node3D = _model.find_child(node_name, true, false) as Node3D
		_gear.append(leg)
		_gear_rest.append(leg.basis if leg != null else Basis.IDENTITY)
	var shown_deploy: float = _gear_deploy
	_gear_deploy = -1.0
	set_gear(maxf(shown_deploy, 0.0))
	_propeller = _model.find_child("PropellerMesh", true, false) as Node3D
	if _propeller != null:
		# A faint disc where the blades blur, parented beside the propeller so
		# it does not spin with it.
		_prop_disc = MeshInstance3D.new()
		_prop_disc.name = "PropBlur"
		_prop_disc.mesh = _unit_cylinder
		_prop_disc.material_override = ToonMaterials.prop_blur()
		_prop_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var diameter: float = MODEL_PROP_RADIUS * 2.04
		_prop_disc.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3(diameter, diameter, 0.04)), _propeller.position)
		_propeller.get_parent().add_child(_prop_disc)

	for node_name: StringName in MUZZLE_NODES:
		var marker: Node3D = _model.find_child(node_name, true, false) as Node3D
		if marker == null:
			continue
		_gun_offsets.append(_transform_to_self(marker).origin)
		var flash: MeshInstance3D = MeshInstance3D.new()
		flash.name = "MuzzleFlash"
		flash.mesh = _unit_sphere
		flash.material_override = ToonMaterials.unlit(Color(1.0, 0.86, 0.3), true)
		flash.transform = Transform3D(Basis.from_scale(Vector3(0.45, 0.45, 1.2)), Vector3(0.0, 0.0, -0.45))
		flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flash.visible = false
		marker.add_child(flash)
		_muzzle_flashes.append(flash)
		_muzzle_timers.append(0.0)

	var engine: Node3D = _pieces[PlaneActor.Part.ENGINE]
	if engine != null:
		for side: float in [-1.0, 1.0]:
			var flame: MeshInstance3D = MeshInstance3D.new()
			flame.name = "NitroFlame"
			flame.mesh = _unit_sphere
			flame.material_override = ToonMaterials.unlit(Color(0.35, 0.85, 1.0), true)
			flame.transform = Transform3D(Basis.from_scale(Vector3(0.28, 0.28, 2.0)), Vector3(side * 0.95, 0.3, 0.9))
			flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			flame.visible = false
			engine.add_child(flame)
			_nitro_flames.append(flame)

	_build_particles()


## Factor from model units to plane units for this plane.
func model_scale() -> float:
	return _data.wing_span * VISUAL_SCALE / MODEL_WING_SPAN


## Puts back anything that has been shot off (used on respawn).
func restore() -> void:
	if _any_detached and _data != null:
		build(_data, _team)
	stop_effects()


## Muzzle positions in PlaneActor space.
func gun_offsets() -> Array[Vector3]:
	return _gun_offsets


## Bounding boxes of the pieces in PlaneActor space, with the Part each one
## belongs to. This is what PlaneHitboxes is built from. Long or curved pieces
## contribute several boxes (see SLICED_PIECES).
func collect_hit_boxes(out_parts: PackedInt32Array, out_boxes: Array[AABB]) -> void:
	out_parts.clear()
	out_boxes.clear()
	for index: int in range(PART_NODES.size()):
		for box: AABB in _piece_boxes(PART_NODES[index]):
			out_parts.append(index)
			out_boxes.append(box)
	for node_name: StringName in EXTRA_HIT_NODES:
		for box: AABB in _piece_boxes(node_name):
			out_parts.append(EXTRA_HIT_NODES[node_name])
			out_boxes.append(box)
	# The spinner is on the (spinning) propeller node, so it is added by hand
	# as part of the engine.
	if _propeller != null:
		var hub: Vector3 = _transform_to_self(_propeller).origin
		var reach: float = MODEL_SPINNER_LENGTH * 0.5 * model_scale()
		out_parts.append(PlaneActor.Part.ENGINE)
		out_boxes.append(AABB(hub - Vector3(reach, reach, reach * 1.4), Vector3(reach * 2.0, reach * 2.0, reach * 2.2)))


func flash_muzzle(index: int) -> void:
	if index < 0 or index >= _muzzle_flashes.size() or not is_instance_valid(_muzzle_flashes[index]):
		return
	_muzzle_flashes[index].visible = true
	_muzzle_timers[index] = MUZZLE_FLASH_TIME


## 0 = propeller stopped, 1 = full throttle.
func set_propeller(ratio: float) -> void:
	_prop_target = 0.0 if ratio <= 0.0 else lerpf(8.0, 62.0, clampf(ratio, 0.0, 1.5))


## 0 = undercarriage up (and hidden inside the wings), 1 = down and locked.
func set_gear(deploy: float) -> void:
	if is_equal_approx(deploy, _gear_deploy):
		return
	_gear_deploy = deploy
	var angle: float = (1.0 - clampf(deploy, 0.0, 1.0)) * GEAR_RETRACT_ANGLE
	for index: int in range(_gear.size()):
		var leg: Node3D = _gear[index]
		if leg == null or not is_instance_valid(leg) or not _model.is_ancestor_of(leg):
			continue  # Went with its wing.
		# The left leg swings out to the left, the right leg to the right.
		var side: float = -1.0 if index == 0 else 1.0
		leg.basis = _gear_rest[index] * Basis(Vector3.BACK, side * angle)
		leg.visible = deploy > 0.03


## Lowest point of the main wheels and of the tail wheel, in PlaneActor space,
## with the undercarriage down. Empty if the model has no undercarriage.
func undercarriage_contacts() -> Array[Vector3]:
	var result: Array[Vector3] = []
	var shown: float = _gear_deploy
	set_gear(1.0)
	var main_wheel: Vector3 = _lowest_point(GEAR_NODES[0])
	var tail_wheel: Vector3 = _lowest_point(TAIL_WHEEL_NODE)
	set_gear(shown)
	if is_finite(main_wheel.y) and is_finite(tail_wheel.y):
		result.append(main_wheel)
		result.append(tail_wheel)
	return result


## How far the bottom of the fuselage is below the plane's origin.
func belly_depth() -> float:
	var lowest: float = INF
	for node_name: StringName in [PART_NODES[PlaneActor.Part.FUSELAGE], PART_NODES[PlaneActor.Part.ENGINE]]:
		lowest = minf(lowest, _lowest_point(node_name).y)
	return -lowest if is_finite(lowest) else 0.0


## Barrel-roll angle (radians) applied on top of the actor's own bank.
func set_roll_angle(angle: float) -> void:
	rotation.z = angle


## Shows the state of every part. [param damage] is PlaneActor.part_damage.
## Damaged parts smoke; a part that has just been destroyed is unbolted and
## thrown clear with [param plane_velocity], taking its attachments with it.
func set_part_damage(damage: PackedFloat32Array, plane_velocity: Vector3, burning: bool) -> void:
	if damage.size() < PlaneActor.PART_COUNT or _pieces.is_empty():
		return
	if _any_detached and _has_refitted_part(damage):
		# Ground crew have fitted a new part: rebuild the model, then take off
		# again (quietly) whatever is still missing.
		_rebuild_with(damage)
	# Parents come before their children in Part order, so a wing is detached
	# before its flap is considered, and the flap simply goes with it.
	for index: int in range(PlaneActor.PART_COUNT):
		if _pieces[index] == null:
			continue
		var parent: int = PlaneActor.PART_PARENT[index]
		if parent >= 0 and _pieces[parent] == null and PlaneActor.PART_DETACHES[parent]:
			_pieces[index] = null  # Already left with its parent.
			continue
		if damage[index] >= 1.0 and PlaneActor.PART_DETACHES[index]:
			_detach(index, plane_velocity)
	for part: PlaneActor.Part in SMOKING_PARTS:
		var smoke: CPUParticles3D = _part_smoke[part]
		if smoke != null:
			smoke.emitting = damage[part] >= 0.4
	if _engine_fire != null:
		_engine_fire.emitting = damage[PlaneActor.Part.ENGINE] >= 1.0
	if _fuel_fire != null:
		_fuel_fire.emitting = burning and damage[PlaneActor.Part.ENGINE] < 1.0


## Where the pilot has the controls: x = roll/yaw (-1 left .. +1 right),
## y = pitch (-1 down .. +1 up), z = flaps (0 up .. 1 fully down).
func set_controls(state: Vector3) -> void:
	_control_target = state


func set_boosting(active: bool) -> void:
	for flame: MeshInstance3D in _nitro_flames:
		if is_instance_valid(flame):
			flame.visible = active


func set_smoke_screen(active: bool) -> void:
	if _screen_smoke != null:
		_screen_smoke.emitting = active


func stop_effects() -> void:
	for smoke: CPUParticles3D in _part_smoke:
		if smoke != null:
			smoke.emitting = false
	if _engine_fire != null:
		_engine_fire.emitting = false
	if _fuel_fire != null:
		_fuel_fire.emitting = false
	set_boosting(false)
	set_smoke_screen(false)
	for flash: MeshInstance3D in _muzzle_flashes:
		if is_instance_valid(flash):
			flash.visible = false


## Whether the model piece for [param part] is still attached.
func has_piece(part: PlaneActor.Part) -> bool:
	return part < _pieces.size() and _pieces[part] != null


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

## The lowest vertex of a piece's mesh, in PlaneActor space (y = INF if the
## piece is not there).
func _lowest_point(node_name: StringName) -> Vector3:
	var lowest: Vector3 = Vector3(0.0, INF, 0.0)
	if _model == null:
		return lowest
	var mesh_instance: MeshInstance3D = _model.find_child(node_name, true, false) as MeshInstance3D
	if mesh_instance == null or mesh_instance.mesh == null:
		return lowest
	var to_self: Transform3D = _transform_to_self(mesh_instance)
	for surface: int in range(mesh_instance.mesh.get_surface_count()):
		var vertices: PackedVector3Array = mesh_instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for vertex: Vector3 in vertices:
			var point: Vector3 = to_self * vertex
			if point.y < lowest.y:
				lowest = point
	return lowest


## True when a piece that is missing from the model should be on it again.
func _has_refitted_part(damage: PackedFloat32Array) -> bool:
	for index: int in range(PlaneActor.PART_COUNT):
		if _pieces[index] == null and PlaneActor.PART_DETACHES[index] and not _is_missing(index, damage):
			return true
	return false


## Whether a part is off the plane: destroyed itself, or hanging on one that is.
func _is_missing(part: int, damage: PackedFloat32Array) -> bool:
	var current: int = part
	while current >= 0:
		if damage[current] >= 1.0 and PlaneActor.PART_DETACHES[current]:
			return true
		current = PlaneActor.PART_PARENT[current]
	return false


func _rebuild_with(damage: PackedFloat32Array) -> void:
	build(_data, _team)
	for index: int in range(PlaneActor.PART_COUNT):
		if _pieces[index] == null or not is_instance_valid(_pieces[index]):
			_pieces[index] = null
			continue
		if damage[index] >= 1.0 and PlaneActor.PART_DETACHES[index]:
			var piece: Node3D = _pieces[index]
			_pieces[index] = null
			_any_detached = true
			piece.get_parent().remove_child(piece)
			piece.queue_free()
	# Children of a removed piece went with it.
	for index: int in range(PlaneActor.PART_COUNT):
		if _pieces[index] != null and _is_missing(index, damage):
			_pieces[index] = null


## Unbolts a piece and hands it to a Debris node in the world.
func _detach(part: int, plane_velocity: Vector3) -> void:
	var piece: Node3D = _pieces[part]
	_pieces[part] = null
	_any_detached = true
	if piece == null or not piece.is_inside_tree():
		return
	var actor: Node = get_parent()
	var world: Node = actor.get_parent() if actor != null else null
	if world == null:
		piece.queue_free()
		return
	# Thrown outward from the plane's centre line, and a little back.
	var outward: Vector3 = piece.global_position - global_position
	var debris: Debris = Debris.new()
	debris.name = "Debris_%s" % piece.name
	world.add_child(debris)
	debris.launch(piece, plane_velocity * 0.92 + outward.normalized() * 9.0)


## Replaces the model's materials with the game's toon materials, chosen by
## the material names the Blender script gave each surface.
func _paint(node: Node) -> void:
	var mesh_instance: MeshInstance3D = node as MeshInstance3D
	if mesh_instance != null and mesh_instance.mesh != null:
		for surface: int in range(mesh_instance.mesh.get_surface_count()):
			var source: Material = mesh_instance.mesh.surface_get_material(surface)
			var material_name: String = source.resource_name if source != null else ""
			mesh_instance.set_surface_override_material(surface, _material_for(material_name))
		var casts: bool = SHADOW_CASTERS.has(StringName(mesh_instance.name))
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child: Node in node.get_children():
		_paint(child)


func _material_for(material_name: String) -> Material:
	match material_name:
		"BodyPrimary":
			return ToonMaterials.toon(_data.body_color)
		"WingAccent_TeamColor":
			return ToonMaterials.toon(Teams.color_of(_team))
		"CanopyGlass":
			return ToonMaterials.glass()
		"PropellerWood":
			return ToonMaterials.toon(WOOD_COLOR)
		"PilotSkin":
			return ToonMaterials.toon(SKIN_COLOR)
		"PilotLeather":
			return ToonMaterials.toon(LEATHER_COLOR)
	# MetalDark, and anything a future model adds without telling us.
	return ToonMaterials.toon(GUNMETAL_COLOR, 0.0, 0.7)


## A node's transform relative to this PlaneVisual, found by walking up the
## tree, so it works before the node is inside the scene tree.
func _transform_to_self(node: Node3D) -> Transform3D:
	var result: Transform3D = Transform3D.IDENTITY
	var current: Node3D = node
	while current != null and current != self:
		result = current.transform * result
		current = current.get_parent() as Node3D
	return result


## The box or boxes for one piece, in PlaneActor space.
func _piece_boxes(node_name: StringName) -> Array[AABB]:
	var result: Array[AABB] = []
	if _model == null:
		return result
	var mesh_instance: MeshInstance3D = _model.find_child(node_name, true, false) as MeshInstance3D
	if mesh_instance == null or mesh_instance.mesh == null:
		return result
	var to_self: Transform3D = _transform_to_self(mesh_instance)
	var whole: AABB = to_self * mesh_instance.mesh.get_aabb()
	if SLICED_PIECES.has(node_name):
		var slicing: Array = SLICED_PIECES[node_name]
		var axis: int = slicing[0]
		var count: int = slicing[1]
		result = _sliced_boxes(mesh_instance.mesh, to_self, whole, axis, count)
	else:
		result.append(whole)
	# A control surface sits in a notch cut out of its parent, so cut the
	# parent's boxes short where the surface begins.
	for pair: Array in NOTCHED_PIECES:
		var parent_name: StringName = pair[0]
		var surface_name: StringName = pair[1]
		if parent_name != node_name:
			continue
		var surface_node: MeshInstance3D = _model.find_child(surface_name, true, false) as MeshInstance3D
		if surface_node == null or surface_node.mesh == null:
			continue
		var surface: AABB = _transform_to_self(surface_node) * surface_node.mesh.get_aabb()
		# Keep a sliver of overlap so no bullet can slip between the two.
		var cut: float = surface.position.z + surface.size.z * 0.1
		for index: int in range(result.size()):
			var box: AABB = result[index]
			var overlaps_span: bool = box.position.x < surface.end.x and box.end.x > surface.position.x \
					and box.position.y < surface.end.y and box.end.y > surface.position.y
			if overlaps_span and cut < box.end.z and cut > box.position.z:
				box.size.z = cut - box.position.z
				result[index] = box
	return result


## Measures a mesh in [param count] slices along [param axis] and returns the
## box round the vertices in each slice.
func _sliced_boxes(mesh: Mesh, to_self: Transform3D, whole: AABB, axis: int, count: int) -> Array[AABB]:
	var lows: Array[Vector3] = []
	var highs: Array[Vector3] = []
	for _slice: int in range(count):
		lows.append(Vector3(INF, INF, INF))
		highs.append(Vector3(-INF, -INF, -INF))
	var start: float = whole.position[axis]
	var length: float = maxf(whole.size[axis], 0.0001)
	for surface: int in range(mesh.get_surface_count()):
		var vertices: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for vertex: Vector3 in vertices:
			var point: Vector3 = to_self * vertex
			var slice: int = clampi(floori((point[axis] - start) / length * float(count)), 0, count - 1)
			lows[slice] = lows[slice].min(point)
			highs[slice] = highs[slice].max(point)
	var result: Array[AABB] = []
	var slice_length: float = length / float(count)
	for slice: int in range(count):
		if lows[slice].x > highs[slice].x:
			continue  # No vertices landed in this slice.
		# Faces span between vertices, so stretch each box to fill its slice.
		var low: Vector3 = lows[slice]
		var high: Vector3 = highs[slice]
		low[axis] = start + slice_length * float(slice)
		high[axis] = start + slice_length * float(slice + 1)
		result.append(AABB(low, high - low))
	return result


## Eases the surfaces toward where the controls are held. Each hinged piece's
## local X axis (local Y for the rudder) lies along its hinge line.
func _animate_controls(delta: float) -> void:
	if _pieces.is_empty():
		return
	_control_shown = _control_shown.lerp(_control_target, 1.0 - exp(-CONTROL_RESPONSE * delta))
	# A positive turn about a surface's hinge swings its trailing edge down.
	# Rolling right: left aileron down, right aileron up.
	_deflect(PlaneActor.Part.LEFT_AILERON, Vector3.RIGHT, _control_shown.x * AILERON_MAX)
	_deflect(PlaneActor.Part.RIGHT_AILERON, Vector3.RIGHT, -_control_shown.x * AILERON_MAX)
	# Nose up: elevator trailing edges up.
	_deflect(PlaneActor.Part.LEFT_ELEVATOR, Vector3.RIGHT, -_control_shown.y * ELEVATOR_MAX)
	_deflect(PlaneActor.Part.RIGHT_ELEVATOR, Vector3.RIGHT, -_control_shown.y * ELEVATOR_MAX)
	# Nose right: rudder trailing edge to the right.
	_deflect(PlaneActor.Part.RUDDER, Vector3.UP, _control_shown.x * RUDDER_MAX)
	_deflect(PlaneActor.Part.LEFT_FLAP, Vector3.RIGHT, _control_shown.z * FLAP_MAX)
	_deflect(PlaneActor.Part.RIGHT_FLAP, Vector3.RIGHT, _control_shown.z * FLAP_MAX)


func _deflect(part: PlaneActor.Part, hinge_axis: Vector3, angle: float) -> void:
	var piece: Node3D = _pieces[part]
	if piece != null:
		piece.basis = _rest_bases[part] * Basis(hinge_axis, angle)


func _build_particles() -> void:
	_part_smoke.resize(PlaneActor.PART_COUNT)
	for part: PlaneActor.Part in SMOKING_PARTS:
		var piece: Node3D = _pieces[part]
		if piece == null:
			continue
		# Emitters sit on the plane at the piece's joint rather than on the
		# piece, so a wing that has been shot off still leaves a smoking stump.
		var smoke: CPUParticles3D = _make_trail("Smoke%d" % part, Color(0.2, 0.2, 0.22, 0.75), 20, 1.0, 0.9, 3.6)
		smoke.position = _transform_to_self(piece).origin
		_part_smoke[part] = smoke
	var engine: Node3D = _pieces[PlaneActor.Part.ENGINE]
	_engine_fire = _make_trail("EngineFire", Color(1.0, 0.5, 0.1, 0.95), 16, 0.35, 0.9, 2.2)
	if engine != null:
		_engine_fire.position = _transform_to_self(engine).origin
	_fuel_fire = _make_trail("FuelFire", Color(1.0, 0.62, 0.15, 0.95), 16, 0.4, 1.0, 2.6)
	_screen_smoke = _make_trail("SmokeScreen", Color(0.93, 0.95, 1.0, 0.85), 48, 2.6, 3.0, 12.0)
	var tail: Node3D = _pieces[PlaneActor.Part.TAIL]
	if tail != null:
		_screen_smoke.position = _transform_to_self(tail).origin


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
	_unit_sphere.radial_segments = 12
	_unit_sphere.rings = 6
	_unit_cylinder = CylinderMesh.new()
	_unit_cylinder.top_radius = 0.5
	_unit_cylinder.bottom_radius = 0.5
	_unit_cylinder.height = 1.0
	_unit_cylinder.radial_segments = 24
	_unit_cylinder.rings = 1
	_particle_mesh = SphereMesh.new()
	_particle_mesh.radius = 0.5
	_particle_mesh.height = 1.0
	_particle_mesh.radial_segments = 8
	_particle_mesh.rings = 4
