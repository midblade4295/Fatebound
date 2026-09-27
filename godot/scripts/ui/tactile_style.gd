extends StyleBox
# A dimensional button face: drop shadow, darker "lip" for physical depth, a vertical gradient body,
# a glossy top highlight and a bright rim. The pressed state sinks the body into its lip.
var top := Color("#244354")
var bottom := Color("#122836")
var lip := Color("#07131b")
var rim := Color("#b8904f")
var glow := Color(0, 0, 0, 0)
var radius := 12.0
var depth := 4.0
var pressed := false
var gloss := 0.22

func _rounded(rect: Rect2, r: float) -> PackedVector2Array:
    var pts := PackedVector2Array()
    r = minf(r, minf(rect.size.x, rect.size.y) * 0.5)
    var corners := [
        [rect.position + Vector2(rect.size.x - r, r), -PI * 0.5],
        [rect.position + Vector2(rect.size.x - r, rect.size.y - r), 0.0],
        [rect.position + Vector2(r, rect.size.y - r), PI * 0.5],
        [rect.position + Vector2(r, r), PI],
    ]
    for c in corners:
        for k in 7:
            var a: float = float(c[1]) + k * (PI * 0.5) / 6.0
            pts.append(c[0] + Vector2(cos(a), sin(a)) * r)
    return pts

func _fill(ci: RID, rect: Rect2, r: float, c_top: Color, c_bottom: Color) -> void:
    if rect.size.x < 2 or rect.size.y < 2:
        return
    var pts := _rounded(rect, r)
    var cols := PackedColorArray()
    for p in pts:
        var t := clampf((p.y - rect.position.y) / rect.size.y, 0, 1)
        cols.append(c_top.lerp(c_bottom, t))
    RenderingServer.canvas_item_add_polygon(ci, pts, cols)

func _outline(ci: RID, rect: Rect2, r: float, color: Color, width: float) -> void:
    var pts := _rounded(rect, r)
    pts.append(pts[0])
    RenderingServer.canvas_item_add_polyline(ci, pts, PackedColorArray([color]), width, true)

func _draw(ci: RID, rect: Rect2) -> void:
    var sink := depth - 1.0 if pressed else 0.0
    var body := Rect2(rect.position + Vector2(0, sink), Vector2(rect.size.x, rect.size.y - depth))
    # Outer glow for primary/active controls.
    if glow.a > 0.0:
        for i in 3:
            var g := glow
            g.a = glow.a * (0.45 - i * 0.13)
            _outline(ci, rect.grow(2.0 + i * 2.2), radius + 2.0 + i * 2.2, g, 2.2)
    # Contact shadow and the physical lip under the face.
    _fill(ci, Rect2(rect.position + Vector2(1, 3), rect.size), radius, Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.42))
    _fill(ci, Rect2(rect.position + Vector2(0, depth), Vector2(rect.size.x, rect.size.y - depth)), radius, lip.lightened(0.08), lip)
    # Gradient face.
    _fill(ci, body, radius, top, bottom)
    # Gloss: a soft band across the upper half.
    var shine := Rect2(body.position + Vector2(3, 2), Vector2(body.size.x - 6, body.size.y * 0.46))
    _fill(ci, shine, maxf(2.0, radius - 3.0), Color(1, 1, 1, gloss), Color(1, 1, 1, 0.0))
    # Crisp rim plus an inner bevel line.
    _outline(ci, body, radius, rim, 1.6)
    var inner := body.grow(-2.0)
    _outline(ci, inner, maxf(2.0, radius - 2.0), Color(1, 1, 1, 0.10 if not pressed else 0.04), 1.0)
