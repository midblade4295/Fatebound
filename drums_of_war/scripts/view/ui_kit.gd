extends RefCounted
## The HUD's look, in one place: palette, lettering, and the drawing routines for wood, brass,
## rounded boxes, the floating banner and tray, the gold cost coin, strength bars, the Powder
## trough and card faces.
##
## Every routine takes the CanvasItem to draw on, so the battle screen and each card (a node of
## its own, see card_view.gd) draw with the same kit. Nothing here holds game state.

const INK := Color("15233a")
const CREAM := Color("f6ead0")
const AMBER := Color("ffb000")
const WOOD_DARK := Color("2a1a0f")
const BRASS_DARK := Color("7a5a1e")
const BRASS_MID := Color("c9a03c")
const BRASS_LIGHT := Color("f5d98a")
const TEAM_BLUE := Color("2456c9")
const ORDER_PURPLE := Color("6a3fa8")
const PARCHMENT := Color("ecd9a6")
const PARCHMENT_LIGHT := Color("f8ecc6")
const PARCHMENT_DARK := Color("c9ad72")
const BROWN_INK := Color("38220e")
const CARD_HEAD := 23.0             # the strip across a card's top that names its kind
const CARD_NAME := 25.0             # the name plate along its foot

var font: Font
var font_bold: FontVariation
var wood: NoiseTexture2D
var _boxes: Dictionary = {}
var _ramps: Dictionary = {}


func _init() -> void:
	font = ThemeDB.fallback_font
	font_bold = FontVariation.new()
	font_bold.base_font = font
	font_bold.variation_embolden = 0.85
	wood = _make_wood()


# --- Lettering ---------------------------------------------------------------------------------

func text(c: CanvasItem, pos: Vector2, string: String, size: int, colour: Color, align: int = HORIZONTAL_ALIGNMENT_CENTER,
		width: float = 200.0, bold: bool = false) -> void:
	var origin := pos
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		origin.x -= width * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		origin.x -= width
	c.draw_string(font_bold if bold else font, origin, string, align, width, size, colour)


## Bold lettering with a thick dark outline and a drop shadow, legible over grass, smoke and
## troops alike.
func outlined(c: CanvasItem, pos: Vector2, string: String, size: int, colour: Color, width: float = 320.0, outline: int = 7) -> void:
	var origin := pos - Vector2(width * 0.5, 0.0)
	var dark := Color(0.09, 0.06, 0.05, colour.a)
	c.draw_string_outline(font_bold, origin + Vector2(0, 3), string, HORIZONTAL_ALIGNMENT_CENTER, width, size, outline, Color(0, 0, 0, 0.45 * colour.a))
	c.draw_string_outline(font_bold, origin, string, HORIZONTAL_ALIGNMENT_CENTER, width, size, outline, dark)
	c.draw_string(font_bold, origin, string, HORIZONTAL_ALIGNMENT_CENTER, width, size, colour)


## A name set one word to a line, centred on a point.
func words(c: CanvasItem, centre: Vector2, name: String, size: int, colour: Color, width: float) -> void:
	var parts := name.split(" ")
	var y := centre.y - (parts.size() - 1) * (size + 2) * 0.5
	for w: String in parts:
		text(c, Vector2(centre.x, y), w, size, colour, HORIZONTAL_ALIGNMENT_CENTER, width)
		y += size + 2


## Bold lettering centred on pos.x, shrunk a point at a time until it fits the width.
func fitted(c: CanvasItem, pos: Vector2, string: String, size: int, colour: Color, width: float) -> void:
	var fit := size
	while fit > 8 and font_bold.get_string_size(string, HORIZONTAL_ALIGNMENT_LEFT, -1, fit).x > width:
		fit -= 1
	c.draw_string(font_bold, pos - Vector2(width * 0.5, (size - fit) * 0.4), string, HORIZONTAL_ALIGNMENT_CENTER, width, fit, colour)


# --- Wood and brass ----------------------------------------------------------------------------

