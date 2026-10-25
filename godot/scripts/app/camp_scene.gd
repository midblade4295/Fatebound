extends Control
# 0.31.194 (Kevin: "Now let's design a new home screen" -- he picked B2, the champions' camp): Home's backdrop -- six
# champions round a campfire in the castle's courtyard at dusk, the castle behind them, its windows lit -- the painting
# (tools/home_camp.py: art_sources/home_camp/camp.png, 1024 x 2048) brought to life:
#   - the campfire burns: tongues of flame over the painted ones, swaying and flickering, a hot heart, its glow breathing,
#     embers spiralling up and a thin smoke over it, and its light flickering over the champions and the stones round it
#     (camp.gdshader, with the flames);
#   - the lanterns, the gate's torches and the candle on the Necromancer's crate flicker, each throwing a little light;
#   - the Necromancer's eyes and the skull in his hand glow green and breathe, wisps curling off them; the Mage's spell
#     orb pulses blue over his book, sparkles rising off the page;
#   - the castle's windows glow, now and then one dimming as someone passes; stars twinkle; now and then a star falls;
#   - fireflies wander the camp; the two big banners ripple; the towers' pennants flutter (camp.gdshader).
# Everything is laid out in the painting's px, scaled by `place` to the screen's width (a little wider if the screen is
# tall enough to need it), standing so the champions' feet are just over the PLAY plaque. Reduce Motion (`calm`): the
# glows hold still, no particles, nothing moves. A safe start (`lite`): the painting and its still glows only.
# (0.31.138-0.31.193: the war room -- home_scene.gd, war_room.gd: a painted tower room and the live war table in 3D.)
# 0.31.215 (Kevin: "I want the home screen as good of quality as the clan screen. The home screen looks very AI
# generated." -> "Real 3D heroes in camp"): the picture is now a 3D render of the game's own models
# (tools/render_home_camp.gd) -- the Royal kit's castle at dusk, the War kit's tents and braziers, the HD Knight, Mage,
# King, Barbarian and Stormcaller round a campfire, a sky with stars and the moon -- in place of the painting (0.31.194-
# 0.31.214, tools/home_camp.py). Over it, as before: the fire's flames, halo, embers and smoke and its light flickering
# on the picture, stars twinkling and falling, fireflies, the banners rippling; the magic is the Mage's blue gem and the
# Stormcaller's crystal, glowing and sparkling (the painting's Necromancer, his eyes and skull, and its lit windows are
# gone with it).
const UI2 = preload("res://scripts/app/ui2.gd")
const CampShader = preload("res://scripts/app/camp.gdshader")
const ART := "res://assets/ui/v2/bg_camp.webp"
const PAINT := Vector2(1024.0, 2048.0)
const FEET_Y := 1257.0                 # the nearest heroes' boots (the Knight's, the Stormcaller's), down the picture
const FEET_OVER := 6.0                 # ... this far (screen px) under PLAY's top at most: the plaque hides no more of them
const COVER_TO := 100.0                # the painting reaches at least this far (screen px) from the screen's bottom
const FIRE := Vector2(512.0, 1086.0)   # the campfire's flames (their middle)
const FIRE_BASE := Vector2(512.0, 1166.0)
# the flames' tongues over the painted fire: [x off the base, width, height, phase]
const TONGUES := [[-36.0, 44.0, 96.0, 0.0], [-15.0, 56.0, 150.0, 1.9], [8.0, 62.0, 172.0, 3.7], [30.0, 50.0, 118.0, 5.1],
	[46.0, 34.0, 74.0, 2.6], [-50.0, 30.0, 64.0, 4.4]]
# the braziers and torches you can see: [where, size, light's reach (0: none)]
const LAMPS := []
# the magic glowing on the heroes: [where, colour, size] -- the Mage's blue gem, the Stormcaller's crystal
const MAGIC := [[Vector2(212, 838), Color(0.45, 0.8, 1.0), 1.0], [Vector2(722, 776), Color(0.55, 0.95, 1.0), 1.1]]
const WINDOWS := []                    # (the castle's windows are dark at dusk in the render)
const SKY := Rect2(0.0, 0.0, 1024.0, 280.0)     # where the stars twinkle (and the falling ones go): above the spires
const CAMP := Rect2(40.0, 736.0, 944.0, 520.0)  # where the fireflies wander
const BANNERS := [Vector4(100, 466, 230, 666), Vector4(795, 466, 915, 666)]
const PENNANTS := []
const FLAME := Color(1.0, 0.62, 0.26)

