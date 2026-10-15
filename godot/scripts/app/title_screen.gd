extends Control
# 0.31.139 (Kevin: "remove the fatebound title and instead put that in a startup screen and any loading screens. Give
# the starting title screen a little jingle tune and have title animate in there like slamming onto the wall or
# something"): the screen the app opens on. A castle wall at dusk (bg_title_wall.webp; tools/build_title_art.py), its
# two torches flickering and throwing up embers. The jingle starts (title_jingle.ogg) and the title (title_logo.gd)
# flies in from the viewer and slams onto the wall: a thud (titleSlam), a flash, the screen shakes, dust bursts out
# from behind it and rubble drops, cracks run out into the stones, the title squashes and settles -- and the King swings
# from his rope. Then TAP TO START: a tap anywhere lifts the screen off Home (a tap during the flight lands it first).
# Reduce motion: the title fades in and holds still, no shake.
const UI = preload("res://scripts/app/ui.gd")
const UI2 = preload("res://scripts/app/ui2.gd")
const TitleLogo = preload("res://scripts/app/title_logo.gd")
const Diag = preload("res://scripts/siege/siege_diag.gd")

const ART := "res://assets/ui/v2/bg_title_wall.webp"
const JINGLE := "res://assets/music/title_jingle.ogg"
const PAINT := Vector2(1152.0, 2560.0)
const TORCHES := [Vector2(121, 832), Vector2(1028, 830)]   # the painted torches' flames
const LOGO_AT := 0.22                  # the title's middle, this far down the screen (over the torches)
const LOGO_W := 330.0                  # at most this wide (screen px)
const START := 0.14                    # the title sets off...
const HIT := 0.5                       # ...and hits the wall
const TAP_AT := 1.5                    # TAP TO START shows

signal done

var app = null
var calm := false
var k := 1.0
var origin := Vector2.ZERO
var paint: Control                     # the wall and its torches, in the painting's pixels
var wall: TextureRect
var stage: Control                     # what shakes (the wall, the title, the dust)
var logo: Control
var cracks: Node2D
var flash: TextureRect
var tap: Label
var jingle: AudioStreamPlayer
var t := 0.0
var landed := false
var leaving := false
var shake := 0.0
var _land_t := 0.0
var _flames: Array = []
var _bursts: Array = []                # CPUParticles2D fired at the hit

class Cracks extends Node2D:
	# cracks running out into the stones from behind the title, drawn as they grow
	var lines: Array = []              # PackedVector2Array each
	var grow := 0.0
	func make(rect: Rect2, seed: int) -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		lines.clear()
		for i in 9:
			var side := i % 4
			var p := Vector2.ZERO
			var dir := Vector2.ZERO
			match side:
				0:
					p = Vector2(rng.randf_range(rect.position.x + 20.0, rect.end.x - 20.0), rect.position.y + 12.0)
					dir = Vector2(rng.randf_range(-0.6, 0.6), -1.0)
				1:
					p = Vector2(rect.end.x - 14.0, rng.randf_range(rect.position.y + 20.0, rect.end.y - 20.0))
					dir = Vector2(1.0, rng.randf_range(-0.7, 0.7))
				2:
					p = Vector2(rng.randf_range(rect.position.x + 20.0, rect.end.x - 20.0), rect.end.y - 14.0)
					dir = Vector2(rng.randf_range(-0.6, 0.6), 1.0)
				_:
					p = Vector2(rect.position.x + 14.0, rng.randf_range(rect.position.y + 20.0, rect.end.y - 20.0))
					dir = Vector2(-1.0, rng.randf_range(-0.7, 0.7))
			var pts := PackedVector2Array([p])
			var len := rng.randf_range(70.0, 170.0)
			var step := len / 6.0
			for s in 6:
				dir = dir.normalized().rotated(rng.randf_range(-0.55, 0.55))
				p += dir * step
				pts.append(p)
			lines.append(pts)
	func _draw() -> void:
		for pts in lines:
			var n := int(ceil(float(pts.size() - 1) * grow)) + 1
			if n < 2:
				continue
			var part: PackedVector2Array = pts.slice(0, n)
			draw_polyline(part, Color(0.95, 0.78, 0.55, 0.3), 12.0, true)     # (the lit lip of the crack)
			draw_polyline(part, Color(0.07, 0.04, 0.03, 0.9), 6.5, true)

