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
##  - shows exactly what is fitted: the model carries every alternative (each
##    kind of gun at each station, both propellers, the bigger engines' intake
##    and bulges, armour plates, three kinds of wingtip, two undercarriages)
##    and build() strips out everything the loadout does not include. A plane
##    with one gun fitted has one gun on its wing,
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
	&"WingTipExtL": PlaneActor.Part.LEFT_WINGTIP,
	&"WingTipExtR": PlaneActor.Part.RIGHT_WINGTIP,
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
## Gun stations in PlaneStats order, as they are named on the model, and the
## kinds of gun modelled at each (ComponentCard.model_variant of a gun).
const GUN_STATION_TAGS: Array[String] = ["L1", "R1", "L2", "R2"]
const GUN_KINDS: Array[String] = ["303", "50", "20"]
## Model pieces each fitting adds, by ComponentCard.model_variant. Pieces in
## OPTIONAL_PIECES that nothing fitted asks for are taken off the model.
const VARIANT_PIECES: Dictionary[StringName, Array] = {
	&"engine_two_stage": [&"EngineIntake"],
	&"engine_griffon": [&"EngineIntake", &"EngineBulges"],
	&"armour_seat": [&"ArmourSeat"],
	&"armour_full": [&"ArmourSeat", &"ArmourScreen"],
	&"tips_extended": [&"WingTipExtL", &"WingTipExtR"],
}
const OPTIONAL_PIECES: Array[StringName] = [
	&"EngineIntake", &"EngineBulges", &"ArmourSeat", &"ArmourScreen", &"WingTipExtL", &"WingTipExtR",
]
## Fittings that replace a piece's shape: variant -> [[piece, piece holding the
## replacement mesh], ...]. The holders are always removed afterwards.
const VARIANT_MESH_SWAPS: Dictionary[StringName, Array] = {
	&"tips_clipped": [[&"WingTipL", &"WingTipL_clipped"], [&"WingTipR", &"WingTipR_clipped"]],
	&"gear_heavy": [[&"GearL", &"GearL_heavy"], [&"GearR", &"GearR_heavy"]],
}
const MESH_HOLDERS: Array[StringName] = [&"WingTipL_clipped", &"WingTipR_clipped", &"GearL_heavy", &"GearR_heavy"]
const PROPELLER_NODES: Array[StringName] = [&"PropellerMesh", &"PropellerMesh4"]
const FOUR_BLADE_VARIANT: StringName = &"prop4"
## Main undercarriage legs (left, right) and the tail wheel.
const GEAR_NODES: Array[StringName] = [&"GearL", &"GearR"]
const TAIL_WHEEL_NODE: StringName = &"TailWheel"
## How far each leg swings outward to lie under its wing.
const GEAR_RETRACT_ANGLE: float = deg_to_rad(86.0)
## What is left of the propeller disc after it has hit the ground.
const BROKEN_PROP_SCALE: Vector3 = Vector3(0.45, 0.45, 1.0)
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
## Bullet holes. Each piece of the model keeps this many; after that the
## oldest is painted over by the newest.
const HOLES_PER_PIECE: int = 18
## A hole's width in metres: this, plus this much per point of the round's
## damage (a rifle-calibre round about 20 cm of torn metal and soot, a cannon
## shell 36). Where a round comes out it leaves a bigger one.
const HOLE_SIZE: float = 0.1
const HOLE_SIZE_PER_DAMAGE: float = 0.0005
const EXIT_HOLE_SCALE: float = 1.35
## How far a hole is held off the skin it lies on, metres.
const HOLE_LIFT: float = 0.012
## A bullet marks no more than this many of the pieces it passes through.
const HOLED_PIECES_PER_BULLET: int = 3
## Parts that are solid all the way through: hit, they are holed where the
## bullet goes in but it does not come out the other side, and their damage
## shows as burnt and chipped paint, never as holes torn right through.
const SOLID_PARTS: Array[PlaneActor.Part] = [PlaneActor.Part.FUSELAGE, PlaneActor.Part.ENGINE]
## Smoke from a damaged part: thin and grey at first, thick and black once it
## is critical. [colour, size].
const LIGHT_SMOKE: Color = Color(0.72, 0.72, 0.74, 0.5)
const HEAVY_SMOKE: Color = Color(0.1, 0.1, 0.11, 0.85)

