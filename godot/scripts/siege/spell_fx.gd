extends Node3D
# The abilities' effects (0.31.201, Kevin: "I want every ability to have much better special effects in the game. Every
# one of them should have its own unique look and I want them especially the ultimates to look exciting"). A child of
# siege_view.gd, which hands it every cast (cast / ult / q / event) and what lasts on heroes and on the ground (sync, each
# frame); it builds each one from a few kinds of thing:
#   - bursts and streams of sprites (GPU particles: the painted and the procedural sprites of assets/vfx, drawn by
#     fx_sprite.gdshader in the spell's colour), rocks (mesh particles) and knives (boxes along their flight);
#   - flashes (a sprite facing the camera, popping and going);
#   - ground discs fitted to the terrain (fx_ground.gdshader: a soft disc, a turning sprite -- runes, cracks, rays, a
#     swirl -- fire, lightning, dappled light), waves (the rim alone, running out), fans (a cone on the ground);
#   - pillars, cones and sheets of light (fx_beam.gdshader: noise scrolling along them), beams between two points;
#   - lightning (a jagged core with a glow, a branch or two);
#   - shells round a hero (fx_shell.gdshader: a shield's bubble, a stone or bark skin, a fury's halo, a dome);
#   - trails behind a dash, a thrown thing, a meteor.
# Each hero's four abilities are their own recipe (cast, ult, q); what lasts -- shields, slows, marks, skins, parries,
# poison, dashes, the ultimates' auras, the zones -- is held by key (_hold) and let go when the sim says it's over.
# Everything is timed by the view's clock and stepped in step(); low_fx thins the particles and skips the extras.
const SPRITE = preload("res://scripts/siege/fx_sprite.gdshader")
const GROUND = preload("res://scripts/siege/fx_ground.gdshader")
const BEAM = preload("res://scripts/siege/fx_beam.gdshader")
const SHELL = preload("res://scripts/siege/fx_shell.gdshader")
const SCORCH = preload("res://scripts/siege/fx_scorch.gdshader")
const Sim = preload("res://scripts/siege/siege_sim.gd")
const TEX_DIRS := ["res://assets/vfx/spell/%s.png", "res://assets/vfx/weapon/%s.png", "res://assets/vfx/smoke/smoke_puff.png"]

var view                                   # siege_view.gd
var _time := 0.0
var _live: Array = []                      # [{node, t0, life, fn}] fn(node, u 0..1, age) each frame, freed at life
var _holds := {}                           # key -> {nodes: [], alive: Callable, fade: [], until}

static var _tex := {}
static var _mats := {}                     # shared sprite materials by key
static var _pms := {}                      # shared particle process materials by key
static var _meshes := {}                   # shared meshes by key
static var _rock_mat: StandardMaterial3D = null

# ---------- colours ----------
const HERO_COL := {
	"knight": ["#ffd65a", "#bcd8ff"], "crusader": ["#ffe9a6", "#fff6d8"], "barbarian": ["#ff6a2a", "#ffb04a"],
	"berserker": ["#ff2a2a", "#7a0c0c"], "rogue": ["#a070ff", "#d8c8ff"], "assassin": ["#8a5bff", "#2a1a4a"],
	"ranger": ["#8fe36a", "#e8ffd0"], "sniper": ["#bfefff", "#ffffff"], "mage": ["#ff8a3a", "#ffd24a"],
	"archmage": ["#c070ff", "#ff6ad0"], "priest": ["#fff1a8", "#ffffff"], "necromancer": ["#7dff8a", "#d8e8c0"],
	"golem": ["#c8b48a", "#ffb04a"], "dragoon": ["#ff7a3a", "#ffd890"], "duelist": ["#ffe27a", "#ffffff"],
	"stormcaller": ["#7fb8ff", "#e8f4ff"], "musketeer": ["#ffd890", "#ff8a3a"], "druid": ["#6aff7a", "#d8ffb0"]}

func _ready() -> void:
	name = "SpellFx"

# ======================================================================================================================
# the pieces
# ======================================================================================================================
static func tex(nm: String) -> Texture2D:
	if not _tex.has(nm):
		var t: Texture2D = null
		for d in TEX_DIRS:
			var p: String = d % nm if d.contains("%s") else d
			if (nm == "smoke" and not d.contains("%s")) or (d.contains("%s") and ResourceLoader.exists(p)):
				t = load(p)
				break
		_tex[nm] = t if t != null else load("res://assets/vfx/weapon/dot.png")
	return _tex[nm]

static func sprite_mat(nm: String, core := 0.6, tint := Color.WHITE, grid := 1.0, flat := false, spin := 0.0) -> ShaderMaterial:
	var k := "%s|%.2f|%s|%.0f|%s|%.2f" % [nm, core, tint.to_html(), grid, str(flat), spin]
	if not _mats.has(k):
		var m := ShaderMaterial.new()
		m.shader = SPRITE
		m.set_shader_parameter("tex", tex(nm))
		m.set_shader_parameter("core", core)
		m.set_shader_parameter("tint", tint)
		m.set_shader_parameter("grid", grid)
		m.set_shader_parameter("lie_flat", flat)
		m.set_shader_parameter("spin", spin)
		_mats[k] = m
	return _mats[k]

static func _ramp(col: Color, fade: String, alpha: float) -> GradientTexture1D:
	var g := Gradient.new()
	var hot := col.lerp(Color.WHITE, 0.65)
	match fade:
		"hot":
			g.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
			g.colors = PackedColorArray([Color(hot, alpha), Color(col, alpha), Color(col.darkened(0.4), 0.0)])
		"flicker":
			g.offsets = PackedFloat32Array([0.0, 0.3, 0.5, 0.75, 1.0])
			g.colors = PackedColorArray([Color(col, alpha), Color(col, alpha * 0.2), Color(hot, alpha), Color(col, alpha * 0.3), Color(col, 0.0)])
		"slow":
			g.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
			g.colors = PackedColorArray([Color(col, 0.0), Color(col, alpha), Color(col, alpha), Color(col, 0.0)])
		"late":
			g.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
			g.colors = PackedColorArray([Color(col, alpha), Color(col, alpha), Color(col, 0.0)])
		"dark":
			g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
			g.colors = PackedColorArray([Color(col, alpha), Color(col.darkened(0.5), alpha * 0.7), Color(Color.BLACK, 0.0)])
		_:
			g.offsets = PackedFloat32Array([0.0, 0.1, 0.6, 1.0])
			g.colors = PackedColorArray([Color(hot, 0.0), Color(col, alpha), Color(col, alpha), Color(col, 0.0)])
	var t := GradientTexture1D.new()
	t.gradient = g
	return t

static func _curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	c.max_value = 2.0
	for p in points:
		c.add_point(p)
	var t := CurveTexture.new()
	t.curve = c
	return t

static func _pm(col: Color, o: Dictionary) -> ParticleProcessMaterial:
	# a burst's or stream's process material (shared by its settings)
	var k := col.to_html() + "|" + JSON.stringify(o)
	if _pms.has(k):
		return _pms[k]
	var pm := ParticleProcessMaterial.new()
	var shape := str(o.get("shape", "sphere"))
	match shape:
		"ring":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
			pm.emission_ring_radius = float(o.get("r", 1.0))
			pm.emission_ring_inner_radius = float(o.get("r", 1.0)) * float(o.get("inner", 0.85))
			pm.emission_ring_height = float(o.get("h", 0.1))
			pm.emission_ring_axis = Vector3.UP
		"box":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			pm.emission_box_extents = o.get("ext", Vector3(0.5, 0.5, 0.5))
		"point":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
		_:
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			pm.emission_sphere_radius = float(o.get("r", 0.4))
	pm.direction = o.get("dir", Vector3.UP)
	pm.spread = float(o.get("spread", 180.0))
	var vel: Array = o.get("vel", [1.0, 3.0])
	pm.initial_velocity_min = float(vel[0])
	pm.initial_velocity_max = float(vel[1])
	pm.gravity = o.get("grav", Vector3.ZERO)
	pm.damping_min = float(o.get("damp", 0.0))
	pm.damping_max = float(o.get("damp", 0.0)) * 1.4
	if o.has("radial"):
		pm.radial_velocity_min = float(o.radial) * 0.7
		pm.radial_velocity_max = float(o.radial)
	if o.has("orbit"):
		pm.orbit_velocity_min = float(o.orbit) * 0.7
		pm.orbit_velocity_max = float(o.orbit)
	var ang := float(o.get("angle", 180.0))
	pm.angle_min = -ang
	pm.angle_max = ang
	var spin := float(o.get("spin", 0.0))
	pm.angular_velocity_min = -spin
	pm.angular_velocity_max = spin
	var sz := float(o.get("sizes", 0.35))
	pm.scale_min = 1.0 - sz
	pm.scale_max = 1.0 + sz
	match str(o.get("shape_life", "")):
		"pop": pm.scale_curve = _curve([Vector2(0, 0.1), Vector2(0.2, 1.0), Vector2(1, 0.0)])
		"shrink": pm.scale_curve = _curve([Vector2(0, 1.0), Vector2(1, 0.15)])
		"grow": pm.scale_curve = _curve([Vector2(0, 0.4), Vector2(1, 1.4)])
		"swell": pm.scale_curve = _curve([Vector2(0, 0.3), Vector2(0.4, 1.0), Vector2(1, 1.8)])
	if float(o.get("grid", 1.0)) > 1.0:
		pm.anim_offset_max = 1.0
	if float(o.get("turb", 0.0)) > 0.0:
		pm.turbulence_enabled = true
		pm.turbulence_noise_scale = 1.8
		pm.turbulence_noise_strength = 1.2
		pm.turbulence_influence_min = 0.04 * float(o.turb)
		pm.turbulence_influence_max = 0.14 * float(o.turb)
	if bool(o.get("align", false)):
		pm.particle_flag_align_y = true
	pm.lifetime_randomness = float(o.get("rand", 0.3))
	pm.color_ramp = _ramp(col, str(o.get("fade", "")), float(o.get("alpha", 1.0)))
	_pms[k] = pm
	return pm

func _thin() -> float:
	return 0.45 if view.low_fx else 1.0

func burst(at: Vector3, col: Color, o: Dictionary) -> GPUParticles3D:
	# a one-shot puff of sprites at `at`. o: n, life, size, tex, core, and the process material's settings (_pm): shape
	# (sphere r / ring r inner h / box ext / point), dir, spread, vel [min, max], grav, damp, radial, orbit, angle, spin,
	# sizes, shape_life (pop / shrink / grow / swell), fade (hot / flicker / slow / late / dark), alpha, turb, align,
	# grid; explode (0..1, 1 = all at once); dur (a stream for dur seconds instead of a burst); parent (ride a node);
	# mesh ("rock": lit stone chips, "knife": a thin box along its flight; else a sprite quad)
	var p := GPUParticles3D.new()
	p.amount = maxi(1, int(ceil(float(o.get("n", 12)) * _thin())))
	p.lifetime = float(o.get("life", 0.7))
	p.one_shot = not o.has("dur")
	p.explosiveness = float(o.get("explode", 1.0)) if p.one_shot else float(o.get("explode", 0.0))
	p.randomness = 0.3
	p.fixed_fps = 30
	p.interpolate = true
	p.local_coords = bool(o.get("local", false))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var reach := float(o.get("reach", 8.0))
	p.visibility_aabb = AABB(Vector3(-reach, -reach * 0.5, -reach), Vector3(reach * 2.0, reach * 2.0, reach * 2.0))
	var po := o.duplicate()
	for k in ["n", "life", "size", "tex", "core", "explode", "dur", "parent", "mesh", "reach", "local", "tilt", "blend"]:
		po.erase(k)
	p.process_material = _pm(col, po)
	var size := float(o.get("size", 0.4))
	match str(o.get("mesh", "")):
		"rock":
			var bm := BoxMesh.new()
			bm.size = Vector3(size, size * 0.7, size * 0.85)
			if _rock_mat == null:
				_rock_mat = StandardMaterial3D.new()
				_rock_mat.albedo_color = Color(0.5, 0.45, 0.38)
				_rock_mat.vertex_color_use_as_albedo = true
				_rock_mat.roughness = 0.95
			bm.material = _rock_mat
			p.draw_pass_1 = bm
		"knife":
			var km := BoxMesh.new()
			km.size = Vector3(size * 0.12, size, size * 0.04)
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.vertex_color_use_as_albedo = true
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			km.material = m
			p.draw_pass_1 = km
		_:
			var q := QuadMesh.new()
			q.size = Vector2.ONE * size
			if str(o.get("blend", "")) == "mix":
				q.material = view._smoke_draw_mat()          # (smoke mixed over the scene, not added: dust, shadow, gun smoke)
				p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
			else:
				q.material = sprite_mat(str(o.get("tex", "dot")), float(o.get("core", 0.7)), Color.WHITE, float(o.get("grid", 1.0)))
			p.draw_pass_1 = q
	var parent: Node3D = o.get("parent", self)
	if parent != self:
		p.position = at
		parent.add_child(p)
	else:
		p.position = at
		add_child(p)
	if o.has("tilt"):
		p.basis = o.tilt
	p.restart()
	if o.has("dur"):
		var dur := float(o.dur)
		_live.append({"node":p, "t0":_time, "life":dur + p.lifetime + 0.3, "fn":func(n, u, age):
			if age >= dur and n.emitting:
				n.emitting = false})
	else:
		_live.append({"node":p, "t0":_time, "life":p.lifetime * (1.0 + float(o.get("rand", 0.3))) + 0.3, "fn":Callable()})
	return p

func flash(at: Vector3, col: Color, size: float, life := 0.35, nm := "dot", core := 0.8, flat := false, spin := 0.0) -> MeshInstance3D:
	# one sprite facing the camera (flat: lying on the ground), popping up and fading
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	mi.mesh = q
	var m := sprite_mat(nm, core, Color.WHITE, 1.0, flat, spin).duplicate() as ShaderMaterial
	m.set_shader_parameter("tint", col)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at
	if flat:
		mi.rotation.x = -PI * 0.5
	add_child(mi)
	_live.append({"node":mi, "t0":_time, "life":life, "fn":func(n, u, _age):
		var s: float = size * (0.35 + 0.65 * sqrt(minf(1.0, u * 4.0))) * (1.0 + 0.25 * u)
		n.scale = Vector3.ONE * s
		var c := col
		c.a = col.a * (1.0 - u * u)
		(n.material_override as ShaderMaterial).set_shader_parameter("tint", c)})
	return mi

# ----- ground -----
func _ground_mesh(c: Vector2, r: float, segs := 10) -> ArrayMesh:
	# a disc of 2r across, its vertices on the terrain (UV 0..1 over it)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := segs
	for j in n + 1:
		for i in n + 1:
			var u := float(i) / float(n)
			var v := float(j) / float(n)
			var p2 := c + Vector2((u - 0.5) * 2.0 * r, (v - 0.5) * 2.0 * r)
			st.set_uv(Vector2(u, v))
			st.add_vertex(Vector3(p2.x - c.x, Sim.height_at(p2) - Sim.height_at(c), p2.y - c.y))
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			st.add_index(a)
			st.add_index(a + n + 1)
			st.add_index(a + 1)
			st.add_index(a + 1)
			st.add_index(a + n + 1)
			st.add_index(a + n + 2)
	return st.commit()

static func _flat_mesh(r: float) -> ArrayMesh:
	# a flat disc of 2r across (for one that rides a hero)
	var k := "flat|%.2f" % r
	if _meshes.has(k):
		return _meshes[k]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in 2:
		for i in 2:
			st.set_uv(Vector2(float(i), float(j)))
			st.add_vertex(Vector3((float(i) - 0.5) * 2.0 * r, 0.0, (float(j) - 0.5) * 2.0 * r))
	st.add_index(0); st.add_index(2); st.add_index(1)
	st.add_index(1); st.add_index(2); st.add_index(3)
	_meshes[k] = st.commit()
	return _meshes[k]

