extends RefCounted
# 0.31.79 menu look (Kevin: "really spruce up the menus ... very good looking and have animated parts"): framed panels
# on damask / parchment / wood / stone, glossy lipped buttons, Luckiest Guy titles with chunky outlines, ribbons,
# dividers and the 3D-style icons. Every box is one SDF skin (skin.gd + ui_skin.gdshader), crisp at any density.
const UI = preload("res://scripts/app/ui.gd")
const SkinNode = preload("res://scripts/app/skin.gd")
const LG = preload("res://assets/fonts/LuckiestGuy-Regular.ttf")

const V2 := "res://assets/ui/v2/"
const INK := Color("#2a1604")
const NAVY := Color("#0b1230")
const GOLD := Color("#ffd65a")
const CREAM := Color("#fff4d6")
const SOFT := Color("#c9d4f0")
const MUTED := Color("#9fb0d6")
const GREEN := Color("#7ee08f")
const CYAN := Color("#7fe3ff")
const PURPLE := Color("#d9a8ff")
const RED := Color("#ff6b5e")

static var _tex := {}

static func tex(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex[path]

static func icon_path(name: String) -> String:
	return V2 + "icons/%s.png" % name

# ---------------- skins ----------------
const RIM_GOLD := [Color("#fff4c8"), Color("#f7cd55"), Color("#b9761b")]
const RIM_BROWN := [Color("#c8925a"), Color("#7a4c26"), Color("#3b2412")]
const RIM_SILVER := [Color("#ffffff"), Color("#c9d3dc"), Color("#6f7d8e")]
const RIM_GREEN := [Color("#d6ffb8"), Color("#6be07c"), Color("#1f8a43")]
const RIM_PURPLE := [Color("#f3dcff"), Color("#c47bff"), Color("#6a2bb8")]
const RIM_BLUE := [Color("#d8ecff"), Color("#5fb6ff"), Color("#1e5aa8")]
const RIM_ORANGE := [Color("#fff0b0"), Color("#ffb13d"), Color("#b9590c")]

static func rim_of(name: String) -> Array:
	return {"gold": RIM_GOLD, "brown": RIM_BROWN, "silver": RIM_SILVER, "green": RIM_GREEN, "purple": RIM_PURPLE,
		"blue": RIM_BLUE, "orange": RIM_ORANGE}.get(name, RIM_GOLD)

static func panel_params(kind: String, rim := "gold") -> Dictionary:
	var dam := tex(V2 + "tex_damask.webp")
	var p := {}
	match kind:
		"royal":
			p = {"fill_top": Color("#4f7ff0"), "fill_bottom": Color("#0e1a52"), "pattern": dam, "pattern_mix": 1.0, "pattern_gain": 8.3, "pattern_luma": 1.0}
		"night":
			p = {"fill_top": Color(0.16, 0.24, 0.6, 0.95), "fill_bottom": Color(0.05, 0.07, 0.2, 0.97), "pattern": dam, "pattern_mix": 1.0, "pattern_gain": 8.3, "pattern_luma": 1.0}
		"purple":
			p = {"fill_top": Color("#a463f2"), "fill_bottom": Color("#25094d"), "pattern": dam, "pattern_mix": 1.0, "pattern_gain": 8.3, "pattern_luma": 1.0}
		"ember":
			p = {"fill_top": Color("#ff9a45"), "fill_bottom": Color("#3a1003"), "pattern": dam, "pattern_mix": 1.0, "pattern_gain": 8.3, "pattern_luma": 1.0}
		"green":
			p = {"fill_top": Color("#4fd27a"), "fill_bottom": Color("#0b3d22"), "pattern": dam, "pattern_mix": 1.0, "pattern_gain": 8.3, "pattern_luma": 1.0}
		"parch":
			p = {"fill_top": Color("#fffaf0"), "fill_bottom": Color("#e9d2a2"), "pattern": tex(V2 + "tex_parchment.webp"), "pattern_mix": 1.0, "pattern_gain": 1.12, "pattern_px": 320.0}
		"wood":
			p = {"fill_top": Color("#ffe2c0"), "fill_bottom": Color("#9a7a62"), "pattern": tex(V2 + "tex_wood.webp"), "pattern_mix": 1.0, "pattern_gain": 1.35, "pattern_px": 240.0}
		"stone":
			p = {"fill_top": Color("#9db0d8"), "fill_bottom": Color("#3a4568"), "pattern": tex(V2 + "tex_stone.webp"), "pattern_mix": 1.0, "pattern_gain": 2.4, "pattern_luma": 1.0, "pattern_px": 220.0}
		"glass":
			p = {"fill_top": Color(0.03, 0.05, 0.16, 0.78), "fill_bottom": Color(0.02, 0.03, 0.1, 0.86), "rim": 0.0, "outline": 1.5,
				"outline_color": Color(1.0, 0.84, 0.35, 0.45), "shadow_alpha": 0.0, "bevel": 0.06}
	var r: Array = rim_of(rim)
	var base := {"radius": 18.0, "outline": 2.0, "outline_color": INK, "rim": 3.0, "rim_a": r[0], "rim_b": r[1], "rim_c": r[2],
		"shadow_y": 6.0, "shadow_alpha": 0.55, "shadow_soft": 6.0, "bevel": 0.16}
	base.merge(p, true)
	return base

# fill top, fill bottom, lip, ink (outline + text outline)
const BTN := {
	"gold": [Color("#fff3ad"), Color("#f0a024"), Color("#b8650f"), Color("#3a1c02")],
	"green": [Color("#b4f7a4"), Color("#25a248"), Color("#16702f"), Color("#0b3416")],
	"orange": [Color("#ffe590"), Color("#f0621a"), Color("#a33c0b"), Color("#3d1602")],
	"purple": [Color("#e8ccff"), Color("#7236d6"), Color("#45198f"), Color("#1e0a45")],
	"blue": [Color("#a9c6ff"), Color("#2a4cae"), Color("#182c74"), Color("#0a1238")],
	"red": [Color("#ffb6a6"), Color("#d6372b"), Color("#8c1d15"), Color("#3a0805")],
	"grey": [Color("#d9dfe8"), Color("#6b778a"), Color("#4a5466"), Color("#1c2230")],
	"ghost": [Color(1, 1, 1, 0.12), Color(1, 1, 1, 0.05), Color(0, 0, 0, 0.25), Color(0, 0, 0, 0.6)],
}

static func button_params(color: String, radius := 14.0, lip := 6.0) -> Dictionary:
	var c: Array = BTN.get(color, BTN.blue)
	return {"radius": radius, "outline": 2.5, "outline_color": c[3], "rim": 0.0, "fill_top": c[0], "fill_bottom": c[1],
		"lip": lip, "lip_color": c[2], "gloss": 1.0, "bevel": 0.12, "shadow_y": 4.0, "shadow_alpha": 0.5, "shadow_soft": 4.0}

static func skin(parent: Control, params: Dictionary) -> Node2D:
	var s: Node2D = SkinNode.new(params)
	parent.add_child(s)
	parent.move_child(s, 0)
	return s

static func frame(parent: Node, kind := "royal", pad := 12, radius := 18.0, rim := "gold", extra := {}) -> VBoxContainer:
	# A framed panel; returns its content box (like UI.card).
	var pc := PanelContainer.new()
	var sb := StyleBoxEmpty.new()
	var p := panel_params(kind, rim)
	p.radius = radius
	p.merge(extra, true)
	var edge := float(p.outline) + float(p.rim)
	for side in ["left", "right", "top", "bottom"]:
		sb.set("content_margin_" + side, edge + pad)
	pc.add_theme_stylebox_override("panel", sb)
	parent.add_child(pc)
	skin(pc, p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	pc.add_child(v)
	return v

static func plate(parent: Control, kind := "royal", radius := 18.0, rim := "gold", extra := {}) -> Node2D:
	# Just the skin behind an existing control (for absolutely placed boxes).
	var p := panel_params(kind, rim)
	p.radius = radius
	p.merge(extra, true)
	return skin(parent, p)

# ---------------- text ----------------
static func text(parent: Node, s: String, size := 20, color := Color.WHITE, ink := INK, outline := -1, shadow := true) -> Label:
	var l := Label.new()
	l.text = s
	l.add_theme_font_override("font", LG)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	var o := outline if outline >= 0 else maxi(4, int(round(size / 3.2)))
	if o > 0:
		l.add_theme_color_override("font_outline_color", ink)
		l.add_theme_constant_override("outline_size", o)
	if shadow:
		l.add_theme_color_override("font_shadow_color", ink)
		l.add_theme_constant_override("shadow_offset_x", 0)
		l.add_theme_constant_override("shadow_offset_y", maxi(2, int(round(size / 11.0))))
		l.add_theme_constant_override("shadow_outline_size", o)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

static func body(parent: Node, s: String, size := 13, color := SOFT, wrap := true) -> Label:
	var l := UI.label(parent, s, size, color, UI.HEAVY_FONT)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func center(l: Label) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

# ---------------- buttons ----------------
static func button(parent: Node, label: String, color: String, on_press: Callable, key := "", size := 18, h := 48.0, radius := 14.0, icon := "") -> Button:
	var b := Button.new()
	b.text = label
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, h)
	var c: Array = BTN.get(color, BTN.blue)
	var lip := clampf(h * 0.12, 4.0, 9.0)
	for st_name in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		var sb := StyleBoxEmpty.new()
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = 4.0 + (2.0 if st_name in ["pressed", "hover_pressed"] else 0.0)
		sb.content_margin_bottom = lip
		b.add_theme_stylebox_override(st_name, sb)
	b.add_theme_font_override("font", LG)
	b.add_theme_font_size_override("font_size", size)
	var ink: Color = c[3] if color != "ghost" else Color(0, 0, 0, 0.7)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.55))
	b.add_theme_color_override("font_outline_color", ink)
	b.add_theme_constant_override("outline_size", maxi(4, int(round(size / 3.4))))
	if icon != "":
		b.icon = tex(icon)
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", int(h * 0.62))
		b.add_theme_constant_override("h_separation", 6)
	if key != "":
		b.set_meta("action_key", key)
	b.pressed.connect(on_press)
	parent.add_child(b)
	skin(b, button_params(color, radius, lip))
	return b

