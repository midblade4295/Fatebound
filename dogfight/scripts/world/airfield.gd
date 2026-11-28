class_name Airfield
extends Node3D
## One team's home base: three hard runways laid out as a triangle on a level
## stretch of the countryside, where that team's planes start the battle and
## where they come back to, to be repaired and refuelled or to cash out.
##
## The ground, the runways and their paint are part of the terrain model
## (tools/blender/coast_world.py makes them, to real scale: a wartime RAF
## fighter station). This node is what the game knows about them. It sits at
## the middle of the main runway, on its surface, and its local -Z is the
## take-off direction; ArenaBuilder puts it on the marker the model carries.
## The numbers below have to match the ones in that script.
##
## Planes do not find the airfield through the physics engine: PlaneActor
## asks contains() / surface_y() directly. That keeps wheels-on-the-ground
## exact and the same on every peer. The level ground still has a collider
## on the world layer for bullets, the camera and the bots' look-ahead rays;
## planes are told to ignore it (see ground_body). Everywhere else the land
## is an ordinary obstacle, and so are the hangars and the tower.

const YARD: float = 0.9144
## Main runway 1,600 yards, the two others 1,100, all 50 yards wide.
const RUNWAY_LENGTH: float = 1600.0 * YARD
const RUNWAY_WIDTH: float = 50.0 * YARD
const SECONDARY_LENGTH: float = 1100.0 * YARD
## The middle of each of the other two is this far to the left of the main
## runway's centre line and this far up or down it from its middle, and they
## cross it at this angle.
const SECONDARY_SIDE: float = 260.0
const SECONDARY_ALONG: float = 250.0
const SECONDARY_ANGLE: float = PI / 3.0
## The ground is dead level, and planes are "on the airfield", within this
## many metres of any runway's centre line.
const LEVEL_REACH: float = 130.0
## The grass off each end of the main runway is airfield too, this far out:
## for landing short, or running long.
const OVERRUN: float = 400.0
## Where planes line up at the start end of the runway, one entry per seat:
## x = metres right of the centre line, y = metres from the start end. Seat 0
## (the player's) is alone on the centre line at the front. The last two are
## spares for when a seat's own spot is busy.
const PARKING_SPOTS: Array[Vector2] = [
	Vector2(0.0, 120.0), Vector2(-16.0, 88.0), Vector2(16.0, 88.0), Vector2(-16.0, 54.0), Vector2(16.0, 54.0),
	Vector2(-16.0, 20.0), Vector2(16.0, 20.0),
]

const APRON_COLOR: Color = Color("6c7480")
const STEEL_COLOR: Color = Color("8e9aa8")

var team: Teams.Id = Teams.Id.TEAM_BLUE
## The collider of the level ground. Planes add a collision exception for it.
var ground_body: StaticBody3D

## Each runway's centre line as [start, end] in this node's own x and z.
var _runways: Array[PackedVector2Array] = []
## The same, with the main runway's overruns: the lines the level ground is
## measured from.
var _ground_lines: Array[PackedVector2Array] = []
var _box: BoxMesh = BoxMesh.new()


## Sets the airfield up. Call once, after the node has been placed and
## turned. [param ground] is the collider of its level ground.
func build(owner_team: Teams.Id, ground: StaticBody3D) -> void:
	team = owner_team
	ground_body = ground
	add_to_group(&"airfields")
	var half: float = RUNWAY_LENGTH * 0.5
	_runways = [PackedVector2Array([Vector2(0.0, half), Vector2(0.0, -half)])]
	for side: float in [1.0, -1.0]:
		var middle: Vector2 = Vector2(-SECONDARY_SIDE, -SECONDARY_ALONG * side)
		var along: Vector2 = Vector2(sin(SECONDARY_ANGLE * side), -cos(SECONDARY_ANGLE * side)) * SECONDARY_LENGTH * 0.5
		_runways.append(PackedVector2Array([middle - along, middle + along]))
	_ground_lines = _runways.duplicate()
	_ground_lines.append(PackedVector2Array([Vector2(0.0, half + OVERRUN), Vector2(0.0, -half - OVERRUN)]))
	_build_buildings()


## Height of the runways and the level ground round them, in the world.
func surface_y() -> float:
	return global_position.y


## How far [param world_position] is, over the ground, from the nearest
## runway's centre line.
func distance_to_runways(world_position: Vector3) -> float:
	return _distance_to(_runways, world_position)