func _ground_mat(col: Color, style: int, o: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = GROUND
	m.set_shader_parameter("color", col)
	m.set_shader_parameter("style", style)
	if o.has("tex"):
		m.set_shader_parameter("tex", tex(str(o.tex)))
	m.set_shader_parameter("spin", float(o.get("spin", 0.0)))
	m.set_shader_parameter("rim", float(o.get("rim", 0.8)))
	m.set_shader_parameter("energy", float(o.get("energy", 1.0)))
	m.set_shader_parameter("seed", randf() * 100.0)
	m.set_shader_parameter("fade", 0.0)
	m.set_shader_parameter("grow", 1.0)
	return m

func disc(c2: Vector2, col: Color, r: float, life: float, style := 0, o := {}) -> MeshInstance3D:
	# a ground disc for `life` seconds (life < 0: held by a _hold key, o.key, until let go): fades in over o.in (0.15),
	# out over o.out (0.3); o.grow: the lit radius runs out over that many seconds; o.up: above the ground (0.1)
	var mi := MeshInstance3D.new()
	mi.mesh = _flat_mesh(r) if bool(o.get("flat", false)) else _ground_mesh(c2, r, 10 if r > 3.0 else 6)
	mi.material_override = _ground_mat(col, style, o)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(c2.x, Sim.height_at(c2) + float(o.get("up", 0.1)), c2.y)
	add_child(mi)
	var t_in := float(o.get("in", 0.15))
	var t_out := float(o.get("out", 0.3))
	var t_grow := float(o.get("grow", 0.0))
	var mat := mi.material_override as ShaderMaterial
	var nodes := [mi]
	var mats := [mat]
	if float(o.get("scorch", 0.0)) > 0.0 and not view.low_fx:
		# the dark under it (mixed over the ground, just below the light)
		var dk := MeshInstance3D.new()
		dk.mesh = mi.mesh
		var dm := ShaderMaterial.new()
		dm.shader = SCORCH
		dm.set_shader_parameter("color", o.get("scorch_col", Color(0.06, 0.03, 0.01)))
		dm.set_shader_parameter("strength", float(o.scorch))
		dm.set_shader_parameter("seed", randf() * 100.0)
		dm.set_shader_parameter("fade", 0.0)
		dk.material_override = dm
		dk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dk.position = mi.position - Vector3(0, 0.03, 0)
		add_child(dk)
		nodes.append(dk)
		mats.append(dm)
	if life < 0.0:
		_hold(str(o.get("key", "disc%d" % mi.get_instance_id())), nodes, o.get("alive", Callable()), t_out, t_in, t_grow)
	else:
		var scorch_out := float(o.get("scorch_out", t_out))
		var dk_life := maxf(life, life - t_out + scorch_out)
		_live.append({"node":mi, "t0":_time, "life":life, "fn":func(_n, _u, age):
			var f: float = minf(1.0, age / t_in) * minf(1.0, (life - age) / t_out)
			mat.set_shader_parameter("fade", clampf(f, 0.0, 1.0))
			if t_grow > 0.0:
				mat.set_shader_parameter("grow", clampf(age / t_grow, 0.0, 1.0) * 1.08)})
		if nodes.size() > 1:
			var dm2: ShaderMaterial = mats[1]
			_live.append({"node":nodes[1], "t0":_time, "life":dk_life, "fn":func(_n, _u, age):
				var f: float = minf(1.0, age / t_in) * minf(1.0, (dk_life - age) / scorch_out)
				dm2.set_shader_parameter("fade", clampf(f, 0.0, 1.0))
				if t_grow > 0.0:
					dm2.set_shader_parameter("grow", clampf(age / t_grow, 0.0, 1.0) * 1.08)})
	return mi

func wave(c2: Vector2, col: Color, r0: float, r1: float, life: float, rim := 1.2, up := 0.12) -> MeshInstance3D:
	# a ring running out from r0 to r1 and fading (the rim style of the ground disc, scaled)
	var mi := MeshInstance3D.new()
	mi.mesh = _ground_mesh(c2, r1, 6)
	var mat := _ground_mat(col, 5, {"rim":rim})
	mat.set_shader_parameter("fade", 1.0)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(c2.x, Sim.height_at(c2) + up, c2.y)
	mi.scale = Vector3(maxf(0.01, r0 / r1), 1.0, maxf(0.01, r0 / r1))
	add_child(mi)
	_live.append({"node":mi, "t0":_time, "life":life, "fn":func(n, u, _age):
		var k: float = 1.0 - (1.0 - u) * (1.0 - u)
		var s: float = maxf(0.01, lerpf(r0, r1, k) / r1)
		n.scale = Vector3(s, 1.0, s)
		mat.set_shader_parameter("fade", 1.0 - u * u)})
	return mi

static func _fan_mesh(arc: float, segs := 12) -> ArrayMesh:
	# a sector of a unit disc, +Z ahead, arc radians either side: UV.y 0 at the apex, 1 at the rim; UV.x across
	var k := "fan|%.2f|%d" % [arc, segs]
	if _meshes.has(k):
		return _meshes[k]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 4
	for j in rings + 1:
		var rr := float(j) / float(rings)
		for i in segs + 1:
			var t := float(i) / float(segs)
			var a := -arc + 2.0 * arc * t
			st.set_uv(Vector2(t, rr))
			st.add_vertex(Vector3(sin(a) * rr, 0.0, cos(a) * rr))
	for j in rings:
		for i in segs:
			var a := j * (segs + 1) + i
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(a + segs + 1)
			st.add_index(a + 1)
			st.add_index(a + segs + 2)
			st.add_index(a + segs + 1)
	_meshes[k] = st.commit()
	return _meshes[k]

static func _tube_mesh(r0: float, r1: float, segs := 14) -> ArrayMesh:
	# a tube of unit height from r0 at the foot (UV.y 0) to r1 at the top (UV.y 1); UV.x round it
	var k := "tube|%.2f|%.2f|%d" % [r0, r1, segs]
	if _meshes.has(k):
		return _meshes[k]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := 3
	for j in rows + 1:
		var y := float(j) / float(rows)
		var rr := lerpf(r0, r1, y)
		for i in segs + 1:
			var a := TAU * float(i) / float(segs)
			st.set_uv(Vector2(float(i) / float(segs), y))
			st.add_vertex(Vector3(cos(a) * rr, y, sin(a) * rr))
	for j in rows:
		for i in segs:
			var a := j * (segs + 1) + i
			st.add_index(a)
			st.add_index(a + segs + 1)
			st.add_index(a + 1)
			st.add_index(a + 1)
			st.add_index(a + segs + 1)
			st.add_index(a + segs + 2)
	_meshes[k] = st.commit()
	return _meshes[k]

static func _sheet_mesh() -> ArrayMesh:
	# two crossed unit quads along +Z (UV.y along, UV.x across): a beam seen from any side
	var k := "sheet"
	if _meshes.has(k):
		return _meshes[k]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 0
	for plane in 2:
		var side := Vector3(1, 0, 0) if plane == 0 else Vector3(0, 1, 0)
		for j in 2:
			for i in 2:
				st.set_uv(Vector2(float(i), float(j)))
				st.add_vertex(side * (float(i) - 0.5) + Vector3(0, 0, float(j)))
		st.add_index(n); st.add_index(n + 2); st.add_index(n + 1)
		st.add_index(n + 1); st.add_index(n + 2); st.add_index(n + 3)
		n += 4
	_meshes[k] = st.commit()
	return _meshes[k]

func _beam_mat(col: Color, o: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = BEAM
	m.set_shader_parameter("color", col)
	m.set_shader_parameter("energy", float(o.get("energy", 1.0)))
	m.set_shader_parameter("speed", float(o.get("speed", 2.0)))
	m.set_shader_parameter("scale", float(o.get("scale", 3.0)))
	m.set_shader_parameter("fade_root", float(o.get("fade_root", 0.15)))
	m.set_shader_parameter("fade_end", float(o.get("fade_end", 0.4)))
	m.set_shader_parameter("side_fade", bool(o.get("side_fade", true)))
	m.set_shader_parameter("core", float(o.get("core", 0.4)))
	m.set_shader_parameter("seed", randf() * 100.0)
	m.set_shader_parameter("fade", 0.0)
	m.set_shader_parameter("grow", 1.0)
	return m

func _timed(mi: MeshInstance3D, mat: ShaderMaterial, life: float, o: Dictionary) -> void:
	var t_in := float(o.get("in", 0.08))
	var t_out := float(o.get("out", 0.35))
	var t_grow := float(o.get("grow", 0.0))
	if life < 0.0:
		_hold(str(o.get("key", "m%d" % mi.get_instance_id())), [mi], o.get("alive", Callable()), t_out, t_in, t_grow)
		return
	_live.append({"node":mi, "t0":_time, "life":life, "fn":func(_n, _u, age):
		mat.set_shader_parameter("fade", clampf(minf(1.0, age / t_in) * minf(1.0, (life - age) / t_out), 0.0, 1.0))
		if t_grow > 0.0:
			mat.set_shader_parameter("grow", clampf(age / t_grow, 0.0, 1.0) * 1.08)})

func pillar(at: Vector3, col: Color, r: float, h: float, life: float, o := {}) -> MeshInstance3D:
	# a column of light standing on `at`: r at the foot, o.top (r) at the top
	var mi := MeshInstance3D.new()
	mi.mesh = _tube_mesh(1.0, float(o.get("top", r)) / r)
	var oo := o.duplicate()
	oo["side_fade"] = false
	oo["fade_end"] = float(o.get("fade_end", 0.5))
	var mat := _beam_mat(col, oo)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at
	mi.scale = Vector3(r, h, r)
	add_child(mi)
	_timed(mi, mat, life, o)
	return mi

func fan(c2: Vector2, dir: Vector2, col: Color, r: float, arc: float, life: float, o := {}) -> MeshInstance3D:
	# a cone of light on the ground ahead of c2 along dir, r long, arc radians either side
	var mi := MeshInstance3D.new()
	mi.mesh = _fan_mesh(arc)
	var oo := o.duplicate()
	oo["fade_root"] = float(o.get("fade_root", 0.1))
	var mat := _beam_mat(col, oo)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(c2.x, Sim.height_at(c2) + float(o.get("up", 0.15)), c2.y)
	mi.rotation.y = Sim.angle_of(dir)
	mi.scale = Vector3(r, 1.0, r)
	add_child(mi)
	_timed(mi, mat, life, o)
	return mi

func beam(from: Vector3, to: Vector3, col: Color, w: float, life: float, o := {}) -> MeshInstance3D:
	# a sheet of light between two points
	var mi := MeshInstance3D.new()
	mi.mesh = _sheet_mesh()
	var mat := _beam_mat(col, o)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var len := maxf(0.05, from.distance_to(to))
	mi.position = from
	if len > 0.06:
		mi.look_at_from_position(from, to, Vector3.UP if absf((to - from).normalized().y) < 0.95 else Vector3.RIGHT)
		mi.rotate_object_local(Vector3.UP, PI)            # (look_at points -Z at the target; the sheet runs along +Z)
	mi.scale = Vector3(w, w, len)
	add_child(mi)
	_timed(mi, mat, life, o)
	return mi

func shell(parent: Node3D, col: Color, r: float, h: float, style: int, life: float, o := {}) -> MeshInstance3D:
	# a bubble round a hero (parent: his root; o.y its centre, 1.0)
	if parent == null:
		return null
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = h
	sm.radial_segments = 20
	sm.rings = 10
	mi.mesh = sm
	var mat := ShaderMaterial.new()
	mat.shader = SHELL
	mat.set_shader_parameter("color", col)
	mat.set_shader_parameter("style", style)
	mat.set_shader_parameter("energy", float(o.get("energy", 1.0)))
	mat.set_shader_parameter("speed", float(o.get("speed", 1.0)))
	mat.set_shader_parameter("seed", randf() * 100.0)
	mat.set_shader_parameter("fade", 0.0)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, float(o.get("y", 1.0)), 0)
	parent.add_child(mi)
	_timed(mi, mat, life, o)
	return mi

func bolt(from: Vector3, to: Vector3, col: Color, life: float, jag: float, w := 0.14, branches := 1) -> void:
	# lightning: a white core and a glow round it, kinked every metre or so, a branch or two off it; thinning out
	var n := maxi(2, int(from.distance_to(to) / 1.1))
	var prev := from
	var pts := [from]
	for i in n:
		var t := float(i + 1) / float(n)
		var nxt := from.lerp(to, t)
		if i < n - 1:
			nxt += Vector3(randf_range(-jag, jag), randf_range(-jag, jag) * 0.6, randf_range(-jag, jag)) * 0.5
		pts.append(nxt)
		prev = nxt
	_bolt_path(pts, col, life, w)
	if not view.low_fx:
		for b in branches:
			var i0 := randi_range(1, maxi(1, pts.size() - 2))
			var p0: Vector3 = pts[i0]
			var d: Vector3 = (to - from).normalized().rotated(Vector3.UP, randf_range(-1.2, 1.2)) * randf_range(0.8, 1.8)
			d.y += randf_range(-0.6, 0.2)
			_bolt_path([p0, p0 + d * 0.5 + Vector3(randf_range(-jag, jag), 0, randf_range(-jag, jag)) * 0.3, p0 + d], col, life * 0.8, w * 0.6)

static func _box_mesh() -> BoxMesh:
	if not _meshes.has("box"):
		var bm := BoxMesh.new()
		bm.size = Vector3(1.0, 1.0, 1.0)
		_meshes["box"] = bm
	return _meshes["box"]

static func _flat_mat(col: Color) -> StandardMaterial3D:
	var k := "flat|" + col.to_html()
	if not _mats.has(k):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = col
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mats[k] = m
	return _mats[k]

func _bolt_path(pts: Array, col: Color, life: float, w: float) -> void:
	for i in range(pts.size() - 1):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var len := maxf(0.05, a.distance_to(b))
		var mid := (a + b) * 0.5
		for layer in 2:
			var seg := MeshInstance3D.new()
			seg.mesh = _box_mesh()
			seg.material_override = _flat_mat(Color(1, 1, 1, 0.95) if layer == 0 else Color(col, 0.55))
			seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(seg)
			seg.position = mid
			if len > 0.06:
				seg.look_at_from_position(mid, b, Vector3.UP if absf((b - a).normalized().y) < 0.95 else Vector3.RIGHT)
			var ww := w * (0.45 if layer == 0 else 1.6)
			seg.scale = Vector3(ww, ww, len)
			_live.append({"node":seg, "t0":_time, "life":life, "fn":func(n, u, _age):
				var k: float = maxf(0.05, 1.0 - u * u)
				n.scale = Vector3(ww * k, ww * k, len)})

func trail(parent: Node3D, col: Color, dur: float, nm := "streak", o := {}) -> GPUParticles3D:
	# sprites left behind a moving thing (parent) for dur seconds
	var oo := {"n":int(o.get("n", 40)), "life":float(o.get("life", 0.45)), "size":float(o.get("size", 0.5)), "tex":nm, "core":0.7,
		"shape":"sphere", "r":float(o.get("r", 0.3)), "vel":[0.2, 0.8], "spread":180.0, "fade":str(o.get("fade", "")),
		"shape_life":str(o.get("shape_life", "shrink")), "dur":dur, "parent":parent, "angle":180.0, "spin":40.0,
		"grav":o.get("grav", Vector3(0, 0.6, 0)), "explode":0.0, "rand":0.2}
	if o.has("alpha"):
		oo["alpha"] = o.alpha
	if o.has("blend"):
		oo["blend"] = o.blend
	return burst(Vector3(0, float(o.get("y", 0.9)), 0), col, oo)

func mover(node: Node3D, from: Vector3, to: Vector3, dur: float, arc: float, spin := 0.0, done := Callable()) -> void:
	# carries a node from one point to another on an arc (arc: its height at the top), spinning; done() at the end
	add_child(node)
	node.position = from
	_live.append({"node":node, "t0":_time, "life":dur, "fn":func(n, u, _age):
		n.position = from.lerp(to, u) + Vector3(0, arc * 4.0 * u * (1.0 - u), 0)
		if spin != 0.0:
			n.rotation.x += spin
		if u >= 0.999 and done.is_valid():
			done.call()})

func shake(k: float, near: Vector2 = Vector2.INF, r := 12.0) -> void:
	if near == Vector2.INF:
		view.shake(k)
	else:
		view._shake_near(near, r, k)

# ----- what lasts -----
func _hold(key: String, nodes: Array, alive: Callable, t_out := 0.3, t_in := 0.1, t_grow := 0.0) -> void:
	# nodes kept until alive() is false (or until release(key)); their shader "fade" eased in and out
	release(key, true)
	_holds[key] = {"nodes":nodes, "alive":alive, "t0":_time, "out":t_out, "in":t_in, "grow":t_grow, "gone":-1.0}

func holding(key: String) -> bool:
	return _holds.has(key) and float(_holds[key].gone) < 0.0

func release(key: String, now := false) -> void:
	if not _holds.has(key):
		return
	var h: Dictionary = _holds[key]
	if now:
		for n in h.nodes:
			if is_instance_valid(n):
				(n as Node).queue_free()
		_holds.erase(key)
	elif float(h.gone) < 0.0:
		h.gone = _time
		for n in h.nodes:
			if is_instance_valid(n) and n is GPUParticles3D:
				(n as GPUParticles3D).emitting = false

func _step_holds() -> void:
	for key in _holds.keys():
		var h: Dictionary = _holds[key]
		if float(h.gone) < 0.0 and h.alive is Callable and (h.alive as Callable).is_valid() and not bool((h.alive as Callable).call()):
			release(key)
		var f := 1.0
		var age := _time - float(h.t0)
		if float(h.gone) >= 0.0:
			f = 1.0 - clampf((_time - float(h.gone)) / maxf(0.01, float(h.out)), 0.0, 1.0)
			if f <= 0.0:
				for n in h.nodes:
					if is_instance_valid(n):
						(n as Node).queue_free()
				_holds.erase(key)
				continue
		f *= clampf(age / maxf(0.01, float(h["in"])), 0.0, 1.0)
		for n in h.nodes:
			if is_instance_valid(n) and n is MeshInstance3D and (n as MeshInstance3D).material_override is ShaderMaterial:
				var m := (n as MeshInstance3D).material_override as ShaderMaterial
				m.set_shader_parameter("fade", f)
				if float(h.grow) > 0.0:
					m.set_shader_parameter("grow", clampf(age / float(h.grow), 0.0, 1.0) * 1.08)

func step(dt: float) -> void:
	_time += dt
	for i in range(_live.size() - 1, -1, -1):
		var e: Dictionary = _live[i]
		var n = e.node
		if not is_instance_valid(n):
			_live.remove_at(i)
			continue
		var age := _time - float(e.t0)
		if age > float(e.life):
			n.queue_free()
			_live.remove_at(i)
			continue
		if e.fn is Callable and (e.fn as Callable).is_valid():
			(e.fn as Callable).call(n, age / maxf(0.001, float(e.life)), age)
	_step_holds()

# ---------- handy ----------
func _g(p2: Vector2, up := 0.1) -> Vector3:
	return Vector3(p2.x, Sim.height_at(p2) + up, p2.y)

func _unit_pos(id: String) -> Vector2:
	var u: Dictionary = view.sim.by_id.get(id, {})
	return u.pos if not u.is_empty() else Vector2.INF

func _root(id: String) -> Node3D:
	var a: Dictionary = view.actors.get(id, {})
	return a.root if not a.is_empty() and is_instance_valid(a.root) else null

func _alive_until(id: String, key: String) -> Callable:
	# true while the sim says the unit's `key` time is ahead
	var sim = view.sim
	return func():
		var u: Dictionary = sim.by_id.get(id, {})
		return not u.is_empty() and sim.alive(u) and float(sim.time) < float(u.get(key, -1.0))

func _alive_while(id: String, test: Callable) -> Callable:
	var sim = view.sim
	return func():
		var u: Dictionary = sim.by_id.get(id, {})
		return not u.is_empty() and sim.alive(u) and bool(test.call(u))

func _sparkles(at: Vector3, col: Color, n: int, r: float, h: float, life := 0.9, nm := "sparkle") -> void:
	burst(at, col, {"n":n, "life":life, "size":0.35, "tex":nm, "core":0.9, "shape":"sphere", "r":r, "vel":[0.3, 1.2],
		"grav":Vector3(0, h, 0), "shape_life":"pop", "fade":"slow", "angle":180.0, "spin":60.0})

func _dust(at: Vector3, col: Color, n: int, r: float, size := 1.4, life := 1.1, vel := 2.5) -> void:
	burst(at, col, {"n":n, "life":life, "size":size * 0.8, "tex":"smoke", "core":0.0, "blend":"mix", "shape":"ring", "r":r, "inner":0.3, "h":0.2,
		"dir":Vector3.UP, "spread":60.0, "vel":[vel * 0.4, vel], "damp":2.0, "grav":Vector3(0, 0.3, 0), "shape_life":"swell",
		"fade":"late", "alpha":0.55, "angle":180.0, "spin":30.0, "rand":0.4})

func _embers(at: Vector3, col: Color, n: int, r: float, up := 2.5, life := 1.3) -> void:
	burst(at, col, {"n":n, "life":life, "size":0.14, "tex":"dot", "core":1.0, "shape":"sphere", "r":r, "vel":[0.5, 2.0],
		"grav":Vector3(0, up, 0), "turb":1.2, "fade":"hot", "shape_life":"shrink", "damp":0.5})

func _flames(at: Vector3, col: Color, n: int, r: float, life := 0.7, size := 0.9, dur := -1.0, up := 3.0) -> GPUParticles3D:
	var o := {"n":n, "life":life, "size":size, "tex":"flame", "core":0.7, "shape":"ring", "r":r, "inner":0.2, "h":0.3,
		"dir":Vector3.UP, "spread":25.0, "vel":[1.0, 2.5], "grav":Vector3(0, up, 0), "shape_life":"shrink", "fade":"hot",
		"angle":12.0, "spin":20.0, "damp":1.0}
	if dur > 0.0:
		o["dur"] = dur
	return burst(at, col, o)

func _rocks(at: Vector3, n: int, r: float, size := 0.3, vel := 6.0, life := 1.2) -> void:
	burst(at, Color(0.55, 0.5, 0.42), {"n":n, "life":life, "size":size, "mesh":"rock", "shape":"sphere", "r":r,
		"dir":Vector3.UP, "spread":55.0, "vel":[vel * 0.4, vel], "grav":Vector3(0, -14.0, 0), "angle":180.0, "spin":400.0,
		"fade":"late", "sizes":0.5, "rand":0.3})

func _shards(at: Vector3, col: Color, dir: Vector2, n: int, arc: float, speed: float, reach: float) -> void:
	# knives (thin glints along their flight) thrown in a fan
	var d3 := Vector3(dir.x, 0.0, dir.y)
	burst(at, col, {"n":n, "life":reach / speed, "size":0.7, "mesh":"knife", "shape":"point", "dir":d3,
		"spread":rad_to_deg(arc), "vel":[speed * 0.8, speed], "align":true, "fade":"late", "rand":0.1, "sizes":0.2})

func _col(hid: String, i := 0) -> Color:
	var c: Array = HERO_COL.get(hid, ["#ffffff", "#ffffff"])
	return Color(str(c[i]))

# ======================================================================================================================
# the casts
# ======================================================================================================================
func cast(sp: String, e: Dictionary, a: Dictionary, at: Vector3, hid: String) -> void:
	# a W or an E (moba_kits.gd "spell"; the new heroes' Q too), at: the caster's place now
	var p2 := Vector2(at.x, at.z)
	var root := _root(str(e.get("id", "")))
	var id := str(e.get("id", ""))
	var c1 := _col(hid, 0)
	var c2 := _col(hid, 1)
	var dir: Vector2 = (e.get("dir", Vector2(0, 1)) as Vector2).normalized()
	match sp:
		# ---- knight ----
		"bash":
			_dash_fx(id, Color("#bcd8ff"), "streak")
			fan(p2, dir, Color("#dce8ff"), 3.0, 0.5, 0.3, {"speed":8.0, "core":0.6})
			flash(at + Vector3(0, 1.1, 0) + Vector3(dir.x, 0, dir.y) * 0.8, Color("#ffffff"), 1.6, 0.25, "ring")
			_dust(at, Color("#d8cfb8"), 8, 0.6)
		"rally":
			var r := float(e.get("r", 7.0))
			disc(p2, Color("#ffd65a"), r, 1.2, 1, {"tex":"rays", "spin":1.2, "grow":0.5, "out":0.5})
			wave(p2, Color("#ffe9a6"), 0.5, r, 0.6)
			pillar(at, Color("#ffd65a"), 0.35, 4.0, 0.7, {"top":0.6, "speed":3.0, "out":0.4, "core":0.15, "energy":0.7})
			for o in view.sim.units:
				if int(o.team) == int(e.get("team", -1)) and bool(o.get("hero", false)) and view.sim.alive(o) \
						and (o.pos as Vector2).distance_to(p2) <= r:
					var ro := _root(str(o.id))
					if ro != null:
						_sparkles(ro.position + Vector3(0, 0.5, 0), Color("#ffe9a6"), 10, 0.5, 2.0, 1.0, "star")
						_shield_style[str(o.id)] = {"col":Color("#ffd65a"), "style":0}
			shake(0.1, p2)
		# ---- crusader ----
		"block":
			_block_up(id, Color("#ffe9a6"))
		"consecrate":
			var r := float(e.get("r", 4.0))
			pillar(at, Color("#ffe9a6"), 0.25, 5.0, 0.8, {"top":0.5, "speed":4.0, "out":0.5, "core":0.15, "energy":0.6})
			wave(p2, Color("#ffe9a6"), 0.3, r, 0.6)
			flash(at + Vector3(0, 2.4, 0), Color("#fff1a8"), 1.8, 0.4, "star")
			_sparkles(at + Vector3(0, 0.3, 0), Color("#fff6d8"), 16, r * 0.6, 1.5, 1.2, "sparkle")
		# ---- barbarian ----
		"leap":
			_dust(at, Color("#d8c8a8"), 10, 0.7, 1.2, 0.9, 3.0)
			_dash_fx(id, Color("#ffb04a"), "streak", 0.6)
		"bloodlust":
			shell(root, Color("#ff3a2a"), 1.1, 2.4, 2, 0.5, {"energy":1.3, "speed":3.0})
			_embers(at + Vector3(0, 0.8, 0), Color("#ff6a2a"), 24, 0.8, 3.5)
			disc(p2, Color("#ff3a2a"), 1.6, 0.6, 2, {"out":0.3})
			shake(0.1, p2)
		# ---- berserker ----
		"charge":
			_dash_fx(id, Color("#ff4a2a"), "flame", 0.7)
			fan(p2, dir, Color("#ff6a3a"), 3.5, 0.35, 0.3, {"speed":10.0, "core":0.7})
			_dust(at, Color("#c8b098"), 10, 0.6, 1.3, 0.9, 3.5)
			shake(0.1, p2)
		"frenzy":
			wave(p2, Color("#ff2a2a"), 0.3, 2.6, 0.45, 1.5)
			shell(root, Color("#ff2a2a"), 1.0, 2.3, 2, 0.6, {"energy":1.4, "speed":4.0})
			burst(at + Vector3(0, 1.0, 0), Color("#ff3a3a"), {"n":18, "life":0.6, "size":0.5, "tex":"crescent", "core":0.6,
				"shape":"sphere", "r":0.3, "vel":[3.0, 6.0], "damp":4.0, "angle":180.0, "spin":500.0, "fade":"hot", "shape_life":"shrink"})
			_sparkles(at + Vector3(0, 0.6, 0), Color("#7dff6a"), 8, 0.5, 2.0, 0.9)      # (the heal)
		# ---- rogue ----
		"caltrops":
			var c3: Vector2 = e.get("c", p2)
			var r := float(e.get("r", 3.0))
			burst(at + Vector3(0, 1.2, 0), Color("#d8d8d8"), {"n":22, "life":0.8, "size":0.26, "tex":"shard", "core":0.3,
				"shape":"point", "dir":(Vector3(c3.x, 0, c3.y) - at + Vector3(0, 4.0, 0)).normalized(), "spread":18.0,
				"vel":[7.0, 10.0], "grav":Vector3(0, -12.0, 0), "angle":180.0, "spin":600.0, "fade":"late", "rand":0.2})
			flash(at + Vector3(0, 1.3, 0), Color("#ffffff"), 0.8, 0.2, "sparkle")
		"poison":
			burst(at + Vector3(0, 1.1, 0), Color("#7dff6a"), {"n":22, "life":0.8, "size":0.2, "tex":"dot", "core":0.8, "shape":"sphere",
				"r":0.5, "vel":[0.3, 1.5], "grav":Vector3(0, -5.0, 0), "fade":"slow", "shape_life":"shrink"})
			shell(root, Color("#5dff4a"), 0.9, 2.2, 0, 0.5, {"energy":1.2})
			if root != null:
				_hold("poison:" + id, [burst(Vector3(0, 1.0, 0), Color("#7dff6a"), {"n":24, "life":0.7, "size":0.22, "tex":"dot", "core":0.8,
					"shape":"sphere", "r":0.45, "vel":[0.1, 0.6], "grav":Vector3(0, -2.5, 0), "fade":"slow", "dur":30.0, "parent":root,
					"explode":0.0})], _alive_while(id, func(uu): return int(uu.get("poison_n", 0)) > 0))
		# ---- assassin ----
		"shadowstep":
			var from: Vector2 = e.get("from", p2)
			var to: Vector2 = e.get("to", p2)
			burst(_g(from, 0.9), Color("#2a1a4a"), {"n":12, "life":0.8, "size":1.3, "tex":"smoke", "core":0.0, "blend":"mix", "shape":"sphere", "r":0.4,
				"vel":[0.5, 1.5], "shape_life":"swell", "fade":"late", "alpha":0.7, "angle":180.0, "spin":40.0})
			_sparkles(_g(from, 0.6), Color("#8a5bff"), 8, 0.4, 1.5, 0.7)
			var fv := _g(from, 1.0)
			var tv := _g(to, 1.0)
			beam(fv, tv, Color("#8a5bff"), 0.5, 0.25, {"speed":12.0, "core":0.5, "out":0.2})
			flash(tv + Vector3(0, 0.3, 0), Color("#d8c8ff"), 2.2, 0.3, "crescent")
			burst(tv, Color("#2a1a4a"), {"n":10, "life":0.7, "size":1.2, "tex":"smoke", "core":0.0, "blend":"mix", "shape":"sphere", "r":0.4,
				"vel":[0.5, 1.5], "shape_life":"swell", "fade":"late", "alpha":0.6, "angle":180.0, "spin":40.0})
		"knives":
			var r := float(e.get("r", 5.5))
			var arc := float(e.get("arc", 0.7))
			fan(p2, dir, Color("#8a5bff"), r, arc, 0.35, {"speed":9.0, "core":0.3, "fade_end":0.6})
			_shards(at + Vector3(0, 1.1, 0), Color("#e8e0ff"), dir, 12, arc, 16.0, r)
			flash(at + Vector3(0, 1.1, 0), Color("#d8c8ff"), 1.2, 0.2, "sparkle")
		"feint":
			_dash_fx(id, Color("#c9b8ff"), "streak", 0.3)
			burst(at + Vector3(0, 1.0, 0), Color("#8a5bff"), {"n":14, "life":0.6, "size":0.3, "tex":"sparkle", "core":0.9, "shape":"sphere",
				"r":1.2, "radial":-4.0, "vel":[0.0, 0.3], "fade":"slow", "shape_life":"shrink"})
			burst(at + Vector3(0, 0.8, 0), Color("#3a2a5a"), {"n":8, "life":0.7, "size":1.2, "tex":"smoke", "core":0.0, "blend":"mix", "shape":"sphere", "r":0.4,
				"vel":[0.3, 1.0], "shape_life":"swell", "fade":"late", "alpha":0.6, "angle":180.0, "spin":40.0})
		# ---- ranger ----
		"tumble":
			_dash_fx(id, Color("#d8c8a8"), "smoke", 0.4)
			burst(at + Vector3(0, 0.6, 0), Color("#8fe36a"), {"n":8, "life":1.2, "size":0.3, "tex":"leaf", "core":0.3, "shape":"sphere", "r":0.5,
				"vel":[1.0, 2.5], "grav":Vector3(0, -1.0, 0), "turb":1.0, "angle":180.0, "spin":200.0, "fade":"slow"})
		"snare":
			var tip := at + Vector3(dir.x, 0.0, dir.y) * 0.8 + Vector3(0, 1.2, 0)
			flash(tip, Color("#e8ffd0"), 1.1, 0.2, "sparkle")
			beam(tip, tip + Vector3(dir.x, 0.0, dir.y) * 4.0, Color("#8fe36a"), 0.35, 0.3, {"speed":14.0, "core":0.5, "fade_end":0.7})
			burst(tip, Color("#6fbf3a"), {"n":10, "life":0.6, "size":0.26, "tex":"leaf", "core":0.3, "shape":"point", "dir":Vector3(dir.x, 0.2, dir.y),
				"spread":25.0, "vel":[4.0, 8.0], "damp":3.0, "angle":180.0, "spin":300.0, "fade":"slow"})
		# ---- sniper ----
		"trap":
			flash(at + Vector3(0, 0.3, 0), Color("#ffffff"), 0.9, 0.25, "sparkle")
			burst(at + Vector3(0, 0.2, 0), Color("#d8d0c0"), {"n":8, "life":0.5, "size":0.14, "tex":"dot", "core":1.0, "shape":"sphere", "r":0.3,
				"vel":[1.0, 3.0], "grav":Vector3(0, -8.0, 0), "fade":"hot"})
		"mark":
			var tid := str(e.get("target", ""))
			var tr := _root(tid)
			if tr != null:
				var tp: Vector3 = tr.position
				beam(at + Vector3(0, 1.4, 0), tp + Vector3(0, 1.3, 0), Color("#ff4a4a"), 0.25, 0.3, {"speed":16.0, "core":0.6, "fade_end":0.2})
				flash(tp + Vector3(0, 2.6, 0), Color("#ff4a4a"), 1.4, 0.5, "ring")
				flash(tp + Vector3(0, 2.6, 0), Color("#ffffff"), 0.6, 0.4, "sparkle")
				_amp_style[tid] = {"col":Color("#ff4a4a"), "tex":"rays", "spin":2.5}
		# ---- mage ----
		"pillar":
			var c3: Vector2 = e.get("c", p2)
			_sparkles(at + Vector3(0, 1.2, 0), Color("#ffd24a"), 8, 0.4, 1.0, 0.5)
			beam(at + Vector3(0, 1.3, 0), _g(c3, 0.3), Color("#ff8a3a"), 0.3, 0.35, {"speed":10.0, "core":0.4})
		"blink":
			var from: Vector2 = e.get("from", p2)
			var to: Vector2 = e.get("to", p2)
			var fv := _g(from, 1.0)
			var tv := _g(to, 1.0)
			burst(fv, Color("#8fc8ff"), {"n":16, "life":0.5, "size":0.3, "tex":"sparkle", "core":0.9, "shape":"sphere", "r":1.3,
				"radial":-6.0, "vel":[0.0, 0.2], "fade":"slow", "shape_life":"shrink"})
			flash(fv, Color("#ffffff"), 1.6, 0.25, "ring")
			beam(fv, tv, Color("#8fc8ff"), 0.6, 0.3, {"speed":14.0, "core":0.6, "out":0.25})
			flash(tv, Color("#dff0ff"), 2.0, 0.3, "star")
			_sparkles(tv - Vector3(0, 0.5, 0), Color("#8fc8ff"), 14, 0.4, 2.0, 0.8)
			wave(to, Color("#8fc8ff"), 0.2, 2.2, 0.4)
		# ---- archmage ----
		"missiles":
			flash(at + Vector3(0, 1.3, 0), Color("#c070ff"), 1.4, 0.3, "runes", 0.6, false, 3.0)
			_sparkles(at + Vector3(0, 1.2, 0), Color("#ff6ad0"), 10, 0.4, 1.0, 0.6)
		"manashield":
			burst(at + Vector3(0, 1.0, 0), Color("#7fb8ff"), {"n":18, "life":0.6, "size":0.3, "tex":"runes", "grid":2.0, "core":0.6,
				"shape":"sphere", "r":1.6, "radial":-4.0, "vel":[0.0, 0.3], "fade":"slow", "shape_life":"shrink", "angle":30.0})
			flash(at + Vector3(0, 1.0, 0), Color("#dff0ff"), 2.4, 0.3, "ring")
			_shield_style[id] = {"col":Color("#7fb8ff"), "style":0}
		# ---- priest ----
		"holylight":
			var tid := str(e.get("target", ""))
			var tr := _root(tid)
			if tr != null:
				var tp: Vector3 = tr.position
				pillar(tp, Color("#ffe9a6"), 0.4, 6.0, 0.9, {"top":0.6, "speed":4.0, "out":0.5, "core":0.2, "energy":0.75})
				disc(Vector2(tp.x, tp.z), Color("#fff1a8"), 1.8, 0.9, 1, {"tex":"rays", "spin":1.5, "out":0.4, "energy":0.8})
				burst(tp + Vector3(0, 3.0, 0), Color("#fff6d8"), {"n":20, "life":1.0, "size":0.3, "tex":"sparkle", "core":0.9,
					"shape":"box", "ext":Vector3(0.8, 0.1, 0.8), "dir":Vector3.DOWN, "spread":10.0, "vel":[2.0, 4.0], "fade":"slow",
					"shape_life":"pop", "angle":180.0})
				flash(tp + Vector3(0, 1.3, 0), Color("#fff6d8"), 1.6, 0.35, "star")
		"dazzle":
			var r := float(e.get("r", 4.5))
			flash(at + Vector3(0, 1.4, 0), Color("#ffffff"), 4.5, 0.3, "star", 1.0)
			flash(at + Vector3(0, 1.4, 0), Color("#fff1a8"), 3.0, 0.5, "rays", 0.9)
			wave(p2, Color("#ffffff"), 0.3, r, 0.4, 1.5)
			burst(at + Vector3(0, 1.3, 0), Color("#ffffff"), {"n":24, "life":0.6, "size":0.4, "tex":"sparkle", "core":1.0, "shape":"point",
				"vel":[6.0, 11.0], "damp":6.0, "fade":"hot", "shape_life":"shrink", "angle":180.0, "spin":200.0})
		# ---- necromancer ----
		"boneshield":
			var tid := str(e.get("target", ""))
			var tr := _root(tid)
			if tr != null:
				burst(tr.position + Vector3(0, 1.0, 0), Color("#e8e0c8"), {"n":14, "life":0.7, "size":0.3, "tex":"shard", "core":0.2,
					"shape":"sphere", "r":1.4, "radial":-3.0, "orbit":1.0, "vel":[0.0, 0.3], "fade":"slow", "angle":180.0, "spin":200.0})
				_sparkles(tr.position + Vector3(0, 0.6, 0), Color("#7dff8a"), 8, 0.5, 1.5, 0.7)
				_shield_style[tid] = {"col":Color("#d8d0b8"), "style":1}
		"curse":
			var tid := str(e.get("target", ""))
			var tr := _root(tid)
			if tr != null:
				var tp: Vector3 = tr.position
				beam(at + Vector3(0, 1.4, 0), tp + Vector3(0, 1.2, 0), Color("#b04aff"), 0.45, 0.35, {"speed":8.0, "core":0.3})
				burst(tp + Vector3(0, 0.9, 0), Color("#4a1a6a"), {"n":12, "life":1.0, "size":1.2, "tex":"smoke", "core":0.0, "blend":"mix", "shape":"sphere",
					"r":0.5, "vel":[0.3, 1.0], "shape_life":"swell", "fade":"late", "alpha":0.7, "angle":180.0, "spin":40.0})
				burst(tp + Vector3(0, 2.2, 0), Color("#7dff8a"), {"n":10, "life":1.0, "size":0.3, "tex":"runes", "grid":2.0, "core":0.5,
					"shape":"sphere", "r":0.5, "vel":[0.1, 0.4], "grav":Vector3(0, -2.0, 0), "fade":"slow", "angle":30.0})
				_amp_style[tid] = {"col":Color("#b04aff"), "tex":"runes", "spin":-1.2}
		# ---- golem ----
		"boulder":
			_dust(at + Vector3(dir.x, 0, dir.y) * 0.5, Color("#c8b89a"), 8, 0.5, 1.0, 0.8, 2.0)
			_rocks(at + Vector3(0, 1.4, 0), 6, 0.3, 0.16, 4.0, 0.9)
		"stoneskin":
			_rocks(at + Vector3(0, 0.9, 0), 10, 0.6, 0.18, 3.0, 1.0)
			_dust(at, Color("#c8b8a0"), 8, 0.6, 1.2, 0.9, 2.0)
			disc(p2, Color("#c8b48a"), 1.8, 0.8, 1, {"tex":"cracks", "out":0.4})
			_skin_style[id] = {"col":Color("#b8b2a4")}
		"quake":
			var r := float(e.get("r", 4.0))
			disc(p2, Color("#ffb04a"), r, 1.2, 1, {"tex":"cracks", "grow":0.25, "out":0.6, "energy":1.2, "scorch":0.35, "scorch_out":2.5, "scorch_col":Color(0.12, 0.09, 0.05)})
			wave(p2, Color("#c8b48a"), 0.4, r + 0.5, 0.5)
			_rocks(at + Vector3(0, 0.3, 0), 18, r * 0.5, 0.26, 7.0)
			_dust(at, Color("#c8b89a"), 16, r * 0.6, 1.8, 1.3, 3.0)
			view.shockwave(at, r)
			shake(0.3, p2, 10.0)
		# ---- dragoon ----
		"sweep":
			var r := float(e.get("r", 3.8))
			var arc := float(e.get("arc", 1.05))
			fan(p2, dir, Color("#ff7a3a"), r, arc, 0.3, {"speed":12.0, "core":0.6, "fade_end":0.3, "up":0.9})
			flash(at + Vector3(dir.x, 0, dir.y) * r * 0.5 + Vector3(0, 1.0, 0), Color("#ffd890"), r * 1.3, 0.25, "crescent", 0.7, true, 6.0)
			_sparkles(at + Vector3(dir.x, 0, dir.y) * r * 0.5 + Vector3(0, 0.9, 0), Color("#ffd890"), 10, r * 0.4, 1.0, 0.5)
		"impale":
			var len := float(e.get("len", 6.0))
			var tip := at + Vector3(0, 1.0, 0)
			var far := tip + Vector3(dir.x, 0, dir.y) * len
			beam(tip, far, Color("#ff7a3a"), 0.5, 0.35, {"speed":16.0, "core":0.7, "fade_end":0.15, "in":0.03})
			flash(far, Color("#ffd890"), 1.4, 0.3, "sparkle")
			burst(far, Color("#ffd890"), {"n":16, "life":0.5, "size":0.3, "tex":"streak", "core":0.7, "shape":"point", "dir":-Vector3(dir.x, 0, dir.y),
				"spread":8.0, "vel":[len * 1.8, len * 2.2], "fade":"slow", "align":false, "angle":0.0})    # (the pull, back to him)
		"vault":
			_dust(at, Color("#d8c8a8"), 8, 0.6, 1.2, 0.9, 3.0)
			_dash_fx(id, Color("#ffcf8a"), "streak", 0.5)
		# ---- duelist ----
		"thrust":
			var far := at + Vector3(dir.x, 0, dir.y) * 5.0 + Vector3(0, 1.0, 0)
			beam(at + Vector3(0, 1.0, 0), far, Color("#ffffff"), 0.25, 0.3, {"speed":20.0, "core":0.8, "fade_end":0.1, "in":0.02})
			_dash_fx(id, Color("#ffe27a"), "streak", 0.35)
			flash(at + Vector3(dir.x, 0, dir.y) * 1.2 + Vector3(0, 1.1, 0), Color("#ffffff"), 1.0, 0.2, "sparkle")
		"riposte":
			shell(root, Color("#ffe27a"), 1.0, 2.3, 0, 0.4, {"energy":1.3})
			flash(at + Vector3(0, 1.2, 0), Color("#fff4c0"), 1.6, 0.3, "ring")
		"feint_":
			pass
		# ---- stormcaller ----
		"chain":
			var pts: Array = e.get("pts", [])
			var prev := at + Vector3(0, 1.4, 0)
			flash(prev, Color("#e8f4ff"), 1.4, 0.25, "sparkle")
			for i in pts.size():
				var pb := _g(pts[i], 1.1)
				if i > 0:
					prev = _g(pts[i - 1], 1.1)
				bolt(prev, pb, Color("#7fb8ff"), 0.4, 0.6, 0.16, 1)
				_zap_hit(pb, Color("#7fb8ff"), 0.8)
		"static":
			var c3: Vector2 = e.get("c", p2)
			bolt(_g(c3, 9.0) + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)), _g(c3, 0.3), Color("#6fb4ff"), 0.3, 1.4, 0.2, 2)
			_zap_hit(_g(c3, 0.4), Color("#9fd4ff"), 1.2)
		"gust":
			var r := float(e.get("r", 5.0))
			var arc := float(e.get("arc", 0.8))
			fan(p2, dir, Color("#d8f4ff"), r, arc, 0.45, {"speed":18.0, "scale":4.0, "core":0.2, "fade_end":0.5, "up":0.4, "energy":0.8})
			burst(at + Vector3(0, 0.8, 0), Color("#e8f8ff"), {"n":26, "life":0.6, "size":0.9, "tex":"streak", "core":0.4, "shape":"point",
				"dir":Vector3(dir.x, 0.1, dir.y), "spread":rad_to_deg(arc), "vel":[r * 1.6, r * 2.2], "fade":"slow", "angle":0.0, "shape_life":"grow"})
			burst(at + Vector3(0, 0.3, 0), Color("#b8d8a0"), {"n":12, "life":1.0, "size":0.24, "tex":"leaf", "core":0.2, "shape":"point",
				"dir":Vector3(dir.x, 0.4, dir.y), "spread":rad_to_deg(arc), "vel":[r, r * 1.6], "damp":2.0, "turb":1.5, "angle":180.0,
				"spin":400.0, "fade":"slow"})
		# ---- musketeer ----
		"buckshot":
			var r := float(e.get("r", 7.0))
			var arc := float(e.get("arc", 0.45))
			var mz := at + Vector3(dir.x, 0, dir.y) * 1.1 + Vector3(0, 1.25, 0)
			flash(mz, Color("#ffe8b0"), 2.2, 0.18, "star", 1.0)
			flash(mz, Color("#ff8a3a"), 1.2, 0.25, "dot", 0.6)
			fan(p2, dir, Color("#ffd890"), r * 0.7, arc, 0.25, {"speed":20.0, "core":0.4, "fade_end":0.6, "up":1.0, "in":0.02})
			_shards(mz, Color("#fff0c8"), dir, 14, arc, 30.0, r)
			burst(mz, Color("#c8c8c8"), {"n":8, "life":1.4, "size":1.0, "tex":"smoke", "core":0.0, "blend":"mix", "shape":"point", "dir":Vector3(dir.x, 0.3, dir.y),
				"spread":30.0, "vel":[2.0, 4.0], "damp":3.0, "shape_life":"swell", "fade":"late", "alpha":0.5, "angle":180.0, "spin":40.0})
			shake(0.12, p2, 8.0)
		"keg":
			var c3: Vector2 = e.get("c", p2)
			flash(at + Vector3(0, 1.4, 0), Color("#ff8a3a"), 0.8, 0.2, "sparkle")
			view._lob(at + Vector3(0, 1.4, 0), _g(c3, 0.3), float(e.get("delay", 0.8)), Color("#6a4a2a"))
			burst(at + Vector3(0, 1.4, 0), Color("#ffb04a"), {"n":10, "life":0.5, "size":0.14, "tex":"dot", "core":1.0, "shape":"point",
				"vel":[1.0, 3.0], "grav":Vector3(0, -6.0, 0), "fade":"hot"})
		"smokeroll":
			_dash_fx(id, Color("#c8c8c8"), "smoke", 0.4)
			burst(at + Vector3(0, 0.8, 0), Color("#b8b8b8"), {"n":12, "life":1.5, "size":1.6, "tex":"smoke", "core":0.0, "blend":"mix", "shape":"sphere", "r":0.6,
				"vel":[1.0, 2.5], "damp":2.0, "shape_life":"swell", "fade":"late", "alpha":0.55, "angle":180.0, "spin":40.0})
		# ---- druid ----
		"rejuv":
			var tid := str(e.get("target", ""))
			var tr := _root(tid)
			if tr != null:
				_sparkles(tr.position + Vector3(0, 0.4, 0), Color("#8dff6a"), 12, 0.5, 2.5, 1.0)
				_hold("rejuv:" + tid, [burst(Vector3(0, 0.3, 0), Color("#8dff6a"), {"n":30, "life":1.4, "size":0.4, "tex":"leaf", "core":0.3,
					"shape":"ring", "r":0.7, "inner":0.6, "h":0.2, "dir":Vector3.UP, "spread":20.0, "vel":[0.8, 1.4], "orbit":0.6,
					"angle":180.0, "spin":120.0, "fade":"slow", "dur":float(e.get("dur", 5.0)), "parent":tr, "explode":0.0, "local":true})],
					_alive_while(tid, func(u): return u.has("dots")))
		"entangle":
			var c3: Vector2 = e.get("c", p2)
			disc(c3, Color("#6fbf3a"), float(e.get("r", 1.8)) + 0.4, float(e.get("delay", 0.5)) + 0.2, 4, {"in":0.1, "out":0.15, "energy":1.3})
			_sparkles(at + Vector3(0, 1.0, 0), Color("#8dff6a"), 8, 0.4, 1.5, 0.6, "leaf")
		"barkskin":
			var tid := str(e.get("target", ""))
			var tr := _root(tid)
			if tr != null:
				burst(tr.position + Vector3(0, 0.8, 0), Color("#a07a4a"), {"n":14, "life":1.0, "size":0.3, "tex":"leaf", "core":0.2,
					"shape":"sphere", "r":1.2, "radial":-2.5, "orbit":1.2, "vel":[0.0, 0.3], "fade":"slow", "angle":180.0, "spin":200.0})
				_sparkles(tr.position + Vector3(0, 0.5, 0), Color("#8dff6a"), 8, 0.5, 1.5, 0.8)
				_skin_style[tid] = {"col":Color("#a07a4a")}
		_:
			view.ring_at(at, c1, 2.2, 0.45)
			_sparkles(at + Vector3(0, 0.6, 0), c2, 8, 0.5, 1.5)

