class_name MidairCollisions
extends Node
## Lets aircraft hit each other.
##
## Planes do not use the physics engine against one another (they are flown,
## not simulated). Instead, every physics tick this node checks each pair of
## nearby planes part against part, using the true-size boxes of the pieces of
## their models (PlaneHitboxes.solid_boxes), turned and rolled with each plane.
## Two planes only collide when two of those pieces really overlap, so a
## wingtip can clip a tail and nothing else is touched.
##
## What a contact does depends on how fast the two planes are closing:
##  - each part involved takes damage in proportion to the closing speed, so a
##    slow scrape in formation dents a wingtip and a fast crossing tears a
##    wing off;
##  - both planes are shoved apart and their noses knocked round;
##  - above BREAKUP_SPEED a hit on the fuselage or engine destroys the plane
##    outright, as it would.
## Team-mates can collide too. A collision with an enemy counts as that
## enemy's doing if the plane is later lost.
##
## Networking: runs on the server only.

signal planes_collided(first: PlaneActor, second: PlaneActor, first_part: int, second_part: int, closing_speed: float)

## Part damage per metre-per-second of closing speed (same units as bullet
## damage). At 10 m/s a contact is worth about one bullet; at 40, a burst.
const DAMAGE_PER_SPEED: float = 15.0
## Contacts slower than this are harmless bumps.
const MIN_DAMAGING_SPEED: float = 3.0
## Closing speed above which a blow to the fuselage or engine is not survivable.
const BREAKUP_SPEED: float = 95.0
## After two planes touch they are not tested again for this long, so one
## contact is one event rather than a hit every tick while they overlap.
const CONTACT_COOLDOWN: float = 0.4
## How hard colliding planes are pushed apart, per m/s of closing speed.
const PUSH_PER_SPEED: float = 0.16
const MIN_PUSH: float = 4.0
const MAX_PUSH: float = 16.0
const YAW_KICK: float = 0.6

var _planes: Array[PlaneActor] = []
## Seconds left before a pair may collide again, keyed by both instance ids.
var _cooldowns: Dictionary[int, float] = {}
var _first_parts: PackedInt32Array = PackedInt32Array()
var _second_parts: PackedInt32Array = PackedInt32Array()


func register_plane(plane: PlaneActor) -> void:
	if not _planes.has(plane):
		_planes.append(plane)


func unregister_plane(plane: PlaneActor) -> void:
	_planes.erase(plane)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	for key: int in _cooldowns.keys():
		_cooldowns[key] -= delta
		if _cooldowns[key] <= 0.0:
			_cooldowns.erase(key)
	for first_index: int in range(_planes.size()):
		var first: PlaneActor = _planes[first_index]
		if not first.alive:
			continue
		for second_index: int in range(first_index + 1, _planes.size()):
			var second: PlaneActor = _planes[second_index]
			if not second.alive or not first.alive:
				continue
			var reach: float = first.hitboxes.bounding_radius + second.hitboxes.bounding_radius
			if first.global_position.distance_squared_to(second.global_position) > reach * reach:
				continue
			var key: int = first_index * 1024 + second_index
			if _cooldowns.has(key):
				continue
			if _find_contacts(first, second):
				_cooldowns[key] = CONTACT_COOLDOWN
				_resolve(first, second)


## Fills _first_parts / _second_parts with every pair of touching parts.
## Returns true if there is at least one.
func _find_contacts(first: PlaneActor, second: PlaneActor) -> bool:
	_first_parts.clear()
	_second_parts.clear()
	var first_basis: Basis = first.hit_basis()
	var second_basis: Basis = second.hit_basis()
	var first_boxes: PlaneHitboxes = first.hitboxes
	var second_boxes: PlaneHitboxes = second.hitboxes
	for first_box: int in range(first_boxes.solid_boxes.size()):
		var first_part: int = first_boxes.parts[first_box]
		if first.gone_mask() & (1 << first_part) != 0:
			continue
		var box_a: AABB = first_boxes.solid_boxes[first_box]
		var centre_a: Vector3 = first.global_position + first_basis * box_a.get_center()
		for second_box: int in range(second_boxes.solid_boxes.size()):
			var second_part: int = second_boxes.parts[second_box]
			if second.gone_mask() & (1 << second_part) != 0:
				continue
			var box_b: AABB = second_boxes.solid_boxes[second_box]
			var centre_b: Vector3 = second.global_position + second_basis * box_b.get_center()
			if boxes_overlap(centre_a, first_basis, box_a.size * 0.5, centre_b, second_basis, box_b.size * 0.5):
				_first_parts.append(first_part)
				_second_parts.append(second_part)
	return not _first_parts.is_empty()


