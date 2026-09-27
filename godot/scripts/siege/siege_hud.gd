extends Control
# Siege HUD. The stick and the combat buttons are drawn and hit-tested by hand from raw
# InputEventScreenTouch events, because Godot's Buttons only follow the first finger and on a
# phone you hold the stick while tapping ATTACK. Modal panels (forge, pause, result) use Buttons.
const VisualTheme = preload("res://scripts/ui/visual_theme.gd")
const Sim = preload("res://scripts/siege/siege_sim.gd")

signal leave_requested
signal replay_requested
signal forge_roll(held: Array)
signal forge_take
signal forge_leave
signal action_pressed(kind: String)
signal fps_toggled

const TEAM_COLORS := [Color("#5fd2f0"), Color("#ff7b52")]
const FACE_LABEL := {"knight":"KNIGHT","barbarian":"BARB","rogue":"ROGUE","ranger":"RANGER","mage":"MAGE","fate":"FATE ✦"}
const FACE_COLOR := {"knight":Color("#9fb6c8"),"barbarian":Color("#e0875a"),"rogue":Color("#8fd18a"),"ranger":Color("#d9c36a"),"mage":Color("#b28cff"),"fate":Color("#ffd46a")}

var sim
var diag
var _bar_style: StyleBox
var player_id := "you"
var project: Callable          # world Vector3 -> HUD Vector2
var on_screen: Callable        # world Vector3 -> bool

var _touchscreen := false
var _touches := {}             # index -> role
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _stick_active := false
var _attack_held := false
var _pressed_at := {}
var _toast := ""
var _toast_at := -10.0
var _toast_color := Color.WHITE
var _time := 0.0
var _font: Font
var _bold: Font
var _title: Font

var forge_panel: PanelContainer
var forge_dice: Array[Button] = []
var forge_held := [false, false, false]
var _forge_key := ""
var forge_status: Label
var forge_take_btn: Button
var forge_roll_btn: Button
var pause_panel: PanelContainer
var result_panel: PanelContainer
var pause_btn: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_touchscreen = DisplayServer.is_touchscreen_available()
	_font = VisualTheme.BODY_FONT
	_bold = VisualTheme.BOLD_FONT
	_title = VisualTheme.TITLE_FONT
	pause_btn = Button.new()
	pause_btn.text = "II"
	pause_btn.custom_minimum_size = Vector2(44, 40)
	VisualTheme.apply_tactile(pause_btn, "secondary", 10)
	pause_btn.pressed.connect(func():
		pause_panel.visible = true
		_center(pause_panel))
	add_child(pause_btn)
	_build_forge_panel()
	_build_pause_panel()
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	pause_btn.position = Vector2(size.x - 52, 78)

# ---------- panels ----------
func _panel(min_w: float) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", VisualTheme.panel(VisualTheme.SURFACE, VisualTheme.GOLD_DARK, 14, 14))
	p.custom_minimum_size = Vector2(min_w, 0)
	p.visible = false
	add_child(p)
	return p

