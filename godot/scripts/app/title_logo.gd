extends Control
# The title (0.31.193, Kevin: "Let's make a brand new title graphic that fits new game style" -> C4: "make the flags on
# side blow around and the lighting effect in middle show effects"): FATEBOUND split by a white-hot rift, FATE in ice
# blue, BOUND in fire, a crown over the split, a team flag at each end. Layers cut from one painting
# (tools/build_title_logo.py): the word with the crown and the rift; the two flags behind it, each waving from its pole
# (title_flag.gdshader); the rift crackling with lightning, its glow flickering, sparks spitting off it
# (title_rift_fx.gd). Still with Reduce Motion (and as the title screen's afterimages). Width sets the size (height
# follows); without the ui pack's art it falls back to text.
# (0.31.113-0.31.192: "All Tied Up" -- the rope-bound title with the captured King swinging from the knot.)
const UI = preload("res://scripts/app/ui.gd")
const UI2 = preload("res://scripts/app/ui2.gd")
const RiftFx = preload("res://scripts/app/title_rift_fx.gd")
const FLAG_SHADER = preload("res://scripts/app/title_flag.gdshader")

const BASE := Vector2(1400, 632)                                       # title_rift_base.webp
const FLAG_L := [Vector2(0.0, 153.1), Vector2(161, 369)]               # title_flag_l.webp: its corner on the base, its size
const FLAG_R := [Vector2(1233.2, 153.1), Vector2(167, 354)]            # title_flag_r.webp
# each pole's line in its flag's own px, (y, x) by y (the cloth waves with its distance from it)
const POLE_L := [Vector2(0.7, 102.5), Vector2(48.5, 114.8), Vector2(110.1, 133.3), Vector2(144.2, 140.1),
	Vector2(260.4, 140.1), Vector2(383.5, 126.5), Vector2(522.9, 119.6)]
const POLE_R := [Vector2(0.7, 63.6), Vector2(48.5, 55.4), Vector2(82.7, 45.1), Vector2(130.6, 31.4), Vector2(157.9, 39.6),
	Vector2(228.3, 54.0), Vector2(269.3, 60.8), Vector2(301.5, 69.0), Vector2(522.9, 69.0)]
const GLOW := [Vector2(605.0, 168.8), Vector2(120, 438)]               # title_rift_glow.webp
# the rift's middle, top to bottom (base px)
const RIFT := [Vector2(634.9, 204.4), Vector2(639.8, 212.6), Vector2(646.3, 220.8), Vector2(653.7, 229.0), Vector2(667.0, 237.2),
	Vector2(667.1, 245.4), Vector2(664.9, 253.6), Vector2(662.2, 261.8), Vector2(659.7, 270.0), Vector2(656.9, 278.2),
	Vector2(654.5, 286.4), Vector2(651.9, 294.6), Vector2(649.4, 302.8), Vector2(650.4, 311.0), Vector2(658.5, 319.2),
	Vector2(665.3, 327.4), Vector2(672.7, 335.6), Vector2(680.1, 343.8), Vector2(678.5, 352.1), Vector2(673.8, 360.3),
	Vector2(668.7, 368.5), Vector2(664.8, 376.7), Vector2(660.7, 384.9), Vector2(657.7, 393.1), Vector2(664.3, 401.3),
	Vector2(672.0, 409.5), Vector2(679.2, 417.7), Vector2(676.5, 425.9), Vector2(671.1, 434.1), Vector2(665.8, 442.3),
	Vector2(660.4, 450.5), Vector2(656.2, 458.7), Vector2(662.6, 466.9), Vector2(669.1, 475.1), Vector2(672.1, 483.3),
	Vector2(666.0, 491.5), Vector2(660.7, 499.7), Vector2(656.4, 507.9), Vector2(661.4, 516.1), Vector2(666.3, 524.3),
	Vector2(669.0, 532.5)]
const FLAG_AMP := 6.0                   # the flags' swing (flag px) in a steady breeze
const KICK_BOOST := 2.6                 # ...times this much more, dying away, after the title's slam

