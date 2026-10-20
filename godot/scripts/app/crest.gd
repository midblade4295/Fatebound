extends Control
# 0.31.196 (Kevin: "Do clan chest, clan camp, crest, ..."): a clan's crest -- its emblem (Eco.CLAN_EMBLEMS) in one colour
# (CLAN_CHARGES) on a shield of another (CLAN_FIELDS), in an iron rim, or gold / silver / bronze for last week's League
# podium ("fr"). Drawn from tools/build_clan_art.py's layers in assets/ui/clans/: the field tinted, the emblem tinted, the
# rim on top. `code` is Eco.crest_code's "e.f.c" (cards, chat lines, the match's names and the boards carry it); "" draws
# nothing. Its height is ASPECT x its width; SocialUI.crest() makes one of a given height.
const Eco = preload("res://scripts/meta/economy.gd")
const DIR := "res://assets/ui/clans/"
const ASPECT := 280.0 / 256.0          # the shield's height / width
const EMBLEM_W := 0.56                 # the emblem's size, of the shield's width
const EMBLEM_Y := 0.48                 # ... its middle, down the shield
const FRAMES := ["gold", "silver", "bronze"]

static var _tex := {}

var code := ""
var frame := ""                        # "gold" / "silver" / "bronze" / "" (iron)

static func tex(name: String) -> Texture2D:
	if not _tex.has(name):
		var p := DIR + name + ".png"
		_tex[name] = load(p) if ResourceLoader.exists(p) else null
	return _tex[name]

static func colors(c: String) -> Dictionary:
	# {"e": emblem name, "field": Color, "charge": Color} ({} for no crest)
	var k := Eco.crest_of_code(c)
	if k.is_empty():
		return {}
	return {"e":str(Eco.CLAN_EMBLEMS[int(k.e)]), "field":Color(str(Eco.CLAN_FIELDS[int(k.f)])), "charge":Color(str(Eco.CLAN_CHARGES[int(k.c)]))}

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

func set_crest(c: String, fr := "") -> void:
	code = c
	frame = fr
	queue_redraw()

func _draw() -> void:
	var w := minf(size.x, size.y / ASPECT)
	var h := w * ASPECT
	draw_on(self, code, Rect2((size.x - w) * 0.5, (size.y - h) * 0.5, w, h), frame)

static func draw_on(ci: CanvasItem, code: String, r: Rect2, frame := "", alpha := 1.0) -> void:
	# the crest drawn into r on any canvas item (the match's nameplates: scripts/siege/siege_hud.gd)
	var k := colors(code)
	if k.is_empty():
		return
	var w := r.size.x
	var h := r.size.y
	var field := tex("shield_field")
	var emblem := tex("emblem_" + str(k.e))
	var rim := tex("shield_rim_" + (frame if frame in FRAMES else "iron"))
	if field == null or rim == null:
		# (no art: a plain shield shape in its colours)
		ci.draw_rect(Rect2(r.position + Vector2(w * 0.1, h * 0.08), Vector2(w * 0.8, h * 0.6)), Color(k.field, alpha))
		ci.draw_colored_polygon(PackedVector2Array([r.position + Vector2(w * 0.1, h * 0.68), r.position + Vector2(w * 0.9, h * 0.68),
			r.position + Vector2(w * 0.5, h * 0.95)]), Color(k.field, alpha))
	else:
		ci.draw_texture_rect(field, r, false, Color(k.field, alpha))
	if emblem != null:
		var es := w * EMBLEM_W
		ci.draw_texture_rect(emblem, Rect2(r.position.x + (w - es) * 0.5, r.position.y + h * EMBLEM_Y - es * 0.5, es, es), false, Color(k.charge, alpha))
	if rim != null:
		ci.draw_texture_rect(rim, r, false, Color(1, 1, 1, alpha))
