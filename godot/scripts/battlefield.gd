extends Control
# Battlefield presentation: a real-time KayKit 3D stage in a SubViewport with a 2D HUD overlay
# (garrisons, tower title, nameplates, effects). Gameplay remains server-authoritative; this node
# only mirrors confirmed state and events.
const Stage = preload("res://scripts/kaykit_stage.gd")
const VisualTheme = preload("res://scripts/ui/visual_theme.gd")
const WORLD_PER_PX := 0.045

var snapshot: Dictionary = {}
var player_id := ""
var preview := false
var front_portrait := false
var reduce_motion := false:
    set(value):
        reduce_motion = value
        if is_instance_valid(stage):
            stage.reduce_motion = value
var preview_char := 0
var preview_weapon := 0
var pan := 0.0
var animation_time := 0.0

var stage
var viewport: SubViewport
var overlay: Control
var _drag := false
var _effects: Array = []
var _positions: Dictionary = {}
var _old_hp: Dictionary = {}
var _last_tower := -1
var _shown_preview := Vector2i(-1,-1)
var _font: Font
var _bold: Font

class Overlay:
    extends Control
    var field
    func _draw() -> void:
        field._paint(self)

func _ready() -> void:
    clip_contents = true
    mouse_filter = Control.MOUSE_FILTER_STOP
    _font = VisualTheme.BODY_FONT
    _bold = VisualTheme.BOLD_FONT
    viewport = SubViewport.new()
    viewport.own_world_3d = true
    viewport.msaa_3d = Viewport.MSAA_2X
    viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
    viewport.handle_input_locally = false
    viewport.gui_disable_input = true
    viewport.size = Vector2i(64,64)
    add_child(viewport)
    # The 3D view is rendered at physical pixel density, not the logical canvas size, so it stays
    # crisp on high-DPI phones where the UI is scaled up by the canvas_items stretch mode.
    var view := TextureRect.new()
    view.texture = viewport.get_texture()
    view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    view.stretch_mode = TextureRect.STRETCH_SCALE
    view.mouse_filter = Control.MOUSE_FILTER_IGNORE
    view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(view)
    stage = Stage.new()
    stage.mode = "portrait" if preview else "battle"
    stage.reduce_motion = reduce_motion
    viewport.add_child(stage)
    overlay = Overlay.new()
    overlay.field = self
    overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
    overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(overlay)
    if preview:
        _sync_preview()

func _process(delta: float) -> void:
    animation_time += delta
    _fit_viewport()
    for i in range(_effects.size()-1,-1,-1):
        if animation_time - float(_effects[i].at) > 0.95:
            _effects.remove_at(i)
    if preview:
        _sync_preview()
    elif is_instance_valid(stage):
        stage.set_pan(pan*WORLD_PER_PX)
    overlay.queue_redraw()

static func render_scale(node: CanvasItem) -> float:
    var k := node.get_viewport().get_final_transform().get_scale().x if node.get_viewport() != null else 1.0
    return clampf(k,1.0,2.0)

func _fit_viewport() -> void:
    if viewport == null or size.x < 2 or size.y < 2:
        return
    var want := Vector2i((size*render_scale(self)).round())
    if viewport.size != want:
        viewport.size = want

# ---------- state ----------
func accept_state(data: Dictionary, who: String) -> void:
    snapshot = data
    player_id = who
    var me := _me()
    var ti := int(me.get("tower",0))
    if ti != _last_tower:
        pan = 0.0
        _effects.clear()
        _old_hp.clear()
        _last_tower = ti
    var hits: Array[String] = []
    for hero in data.get("heroes",[]):
        var hid := str(hero.get("id",""))
        var hp := int(hero.get("hp",0))
        if _old_hp.has(hid) and hp > 0 and hp < int(_old_hp[hid]):
            hits.append(hid)
        _old_hp[hid] = hp
    _sync_stage()
    for hid in hits:
        stage.act(hid,"hit")

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
    # The local player always stands in the front rank.
    heroes.sort_custom(func(a,b): return str(a.get("id","")) == player_id and str(b.get("id","")) != player_id)
    return heroes

func _max_rows() -> int:
    return 2 if size.y < 330 else 3