static var _unit_sphere: SphereMesh
static var _unit_cylinder: CylinderMesh
static var _particle_mesh: SphereMesh
static var _hole_mesh: QuadMesh
## Every triangle of a mesh (three corners each), read once and kept.
static var _triangles: Dictionary[Mesh, PackedVector3Array] = {}

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
## What is fitted, in mount order (see CommanderProgression); may be empty.
var _fittings: Array[ComponentCard] = []
## The gun piece at each station, or null where no gun is fitted.
var _gun_nodes: Array[MeshInstance3D] = []
## Smoke emitter per Part (null where a part does not smoke).
var _part_smoke: Array[CPUParticles3D] = []
var _engine_fire: CPUParticles3D
var _fuel_fire: CPUParticles3D
var _control_target: Vector3 = Vector3.ZERO
var _control_shown: Vector3 = Vector3.ZERO
var _rudder_target: float = 0.0
var _rudder_shown: float = 0.0
var _prop_speed: float = 40.0
var _prop_target: float = 40.0
var _gear: Array[Node3D] = []
var _gear_rest: Array[Basis] = []
var _gear_deploy: float = -1.0
## Undercarriage legs that have collapsed and left the model (bit 0 = left).
var _gear_broken: int = 0
var _prop_broken: bool = false
var _last_damage: PackedFloat32Array = PackedFloat32Array()
## The damage each part is drawn with (negative: not drawn yet).
var _shown_damage: PackedFloat32Array = PackedFloat32Array()
## For each Part, the model pieces that are its skin (what a bullet can hole)
## and every piece that wears its damage.
var _part_skin: Array[Array] = []
var _part_wearers: Array[Array] = []
## The bullet holes on each piece, and how many it has had.
var _holes: Dictionary[MeshInstance3D, MultiMesh] = {}
var _hole_counts: Dictionary[MeshInstance3D, int] = {}
## Makes this plane's damage patterns its own.
var _damage_seed: float = 0.0


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
			if _muzzle_timers[index] <= 0.0 and _muzzle_flashes[index] != null and is_instance_valid(_muzzle_flashes[index]):
				_muzzle_flashes[index].visible = false
	_animate_controls(delta)


