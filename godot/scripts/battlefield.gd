extends Control
# Native CanvasItem presentation. Gameplay remains server-authoritative.
const CELL := Vector2(340,280)
const CLIPS := {"idle":6,"attack":8,"big":8,"hit":3,"death":1}
const HERO_ART := ["hero_knight.webp","hero_rogue.webp","hero_barbarian.webp","hero_mage.webp","hero_ranger.webp"]
var snapshot: Dictionary = {}
var player_id := ""
var preview := false
var front_portrait := false
var reduce_motion := false
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
    var folder := "res://assets/premium/" if key in HERO_ART or key in ["hero_stage.webp","battle_arena.webp"] else ("res://assets/portraits/" if key.begins_with("portrait_") else "res://assets/art/")
    var path := folder + key
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
    if typ in ["spell","rally","ultimate","ko"] and not reduce_motion:
        if _effects.size() >= 8:
            _effects.pop_front()
        _effects.append({"kind":str(event.get("spell",typ)),"at":animation_time,"actor":actor})

func _panel(rect: Rect2, color: Color, border: Color, radius := 8) -> void:
    var style := StyleBoxFlat.new()
    style.bg_color = color
    style.border_color = border
    style.set_border_width_all(1)
    style.border_width_top = 2
    style.set_corner_radius_all(radius)
    style.shadow_color = Color(0,0,0,0.33)
    style.shadow_size = 3
    draw_style_box(style,rect)

func _text(text: String, rect: Rect2, font_size: int, color: Color) -> void:
    draw_string(_font,Vector2(rect.position.x,rect.position.y+font_size),text,HORIZONTAL_ALIGNMENT_CENTER,rect.size.x,font_size,color)

func _draw() -> void:
    if _font == null or size.x < 1 or size.y < 1:
        return
    draw_rect(Rect2(Vector2.ZERO,size),Color("#07141b"))
    var bg := texture("hero_stage.webp" if preview else "battle_arena.webp")
    if bg != null:
        var scale_factor := maxf(size.x/bg.get_width(),size.y/bg.get_height())
        var extent := bg.get_size()*scale_factor
        var crop_y := maxf(0,extent.y-size.y)*(0.5 if preview else 0.23)
        draw_texture_rect(bg,Rect2(Vector2((size.x-extent.x)*0.5,-crop_y),extent),false)
    if not preview:
        draw_rect(Rect2(0,0,size.x,minf(95.0,size.y*0.20)),Color(0.01,0.05,0.09,0.22))
        draw_rect(Rect2(0,maxf(0,size.y-119),size.x,119),Color(0.01,0.04,0.07,0.42))
        draw_rect(Rect2(0,0,2,size.y),Color("#7dd5de77"))
        draw_rect(Rect2(size.x-2,0,2,size.y),Color("#edaf6a77"))
        if not reduce_motion:
            for i in 7:
                var x := fposmod(i*117.0+animation_time*(11+i%3*3),size.x)
                var y := fposmod(i*131.0-animation_time*(9+i%2*4),size.y*0.68)+size.y*0.17
                draw_circle(Vector2(x,y),1.0+i%2,Color(1,0.86,0.58,0.12))
    _positions.clear()
    if preview:
        var artwork := texture(HERO_ART[clampi(preview_char,0,4)])
        if artwork != null:
            var h := size.y*0.79
            var w := h*artwork.get_width()/artwork.get_height()
            var foot := Vector2(size.x*0.5,size.y*0.83)
            draw_set_transform(foot,0,Vector2(1,0.25))
            draw_circle(Vector2.ZERO,h*0.24,Color(0,0,0,0.42))
            draw_set_transform(Vector2.ZERO)
            var float_y := 0.0 if reduce_motion else sin(animation_time*1.75)*1.5
            draw_texture_rect(artwork,Rect2(foot.x-w*0.5,foot.y-h+float_y,w,h),false)
        return
    if snapshot.is_empty():
        return
    if snapshot.get("mode","")=="raid":
        _draw_raid()
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
    var tower_accent := Color("#86e2e9") if lead==side else (Color("#f2a177") if lead>=0 else Color("#edcd8f"))
    _panel(Rect2(size.x*0.5-54,6,108,27),Color("#071722f2"),tower_accent)
    _text("TOWER "+str(tower.get("name",ti+1)),Rect2(size.x*0.5-54,9,108,23),12,Color("#ffdf9e"))
    for team in 2:
        var team_side: int = side if team == 0 else 1-side
        var roster := _roster(team_side)
        var n := roster.size()
        _garrison(roster,team)
        var row_count := mini(_max_rows(),maxi(1,n))
        var top := maxf(size.y*0.36,105)
        var bottom := size.y-151
        if bottom < top:
            bottom = top+25
        var spacing := (bottom-top)/maxi(1,row_count-1)
        for i in n:
            var row := i%_max_rows()
            var col := i/_max_rows()
            var x := size.x*0.5 + (-1 if team == 0 else 1)*(size.x*0.255+col*145)-pan
            var y := top if row_count > 1 else minf(size.y*0.61,size.y-(74 if size.y < 300 else 111)-43)
            if row_count > 1:
                y += spacing*row
            var cell_h := minf(190.0,maxf(68.0,spacing*1.15)) if row_count > 1 else minf(225.0,size.y*0.45)
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
    var w := minf(size.x*0.38,166)
    var x := 7.0 if team == 0 else size.x-w-7
    var col := Color("#69e4f4") if team == 0 else Color("#ff9867")
    _panel(Rect2(x,39,w,51),Color("#081b25f2"),col.darkened(0.24))
    _text("YOUR GARRISON" if team == 0 else "ENEMY GARRISON",Rect2(x,43,w,12),9,col)
    _text("%d / %d  ·  %d UP" % [hp,total,up],Rect2(x,58,w,14),11,Color.WHITE)
    draw_rect(Rect2(x+9,79,w-18,5),Color("#14232b"))
    if total > 0:
        draw_rect(Rect2(x+9,79,(w-18)*clampf(float(hp)/total,0,1),5),col)