func _pan_limit() -> float:
    var a := _roster(int(_me().get("side",0))).size()
    var b := _roster(1-int(_me().get("side",0))).size()
    var cols := int(ceil(float(maxi(a,b))/_max_rows()))
    return maxf(0.0,(cols-1)*2.6/WORLD_PER_PX)

func _slot(team: int, index: int) -> Dictionary:
    # Two ranks facing each other across the lane; extra fighters form further columns outward.
    var rows := _max_rows()
    var row := index % rows
    var col := index / rows
    var dir := -1.0 if team == 0 else 1.0
    var x := dir*(2.55 + col*2.8 + (0.4 if row == 1 else 0.0))
    var z: float = [5.2,0.3,-5.3][row] if rows == 3 else [4.6,-1.4][row]
    var facing := (PI*0.5 - 0.42) if team == 0 else (-PI*0.5 + 0.42)
    return {"pos":Vector3(x,0,z),"facing":facing}

func _sync_stage() -> void:
    if not is_instance_valid(stage) or preview:
        return
    var entries: Array = []
    if snapshot.get("mode","") == "raid":
        stage.mode = "raid"
        var allies: Array = []
        for h in snapshot.get("heroes",[]):
            if str(h.get("id","")) == "boss":
                entries.append({"id":"boss","char":int(h.get("char",3)),"weapon":int(h.get("weapon",5)),"pos":Vector3(0,0,-6.5),"facing":0.0,"dead":int(h.get("hp",0))<=0,"big":true})
            elif int(h.get("side",0)) == 0:
                allies.append(h)
        for i in mini(allies.size(),15):
            var row := i/5
            var col := i%5
            var h: Dictionary = allies[i]
            var x := (col-2)*2.3 + (1.15 if row%2 else 0.0)
            entries.append({"id":str(h.id),"char":int(h.get("char",0)),"weapon":int(h.get("weapon",0)),"pos":Vector3(x,0,-0.5+row*2.4),"facing":PI,"dead":int(h.get("hp",0))<=0})
    else:
        stage.mode = "battle"
        var side := int(_me().get("side",0))
        for team in 2:
            var roster := _roster(side if team == 0 else 1-side)
            for i in roster.size():
                var h: Dictionary = roster[i]
                var slot := _slot(team,i)
                entries.append({"id":str(h.id),"char":int(h.get("char",0)),"weapon":int(h.get("weapon",0)),"pos":slot.pos,"facing":slot.facing,"dead":int(h.get("hp",0))<=0,"tier":int(h.get("tier",0))})
        var towers: Array = snapshot.get("towers",[])
        var ti := int(_me().get("tower",0))
        if towers.size() == 10:
            var tower: Dictionary = towers[ti]
            var dmg: Array = tower.get("dmg",[0,0])
            var lead := int(tower.get("prev",-1))
            if float(dmg[0]) != float(dmg[1]):
                lead = 0 if float(dmg[0]) > float(dmg[1]) else 1
            # Blue banners for the player's side, red for the opponent, regardless of server side index.
            stage.set_tower_lead(-1 if lead < 0 else (0 if lead == side else 1))
    stage.sync_actors(entries)

func _sync_preview() -> void:
    var key := Vector2i(preview_char,preview_weapon)
    if key == _shown_preview or not is_instance_valid(stage):
        return
    _shown_preview = key
    stage.sync_actors([{"id":"preview","char":preview_char,"weapon":preview_weapon,"pos":Vector3.ZERO,"facing":0.42}])

func _gui_input(event: InputEvent) -> void:
    if preview:
        return
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
        stage.act(actor,"attack",event.get("tier","") == "triple")
    if typ in ["spell","rally","ultimate","ko"]:
        var kind := str(event.get("spell",typ))
        var colour := Color("#9fe8ff")
        if kind in ["horn","rally"]:
            colour = Color("#ffd46b")
        elif kind in ["surge","ultimate"]:
            colour = Color("#c79bff")
        elif kind == "ko":
            colour = Color("#ff8a5c")
        var at: Vector3 = stage.foot_position(actor) if kind in ["bulwark","ultimate","surge"] else Vector3(0,0,1.0)
        stage.ring(at,colour,3.2 if kind in ["barrage","horn","rally"] else 2.0)
        if reduce_motion:
            return
        if _effects.size() >= 8:
            _effects.pop_front()
        _effects.append({"kind":kind,"at":animation_time,"actor":actor})

