extends Control

const ArenaApiScript = preload("res://scripts/arena_api.gd")
const ArenaWireScript = preload("res://scripts/arena_wire.gd")
const SpellFXScript = preload("res://scripts/spell_fx.gd")

const SPELLS := ["barrage","bulwark","horn","surge"]
const SPELL_NAMES := {"barrage":"Barrage","bulwark":"Bulwark","horn":"War Horn","surge":"Arcane Surge"}
const FACE_NAMES := {"S":"SWORD","C":"CRIT","H":"SHIELD","G":"GOLD","E":"FOCUS","F":"GIFT"}

var api
var ui_root: Control
var poll_timer: Timer
var spell_fx

var searching := false
var active := false
var polling := false
var busy := false
var latest: Dictionary = {}
var latest_state: Dictionary = {}
var current_match_id := ""
var event_seq := 0
var hero_rows: Dictionary = {}
var tower_buttons: Array[Button] = []
var selected_mult := 1
var selected_loadout := ["barrage","bulwark"]

var queue_status: Label
var queue_clock: Label
var timer_label: Label
var score_label: Label
var connection_label: Label
var net_label: Label
var tower_label: Label
var tower_detail: Label
var focus_label: Label
var result_label: Label
var earnings_label: Label
var dice_labels: Array[Label] = []
var roll_button: Button
var rally_button: Button
var ultimate_button: Button
var spell_buttons: Array[Button] = []
var mult_select: OptionButton
var all_in: CheckButton
var heroes_left: VBoxContainer
var heroes_right: VBoxContainer

func _ready() -> void:
    api = ArenaApiScript.new()
    add_child(api)
    poll_timer = Timer.new()
    poll_timer.wait_time = 0.75
    poll_timer.one_shot = false
    poll_timer.timeout.connect(_poll)
    add_child(poll_timer)
    spell_fx = SpellFXScript.new()
    add_child(spell_fx)
    _show_home()

func _process(_delta: float) -> void:
    if active and not latest.is_empty():
        _paint_clock_and_controls()

func _clear_ui() -> void:
    hero_rows.clear()
    tower_buttons.clear()
    dice_labels.clear()
    spell_buttons.clear()
    if is_instance_valid(ui_root):
        ui_root.queue_free()
    ui_root = Control.new()
    ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(ui_root)
    move_child(spell_fx,get_child_count()-1)

func _background() -> ColorRect:
    var bg := ColorRect.new()
    bg.color = Color("#071924")
    bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    ui_root.add_child(bg)
    return bg

func _style(bg: Color, border := Color("#57717a"), radius := 12) -> StyleBoxFlat:
    var s := StyleBoxFlat.new()
    s.bg_color = bg
    s.border_color = border
    s.set_border_width_all(1)
    s.set_corner_radius_all(radius)
    s.content_margin_left = 10
    s.content_margin_right = 10
    s.content_margin_top = 8
    s.content_margin_bottom = 8
    return s

func _label(text := "", size := 14, color := Color("#d8e7e8")) -> Label:
    var l := Label.new()
    l.text = text
    l.add_theme_font_size_override("font_size",size)
    l.add_theme_color_override("font_color",color)
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    return l

func _button(text: String) -> Button:
    var b := Button.new()
    b.text = text
    b.custom_minimum_size = Vector2(0,48)
    b.add_theme_stylebox_override("normal",_style(Color("#143242"),Color("#8da09a"),10))
    b.add_theme_stylebox_override("hover",_style(Color("#204a5d"),Color("#e2c47f"),10))
    b.add_theme_stylebox_override("pressed",_style(Color("#2a5b6d"),Color("#ffe19b"),10))
    b.add_theme_stylebox_override("disabled",_style(Color("#12232c"),Color("#45565c"),10))
    return b