static func when_ready(c: Node, f: Callable) -> void:
	# Tweens need the node in the tree: run now if it is, else once it enters.
	if c.is_inside_tree():
		f.call()
	else:
		c.ready.connect(f, CONNECT_ONE_SHOT)

static func sweep(c: Control, period := 3.2, width := 70.0, alpha := 0.55) -> void:
	# A light band that sweeps across the control every few seconds (clipped to it).
	var clip := Control.new()
	clip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip.offset_left = 4
	clip.offset_right = -4
	clip.offset_top = 4
	clip.offset_bottom = -6
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(clip)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.5, Color(1, 1, 1, alpha))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0.5)
	gt.fill_to = Vector2(1, 0.5)
	gt.width = 64
	gt.height = 4
	var band := TextureRect.new()
	band.texture = gt
	band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	band.size = Vector2(width, 400)
	band.position = Vector2(-width - 40, -150)
	band.rotation = deg_to_rad(18)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(band)
	when_ready(c, func():
		var tw := c.create_tween().set_loops()
		tw.tween_interval(randf_range(0.2, 1.6))
		tw.tween_method(func(v: float): band.position.x = lerpf(-width - 60.0, clip.size.x + 40.0, v), 0.0, 1.0, 0.9).set_trans(Tween.TRANS_SINE)
		tw.tween_interval(period))

