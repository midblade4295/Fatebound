class_name ArenaBuilder
extends Node3D
## Builds the battlefield at load time: a stretch of coastal countryside.
## Rolling hills and a patchwork of fields, white chalk cliffs dropping sheer
## into a turquoise sea, woods, boulders and cottages, an airfield for each
## team, and a ring of puffy clouds.
##
## The land itself is a model (tools/blender/coast_world.py makes it and
## everything that goes with it, into assets/models/coast). This node:
##  - puts the terrain in with its shader, and gives it colliders;
##  - makes an Airfield for each team where the model has a marker for one;
##  - builds the sea, a mesh that follows the coast and knows its own depth
##    (see shaders/coast_water.gdshader);
##  - scatters trees, boulders and villages over the gentle ground, in
##    MultiMeshes cut into squares so that what is out of sight is not drawn;
##  - loads the GroundMap, which is how the rest of the game asks how high
##    the land is at any point.
## The scatter comes from one seed, so every peer in an online match builds
## the identical countryside without replicating any of it.
##
## Solid things are StaticBody3Ds on the "world" physics layer: planes crash
## into them, bullets stop on them, the camera's spring arm and the bots'
## look-ahead rays see them. Trees, boulders, cottages, clouds and the water
## surface are visual only; the sea itself is the WorldBoundary collider
## under the "Sea" node in the scene.

const LAND_SCENE: PackedScene = preload("res://assets/models/coast/coast_terrain.glb")
const TREE_SCENE: PackedScene = preload("res://assets/models/coast/coast_tree.glb")
const BOULDER_SCENE: PackedScene = preload("res://assets/models/coast/coast_boulder.glb")
const COTTAGE_SCENE: PackedScene = preload("res://assets/models/coast/coast_cottage.glb")
const GROUND_DATA: String = "res://assets/models/coast/coast_ground.json"
const TERRAIN_SHADER: Shader = preload("res://shaders/coast_terrain.gdshader")
const WATER_SHADER: Shader = preload("res://shaders/coast_water.gdshader")
const FOLIAGE_SHADER: Shader = preload("res://shaders/coast_foliage.gdshader")

const RUNWAY_COLOR: Color = Color("5b6470")
const MARKING_COLOR: Color = Color("f4f1e4")
const ROCK_COLOR: Color = Color("a9a59c")
## The airfields' markers in the model, by Teams.Id.
const TEAM_TAGS: Array[String] = ["Blue", "Red"]
## Toon colours for the cottage, by the name of each surface's material.
const COTTAGE_COLORS: Dictionary[String, Color] = {
	"CottageWall": Color("f1e3c2"), "CottageRoof": Color("d9612f"), "CottageWood": Color("6a4424"),
	"CottageWindow": Color("9fd4ef"), "CottageStone": Color("a39f97"),
}

# --- The sea -----------------------------------------------------------------------
## The sea mesh has a line of vertices at each of these distances out from
## the lip of the cliffs (metres), and reaches SEA_REACH in every direction.
const SEA_OFFSETS: Array[float] = [-30.0, 0.0, 4.0, 10.0, 22.0, 45.0, 90.0, 180.0, 400.0, 900.0, 2500.0]
const SEA_REACH: float = 60000.0
## The sea bed at the foot of the cliffs and how fast it shelves, as in the
## model, and what the water shader takes as "deepest" and "far from shore".
const CLIFF_LEAN: float = 4.0
const SHORE_DEPTH: float = 5.0
const SHELVING: float = 0.035
const DEEPEST: float = 70.0
const SHORE_REACH: float = 200.0

