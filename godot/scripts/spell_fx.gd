class_name FateboundSpellFX
extends Control

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func play_spell(spell: String, friendly := true) -> void:
    match spell:
        "barrage":
            for i in 3:
                _falling_bolt(i, friendly)
        "bulwark":
            _pulse("◯", Color("#63e8ff"), 86.0)
            _pulse("◯", Color("#a6f5ff"), 62.0, 0.12)
        "horn":
            _pulse("◉", Color("#ffd36a"), 92.0)
            _pulse("◎", Color("#ffefad"), 68.0, 0.13)
        "surge":
            for i in 4:
                _spark(i, friendly)
        _:
            _pulse("✦", Color("#d09cff"), 64.0)

func _label(text: String, color: Color, size: int) -> Label:
    var node := Label.new()
    node.text = text
    node.add_theme_font_size_override("font_size",size)
    node.add_theme_color_override("font_color",color)
    node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    node.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(node)
    return node

func _falling_bolt(index: int, friendly: bool) -> void:
    var c := Color("#6eeaff") if friendly else Color("#ff7a54")
    var node := _label("✦",c,38)
    var x := size.x * (0.36 + index * 0.14)
    node.position = Vector2(x,-35.0-index*12.0)
    node.size = Vector2(48,48)
    node.rotation = -0.35
    var target := Vector2(x + (index-1)*18.0,size.y*0.48)
    var tween := create_tween()
    tween.set_parallel(true)
    tween.tween_property(node,"position",target,0.34).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
    tween.tween_property(node,"modulate:a",0.0,0.18).set_delay(0.28)
    tween.chain().tween_callback(node.queue_free)

func _pulse(symbol: String, color: Color, diameter: float, delay := 0.0) -> void:
    var node := _label(symbol,color,int(diameter))
    node.pivot_offset = Vector2(diameter,diameter) * 0.5
    node.size = Vector2(diameter,diameter)
    node.position = size * 0.5 - node.size * 0.5
    node.scale = Vector2(0.25,0.25)
    node.modulate.a = 0.0
    var tween := create_tween().set_parallel(true)
    tween.tween_property(node,"scale",Vector2(1.35,1.35),0.55).set_delay(delay).set_trans(Tween.TRANS_QUAD)
    tween.tween_property(node,"modulate:a",0.9,0.12).set_delay(delay)
    tween.tween_property(node,"modulate:a",0.0,0.28).set_delay(delay+0.32)
    tween.chain().tween_callback(node.queue_free)

func _spark(index: int, friendly: bool) -> void:
    var c := Color("#bf7cff") if friendly else Color("#ff7895")
    var node := _label("✦",c,30)
    var angle := TAU * float(index) / 4.0
    var center := size * 0.5
    node.size = Vector2(36,36)
    node.position = center - node.size*0.5
    var target := center + Vector2(cos(angle),sin(angle))*110.0 - node.size*0.5
    var tween := create_tween().set_parallel(true)
    tween.tween_property(node,"position",target,0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    tween.tween_property(node,"rotation",angle+1.5,0.5)
    tween.tween_property(node,"modulate:a",0.0,0.22).set_delay(0.3)
    tween.chain().tween_callback(node.queue_free)
