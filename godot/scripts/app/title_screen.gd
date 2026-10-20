extends Control
# 0.31.139 (Kevin: "remove the fatebound title and instead put that in a startup screen and any loading screens. Give
# the starting title screen a little jingle tune and have title animate in there like slamming onto the wall or
# something"): the screen the app opens on. A castle wall at dusk (bg_title_wall.webp; tools/build_title_art.py), its
# two torches flickering and throwing up embers; the title (title_logo.gd) flies in from the viewer and slams onto the
# wall: a thud (titleSlam), a flash, the screen shakes, dust bursts out from behind it and rubble drops, cracks run out
# into the stones, the title squashes and settles -- its flags whip about and its rift flares (0.31.193; until then
# the King swung from his rope). Then TAP TO START: a tap
# anywhere lifts the screen off Home (a tap during the flight lands it first). Reduce motion: the title fades in and
# holds still, no shake.
#
# 0.31.141 (Kevin: "Make the intro splash screen more exciting and also load faster"):
#  - FASTER: the start-up screen (content_loader.gd) puts this up as soon as the content packs are mounted and loads
#    the game (Main.tscn) on a thread behind it, instead of after it -- so the title is on screen ~2 s sooner and the
#    show plays while the game loads. The game is put in behind it once the slam has settled (can_swap), and says
#    when Home is built and drawn (home_ready): TAP TO START shows then (LOADING... until; a tap meanwhile is kept and
#    lifts the screen the moment Home is ready). A long frame slows the show down rather than skipping it.
#  - MORE EXCITING: the wall comes up from the boot splash as the edges darken; the torches flare alight one after the
#    other (whoosh of fire); the title launches with a whoosh, trailing afterimages; it hits on the jingle's first
#    note: a shockwave ring, gold sparks, a punch-in zoom, the torches flaring, the title's flags whipping (0.31.193); then
#    light rays turn slowly behind the title, a gold glint sweeps across the letters every few seconds, and embers
#    drift up the screen. The game's own sounds (tm_fireball1, tm_sword_swing2, tm_crumble1), no new files.
#    Reduce motion: no flight, shake, zoom, rays turning, glint or drifting embers.
# 0.31.142 (Kevin: "Getting freezes during it now"; his log: the game going in behind the title stopped the screen
# for 6.4 s mid-show -- Home's build 1.9 s, then its first frame 4.5 s): the show now waits for the game. The wall and
# its torches open (the PRE-ROLL) while the game loads on its thread; once loaded, the screen settles to a still
# LOADING... (the drifting embers fade, the torches hold steady: hold_for_game, SETTLE) and the game goes in behind it
# (can_swap), so the pause in drawing is a still loading screen, not a show stopping mid-swing; when Home is built and
# drawn (home_ready) the embers come back and the SHOW plays -- the flight, the slam, TAP TO START just after. A tap
# while loading is kept: in the moment Home is ready, straight in (no show). (And Home's first frame is shorter:
# war_room.gd / chest_row.gd no longer use MSAA.)
const UI = preload("res://scripts/app/ui.gd")
const UI2 = preload("res://scripts/app/ui2.gd")
const TitleLogo = preload("res://scripts/app/title_logo.gd")
const Diag = preload("res://scripts/siege/siege_diag.gd")
const RaysShader = preload("res://scripts/app/title_rays.gdshader")
const GlintShader = preload("res://scripts/app/title_glint.gdshader")

