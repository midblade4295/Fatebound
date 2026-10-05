extends Control
# Siege HUD. The stick and the combat buttons are drawn and hit-tested by hand from raw
# InputEventScreenTouch events, because Godot's Buttons only follow the first finger and on a
# phone you hold the stick while tapping ATTACK. Modal panels (workshop, pause, result) use Buttons.
const VisualTheme = preload("res://scripts/ui/visual_theme.gd")
const UI = preload("res://scripts/app/ui.gd")
# The old brass kinds map onto the app's tactile styles so battle panels match the menus.
const BUTTON_STYLE := {"primary":"primary", "secondary":"secondary", "gold":"gold", "roll":"gold", "active":"claim"}
const Sim = preload("res://scripts/siege/siege_sim.gd")

signal leave_requested
signal replay_requested
signal action_pressed(kind: String)
signal res_cycled
var res_label_source: Callable   # -> float render scale
signal workshop_tools
signal workshop_buy(id: String)
signal workshop_leave

const TEAM_COLORS := [Color("#5fd2f0"), Color("#ff7b52")]

var sim
var diag
var _bar_style: StyleBox
var player_id := "you"
var project: Callable          # world Vector3 -> HUD Vector2
var on_screen: Callable        # world Vector3 -> bool
var numbers_source: Callable   # -> Array of {pos, text, mine, at} from the 3D view
var bars_source: Callable      # -> Array of {pos, fill, color} for 2D health bars
var numbers_clock: Callable    # -> float, the view clock those "at" values use

var _touchscreen := false
var _touches := {}             # index -> role
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _stick_active := false
var _attack_held := false
var _ability_held := false
var _pressed_at := {}
var _toast := ""
var _multi: Label = null                 # 0.31.29: DOUBLE KILL ... LEGENDARY
var _multi_at := -10.0
const MULTI_COLORS := [Color.WHITE, Color.WHITE, Color("#ffe08a"), Color("#ffb04a"), Color("#ff6a3d"), Color("#ff3d6e"), Color("#c77dff")]
var _toast_at := -10.0
var _toast_color := Color.WHITE
var _time := 0.0
var _font: Font
var _bold: Font
var _title: Font

var workshop_panel: PanelContainer
var workshop_stock: Label
var workshop_buttons: Dictionary = {}
var workshop_tools_btn: Button
var _workshop_key := ""
var gate_bars_source: Callable   # -> Array of {pos, fill, color, broken}
var pause_panel: PanelContainer
var result_panel: PanelContainer
var pause_btn: Button

static var ready_times := {}

func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_touchscreen = DisplayServer.is_touchscreen_available()
	_font = VisualTheme.BODY_FONT
	_bold = VisualTheme.BOLD_FONT
	_title = VisualTheme.TITLE_FONT
	pause_btn = Button.new()
	pause_btn.text = "II"
	pause_btn.custom_minimum_size = Vector2(44, 40)
	UI.style_button(pause_btn, "secondary", 16, 12)
	pause_btn.pressed.connect(func():
		if pause_panel == null:
			_build_pause_panel()
		pause_panel.visible = true
		_center(pause_panel))
	add_child(pause_btn)
	# 0.31.8: the workshop and pause panels are built the first time they open (they cost ~370 ms at match start).
	resized.connect(_layout)
	_layout()
	ready_times["hud _ready total"] = Time.get_ticks_msec() - t0

func _layout() -> void:
	pause_btn.position = Vector2(size.x - 52, 78)

# ---------- panels ----------
func _panel(min_w: float) -> PanelContainer:
	var p := PanelContainer.new()
	var ps := UI.card_style(Color(0.07, 0.11, 0.19, 0.97), 22, UI.CARD_HI)
	ps.content_margin_left = 18
	ps.content_margin_right = 18
	ps.content_margin_top = 16
	ps.content_margin_bottom = 16
	p.add_theme_stylebox_override("panel", ps)
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
	UI.style_button(b, str(BUTTON_STYLE.get(kind, "secondary")), 15, 14)
	UI.tighten(b, 8)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _center(p: Control) -> void:
	p.size = Vector2(minf(p.custom_minimum_size.x, size.x - 20), 0)
	p.reset_size()
	p.position = ((size - p.size) * 0.5).max(Vector2(10, 10))