## (Re)builds the model for [param data] in [param team] colours, showing
## [param fittings] (in mount order; null or missing entries are empty mounts).
func build(data: PlaneData, team: Teams.Id, fittings: Array[ComponentCard] = []) -> void:
	_data = data
	_team = team
	_fittings = fittings
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_pieces.clear()
	_rest_bases.clear()
	_muzzle_flashes.clear()
	_muzzle_timers.clear()
	_gun_nodes.clear()
	_part_smoke.clear()
	_holes.clear()
	_hole_counts.clear()
	_shown_damage.clear()
	_shown_damage.resize(PlaneActor.PART_COUNT)
	_shown_damage.fill(-1.0)
	_damage_seed = randf()
	_any_detached = false
	_control_shown = Vector3.ZERO
	_rudder_shown = 0.0
	_gear.clear()
	_gear_rest.clear()
	_ensure_shared_meshes()

	_model = MODEL.instantiate() as Node3D
	_model.name = "Model"
	_model.scale = Vector3.ONE * model_scale()
	add_child(_model)
	_apply_fittings()
	_paint(_model)

	for node_name: StringName in PART_NODES:
		var piece: Node3D = _model.find_child(node_name, true, false) as Node3D
		_pieces.append(piece)
		_rest_bases.append(piece.basis if piece != null else Basis.IDENTITY)

	_sort_pieces_by_part()

	for node_name: StringName in GEAR_NODES:
		var leg: Node3D = _model.find_child(node_name, true, false) as Node3D
		_gear.append(leg)
		_gear_rest.append(leg.basis if leg != null else Basis.IDENTITY)
	for index: int in range(_gear.size()):
		# A leg that has collapsed stays off a rebuilt model.
		if _gear_broken & (1 << index) != 0 and _gear[index] != null:
			_gear[index].get_parent().remove_child(_gear[index])
			_gear[index].queue_free()
			_gear[index] = null
	var shown_deploy: float = _gear_deploy
	_gear_deploy = -1.0
	_apply_gear(maxf(shown_deploy, 0.0))
	_propeller = _find_propeller()
	if _propeller != null and _prop_broken:
		_propeller.scale = BROKEN_PROP_SCALE
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

	# A muzzle flash on the end of every fitted gun.
	for station: int in range(_gun_nodes.size()):
		var gun: MeshInstance3D = _gun_nodes[station]
		var flash: MeshInstance3D = null
		if gun != null:
			flash = MeshInstance3D.new()
			flash.name = "MuzzleFlash"
			flash.mesh = _unit_sphere
			flash.material_override = ToonMaterials.unlit(Color(1.0, 0.86, 0.3), true)
			var muzzle_z: float = gun.mesh.get_aabb().position.z
			flash.transform = Transform3D(Basis.from_scale(Vector3(0.45, 0.45, 1.2)), Vector3(0.0, 0.0, muzzle_z - 0.45))
			flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			flash.visible = false
			gun.add_child(flash)
		_muzzle_flashes.append(flash)
		_muzzle_timers.append(0.0)

	_build_particles()


## Factor from model units to plane units for this plane.
func model_scale() -> float:
	return _data.wing_span * VISUAL_SCALE / MODEL_WING_SPAN


## Puts back anything that has been shot off (used on respawn).
func restore() -> void:
	if _any_detached and _data != null:
		build(_data, _team, _fittings)
	# A new aeroplane has no holes in it.
	for part: int in range(_part_skin.size()):
		_patch_holes(part)
	stop_effects()


## Where each gun station's muzzle is, in PlaneActor space, in station order.
## Vector3.ZERO for a station with no gun.
func gun_muzzles() -> Array[Vector3]:
	var muzzles: Array[Vector3] = []
	for gun: MeshInstance3D in _gun_nodes:
		if gun == null:
			muzzles.append(Vector3.ZERO)
			continue
		var box: AABB = gun.mesh.get_aabb()
		muzzles.append(_transform_to_self(gun) * Vector3(box.get_center().x, box.get_center().y, box.position.z))
	return muzzles


## Whether a gun is shown at [param station] (0 = left inner, 1 = right inner,
## 2 = left outer, 3 = right outer).
func has_gun_at(station: int) -> bool:
	return station >= 0 and station < _gun_nodes.size() and _gun_nodes[station] != null \
			and is_instance_valid(_gun_nodes[station]) and _model.is_ancestor_of(_gun_nodes[station])


## Whether a named piece of the model is present (after fittings were applied).
func has_model_piece(piece_name: StringName) -> bool:
	return _model != null and _model.find_child(piece_name, true, false) != null


## The piece that spins: PropellerMesh or PropellerMesh4, whichever is fitted.
func propeller_piece_name() -> StringName:
	return StringName(_propeller.name) if _propeller != null else &""


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
	if index < 0 or index >= _muzzle_flashes.size() or _muzzle_flashes[index] == null or not is_instance_valid(_muzzle_flashes[index]):
		return
	_muzzle_flashes[index].visible = true
	_muzzle_timers[index] = MUZZLE_FLASH_TIME


## 0 = propeller stopped, 1 = full throttle. It spools up and winds down to
## the new speed unless [param at_once] is set (a plane standing in a hangar).
func set_propeller(ratio: float, at_once: bool = false) -> void:
	_prop_target = 0.0 if ratio <= 0.0 else lerpf(8.0, 62.0, clampf(ratio, 0.0, 1.5))
	if at_once:
		_prop_speed = _prop_target