const GROUP := "title_screen"
const ART := "res://assets/ui/v2/bg_title_wall.webp"
const SPLASH := "res://assets/branding/splash.png"        # (the base build's copy of the wall, without the ui pack)
const JINGLE := "res://assets/music/title_jingle.ogg"
const SOUNDS := {                                          # name -> [file, loudness as the game's ui cues (x 0.2)]
	"ignite": ["res://assets/sounds/tm_fireball1.wav", 0.6],
	"whoosh": ["res://assets/sounds/tm_sword_swing2.wav", 1.3],
	"slam": ["res://assets/sounds/titleSlam.wav", 1.7],
	"crumble": ["res://assets/sounds/tm_crumble1.wav", 0.5],
}
const PAINT := Vector2(1152.0, 2560.0)
const TORCHES := [Vector2(121, 832), Vector2(1028, 830)]   # the painted torches' flames
const LOGO_AT := 0.22                  # the title's middle, this far down the screen (over the torches)
const LOGO_W := 330.0                  # at most this wide (screen px)
const IGNITE := [0.05, 0.16]           # the torches flare alight
const START := 0.22                    # the title sets off no sooner than this (and not before the game is ready)...
const FLIGHT := 0.36                   # ...and hits the wall this long after
const JINGLE_LEAD := 0.13              # the jingle's first note comes this long into it: started so it lands on the hit
const SETTLE := 0.25                   # the screen settles this long before the game goes in behind it
const LOADING_AT := 0.9                # LOADING... in the pre-roll, if the game still isn't ready
const TAP_AFTER := 0.6                 # TAP TO START, this long after the hit
const GLINT_AT := 0.8                  # the first glint, after the hit...
const GLINT_EVERY := 4.5               # ...then every this often
const GLINT_TIME := 0.75
const GHOSTS := 2                      # afterimages trailing the flight
const KICK_DEG := 32.0                 # the hit's kick to the title (title_logo.kick: its flags whip, its rift flares)
const MAX_STEP := 1.0 / 20.0           # a longer frame slows the show instead of skipping it

signal done
signal shown                           # the show is over (TAP TO START is up): the game may get on with its loading
signal lifting                         # the screen starts to fade off what's behind it

var app = null
var calm := false
var home_is_ready := false             # the game's Home is built and drawn behind: TAP TO START
var want_leave := false                # tapped while Home was still loading: lift as soon as it's ready
var holding := false                   # settled, still, for the game going in behind (hold_for_game)
var _hold_t := 0.0
var _launch := -1.0                    # when the flight set off (-1: not yet)
var _shown := false
var _drift: CPUParticles2D
var bar: ProgressBar                   # 0.31.142: the LOADING bar (set_progress)
var _progress_to := 0.0
var k := 1.0
var origin := Vector2.ZERO
var paint: Control                     # the wall and its torches, in the painting's pixels
var wall: TextureRect
var stage: Control                     # what shakes and punches in (the wall, the title, the dust)
var vignette: TextureRect
var rays: TextureRect
var rays_mat: ShaderMaterial
var glint_mat: ShaderMaterial
var logo: TitleLogo
var ghosts: Array = []
var cracks: Node2D
var ring: Node2D
var flash: TextureRect
var tap: Label
var jingle: AudioStreamPlayer
var t := 0.0
var landed := false
var leaving := false
var shake := 0.0
var punch := 0.0
var _land_t := 0.0
var _flames: Array = []
var _bursts: Array = []                # CPUParticles2D fired at the hit: dust, rubble, sparks
var _players := {}
var _levels := {}
var _lit := [false, false]
var _whooshed := false
var _crumbled := false
var _first := true

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

class Ring extends Node2D:
	# 0.31.141: the shockwave of the hit, a bright ring racing out from the title and fading
	var p := -1.0                      # 0..1 while it spreads
	var r0 := 120.0
	var r1 := 900.0
	func _draw() -> void:
		if p < 0.0 or p >= 1.0:
			return
		var e := 1.0 - pow(1.0 - p, 3.0)
		var r := lerpf(r0, r1, e)
		var a := (1.0 - p) * 0.8
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 96, Color(1.0, 0.88, 0.6, a), lerpf(70.0, 8.0, p), true)
		draw_arc(Vector2.ZERO, r * 0.86, 0.0, TAU, 96, Color(1.0, 0.62, 0.3, a * 0.5), lerpf(40.0, 4.0, p), true)

func _init(a = null, reduce_motion := false) -> void:
	app = a
	calm = reduce_motion

static func saved_settings() -> Dictionary:
	# the player's settings before the game has read its profile (the boot screen puts this up first): the volumes and
	# Reduce Motion, straight from the saved profile
	var path := "user://siege_profile.json"
	if FileAccess.file_exists(path):
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if v is Dictionary and (v as Dictionary).get("settings") is Dictionary:
			return v.settings
	return {}

