extends RefCounted
## The HUD's look, in one place: palette, lettering, and the drawing routines for wood, brass,
## rounded boxes, the gold cost coin, strength bars and card faces.
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
const CARD_BAND := 24.0             # the coloured strip across a card's top, and its name strip

var font: Font
var font_bold: FontVariation
var wood: NoiseTexture2D
var _boxes: Dictionary = {}


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


## The Powder cost as an embossed gold coin.
func coin(c: CanvasItem, at: Vector2, cost: int, can_pay: bool) -> void:
	var dull := 1.0 if can_pay else 0.62
	var grey := Color(dull, dull, dull)
	c.draw_circle(at + Vector2(0, 2.5), 15.5, Color(0, 0, 0, 0.5))
	c.draw_circle(at, 15.5, Color("7a5510") * grey)
	c.draw_circle(at, 14.0, Color("f7d868") * grey)
	c.draw_circle(at, 11.5, Color("e0a626") * grey)
	c.draw_arc(at, 12.6, PI * 1.05, PI * 1.6, 12, Color(1.0, 0.97, 0.75, 0.9 * dull), 1.6)
	c.draw_arc(at, 12.6, PI * 0.05, PI * 0.6, 12, Color(0.45, 0.3, 0.05, 0.7), 1.6)
	var label := str(cost)
	text(c, at + Vector2(0, 7.5), label, 19, Color(1.0, 0.93, 0.6, dull), HORIZONTAL_ALIGNMENT_CENTER, 30.0, true)
	text(c, at + Vector2(0, 6.5), label, 19, Color("4a3206"), HORIZONTAL_ALIGNMENT_CENTER, 30.0, true)


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


# --- Cards -------------------------------------------------------------------------------------

## A card's face, drawn to fill rect: brass frame, coloured strip naming its kind, portrait,
## name plate and cost coin. halo (0..1) is the amber glow of a playable or chosen card.
func card_face(c: CanvasItem, rect: Rect2, def: Dictionary, art: Texture2D, can_pay: bool, halo: float) -> void:
	var is_order: bool = def["type"] == "order"
	if halo > 0.02:
		for ring in 3:
			c.draw_rect(rect.grow(4.0 + ring * 3.0), Color(1.0, 0.72, 0.1, halo * (0.34 - ring * 0.09)), false, 3.0)
	c.draw_style_box(box("card_edge", BRASS_DARK, 9.0), rect.grow(4.0))
	c.draw_style_box(box("card_face", BRASS_LIGHT, 8.0), rect.grow(2.5))
	c.draw_style_box(box("card_inner", BRASS_MID, 6.0, 1.0, BRASS_DARK), rect.grow(1.0))
	var inner := rect.grow(-2.0)
	var band := ORDER_PURPLE if is_order else TEAM_BLUE
	var band_rect := Rect2(inner.position, Vector2(inner.size.x, CARD_BAND - 2.0))
	c.draw_rect(band_rect, band)
	c.draw_rect(Rect2(band_rect.position, Vector2(band_rect.size.x, band_rect.size.y * 0.45)), Color(1, 1, 1, 0.14))
	c.draw_rect(Rect2(band_rect.position.x, band_rect.end.y - 2.0, band_rect.size.x, 2.0), Color(0, 0, 0, 0.3))
	var kind := "ORDER" if is_order else String(def["arm"]).to_upper()
	text(c, band_rect.position + Vector2(band_rect.size.x * 0.5 + 10.0, 16), kind, 11, CREAM, HORIZONTAL_ALIGNMENT_CENTER, band_rect.size.x - 24.0, true)
	var name_rect := Rect2(Vector2(inner.position.x, inner.end.y - CARD_BAND + 2.0), Vector2(inner.size.x, CARD_BAND - 2.0))
	var art_rect := Rect2(Vector2(inner.position.x, band_rect.end.y), Vector2(inner.size.x, name_rect.position.y - band_rect.end.y))
	if art != null:
		# The portrait is drawn from the top of the picture down, as much as the card has room for.
		var src_w := float(art.get_width())
		var src_h := minf(float(art.get_height()), src_w * art_rect.size.y / art_rect.size.x)
		c.draw_texture_rect_region(art, art_rect, Rect2(0, 0, src_w, src_h))
	else:
		c.draw_rect(art_rect, band.lightened(0.55))
		words(c, art_rect.get_center() + Vector2(0, 6), String(def["name"]), 15, INK, rect.size.x - 8.0)
	c.draw_rect(Rect2(art_rect.position, Vector2(art_rect.size.x, 5.0)), Color(0, 0, 0, 0.18))    # the frame's shadow on the picture
	c.draw_rect(name_rect, WOOD_DARK)
	c.draw_rect(Rect2(name_rect.position, Vector2(name_rect.size.x, 1.5)), BRASS_MID)
	text(c, name_rect.position + Vector2(name_rect.size.x * 0.5, 16), String(def["name"]), 13, CREAM, HORIZONTAL_ALIGNMENT_CENTER, name_rect.size.x - 4.0, true)
	if not can_pay:
		c.draw_rect(inner, Color(0.06, 0.05, 0.08, 0.4))
	coin(c, rect.position + Vector2(9, 9), int(def["cost"]), can_pay)
