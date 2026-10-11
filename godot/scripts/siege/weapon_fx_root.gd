extends Node3D
# A weapon's particles, pinned sprites and swing ribbon (0.31.100, weapon_fx.gd sets box / specs / trail). Built on the
# first frame in the tree: Godot draws a particle at its own size whatever the emitter's scale, so the piece's length
# in the world is measured first and this node undoes the piece's scale -- below it everything is in world units.
const SPRITE = preload("res://scripts/siege/fx_sprite.gdshader")
const TRAIL = preload("res://scripts/siege/fx_trail.gdshader")
const TEX := "res://assets/vfx/weapon/%s.png"
const TRAIL_LIFE := 0.16             # s of ribbon
const TRAIL_SUB := 3                 # points between two frames' samples (a smooth curve)

var box := AABB()                    # the piece, in its own space
var specs: Array = []
var trail := Color(0, 0, 0, 0)

static var _mats := {}
var _built := false
var _ps := 1.0
var _len := 1.0                      # the piece's length in the world
var _axis := 1
var _spinners: Array = []            # [node, axis, rad/s]
var _ribbon: MeshInstance3D = null
var _im: ImmediateMesh = null
var _samples: Array = []             # [base, tip, time], newest first
var _clock := 0.0
var _base_l := Vector3.ZERO
var _tip_l := Vector3.ZERO

func _process(delta: float) -> void:
	if not _built:
		_built = true
		_build()
	for s in _spinners:
		if is_instance_valid(s[0]):
			(s[0] as Node3D).rotate_object_local(s[1], float(s[2]) * delta)
	if _ribbon != null:
		_update_ribbon(delta)

func at_point(f: float) -> Vector3:
	# a point on the piece's axis (its longest side; 0 = its low end, 1 = its high end), in its own space
	var p := box.get_center()
	p[_axis] = box.position[_axis] + box.size[_axis] * f
	return p

func _build() -> void:
	var model := get_parent() as Node3D
	if model == null:
		return
	_ps = maxf(model.global_basis.get_scale().x, 0.0001)
	scale = Vector3.ONE / _ps
	_axis = 1
	if box.size.x > box.size[_axis] * 1.15:
		_axis = 0
	if box.size.z > box.size[_axis] * 1.15:
		_axis = 2
	_len = maxf(box.size[_axis], 0.05) * _ps
	for s in specs:
		match str(s.get("kind", "p")):
			"p":
				_particles(s)
			"bill", "flat":
				_pinned(s)
			"orbit":
				_orbit(s)
	if trail.a > 0.0:
		_base_l = at_point(0.45)
		_tip_l = at_point(1.0)
		_im = ImmediateMesh.new()
		_ribbon = MeshInstance3D.new()
		_ribbon.name = "Ribbon"
		_ribbon.top_level = true
		_ribbon.mesh = _im
		_ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := ShaderMaterial.new()
		m.shader = TRAIL
		m.set_shader_parameter("tint", Color(trail, 1.0))
		m.set_shader_parameter("energy", trail.a)
		_ribbon.material_override = m
		add_child(_ribbon)
		_ribbon.global_transform = Transform3D.IDENTITY

static func sprite_mat(tex: String, grid: float, core: float, tint := Color.WHITE, spin := 0.0, pulse := 0.0, flat := false) -> ShaderMaterial:
	var k := "%s|%.0f|%.2f|%s|%.2f|%.2f|%s" % [tex, grid, core, tint.to_html(), spin, pulse, str(flat)]
	if not _mats.has(k):
		var m := ShaderMaterial.new()
		m.shader = SPRITE
		m.set_shader_parameter("tex", load(TEX % tex))
		m.set_shader_parameter("grid", grid)
		m.set_shader_parameter("core", core)
		m.set_shader_parameter("tint", tint)
		m.set_shader_parameter("spin", spin)
		m.set_shader_parameter("pulse", pulse)
		m.set_shader_parameter("lie_flat", flat)
		_mats[k] = m
	return _mats[k]