func _show_home() -> void:
    searching = false
    active = false
    poll_timer.stop()
    _clear_ui()
    _background()
    var margin := MarginContainer.new()
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    margin.add_theme_constant_override("margin_left",20)
    margin.add_theme_constant_override("margin_right",20)
    margin.add_theme_constant_override("margin_top",max(28,int(get_viewport_rect().size.y*0.05)))
    margin.add_theme_constant_override("margin_bottom",24)
    ui_root.add_child(margin)
    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation",12)
    margin.add_child(box)
    var title := _label("FATEBOUND",34,Color("#f3d488"))
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    box.add_child(title)
    var sub := _label("Godot native-client milestone 1",15,Color("#7ce1ef"))
    sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    box.add_child(sub)
    box.add_child(_label("This preview uses the live authoritative arena. The existing HTML client remains untouched.",13,Color("#a8bbc1")))
    var name_edit := LineEdit.new()
    name_edit.name = "PlayerName"
    name_edit.placeholder_text = "Player name"
    name_edit.text = "Godot Player"
    name_edit.custom_minimum_size.y = 48
    box.add_child(name_edit)
    var loadout_row := HBoxContainer.new()
    loadout_row.add_theme_constant_override("separation",8)
    box.add_child(loadout_row)
    for slot in 2:
        var choose := OptionButton.new()
        choose.name = "Spell%d" % slot
        choose.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        for spell in SPELLS:
            choose.add_item(SPELL_NAMES[spell])
            choose.set_item_metadata(choose.item_count-1,spell)
        choose.select(slot)
        loadout_row.add_child(choose)
    box.add_child(_label("Milestone combat is level-10 equalized, exactly like the current online alpha. Gzip state responses and transport-v2 deltas are enabled.",12,Color("#9db7bd")))
    var play := _button("FIND 20-PLAYER BATTLE")
    play.pressed.connect(func(): _start_queue(name_edit.text))
    box.add_child(play)
    var status := _label("Arena endpoint: " + api.base_url,11,Color("#78969d"))
    status.name = "HomeStatus"
    box.add_child(status)

func _start_queue(display_name: String) -> void:
    if searching or active:
        return
    var home_status := ui_root.find_child("HomeStatus",true,false) as Label
    if home_status:
        home_status.text = "Connecting…"
    selected_loadout.clear()
    for slot in 2:
        var choose := ui_root.find_child("Spell%d" % slot,true,false) as OptionButton
        selected_loadout.append(str(choose.get_item_metadata(choose.selected)))
    if selected_loadout[0] == selected_loadout[1]:
        if home_status:
            home_status.text = "Choose two different spells."
        return
    var session: Dictionary = await api.ensure_session(display_name.strip_edges() if not display_name.strip_edges().is_empty() else "Godot Player")
    if not session.get("ok",false):
        if home_status:
            home_status.text = str(session.get("error","Could not create arena session"))
        return
    var state: Dictionary = await api.queue(0,0,selected_loadout)
    if not state.get("ok",false):
        if home_status:
            home_status.text = str(state.get("error","Queue failed"))
        return
    _show_queue()
    _accept(state)
    poll_timer.start()

func _show_queue() -> void:
    searching = true
    _clear_ui()
    _background()
    var center := CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    ui_root.add_child(center)
    var panel := PanelContainer.new()
    panel.custom_minimum_size = Vector2(340,330)
    panel.add_theme_stylebox_override("panel",_style(Color("#0d2633"),Color("#d0b470"),18))
    center.add_child(panel)
    var box := VBoxContainer.new()
    box.alignment = BoxContainer.ALIGNMENT_CENTER
    box.add_theme_constant_override("separation",14)
    panel.add_child(box)
    var t := _label("FINDING PLAYERS",24,Color("#f2d38a"))
    t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    box.add_child(t)
    queue_clock = _label("20",64,Color("#79e7ef"))
    queue_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    box.add_child(queue_clock)
    queue_status = _label("Connecting to the arena…",14)
    queue_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    box.add_child(queue_status)
    box.add_child(_label("20 total slots · 10 per side\nBots fill only after the 20-second deadline.",12,Color("#9db7bd")))
    var cancel := _button("CANCEL")
    cancel.pressed.connect(_cancel_queue)
    box.add_child(cancel)