## A strip of wood grain, made once: noise much longer one way than the other, in browns.
func _make_wood() -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.035
	n.fractal_octaves = 4
	n.seed = 1861
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.4, 0.62, 0.8, 1.0])
	ramp.colors = PackedColorArray([Color("38230f"), Color("4a2f17"), Color("5a3a1d"), Color("4f3319"), Color("6a4624")])
	var t := NoiseTexture2D.new()
	t.width = 48
	t.height = 256
	t.seamless = true
	t.noise = n
	t.color_ramp = ramp
	return t


## A panel of dark planks: grain running across, a seam every plank's width, lit from above so
## it darkens toward the bottom. The canvas item must have texture_repeat enabled.
func wood_panel(c: CanvasItem, rect: Rect2, tint: Color = Color.WHITE) -> void:
	c.draw_rect(rect, Color("4a2f17") * tint)
	if wood != null:
		c.draw_texture_rect_region(wood, rect, Rect2(0, 0, rect.size.x / 9.0, rect.size.y / 1.1), tint)
	var plank := 46.0
	var y := rect.position.y + plank
	while y < rect.end.y - 4.0:
		c.draw_rect(Rect2(rect.position.x, y, rect.size.x, 2.0), Color(0.08, 0.05, 0.03, 0.55))
		c.draw_rect(Rect2(rect.position.x, y + 2.0, rect.size.x, 1.0), Color(1, 0.9, 0.7, 0.07))
		y += plank
	# Top-lit gradient: a pale wash over the upper third, shade gathering toward the foot.
	var bands := 6
	for i in bands:
		var t := float(i) / (bands - 1)
		var band := Rect2(rect.position.x, rect.position.y + rect.size.y * i / bands, rect.size.x, rect.size.y / bands + 1.0)
		c.draw_rect(band, Color(1, 0.92, 0.75, 0.07 * (1.0 - t * 2.2)) if t < 0.45 else Color(0, 0, 0, 0.22 * (t - 0.45) / 0.55))


## A bevelled brass strip: dark edge, bright face, dark edge.
func brass_strip(c: CanvasItem, rect: Rect2) -> void:
	c.draw_rect(rect, BRASS_DARK)
	c.draw_rect(Rect2(rect.position + Vector2(0, 1), Vector2(rect.size.x, maxf(1.0, rect.size.y - 2.0))), BRASS_MID)
	c.draw_rect(Rect2(rect.position + Vector2(0, 1), Vector2(rect.size.x, 1.0)), BRASS_LIGHT)


func brass_frame(c: CanvasItem, rect: Rect2, width: float = 3.0) -> void:
	c.draw_rect(rect, BRASS_DARK, false, width + 2.0)
	c.draw_rect(rect, BRASS_MID, false, width)
	c.draw_rect(rect.grow(width * 0.5 - 0.5), BRASS_LIGHT, false, 1.0)


func rivet(c: CanvasItem, at: Vector2) -> void:
	c.draw_circle(at + Vector2(0, 1.5), 5.0, Color(0, 0, 0, 0.45))
	c.draw_circle(at, 5.0, BRASS_DARK)
	c.draw_circle(at, 3.8, BRASS_MID)
	c.draw_circle(at + Vector2(-1.2, -1.2), 1.5, BRASS_LIGHT)


## A rounded box with an optional border and soft shadow; made once per look and reused.
func box(key: String, fill: Color, radius: float, border: float = 0.0, border_colour: Color = Color.BLACK,
		shadow: float = 0.0, shadow_colour: Color = Color(0, 0, 0, 0.5), shadow_drop: float = 0.0) -> StyleBoxFlat:
	if not _boxes.has(key):
		var sb := StyleBoxFlat.new()
		sb.bg_color = fill
		sb.set_corner_radius_all(int(radius))
		sb.set_border_width_all(int(border))
		sb.border_color = border_colour
		sb.shadow_size = int(shadow)
		sb.shadow_color = shadow_colour
		sb.shadow_offset = Vector2(0, shadow_drop)
		sb.anti_aliasing = true
		_boxes[key] = sb
	return _boxes[key]


