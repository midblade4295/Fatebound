class_name GroundMap
extends RefCounted
## The height of the land, as numbers: what the game asks when it needs to
## know how far a plane is above the ground, how steep a slope is, or where
## the coast runs. Written by tools/blender/coast_world.py alongside the
## terrain mesh (coast_ground.json), so the two always agree.
##
## The terrain is a grid whose rows run west to east. Every row is stretched
## to fit between the west edge of the map and that row's own point on the
## coast, where the land stops at the lip of the cliff. So a height is found
## by: which two rows the point lies between; how far along each it is, as a
## share of the way from the edge to the coast; and the heights of the grid
## points either side. East of the cliff is the sea, and the sea is level 0.
##
## Blender's +Y is the game's -Z: rows are indexed by -z.

## Row positions (-z) and, for columns, where they fall before stretching.
var _axis: PackedFloat32Array = PackedFloat32Array()
## The x of the cliff's lip on each row.
var _coast: PackedFloat32Array = PackedFloat32Array()
## Land heights: one row after another, _columns to a row.
var _heights: PackedFloat32Array = PackedFloat32Array()
var _columns: int = 0
var _half: float = 0.0
var _cliff_lean: float = 4.0
## The level of each airfield, by team name ("Blue", "Red").
var airfield_levels: Dictionary = {}


static func load_from(path: String) -> GroundMap:
	var source: JSON = load(path) as JSON
	if source == null or not source.data is Dictionary:
		push_warning("GroundMap: could not read %s" % path)
		return null
	var data: Dictionary = source.data
	var map: GroundMap = GroundMap.new()
	map._axis = PackedFloat32Array(_list(data, "axis"))
	map._coast = PackedFloat32Array(_list(data, "coast"))
	map._heights = PackedFloat32Array(_list(data, "heights"))
	map._columns = roundi(_number(data, "lip", 0.0)) + 1
	map._cliff_lean = _number(data, "cliff_lean", 4.0)
	if map._axis.size() < 2 or map._coast.size() != map._axis.size() or map._heights.size() != map._axis.size() * map._columns:
		push_warning("GroundMap: %s does not hold a complete map" % path)
		return null
	map._half = map._axis[map._axis.size() - 1]
	var levels: Variant = data.get("airfields", {})
	if levels is Dictionary:
		map.airfield_levels = levels
	return map


## Height of the ground at a point, metres above the sea. 0 over the sea
## (and beyond the edge of the map, which is sea too).
func height(x: float, z: float) -> float:
	var along: float = -z
	var last: int = _axis.size() - 1
	if along <= _axis[0] or along >= _axis[last]:
		return 0.0
	var row: int = clampi(_axis.bsearch(along) - 1, 0, last - 1)
	var share: float = (along - _axis[row]) / (_axis[row + 1] - _axis[row])
	return lerpf(_row_height(row, x), _row_height(row + 1, x), share)


## True where there is land under a point (not sea, not the cliff face).
func is_land(x: float, z: float) -> bool:
	return x < coast_x(z) and absf(x) < _half and absf(z) < _half


## Where the lip of the cliff is, east-west, at a given z.
func coast_x(z: float) -> float:
	var along: float = clampf(-z, _axis[0], _axis[_axis.size() - 1])
	var row: int = clampi(_axis.bsearch(along) - 1, 0, _axis.size() - 2)
	var share: float = (along - _axis[row]) / (_axis[row + 1] - _axis[row])
	return lerpf(_coast[row], _coast[row + 1], share)


## How steep the ground is at a point, in radians from level.
func slope(x: float, z: float, reach: float = 12.0) -> float:
	var east_west: float = height(x + reach, z) - height(x - reach, z)
	var north_south: float = height(x, z + reach) - height(x, z - reach)
	return atan(Vector2(east_west, north_south).length() / (2.0 * reach))


## How far the finely meshed land reaches from the middle of the map, and how
## far the map goes in all.
func extent() -> float:
	return _half


## The rows of the grid, as z positions from north to south: for building
## things that have to follow the coast row by row.
func row_positions() -> PackedFloat32Array:
	var rows: PackedFloat32Array = PackedFloat32Array()
	for value: float in _axis:
		rows.append(-value)
	return rows


## Height on one row of the grid at [param x].
func _row_height(row: int, x: float) -> float:
	var lip: float = _coast[row]
	var edge: int = _columns - 1
	if x >= lip + _cliff_lean or x <= -_half:
		return 0.0
	var start: int = row * _columns
	if x >= lip:
		# On the cliff face itself.
		return lerpf(_heights[start + edge], 0.0, (x - lip) / _cliff_lean)
	# Undo the stretch: where this x falls on the unstretched axis.
	var place: float = _axis[0] + (x + _half) / (lip + _half) * (_axis[edge] - _axis[0])
	var column: int = clampi(_axis.bsearch(place) - 1, 0, edge - 1)
	var share: float = clampf((place - _axis[column]) / (_axis[column + 1] - _axis[column]), 0.0, 1.0)
	return lerpf(_heights[start + column], _heights[start + column + 1], share)


static func _list(data: Dictionary, key: String) -> Array:
	var value: Variant = data.get(key)
	if value is Array:
		var list: Array = value
		return list
	return []


static func _number(data: Dictionary, key: String, fallback: float) -> float:
	var value: Variant = data.get(key)
	if value is float:
		var number: float = value
		return number
	if value is int:
		var whole: int = value
		return float(whole)
	return fallback