var _shield_style := {}                   # unit id -> {col, style}: the last shield cast on him (what its bubble looks like)
var _amp_style := {}                      # unit id -> {col, tex, spin}: a mark or a curse
var _skin_style := {}                     # unit id -> {col}: stone or bark
var _dash_style := {}                     # unit id -> {col, tex, at, dur}: the dash just cast (its trail)

func _dash_fx(id: String, col: Color, nm: String, dur := 0.5) -> void:
	_dash_style[id] = {"col":col, "tex":nm, "at":_time, "dur":dur}

func _block_up(id: String, col: Color) -> void:
	var root := _root(id)
	if root == null:
		return
	var u: Dictionary = view.sim.by_id.get(id, {})
	var f := Vector2(sin(float(u.get("face", 0.0))), cos(float(u.get("face", 0.0))))
	var at: Vector3 = root.position + Vector3(f.x, 0, f.y) * 0.9 + Vector3(0, 1.1, 0)
	flash(at, col, 1.8, 0.3, "ring")
	_sparkles(at, Color("#ffffff"), 6, 0.4, 0.8, 0.5)

func _zap_hit(at: Vector3, col: Color, size: float) -> void:
	flash(at, Color("#ffffff"), 1.4 * size, 0.2, "sparkle", 1.0)
	burst(at, col, {"n":10, "life":0.4, "size":0.5 * size, "tex":"lightning", "core":0.9, "shape":"sphere", "r":0.2 * size,
		"vel":[1.0, 3.0], "fade":"flicker", "angle":180.0, "spin":100.0, "shape_life":"shrink"})
	wave(Vector2(at.x, at.z), col, 0.2, 1.6 * size, 0.35)

