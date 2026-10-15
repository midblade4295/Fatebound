extends Control
# 0.31.113 (Kevin: "I like the all tied up one. Can you also make it so the king swings back and forth from the rope"):
# Home's title. FATEBOUND bound in rope over the "STEAL THEIR KING. SAVE YOURS." scroll, and the captured King hanging
# from the knot under the D, swinging gently on his two rope ends. Two layers cut from one painting
# (tools/build_title_logo.py): the logo with the King painted out, and the King turned about the knot. He hangs still
# with Reduce Motion on. Width sets the size (height follows); without the ui pack's art it falls back to text.
const UI = preload("res://scripts/app/ui.gd")
const UI2 = preload("res://scripts/app/ui2.gd")

const TAGLINE := "STEAL THEIR KING. SAVE YOURS."
const BASE := Vector2(1211, 571)        # logo_base.webp
const KING_AT := Vector2(898, 193)      # logo_king.webp's corner on the base
const KING_SIZE := Vector2(251, 378)
const PIVOT := Vector2(1044, 192)       # under the knot, on the base
const SWING_DEG := 7.0                  # each way
const PERIOD := 2.8                     # seconds, there and back

var calm := false
var t := 0.0
var king: TextureRect
var _base: TextureRect
var _kick := 0.0                        # 0.31.141: extra swing (degrees) from the title screen's slam, dying away

static func aspect() -> float:
	return BASE.y / BASE.x

func _init(still := false) -> void:
	calm = still
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bt := UI2.tex(UI2.V2 + "logo_base.webp")
	var kt := UI2.tex(UI2.V2 + "logo_king.webp")
	if bt == null or kt == null:
		_fallback()
		return
	_base = _layer(bt)
	king = _layer(kt)
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

func _lay() -> void:
	var s := size.x / BASE.x
	_base.position = Vector2.ZERO
	_base.size = BASE * s
	king.position = KING_AT * s
	king.size = KING_SIZE * s
	king.pivot_offset = (PIVOT - KING_AT) * s

func kick(deg: float) -> void:
	# 0.31.141: the title slamming onto the wall knocks the King into a big swing that dies down to his gentle one
	if king == null or calm:
		return
	_kick = maxf(0.0, deg - SWING_DEG)
	t = 0.0

func set_shine(mat: Material) -> void:
	# 0.31.141: a material on the lettering (the title screen's gold glint)
	if _base != null:
		_base.material = mat

func _process(delta: float) -> void:
	if king == null:
		return
	if calm:
		king.rotation = 0.0
		return
	t = fmod(t + delta, PERIOD)
	_kick *= exp(-delta / 1.0)
	king.rotation = deg_to_rad(SWING_DEG + _kick) * sin(TAU * t / PERIOD)

func _fallback() -> void:
	# the text logo it replaced, with the new line
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	var logo := UI2.text(v, "FATEBOUND", 50, UI2.GOLD, UI2.INK, 13)
	logo.add_theme_color_override("font_shadow_color", Color(0.1, 0.05, 0.0, 0.85))
	logo.add_theme_constant_override("shadow_offset_y", 6)
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var tag := UI.label(v, TAGLINE, 11, UI2.CREAM, UI.HEAVY_FONT)
	tag.autowrap_mode = TextServer.AUTOWRAP_OFF
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	tag.add_theme_constant_override("outline_size", 4)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