static func pulse(c: Control, amount := 0.03, secs := 1.1) -> void:
	c.resized.connect(func(): c.pivot_offset = c.size * 0.5)
	var go := func():
		var tw := c.create_tween().set_loops()
		tw.tween_property(c, "scale", Vector2.ONE * (1.0 + amount), secs).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(c, "scale", Vector2.ONE, secs).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	when_ready(c, go)

static func bob(c: Control, px := 5.0, secs := 1.3, delay := 0.0) -> void:
	var go := func():
		var y0 := c.position.y
		var tw := c.create_tween().set_loops()
		tw.tween_interval(delay)
		tw.tween_property(c, "position:y", y0 - px, secs).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(c, "position:y", y0, secs).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	when_ready(c, func(): c.get_tree().process_frame.connect(go, CONNECT_ONE_SHOT))

static func spin(c: Control, secs := 12.0) -> void:
	c.resized.connect(func(): c.pivot_offset = c.size * 0.5)
	var go := func():
		var tw := c.create_tween().set_loops()
		tw.tween_property(c, "rotation", TAU, secs).from(0.0)
	when_ready(c, go)

static func wiggle(c: Control, every := 2.8) -> void:
	c.resized.connect(func(): c.pivot_offset = c.size * 0.5)
	var go := func():
		var tw := c.create_tween().set_loops()
		tw.tween_interval(every)
		for a in [-10.0, 9.0, -6.0, 3.0, 0.0]:
			tw.tween_property(c, "rotation", deg_to_rad(a), 0.08)
	when_ready(c, go)

