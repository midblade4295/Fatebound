class_name ArenaBuilder
extends Node3D
## Builds the whole battlefield out of primitive meshes at load time: ocean,
## chunky cliff islands, an island airfield for each team and a ring of puffy
## clouds. Everything is generated from one seed, so every peer in an
## online match builds the identical arena without replicating any of it.
##
## Solid things get a StaticBody3D on the "world" physics layer (planes crash
## into them, bullets stop on them, the camera's spring arm and the bots' look-
## ahead rays see them). Clouds and the water surface are visual only; the sea
## itself is the WorldBoundary collider under the "Sea" node in the scene.

const SAND_COLOR: Color = Color("f2dc9b")
const CLIFF_COLOR: Color = Color("c9a878")
const CLIFF_DARK_COLOR: Color = Color("a8875c")
const GRASS_COLOR: Color = Color("5fc24a")
const GRASS_DARK_COLOR: Color = Color("3f9d3a")

@export var arena_seed: int = 1942
@export var arena_radius: float = 3200.0
@export var island_count: int = 9
@export var cloud_count: int = 80
## Light whose direction tints the sun-facing side of the clouds.
@export var sun: DirectionalLight3D
## Where each team's airfield is built. Each runway points at the arena centre.
@export var blue_base_position: Vector3 = Vector3(0.0, 0.0, 2300.0)
@export var red_base_position: Vector3 = Vector3(0.0, 0.0, -2300.0)
## Islands are kept this far (metres) from the line the runways lie on, so
## nothing stands in the way of a take-off or an approach.
@export var runway_corridor: float = 640.0

## Both airfields, indexed by Teams.Id.
var airfields: Array[Airfield] = []

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _cylinder: CylinderMesh
var _box: BoxMesh
var _sphere: SphereMesh


func _ready() -> void:
	_rng.seed = arena_seed
	_cylinder = CylinderMesh.new()
	_cylinder.top_radius = 0.5
	_cylinder.bottom_radius = 0.5
	_cylinder.height = 1.0
	_cylinder.radial_segments = 12  # Low segment count = faceted, chunky cliffs.
	_cylinder.rings = 1
	_box = BoxMesh.new()
	_sphere = SphereMesh.new()
	_sphere.radius = 0.5
	_sphere.height = 1.0
	_sphere.radial_segments = 12
	_sphere.rings = 6
	_build_ocean()
	_build_islands()
	airfields = [
		_build_airfield(blue_base_position, Teams.Id.TEAM_BLUE),
		_build_airfield(red_base_position, Teams.Id.TEAM_RED),
	]
	_build_clouds()


func _build_ocean() -> void:
	var water: PlaneMesh = PlaneMesh.new()
	water.size = Vector2(36000.0, 36000.0)
	var ocean: MeshInstance3D = MeshInstance3D.new()
	ocean.name = "Ocean"
	ocean.mesh = water
	ocean.material_override = ToonMaterials.ocean()
	ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ocean)


func _build_islands() -> void:
	for index: int in range(island_count):
		# Spread islands around a ring, leaving the centre open for the furball.
		var angle: float = TAU * (float(index) + 0.5) / float(island_count) + _rng.randf_range(-0.2, 0.2)
		var distance: float = _rng.randf_range(0.3, 0.72) * arena_radius
		var center: Vector3 = Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
		var radius: float = _rng.randf_range(150.0, 320.0)
		# Slide the island sideways out of the runway corridor if it landed in it.
		var clear_of_runways: float = runway_corridor + radius * 1.32
		if absf(center.x) < clear_of_runways:
			center.x = clear_of_runways * (1.0 if center.x >= 0.0 else -1.0)
		_build_island(center, radius, _rng.randf_range(80.0, 280.0), "Island%d" % index)