func _ready() -> void:
	add_to_group(GROUP)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_levels = _read_levels()
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
	var wt: Texture2D = UI2.tex(ART)
	wall.texture = wt if wt != null else load(SPLASH)
	wall.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wall.stretch_mode = TextureRect.STRETCH_SCALE
	wall.size = PAINT
	wall.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paint.add_child(wall)
	for at in TORCHES:
		_torch(at)
	vignette = _vignette()
	paint.add_child(vignette)
	rays = TextureRect.new()
	rays.texture = _white()
	rays.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rays.stretch_mode = TextureRect.STRETCH_SCALE
	rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rays_mat = ShaderMaterial.new()
	rays_mat.shader = RaysShader
	rays_mat.set_shader_parameter("power", 0.0)          # (drawn from the first frame, so it's compiled before the show)
	rays.material = rays_mat
	paint.add_child(rays)
	cracks = Cracks.new()
	paint.add_child(cracks)
	flash = _glow(paint, Vector2.ZERO, Vector2(900, 600), Color(1.0, 0.93, 0.75, 0.0))
	_bursts = [_dust(), _rubble(), _sparks()]
	paint.add_child(_bursts[0])                  # (the dust puffs out from behind the title...)
	if not calm:
		for i in GHOSTS:
			var g := TitleLogo.new(true)
			g.modulate.a = 0.0
			paint.add_child(g)
			ghosts.append(g)
	logo = TitleLogo.new(calm)
	logo.modulate.a = 0.01                       # (drawn, so its glint is compiled before the show; too faint to see)
	paint.add_child(logo)
	glint_mat = ShaderMaterial.new()
	glint_mat.shader = GlintShader
	glint_mat.set_shader_parameter("sweep", -1.0)
	logo.set_shine(glint_mat)
	paint.add_child(_bursts[1])                  # (...the rubble drops in front of it...)
	paint.add_child(_bursts[2])                  # (...and the sparks fly)
	ring = Ring.new()
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	ring.material = add
	paint.add_child(ring)
	if not calm:
		_drift = _drift_embers()
		paint.add_child(_drift)
	tap = UI2.text(self, "TAP TO START", 30, UI2.GOLD, Color("#2a1205"), 9)
	tap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tap.modulate.a = 0.0
	tap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar = _loading_bar()
	add_child(bar)
	var ver := UI.label(self, "v" + Diag.BUILD.replace("-fatebound", ""), 11, Color(1, 1, 1, 0.45), UI.HEAVY_FONT)
	ver.name = "Version"
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	ver.offset_top = -30
	ver.offset_bottom = -10
	ver.mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_lay)
	_lay()
	_prepare_sounds()

func _lay() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return
	stage.size = size
	stage.pivot_offset = Vector2(w * 0.5, h * LOGO_AT)    # (the punch-in zooms on the title)
	k = maxf(w / PAINT.x, h / PAINT.y)
	origin = Vector2((w - PAINT.x * k) * 0.5, (h - PAINT.y * k) * 0.5)
	paint.position = origin
	paint.scale = Vector2(k, k)
	var lw := minf(w - 36.0, LOGO_W) / k
	var centre := Vector2(PAINT.x * 0.5, (h * LOGO_AT - origin.y) / k)
	for l in [logo] + ghosts:
		var c := l as Control
		c.size = Vector2(lw, lw * TitleLogo.aspect())
		c.position = centre - c.size * 0.5
		c.pivot_offset = c.size * 0.5
	var r := Rect2(logo.position, logo.size)
	cracks.make(r.grow(-lw * 0.04), 1139)
	cracks.queue_redraw()
	flash.size = logo.size * Vector2(1.5, 2.0)
	flash.pivot_offset = flash.size * 0.5
	flash.position = centre - flash.size * 0.5
	rays.size = Vector2(lw * 2.1, lw * 2.1)
	rays.position = centre - rays.size * 0.5
	ring.position = centre
	ring.r0 = lw * 0.35
	ring.r1 = lw * 1.25
	# the vignette covers what the screen shows of the painting
	vignette.position = -origin / k
	vignette.size = size / k
	for b in _bursts:
		var p := b as CPUParticles2D
		match str(p.name):
			"Dust":
				p.position = centre + Vector2(0.0, logo.size.y * 0.1)
				p.emission_rect_extents = Vector2(logo.size.x * 0.46, logo.size.y * 0.36)
			"Rubble":
				p.position = centre + Vector2(0.0, logo.size.y * 0.38)
				p.emission_rect_extents = Vector2(logo.size.x * 0.4, logo.size.y * 0.08)
			_:
				p.position = centre
				p.emission_rect_extents = Vector2(logo.size.x * 0.42, logo.size.y * 0.3)
	tap.size = Vector2(w, 44)
	tap.position = Vector2(0, h * 0.8)
	tap.pivot_offset = tap.size * 0.5
	bar.size = Vector2(minf(w * 0.56, 240.0), 12.0)
	bar.position = Vector2((w - bar.size.x) * 0.5, h * 0.8 + 50.0)

