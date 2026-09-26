extends Control
const Api = preload("res://scripts/arena_api.gd")
const Field = preload("res://scripts/battlefield.gd")
const Dice = preload("res://scripts/dice_strip.gd")
const Audio = preload("res://scripts/native_audio.gd")
const SPELLS := ["barrage","bulwark","horn","surge"]
const SPELL_NAMES := {"barrage":"Barrage","bulwark":"Bulwark","horn":"War Horn","surge":"Arcane Surge"}
const HERO_NAMES := ["Knight","Rogue","Barbarian","Mage","Ranger"]
const ROMAN := ["I","II","III","IV","V","VI","VII","VIII","IX","X"]
var api
var audio
var poll_timer: Timer
var ui_root: Control
var page: VBoxContainer
var margins: MarginContainer
var board
var dice
var screen := "home"
var latest: Dictionary = {}
var latest_state: Dictionary = {}
var current_match_id := ""
var selected_loadout: Array = ["barrage","bulwark"]
var selected_char := 0
var selected_weapon := 0
var busy := false
var joining := false
var polling := false
var epoch := 0
var received_ms := 0
var event_seq := 0
var clock: Label
var score: Label
var status: Label
var roll_result: Label
var bank: Label
var focus: Label
var roll_button: Button
var rally_button: Button
var ult_button: Button
var stored_button: Button
var spell_buttons: Array[Button] = []
var mult_select: OptionButton
var all_in: Button
var queue_clock: Label
var queue_status: Label
var tower_title: Button
var modal: Control
var notice_until := 0
var home_preview

func _ready() -> void:
    api = Api.new()
    add_child(api)
    audio = Audio.new()
    add_child(audio)
    poll_timer = Timer.new()
    poll_timer.wait_time = 0.75
    poll_timer.timeout.connect(_poll)
    add_child(poll_timer)
    get_tree().auto_accept_quit = false
    resized.connect(_safe_area)
    _show_home()

func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_GO_BACK_REQUEST:
        if is_instance_valid(modal):
            modal.queue_free()
            modal = null
        elif screen == "battle":
            _notice("Finish this battle before leaving.")
        elif screen == "queue":
            _cancel_queue()

func _process(_delta: float) -> void:
    if screen == "battle" and not latest.is_empty():
        _paint_controls()
    elif screen == "queue" and not latest_state.is_empty() and is_instance_valid(queue_clock):
        queue_clock.text = str(maxi(0,int(ceil((float(latest_state.get("deadline",0))-_server_now())/1000.0))))

func _server_now() -> float:
    return float(latest_state.get("serverNow",latest.get("now",0)))+minf(Time.get_ticks_msec()-received_ms,10000)

func _style(bg: Color, border := Color("#927d51"), radius := 12) -> StyleBoxFlat:
    var s := StyleBoxFlat.new()
    s.bg_color = bg
    s.border_color = border
    s.set_border_width_all(1)
    s.set_corner_radius_all(radius)
    s.content_margin_left = 10
    s.content_margin_right = 10
    s.content_margin_top = 6
    s.content_margin_bottom = 6
    return s

func _label(text := "", fontsize := 14, color := Color("#e0e5df"), wrap := false) -> Label:
    var l := Label.new()
    l.text = text
    l.add_theme_font_size_override("font_size",fontsize)
    l.add_theme_color_override("font_color",color)
    l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
    l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    l.clip_text = not wrap
    return l

func _button(text: String, height := 44) -> Button:
    var b := Button.new()
    b.text = text
    b.clip_text = true
    b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    b.custom_minimum_size = Vector2(0,height)
    b.add_theme_font_size_override("font_size",15)
    b.add_theme_color_override("font_color",Color("#f3d999"))
    b.add_theme_stylebox_override("normal",_style(Color("#16333d")))
    b.add_theme_stylebox_override("hover",_style(Color("#245363"),Color("#f4dcaa")))
    b.add_theme_stylebox_override("pressed",_style(Color("#17615d"),Color("#84e6d9")))
    b.add_theme_stylebox_override("disabled",_style(Color("#142a30"),Color("#415e63")))
    b.pressed.connect(func(): audio.play("tap"))
    return b

func _row(parent: Node) -> HBoxContainer:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation",6)
    parent.add_child(row)
    return row

