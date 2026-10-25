extends Control
# 0.31.196 (Kevin: "Do clan chest, clan camp, crest, ..."): the CLAN CAMP at the top of the CLAN window -- the clan's
# camp painted at its stage (Eco.clan_camp_stage of its level: a tent and a banner; two tents and two banners; a palisade,
# three banners and a cauldron; a hall, a watchtower and five banners -- tools/build_clan_art.py), alive: the banners in
# the crest's field colour with the crest on each (the cloth ripples), the campfire's flames, halo and embers with its
# light flickering over the camp (clan_camp.gdshader), fireflies. Reduce Motion: still.
# 0.31.197 (Kevin: "make the camp screen fill the entire screen instead of being a small box and incorporate the clan
# buttons into the screen"): the whole CLAN screen -- the painting is tall now (the stage in its middle, the night sky
# above it, the ground falling into shadow below: tools/build_clan_art.py), covering this control like Home's camp
# (cut at the sides on a phone longer than 1:2), with stars twinkling and now and then falling in its sky. The window
# puts its buttons over it (clan_panel.gd).
const UI2 = preload("res://scripts/app/ui2.gd")
const Eco = preload("res://scripts/meta/economy.gd")
const CampScene = preload("res://scripts/app/camp_scene.gd")
const CampShader = preload("res://scripts/app/clan_camp.gdshader")
const Crest = preload("res://scripts/app/crest.gd")
const PAINT := Vector2(1024.0, 2048.0)
# tools/build_clan_art.py prints these: per stage, each banner's cloth (above its swallowtails), and the fire's middle
const BANNERS := [
	[Rect2(564, 774, 91, 158)],
	[Rect2(349, 787, 90, 176), Rect2(649, 786, 99, 179)],
	[Rect2(333, 730, 81, 146), Rect2(473, 697, 87, 154), Rect2(612, 734, 86, 153)],
	[Rect2(38, 754, 61, 124), Rect2(163, 758, 57, 120), Rect2(289, 768, 61, 120), Rect2(715, 777, 62, 102), Rect2(932, 759, 64, 126)],
]
const FIRES := [Vector2(520, 1182), Vector2(522, 1217), Vector2(520, 1202), Vector2(525, 1162)]
const FIRE_SIZE := [1.05, 0.85, 0.75, 1.3]         # (stage 3's fire is under the cauldron)
const CREST_W := 0.74                              # a banner's crest, of its width
const FLIES := Rect2(80.0, 1000.0, 860.0, 420.0)
const SKY := Rect2(0.0, 0.0, 1024.0, 560.0)        # where the stars are (and the falling ones go)
# 0.31.216 (landscape): the band of the (portrait) painting a wide screen shows -- its banners down to just under the
# fire, as tall as the screen; either side of it the painting again, wider, dark and soft (back)
const BAND := Rect2(0.0, 640.0, 1024.0, 640.0)

var stage := 1
var code := ""
var frame := ""
var calm := false
var layer: Control
var art: TextureRect
var back: TextureRect                              # 0.31.216: the painting behind it all, darkened (landscape's sides)
var crests: Array = []
var _halo: TextureRect
var _heart: TextureRect
var _embers: CPUParticles2D
var _clock := 0.0
var _stars: Array = []                             # [TextureRect, rate, phase]
var k := 1.0                                       # painting px -> this control's px
var origin := Vector2.ZERO                         # the painting's top left here