# --- The scatter -------------------------------------------------------------------
## Trees, boulders and cottages are grouped by squares this big (metres),
## and not drawn from further away than their own distance below.
const CHUNK_SIZE: float = 1200.0
const TREE_SIGHT: float = 6500.0
const BOULDER_SIGHT: float = 2600.0
const COTTAGE_SIGHT: float = 7000.0
## Things are scattered out to this far from the middle of the map.
const SCATTER_REACH: float = 4700.0
const TREE_TRIES: int = 26000
const BOULDER_TRIES: int = 6000
const VILLAGES: int = 18
## Nothing stands on ground steeper than this (degrees) ...
const TREE_SLOPE: float = 20.0
const COTTAGE_SLOPE: float = 7.0
## ... or this close to an airfield's runways, or in the way of a take-off
## or an approach: this far either side of the main runway's line, out to
## this far beyond its ends.
const AIRFIELD_CLEARANCE: float = 230.0
const APPROACH_HALF_WIDTH: float = 130.0
const APPROACH_LENGTH: float = 1700.0
## The patchwork of fields, as in coast_world.py and the terrain shader.
const FIELD_SIZE: Vector2 = Vector2(190.0, 150.0)
const FIELD_TURN: float = 0.41887902
const FIELD_SEED: int = 12
const FIELD_CROP_SHARE: float = 0.62

@export var arena_seed: int = 1942
@export var arena_radius: float = 3200.0
@export var cloud_count: int = 80
## Light whose direction tints the sun-facing side of the clouds.
@export var sun: DirectionalLight3D

## Both airfields, indexed by Teams.Id.
var airfields: Array[Airfield] = []
## The height of the land at any point.
var ground_map: GroundMap
## How many of each were scattered (for the tests, and for curiosity).
var tree_count: int = 0
var boulder_count: int = 0
var cottage_count: int = 0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _sphere: SphereMesh


func _ready() -> void:
	_rng.seed = arena_seed
	_sphere = SphereMesh.new()
	_sphere.radius = 0.5
	_sphere.height = 1.0
	_sphere.radial_segments = 12
	_sphere.rings = 6
	ground_map = GroundMap.load_from(GROUND_DATA)
	_build_land()
	_build_sea()
	if ground_map != null:
		_scatter_countryside()
	_build_clouds()


## The airfield for [param team], or null if the arena has not been built.
func airfield_for(team: Teams.Id) -> Airfield:
	return airfields[team] if int(team) < airfields.size() else null


## Height of the land at a point (0 over the sea).
func ground_height(x: float, z: float) -> float:
	return ground_map.height(x, z) if ground_map != null else 0.0


# ---------------------------------------------------------------------------
# The land
# ---------------------------------------------------------------------------

func _build_land() -> void:
	var land: Node3D = LAND_SCENE.instantiate() as Node3D
	land.name = "Land"
	add_child(land)
	var turf: ShaderMaterial = ShaderMaterial.new()
	turf.shader = TERRAIN_SHADER
	var grounds: Dictionary[String, StaticBody3D] = {}
	for child: Node in land.get_children():
		var piece: MeshInstance3D = child as MeshInstance3D
		if piece == null or piece.mesh == null:
			continue
		var piece_name: String = String(piece.name)
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if piece_name == "Terrain" or piece_name.begins_with("AirfieldGround"):
			piece.material_override = turf
			# Solid: the triangles of the mesh itself.
			var body: StaticBody3D = StaticBody3D.new()
			body.name = "%sBody" % piece_name
			body.collision_layer = PlaneActor.COLLISION_LAYER_WORLD
			body.collision_mask = 0
			var collider: CollisionShape3D = CollisionShape3D.new()
			collider.name = "CollisionShape3D"
			collider.shape = piece.mesh.create_trimesh_shape()
			body.add_child(collider)
			add_child(body)
			body.global_transform = piece.global_transform
			grounds[piece_name] = body
		elif piece_name.begins_with("RunwayPaint"):
			piece.material_override = ToonMaterials.toon(MARKING_COLOR, 0.0, 0.0, 0.0)
		elif piece_name.begins_with("Runways"):
			piece.material_override = ToonMaterials.toon(RUNWAY_COLOR, 0.0, 0.0, 0.0)
	for team: int in range(TEAM_TAGS.size()):
		var marker: Node3D = land.get_node_or_null("Airfield_%s" % TEAM_TAGS[team]) as Node3D
		if marker == null:
			push_warning("ArenaBuilder: the land has no marker for the %s airfield" % TEAM_TAGS[team])
			continue
		var airfield: Airfield = Airfield.new()
		airfield.name = "%sAirfield" % Teams.name_of(team as Teams.Id)
		add_child(airfield)
		airfield.global_transform = marker.global_transform.orthonormalized()
		airfield.build(team as Teams.Id, grounds.get("AirfieldGround_%s" % TEAM_TAGS[team]) as StaticBody3D)
		airfields.append(airfield)