# ======================================================================================================================
# the ultimates
# ======================================================================================================================
func ult(hid: String, e: Dictionary, a: Dictionary, at: Vector3) -> void:
	var p2 := Vector2(at.x, at.z)
	var id := str(e.get("id", ""))
	var root := _root(id)
	match hid:
		"knight":                                  # BULWARK: a golden dome over them all
			var r := float(view.sim.moba.BULWARK_R)
			disc(p2, Color("#ffd65a"), r * 0.85, 1.5, 1, {"tex":"rays", "spin":0.8, "grow":0.5, "out":0.8, "energy":0.75})
			wave(p2, Color("#ffe9a6"), 0.5, r, 0.7, 1.4)
			pillar(at, Color("#ffd65a"), 0.45, 6.0, 0.8, {"top":0.7, "speed":4.0, "out":0.5, "core":0.2, "energy":0.7})
			flash(at + Vector3(0, 1.4, 0), Color("#fff1a8"), 2.4, 0.4, "star")
			if root != null:
				var dome := shell(root, Color("#ffd65a", 0.45), r, r * 2.0, 3, -1.0, {"energy":0.8, "speed":0.6, "y":0.2, "key":"bulwark:" + id,
					"alive":_alive_until(id, "dr_until"), "in":0.4, "out":0.6})
				dome.scale = Vector3(1.0, 0.55, 1.0)
			for oid in e.get("ids", []):
				var ro := _root(str(oid))
				if ro != null:
					_sparkles(ro.position + Vector3(0, 0.5, 0), Color("#ffe9a6"), 10, 0.5, 2.0, 1.0, "star")
			shake(0.2, p2)
		"barbarian":                               # WAR CRY: a roar of fire
			for i in 3:
				wave(p2, Color("#ff6a2a"), 0.3, 5.0 + 2.5 * i, 0.5 + 0.2 * i, 1.4)
			disc(p2, Color("#ff5a2a"), 4.0, 0.9, 2, {"grow":0.35, "out":0.5, "energy":1.2, "scorch":0.4, "scorch_out":2.0})
			_flames(at, Color("#ff6a2a"), 30, 1.6, 0.7, 1.2)
			_embers(at + Vector3(0, 0.8, 0), Color("#ffb04a"), 30, 1.0, 4.0)
			flash(at + Vector3(0, 1.4, 0), Color("#ffb04a"), 4.0, 0.4, "rays", 0.9)
			view.shockwave(at + Vector3(0, 0.3, 0), 5.0)
			shake(0.35, p2)
		"rogue":                                   # EXECUTE: out of the dark, the kill
			var from: Vector2 = e.get("from", p2)
			var to: Vector2 = e.get("to", p2)
			burst(_g(from, 0.9), Color("#3a2a5a"), {"n":12, "life":0.8, "size":1.4, "tex":"smoke", "core":0.0, "blend":"mix", "shape":"sphere", "r":0.4,
				"vel":[0.5, 1.5], "shape_life":"swell", "fade":"late", "alpha":0.7, "angle":180.0, "spin":40.0})
			_sparkles(_g(from, 0.6), Color("#a070ff"), 10, 0.4, 1.5, 0.7)
			var tr := _root(str(e.get("target", "")))
			var tp: Vector3 = tr.position if tr != null else _g(to)
			flash(tp + Vector3(0, 1.3, 0), Color("#d8c8ff"), 3.2, 0.35, "crescent", 0.8)
			var f2 := flash(tp + Vector3(0, 1.3, 0), Color("#d8c8ff"), 3.2, 0.35, "crescent", 0.8)
			f2.rotation.z = PI * 0.5
			flash(tp + Vector3(0, 1.3, 0), Color("#ff3a3a"), 1.8, 0.3, "star", 1.0)
			burst(tp + Vector3(0, 1.1, 0), Color("#a070ff"), {"n":20, "life":0.5, "size":0.5, "tex":"streak", "core":0.8, "shape":"point",
				"vel":[6.0, 12.0], "damp":6.0, "fade":"hot", "shape_life":"shrink", "angle":180.0})
			wave(to, Color("#a070ff"), 0.3, 3.0, 0.4)
			shake(0.2, to)
		"ranger":                                  # ARROW RAIN: the sky darkens with arrows
			var c3: Vector2 = e.get("c", p2)
			var r := float(e.get("r", 4.5))
			var dur := float(e.get("dur", 2.0))
			disc(c3, Color("#8fe36a"), r, dur + 0.3, 1, {"tex":"rays", "spin":-0.8, "grow":0.3, "out":0.5})
			wave(c3, Color("#cfe8b8"), 0.3, r, 0.5)
			pillar(at, Color("#cfe8b8"), 0.25, 7.0, 0.5, {"top":0.05, "speed":12.0, "out":0.3, "fade_end":0.8, "core":0.2, "energy":0.8})
			burst(_g(c3, 9.0), Color("#e8ffd0"), {"n":30, "life":0.5, "size":0.6, "tex":"streak", "core":0.6, "shape":"box",
				"ext":Vector3(r * 0.7, 0.3, r * 0.7), "dir":Vector3.DOWN, "spread":6.0, "vel":[14.0, 18.0], "align":true, "fade":"late",
				"dur":dur, "angle":0.0, "explode":0.0, "rand":0.1})
			burst(_g(c3, 0.3), Color("#d8c8a8"), {"n":40, "life":0.7, "size":0.7, "tex":"smoke", "core":0.0, "blend":"mix", "shape":"ring", "r":r * 0.8,
				"inner":0.0, "h":0.1, "dir":Vector3.UP, "spread":40.0, "vel":[0.8, 2.0], "damp":2.0, "shape_life":"swell", "fade":"late",
				"alpha":0.4, "angle":180.0, "spin":30.0, "dur":dur, "explode":0.0})
		"mage":                                    # INFERNO: a wall of fire running out
			var r := float(e.get("r", 7.0))
			disc(p2, Color("#ff4a12"), r, 3.0, 2, {"grow":0.45, "out":1.2, "energy":1.1, "scorch":0.55, "scorch_out":4.0})
			wave(p2, Color("#ffb04a"), 0.3, r, 0.55, 1.4)
			pillar(at, Color("#ff8a2a"), 0.7, 6.0, 0.7, {"top":1.3, "speed":5.0, "out":0.45, "core":0.25, "energy":0.8})
			flash(at + Vector3(0, 1.5, 0), Color("#fff0c0"), 5.0, 0.4, "star", 1.0)
			for i in 3:
				var rr := r * (0.35 + 0.3 * i)
				get_tree().create_timer(0.12 * i).timeout.connect(func():
					_flames(at, Color("#ff6a1a"), 30, rr, 0.9, 2.2 + 0.3 * i, -1.0, 4.0)
					_embers(at + Vector3(0, 0.5, 0), Color("#ffb04a"), 20, rr, 4.0))
			burst(at + Vector3(0, 0.4, 0), Color("#ff6a1a"), {"n":40, "life":0.8, "size":2.2, "tex":"flame", "core":0.6, "shape":"ring", "r":r * 0.95,
				"inner":0.9, "h":0.2, "dir":Vector3.UP, "spread":15.0, "vel":[2.0, 4.0], "grav":Vector3(0, 3.0, 0), "shape_life":"shrink",
				"fade":"hot", "angle":12.0, "spin":20.0, "dur":2.0, "explode":0.0})
			view.shockwave(at + Vector3(0, 0.3, 0), r)
			shake(0.5, p2, 20.0)
		"priest":                                  # GRACE: light on every one of them
			disc(p2, Color("#fff1a8"), 4.5, 1.4, 1, {"tex":"rays", "spin":1.0, "grow":0.5, "out":0.7, "energy":0.8})
			flash(at + Vector3(0, 1.4, 0), Color("#fff1a8"), 3.0, 0.5, "star", 1.0)
			for oid in e.get("ids", []):
				var ro := _root(str(oid))
				if ro != null and ro.visible:
					var tp: Vector3 = ro.position
					pillar(tp, Color("#ffe9a6"), 0.4, 6.0, 1.2, {"top":0.6, "speed":3.0, "out":0.7, "core":0.2, "energy":0.75})
					disc(Vector2(tp.x, tp.z), Color("#fff1a8"), 1.8, 1.2, 1, {"tex":"rays", "spin":1.5, "out":0.5, "energy":0.8})
					burst(tp + Vector3(0, 0.4, 0), Color("#fff6d8"), {"n":18, "life":1.2, "size":0.3, "tex":"sparkle", "core":0.9, "shape":"sphere",
						"r":0.6, "vel":[0.3, 1.0], "grav":Vector3(0, 2.0, 0), "fade":"slow", "shape_life":"pop", "angle":180.0, "spin":60.0})
		"crusader":                                # JUDGMENT: a pillar from heaven
			var r := float(e.get("r", 5.5))
			pillar(at, Color("#ffe9a6"), 1.0, 11.0, 1.0, {"top":1.4, "speed":5.0, "out":0.55, "core":0.2, "in":0.05, "energy":0.75})
			disc(p2, Color("#ffd65a"), r, 1.6, 1, {"tex":"rays", "spin":2.0, "grow":0.3, "out":0.7, "energy":0.9})
			wave(p2, Color("#fff6d8"), 0.3, r + 0.5, 0.5, 1.6)
			flash(at + Vector3(0, 2.0, 0), Color("#fff6d8"), 4.0, 0.4, "star", 1.0)
			burst(at + Vector3(0, 0.3, 0), Color("#fff1a8"), {"n":30, "life":1.0, "size":0.4, "tex":"sparkle", "core":0.9, "shape":"ring",
				"r":r * 0.7, "inner":0.1, "h":0.2, "dir":Vector3.UP, "spread":30.0, "vel":[2.0, 5.0], "grav":Vector3(0, -3.0, 0),
				"fade":"slow", "shape_life":"pop", "angle":180.0, "spin":60.0})
			view.shockwave(at + Vector3(0, 0.3, 0), r)
			shake(0.45, p2, 20.0)
		"berserker":                               # UNDYING: nothing takes him down
			wave(p2, Color("#ff2a2a"), 0.3, 4.0, 0.5, 1.5)
			disc(p2, Color("#7a0c0c"), 2.4, 1.0, 2, {"out":0.5, "energy":1.5, "scorch":0.5, "scorch_col":Color(0.1, 0.0, 0.0)})
			burst(at + Vector3(0, 1.0, 0), Color("#ff2a2a"), {"n":24, "life":0.7, "size":0.5, "tex":"crescent", "core":0.5, "shape":"sphere", "r":0.4,
				"vel":[4.0, 8.0], "damp":5.0, "angle":180.0, "spin":500.0, "fade":"hot", "shape_life":"shrink"})
			burst(at + Vector3(0, 1.2, 0), Color("#2a0404"), {"n":10, "life":1.0, "size":1.6, "tex":"smoke", "core":0.0, "blend":"mix", "shape":"sphere", "r":0.5,
				"vel":[0.5, 2.0], "shape_life":"swell", "fade":"late", "alpha":0.7, "angle":180.0, "spin":40.0})
			flash(at + Vector3(0, 1.3, 0), Color("#ff4a2a"), 3.0, 0.4, "rays", 0.8)
			shake(0.3, p2)
		"assassin":                                # FLURRY: the first of the darts
			burst(at + Vector3(0, 1.0, 0), Color("#2a1a4a"), {"n":14, "life":0.8, "size":1.4, "tex":"smoke", "core":0.0, "blend":"mix", "shape":"sphere", "r":0.5,
				"vel":[0.5, 2.0], "shape_life":"swell", "fade":"late", "alpha":0.7, "angle":180.0, "spin":40.0})
			flash(at + Vector3(0, 1.2, 0), Color("#9a6bff"), 2.6, 0.3, "crescent", 0.8)
			wave(p2, Color("#8a5bff"), 0.3, float(view.sim.moba.FLURRY_R), 0.5)
		"sniper":                                  # DEADEYE: the shot across the field
			var u: Dictionary = view.sim.by_id.get(id, {})
			var f := Vector2(sin(float(u.get("face", 0.0))), cos(float(u.get("face", 0.0))))
			var mz := at + Vector3(f.x, 0, f.y) * 1.0 + Vector3(0, 1.3, 0)
			flash(mz, Color("#ffffff"), 3.4, 0.25, "star", 1.0)
			flash(mz, Color("#bfefff"), 2.0, 0.4, "rays", 0.8)
			beam(mz, mz + Vector3(f.x, 0, f.y) * float(view.sim.moba.DEADEYE_RANGE), Color("#bfefff"), 0.8, 0.9, {"speed":30.0, "core":0.8,
				"fade_end":0.3, "in":0.03, "out":0.6, "grow":0.25})
			burst(mz, Color("#ffffff"), {"n":20, "life":0.5, "size":0.4, "tex":"sparkle", "core":1.0, "shape":"point", "vel":[4.0, 9.0], "damp":6.0,
				"fade":"hot", "shape_life":"shrink", "angle":180.0, "spin":200.0})
			wave(p2, Color("#bfefff"), 0.2, 3.0, 0.4)
			shake(0.3, p2)
		"archmage":                                # METEORS: the sky called down
			var c3: Vector2 = e.get("c", p2)
			disc(c3, Color("#c070ff"), float(view.sim.moba.STORM_SPREAD) + 2.0, 2.6, 1, {"tex":"runes", "spin":1.5, "grow":0.4, "out":0.8, "energy":1.2})
			wave(c3, Color("#ff6ad0"), 0.3, float(view.sim.moba.STORM_SPREAD) + 2.0, 0.6)
			flash(at + Vector3(0, 1.4, 0), Color("#c070ff"), 2.2, 0.4, "runes", 0.6, false, 4.0)
			pillar(at, Color("#c070ff"), 0.3, 9.0, 0.6, {"top":0.05, "speed":12.0, "out":0.35, "fade_end":0.7, "core":0.2, "energy":0.8})
		"necromancer":                             # LEGION: the dead rise
			disc(p2, Color("#7dff8a"), 4.0, 2.0, 1, {"tex":"runes", "spin":-1.0, "grow":0.5, "out":0.8})
			burst(at + Vector3(0, 0.3, 0), Color("#1a3a1a"), {"n":16, "life":1.6, "size":1.8, "tex":"smoke", "core":0.0, "blend":"mix", "shape":"ring", "r":2.5,
				"inner":0.2, "h":0.1, "dir":Vector3.UP, "spread":40.0, "vel":[0.5, 1.5], "shape_life":"swell", "fade":"late", "alpha":0.7,
				"angle":180.0, "spin":30.0})
			for oid in e.get("ids", []):
				var zp := _unit_pos(str(oid))
				if zp != Vector2.INF:
					pillar(_g(zp, 0.0), Color("#7dff8a"), 0.35, 4.0, 1.0, {"top":0.6, "speed":3.0, "out":0.6, "core":0.2, "energy":0.85})
					burst(_g(zp, 0.6), Color("#e8e0c8"), {"n":10, "life":0.9, "size":0.26, "tex":"shard", "core":0.2, "shape":"sphere", "r":0.4,
						"vel":[1.0, 3.0], "grav":Vector3(0, -6.0, 0), "angle":180.0, "spin":300.0, "fade":"late"})
			flash(at + Vector3(0, 1.4, 0), Color("#7dff8a"), 2.6, 0.4, "runes", 0.6, false, -3.0)
		"golem", "dragoon", "duelist", "stormcaller", "musketeer", "druid":
			_new_ult(str(e.get("spell", "")), e, a, at, id, root)
		_:
			view.ring_at(at, _col(hid, 0), 2.6, 0.6)

