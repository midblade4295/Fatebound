extends Control
# Small vector ornaments keep navigation crisp at every phone resolution.
var kind := "coin"
var tint := Color("#eed19a")

func _ready() -> void:
    custom_minimum_size = Vector2(28,28)
    mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
    var s := minf(size.x,size.y)/36.0
    draw_set_transform(size*0.5,0.0,Vector2(s,s))
    var dark := Color("#603c1b")
    draw_circle(Vector2(0,1),17,Color(0.98,0.65,0.22,0.055))
    match kind:
        "coin":
            draw_circle(Vector2.ZERO,13,dark)
            draw_arc(Vector2.ZERO,12,0,TAU,32,tint,2.5,true)
            draw_arc(Vector2.ZERO,9,0,TAU,32,tint.darkened(0.18),1.3,true)
            draw_string(ThemeDB.fallback_font,Vector2(-9,7),"✦",HORIZONTAL_ALIGNMENT_CENTER,18,18,tint)
        "gem":
            var gem := PackedVector2Array([Vector2(-11,-6),Vector2(-6,-12),Vector2(7,-12),Vector2(12,-6),Vector2(0,12)])
            draw_colored_polygon(gem,Color("#5d2a7c"))
            for i in gem.size():draw_line(gem[i],gem[(i+1)%gem.size()],Color("#e8b2ff"),2,true)
            draw_line(Vector2(-11,-6),Vector2(12,-6),Color("#e8b2ff"),1.3,true)
            draw_line(Vector2(0,12),Vector2(-2,-6),Color("#d898fb"),1.3,true)
        "castle":
            draw_rect(Rect2(-11,-3,22,16),dark)
            draw_rect(Rect2(-13,-9,8,19),dark)
            draw_rect(Rect2(5,-9,8,19),dark)
            for x in [-10,0,10]:draw_rect(Rect2(x-3,-12,6,5),tint)
            draw_line(Vector2(-13,11),Vector2(13,11),tint,2,true)
            draw_line(Vector2(-11,-8),Vector2(-11,10),tint,1.6,true)
            draw_line(Vector2(11,-8),Vector2(11,10),tint,1.6,true)
            draw_rect(Rect2(-3,4,6,8),tint.darkened(0.25))
        "helm":
            draw_colored_polygon(PackedVector2Array([Vector2(-12,-4),Vector2(-9,-12),Vector2(0,-15),Vector2(9,-12),Vector2(12,-4),Vector2(8,5),Vector2(-8,5)]),dark)
            draw_arc(Vector2(0,-2),12,PI,TAU,20,tint,2,true)
            draw_line(Vector2(-11,-2),Vector2(11,-2),tint,2,true)
            draw_line(Vector2(-8,4),Vector2(8,4),tint,2,true)
            draw_line(Vector2(0,-14),Vector2(0,13),tint,2,true)
            draw_line(Vector2(-7,5),Vector2(-4,12),tint,2,true)
            draw_line(Vector2(7,5),Vector2(4,12),tint,2,true)
        "shield":
            var edge := PackedVector2Array([Vector2(0,-14),Vector2(12,-9),Vector2(10,4),Vector2(0,15),Vector2(-10,4),Vector2(-12,-9)])
            draw_colored_polygon(edge,dark)
            for i in edge.size():draw_line(edge[i],edge[(i+1)%edge.size()],tint,2,true)
            draw_line(Vector2(0,-11),Vector2(0,11),tint.darkened(0.16),1.7,true)
        "friends":
            for x in [-7,7]:
                draw_circle(Vector2(x,-6),5,dark)
                draw_arc(Vector2(x,-6),5,0,TAU,18,tint,1.7,true)
                draw_arc(Vector2(x,13),8,PI,TAU,18,tint,2,true)
        "swords":
            for sign in [-1,1]:
                draw_line(Vector2(-sign*12,-12),Vector2(sign*10,11),tint,3,true)
                draw_line(Vector2(sign*4,9),Vector2(sign*13,0),tint,2,true)
                draw_circle(Vector2(sign*12,13),2.5,tint)
        "chest":
            draw_rect(Rect2(-13,-5,26,17),dark)
            draw_arc(Vector2(0,-5),13,PI,TAU,20,tint,2,true)
            draw_rect(Rect2(-12,-4,24,16),Color("#463020"))
            draw_rect(Rect2(-12,-4,24,16),tint,false,2)
            draw_line(Vector2(-12,2),Vector2(12,2),tint,2,true)
            draw_rect(Rect2(-2,1,4,7),tint)
        "laurel":
            draw_arc(Vector2.ZERO,13,0.48,PI*0.98,18,tint,2,true)
            draw_arc(Vector2.ZERO,13,PI*1.02,TAU-0.48,18,tint,2,true)
            draw_colored_polygon(PackedVector2Array([Vector2(0,-11),Vector2(3,-3),Vector2(11,-3),Vector2(5,2),Vector2(7,11),Vector2(0,6),Vector2(-7,11),Vector2(-5,2),Vector2(-11,-3),Vector2(-3,-3)]),tint)
        "heart":
            draw_circle(Vector2(-5,-5),7,tint)
            draw_circle(Vector2(5,-5),7,tint)
            draw_colored_polygon(PackedVector2Array([Vector2(-12,-4),Vector2(12,-4),Vector2(0,14)]),tint)
        "target":
            for radius in [13.0,7.0]:draw_arc(Vector2.ZERO,radius,0,TAU,32,tint,2,true)
            draw_circle(Vector2.ZERO,2,tint)
            for a in 4:
                var v := Vector2.RIGHT.rotated(a*PI/2)
                draw_line(v*16,v*10,tint,1.7,true)
    draw_set_transform(Vector2.ZERO)