func _build_workshop_panel() -> void:
	workshop_panel = _panel(340)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 9)
	workshop_panel.add_child(v)
	_label(v, "THE WORKSHOP", 22, VisualTheme.GOLD, _title)
	workshop_stock = _label(v, "", 15, VisualTheme.TEXT, _bold)
	workshop_tools_btn = _button(v, "TAKE TOOLS · BECOME A WORKER", "active", func(): workshop_tools.emit())
	_label(v, "Workers chop trees and mine stone, carry it here, and repair gates with wood.", 11, Color("#d4cbbb"))
	for id in ["gates", "armory", "catapult", "launcher"]:
		var up: Dictionary = Sim.UPGRADES[id]
		var b := _button(v, str(up.name), "gold", func(): workshop_buy.emit(id))
		b.custom_minimum_size = Vector2(0, 54)
		b.add_theme_font_size_override("font_size", 14)
		workshop_buttons[id] = b
	_label(v, "Hat upgrades are bought at each hat shop.", 11, Color("#d4cbbb"))
	_button(v, "LEAVE WORKSHOP", "secondary", func(): workshop_leave.emit())

func paused() -> bool:
	return pause_panel != null and pause_panel.visible

func show_pause() -> void:
	if pause_panel == null:
		_build_pause_panel()
	pause_panel.visible = true
	_center(pause_panel)

func _refresh_workshop(me: Dictionary) -> void:
	if not me.workshop_open:
		if workshop_panel != null and workshop_panel.visible:
			workshop_panel.visible = false
		return
	if workshop_panel == null:
		_build_workshop_panel()
	var t: int = me.team
	var key := "%s|%s|%s|%s" % [str(sim.stock[t]), str(sim.levels[t]), me.cls, me.carrying]
	if workshop_panel.visible and key == _workshop_key:
		return
	_workshop_key = key
	if not workshop_panel.visible:
		workshop_panel.visible = true
		_center(workshop_panel)
	workshop_stock.text = "WOOD %d   ·   STONE %d" % [sim.stock[t].wood, sim.stock[t].stone]
	workshop_tools_btn.disabled = me.cls == "worker" or me.carrying
	workshop_tools_btn.text = "YOU ARE A WORKER" if me.cls == "worker" else "TAKE TOOLS · BECOME A WORKER"
	workshop_tools_btn.disabled = false
	for id in workshop_buttons:
		var up: Dictionary = Sim.UPGRADES[id]
		var lvl: int = sim.levels[t][id]
		var b: Button = workshop_buttons[id]
		var cost: Dictionary = sim.upgrade_cost(t, id)
		if cost.is_empty():
			b.text = ("%s ✔" % str(Sim.UPGRADE_NAME[id.substr(4)]).to_upper()) if id.begins_with("hat_") else "%s · MAX" % up.name
			b.disabled = true
		else:
			if id.begins_with("hat_"):
				b.text = "%s\n%dw · %ds" % [str(Sim.UPGRADE_NAME[id.substr(4)]).to_upper(), int(cost.wood), int(cost.stone)]
			else:
				b.text = "%s %s\n%d wood · %d stone" % [up.name, "I".repeat(lvl + 1) if int(up.max) > 1 else "", int(cost.wood), int(cost.stone)]
			b.disabled = not sim.can_buy(t, id)
		b.tooltip_text = str(up.desc)

func _build_pause_panel() -> void:
	pause_panel = _panel(300)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pause_panel.add_child(v)
	_label(v, "FATEBOUND", 22, VisualTheme.GOLD, _title)
	_label(v, "Break into the enemy castle and carry your King from their dungeon to his throne room. First to %d rescues wins. Standing by him in their dungeon heals you. Catch fish from the river (ACTION on a bank) and feed them to THEIR King: each size needs another lifter (up to 6). Left on the ground, a King throws a tantrum that knocks everyone back. Workers gather, repair gates and fund upgrades." % Sim.WIN_RESCUES, 11, Color("#d4cbbb"))
	_button(v, "RESUME", "gold", func(): pause_panel.visible = false)
	var res_btn := _button(v, "RESOLUTION: 100%", "secondary", func(): pass)
	res_btn.pressed.connect(func():
		res_cycled.emit()
		res_btn.text = "RESOLUTION: %d%%" % int(res_label_source.call() * 100.0) if res_label_source.is_valid() else "RESOLUTION")
	pause_panel.visibility_changed.connect(func():
		if res_label_source.is_valid(): res_btn.text = "RESOLUTION: %d%%" % int(res_label_source.call() * 100.0))
	_button(v, "LEAVE MATCH", "secondary", func(): leave_requested.emit())