func _new_ult(sp: String, e: Dictionary, _a: Dictionary, at: Vector3, id: String, root: Node3D) -> void:
	var p2 := Vector2(at.x, at.z)
	match sp:
		"landslide":                               # the avalanche
			_dash_fx(id, Color("#c8b89a"), "smoke", 0.7)
			wave(p2, Color("#c8b48a"), 0.4, 4.0, 0.5)
			_rocks(at + Vector3(0, 0.4, 0), 14, 1.0, 0.3, 6.0)
			_dust(at, Color("#c8b89a"), 16, 1.0, 2.0, 1.3, 3.0)
			if root != null:
				_hold("slide:" + id, [burst(Vector3(0, 0.3, 0), Color("#a89880"), {"n":18, "life":0.8, "size":0.3, "mesh":"rock", "shape":"sphere",
					"r":0.8, "dir":Vector3.UP, "spread":70.0, "vel":[3.0, 6.0], "grav":Vector3(0, -14.0, 0), "angle":180.0, "spin":500.0,
					"fade":"late", "sizes":0.5, "dur":0.7, "parent":root, "explode":0.0})], _alive_while(id, func(u): return u.state == "dash"))
			shake(0.3, p2)
		"dragondive":                              # up in fire, down in fire
			var to: Vector2 = e.get("to", p2)
			_flames(at, Color("#ff7a3a"), 20, 0.8, 0.6, 1.2, -1.0, 6.0)
			pillar(at, Color("#ff7a3a"), 0.4, 6.0, 0.5, {"top":0.1, "speed":10.0, "out":0.3, "fade_end":0.7, "core":0.2, "energy":0.8})
			_dash_fx(id, Color("#ff7a3a"), "flame", 1.0)
			disc(to, Color("#ff3a2a"), float(e.get("r", 3.5)), 1.0, 1, {"tex":"rays", "spin":3.0, "energy":1.3, "out":0.2})
			_dust(at, Color("#d8c8a8"), 10, 0.7, 1.4, 0.9, 3.5)
		"challenge":                               # en garde
			var tr := _root(str(e.get("target", "")))
			disc(p2, Color("#ffe27a"), 3.0, 1.4, 1, {"tex":"rays", "spin":2.5, "out":0.5})
			flash(at + Vector3(0, 1.3, 0), Color("#ffffff"), 2.4, 0.3, "star", 1.0)
			if tr != null:
				beam(at + Vector3(0, 1.2, 0), tr.position + Vector3(0, 1.2, 0), Color("#ffe27a"), 0.3, 0.3, {"speed":20.0, "core":0.7})
				wave(Vector2(tr.position.x, tr.position.z), Color("#ffe27a"), 0.3, 3.0, 0.5)
		"thunderstorm":                            # the storm gathers
			var c3: Vector2 = e.get("c", p2)
			var r := float(e.get("r", 5.0))
			pillar(at, Color("#7fb8ff"), 0.25, 9.0, 0.5, {"top":0.05, "speed":14.0, "out":0.3, "fade_end":0.7, "core":0.2, "energy":0.8})
			flash(at + Vector3(0, 1.4, 0), Color("#e8f4ff"), 2.0, 0.3, "sparkle", 1.0)
			bolt(at + Vector3(0, 1.5, 0), _g(c3, 7.0), Color("#7fb8ff"), 0.35, 1.0, 0.18, 2)
			var dur := 4.5
			burst(_g(c3, 7.5), Color("#2a3a5a"), {"n":40, "life":2.2, "size":3.0, "tex":"smoke", "core":0.0, "blend":"mix", "shape":"ring", "r":r * 0.9,
				"inner":0.0, "h":0.6, "dir":Vector3.UP, "spread":90.0, "vel":[0.2, 0.8], "damp":0.5, "shape_life":"swell", "fade":"slow",
				"alpha":0.85, "angle":180.0, "spin":20.0, "dur":dur, "explode":0.0, "rand":0.4, "reach":14.0})
			shake(0.25, p2, 20.0)
		"quickdraw":                               # every shot at once
			var u: Dictionary = view.sim.by_id.get(id, {})
			var f := Vector2(sin(float(u.get("face", 0.0))), cos(float(u.get("face", 0.0))))
			var mz := at + Vector3(f.x, 0, f.y) * 1.0 + Vector3(0, 1.3, 0)
			disc(p2, Color("#ffd890"), 2.6, 0.9, 1, {"tex":"rays", "spin":4.0, "out":0.4})
			flash(mz, Color("#ffffff"), 2.6, 0.25, "star", 1.0)
			burst(mz, Color("#c8c8c8"), {"n":12, "life":1.6, "size":1.2, "tex":"smoke", "core":0.0, "blend":"mix", "shape":"sphere", "r":0.3, "vel":[1.0, 2.5],
				"damp":2.0, "shape_life":"swell", "fade":"late", "alpha":0.5, "angle":180.0, "spin":40.0})
			var i := 0
			for pt in e.get("pts", []):
				var tp := _g(pt, 1.1)
				get_tree().create_timer(0.06 * i).timeout.connect(func():
					beam(mz, tp, Color("#fff0c8"), 0.3, 0.22, {"speed":30.0, "core":0.9, "fade_end":0.1, "in":0.02})
					flash(mz, Color("#ffe8b0"), 1.6, 0.15, "star", 1.0)
					flash(tp, Color("#ffd890"), 1.6, 0.3, "sparkle", 1.0)
					burst(tp, Color("#ffd890"), {"n":10, "life":0.4, "size":0.3, "tex":"dot", "core":1.0, "shape":"point", "vel":[3.0, 7.0],
						"grav":Vector3(0, -8.0, 0), "fade":"hot"}))
				i += 1
			shake(0.25, p2)
		"wildgrowth":                              # the grove
			var r := float(e.get("r", 7.0))
			wave(p2, Color("#6aff7a"), 0.3, r, 0.7, 1.4)
			pillar(at, Color("#8dff6a"), 0.35, 5.0, 0.7, {"top":0.6, "speed":3.0, "out":0.5, "core":0.15, "energy":0.7})
			burst(at + Vector3(0, 0.3, 0), Color("#8dff6a"), {"n":30, "life":1.6, "size":0.3, "tex":"leaf", "core":0.3, "shape":"ring", "r":r * 0.7,
				"inner":0.1, "h":0.1, "dir":Vector3.UP, "spread":30.0, "vel":[1.5, 3.0], "grav":Vector3(0, -0.8, 0), "turb":1.0, "angle":180.0,
				"spin":200.0, "fade":"slow"})
			view._vines(at, r * 0.6)
			_sparkles(at + Vector3(0, 0.3, 0), Color("#d8ffb0"), 20, r * 0.6, 1.5, 1.2)