## The Powder cost as an embossed gold coin with a pale numeral.
func coin(c: CanvasItem, at: Vector2, cost: int, can_pay: bool) -> void:
	var dull := 1.0 if can_pay else 0.66
	var grey := Color(dull, dull, dull)
	c.draw_circle(at + Vector2(0, 2.5), 14.5, Color(0, 0, 0, 0.45))
	c.draw_circle(at, 14.5, Color("4a300c") * grey)
	c.draw_circle(at, 13.0, Color("f3d477") * grey)
	c.draw_circle(at, 10.8, Color("c68f28") * grey)
	c.draw_arc(at, 11.8, PI * 1.05, PI * 1.6, 12, Color(1.0, 0.97, 0.78, 0.9 * dull), 1.5)
	c.draw_arc(at, 11.8, PI * 0.05, PI * 0.6, 12, Color(0.4, 0.26, 0.04, 0.7), 1.5)
	var label := str(cost)
	var origin := at + Vector2(-15.0, 6.5)
	c.draw_string_outline(font_bold, origin, label, HORIZONTAL_ALIGNMENT_CENTER, 30.0, 18, 4, Color("4a300c") * grey)
	c.draw_string(font_bold, origin, label, HORIZONTAL_ALIGNMENT_CENTER, 30.0, 18, Color(1.0, 0.96, 0.8) * grey)


# --- Bars --------------------------------------------------------------------------------------

## A strength bar: a recessed dark slot holding a glossy fill, lighter above and darker below.
## "recent" (at least "fraction") is the strength shown a moment ago; the difference is drawn
## pale, so a heavy hit reads as a chunk coming off. "flash" washes the fill white.
func strength_bar(c: CanvasItem, at: Vector2, width: float, height: float, fraction: float, recent: float,
		colour: Color, flash: bool) -> void:
	var slot := Rect2(at - Vector2(2, 2), Vector2(width + 4.0, height + 4.0))
	c.draw_style_box(box("bar_slot", Color("0d0906"), 3.0, 1.0, Color(0, 0, 0, 0.9), 3.0, Color(0, 0, 0, 0.5), 1.0), slot)
	c.draw_rect(Rect2(at, Vector2(width, maxf(1.0, height * 0.3))), Color(0, 0, 0, 0.5))          # the slot's inner shadow
	if recent > fraction + 0.002:
		c.draw_rect(Rect2(at, Vector2(width * recent, height)), Color(1.0, 0.95, 0.8))
	var w := width * clampf(fraction, 0.0, 1.0)
	if w <= 0.0:
		return
	var body := Color(1, 1, 1) if flash else colour
	c.draw_rect(Rect2(at, Vector2(w, height)), body)
	c.draw_rect(Rect2(at, Vector2(w, height * 0.5)), body.lightened(0.38))                        # upper half catches the light
	c.draw_rect(Rect2(at + Vector2(0, height * 0.72), Vector2(w, height * 0.28)), body.darkened(0.3))
	c.draw_rect(Rect2(at + Vector2(0, maxf(0.5, height * 0.12)), Vector2(w, maxf(1.0, height * 0.16))), Color(1, 1, 1, 0.55))   # gloss
	c.draw_rect(Rect2(at + Vector2(w - 1.0, 0), Vector2(1.0, height)), Color(1, 1, 1, 0.5))       # bright leading edge