## A smashed propeller is shown as stumps on a stopped hub.
func set_propeller_broken(broken: bool) -> void:
	if broken == _prop_broken:
		return
	_prop_broken = broken
	if _propeller != null:
		_propeller.scale = BROKEN_PROP_SCALE if broken else Vector3.ONE


## Whether an undercarriage leg (0 = left, 1 = right) is still on the model.
func has_gear_leg(index: int) -> bool:
	return index < _gear.size() and _gear[index] != null and is_instance_valid(_gear[index]) and _model.is_ancestor_of(_gear[index])


## 0 = undercarriage up (and hidden inside the wings), 1 = down and locked.
## [param broken_mask] says which legs have collapsed (bit 0 = left, bit 1 =
## right): a leg that has just gone is thrown clear with [param plane_velocity],
## and one that has been replaced comes back.
func set_gear(deploy: float, broken_mask: int = 0, plane_velocity: Vector3 = Vector3.ZERO) -> void:
	if broken_mask != _gear_broken:
		var replaced: int = _gear_broken & ~broken_mask
		var newly_broken: int = broken_mask & ~_gear_broken
		_gear_broken = broken_mask
		if replaced != 0 and _data != null:
			if _last_damage.size() >= PlaneActor.PART_COUNT:
				_rebuild_with(_last_damage)
			else:
				build(_data, _team, _fittings)
		for index: int in range(_gear.size()):
			if newly_broken & (1 << index) != 0 and has_gear_leg(index):
				_throw_clear(_gear[index], plane_velocity * 0.85 + Vector3.UP * 3.0)
				_gear[index] = null
	_apply_gear(deploy)


func _apply_gear(deploy: float) -> void:
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
	_apply_gear(1.0)
	var main_wheel: Vector3 = _lowest_point(GEAR_NODES[0])
	var tail_wheel: Vector3 = _lowest_point(TAIL_WHEEL_NODE)
	_apply_gear(shown)
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


## Shows the state of every part. [param damage] is PlaneActor.part_damage.
## Damaged parts smoke; a part that has just been destroyed is unbolted and
## thrown clear with [param plane_velocity], taking its attachments with it.
func set_part_damage(damage: PackedFloat32Array, plane_velocity: Vector3, burning: bool) -> void:
	if damage.size() < PlaneActor.PART_COUNT or _pieces.is_empty():
		return
	_last_damage = damage
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
	_show_damage(damage)
	for part: PlaneActor.Part in SMOKING_PARTS:
		var smoke: CPUParticles3D = _part_smoke[part]
		if smoke != null:
			smoke.emitting = damage[part] >= PlaneActor.PART_DAMAGED_AT
			# Thin grey smoke from a damaged part, thick and black once it is critical.
			var heavy: bool = damage[part] >= PlaneActor.PART_CRITICAL_AT
			smoke.color = HEAVY_SMOKE if heavy else LIGHT_SMOKE
			smoke.scale_amount_min = 0.9 if heavy else 0.5
			smoke.scale_amount_max = 1.3 if heavy else 0.75
	if _engine_fire != null:
		_engine_fire.emitting = damage[PlaneActor.Part.ENGINE] >= 1.0
	if _fuel_fire != null:
		_fuel_fire.emitting = burning and damage[PlaneActor.Part.ENGINE] < 1.0


## How badly [param part] is drawn damaged, 0..1 (what its pieces' paint is
## being told), or -1 if it has not been drawn yet.
func shown_damage(part: PlaneActor.Part) -> float:
	return _shown_damage[part] if part < _shown_damage.size() else -1.0


## How many bullet holes are showing on [param part].
func bullet_hole_count(part: PlaneActor.Part) -> int:
	var total: int = 0
	if part >= _part_skin.size():
		return 0
	for piece: MeshInstance3D in _still_there(_part_skin[part]):
		if _holes.has(piece):
			total += _holes[piece].visible_instance_count
	return total