# ---------------- pieces ----------------
static func img(parent: Node, path: String, px := 40.0) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex(path)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(px, px)
	t.size = Vector2(px, px)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(t)
	return t

static func icon(parent: Node, name: String, px := 40.0) -> TextureRect:
	return img(parent, icon_path(name), px)

static func badge(parent: Control, n: String, at := Vector2(6, -6)) -> PanelContainer:
	# A red count bubble pinned to the parent's top-right corner, with a bounce every few seconds.
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#e8443a")
	sb.border_color = Color("#3a0805")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(11)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 2
	sb.shadow_offset = Vector2(0, 2)
	pc.add_theme_stylebox_override("panel", sb)
	pc.custom_minimum_size = Vector2(22, 22)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(pc)
	var l := UI.label(pc, n, 12, Color.WHITE, UI.HEAVY_FONT)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pc.anchor_left = 1.0
	pc.anchor_right = 1.0
	pc.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	pc.offset_right = at.x
	pc.offset_left = at.x - 22
	pc.offset_top = at.y
	pc.offset_bottom = at.y + 22
	pc.resized.connect(func(): pc.pivot_offset = pc.size * 0.5)
	when_ready(pc, func():
		var tw := pc.create_tween().set_loops()
		tw.tween_interval(2.0)
		tw.tween_property(pc, "scale", Vector2.ONE * 1.3, 0.12)
		tw.tween_property(pc, "scale", Vector2.ONE * 0.92, 0.1)
		tw.tween_property(pc, "scale", Vector2.ONE, 0.1))
	return pc

static func chip(parent: Node, s: String, fill: Color, ink: Color, border := Color(0, 0, 0, 0)) -> PanelContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(9)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(1)
	pc.add_theme_stylebox_override("panel", sb)
	pc.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(pc)
	var l := UI.label(pc, s, 10, ink, UI.HEAVY_FONT)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return pc

static func icon_chip(parent: Node, icon_file: String, s: String, fill: Color, ink: Color, border := Color(0, 0, 0, 0)) -> PanelContainer:
	var pc := chip(parent, "", fill, ink, border)
	var l: Label = pc.get_child(0)
	pc.remove_child(l)
	l.queue_free()
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 4)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(r)
	img(r, icon_file, 16.0)
	var t := UI.label(r, s, 10, ink, UI.HEAVY_FONT)
	t.autowrap_mode = TextServer.AUTOWRAP_OFF
	return pc