func show_result(result: Dictionary = {}) -> void:
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
	if me.gathered > 0 or me.gate_dmg > 0.0:
		_label(v, "Gathered %d · gate damage %d" % [int(me.gathered), int(me.gate_dmg)], 13, Color("#cfe8b8"))
	var rw: Dictionary = result.get("rewards", {})
	if not rw.is_empty():
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		v.add_child(box)
		for ln in rw.lines:
			var row := HBoxContainer.new()
			box.add_child(row)
			# _label() gives every label a 290 px minimum; two of those don't fit a phone row.
			var name_l := _label(row, str(ln.label), 12, Color("#d4cbbb"))
			name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			name_l.custom_minimum_size = Vector2(150, 0)
			name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var val := _label(row, "+%d gold  +%d pass" % [int(ln.gold), int(ln.pass)], 12, VisualTheme.GOLD)
			val.custom_minimum_size = Vector2(130, 0)
			val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_label(v, "+%d GOLD  ·  +%d XP  ·  +%d PASS" % [int(rw.gold), int(rw.xp), int(rw.pass)], 14, VisualTheme.GOLD, _bold)
		for lv in result.get("levels", []):
			_label(v, "LEVEL UP! Level %d  ·  +%d gold%s" % [int(lv.level), int(lv.reward.get("gold", 0)), ("  ·  +%d gems" % int(lv.reward.gems)) if lv.reward.has("gems") else ""], 14, VisualTheme.CYAN, _bold)
		var tiers: Array = result.get("tiers", [])
		if not tiers.is_empty():
			_label(v, "Siege Pass tier %s reached — claim it on the Pass screen" % (str(tiers[-1]) if tiers.size() == 1 else "%d–%d" % [tiers[0], tiers[-1]]), 13, Color("#ffcf7a"))
		for c in (result.get("challenges", []) as Array).slice(0, 4):
			_label(v, "%s  %s  %d/%d" % ["✔" if c.done else "•", str(c.text), int(c.progress), int(c.goal)], 12, VisualTheme.CYAN if c.done else Color("#b9c3c4"))
	_button(v, "PLAY AGAIN", "primary", func(): replay_requested.emit())
	_button(v, "HOME", "secondary", func(): leave_requested.emit())
	result_panel.visible = true
	_center(result_panel)
	if pause_panel != null:
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
	if str(e.k) == "class_full" and str(e.get("id", "")) == str(player_id):
		toast("%s full · %d/%d" % [str(Sim.CLASSES.get(str(e.cls), {"name":str(e.cls).capitalize()}).get("name", str(e.cls).capitalize())) + ("s" if str(e.cls) != "worker" else "s"), int(e.n), int(e.cap)], VisualTheme.GOLD)
		return
	match str(e.k):
		"multikill":
			var n := int(e.n)
			if str(e.id) == str(player_id):
				_show_multi(str(e.name), n)
			elif n >= 3:
				var who: String = "An ally" if mine else "An enemy"
				toast("%s: %s" % [who, str(e.name)], VisualTheme.CYAN if mine else VisualTheme.RED)
		"rescue":
			toast("OUR KING IS HOME!" if mine else "THE ENEMY RESCUED THEIR KING", VisualTheme.GOLD if mine else VisualTheme.RED)
		"pickup":
			toast("You have the King — run home!" if e.id == player_id else ("An ally has our King — escort!" if mine else "Enemy took their King — stop them!"), VisualTheme.CYAN if mine else VisualTheme.RED)
		"drop":
			if mine:
				toast("Our King is loose — grab him!", VisualTheme.GOLD)
		"recaptured":
			toast("Our King was dragged back to his cell" if mine else "Enemy King returned to our keep", Color("#d4cbbb"))
		"class":
			if e.id == player_id:
				var nm: String = sim.class_label(me)
				toast("You are now %s %s" % ["an" if "AEIOU".contains(nm.left(1).to_upper()) else "a", nm], VisualTheme.GOLD)
		"death":
			if e.id == player_id:
				toast("You fell!", VisualTheme.RED)
		"fed":
			# Only stage changes are worth a toast (every other fish is just a third of a stage).
			if bool(e.get("stage_up", true)):
				if mine:
					toast("Our King got fatter! Size %d — needs %d to lift" % [int(e.weight), int(e.need)], VisualTheme.RED)
				else:
					toast("Their King grew to size %d — needs %d to lift" % [int(e.weight), int(e.need)], Color("#ff9ec8"))
		"fish_caught":
			if e.id == player_id:
				toast("Caught a fish! Feed it to their King in our dungeon", Color("#9fdcff"))
		"fish_lost":
			if e.id == player_id:
				toast("The fish got away!", Color("#c8d4dc"))
		"tantrum":
			var tt := int(e.team)
			if tt == sim.by_id[player_id].team:
				toast("Our King throws a TANTRUM — reach him now!", VisualTheme.GOLD)
			else:
				toast("Their King throws a tantrum!", Color("#ffb3c6"))
		"lift_join":
			var lo: Dictionary = sim.oracles[int(e.team)]
			if lo.carrier == player_id or e.id == player_id:
				var need := int(e.need)
				if int(e.n) < need:
					toast("Lifting %d/%d — need %d more" % [int(e.n), need, need - int(e.n)], Color("#f2d18d"))
				elif int(e.n) == need:
					toast("Enough hands — move him!", VisualTheme.GOLD)
		"gate_broken":
			var side: String = str(sim.gates[int(e.gate)].side).to_upper()
			if side == "JAIL":
				# The jail door in the dungeon wing (Round 13).
				toast("THEY SMASHED OUR JAIL — stop them taking their King!" if mine else "THEIR JAIL IS OPEN — grab our King!", VisualTheme.RED if mine else VisualTheme.GOLD)
			else:
				toast("OUR %s GATE HAS FALLEN!" % side if mine else "ENEMY %s GATE BROKEN — CHARGE!" % side, VisualTheme.RED if mine else VisualTheme.GOLD)
		"jail_reset":
			if mine:
				toast("Our jail is locked again", VisualTheme.CYAN)
		"gate_rebuilt":
			if mine:
				toast("Our %s gate is rebuilt" % str(sim.gates[int(e.gate)].side), VisualTheme.CYAN)
		"hat_take", "hat_pick":
			if str(e.get("id", "")) == player_id:
				var nm: String = sim.class_label(me)
				toast(("You are now a%s %s!" % ["n" if nm.left(1) in ["A", "E", "I", "O", "U"] else "", nm]), VisualTheme.GOLD)
		"outpost_captured":
			if int(e.team) == me.team:
				toast("Outpost captured! Climb it, or drop resources here", VisualTheme.GOLD)
			else:
				toast("The enemy took an outpost", VisualTheme.RED)
		"outpost_lost":
			if int(e.team) == me.team:
				toast("We lost an outpost", VisualTheme.RED)
		"ladder_up":
			toast("Ladder raised on the enemy wall — climb over!" if mine else "Enemy ladder on our wall — knock it down!", VisualTheme.GOLD if mine else VisualTheme.RED)
		"ladder_down":
			toast("Our ladder was knocked down" if mine else "Enemy ladder destroyed", Color("#d4cbbb"))
		"upgrade":
			if mine:
				var up: Dictionary = Sim.UPGRADES[str(e.upgrade)]
				toast("%s upgraded (level %d)" % [up.name, int(e.level)], VisualTheme.GOLD)

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
	return (workshop_panel != null and workshop_panel.visible) or paused() or (result_panel != null and result_panel.visible)

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
				elif b.id == "ability":
					_ability_held = true
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
		elif role == "ability":
			_ability_held = false
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