func _new_screen(kind: String) -> void:
    epoch += 1
    screen = kind
    modal = null
    board = null
    dice = null
    spell_buttons.clear()
    if is_instance_valid(ui_root):
        ui_root.queue_free()
    ui_root = Control.new()
    ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(ui_root)
    var bg := ColorRect.new()
    bg.color = Color("#071923")
    bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    ui_root.add_child(bg)
    margins = MarginContainer.new()
    margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    ui_root.add_child(margins)
    page = VBoxContainer.new()
    page.add_theme_constant_override("separation",6)
    margins.add_child(page)
    _safe_area()

func _safe_area() -> void:
    if not is_instance_valid(margins):
        return
    var inset := Vector4(8,8,8,8)
    if OS.get_name() in ["Android","iOS"]:
        var safe := DisplayServer.get_display_safe_area()
        var physical := DisplayServer.screen_get_size()
        if physical.x > 0 and physical.y > 0 and safe.size.x > 0:
            var scale := get_viewport_rect().size/Vector2(physical)
            inset = Vector4(maxf(8,safe.position.x*scale.x),maxf(8,safe.position.y*scale.y),maxf(8,(physical.x-safe.end.x)*scale.x),maxf(8,(physical.y-safe.end.y)*scale.y))
    margins.add_theme_constant_override("margin_left",int(inset.x))
    margins.add_theme_constant_override("margin_top",int(inset.y))
    margins.add_theme_constant_override("margin_right",int(inset.z))
    margins.add_theme_constant_override("margin_bottom",int(inset.w))

func _show_home() -> void:
    busy = false
    joining = false
    poll_timer.stop()
    _new_screen("home")
    page.add_child(_label("FATEBOUND",32,Color("#f3d693")))
    page.add_child(_label("NATIVE PREVIEW 0.2 · ORIGINAL BATTLE ART",11,Color("#8de0d5")))
    home_preview = Field.new()
    home_preview.preview = true
    home_preview.preview_char = selected_char
    home_preview.preview_weapon = selected_weapon
    home_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
    page.add_child(home_preview)
    var hero_choice := OptionButton.new()
    hero_choice.fit_to_longest_item = false
    hero_choice.clip_text = true
    hero_choice.custom_minimum_size.y = 44
    for n in HERO_NAMES:
        hero_choice.add_item(n)
    hero_choice.selected = selected_char
    hero_choice.item_selected.connect(func(index):
        selected_char = index
        selected_weapon = [0,1,4,5,7][index]
        home_preview.preview_char = selected_char
        home_preview.preview_weapon = selected_weapon
        audio.play("equip")
    )
    page.add_child(hero_choice)
    var edit := LineEdit.new()
    edit.text = "Godot Player"
    edit.placeholder_text = "Player name"
    edit.max_length = 24
    edit.custom_minimum_size.y = 44
    page.add_child(edit)
    var choices := _row(page)
    var pickers: Array[OptionButton] = []
    for slot in 2:
        var picker := OptionButton.new()
        picker.fit_to_longest_item = false
        picker.clip_text = true
        picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        picker.custom_minimum_size.y = 44
        for spell in SPELLS:
            picker.add_item(SPELL_NAMES[spell])
        picker.select(maxi(0,SPELLS.find(selected_loadout[slot])))
        pickers.append(picker)
        choices.add_child(picker)
    var start := _button("FIND 20-PLAYER BATTLE",54)
    start.pressed.connect(func():
        selected_loadout = [SPELLS[pickers[0].selected],SPELLS[pickers[1].selected]]
        _start_queue(edit.text)
    )
    page.add_child(start)
    status = _label("5-minute battles · 20-second search · bots fill empty slots",12,Color("#b0c8c8"),true)
    status.custom_minimum_size.y = 32
    page.add_child(status)
    var lower := _row(page)
    var sound := _button("Sound on" if not audio.muted else "Sound off")
    sound.pressed.connect(func():
        audio.toggle()
        sound.text = "Sound off" if audio.muted else "Sound on"
        audio.play("menuOpen")
    )
    lower.add_child(sound)
    var note := _label("Separate test profile. Home, guilds, shop and raids are not migrated yet.",10,Color("#92a9ae"),true)
    page.add_child(note)

func _start_queue(display_name: String) -> void:
    if joining or screen != "home":
        return
    if selected_loadout[0] == selected_loadout[1]:
        status.text = "Choose two different spells."
        return
    joining = true
    status.text = "Connecting…"
    var generation := epoch
    var session: Dictionary = await api.ensure_session(display_name.strip_edges() if not display_name.strip_edges().is_empty() else "Godot Player")
    if generation != epoch:
        return
    if not session.get("ok",false):
        joining = false
        status.text = str(session.get("error","Connection failed"))
        return
    var state: Dictionary = await api.queue(selected_char,selected_weapon,selected_loadout)
    if generation != epoch:
        return
    joining = false
    if not state.get("ok",false):
        status.text = str(state.get("error","Queue unavailable"))
        return
    _show_queue()
    _accept(state)
    poll_timer.start()