# ---------------- the parts ----------------
func _loading_bar() -> ProgressBar:
	# 0.31.142: a gold bar under LOADING..., as the first-start download screen has (content_loader.gd)
	var b := ProgressBar.new()
	b.show_percentage = false
	b.min_value = 0.0
	b.max_value = 1.0
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.03, 0.02, 0.05, 0.75)
	back.set_corner_radius_all(6)
	back.border_color = Color(1.0, 0.85, 0.5, 0.35)
	back.set_border_width_all(1)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UI2.GOLD
	fill.set_corner_radius_all(6)
	b.add_theme_stylebox_override("background", back)
	b.add_theme_stylebox_override("fill", fill)
	b.modulate.a = 0.0
	return b

func set_progress(f: float) -> void:
	# how far the game behind has got (the boot screen and the game say, 0..1); the bar never goes back
	_progress_to = maxf(_progress_to, clampf(f, 0.0, 1.0))

static func _white() -> Texture2D:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)

func _vignette() -> TextureRect:
	# the screen's edges darkening as the show starts (it opens as the boot splash left it)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.05), Color(0.02, 0.0, 0.02, 0.8)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.42)
	gt.fill_to = Vector2(1.08, 1.0)
	gt.width = 128
	gt.height = 256
	var v := TextureRect.new()
	v.texture = gt
	v.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	v.stretch_mode = TextureRect.STRETCH_SCALE
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.modulate.a = 1.0 if calm else 0.0
	return v

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

func _additive(p: CPUParticles2D) -> CPUParticles2D:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = m
	return p

func _torch(at: Vector2) -> void:
	var pool := _glow(paint, at + Vector2(0, 40), Vector2(560, 640), Color(1.0, 0.5, 0.18, 0.16))
	var halo := _glow(paint, at, Vector2(190, 210), Color(1.0, 0.6, 0.25, 0.45))
	var core := _glow(paint, at + Vector2(0, -6), Vector2(46, 92), Color(1.0, 0.82, 0.45, 0.85))
	core.pivot_offset = Vector2(23, 80)
	var f := {"pool": pool, "halo": halo, "core": core, "phase": randf() * TAU, "boost": 0.0, "burst": null, "embers": null}
	_flames.append(f)
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
	embers.color_ramp = _fire_ramp()
	paint.add_child(_additive(embers))
	f.embers = embers
	# 0.31.141: the flare as it catches -- a burst of sparks up out of the torch
	var burst := CPUParticles2D.new()
	burst.texture = UI2.glow_tex()
	burst.one_shot = true
	burst.emitting = false
	burst.explosiveness = 0.9
	burst.amount = 16
	burst.lifetime = 0.9
	burst.position = at + Vector2(0, -20)
	burst.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	burst.emission_rect_extents = Vector2(18, 10)
	burst.direction = Vector2(0, -1)
	burst.spread = 45.0
	burst.gravity = Vector2(0, 220)
	burst.initial_velocity_min = 160.0
	burst.initial_velocity_max = 420.0
	burst.scale_amount_min = 0.1
	burst.scale_amount_max = 0.24
	burst.color_ramp = _fire_ramp()
	paint.add_child(_additive(burst))
	f.burst = burst

static func _fire_ramp() -> Gradient:
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.8, 0.4, 1.0))
	ramp.set_color(1, Color(1.0, 0.35, 0.1, 0.0))
	return ramp

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

