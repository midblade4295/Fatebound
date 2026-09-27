extends Control
const Wire = preload("res://scripts/arena_wire.gd")
const NAMES := {"S":"SWORD","C":"CRITICAL","H":"SHIELD","G":"GOLD","E":"FOCUS","F":"GIFT"}
var faces: Array = []
var pending := false
var reduce_motion := false
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
    draw_rect(Rect2(0,0,size.x,size.y),Color(0.02,0.07,0.11,0.29))
    var match_info: Dictionary = Wire.winning_dice(faces)
    var width := minf(size.x/3-9,122)
    var die := minf(width-5,size.y-31)
    var spinning := (pending or elapsed < rolling_until) and not reduce_motion
    for i in 3:
        var center := Vector2(size.x*(i+0.5)/3,die*0.50+5)
        var symbol: String = str(faces[i]) if faces.size() == 3 else ""
        if spinning:
            symbol = ["S","C","H","G","E","F"][(int(elapsed*18)+i*2)%6]
        var winner: bool = not spinning and (match_info.get("indices",[]) as Array).has(i)
        if winner:
            draw_circle(center,die*0.52,Color(0.21,0.94,0.89,0.20))
            draw_arc(center,die*0.55,0,TAU,48,Color("#8dfbee"),2.4,true)
        draw_set_transform(center+Vector2(1,die*0.38),0.0,Vector2(1,0.25))
        draw_circle(Vector2.ZERO,die*0.43,Color(0,0,0,0.40))
        draw_set_transform(center,0.05*sin(elapsed*34+i) if spinning else 0.0)
        var r := die*0.47
        var outer := PackedVector2Array()
        var lower := PackedVector2Array()
        for corner in 10:
            var a := TAU*corner/10-PI*0.5
            outer.append(Vector2(cos(a)*r,sin(a)*r*0.91))
            lower.append(Vector2(cos(a)*r,sin(a)*r*0.91+die*0.10))
        draw_colored_polygon(lower,Color("#6f3919"))
        draw_colored_polygon(outer,Color("#ad651e"))
        for facet in 10:
            var next := (facet+1)%10
            draw_colored_polygon(PackedVector2Array([Vector2.ZERO,outer[facet],outer[next]]),Color("#eab448") if facet%2==0 else Color("#d88f2d"))
            draw_line(outer[facet],outer[next],Color("#ffe5a2"),1.6,true)
        var face := PackedVector2Array()
        for corner in 8:
            var a := TAU*corner/8-PI*0.5
            face.append(Vector2(cos(a)*r*0.70,sin(a)*r*0.65))
        draw_colored_polygon(face,Color("#f5c95c") if not symbol.is_empty() else Color("#bf8e42"))
        for corner in 8:
            draw_line(face[corner],face[(corner+1)%8],Color("#ffe8a0"),1.8,true)
        draw_line(Vector2(-r*0.43,-r*0.43),Vector2(r*0.07,-r*0.58),Color(1,1,0.84,0.38),2,true)
        if not symbol.is_empty():
            _symbol(symbol,die*0.22)
        draw_set_transform(Vector2.ZERO)
        var label: String = NAMES.get(symbol,"READY")
        if winner and str(match_info.tier) != "none":
            label = str(match_info.tier).to_upper()+" · "+label
        draw_string(_font,Vector2(size.x*i/3,die+24),label,HORIZONTAL_ALIGNMENT_CENTER,size.x/3,10,Color("#affaf1") if winner else Color("#f0d59a"))

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