func ability_held() -> bool:
	# Knights hold ABILITY to keep the shield up (K on a keyboard).
	return _ability_held or (not _modal_open() and Input.is_physical_key_pressed(KEY_K))

func attack_held() -> bool:
	return _attack_held or (not _modal_open() and (Input.is_physical_key_pressed(KEY_J) or Input.is_physical_key_pressed(KEY_SPACE)))

# ---------- drawing ----------
func _show_multi(text: String, n: int) -> void:
	if _multi == null:
		_multi = Label.new()
		_multi.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_multi.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_multi.add_theme_font_override("font", load("res://assets/fonts/LuckiestGuy-Regular.ttf"))
		_multi.add_theme_constant_override("outline_size", 14)
		_multi.add_theme_color_override("font_outline_color", Color(0.12, 0.06, 0.02))
		_multi.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_multi)
	_multi.text = text
	_multi.add_theme_font_size_override("font_size", 64 + 4 * mini(n - 2, 3))     # fits a portrait phone at rest
	_multi.add_theme_color_override("font_color", MULTI_COLORS[mini(n, MULTI_COLORS.size() - 1)])
	_multi_at = _time
	_multi.visible = true

func _sync_multi() -> void:
	if _multi == null or not _multi.visible:
		return
	var k := (_time - _multi_at) / 1.8
	if k >= 1.0:
		_multi.visible = false
		return
	var vs := get_viewport_rect().size
	_multi.size = Vector2(vs.x, 120.0)
	_multi.pivot_offset = _multi.size * 0.5
	_multi.position = Vector2(0.0, vs.y * 0.3)
	var pop := 1.0 + 0.45 * maxf(0.0, 1.0 - k * 6.0)          # slams in big, settles
	_multi.scale = Vector2.ONE * pop
	_multi.modulate.a = clampf((1.0 - k) * 3.0, 0.0, 1.0)

