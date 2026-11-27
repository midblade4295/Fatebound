class_name PlaneHitboxes
extends RefCounted
## The shape bullets actually have to hit: one box per piece of the airframe,
## in the plane's own space (-Z nose, +X right wing, +Y up).
##
##   engine      the nose, from the spinner back to the firewall
##   hull        cockpit and centre fuselage, including the canopy
##   tail        rear fuselage, the stabiliser, and the tall fin (three boxes)
##   left wing   one slab from the fuselage side to the tip
##   right wing  its mirror
##
## A bullet's path is traced through these boxes in order. Whatever it enters
## first is what it hits; if it keeps going it can hit what lies behind. So a
## shot from dead astern goes tail -> hull -> engine, a head-on shot stops in
## the engine, and one that skims over the nose can still catch the fin.
## A path that threads between the boxes is a miss, however close it came.
##
## The boxes follow the same proportions PlaneVisual uses to build the model,
## so what you see is what can be hit, plus a small PADDING all round: thin
## wings would otherwise be nearly impossible to hit from behind on a phone.

## Metres added to every side of every box.
const PADDING: float = 0.3

var boxes: Array[AABB] = []
## PlaneActor.Part for each entry in `boxes`.
var parts: PackedInt32Array = PackedInt32Array()
## Radius of a sphere around the plane's origin that contains every box. Used
## as a cheap first test before tracing the boxes.
var bounding_radius: float = 0.0


static func build(data: PlaneData) -> PlaneHitboxes:
	var result: PlaneHitboxes = PlaneHitboxes.new()
	var scale: float = PlaneVisual.VISUAL_SCALE
	var length: float = data.fuselage_length * scale
	var radius: float = data.fuselage_radius * scale
	var span: float = data.wing_span * scale
	var chord: float = data.wing_chord * scale
	var wing_y: float = -radius * 0.38
	var wing_z: float = -length * 0.1
	var wing_half_thickness: float = radius * 0.15

	result._add(PlaneActor.Part.ENGINE, Vector3(-radius, -radius, -length * 0.6), Vector3(radius, radius, -length * 0.25))
	result._add(PlaneActor.Part.HULL, Vector3(-radius, -radius, -length * 0.25), Vector3(radius, radius * 1.4, length * 0.14))
	# Tail: tapering rear fuselage, horizontal stabiliser, vertical fin.
	result._add(PlaneActor.Part.TAIL, Vector3(-radius * 0.75, -radius * 0.7, length * 0.14), Vector3(radius * 0.75, radius * 0.8, length * 0.62))
	result._add(PlaneActor.Part.TAIL, Vector3(-span * 0.2, -radius * 0.05, length * 0.52 - chord * 0.31), Vector3(span * 0.2, radius * 0.25, length * 0.52 + chord * 0.31))
	result._add(PlaneActor.Part.TAIL, Vector3(-0.15, radius * 0.1, length * 0.54 - chord * 0.37), Vector3(0.15, radius * 1.75, length * 0.54 + chord * 0.37))
	result._add(PlaneActor.Part.LEFT_WING, Vector3(-span * 0.5, wing_y - wing_half_thickness, wing_z - chord * 0.48),
			Vector3(-radius * 0.9, wing_y + wing_half_thickness, wing_z + chord * 0.48))
	result._add(PlaneActor.Part.RIGHT_WING, Vector3(radius * 0.9, wing_y - wing_half_thickness, wing_z - chord * 0.48),
			Vector3(span * 0.5, wing_y + wing_half_thickness, wing_z + chord * 0.48))
	return result


## Traces a straight path through the boxes. [param origin] and
## [param direction] (normalised) are in plane space. Fills the two output
## arrays with each part the path enters within [param max_distance], nearest
## first, and how far along the path it is entered. A part made of several
## boxes is listed once, at its first box.
func trace(origin: Vector3, direction: Vector3, max_distance: float, out_parts: PackedInt32Array, out_distances: PackedFloat32Array) -> void:
	out_parts.clear()
	out_distances.clear()
	for index: int in range(boxes.size()):
		var entry: float = _ray_box_entry(origin, direction, boxes[index])
		if entry < 0.0 or entry > max_distance:
			continue
		var part: int = parts[index]
		var known: int = out_parts.find(part)
		if known != -1:
			if entry >= out_distances[known]:
				continue
			out_parts.remove_at(known)
			out_distances.remove_at(known)
		# Insertion sort: there are never more than five entries.
		var slot: int = 0
		while slot < out_distances.size() and out_distances[slot] <= entry:
			slot += 1
		out_parts.insert(slot, part)
		out_distances.insert(slot, entry)


func _add(part: int, low: Vector3, high: Vector3) -> void:
	var box: AABB = AABB(low, high - low).grow(PADDING)
	boxes.append(box)
	parts.append(part)
	for corner: int in range(8):
		bounding_radius = maxf(bounding_radius, box.get_endpoint(corner).length())


## Distance along the ray at which it enters the box (0 if it starts inside),
## or -1.0 if it misses. Standard slab test.
static func _ray_box_entry(origin: Vector3, direction: Vector3, box: AABB) -> float:
	var near: float = -INF
	var far: float = INF
	var low: Vector3 = box.position
	var high: Vector3 = box.end
	for axis: int in range(3):
		var start: float = origin[axis]
		var slope: float = direction[axis]
		if absf(slope) < 0.000001:
			# Parallel to this pair of faces: either always between them or never.
			if start < low[axis] or start > high[axis]:
				return -1.0
			continue
		var first: float = (low[axis] - start) / slope
		var second: float = (high[axis] - start) / slope
		if first > second:
			var swap: float = first
			first = second
			second = swap
		near = maxf(near, first)
		far = minf(far, second)
		if near > far:
			return -1.0
	if far < 0.0:
		return -1.0  # The whole box is behind the start point.
	return maxf(near, 0.0)