# ---------- overlay ----------
func _screen(world: Vector3) -> Vector2:
    var cam: Camera3D = stage.camera
    if cam == null or cam.is_position_behind(world):
        return Vector2(-999,-999)
    var p := cam.unproject_position(world)
    var vs := Vector2(viewport.size)
    if vs.x <= 0:
        return p
    return p*size/vs

func _panel(c: CanvasItem, rect: Rect2, bg: Color, border: Color, radius := 9, width := 1.5) -> void:
    var style := StyleBoxFlat.new()
    style.bg_color = bg
    style.border_color = border
    style.set_border_width_all(int(width))
    style.set_corner_radius_all(radius)
    style.shadow_color = Color(0,0,0,0.38)
    style.shadow_size = 4
    style.shadow_offset = Vector2(0,2)
    style.anti_aliasing = true
    c.draw_style_box(style,rect)

func _text(c: CanvasItem, text: String, pos: Vector2, font_size: int, color: Color, font: Font = null, width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
    var f := font if font != null else _bold
    c.draw_string(f,pos+Vector2(0,1),text,align,width,font_size,Color(0,0,0,0.55))
    c.draw_string(f,pos,text,align,width,font_size,color)

func _hex(c: CanvasItem, center: Vector2, r: float, fill: Color, stroke: Color) -> void:
    var pts := PackedVector2Array()
    for i in 6:
        var a := PI/6 + i*PI/3
        pts.append(center+Vector2(cos(a),sin(a))*r)
    c.draw_colored_polygon(pts,fill)
    pts.append(pts[0])
    c.draw_polyline(pts,stroke,1.6,true)

func _paint(c: Control) -> void:
    _positions.clear()
    if preview:
        return
    # Soft vignette frames the arena and pushes focus toward the fighters.
    var w := size.x
    var h := size.y
    var shade := Color(0.02,0.05,0.08,0.34)
    var clear := Color(0.02,0.05,0.08,0.0)
    c.draw_polygon(PackedVector2Array([Vector2(0,0),Vector2(w,0),Vector2(w,h*0.12),Vector2(0,h*0.12)]),PackedColorArray([shade,shade,clear,clear]))
    c.draw_polygon(PackedVector2Array([Vector2(0,h*0.8),Vector2(w,h*0.8),Vector2(w,h),Vector2(0,h)]),PackedColorArray([clear,clear,shade,shade]))
    c.draw_polygon(PackedVector2Array([Vector2(0,0),Vector2(w*0.07,0),Vector2(w*0.07,h),Vector2(0,h)]),PackedColorArray([shade,clear,clear,shade]))
    c.draw_polygon(PackedVector2Array([Vector2(w*0.93,0),Vector2(w,0),Vector2(w,h),Vector2(w*0.93,h)]),PackedColorArray([clear,shade,shade,clear]))
    if snapshot.is_empty():
        return
    if snapshot.get("mode","") == "raid":
        _paint_raid(c)
        return
    var side := int(_me().get("side",0))
    var ti := int(_me().get("tower",0))
    var towers: Array = snapshot.get("towers",[])
    if towers.size() != 10:
        return
    var tower: Dictionary = towers[ti]
    var labels: Array = []
    for team in 2:
        for hero in _roster(side if team == 0 else 1-side):
            var hid := str(hero.get("id",""))
            var head := _screen(stage.head_position(hid))
            _positions[hid] = _screen(stage.foot_position(hid))
            if head.x > -60 and head.x < w+60:
                labels.append({"hero":hero,"at":head,"enemy":team == 1})
    labels.sort_custom(func(a,b): return a.at.y < b.at.y)
    _paint_effects(c)
    for item in labels:
        _nameplate(c,item.hero,item.at,item.enemy)
    for team in 2:
        _garrison(c,_roster(side if team == 0 else 1-side),team)
    var title := "Tower "+str(tower.get("name",ti+1))
    var anchor := _screen(stage.tower_anchor())
    var tw := _bold.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,17).x+26
    var ty := clampf(anchor.y-34,62,h*0.35)
    _panel(c,Rect2(w*0.5-tw*0.5,ty,tw,30),Color("#0a1319e6"),Color("#e9c97a"),8,1)
    _text(c,title,Vector2(w*0.5-tw*0.5,ty+22),17,Color("#ffd97a"),_bold,tw,HORIZONTAL_ALIGNMENT_CENTER)
    if _pan_limit() > 1:
        _text(c,"◂ drag to see more fighters ▸",Vector2(0,h-8),10,Color(1,1,1,0.75),_font,w,HORIZONTAL_ALIGNMENT_CENTER)

