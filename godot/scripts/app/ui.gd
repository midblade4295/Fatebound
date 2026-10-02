extends RefCounted
# Fatebound Siege UI toolkit: palette, fonts and styled building blocks for the app shell.
# Static helpers only; screens call these so the whole app shares one look.

const TITLE_FONT = preload("res://assets/fonts/Cinzel-Black.woff2")
const HEAVY_FONT = preload("res://assets/fonts/Nunito-ExtraBold.woff2")
const BODY_FONT = preload("res://assets/fonts/Nunito-Bold.woff2")
const Icon = preload("res://scripts/app/icon.gd")

const BG_TOP := Color("#13203a")
const BG_BOTTOM := Color("#070b15")
const CARD := Color(0.086, 0.137, 0.235, 0.94)
const CARD_HI := Color("#2d4a78")
const GOLD := Color("#ffc94d")
const CYAN := Color("#5fd2f0")
const GREEN := Color("#5fdc86")
const RED := Color("#ff5f57")
const PURPLE := Color("#b77cff")
const TEXT := Color("#f2f5fa")
const MUTED := Color("#93a4bd")

# style: [fill, lip (darker bottom edge), text colour]
const BUTTONS := {
	"primary":   [Color("#ff9a2e"), Color("#b04f10"), Color("#2a1300")],
	"gold":      [Color("#ffc94d"), Color("#a3680f"), Color("#2e1d00")],
	"secondary": [Color("#26406b"), Color("#101d34"), Color("#eef3fa")],
	"premium":   [Color("#9b5cff"), Color("#4e2698"), Color("#ffffff")],
	"claim":     [Color("#43c86f"), Color("#1d7a3f"), Color("#062b14")],
	"danger":    [Color("#ff5f57"), Color("#9c2621"), Color("#ffffff")],
	"ghost":     [Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.02), Color("#dfe7f2")],
}

static func card_style(fill := CARD, radius := 18, border := CARD_HI, shadow := true) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(radius)
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.border_width_top = 2                 # a lighter top edge reads as a bevel
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	if shadow:
		sb.shadow_color = Color(0, 0, 0, 0.45)
		sb.shadow_size = 10
		sb.shadow_offset = Vector2(0, 5)
	sb.anti_aliasing = true
	return sb

static func card(parent: Node, fill := CARD, border := CARD_HI) -> VBoxContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", card_style(fill, 18, border))
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	return v