func _cancel_queue() -> void:
    searching = false
    poll_timer.stop()
    await api.cancel()
    _show_home()

func _poll() -> void:
    if polling or (not searching and not active):
        return
    polling = true
    var state: Dictionary = await api.state()
    polling = false
    if state.get("ok",false):
        _accept(state)
    elif active:
        if connection_label:
            connection_label.text = "RECONNECTING"

func _accept(state: Dictionary) -> void:
    latest_state = state
    var status := str(state.get("status",""))
    if status == "searching":
        searching = true
        if queue_status:
            queue_status.text = "%d / 20 human players" % int(state.get("humans",0))
        if queue_clock:
            queue_clock.text = str(int(ceil(max(0.0,float(state.get("deadline",0))-float(state.get("serverNow",0)))/1000.0)))
        return
    if status == "idle":
        if searching:
            _show_home()
        return
    if status != "battle" and status != "complete":
        return
    searching = false
    var match: Dictionary = state.get("match",{})
    if match.is_empty():
        return
    latest = match
    current_match_id = str(match.get("id",""))
    if not active:
        active = true
        _show_battle()
    _update_battle(match,state.get("earnings",{}))
    if status == "complete":
        poll_timer.stop()
        _show_result(state)

func _show_battle() -> void:
    _clear_ui()
    _background()
    var safe := MarginContainer.new()
    safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    safe.add_theme_constant_override("margin_left",8)
    safe.add_theme_constant_override("margin_right",8)
    safe.add_theme_constant_override("margin_top",8)
    safe.add_theme_constant_override("margin_bottom",8)
    ui_root.add_child(safe)
    var page := VBoxContainer.new()
    page.add_theme_constant_override("separation",5)
    safe.add_child(page)

    var header := HBoxContainer.new()
    page.add_child(header)
    score_label = _label("0 — 0",20,Color("#f1d184"))
    score_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    header.add_child(score_label)
    timer_label = _label("5:00",24,Color.WHITE)
    timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    timer_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    header.add_child(timer_label)
    connection_label = _label("LIVE",12,Color("#78e7a1"))
    connection_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    connection_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    header.add_child(connection_label)

    var tower_scroll := ScrollContainer.new()
    tower_scroll.custom_minimum_size.y = 54
    tower_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
    tower_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    page.add_child(tower_scroll)
    var towers := HBoxContainer.new()
    towers.add_theme_constant_override("separation",5)
    tower_scroll.add_child(towers)
    for i in 10:
        var b := _button(str(i+1))
        b.custom_minimum_size = Vector2(52,44)
        b.pressed.connect(_move_to.bind(i))
        tower_buttons.append(b)
        towers.add_child(b)

    var field := PanelContainer.new()
    field.size_flags_vertical = Control.SIZE_EXPAND_FILL
    field.add_theme_stylebox_override("panel",_style(Color("#173c34"),Color("#6f9b75"),16))
    page.add_child(field)
    var fbox := VBoxContainer.new()
    fbox.add_theme_constant_override("separation",4)
    field.add_child(fbox)
    tower_label = _label("Tower",20,Color("#ffe08a"))
    tower_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    fbox.add_child(tower_label)
    tower_detail = _label("",11,Color("#b8d0c5"))
    tower_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    fbox.add_child(tower_detail)
    var teams := HBoxContainer.new()
    teams.size_flags_vertical = Control.SIZE_EXPAND_FILL
    teams.add_theme_constant_override("separation",8)
    fbox.add_child(teams)
    heroes_left = VBoxContainer.new()
    heroes_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    teams.add_child(heroes_left)
    heroes_right = VBoxContainer.new()
    heroes_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    teams.add_child(heroes_right)
    _build_hero_rows()

    var dice := HBoxContainer.new()
    dice.alignment = BoxContainer.ALIGNMENT_CENTER
    dice.add_theme_constant_override("separation",7)
    fbox.add_child(dice)
    for i in 3:
        var d := _label("—",15,Color("#e6d699"))
        d.custom_minimum_size = Vector2(88,50)
        d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        d.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        d.add_theme_stylebox_override("normal",_style(Color("#382b16"),Color("#d0a748"),10))
        dice_labels.append(d)
        dice.add_child(d)

    result_label = _label("Server-confirmed roll effects appear here.",11,Color("#c6e2e4"))
    result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    fbox.add_child(result_label)
    earnings_label = _label("",10,Color("#91c7cd"))
    earnings_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    fbox.add_child(earnings_label)

    var controls := HBoxContainer.new()
    controls.add_theme_constant_override("separation",5)
    page.add_child(controls)
    mult_select = OptionButton.new()
    mult_select.custom_minimum_size = Vector2(76,48)
    for m in [1,2,3,4]:
        mult_select.add_item("×%d" % m,m)
    controls.add_child(mult_select)
    all_in = CheckButton.new()
    all_in.text = "ALL-IN"
    all_in.custom_minimum_size.x = 75
    controls.add_child(all_in)
    roll_button = _button("ROLL")
    roll_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    roll_button.pressed.connect(_roll)
    controls.add_child(roll_button)
    rally_button = _button("RALLY")
    rally_button.custom_minimum_size.x = 78
    rally_button.pressed.connect(func(): _do_action("rally"))
    controls.add_child(rally_button)

    var powers := HBoxContainer.new()
    powers.add_theme_constant_override("separation",5)
    page.add_child(powers)
    ultimate_button = _button("ULTIMATE")
    ultimate_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    ultimate_button.pressed.connect(func(): _do_action("ultimate"))
    powers.add_child(ultimate_button)
    for spell in selected_loadout:
        var b := _button(SPELL_NAMES[spell])
        b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        b.set_meta("spell",spell)
        b.pressed.connect(_cast_spell.bind(spell))
        spell_buttons.append(b)
        powers.add_child(b)

    focus_label = _label("FOCUS",11,Color("#efc875"))
    focus_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    page.add_child(focus_label)
    net_label = _label("",9,Color("#6f969e"))
    net_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    page.add_child(net_label)

