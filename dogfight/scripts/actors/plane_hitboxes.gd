class_name PlaneHitboxes
extends RefCounted
## The shape bullets actually have to hit: one box per piece of the airframe,
## in the plane's own space (-Z nose, +X right wing, +Y up).
##
##   engine      the nose, from the spinner back to the firewall
##   hull        cockpit and centre fuselage, including the canopy
##   tail        rear fuselage, the stabiliser with its elevators, and the
##               fixed front part of the fin (three boxes)
##   rudder      the hinged rear part of the fin
##   wings       the front of each wing plus its outer rear, where the
##               aileron is (two boxes a side)
##   flaps       the inner rear of each wing
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
## Where the flap sits on the wing, shared with PlaneVisual so the surface you
## see is the surface that gets hit: hinge line as a fraction of chord behind
## the wing's centre, and outer end as a fraction of the full span.
const FLAP_HINGE_CHORD: float = 0.2
const FLAP_OUTER_SPAN: float = 0.27

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
	# Tail: tapering rear fuselage, horizontal stabiliser, and the fin, whose
	# rear 55% is the rudder.
	result._add(PlaneActor.Part.TAIL, Vector3(-radius * 0.75, -radius * 0.7, length * 0.14), Vector3(radius * 0.75, radius * 0.8, length * 0.62))
	result._add(PlaneActor.Part.TAIL, Vector3(-span * 0.2, -radius * 0.05, length * 0.52 - chord * 0.31), Vector3(span * 0.2, radius * 0.25, length * 0.52 + chord * 0.31))
	var fin_front: float = length * 0.54 - chord * 0.37
	var fin_back: float = length * 0.54 + chord * 0.37
	var rudder_hinge: float = lerpf(fin_front, fin_back, 0.45)
	result._add(PlaneActor.Part.TAIL, Vector3(-0.15, radius * 0.1, fin_front), Vector3(0.15, radius * 1.75, rudder_hinge))
	result._add(PlaneActor.Part.RUDDER, Vector3(-0.15, radius * 0.1, rudder_hinge), Vector3(0.15, radius * 1.75, fin_back))
	# Wings: the trailing edge is split where PlaneVisual puts the surfaces,
	# flap inboard and aileron (part of the wing) outboard.
	var wing_front: float = wing_z - chord * 0.48
	var wing_back: float = wing_z + chord * 0.48
	var surface_hinge: float = wing_z + chord * FLAP_HINGE_CHORD
	var flap_outer: float = span * FLAP_OUTER_SPAN
	for side: float in [-1.0, 1.0]:
		var wing: int = PlaneActor.Part.LEFT_WING if side < 0.0 else PlaneActor.Part.RIGHT_WING
		var flap: int = PlaneActor.Part.LEFT_FLAP if side < 0.0 else PlaneActor.Part.RIGHT_FLAP
		result._add_side(wing, side, radius * 0.9, span * 0.5, wing_y - wing_half_thickness, wing_y + wing_half_thickness, wing_front, surface_hinge)
		result._add_side(wing, side, flap_outer, span * 0.5, wing_y - wing_half_thickness, wing_y + wing_half_thickness, surface_hinge, wing_back)
		result._add_side(flap, side, radius * 0.9, flap_outer, wing_y - wing_half_thickness, wing_y + wing_half_thickness, surface_hinge, wing_back)
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
		# Insertion sort: there are only ever a handful of entries.
		var slot: int = 0
		while slot < out_distances.size() and out_distances[slot] <= entry:
			slot += 1
		out_parts.insert(slot, part)
		out_distances.insert(slot, entry)


## Adds a box on the left (side -1) or right (side +1), given how far out
## from the centre line it starts and ends.
func _add_side(part: int, side: float, inner: float, outer: float, bottom: float, top: float, front: float, back: float) -> void:
	var near_x: float = minf(side * inner, side * outer)
	var far_x: float = maxf(side * inner, side * outer)
	_add(part, Vector3(near_x, bottom, front), Vector3(far_x, top, back))


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