## Where the bullet holes on [param part] are, in this node's space.
func bullet_hole_positions(part: PlaneActor.Part) -> Array[Vector3]:
	var result: Array[Vector3] = []
	if part >= _part_skin.size():
		return result
	for piece: MeshInstance3D in _still_there(_part_skin[part]):
		if not _holes.has(piece):
			continue
		var to_self: Transform3D = _transform_to_self(piece)
		var holes: MultiMesh = _holes[piece]
		for index: int in range(holes.visible_instance_count):
			result.append(to_self * holes.get_instance_transform(index).origin)
	return result


## Puts bullet holes where a bullet's path meets the skin of the pieces it
## went through. [param origin] and [param direction] are the path in this
## node's space; [param parts] the Parts it passed through, nearest first.
## It goes in through the first skin it meets on each piece and, on thin
## pieces, out through the last.
func add_bullet_holes(origin: Vector3, direction: Vector3, parts: PackedInt32Array, damage: float) -> void:
	if _model == null or _part_skin.is_empty() or direction.length_squared() < 0.0001:
		return
	var size: float = HOLE_SIZE + HOLE_SIZE_PER_DAMAGE * damage
	var heading: Vector3 = direction.normalized()
	var marked: int = 0
	for index: int in range(parts.size()):
		if marked >= HOLED_PIECES_PER_BULLET:
			return
		var part: int = parts[index]
		if part < 0 or part >= _part_skin.size() or _pieces[part] == null:
			continue
		if _hole_part(part, origin, heading, size):
			marked += 1
		elif index == 0:
			# It hit, but only in the margin round the piece: put the hole
			# where it would have gone in had it been aimed at the middle.
			var piece: MeshInstance3D = _pieces[part] as MeshInstance3D
			if piece != null and piece.mesh != null:
				var middle: Vector3 = _transform_to_self(piece) * piece.mesh.get_aabb().get_center()
				if _hole_part(part, origin, (middle - origin).normalized(), size):
					marked += 1


## Holes one part along a path. False if the path misses its skin altogether.
func _hole_part(part: int, origin: Vector3, heading: Vector3, size: float) -> bool:
	var entry_piece: MeshInstance3D = null
	var entry_distance: float = INF
	var entry_point: Vector3 = Vector3.ZERO
	var entry_normal: Vector3 = Vector3.ZERO
	var exit_piece: MeshInstance3D = null
	var exit_distance: float = -INF
	var exit_point: Vector3 = Vector3.ZERO
	var exit_normal: Vector3 = Vector3.ZERO
	for piece: MeshInstance3D in _still_there(_part_skin[part]):
		if piece.mesh == null:
			continue
		# The path in the piece's own space. The heading is left its full
		# (scaled) length, so distances along it are still metres.
		var to_piece: Transform3D = _transform_to_self(piece).affine_inverse()
		var from: Vector3 = to_piece * origin
		var along: Vector3 = to_piece.basis * heading
		if piece.mesh.get_aabb().grow(0.01).intersects_ray(from, along) == null:
			continue
		var per_metre: float = along.length_squared()
		var corners: PackedVector3Array = _triangles_of(piece.mesh)
		for corner: int in range(0, corners.size(), 3):
			var hit: Variant = Geometry3D.ray_intersects_triangle(from, along, corners[corner], corners[corner + 1], corners[corner + 2])
			if hit == null:
				continue
			var point: Vector3 = hit
			var distance: float = (point - from).dot(along) / per_metre
			if distance < entry_distance or distance > exit_distance:
				var normal: Vector3 = (corners[corner + 1] - corners[corner]).cross(corners[corner + 2] - corners[corner]).normalized()
				if distance < entry_distance:
					entry_distance = distance
					entry_piece = piece
					entry_point = point
					# Facing back up the path, whichever way the triangle is wound.
					entry_normal = -normal if normal.dot(along) > 0.0 else normal
				if distance > exit_distance:
					exit_distance = distance
					exit_piece = piece
					exit_point = point
					exit_normal = normal if normal.dot(along) > 0.0 else -normal
	if entry_piece == null:
		return false
	_put_hole(entry_piece, entry_point, entry_normal, size)
	if not SOLID_PARTS.has(part as PlaneActor.Part) and exit_piece != null and exit_distance - entry_distance > 0.03:
		_put_hole(exit_piece, exit_point, exit_normal, size * EXIT_HOLE_SCALE)
	return true