func _ramp(col: Color, fade: String, alpha: float) -> GradientTexture1D:
	var g := Gradient.new()
	var a := alpha
	match fade:
		"hot":
			g.set_color(0, Color(col.lerp(Color.WHITE, 0.7), a))
			g.add_point(0.3, Color(col, a))
			g.set_color(g.get_point_count() - 1, Color(col.darkened(0.5), 0.0))
		"flicker":
			g.set_color(0, Color(col, a))
			g.add_point(0.25, Color(col, a * 0.25))
			g.add_point(0.5, Color(col, a))
			g.add_point(0.75, Color(col, a * 0.35))
			g.set_color(g.get_point_count() - 1, Color(col, 0.0))
		"slow":
			g.set_color(0, Color(col, 0.0))
			g.add_point(0.3, Color(col, a))
			g.add_point(0.7, Color(col, a))
			g.set_color(g.get_point_count() - 1, Color(col, 0.0))
		_:
			g.set_color(0, Color(col, 0.0))
			g.add_point(0.12, Color(col, a))
			g.add_point(0.65, Color(col, a))
			g.set_color(g.get_point_count() - 1, Color(col, 0.0))
	var t := GradientTexture1D.new()
	t.gradient = g
	return t

func _curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	c.max_value = 2.0
	for p in points:
		c.add_point(p)
	var t := CurveTexture.new()
	t.curve = c
	return t

func _particles(s: Dictionary) -> void:
	var L := _len
	var at: Array = s.get("at", [0.5, 1.0])
	var p := GPUParticles3D.new()
	p.name = "Fx_" + str(s.tex)
	p.amount = int(s.get("n", 8))
	p.lifetime = float(s.get("life", 1.0))
	p.preprocess = p.lifetime
	p.randomness = 0.35
	p.local_coords = not bool(s.get("world", false))
	p.position = at_point((float(at[0]) + float(at[1])) * 0.5) * _ps
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	var ext := box.size * 0.5 * float(s.get("w", 0.6))
	ext[_axis] = box.size[_axis] * absf(float(at[1]) - float(at[0])) * 0.5
	pm.emission_box_extents = ext * _ps
	var dir := Vector3.ZERO
	dir[_axis] = 1.0
	pm.direction = dir
	pm.spread = float(s.get("spread", 0.0))
	var vel: Array = s.get("vel", [0.0, 0.0])
	pm.initial_velocity_min = float(vel[0]) * L
	pm.initial_velocity_max = float(vel[1]) * L
	pm.gravity = (s.get("grav", Vector3.ZERO) as Vector3) * L
	var ang := float(s.get("angle", 0.0))
	pm.angle_min = -ang
	pm.angle_max = ang
	var spin := float(s.get("spin", 0.0))
	pm.angular_velocity_min = -spin
	pm.angular_velocity_max = spin
	pm.scale_min = 0.7
	pm.scale_max = 1.2
	if bool(s.get("pop", false)):
		pm.scale_curve = _curve([Vector2(0, 0), Vector2(0.18, 1.0), Vector2(1, 0)])
	elif bool(s.get("shrink", false)):
		pm.scale_curve = _curve([Vector2(0, 1.0), Vector2(1, 0.25)])
	elif bool(s.get("grow", false)):
		pm.scale_curve = _curve([Vector2(0, 0.45), Vector2(1, 1.2)])
	var grid := float(s.get("grid", 1.0))
	if grid > 1.0:
		pm.anim_offset_max = 1.0
	if float(s.get("turb", 0.0)) > 0.0:
		pm.turbulence_enabled = true
		pm.turbulence_noise_scale = 1.5
		pm.turbulence_noise_strength = 1.0
		pm.turbulence_influence_min = 0.03 * float(s.turb)
		pm.turbulence_influence_max = 0.12 * float(s.turb)
	pm.color_ramp = _ramp(s.col, str(s.get("fade", "")), float(s.get("alpha", 1.0)))
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2.ONE * float(s.get("size", 0.1)) * L
	q.material = sprite_mat(str(s.tex), grid, float(s.get("core", 0.6)))
	p.draw_pass_1 = q
	p.visibility_aabb = AABB(-Vector3.ONE * L * 2.0, Vector3.ONE * L * 4.0)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)

