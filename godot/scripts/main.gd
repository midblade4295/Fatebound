extends Control
const Api = preload("res://scripts/arena_api.gd")
const Field = preload("res://scripts/battlefield.gd")
const Dice = preload("res://scripts/dice_strip.gd")
const Audio = preload("res://scripts/native_audio.gd")
const VisualTheme = preload("res://scripts/ui/visual_theme.gd")
const HexBackdrop = preload("res://scripts/ui/hex_backdrop.gd")

# A slow diagonal light sweep across the primary button while it is ready to press.
class Shimmer:
    extends Control
    var button: Button
    var app
    var t := 0.0
    func _process(delta: float) -> void:
        t += delta
        queue_redraw()
    func _draw() -> void:
        if button == null or button.disabled or (app != null and app.ui_reduce_motion):
            return
        var cycle := fmod(t, 2.8) / 1.1
        if cycle > 1.0:
            return
        var x := lerpf(size.y * 0.5 + 10, size.x - 10 - size.x * 0.12, cycle)
        var w := size.x * 0.12
        var pts := PackedVector2Array([Vector2(x, 4), Vector2(x + w, 4), Vector2(x + w - size.y * 0.45, size.y - 9), Vector2(x - size.y * 0.45, size.y - 9)])
        draw_colored_polygon(pts, Color(1, 1, 1, 0.14 * sin(cycle * PI)))
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
var score_meter: ProgressBar
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
var score_ours: Label
var score_theirs: Label
var roll_hint: Label
var ui_reduce_motion := false
var arena_space: Control
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
    if screen == "battle" and is_instance_valid(board) and is_instance_valid(arena_space) and is_instance_valid(dice):
        # The battlefield frames its fighters inside the gap between the HUD bars.
        var top: float = arena_space.get_global_rect().position.y-board.get_global_rect().position.y
        board.clear_zone = Rect2(0,top,board.size.x,arena_space.size.y+dice.size.y)
    if screen == "battle" and not latest.is_empty():
        _paint_controls()
    elif screen == "queue" and not latest_state.is_empty() and is_instance_valid(queue_clock):
        queue_clock.text = str(maxi(0,int(ceil((float(latest_state.get("deadline",0))-_server_now())/1000.0))))

func _server_now() -> float:
    return float(latest_state.get("serverNow",latest.get("now",0)))+minf(Time.get_ticks_msec()-received_ms,10000)

func _style(bg: Color, border := Color("#927d51"), radius := 12) -> StyleBoxFlat:
    return VisualTheme.panel(bg,border,radius,8)

func _label(text := "", fontsize := 14, color := Color("#e0e5df"), wrap := false) -> Label:
    var l := Label.new()
    l.text = text
    l.add_theme_font_size_override("font_size",fontsize)
    l.add_theme_color_override("font_color",color)
    l.add_theme_font_override("font",VisualTheme.BODY_FONT)
    l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
    l.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING if wrap else TextServer.OVERRUN_TRIM_ELLIPSIS
    l.clip_text = not wrap
    return l

func _button(text: String, height := 44) -> Button:
    var b := Button.new()
    b.text = text
    b.clip_text = true
    b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    b.custom_minimum_size = Vector2(0,height)
    b.add_theme_font_override("font",VisualTheme.BOLD_FONT)
    b.add_theme_font_size_override("font_size",15)
    VisualTheme.apply_tactile(b,"secondary",11)
    b.pressed.connect(func(): audio.play("tap"))
    _press_fx(b)
    return b

func _press_fx(b: Button) -> void:
    # Physical response: the face sinks into its lip (stylebox) and the whole control gives a small squash.
    b.resized.connect(func(): b.pivot_offset = b.size*0.5)
    b.button_down.connect(func(): _bump(b,0.955,0.07,false))
    b.button_up.connect(func(): _bump(b,1.0,0.28,true))