func _show_queue() -> void:
    _new_screen("queue")
    page.add_spacer(false)
    page.add_child(_label("FINDING YOUR BATTLE",25,Color("#f3d693")))
    queue_clock = _label("20",68,Color("#81e3d4"))
    page.add_child(queue_clock)
    queue_status = _label("Searching for players",16)
    page.add_child(queue_status)
    page.add_child(_label("10 versus 10\nBots join only after the 20-second deadline.",14,Color("#b9cece"),true))
    var cancel := _button("CANCEL SEARCH")
    cancel.pressed.connect(_cancel_queue)
    page.add_child(cancel)
    page.add_spacer(false)

func _cancel_queue() -> void:
    if busy or screen != "queue":
        return
    busy = true
    var state: Dictionary = await api.cancel()
    busy = false
    if state.get("ok",false):
        _accept(state)
    elif is_instance_valid(queue_status):
        queue_status.text = "Cancel not confirmed. Retrying connection…"

func _poll() -> void:
    if polling or not screen in ["battle","queue"]:
        return
    polling = true
    var generation := epoch
    var state: Dictionary = await api.state()
    polling = false
    if generation != epoch:
        return
    if state.get("ok",false):
        _accept(state)
    elif screen == "battle":
        _notice("Reconnecting · waiting for server")

func _accept(state: Dictionary) -> void:
    var mode := str(state.get("status",""))
    var data: Dictionary = state.get("match",{})
    if not data.is_empty() and str(data.get("id","")) == current_match_id and int(data.get("revision",0)) < int(latest.get("revision",0)):
        return
    latest_state = state
    received_ms = Time.get_ticks_msec()
    if mode == "idle":
        _show_home()
        return
    if mode == "searching":
        if screen != "queue":
            _show_queue()
        queue_status.text = "%d / 20 human players" % int(state.get("humans",0))
        return
    if not mode in ["battle","complete"] or data.is_empty():
        return
    var new_room := str(data.get("id","")) != current_match_id
    if new_room:
        event_seq = int(data.get("seq",0))
        current_match_id = str(data.get("id",""))
    latest = data
    if mode == "complete":
        if screen != "result":
            _show_result(state)
        return
    if screen != "battle":
        var me := _me()
        selected_loadout = me.get("loadout",selected_loadout).duplicate()
        _show_battle()
    _update_battle(data,state.get("earnings",{}))

func _me() -> Dictionary:
    for hero in latest.get("heroes",[]):
        if str(hero.get("id","")) == api.player_id:
            return hero
    return {}

func _show_battle() -> void:
    _new_screen("battle")
    var header := _row(page)
    score = _label("0 — 0",22,Color("#f3d693"))
    header.add_child(score)
    clock = _label("5:00",25,Color.WHITE)
    header.add_child(clock)
    var menu := _button("MORE",40)
    menu.size_flags_stretch_ratio = 0.65
    menu.pressed.connect(_more)
    header.add_child(menu)
    tower_title = _button("TOWER I · CHANGE TOWER",38)
    tower_title.pressed.connect(_tower_map)
    page.add_child(tower_title)
    board = Field.new()
    board.size_flags_vertical = Control.SIZE_EXPAND_FILL
    page.add_child(board)
    dice = Dice.new()
    dice.custom_minimum_size.y = 92
    page.add_child(dice)
    roll_result = _label("Roll to attack, defend and support your team.",12,Color("#ecdbb5"),true)
    roll_result.custom_minimum_size.y = 32
    page.add_child(roll_result)
    bank = _label("Banked this match · 0 gold · 0 XP",11,Color("#9bc7cf"))
    page.add_child(bank)
    focus = _label("FOCUS 8/8",12,Color("#f6d58c"))
    page.add_child(focus)
    var rolls := _row(page)
    mult_select = OptionButton.new()
    mult_select.fit_to_longest_item = false
    mult_select.clip_text = true
    mult_select.custom_minimum_size = Vector2(60,50)
    for i in [1,2,3,4]:
        mult_select.add_item("×%d"%i,i)
    rolls.add_child(mult_select)
    roll_button = _button("ROLL",54)
    roll_button.add_theme_font_size_override("font_size",23)
    roll_button.add_theme_stylebox_override("normal",_style(Color("#ba6222"),Color("#ffde96")))
    roll_button.pressed.connect(_roll)
    rolls.add_child(roll_button)
    rally_button = _button("RALLY",54)
    rally_button.size_flags_horizontal = Control.SIZE_FILL
    rally_button.custom_minimum_size.x = 76
    rally_button.pressed.connect(func(): _do_action("rally"))
    rolls.add_child(rally_button)
    var powers := _row(page)
    for spell in selected_loadout:
        var b := _button(SPELL_NAMES.get(spell,spell),44)
        b.set_meta("spell",spell)
        b.pressed.connect(_cast.bind(spell))
        powers.add_child(b)
        spell_buttons.append(b)
    var utility := _row(page)
    all_in = _button("ALL-IN OFF",40)
    all_in.toggle_mode = true
    all_in.toggled.connect(func(on): all_in.text = "ALL-IN ON" if on else "ALL-IN OFF")
    utility.add_child(all_in)
    ult_button = _button("ULTIMATE 0%",40)
    ult_button.pressed.connect(func(): _do_action("ultimate"))
    utility.add_child(ult_button)
    status = _label("LIVE · 20 combatants",10,Color("#9ebeb9"))
    page.add_child(status)