# ======================================================================================================================
# the old classes' Q (siege_sim.gd) and the one-off events
# ======================================================================================================================
func q(ab: String, a: Dictionary, u: Dictionary) -> void:
	var root := _root(str(u.id))
	if root == null:
		return
	var at: Vector3 = root.position
	var p2 := Vector2(at.x, at.z)
	var f := Vector2(sin(float(u.face)), cos(float(u.face)))
	match ab:
		"spin":                                    # the Barbarian's
			flash(at + Vector3(0, 1.0, 0), Color("#ffb04a"), 5.0, 0.35, "crescent", 0.6, true, 14.0)
			wave(p2, Color("#ff8a3a"), 0.3, 3.2, 0.4)
			burst(at + Vector3(0, 1.0, 0), Color("#ffcf7a"), {"n":16, "life":0.45, "size":0.4, "tex":"streak", "core":0.7, "shape":"ring", "r":1.6,
				"inner":0.8, "h":0.2, "dir":Vector3.UP, "spread":90.0, "vel":[0.5, 1.5], "orbit":2.5, "fade":"hot", "angle":180.0})
		"lunge":                                   # the Rogue's
			_dash_fx(str(u.id), Color("#a070ff"), "streak", 0.35)
			flash(at + Vector3(f.x, 0, f.y) * 1.0 + Vector3(0, 1.1, 0), Color("#d8c8ff"), 1.6, 0.25, "crescent", 0.7)
		"volley":                                  # the Ranger's
			flash(at + Vector3(f.x, 0, f.y) * 0.8 + Vector3(0, 1.2, 0), Color("#e8ffd0"), 1.4, 0.2, "sparkle")
			fan(p2, f, Color("#8fe36a"), 3.0, 0.6, 0.3, {"speed":14.0, "core":0.3, "up":1.0, "fade_end":0.7})
			burst(at + Vector3(0, 1.0, 0), Color("#8fe36a"), {"n":8, "life":0.9, "size":0.24, "tex":"feather", "core":0.3, "shape":"sphere", "r":0.4,
				"vel":[0.5, 1.5], "grav":Vector3(0, -0.8, 0), "turb":0.8, "angle":180.0, "spin":200.0, "fade":"slow"})
		"hammer":                                  # the Crusader's
			flash(at + Vector3(f.x, 0, f.y) * 0.8 + Vector3(0, 1.3, 0), Color("#ffd65a"), 1.6, 0.25, "star")
			_sparkles(at + Vector3(0, 1.2, 0), Color("#ffe9a6"), 8, 0.4, 1.0, 0.6)
		"whirlwind":                               # the Berserker's (the ribbon is the view's; the dust it kicks)
			if not holding("whirl:" + str(u.id)):
				_hold("whirl:" + str(u.id), [burst(Vector3(0, 0.2, 0), Color("#d8c8a8"), {"n":24, "life":0.8, "size":1.4, "tex":"smoke", "core":0.0, "blend":"mix",
					"shape":"ring", "r":1.2, "inner":0.5, "h":0.1, "dir":Vector3.UP, "spread":50.0, "vel":[1.0, 2.5], "orbit":2.0, "damp":1.5,
					"shape_life":"swell", "fade":"late", "alpha":0.45, "angle":180.0, "spin":30.0, "dur":30.0, "parent":root, "explode":0.0}),
					burst(Vector3(0, 1.0, 0), Color("#ff2a2a"), {"n":24, "life":0.4, "size":0.8, "tex":"crescent", "core":0.5, "shape":"ring", "r":1.5,
					"inner":0.9, "h":0.3, "dir":Vector3.UP, "spread":90.0, "vel":[0.3, 1.0], "orbit":3.0, "fade":"hot", "angle":180.0, "dur":30.0,
					"parent":root, "explode":0.0})], _alive_while(str(u.id), func(uu): return view.sim.whirling(uu)))
		"vanish":                                  # the Assassin's
			burst(at + Vector3(0, 1.0, 0), Color("#2a1a4a"), {"n":16, "life":1.0, "size":1.6, "tex":"smoke", "core":0.0, "blend":"mix", "shape":"sphere", "r":0.5,
				"vel":[0.5, 1.5], "shape_life":"swell", "fade":"late", "alpha":0.8, "angle":180.0, "spin":40.0})
			burst(at + Vector3(0, 1.0, 0), Color("#8a5bff"), {"n":16, "life":0.5, "size":0.3, "tex":"sparkle", "core":0.9, "shape":"sphere", "r":1.4,
				"radial":-5.0, "vel":[0.0, 0.2], "fade":"slow", "shape_life":"shrink"})
		"pierce":                                  # the Sniper's: the draw (the shot: event "proj")
			flash(at + Vector3(f.x, 0, f.y) * 0.8 + Vector3(0, 1.3, 0), Color("#bfefff"), 1.0, 0.3, "sparkle", 1.0)
		"meteor":                                  # the Archmage's (the rock itself: meteor_warn)
			flash(at + Vector3(0, 1.4, 0), Color("#ff6ad0"), 1.8, 0.35, "runes", 0.6, false, 4.0)
			pillar(at, Color("#c070ff"), 0.25, 7.0, 0.5, {"top":0.05, "speed":12.0, "out":0.3, "fade_end":0.7, "core":0.2, "energy":0.8})
		"nova":                                    # the Mage's: the gathering (the blast: event "nova")
			burst(at + Vector3(0, 1.2, 0), Color("#ffd24a"), {"n":12, "life":0.4, "size":0.3, "tex":"sparkle", "core":0.9, "shape":"sphere", "r":1.4,
				"radial":-5.0, "vel":[0.0, 0.2], "fade":"slow", "shape_life":"shrink"})
		"nova_blast":
			var r := float(Sim.NOVA_R)
			disc(p2, Color("#ff5a1a"), r, 0.9, 2, {"grow":0.3, "out":0.5, "energy":1.1, "scorch":0.4, "scorch_out":2.0})
			wave(p2, Color("#ffb04a"), 0.3, r, 0.45, 1.4)
			_flames(at, Color("#ff6a1a"), 26, r * 0.6, 0.6, 1.8, -1.0, 3.5)
			_embers(at + Vector3(0, 0.5, 0), Color("#ffb04a"), 16, r * 0.5, 3.0)
			flash(at + Vector3(0, 1.2, 0), Color("#fff0c0"), 2.6, 0.3, "star", 1.0)
			view.shockwave(at + Vector3(0, 0.3, 0), r)
			shake(0.2, p2)
		"sanctuary":                               # the Priest's: the prayer (the light: event "sanctuary")
			_sparkles(at + Vector3(0, 1.2, 0), Color("#fff6d8"), 8, 0.4, 1.5, 0.6)
		"sanctuary_blast":
			var r := float(Sim.SANCTUARY_R)
			disc(p2, Color("#fff1a8"), r, 1.0, 1, {"tex":"rays", "spin":1.2, "grow":0.4, "out":0.5})
			wave(p2, Color("#fff6d8"), 0.3, r, 0.6)
			pillar(at, Color("#ffe9a6"), 0.3, 5.0, 0.7, {"top":0.5, "speed":3.0, "out":0.5, "core":0.15, "energy":0.7})
			burst(at + Vector3(0, 0.3, 0), Color("#fff6d8"), {"n":24, "life":1.2, "size":0.3, "tex":"sparkle", "core":0.9, "shape":"ring", "r":r * 0.7,
				"inner":0.1, "h":0.2, "dir":Vector3.UP, "spread":20.0, "vel":[0.8, 2.0], "fade":"slow", "shape_life":"pop", "angle":180.0, "spin":60.0})
		"resurrect":
			pass                                   # (the "resurrect" event, where he rises)
		"block":
			pass                                   # (block_up)
		_:
			pass