func _process(delta: float) -> void:
	_sync_multi()
	_time += delta
	if sim == null:
		return
	var me: Dictionary = sim.by_id.get(player_id, {})
	if not me.is_empty():
		_refresh_workshop(me)
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
	_draw_station_titles(me)                  # first, so buttons and panels draw over them
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
	_draw_castle_status(me)
	# Toast.
	var age := _time - _toast_at
	if age < 2.6 and _toast != "":
		var c := _toast_color
		c.a = clampf(2.6 - age, 0.0, 1.0)
		_text(Vector2(w * 0.5, 176), _toast, 18, c, _bold)
	_draw_bars()
	_draw_gate_bars()
	_draw_oracle_marker(me)
	_draw_numbers()
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

func _draw_bars() -> void:
	if not bars_source.is_valid() or not project.is_valid():
		return
	for b in bars_source.call():
		if on_screen.is_valid() and not on_screen.call(b.pos):
			continue
		var p: Vector2 = project.call(b.pos)
		if p.y < 150.0:
			continue
		var r := Rect2(p - Vector2(17, 3), Vector2(34, 5))
		draw_rect(r.grow(1.0), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(r.position, Vector2(r.size.x * float(b.fill), r.size.y)), b.color)

func _draw_numbers() -> void:
	# Damage numbers: projected from 3D and drawn on the HUD canvas (no Label3D mesh rebuilds).
	if not numbers_source.is_valid() or not project.is_valid():
		return
	var now: float = numbers_clock.call()
	for n in numbers_source.call():
		var u := clampf((now - float(n.at)) / 0.8, 0.0, 1.0)
		if on_screen.is_valid() and not on_screen.call(n.pos):
			continue
		var p: Vector2 = project.call(n.pos)
		if p.y < 150.0:
			continue   # keep clear of the scoreboard and status lines
		var c := Color("#ff6b5a") if n.mine else Color("#fff1c2")
		c.a = 1.0 - u * u
		_text(p + Vector2(0, -34.0 * u), str(n.text), 18, c, _bold)