## A structure's strength: a gunmetal frame round a recessed slot, the fill running from a deep
## colour to a hot one at its leading end, glossy across the top.
func framed_bar(c: CanvasItem, at: Vector2, width: float, height: float, fraction: float, recent: float,
		deep: Color, hot: Color, flash: bool) -> void:
	var slot := Rect2(at, Vector2(width, height))
	c.draw_style_box(box("fbar_frame", Color("3b3f48"), 5.0, 1.0, Color("111216"), 5.0, Color(0, 0, 0, 0.5), 2.0), slot.grow(3.5))
	c.draw_rect(Rect2(slot.position + Vector2(-1.5, -2.5), Vector2(width + 3.0, 1.0)), Color(1, 1, 1, 0.38))      # frame's top edge
	c.draw_style_box(box("fbar_slot", Color("120e0c"), 2.0), slot.grow(0.5))
	if recent > fraction + 0.002:
		c.draw_rect(Rect2(at, Vector2(width * clampf(recent, 0.0, 1.0), height)), Color(1.0, 0.95, 0.8))
	var w := width * clampf(fraction, 0.0, 1.0)
	if w <= 0.5:
		return
	# The fill is one stretched gradient texture and four overlays, not a stack of slices: this
	# is drawn for every structure every frame.
	var body := Rect2(at, Vector2(w, height))
	if flash:
		c.draw_rect(body, Color(1, 1, 1))
	else:
		c.draw_texture_rect(_ramp(deep, hot), body, false)
	c.draw_rect(Rect2(at, Vector2(w, height * 0.5)), Color(1, 1, 1, 0.2))
	c.draw_rect(Rect2(at + Vector2(0, height * 0.74), Vector2(w, height * 0.26)), Color(0, 0, 0, 0.24))
	c.draw_rect(Rect2(at + Vector2(1.0, height * 0.14), Vector2(maxf(0.0, w - 2.0), maxf(1.0, height * 0.18))), Color(1, 1, 1, 0.5))      # gloss
	c.draw_rect(Rect2(at + Vector2(w - 1.0, 0), Vector2(1.0, height)), Color(1, 1, 1, 0.45))


## A left-to-right colour ramp: deep for the first half, running to hot at the leading end.
func _ramp(deep: Color, hot: Color) -> GradientTexture2D:
	var key := deep.to_html() + hot.to_html()
	if not _ramps.has(key):
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		g.colors = PackedColorArray([deep, deep, hot])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.width = 64
		t.height = 4
		_ramps[key] = t
	return _ramps[key]


# --- Panels ------------------------------------------------------------------------------------

## The top banner: a wood plank with pointed brass-bound ends, and a darker plaque for the clock
## standing proud of its middle. Both float over the battlefield on a soft shadow.
func banner(c: CanvasItem, plank: Rect2, plaque: Rect2) -> void:
	var tip := 11.0
	var mid := plank.get_center().y
	c.draw_style_box(box("banner_shadow", Color(0, 0, 0, 0.3), 8.0, 0.0, Color.BLACK, 9.0, Color(0, 0, 0, 0.45), 5.0), plank.grow_individual(tip * 0.5, 0, tip * 0.5, 0))
	var left := PackedVector2Array([plank.position, Vector2(plank.position.x - tip, mid), Vector2(plank.position.x, plank.end.y)])
	var right := PackedVector2Array([Vector2(plank.end.x, plank.position.y), Vector2(plank.end.x + tip, mid), plank.end])
	c.draw_colored_polygon(left, Color("5a3a1d"))
	c.draw_colored_polygon(right, Color("4f3319"))
	wood_panel(c, plank)
	var outline := PackedVector2Array([plank.position, Vector2(plank.end.x, plank.position.y), Vector2(plank.end.x + tip, mid), plank.end,
			Vector2(plank.position.x, plank.end.y), Vector2(plank.position.x - tip, mid), plank.position])
	c.draw_polyline(outline, BRASS_DARK, 6.0, true)
	c.draw_polyline(outline, BRASS_MID, 3.5, true)
	c.draw_line(plank.position + Vector2(0, -1.0), Vector2(plank.end.x, plank.position.y - 1.0), BRASS_LIGHT, 1.0)
	c.draw_rect(plank.grow(-5.0), Color(0, 0, 0, 0.3), false, 1.0)
	for x: float in [plank.position.x - tip + 8.0, plank.end.x + tip - 8.0]:
		c.draw_circle(Vector2(x, mid), 2.6, BRASS_DARK)
		c.draw_circle(Vector2(x, mid), 1.8, BRASS_LIGHT)
	c.draw_style_box(box("plaque_edge", BRASS_DARK, 8.0, 0.0, Color.BLACK, 8.0, Color(0, 0, 0, 0.5), 4.0), plaque.grow(4.0))
	c.draw_style_box(box("plaque_brass", BRASS_MID, 7.0, 1.0, BRASS_LIGHT), plaque.grow(2.5))
	c.draw_style_box(box("plaque_face", Color("2c1c10"), 5.0, 1.0, Color("160d06")), plaque)
	c.draw_rect(Rect2(plaque.position + Vector2(3, 2), Vector2(plaque.size.x - 6.0, plaque.size.y * 0.4)), Color(1, 0.9, 0.7, 0.05))
	c.draw_rect(plaque.grow(-4.5), Color(BRASS_DARK, 0.75), false, 1.0)