static func label(parent: Node, text: String, size := 14, color := TEXT, font: Font = null, outline := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font if font != null else HEAVY_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		l.add_theme_constant_override("outline_size", maxi(3, size / 5))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l

static func title(parent: Node, text: String, size := 22, color := GOLD) -> Label:
	var l := label(parent, text, size, color, TITLE_FONT, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

static func _button_box(fill: Color, lip: Color, pressed: bool, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(radius)
	sb.border_color = lip
	sb.border_width_bottom = 2 if pressed else 6
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10 + (4 if pressed else 0)
	sb.content_margin_bottom = 10
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 1 if pressed else 6
	sb.shadow_offset = Vector2(0, 1 if pressed else 4)
	sb.anti_aliasing = true
	return sb

static func button(parent: Node, text: String, style: String, on_press: Callable, key := "", size := 16, radius := 16) -> Button:
	var b := Button.new()
	b.text = text
	style_button(b, style, size, radius)
	if key != "":
		b.set_meta("action_key", key)
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b

static func style_button(b: Button, style: String, size := 16, radius := 16) -> void:
	# The shared tactile look; also used by the in-match HUD so menus and battle match.
	var st: Array = BUTTONS.get(style, BUTTONS.secondary)
	var fill: Color = st[0]
	var lip: Color = st[1]
	b.add_theme_stylebox_override("normal", _button_box(fill, lip, false, radius))
	b.add_theme_stylebox_override("hover", _button_box(fill.lightened(0.06), lip, false, radius))
	b.add_theme_stylebox_override("pressed", _button_box(fill.darkened(0.08), lip, true, radius))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var dis := _button_box(Color(fill.r, fill.g, fill.b, 0.35).darkened(0.3), Color(lip, 0.4), false, radius)
	b.add_theme_stylebox_override("disabled", dis)
	b.add_theme_font_override("font", HEAVY_FONT)
	b.add_theme_font_size_override("font_size", size)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, st[2])
	b.add_theme_color_override("font_disabled_color", Color(st[2], 0.45))
	b.focus_mode = Control.FOCUS_NONE

static func tighten(b: Button, side := 6) -> void:
	# Narrow side padding for buttons in tight rows (in-match dice, two-up action rows); long
	# labels are clipped instead of pushing the row past its panel.
	for st_name in ["normal", "hover", "pressed", "disabled"]:
		var sb := b.get_theme_stylebox(st_name) as StyleBoxFlat
		if sb != null:
			sb.content_margin_left = side
			sb.content_margin_right = side
	b.clip_text = true
	b.custom_minimum_size.x = 0

static var _tex_cache: Dictionary = {}

static func tex(path: String) -> Texture2D:
	if not _tex_cache.has(path):
		_tex_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex_cache[path]

static func tex_icon(parent: Node, path: String, px := 24) -> TextureRect:
	# A pre-rendered image (Blender/Godot renders in assets/ui) at a fixed size.
	var t := TextureRect.new()
	t.texture = tex(path)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(px, px)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(t)
	return t

static func play_button(parent: Node, text: String, on_press: Callable, key := "") -> Button:
	# The big call to action: orange glow, a slow pulse and a light sweep every few seconds.
	var b := button(parent, text, "primary", on_press, key, 34, 22)
	b.add_theme_font_override("font", TITLE_FONT)
	b.custom_minimum_size = Vector2(0, 82)
	for st_name in ["normal", "hover", "pressed"]:
		var sb := b.get_theme_stylebox(st_name).duplicate() as StyleBoxFlat
		sb.shadow_color = Color(1.0, 0.5, 0.08, 0.5)
		sb.shadow_size = 18
		sb.shadow_offset = Vector2(0, 5)
		b.add_theme_stylebox_override(st_name, sb)
	var clip := Control.new()                     # clips the sweep to the button, not the glow
	clip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(clip)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.5, Color(1, 1, 1, 0.42))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0.5)
	gt.fill_to = Vector2(1, 0.5)
	gt.width = 128
	gt.height = 8
	var band := TextureRect.new()
	band.texture = gt
	band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	band.size = Vector2(110, 90)
	band.position = Vector2(-140, -4)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(band)
	b.resized.connect(func(): b.pivot_offset = b.size * 0.5)
	if b.is_inside_tree():
		var tw := b.create_tween().set_loops()
		tw.tween_method(func(v: float): band.position.x = lerpf(-140.0, clip.size.x + 30.0, v), 0.0, 1.0, 0.85).set_trans(Tween.TRANS_SINE)
		tw.tween_interval(2.6)
		var pulse := b.create_tween().set_loops()
		pulse.tween_property(b, "scale", Vector2(1.022, 1.022), 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		pulse.tween_property(b, "scale", Vector2.ONE, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return b

static func icon(parent: Node, kind: String, px := 24, tint := Color.WHITE) -> Control:
	var i := Icon.new()
	i.kind = kind
	i.tint = tint
	i.custom_minimum_size = Vector2(px, px)
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(i)
	return i

static func progress(parent: Node, value: float, max_value: float, fill := GOLD, height := 12) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.max_value = maxf(1.0, max_value)
	pb.value = clampf(value, 0.0, pb.max_value)
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(0, height)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	bg.set_corner_radius_all(height / 2)
	bg.border_color = Color(1, 1, 1, 0.08)
	bg.set_border_width_all(1)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.set_corner_radius_all(height / 2)
	fg.border_color = fill.lightened(0.35)
	fg.border_width_top = 2
	pb.add_theme_stylebox_override("background", bg)
	pb.add_theme_stylebox_override("fill", fg)
	parent.add_child(pb)
	return pb

static func row(parent: Node, sep := 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	parent.add_child(h)
	return h

static func spacer(parent: Node, h := 8.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	parent.add_child(c)
	return c

static func grow(c: Control) -> Control:
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c

static func compact(n: int) -> String:
	if n >= 1000000:
		return "%.1fM" % (n / 1000000.0)
	if n >= 10000:
		return "%.1fK" % (n / 1000.0)
	return str(n)

static func duration(seconds: int) -> String:
	var s := maxi(0, seconds)
	if s >= 86400:
		return "%dd %dh" % [s / 86400, (s % 86400) / 3600]
	if s >= 3600:
		return "%dh %dm" % [s / 3600, (s % 3600) / 60]
	return "%dm" % maxi(1, s / 60)