func _actor(hero: Dictionary, foot: Vector2, height: float, enemy: bool, hide_label := false) -> void:
    var hid := str(hero.get("id",""))
    var dead := int(hero.get("hp",0)) <= 0
    var clip := "death" if dead else "idle"
    var age := 0.0
    if not dead and _animations.has(hid):
        var ani: Dictionary = _animations[hid]
        age = animation_time-float(ani.at)
        if age < float(ani.duration):
            clip = str(ani.clip)
        else:
            _animations.erase(hid)
    if foot.x+height<0 or foot.x-height>size.x:return
    var cls := 3 if hid=="boss" else clampi(int(hero.get("char",0)),0,4)
    var tex := texture(HERO_ART[cls])
    if tex == null:
        return
    var width := height*tex.get_width()/tex.get_height()
    _positions[hid] = foot
    draw_set_transform(foot,0.0,Vector2(1,0.25))
    draw_circle(Vector2.ZERO,width*0.33,Color(0,0,0,0.52))
    var shift := Vector2.ZERO
    var angle := 0.0
    var scale_y := 1.0
    var tint := Color(0.68,0.75,0.78,0.43) if dead else Color.WHITE
    if not dead and not reduce_motion:
        shift.y = sin(animation_time*1.9+float(absi(hid.hash())%7))*1.2
        scale_y = 1.0+sin(animation_time*1.9+float(absi(hid.hash())%7))*0.008
        if clip in ["attack","big"]:
            shift.x = (1 if enemy else -1)*sin(minf(1.0,age/0.65)*PI)*minf(15.0,height*0.13)
            angle = (0.06 if enemy else -0.06)*sin(minf(1.0,age/0.65)*PI)
        elif clip=="hit":
            shift.x = (1 if enemy else -1)*sin(minf(1.0,age/0.38)*PI)*minf(8.0,height*0.08)
            tint = Color(1.0,0.72,0.64,1.0)
    draw_set_transform(foot+shift,angle,Vector2(-1 if enemy else 1,scale_y))
    draw_texture_rect(tex,Rect2(-width*0.5,-height,width,height),false,tint)
    draw_set_transform(Vector2.ZERO)
    if not dead and not (hero.get("shieldSlots",[]) as Array).is_empty():
        draw_arc(foot+Vector2(0,-height*0.38),height*0.37,PI*0.93,TAU+0.3,28,Color(0.5,0.9,1,0.55),2,true)
    if hide_label:
        return
    var col := Color("#ff9367") if enemy else Color("#73ddeb")
    if hid == player_id:
        col = Color("#ffe198")
    var plate := Rect2(foot.x-58,foot.y+3,116,33)
    _panel(plate,Color("#061923f2"),col.darkened(0.17),7)
    var title := "YOU" if hid == player_id else str(hero.get("name","Hero")).left(13)
    _text(title,Rect2(plate.position+Vector2(0,2),Vector2(116,13)),11,col)
    if dead:
        var remain := maxi(0,int(ceil((float(hero.get("downUntil",0))-float(snapshot.get("now",0)))/1000.0)))
        _text("KO %ds" % remain if remain > 0 else "Awaiting respawn",Rect2(plate.position+Vector2(0,16),Vector2(116,11)),9,Color("#ddd8c9"))
    else:
        draw_rect(Rect2(plate.position+Vector2(7,23),Vector2(102,5)),Color("#122b24"))
        var ratio := clampf(float(hero.get("hp",0))/maxf(1,float(hero.get("maxHp",1))),0,1)
        draw_rect(Rect2(plate.position+Vector2(7,23),Vector2(102*ratio,5)),Color("#9ddc65") if ratio > 0.3 else Color("#ff755a"))

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

