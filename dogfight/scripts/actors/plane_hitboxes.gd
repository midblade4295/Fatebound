class_name PlaneHitboxes
extends RefCounted
## The shape bullets and other aircraft actually hit: one box per piece of the
## model, in the plane's own space (-Z nose, +X right wing, +Y up).
##
## The boxes are read from the model's pieces (PlaneVisual.collect_hit_boxes),
## so every wing panel, wingtip, flap, aileron, elevator, the fin, the rudder,
## the tail, the engine and the fuselage is hit where it is drawn.
##
## A bullet's path is traced through the boxes in order. Whatever it enters
## first is what it hits; if it keeps going it can hit what lies behind. A
## path that threads between the boxes is a miss, however close it came, and
## a part that has been shot off is no longer there to be hit.
##
## Two sets of boxes are kept: `boxes` are padded by BULLET_PADDING so thin
## surfaces are hittable on a phone, `solid_boxes` are the true size and are
## what mid-air collisions use, so two planes only touch when they really do.

## Metres added to every side of every box for bullets.
const BULLET_PADDING: float = 0.3

## Padded boxes, for bullets.
var boxes: Array[AABB] = []
## True-size boxes, for collisions between aircraft.
var solid_boxes: Array[AABB] = []
## PlaneActor.Part for each entry in `boxes` / `solid_boxes`.
var parts: PackedInt32Array = PackedInt32Array()
## Radius of a sphere around the plane's origin that contains every padded
## box. Used as a cheap first test before tracing the boxes.
var bounding_radius: float = 0.0


static func from_visual(visual: PlaneVisual) -> PlaneHitboxes:
	var result: PlaneHitboxes = PlaneHitboxes.new()
	var piece_parts: PackedInt32Array = PackedInt32Array()
	var piece_boxes: Array[AABB] = []
	visual.collect_hit_boxes(piece_parts, piece_boxes)
	for index: int in range(piece_boxes.size()):
		result.add_box(piece_parts[index], piece_boxes[index])
	return result


## Adds a true-size box for [param part].
func add_box(part: int, solid: AABB) -> void:
	var padded: AABB = solid.grow(BULLET_PADDING)
	solid_boxes.append(solid)
	boxes.append(padded)
	parts.append(part)
	for corner: int in range(8):
		bounding_radius = maxf(bounding_radius, padded.get_endpoint(corner).length())


## Traces a straight path through the boxes. [param origin] and
## [param direction] (normalised) are in plane space. Boxes whose part has its
## bit set in [param gone_mask] are skipped. Fills the two output arrays with
## each part the path enters within [param max_distance], nearest first, and
## how far along the path it is entered. A part made of several boxes is
## listed once, at its first box.
func trace(origin: Vector3, direction: Vector3, max_distance: float, gone_mask: int,
		out_parts: PackedInt32Array, out_distances: PackedFloat32Array) -> void:
	out_parts.clear()
	out_distances.clear()
	for index: int in range(boxes.size()):
		var part: int = parts[index]
		if gone_mask & (1 << part) != 0:
			continue
		var entry: float = _ray_box_entry(origin, direction, boxes[index])
		if entry < 0.0 or entry > max_distance:
			continue
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