static func _diamond(parent: Node) -> void:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(14, 14)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(holder)
	var dia := Panel.new()
	var ds := StyleBoxFlat.new()
	ds.bg_color = GOLD
	ds.border_color = INK
	ds.set_border_width_all(2)
	dia.add_theme_stylebox_override("panel", ds)
	dia.size = Vector2(10, 10)
	dia.position = Vector2(2, 2)
	dia.pivot_offset = Vector2(5, 5)
	dia.rotation = PI / 4.0
	dia.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(dia)

static func _rule(parent: Node, fade_left: bool) -> void:
	var line := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(GOLD, 0.0) if fade_left else GOLD)
	g.set_color(1, GOLD if fade_left else Color(GOLD, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 64
	gt.height = 2
	line.texture = gt
	line.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	line.stretch_mode = TextureRect.STRETCH_SCALE
	line.custom_minimum_size = Vector2(0, 3)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)

static func divider(parent: Node, s: String, size := 22, sub := "") -> VBoxContainer:
	# ◆──── TITLE ────◆  with an optional muted line under it
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	parent.add_child(v)
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 8)
	v.add_child(r)
	_rule(r, true)
	_diamond(r)
	text(r, s, size, GOLD)
	_diamond(r)
	_rule(r, false)
	if sub != "":
		center(body(v, sub, 11, MUTED))
	return v

