extends Control
const Wire = preload("res://scripts/arena_wire.gd")
const NAMES := {"S":"SWORD","C":"CRITICAL","H":"SHIELD","G":"GOLD","E":"FOCUS","F":"GIFT"}
var faces: Array = []
var pending := false
var rolling_until := 0.0
var elapsed := 0.0
var _font: Font

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    clip_contents = true
    _font = ThemeDB.fallback_font

func _process(delta: float) -> void:
    elapsed += delta
    queue_redraw()

func set_faces(value: Variant) -> void:
    if not value is Array or value.size() != 3:
        return
    faces = value.duplicate()
    pending = false
    queue_redraw()

func start_roll() -> void:
    pending = true
    rolling_until = elapsed+0.5

func _draw() -> void:
    if _font == null or size.x <= 1:
        return
    var match_info: Dictionary = Wire.winning_dice(faces)
    var width := minf(size.x/3-14,108)
    var die := minf(width-10,size.y-29)
    var spinning := pending or elapsed < rolling_until
    for i in 3:
        var center := Vector2(size.x*(i+0.5)/3,die*0.5+6)
        var symbol: String = str(faces[i]) if faces.size() == 3 else ""
        if spinning:
            symbol = ["S","C","H","G","E","F"][(int(elapsed*18)+i*2)%6]
        var winner: bool = not spinning and (match_info.get("indices",[]) as Array).has(i)
        if winner:
            draw_arc(center,die*0.65,0,TAU,40,Color("#76f1db"),2.5,true)
        draw_set_transform(center,0.05*sin(elapsed*34+i) if spinning else 0.0)
        var half := die*0.45
        var bevel := die*0.13
        var points := PackedVector2Array([Vector2(-half,-half+bevel),Vector2(-half+bevel,-half),Vector2(half-bevel,-half),Vector2(half,-half+bevel),Vector2(half,half-bevel),Vector2(half-bevel,half),Vector2(-half+bevel,half),Vector2(-half,half-bevel)])
        draw_colored_polygon(points,Color("#ba751e"))
        var style := StyleBoxFlat.new()
        style.bg_color = Color("#edba4f")
        style.border_color = Color("#ffe09c")
        style.set_border_width_all(2)
        style.set_corner_radius_all(7)
        draw_style_box(style,Rect2(-half+4,-half+3,die*0.9-8,die*0.9-8))
        _symbol(symbol,die*0.32)
        draw_set_transform(Vector2.ZERO)
        var label: String = NAMES.get(symbol,"ROLL")
        if winner and str(match_info.tier) != "none":
            label = str(match_info.tier).to_upper()+" · "+label
        draw_string(_font,Vector2(size.x*i/3,die+22),label,HORIZONTAL_ALIGNMENT_CENTER,size.x/3,10,Color("#9be7df") if winner else Color("#d9c793"))

func _symbol(symbol: String, radius: float) -> void:
    var ink := Color("#493013")
    if symbol == "C":
        var star := PackedVector2Array()
        for i in 12:
            var angle := TAU*i/12-PI/2
            star.append(Vector2(cos(angle),sin(angle))*radius*(1.0 if i%2==0 else 0.42))
        draw_colored_polygon(star,ink)
    elif symbol == "S":
        draw_colored_polygon(PackedVector2Array([Vector2(-3,-radius*0.8),Vector2(0,-radius),Vector2(4,-radius*0.8),Vector2(3,radius*0.3),Vector2(-3,radius*0.3)]),ink)
        draw_line(Vector2(-radius*0.5,radius*0.3),Vector2(radius*0.5,radius*0.3),ink,4,true)
        draw_line(Vector2(0,radius*0.3),Vector2(0,radius*0.75),ink,5,true)
    elif symbol == "H":
        draw_colored_polygon(PackedVector2Array([Vector2(-radius*0.75,-radius*0.8),Vector2(radius*0.75,-radius*0.8),Vector2(radius*0.6,radius*0.3),Vector2(0,radius),Vector2(-radius*0.6,radius*0.3)]),ink)
    elif symbol == "G":
        draw_arc(Vector2.ZERO,radius*0.85,0,TAU,32,ink,4,true)
        draw_string(_font,Vector2(-radius,-radius*0.1+8),"G",HORIZONTAL_ALIGNMENT_CENTER,radius*2,int(radius),ink)
    elif symbol == "E":
        draw_colored_polygon(PackedVector2Array([Vector2(radius*0.1,-radius),Vector2(-radius*0.7,0),Vector2(-1,0),Vector2(-radius*0.1,radius),Vector2(radius*0.7,-2),Vector2(1,-2)]),ink)
    elif symbol == "F":
        draw_rect(Rect2(-radius*0.7,-radius*0.55,radius*1.4,radius*1.25),ink)
        draw_line(Vector2(0,-radius*0.8),Vector2(0,radius*0.7),Color("#edba4f"),4,true)
        draw_line(Vector2(-radius*0.8,-radius*0.1),Vector2(radius*0.8,-radius*0.1),Color("#edba4f"),3,true)
    else:
        draw_circle(Vector2.ZERO,3,ink)
