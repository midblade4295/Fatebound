class_name BulletSystem
extends Node3D
## Every bullet in the match, simulated as plain data and drawn with a single
## MultiMesh. No bullet nodes, no Area3Ds: ten planes firing at once is one
## draw call.
##
## Flight: each physics tick a bullet's velocity is updated for gravity and
## drag (Ballistics.step), then it sweeps from where it was to where it will
## be, so fast bullets can never tunnel through anything.
##
## Hits are decided by where the bullet actually goes:
##  - against the world (cliffs, airfields, sea) with one physics ray;
##  - against each enemy plane by tracing the bullet's path, relative to that
##    plane's own motion, through its per-part hit boxes (PlaneHitboxes). The
##    first box entered is the part that is hit, and the trace carries on
##    through the airframe so the same bullet can damage what lies behind it.
##    A path that passes between the boxes is a miss.
## Whichever is nearer along the path, world or plane, is what the bullet hits.
##
## Impact energy: damage scales with the square of the closing speed between
## bullet and target, so a head-on pass hits harder than a tail chase and a
## bullet slowed by drag at long range hits softer.
##
## Friendly fire cannot happen: bullets are never tested against the
## shooter's own team.
##
## Networking: run this on the server only. Clients can render their own
## cosmetic tracers from PlaneActor.shot_fired.

signal bullet_hit(victim: PlaneActor, shooter: PlaneActor, world_position: Vector3)
## A bullet that was not fired by `listener` passed close to it without
## hitting. [param world_position] is where it was nearest. Sound only.
signal bullet_whizzed(world_position: Vector3)

const MAX_BULLETS: int = 512
const TRACER_LENGTH: float = 9.0
const TRACER_WIDTH: float = 0.32
const SPARK_POOL_SIZE: int = 12
const SPARK_TIME: float = 0.16
const TRACER_COLORS: Array[Color] = [Color(0.75, 0.92, 1.0), Color(1.0, 0.84, 0.35)]
## Limits on the impact-energy damage multiplier (closing speed squared).
const MIN_IMPACT_ENERGY: float = 0.45
const MAX_IMPACT_ENERGY: float = 1.5
## A bullet passing within this many metres of the listener is heard going by.
const WHIZ_RADIUS: float = 16.0

var _positions: PackedVector3Array = PackedVector3Array()
var _velocities: PackedVector3Array = PackedVector3Array()
var _lifetimes: PackedFloat32Array = PackedFloat32Array()
var _damages: PackedFloat32Array = PackedFloat32Array()
var _muzzle_speeds: PackedFloat32Array = PackedFloat32Array()
var _burn_dps: PackedFloat32Array = PackedFloat32Array()
var _burn_durations: PackedFloat32Array = PackedFloat32Array()
var _shooters: Array[PlaneActor] = []
var _teams: PackedInt32Array = PackedInt32Array()
## 1 once a bullet has already been heard going past, so it is heard once.
var _whizzed: PackedByteArray = PackedByteArray()
var _count: int = 0

## The plane whose pilot hears near misses (the local player), or null.
var listener: PlaneActor

var _planes: Array[PlaneActor] = []
var _multimesh: MultiMesh
var _query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
# Scratch arrays reused for every trace so the hot loop never allocates.
var _trace_parts: PackedInt32Array = PackedInt32Array()
var _trace_distances: PackedFloat32Array = PackedFloat32Array()
var _hit_parts: PackedInt32Array = PackedInt32Array()
var _sparks: Array[MeshInstance3D] = []
var _spark_timers: PackedFloat32Array = PackedFloat32Array()
var _next_spark: int = 0


func _ready() -> void:
	_positions.resize(MAX_BULLETS)
	_velocities.resize(MAX_BULLETS)
	_lifetimes.resize(MAX_BULLETS)
	_damages.resize(MAX_BULLETS)
	_muzzle_speeds.resize(MAX_BULLETS)
	_burn_dps.resize(MAX_BULLETS)
	_burn_durations.resize(MAX_BULLETS)
	_teams.resize(MAX_BULLETS)
	_whizzed.resize(MAX_BULLETS)
	_shooters.resize(MAX_BULLETS)
	# Planes are handled by the box trace, so the physics ray only sees the world.
	_query.collision_mask = PlaneActor.COLLISION_LAYER_WORLD
	_build_tracer_multimesh()
	_build_spark_pool()


## Registers a plane as something bullets can hit.
func register_plane(plane: PlaneActor) -> void:
	if not _planes.has(plane):
		_planes.append(plane)


func unregister_plane(plane: PlaneActor) -> void:
	_planes.erase(plane)


func active_bullet_count() -> int:
	return _count


func clear() -> void:
	_count = 0
	_multimesh.visible_instance_count = 0


