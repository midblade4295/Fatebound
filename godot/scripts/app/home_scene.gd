extends Control
# 0.31.138 (Kevin picked the war room concept for Home: "Make sure to bring the scene to life with candles emitting
# light glow along with the glow effect of sun. Also maybe glimmer of the water and birds flying in sky ect ect"):
# Home's backdrop -- the war room at the top of a tower at dusk, its great arched window open on the land and the
# rival castles -- with the live war table and the heroes in 3D standing in it (war_room.gd), and the scene alive:
#   - the sun setting on the sea: a breathing glow and slow rays, seen only through the window;
#   - the water in the view (the river, the lake, the sea) shimmering and glinting (home_room.gdshader);
#   - birds crossing the sky in small flocks, flapping and gliding; cloud wisps drifting; the first stars twinkling;
#   - every candle (the painted ones on the stands and the sill, and those on the table's rim) flickering, its warm
#     halo breathing; motes of dust drifting in the light.
# The painting (tools/home_war_room.py: art_sources/home_war_room/room.png) is 1152 x 2560; everything here is laid
# out in its pixels, scaled to the screen by `place` so that its row ANCHOR_Y (just under the table's near edge) sits
# at PLAY's top. Reduce motion (`calm`) keeps the light and the water still and lets no birds or clouds go by; a safe
# start (`lite`) draws the painting alone, no 3D.
const UI2 = preload("res://scripts/app/ui2.gd")
const WarRoom = preload("res://scripts/app/war_room.gd")
const RoomShader = preload("res://scripts/app/home_room.gdshader")
const LandView = preload("res://scripts/app/war_land_view.gd")
const ART := "res://assets/ui/v2/bg_war_room.webp"
const MASK := "res://assets/ui/v2/bg_war_room_mask.png"
const PAINT := Vector2(1152.0, 2560.0)
const ANCHOR_Y := 1418.0               # this row of the painting sits at PLAY's top (at 420 x 933 it then fills the width from the top)
const SUN := Vector2(247.0, 469.0)
const WINDOW := Rect2(190.0, 37.0, 760.0, 775.0)   # the window's opening (its arch inside this; the mask is exact)
const HORIZON := 468.0
# the painted candles' flames: the stands either side of the window and the clusters on its sill
const FLAMES := [Vector2(70, 649), Vector2(105, 616), Vector2(141, 643), Vector2(212, 800), Vector2(225, 770),
	Vector2(259, 789), Vector2(875, 792), Vector2(912, 767), Vector2(924, 800), Vector2(1018, 645), Vector2(1055, 618),
	Vector2(1090, 649)]
const STANDS := [Vector2(105, 650), Vector2(1055, 650)]   # each stand's warm pool of light on the wall
const FLAME := Color(1.0, 0.62, 0.26)

var calm := false
var lite := false
var room: Control = null                # the 3D war table and heroes (war_room.gd); null on a safe start
var k := 1.0                            # painting px -> screen px
var origin := Vector2.ZERO              # the painting's top left on the screen
var paint_layer: Control                # (the painting, the sky, the room's light: in painting px, scaled)
var top_layer: Control                  # (the table's candle flames and the motes: over the 3D)
var _sky: Control
var _birds: Node2D
var _sun_rays: TextureRect
var _clouds: Array = []                 # [TextureRect, speed px/s]
var _stars: Array = []                  # [TextureRect, rate, phase]
var _flames: Array = []                 # [core, halo, phase, table candle index or -1, glow alpha]
var _pools: Array = []                  # [TextureRect, phase]
var _clock := 0.0