func _garrison(c: CanvasItem, heroes: Array, team: int) -> void:
    var hp := 0
    var total := 0
    var up := 0
    var shields := 0
    for hero in heroes:
        hp += maxi(0,int(hero.get("hp",0)))
        total += int(hero.get("maxHp",0))
        if int(hero.get("hp",0)) > 0:
            up += 1
        shields += (hero.get("shieldSlots",[]) as Array).size()
    var w := minf(size.x*0.44,196.0)
    var x := 6.0 if team == 0 else size.x-w-6
    var col := Color("#55d3ee") if team == 0 else Color("#ff8a4a")
    _panel(c,Rect2(x,6,w,56),Color("#0a1319e0"),Color(col,0.35),9,1)
    var title := "YOUR GARRISON" if team == 0 else "ENEMY GARRISON"
    _text(c,title,Vector2(x+8,22),12,col,_bold,w-16,HORIZONTAL_ALIGNMENT_LEFT if team == 0 else HORIZONTAL_ALIGNMENT_RIGHT)
    var bar := Rect2(x+8,27,w-16,15)
    c.draw_rect(bar,Color("#1a262e"))
    var ratio := clampf(float(hp)/maxf(1.0,float(total)),0,1)
    _panel(c,Rect2(bar.position,Vector2(maxf(14,bar.size.x*ratio),bar.size.y)),col,Color(col.lightened(0.3),0.6),7,0)
    c.draw_rect(Rect2(bar.position+Vector2(4,2),Vector2(maxf(6,bar.size.x*ratio-8),3)),Color(1,1,1,0.22))
    _text(c,"%s / %s" % [_k(hp),_k(total)],Vector2(bar.position.x,bar.position.y+12),11,Color.WHITE,_bold,bar.size.x,HORIZONTAL_ALIGNMENT_CENTER)
    _text(c,"⛨ %d absorb · %d/%d up" % [shields,up,heroes.size()],Vector2(x+8,57),11,Color("#9fd8ff"),_font,w-16,HORIZONTAL_ALIGNMENT_LEFT if team == 0 else HORIZONTAL_ALIGNMENT_RIGHT)

func _k(n: int) -> String:
    if n >= 100000:
        return "%.1fk" % (n/1000.0)
    return str(n)