func _build_hero_rows() -> void:
    for hero in latest.get("heroes",[]):
        var side := int(hero.get("side",0))
        var row := VBoxContainer.new()
        row.add_theme_constant_override("separation",1)
        var name := _label("",10,Color("#dbe8e6"))
        name.name = "Name"
        row.add_child(name)
        var hp := ProgressBar.new()
        hp.name = "HP"
        hp.show_percentage = false
        hp.custom_minimum_size.y = 8
        row.add_child(hp)
        hero_rows[str(hero.get("id",""))] = row
        (heroes_left if side == 0 else heroes_right).add_child(row)

func _me() -> Dictionary:
    for hero in latest.get("heroes",[]):
        if str(hero.get("id","")) == api.player_id:
            return hero
    return {}

func _update_battle(match: Dictionary, earnings: Variant = {}) -> void:
    latest = match
    var me := _me()
    if me.is_empty():
        connection_label.text = "SLOT LOST"
        return
    var tower := int(me.get("tower",0))
    for i in tower_buttons.size():
        tower_buttons[i].text = ("● " if i == tower else "") + str(i+1)
        tower_buttons[i].disabled = busy or int(me.get("hp",0)) <= 0
    var scores: Array = match.get("score",[0,0])
    score_label.text = "%d — %d" % [int(scores[0]),int(scores[1])]
    tower_label.text = str(match.get("towers",[])[tower].get("name","Tower %d" % (tower+1)))
    var t: Dictionary = match.get("towers",[])[tower]
    tower_detail.text = "Tower damage %s · phase %s" % [str(t.get("dmg",[0,0])),str(match.get("phase","regulation")).capitalize()]
    var my_side := int(me.get("side",0))
    for hero in match.get("heroes",[]):
        var row: VBoxContainer = hero_rows.get(str(hero.get("id","")))
        if row == null:
            continue
        var visible_here := int(hero.get("tower",-1)) == tower
        row.visible = visible_here
        var n := row.get_node("Name") as Label
        var p := row.get_node("HP") as ProgressBar
        var hpv := int(hero.get("hp",0))
        var max_hp: int = maxi(1,int(hero.get("maxHp",1)))
        p.max_value = max_hp
        p.value = hpv
        n.text = "%s%s  %d/%d" % [str(hero.get("name","Hero")),(" [BOT]" if hero.get("bot",false) else ""),hpv,max_hp]
        if str(hero.get("id","")) == api.player_id:
            n.add_theme_color_override("font_color",Color("#ffe18d"))
        elif int(hero.get("side",0)) == my_side:
            n.add_theme_color_override("font_color",Color("#8beaff"))
        else:
            n.add_theme_color_override("font_color",Color("#ff9d79"))
    _paint_dice(me.get("lastFaces",[]))
    _paint_clock_and_controls()
    if earnings is Dictionary and not earnings.is_empty():
        earnings_label.text = "Banked: %s" % JSON.stringify(earnings)
    net_label.text = "transport2 · full %d · delta %d · %.1f KB decoded JSON received" % [api.wire.stats.full,api.wire.stats.delta,float(api.bytes_received)/1024.0]
    _process_events(match)