func _init(a = null, reduce_motion := false) -> void:
	app = a
	calm = reduce_motion

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var under := ColorRect.new()
	under.color = Color("#120b10")
	under.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	under.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(under)
	stage = Control.new()
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)
	paint = Control.new()
	paint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paint.size = PAINT
	stage.add_child(paint)
	wall = TextureRect.new()
	wall.texture = UI2.tex(ART)
	wall.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wall.stretch_mode = TextureRect.STRETCH_SCALE
	wall.size = PAINT
	wall.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paint.add_child(wall)
	for at in TORCHES:
		_torch(at)
	cracks = Cracks.new()
	paint.add_child(cracks)
	flash = _glow(paint, Vector2.ZERO, Vector2(900, 600), Color(1.0, 0.93, 0.75, 0.0))
	_bursts = [_dust(), _rubble()]
	paint.add_child(_bursts[0])                  # (the dust puffs out from behind the title...)
	logo = TitleLogo.new(calm)
	logo.modulate.a = 0.0
	paint.add_child(logo)
	paint.add_child(_bursts[1])                  # (...the rubble drops in front of it)
	tap = UI2.text(self, "TAP TO START", 30, UI2.GOLD, Color("#2a1205"), 9)
	tap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tap.modulate.a = 0.0
	tap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ver := UI.label(self, "v" + Diag.BUILD.replace("-fatebound", ""), 11, Color(1, 1, 1, 0.45), UI.HEAVY_FONT)
	ver.name = "Version"
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	ver.offset_top = -30
	ver.offset_bottom = -10
	ver.mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_lay)
	_lay()
	_play_jingle()

func _lay() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return
	k = maxf(w / PAINT.x, h / PAINT.y)
	origin = Vector2((w - PAINT.x * k) * 0.5, (h - PAINT.y * k) * 0.5)
	paint.position = origin
	paint.scale = Vector2(k, k)
	var lw := minf(w - 36.0, LOGO_W) / k
	logo.size = Vector2(lw, lw * TitleLogo.aspect())
	var centre := Vector2(PAINT.x * 0.5, (h * LOGO_AT - origin.y) / k)
	logo.position = centre - logo.size * 0.5
	logo.pivot_offset = logo.size * 0.5
	var r := Rect2(logo.position, logo.size)
	cracks.make(r.grow(-lw * 0.04), 1139)
	cracks.queue_redraw()
	flash.size = logo.size * Vector2(1.5, 2.0)
	flash.pivot_offset = flash.size * 0.5
	flash.position = centre - flash.size * 0.5
	for b in _bursts:
		var p := b as CPUParticles2D
		p.position = centre + Vector2(0.0, logo.size.y * (0.1 if p.name == "Dust" else 0.38))
		p.emission_rect_extents = Vector2(logo.size.x * (0.46 if p.name == "Dust" else 0.4), logo.size.y * (0.36 if p.name == "Dust" else 0.08))
	tap.size = Vector2(w, 44)
	tap.position = Vector2(0, h * 0.8)
	tap.pivot_offset = tap.size * 0.5

func _glow(parent: Control, centre: Vector2, sz: Vector2, col: Color, add := true) -> TextureRect:
	var g := TextureRect.new()
	g.texture = UI2.glow_tex()
	g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	g.stretch_mode = TextureRect.STRETCH_SCALE
	g.size = sz
	g.pivot_offset = sz * 0.5
	g.position = centre - sz * 0.5
	g.modulate = col
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if add:
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		g.material = m
	parent.add_child(g)
	return g

func _torch(at: Vector2) -> void:
	var pool := _glow(paint, at + Vector2(0, 40), Vector2(560, 640), Color(1.0, 0.5, 0.18, 0.16))
	var halo := _glow(paint, at, Vector2(190, 210), Color(1.0, 0.6, 0.25, 0.45))
	var core := _glow(paint, at + Vector2(0, -6), Vector2(46, 92), Color(1.0, 0.82, 0.45, 0.85))
	core.pivot_offset = Vector2(23, 80)
	_flames.append({"pool": pool, "halo": halo, "core": core, "phase": randf() * TAU})
	if calm:
		return
	var embers := CPUParticles2D.new()
	embers.texture = UI2.glow_tex()
	embers.amount = 10
	embers.lifetime = 2.6
	embers.preprocess = 2.6
	embers.position = at + Vector2(0, -30)
	embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	embers.emission_rect_extents = Vector2(14, 6)
	embers.direction = Vector2(0, -1)
	embers.spread = 22.0
	embers.gravity = Vector2(0, -12)
	embers.initial_velocity_min = 40.0
	embers.initial_velocity_max = 90.0
	embers.scale_amount_min = 0.08
	embers.scale_amount_max = 0.16
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.8, 0.4, 1.0))
	ramp.set_color(1, Color(1.0, 0.35, 0.1, 0.0))
	embers.color_ramp = ramp
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	embers.material = m
	paint.add_child(embers)

func _dust() -> CPUParticles2D:
	# the dust knocked out of the wall: puffs bursting out round the title's edges, spreading and fading
	var d := CPUParticles2D.new()
	d.name = "Dust"
	d.texture = UI2.glow_tex()
	d.one_shot = true
	d.emitting = false
	d.explosiveness = 0.92
	d.amount = 40
	d.lifetime = 1.3
	d.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	d.direction = Vector2(0, 0)
	d.spread = 180.0
	d.gravity = Vector2(0, 60)
	d.initial_velocity_min = 120.0
	d.initial_velocity_max = 380.0
	d.damping_min = 220.0
	d.damping_max = 320.0
	d.scale_amount_min = 1.2
	d.scale_amount_max = 2.6
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.5))
	curve.add_point(Vector2(1.0, 1.6))
	d.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.86, 0.78, 0.66, 0.5))
	ramp.set_color(1, Color(0.6, 0.52, 0.45, 0.0))
	d.color_ramp = ramp
	return d

