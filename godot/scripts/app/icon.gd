extends Control
# Crisp procedural icons (no image assets): currencies, tabs, classes and item types.
# Drawn in a 32x32 design space scaled to the control.
var kind := "coin"
var tint := Color.WHITE

func _ready() -> void:
	resized.connect(queue_redraw)

func _draw() -> void:
	var s := minf(size.x, size.y) / 32.0
	draw_set_transform(size * 0.5, 0.0, Vector2(s, s))
	var w := tint
	match kind:
		"coin":
			draw_circle(Vector2.ZERO, 14, Color("#8a5a0c"))
			draw_circle(Vector2(0, -1), 13, Color("#ffcf4a"))
			draw_arc(Vector2(0, -1), 9.5, 0, TAU, 32, Color("#e0a226"), 2.5, true)
			draw_rect(Rect2(-2, -7, 4, 12), Color("#e0a226"))
			draw_arc(Vector2(-4, -6), 5, PI * 1.1, PI * 1.6, 8, Color(1, 1, 1, 0.8), 2, true)
		"gem":
			var top := PackedVector2Array([Vector2(-13, -4), Vector2(-7, -12), Vector2(7, -12), Vector2(13, -4)])
			var body := PackedVector2Array([Vector2(-13, -4), Vector2(13, -4), Vector2(0, 14)])
			draw_colored_polygon(top, Color("#b9f3ff"))
			draw_colored_polygon(body, Color("#3fb8e8"))
			draw_colored_polygon(PackedVector2Array([Vector2(-5, -4), Vector2(5, -4), Vector2(0, 14)]), Color("#7fdcff"))
			draw_polyline(PackedVector2Array([Vector2(-13, -4), Vector2(-7, -12), Vector2(7, -12), Vector2(13, -4), Vector2(0, 14), Vector2(-13, -4)]), Color("#0f4a73"), 1.5, true)
		"xp", "star":
			var pts := PackedVector2Array()
			for i in 10:
				var r := 14.0 if i % 2 == 0 else 6.0
				var a := -PI / 2 + i * PI / 5
				pts.append(Vector2(cos(a), sin(a)) * r)
			draw_colored_polygon(pts, w if kind == "star" else Color("#7fe0ff"))
		"home":
			draw_rect(Rect2(-12, -2, 24, 14), w)
			for x in [-12, -4, 4]:
				draw_rect(Rect2(x, -6, 5, 4), w)
			draw_rect(Rect2(-4, -13, 8, 11), w)
			draw_rect(Rect2(-2.5, 4, 5, 8), Color(0, 0, 0, 0.55))
		"pass":
			draw_colored_polygon(PackedVector2Array([Vector2(-10, -13), Vector2(10, -13), Vector2(10, 13), Vector2(0, 7), Vector2(-10, 13)]), w)
			var sp := PackedVector2Array()
			for i in 10:
				var r := 6.0 if i % 2 == 0 else 2.6
				var a := -PI / 2 + i * PI / 5
				sp.append(Vector2(cos(a), sin(a)) * r + Vector2(0, -3))
			draw_colored_polygon(sp, Color(0, 0, 0, 0.55))
		"shop":
			draw_arc(Vector2(0, -6), 6, PI, TAU, 16, w, 2.5, true)
			draw_colored_polygon(PackedVector2Array([Vector2(-12, -5), Vector2(12, -5), Vector2(10, 13), Vector2(-10, 13)]), w)
			draw_circle(Vector2(0, 3), 2.2, Color(0, 0, 0, 0.55))
		"locker":
			# knight helm
			draw_colored_polygon(PackedVector2Array([Vector2(-11, 12), Vector2(-11, -3), Vector2(-7, -11), Vector2(7, -11), Vector2(11, -3), Vector2(11, 12)]), w)
			draw_rect(Rect2(-9, -2, 18, 3), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(-1.2, 1, 2.4, 10), Color(0, 0, 0, 0.45))
		"gear":
			for i in 8:
				var a := i * TAU / 8
				draw_set_transform(size * 0.5, a, Vector2(s, s))
				draw_rect(Rect2(-3, -15, 6, 6), w)
			draw_set_transform(size * 0.5, 0.0, Vector2(s, s))
			draw_circle(Vector2.ZERO, 10, w)
			draw_circle(Vector2.ZERO, 4.5, Color(0, 0, 0, 0.6))
		"play":
			draw_colored_polygon(PackedVector2Array([Vector2(-8, -12), Vector2(12, 0), Vector2(-8, 12)]), w)
		"lock":
			draw_arc(Vector2(0, -3), 7, PI, TAU, 16, w, 3, true)
			draw_line(Vector2(-7, -3), Vector2(-7, 1), w, 3)
			draw_line(Vector2(7, -3), Vector2(7, 1), w, 3)
			draw_rect(Rect2(-10, 0, 20, 13), w)
			draw_circle(Vector2(0, 6), 2.2, Color(0, 0, 0, 0.6))
		"check":
			draw_polyline(PackedVector2Array([Vector2(-11, 1), Vector2(-3, 9), Vector2(12, -8)]), w, 4.5, true)
		"crown":
			draw_colored_polygon(PackedVector2Array([Vector2(-13, 10), Vector2(-13, -8), Vector2(-6, 0), Vector2(0, -11), Vector2(6, 0), Vector2(13, -8), Vector2(13, 10)]), w)
		"clock":
			draw_arc(Vector2.ZERO, 12, 0, TAU, 28, w, 3, true)
			draw_line(Vector2.ZERO, Vector2(0, -7), w, 2.5)
			draw_line(Vector2.ZERO, Vector2(5, 3), w, 2.5)
		"skin":
			draw_colored_polygon(PackedVector2Array([Vector2(-6, -12), Vector2(6, -12), Vector2(13, -6), Vector2(9, -1), Vector2(7, -3), Vector2(7, 13), Vector2(-7, 13), Vector2(-7, -3), Vector2(-9, -1), Vector2(-13, -6)]), w)
		"weapon", "knight":
			draw_set_transform(size * 0.5, PI / 4, Vector2(s, s))
			draw_rect(Rect2(-2, -14, 4, 20), w)
			draw_rect(Rect2(-7, 5, 14, 3), w)
			draw_rect(Rect2(-1.5, 8, 3, 6), w.darkened(0.3))
			draw_set_transform(size * 0.5, 0.0, Vector2(s, s))
		"barbarian":
			draw_line(Vector2(-8, 13), Vector2(6, -9), w.darkened(0.3), 3)
			draw_colored_polygon(PackedVector2Array([Vector2(1, -13), Vector2(13, -8), Vector2(9, 3), Vector2(3, -3)]), w)
		"rogue":
			draw_colored_polygon(PackedVector2Array([Vector2(0, -14), Vector2(4, 2), Vector2(-4, 2)]), w)
			draw_rect(Rect2(-7, 2, 14, 3), w)
			draw_rect(Rect2(-1.5, 5, 3, 8), w.darkened(0.3))
		"ranger":
			draw_arc(Vector2(-4, 0), 13, -PI / 2.6, PI / 2.6, 16, w, 3, true)
			draw_line(Vector2(0.5, -12), Vector2(0.5, 12), w.darkened(0.2), 1.2)
			draw_line(Vector2(-10, 0), Vector2(12, 0), w, 2)
			draw_colored_polygon(PackedVector2Array([Vector2(14, 0), Vector2(9, -3), Vector2(9, 3)]), w)
		"mage":
			draw_line(Vector2(-6, 13), Vector2(4, -6), w.darkened(0.25), 3)
			draw_circle(Vector2(6, -9), 5, w)
			draw_circle(Vector2(6, -9), 2.2, Color(1, 1, 1, 0.8))
		"worker":
			draw_line(Vector2(-9, 12), Vector2(6, -3), w.darkened(0.3), 3)
			draw_colored_polygon(PackedVector2Array([Vector2(0, -8), Vector2(10, -13), Vector2(13, -4), Vector2(6, -1)]), w)
		"title":
			draw_rect(Rect2(-10, -9, 20, 18), w)
			draw_circle(Vector2(-10, -9), 3, w.darkened(0.2))
			draw_circle(Vector2(10, 9), 3, w.darkened(0.2))
			for y in [-4, 0, 4]:
				draw_line(Vector2(-6, y), Vector2(6, y), Color(0, 0, 0, 0.5), 1.5)
		"plus":
			draw_rect(Rect2(-2, -9, 4, 18), w)
			draw_rect(Rect2(-9, -2, 18, 4), w)
		"chest":                                         # 0.31.37: a chest -- lid, body, band and lock, in the tint
			var body := tint if tint != Color.WHITE else Color("#c48a4a")
			draw_rect(Rect2(-13, -2, 26, 13), body.darkened(0.15))
			draw_colored_polygon(PackedVector2Array([Vector2(-13, -2), Vector2(-13, -7), Vector2(-9, -12), Vector2(9, -12), Vector2(13, -7), Vector2(13, -2)]), body)
			draw_rect(Rect2(-13, -3, 26, 2), Color(0.15, 0.1, 0.06))
			draw_rect(Rect2(-9, -12, 3, 23), Color(0.2, 0.14, 0.08, 0.6))
			draw_rect(Rect2(6, -12, 3, 23), Color(0.2, 0.14, 0.08, 0.6))
			draw_rect(Rect2(-3, -5, 6, 7), Color("#ffd75e"))
			draw_rect(Rect2(-1, -2, 2, 3), Color(0.15, 0.1, 0.06))
		"trophy":
			draw_colored_polygon(PackedVector2Array([Vector2(-9, -12), Vector2(9, -12), Vector2(7, -2), Vector2(0, 3), Vector2(-7, -2)]), w)
			draw_rect(Rect2(-2, 3, 4, 5), w)
			draw_rect(Rect2(-7, 8, 14, 4), w)
		_:
			draw_circle(Vector2.ZERO, 10, w)