func _quad(tex: String, size: float, col: Color, s: Dictionary, flat := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size
	mi.mesh = q
	mi.material_override = sprite_mat(tex, 1.0, float(s.get("core", 0.5)), Color(col, float(s.get("alpha", 1.0))),
		float(s.get("spin", 0.0)), float(s.get("pulse", 0.0)), flat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

func _pinned(s: Dictionary) -> void:
	var flat := str(s.get("kind", "")) == "flat"
	var mi := _quad(str(s.tex), float(s.get("size", 0.5)) * _len, s.col, s, flat)
	mi.name = "Fx_" + str(s.tex)
	mi.position = at_point(float(s.get("at", 0.9))) * _ps
	if flat:
		# the quad faces +Z: turn it to face along the piece (a halo lies across a staff)
		var ax := Vector3.ZERO
		ax[_axis] = 1.0
		if _axis != 2:
			mi.basis = Basis.looking_at(-ax, Vector3.BACK if _axis == 1 else Vector3.UP)
	add_child(mi)

func _orbit(s: Dictionary) -> void:
	var hub := Node3D.new()
	hub.name = "Fx_orbit"
	hub.position = at_point(float(s.get("at", 0.9))) * _ps
	add_child(hub)
	var ax := Vector3.ZERO
	ax[_axis] = 1.0
	var side := Vector3.RIGHT if _axis != 0 else Vector3.UP
	var n := int(s.get("n", 3))
	for i in n:
		var mi := _quad(str(s.tex), float(s.get("size", 0.1)) * _len, s.col, s)
		mi.position = side.rotated(ax, TAU * float(i) / float(n)) * float(s.get("r", 0.17)) * _len
		hub.add_child(mi)
	_spinners.append([hub, ax, float(s.get("speed", 1.8))])

func _update_ribbon(delta: float) -> void:
	_clock += delta
	var model := get_parent() as Node3D
	if model == null:
		return
	var xf := model.global_transform
	var tip := xf * _tip_l
	if not _samples.is_empty() and tip.distance_to(_samples[0][1]) > _len * 1.2:
		_samples.clear()                              # a jump (a clip starting over, a respawn), not a swing
	_samples.push_front([xf * _base_l, tip, _clock])
	while _samples.size() > 2 and _clock - float(_samples[-1][2]) > TRAIL_LIFE:
		_samples.pop_back()
	_im.clear_surfaces()
	var n := _samples.size()
	if n < 2:
		return
	# how fast the tip moved at each sample (a still or idling weapon draws nothing)
	var speed: Array = []
	var any := false
	for i in n:
		var j := i + 1 if i < n - 1 else i - 1
		var dt := maxf(absf(float(_samples[i][2]) - float(_samples[j][2])), 0.001)
		var v := ((_samples[i][1] as Vector3) - (_samples[j][1] as Vector3)).length() / dt
		var a := clampf((v / maxf(_len, 0.01) - 1.0) / 2.5, 0.0, 1.0)
		speed.append(a)
		any = any or a > 0.01
	if not any:
		return
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in n - 1:
		for sub in TRAIL_SUB:
			var t := float(sub) / float(TRAIL_SUB)
			var i0 := maxi(i - 1, 0)
			var i3 := mini(i + 2, n - 1)
			var b := _cr(_samples[i0][0], _samples[i][0], _samples[i + 1][0], _samples[i3][0], t)
			var tp := _cr(_samples[i0][1], _samples[i][1], _samples[i + 1][1], _samples[i3][1], t)
			var age := (_clock - lerpf(float(_samples[i][2]), float(_samples[i + 1][2]), t)) / TRAIL_LIFE
			var a := lerpf(float(speed[i]), float(speed[i + 1]), t)
			_im.surface_set_color(Color(1, 1, 1, a))
			_im.surface_set_uv(Vector2(age, 0.0))
			_im.surface_add_vertex(b)
			_im.surface_set_color(Color(1, 1, 1, a))
			_im.surface_set_uv(Vector2(age, 1.0))
			_im.surface_add_vertex(tp)
	var last: Array = _samples[n - 1]
	_im.surface_set_color(Color(1, 1, 1, float(speed[n - 1])))
	_im.surface_set_uv(Vector2((_clock - float(last[2])) / TRAIL_LIFE, 0.0))
	_im.surface_add_vertex(last[0])
	_im.surface_set_color(Color(1, 1, 1, float(speed[n - 1])))
	_im.surface_set_uv(Vector2((_clock - float(last[2])) / TRAIL_LIFE, 1.0))
	_im.surface_add_vertex(last[1])
	_im.surface_end()

static func _cr(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	# Catmull-Rom between p1 and p2
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