var calm := false
var lite := false
var k := 1.0                            # painting px -> screen px
var origin := Vector2.ZERO              # the painting's top left on the screen
var paint_layer: Control                # the painting and everything on it, in painting px (scaled)
var art: TextureRect
var room = null                         # (the war room's 3D; the camp has none -- siege_app reads it)
var embers: CPUParticles2D
var smoke: CPUParticles2D
var wisps: Array = []                   # the magic's sparkles (one stream each)
var flies: Node2D
var _fire_halo: TextureRect
var _fire_heart: TextureRect
var _tongues: Array = []                # [TextureRect, phase, height]
var _lamps: Array = []                  # {core, halo, phase, a}
var _pulses: Array = []                 # [TextureRect, base alpha, rate, phase, depth] (the magic's glows)
var _windows: Array = []                # [TextureRect, base alpha, next dim, dim until]
var _stars: Array = []                  # [TextureRect, rate, phase]
var _shooting: Node2D
var _clock := 0.0
var flick := 0.0                        # the fire's flicker now (-1..1)
static var _glow_t: Texture2D = null    # one soft round glow for every light here
static var _dot_t: Texture2D = null     # ... and one dot for the particles

static func glow_texture() -> Texture2D:
	if _glow_t == null:
		_glow_t = UI2.glow_tex()
	return _glow_t

class Fireflies extends Node2D:
	# little lights wandering the camp, each blinking on and off in its own time
	var area := Rect2()
	var tex: Texture2D                  # (camp_scene's one glow texture: a fresh one each frame drew a square)
	var flies: Array = []               # {p, v, phase, rate, size}
	func setup(n: int) -> void:
		for i in n:
			flies.append({"p": Vector2(randf_range(area.position.x, area.end.x), randf_range(area.position.y, area.end.y)),
				"v": Vector2(randf_range(-14.0, 14.0), randf_range(-10.0, 10.0)), "phase": randf() * TAU,
				"rate": randf_range(0.5, 1.2), "size": randf_range(9.0, 15.0), "turn": randf() * TAU})
	func _process(delta: float) -> void:
		for f in flies:
			f.turn += randf_range(-1.6, 1.6) * delta
			f.v = f.v.lerp(Vector2(cos(f.turn), sin(f.turn) * 0.7) * 16.0, minf(1.0, delta * 0.8))
			f.p += f.v * delta
			if not area.has_point(f.p):              # (turned back in at the edges)
				f.turn = (area.get_center() - f.p).angle()
			f.phase += delta * f.rate
		queue_redraw()
	func _draw() -> void:
		for f in flies:
			var a := pow(maxf(0.0, sin(f.phase * TAU * 0.5)), 2.0)
			if a < 0.02:
				continue
			var s: float = f.size * (0.7 + 0.3 * a)
			draw_texture_rect(tex, Rect2(f.p - Vector2(s, s) * 1.6, Vector2(s, s) * 3.2), false, Color(0.75, 1.0, 0.35, 0.35 * a))
			draw_texture_rect(tex, Rect2(f.p - Vector2(s, s) * 0.35, Vector2(s, s) * 0.7), false, Color(1.0, 1.0, 0.7, 0.95 * a))

class FallingStar extends Node2D:
	# now and then a star falls across the sky
	var area := Rect2()
	var tex: Texture2D
	var t := -1.0
	var wait := 6.0
	var from := Vector2.ZERO
	var dir := Vector2.ZERO
	var made := 0
	func _process(delta: float) -> void:
		if t < 0.0:
			wait -= delta
			if wait <= 0.0:
				t = 0.0
				made += 1
				from = Vector2(randf_range(area.position.x + 100.0, area.end.x - 100.0), randf_range(area.position.y + 10.0, area.end.y * 0.6))
				dir = Vector2(-1.0 if randf() < 0.5 else 1.0, randf_range(0.3, 0.55)).normalized()
		else:
			t += delta
			if t > 0.9:
				t = -1.0
				wait = randf_range(9.0, 20.0)
		queue_redraw()
	func _draw() -> void:
		if t < 0.0:
			return
		var head := from + dir * 420.0 * t
		var a := sin(clampf(t / 0.9, 0.0, 1.0) * PI)
		for i in 10:
			var f := float(i) / 10.0
			draw_line(head - dir * 90.0 * f, head - dir * 90.0 * (f + 0.1), Color(1.0, 0.97, 0.85, a * (1.0 - f) * 0.9), 3.0 * (1.0 - f) + 0.6, true)
		draw_texture_rect(tex, Rect2(head - Vector2(10, 10), Vector2(20, 20)), false, Color(1, 1, 0.9, a))