func _label(parent: Node, text: String, size_px: int, color: Color, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(290, 0)
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	if font != null:
		l.add_theme_font_override("font", font)
	parent.add_child(l)
	return l

func _button(parent: Node, text: String, kind: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 50)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	VisualTheme.apply_tactile(b, kind, 12)
	b.add_theme_font_override("font", VisualTheme.BOLD_FONT)
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _center(p: Control) -> void:
	p.size = Vector2(minf(p.custom_minimum_size.x, size.x - 20), 0)
	p.reset_size()
	p.position = ((size - p.size) * 0.5).max(Vector2(10, 10))

func _build_forge_panel() -> void:
	forge_panel = _panel(340)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	forge_panel.add_child(v)
	_label(v, "THE FORGE", 22, VisualTheme.GOLD, _title)
	_label(v, "Roll 3 dice. A pair grants a class, three of a kind its upgraded form. FATE is wild. Tap a die to keep it.", 12, Color("#d4cbbb"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	for i in 3:
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 78)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_override("font", VisualTheme.BOLD_FONT)
		b.add_theme_font_size_override("font_size", 14)
		VisualTheme.apply_tactile(b, "secondary", 12)
		var idx := i
		b.pressed.connect(func(): _toggle_hold(idx))
		row.add_child(b)
		forge_dice.append(b)
	forge_status = _label(v, "", 15, VisualTheme.TEXT, _bold)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	v.add_child(actions)
	forge_roll_btn = _button(actions, "ROLL", "roll", func(): forge_roll.emit(forge_held.duplicate()))
	forge_take_btn = _button(actions, "TAKE", "primary", func(): forge_take.emit())
	_button(v, "LEAVE FORGE", "secondary", func(): forge_leave.emit())

func _toggle_hold(i: int) -> void:
	var me: Dictionary = sim.by_id.get(player_id, {})
	if me.is_empty() or not me.forge.rolled or me.forge.rolling > 0.0:
		return
	forge_held[i] = not forge_held[i]

func _refresh_forge(me: Dictionary) -> void:
	var f: Dictionary = me.forge
	if not f.open:
		if forge_panel.visible:
			forge_panel.visible = false
			forge_held = [false, false, false]
		return
	if not forge_panel.visible:
		forge_panel.visible = true
		forge_held = [false, false, false]
		_forge_key = ""
		_center(forge_panel)
	var rolling: bool = f.rolling > 0.0
	# Only rebuild the dice styling when something changed, not every frame.
	var state_key := "%s|%s|%s|%s|%d" % [str(f.faces), str(forge_held), f.rolled, rolling, int(_time * 14.0) if rolling else 0]
	if state_key == _forge_key:
		return
	_forge_key = state_key
	for i in 3:
		var b := forge_dice[i]
		var face := str(f.faces[i])
		if not f.rolled:
			b.text = "?"
		elif rolling and not f.held[i]:
			b.text = FACE_LABEL[Sim.FACES[int(_time * 14.0 + i * 2) % Sim.FACES.size()]]
		else:
			b.text = FACE_LABEL[face] + ("\nKEPT" if forge_held[i] else "")
		VisualTheme.apply_tactile(b, "active" if forge_held[i] else "secondary", 12)
		b.add_theme_color_override("font_color", FACE_COLOR.get(face, VisualTheme.TEXT) if f.rolled and not rolling else VisualTheme.TEXT)
	var r := Sim.forge_result(f.faces)
	var triple_fate: bool = f.faces.count("fate") == 3
	forge_roll_btn.disabled = rolling
	forge_roll_btn.text = "ROLL" if not f.rolled else "REROLL"
	if not f.rolled:
		forge_status.text = "Current: %s" % sim.class_label(me)
		forge_take_btn.disabled = true
		forge_take_btn.text = "TAKE"
	elif rolling:
		forge_status.text = "Rolling..."
		forge_take_btn.disabled = true
	elif triple_fate:
		forge_status.text = "Triple FATE — a random upgraded class!"
		forge_take_btn.disabled = false
		forge_take_btn.text = "TAKE FATE"
	elif r.cls != "":
		var nm: String = Sim.UPGRADE_NAME[r.cls] if r.up else str(Sim.CLASSES[r.cls].name)
		forge_status.text = ("THREE OF A KIND — " if r.up else "Pair — ") + nm
		forge_take_btn.disabled = false
		forge_take_btn.text = "TAKE " + nm.to_upper()
	else:
		forge_status.text = "No match. Keep dice and reroll."
		forge_take_btn.disabled = true
		forge_take_btn.text = "TAKE"

func _build_pause_panel() -> void:
	pause_panel = _panel(300)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pause_panel.add_child(v)
	_label(v, "SIEGE", 22, VisualTheme.GOLD, _title)
	_label(v, "Carry your Oracle out of the enemy keep and back to your throne. First to %d rescues wins." % Sim.WIN_RESCUES, 13, Color("#d4cbbb"))
	_button(v, "RESUME", "gold", func(): pause_panel.visible = false)
	var fps_btn := _button(v, "30 FPS MODE: OFF", "secondary", func(): pass)
	pause_panel.visibility_changed.connect(func(): fps_btn.text = "30 FPS MODE: " + ("ON" if Engine.max_fps == 30 else "OFF"))
	fps_btn.pressed.connect(func():
		fps_toggled.emit()
		fps_btn.text = "30 FPS MODE: " + ("ON" if Engine.max_fps == 30 else "OFF"))
	_button(v, "LEAVE MATCH", "secondary", func(): leave_requested.emit())

func show_result() -> void:
	if result_panel != null:
		return
	var me: Dictionary = sim.by_id.get(player_id, {})
	result_panel = _panel(320)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	result_panel.add_child(v)
	var won: bool = sim.winner == me.team
	var draw: bool = sim.winner == -1
	_label(v, "DRAW" if draw else ("VICTORY" if won else "DEFEAT"), 30, VisualTheme.GOLD if won or draw else VisualTheme.RED, _title)
	_label(v, "Rescues  %d – %d" % [sim.score[me.team], sim.score[1 - me.team]], 17, VisualTheme.TEXT, _bold)
	_label(v, "Kills  %d – %d" % [sim.kills[me.team], sim.kills[1 - me.team]], 14, Color("#d4cbbb"))
	_label(v, "You: %d KOs · %d downs · %d rescues" % [me.kills, me.deaths, me.rescues], 14, Color("#d4cbbb"))
	_button(v, "PLAY AGAIN", "primary", func(): replay_requested.emit())
	_button(v, "HOME", "secondary", func(): leave_requested.emit())
	result_panel.visible = true
	_center(result_panel)
	forge_panel.visible = false
	pause_panel.visible = false

func toast(text: String, color := Color.WHITE) -> void:
	_toast = text
	_toast_at = _time
	_toast_color = color

func on_event(e: Dictionary) -> void:
	var me: Dictionary = sim.by_id.get(player_id, {})
	if me.is_empty():
		return
	var mine: bool = e.get("team", -1) == me.team
	match str(e.k):
		"rescue":
			toast("OUR ORACLE IS HOME!" if mine else "THE ENEMY RESCUED THEIR ORACLE", VisualTheme.GOLD if mine else VisualTheme.RED)
		"pickup":
			toast("You have the Oracle — run home!" if e.id == player_id else ("An ally has our Oracle — escort!" if mine else "Enemy took their Oracle — stop them!"), VisualTheme.CYAN if mine else VisualTheme.RED)
		"drop":
			if mine:
				toast("Our Oracle is loose — grab her!", VisualTheme.GOLD)
		"recaptured":
			toast("Our Oracle was dragged back to her cell" if mine else "Enemy Oracle returned to our keep", Color("#d4cbbb"))
		"class":
			if e.id == player_id:
				var nm: String = sim.class_label(me)
				toast("You are now %s %s" % ["an" if "AEIOU".contains(nm.left(1).to_upper()) else "a", nm], VisualTheme.GOLD)
		"death":
			if e.id == player_id:
				toast("You fell!", VisualTheme.RED)

# ---------- input ----------
func _buttons() -> Array:
	var me: Dictionary = sim.by_id.get(player_id, {})
	var ctx: String = "" if me.is_empty() else sim.context_action(me)
	var br := Vector2(size.x, size.y)
	var out := [
		{"id":"attack", "c":br + Vector2(-82, -118), "r":50.0},
		{"id":"ability", "c":br + Vector2(-178, -78), "r":34.0},
		{"id":"dodge", "c":br + Vector2(-66, -228), "r":31.0},
	]
	if ctx != "":
		out.append({"id":"action", "c":br + Vector2(-172, -182), "r":36.0, "ctx":ctx})
	return out

func _modal_open() -> bool:
	return forge_panel.visible or pause_panel.visible or (result_panel != null and result_panel.visible)

func _input(event: InputEvent) -> void:
	if sim == null:
		return
	if event is InputEventScreenTouch:
		_touch(event.index, make_input_local(event).position, event.pressed)
	elif event is InputEventScreenDrag:
		_drag(event.index, make_input_local(event).position)
	elif not _touchscreen and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_touch(-1, make_input_local(event).position, event.pressed)
	elif not _touchscreen and event is InputEventMouseMotion and _touches.has(-1):
		_drag(-1, make_input_local(event).position)
	elif event is InputEventKey and event.pressed and not event.echo and not _modal_open():
		match event.physical_keycode:
			KEY_J, KEY_SPACE: action_pressed.emit("attack")
			KEY_K: action_pressed.emit("ability")
			KEY_L, KEY_SHIFT: action_pressed.emit("dodge")
			KEY_E: action_pressed.emit("action")

func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	if pressed:
		if _modal_open() or pause_btn.get_global_rect().has_point(pos + global_position):
			return
		for b in _buttons():
			if pos.distance_to(b.c) <= b.r + 12.0:
				_touches[index] = b.id
				_pressed_at[b.id] = _time
				if b.id == "attack":
					_attack_held = true
				action_pressed.emit(b.id)
				get_viewport().set_input_as_handled()
				return
		if pos.x < size.x * 0.58 and pos.y > 150.0 and not _stick_active:
			_touches[index] = "stick"
			_stick_active = true
			_stick_origin = pos
			_stick_pos = pos
			get_viewport().set_input_as_handled()
	else:
		var role: String = _touches.get(index, "")
		_touches.erase(index)
		if role == "stick":
			_stick_active = false
		elif role == "attack":
			_attack_held = false
		if role != "":
			get_viewport().set_input_as_handled()

func _drag(index: int, pos: Vector2) -> void:
	if _touches.get(index, "") == "stick":
		_stick_pos = pos
		# Let the base follow a finger that drifts too far, so direction changes stay quick.
		var off := _stick_pos - _stick_origin
		if off.length() > 70.0:
			_stick_origin = _stick_pos - off.normalized() * 70.0
		get_viewport().set_input_as_handled()

func move_vector() -> Vector2:
	var v := Vector2.ZERO
	if _stick_active:
		var off := (_stick_pos - _stick_origin) / 60.0
		if off.length() > 0.15:
			v = off.limit_length(1.0)
	elif not _modal_open():
		v = Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
		if Input.is_physical_key_pressed(KEY_A): v.x -= 1
		if Input.is_physical_key_pressed(KEY_D): v.x += 1
		if Input.is_physical_key_pressed(KEY_W): v.y -= 1
		if Input.is_physical_key_pressed(KEY_S): v.y += 1
		v = v.limit_length(1.0)
	return v

func attack_held() -> bool:
	return _attack_held or (not _modal_open() and (Input.is_physical_key_pressed(KEY_J) or Input.is_physical_key_pressed(KEY_SPACE)))

# ---------- drawing ----------
func _process(delta: float) -> void:
	_time += delta
	if sim == null:
		return
	var me: Dictionary = sim.by_id.get(player_id, {})
	if not me.is_empty():
		_refresh_forge(me)
	queue_redraw()

func _text(pos: Vector2, text: String, size_px: int, color: Color, font: Font = null, align := HORIZONTAL_ALIGNMENT_CENTER, width := -1.0) -> void:
	var f := font if font != null else _bold
	if align == HORIZONTAL_ALIGNMENT_CENTER and width < 0:
		width = 400.0
		pos.x -= width * 0.5
	draw_string_outline(f, pos, text, align, width, size_px, 5, Color(0, 0, 0, 0.6))
	draw_string(f, pos, text, align, width, size_px, color)

func _draw() -> void:
	var t0 := Time.get_ticks_usec()
	if diag != null:
		diag.mark("hud draw")
	_draw_hud()
	if diag != null:
		diag.add_time("hud", Time.get_ticks_usec() - t0)
		diag.mark("hud drawn, rendering")

func _draw_hud() -> void:
	if sim == null:
		return
	var me: Dictionary = sim.by_id.get(player_id, {})
	if me.is_empty():
		return
	var w := size.x
	# Scoreboard.
	var bar := Rect2(8, 8, w - 16, 62)
	if _bar_style == null:
		_bar_style = VisualTheme.panel(Color(0.035, 0.09, 0.12, 0.92), VisualTheme.GOLD_DARK, 12, 8)
	draw_style_box(_bar_style, bar)
	var t: int = me.team
	_text(Vector2(24, 34), "YOUR SIDE", 12, TEAM_COLORS[t], _bold, HORIZONTAL_ALIGNMENT_LEFT, 120)
	_text(Vector2(24, 60), "%d ♛" % sim.score[t], 26, VisualTheme.GOLD, _title, HORIZONTAL_ALIGNMENT_LEFT, 120)
	_text(Vector2(w - 144, 34), "ENEMY", 12, TEAM_COLORS[1 - t], _bold, HORIZONTAL_ALIGNMENT_RIGHT, 120)
	_text(Vector2(w - 144, 60), "%d ♛" % sim.score[1 - t], 26, VisualTheme.GOLD, _title, HORIZONTAL_ALIGNMENT_RIGHT, 120)
	var left := maxf(0.0, Sim.MATCH_TIME - sim.time)
	_text(Vector2(w * 0.5, 52), "%d:%02d" % [int(left) / 60, int(left) % 60], 32, Color("#e8eef2") if left > 60 else VisualTheme.RED, _title)
	# Player status line.
	var hp_rect := Rect2(12, 78, minf(220.0, w * 0.52), 14)
	draw_rect(hp_rect, Color(0, 0, 0, 0.55))
	var frac := clampf(me.hp / maxf(1.0, me.max_hp), 0.0, 1.0)
	draw_rect(Rect2(hp_rect.position, Vector2(hp_rect.size.x * frac, hp_rect.size.y)), Color("#7dff8a") if frac > 0.35 else VisualTheme.RED)
	draw_rect(hp_rect, VisualTheme.GOLD_DARK, false, 1.5)
	_text(Vector2(14, 110), "%s · %d HP" % [sim.class_label(me).to_upper(), int(ceil(me.hp))], 13, VisualTheme.TEXT, _bold, HORIZONTAL_ALIGNMENT_LEFT, 260)
	_text(Vector2(14, 128), _oracle_status(me), 12, VisualTheme.GOLD, _font, HORIZONTAL_ALIGNMENT_LEFT, w - 80)
	# Toast.
	var age := _time - _toast_at
	if age < 2.6 and _toast != "":
		var c := _toast_color
		c.a = clampf(2.6 - age, 0.0, 1.0)
		_text(Vector2(w * 0.5, 176), _toast, 18, c, _bold)
	_draw_oracle_marker(me)
	if diag != null and diag.fps_text != "":
		_text(Vector2(w - 212, 142), diag.fps_text, 11, Color(1, 1, 1, 0.6), _font, HORIZONTAL_ALIGNMENT_RIGHT, 200)
	if me.state == "dead":
		_text(Vector2(w * 0.5, size.y * 0.45), "RESPAWNING IN %d" % int(ceil(me.respawn_at - sim.time)), 22, VisualTheme.GOLD, _title)
		return
	if _modal_open():
		return
	# Stick.
	if _stick_active:
		draw_circle(_stick_origin, 62, Color(1, 1, 1, 0.08))
		draw_arc(_stick_origin, 62, 0, TAU, 40, Color(1, 1, 1, 0.3), 2.0, true)
		var knob := _stick_origin + (_stick_pos - _stick_origin).limit_length(60.0)
		draw_circle(knob, 26, Color(1, 1, 1, 0.35))
	elif _touchscreen:
		var home := Vector2(96, size.y - 120)
		draw_arc(home, 62, 0, TAU, 40, Color(1, 1, 1, 0.14), 2.0, true)
		_text(home + Vector2(0, 6), "MOVE", 12, Color(1, 1, 1, 0.35), _bold)
	# Combat buttons.
	for b in _buttons():
		_draw_button(b, me)

func _oracle_status(me: Dictionary) -> String:
	var o: Dictionary = sim.oracles[me.team]
	match str(o.state):
		"cell": return "Our Oracle: captive in the enemy keep"
		"carried": return "Our Oracle: YOU are carrying her!" if o.carrier == player_id else "Our Oracle: an ally is carrying her"
		"dropped": return "Our Oracle: loose — returns in %ds" % int(ceil(Sim.DROP_RETURN - (sim.time - o.dropped_at)))
	return ""

func _draw_oracle_marker(me: Dictionary) -> void:
	# Point to our Oracle (or home, while carrying her) when she is off-screen.
	if not project.is_valid() or not on_screen.is_valid():
		return
	var goal: Vector2 = Sim.throne(me.team) if me.carrying else sim.oracles[me.team].pos
	var world := Vector3(goal.x, 1.0, goal.y)
	if on_screen.call(world):
		return
	var p: Vector2 = project.call(world)
	var center := size * 0.5
	var dir := (p - center).normalized()
	var edge := center + dir * minf(size.x * 0.42, size.y * 0.36)
	var col: Color = VisualTheme.GOLD if not me.carrying else TEAM_COLORS[me.team]
	var tip := edge + dir * 16
	var side := Vector2(-dir.y, dir.x) * 11
	draw_colored_polygon(PackedVector2Array([tip, edge - dir * 6 + side, edge - dir * 6 - side]), col)
	_text(edge - dir * 22 + Vector2(0, 5), "HOME" if me.carrying else "ORACLE", 11, col, _bold)

func _draw_button(b: Dictionary, me: Dictionary) -> void:
	var c: Vector2 = b.c
	var r: float = b.r
	var label := ""
	var col := Color("#2c3136")
	var rim := Color("#b8904e")
	var cd := 0.0
	var cd_max := 1.0
	var ready := true
	match str(b.id):
		"attack":
			label = "ATTACK"
			col = Color("#9a6414")
			rim = Color("#fff1bf")
			ready = not me.carrying
		"ability":
			var ab := str(Sim.CLASSES[me.cls].ability)
			label = ab.to_upper() if ab != "" else "—"
			col = Color("#35226a")
			rim = Color("#d6b8ff")
			cd = me.cd_ability
			cd_max = maxf(0.1, float(Sim.CLASSES[me.cls].ab_cd))
			ready = ab != "" and cd <= 0.0 and not me.carrying
		"dodge":
			label = "DODGE"
			cd = me.cd_dodge
			cd_max = 2.2
			ready = cd <= 0.0 and not me.carrying
		"action":
			label = {"forge":"FORGE","grab":"GRAB","throw":"THROW"}.get(b.ctx, "USE")
			col = Color("#155258")
			rim = Color("#9ff6ef")
	var pressed: bool = _time - float(_pressed_at.get(b.id, -10.0)) < 0.12 or (b.id == "attack" and _attack_held)
	var body := col.lightened(0.15) if pressed else col
	if not ready:
		body = body.darkened(0.45)
	draw_circle(c + Vector2(0, 4), r, Color(0, 0, 0, 0.45))
	draw_circle(c, r, body)
	draw_arc(c, r, 0, TAU, 48, rim if ready else rim.darkened(0.5), 3.0, true)
	if cd > 0.0:
		draw_arc(c, r - 6, -PI * 0.5, -PI * 0.5 + TAU * (cd / cd_max), 40, Color(1, 1, 1, 0.55), 5.0, true)
	_text(c + Vector2(0, 6), label, 15 if r > 40 else 12, Color("#fffaf0") if ready else Color("#8a939a"), _bold)