# ---------------------------------------------------------------------------
# The sea
# ---------------------------------------------------------------------------

## One flat mesh at sea level, with lines of vertices following the coast so
## that each can carry how deep the water is there and how far it is from
## the foot of the cliffs. It carries on under the land and far out to sea.
func _build_sea() -> void:
	var rows: PackedFloat32Array = PackedFloat32Array([-SEA_REACH])
	if ground_map != null:
		var mapped: PackedFloat32Array = ground_map.row_positions()
		mapped.reverse()  # North (-z) first, so z rises with the row number.
		rows.append_array(mapped)
	rows.append(SEA_REACH)
	var columns: int = SEA_OFFSETS.size() + 2
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()
	for row: int in range(rows.size()):
		var z: float = rows[row]
		var coast: float = ground_map.coast_x(z) if ground_map != null else -SEA_REACH
		for column: int in range(columns):
			var x: float = -SEA_REACH
			if column == columns - 1:
				x = SEA_REACH
			elif column > 0:
				x = coast + SEA_OFFSETS[column - 1]
			# Past the foot of the cliff the bed shelves away steadily.
			var out: float = x - coast - CLIFF_LEAN
			var depth: float = SHORE_DEPTH + SHELVING * out if out >= 0.0 else 0.0
			vertices.append(Vector3(x, 0.0, z))
			normals.append(Vector3.UP)
			colors.append(Color(clampf(depth / DEEPEST, 0.0, 1.0), clampf(out / SHORE_REACH, 0.0, 1.0), 0.0))
	for row: int in range(rows.size() - 1):
		for column: int in range(columns - 1):
			var corner: int = row * columns + column
			indices.append_array(PackedInt32Array([corner, corner + 1, corner + columns, corner + 1, corner + columns + 1, corner + columns]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var water: ArrayMesh = ArrayMesh.new()
	water.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var surface: ShaderMaterial = ShaderMaterial.new()
	surface.shader = WATER_SHADER
	surface.set_shader_parameter(&"deepest", DEEPEST)
	surface.set_shader_parameter(&"shore_reach", SHORE_REACH)
	var ocean: MeshInstance3D = MeshInstance3D.new()
	ocean.name = "Ocean"
	ocean.mesh = water
	ocean.material_override = surface
	ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ocean)


# ---------------------------------------------------------------------------
# Trees, boulders and villages
# ---------------------------------------------------------------------------

func _scatter_countryside() -> void:
	var tree_mesh: Mesh = _mesh_of(TREE_SCENE)
	var boulder_mesh: Mesh = _mesh_of(BOULDER_SCENE)
	var cottage_mesh: Mesh = _mesh_of(COTTAGE_SCENE)
	var woods: FastNoiseLite = FastNoiseLite.new()
	woods.seed = arena_seed
	woods.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	woods.frequency = 1.0 / 900.0

	# Trees: thick in the woods (where the noise is high), thin elsewhere,
	# and along the hedges. Never in a field, on the cliff's edge or anywhere
	# an aeroplane needs to be.
	var trees: Array[Transform3D] = []
	for _try: int in range(TREE_TRIES):
		var place: Vector2 = _random_place()
		if not _is_open_ground(place, TREE_SLOPE, 30.0):
			continue
		var wooded: float = woods.get_noise_2d(place.x, place.y)
		var in_field: bool = _is_in_field(place)
		if in_field or (wooded < 0.12 and _rng.randf() > 0.07):
			continue
		trees.append(_standing(place, _rng.randf_range(1.5, 2.7), 0.4))
	tree_count = trees.size()
	var foliage: ShaderMaterial = ShaderMaterial.new()
	foliage.shader = FOLIAGE_SHADER
	_place_in_chunks("Trees", tree_mesh, trees, foliage, TREE_SIGHT)

	# Boulders: on the rougher ground, and along the top of the cliffs.
	var boulders: Array[Transform3D] = []
	for _try: int in range(BOULDER_TRIES):
		var place: Vector2 = _random_place()
		if not _is_open_ground(place, 32.0, 8.0) or _is_in_field(place):
			continue
		var rough: bool = ground_map.slope(place.x, place.y) > deg_to_rad(9.0)
		var by_the_cliff: bool = ground_map.coast_x(place.y) - place.x < 260.0
		if not rough and not by_the_cliff and _rng.randf() > 0.12:
			continue
		var rock: Transform3D = _standing(place, _rng.randf_range(1.4, 4.2), 0.25)
		boulders.append(rock * Transform3D(Basis.from_scale(Vector3(1.0, _rng.randf_range(0.7, 1.2), _rng.randf_range(0.8, 1.2))), Vector3.ZERO))
	boulder_count = boulders.size()
	if boulder_mesh != null:
		_place_in_chunks("Boulders", boulder_mesh, boulders, ToonMaterials.toon(ROCK_COLOR, 0.0, 0.1), BOULDER_SIGHT)

	# Villages: a handful of cottages each, on level ground among the fields.
	var cottages: Array[Transform3D] = []
	var founded: int = 0
	var attempts: int = 0
	while founded < VILLAGES and attempts < VILLAGES * 40:
		attempts += 1
		var centre: Vector2 = _random_place()
		if not _is_open_ground(centre, COTTAGE_SLOPE, 120.0, 2.2):
			continue
		founded += 1
		var street: float = _rng.randf_range(0.0, TAU)
		for _house: int in range(_rng.randi_range(4, 8)):
			var place: Vector2 = centre + Vector2.from_angle(_rng.randf_range(0.0, TAU)) * _rng.randf_range(12.0, 95.0)
			if not _is_open_ground(place, COTTAGE_SLOPE, 60.0, 1.5):
				continue
			var home: Transform3D = _standing(place, _rng.randf_range(2.0, 2.8), 0.15)
			home.basis = Basis(Vector3.UP, street + float(_rng.randi_range(0, 3)) * PI * 0.5 + _rng.randf_range(-0.15, 0.15)).scaled(home.basis.get_scale())
			cottages.append(home)
	cottage_count = cottages.size()
	if cottage_mesh != null:
		for surface: int in range(cottage_mesh.get_surface_count()):
			var named: Material = cottage_mesh.surface_get_material(surface)
			var paint: Color = COTTAGE_COLORS.get(named.resource_name if named != null else "", Color("f1e3c2"))
			cottage_mesh.surface_set_material(surface, ToonMaterials.toon(paint, 0.0, 0.1))
		_place_in_chunks("Cottages", cottage_mesh, cottages, null, COTTAGE_SIGHT)


func _random_place() -> Vector2:
	return Vector2(_rng.randf_range(-SCATTER_REACH, SCATTER_REACH), _rng.randf_range(-SCATTER_REACH, SCATTER_REACH))


## Ground something could stand on: land, no steeper than [param steepest]
## degrees, at least [param from_cliff] metres back from the cliffs, and
## clear of the airfields ([param airfield_margin] widens that for things
## that should keep well away).
func _is_open_ground(place: Vector2, steepest: float, from_cliff: float, airfield_margin: float = 1.0) -> bool:
	if ground_map.coast_x(place.y) - place.x < from_cliff or not ground_map.is_land(place.x, place.y):
		return false
	if ground_map.slope(place.x, place.y) > deg_to_rad(steepest):
		return false
	var where: Vector3 = Vector3(place.x, 0.0, place.y)
	for airfield: Airfield in airfields:
		if airfield.distance_to_runways(where) < AIRFIELD_CLEARANCE * airfield_margin:
			return false
		# The way in and the way out along the main runway.
		var along: Vector2 = airfield.runway_coordinates(where)
		var beyond: float = maxf(-along.y, along.y - Airfield.RUNWAY_LENGTH)
		if absf(along.x) < APPROACH_HALF_WIDTH * airfield_margin and beyond < APPROACH_LENGTH:
			return false
	return true


## True in a field that is under crop (wheat, plough or pasture) and clear
## of its hedge: the same grid and the same hash as the terrain shader draws.
func _is_in_field(place: Vector2) -> bool:
	var across: Vector2 = Vector2(place.x * cos(FIELD_TURN) - place.y * sin(FIELD_TURN), -place.x * sin(FIELD_TURN) - place.y * cos(FIELD_TURN)) / FIELD_SIZE
	var cell: Vector2i = Vector2i(floori(across.x), floori(across.y))
	var within: Vector2 = across - Vector2(cell)
	var to_hedge: float = minf(minf(within.x, 1.0 - within.x) * FIELD_SIZE.x, minf(within.y, 1.0 - within.y) * FIELD_SIZE.y)
	return to_hedge > 5.0 and field_hash(cell.x, cell.y, FIELD_SEED) < FIELD_CROP_SHARE


## The same repeatable number per grid cell that coast_world.py's _lattice()
## and the terrain shader's lattice() give.
static func field_hash(cell_x: int, cell_y: int, hash_seed: int) -> float:
	var n: int = (cell_x * 374761393 + cell_y * 668265263 + hash_seed * 1442695041) & 0xFFFFFFFF
	n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
	return float((n ^ (n >> 16)) & 0xFFFFFFFF) / 4294967295.0


## Something standing on the ground at [param place], turned any way round,
## [param size] times its modelled size, sunk [param sunk] of a metre in.
func _standing(place: Vector2, size: float, sunk: float) -> Transform3D:
	var turned: Basis = Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * size)
	return Transform3D(turned, Vector3(place.x, ground_map.height(place.x, place.y) - sunk, place.y))