func _draw_raid()->void:
    var boss:Dictionary=snapshot.get("boss",{})
    if boss.is_empty():return
    var boss_entity:Dictionary={}
    var allies:Array=[]
    for h in snapshot.get("heroes",[]):
        if str(h.id)=="boss":boss_entity=h
        elif int(h.side)==0:allies.append(h)
    var w:=size.x-24
    _panel(Rect2(12,8,w,51),Color("#081b25ed"),Color("#f29c61"))
    _text(str(boss.get("name","DAILY BOSS")),Rect2(15,11,w-6,15),14,Color("#ffcc8e"))
    _text("%d / %d"%[maxi(0,int(boss.get("hp",0))),int(boss.get("max",1))],Rect2(15,30,w-6,12),11,Color.WHITE)
    draw_rect(Rect2(23,49,w-22,4),Color("#331a13"))
    var ratio:=clampf(float(boss.get("hp",0))/maxf(1,float(boss.get("max",1))),0,1)
    draw_rect(Rect2(23,49,(w-22)*ratio,4),Color("#e97843"))
    if not boss_entity.is_empty():_actor(boss_entity,Vector2(size.x*0.5,size.y*0.46),minf(240,size.y*0.6),true,true)
    var shown:=mini(20,allies.size())
    for i in shown:
        var row:=i/5;var column:=i%5
        var position:=Vector2(size.x*(column+0.5)/5,size.y*(0.56+row*0.11))
        var height:=minf(85.0,size.y*0.27)
        if i==0:height*=1.25
        _actor(allies[i],position,height,false,true)
    var run:Dictionary=snapshot.get("raid",{})
    if int(run.get("telegraphUntil",0))>float(snapshot.get("now",0)):
        var center:=Vector2(size.x*0.5,size.y*0.3)
        draw_arc(center,44,0,TAU,40,Color("#ffdd91"),3,true)
        _text("PARRY",Rect2(center-Vector2(60,10),Vector2(120,20)),17,Color("#fff0b8"))
    _draw_effects()