func _sparks() -> CPUParticles2D:
	# 0.31.141: gold sparks flying out from the hit and falling
	var s := CPUParticles2D.new()
	s.name = "Sparks"
	s.texture = UI2.glow_tex()
	s.one_shot = true
	s.emitting = false
	s.explosiveness = 0.95
	s.amount = 44
	s.lifetime = 1.1
	s.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	s.direction = Vector2(0, -0.3)
	s.spread = 180.0
	s.gravity = Vector2(0, 1100)
	s.initial_velocity_min = 450.0
	s.initial_velocity_max = 1250.0
	s.damping_min = 300.0
	s.damping_max = 500.0
	s.scale_amount_min = 0.12
	s.scale_amount_max = 0.3
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	ramp.colors = PackedColorArray([Color(1.0, 0.97, 0.8, 1.0), Color(1.0, 0.75, 0.3, 0.9), Color(1.0, 0.4, 0.1, 0.0)])
	s.color_ramp = ramp
	return _additive(s)

func _drift_embers() -> CPUParticles2D:
	# 0.31.141: embers drifting up the screen the whole time
	var e := CPUParticles2D.new()
	e.texture = UI2.glow_tex()
	e.amount = 26
	e.lifetime = 9.0
	e.preprocess = 9.0
	e.position = Vector2(PAINT.x * 0.5, PAINT.y * 0.98)
	e.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	e.emission_rect_extents = Vector2(PAINT.x * 0.55, 60)
	e.direction = Vector2(0.15, -1)
	e.spread = 18.0
	e.gravity = Vector2(14, -10)
	e.initial_velocity_min = 160.0
	e.initial_velocity_max = 300.0
	e.scale_amount_min = 0.07
	e.scale_amount_max = 0.17
	e.hue_variation_min = -0.03
	e.hue_variation_max = 0.03
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.15, 0.8, 1.0])
	ramp.colors = PackedColorArray([Color(1.0, 0.7, 0.3, 0.0), Color(1.0, 0.75, 0.35, 0.9), Color(1.0, 0.45, 0.15, 0.6), Color(1.0, 0.3, 0.1, 0.0)])
	e.color_ramp = ramp
	return _additive(e)

# ---------------- sound ----------------
func _read_levels() -> Dictionary:
	# the volumes: the game's when it's up, else the saved settings (the boot screen puts this up before the game)
	if app != null and app.get("audio") != null:
		var au = app.audio
		var lv: Dictionary = au.get("levels") if au.get("levels") is Dictionary else {}
		return {"master": float(lv.get("master", 1.0)), "music": float(lv.get("music", 1.0)), "ui": float(lv.get("ui", 1.0)),
			"muted": bool(au.get("muted"))}
	var st := saved_settings()
	var cfg := ConfigFile.new()
	var muted := cfg.load("user://native_audio.cfg") == OK and bool(cfg.get_value("audio", "muted", false))
	return {"master": clampf(float(st.get("master", 1.0)), 0.0, 1.0), "music": clampf(float(st.get("music", 1.0)), 0.0, 1.0),
		"ui": clampf(float(st.get("sfx", 1.0)), 0.0, 1.0), "muted": muted}

func _prepare_sounds() -> void:
	if bool(_levels.get("muted", false)):
		return
	var music := 0.7 * float(_levels.master) * float(_levels.music)
	if music > 0.001 and ResourceLoader.exists(JINGLE):
		jingle = AudioStreamPlayer.new()
		jingle.stream = load(JINGLE)
		jingle.volume_db = linear_to_db(music)
		add_child(jingle)
	for n in SOUNDS:
		var gain := minf(1.0, 0.2 * float(_levels.master) * float(_levels.ui) * float(SOUNDS[n][1]))
		if gain <= 0.001 or not ResourceLoader.exists(str(SOUNDS[n][0])):
			continue
		var p := AudioStreamPlayer.new()
		p.stream = load(str(SOUNDS[n][0]))
		p.volume_db = linear_to_db(gain)
		add_child(p)
		_players[n] = p

func _sound(n: String) -> void:
	var p: AudioStreamPlayer = _players.get(n)
	if p != null:
		p.play()

func _mark(s: String) -> void:
	if not is_inside_tree():
		return
	var g := get_node_or_null("/root/BootGuard")
	if g != null and g.has_method("mark"):
		g.mark(s)