## Draws a great many copies of one mesh, a MultiMesh for each square of the
## map that has any, so that squares out of view (or too far off) cost nothing.
func _place_in_chunks(group_name: String, mesh: Mesh, places: Array[Transform3D], material: Material, sight: float) -> void:
	if mesh == null or places.is_empty():
		return
	var squares: Dictionary[Vector2i, Array] = {}
	for place: Transform3D in places:
		var square: Vector2i = Vector2i(floori(place.origin.x / CHUNK_SIZE), floori(place.origin.z / CHUNK_SIZE))
		if not squares.has(square):
			squares[square] = []
		squares[square].append(place)
	var group: Node3D = Node3D.new()
	group.name = group_name
	add_child(group)
	for square: Vector2i in squares:
		var members: Array = squares[square]
		# Each square's instances are placed relative to its own middle, so
		# its bounds (and the distance it is last drawn at) are its own.
		var middle: Vector3 = Vector3((float(square.x) + 0.5) * CHUNK_SIZE, 0.0, (float(square.y) + 0.5) * CHUNK_SIZE)
		var multimesh: MultiMesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = mesh
		multimesh.instance_count = members.size()
		for index: int in range(members.size()):
			var place: Transform3D = members[index]
			place.origin -= middle
			multimesh.set_instance_transform(index, place)
		var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
		instance.name = "%s_%d_%d" % [group_name, square.x, square.y]
		instance.multimesh = multimesh
		instance.position = middle
		if material != null:
			instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.visibility_range_end = sight
		instance.visibility_range_end_margin = 300.0
		instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		group.add_child(instance)


## The first mesh in a model file.
func _mesh_of(scene: PackedScene) -> Mesh:
	var model: Node = scene.instantiate()
	var found: Mesh = null
	var pending: Array[Node] = [model]
	while not pending.is_empty() and found == null:
		var node: Node = pending.pop_back()
		var piece: MeshInstance3D = node as MeshInstance3D
		if piece != null and piece.mesh != null:
			found = piece.mesh
		pending.append_array(node.get_children())
	model.free()
	return found


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
