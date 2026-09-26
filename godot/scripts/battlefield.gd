extends Control
# Native CanvasItem rendering of the exact baked v114 art; no combat rules here.
const CELL := Vector2(340,280)
const CLIPS := {"idle":6,"attack":8,"big":8,"hit":3,"death":1}
var snapshot: Dictionary = {}
var player_id := ""
var preview := false
var preview_char := 0
var preview_weapon := 0
var pan := 0.0
var _drag := false
var _textures: Dictionary = {}
var _used: Dictionary = {}
var _animations: Dictionary = {}
var _effects: Array = []
var _positions: Dictionary = {}
var _old_hp: Dictionary = {}
var _last_tower := -1
var animation_time := 0.0
var _phase := 0.0
var _font: Font

func _ready() -> void:
    clip_contents = true
    mouse_filter = Control.MOUSE_FILTER_STOP
    texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    _font = ThemeDB.fallback_font

func _process(delta: float) -> void:
    animation_time += delta
    _phase += delta
    for i in range(_effects.size()-1,-1,-1):
        if animation_time - float(_effects[i].at) > 0.95:
            _effects.remove_at(i)
    # Visual animation runs at 30Hz independently of authoritative network timing.
    if _phase >= 1.0/30.0:
        _phase = 0.0
        queue_redraw()

func texture(key: String) -> Texture2D:
    _used[key] = Time.get_ticks_msec()
    if _textures.has(key):
        return _textures[key]
    var path := "res://assets/art/" + key
    if not ResourceLoader.exists(path):
        return null
    var value: Texture2D = load(path)
    _textures[key] = value
    if _textures.size() > 48:
        var oldest := key
        for k in _textures:
            if k != key and int(_used.get(k,0)) < int(_used.get(oldest,0)):
                oldest = k
        _textures.erase(oldest)
        _used.erase(oldest)
    return value

func accept_state(data: Dictionary, who: String) -> void:
    snapshot = data
    player_id = who
    var me := _me()
    var ti := int(me.get("tower",0))
    if ti != _last_tower:
        pan = 0.0
        _animations.clear()
        _effects.clear()
        _old_hp.clear()
        _last_tower = ti
    for hero in data.get("heroes",[]):
        var hid := str(hero.get("id",""))
        var hp := int(hero.get("hp",0))
        if _old_hp.has(hid) and hp > 0 and hp < int(_old_hp[hid]):
            _animations[hid] = {"clip":"hit","at":animation_time,"duration":0.38}
        _old_hp[hid] = hp
    queue_redraw()

func _me() -> Dictionary:
    for hero in snapshot.get("heroes",[]):
        if str(hero.get("id","")) == player_id:
            return hero
    return {}

func _roster(side: int) -> Array:
    var heroes: Array = []
    var tower := int(_me().get("tower",0))
    for hero in snapshot.get("heroes",[]):
        if int(hero.get("tower",-1)) == tower and int(hero.get("side",-1)) == side:
            heroes.append(hero)
    return heroes

func _max_rows() -> int:
    return 1 if size.y < 300 else (2 if size.y < 420 else 3)

func _pan_limit() -> float:
    var a := _roster(int(_me().get("side",0))).size()
    var b := _roster(1-int(_me().get("side",0))).size()
    return maxf(0.0,ceil(float(maxi(a,b))/_max_rows())*150.0-size.x*0.38)

func _gui_input(event: InputEvent) -> void:
    if event is InputEventScreenDrag:
        pan = clampf(pan-event.relative.x,-_pan_limit(),_pan_limit())
        accept_event()
    elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        _drag = event.pressed
    elif event is InputEventMouseMotion and _drag:
        pan = clampf(pan-event.relative.x,-_pan_limit(),_pan_limit())
        accept_event()

func confirm_event(event: Dictionary) -> void:
    if snapshot.is_empty() or int(event.get("tower",_last_tower)) != _last_tower:
        return
    var typ := str(event.get("type",""))
    var actor := str(event.get("actor",""))
    if typ == "roll" and (int(event.get("dealt",0)) > 0 or int(event.get("absorbed",0)) > 0):
        _animations[actor] = {"clip":"big" if event.get("tier","") == "triple" else "attack","at":animation_time,"duration":0.65}
    if typ in ["spell","rally","ultimate","ko"]:
        if _effects.size() >= 8:
            _effects.pop_front()
        _effects.append({"kind":str(event.get("spell",typ)),"at":animation_time,"actor":actor})