class Birds extends Node2D:
	# small flocks crossing the sky, each bird flapping and gliding, drawn as a dark stroke against the sunset
	var birds: Array = []               # {p: Vector2, v: Vector2, size, flap, phase, glide_until, flap_until, shade}
	var next_flock := 3.0
	var area := Rect2()                 # (the sky in the window: where they fly)
	func flock(first := false) -> void:
		var n := randi_range(3, 6)
		var right := randf() < 0.5
		var y := randf_range(area.position.y + 40.0, area.end.y - 30.0)
		var far := clampf((y - area.position.y) / maxf(1.0, area.size.y), 0.0, 1.0)   # lower in the sky: further off
		var speed := lerpf(34.0, 20.0, far) * (1.0 if right else -1.0)
		var x0 := area.position.x - 60.0 if right else area.end.x + 60.0
		if first:
			x0 = randf_range(area.position.x + 120.0, area.end.x - 120.0)
		for i in n:
			var off := Vector2(-sign(speed) * (18.0 * i + randf_range(0.0, 14.0)), (i % 2) * 14.0 - 7.0 + randf_range(-8.0, 8.0))
			birds.append({"p": Vector2(x0, y) + off, "v": Vector2(speed * randf_range(0.92, 1.08), randf_range(-1.5, 1.5)),
				"size": lerpf(22.0, 13.0, far) * randf_range(0.85, 1.15), "flap": randf_range(2.6, 3.6),
				"phase": randf() * TAU, "glide": 0.0, "until": randf_range(0.5, 2.0), "shade": far})
	func _process(delta: float) -> void:
		next_flock -= delta
		if next_flock <= 0.0 and birds.size() < 12:
			flock()
			next_flock = randf_range(9.0, 18.0)
		for b in birds:
			b.p += b.v * delta
			b.until -= delta
			if b.until <= 0.0:
				b.glide = 0.0 if b.glide > 0.5 else 1.0          # flap a while, glide a while
				b.until = randf_range(1.2, 2.6) if b.glide > 0.5 else randf_range(0.8, 2.2)
			if b.glide < 0.5:
				b.phase += delta * b.flap * TAU
			else:
				b.phase = lerp_angle(b.phase, PI * 0.5, minf(1.0, delta * 4.0))   # wings held out
			b.p.y += sin(b.phase) * delta * 3.0
		birds = birds.filter(func(b): return b.p.x > area.position.x - 120.0 and b.p.x < area.end.x + 120.0)
		queue_redraw()
	func _draw() -> void:
		for b in birds:
			var s: float = b.size
			var lift := sin(b.phase)                               # +1 wings up, -1 down
			var col := Color(0.1, 0.06, 0.14, 0.92).lerp(Color(0.32, 0.2, 0.36, 0.75), float(b.shade))
			var p: Vector2 = b.p
			var tip := s * 0.5
			var pts := PackedVector2Array([
				p + Vector2(-tip, -lift * s * 0.34 - s * 0.05),
				p + Vector2(-tip * 0.45, -lift * s * 0.18 - s * 0.1),
				p,
				p + Vector2(tip * 0.45, -lift * s * 0.18 - s * 0.1),
				p + Vector2(tip, -lift * s * 0.34 - s * 0.05)])
			draw_polyline(pts, col, maxf(2.2, s * 0.15), true)

func _init(reduce_motion := false, safe := false) -> void:
	calm = reduce_motion
	lite = safe

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	var art: Texture2D = UI2.tex(ART)
	var mask: Texture2D = UI2.tex(MASK)
	var noise := LandView.noise_tex(0.05, 21, 256)
	paint_layer = _layer()
	# the painting, its water glimmering
	var back := _painting(art, mask, noise, false)
	# the sky beyond the window
	_sky = Control.new()
	_sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paint_layer.add_child(_sky)
	_build_sky()
	# the room again, over the sky (the window's opening cut out)
	_painting(art, mask, noise, true)
	_build_room_light()
	if not lite:
		room = WarRoom.new()
		room.calm = calm
		add_child(room)
	top_layer = _layer()
	if room != null:
		for i in WarRoom.CANDLE_SPOTS.size() * WarRoom.CANDLES.size():
			_flame(top_layer, Vector2.ZERO, 1.0, i)
	if not calm:
		_motes()
	back.set_meta("home_art", true)

func _layer() -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.size = PAINT
	add_child(c)
	return c

func _painting(art: Texture2D, mask: Texture2D, noise: Texture2D, room_only: bool) -> TextureRect:
	var t := TextureRect.new()
	t.texture = art
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.size = PAINT
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = RoomShader
	m.set_shader_parameter("mask", mask)
	m.set_shader_parameter("noise_tex", noise)
	m.set_shader_parameter("room_only", room_only)
	m.set_shader_parameter("motion", 0.0 if calm else 1.0)
	m.set_shader_parameter("paint_size", PAINT)
	m.set_shader_parameter("sun", SUN)
	t.material = m
	paint_layer.add_child(t)
	return t