func _resolve(first: PlaneActor, second: PlaneActor) -> void:
	var closing_speed: float = (first.velocity - second.velocity).length()
	var hostile: bool = first.is_hostile_to(second)
	# Read everything needed before applying damage: damage can change which
	# parts exist.
	var first_parts: PackedInt32Array = _unique(_first_parts)
	var second_parts: PackedInt32Array = _unique(_second_parts)
	var first_vital: bool = _hits_vitals(first_parts)
	var second_vital: bool = _hits_vitals(second_parts)

	if closing_speed >= MIN_DAMAGING_SPEED:
		var amount: float = DAMAGE_PER_SPEED * closing_speed
		for part: int in first_parts:
			first.apply_damage(amount, second if hostile else null, part as PlaneActor.Part)
		for part: int in second_parts:
			second.apply_damage(amount, first if hostile else null, part as PlaneActor.Part)

	# Shove them apart along the line between them and kick their noses round.
	var apart: Vector3 = first.global_position - second.global_position
	apart = apart.normalized() if apart.length_squared() > 0.0001 else Vector3.UP
	var push: float = clampf(closing_speed * PUSH_PER_SPEED, MIN_PUSH, MAX_PUSH)
	var kick: float = YAW_KICK * clampf(closing_speed / 60.0, 0.2, 1.0)
	var side: float = signf(apart.dot(first.global_transform.basis.x))
	first.knock(apart * push, side * kick)
	second.knock(-apart * push, -side * kick)

	planes_collided.emit(first, second, _first_parts[0], _second_parts[0], closing_speed)

	if closing_speed >= BREAKUP_SPEED:
		if first_vital:
			first.destroy(second if hostile else null)
		if second_vital:
			second.destroy(first if hostile else null)


func _hits_vitals(part_list: PackedInt32Array) -> bool:
	return part_list.has(PlaneActor.Part.FUSELAGE) or part_list.has(PlaneActor.Part.ENGINE)


func _unique(values: PackedInt32Array) -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	for value: int in values:
		if not result.has(value):
			result.append(value)
	return result


## Whether two oriented boxes overlap (separating-axis test). Each box is a
## centre, an orthonormal basis and half-extents along that basis's axes.
static func boxes_overlap(centre_a: Vector3, basis_a: Basis, half_a: Vector3,
		centre_b: Vector3, basis_b: Basis, half_b: Vector3) -> bool:
	var axes_a: Array[Vector3] = [basis_a.x, basis_a.y, basis_a.z]
	var axes_b: Array[Vector3] = [basis_b.x, basis_b.y, basis_b.z]
	var between: Vector3 = centre_b - centre_a
	# The 15 candidate separating axes: 3 face normals of each box and the 9
	# cross products of their edges.
	for index: int in range(3):
		if _separated(axes_a[index], between, axes_a, half_a, axes_b, half_b):
			return false
		if _separated(axes_b[index], between, axes_a, half_a, axes_b, half_b):
			return false
	for first: int in range(3):
		for second: int in range(3):
			var axis: Vector3 = axes_a[first].cross(axes_b[second])
			if axis.length_squared() < 0.000001:
				continue  # Parallel edges: already covered by the face normals.
			if _separated(axis.normalized(), between, axes_a, half_a, axes_b, half_b):
				return false
	return true


## True if, seen along [param axis], the two boxes' shadows do not touch.
static func _separated(axis: Vector3, between: Vector3, axes_a: Array[Vector3], half_a: Vector3,
		axes_b: Array[Vector3], half_b: Vector3) -> bool:
	var reach_a: float = absf(axes_a[0].dot(axis)) * half_a.x + absf(axes_a[1].dot(axis)) * half_a.y + absf(axes_a[2].dot(axis)) * half_a.z
	var reach_b: float = absf(axes_b[0].dot(axis)) * half_b.x + absf(axes_b[1].dot(axis)) * half_b.y + absf(axes_b[2].dot(axis)) * half_b.z
	return absf(between.dot(axis)) > reach_a + reach_b