func _panel(rect: Rect2, color: Color, border: Color, radius := 8) -> void:
    var style := StyleBoxFlat.new()
    style.bg_color = color
    style.border_color = border
    style.set_border_width_all(1)
    style.set_corner_radius_all(radius)
    draw_style_box(style,rect)

func _text(text: String, rect: Rect2, font_size: int, color: Color) -> void:
    draw_string(_font,Vector2(rect.position.x,rect.position.y+font_size),text,HORIZONTAL_ALIGNMENT_CENTER,rect.size.x,font_size,color)

func _draw() -> void:
    if _font == null or size.x < 1 or size.y < 1:
        return
    draw_rect(Rect2(Vector2.ZERO,size),Color("#294838"))
    var bg := texture("map.jpeg" if preview else "pano.jpeg")
    if bg != null:
        var scale_factor := maxf(size.x/bg.get_width(),size.y/bg.get_height())
        var extent := bg.get_size()*scale_factor
        draw_texture_rect(bg,Rect2(Vector2((size.x-extent.x)*0.5-pan,0),extent),false)
    _positions.clear()
    if preview:
        _actor({"id":"preview","name":"","char":preview_char,"weapon":preview_weapon,"hp":1,"maxHp":1,"shieldSlots":[]},Vector2(size.x*0.5,size.y*0.95),minf(size.y*1.4,360.0),false,true)
        return
    if snapshot.is_empty():
        return
    var side := int(_me().get("side",0))
    var ti := int(_me().get("tower",0))
    var towers: Array = snapshot.get("towers",[])
    if towers.size() != 10:
        return
    var tower: Dictionary = towers[ti]
    var dmg: Array = tower.get("dmg",[0,0])
    var lead := int(tower.get("prev",-1))
    if float(dmg[0]) != float(dmg[1]):
        lead = 0 if float(dmg[0]) > float(dmg[1]) else 1
    var tower_image := texture("scaffold.png" if lead < 0 else ("towerB.png" if lead == side else "towerR.png"))
    if tower_image != null:
        var h := clampf(size.y*0.25,65,125)
        var w := h*tower_image.get_width()/tower_image.get_height()
        draw_texture_rect(tower_image,Rect2(Vector2(size.x*0.5-w*0.5-pan,size.y*0.12),Vector2(w,h)),false)
    _panel(Rect2(size.x*0.5-43,5,86,25),Color("#0b1a24ed"),Color("#a78a4a"))
    _text("TOWER "+str(tower.get("name",ti+1)),Rect2(size.x*0.5-43,8,86,23),12,Color("#ffdc89"))
    for team in 2:
        var team_side: int = side if team == 0 else 1-side
        var roster := _roster(team_side)
        var n := roster.size()
        _garrison(roster,team)
        var row_count := mini(_max_rows(),maxi(1,n))
        var top := maxf(size.y*0.42,110)
        var bottom := size.y-46
        var spacing := (bottom-top)/maxi(1,row_count-1)
        for i in n:
            var row := i%_max_rows()
            var col := i/_max_rows()
            var x := size.x*0.5 + (-1 if team == 0 else 1)*(size.x*0.235+col*140)-pan
            var y := top if row_count > 1 else size.y*0.72
            if row_count > 1:
                y += spacing*row
            var cell_h := minf(170.0,maxf(68.0,spacing*0.95)) if row_count > 1 else minf(205.0,size.y*0.50)
            _actor(roster[i],Vector2(x,y),cell_h,team == 1)
    if _pan_limit() > 1:
        _text("Drag battlefield to see more fighters",Rect2(0,size.y-19,size.x,16),10,Color("#ffffff"))
    _draw_effects()

func _garrison(heroes: Array, team: int) -> void:
    var hp := 0
    var total := 0
    var up := 0
    for hero in heroes:
        hp += int(hero.get("hp",0))
        total += int(hero.get("maxHp",0))
        if int(hero.get("hp",0)) > 0:
            up += 1
    var w := minf(size.x*0.32,146)
    var x := 7.0 if team == 0 else size.x-w-7
    var col := Color("#69e4f4") if team == 0 else Color("#ff9867")
    _panel(Rect2(x,36,w,44),Color("#081b25e8"),col.darkened(0.45))
    _text("YOUR GARRISON" if team == 0 else "ENEMY GARRISON",Rect2(x,39,w,12),9,col)
    _text("%d / %d" % [hp,total],Rect2(x,52,w,13),11,Color.WHITE)
    draw_rect(Rect2(x+8,69,w-16,4),Color("#14232b"))
    if total > 0:
        draw_rect(Rect2(x+8,69,(w-16)*float(hp)/total,4),col)