func _draw_castle_status(me: Dictionary) -> void:
	var t: int = me.team
	var load_txt := ""
	if me.load.n > 0:
		load_txt = "   carrying %d %s" % [me.load.n, me.load.kind]
	_text(Vector2(14, 146), "WOOD %d · STONE %d%s" % [sim.stock[t].wood, sim.stock[t].stone, load_txt], 12, Color("#cfe8b8"), _bold, HORIZONTAL_ALIGNMENT_LEFT, 300)
	# Our two gates as small health bars.
	var x := 14.0
	for g in sim.gates:
		if g.team != t or str(g.get("kind", "")) == "jail":      # the jail door shows its own bar in the world
			continue
		var r := Rect2(Vector2(x + 40, 153), Vector2(56, 6))
		_text(Vector2(x, 160), str(g.side).to_upper().left(1) + " GATE", 10, Color(1, 1, 1, 0.75), _bold, HORIZONTAL_ALIGNMENT_LEFT, 44)
		draw_rect(r.grow(1), Color(0, 0, 0, 0.6))
		if sim.gate_blocks(g):
			draw_rect(Rect2(r.position, Vector2(r.size.x * g.hp / g.max_hp, r.size.y)), TEAM_COLORS[t])
		else:
			_text(r.position + Vector2(2, 7), "BROKEN", 9, VisualTheme.RED, _bold, HORIZONTAL_ALIGNMENT_LEFT, 60)
		x += 112.0
	_draw_outpost_pips(t, x + 4.0)

var _outpost_alert_at := -100.0
var _outpost_prev: Dictionary = {}

func _draw_outpost_pips(t: int, x: float) -> void:
	# One diamond per outpost: owner colour (grey neutral); while a capture is in progress it
	# fills with the capturing team's colour. Ours first, then the enemy side.
	if sim.outposts.is_empty():
		return
	_text(Vector2(x, 160), "POSTS", 10, Color(1, 1, 1, 0.75), _bold, HORIZONTAL_ALIGNMENT_LEFT, 44)
	var cx := x + 44.0
	for op in sim.outposts:
		var c := Vector2(cx, 156)
		var pts := PackedVector2Array([c + Vector2(0, -7), c + Vector2(7, 0), c + Vector2(0, 7), c + Vector2(-7, 0)])
		var owner: int = op.owner
		draw_colored_polygon(pts, Color(0, 0, 0, 0.6))
		var inner := PackedVector2Array([c + Vector2(0, -5), c + Vector2(5, 0), c + Vector2(0, 5), c + Vector2(-5, 0)])
		var base: Color = Color(0.55, 0.58, 0.62) if owner < 0 else TEAM_COLORS[owner]
		draw_colored_polygon(inner, base)
		var pr: float = op.prog
		var capturing: bool = (owner < 0 and absf(pr) > 0.02) or (owner == 0 and pr < 0.999) or (owner == 1 and pr > -0.999)
		if capturing:
			var towards: Color = TEAM_COLORS[0] if pr > 0.0 else TEAM_COLORS[1]
			var f := absf(pr) if owner < 0 else 1.0 - absf(pr)
			draw_arc(c, 9.0, -PI / 2, -PI / 2 + TAU * clampf(f, 0.0, 1.0), 18, towards, 2.5, true)
		cx += 20.0
	# Alert once when enemies start taking one of ours.
	for op in sim.outposts:
		var prev: float = _outpost_prev.get(op.id, op.prog)
		var losing: bool = int(op.owner) == t and ((t == 0 and op.prog < prev - 0.0001) or (t == 1 and op.prog > prev + 0.0001))
		if losing and _time - _outpost_alert_at > 10.0:
			_outpost_alert_at = _time
			toast("Enemies are taking one of our outposts!", VisualTheme.RED)
		_outpost_prev[op.id] = op.prog

func _draw_gate_bars() -> void:
	if not gate_bars_source.is_valid() or not project.is_valid():
		return
	for b in gate_bars_source.call():
		if on_screen.is_valid() and not on_screen.call(b.pos):
			continue
		var p: Vector2 = project.call(b.pos)
		if p.y < 170.0:
			continue
		var r := Rect2(p - Vector2(30, 4), Vector2(60, 7))
		draw_rect(r.grow(1.5), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(r.position, Vector2(r.size.x * float(b.fill), r.size.y)), b.color)

func _oracle_status(me: Dictionary) -> String:
	var o: Dictionary = sim.oracles[me.team]
	var need: int = sim.lifters_needed(o)
	var suffix := "  · size %d, needs %d" % [int(o.weight), need] if int(o.weight) > 0 else ""
	return _oracle_state_text(me, o) + suffix