# ---------------- the show ----------------
func land() -> void:
	# the hit: the thud, a flash, the shockwave, sparks, dust and rubble, the cracks, the shake, the title's flags whipping
	if landed:
		return
	landed = true
	_land_t = t
	_mark("title: slam")
	logo.modulate.a = 1.0
	logo.scale = Vector2.ONE
	logo.rotation = 0.0
	for g in ghosts:
		(g as Control).modulate.a = 0.0
	if jingle != null and not jingle.playing:
		jingle.play(maxf(0.0, JINGLE_LEAD - 0.02))       # (a tap that lands it early: the first note now)
	_sound("slam")
	if calm:
		cracks.grow = 1.0
		cracks.queue_redraw()
		return
	shake = 1.0
	punch = 1.0
	flash.modulate.a = 0.9
	ring.p = 0.0
	logo.kick(KICK_DEG)
	for f in _flames:
		f.boost = maxf(float(f.boost), 0.7)                  # (the torches gust up with the blow)
	for b in _bursts:
		(b as CPUParticles2D).restart()
		(b as CPUParticles2D).emitting = true

func home_ready() -> void:
	# the game behind is built and drawn: the show (or, tapped already, straight in)
	if home_is_ready:
		return
	home_is_ready = true
	holding = false
	set_progress(1.0)
	_mark("title: the game is ready behind it")
	if want_leave:
		leave()

func hold_for_game() -> void:
	# 0.31.142: the game has loaded and is about to go in behind (building Home and drawing it the first time stop the
	# drawing for a moment): settle to a still LOADING... first
	if holding or home_is_ready:
		return
	holding = true
	_hold_t = t
	set_progress(0.6)

func can_swap() -> bool:
	# the boot screen may now put the game in behind
	return holding and (t - _hold_t >= SETTLE or want_leave)

func leave() -> void:
	if leaving:
		return
	leaving = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	lifting.emit()
	if app != null:
		app.sfx("tap")
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.45).set_trans(Tween.TRANS_SINE)
	if jingle != null and jingle.playing:
		tw.parallel().tween_property(jingle, "volume_db", jingle.volume_db - 24.0, 0.45)
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
	if not home_is_ready:
		want_leave = true                        # (in the moment Home is ready: straight in)
	elif not landed:
		land()
	elif t - _land_t > 0.35:
		leave()

