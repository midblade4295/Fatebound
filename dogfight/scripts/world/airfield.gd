class_name Airfield
extends Node3D
## One team's home base: a low island with a hard runway, where that team's
## planes start the battle, come back to after being shot down, and can land to
## be repaired.
##
## The node sits at sea level in the middle of the island. Its local -Z is the
## take-off direction, so ArenaBuilder only has to turn the node to point the
## runway at the middle of the arena.
##
## The top of the island is flat, and planes do not find it through the
## physics engine: PlaneActor asks contains() / surface_y() directly. That
## keeps wheels-on-the-ground exact and the same on every peer. The island
## still has a collider on the world layer for bullets, the camera and the
## bots' look-ahead rays; planes are told to ignore it (see ground_body).
## Hangars and the tower are ordinary obstacles.

const ISLAND_HALF_WIDTH: float = 200.0
const ISLAND_HALF_LENGTH: float = 410.0
## Height of the flat top above the sea.
const SURFACE_HEIGHT: float = 14.0
## Planes are on the island while inside this share of its outline; the rim
## beyond it is the sloping edge.
const USABLE_SHARE: float = 0.94
const RUNWAY_LENGTH: float = 620.0
const RUNWAY_WIDTH: float = 52.0
## Where planes line up at the start end of the runway, one entry per seat:
## x = metres right of the centre line, y = metres from the start end. Seat 0
## (the player's) is alone on the centre line at the front. The last two are
## spares for when a seat's own spot is busy.
const PARKING_SPOTS: Array[Vector2] = [
	Vector2(0.0, 120.0), Vector2(-16.0, 88.0), Vector2(16.0, 88.0), Vector2(-16.0, 54.0), Vector2(16.0, 54.0),
	Vector2(-16.0, 20.0), Vector2(16.0, 20.0),
]

const SAND_COLOR: Color = Color("f2dc9b")
const CLIFF_COLOR: Color = Color("c9a878")
const GRASS_COLOR: Color = Color("5fc24a")
const GRASS_DARK_COLOR: Color = Color("4aa83f")
const RUNWAY_COLOR: Color = Color("5b6470")
const APRON_COLOR: Color = Color("6c7480")
const MARKING_COLOR: Color = Color("f4f1e4")
const STEEL_COLOR: Color = Color("8e9aa8")
const OUTLINE_SIDES: int = 20

var team: Teams.Id = Teams.Id.TEAM_BLUE
## The island's collider. Planes add a collision exception for it.
var ground_body: StaticBody3D

var _box: BoxMesh = BoxMesh.new()


## Builds the island. Call once, after the node has been placed and turned.
func build(owner_team: Teams.Id) -> void:
	team = owner_team
	add_to_group(&"airfields")
	ground_body = StaticBody3D.new()
	ground_body.name = "Ground"
	ground_body.collision_layer = PlaneActor.COLLISION_LAYER_WORLD
	ground_body.collision_mask = 0
	add_child(ground_body)
	_add_slab("Sand", SAND_COLOR, 1.12, 1.2, -1.0, 3.0)
	_add_slab("Cliff", CLIFF_COLOR, 1.0, 1.06, 2.0, SURFACE_HEIGHT - 2.5)
	_add_slab("Grass", GRASS_COLOR, 0.985, 1.0, SURFACE_HEIGHT - 2.5, SURFACE_HEIGHT)
	var points: PackedVector3Array = PackedVector3Array()
	for index: int in range(OUTLINE_SIDES):
		var angle: float = TAU * float(index) / float(OUTLINE_SIDES)
		var rim: Vector3 = Vector3(cos(angle) * ISLAND_HALF_WIDTH, 0.0, sin(angle) * ISLAND_HALF_LENGTH)
		points.append(rim * 1.1 + Vector3(0.0, -3.0, 0.0))
		points.append(rim + Vector3(0.0, SURFACE_HEIGHT - 0.4, 0.0))
	var shape: ConvexPolygonShape3D = ConvexPolygonShape3D.new()
	shape.points = points
	var collider: CollisionShape3D = CollisionShape3D.new()
	collider.name = "CollisionShape3D"
	collider.shape = shape
	ground_body.add_child(collider)
	_build_runway()
	_build_buildings()


## Height of the flat top in the world.
func surface_y() -> float:
	return global_position.y + SURFACE_HEIGHT


## True when [param world_position] is above (or below) the flat top.
func contains(world_position: Vector3) -> bool:
	var local: Vector3 = to_local(world_position)
	var across: float = local.x / (ISLAND_HALF_WIDTH * USABLE_SHARE)
	var along: float = local.z / (ISLAND_HALF_LENGTH * USABLE_SHARE)
	return across * across + along * along <= 1.0