func _oracle_state_text(_me: Dictionary, o: Dictionary) -> String:
	match str(o.state):
		"cell": return "Our King: captive in the enemy dungeon"
		"carried":
			var n: int = o.lifters.size()
			var need: int = sim.lifters_needed(o)
			if int(o.carry_team) != int(o.team):
				return "Our King: ENEMIES are hauling him back!"
			if n < need:
				return "Our King: lifting %d/%d — need %d more!" % [n, need, need - n]
			return "Our King: YOU lead the lift!" if o.carrier == player_id else "Our King: allies are carrying him"
		"dropped": return "Our King: loose — back to his cell in %ds" % int(ceil(Sim.DROP_RETURN - (sim.time - o.dropped_at)))
	return ""

static var _plate_styles: Dictionary = {}

func _plate_style(team: int, up: bool) -> StyleBoxFlat:
	# A slim signboard: dark lacquered panel, thin gold rim (brighter when upgraded), a team-coloured
	# top edge, a soft shadow. Anti-aliased rounded corners. Cached.
	var key := "%d:%s" % [team, up]
	if not _plate_styles.has(key):
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.10, 0.08, 0.06, 0.88)
		sb.border_color = Color("#ffd257") if up else Color("#c9a45a")
		sb.set_border_width_all(1)
		sb.border_width_top = 2
		sb.set_corner_radius_all(6)
		sb.shadow_color = Color(0, 0, 0, 0.35)
		sb.shadow_size = 3
		sb.shadow_offset = Vector2(0, 2)
		sb.anti_aliasing = true
		_plate_styles[key] = sb
	return _plate_styles[key]

func _draw_station_titles(me: Dictionary) -> void:
	# Name plates over the hat shops and the workshops in view. Round 18 (Kevin: "very bulky and
	# covering a lot of the ground"): one slim line -- the name (Cinzel 13) and, for hat shops, the stock
	# as dots -- about half the height of the 0.19.5 two-line signboard; shown within 16 m, fading over
	# the last 4. A pointer marks the building; kept on screen at the edges.
	if not project.is_valid() or not on_screen.is_valid():
		return
	var spots := []
	for st in sim.stands:
		var up: bool = int(sim.levels[int(st.team)].get("hat_" + str(st.cls), 0)) > 0
		var nm: String = (str(Sim.UPGRADE_NAME[st.cls]) if up else str(Sim.CLASSES[st.cls].name)).to_upper()
		spots.append({"p": st.p, "name": nm, "stock": int(st.stock), "team": int(st.team), "up": up,
			"at": st.get("b", st.p), "top": float(st.get("top", 2.7))})
	for t in 2:
		spots.append({"p": Sim.workshop(t), "name": "WORKSHOP", "stock": -1, "team": t, "up": false})
	var title_font: Font = VisualTheme.TITLE_FONT
	var name_px := 13
	for sp in spots:
		var dist: float = (sp.p as Vector2).distance_to(me.pos)
		if dist > 16.0:
			continue
		# Over the building's roof for hat shops (Round 20), over the spot otherwise.
		var at: Vector2 = sp.get("at", sp.p)
		var world := Vector3(at.x, Sim.height_at(sp.p) + float(sp.get("top", 2.7)) - (Sim.height_at(sp.p) if sp.has("top") else 0.0), at.y)
		if not on_screen.call(world):
			continue
		var fade := clampf((16.0 - dist) / 4.0, 0.0, 1.0)
		var s: Vector2 = project.call(world)
		var title := ("★ " if sp.up else "") + str(sp.name)
		var tw := title_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, name_px).x
		var pips := int(sp.stock) >= 0
		var w := tw + 18.0 + (3 * 7.5 + 5.0 if pips else 0.0)
		var h := 22.0
		var x := clampf(s.x - w * 0.5, 6.0, size.x - w - 6.0)          # never cut off at the edge
		var r := Rect2(x, s.y - h - 7.0, w, h)
		var sb := _plate_style(int(sp.team), bool(sp.up))
		var team_col: Color = TEAM_COLORS[int(sp.team)]
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var tip := Vector2(clampf(s.x, r.position.x + 8.0, r.end.x - 8.0), r.end.y + 5.0)
		draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-5, -6), tip + Vector2(5, -6)]), Color(sb.border_color, fade))
		sb.bg_color.a = 0.88 * fade
		sb.border_color.a = fade
		sb.shadow_color.a = 0.35 * fade
		draw_style_box(sb, r)
		sb.bg_color.a = 0.88
		sb.border_color.a = 1.0
		sb.shadow_color.a = 0.35
		draw_rect(Rect2(r.position + Vector2(6, 1), Vector2(r.size.x - 12, 1.5)), Color(team_col, 0.9 * fade))
		var name_col := Color("#ffe9b0") if sp.up else Color("#fff6e3")
		var tx := r.position.x + 9.0
		var ty := r.position.y + 16.0
		draw_string_outline(title_font, Vector2(tx, ty), title, HORIZONTAL_ALIGNMENT_LEFT, -1, name_px, 3, Color(0, 0, 0, 0.6 * fade))
		draw_string(title_font, Vector2(tx, ty), title, HORIZONTAL_ALIGNMENT_LEFT, -1, name_px, Color(name_col, fade))
		if pips:
			for k in 3:
				var c := Vector2(tx + tw + 8.0 + k * 7.5, r.position.y + h * 0.5 + 0.5)
				if k < int(sp.stock):
					draw_circle(c, 2.6, Color(team_col, fade))
				else:
					draw_arc(c, 2.4, 0.0, TAU, 12, Color(0.86, 0.79, 0.64, 0.6 * fade), 1.0, true)