func _init(reduce_motion := false, safe := false) -> void:
	calm = reduce_motion
	lite = safe

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	paint_layer = Control.new()
	paint_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paint_layer.size = PAINT
	add_child(paint_layer)
	art = TextureRect.new()
	art.texture = UI2.tex(ART)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.size = PAINT
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_meta("home_art", true)
	var m := ShaderMaterial.new()
	m.shader = CampShader
	m.set_shader_parameter("paint_size", PAINT)
	m.set_shader_parameter("motion", 0.0 if calm else 1.0)
	m.set_shader_parameter("fire", Vector3(FIRE.x, FIRE.y + 20.0, 360.0))
	var lamps := []
	for i in LAMPS.size():
		if float(LAMPS[i][2]) > 0.0:
			lamps.append(Vector4(LAMPS[i][0].x, LAMPS[i][0].y, float(LAMPS[i][2]), 1.7 * i))
	if not lamps.is_empty():                       # (0.31.215: the render may have none in view)
		m.set_shader_parameter("lamps", lamps)
	m.set_shader_parameter("lamp_n", lamps.size())
	if not BANNERS.is_empty():
		m.set_shader_parameter("cloth", BANNERS)
	m.set_shader_parameter("cloth_n", BANNERS.size())
	if not PENNANTS.is_empty():
		m.set_shader_parameter("pennants", PENNANTS)
	m.set_shader_parameter("pennant_n", PENNANTS.size())
	art.material = m
	paint_layer.add_child(art)
	_build_sky()
	_build_windows()
	_build_fire()
	for i in LAMPS.size():
		_lamp(LAMPS[i][0], float(LAMPS[i][1]), i)
	_build_magic()
	if not calm and not lite:
		flies = Fireflies.new()
		flies.tex = glow_texture()
		flies.area = CAMP
		flies.setup(14)
		paint_layer.add_child(flies)

func _glow(parent: Control, centre: Vector2, sz: Vector2, col: Color, add := true) -> TextureRect:
	var t := TextureRect.new()
	t.texture = glow_texture()
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.size = sz
	t.pivot_offset = sz * 0.5
	t.position = centre - sz * 0.5
	t.modulate = col
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if add:
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		t.material = mat
	parent.add_child(t)
	return t

static func _dot_tex() -> Texture2D:
	if _dot_t != null:
		return _dot_t
	var t := GradientTexture2D.new()
	t.width = 24
	t.height = 24
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.add_point(0.35, Color(1, 1, 1, 0.75))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	t.gradient = g
	_dot_t = t
	return t

func _particles(at: Vector2, n: int, life: float, ramp: Array, add := true) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = at
	p.amount = n
	p.lifetime = life
	p.preprocess = life
	p.texture = _dot_tex()
	p.local_coords = false
	var g := Gradient.new()
	g.set_color(0, ramp[0])
	for i in range(1, ramp.size() - 1):
		g.add_point(float(i) / float(ramp.size() - 1), ramp[i])
	g.set_color(g.get_point_count() - 1, ramp[ramp.size() - 1])
	p.color_ramp = g
	if add:
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		p.material = mat
	p.emitting = not calm and not lite
	paint_layer.add_child(p)
	return p

# ---------------- the sky and the castle ----------------
func _build_sky() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 194
	for i in 18:
		var at := Vector2(rng.randf_range(20.0, 1004.0), rng.randf_range(10.0, SKY.end.y))
		var st := _glow(paint_layer, at, Vector2.ONE * rng.randf_range(9.0, 16.0), Color(0.95, 0.93, 1.0, 0.0 if not calm else 0.35))
		_stars.append([st, rng.randf_range(0.4, 1.2), rng.randf() * TAU])
	_shooting = FallingStar.new()
	_shooting.tex = glow_texture()
	_shooting.area = SKY
	_shooting.wait = 4.0
	paint_layer.add_child(_shooting)
	if calm or lite:
		_shooting.process_mode = Node.PROCESS_MODE_DISABLED

func _build_windows() -> void:
	for i in WINDOWS.size():
		var a := 0.32
		var g := _glow(paint_layer, WINDOWS[i], Vector2(46, 46), Color(1.0, 0.78, 0.4, a))
		_windows.append([g, a, randf_range(3.0, 14.0) + i * 1.3, 0.0])

