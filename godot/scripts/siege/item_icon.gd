extends Control
# 0.31.157 5V5: an item's glyph (scripts/siege/moba.gd ITEMS), drawn, not an image -- the shop's cells and slots use this
# Control; the HUD's item slots call draw_item() on its own canvas.
const Moba = preload("res://scripts/siege/moba.gd")

const ITEM_TINT := {"sword":"#d8dee6", "ruby":"#e8304a", "dagger":"#cfd6de", "boots":"#9a6a3a", "tome":"#3a6bd0", "fang":"#f2ead8",
	"bead":"#4ad07a", "cloth":"#9aa6b2", "greaves":"#e0b040", "bloodthirster":"#e04040", "titan":"#ff8a3a", "phantom":"#9a6bff",
	"archon":"#a050ff", "thorn":"#5aa860", "relic":"#ffd65a"}
var item := ""
var dim := false

func _draw() -> void:
	if item != "":
		draw_item(self, item, size * 0.5, minf(size.x, size.y), dim)

static func draw_item(ci: CanvasItem, id: String, c: Vector2, sz: float, dim := false) -> void:
	# an item's glyph, drawn in a 32x32 space (crisp at any size); the big items on a gold disc
	var it: Dictionary = Moba.ITEMS.get(id, {})
	var tint := Color(str(ITEM_TINT.get(id, "#ffffff")))
	if dim:
		tint = tint.darkened(0.45)
	var k := sz / 32.0
	var ink := Color(0.07, 0.05, 0.03)
	var gold := Color("#d9b04a") if not dim else Color("#7a6230")
	if it.has("from"):
		ci.draw_circle(c, 15.5 * k, Color(0.16, 0.1, 0.03, 0.9))
		ci.draw_arc(c, 15.0 * k, 0, TAU, 32, gold, 1.6 * k, true)
	var rot := 0.0
	match str(it.get("icon", "")):
		"sword": rot = -PI * 0.25
		"dagger": rot = PI * 0.2
	ci.draw_set_transform(c, rot, Vector2(k, k))
	match str(it.get("icon", "")):
		"sword":
			var blade := PackedVector2Array([Vector2(0, -15), Vector2(2.6, -11), Vector2(2.6, 5), Vector2(-2.6, 5), Vector2(-2.6, -11)])
			ci.draw_colored_polygon(blade, tint)
			ci.draw_polyline(blade + PackedVector2Array([blade[0]]), ink, 1.0, true)
			ci.draw_line(Vector2(0, -11), Vector2(0, 4), tint.lightened(0.4), 1.0)
			ci.draw_rect(Rect2(-7, 5, 14, 3), gold)
			ci.draw_rect(Rect2(-1.4, 8, 2.8, 5), Color("#6a4022"))
			ci.draw_circle(Vector2(0, 14.5), 2.2, gold)
		"dagger":
			for sx in [-1.0, 1.0]:
				var b := PackedVector2Array([Vector2(0, -12), Vector2(2.4, -8), Vector2(2.4, 3), Vector2(-2.4, 3), Vector2(-2.4, -8)])
				var tf := Transform2D(sx * 0.35, Vector2(sx * 3.5, 0))
				var bb := tf * b
				ci.draw_colored_polygon(bb, tint)
				ci.draw_polyline(bb + PackedVector2Array([bb[0]]), ink, 1.0, true)
				ci.draw_colored_polygon(tf * PackedVector2Array([Vector2(-5.5, 3), Vector2(5.5, 3), Vector2(5.5, 5.4), Vector2(-5.5, 5.4)]), gold)
				ci.draw_colored_polygon(tf * PackedVector2Array([Vector2(-1.2, 5.4), Vector2(1.2, 5.4), Vector2(1.2, 10.5), Vector2(-1.2, 10.5)]), Color("#6a4022"))
		"ruby":
			var hexp := PackedVector2Array()
			var inner := PackedVector2Array()
			for i in 6:
				var a := PI / 6.0 + TAU * float(i) / 6.0
				hexp.append(Vector2(cos(a), sin(a)) * 12.5)
				inner.append(Vector2(cos(a), sin(a)) * 6.0)
			ci.draw_colored_polygon(hexp, tint)
			ci.draw_colored_polygon(inner, tint.lightened(0.3))
			ci.draw_polyline(hexp + PackedVector2Array([hexp[0]]), ink, 1.0, true)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-7, -6), Vector2(-2, -9), Vector2(-4, -3)]), Color(1, 1, 1, 0.7))
		"boots":
			var bt := PackedVector2Array([Vector2(-7, -12), Vector2(3, -12), Vector2(3, 3), Vector2(12, 6), Vector2(12, 12), Vector2(-7, 12)])
			ci.draw_colored_polygon(bt, tint)
			ci.draw_polyline(bt + PackedVector2Array([bt[0]]), ink, 1.0, true)
			ci.draw_rect(Rect2(-7, 10, 19, 2.5), tint.darkened(0.5))
			ci.draw_rect(Rect2(-8.5, -14, 13, 4), tint.lightened(0.35))
			if it.has("from"):
				ci.draw_colored_polygon(PackedVector2Array([Vector2(-8, -6), Vector2(-15, -11), Vector2(-13, -4), Vector2(-15, 0), Vector2(-8, -1)]), Color("#fff1c2"))
		"tome":
			ci.draw_rect(Rect2(-10, -13, 20, 26), tint)
			ci.draw_rect(Rect2(-10, -13, 3.5, 26), tint.darkened(0.4))
			ci.draw_rect(Rect2(7, -11, 2.5, 22), Color("#f2e6c8"))
			ci.draw_rect(Rect2(-10, -13, 20, 26), ink, false, 1.0)
			ci.draw_circle(Vector2(1, 0), 4.2, gold)
			ci.draw_circle(Vector2(1, 0), 2.0, tint.lightened(0.5))
		"fang":
			var fg := PackedVector2Array([Vector2(-7, -13), Vector2(7, -13), Vector2(5, -4), Vector2(1, 13), Vector2(-2, -4)])
			ci.draw_colored_polygon(fg, tint)
			ci.draw_polyline(fg + PackedVector2Array([fg[0]]), ink, 1.0, true)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-0.5, 5), Vector2(3, 5), Vector2(1, 13)]), Color("#d42a2a"))
		"bead":
			ci.draw_arc(Vector2(0, -12), 7.0, PI * 1.15, PI * 1.85, 10, Color("#c8b07a"), 1.4, true)
			ci.draw_circle(Vector2(0, 2), 10.0, tint)
			ci.draw_arc(Vector2(0, 2), 10.0, 0, TAU, 24, ink, 1.0, true)
			ci.draw_circle(Vector2(-3.5, -1.5), 3.0, Color(1, 1, 1, 0.6))
		"shield":
			var sh := PackedVector2Array([Vector2(-11, -13), Vector2(11, -13), Vector2(11, 0), Vector2(0, 14), Vector2(-11, 0)])
			ci.draw_colored_polygon(sh, tint)
			ci.draw_polyline(sh + PackedVector2Array([sh[0]]), ink, 1.0, true)
			ci.draw_rect(Rect2(-1.6, -11, 3.2, 21), gold)
			ci.draw_rect(Rect2(-9, -5.5, 18, 3.2), gold)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