var calm := false
var t := 0.0
var boost := 0.0                        # the flags' extra swing (the slam), dying away
var flag_l: TextureRect
var flag_r: TextureRect
var rift: Control                       # title_rift_fx.gd
var _base: TextureRect

static func aspect() -> float:
	return BASE.y / BASE.x

func _init(still := false) -> void:
	calm = still
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bt := UI2.tex(UI2.V2 + "title_rift_base.webp")
	var lt := UI2.tex(UI2.V2 + "title_flag_l.webp")
	var rt := UI2.tex(UI2.V2 + "title_flag_r.webp")
	var gt := UI2.tex(UI2.V2 + "title_rift_glow.webp")
	if bt == null or lt == null or rt == null or gt == null:
		_fallback()
		return
	flag_l = _layer(lt)                 # (behind the word: the poles go behind its outline)
	flag_r = _layer(rt)
	flag_l.material = _flag_mat(lt, POLE_L, 1.0, 0.0)
	flag_r.material = _flag_mat(rt, POLE_R, -1.0, 0.37)
	_base = _layer(bt)
	rift = RiftFx.new(gt, still)
	var pts := PackedVector2Array()
	for q in RIFT:
		pts.append(q)
	rift.line = pts
	add_child(rift)
	resized.connect(_lay)

func _layer(tx: Texture2D) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tx
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r

func _flag_mat(tx: Texture2D, pole: Array, side: float, phase: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FLAG_SHADER
	m.set_shader_parameter("tex_px", Vector2(tx.get_size()))
	var pts := PackedVector2Array()
	for q in pole:
		pts.append(q)
	while pts.size() < 10:
		pts.append(pts[pts.size() - 1])
	m.set_shader_parameter("pole", pts)
	m.set_shader_parameter("pole_n", pole.size())
	m.set_shader_parameter("side", side)
	m.set_shader_parameter("amp", 0.0 if calm else FLAG_AMP)
	m.set_shader_parameter("reach", 130.0)
	m.set_shader_parameter("t", phase)
	m.set_meta("phase", phase)          # (the two flags out of step)
	return m

func _ready() -> void:
	if _base != null:
		_lay()                              # (sized before it went in)

func _lay() -> void:
	var s := size.x / BASE.x
	_base.position = Vector2.ZERO
	_base.size = BASE * s
	flag_l.position = FLAG_L[0] * s
	flag_l.size = FLAG_L[1] * s
	flag_r.position = FLAG_R[0] * s
	flag_r.size = FLAG_R[1] * s
	rift.position = Vector2.ZERO
	rift.size = BASE * s
	rift.lay(s, Rect2(GLOW[0], GLOW[1]))

func kick(deg: float) -> void:
	# the title slamming onto the wall: the flags whip about, the rift flares (deg: the slam's strength, title_screen.gd
	# KICK_DEG)
	if _base == null or calm:
		return
	boost = KICK_BOOST * clampf(deg / 32.0, 0.0, 1.5)
	rift.burst(1.0)

func set_shine(mat: Material) -> void:
	# 0.31.141: a material on the lettering (the title screen's gold glint)
	if _base != null:
		_base.material = mat

func flag_amp() -> float:
	return float((flag_l.material as ShaderMaterial).get_shader_parameter("amp")) if flag_l != null else 0.0

func _process(delta: float) -> void:
	if _base == null or calm:
		return
	t += delta
	boost *= exp(-delta / 0.9)
	for f in [flag_l, flag_r]:
		var m := (f as TextureRect).material as ShaderMaterial
		m.set_shader_parameter("t", t + float(m.get_meta("phase")))
		m.set_shader_parameter("amp", FLAG_AMP * (1.0 + boost))

func _fallback() -> void:
	# the text title, if the ui pack's art isn't there
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	var logo := UI2.text(v, "FATEBOUND", 50, UI2.GOLD, UI2.INK, 13)
	logo.add_theme_color_override("font_shadow_color", Color(0.1, 0.05, 0.0, 0.85))
	logo.add_theme_constant_override("shadow_offset_y", 6)
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