func event(e: Dictionary) -> void:
	# the one-off events (siege_view.on_event hands these over)
	var a: Dictionary = view.actors.get(str(e.get("id", "")), {})
	var root: Node3D = a.root if not a.is_empty() and is_instance_valid(a.root) else null
	match str(e.k):
		"block_up":
			if root != null and root.visible:
				var u: Dictionary = view.sim.by_id.get(str(e.id), {})
				_block_up(str(e.id), Color("#ffe9a6") if str(u.get("hid", "")) == "crusader" else Color("#bcd8ff"))
		"pillar":                                  # FIRE PILLAR erupts
			var c3: Vector2 = e.c
			var r := float(e.r)
			var at := _g(c3, 0.0)
			pillar(at, Color("#ff7a2a"), r * 0.5, 5.0, 0.7, {"top":r * 0.2, "speed":6.0, "out":0.4, "core":0.25, "in":0.04, "energy":0.8})
			disc(c3, Color("#ff6a2a"), r + 0.5, 1.2, 1, {"tex":"cracks", "out":0.6, "energy":1.2, "scorch":0.5, "scorch_out":3.0})
			_flames(at, Color("#ff6a1a"), 26, r * 0.7, 0.7, 1.9, -1.0, 5.0)
			_embers(at + Vector3(0, 0.5, 0), Color("#ffd24a"), 20, r * 0.5, 5.0)
			flash(at + Vector3(0, 2.0, 0), Color("#fff0c0"), 3.0, 0.3, "star", 1.0)
			wave(c3, Color("#ffd24a"), 0.3, r + 1.0, 0.45, 1.5)
			view.shockwave(at + Vector3(0, 0.3, 0), r)
			shake(0.25, c3)
		"slam":                                    # a LEAP's or a dive's or the avalanche's landing
			var c3: Vector2 = e.pos
			var r := float(e.get("r", 2.5))
			var at := _g(c3, 0.0)
			var u: Dictionary = view.sim.by_id.get(str(e.get("id", "")), {})
			var hid := str(u.get("hid", ""))
			var col := Color("#ffb04a") if hid == "barbarian" else (Color("#ff7a3a") if hid == "dragoon" else Color("#c8b48a"))
			disc(c3, col, r, 1.0, 1, {"tex":"cracks", "out":0.5, "energy":1.2, "scorch":0.4, "scorch_out":2.5, "scorch_col":Color(0.12, 0.09, 0.05)})
			wave(c3, col, 0.3, r + 0.8, 0.45, 1.5)
			_rocks(at + Vector3(0, 0.3, 0), 10 if hid != "golem" else 20, r * 0.4, 0.22, 6.0)
			_dust(at, Color("#c8b89a"), 14, r * 0.5, 1.6, 1.1, 3.0)
			if hid == "dragoon":
				_flames(at, Color("#ff7a3a"), 24, r * 0.7, 0.6, 1.3, -1.0, 4.0)
				flash(at + Vector3(0, 1.2, 0), Color("#ffd890"), 5.0, 0.3, "crescent", 0.7, true, 8.0)
			view.shockwave(at + Vector3(0, 0.3, 0), r)
			shake(0.3 if hid != "golem" else 0.45, c3)
		"burst":                                   # the keg goes off / the roots burst up
			var c3: Vector2 = e.c
			var r := float(e.get("r", 2.0))
			var at := _g(c3, 0.0)
			if str(e.spell) == "keg":
				view._pack_explosion("light", at + Vector3(0, 0.5, 0), 1.2)
				flash(at + Vector3(0, 0.8, 0), Color("#ffe0a0"), 4.0, 0.3, "star", 1.0)
				disc(c3, Color("#ff9a3a"), r, 0.8, 2, {"out":0.5})
				wave(c3, Color("#ff9a3a"), 0.3, r + 1.0, 0.45, 1.5)
				burst(at + Vector3(0, 0.5, 0), Color("#6a4a2a"), {"n":14, "life":1.0, "size":0.22, "mesh":"rock", "shape":"sphere", "r":0.3,
					"dir":Vector3.UP, "spread":60.0, "vel":[3.0, 8.0], "grav":Vector3(0, -14.0, 0), "angle":180.0, "spin":500.0, "fade":"late"})
				view.smoke_cloud(at + Vector3(0, 0.6, 0), 0.5, 12, 4.0)
				view.shockwave(at + Vector3(0, 0.3, 0), r)
				shake(0.25, c3)
			else:
				disc(c3, Color("#6fbf3a"), r + 0.5, 1.6, 4, {"out":0.7, "energy":1.3})
				wave(c3, Color("#8dff6a"), 0.3, r + 1.0, 0.5)
				view._vines(at, r)
				burst(at + Vector3(0, 0.3, 0), Color("#8dff6a"), {"n":18, "life":1.2, "size":0.28, "tex":"leaf", "core":0.3, "shape":"ring", "r":r * 0.6,
					"inner":0.2, "h":0.1, "dir":Vector3.UP, "spread":30.0, "vel":[2.0, 4.0], "grav":Vector3(0, -1.5, 0), "turb":1.0, "angle":180.0,
					"spin":200.0, "fade":"slow"})
				_dust(at, Color("#8a7a5a"), 8, r * 0.5, 1.0, 0.8, 2.0)
		"zap":                                     # a THUNDERSTORM bolt
			var zp := _g(e.c, 0.1)
			bolt(zp + Vector3(randf_range(-1.5, 1.5), 8.0, randf_range(-1.5, 1.5)), zp + Vector3(0, 0.3, 0), Color("#7fb8ff"), 0.3, 1.6, 0.22, 2)
			_zap_hit(zp + Vector3(0, 0.5, 0), Color("#9fd4ff"), 1.3)
			flash(zp + Vector3(0, 6.0, 0), Color("#dff0ff"), 6.0, 0.15, "dot", 0.3)
			shake(0.12, e.c, 14.0)
		"riposte":                                 # the Duelist answers
			var rp := _g(e.pos, 1.0)
			flash(rp, Color("#ffffff"), 2.2, 0.25, "star", 1.0)
			var f2 := flash(rp, Color("#ffe27a"), 2.8, 0.3, "crescent", 0.8)
			f2.rotation.z = randf() * TAU
			burst(rp, Color("#fff4c0"), {"n":14, "life":0.45, "size":0.4, "tex":"streak", "core":0.8, "shape":"point", "vel":[4.0, 9.0], "damp":6.0,
				"fade":"hot", "shape_life":"shrink", "angle":180.0})
			wave(e.pos, Color("#ffe27a"), 0.3, 2.4, 0.4)
		"flurry_hit":                              # FLURRY's or GRAND CHALLENGE's strike
			var u: Dictionary = view.sim.by_id.get(str(e.get("id", "")), {})
			var gold := str(u.get("hid", "")) == "duelist"
			var fp := _g(e.pos, 1.1)
			var col := Color("#ffe27a") if gold else Color("#9a6bff")
			var f1 := flash(fp, col.lerp(Color.WHITE, 0.5), 2.6, 0.28, "crescent", 0.8)
			f1.rotation.z = randf() * TAU
			burst(fp, col, {"n":12, "life":0.4, "size":0.5, "tex":"streak", "core":0.8, "shape":"point", "vel":[5.0, 10.0], "damp":6.0,
				"fade":"hot", "shape_life":"shrink", "angle":180.0})
			if not gold:
				burst(_g(e.get("from", e.pos), 0.9), Color("#2a1a4a"), {"n":6, "life":0.6, "size":1.2, "tex":"smoke", "core":0.0, "blend":"mix", "shape":"sphere",
					"r":0.3, "vel":[0.3, 1.0], "shape_life":"swell", "fade":"late", "alpha":0.6, "angle":180.0, "spin":40.0})
			else:
				bolt(fp + Vector3(randf_range(-2, 2), 5.0, randf_range(-2, 2)), fp, Color("#ffe27a"), 0.25, 0.8, 0.14, 1)
		"trap_snap":
			var tp := _g(e.pos, 0.2)
			flash(tp + Vector3(0, 0.4, 0), Color("#ffffff"), 1.4, 0.2, "sparkle", 1.0)
			burst(tp, Color("#ffd27a"), {"n":16, "life":0.5, "size":0.16, "tex":"dot", "core":1.0, "shape":"sphere", "r":0.3, "vel":[2.0, 6.0],
				"grav":Vector3(0, -10.0, 0), "fade":"hot"})
			wave(e.pos, Color("#ff4a4a"), 0.2, 1.8, 0.35)
		"nova":
			var u: Dictionary = view.sim.by_id.get(str(e.id), {})
			if not u.is_empty():
				q("nova_blast", a, u)
		"sanctuary":
			var u: Dictionary = view.sim.by_id.get(str(e.id), {})
			if not u.is_empty():
				q("sanctuary_blast", a, u)
		"proj":                                    # a shot leaves: the Sniper's muzzle flash
			if str(e.get("kind", "")) == "pierce" and root != null and root.visible:
				var u: Dictionary = view.sim.by_id.get(str(e.get("id", "")), {})
				if not u.is_empty():
					var f := Vector2(sin(float(u.face)), cos(float(u.face)))
					var mz: Vector3 = root.position + Vector3(f.x, 0, f.y) * 1.0 + Vector3(0, 1.3, 0)
					flash(mz, Color("#ffffff"), 1.8, 0.2, "star", 1.0)
					fan(Vector2(root.position.x, root.position.z), f, Color("#bfefff"), 2.5, 0.25, 0.25, {"speed":20.0, "core":0.6, "up":1.2, "in":0.02})
		"resurrect":
			var rp := _g(e.pos, 0.0)
			pillar(rp, Color("#7dff8a"), 0.35, 5.0, 1.2, {"top":0.5, "speed":3.0, "out":0.7, "core":0.2, "energy":0.75})
			disc(e.pos, Color("#7dff8a"), 2.2, 1.4, 1, {"tex":"runes", "spin":-1.5, "out":0.6})
			burst(rp + Vector3(0, 0.3, 0), Color("#d8e8c0"), {"n":16, "life":1.2, "size":0.3, "tex":"sparkle", "core":0.9, "shape":"sphere", "r":0.5,
				"vel":[0.3, 1.0], "grav":Vector3(0, 2.0, 0), "fade":"slow", "shape_life":"pop", "angle":180.0, "spin":60.0})
			burst(rp + Vector3(0, 0.6, 0), Color("#e8e0c8"), {"n":10, "life":0.9, "size":0.26, "tex":"shard", "core":0.2, "shape":"sphere", "r":0.5,
				"radial":-3.0, "vel":[0.0, 0.3], "fade":"slow", "angle":180.0, "spin":200.0})
		"pierce_hit":
			var ph := _g(e.pos, 1.1)
			flash(ph, Color("#ffffff"), 1.4, 0.2, "sparkle", 1.0)
			burst(ph, Color("#bfefff"), {"n":10, "life":0.4, "size":0.3, "tex":"streak", "core":0.8, "shape":"point", "vel":[3.0, 7.0], "damp":5.0,
				"fade":"hot", "shape_life":"shrink", "angle":180.0})
		"boom":                                    # a fireball lands
			var bp := _g(e.pos, 0.3)
			flash(bp + Vector3(0, 0.4, 0), Color("#ffb04a"), 2.0, 0.25, "star", 0.9)
			_flames(bp, Color("#ff8a3a"), 8, 0.5, 0.5, 0.8, -1.0, 3.0)
			wave(e.pos, Color("#ff8a3a"), 0.2, 2.0, 0.35)
		"vanish":
			pass                                   # (q "vanish")
		"dodge":
			if root != null and root.visible:
				_dust(root.position, Color("#d8c8a8"), 5, 0.4, 0.9, 0.7, 2.0)
		"meteor_warn":
			var c3: Vector2 = e.pos
			disc(c3, Color("#ff6a3a"), float(Sim.METEOR_R), float(e.delay) + 0.1, 1, {"tex":"runes", "spin":4.0, "in":0.1, "out":0.1, "energy":1.3})
		"meteor_hit":
			var c3: Vector2 = e.pos
			disc(c3, Color("#ff6a3a"), float(Sim.METEOR_R) + 1.0, float(e.burn) + 0.5, 2, {"out":1.0, "energy":1.1, "in":0.05, "scorch":0.6, "scorch_out":6.0})
			disc(c3, Color("#ffb04a"), float(Sim.METEOR_R) * 1.4, 2.0, 1, {"tex":"cracks", "out":1.2, "energy":1.2})
			_rocks(_g(c3, 0.3), 16, 1.0, 0.3, 8.0)
			_embers(_g(c3, 0.6), Color("#ffb04a"), 24, 1.5, 5.0)
			flash(_g(c3, 1.0), Color("#fff0c0"), 6.0, 0.3, "star", 1.0)

func meteor_trail(rock: Node3D) -> void:
	# fire and smoke streaming off a falling meteor (siege_view._meteor_warn's rock)
	var rm := rock.get_node_or_null("rock_mesh")
	burst(Vector3.ZERO, Color("#ff8a3a"), {"n":30, "life":0.5, "size":1.3, "tex":"flame", "core":0.7, "shape":"sphere", "r":0.5, "vel":[0.5, 1.5],
		"grav":Vector3(0, 2.0, 0), "shape_life":"grow", "fade":"hot", "angle":180.0, "spin":60.0, "dur":6.0, "parent":rock, "explode":0.0, "reach":30.0})
	burst(Vector3.ZERO, Color("#3a2a20"), {"n":20, "life":1.2, "size":1.6, "tex":"smoke", "core":0.0, "blend":"mix", "shape":"sphere", "r":0.5, "vel":[0.2, 0.8],
		"grav":Vector3(0, 0.8, 0), "shape_life":"swell", "fade":"late", "alpha":0.6, "angle":180.0, "spin":30.0, "dur":6.0, "parent":rock, "explode":0.0, "reach":30.0})
	if rm == null:
		var glow := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2.ONE * 3.2
		glow.mesh = q
		glow.material_override = sprite_mat("dot", 0.9, Color("#ffb04a"))
		glow.name = "rock_mesh"
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rock.add_child(glow)

func proj_trail(node: Node3D, p: Dictionary) -> void:
	# what a projectile leaves behind it, by what it is (siege_view._sync_projectiles, when its node is made)
	var kind := str(p.kind)
	var sp := str(p.get("spell", ""))
	match kind:
		"hammer":
			trail(node, Color("#ffd65a"), 30.0, "sparkle", {"n":20, "life":0.4, "size":0.35, "y":0.0, "grav":Vector3.ZERO, "shape_life":"pop"})
		"pierce":
			trail(node, Color("#bfefff"), 30.0, "streak", {"n":24, "life":0.3, "size":0.5, "y":0.0, "grav":Vector3.ZERO})
		"boulder":
			trail(node, Color("#c8b89a"), 30.0, "smoke", {"n":16, "life":0.7, "size":0.9, "y":-0.3, "grav":Vector3(0, 0.3, 0), "shape_life":"grow", "alpha":0.4, "fade":"late"})
		"bolt":
			trail(node, Color("#9fd4ff"), 30.0, "lightning", {"n":16, "life":0.25, "size":0.6, "y":0.0, "grav":Vector3.ZERO, "fade":"flicker"})
		"ball":
			trail(node, Color("#ff8a3a"), 30.0, "flame", {"n":20, "life":0.4, "size":0.7, "y":0.0, "grav":Vector3(0, 1.5, 0), "fade":"hot"})
		"thorn":
			trail(node, Color("#8dff6a"), 30.0, "leaf", {"n":12, "life":0.5, "size":0.3, "y":0.0, "grav":Vector3(0, -0.5, 0)})
		"fire":
			if sp == "missiles":
				trail(node, Color("#c070ff"), 30.0, "runes", {"n":14, "life":0.35, "size":0.4, "y":0.0, "grav":Vector3.ZERO, "shape_life":"shrink"})
				trail(node, Color("#ff6ad0"), 30.0, "sparkle", {"n":14, "life":0.3, "size":0.3, "y":0.0, "grav":Vector3.ZERO, "shape_life":"pop"})
			else:
				trail(node, Color("#ff8a3a"), 30.0, "flame", {"n":16, "life":0.35, "size":0.6, "y":0.0, "grav":Vector3(0, 1.0, 0), "fade":"hot"})
		"arrow":
			if sp == "snare":
				trail(node, Color("#8fe36a"), 30.0, "leaf", {"n":14, "life":0.45, "size":0.28, "y":0.0, "grav":Vector3(0, -0.8, 0)})
				trail(node, Color("#e8ffd0"), 30.0, "streak", {"n":12, "life":0.25, "size":0.5, "y":0.0, "grav":Vector3.ZERO})
			elif bool(p.get("big", false)):
				trail(node, Color("#cfe8b8"), 30.0, "streak", {"n":20, "life":0.3, "size":0.7, "y":0.0, "grav":Vector3.ZERO})

