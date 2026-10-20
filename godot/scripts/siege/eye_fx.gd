extends Node3D
# Glowing, smoking eyes (0.31.192, Kevin: "add glow/smoky effects to the necromancers eyes"). siege_view.make_body puts
# one under a BoneAttachment3D on the head (EYE_FX: each eye's place on the mesh, through the head's skin bind) and
# sets pts / col / lite. Built on its first frame in the tree, like weapon_fx_root.gd: Godot draws a particle at its own
# size whatever the emitter's scale, so this node undoes the world scale and everything below is in world units, sized
# from the distance between the eyes (the same look on every body size).
#  - each eye: a white-hot core and a wider soft glow in the eye's colour (billboards, pulsing out of step);
#  - each eye: wisps and a thin smoke in its colour streaming off it -- out to its side across the temple, and up --
#    left behind in the world as he moves (not with "lite": another player's body with fewer effects on keeps the
#    glow only).
const Root = preload("res://scripts/siege/weapon_fx_root.gd")

var pts: Array = []          # the eyes, in the head attachment's space
var up := Vector3.UP         # the face's up and forward, in that space
var fwd := Vector3.BACK
var col := Color("#9dff5a")
var lite := false
var _built := false

func _process(_d: float) -> void:
	if not _built:
		_built = true
		_build()
	set_process(false)

func _build() -> void:
	if pts.size() < 1:
		return
	var ps := maxf(global_basis.get_scale().x, 0.0001)
	scale = Vector3.ONE / ps
	var gap := 0.1
	var mid := Vector3.ZERO
	for q in pts:
		mid += (q as Vector3) / float(pts.size())
	if pts.size() >= 2:
		gap = maxf(((pts[0] as Vector3) - (pts[1] as Vector3)).length() * ps, 0.02)
	for i in pts.size():
		var eye := Node3D.new()
		eye.name = "Eye%d" % i
		eye.position = (pts[i] as Vector3) * ps
		add_child(eye)
		# the glow: a soft halo, then the core (white at its heart); the two eyes pulse a little out of step
		eye.add_child(_glow("Glow", gap * 1.25, Color(col, 0.55), 0.0, 0.3 + 0.08 * i))
		eye.add_child(_glow("Core", gap * 0.5, Color(col.lightened(0.25), 1.0), 0.95, 0.2 + 0.05 * i))
		if lite:
			continue
		var out := ((pts[i] as Vector3) - mid).normalized()
		var dir := (out * 0.85 + fwd.normalized() * 0.2 + up.normalized() * 0.5).normalized()
		for pr in [_smoke("Wisps", "wisp", 9, 1.0, gap * 0.85, gap, 0.6, 1.0, 1.3), _smoke("Smoke", "smoke", 5, 1.5, gap * 1.0, gap, 0.0, 0.35, 0.8)]:
			(pr as Node3D).basis = Basis(Quaternion(Vector3.UP, dir))       # streaming out along dir
			eye.add_child(pr)

func _glow(nm: String, size: float, c: Color, core: float, pulse: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size
	mi.mesh = q
	mi.material_override = Root.sprite_mat("dot", 1.0, core, c, 0.0, pulse)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

func _smoke(nm: String, tex: String, n: int, life: float, size: float, gap: float, core: float, alpha: float, speed: float) -> GPUParticles3D:
	# off the eye along the emitter's +Y, rising, left behind in the world, growing and fading
	var p := GPUParticles3D.new()
	p.name = nm
	p.amount = n
	p.lifetime = life
	p.preprocess = life
	p.randomness = 0.4
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = gap * 0.12
	pm.direction = Vector3.UP
	pm.spread = 22.0
	pm.initial_velocity_min = gap * 1.2 * speed
	pm.initial_velocity_max = gap * 2.2 * speed
	pm.gravity = Vector3(0, gap * 1.4, 0)
	pm.damping_min = gap * 0.5
	pm.damping_max = gap * 1.0
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -60.0
	pm.angular_velocity_max = 60.0
	pm.scale_min = 0.7
	pm.scale_max = 1.2
	var sc := Curve.new()
	sc.max_value = 2.0
	sc.add_point(Vector2(0.0, 0.35))
	sc.add_point(Vector2(1.0, 1.4))
	var st := CurveTexture.new()
	st.curve = sc
	pm.scale_curve = st
	pm.turbulence_enabled = true
	pm.turbulence_noise_scale = 1.2
	pm.turbulence_noise_strength = 1.0
	pm.turbulence_influence_min = 0.04
	pm.turbulence_influence_max = 0.12
	var g := Gradient.new()
	g.set_color(0, Color(col.lightened(0.2), 0.0))
	g.add_point(0.12, Color(col.lightened(0.1), alpha))
	g.add_point(0.55, Color(col, alpha * 0.7))
	g.set_color(g.get_point_count() - 1, Color(col.darkened(0.3), 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size
	q.material = Root.sprite_mat(tex, 1.0, core)
	p.draw_pass_1 = q
	p.visibility_aabb = AABB(Vector3(-gap * 4.0, -gap * 2.0, -gap * 4.0), Vector3(gap * 8.0, gap * 10.0, gap * 8.0))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p