func _update_battle(data: Dictionary, earnings: Variant = {}) -> void:
    if screen != "battle":
        return
    board.accept_state(data,api.player_id)
    var me := _me()
    var crowns: Array = data.get("score",[0,0])
    var side := int(me.get("side",0))
    score.text = "%d — %d" % [int(crowns[side]),int(crowns[1-side])]
    tower_title.text = "TOWER %s · CHANGE TOWER" % ROMAN[int(me.get("tower",0))]
    if not busy:
        dice.set_faces(me.get("lastFaces",[]))
    if earnings is Dictionary:
        bank.text = "Banked this match · %d gold · %d XP" % [int(earnings.get("gold",0)),int(earnings.get("xp",0))]
    _events(data)
    _paint_controls()

func _paint_controls() -> void:
    if screen != "battle" or not is_instance_valid(roll_button):
        return
    var me := _me()
    var now := _server_now()
    var remain := maxi(0,int(ceil((float(latest.get("endAt",now))-now)/1000.0)))
    clock.text = "%d:%02d" % [remain/60,remain%60]
    var ko := int(me.get("hp",0)) <= 0
    var stale := Time.get_ticks_msec()-received_ms > 4000
    var wait := maxi(0,int(ceil((float(me.get("downUntil",0))-now)/1000.0)))
    var energy := int(me.get("focus",0))
    var mult := mult_select.get_selected_id()
    var free := int(me.get("rampage",0)) > 0
    var cost := 0 if free else (mini(8,energy) if all_in.button_pressed else mult)
    focus.text = "FOCUS %d/8 · SPELLS %d/2" % [energy,int(me.get("spell",0))]
    var locked := busy or ko or stale or me.is_empty()
    roll_button.text = "WAITING…" if busy else ("KO %ds"%wait if ko and wait > 0 else ("RESPAWNING…" if ko else "ROLL"))
    roll_button.disabled = locked or float(me.get("rollAt",0)) > now or (not free and (energy < cost or cost <= 0))
    tower_title.disabled = locked
    rally_button.disabled = locked or int(me.get("ralliesLeft",0)) <= 0 or float(me.get("rallyAt",0)) > now or energy < 2
    ult_button.text = "ULTIMATE %d%%" % int(me.get("ult",0))
    ult_button.disabled = locked or int(me.get("ult",0)) < 100
    mult_select.disabled = locked or free
    if free:
        mult_select.select(0)
        all_in.set_pressed_no_signal(false)
        all_in.text = "ALL-IN OFF"
    all_in.disabled = locked or free or energy == 0
    for b in spell_buttons:
        b.disabled = locked or int(me.get("spell",0)) <= 0 or float(me.get("spellAt",0)) > now
        if str(b.get_meta("spell")) == "horn":
            b.disabled = b.disabled or int(me.get("ralliesLeft",0)) <= 0 or float(me.get("rallyAt",0)) > now
    if stale:
        status.text = "Reconnecting · waiting for fresh server state"
    elif Time.get_ticks_msec() > notice_until:
        var humans := 0
        for h in latest.get("heroes",[]):
            if not h.get("bot",true):
                humans += 1
        status.text = "LIVE · %d humans · %d bots · Compressed sync" % [humans,20-humans]