## Lays one hole on a piece, at [param point] facing [param normal], both in
## the piece's own space.
func _put_hole(piece: MeshInstance3D, point: Vector3, normal: Vector3, size: float) -> void:
	var holes: MultiMesh = _holes.get(piece) as MultiMesh
	if holes == null:
		holes = MultiMesh.new()
		holes.transform_format = MultiMesh.TRANSFORM_3D
		holes.use_custom_data = true
		holes.mesh = _hole_mesh
		holes.instance_count = HOLES_PER_PIECE
		holes.visible_instance_count = 0
		var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
		instance.name = "BulletHoles"
		instance.multimesh = holes
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		piece.add_child(instance)
		_holes[piece] = holes
		_hole_counts[piece] = 0
	# Sizes are in metres; the piece is in model units.
	var unit: float = 1.0 / maxf(model_scale(), 0.001)
	var across: Vector3 = normal.cross(Vector3.FORWARD if absf(normal.z) < 0.9 else Vector3.RIGHT).normalized()
	across = across.rotated(normal, randf() * TAU)
	var width: float = size * unit
	var hole_basis: Basis = Basis(across * width, normal.cross(across) * width, normal)
	var count: int = _hole_counts[piece]
	var slot: int = count % HOLES_PER_PIECE
	holes.set_instance_transform(slot, Transform3D(hole_basis, point + normal * HOLE_LIFT * unit))
	holes.set_instance_custom_data(slot, Color(randf(), 1.0, 0.8, 0.0))
	_hole_counts[piece] = count + 1
	holes.visible_instance_count = mini(count + 1, HOLES_PER_PIECE)


## Removes the bullet holes from a part's skin (it has been patched).
func _patch_holes(part: int) -> void:
	for piece: MeshInstance3D in _still_there(_part_skin[part]):
		if _holes.has(piece):
			_holes[piece].visible_instance_count = 0
			_hole_counts[piece] = 0


## Tells every piece of the model how hurt its part is, so that its paint
## shows it (see shaders/toon_plane_damage.gdshader). A part that is better
## than it was has been repaired: its bullet holes go too.
func _show_damage(damage: PackedFloat32Array) -> void:
	if _part_wearers.size() < PlaneActor.PART_COUNT:
		return
	for part: int in range(PlaneActor.PART_COUNT):
		var level: float = clampf(damage[part], 0.0, 1.0)
		if is_equal_approx(level, _shown_damage[part]):
			continue
		if level < _shown_damage[part] - 0.001:
			_patch_holes(part)
		_shown_damage[part] = level
		for piece: MeshInstance3D in _still_there(_part_wearers[part]):
			piece.set_instance_shader_parameter(&"damage", level)


## Works out which pieces of the model belong to which Part: its skin (the
## part's own piece and any others that are hit as part of it), and
## everything bolted to it that should look as battered as it does (guns,
## wheels, armour), which is every piece below it in the model down to the
## next Part.
func _sort_pieces_by_part() -> void:
	_part_skin.clear()
	_part_wearers.clear()
	for part: int in range(PlaneActor.PART_COUNT):
		var skin: Array[MeshInstance3D] = []
		var wearers: Array[MeshInstance3D] = []
		var piece: MeshInstance3D = _pieces[part] as MeshInstance3D
		if piece != null:
			skin.append(piece)
			_collect_wearers(piece, wearers)
		_part_skin.append(skin)
		_part_wearers.append(wearers)
	for node_name: StringName in EXTRA_HIT_NODES:
		var extra: MeshInstance3D = _model.find_child(node_name, true, false) as MeshInstance3D
		if extra != null:
			_part_skin[EXTRA_HIT_NODES[node_name]].append(extra)
	for part: int in range(PlaneActor.PART_COUNT):
		var thin: float = 0.0 if SOLID_PARTS.has(part as PlaneActor.Part) else 1.0
		for wearer: MeshInstance3D in _part_wearers[part]:
			wearer.set_instance_shader_parameter(&"damage", 0.0)
			wearer.set_instance_shader_parameter(&"damage_seed", _damage_seed + float(part) * 0.37)
			# Only the skin itself tears open; what is bolted to it does not.
			wearer.set_instance_shader_parameter(&"skin", thin if _part_skin[part].has(wearer) else 0.0)


