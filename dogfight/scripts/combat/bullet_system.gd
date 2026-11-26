class_name BulletSystem
extends Node3D
## Every bullet in the match, simulated as plain data and drawn with a single
## MultiMesh. No bullet nodes, no Area3Ds: ten planes firing at once is one
## draw call and at most a few hundred short ray casts per physics tick.
##
## Each tick a bullet sweeps a ray from where it was to where it will be, so
## fast bullets can never tunnel through a plane. Rays hit the "world" layer
## (cliffs block shots) and the "planes" layer. Friendly fire is prevented by
## excluding the shooter's whole team from the ray, so bullets pass through
## wingmen instead of being wasted on them.
##
## Networking: run this on the server only. Clients can render their own
## cosmetic tracers from PlaneActor.shot_fired.

signal bullet_hit(victim: PlaneActor, shooter: PlaneActor, world_position: Vector3)

const MAX_BULLETS: int = 512
const TRACER_LENGTH: float = 9.0
const TRACER_WIDTH: float = 0.32
const SPARK_POOL_SIZE: int = 12
const SPARK_TIME: float = 0.16
const TRACER_COLORS: Array[Color] = [Color(0.75, 0.92, 1.0), Color(1.0, 0.84, 0.35)]

var _positions: PackedVector3Array = PackedVector3Array()
var _velocities: PackedVector3Array = PackedVector3Array()
var _lifetimes: PackedFloat32Array = PackedFloat32Array()
var _damages: PackedFloat32Array = PackedFloat32Array()
var _burn_dps: PackedFloat32Array = PackedFloat32Array()
var _burn_durations: PackedFloat32Array = PackedFloat32Array()
var _shooters: Array[PlaneActor] = []
var _teams: PackedInt32Array = PackedInt32Array()
var _count: int = 0

## Collision RIDs per team, used as the ray "exclude" list.
var _blue_rids: Array[RID] = []
var _red_rids: Array[RID] = []
var _multimesh: MultiMesh
var _query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
var _sparks: Array[MeshInstance3D] = []
var _spark_timers: PackedFloat32Array = PackedFloat32Array()
var _next_spark: int = 0


func _ready() -> void:
	_positions.resize(MAX_BULLETS)
	_velocities.resize(MAX_BULLETS)
	_lifetimes.resize(MAX_BULLETS)
	_damages.resize(MAX_BULLETS)
	_burn_dps.resize(MAX_BULLETS)
	_burn_durations.resize(MAX_BULLETS)
	_teams.resize(MAX_BULLETS)
	_shooters.resize(MAX_BULLETS)
	_query.collision_mask = PlaneActor.COLLISION_LAYER_WORLD | PlaneActor.COLLISION_LAYER_PLANES
	_build_tracer_multimesh()
	_build_spark_pool()


## Registers a plane so its team-mates' bullets ignore it.
func register_plane(plane: PlaneActor) -> void:
	var rids: Array[RID] = _rids_for(plane.team)
	if not rids.has(plane.get_rid()):
		rids.append(plane.get_rid())


func unregister_plane(plane: PlaneActor) -> void:
	_blue_rids.erase(plane.get_rid())
	_red_rids.erase(plane.get_rid())


func _rids_for(team: int) -> Array[RID]:
	return _blue_rids if team == Teams.Id.TEAM_BLUE else _red_rids


func active_bullet_count() -> int:
	return _count


func clear() -> void:
	_count = 0
	_multimesh.visible_instance_count = 0


## Adds one bullet. Silently drops it when the pool is full (never allocates).
func spawn(origin: Vector3, bullet_velocity: Vector3, shooter: PlaneActor, lifetime: float,
		damage: float, burn_dps: float = 0.0, burn_duration: float = 0.0) -> void:
	if _count >= MAX_BULLETS or shooter == null:
		return
	var index: int = _count
	_positions[index] = origin
	_velocities[index] = bullet_velocity
	_lifetimes[index] = lifetime
	_damages[index] = damage
	_burn_dps[index] = burn_dps
	_burn_durations[index] = burn_duration
	_shooters[index] = shooter
	_teams[index] = shooter.team
	_count += 1


func _physics_process(delta: float) -> void:
	if _count > 0 and multiplayer.is_server():
		_step_bullets(delta)
	_write_tracers()