func _process(delta: float) -> void:
	if _first:
		_first = false
		_mark("title: first frame")
	delta = minf(delta, MAX_STEP)
	t += delta
	# the opening: the edges darken, the torches flare alight one after the other
	if not calm:
		vignette.modulate.a = smoothstep(0.0, 0.4, t)
	for i in _flames.size():
		if not _lit[i] and t >= IGNITE[i]:
			_lit[i] = true
			if not calm:
				_flames[i].boost = 1.0
				if _flames[i].burst != null:
					(_flames[i].burst as CPUParticles2D).restart()
					(_flames[i].burst as CPUParticles2D).emitting = true
			if i == 0:
				_sound("ignite")
	# the show waits for the game behind (the pre-roll), then sets off
	if _launch < 0.0 and home_is_ready and not leaving and t >= START:
		_launch = t
		_mark("title: the show")
	var since := t - _launch if _launch >= 0.0 else -1.0
	if not _whooshed and since >= 0.0:
		_whooshed = true
		if not calm:
			_sound("whoosh")
	if jingle != null and not jingle.playing and not landed and since >= FLIGHT - JINGLE_LEAD:
		jingle.play()
	# the pre-roll's embers fade while it holds still for the game, and come back for the show
	if _drift != null:
		_drift.modulate.a = clampf(1.0 - (t - _hold_t) / SETTLE, 0.0, 1.0) if holding else minf(1.0, _drift.modulate.a + delta * 2.5)
	# the title's flight: from big and tilted at the viewer, faster and faster, onto the wall, afterimages trailing
	if not landed:
		if since >= 0.0:
			var p := clampf(since / FLIGHT, 0.0, 1.0)
			if calm:
				logo.modulate.a = maxf(0.01, p)
			else:
				var e := p * p
				logo.modulate.a = clampf(p * 3.0, 0.01, 1.0)
				logo.scale = Vector2.ONE * lerpf(3.6, 1.0, e)
				logo.rotation = lerpf(-0.26, 0.0, e)
				for i in ghosts.size():
					var g := ghosts[i] as Control
					var pg := clampf(p - 0.09 * (i + 1), 0.0, 1.0)
					g.scale = Vector2.ONE * lerpf(3.6, 1.0, pg * pg)
					g.rotation = lerpf(-0.26, 0.0, pg * pg)
					g.modulate.a = (0.34 / (i + 1)) * clampf(p * 3.0, 0.0, 1.0) * clampf(since / 0.06, 0.0, 1.0)
			if since >= FLIGHT:
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
			punch = maxf(0.0, punch - delta * 2.8)
			var amp := 16.0 * shake * shake
			stage.position = Vector2(randf_range(-amp, amp), randf_range(-amp, amp))
			stage.scale = Vector2.ONE * (1.0 + 0.06 * punch * punch)
			if ring.p >= 0.0 and ring.p < 1.0:
				ring.p = s / 0.45
				ring.queue_redraw()
			if not _crumbled and s >= 0.14:
				_crumbled = true
				_sound("crumble")
			# light rays turning behind the title; a gold glint sweeping across the letters every few seconds
			rays_mat.set_shader_parameter("power", 0.45 * smoothstep(0.05, 0.7, s))
			rays_mat.set_shader_parameter("spin", t * 0.22)
			var g := s - GLINT_AT
			var sweep := -1.0
			if g >= 0.0 and fmod(g, GLINT_EVERY) < GLINT_TIME:
				sweep = lerpf(-0.15, 1.15, fmod(g, GLINT_EVERY) / GLINT_TIME)
			glint_mat.set_shader_parameter("sweep", sweep)
		else:
			rays_mat.set_shader_parameter("power", 0.4 * smoothstep(0.0, 0.5, s))
	# LOADING... while the game gets ready behind (still while holding), TAP TO START just after the slam
	if not leaving:
		if home_is_ready and landed and t - _land_t >= TAP_AFTER:
			var a := clampf((t - _land_t - TAP_AFTER) / 0.4, 0.0, 1.0)
			if tap.text != "TAP TO START":
				tap.text = "TAP TO START"
				_mark("title: TAP TO START")
			tap.modulate.a = a * (0.75 + 0.25 * sin(t * 4.0))
			if not calm:
				tap.scale = Vector2.ONE * (1.0 + 0.04 * sin(t * 4.0))
			if not _shown:
				_shown = true
				shown.emit()
		elif not home_is_ready and (t >= LOADING_AT or want_leave or holding):
			tap.text = "LOADING..."
			tap.scale = Vector2.ONE
			tap.modulate.a = 0.6 if holding or want_leave else clampf((t - LOADING_AT) / 0.4, 0.0, 1.0) * (0.45 + 0.2 * sin(t * 5.0))
		else:
			tap.modulate.a = maxf(0.0, tap.modulate.a - delta * 4.0)
	# the LOADING bar: creeping on by itself while the game loads on its thread, then a step for each piece of Home
	if not home_is_ready and not holding:
		_progress_to = maxf(_progress_to, 0.55 * (1.0 - exp(-t / 2.2)))
	bar.value = _progress_to if holding or home_is_ready else lerpf(bar.value, _progress_to, minf(1.0, delta * 6.0))
	var loading_shown := tap.text == "LOADING..." and not leaving and not landed
	bar.modulate.a = clampf(tap.modulate.a / 0.6, 0.0, 1.0) if loading_shown and (not home_is_ready) else maxf(0.0, bar.modulate.a - delta * 4.0)
	# the torches
	if calm:
		return
	for f in _flames:
		var ph: float = f.phase
		f.boost = maxf(0.0, float(f.boost) - delta * 1.8)
		var b: float = f.boost
		var fl := 0.5 + 0.22 * sin(t * 9.3 + ph) + 0.16 * sin(t * 15.7 + ph * 1.7) + 0.12 * sin(t * 3.1 + ph * 0.6)
		if holding:
			fl = lerpf(fl, 0.5, clampf((t - _hold_t) / SETTLE, 0.0, 1.0))     # (steady while the game goes in)
		if f.embers != null:
			(f.embers as CanvasItem).modulate.a = _drift.modulate.a if _drift != null else 1.0
		(f.core as Control).scale = Vector2(0.9 + 0.12 * fl, 0.82 + 0.32 * fl) * (1.0 + 0.7 * b)
		(f.core as Control).rotation = 0.08 * sin(t * 2.4 + ph)
		(f.halo as Control).modulate.a = 0.32 + 0.22 * fl + 0.55 * b
		(f.halo as Control).scale = Vector2.ONE * (1.0 + 0.5 * b)
		(f.pool as Control).modulate.a = 0.12 + 0.06 * fl + 0.22 * b