func _rubble() -> CPUParticles2D:
	# chips of stone dropping from under the title
	var r := CPUParticles2D.new()
	r.name = "Rubble"
	var img := Image.create(6, 6, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.33, 0.27, 0.24))
	r.texture = ImageTexture.create_from_image(img)
	r.one_shot = true
	r.emitting = false
	r.explosiveness = 0.85
	r.amount = 18
	r.lifetime = 1.4
	r.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	r.direction = Vector2(0, 1)
	r.spread = 70.0
	r.gravity = Vector2(0, 1500)
	r.initial_velocity_min = 60.0
	r.initial_velocity_max = 260.0
	r.angular_velocity_min = -400.0
	r.angular_velocity_max = 400.0
	r.scale_amount_min = 0.8
	r.scale_amount_max = 2.2
	return r

func _play_jingle() -> void:
	var stream: AudioStream = load(JINGLE) if ResourceLoader.exists(JINGLE) else null
	if stream == null or app == null or app.audio == null:
		return
	var au = app.audio
	if bool(au.get("muted")):
		return
	var lv: Dictionary = au.get("levels") if au.get("levels") is Dictionary else {}
	var gain := 0.7 * float(lv.get("master", 1.0)) * float(lv.get("music", 1.0))
	if gain <= 0.001:
		return
	jingle = AudioStreamPlayer.new()
	jingle.stream = stream
	jingle.volume_db = linear_to_db(gain)
	add_child(jingle)
	jingle.play()

func land() -> void:
	# the hit: the thud, a flash, the dust and the rubble, the cracks, the shake
	if landed:
		return
	landed = true
	_land_t = t
	logo.modulate.a = 1.0
	logo.scale = Vector2.ONE
	logo.rotation = 0.0
	if app != null:
		app.sfx("titleSlam")
	if calm:
		cracks.grow = 1.0
		cracks.queue_redraw()
		return
	shake = 1.0
	flash.modulate.a = 0.85
	for b in _bursts:
		(b as CPUParticles2D).restart()
		(b as CPUParticles2D).emitting = true

func leave() -> void:
	if leaving:
		return
	leaving = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if app != null:
		app.sfx("tap")
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.45).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func():
		done.emit()
		queue_free())

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouse and (ev as InputEventMouse).device == InputEvent.DEVICE_ID_EMULATION:
		return                                   # (a phone's touch arrives as a touch; skip its mouse copy)
	var press := (ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed) \
		or (ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT)
	if not press:
		return
	accept_event()
	if not landed:
		land()
	elif t - _land_t > 0.35:
		leave()

func _process(delta: float) -> void:
	t += delta
	# the title's flight: from big and tilted at the viewer, faster and faster, onto the wall
	if not landed:
		if t >= START:
			var p := clampf((t - START) / (HIT - START), 0.0, 1.0)
			if calm:
				logo.modulate.a = p
			else:
				var e := p * p
				logo.modulate.a = clampf(p * 3.0, 0.0, 1.0)
				logo.scale = Vector2.ONE * lerpf(3.4, 1.0, e)
				logo.rotation = lerpf(-0.2, 0.0, e)
		if t >= HIT:
			land()
	else:
		var s := t - _land_t
		if not calm:
			# squash on the hit, then settle
			var bounce := exp(-s * 9.0) * cos(s * 34.0)
			logo.scale = Vector2(1.0 + 0.07 * bounce, 1.0 - 0.07 * bounce)
			cracks.grow = clampf(s / 0.18, 0.0, 1.0)
			cracks.queue_redraw()
			flash.modulate.a = maxf(0.0, flash.modulate.a - delta * 3.4)
			shake = maxf(0.0, shake - delta * 2.4)
			var amp := 16.0 * shake * shake
			stage.position = Vector2(randf_range(-amp, amp), randf_range(-amp, amp))
	# TAP TO START
	if t >= TAP_AT and not leaving:
		var a := clampf((t - TAP_AT) / 0.4, 0.0, 1.0)
		tap.modulate.a = a * (0.75 + 0.25 * sin(t * 4.0))
		if not calm:
			tap.scale = Vector2.ONE * (1.0 + 0.04 * sin(t * 4.0))
	# the torches
	if calm:
		return
	for f in _flames:
		var ph: float = f.phase
		var fl := 0.5 + 0.22 * sin(t * 9.3 + ph) + 0.16 * sin(t * 15.7 + ph * 1.7) + 0.12 * sin(t * 3.1 + ph * 0.6)
		(f.core as Control).scale = Vector2(0.9 + 0.12 * fl, 0.82 + 0.32 * fl)
		(f.core as Control).rotation = 0.08 * sin(t * 2.4 + ph)
		(f.halo as Control).modulate.a = 0.32 + 0.22 * fl
		(f.pool as Control).modulate.a = 0.12 + 0.06 * fl