func _paint_dice(faces: Array) -> void:
    var win: Dictionary = ArenaWireScript.winning_dice(faces)
    for i in 3:
        var label := dice_labels[i]
        if i < faces.size():
            label.text = FACE_NAMES.get(str(faces[i]),str(faces[i]))
        else:
            label.text = "—"
        var winning: bool = (win.get("indices",[]) as Array).has(i)
        label.add_theme_stylebox_override("normal",_style(Color("#4d3a12") if winning else Color("#2d281b"),Color("#71f0d2") if winning else Color("#907849"),10))
        label.add_theme_color_override("font_color",Color("#fff0b0") if winning else Color("#d8c991"))

func _paint_clock_and_controls() -> void:
    if latest.is_empty():
        return
    var now := int(latest.get("now",Time.get_unix_time_from_system()*1000))
    var end_at := int(latest.get("endAt",now))
    var remain: int = maxi(0,end_at-now)
    timer_label.text = "%d:%02d" % [remain/60000,(remain/1000)%60]
    var me := _me()
    if me.is_empty():
        return
    var hp := int(me.get("hp",0))
    var down_until := int(me.get("downUntil",0))
    var focus := int(me.get("focus",0))
    focus_label.text = "FOCUS %d/8 · SPELL %d/2 · ULT %d%%" % [focus,int(me.get("spell",0)),int(me.get("ult",0))]
    connection_label.text = "LIVE" if not me.get("substitute",false) else "RECONNECTING"
    var ko := hp <= 0
    var ko_left: int = maxi(0,int(ceil(float(down_until-now)/1000.0)))
    roll_button.text = "ROLL\n%s" % (("KO %ds" % ko_left) if ko else "server authoritative")
    var cooldown := int(me.get("rollAt",0)) > now
    roll_button.disabled = busy or ko or cooldown
    rally_button.disabled = busy or ko or int(me.get("ralliesLeft",0)) <= 0 or int(me.get("rallyAt",0)) > now or focus < 2
    ultimate_button.disabled = busy or ko or int(me.get("ult",0)) < 100
    for b in spell_buttons:
        b.disabled = busy or ko or int(me.get("spell",0)) <= 0 or int(me.get("spellAt",0)) > now

func _cast_spell(spell: String) -> void:
    await _do_action("spell",{"spell":spell})

func _roll() -> void:
    selected_mult = mult_select.get_selected_id()
    await _do_action("roll",{"mult":selected_mult,"allIn":all_in.button_pressed})
    all_in.button_pressed = false