## A stack of tapered cylinders: sand skirt, rock cliff, grass cap, plus a rock
## spire or two. One cylinder collider covers the lot.
func _build_island(center: Vector3, radius: float, height: float, island_name: String) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = island_name
	body.position = center
	body.rotation.y = _rng.randf_range(0.0, TAU)
	body.collision_layer = PlaneActor.COLLISION_LAYER_WORLD
	body.collision_mask = 0
	add_child(body)
	var cap_height: float = height * 0.16
	_add_frustum(body, "Sand", SAND_COLOR, radius * 1.22, radius * 1.32, 5.0, 1.0)
	_add_frustum(body, "Cliff", CLIFF_COLOR, radius * 0.86, radius, height, height * 0.5)
	_add_frustum(body, "CliffBand", CLIFF_DARK_COLOR, radius * 0.99, radius * 1.05, height * 0.3, height * 0.15)
	_add_frustum(body, "Grass", GRASS_COLOR, radius * 0.7, radius * 0.9, cap_height, height + cap_height * 0.5)
	_add_frustum(body, "GrassTop", GRASS_DARK_COLOR, radius * 0.38, radius * 0.6, cap_height * 0.7, height + cap_height * 1.3)
	var shape: CylinderShape3D = CylinderShape3D.new()
	shape.radius = radius
	shape.height = height + cap_height * 1.7
	var collider: CollisionShape3D = CollisionShape3D.new()
	collider.name = "CollisionShape3D"
	collider.shape = shape
	collider.position.y = shape.height * 0.5
	body.add_child(collider)
	return body


func _add_frustum(parent: Node3D, part_name: String, color: Color, top_radius: float, bottom_radius: float, height: float, center_y: float) -> void:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 1
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = part_name
	instance.mesh = mesh
	instance.material_override = ToonMaterials.toon(color, 0.0, 0.1)
	instance.position.y = center_y
	parent.add_child(instance)


## The airfield for [param team], or null if the arena has not been built.
func airfield_for(team: Teams.Id) -> Airfield:
	return airfields[team] if int(team) < airfields.size() else null


## A team's home: a low island with a runway aimed at the middle of the arena.
func _build_airfield(center: Vector3, team: Teams.Id) -> Airfield:
	var airfield: Airfield = Airfield.new()
	airfield.name = "%sAirfield" % Teams.name_of(team)
	add_child(airfield)
	airfield.position = center
	# Local -Z is the take-off direction: turn it toward the centre.
	var to_center: Vector3 = -center
	to_center.y = 0.0
	if to_center.length_squared() > 1.0:
		airfield.rotation.y = atan2(-to_center.x, -to_center.z)
	airfield.build(team)
	return airfield


## All cloud puffs live in one MultiMesh: a few hundred spheres, one draw call.
func _build_clouds() -> void:
	var transforms: Array[Transform3D] = []
	for _cloud: int in range(cloud_count):
		var angle: float = _rng.randf_range(0.0, TAU)
		var distance: float = sqrt(_rng.randf()) * arena_radius * 1.9
		var center: Vector3 = Vector3(cos(angle) * distance, _rng.randf_range(700.0, 2100.0), sin(angle) * distance)
		var cloud_size: float = _rng.randf_range(110.0, 280.0)
		var puffs: int = _rng.randi_range(4, 7)
		for puff: int in range(puffs):
			# Puffs are strung out sideways and squashed so clouds read as flat-bottomed.
			var offset: Vector3 = Vector3(
					(float(puff) - float(puffs - 1) * 0.5) * cloud_size * 0.42 + _rng.randf_range(-8.0, 8.0),
					_rng.randf_range(-0.08, 0.16) * cloud_size,
					_rng.randf_range(-0.25, 0.25) * cloud_size)
			var edge_falloff: float = 1.0 - absf(float(puff) - float(puffs - 1) * 0.5) / float(puffs) * 0.9
			var puff_size: float = cloud_size * _rng.randf_range(0.55, 0.8) * edge_falloff
			transforms.append(Transform3D(Basis.from_scale(Vector3(puff_size, puff_size * 0.62, puff_size * 0.85)), center + offset))
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _sphere
	multimesh.instance_count = transforms.size()
	for index: int in range(transforms.size()):
		multimesh.set_instance_transform(index, transforms[index])
	var sun_direction: Vector3 = Vector3(0.4, 0.8, 0.3)
	if sun != null:
		sun_direction = sun.global_transform.basis.z  # Lights shine along -Z.
	var clouds: MultiMeshInstance3D = MultiMeshInstance3D.new()
	clouds.name = "Clouds"
	clouds.multimesh = multimesh
	clouds.material_override = ToonMaterials.cloud(sun_direction)
	clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(clouds)