func _actor(hero: Dictionary, foot: Vector2, height: float, enemy: bool, hide_label := false) -> void:
    var hid := str(hero.get("id",""))
    var dead := int(hero.get("hp",0)) <= 0
    var row := clampi(int(hero.get("char",0)),0,4)*9+clampi(int(hero.get("weapon",0)),0,8)
    var clip := "death" if dead else "idle"
    var frame := int(animation_time/0.15 + absi(hid.hash())%6)%6
    if int(hero.get("weapon",0)) == 8:
        frame = 0
    if dead:
        frame = 0
    elif _animations.has(hid):
        var ani: Dictionary = _animations[hid]
        var age := animation_time-float(ani.at)
        if age < float(ani.duration):
            clip = str(ani.clip)
            frame = mini(int(CLIPS[clip])-1,int(age/float(ani.duration)*int(CLIPS[clip])))
        else:
            _animations.erase(hid)
    var tex := texture("hero_%02d_%s.webp" % [row,clip])
    if tex == null:
        return
    var width := height*CELL.x/CELL.y
    _positions[hid] = foot
    draw_set_transform(foot,0.0,Vector2(1,0.25))
    draw_circle(Vector2.ZERO,width*0.22,Color(0,0,0,0.25))
    draw_set_transform(foot,0.0,Vector2(-1 if enemy else 1,1))
    var tint := Color(1,1,1,0.50) if dead else Color.WHITE
    draw_texture_rect_region(tex,Rect2(-width*0.5,-height+height*0.12,width,height),Rect2(frame*340,0,340,280),tint)
    draw_set_transform(Vector2.ZERO)
    if not dead and not (hero.get("shieldSlots",[]) as Array).is_empty():
        draw_arc(foot+Vector2(0,-height*0.38),height*0.37,PI*0.93,TAU+0.3,28,Color(0.5,0.9,1,0.55),2,true)
    if hide_label:
        return
    var col := Color("#ff9367") if enemy else Color("#73ddeb")
    if hid == player_id:
        col = Color("#ffe198")
    var plate := Rect2(foot.x-53,foot.y+4,106,30)
    _panel(plate,Color("#061b22e8"),col.darkened(0.30),5)
    var title := "YOU" if hid == player_id else str(hero.get("name","Hero")).left(14)
    _text(title,Rect2(plate.position+Vector2(0,1),Vector2(106,12)),10,col)
    if dead:
        var remain := maxi(0,int(ceil((float(hero.get("downUntil",0))-float(snapshot.get("now",0)))/1000.0)))
        _text("KO %ds" % remain if remain > 0 else "Awaiting respawn",Rect2(plate.position+Vector2(0,14),Vector2(106,11)),9,Color("#ddd8c9"))
    else:
        draw_rect(Rect2(plate.position+Vector2(6,20),Vector2(94,4)),Color("#122b24"))
        var ratio := clampf(float(hero.get("hp",0))/maxf(1,float(hero.get("maxHp",1))),0,1)
        draw_rect(Rect2(plate.position+Vector2(6,20),Vector2(94*ratio,4)),Color("#9ddc65") if ratio > 0.3 else Color("#ff755a"))

func _draw_effects() -> void:
    for fx in _effects:
        var t := clampf((animation_time-float(fx.at))/0.95,0,1)
        var actor: Vector2 = _positions.get(str(fx.actor),size*0.5)
        var center := Vector2(size.x*0.5,size.y*0.6)
        var kind := str(fx.kind)
        var color := Color("#b9edff")
        if kind in ["horn","rally"]:
            color = Color("#ffdf7c")
        elif kind in ["surge","ultimate"]:
            color = Color("#c593ff")
        color.a = (1-t)*0.85
        if kind == "barrage":
            for i in 3:
                var end := center+Vector2((i-1)*50,20)
                var point := (end+Vector2(-30,-200)).lerp(end,minf(1,t*2.5))
                draw_line(point-Vector2(16,55),point,color,4,true)
                draw_circle(point,5,color)
                if t > 0.4:
                    draw_arc(end,(t-0.4)*120,0,TAU,32,color,3,true)
        else:
            var origin := actor-Vector2(0,40) if kind == "bulwark" else center
            for i in 3:
                draw_arc(origin,20+t*95+i*12,0,TAU,48,color,2,true)
            if kind in ["surge","ultimate"]:
                for i in 8:
                    var angle := TAU*i/8+t*2
                    var dir := Vector2(cos(angle),sin(angle))
                    draw_line(origin+dir*(20+t*70),origin+dir*(34+t*90),color,3,true)