func _glow(parent: Control, centre: Vector2, sz: Vector2, col: Color, add := true) -> TextureRect:
	var t := TextureRect.new()
	t.texture = UI2.glow_tex()
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

# ---------------- the sky ----------------
func _build_sky() -> void:
	# the sun on the horizon: a wide warm glow, its rays turning slowly, a bright heart
	_glow(_sky, SUN, Vector2(620, 520), Color(1.0, 0.55, 0.3, 0.42))
	_sun_rays = TextureRect.new()
	_sun_rays.texture = UI2.ray_texture(Color(1.0, 0.82, 0.55), 16)
	_sun_rays.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sun_rays.size = Vector2(980, 980)
	_sun_rays.pivot_offset = _sun_rays.size * 0.5
	_sun_rays.position = SUN - _sun_rays.size * 0.5
	_sun_rays.modulate = Color(1, 1, 1, 0.3)
	_sun_rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_sun_rays.material = add
	_sky.add_child(_sun_rays)
	var heart := _glow(_sky, SUN, Vector2(170, 150), Color(1.0, 0.9, 0.7, 0.75))
	heart.set_meta("sun", true)
	# the first stars, high in the violet
	var rng := RandomNumberGenerator.new()
	rng.seed = 1138
	for i in 14:
		var at := Vector2(rng.randf_range(330.0, 860.0), rng.randf_range(70.0, 270.0))
		var st := _glow(_sky, at, Vector2.ONE * rng.randf_range(10.0, 18.0), Color(0.95, 0.92, 1.0, 0.0))
		_stars.append([st, rng.randf_range(0.5, 1.4), rng.randf() * TAU])
	# cloud wisps catching the last light
	for cd in [[300.0, 360.0, 70.0, 7.0, Color(1.0, 0.7, 0.8, 0.2)], [700.0, 300.0, 54.0, -5.0, Color(1.0, 0.78, 0.86, 0.16)],
			[520.0, 420.0, 46.0, 9.0, Color(1.0, 0.62, 0.55, 0.18)], [860.0, 230.0, 40.0, 4.0, Color(0.9, 0.75, 1.0, 0.14)]]:
		var c := _glow(_sky, Vector2(float(cd[0]), float(cd[1])), Vector2(float(cd[2]) * 6.0, float(cd[2])), cd[4], false)
		_clouds.append([c, float(cd[3])])
	_birds = Birds.new()
	_birds.area = Rect2(WINDOW.position.x, 120.0, WINDOW.size.x, HORIZON - 150.0)
	_sky.add_child(_birds)
	if calm:
		_birds.process_mode = Node.PROCESS_MODE_DISABLED
	else:
		_birds.flock(true)

# ---------------- the room's light ----------------
func _build_room_light() -> void:
	# a warm pool on the wall round each candle stand, breathing with its flames
	for i in STANDS.size():
		var pool := _glow(paint_layer, STANDS[i], Vector2(420, 460), Color(1.0, 0.55, 0.22, 0.1))
		_pools.append([pool, 1.3 * i])
	for i in FLAMES.size():
		_flame(paint_layer, FLAMES[i], 1.0, -1)

func _flame(parent: Control, at: Vector2, size_k: float, table_i: int) -> void:
	# a candle's flame: its halo, and a bright core that flickers and sways (the painted flames are under the core;
	# the table's candles get their whole flame from it)
	var halo := _glow(parent, at, Vector2(130, 130) * size_k, Color(FLAME, 0.34 if table_i < 0 else 0.5))
	var core_sz := Vector2(13, 30) * size_k if table_i < 0 else Vector2(24, 54) * size_k
	var core := _glow(parent, at, core_sz, Color(1.0, 0.7, 0.3, 0.8) if table_i < 0 else Color(1.0, 0.62, 0.22, 1.0))
	core.pivot_offset = Vector2(core_sz.x * 0.5, core_sz.y * 0.85)
	var heart: TextureRect = null
	if table_i >= 0:
		heart = _glow(parent, at, core_sz * Vector2(0.45, 0.5), Color(1.0, 0.96, 0.8, 1.0))
	_flames.append({"core": core, "halo": halo, "heart": heart, "phase": randf() * TAU + float(_flames.size()) * 1.37,
		"table": table_i, "at": at, "a": halo.modulate.a})