func _bump(b: Button, target: float, seconds: float, springy: bool) -> void:
    if not is_instance_valid(b):
        return
    if ui_reduce_motion:
        b.scale = Vector2.ONE
        return
    var tw := b.create_tween()
    tw.tween_property(b,"scale",Vector2.ONE*target,seconds).set_trans(Tween.TRANS_BACK if springy else Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _row(parent: Node) -> HBoxContainer:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation",6)
    parent.add_child(row)
    return row

func _new_screen(kind: String) -> void:
    if theme == null:
        theme = VisualTheme.install()
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
    bg.color = VisualTheme.INK
    bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    ui_root.add_child(bg)
    if kind != "battle":
        var scene := HexBackdrop.new()
        scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        ui_root.add_child(scene)
    margins = MarginContainer.new()
    margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    ui_root.add_child(margins)
    page = VBoxContainer.new()
    page.add_theme_constant_override("separation",7)
    margins.add_child(page)
    _safe_area()

func _safe_area() -> void:
    if not is_instance_valid(margins):
        return
    var inset := Vector4(10,8,10,8)
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
    if screen == "battle" and is_instance_valid(dice):
        var compact := size.y < 720
        roll_result.visible = not compact
        bank.visible = not compact
        status.visible = not compact
        dice.custom_minimum_size.y = 80 if compact else 112

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
    page.add_theme_constant_override("separation",6)
    # Full-screen battlefield: the 3D scene fills the whole screen behind a translucent HUD.
    board = Field.new()
    board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    ui_root.add_child(board)
    ui_root.move_child(board,1)
    margins.mouse_filter = Control.MOUSE_FILTER_IGNORE
    page.mouse_filter = Control.MOUSE_FILTER_IGNORE
    # --- scoreboard: our crowns, match clock, their crowns ---
    var header_frame := PanelContainer.new()
    header_frame.add_theme_stylebox_override("panel",VisualTheme.panel(Color(0.03,0.08,0.11,0.78),Color(0.75,0.6,0.35,0.55),14,6))
    page.add_child(header_frame)
    var header := _row(header_frame)
    var ours := VBoxContainer.new()
    ours.add_theme_constant_override("separation",-4)
    ours.custom_minimum_size.x = 92
    header.add_child(ours)
    var ours_tag := _label("YOUR SIDE",10,Color("#7fdcef"))
    ours_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    ours_tag.add_theme_font_override("font",VisualTheme.BOLD_FONT)
    ours.add_child(ours_tag)
    score_ours = _label("0♛",26,Color("#5fd4ea"))
    score_ours.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    score_ours.add_theme_font_override("font",VisualTheme.BOLD_FONT)
    ours.add_child(score_ours)
    var middle := VBoxContainer.new()
    middle.add_theme_constant_override("separation",-2)
    middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    header.add_child(middle)
    clock = _label("5:00",27,VisualTheme.TEXT)
    clock.add_theme_font_override("font",VisualTheme.BOLD_FONT)
    clock.add_theme_color_override("font_outline_color",Color(0,0,0,0.6))
    clock.add_theme_constant_override("outline_size",4)
    middle.add_child(clock)
    score = _label("0  —  0",11,VisualTheme.GOLD)
    score.add_theme_font_override("font",VisualTheme.BOLD_FONT)
    middle.add_child(score)
    score.visible = false
    var theirs := VBoxContainer.new()
    theirs.add_theme_constant_override("separation",-4)
    theirs.custom_minimum_size.x = 92
    header.add_child(theirs)
    var theirs_tag := _label("ENEMY",10,Color("#ff9d6a"))
    theirs_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    theirs_tag.add_theme_font_override("font",VisualTheme.BOLD_FONT)
    theirs.add_child(theirs_tag)
    score_theirs = _label("0♛",26,Color("#ff8a4a"))
    score_theirs.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    score_theirs.add_theme_font_override("font",VisualTheme.BOLD_FONT)
    theirs.add_child(score_theirs)
    score_meter = ProgressBar.new()
    score_meter.custom_minimum_size.y = 6
    score_meter.show_percentage = false
    score_meter.value = 50
    score_meter.add_theme_stylebox_override("background",VisualTheme.panel(Color("#d0643a"),Color.TRANSPARENT,4,0))
    score_meter.add_theme_stylebox_override("fill",VisualTheme.panel(Color("#4fcde6"),Color.TRANSPARENT,4,0))
    page.add_child(score_meter)
    # --- tower strip: which tower, and a tap target for the war map ---
    var tower_row := _row(page)
    tower_title = _button("◀ MAP   ·   TOWER I",38)
    tower_title.add_theme_font_size_override("font_size",14)
    tower_title.pressed.connect(_tower_map)
    tower_row.add_child(tower_title)
    var menu := _button("•••",38)
    menu.name = "battle_more"
    menu.size_flags_horizontal = Control.SIZE_FILL
    menu.custom_minimum_size.x = 58
    menu.pressed.connect(_more)
    tower_row.add_child(menu)
    # --- open window onto the battlefield, with the dice tray standing on its lower edge ---
    arena_space = Control.new()
    arena_space.size_flags_vertical = Control.SIZE_EXPAND_FILL
    arena_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
    page.add_child(arena_space)
    dice = Dice.new()
    dice.custom_minimum_size.y = 112
    dice.mouse_filter = Control.MOUSE_FILTER_IGNORE
    page.add_child(dice)
    # --- action deck ---
    var action_frame := PanelContainer.new()
    action_frame.add_theme_stylebox_override("panel",VisualTheme.panel(Color(0.03,0.08,0.11,0.82),Color(0.75,0.6,0.35,0.55),16,7))
    page.add_child(action_frame)
    var actions := VBoxContainer.new()
    actions.add_theme_constant_override("separation",6)
    action_frame.add_child(actions)
    var result_frame := PanelContainer.new()
    result_frame.add_theme_stylebox_override("panel",VisualTheme.panel(Color(0.02,0.05,0.07,0.7),Color("#26404c"),9,6))
    actions.add_child(result_frame)
    var result_box := VBoxContainer.new()
    result_box.add_theme_constant_override("separation",1)
    result_frame.add_child(result_box)
    roll_result = _label("Roll to attack, defend and support your team.",12,Color("#e9f4f1"),true)
    roll_result.custom_minimum_size.y = 18
    result_box.add_child(roll_result)
    var meta := _row(result_box)
    focus = _label("FOCUS 8/8",11,Color("#ffd97a"))
    focus.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    focus.add_theme_font_override("font",VisualTheme.BOLD_FONT)
    meta.add_child(focus)
    bank = _label("Banked · 0 gold · 0 XP",10,Color("#8fb3ba"))
    bank.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    meta.add_child(bank)
    var rolls := _row(actions)
    rolls.add_theme_constant_override("separation",7)
    mult_select = OptionButton.new()
    mult_select.fit_to_longest_item = false
    mult_select.clip_text = true
    mult_select.custom_minimum_size = Vector2(70,62)
    mult_select.add_theme_font_override("font",VisualTheme.BOLD_FONT)
    mult_select.add_theme_font_size_override("font_size",18)
    for state in ["normal","hover","pressed","disabled"]:
        mult_select.add_theme_stylebox_override(state,VisualTheme.tactile("secondary",state,12))
    mult_select.add_theme_stylebox_override("focus",StyleBoxEmpty.new())
    for i in [1,2,3,4]:
        mult_select.add_item("×%d"%i,i)
    rolls.add_child(mult_select)
    roll_button = _button("ROLL",62)
    VisualTheme.apply_tactile(roll_button,"primary",14)
    roll_button.add_theme_font_override("font",VisualTheme.BOLD_FONT)
    roll_button.add_theme_font_size_override("font_size",27)
    for state in ["normal","hover","pressed","disabled"]:
        var sb: StyleBox = roll_button.get_theme_stylebox(state)
        sb.content_margin_bottom += 12
    roll_button.pressed.connect(_roll)
    rolls.add_child(roll_button)
    roll_hint = _label("1 Focus · hold for AutoRoll",10,Color("#fff1d8"))
    roll_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
    roll_hint.anchor_left = 0.0
    roll_hint.anchor_right = 1.0
    roll_hint.anchor_top = 1.0
    roll_hint.anchor_bottom = 1.0
    roll_hint.offset_top = -24
    roll_hint.offset_bottom = -9
    roll_hint.add_theme_color_override("font_outline_color",Color(0.35,0.1,0,0.6))
    roll_hint.add_theme_constant_override("outline_size",3)
    roll_button.add_child(roll_hint)
    var shine := Shimmer.new()
    shine.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
    shine.button = roll_button
    shine.app = self
    roll_button.add_child(shine)
    rally_button = _button("RALLY",62)
    rally_button.size_flags_horizontal = Control.SIZE_FILL
    rally_button.custom_minimum_size.x = 86
    rally_button.pressed.connect(func(): _do_action("rally"))
    rolls.add_child(rally_button)
    # One compact row: both spells, ALL-IN and the ultimate.
    var powers := _row(actions)
    powers.add_theme_constant_override("separation",5)
    for spell in selected_loadout:
        var b := _button(SPELL_NAMES.get(spell,spell),44)
        b.add_theme_font_size_override("font_size",13)
        VisualTheme.apply_tactile(b,"arcane",11)
        b.set_meta("spell",spell)
        b.pressed.connect(_cast.bind(spell))
        powers.add_child(b)
        spell_buttons.append(b)
    var utility := powers
    all_in = _button("ALL-IN",44)
    all_in.add_theme_font_size_override("font_size",13)
    all_in.toggle_mode = true
    all_in.toggled.connect(func(on):
        all_in.text = "ALL-IN ON" if on else "ALL-IN"
        VisualTheme.apply_tactile(all_in,"active" if on else "secondary",11))
    utility.add_child(all_in)
    ult_button = _button("ULT 0%",44)
    ult_button.add_theme_font_size_override("font_size",13)
    ult_button.pressed.connect(func(): _do_action("ultimate"))
    utility.add_child(ult_button)
    status = _label("LIVE · 20 combatants",10,Color("#88a7ad"))
    actions.add_child(status)
    _safe_area()

func _update_battle(data: Dictionary, earnings: Variant = {}) -> void:
    if screen != "battle":
        return
    board.accept_state(data,api.player_id)
    var me := _me()
    var crowns: Array = data.get("score",[0,0])
    var side := int(me.get("side",0))
    score.text = "YOU %d  ·  %d ENEMY" % [int(crowns[side]),int(crowns[1-side])]
    if is_instance_valid(score_ours):
        score_ours.text = "%d♛" % int(crowns[side])
        score_theirs.text = "%d♛" % int(crowns[1-side])
    var total := int(crowns[side])+int(crowns[1-side])
    if is_instance_valid(score_meter):
        score_meter.value = 50.0 if total <= 0 else 100.0*float(crowns[side])/float(total)
    var tower_i := int(me.get("tower",0))
    var pts := 3 if tower_i >= 8 else (2 if tower_i >= 5 else 1)
    tower_title.text = "◀ MAP   ·   TOWER %s  ·  %d♛" % [ROMAN[tower_i],pts]
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
    ult_button.text = "ULT %d%%" % int(me.get("ult",0))
    # Keep the ALL-IN face in step even when code resets it without a toggle signal.
    if bool(all_in.get_meta("on",false)) != all_in.button_pressed:
        all_in.set_meta("on",all_in.button_pressed)
        VisualTheme.apply_tactile(all_in,"active" if all_in.button_pressed else "secondary",11)
        all_in.text = "ALL-IN ON" if all_in.button_pressed else "ALL-IN"
    if is_instance_valid(roll_hint):
        roll_hint.text = ("FREE · Rampage" if free else ("%d Focus · ALL-IN" % cost if all_in.button_pressed else "%d Focus · hold for AutoRoll" % cost))
        roll_hint.visible = not ko and not busy
    var ult_ready := int(me.get("ult",0)) >= 100
    if ult_button.get_meta("ready",false) != ult_ready:
        ult_button.set_meta("ready",ult_ready)
        VisualTheme.apply_tactile(ult_button,"arcane" if ult_ready else "secondary",11)
    ult_button.disabled = locked or int(me.get("ult",0)) < 100
    mult_select.disabled = locked or free
    if free:
        mult_select.select(0)
        all_in.set_pressed_no_signal(false)
        all_in.text = "ALL-IN"
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
        all_in.text = "ALL-IN"

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