## The pieces in [param pieces] that are still on the model: a piece that has
## been shot off, or taken off for what is fitted, is gone for good.
func _still_there(pieces: Array) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for entry: Variant in pieces:
		if is_instance_valid(entry):
			var piece: MeshInstance3D = entry as MeshInstance3D
			if piece != null and not piece.is_queued_for_deletion():
				result.append(piece)
	return result


func _collect_wearers(node: Node, out: Array[MeshInstance3D]) -> void:
	var mesh_instance: MeshInstance3D = node as MeshInstance3D
	if mesh_instance != null and mesh_instance.mesh != null and not PROPELLER_NODES.has(StringName(node.name)):
		out.append(mesh_instance)
	for child: Node in node.get_children():
		# Another Part's piece, and everything under it, is that Part's business.
		if not PART_NODES.has(StringName(child.name)):
			_collect_wearers(child, out)


static func _triangles_of(mesh: Mesh) -> PackedVector3Array:
	if not _triangles.has(mesh):
		_triangles[mesh] = mesh.get_faces()
	return _triangles[mesh]


## Where the pilot has the controls: x = roll/yaw (-1 left .. +1 right),
## y = pitch (-1 down .. +1 up), z = flaps (0 up .. 1 fully down).
func set_controls(state: Vector3, rudder: float = 0.0) -> void:
	_control_target = state
	_rudder_target = rudder


func stop_effects() -> void:
	for smoke: CPUParticles3D in _part_smoke:
		if smoke != null:
			smoke.emitting = false
	if _engine_fire != null:
		_engine_fire.emitting = false
	if _fuel_fire != null:
		_fuel_fire.emitting = false
	for flash: MeshInstance3D in _muzzle_flashes:
		if flash != null and is_instance_valid(flash):
			flash.visible = false


## Whether the model piece for [param part] is still attached.
func has_piece(part: PlaneActor.Part) -> bool:
	return part < _pieces.size() and _pieces[part] != null


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

## Strips the model down to what is fitted. Runs on the fresh model, before
## anything else looks at it, so hit boxes, wheel heights and gun muzzles are
## all measured from the aeroplane as it is actually equipped.
func _apply_fittings() -> void:
	var wanted: Array[StringName] = []
	var swaps: Array = []
	var four_blade: bool = false
	for card: ComponentCard in _fittings:
		if card == null or card.is_gun():
			continue
		if card.model_variant == FOUR_BLADE_VARIANT:
			four_blade = true
		if VARIANT_PIECES.has(card.model_variant):
			var added: Array = VARIANT_PIECES[card.model_variant]
			for piece_name: StringName in added:
				wanted.append(piece_name)
		if VARIANT_MESH_SWAPS.has(card.model_variant):
			swaps.append_array(VARIANT_MESH_SWAPS[card.model_variant])
	# Guns: at each station keep the one kind that is fitted there, if any.
	for station: int in range(GUN_STATION_TAGS.size()):
		var fitted: ComponentCard = _fittings[station] if station < _fittings.size() else null
		var kept: MeshInstance3D = null
		for kind: String in GUN_KINDS:
			var gun_name: String = "Gun%s_%s" % [GUN_STATION_TAGS[station], kind]
			if fitted != null and fitted.is_gun() and String(fitted.model_variant) == kind:
				kept = _model.find_child(gun_name, true, false) as MeshInstance3D
			else:
				_remove_piece(StringName(gun_name))
		_gun_nodes.append(kept)
	_remove_piece(PROPELLER_NODES[0] if four_blade else PROPELLER_NODES[1])
	for piece_name: StringName in OPTIONAL_PIECES:
		if not wanted.has(piece_name):
			_remove_piece(piece_name)
	for swap: Array in swaps:
		var piece_name: StringName = swap[0]
		var holder_name: StringName = swap[1]
		var piece: MeshInstance3D = _model.find_child(piece_name, true, false) as MeshInstance3D
		var holder: MeshInstance3D = _model.find_child(holder_name, true, false) as MeshInstance3D
		if piece != null and holder != null:
			piece.mesh = holder.mesh
	for holder_name: StringName in MESH_HOLDERS:
		_remove_piece(holder_name)