static func ribbon(parent: Control, title: String, sub: String, width: float, height := 52.0, colors := [Color("#5d89f0"), Color("#1b2d78")]) -> Control:
	# A banner ribbon with notched ends: a gold outer shape, a coloured inner one, the title and a line under it.
	var c := Control.new()
	c.custom_minimum_size = Vector2(width, height)
	c.size = Vector2(width, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
	var n := 16.0
	var shape := func(inset: float) -> PackedVector2Array:
		var w := width - inset * 2.0
		var h := height - inset * 2.0
		var o := Vector2(inset, inset)
		var k := n - inset * 0.6
		return PackedVector2Array([o, o + Vector2(w, 0), o + Vector2(w - k, h * 0.5), o + Vector2(w, h), o + Vector2(0, h), o + Vector2(k, h * 0.5)])
	var shadow := Polygon2D.new()
	shadow.polygon = shape.call(0.0)
	shadow.color = Color(0, 0, 0, 0.5)
	shadow.position = Vector2(0, 4)
	c.add_child(shadow)
	var outer := Polygon2D.new()
	outer.polygon = shape.call(0.0)
	outer.color = Color("#e8b546")
	c.add_child(outer)
	var inner := Polygon2D.new()
	inner.polygon = shape.call(3.0)
	var pts: PackedVector2Array = inner.polygon
	var cols := PackedColorArray()
	for pt in pts:
		cols.append((colors[0] as Color).lerp(colors[1], clampf(pt.y / height, 0.0, 1.0)))
	inner.vertex_colors = cols
	c.add_child(inner)
	var tl := text(c, title, int(height * 0.44) if sub != "" else int(height * 0.5), Color.WHITE, Color("#0e1433"))
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.position = Vector2(0, 4 if sub != "" else 0)
	tl.size = Vector2(width, height * (0.56 if sub != "" else 1.0))
	if sub != "":
		var sl := UI.label(c, sub, 11, Color("#ffe39a"), UI.HEAVY_FONT)
		sl.autowrap_mode = TextServer.AUTOWRAP_OFF
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sl.add_theme_color_override("font_outline_color", Color("#0e1433"))
		sl.add_theme_constant_override("outline_size", 3)
		sl.position = Vector2(0, height * 0.58)
		sl.size = Vector2(width, height * 0.34)
		sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

static func bar(parent: Node, value: float, max_value: float, top := Color("#b6f3ff"), bottom := Color("#36b9ea"), h := 12.0) -> Control:
	# A rounded progress bar with a gradient fill and a moving shine.
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
	skin(c, {"radius": h * 0.5, "outline": 2.0, "outline_color": Color("#050818"), "rim": 0.0, "fill_top": Color(0.01, 0.02, 0.07, 0.95),
		"fill_bottom": Color(0.03, 0.05, 0.14, 0.95), "shadow_alpha": 0.0, "bevel": -0.2})
	var f := Control.new()
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(f)
	var frac := clampf(value / maxf(1.0, max_value), 0.0, 1.0)
	var fs := skin(f, {"radius": h * 0.5 - 2.0, "outline": 0.0, "rim": 0.0, "fill_top": top, "fill_bottom": bottom, "shadow_alpha": 0.0, "gloss": 0.8, "bevel": 0.1})
	var lay := func():
		f.position = Vector2(2, 2)
		f.size = Vector2(maxf(0.0, (c.size.x - 4.0) * frac), c.size.y - 4.0)
		f.visible = frac > 0.0
	c.resized.connect(lay)
	sweep(f, 2.4, 40.0, 0.6)
	return c

static func knob_texture(px := 26) -> ImageTexture:
	# a gold slider knob: dark outline, gold body, a highlight
	var n := px * 3
	var im := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := Vector2(n, n) * 0.5
	for y in n:
		for x in n:
			var d := (Vector2(x + 0.5, y + 0.5) - c).length() / (n * 0.5)
			var col := Color(0, 0, 0, 0)
			if d < 1.0:
				col = Color("#2a1604")
			if d < 0.84:
				var t := float(y) / n
				col = Color("#fff3b8").lerp(Color("#d98516"), t)
				var hl := (Vector2(x + 0.5, y + 0.5) - c - Vector2(-n * 0.12, -n * 0.16)).length() / (n * 0.22)
				if hl < 1.0:
					col = col.lerp(Color.WHITE, (1.0 - hl) * 0.6)
			col.a *= clampf((1.0 - d) * n * 0.5, 0.0, 1.0)
			im.set_pixel(x, y, col)
	var tex := ImageTexture.create_from_image(im)
	tex.set_size_override(Vector2i(px, px))
	return tex

static var _knob: ImageTexture

static func style_slider(sl: HSlider) -> void:
	if _knob == null:
		_knob = knob_texture(26)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.01, 0.02, 0.07, 0.95)
	track.border_color = Color("#050818")
	track.set_border_width_all(2)
	track.set_corner_radius_all(8)
	track.content_margin_top = 7
	track.content_margin_bottom = 7
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#ffc94d")
	fill.border_color = Color("#fff3a8")
	fill.border_width_top = 2
	fill.set_corner_radius_all(8)
	fill.content_margin_top = 7
	fill.content_margin_bottom = 7
	fill.shadow_color = Color(1.0, 0.8, 0.3, 0.45)
	fill.shadow_size = 4
	sl.add_theme_stylebox_override("slider", track)
	sl.add_theme_stylebox_override("grabber_area", fill)
	sl.add_theme_stylebox_override("grabber_area_highlight", fill)
	sl.add_theme_icon_override("grabber", _knob)
	sl.add_theme_icon_override("grabber_highlight", _knob)
	sl.custom_minimum_size = Vector2(0, 30)