func _notice(text: String) -> void:
    if is_instance_valid(status):
        status.text = text
        notice_until = Time.get_ticks_msec()+3500

func _roll() -> void:
    if roll_button.disabled:
        return
    dice.start_roll()
    audio.play("roll")
    await _do_action("roll",{"mult":mult_select.get_selected_id(),"allIn":all_in.button_pressed})
    if screen == "battle" and is_instance_valid(all_in):
        all_in.set_pressed_no_signal(false)
        all_in.text = "ALL-IN OFF"

func _cast(spell: String) -> void:
    await _do_action("spell",{"spell":spell})

func _do_action(kind: String, payload := {}) -> void:
    if busy or screen != "battle":
        return
    busy = true
    var generation := epoch
    var room := current_match_id
    _paint_controls()
    var answer: Dictionary = await api.action(kind,room,payload)
    if epoch != generation or current_match_id != room:
        busy = false
        return
    busy = false
    if not (answer.get("state",{}) as Dictionary).is_empty():
        _accept(answer.state)
    if screen != "battle":
        return
    dice.pending = false
    dice.set_faces(_me().get("lastFaces",[]))
    if not answer.get("ok",false):
        _notice(str(answer.get("error","Action not confirmed")))
        return
    var result: Dictionary = answer.get("result",{})
    if kind == "roll":
        var effects: Dictionary = result.get("effects",{})
        var messages: Array[String] = []
        if int(result.get("dealt",0)) > 0:
            messages.append("%d damage" % int(result.dealt))
        if int(result.get("absorbed",0)) > 0:
            messages.append("%d blocked" % int(result.absorbed))
        for spec in [["shieldAdded","shield"],["focusGained","Focus"],["goldAdded","gold"],["xpAdded","XP"],["giftAdded","gift power"]]:
            var n := int(effects.get(spec[0],0))
            if n > 0:
                messages.append("+%d %s"%[n,spec[1]])
        roll_result.text = " · ".join(messages) if not messages.is_empty() else "Roll confirmed · current bonuses and caps preserved"
        audio.play("land")
    else:
        _notice(kind.capitalize()+" confirmed")
    _paint_controls()

func _events(data: Dictionary) -> void:
    for event in data.get("events",[]):
        var seq := int(event.get("seq",0))
        if seq <= event_seq:
            continue
        event_seq = seq
        if float(data.get("now",0))-float(event.get("at",0)) > 1800:
            continue
        if int(event.get("tower",_me().get("tower",0))) != int(_me().get("tower",0)):
            continue
        board.confirm_event(event)
        var kind := str(event.get("type",""))
        var own: bool = str(event.get("actor","")) == api.player_id
        if kind == "roll":
            if int(event.get("dealt",0)) > 0:
                audio.play("crit" if event.get("symbol","") == "C" else "hit",not own)
            elif event.get("symbol","") == "H":
                audio.play("shield",not own)
        elif kind == "spell":
            audio.play(str(event.get("spell","barrage")),not own)
        elif kind == "rally":
            audio.play("horn",not own)

func _popup(title: String) -> VBoxContainer:
    if is_instance_valid(modal):
        modal.queue_free()
    modal = Control.new()
    modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    ui_root.add_child(modal)
    var shade := ColorRect.new()
    shade.color = Color(0,0,0,0.7)
    shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    modal.add_child(shade)
    var safe := MarginContainer.new()
    safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    for edge in ["left","right","top","bottom"]:
        safe.add_theme_constant_override("margin_"+edge,22)
    modal.add_child(safe)
    var panel := PanelContainer.new()
    panel.add_theme_stylebox_override("panel",_style(Color("#10232e"),Color("#c7ac6a"),16))
    safe.add_child(panel)
    var scroll := ScrollContainer.new()
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    panel.add_child(scroll)
    var box := VBoxContainer.new()
    box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    box.add_theme_constant_override("separation",9)
    scroll.add_child(box)
    var heading := _row(box)
    heading.add_child(_label(title,21,Color("#f4d48c")))
    var close := _button("CLOSE",42)
    close.size_flags_horizontal = Control.SIZE_FILL
    close.custom_minimum_size.x = 80
    close.pressed.connect(func():
        if is_instance_valid(modal):
            modal.queue_free()
            modal = null
    )
    heading.add_child(close)
    audio.play("menuOpen")
    return box