## The card tray: a floating panel of planks in a brass frame with plated corners.
func tray(c: CanvasItem, rect: Rect2) -> void:
	c.draw_style_box(box("tray_shadow", Color(0, 0, 0, 0.35), 8.0, 0.0, Color.BLACK, 12.0, Color(0, 0, 0, 0.5), 5.0), rect.grow(2.0))
	wood_panel(c, rect)
	c.draw_rect(rect.grow(-7.0), Color(0, 0, 0, 0.32), false, 1.5)
	brass_frame(c, rect, 3.0)
	# Corner plates: an L of brass over each corner, pinned with a rivet.
	var arm := 24.0
	var thick := 8.0
	for corner in 4:
		var sx := 1.0 if corner % 2 == 0 else -1.0
		var sy := 1.0 if corner < 2 else -1.0
		var at := Vector2(rect.position.x - 3.0 if sx > 0.0 else rect.end.x + 3.0, rect.position.y - 3.0 if sy > 0.0 else rect.end.y + 3.0)
		var plate := PackedVector2Array([at, at + Vector2(sx * arm, 0), at + Vector2(sx * (arm - 4.0), sy * thick), at + Vector2(sx * thick, sy * thick),
				at + Vector2(sx * thick, sy * (arm - 4.0)), at + Vector2(0, sy * arm)])
		c.draw_colored_polygon(plate, BRASS_MID)
		var closed := plate.duplicate()
		closed.append(at)
		c.draw_polyline(closed, BRASS_DARK, 1.5, true)
		c.draw_line(at + Vector2(sx * 2.0, sy * 1.5), at + Vector2(sx * (arm - 3.0), sy * 1.5), BRASS_LIGHT, 1.0)
		c.draw_circle(at + Vector2(sx * 5.0, sy * 5.0), 1.8, BRASS_DARK)


## Powder: a dark trough holding one glossy gold charge per point. The charge still filling is
## shown part-way; charges a chosen card would spend are outlined; all glow when "ready".
func powder_bar(c: CanvasItem, rect: Rect2, have: float, total: int, ready: bool, throb: float, spend: int) -> void:
	c.draw_style_box(box("powder_trough", Color("100a06"), 7.0, 2.0, Color("6b4d1c"), 4.0, Color(0, 0, 0, 0.45), 2.0), rect)
	c.draw_rect(Rect2(rect.position + Vector2(4, 2.5), Vector2(rect.size.x - 8.0, 2.0)), Color(0, 0, 0, 0.5))
	var inner := rect.grow_individual(-5.0, -4.5, -5.0, -4.5)
	var gap := 4.0
	var seg := (inner.size.x - gap * (total - 1)) / total
	for i in total:
		var cell := Rect2(inner.position.x + i * (seg + gap), inner.position.y, seg, inner.size.y)
		var fill := clampf(have - i, 0.0, 1.0)
		c.draw_style_box(box("powder_empty", Color("2a1c12"), 3.0, 1.0, Color("0a0603")), cell)
		if fill > 0.0:
			var dim := 1.0 if fill >= 1.0 else 0.6
			var tone := Color(dim, dim, dim)
			var bar := Rect2(cell.position, Vector2(maxf(3.0, cell.size.x * fill), cell.size.y))
			if fill >= 1.0 and ready:
				c.draw_rect(bar.grow(1.0 + throb), Color(1.0, 0.75, 0.2, 0.1 + 0.14 * throb))
			c.draw_style_box(box("powder_full" if fill >= 1.0 else "powder_part", Color("eea516") * tone, 3.0, 1.0, Color("7a4c06") * tone), bar)
			var face := bar.grow(-1.5)
			c.draw_rect(Rect2(face.position, Vector2(face.size.x, face.size.y * 0.5)), Color(1.0, 0.86, 0.4, dim))
			c.draw_rect(Rect2(face.position + Vector2(1, 1), Vector2(maxf(0.0, face.size.x - 2.0), 2.0)), Color(1.0, 0.98, 0.82, 0.9 * dim))
			c.draw_rect(Rect2(face.position.x, face.end.y - 3.0, face.size.x, 3.0), Color(0.75, 0.45, 0.04, dim))
		if i < spend:
			c.draw_rect(cell.grow(1.5), CREAM, false, 1.5)