func _move_to(tower: int) -> void:
    if busy:
        return
    await _do_action("move",{"tower":tower})

func _do_action(kind: String, payload := {}) -> void:
    if busy or current_match_id.is_empty():
        return
    busy = true
    _paint_clock_and_controls()
    result_label.text = "Confirming %s with server…" % kind
    var response: Dictionary = await api.action(kind,current_match_id,payload)
    busy = false
    if not response.get("ok",false):
        if response.get("state",{}) is Dictionary and not response.get("state",{}).is_empty():
            _accept(response["state"])
        result_label.text = str(response.get("error","Action rejected"))
        _paint_clock_and_controls()
        return
    if response.has("state"):
        _accept(response["state"])
    var result: Dictionary = response.get("result",{})
    if kind == "roll":
        var effects: Dictionary = result.get("effects",{})
        result_label.text = "%s %s · dealt %d · absorbed %d · Focus +%d · shield +%d · gold +%d · XP +%d" % [
            str(result.get("tier","none")).capitalize(),FACE_NAMES.get(str(result.get("symbol","")),"MIXED"),
            int(result.get("dealt",0)),int(result.get("absorbed",0)),int(effects.get("focusGained",0)),
            int(effects.get("shieldAdded",0)),int(effects.get("goldAdded",0)),int(effects.get("xpAdded",0))]
    else:
        result_label.text = "%s confirmed by server." % kind.capitalize()
        if kind == "spell":
            spell_fx.play_spell(str(payload.get("spell","")),true)
        elif kind == "rally":
            spell_fx.play_spell("horn",true)
    _paint_clock_and_controls()

func _process_events(match: Dictionary) -> void:
    for event in match.get("events",[]):
        var seq := int(event.get("seq",0))
        if seq <= event_seq:
            continue
        event_seq = seq
        if str(event.get("type","")) == "spell":
            var actor_side := -1
            for hero in match.get("heroes",[]):
                if str(hero.get("id","")) == str(event.get("actor","")):
                    actor_side = int(hero.get("side",-1))
                    break
            var me := _me()
            spell_fx.play_spell(str(event.get("spell","")),actor_side == int(me.get("side",-2)))

func _show_result(state: Dictionary) -> void:
    active = false
    _clear_ui()
    _background()
    var center := CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    ui_root.add_child(center)
    var panel := PanelContainer.new()
    panel.custom_minimum_size = Vector2(350,470)
    panel.add_theme_stylebox_override("panel",_style(Color("#0d2633"),Color("#d7b66c"),18))
    center.add_child(panel)
    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation",12)
    panel.add_child(box)
    var r: Dictionary = state.get("result",{})
    var headline := "DRAW" if r.get("draw",false) else ("VICTORY" if r.get("win",false) else "DEFEAT")
    var title := _label(headline,30,Color("#f2d38a"))
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    box.add_child(title)
    var score: Array = r.get("score",[0,0])
    box.add_child(_label("Final crowns: %s — %s" % [score[0],score[1]],20))
    box.add_child(_label("The server remains authoritative. This result came from the existing Fatebound arena, not duplicated Godot combat logic.",12,Color("#9db7bd")))
    var shard := OptionButton.new()
    for key in ["steel","arcane","fletch"]:
        shard.add_item(key.capitalize())
        shard.set_item_metadata(shard.item_count-1,key)
    box.add_child(shard)
    var claim := _button("CLAIM REWARD")
    box.add_child(claim)
    var status := _label("",12,Color("#9fe5be"))
    box.add_child(status)
    claim.pressed.connect(func():
        claim.disabled = true
        var data: Dictionary = await api.claim(current_match_id,str(shard.get_item_metadata(shard.selected)))
        if data.get("ok",false):
            status.text = "Claimed: " + JSON.stringify(data.get("receipt",{}))
        else:
            status.text = str(data.get("error","Claim failed"))
            claim.disabled = false
    )
    var again := _button("QUEUE AGAIN")
    again.pressed.connect(_show_home)
    box.add_child(again)