func _remove_piece(piece_name: StringName) -> void:
	var piece: Node = _model.find_child(piece_name, true, false)
	if piece != null:
		piece.get_parent().remove_child(piece)
		piece.queue_free()


func _find_propeller() -> Node3D:
	for node_name: StringName in PROPELLER_NODES:
		var found: Node3D = _model.find_child(node_name, true, false) as Node3D
		if found != null:
			return found
	return null


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
	build(_data, _team, _fittings)
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
	_throw_clear(piece, plane_velocity * 0.92 + outward.normalized() * 9.0)


## Hands a piece of the model to a Debris node in the world, moving at
## [param start_velocity]. Over an airfield it ends up lying on the ground.
func _throw_clear(piece: Node3D, start_velocity: Vector3) -> void:
	var actor: PlaneActor = get_parent() as PlaneActor
	var world: Node = actor.get_parent() if actor != null else null
	if world == null or not piece.is_inside_tree():
		piece.queue_free()
		return
	var debris: Debris = Debris.new()
	debris.name = "Debris_%s" % piece.name
	var field: Airfield = actor.airfield_at(piece.global_position)
	if field != null:
		debris.floor_height = field.surface_y() + 0.3
	world.add_child(debris)
	debris.launch(piece, start_velocity)


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
			return ToonMaterials.toon_damageable(_data.body_color)
		"WingAccent_TeamColor":
			return ToonMaterials.toon_damageable(Teams.color_of(_team))
		"CanopyGlass":
			return ToonMaterials.glass()
		"PropellerWood":
			return ToonMaterials.toon(WOOD_COLOR)
		"PilotSkin":
			return ToonMaterials.toon(SKIN_COLOR)
		"PilotLeather":
			return ToonMaterials.toon(LEATHER_COLOR)
	# MetalDark, and anything a future model adds without telling us.
	return ToonMaterials.toon_damageable(GUNMETAL_COLOR, 0.7)


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
	_rudder_shown = lerpf(_rudder_shown, _rudder_target, 1.0 - exp(-CONTROL_RESPONSE * delta))
	# A positive turn about a surface's hinge swings its trailing edge down.
	# Rolling right: left aileron down, right aileron up.
	_deflect(PlaneActor.Part.LEFT_AILERON, Vector3.RIGHT, _control_shown.x * AILERON_MAX)
	_deflect(PlaneActor.Part.RIGHT_AILERON, Vector3.RIGHT, -_control_shown.x * AILERON_MAX)
	# Nose up: elevator trailing edges up.
	_deflect(PlaneActor.Part.LEFT_ELEVATOR, Vector3.RIGHT, -_control_shown.y * ELEVATOR_MAX)
	_deflect(PlaneActor.Part.RIGHT_ELEVATOR, Vector3.RIGHT, -_control_shown.y * ELEVATOR_MAX)
	# Nose right: rudder trailing edge to the right.
	_deflect(PlaneActor.Part.RUDDER, Vector3.UP, _rudder_shown * RUDDER_MAX)
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
	_hole_mesh = QuadMesh.new()
	_hole_mesh.material = ToonMaterials.bullet_hole()
	_particle_mesh = SphereMesh.new()
	_particle_mesh.radius = 0.5
	_particle_mesh.height = 1.0
	_particle_mesh.radial_segments = 8
	_particle_mesh.rings = 4