# --- Cards -------------------------------------------------------------------------------------

## The window of a card picture that fits a frame of the given shape: the full width, and as
## much height as that allows, taken from a little above the middle where the subject is.
func art_window(art: Texture2D, shape: Vector2) -> Rect2:
	var src_w := float(art.get_width())
	var full_h := float(art.get_height())
	var src_h := minf(full_h, src_w * shape.y / shape.x)
	return Rect2(0.0, (full_h - src_h) * 0.36, src_w, src_h)


## A card's face, drawn to fill rect: a gilt-edged parchment card with its kind lettered across
## the top, a framed picture, its name along the foot and the cost on a coin at the corner.
## halo (0..1) is the amber glow of a playable or chosen card.
func card_face(c: CanvasItem, rect: Rect2, def: Dictionary, art: Texture2D, can_pay: bool, halo: float) -> void:
	var is_order: bool = def["type"] == "order"
	if halo > 0.02:
		for ring in 3:
			c.draw_rect(rect.grow(4.0 + ring * 3.0), Color(1.0, 0.76, 0.16, halo * (0.36 - ring * 0.1)), false, 3.0)
	c.draw_style_box(box("card_edge", Color("4a300c"), 9.0), rect.grow(3.5))
	c.draw_style_box(box("card_gilt", BRASS_LIGHT, 8.0), rect.grow(2.2))
	c.draw_style_box(box("card_gilt_low", BRASS_MID, 7.0), rect.grow_individual(1.0, 0.0, 1.0, 1.2))
	var body := rect.grow(-1.5)
	c.draw_style_box(box("card_body", PARCHMENT, 5.0, 1.0, Color("8a6a2c")), body)
	c.draw_rect(Rect2(body.position + Vector2(2, 2), Vector2(body.size.x - 4.0, CARD_HEAD - 3.0)), Color(PARCHMENT_LIGHT, 0.75))
	fitted(c, Vector2(rect.position.x + rect.size.x * 0.5 + 10.0, rect.position.y + 16.0), kind_label(def), 11, BROWN_INK, rect.size.x - 32.0)
	var art_rect := Rect2(rect.position.x + 6.0, rect.position.y + CARD_HEAD, rect.size.x - 12.0, rect.size.y - CARD_HEAD - CARD_NAME)
	c.draw_rect(art_rect.grow(1.5), Color("4a3215"))
	if art != null:
		c.draw_texture_rect_region(art, art_rect, art_window(art, art_rect.size))
	else:
		# No picture yet: the card says what it is in words instead.
		c.draw_rect(art_rect, (ORDER_PURPLE if is_order else TEAM_BLUE).lightened(0.62))
		c.draw_rect(Rect2(art_rect.position, Vector2(art_rect.size.x, art_rect.size.y * 0.3)), Color(1, 1, 1, 0.18))
		var parts := String(def["name"]).split(" ")
		var line_y := art_rect.position.y + 20.0
		for part: String in parts:
			fitted(c, Vector2(art_rect.get_center().x, line_y), part, 14, INK, art_rect.size.x - 6.0)
			line_y += 15.0
		c.draw_multiline_string(font, Vector2(art_rect.position.x + 4.0, line_y + 4.0), String(def.get("field", "")), HORIZONTAL_ALIGNMENT_CENTER,
				art_rect.size.x - 8.0, 9, 3, Color(INK, 0.8))
	c.draw_rect(Rect2(art_rect.position, Vector2(art_rect.size.x, 4.0)), Color(0, 0, 0, 0.2))     # the frame's shadow on the picture
	c.draw_rect(art_rect, Color(1, 1, 1, 0.12), false, 1.0)
	var name_y := rect.end.y - CARD_NAME
	c.draw_rect(Rect2(body.position.x + 2.0, name_y + 3.0, body.size.x - 4.0, CARD_NAME - 6.5), Color(PARCHMENT_LIGHT, 0.6))
	fitted(c, Vector2(rect.position.x + rect.size.x * 0.5, name_y + 17.5), String(def["name"]), 14, BROWN_INK, rect.size.x - 10.0)
	if not can_pay:
		c.draw_style_box(box("card_dim", Color(0.07, 0.05, 0.08, 0.42), 5.0), body)
	coin(c, rect.position + Vector2(8, 9), int(def["cost"]), can_pay)