# ---------------- the campfire ----------------
func _build_fire() -> void:
	_fire_halo = _glow(paint_layer, FIRE + Vector2(0, 30), Vector2(520, 420), Color(1.0, 0.5, 0.18, 0.32))
	smoke = _particles(FIRE + Vector2(0, -90), 14, 4.5, [Color(0.35, 0.3, 0.32, 0.0), Color(0.35, 0.3, 0.32, 0.16),
		Color(0.3, 0.28, 0.32, 0.1), Color(0.3, 0.28, 0.32, 0.0)], false)
	smoke.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	smoke.emission_rect_extents = Vector2(18, 6)
	smoke.direction = Vector2(0.15, -1.0)
	smoke.spread = 10.0
	smoke.gravity = Vector2(6, -4)
	smoke.initial_velocity_min = 20.0
	smoke.initial_velocity_max = 34.0
	smoke.scale_amount_min = 2.2
	smoke.scale_amount_max = 3.6
	smoke.scale_amount_curve = _rising_curve()
	for tg in TONGUES:
		var w: float = tg[1]
		var h: float = tg[2]
		var t := _glow(paint_layer, Vector2.ZERO, Vector2(w, h), Color(1.0, 0.55, 0.16, 0.85))
		t.pivot_offset = Vector2(w * 0.5, h * 0.92)
		t.position = FIRE_BASE + Vector2(float(tg[0]), 0.0) - t.pivot_offset
		_tongues.append([t, float(tg[3]), h])
	_fire_heart = _glow(paint_layer, FIRE_BASE + Vector2(0, -34), Vector2(84, 74), Color(1.0, 0.92, 0.62, 0.8))
	embers = _particles(FIRE_BASE + Vector2(0, -40), 26, 2.6, [Color(1.0, 0.95, 0.7, 1.0), Color(1.0, 0.7, 0.25, 1.0),
		Color(1.0, 0.4, 0.1, 0.8), Color(0.9, 0.2, 0.05, 0.0)])
	embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	embers.emission_rect_extents = Vector2(36, 18)
	embers.direction = Vector2(0, -1)
	embers.spread = 22.0
	embers.gravity = Vector2(0, -30)
	embers.initial_velocity_min = 50.0
	embers.initial_velocity_max = 120.0
	embers.tangential_accel_min = -30.0
	embers.tangential_accel_max = 30.0
	embers.scale_amount_min = 0.18
	embers.scale_amount_max = 0.42

static func _rising_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.4))
	c.add_point(Vector2(1.0, 1.0))
	return c

func _lamp(at: Vector2, s: float, i: int) -> void:
	# a lantern's (or torch's, or candle's) flame: its halo and a bright core that flickers and sways
	var halo := _glow(paint_layer, at, Vector2(120, 120) * s, Color(FLAME, 0.36))
	var core := _glow(paint_layer, at, Vector2(16, 30) * s, Color(1.0, 0.78, 0.4, 0.85))
	core.pivot_offset = Vector2(core.size.x * 0.5, core.size.y * 0.85)
	core.position = at - core.pivot_offset + Vector2(0, core.size.y * 0.35)
	_lamps.append({"core": core, "halo": halo, "phase": randf() * TAU + i * 1.37, "a": halo.modulate.a})

# ---------------- the magic: the Mage's gem, the Stormcaller's crystal ----------------
func _build_magic() -> void:
	for i in MAGIC.size():
		var at: Vector2 = MAGIC[i][0]
		var col: Color = MAGIC[i][1]
		var sz: float = MAGIC[i][2]
		_pulses.append([_glow(paint_layer, at, Vector2(96, 96) * sz, Color(col, 0.5)), 0.5, 1.5 + 0.3 * i, 0.7 * i, 0.4])
		_pulses.append([_glow(paint_layer, at, Vector2(24, 24) * sz, Color(0.9, 0.97, 1.0, 0.75)), 0.75, 1.5 + 0.3 * i, 0.7 * i, 0.25])
		var sp := _particles(at + Vector2(0, -6), 9, 1.9, [Color(col, 0.0), Color(0.85, 0.97, 1.0, 0.9), Color(col, 0.5),
			Color(col, 0.0)])
		sp.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		sp.emission_sphere_radius = 14.0 * sz
		sp.direction = Vector2(0, -1)
		sp.spread = 30.0
		sp.gravity = Vector2(0, -8)
		sp.initial_velocity_min = 10.0
		sp.initial_velocity_max = 24.0
		sp.scale_amount_min = 0.15
		sp.scale_amount_max = 0.35
		wisps.append(sp)