func _process(delta: float) -> void:
	for index: int in range(_sparks.size()):
		if _spark_timers[index] <= 0.0:
			continue
		_spark_timers[index] -= delta
		var spark: MeshInstance3D = _sparks[index]
		if _spark_timers[index] <= 0.0:
			spark.visible = false
		else:
			spark.scale = Vector3.ONE * lerpf(0.5, 3.0, 1.0 - _spark_timers[index] / SPARK_TIME)


func _step_bullets(delta: float) -> void:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var index: int = _count - 1
	# Iterate backwards so swap-removal never skips a bullet.
	while index >= 0:
		var from: Vector3 = _positions[index]
		var to: Vector3 = from + _velocities[index] * delta
		_query.from = from
		_query.to = to
		_query.exclude = _rids_for(_teams[index])
		var hit: Dictionary = space.intersect_ray(_query)
		if not hit.is_empty():
			var hit_position: Vector3 = hit["position"]
			var victim: PlaneActor = hit["collider"] as PlaneActor
			var shooter: PlaneActor = _shooters[index]
			if victim != null and is_instance_valid(shooter):
				victim.apply_damage(_damages[index], shooter, _burn_dps[index], _burn_durations[index])
				bullet_hit.emit(victim, shooter, hit_position)
			_show_spark(hit_position)
			_remove(index)
		else:
			_positions[index] = to
			_lifetimes[index] -= delta
			if _lifetimes[index] <= 0.0:
				_remove(index)
		index -= 1


func _remove(index: int) -> void:
	var last: int = _count - 1
	if index != last:
		_positions[index] = _positions[last]
		_velocities[index] = _velocities[last]
		_lifetimes[index] = _lifetimes[last]
		_damages[index] = _damages[last]
		_burn_dps[index] = _burn_dps[last]
		_burn_durations[index] = _burn_durations[last]
		_shooters[index] = _shooters[last]
		_teams[index] = _teams[last]
	_shooters[last] = null
	_count = last


func _write_tracers() -> void:
	_multimesh.visible_instance_count = _count
	for index: int in range(_count):
		var direction: Vector3 = _velocities[index].normalized()
		# Any up vector works as long as it is not parallel to the bullet.
		var up: Vector3 = Vector3.UP if absf(direction.y) < 0.99 else Vector3.RIGHT
		var tracer_basis: Basis = Basis.looking_at(direction, up)
		_multimesh.set_instance_transform(index, Transform3D(tracer_basis, _positions[index]))
		_multimesh.set_instance_color(index, TRACER_COLORS[_teams[index]])


func _build_tracer_multimesh() -> void:
	var tracer: BoxMesh = BoxMesh.new()
	tracer.size = Vector3(TRACER_WIDTH, TRACER_WIDTH, TRACER_LENGTH)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(1.6, 1.6, 1.6)  # Over-bright so glow picks tracers up.
	tracer.material = material
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_colors = true
	_multimesh.mesh = tracer
	_multimesh.instance_count = MAX_BULLETS
	_multimesh.visible_instance_count = 0
	# Bullets roam the whole arena: a fixed huge AABB avoids per-frame bounds work
	# and stops the batch being culled when its first instance is off-screen.
	_multimesh.custom_aabb = AABB(Vector3(-6000.0, -200.0, -6000.0), Vector3(12000.0, 2400.0, 12000.0))
	var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	instance.name = "Tracers"
	instance.multimesh = _multimesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Transforms are rewritten every physics tick; interpolating them would lag.
	instance.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(instance)


func _build_spark_pool() -> void:
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 8
	mesh.rings = 4
	_spark_timers.resize(SPARK_POOL_SIZE)
	for index: int in range(SPARK_POOL_SIZE):
		var spark: MeshInstance3D = MeshInstance3D.new()
		spark.name = "Spark%d" % index
		spark.mesh = mesh
		spark.material_override = ToonMaterials.unlit(Color(1.0, 0.9, 0.45, 0.9), true)
		spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		spark.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		spark.visible = false
		add_child(spark)
		_sparks.append(spark)


func _show_spark(world_position: Vector3) -> void:
	var spark: MeshInstance3D = _sparks[_next_spark]
	spark.global_position = world_position
	spark.scale = Vector3.ONE * 0.5
	spark.visible = true
	_spark_timers[_next_spark] = SPARK_TIME
	_next_spark = (_next_spark + 1) % SPARK_POOL_SIZE