## True when [param world_position] is above (or below) the level ground:
## round the runways, and off the ends of the main one.
func contains(world_position: Vector3) -> bool:
	return _distance_to(_ground_lines, world_position) <= LEVEL_REACH


## True on a hard runway; everywhere else on the airfield is rough grass.
func is_on_runway(world_position: Vector3) -> bool:
	return distance_to_runways(world_position) <= RUNWAY_WIDTH * 0.5


func _distance_to(lines: Array[PackedVector2Array], world_position: Vector3) -> float:
	var local: Vector3 = to_local(world_position)
	var place: Vector2 = Vector2(local.x, local.z)
	var nearest: float = INF
	for line: PackedVector2Array in lines:
		nearest = minf(nearest, place.distance_to(Geometry2D.get_closest_point_to_segment(place, line[0], line[1])))
	return nearest


## Unit vector along the main runway in the take-off direction.
func takeoff_direction() -> Vector3:
	return -global_transform.basis.z.normalized()


## Middle of the main runway, on the surface.
func runway_center() -> Vector3:
	return global_position


## The end planes start their take-off run from.
func runway_start() -> Vector3:
	return runway_center() - takeoff_direction() * RUNWAY_LENGTH * 0.5


## The end they should be off the ground before.
func runway_end() -> Vector3:
	return runway_center() + takeoff_direction() * RUNWAY_LENGTH * 0.5


## How far along the main runway [param world_position] is, in metres from
## the start end, and how far to the right of the centre line (x = right,
## y = along).
func runway_coordinates(world_position: Vector3) -> Vector2:
	var local: Vector3 = to_local(world_position)
	return Vector2(local.x, RUNWAY_LENGTH * 0.5 - local.z)


func parking_spot_count() -> int:
	return PARKING_SPOTS.size()


## Where a plane waits before take-off: on the surface (y is the ground, the
## plane adds its own wheel height), nose down the runway.
func parking_transform(spot: int) -> Transform3D:
	var place: Vector2 = PARKING_SPOTS[posmod(spot, PARKING_SPOTS.size())]
	var direction: Vector3 = takeoff_direction()
	var right: Vector3 = direction.cross(Vector3.UP).normalized()
	var origin: Vector3 = runway_start() + direction * place.y + right * place.x
	return Transform3D(Basis.looking_at(direction, Vector3.UP), origin)


# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------

## [param flat] is for paint and tarmac lying on the ground (no rim light).
func _add_box(parent: Node3D, box_name: String, color: Color, size: Vector3, center: Vector3, flat: bool = true) -> void:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = box_name
	instance.mesh = _box
	instance.material_override = ToonMaterials.toon(color, 0.0, 0.0, 0.0) if flat else ToonMaterials.toon(color, 0.0, 0.2)
	instance.scale = size
	instance.position = center
	parent.add_child(instance)


## Hangars in the team colour and a control tower by the start end of the
## main runway, well clear of it, with an apron in front of the hangars.
func _build_buildings() -> void:
	var start_z: float = RUNWAY_LENGTH * 0.5
	_add_box(self, "Apron", APRON_COLOR, Vector3(70.0, 0.3, 150.0), Vector3(96.0, -0.1, start_z - 150.0))
	for index: int in range(2):
		_add_building("Hangar%d" % index, Teams.color_of(team), Vector3(34.0, 17.0, 44.0), Vector3(118.0, 0.0, start_z - 110.0 - float(index) * 78.0))
	_add_building("Tower", STEEL_COLOR, Vector3(13.0, 30.0, 13.0), Vector3(-104.0, 0.0, start_z - 190.0))
	var tower: Node3D = get_node("Tower") as Node3D
	_add_box(tower, "Cab", Teams.color_of(team), Vector3(18.0, 7.0, 18.0), Vector3(0.0, 33.0, 0.0), false)


func _add_building(building_name: String, color: Color, size: Vector3, base: Vector3) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = building_name
	body.position = base
	body.collision_layer = PlaneActor.COLLISION_LAYER_WORLD
	body.collision_mask = 0
	add_child(body)
	_add_box(body, "Walls", color, size, Vector3(0.0, size.y * 0.5, 0.0), false)
	_add_box(body, "Roof", color.darkened(0.3), Vector3(size.x + 2.0, 1.6, size.z + 2.0), Vector3(0.0, size.y + 0.8, 0.0), false)
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	var collider: CollisionShape3D = CollisionShape3D.new()
	collider.name = "CollisionShape3D"
	collider.shape = shape
	collider.position.y = size.y * 0.5
	body.add_child(collider)