## True on the hard runway; everywhere else on the island is rough grass.
func is_on_runway(world_position: Vector3) -> bool:
	var local: Vector3 = to_local(world_position)
	return absf(local.x) <= RUNWAY_WIDTH * 0.5 and absf(local.z) <= RUNWAY_LENGTH * 0.5


## Unit vector along the runway in the take-off direction.
func takeoff_direction() -> Vector3:
	return -global_transform.basis.z.normalized()


## Middle of the runway, on the surface.
func runway_center() -> Vector3:
	return global_position + Vector3(0.0, SURFACE_HEIGHT, 0.0)


## The end planes start their take-off run from.
func runway_start() -> Vector3:
	return runway_center() - takeoff_direction() * RUNWAY_LENGTH * 0.5


## The end they should be off the ground before.
func runway_end() -> Vector3:
	return runway_center() + takeoff_direction() * RUNWAY_LENGTH * 0.5


## How far along the runway [param world_position] is, in metres from the
## start end, and how far to the right of the centre line (x = right, y = along).
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

## One elliptical layer of the island. Radii are shares of the island outline.
func _add_slab(slab_name: String, color: Color, top_share: float, bottom_share: float, bottom_y: float, top_y: float) -> void:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = top_share
	mesh.bottom_radius = bottom_share
	mesh.height = 1.0
	mesh.radial_segments = OUTLINE_SIDES
	mesh.rings = 1
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = slab_name
	instance.mesh = mesh
	instance.material_override = ToonMaterials.toon(color, 0.0, 0.0, 0.0)
	instance.scale = Vector3(ISLAND_HALF_WIDTH, top_y - bottom_y, ISLAND_HALF_LENGTH)
	instance.position.y = (top_y + bottom_y) * 0.5
	ground_body.add_child(instance)


## [param flat] is for paint and tarmac lying on the ground (no rim light).
func _add_box(parent: Node3D, box_name: String, color: Color, size: Vector3, center: Vector3, flat: bool = true) -> void:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = box_name
	instance.mesh = _box
	instance.material_override = ToonMaterials.toon(color, 0.0, 0.0, 0.0) if flat else ToonMaterials.toon(color, 0.0, 0.2)
	instance.scale = size
	instance.position = center
	parent.add_child(instance)


## Paint lies a few centimetres proud of the grass, each layer above the last,
## so nothing flickers.
func _build_runway() -> void:
	var top: float = SURFACE_HEIGHT
	_add_box(self, "Runway", RUNWAY_COLOR, Vector3(RUNWAY_WIDTH, 0.3, RUNWAY_LENGTH), Vector3(0.0, top - 0.1, 0.0))
	var half: float = RUNWAY_LENGTH * 0.5
	for side: float in [-1.0, 1.0]:
		_add_box(self, "Edge", MARKING_COLOR, Vector3(1.0, 0.3, RUNWAY_LENGTH - 8.0), Vector3(side * (RUNWAY_WIDTH * 0.5 - 2.0), top - 0.04, 0.0))
		# Threshold bars at both ends.
		for bar: int in range(6):
			var x: float = (float(bar) - 2.5) * 7.0
			_add_box(self, "Threshold", MARKING_COLOR, Vector3(3.2, 0.3, 26.0), Vector3(x, top - 0.04, side * (half - 22.0)))
	var dashes: int = 11
	for dash: int in range(dashes):
		var z: float = lerpf(-half + 70.0, half - 70.0, float(dash) / float(dashes - 1))
		_add_box(self, "CentreLine", MARKING_COLOR, Vector3(1.4, 0.3, 24.0), Vector3(0.0, top - 0.04, z))
	# Darker grass strips either side so the runway reads from the air.
	for side: float in [-1.0, 1.0]:
		_add_box(self, "Verge", GRASS_DARK_COLOR, Vector3(14.0, 0.3, RUNWAY_LENGTH + 30.0), Vector3(side * (RUNWAY_WIDTH * 0.5 + 7.0), top - 0.14, 0.0))


## Hangars in the team colour and a control tower, well clear of the runway.
func _build_buildings() -> void:
	var top: float = SURFACE_HEIGHT
	var start_z: float = RUNWAY_LENGTH * 0.5
	_add_box(self, "Apron", APRON_COLOR, Vector3(70.0, 0.3, 150.0), Vector3(96.0, top - 0.12, start_z - 150.0))
	for index: int in range(2):
		_add_building("Hangar%d" % index, Teams.color_of(team), Vector3(34.0, 17.0, 44.0), Vector3(118.0, top, start_z - 110.0 - float(index) * 78.0))
	_add_building("Tower", STEEL_COLOR, Vector3(13.0, 30.0, 13.0), Vector3(-104.0, top, start_z - 190.0))
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
