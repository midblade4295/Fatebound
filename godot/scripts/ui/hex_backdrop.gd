extends Control

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    resized.connect(queue_redraw)

func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO,size),Color("#06131b"))
    var radius := 25.0
    var row_step := radius*1.5
    var col_step := radius*1.73
    var rows := int(ceil(size.y/row_step))+2
    var columns := int(ceil(size.x/col_step))+2
    for row in rows:
        for col in columns:
            var center := Vector2(col*col_step+(col_step*0.5 if row%2 else 0),row*row_step)
            var outline := PackedVector2Array()
            for corner in 7:
                var angle := TAU*corner/6-PI/6
                outline.append(center+Vector2(cos(angle),sin(angle))*radius)
            draw_polyline(outline,Color(0.75,0.68,0.46,0.042),1.0,true)
    for i in 12:
        var rect := Rect2(0,0,size.x,size.y*0.30+i*15)
        draw_rect(rect,Color(0.18,0.34,0.38,0.0025))