func _tower_map() -> void:
    var box := _popup("CHOOSE A TOWER")
    box.add_child(_label("Tap a tower to move. Scrolling does not move your hero.",12,Color("#acc8cb"),true))
    var grid := GridContainer.new()
    grid.columns = 2
    grid.add_theme_constant_override("h_separation",8)
    grid.add_theme_constant_override("v_separation",8)
    box.add_child(grid)
    var now := _server_now()
    for i in 10:
        var tower: Dictionary = latest.get("towers",[])[i]
        var b := _button("TOWER "+ROMAN[i]+" · "+str(int(tower.get("pts",0)))+" crowns",62)
        b.disabled = i == int(_me().get("tower",0)) or busy or float(_me().get("moveAt",0)) > now or int(_me().get("hp",0)) <= 0
        b.pressed.connect(_move_to.bind(i))
        grid.add_child(b)

func _move_to(tower: int) -> void:
    if is_instance_valid(modal):
        modal.queue_free()
        modal = null
    await _do_action("move",{"tower":tower})

func _more() -> void:
    var box := _popup("BATTLE MENU")
    var sound := _button("Sound off" if audio.muted else "Sound on")
    sound.pressed.connect(func():
        audio.toggle()
        sound.text = "Sound off" if audio.muted else "Sound on"
        audio.play("menuOpen")
    )
    box.add_child(sound)
    var stored := _button("USE STORED ATTACK · %d power" % int(_me().get("storedDamage",0)))
    stored.disabled = int(_me().get("storedDamage",0)) <= 0 or busy or int(_me().get("hp",0)) <= 0
    stored.pressed.connect(func():
        modal.queue_free()
        modal = null
        _do_action("stored")
    )
    box.add_child(stored)
    box.add_child(_label("Gift power ready: %d · choose a teammate" % int(_me().get("giftDamage",0)),12,Color("#efdda1"),true))
    for hero in latest.get("heroes",[]):
        if int(hero.get("side",-1)) != int(_me().get("side",0)) or str(hero.id) == api.player_id:
            continue
        var send := _button("SEND TO "+str(hero.get("name","Teammate")))
        send.disabled = int(_me().get("giftDamage",0)) <= 0 or busy or int(_me().get("hp",0)) <= 0
        send.pressed.connect(_send_gift.bind(str(hero.id)))
        box.add_child(send)
    box.add_child(_label("Preview 0.2 · transport 2\n%d full + %d changed-state responses\n%.1f KB decoded JSON (not carrier data)" % [api.wire.stats.full,api.wire.stats.delta,float(api.bytes_received)/1024.0],11,Color("#8daeb4"),true))

func _send_gift(target: String) -> void:
    if is_instance_valid(modal):
        modal.queue_free()
        modal = null
    await _do_action("gift",{"target":target})

func _show_result(state: Dictionary) -> void:
    poll_timer.stop()
    busy = false
    _new_screen("result")
    var result: Dictionary = state.get("result",{})
    page.add_spacer(false)
    page.add_child(_label("DRAW" if result.get("draw",false) else ("VICTORY" if result.get("win",false) else "DEFEAT"),32,Color("#f1d491")))
    var crowns: Array = result.get("score",[0,0])
    page.add_child(_label("Final crowns · %d — %d" % [int(crowns[0]),int(crowns[1])],22))
    var reward: Dictionary = result.get("reward",{})
    page.add_child(_label("%d gold · %d XP" % [int(reward.get("gold",0)),int(reward.get("xp",0))],18,Color("#9de4ce")))
    var choice := OptionButton.new()
    choice.fit_to_longest_item = false
    choice.custom_minimum_size.y = 44
    for label in ["Steel shards","Arcane shards","Fletch shards"]:
        choice.add_item(label)
    page.add_child(choice)
    status = _label("Rewards belong to this separate preview profile.",12,Color("#abc6c9"),true)
    page.add_child(status)
    var claim := _button("CLAIM REWARD",52)
    var again := _button("PLAY AGAIN",48)
    again.disabled = true
    claim.pressed.connect(func():
        if claim.disabled:
            return
        claim.disabled = true
        var answer: Dictionary = await api.claim(current_match_id,["steel","arcane","fletch"][choice.selected])
        if not is_instance_valid(claim):
            return
        if answer.get("ok",false):
            status.text = "Rewards claimed. Ready for your next battle."
            claim.text = "CLAIMED"
            again.disabled = false
            audio.play("reward")
        else:
            status.text = str(answer.get("error","Claim not confirmed. Retry safely."))
            claim.disabled = false
    )
    again.pressed.connect(_show_home)
    page.add_child(claim)
    page.add_child(again)
    page.add_spacer(false)
