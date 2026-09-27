extends StyleBox
# Beveled brass-framed panel: soft drop shadow, a 2px brass rim lit from above, an inner dark bevel
# line, a faint inner highlight and a dark navy/charcoal body with a gentle vertical gradient.
var top := Color("#16222b")
var bottom := Color("#0b1116")
var rim_light := Color("#f0cf82")
var rim_dark := Color("#6f4f1e")
var radius := 12.0
var rim := 2.0
var glow := Color(0, 0, 0, 0)
var shadow := 0.5
var ornate := false

func _rounded(rect: Rect2, r: float) -> PackedVector2Array:
    var pts := PackedVector2Array()
    r = maxf(0.0, minf(r, minf(rect.size.x, rect.size.y) * 0.5))
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

func _fill(ci: RID, rect: Rect2, r: float, a: Color, b: Color) -> void:
    if rect.size.x < 2 or rect.size.y < 2:
        return
    var pts := _rounded(rect, r)
    var cols := PackedColorArray()
    for p in pts:
        cols.append(a.lerp(b, clampf((p.y - rect.position.y) / rect.size.y, 0, 1)))
    RenderingServer.canvas_item_add_polygon(ci, pts, cols)

func _line(ci: RID, rect: Rect2, r: float, color: Color, width: float) -> void:
    var pts := _rounded(rect, r)
    pts.append(pts[0])
    RenderingServer.canvas_item_add_polyline(ci, pts, PackedColorArray([color]), width, true)

func _draw(ci: RID, rect: Rect2) -> void:
    if glow.a > 0.0:
        for i in 3:
            var g := glow
            g.a = glow.a * (0.5 - i * 0.14)
            _line(ci, rect.grow(2.0 + i * 2.4), radius + 2.0 + i * 2.4, g, 2.4)
    if shadow > 0.0:
        _fill(ci, Rect2(rect.position + Vector2(0, 3), rect.size).grow(1.0), radius + 1.0, Color(0, 0, 0, 0.0), Color(0, 0, 0, shadow))
    # Brass rim: a filled plate lit from the top, then the body inset by the rim width.
    _fill(ci, rect, radius, rim_light, rim_dark)
    var body := rect.grow(-rim)
    _fill(ci, body, radius - rim, top, bottom)
    # Inner dark bevel and a hairline highlight just inside it.
    _line(ci, body.grow(-0.75), radius - rim - 0.75, Color(0, 0, 0, 0.55 * top.a), 1.5)
    _line(ci, body.grow(-2.2), radius - rim - 2.2, Color(1, 1, 1, 0.05), 1.0)
    # Gloss across the top of the body.
    _fill(ci, Rect2(body.position + Vector2(3, 2), Vector2(body.size.x - 6, minf(22.0, body.size.y * 0.35))), maxf(2.0, radius - rim - 2.0), Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.0))
    if ornate:
        # Small diamond studs at the four corners of a title plate.
        for c in [rect.position + Vector2(radius * 0.6, radius * 0.6), Vector2(rect.end.x - radius * 0.6, rect.position.y + radius * 0.6),
                Vector2(rect.position.x + radius * 0.6, rect.end.y - radius * 0.6), rect.end - Vector2(radius * 0.6, radius * 0.6)]:
            var d := 4.0
            RenderingServer.canvas_item_add_polygon(ci, PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0)]), PackedColorArray([rim_light]))