static func toggle(parent: Node, label: String, sub: String, on: bool, key: String, changed: Callable) -> Button:
	# A label on the left and a pill switch on the right (green ON / dark OFF) that slides.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	text(v, label.to_upper(), 14, Color.WHITE)
	body(v, sub, 11, MUTED, false)
	var b := Button.new()
	b.toggle_mode = true
	b.button_pressed = on
	b.focus_mode = Control.FOCUS_NONE
	for st_name in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		b.add_theme_stylebox_override(st_name, StyleBoxEmpty.new())
	b.custom_minimum_size = Vector2(74, 36)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.set_meta("action_key", key)
	row.add_child(b)
	var sk := skin(b, button_params("green" if on else "grey", 18.0, 3.0))
	var knob := Panel.new()
	var ks := StyleBoxFlat.new()
	ks.bg_color = Color("#f2f6ff")
	ks.border_color = Color("#1c2230")
	ks.set_border_width_all(2)
	ks.set_corner_radius_all(13)
	ks.shadow_color = Color(0, 0, 0, 0.35)
	ks.shadow_size = 2
	ks.shadow_offset = Vector2(0, 2)
	knob.add_theme_stylebox_override("panel", ks)
	knob.size = Vector2(26, 26)
	knob.position = Vector2(42 if on else 6, 4)
	knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(knob)
	var tl := UI.label(b, "ON" if on else "OFF", 11, Color.WHITE, UI.HEAVY_FONT)
	tl.autowrap_mode = TextServer.AUTOWRAP_OFF
	tl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	tl.add_theme_constant_override("outline_size", 3)
	tl.size = Vector2(30, 26)
	tl.position = Vector2(10 if on else 38, 3)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.toggled.connect(func(now_on: bool):
		var c: Array = BTN.green if now_on else BTN.grey
		sk.set_param("fill_top", c[0])
		sk.set_param("fill_bottom", c[1])
		sk.set_param("lip_color", c[2])
		sk.set_param("outline_color", c[3])
		tl.text = "ON" if now_on else "OFF"
		tl.position.x = 10 if now_on else 38
		b.create_tween().tween_property(knob, "position:x", 42.0 if now_on else 6.0, 0.15).set_trans(Tween.TRANS_BACK)
		changed.call(now_on))
	return b

static func dim_button(b: Button, off: bool) -> void:
	b.disabled = off                       # (its skin greys itself: skin.gd)

static func ray_texture(color := Color(1, 0.9, 0.6), rays := 14) -> ImageTexture:
	# Soft sunburst: alternating rays fading out from the centre (for chest reveals, the prize and VICTORY).
	var n := 256
	var im := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := Vector2(n, n) * 0.5
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5, y + 0.5) - c
			var r := d.length() / (n * 0.5)
			if r > 1.0:
				im.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var a := atan2(d.y, d.x)
			var ray := pow(maxf(0.0, cos(a * rays)), 3.0)
			var fade := (1.0 - r) * (1.0 - r)
			im.set_pixel(x, y, Color(color, clampf(ray * fade * 1.2 + (1.0 - r) * 0.12, 0.0, 1.0)))
	return ImageTexture.create_from_image(im)

static func rays(parent: Control, size: float, color := Color(1, 0.9, 0.6), secs := 30.0, alpha := 0.5) -> TextureRect:
	var t := TextureRect.new()
	t.texture = _rays_cached(color)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.size = Vector2(size, size)
	t.custom_minimum_size = Vector2(size, size)
	t.pivot_offset = Vector2(size, size) * 0.5
	t.modulate = Color(1, 1, 1, alpha)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	t.material = mat
	parent.add_child(t)
	var go := func():
		var tw := t.create_tween().set_loops()
		tw.tween_property(t, "rotation", TAU, secs).from(0.0)
	when_ready(t, go)
	return t

static var _ray_cache := {}

static func _rays_cached(color: Color) -> ImageTexture:
	var k := color.to_html()
	if not _ray_cache.has(k):
		_ray_cache[k] = ray_texture(color)
	return _ray_cache[k]

static func glow_tex() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	return gt

static func glow(parent: Control, rect: Rect2, color: Color, breathe := true) -> TextureRect:
	var t := TextureRect.new()
	t.texture = glow_tex()
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.position = rect.position
	t.size = rect.size
	t.modulate = color
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(t)
	if breathe:
		var go := func():
			var tw := t.create_tween().set_loops()
			tw.tween_property(t, "modulate:a", color.a * 0.5, 1.4).set_trans(Tween.TRANS_SINE)
			tw.tween_property(t, "modulate:a", color.a, 1.4).set_trans(Tween.TRANS_SINE)
		when_ready(t, go)
	return t