func _nameplate(c: CanvasItem, hero: Dictionary, head: Vector2, enemy: bool) -> void:
    var hid := str(hero.get("id",""))
    var dead := int(hero.get("hp",0)) <= 0
    var me := hid == player_id
    var col := Color("#ff9a5c") if enemy else Color("#5fd4ea")
    var name := "You" if me else str(hero.get("name","Hero")).left(12)
    var atk := "ATK %d" % int(hero.get("atk",0))
    var nw := _bold.get_string_size(name,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x
    var aw := _bold.get_string_size(atk,HORIZONTAL_ALIGNMENT_LEFT,-1,10).x
    var pw := 34.0+nw+6+aw+10
    var rect := Rect2(head.x-pw*0.5,head.y-34,pw,30)
    rect.position.x = clampf(rect.position.x,2,size.x-pw-2)
    var border := Color("#7fe36b") if me else Color(col,0.75)
    _panel(c,rect,Color("#0b1419ee"),border,9,2 if me else 1)
    c.draw_rect(Rect2(rect.position+Vector2(3,2),Vector2(pw-6,1)),Color(1,1,1,0.10))
    _hex(c,rect.position+Vector2(15,13),10,Color("#0d2230") if not enemy else Color("#2b140c"),col)
    _text(c,str(int(hero.get("level",1))),rect.position+Vector2(5,18),11,Color.WHITE,_bold,20,HORIZONTAL_ALIGNMENT_CENTER)
    _text(c,name,rect.position+Vector2(30,19),14,Color("#b6f28f") if me else Color.WHITE,_bold)
    _text(c,atk,rect.position+Vector2(30+nw+6,18),10,col,_bold)
    var bar := Rect2(rect.position+Vector2(8,23),Vector2(pw-16,4))
    c.draw_rect(bar,Color("#0f2a1b"))
    if dead:
        var remain := maxi(0,int(ceil((float(hero.get("downUntil",0))-float(snapshot.get("now",0)))/1000.0)))
        _text(c,("KO · %ds" % remain) if remain > 0 else "Respawning",rect.position+Vector2(0,rect.size.y+13),11,Color("#ffd2c2"),_bold,pw,HORIZONTAL_ALIGNMENT_CENTER)
    else:
        var ratio := clampf(float(hero.get("hp",0))/maxf(1,float(hero.get("maxHp",1))),0,1)
        c.draw_rect(Rect2(bar.position,Vector2(bar.size.x*ratio,bar.size.y)),Color("#63d85a") if ratio > 0.3 else Color("#ff6a4d"))
    var tip := Vector2(clampf(head.x,rect.position.x+10,rect.end.x-10),rect.end.y)
    c.draw_colored_polygon(PackedVector2Array([tip+Vector2(-6,0),tip+Vector2(6,0),tip+Vector2(0,6)]),Color("#0b1419ee"))
    var shields := (hero.get("shieldSlots",[]) as Array).size()
    for i in shields:
        _shield_icon(c,rect.position+Vector2(pw-10-i*13,-6))

func _shield_icon(c: CanvasItem, at: Vector2) -> void:
    var pts := PackedVector2Array([at+Vector2(-6,-6),at+Vector2(6,-6),at+Vector2(6,1),at+Vector2(0,7),at+Vector2(-6,1)])
    c.draw_colored_polygon(pts,Color("#8fd1ff"))
    pts.append(pts[0])
    c.draw_polyline(pts,Color("#0b1419"),1.4,true)

func _paint_effects(c: CanvasItem) -> void:
    for fx in _effects:
        var t := clampf((animation_time-float(fx.at))/0.95,0,1)
        var actor: Vector2 = _positions.get(str(fx.actor),size*0.5)
        var center := Vector2(size.x*0.5,size.y*0.58)
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
                c.draw_line(point-Vector2(16,55),point,color,4,true)
                c.draw_circle(point,5,color)
        elif kind in ["surge","ultimate"]:
            var origin := actor-Vector2(0,40)
            for i in 8:
                var angle := TAU*i/8+t*2
                var dir := Vector2(cos(angle),sin(angle))
                c.draw_line(origin+dir*(20+t*70),origin+dir*(34+t*90),color,3,true)

func _paint_raid(c: CanvasItem) -> void:
    var boss: Dictionary = snapshot.get("boss",{})
    if boss.is_empty():
        return
    var w := size.x-16
    _panel(c,Rect2(8,8,w,52),Color("#0a1319e6"),Color("#f29c61"),10,1)
    _text(c,str(boss.get("name","DAILY BOSS")),Vector2(8,28),15,Color("#ffcc8e"),_bold,w,HORIZONTAL_ALIGNMENT_CENTER)
    var bar := Rect2(20,36,w-24,15)
    c.draw_rect(bar,Color("#331a13"))
    var ratio := clampf(float(boss.get("hp",0))/maxf(1,float(boss.get("max",1))),0,1)
    _panel(c,Rect2(bar.position,Vector2(maxf(14,bar.size.x*ratio),bar.size.y)),Color("#e0643a"),Color("#ffb27a"),7,0)
    _text(c,"%d / %d"%[maxi(0,int(boss.get("hp",0))),int(boss.get("max",1))],Vector2(bar.position.x,bar.position.y+12),11,Color.WHITE,_bold,bar.size.x,HORIZONTAL_ALIGNMENT_CENTER)
    for h in snapshot.get("heroes",[]):
        _positions[str(h.id)] = _screen(stage.foot_position(str(h.id)))
    var run: Dictionary = snapshot.get("raid",{})
    if int(run.get("telegraphUntil",0)) > float(snapshot.get("now",0)):
        var center := _screen(stage.head_position("boss"))+Vector2(0,30)
        var pulse := 1.0+0.08*sin(animation_time*14)
        c.draw_arc(center,46*pulse,0,TAU,48,Color("#ffdd91"),3,true)
        _text(c,"PARRY",center-Vector2(60,-7),20,Color("#fff0b8"),_bold,120,HORIZONTAL_ALIGNMENT_CENTER)
    _paint_effects(c)
