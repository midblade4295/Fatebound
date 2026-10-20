extends Control
# 0.31.193 (Kevin: "the lighting effect in middle show effects"): the title's rift alive (title_logo.gd puts it over
# the word, the same size). Along the rift's line (title_logo.gd RIFT, in the base's px; sc turns them into this
# control's px):
#  - its white-hot core glows and flickers (title_rift_glow.webp, added on);
#  - lightning crackles along it: jagged bolts, each a few hundredths of a second, over part of the rift, now and then
#    forking out into the letters;
#  - sparks spit off it and fall;
#  - every couple of seconds a flare: bolts the whole length, the glow up, a burst of sparks (and on the title's slam).
# With calm (Reduce Motion, and the title screen's afterimages): only the glow, steady.
const GLOW_A := 0.32

var line := PackedVector2Array()
var sc := 1.0
var calm := false
var flare := 0.0                 # 0..1: the glow's and the bolts' extra, dying away
var bolts: Array = []            # {p: PackedVector2Array (base px), w, life, t}
var made := 0                    # bolts made so far (tests)
var glow: TextureRect
var sparks: CPUParticles2D
var burst_sparks: CPUParticles2D
var rng := RandomNumberGenerator.new()
var _next := 0.2
var _flare_in := 1.4
var _flick := 0.0

func _init(glow_tex: Texture2D, still := false) -> void:
	calm = still
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = add
	glow = TextureRect.new()
	glow.texture = glow_tex
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.material = add
	glow.modulate.a = GLOW_A
	add_child(glow)
	sparks = _emitter(26, 0.75, false)
	burst_sparks = _emitter(46, 0.9, true)
	sparks.emitting = not calm

func _emitter(n: int, life: float, one_shot: bool) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = n
	p.lifetime = life
	p.one_shot = one_shot
	p.explosiveness = 1.0 if one_shot else 0.0
	p.randomness = 0.5
	p.emitting = false
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.gravity = Vector2(0, 300)
	p.texture = _dot()
	p.scale_amount_min = 0.25
	p.scale_amount_max = 0.6
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 1.0, 0.92, 1.0))
	g.add_point(0.35, Color(1.0, 0.86, 0.42, 1.0))
	g.set_color(g.get_point_count() - 1, Color(1.0, 0.45, 0.1, 0.0))
	p.color_ramp = g
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = add
	add_child(p)
	return p

static var _dot_tex: Texture2D = null

static func _dot() -> Texture2D:
	if _dot_tex == null:
		var t := GradientTexture2D.new()
		t.width = 24
		t.height = 24
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.add_point(0.35, Color(1, 1, 1, 0.8))
		g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
		t.gradient = g
		_dot_tex = t
	return _dot_tex

func lay(s: float, glow_rect: Rect2) -> void:
	sc = s
	glow.position = glow_rect.position * s
	glow.size = glow_rect.size * s
	var pts := PackedVector2Array()
	for q in line:
		pts.append(q * s)
	for p in [sparks, burst_sparks]:
		(p as CPUParticles2D).emission_points = pts
		(p as CPUParticles2D).initial_velocity_min = 40.0 * s
		(p as CPUParticles2D).initial_velocity_max = 150.0 * s
		(p as CPUParticles2D).gravity = Vector2(0, 340.0 * s)
		(p as CPUParticles2D).scale_amount_min = 0.22 * s / 0.7
		(p as CPUParticles2D).scale_amount_max = 0.55 * s / 0.7

func burst(strength := 1.0) -> void:
	# a flare: bolts the whole length, the glow up, a burst of sparks
	if calm or line.size() < 2:
		return
	flare = maxf(flare, strength)
	for i in 2 + int(strength * 2.0):
		_bolt(true)
	burst_sparks.restart()
	burst_sparks.emitting = true

func _process(delta: float) -> void:
	if calm or line.size() < 2:
		return
	_flare_in -= delta
	if _flare_in <= 0.0:
		burst(0.8)
		_flare_in = rng.randf_range(1.6, 3.2)
	flare = maxf(0.0, flare - delta * 1.8)
	_next -= delta
	if _next <= 0.0:
		_bolt(false)
		_next = rng.randf_range(0.05, 0.18) * (0.4 if flare > 0.3 else 1.0)
	var i := bolts.size() - 1
	while i >= 0:
		bolts[i].life -= delta
		if float(bolts[i].life) <= 0.0:
			bolts.remove_at(i)
		i -= 1
	_flick = lerpf(_flick, rng.randf_range(-1.0, 1.0), minf(1.0, delta * 18.0))
	glow.modulate.a = clampf(GLOW_A + 0.14 * _flick + 0.5 * flare + 0.08 * bolts.size(), 0.12, 0.95)
	queue_redraw()

func _bolt(full: bool) -> void:
	var n := line.size()
	var i0 := 0
	var i1 := n - 1
	if not full:
		var span := rng.randi_range(4, mini(14, n - 1))
		i0 = rng.randi_range(0, n - 1 - span)
		i1 = i0 + span
	var pts := PackedVector2Array()
	for i in range(i0, i1):
		var a: Vector2 = line[i]
		var b: Vector2 = line[i + 1]
		var steps := maxi(1, int(a.distance_to(b) / 5.0))
		var nrm := (b - a).normalized().orthogonal()
		for k in steps:
			var q := a.lerp(b, float(k) / float(steps))
			var edge := minf(float(i - i0) + float(k) / float(steps), float(i1 - i)) # (pinned at its two ends)
			pts.append(q + nrm * rng.randf_range(-6.0, 6.0) * clampf(edge, 0.0, 1.0))
	pts.append(line[i1])
	var w := rng.randf_range(2.2, 3.4) * (1.3 if full else 1.0)
	var life := rng.randf_range(0.05, 0.12) * (1.6 if full else 1.0)
	bolts.append({"p": pts, "w": w, "life": life, "t": life})
	made += 1
	# a fork or two off it, out into the letters
	for f in (rng.randi_range(1, 3) if full else rng.randi_range(0, 1)):
		var at := rng.randi_range(1, maxi(1, pts.size() - 2))
		var dir := Vector2(1.0 if rng.randf() < 0.5 else -1.0, rng.randf_range(-0.6, 0.9)).normalized()
		var fp := PackedVector2Array([pts[at]])
		var q: Vector2 = pts[at]
		for k in rng.randi_range(3, 6):
			q += dir * rng.randf_range(5.0, 11.0) + Vector2(rng.randf_range(-4.0, 4.0), rng.randf_range(-4.0, 4.0))
			fp.append(q)
		bolts.append({"p": fp, "w": w * 0.55, "life": life, "t": life})

func _draw() -> void:
	for b in bolts:
		var a := clampf(float(b.life) / float(b.t), 0.0, 1.0)
		var pts := PackedVector2Array()
		for q in (b.p as PackedVector2Array):
			pts.append(q * sc)
		draw_polyline(pts, Color(1.0, 0.78, 0.38, 0.35 * a), float(b.w) * 3.4 * sc, true)
		draw_polyline(pts, Color(1.0, 0.98, 0.9, 0.95 * a), float(b.w) * sc, true)