# ======================================================================================================================
# what lasts (siege_view._sync_kits and _sync_auras hand over here, each frame)
# ======================================================================================================================
func sync_unit(id: String, u: Dictionary, a: Dictionary, vis: bool) -> void:
	# a hero's lasting states: a shield's bubble, a slow's frost, a mark or curse, a stone or bark skin, a parry's
	# glints, poison, a dash's trail, the ultimates' auras and the jungle buffs
	var sim = view.sim
	var t: float = sim.time
	var root: Node3D = a.root
	var hid := str(u.get("hid", ""))
	# shield
	var want_shield: bool = vis and float(u.get("shield", 0.0)) > 0.0 and t < float(u.get("shield_until", -1.0))
	if want_shield and not holding("shield:" + id):
		var st: Dictionary = _shield_style.get(id, {"col":Color("#7fb8ff"), "style":0})
		shell(root, st.col, 0.95, 2.3, int(st.style), -1.0, {"key":"shield:" + id, "alive":_alive_while(id, func(uu): return float(uu.get("shield", 0.0)) > 0.0 and sim.time < float(uu.get("shield_until", -1.0))), "energy":0.9})
	elif not want_shield and holding("shield:" + id):
		release("shield:" + id)
	# slow: frost drifting round his feet
	var want_slow: bool = vis and t < float(u.get("slow_until", -1.0))
	if want_slow and not holding("slow:" + id):
		var d := disc(Vector2.ZERO, Color("#9fd4ff"), 0.9, -1.0, 1, {"tex":"swirl", "spin":-2.0, "key":"slow:" + id, "alive":_alive_until(id, "slow_until"), "rim":0.4, "flat":true})
		d.reparent(root, false)
		d.position = Vector3(0, 0.1, 0)
	elif not want_slow and holding("slow:" + id):
		release("slow:" + id)
	# a mark or a curse
	var want_amp: bool = vis and t < float(u.get("amp_until", -1.0))
	if want_amp and not holding("amp:" + id):
		var st2: Dictionary = _amp_style.get(id, {"col":Color("#ff4a4a"), "tex":"rays", "spin":2.5})
		var d2 := disc(Vector2.ZERO, st2.col, 1.1, -1.0, 1, {"tex":str(st2.tex), "spin":float(st2.spin), "key":"amp:" + id, "alive":_alive_until(id, "amp_until"), "rim":0.6, "flat":true})
		d2.reparent(root, false)
		d2.position = Vector3(0, 0.12, 0)
	elif not want_amp and holding("amp:" + id):
		release("amp:" + id)
	# stone or bark
	var want_skin: bool = vis and t < float(u.get("skin_until", -1.0))
	if want_skin and not holding("skin:" + id):
		var st3: Dictionary = _skin_style.get(id, {"col":Color("#b8b2a4") if hid == "golem" else Color("#a07a4a")})
		shell(root, st3.col, 0.9, 2.2, 1, -1.0, {"key":"skin:" + id, "alive":_alive_until(id, "skin_until"), "energy":0.7, "speed":0.3})
	elif not want_skin and holding("skin:" + id):
		release("skin:" + id)
	# a parry
	var want_parry: bool = vis and u.has("riposte")
	if want_parry and not holding("parry:" + id):
		_hold("parry:" + id, [burst(Vector3(0, 1.1, 0), Color("#ffe27a"), {"n":20, "life":0.5, "size":0.6, "tex":"crescent", "core":0.7, "shape":"ring",
			"r":0.8, "inner":0.9, "h":0.1, "dir":Vector3.UP, "spread":10.0, "vel":[0.0, 0.2], "orbit":3.0, "fade":"slow", "angle":180.0, "spin":200.0,
			"dur":5.0, "parent":root, "explode":0.0, "local":true})], _alive_while(id, func(uu): return uu.has("riposte")))
	elif not want_parry and holding("parry:" + id):
		release("parry:" + id)
	# poison ticking on him
	var want_dots: bool = vis and u.has("dots") and not view.low_fx and hid != "" and not holding("rejuv:" + id)
	if want_dots and not holding("dots:" + id):
		_hold("dots:" + id, [burst(Vector3(0, 1.0, 0), Color("#7dff6a"), {"n":20, "life":0.9, "size":0.26, "tex":"dot", "core":0.8, "shape":"sphere", "r":0.4,
			"vel":[0.2, 0.8], "grav":Vector3(0, 1.5, 0), "fade":"slow", "dur":30.0, "parent":root, "explode":0.0, "shape_life":"shrink"})],
			_alive_while(id, func(uu): return uu.has("dots")))
	elif not want_dots and holding("dots:" + id):
		release("dots:" + id)
	# the Berserker's whirlwind: the dust it kicks and the crescents round it (the ribbon is the view's)
	var want_whirl: bool = vis and view.sim.whirling(u)
	if want_whirl and not holding("whirl:" + id):
		q("whirlwind", a, u)
	elif not want_whirl and holding("whirl:" + id):
		release("whirl:" + id)
	# a dash's trail
	var want_dash: bool = vis and u.state == "dash"
	if want_dash and not holding("dash:" + id):
		var ds: Dictionary = _dash_style.get(id, {})
		if ds.is_empty() or _time - float(ds.at) > 1.5:
			ds = {"col":Color("#e0d0b0"), "tex":"streak"}
		var nm := str(ds.tex)
		var o := {"n":60, "life":0.45, "size":0.6 if nm != "smoke" else 1.2, "y":0.8 if nm != "smoke" else 0.3, "alpha":0.8}
		if nm == "smoke":
			o["alpha"] = 0.5
			o["blend"] = "mix"
			o["shape_life"] = "swell"
			o["fade"] = "late"
		elif nm == "flame":
			o["grav"] = Vector3(0, 2.0, 0)
			o["fade"] = "hot"
		_hold("dash:" + id, [trail(root, ds.col, 3.0, nm, o)], _alive_while(id, func(uu): return uu.state == "dash"))
	elif not want_dash and holding("dash:" + id):
		release("dash:" + id)
	# the ultimates' auras
	_aura(id, u, root, vis, "dr", t < float(u.get("dr_until", -1.0)) and not (t < float(u.get("skin_until", -1.0))), Color("#ffd65a"), "star")
	_aura(id, u, root, vis, "bl", t < float(u.get("bl_until", -1.0)) or t < float(u.get("ls_until", -1.0)), Color("#ff5a3a"), "flame")
	_aura(id, u, root, vis, "ud", t < float(u.get("ud_until", -1.0)), Color("#ff2a2a"), "crescent")
	var b: Dictionary = u.get("buffs", {})
	_aura(id, u, root, vis, "arcane", t < float(b.get("arcane", -1.0)), Color("#7fb8ff"), "runes")
	_aura(id, u, root, vis, "ember", t < float(b.get("ember", -1.0)), Color("#ff8a3a"), "dot")
	_aura(id, u, root, vis, "lord", t < float(b.get("lord", -1.0)), Color("#c9a6ff"), "sparkle")

func _aura(id: String, _u: Dictionary, root: Node3D, vis: bool, kind: String, on: bool, col: Color, nm: String) -> void:
	var key := kind + ":" + id
	var want: bool = vis and on and not view.low_fx
	if want and not holding(key):
		var nodes := []
		match kind:
			"dr":
				nodes.append(burst(Vector3(0, 1.0, 0), col, {"n":24, "life":1.2, "size":0.5, "tex":nm, "core":0.9, "shape":"ring", "r":0.9, "inner":0.9,
					"h":1.4, "dir":Vector3.UP, "spread":10.0, "vel":[0.1, 0.4], "orbit":1.5, "fade":"slow", "shape_life":"pop", "angle":180.0,
					"spin":60.0, "dur":30.0, "parent":root, "explode":0.0, "local":true}))
			"bl":
				nodes.append(burst(Vector3(0, 0.2, 0), col, {"n":36, "life":0.7, "size":1.3, "tex":nm, "core":0.7, "shape":"ring", "r":0.7, "inner":0.3,
					"h":0.3, "dir":Vector3.UP, "spread":20.0, "vel":[1.0, 2.2], "grav":Vector3(0, 2.5, 0), "shape_life":"shrink", "fade":"hot",
					"angle":12.0, "spin":20.0, "dur":30.0, "parent":root, "explode":0.0}))
			"ud":
				nodes.append(shell(root, Color("#7a0c0c"), 1.0, 2.3, 2, 1e9, {"energy":1.2, "speed":3.0, "in":0.3}))
				nodes.append(burst(Vector3(0, 1.0, 0), col, {"n":24, "life":0.7, "size":0.8, "tex":nm, "core":0.5, "shape":"ring", "r":1.1, "inner":0.8,
					"h":1.2, "dir":Vector3.UP, "spread":20.0, "vel":[0.2, 0.6], "orbit":2.5, "fade":"hot", "angle":180.0, "spin":400.0, "dur":30.0,
					"parent":root, "explode":0.0, "local":true}))
			_:
				nodes.append(burst(Vector3(0, 0.6, 0), col, {"n":20, "life":1.4, "size":0.45, "tex":nm, "core":0.7, "shape":"ring", "r":0.7, "inner":0.6,
					"h":0.8, "dir":Vector3.UP, "spread":15.0, "vel":[0.3, 0.8], "orbit":0.8, "fade":"slow", "shape_life":"pop", "angle":180.0,
					"spin":40.0, "dur":30.0, "parent":root, "explode":0.0, "local":true, "grid":2.0 if nm == "runes" else 1.0}))
		for n in nodes:
			if n is MeshInstance3D:
				for i in range(_live.size() - 1, -1, -1):
					if _live[i].node == n:
						_live.remove_at(i)                      # (held, not timed)
		var until_key: String = {"dr":"dr_until", "bl":"bl_until", "ud":"ud_until"}.get(kind, "")
		var alive: Callable
		if until_key != "":
			alive = _alive_while(id, func(uu): return (view.sim.time < float(uu.get(until_key, -1.0)) and not (kind == "dr" and view.sim.time < float(uu.get("skin_until", -1.0)))) or (kind == "bl" and view.sim.time < float(uu.get("ls_until", -1.0))))
		else:
			alive = _alive_while(id, func(uu): return view.sim.time < float((uu.get("buffs", {}) as Dictionary).get(kind, -1.0)))
		_hold(key, nodes, alive, 0.5, 0.2)
	elif not want and holding(key):
		release(key)

func zone(z: Dictionary) -> Array:
	# a zone's look while it lasts (siege_view._sync_kits): what's on the ground, by the spell; returns the nodes to free
	var c: Vector2 = z.at
	var r := float(z.r)
	var sp := str(z.spell)
	var nodes := []
	var key := "zone:%d" % int(z.zid)
	var kits = view.sim.moba.kits
	var zid := int(z.zid)
	var alive := func():
		for zz in kits.zones:
			if int(zz.zid) == zid:
				return true
		return false
	var at := _g(c, 0.0)
	match sp:
		"consecrate":
			nodes.append(disc(c, Color("#ffe9a6"), r, -1.0, 1, {"tex":"rays", "spin":0.9, "key":key, "alive":alive, "grow":0.3, "out":0.5}))
			nodes.append(burst(at + Vector3(0, 0.2, 0), Color("#fff6d8"), {"n":30, "life":1.4, "size":0.4, "tex":"sparkle", "core":0.9, "shape":"ring",
				"r":r * 0.9, "inner":0.0, "h":0.1, "dir":Vector3.UP, "spread":10.0, "vel":[0.4, 1.0], "fade":"slow", "shape_life":"pop", "angle":180.0,
				"spin":60.0, "dur":60.0, "explode":0.0}))
		"caltrops":
			nodes.append(disc(c, Color("#b8b8b8"), r, -1.0, 0, {"key":key, "alive":alive, "rim":0.5, "energy":0.7, "out":0.4}))
			nodes.append(burst(at + Vector3(0, 0.15, 0), Color("#e8e8e8"), {"n":24, "life":1.0, "size":0.3, "tex":"sparkle", "core":1.0, "shape":"ring",
				"r":r * 0.9, "inner":0.0, "h":0.05, "vel":[0.0, 0.05], "fade":"flicker", "shape_life":"pop", "angle":180.0, "dur":60.0, "explode":0.0}))
		"static":
			nodes.append(disc(c, Color("#6fb4ff"), r, -1.0, 3, {"key":key, "alive":alive, "energy":1.2, "out":0.3}))
			nodes.append(burst(at + Vector3(0, 0.3, 0), Color("#9fd4ff"), {"n":30, "life":0.35, "size":0.8, "tex":"lightning", "core":0.9, "shape":"ring",
				"r":r * 0.9, "inner":0.0, "h":0.4, "vel":[0.2, 1.0], "fade":"flicker", "angle":180.0, "spin":100.0, "dur":60.0, "explode":0.0}))
		"smoke":
			nodes.append(burst(at + Vector3(0, 0.6, 0), Color("#b8b8b8"), {"n":18, "life":1.8, "size":1.8, "tex":"smoke", "core":0.0, "blend":"mix", "shape":"ring",
				"r":r * 0.7, "inner":0.0, "h":0.4, "dir":Vector3.UP, "spread":40.0, "vel":[0.2, 0.6], "damp":1.0, "shape_life":"swell", "fade":"slow",
				"alpha":0.6, "angle":180.0, "spin":20.0, "dur":60.0, "explode":0.0, "rand":0.4}))
			_hold(key, [], alive)
		"wildgrowth":
			nodes.append(disc(c, Color("#6aff7a"), r, -1.0, 4, {"key":key, "alive":alive, "grow":0.5, "out":0.8, "energy":1.1}))
			nodes.append(burst(at + Vector3(0, 0.2, 0), Color("#8dff6a"), {"n":40, "life":1.8, "size":0.36, "tex":"leaf", "core":0.3, "shape":"ring",
				"r":r * 0.9, "inner":0.0, "h":0.1, "dir":Vector3.UP, "spread":30.0, "vel":[0.6, 1.4], "grav":Vector3(0, -0.3, 0), "turb":1.0,
				"angle":180.0, "spin":150.0, "fade":"slow", "dur":60.0, "explode":0.0}))
			nodes.append(burst(at + Vector3(0, 0.2, 0), Color("#d8ffb0"), {"n":30, "life":1.4, "size":0.36, "tex":"sparkle", "core":0.9, "shape":"ring",
				"r":r * 0.9, "inner":0.0, "h":0.1, "dir":Vector3.UP, "spread":10.0, "vel":[0.5, 1.2], "fade":"slow", "shape_life":"pop", "angle":180.0,
				"spin":60.0, "dur":60.0, "explode":0.0}))
		"thunderstorm":
			nodes.append(disc(c, Color("#4a78c8"), r, -1.0, 3, {"key":key, "alive":alive, "energy":1.0, "out":0.5, "rim":0.9}))
		"pillar":
			nodes.append(disc(c, Color("#ff6a3a"), r, -1.0, 1, {"tex":"runes", "spin":5.0, "key":key, "alive":alive, "energy":1.3, "in":0.08, "out":0.08}))
		"entangle":
			nodes.append(disc(c, Color("#6fbf3a"), r + 0.3, -1.0, 4, {"key":key, "alive":alive, "energy":1.3, "in":0.08, "out":0.1}))
		_:
			nodes.append(disc(c, Color("#ffffff"), r, -1.0, 0, {"key":key, "alive":alive}))
	if _holds.has(key):
		for n in nodes:
			if not (_holds[key].nodes as Array).has(n):
				(_holds[key].nodes as Array).append(n)
				for i in range(_live.size() - 1, -1, -1):
					if _live[i].node == n:
						_live.remove_at(i)
	return nodes

func trap_node(at: Vector3, team_col: Color) -> Node3D:
	# a bear trap of your side: two iron jaws open on the ground and a glint between them
	var root := Node3D.new()
	root.position = at
	for s in [-1.0, 1.0]:
		var jaw := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.34
		tm.outer_radius = 0.44
		tm.rings = 16
		tm.ring_segments = 4
		jaw.mesh = tm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.32, 0.3, 0.28)
		m.metallic = 0.7
		m.roughness = 0.45
		jaw.material_override = m
		jaw.scale = Vector3(1.0, 0.5, 0.55)
		jaw.position = Vector3(0, 0.05, s * 0.2)
		jaw.rotation.x = s * 0.5
		root.add_child(jaw)
	var glint := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * 0.5
	glint.mesh = q
	glint.material_override = sprite_mat("sparkle", 0.9, team_col, 1.0, false, 0.0)
	glint.position = Vector3(0, 0.15, 0)
	root.add_child(glint)
	add_child(root)
	return root