## The word across a card's head: its arm of service, or what sort of card it is.
func kind_label(def: Dictionary) -> String:
	if def["type"] == "order":
		return "ORDER"
	if def["type"] == "work":
		return "WORKS"
	return String(def.get("arm", "unit")).to_upper()


## A push button: a brass-edged plate with bold lettering. look is "gold" (the thing to press),
## "wood" (an ordinary choice), "on" (a choice that is switched on) or "off" (cannot be pressed).
func button(c: CanvasItem, rect: Rect2, label: String, look: String = "wood", size: int = 18) -> void:
	c.draw_style_box(box("btn_shadow", Color(0, 0, 0, 0.35), 9.0, 0.0, Color.BLACK, 6.0, Color(0, 0, 0, 0.45), 3.0), rect)
	c.draw_style_box(box("btn_edge", BRASS_DARK, 9.0), rect.grow(2.5))
	c.draw_style_box(box("btn_rim", BRASS_LIGHT if look != "off" else BRASS_MID, 8.0), rect.grow(1.0))
	var face := Color("5a3a1d")
	var ink := CREAM
	match look:
		"gold":
			face = Color("e8a91c")
			ink = Color("3a2206")
		"on":
			face = Color("2f6fd6")
		"off":
			face = Color("3a2a1c")
			ink = Color(CREAM, 0.4)
	c.draw_style_box(box("btn_face_" + look, face, 7.0, 1.0, face.darkened(0.45)), rect.grow(-1.0))
	c.draw_rect(Rect2(rect.position + Vector2(5, 3), Vector2(rect.size.x - 10.0, rect.size.y * 0.42)), Color(1, 1, 1, 0.13 if look != "off" else 0.04))
	c.draw_rect(Rect2(rect.position.x + 5.0, rect.end.y - 6.0, rect.size.x - 10.0, 3.0), Color(0, 0, 0, 0.18))
	var base := rect.get_center() + Vector2(0, size * 0.36)
	if look != "gold":
		fitted(c, base + Vector2(0, 1.5), label, size, Color(0, 0, 0, 0.5 if look != "off" else 0.2), rect.size.x - 12.0)
	fitted(c, base, label, size, ink, rect.size.x - 12.0)


## The small card that shows what comes next: gilt edge, parchment mat, picture.
func mini_card(c: CanvasItem, rect: Rect2, art: Texture2D, name: String) -> void:
	c.draw_style_box(box("mini_edge", Color("4a300c"), 7.0, 0.0, Color.BLACK, 5.0, Color(0, 0, 0, 0.5), 3.0), rect.grow(3.5))
	c.draw_style_box(box("mini_gilt", BRASS_LIGHT, 6.0), rect.grow(2.2))
	c.draw_style_box(box("mini_body", PARCHMENT, 4.0, 1.0, Color("8a6a2c")), rect)
	var inner := rect.grow(-4.0)
	c.draw_rect(inner.grow(1.0), Color("4a3215"))
	if art != null:
		c.draw_texture_rect_region(art, inner, art_window(art, inner.size))
	else:
		c.draw_rect(inner, TEAM_BLUE.lightened(0.62))
		var parts := name.split(" ")
		var line_y := inner.get_center().y + 3.0 - (parts.size() - 1) * 5.0
		for part: String in parts:
			fitted(c, Vector2(inner.get_center().x, line_y), part, 9, INK, inner.size.x - 2.0)
			line_y += 10.0
