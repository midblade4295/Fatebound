class_name ExplosionFx
extends Node3D
## One-shot cartoon explosion: a fast orange burst, a slower dark smoke puff and
## a few team-coloured chunks. Frees itself when finished. Cosmetic only.

const LIFETIME: float = 2.2

static var _puff_mesh: SphereMesh
static var _chunk_mesh: BoxMesh


## Creates an explosion under [param parent] at a world position.
static func spawn(parent: Node, world_position: Vector3, team_color: Color) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var fx: ExplosionFx = ExplosionFx.new()
	fx.name = "Explosion"
	parent.add_child(fx)
	fx.global_position = world_position
	fx._build(team_color)


func _build(team_color: Color) -> void:
	if _puff_mesh == null:
		_puff_mesh = SphereMesh.new()
		_puff_mesh.radius = 0.5
		_puff_mesh.height = 1.0
		_puff_mesh.radial_segments = 8
		_puff_mesh.rings = 4
		_chunk_mesh = BoxMesh.new()
	_add_burst("Fire", _puff_mesh, Color(1.0, 0.72, 0.18), Color(1.0, 0.25, 0.05, 0.0), 22, 0.55, 26.0, 3.0, 9.0, Vector3.ZERO)
	_add_burst("Smoke", _puff_mesh, Color(0.2, 0.2, 0.22, 0.9), Color(0.1, 0.1, 0.1, 0.0), 16, 1.9, 9.0, 4.0, 13.0, Vector3(0.0, 3.0, 0.0))
	_add_burst("Chunks", _chunk_mesh, team_color, Color(team_color.r, team_color.g, team_color.b, 0.0), 10, 1.4, 38.0, 1.1, 0.6, Vector3(0.0, -30.0, 0.0))
	get_tree().create_timer(LIFETIME).timeout.connect(queue_free)


func _add_burst(burst_name: String, mesh: Mesh, start: Color, end: Color, amount: int, lifetime: float,
		burst_speed: float, start_scale: float, end_scale: float, gravity: Vector3) -> void:
	var particles: CPUParticles3D = CPUParticles3D.new()
	particles.name = burst_name
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.amount = amount
	particles.lifetime = lifetime
	particles.mesh = mesh
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 1.5
	particles.direction = Vector3.UP
	particles.spread = 180.0
	particles.initial_velocity_min = burst_speed * 0.4
	particles.initial_velocity_max = burst_speed
	particles.damping_min = burst_speed * 0.6
	particles.damping_max = burst_speed * 0.9
	particles.gravity = gravity
	particles.scale_amount_min = start_scale
	particles.scale_amount_max = start_scale * 1.5
	var size_curve: Curve = Curve.new()
	size_curve.add_point(Vector2(0.0, 1.0))
	size_curve.add_point(Vector2(1.0, end_scale / start_scale))
	particles.scale_amount_curve = size_curve
	var ramp: Gradient = Gradient.new()
	ramp.set_color(0, start)
	ramp.set_color(1, end)
	particles.color_ramp = ramp
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particles.material_override = material
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(particles)
	particles.emitting = true