func _motes() -> void:
	var glow := Gradient.new()
	glow.set_color(0, Color(1, 0.85, 0.55, 1.0))
	glow.set_color(1, Color(1, 0.85, 0.55, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = glow
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 24
	gt.height = 24
	var motes := CPUParticles2D.new()
	motes.texture = gt
	motes.amount = 26
	motes.lifetime = 9.0
	motes.preprocess = 9.0
	motes.position = Vector2(576, 980)
	motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	motes.emission_rect_extents = Vector2(520, 260)
	motes.direction = Vector2(0.15, -1.0)
	motes.spread = 25.0
	motes.gravity = Vector2.ZERO
	motes.initial_velocity_min = 10.0
	motes.initial_velocity_max = 26.0
	motes.scale_amount_min = 0.35
	motes.scale_amount_max = 0.9
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.0))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	ramp.add_point(0.3, Color(1, 1, 1, 0.75))
	ramp.add_point(0.7, Color(1, 1, 1, 0.5))
	motes.color_ramp = ramp
	top_layer.add_child(motes)

# ---------------- layout ----------------
func place(play_top: float) -> void:
	# the painting covers the screen's width, its row ANCHOR_Y at PLAY's top (and no gap above it: taller, it grows)
	var w := size.x
	k = maxf(w / PAINT.x, play_top / ANCHOR_Y)
	origin = Vector2((w - PAINT.x * k) * 0.5, play_top - ANCHOR_Y * k)
	for l in [paint_layer, top_layer]:
		(l as Control).position = origin
		(l as Control).scale = Vector2(k, k)
	if room != null:
		room.position = origin + WarRoom.FRAME.position * k
		room.size = WarRoom.FRAME.size * k

func painting_bottom() -> float:
	return origin.y + PAINT.y * k

func set_looks(looks: Dictionary) -> void:
	if room != null:
		room.set_looks(looks)

func paint_war(war: Dictionary) -> void:
	if room != null:
		room.paint(war)

# ---------------- alive ----------------
func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_clock += delta
	var t := _clock
	# the table's candles: their flames follow the 3D (in painting px)
	var pts: Array = room.flame_points() if room != null else []
	for f in _flames:
		var ti: int = f.table
		var core: TextureRect = f.core
		var halo: TextureRect = f.halo
		var heart: TextureRect = f.heart
		if ti >= 0:
			if ti >= pts.size():
				continue
			var at: Vector2 = WarRoom.FRAME.position + (pts[ti] as Vector2) / k
			core.position = at - core.pivot_offset
			halo.position = at - halo.size * 0.5
			if heart != null:
				heart.position = at - Vector2(heart.size.x * 0.5, heart.size.y * 0.75)
		if calm:
			continue
		var ph: float = f.phase
		var fl := 0.5 + 0.22 * sin(t * 9.1 + ph) + 0.16 * sin(t * 15.3 + ph * 1.7) + 0.12 * sin(t * 3.7 + ph * 0.6)
		core.scale = Vector2(0.92 + 0.1 * fl, 0.84 + 0.3 * fl)
		core.rotation = 0.09 * sin(t * 2.3 + ph) + 0.05 * sin(t * 6.1 + ph)
		halo.modulate.a = float(f.a) * (0.7 + 0.55 * fl)
		halo.scale = Vector2.ONE * (0.92 + 0.14 * fl)
		if heart != null:
			heart.scale = core.scale
			heart.rotation = core.rotation
	if calm:
		return
	for p in _pools:
		var pool: TextureRect = p[0]
		pool.modulate.a = 0.1 + 0.03 * sin(t * 5.3 + float(p[1])) + 0.02 * sin(t * 11.7 + float(p[1]))
	_sun_rays.rotation = fmod(t * TAU / 140.0, TAU)
	for s in _stars:
		var st: TextureRect = s[0]
		st.modulate.a = 0.85 * pow(maxf(0.0, sin(t * float(s[1]) + float(s[2]))), 3.0)
	for c in _clouds:
		var cl: TextureRect = c[0]
		cl.position.x += float(c[1]) * delta
		if cl.position.x > WINDOW.end.x + 40.0:
			cl.position.x = WINDOW.position.x - cl.size.x - 40.0
		elif cl.position.x + cl.size.x < WINDOW.position.x - 40.0:
			cl.position.x = WINDOW.end.x + 40.0