# ---------------- layout ----------------
func place(play_top: float) -> void:
	# the painting as wide as the screen (wider if it'd stop too high), standing so the champions' feet are just over
	# PLAY -- but never ending more than COVER_TO over the screen's bottom, nor leaving a gap at its top
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return
	k = maxf(w / PAINT.x, (h - COVER_TO) / PAINT.y)
	var lo := minf(0.0, (h - COVER_TO) - PAINT.y * k)
	origin = Vector2((w - PAINT.x * k) * 0.5, clampf(play_top + FEET_OVER - FEET_Y * k, lo, 0.0))
	paint_layer.position = origin
	paint_layer.scale = Vector2(k, k)

func painting_bottom() -> float:
	return origin.y + PAINT.y * k

func to_screen(p: Vector2) -> Vector2:
	return origin + p * k

# (the war room's: Home's heroes in their looks, the live war on the table -- the camp is painted)
func set_looks(_looks: Dictionary) -> void:
	pass

func paint_war(_war: Dictionary) -> void:
	pass

# ---------------- alive ----------------
func _process(delta: float) -> void:
	if not is_visible_in_tree() or calm:
		return
	_clock += delta
	var t := _clock
	# the fire: the tongues sway and leap; the heart and the halo breathe with them; its light on the painting too
	flick = 0.55 * sin(t * 7.3) + 0.3 * sin(t * 13.1 + 1.3) + 0.15 * sin(t * 2.1 + 0.4)
	for tg in _tongues:
		var tr: TextureRect = tg[0]
		var ph: float = tg[1]
		var f := 0.5 + 0.25 * sin(t * 8.7 + ph) + 0.17 * sin(t * 14.9 + ph * 1.7) + 0.08 * sin(t * 3.1 + ph * 0.6)
		tr.scale = Vector2(0.85 + 0.2 * (1.0 - f), 0.72 + 0.5 * f)
		tr.rotation = 0.12 * sin(t * 2.3 + ph) + 0.06 * sin(t * 6.7 + ph)
		tr.modulate.a = 0.6 + 0.3 * f
	_fire_heart.modulate.a = 0.62 + 0.18 * flick
	_fire_heart.scale = Vector2.ONE * (0.95 + 0.08 * flick)
	_fire_halo.modulate.a = 0.3 + 0.08 * flick
	_fire_halo.scale = Vector2.ONE * (0.97 + 0.05 * flick)
	var m := art.material as ShaderMaterial
	m.set_shader_parameter("clock", t)
	m.set_shader_parameter("fire_flick", flick)
	for l in _lamps:
		var ph: float = l.phase
		var fl := 0.5 + 0.22 * sin(t * 9.3 + ph) + 0.16 * sin(t * 15.1 + ph * 1.7) + 0.12 * sin(t * 3.7 + ph * 0.6)
		var core: TextureRect = l.core
		var halo: TextureRect = l.halo
		core.scale = Vector2(0.92 + 0.1 * fl, 0.84 + 0.3 * fl)
		core.rotation = 0.09 * sin(t * 2.3 + ph) + 0.05 * sin(t * 6.1 + ph)
		halo.modulate.a = float(l.a) * (0.7 + 0.55 * fl)
		halo.scale = Vector2.ONE * (0.92 + 0.14 * fl)
	for p in _pulses:
		var g: TextureRect = p[0]
		var v := 0.5 + 0.5 * sin(t * float(p[2]) * TAU * 0.5 + float(p[3]))
		g.modulate.a = float(p[1]) * (1.0 - float(p[4]) + float(p[4]) * v)
		g.scale = Vector2.ONE * (0.94 + 0.12 * v)
	for wd in _windows:
		var g: TextureRect = wd[0]
		wd[2] = float(wd[2]) - delta
		if float(wd[2]) <= 0.0:                  # someone passes the window: it dims a moment
			wd[3] = randf_range(0.6, 1.6)
			wd[2] = randf_range(6.0, 18.0)
		var dim := 0.0
		if float(wd[3]) > 0.0:
			wd[3] = float(wd[3]) - delta
			dim = 0.7
		g.modulate.a = lerpf(g.modulate.a, float(wd[1]) * (1.0 - dim) * (0.9 + 0.1 * sin(t * 3.0 + g.position.x)), minf(1.0, delta * 6.0))
	for s in _stars:
		var st: TextureRect = s[0]
		st.modulate.a = 0.8 * pow(maxf(0.0, sin(t * float(s[1]) + float(s[2]))), 3.0)