## Adds one bullet. [param muzzle_speed] is the gun's own muzzle speed (not
## including the firing plane's velocity); impact energy is measured against
## it. Silently drops the bullet when the pool is full (never allocates).
func spawn(origin: Vector3, bullet_velocity: Vector3, shooter: PlaneActor, lifetime: float,
		damage: float, muzzle_speed: float, burn_dps: float = 0.0, burn_duration: float = 0.0) -> void:
	if _count >= MAX_BULLETS or shooter == null:
		return
	var index: int = _count
	_positions[index] = origin
	_velocities[index] = bullet_velocity
	_lifetimes[index] = lifetime
	_damages[index] = damage
	_muzzle_speeds[index] = maxf(muzzle_speed, 1.0)
	_burn_dps[index] = burn_dps
	_burn_durations[index] = burn_duration
	_shooters[index] = shooter
	_teams[index] = shooter.team
	_whizzed[index] = 0
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
		var velocity: Vector3 = Ballistics.step(_velocities[index], delta)
		_velocities[index] = velocity
		var from: Vector3 = _positions[index]
		var to: Vector3 = from + velocity * delta
		var step_length: float = from.distance_to(to)

		# World: how far along this step, if at all, something solid is in the way.
		_query.from = from
		_query.to = to
		var world_hit: Dictionary = space.intersect_ray(_query)
		var nearest: float = step_length
		var hit_world: bool = not world_hit.is_empty()
		if hit_world:
			var world_point: Vector3 = world_hit["position"]
			nearest = from.distance_to(world_point)

		# Planes: the nearest enemy airframe this step's path really passes through.
		var victim: PlaneActor = null
		var victim_closing_speed: float = 0.0
		var team: int = _teams[index]
		for plane: PlaneActor in _planes:
			if not plane.alive or plane.team == team:
				continue
			# Work in the plane's moving frame: there the bullet covers this much.
			var relative_step: Vector3 = (velocity - plane.velocity) * delta
			var relative_length: float = relative_step.length()
			if relative_length < 0.0001:
				continue
			var direction: Vector3 = relative_step / relative_length
			# Cheap reject: does the step come anywhere near the plane at all?
			var to_plane: Vector3 = plane.global_position - from
			var along: float = clampf(to_plane.dot(direction), 0.0, relative_length)
			var reach: float = plane.hitboxes.bounding_radius
			if (to_plane - direction * along).length_squared() > reach * reach:
				continue
			# Trace on past the end of this step so the list holds everything
			# the bullet would go on to pass through inside the airframe.
			plane.trace_parts(from, direction, relative_length + reach * 2.0, _trace_parts, _trace_distances)
			if _trace_parts.is_empty() or _trace_distances[0] > relative_length:
				continue  # Missed the boxes, or will not reach them until a later tick.
			# Convert "how far in the plane's frame" back to distance along the real path.
			var distance: float = _trace_distances[0] / relative_length * step_length
			if distance <= nearest:
				nearest = distance
				victim = plane
				victim_closing_speed = relative_length / delta
				_hit_parts = _trace_parts.duplicate()

		if victim != null:
			var shooter: PlaneActor = _shooters[index]
			var hit_position: Vector3 = from + (to - from).normalized() * nearest
			if is_instance_valid(shooter):
				var speed_ratio: float = victim_closing_speed / _muzzle_speeds[index]
				var impact_energy: float = clampf(speed_ratio * speed_ratio, MIN_IMPACT_ENERGY, MAX_IMPACT_ENERGY)
				victim.take_bullet(_hit_parts, _damages[index] * impact_energy, shooter, _burn_dps[index], _burn_durations[index])
				bullet_hit.emit(victim, shooter, hit_position)
			_show_spark(hit_position)
			_remove(index)
		elif hit_world:
			var world_position: Vector3 = world_hit["position"]
			_show_spark(world_position)
			_remove(index)
		else:
			if listener != null and _whizzed[index] == 0:
				_check_whiz(index, from, velocity, delta)
			_positions[index] = to
			_lifetimes[index] -= delta
			if _lifetimes[index] <= 0.0:
				_remove(index)
		index -= 1


## Reports a bullet that is passing close to the listener this tick. It only
## counts at the moment of closest approach (the bullet is beside the plane,
## not still coming or already gone), and only for other people's bullets.
func _check_whiz(index: int, from: Vector3, velocity: Vector3, delta: float) -> void:
	if not is_instance_valid(listener) or not listener.alive or _shooters[index] == listener:
		return
	var relative_step: Vector3 = (velocity - listener.velocity) * delta
	var step_length: float = relative_step.length()
	if step_length < 0.0001:
		return
	var direction: Vector3 = relative_step / step_length
	var to_listener: Vector3 = listener.global_position - from
	var along: float = to_listener.dot(direction)
	if along < 0.0 or along > step_length:
		return  # Nearest point is not within this tick's travel.
	var nearest: Vector3 = from + direction * along
	if nearest.distance_squared_to(listener.global_position) <= WHIZ_RADIUS * WHIZ_RADIUS:
		_whizzed[index] = 1
		bullet_whizzed.emit(nearest)


func _remove(index: int) -> void:
	var last: int = _count - 1
	if index != last:
		_positions[index] = _positions[last]
		_velocities[index] = _velocities[last]
		_lifetimes[index] = _lifetimes[last]
		_damages[index] = _damages[last]
		_muzzle_speeds[index] = _muzzle_speeds[last]
		_burn_dps[index] = _burn_dps[last]
		_burn_durations[index] = _burn_durations[last]
		_shooters[index] = _shooters[last]
		_teams[index] = _teams[last]
		_whizzed[index] = _whizzed[last]
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