func _draw_oracle_marker(me: Dictionary) -> void:
	# Point to our Oracle (or home, while carrying her) when she is off-screen.
	if not project.is_valid() or not on_screen.is_valid():
		return
	var goal: Vector2 = sim.oracles[me.team].pos
	if me.carrying:
		var ho: Dictionary = sim.lifting_oracle(me)
		goal = Sim.throne(me.team) if int(ho.get("team", me.team)) == me.team else Sim.cell(int(ho.team))
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
	_text(edge - dir * 22 + Vector2(0, 5), "HOME" if me.carrying else "KING", 11, col, _bold)

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
			var ab := str(sim.ability_of(me))
			label = ab.to_upper() if ab != "" else "—"
			col = Color("#35226a")
			rim = Color("#d6b8ff")
			cd = me.cd_ability
			cd_max = maxf(0.1, Sim.HAMMER_CD if ab == "hammer" else (Sim.RESURRECT_CD if ab == "resurrect" else float(Sim.CLASSES[me.cls].ab_cd)))
			ready = ab != "" and cd <= 0.0 and not me.carrying
		"dodge":
			label = "DODGE"
			cd = me.cd_dodge
			cd_max = 2.2
			ready = cd <= 0.0 and not me.carrying
		"action":
			label = {"hat_up":"UPGRADE","hat":"NEW HAT","class_full":"FULL","grab":"LIFT","throw":"THROW","workshop":"WORKSHOP","chop":"CHOP","mine":"MINE",
				"repair":"REPAIR","gather":"WORKING","repairing":"REPAIRING","ladder":"LADDER","build_ladder":"BUILDING","fish":"FISH","feed":"FEED",
				"join":"HELP LIFT","letgo":"LET GO","tower_up":"CLIMB","tower_down":"CLIMB DOWN","pick_up":"PICK UP",
				"bomb_pick":"PICK UP BOMB","bomb_throw":"THROW BOMB",
				"hat_pick":"PICK UP HAT","hat_equip_up":"WEAR UPGRADE",
				"launch_lever":"PULL LEVER"}.get(b.ctx, "USE")
			col = Color("#155258")
			rim = Color("#9ff6ef")
			if b.ctx == "hat_up":
				# Upgrade at the hat shop: gold button, cost underneath, dim when unaffordable.
				var hid: String = sim.hat_shop_upgrade(me)
				if hid != "":
					var cost: Dictionary = sim.upgrade_cost(me.team, hid)
					ready = sim.can_buy(me.team, hid)
					col = Color("#8a5a10")
					rim = Color("#ffe39a")
					_text(b.c + Vector2(-60, b.r + 18), "%dw · %ds" % [int(cost.wood), int(cost.stone)], 11, Color(1, 1, 1, 0.85), _bold, HORIZONTAL_ALIGNMENT_CENTER, 120)
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