func setup(st: int, crest_code: String, fr := "", reduce_motion := false) -> void:
	stage = clampi(st, 1, 4)
	code = crest_code
	frame = fr
	calm = reduce_motion

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	back = TextureRect.new()
	back.texture = UI2.tex("res://assets/ui/clans/camp_%d.webp" % stage)
	back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	back.stretch_mode = TextureRect.STRETCH_SCALE
	back.modulate = Color(0.32, 0.3, 0.38)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	layer = Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.size = PAINT
	add_child(layer)
	art = TextureRect.new()
	art.texture = UI2.tex("res://assets/ui/clans/camp_%d.webp" % stage)
	art.set_anchors_preset(Control.PRESET_TOP_LEFT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.size = PAINT
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_meta("clan_camp", stage)
	var m := ShaderMaterial.new()
	m.shader = CampShader
	m.set_shader_parameter("paint_size", PAINT)
	m.set_shader_parameter("motion", 0.0 if calm else 1.0)
	var fire: Vector2 = FIRES[stage - 1]
	m.set_shader_parameter("fire", Vector3(fire.x, fire.y, 300.0))
	var cloth := []
	for b in BANNERS[stage - 1]:
		var r: Rect2 = b
		cloth.append(Vector4(r.position.x, r.position.y, r.end.x, r.end.y))
	m.set_shader_parameter("cloth", cloth)
	m.set_shader_parameter("cloth_n", cloth.size())
	var k := Crest.colors(code)
	m.set_shader_parameter("recolor", 0.0 if k.is_empty() else 1.0)
	if not k.is_empty():
		var fc: Color = k.field
		m.set_shader_parameter("field_col", Vector3(fc.r, fc.g, fc.b))
	art.material = m
	layer.add_child(art)
	# the crest on each banner
	for b in BANNERS[stage - 1]:
		var r: Rect2 = b
		var c := Crest.new()
		c.set_crest(code, frame)
		var w := r.size.x * CREST_W
		c.size = Vector2(w, w * Crest.ASPECT)
		c.position = Vector2(r.position.x + (r.size.x - w) * 0.5, r.position.y + r.size.y * 0.47 - c.size.y * 0.5)
		c.set_meta("banner_crest", true)
		layer.add_child(c)
		crests.append(c)
	# the fire
	var s: float = FIRE_SIZE[stage - 1]
	_halo = _glow(fire + Vector2(0, -10) * s, Vector2(380, 300) * s, Color(1.0, 0.5, 0.18, 0.3))
	_heart = _glow(fire + Vector2(0, -12) * s, Vector2(70, 60) * s, Color(1.0, 0.9, 0.6, 0.55))
	if not calm:
		_embers = CPUParticles2D.new()
		_embers.position = fire + Vector2(0, -24) * s
		_embers.amount = 18
		_embers.lifetime = 2.2
		_embers.preprocess = 2.2
		_embers.texture = CampScene._dot_tex()
		_embers.local_coords = false
		var g := Gradient.new()
		g.set_color(0, Color(1.0, 0.95, 0.7, 1.0))
		g.add_point(0.4, Color(1.0, 0.6, 0.2, 0.9))
		g.set_color(g.get_point_count() - 1, Color(0.9, 0.2, 0.05, 0.0))
		_embers.color_ramp = g
		var add := CanvasItemMaterial.new()
		add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_embers.material = add
		_embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		_embers.emission_rect_extents = Vector2(26, 10) * s
		_embers.direction = Vector2(0, -1)
		_embers.spread = 22.0
		_embers.gravity = Vector2(0, -25)
		_embers.initial_velocity_min = 40.0
		_embers.initial_velocity_max = 95.0
		_embers.tangential_accel_min = -25.0
		_embers.tangential_accel_max = 25.0
		_embers.scale_amount_min = 0.16
		_embers.scale_amount_max = 0.36
		layer.add_child(_embers)
		var flies = CampScene.Fireflies.new()
		flies.tex = CampScene.glow_texture()
		flies.area = FLIES
		flies.setup(10)
		layer.add_child(flies)
	# the night sky: stars that twinkle, and now and then one that falls
	var rng := RandomNumberGenerator.new()
	rng.seed = 197
	for i in 26:
		var at := Vector2(rng.randf_range(20.0, 980.0), rng.randf_range(16.0, SKY.end.y - 40.0))
		var st := _glow(at, Vector2.ONE * rng.randf_range(10.0, 18.0), Color(0.95, 0.93, 1.0, 0.35 if calm else 0.0))
		_stars.append([st, rng.randf_range(0.4, 1.2), rng.randf() * TAU])
	if not calm:
		var fall = CampScene.FallingStar.new()
		fall.tex = CampScene.glow_texture()
		fall.area = SKY
		fall.wait = 5.0
		layer.add_child(fall)
	_fit()

func _glow(centre: Vector2, sz: Vector2, col: Color) -> TextureRect:
	var t := TextureRect.new()
	t.texture = CampScene.glow_texture()
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.size = sz
	t.pivot_offset = sz * 0.5
	t.position = centre - sz * 0.5
	t.modulate = col
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	t.material = mat
	layer.add_child(t)
	return t

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_fit()

func _fit() -> void:
	# the painting covers this control (centred: a phone longer than 1:2 loses a little of its sides)
	if layer == null or size.x <= 0.0 or size.y <= 0.0:
		return
	k = maxf(size.x / PAINT.x, size.y / PAINT.y)
	origin = ((size - PAINT * k) * 0.5).round()
	if size.x > size.y:
		# 0.31.216 (landscape): the band from the banners to the fire, as tall as the screen; the darkened painting on
		# the sides (cover-scaled about the same band)
		var kb := maxf(size.x / PAINT.x, size.y / BAND.size.y)
		back.size = PAINT * kb
		back.position = Vector2((size.x - PAINT.x * kb) * 0.5, clampf(size.y * 0.5 - BAND.get_center().y * kb, size.y - PAINT.y * kb, 0.0))
		k = minf(k, size.y / BAND.size.y)
		origin = Vector2((size.x - PAINT.x * k) * 0.5, -BAND.position.y * k).round()
	back.visible = size.x > size.y and PAINT.x * k < size.x - 0.5
	layer.position = origin
	layer.scale = Vector2(k, k)

func to_screen(p: Vector2) -> Vector2:
	# a point of the painting -> this control's px
	return origin + p * k

func _process(delta: float) -> void:
	if calm or not is_visible_in_tree() or art == null:
		return
	_clock += delta
	var t := _clock
	var flick := 0.55 * sin(t * 7.3) + 0.3 * sin(t * 13.1 + 1.3) + 0.15 * sin(t * 2.1 + 0.4)
	_heart.modulate.a = 0.5 + 0.16 * flick
	_heart.scale = Vector2.ONE * (0.95 + 0.08 * flick)
	_halo.modulate.a = 0.28 + 0.07 * flick
	_halo.scale = Vector2.ONE * (0.97 + 0.05 * flick)
	var m := art.material as ShaderMaterial
	m.set_shader_parameter("clock", t)
	m.set_shader_parameter("fire_flick", flick)
	for st in _stars:
		(st[0] as TextureRect).modulate.a = 0.8 * pow(maxf(0.0, sin(t * float(st[1]) + float(st[2]))), 3.0)
