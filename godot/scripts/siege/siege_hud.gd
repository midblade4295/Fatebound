extends Control
const Sim_Eco = preload("res://scripts/meta/economy.gd")
# Siege HUD. The stick and the combat buttons are drawn and hit-tested by hand from raw
# InputEventScreenTouch events, because Godot's Buttons only follow the first finger and on a
# phone you hold the stick while tapping ATTACK. Modal panels (workshop, pause, result) use Buttons.
const VisualTheme = preload("res://scripts/ui/visual_theme.gd")
const UI = preload("res://scripts/app/ui.gd")
const UI2 = preload("res://scripts/app/ui2.gd")
# The old brass kinds map onto the app's tactile styles so battle panels match the menus.
const BUTTON_STYLE := {"primary":"orange", "secondary":"blue", "gold":"gold", "roll":"gold", "active":"green", "danger":"red"}   # 0.31.79: the menu skins
const Sim = preload("res://scripts/siege/siege_sim.gd")
const NetT = preload("res://scripts/siege/siege_net.gd")
const Cards = preload("res://scripts/meta/cards.gd")
const Moba = preload("res://scripts/siege/moba.gd")
const ItemIcon = preload("res://scripts/siege/item_icon.gd")   # 0.31.157 5V5: the shop's item glyphs

signal leave_requested
signal replay_requested
signal action_pressed(kind: String)
signal quick_chat(i: int)              # 0.31.111: a line from the quick chat wheel (NetT.QUICK_CHAT index)
signal res_cycled
var res_label_source: Callable   # -> float render scale
signal workshop_tools
signal workshop_buy(id: String)
signal workshop_leave
signal card_pressed(slot: int)          # 0.31.153 COMMANDER: a card in the hand tapped

const TEAM_COLORS := [Color("#5fd2f0"), Color("#ff7b52"), Color("#e2c85c")]      # (0.31.157: the jungle's monsters)

var sim
var diag
var _bar_style: StyleBox
var player_id := "you"
var player_name := "Player"         # (0.31.87: the results panel shows an earned title on it)

func vt(t: int) -> int:
	# 0.31.85: your side drawn blue, the other red, whichever team you're on (as siege_view.vt)
	if t < 0 or t > 1 or sim == null:
		return t
	return t if int(sim.by_id.get(player_id, {}).get("team", 0)) == 0 else 1 - t
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
var _block_held := false            # 0.31.61: the Crusader's shield button
var _pressed_at := {}
var _toast := ""
var _multi: Label = null                 # 0.31.29: DOUBLE KILL ... LEGENDARY
var _multi_at := -10.0
const MULTI_COLORS := [Color.WHITE, Color.WHITE, Color("#ffe08a"), Color("#ffb04a"), Color("#ff6a3d"), Color("#ff3d6e"), Color("#c77dff")]
var _toast_at := -10.0
var net_names := {}                 # 0.31.119: online, unit id -> player name (the server's "pn"), for the scoreboard
var score_panel: PanelContainer = null
var rejoin_until := -1.0            # 0.31.120: reconnecting after a dropped connection, until (ticks clock)
var idle_kick_at := -1.0            # 0.31.119: online, a bot plays for me (I was idle); when I'll be removed (s, ticks clock)
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
var war_battle := false                 # 0.31.135: a battle on the war map: no PLAY AGAIN, WAR MAP instead
var war_line := {}                      # 0.31.135: what the battle did ({"t":"war", ...}); shown on the results
var exit_to := ""                       # 0.31.135: "war": the app opens the war map after this match
var _war_box: VBoxContainer = null
var pause_btn: Button
# 0.31.111 (Kevin: "add the quick chat pings"): the horn beside the pause button opens the quick chat; a line said shows
# as a bubble over the speaker (pinned to the screen edge, with an arrow, when they're off it) and in a short feed.
var qc_btn: Button
var qc_panel: PanelContainer
var unit_world: Callable              # unit id -> its world position (Vector3.INF when unknown)
var _pings: Array = []                # {"u", "i", "at"}
var _feed: Array = []                 # {"n", "i", "at", "col"}
const PING_LIFE := 4.0
const FEED_LIFE := 6.0

static var ready_times := {}

func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_touchscreen = DisplayServer.is_touchscreen_available()
	_font = VisualTheme.BODY_FONT
	_bold = VisualTheme.BOLD_FONT
	_title = VisualTheme.TITLE_FONT
	pause_btn = UI2.button(self, "II", "blue", func():
		if pause_panel == null:
			_build_pause_panel()
		pause_panel.visible = true
		_center(pause_panel, true), "", 16, 40.0, 12.0)
	pause_btn.custom_minimum_size = Vector2(44, 40)
	pause_btn.size = Vector2(44, 40)
	qc_btn = UI2.button(self, "", "purple", func(): _toggle_qc(), "quick_chat", 14, 46.0, 14.0, UI2.icon_path("horn"))
	qc_btn.custom_minimum_size = Vector2(46, 46)
	qc_btn.size = Vector2(46, 46)
	qc_btn.add_theme_constant_override("icon_max_width", 34)
	# 0.31.8: the workshop and pause panels are built the first time they open (they cost ~370 ms at match start).
	resized.connect(_layout)
	_layout()
	ready_times["hud _ready total"] = Time.get_ticks_msec() - t0

func _layout() -> void:
	pause_btn.position = Vector2(size.x - 52, 78)
	qc_btn.position = Vector2(size.x - 104, 75)            # (left of the pause button, clear of the gate and post pips)
	if qc_panel != null:
		qc_panel.position = Vector2(size.x - qc_panel.size.x - 10, 126)

# ---------------- quick chat (0.31.111) ----------------
func _toggle_qc() -> void:
	if qc_panel == null:
		qc_panel = PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.03, 0.05, 0.14, 0.92)
		sb.border_color = Color("#c47bff")
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(16)
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		qc_panel.add_theme_stylebox_override("panel", sb)
		add_child(qc_panel)
		var g := GridContainer.new()
		g.columns = 2
		g.add_theme_constant_override("h_separation", 6)
		g.add_theme_constant_override("v_separation", 6)
		qc_panel.add_child(g)
		for i in NetT.QUICK_CHAT.size():
			var q: Dictionary = NetT.QUICK_CHAT[i]
			var ii := i
			var b := UI2.button(g, str(q.x).to_upper(), "red" if str(q.x) == "Need help!" else ("purple" if bool(q.get("all", false)) else "blue"), func():
				qc_panel.visible = false
				quick_chat.emit(ii), "qc_%d" % i, 13, 40.0, 12.0)
			b.custom_minimum_size.x = 132
		qc_panel.visible = false
	qc_panel.visible = not qc_panel.visible
	qc_panel.reset_size()
	_layout()

func add_ping(unit: String, i: int, name: String) -> void:
	# a quick chat line from `unit` (name "" for an unnamed bot -- only players speak, so it's always someone)
	if i < 0 or i >= NetT.QUICK_CHAT.size():
		return
	_pings = _pings.filter(func(p): return str(p.u) != unit)
	_pings.append({"u":unit, "i":i, "at":_time})
	var u: Dictionary = sim.by_id.get(unit, {}) if sim != null else {}
	var me: Dictionary = sim.by_id.get(player_id, {}) if sim != null else {}
	var col: Color = Color("#ffd65a") if unit == player_id else (TEAM_COLORS[vt(int(u.team))] if not u.is_empty() else Color.WHITE)
	_feed.append({"n":name if name != "" else "Ally", "i":i, "at":_time, "col":col, "enemy":not u.is_empty() and not me.is_empty() and int(u.team) != int(me.team)})
	while _feed.size() > 3:
		_feed.pop_front()

func _draw_pings() -> void:
	_pings = _pings.filter(func(p): return _time - float(p.at) < PING_LIFE)
	_feed = _feed.filter(func(f): return _time - float(f.at) < FEED_LIFE)
	var vp := Rect2(Vector2(10, 150), size - Vector2(20, 300))
	for p in _pings:
		if not unit_world.is_valid() or not project.is_valid():
			break
		var w3: Vector3 = unit_world.call(str(p.u))
		if w3 == Vector3.INF:
			continue
		var q: Dictionary = NetT.QUICK_CHAT[int(p.i)]
		var age := _time - float(p.at)
		var a := clampf(minf(age * 6.0, (PING_LIFE - age) * 2.0), 0.0, 1.0)
		var anchor: Vector3 = w3 + Vector3(0, 2.7, 0)
		var inside: bool = on_screen.is_valid() and on_screen.call(anchor)
		var sp: Vector2 = project.call(anchor) if inside else Vector2.ZERO
		var txt := str(q.x)
		var tw := _bold.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var box := Vector2(tw + 22.0, 28.0)
		var col := Color(str(q.c))
		var pos: Vector2
		var arrow := Vector2.ZERO
		if inside:
			pos = sp + Vector2(-box.x * 0.5, -box.y - 46.0 - (1.0 - minf(age * 5.0, 1.0)) * 10.0)
			pos.x = clampf(pos.x, 6.0, size.x - box.x - 6.0)          # (someone at the edge: the bubble stays on the screen)
		else:
			# off the screen: on its edge, toward them, with an arrow
			var me3: Vector3 = unit_world.call(player_id)
			var dir := Vector2(w3.x - me3.x, w3.z - me3.z) if me3 != Vector3.INF else Vector2(0, -1)
			dir = dir.normalized() if dir.length() > 0.01 else Vector2(0, -1)
			var c := vp.get_center()
			var k := minf(absf(vp.size.x * 0.5 / maxf(absf(dir.x), 0.001)), absf(vp.size.y * 0.5 / maxf(absf(dir.y), 0.001)))
			var edge := c + dir * k
			pos = Vector2(clampf(edge.x - box.x * 0.5, vp.position.x, vp.end.x - box.x), clampf(edge.y - box.y * 0.5, vp.position.y, vp.end.y - box.y))
			arrow = dir
		var r := Rect2(pos, box)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.03, 0.04, 0.1, 0.88 * a)
		bg.border_color = Color(col, a)
		bg.set_border_width_all(2)
		bg.set_corner_radius_all(12)
		draw_style_box(bg, r)
		if inside:
			var tip := Vector2(clampf(sp.x, r.position.x + 12.0, r.end.x - 12.0), r.end.y)
			draw_colored_polygon(PackedVector2Array([tip + Vector2(-7, -1), tip + Vector2(7, -1), tip + Vector2(0, 9)]), Color(col, a))
		else:
			var tip2 := r.get_center() + arrow * (maxf(box.x, box.y) * 0.5 + 10.0)
			var side := Vector2(-arrow.y, arrow.x) * 7.0
			draw_colored_polygon(PackedVector2Array([tip2, tip2 - arrow * 11.0 + side, tip2 - arrow * 11.0 - side]), Color(col, a))
		draw_string_outline(_bold, r.position + Vector2(11, 20), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(0, 0, 0, 0.7 * a))
		draw_string(_bold, r.position + Vector2(11, 20), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(col.lightened(0.25), a))
	var y := 210.0                                          # (under the gate / post row and the toast)
	for f in _feed:
		var a2 := clampf((FEED_LIFE - (_time - float(f.at))) * 1.5, 0.0, 1.0)
		var q2: Dictionary = NetT.QUICK_CHAT[int(f.i)]
		var nm := str(f.n) + ": "
		var nw := _bold.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string_outline(_bold, Vector2(14, y), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.7 * a2))
		draw_string(_bold, Vector2(14, y), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(f.col, a2))
		draw_string_outline(_bold, Vector2(14 + nw, y), str(q2.x), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.7 * a2))
		draw_string(_bold, Vector2(14 + nw, y), str(q2.x), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(Color(str(q2.c)).lightened(0.3), a2))
		y += 18.0

# ---------- panels ----------
func _panel(min_w: float, kind := "night") -> PanelContainer:
	# 0.31.79: a gold-framed damask (or parchment) panel, like the menus
	var p := PanelContainer.new()
	var ps := StyleBoxEmpty.new()
	ps.content_margin_left = 20
	ps.content_margin_right = 20
	ps.content_margin_top = 18
	ps.content_margin_bottom = 18
	p.add_theme_stylebox_override("panel", ps)
	p.custom_minimum_size = Vector2(min_w, 0)
	p.visible = false
	add_child(p)
	UI2.plate(p, kind, 22.0, "brown" if kind == "parch" else "gold", {"rim": 4.0, "shadow_y": 10.0, "shadow_alpha": 0.7, "shadow_soft": 12.0})
	return p

func _unroll(p: Control) -> void:
	# the panel drops open from the top
	var fit := float(p.get_meta("fit", 1.0))
	p.pivot_offset = Vector2(p.size.x * 0.5, 0)
	p.scale = Vector2(fit, fit * 0.15)
	p.modulate.a = 0.0
	var tw := p.create_tween().set_parallel()
	tw.tween_property(p, "scale", Vector2.ONE * fit, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(p, "modulate:a", 1.0, 0.15)

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
	var b := UI2.button(parent, text, str(BUTTON_STYLE.get(kind, "blue")), cb, "", 17, 50.0, 14.0)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = true
	return b

func _center(p: Control, unroll := false) -> void:
	# wrapping labels report no width until laid out, so give them one (else a panel measures them a letter wide)
	for l in p.find_children("*", "Label", true, false):
		if (l as Label).autowrap_mode != TextServer.AUTOWRAP_OFF and (l as Label).custom_minimum_size.x < 1.0:
			(l as Label).custom_minimum_size.x = 200.0
	# re-placed whenever its measured size settles (the labels learn their heights a frame or two later)
	if not p.has_meta("placed"):
		p.set_meta("placed", true)
		p.minimum_size_changed.connect(func():
			if is_instance_valid(p) and p.visible:
				_place.call_deferred(p))
	_place(p)
	if unroll:
		p.modulate.a = 0.0
		if is_inside_tree():
			var t := get_tree().create_timer(0.05)
			var pref: WeakRef = weakref(p)       # (0.31.144: held weakly -- a freed panel in a lambda logs an error)
			t.timeout.connect(func():
				var pp := pref.get_ref() as Control
				if pp != null:
					_place(pp)
					_unroll(pp))

func _place(p: Control) -> void:
	p.size = Vector2(minf(p.custom_minimum_size.x, size.x - 20), 0)
	p.reset_size()
	# 0.31.79: a panel taller than the screen (a long results list) is shrunk to fit rather than cut off
	var fit := minf(1.0, (size.y - 24.0) / maxf(1.0, p.size.y))
	p.set_meta("fit", fit)
	p.pivot_offset = Vector2(p.size.x * 0.5, 0)
	p.scale = Vector2.ONE * fit
	p.position = Vector2((size.x - p.size.x) * 0.5, maxf(12.0, (size.y - p.size.y * fit) * 0.5))

func _build_workshop_panel() -> void:
	workshop_panel = _panel(340)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 9)
	workshop_panel.add_child(v)
	UI2.center(UI2.text(v, "THE WORKSHOP", 26, UI2.GOLD))
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
	_center(pause_panel, true)

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
	# 0.31.79: a parchment sheet -- how to win in three steps with the 3D icons, the tricks, then RESUME.
	pause_panel = _panel(330, "parch")
	var ink := Color("#3b2412")
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	pause_panel.add_child(v)
	UI2.center(UI2.text(v, "PAUSED", 38, UI2.GOLD, ink, 9))
	var hw := UI.label(v, "HOW TO WIN", 11, Color("#8a6a44"), UI.HEAVY_FONT)
	hw.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for st in [["castle", "1 · BREAK IN", "Smash their gate or fly over the wall"], ["crown", "2 · CARRY YOUR KING HOME", "From their dungeon to your throne room"],
			["trophy", "3 · FIRST TO %d RESCUES" % Sim.WIN_RESCUES, "wins the siege"]]:
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 10)
		v.add_child(r)
		var disc := Control.new()
		disc.custom_minimum_size = Vector2(50, 50)
		r.add_child(disc)
		UI2.plate(disc, "parch", 25.0, "gold", {"rim": 3.0, "shadow_y": 3.0, "pattern_mix": 0.0, "fill_top": Color("#fff8e0"), "fill_bottom": Color("#e9cf94")})
		var ic := UI2.icon(disc, str(st[0]), 40.0)
		ic.position = Vector2(5, 3)
		var tv := VBoxContainer.new()
		tv.add_theme_constant_override("separation", 0)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(tv)
		UI2.text(tv, str(st[1]), 15, ink, ink, 0, false)
		var sl := UI.label(tv, str(st[2]), 12, Color("#5d3a1c"), UI.HEAVY_FONT)
		sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var tricks := UI.label(v, "Standing by your King in their dungeon heals you. Catch fish from the river (ACTION on a bank) and feed them to THEIR King: each size needs another lifter (up to 6). Left on the ground, a King throws a tantrum that knocks everyone back. Workers gather, repair gates and fund upgrades.", 11, Color("#5d3a1c"), UI.HEAVY_FONT)
	tricks.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tricks.custom_minimum_size = Vector2(290, 0)
	var rb := _button(v, "RESUME", "active", func(): pause_panel.visible = false)
	rb.custom_minimum_size.y = 58
	rb.add_theme_font_size_override("font_size", 26)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	var res_btn := _button(row, "RESOLUTION: 100%", "secondary", func(): pass)
	res_btn.add_theme_font_size_override("font_size", 13)
	res_btn.pressed.connect(func():
		res_cycled.emit()
		res_btn.text = "RESOLUTION: %d%%" % int(res_label_source.call() * 100.0) if res_label_source.is_valid() else "RESOLUTION")
	pause_panel.visibility_changed.connect(func():
		if res_label_source.is_valid(): res_btn.text = "RESOLUTION: %d%%" % int(res_label_source.call() * 100.0))
	var lv := _button(row, "LEAVE MATCH", "danger", func(): leave_requested.emit())
	lv.add_theme_font_size_override("font_size", 13)

func show_result(result: Dictionary = {}) -> void:
	# 0.31.79: a ribbon banner (VICTORY / DEFEAT / DRAW) with a crown and a sunburst behind a win, the score in team
	# colours, your match, the spoils as a table, chests with their pictures, then PLAY AGAIN / HOME.
	if result_panel != null:
		return
	var me: Dictionary = sim.by_id.get(player_id, {})
	result_panel = _panel(340)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	result_panel.add_child(v)
	var won: bool = sim.winner == me.team
	var draw: bool = sim.winner == -1
	var head := Control.new()
	head.custom_minimum_size = Vector2(300, 92)
	v.add_child(head)
	if won:
		var ry := UI2.rays(head, 420.0, Color(1.0, 0.86, 0.45), 30.0, 0.45)
		head.resized.connect(func(): ry.position = Vector2(head.size.x * 0.5 - 210.0, -160.0))
		var cr := UI2.icon(head, "crown", 54.0)
		head.resized.connect(func(): cr.position = Vector2(head.size.x * 0.5 - 27.0, -26.0))
		UI2.bob(cr, 4.0, 1.0)
	var title := "DRAW" if draw else ("VICTORY!" if won else "DEFEAT")
	var cols: Array = [Color("#ff8a6a"), Color("#a8221a")] if won else ([Color("#5d89f0"), Color("#1b2d78")] if draw else [Color("#6b7486"), Color("#2a2f3c")])
	var rib := UI2.ribbon(head, title, "", 300.0, 58.0, cols)
	head.resized.connect(func(): rib.position = Vector2((head.size.x - 300.0) * 0.5, 30.0))
	# score
	var sc := HBoxContainer.new()
	sc.add_theme_constant_override("separation", 0)
	sc.custom_minimum_size = Vector2(0, 62)
	v.add_child(sc)
	for side in 3:
		var cell := VBoxContainer.new()
		cell.alignment = BoxContainer.ALIGNMENT_CENTER
		cell.add_theme_constant_override("separation", 0)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL if side != 1 else Control.SIZE_FILL
		cell.custom_minimum_size = Vector2(92 if side == 1 else 0, 0)
		sc.add_child(cell)
		if side == 1:
			UI2.center(UI2.body(cell, "KINGS" if sim.moba != null else "RESCUES", 11, UI2.GOLD, false))
			UI2.center(UI2.body(cell, "KOs %d–%d" % [sim.kills[me.team], sim.kills[1 - me.team]], 10, UI2.MUTED, false))
			continue
		var mine := side == 0
		var t: int = me.team if mine else 1 - me.team
		UI2.plate(cell, "royal", 14.0, "gold", {"rim": 0.0, "outline": 2.0, "pattern_mix": 0.0,
			"fill_top": TEAM_COLORS[vt(t)].lightened(0.15), "fill_bottom": TEAM_COLORS[vt(t)].darkened(0.45), "shadow_y": 3.0})
		UI2.center(UI2.body(cell, "YOU" if mine else "ENEMY", 10, Color.WHITE, false))
		UI2.center(UI2.text(cell, str(sim.score[t]), 30, Color.WHITE, Color("#0a1238"), 7))
	# you
	var you := HBoxContainer.new()
	you.alignment = BoxContainer.ALIGNMENT_CENTER
	you.add_theme_constant_override("separation", 6)
	v.add_child(you)
	for ch in [["skull", "%d KOs" % me.kills], ["helmet", "%d downs" % me.deaths], ["crown", "%d rescue%s" % [me.rescues, "" if me.rescues == 1 else "s"]]]:
		var c := UI2.chip(you, "", Color(0.01, 0.02, 0.08, 0.8), Color.WHITE, Color(UI2.GOLD, 0.4))
		var cl: Label = c.get_child(0)
		c.remove_child(cl)
		cl.queue_free()
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 3)
		c.add_child(r)
		UI2.icon(r, str(ch[0]), 20.0)
		UI2.body(r, str(ch[1]), 11, Color.WHITE, false)
	if me.gathered > 0 or me.gate_dmg > 0.0:
		UI2.center(UI2.body(v, "Gathered %d · gate damage %d" % [int(me.gathered), int(me.gate_dmg)], 12, Color("#cfe8b8"), false))
	if sim.moba != null:
		# 0.31.155 5V5 (the test): the towers each side brought down, your level; no rewards yet
		UI2.center(UI2.body(v, "Towers down: theirs %d · yours %d  ·  you reached level %d" % [sim.moba.towers_down(1 - int(me.team)),
			sim.moba.towers_down(int(me.team)), int(me.get("level", 1))], 12, Color("#ffcf7a"), false))
		UI2.center(UI2.body(v, "Gold earned %d · %d item%s" % [int(me.get("gold_total", 0.0)), (me.get("items", []) as Array).size(),
			"" if (me.get("items", []) as Array).size() == 1 else "s"], 12, Color("#ffe39a"), false))
		UI2.center(UI2.body(v, "5V5 is a test -- no rewards yet", 11, UI2.MUTED, false))
	if sim.commander:
		# 0.31.153 COMMANDER (the test): the cards each side played; no rewards yet
		UI2.center(UI2.body(v, "Cards played: you %d · enemy %d" % [int(sim.cmd[me.team].played), int(sim.cmd[1 - int(me.team)].played)], 12, Color("#d6a2ff"), false))
		UI2.center(UI2.body(v, "COMMANDER is a test -- no rewards yet", 11, UI2.MUTED, false))
	_mvp_strip(v)
	var rw: Dictionary = result.get("rewards", {})
	if not rw.is_empty():
		var tab := PanelContainer.new()
		var ts := StyleBoxEmpty.new()
		for side in ["left", "right", "top", "bottom"]:
			ts.set("content_margin_" + side, 12.0)
		tab.add_theme_stylebox_override("panel", ts)
		v.add_child(tab)
		UI2.plate(tab, "parch", 14.0, "brown", {"rim": 3.0})
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 1)
		tab.add_child(box)
		var ink := Color("#3b2412")
		var hdr := HBoxContainer.new()
		box.add_child(hdr)
		var ht := UI2.text(hdr, "SPOILS OF WAR", 15, ink, ink, 0, false)
		ht.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for hh in ["GOLD", "PASS"]:
			var hl := UI.label(hdr, hh, 9, Color("#7a5530"), UI.HEAVY_FONT)
			hl.custom_minimum_size = Vector2(52, 0)
			hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		for ln in rw.lines:
			var row := HBoxContainer.new()
			box.add_child(row)
			var name_l := UI.label(row, str(ln.label), 12, ink, UI.HEAVY_FONT)
			name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			for val in [["+%d" % int(ln.gold), Color("#8a5a0a")], ["+%d" % int(ln.pass), Color("#6a2bb8")]]:
				var vl := UI.label(row, str(val[0]), 12, val[1], UI.HEAVY_FONT)
				vl.custom_minimum_size = Vector2(52, 0)
				vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var tot := HBoxContainer.new()
		tot.alignment = BoxContainer.ALIGNMENT_CENTER
		tot.add_theme_constant_override("separation", 10)
		v.add_child(tot)
		var totals := [["res://assets/ui/currency/coin.png", "+%d" % int(rw.gold), UI2.GOLD], ["", "+%d XP" % int(rw.xp), UI2.CYAN], ["", "+%d PASS" % int(rw.pass), UI2.PURPLE]]
		if int(result.get("embers", 0)) > 0:                    # 0.31.93: Embers for the Forge
			totals.append(["res://assets/ui/currency/embers.png", "+%d" % int(result.embers), Color("#ff9a3c")])
		if totals.size() > 3:
			tot.add_theme_constant_override("separation", 6)       # (four totals fit a narrow phone)
		for tv in totals:
			var tr := HBoxContainer.new()
			tr.add_theme_constant_override("separation", 3)
			tot.add_child(tr)
			if str(tv[0]) != "":
				UI2.img(tr, str(tv[0]), 24.0 if totals.size() > 3 else 26.0)
			UI2.text(tr, str(tv[1]), 16 if totals.size() > 3 else 18, tv[2], UI2.INK, 5)
		for lv in result.get("levels", []):
			UI2.center(UI2.text(v, "LEVEL UP!  LEVEL %d" % int(lv.level), 18, UI2.CYAN, Color("#06283a"), 5))
			UI2.center(UI2.body(v, "+%d gold%s" % [int(lv.reward.get("gold", 0)), ("  ·  +%d gems" % int(lv.reward.gems)) if lv.reward.has("gems") else ""], 12, Color.WHITE, false))
		for ch in result.get("chests", []):                     # 0.31.37
			var kind := str(ch.kind)
			var cn := str(Sim_Eco.CHESTS[kind].name)
			var cr := HBoxContainer.new()
			cr.add_theme_constant_override("separation", 8)
			v.add_child(cr)
			var ci := UI2.img(cr, UI2.V2 + "chests/%s_icon.png" % str({"wooden": "wood"}.get(kind, kind)), 52.0)
			if not bool(ch.get("full", false)):
				UI2.bob(ci, 3.0, 1.0)
			var cv := VBoxContainer.new()
			cv.add_theme_constant_override("separation", 0)
			cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cr.add_child(cv)
			if bool(ch.get("full", false)):
				UI2.text(cv, cn.to_upper(), 14, Color.WHITE)
				UI2.body(cv, "Chest slots full -- turned into %d gold" % int(ch.gold), 11, UI2.SOFT)
			else:
				UI2.text(cv, "%s EARNED!" % cn.to_upper(), 15, Color(str(Sim_Eco.CHESTS[kind].color)))
				UI2.body(cv, "Unlock it from Home", 11, UI2.SOFT)
		for tid in result.get("titles", []):                    # 0.31.87: a title earned this match
			var trar := NetT.title_rarity(str(tid))
			var tbox := UI2.frame(v, {"common": "night", "rare": "royal", "epic": "purple", "legendary": "ember"}.get(trar, "night"), 8, 14.0,
				{"common": "silver", "rare": "blue", "epic": "purple", "legendary": "orange"}.get(trar, "gold"), {"pattern_mix": 0.0})
			if trar == "legendary":
				UI2.sweep(tbox.get_parent() as Control, 2.2, 60.0, 0.35)
			UI2.center(UI2.text(tbox, "TITLE EARNED!", 15, UI2.GOLD))
			var tl := HBoxContainer.new()
			tl.alignment = BoxContainer.ALIGNMENT_CENTER
			tl.add_theme_constant_override("separation", 0)
			tbox.add_child(tl)
			for part in NetT.title_parts(str(player_name), str(tid)):
				UI2.text(tl, str(part[0]), 17, TAG_COL.get(trar, Color.WHITE) if part[1] else Color.WHITE, Color("#120a02"), 5)
			UI2.center(UI2.body(tbox, "%s · wear it from the Locker" % trar.capitalize(), 11, Color(1, 1, 1, 0.8), false))
		var tiers: Array = result.get("tiers", [])
		if not tiers.is_empty():
			UI2.center(UI2.body(v, "Siege Pass tier %s reached — claim it on the Pass screen" % (str(tiers[-1]) if tiers.size() == 1 else "%d–%d" % [tiers[0], tiers[-1]]), 12, Color("#ffcf7a")))
		for c in (result.get("challenges", []) as Array).slice(0, 4):
			UI2.center(UI2.body(v, "%s  %s  %d/%d" % ["✔" if c.done else "•", str(c.text), mini(int(c.progress), int(c.goal)), int(c.goal)], 11, UI2.GREEN if c.done else UI2.MUTED, false))
		# 0.31.97: class quests -- the steps this match moved, and a banner when one is ready to claim
		var qlines: Array = result.get("quests", [])
		var qready := qlines.filter(func(x): return bool(x.done))
		if not qready.is_empty():
			var qb := UI2.frame(v, "ember", 8, 14.0, "orange", {"pattern_mix": 0.0})
			UI2.sweep(qb.get_parent() as Control, 2.2, 60.0, 0.35)
			UI2.center(UI2.text(qb, "QUEST STEP DONE!", 15, Color("#ffd27a")))
			for ql in qready.slice(0, 2):
				UI2.center(UI2.body(qb, "%s: %s" % [str(Sim_Eco.CLASS_NAMES.get(str(ql.cls), "")), str(ql.text)], 11, Color.WHITE, false))
			UI2.center(UI2.body(qb, "Claim it in Quests from Home", 10, Color(1, 1, 1, 0.75), false))
		for ql in qlines.filter(func(x): return not bool(x.done)).slice(0, 2):
			UI2.center(UI2.body(v, "⚔  %s quest  %s  %d/%d" % [str(Sim_Eco.CLASS_NAMES.get(str(ql.cls), "")), str(ql.text), int(ql.progress), int(ql.goal)], 11, Color("#ffcf7a"), false))
	if war_battle:
		_war_box = VBoxContainer.new()                      # 0.31.135: what the battle did (now, or when it arrives)
		_war_box.add_theme_constant_override("separation", 2)
		v.add_child(_war_box)
		v.move_child(_war_box, 2)
		_fill_war()
	var br := HBoxContainer.new()
	br.add_theme_constant_override("separation", 10)
	v.add_child(br)
	_button(br, "HOME", "secondary", func(): leave_requested.emit())
	var sb := _button(br, "SCORES", "gold", func(): show_scoreboard())         # 0.31.119
	sb.set_meta("key", "scoreboard")
	if war_battle:
		var wm := _button(br, "WAR MAP", "primary", func():
			exit_to = "war"
			leave_requested.emit())
		wm.size_flags_stretch_ratio = 1.5
		wm.set_meta("key", "war_map")
		UI2.sweep(wm)
	else:
		var pa := _button(br, "PLAY AGAIN", "primary", func(): replay_requested.emit())
		pa.size_flags_stretch_ratio = 1.5
		UI2.sweep(pa)
	result_panel.visible = true
	_center(result_panel, true)
	if pause_panel != null:
		pause_panel.visible = false

# ---------- the war map's battle (0.31.135) ----------
func show_war(m: Dictionary) -> void:
	war_line = m
	_fill_war()

func _fill_war() -> void:
	# a gold frame on the results: the territory, the crowns, the points and the clan's bar (or, defending, if it held)
	if not is_instance_valid(_war_box):
		return
	for c in _war_box.get_children():
		c.queue_free()
	var m := war_line
	var f := UI2.frame(_war_box, "ember", 8, 14.0, "orange", {"pattern_mix": 0.0})
	var place := str(m.get("name", "the territory")).to_upper()
	if m.is_empty():
		UI2.center(UI2.body(f, "Counting the battle...", 12, UI2.MUTED, false))
		return
	if bool(m.get("def", false)):
		UI2.center(UI2.text(f, ("%s HELD!" if bool(m.get("held", false)) else "%s LOST") % place, 16, Color("#ffd27a")))
		UI2.center(UI2.body(f, "You defended it for your house" if bool(m.get("held", false)) else "The attackers took it", 11, Color.WHITE, false))
		return
	if bool(m.get("helped", false)):
		UI2.center(UI2.text(f, "BATTLE FOR %s" % place, 15, Color("#ffd27a")))
		# (0.31.150: no daily attempts -- "helped" is one of another clan of the attackers' house: its bar moved, not yours)
		UI2.center(UI2.body(f, "You fought for your house beside another clan (its bar moves, not your clan's)", 11, Color.WHITE, false))
		return
	if bool(m.get("late", false)):
		UI2.center(UI2.text(f, "BATTLE FOR %s" % place, 15, Color("#ffd27a")))
		UI2.center(UI2.body(f, "The week ended before the battle did -- it doesn't count on the new map", 11, Color.WHITE, false))
		return
	var crowns := []
	if bool(m.get("gate", false)):
		crowns.append("gate")
	if bool(m.get("king", false)):
		crowns.append("rescue")
	if bool(m.get("won", false)):
		crowns.append("win")
	UI2.center(UI2.text(f, ("%s IS YOURS!" % place) if bool(m.get("took", false)) else "BATTLE FOR %s" % place, 16, Color("#ffd27a")))
	UI2.center(UI2.body(f, "%s  %s   %+d points" % ["♛".repeat(int(m.get("crowns", 0))) if int(m.get("crowns", 0)) > 0 else "no crowns",
		("(" + ", ".join(crowns) + ")") if not crowns.is_empty() else "", int(m.get("pts", 0))], 13, Color.WHITE, false))
	if not bool(m.get("took", false)):
		UI2.center(UI2.body(f, "Your clan: %d / %d to take it" % [int(m.get("bar", 0)), int(m.get("need", 0))], 11, Color(1, 1, 1, 0.8), false))
	elif m.get("reward", null) is Dictionary:
		# 0.31.151: the land taken -- the fighters' reward (already in the account)
		var rw: Dictionary = m.reward
		var bits := []
		if int(rw.get("gold", 0)) > 0:
			bits.append("+%d gold" % int(rw.gold))
		if int(rw.get("gems", 0)) > 0:
			bits.append("+%d gems" % int(rw.gems))
		if str(rw.get("chest", "")) != "":
			bits.append("a %s" % str(Sim_Eco.CHESTS.get(str(rw.chest), {}).get("name", "chest")))
		var rl := UI2.body(f, "Your reward: " + "  ·  ".join(bits), 12, Color("#ffd27a"), false)
		rl.name = "WarReward"
		UI2.center(rl)

# ---------- scoreboard and MVP (0.31.119, Kevin: "Do all" -- a proper end-of-match screen) ----------
# Every unit's knockouts, downs, rescues, gathering, gate damage and fish fed come with the snapshots (and are the sim's
# own offline), so the board is the match as the server counted it. Points: a rescue 300, a knockout 20, a fish fed
# to their King 30, gathering 2 a load, gate damage 1 per 10. Bots are on the board too (as "Bot · <class>"): most
# matches are mostly bots, and an honest board says when one outplayed everybody.
const MVP_RESCUE := 300
const MVP_KO := 20
const MVP_FED := 30
const MVP_GATHER := 2
const MVP_GATE := 0.1

static func points(u: Dictionary) -> int:
	return int(u.get("rescues", 0)) * MVP_RESCUE + int(u.get("kills", 0)) * MVP_KO + int(u.get("fed", 0)) * MVP_FED \
		+ int(u.get("gathered", 0)) * MVP_GATHER + int(float(u.get("gate_dmg", 0.0)) * MVP_GATE)

func display_name(u: Dictionary) -> String:
	if str(u.id) == player_id:
		return player_name
	if net_names.has(str(u.id)):
		return str(net_names[str(u.id)])
	return "Bot · %s" % sim.class_label(u)

func is_player(u: Dictionary) -> bool:
	return str(u.id) == player_id or net_names.has(str(u.id))

func ranking(team := -1) -> Array:
	# units by points (then knockouts, then fewer downs); team -1 = everyone
	var out: Array = sim.units.filter(func(u): return (team < 0 or int(u.team) == team) and (sim.moba == null or bool(u.get("hero", false))))
	out.sort_custom(func(a, b):
		var pa := points(a)
		var pb := points(b)
		if pa != pb:
			return pa > pb
		if int(a.kills) != int(b.kills):
			return int(a.kills) > int(b.kills)
		if int(a.deaths) != int(b.deaths):
			return int(a.deaths) < int(b.deaths)
		return is_player(a) and not is_player(b))
	return out

func mvp() -> Dictionary:
	var r := ranking()
	return r[0] if not r.is_empty() and points(r[0]) > 0 else {}

func _mvp_strip(v: VBoxContainer) -> void:
	var m := mvp()
	if m.is_empty():
		return
	var mine := str(m.id) == player_id
	var box := UI2.frame(v, "ember" if mine else "royal", 6, 14.0, "orange" if mine else "gold", {"pattern_mix": 0.0})
	box.name = "MvpStrip"
	if mine:
		UI2.sweep(box.get_parent() as Control, 2.2, 60.0, 0.4)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	UI2.icon(row, "crown", 30.0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	row.add_child(col)
	var head := UI2.text(col, "YOU ARE THE MVP!" if mine else "MVP  ·  %s" % display_name(m), 16 if mine else 15,
		UI2.GOLD if mine else Color.WHITE, Color("#1a0c02"), 5)
	head.name = "MvpName"
	var bits := []
	if int(m.rescues) > 0:
		bits.append("%d rescue%s" % [int(m.rescues), "" if int(m.rescues) == 1 else "s"])
	bits.append("%d KOs" % int(m.kills))
	bits.append("%d pts" % points(m))
	UI2.body(col, " · ".join(bits), 11, Color(1, 1, 1, 0.85), false)

func show_scoreboard() -> void:
	# both sides, best first: the top 6 of each (and you, wherever you placed)
	if score_panel != null:
		score_panel.queue_free()
	score_panel = _panel(360)
	score_panel.name = "Scoreboard"
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	score_panel.add_child(v)
	UI2.center(UI2.text(v, "SCOREBOARD", 24, UI2.GOLD, Color("#1a0c02"), 6))
	var me: Dictionary = sim.by_id.get(player_id, {})
	var my_team := int(me.get("team", 0))
	for side in [my_team, 1 - my_team]:
		var hdr := HBoxContainer.new()
		hdr.add_theme_constant_override("separation", 4)
		v.add_child(hdr)
		var hl := UI2.text(hdr, "YOUR SIDE" if side == my_team else "ENEMY", 14, TEAM_COLORS[vt(side)], Color("#0a1238"), 4)
		hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for hh in [["KO", 34], ["♛", 26], ["PTS", 46]]:
			var hc := UI.label(hdr, str(hh[0]), 10, UI2.MUTED, UI.HEAVY_FONT)
			hc.autowrap_mode = TextServer.AUTOWRAP_OFF
			hc.custom_minimum_size = Vector2(float(hh[1]), 0)
			hc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var rows := ranking(side)
		var shown := rows.slice(0, 6)
		var my_rank := rows.find(me)
		if side == my_team and my_rank >= 6:
			shown.append(me)
		for u in shown:
			_score_row(v, u, rows.find(u) + 1, str(u.id) == player_id, side)
	UI2.center(UI2.body(v, "Points: rescue %d · KO %d · fish %d · gathering %d · gate dmg ÷%d" % [MVP_RESCUE, MVP_KO, MVP_FED, MVP_GATHER, int(1.0 / MVP_GATE)], 10, UI2.MUTED, true))
	var back := _button(v, "BACK", "secondary", func():
		score_panel.visible = false                  # (hidden, not freed: its opening animation may still be running)
		if result_panel != null:
			result_panel.visible = true
			_center(result_panel))
	back.set_meta("key", "scoreboard_back")
	if result_panel != null:
		result_panel.visible = false
	score_panel.visible = true
	_center(score_panel, true)

func _score_row(v: VBoxContainer, u: Dictionary, rank: int, mine: bool, side: int) -> void:
	var row := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(UI2.GOLD, 0.22) if mine else Color(TEAM_COLORS[vt(side)], 0.08)
	st.set_corner_radius_all(8)
	st.content_margin_left = 6
	st.content_margin_right = 6
	st.content_margin_top = 3
	st.content_margin_bottom = 3
	if mine:
		st.border_color = UI2.GOLD
		st.set_border_width_all(1)
	row.add_theme_stylebox_override("panel", st)
	v.add_child(row)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	row.add_child(h)
	var rl := UI.label(h, "%d" % rank, 12, UI2.GOLD if rank == 1 else UI2.MUTED, UI.HEAVY_FONT)
	rl.autowrap_mode = TextServer.AUTOWRAP_OFF
	rl.custom_minimum_size = Vector2(18, 0)
	var name_col := Color.WHITE if is_player(u) else Color(1, 1, 1, 0.62)
	var nl := UI.label(h, display_name(u), 13, UI2.GOLD if mine else name_col, UI.HEAVY_FONT)
	nl.autowrap_mode = TextServer.AUTOWRAP_OFF
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nl.clip_text = true
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	for val in [[str(int(u.kills)), 34], [str(int(u.rescues)), 26], [str(points(u)), 46]]:
		var vl := UI.label(h, str(val[0]), 13, Color.WHITE, UI.HEAVY_FONT)
		vl.autowrap_mode = TextServer.AUTOWRAP_OFF
		vl.custom_minimum_size = Vector2(float(val[1]), 0)
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

func toast(text: String, color := Color.WHITE) -> void:
	_toast = text
	_toast_at = _time
	_toast_color = color

func on_event(e: Dictionary) -> void:
	var me: Dictionary = sim.by_id.get(player_id, {})
	if me.is_empty():
		return
	_kf_event(e, me)
	var mine: bool = e.get("team", -1) == me.team
	if str(e.k) == "class_full" and str(e.get("id", "")) == str(player_id):
		toast("%s full · %d/%d" % [str(Sim.CLASSES.get(str(e.cls), {"name":str(e.cls).capitalize()}).get("name", str(e.cls).capitalize())) + ("s" if str(e.cls) != "worker" else "s"), int(e.n), int(e.cap)], VisualTheme.GOLD)
		return
	match str(e.k):
		"level":
			if str(e.get("id", "")) == str(player_id):
				toast("LEVEL %d!  PICK AN UPGRADE" % int(e.level), VisualTheme.GOLD)
		"tower_immune":
			toast("That tower is protected -- take the one in front of it first", Color("#ffcf7a"))
		"king_immune":
			toast("Their King is protected until one of his gates falls", Color("#ffcf7a"))
		"king_down":
			toast("THEIR KING IS DEFEATED!" if int(e.get("team", -1)) != int(me.team) else "OUR KING HAS FALLEN", VisualTheme.GOLD if int(e.get("team", -1)) != int(me.team) else VisualTheme.RED)
		"ult_ready":                                     # 0.31.157 5V5
			if str(e.get("id", "")) == str(player_id):
				var un := str(sim.moba.ult_info(me).get("name", "ULTIMATE"))
				toast(("ULTIMATE READY: %s!" % un) if int(e.rank) < 2 else ("%s IS STRONGER NOW" % un), Color("#ffb04a"))
		"buff":
			if str(e.get("id", "")) == str(player_id):
				toast("%s! %s" % [str(sim.moba.BUFF_NAMES.get(str(e.buff), "")), "Abilities recharge faster" if str(e.buff) == "arcane" else "You hit harder"], Color("#7fb8ff") if str(e.buff) == "arcane" else Color("#ff9a5a"))
		"lord_down":
			toast("WE SLEW THE BONE LORD! Gold for all, and his blessing" if int(e.get("team", -1)) == int(me.team) else "THEY SLEW THE BONE LORD", VisualTheme.GOLD if int(e.get("team", -1)) == int(me.team) else VisualTheme.RED)
		"camp_up":
			if str(e.get("kind", "")) == "lord":
				toast("THE BONE LORD HAS RISEN ON THE ISLAND", Color("#d8c2ff"))
		"lord_march":                                    # 0.31.158 5V5: the slain Lord marches for the slayers
			toast("THE BONE LORD MARCHES WITH US DOWN THE MIDDLE!" if int(e.get("team", -1)) == int(me.team) else "THE BONE LORD MARCHES ON US -- MIDDLE LANE!",
				VisualTheme.GOLD if int(e.get("team", -1)) == int(me.team) else VisualTheme.RED)
		"gate_rebuilt":
			toast("Our gate is rebuilt" if int(e.get("team", -1)) == int(me.team) else "Their gate is rebuilt", Color("#e8dcc0"))
		"plate":
			if (e.get("ids", []) as Array).has(str(player_id)):
				toast("TOWER PLATE! +%d gold" % int(e.get("gold", 0)), VisualTheme.GOLD)
		"ward":
			if str(e.get("id", "")) == str(player_id):
				toast("Ward placed -- it watches %d s" % int(sim.moba.vision.WARD_LIFE), Color("#8fe3ff"))
		"buy":
			if str(e.get("id", "")) == str(player_id):
				toast("Bought %s" % str(sim.moba.ITEMS[str(e.item)].name), VisualTheme.GOLD)
		"sell":
			if str(e.get("id", "")) == str(player_id):
				toast("Sold %s · +%d gold" % [str(sim.moba.ITEMS[str(e.item)].name), int(e.gold)], Color("#e8dcc0"))
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
	if not me.is_empty() and me.cls == "knight" and bool(me.get("up", false)):
		out.append({"id":"block", "c":br + Vector2(-262, -64), "r":30.0})     # the Crusader keeps his shield
	if sim.moba != null and not me.is_empty() and bool(me.get("hero", false)) and ctx == "":
		out.append({"id":"ult", "c":br + Vector2(-172, -182), "r":36.0})      # 0.31.157 5V5: the ultimate (level 6)
	if sim.moba != null and not me.is_empty() and bool(me.get("hero", false)):
		out.append({"id":"ward", "c":br + Vector2(-150, -264), "r":26.0})     # 0.31.158 5V5: a ward at your feet
	return out

func _modal_open() -> bool:
	return (workshop_panel != null and workshop_panel.visible) or paused() or (result_panel != null and result_panel.visible) \
		or (score_panel != null and is_instance_valid(score_panel) and score_panel.visible) or shop_open()

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
			KEY_R: action_pressed.emit("ult")             # 0.31.157 5V5
			KEY_T: action_pressed.emit("ward")            # 0.31.158 5V5
			KEY_B:
				if sim.moba != null:
					open_shop()

func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	if pressed:
		if _modal_open() or pause_btn.get_global_rect().has_point(pos + global_position) \
				or (qc_btn.visible and qc_btn.get_global_rect().has_point(pos + global_position)):
			return
		if qc_panel != null and qc_panel.visible:
			if qc_panel.get_global_rect().has_point(pos + global_position):
				return                             # (the wheel's own buttons take it)
			qc_panel.visible = false
		if sim.moba != null:
			for i in 3:
				if pick_rect(i).has_point(pos) and _picks_open():
					action_pressed.emit("pick%d" % i)
					get_viewport().set_input_as_handled()
					return
			if shop_rect().grow(6.0).has_point(pos):
				open_shop()                            # 0.31.157 5V5: the shop
				get_viewport().set_input_as_handled()
				return
		if sim.commander:
			for i in Cards.HAND:
				if card_rect(i).grow(4.0).has_point(pos):
					_card_tap[i] = _time
					card_pressed.emit(i)
					get_viewport().set_input_as_handled()
					return
		for b in _buttons():
			if pos.distance_to(b.c) <= b.r + 12.0:
				_touches[index] = b.id
				_pressed_at[b.id] = _time
				if b.id == "attack":
					_attack_held = true
				elif b.id == "ability":
					_ability_held = true
				elif b.id == "block":
					_block_held = true
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
		elif role == "block":
			_block_held = false
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

func block_held() -> bool:
	return _block_held or (not _modal_open() and Input.is_physical_key_pressed(KEY_L))

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
		if shop_open():
			_refresh_shop(me)
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
	_text(Vector2(24, 34), "YOUR SIDE", 12, TEAM_COLORS[vt(t)], _bold, HORIZONTAL_ALIGNMENT_LEFT, 120)
	if sim.moba != null:
		# 0.31.156 5V5: each side's King (the heart), his health
		_text(Vector2(24, 60), "♛ %d%%" % int(ceil(sim.moba.king_frac(t) * 100.0)), 22, VisualTheme.GOLD, _title, HORIZONTAL_ALIGNMENT_LEFT, 120)
		_text(Vector2(w - 144, 34), "ENEMY", 12, TEAM_COLORS[vt(1 - t)], _bold, HORIZONTAL_ALIGNMENT_RIGHT, 120)
		_text(Vector2(w - 144, 60), "%d%% ♛" % int(ceil(sim.moba.king_frac(1 - t) * 100.0)), 22, VisualTheme.GOLD, _title, HORIZONTAL_ALIGNMENT_RIGHT, 120)
	else:
		_text(Vector2(24, 60), "%d ♛" % sim.score[t], 26, VisualTheme.GOLD, _title, HORIZONTAL_ALIGNMENT_LEFT, 120)
		_text(Vector2(w - 144, 34), "ENEMY", 12, TEAM_COLORS[vt(1 - t)], _bold, HORIZONTAL_ALIGNMENT_RIGHT, 120)
		_text(Vector2(w - 144, 60), "%d ♛" % sim.score[1 - t], 26, VisualTheme.GOLD, _title, HORIZONTAL_ALIGNMENT_RIGHT, 120)
	var left := maxf(0.0, float(sim.match_time) - sim.time)
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
		_text(Vector2(w * 0.5, 176 if sim.moba == null else 284), _toast, 18, c, _bold)     # (0.31.157 5V5: under the kill feed, clear of the gold)
	_draw_kill_feed()
	_draw_idle(me)
	_draw_rejoin()
	_draw_bars()
	_draw_pings()
	_draw_gate_bars()
	_draw_oracle_marker(me)
	_draw_numbers()
	if diag != null and diag.fps_text != "":
		_text(Vector2(w - 212, 142), diag.fps_text, 11, Color(1, 1, 1, 0.6), _font, HORIZONTAL_ALIGNMENT_RIGHT, 200)
	if sim.commander and not _modal_open():
		_draw_cards(me)
	if sim.moba != null and not _modal_open():
		_draw_picks(me)                           # (before the respawn line: the hand plays while you're down too)
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

func _draw_idle(me: Dictionary) -> void:
	# 0.31.119: "A BOT IS PLAYING FOR YOU" while the server's bot holds my unit (I gave no input for a while)
	if idle_kick_at < 0.0 or not bool(me.get("bot", false)):
		return
	var w := size.x
	var left := maxf(0.0, idle_kick_at - Time.get_ticks_msec() / 1000.0)
	var r := Rect2(w * 0.5 - minf(180.0, w * 0.45), size.y * 0.3, minf(360.0, w * 0.9), 74)
	if _idle_style == null:
		_idle_style = VisualTheme.panel(Color(0.06, 0.04, 0.02, 0.9), VisualTheme.GOLD, 12, 8)
	draw_style_box(_idle_style, r)
	var pulse := 0.75 + 0.25 * sin(_time * 4.0)
	_text(Vector2(w * 0.5, r.position.y + 30), "A BOT IS PLAYING FOR YOU", 20, Color(VisualTheme.GOLD, pulse), _title)
	_text(Vector2(w * 0.5, r.position.y + 56), "Move or attack to take over · removed in %d:%02d" % [int(left) / 60, int(left) % 60], 13, VisualTheme.TEXT, _bold)

var _idle_style: StyleBox = null

# ---------------- kill feed (0.31.120, Kevin: "kill feed") ----------------
# On the right under the toast line: who knocked out whom, kings grabbed and rescued, gates broken --
# newest on top, KF_MAX lines, each KF_LIFE seconds then fading. Players by name (you: "You", on a gold plate),
# bots by class, in their side's colour; a knockout with no one behind it (a fall, the moat) shows a skull.
const KF_MAX := 4
const KF_LIFE := 6.0
const KF_PX := 12
const KF_TOP := 202.0                 # (under the toast; the quick-chat lines are on the left at the same height)
const KF_STEP := 19.0
var kill_feed: Array = []                  # newest first: {"parts": [[text, colour], ...], "at": _time, "me": I'm in it}
var kill_feed_on := true                   # (a match can turn it off: the tutorial)

func kf_name(id: String) -> Array:
	# [text, colour] for a unit in the feed
	var u: Dictionary = sim.by_id.get(id, {})
	if u.is_empty():
		return ["?", VisualTheme.TEXT]
	var col: Color = TEAM_COLORS[vt(int(u.team))].lightened(0.15)
	if id == player_id:
		return ["You", VisualTheme.GOLD]
	if net_names.has(id):
		return [str(net_names[id]).left(16), col]
	return [sim.class_label(u), col]

func _kf_add(parts: Array, mine: bool) -> void:
	kill_feed.push_front({"parts":parts, "at":_time, "me":mine})
	if kill_feed.size() > KF_MAX:
		kill_feed.resize(KF_MAX)
	queue_redraw()

func _kf_event(e: Dictionary, me: Dictionary) -> void:
	if not kill_feed_on:
		return
	var grey := Color("#c9d1dc")
	match str(e.k):
		"card":
			# 0.31.153 COMMANDER: what the enemy commander just sent, in the feed; yours as a toast
			var cd: Dictionary = Cards.card(str(e.get("card", "")))
			var n: int = (e.get("ids", []) as Array).size()
			if cd.is_empty() or n == 0:
				return
			if int(e.get("team", -1)) == int(me.team):
				toast("%s%s ARE OUT!" % [str(cd.name).to_upper(), (" ×%d" % n) if n > 1 else ""] if n > 1 else "%s IS OUT!" % str(cd.name).to_upper(),
					Color(str(Cards.RARITY_COLOR.get(str(cd.rarity), "#ffffff"))).lightened(0.2))
				return
			_kf_add([["Enemy", TEAM_COLORS[vt(1 - int(me.team))].lightened(0.15)], [" sent ", grey],
				[str(cd.name) + (" ×%d" % n if n > 1 else ""), Color(str(Cards.RARITY_COLOR.get(str(cd.rarity), "#ffffff")))]], false)
		"lord_down":
			var ours_l := int(e.get("team", -1)) == int(me.team)
			var lb := str(e.get("by", ""))
			if lb != "" and sim.by_id.has(lb):
				_kf_add([kf_name(lb), [" slew the Bone Lord", VisualTheme.GOLD if ours_l else VisualTheme.RED]], lb == player_id)
		"buff":
			if str(e.get("id", "")) != str(player_id) and sim.by_id.has(str(e.get("id", ""))):
				_kf_add([kf_name(str(e.id)), [" took %s" % str(sim.moba.BUFF_NAMES.get(str(e.buff), "")), Color("#7fb8ff") if str(e.buff) == "arcane" else Color("#ff9a5a")]], false)
		"tower_down":
			if sim.moba == null:
				return
			var ours_t := int(e.get("team", -1)) == int(me.team)
			_kf_add([["%s %s %s tower fell" % ["Our" if ours_t else "Their", str(sim.moba.LANE_NAMES[int(e.lane)]),
				"outer" if int(e.tier) == 1 else "inner"], VisualTheme.RED if ours_t else VisualTheme.GOLD]], false)
		"death":
			if bool(e.get("minion", false)) or bool(e.get("mon", false)):
				return                                     # (0.31.155: minions fall all the time; 0.31.157: so do monsters)
			var victim := str(e.get("id", ""))
			var by := str(e.get("by", ""))
			if not sim.by_id.has(victim):
				return
			if by == "" or by == victim or not sim.by_id.has(by):
				_kf_add([["☠", grey], [" ", grey], kf_name(victim)], victim == player_id)
			else:
				_kf_add([kf_name(by), ["  ⚔  ", Color(1, 1, 1, 0.85)], kf_name(victim)], victim == player_id or by == player_id)
		"rescue":
			var lead := str(e.get("id", ""))
			var ours := int(e.get("team", -1)) == int(me.team)
			if sim.by_id.has(lead):
				_kf_add([kf_name(lead), [" rescued %s King!" % ("our" if ours else "their"), VisualTheme.GOLD]], lead == player_id)
			else:
				_kf_add([["%s King was rescued!" % ("Our" if ours else "Their"), VisualTheme.GOLD]], false)
		"pickup":
			var carrier := str(e.get("id", ""))
			if sim.by_id.has(carrier):
				var ours2 := int(e.get("team", -1)) == int(me.team)
				_kf_add([kf_name(carrier), [" grabbed %s King" % ("our" if ours2 else "their"), grey]], carrier == player_id)
		"gate_broken":
			var gi := int(e.get("gate", -1))
			if gi < 0 or gi >= sim.gates.size():
				return
			var g: Dictionary = sim.gates[gi]
			var ours3 := int(g.team) == int(me.team)
			var what := "the jail" if str(g.get("kind", "")) == "jail" or str(g.get("side", "")) == "jail" else "the %s gate" % str(g.get("side", "")).to_lower()
			var by2 := str(e.get("by", ""))
			var tail := [" broke %s %s" % [("our" if ours3 else "their"), what.trim_prefix("the ")], VisualTheme.RED if ours3 else VisualTheme.GOLD]
			if by2 != "" and sim.by_id.has(by2):
				_kf_add([kf_name(by2), tail], by2 == player_id)
			else:
				_kf_add([["%s %s fell" % ["Our" if ours3 else "Their", what.trim_prefix("the ")], VisualTheme.RED if ours3 else VisualTheme.GOLD]], false)

func _draw_kill_feed() -> void:
	if kill_feed.is_empty():
		return
	var right := size.x - 10.0
	var y := KF_TOP
	var keep := []
	for it in kill_feed:
		var age: float = _time - float(it.at)
		if age > KF_LIFE:
			continue
		keep.append(it)
		var a := clampf((KF_LIFE - age) / 0.6, 0.0, 1.0) * clampf(age / 0.15, 0.0, 1.0)
		var w := 0.0
		for part in it.parts:
			w += _bold.get_string_size(str(part[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, KF_PX).x
		w = minf(w, size.x * 0.56)
		var plate := Rect2(right - w - 12.0, y - 14.0, w + 12.0, 18.0)
		draw_rect(plate, Color(0.03, 0.05, 0.1, 0.55 * a))
		if bool(it.me):
			draw_rect(plate, Color(VisualTheme.GOLD, 0.8 * a), false, 1.0)
		var x := plate.position.x + 6.0
		for part in it.parts:
			var t := str(part[0])
			var c: Color = part[1]
			c.a *= a
			var tw := _bold.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, KF_PX).x
			draw_string_outline(_bold, Vector2(x, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, KF_PX, 4, Color(0, 0, 0, 0.55 * a))
			draw_string(_bold, Vector2(x, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, KF_PX, c)
			x += tw
		y += KF_STEP
	if keep.size() != kill_feed.size():
		kill_feed = keep

# ---------- 5V5 (0.31.155) ----------
# Under your health: your level and XP, then the towers standing (yours, theirs). A level-up: three upgrade chips in
# the middle of the screen until you tap one (siege_mode -> sim "pick").
func _draw_moba_status(me: Dictionary) -> void:
	var t: int = me.team
	var lv := int(me.get("level", 1))
	var need: float = sim.moba.need(lv)
	var xr := Rect2(14, 140, minf(160.0, size.x * 0.38), 6)
	_text(Vector2(xr.end.x + 8, 147), "LEVEL %d" % lv, 12, VisualTheme.GOLD, _bold, HORIZONTAL_ALIGNMENT_LEFT, 100)
	draw_rect(xr.grow(1), Color(0, 0, 0, 0.6))
	if lv < sim.moba.LEVEL_MAX:
		draw_rect(Rect2(xr.position, Vector2(xr.size.x * clampf(float(me.get("xp", 0.0)) / need, 0.0, 1.0), xr.size.y)), Color("#ffd65a"))
	else:
		draw_rect(xr, Color("#ffd65a"))
	var ours := 0
	var theirs := 0
	for tw in sim.moba.towers:
		if bool(tw.dead):
			continue
		if int(tw.team) == t:
			ours += 1
		else:
			theirs += 1
	_text(Vector2(14, 164), "TOWERS  YOURS %d · THEIRS %d" % [ours, theirs], 11, Color("#cfe8b8"), _bold, HORIZONTAL_ALIGNMENT_LEFT, 260)
	_draw_gold_and_items(me)                      # 0.31.157
	_draw_camp_timers()

func _picks_open() -> bool:
	var me: Dictionary = sim.by_id.get(player_id, {})
	return not me.is_empty() and not (me.get("picks", []) as Array).is_empty()

func pick_rect(i: int) -> Rect2:
	var w := minf(124.0, (size.x - 40.0) / 3.0)
	var x0 := (size.x - (w * 3.0 + 16.0)) * 0.5
	return Rect2(x0 + (w + 8.0) * float(i), 312.0, w, 52.0)

var _pick_style: StyleBox = null

func _draw_picks(me: Dictionary) -> void:
	var picks: Array = me.get("picks", [])
	if picks.is_empty():
		return
	var offer: Array = picks[0]
	if _pick_style == null:
		_pick_style = VisualTheme.panel(Color(0.08, 0.05, 0.16, 0.92), VisualTheme.GOLD, 10, 6)
	var pulse := 0.75 + 0.25 * sin(_time * 5.0)
	_text(Vector2(size.x * 0.5, 304.0), "LEVEL %d · CHOOSE ONE%s" % [int(me.level) - picks.size() + 1, "  (+%d more)" % (picks.size() - 1) if picks.size() > 1 else ""],
		13, Color(1.0, 0.85, 0.4, pulse), _bold)
	for i in offer.size():
		var r := pick_rect(i)
		draw_style_box(_pick_style, r)
		var nm := str(sim.moba.UPGRADES.get(str(offer[i]), {}).get("name", str(offer[i])))
		var have := int((me.get("ups", {}) as Dictionary).get(str(offer[i]), 0))
		_text(Vector2(r.get_center().x, r.position.y + 25.0), nm, 12 if nm.length() <= 12 else 10, Color.WHITE, _bold)
		if have > 0:
			_text(Vector2(r.get_center().x, r.position.y + 42.0), "have %d" % have, 10, Color(1, 1, 1, 0.6), _font)

# ---------- COMMANDER's hand (0.31.153) ----------
# A column on the right edge, between the kill feed and DODGE: the next card (small), your army, then the 4 cards of the
# hand, with the command points as a bar beside them. A card you can't pay for yet is dimmed and fills from the bottom as
# the points come in; FULL when every soldier is already out. Tap a card to play it (siege_mode._play_card).
const CMD_COL := Color("#b25cff")
var _card_tex := {}
var _card_tap := {}                    # slot -> when it was tapped (a little press)
var _card_style := {}
var _cmd_flash := -10.0                # (a refused card: the bar flashes)

func _card_size() -> Vector2:
	var top := maxf(KF_TOP + KF_STEP * 3.0, 150.0) + 58.0      # (under the kill feed's rows and the NEXT card)
	var bottom := size.y - 262.0                               # (over DODGE)
	var ch := clampf((bottom - top - 3.0 * 6.0) / 4.0, 52.0, 84.0)
	return Vector2(roundf(ch * 0.8), roundf(ch))

func card_rect(i: int) -> Rect2:
	var cs := _card_size()
	var bottom := size.y - 262.0
	var x := size.x - cs.x - 8.0
	var y := bottom - (cs.y + 6.0) * float(Cards.HAND - i) + 6.0
	return Rect2(x, y, cs.x, cs.y)

func _ctex(id: String) -> Texture2D:
	if not _card_tex.has(id):
		var p := Cards.portrait(id)
		_card_tex[id] = load(p) as Texture2D if ResourceLoader.exists(p) else null
	return _card_tex[id]

func _cstyle(rarity: String, dim: bool) -> StyleBoxFlat:
	var key := rarity + ("d" if dim else "")
	if not _card_style.has(key):
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.07, 0.06, 0.12, 0.92)
		var rc := Color(str(Cards.RARITY_COLOR.get(rarity, "#b8c4c9")))
		sb.border_color = rc.darkened(0.45) if dim else rc
		sb.set_border_width_all(3 if rarity in ["epic", "legendary"] else 2)
		sb.set_corner_radius_all(8)
		sb.shadow_color = Color(0, 0, 0, 0.45)
		sb.shadow_size = 3
		_card_style[key] = sb
	return _card_style[key]

func _draw_cards(me: Dictionary) -> void:
	var t := int(me.team)
	var c: Dictionary = sim.cmd[t]
	if c.is_empty():
		return
	var pts := float(c.pts)
	var full: bool = sim.cmd_ready(t).is_empty()
	for i in Cards.HAND:
		var id := str(c.hand[i])
		var cd: Dictionary = Cards.card(id)
		var r := card_rect(i)
		var tap := _time - float(_card_tap.get(i, -10.0))
		if tap < 0.12:
			r = r.grow(-3.0)
		var afford := pts >= float(cd.cost)
		var dim := not afford or full
		draw_style_box(_cstyle(str(cd.rarity), dim), r)
		var inner := Rect2(r.position + Vector2(3, 3), Vector2(r.size.x - 6, r.size.y - 18))
		var tex := _ctex(id)
		if tex != null:
			draw_texture_rect(tex, inner, false, Color(0.5, 0.5, 0.55) if dim else Color.WHITE)
		if not afford:
			# the points still to come, as a shade over the top of the portrait
			var need := clampf(1.0 - pts / float(cd.cost), 0.0, 1.0)
			draw_rect(Rect2(inner.position, Vector2(inner.size.x, inner.size.y * need)), Color(0.02, 0.02, 0.06, 0.55))
		var name := str(cd.name).to_upper()
		var nsz := 10 if name.length() <= 9 else 9
		_text(Vector2(r.position.x + r.size.x * 0.5, r.end.y - 4.0), name, nsz, Color.WHITE if not dim else Color(0.75, 0.75, 0.8), _bold)
		# cost bubble (top left), squad (top right)
		var cc := r.position + Vector2(10, 10)
		draw_circle(cc, 11.0, Color(0.1, 0.02, 0.18))
		draw_circle(cc, 9.5, CMD_COL if afford else CMD_COL.darkened(0.5))
		_text(cc + Vector2(0, 5), str(int(cd.cost)), 14, Color.WHITE, _title)
		if int(cd.squad) > 1:
			_text(Vector2(r.end.x - 12, r.position.y + 15), "×%d" % int(cd.squad), 11, Color.WHITE, _bold)
		if full:
			var fr := Rect2(r.position.x, r.position.y + r.size.y * 0.42, r.size.x, 15)
			draw_rect(fr, Color(0.55, 0.08, 0.05, 0.85))
			_text(Vector2(fr.position.x + fr.size.x * 0.5, fr.end.y - 3.0), "FULL", 11, Color.WHITE, _bold)
	# the next card, small, over the column
	var r0 := card_rect(0)
	var nid := str((c.queue as Array)[0]) if not (c.queue as Array).is_empty() else ""
	var nr := Rect2(r0.end.x - 40.0, r0.position.y - 48.0, 40.0, 40.0)
	if nid != "":
		draw_style_box(_cstyle(str(Cards.card(nid).rarity), true), nr)
		var nt := _ctex(nid)
		if nt != null:
			draw_texture_rect(nt, nr.grow(-3.0), false, Color(0.8, 0.8, 0.85))
		_text(Vector2(nr.position.x - 64.0, nr.position.y + 15.0), "NEXT", 10, Color(1, 1, 1, 0.7), _bold, HORIZONTAL_ALIGNMENT_RIGHT, 60)
	# (right-aligned text: x is the left of the box it's aligned in)
	_text(Vector2(nr.position.x - 104.0, nr.position.y + 33.0), "ARMY %d/%d" % [sim.cmd_army(t), sim.cmd_soldiers(t)], 11,
		VisualTheme.GOLD if not full else Color("#ff9a7a"), _bold, HORIZONTAL_ALIGNMENT_RIGHT, 100)
	# the command points: a bar of 10 down the left of the column, the count on top
	var top := r0.position.y
	var bottom := card_rect(Cards.HAND - 1).end.y
	var bar := Rect2(r0.position.x - 15.0, top + 18.0, 9.0, bottom - top - 18.0)
	draw_rect(bar, Color(0.05, 0.02, 0.1, 0.8))
	var frac := clampf(pts / Sim.CMD_MAX, 0.0, 1.0)
	var flash := clampf(1.0 - (_time - _cmd_flash) / 0.5, 0.0, 1.0)
	var fill_col: Color = CMD_COL.lerp(Color("#ff5050"), flash)
	draw_rect(Rect2(bar.position.x, bar.end.y - bar.size.y * frac, bar.size.x, bar.size.y * frac), fill_col)
	for k in range(1, int(Sim.CMD_MAX)):
		var yy := bar.end.y - bar.size.y * float(k) / Sim.CMD_MAX
		draw_line(Vector2(bar.position.x, yy), Vector2(bar.end.x, yy), Color(0, 0, 0, 0.55), 1.0)
	draw_rect(bar, Color(0.85, 0.7, 1.0, 0.6), false, 1.0)
	var bc := Vector2(bar.position.x + bar.size.x * 0.5, top + 6.0)
	draw_circle(bc, 12.0, Color(0.1, 0.02, 0.18))
	draw_circle(bc, 10.5, fill_col)
	_text(bc + Vector2(0, 6), str(int(floor(pts))), 15, Color.WHITE, _title)
	if int(c.played) == 0 and me.state != "dead":
		# until the first card: a pulsing hint beside the hand
		var pa := 0.55 + 0.45 * sin(_time * 5.0)
		var hy := (top + bottom) * 0.5
		_text(Vector2(bar.position.x - 214.0, hy - 6.0), "TAP A CARD TO SEND", 14, Color(1, 1, 1, pa), _bold, HORIZONTAL_ALIGNMENT_RIGHT, 200)
		_text(Vector2(bar.position.x - 214.0, hy + 12.0), "YOUR SOLDIERS OUT  ▶", 14, Color(0.84, 0.64, 1.0, pa), _bold, HORIZONTAL_ALIGNMENT_RIGHT, 200)

func card_refused() -> void:
	_cmd_flash = _time

func _draw_rejoin() -> void:
	# 0.31.120: "RECONNECTING..." while the game gets back onto my seat
	if rejoin_until < 0.0:
		return
	var w := size.x
	var left := maxf(0.0, rejoin_until - Time.get_ticks_msec() / 1000.0)
	var r := Rect2(w * 0.5 - minf(170.0, w * 0.42), size.y * 0.42, minf(340.0, w * 0.84), 70)
	if _rejoin_style == null:
		_rejoin_style = VisualTheme.panel(Color(0.02, 0.05, 0.12, 0.92), Color("#5fb6ff"), 12, 8)
	draw_style_box(_rejoin_style, r)
	var dots := ".".repeat(1 + int(_time * 2.0) % 3)
	_text(Vector2(w * 0.5, r.position.y + 30), "RECONNECTING" + dots, 20, Color("#bfe3ff"), _title)
	_text(Vector2(w * 0.5, r.position.y + 54), "Your seat is held for you · %d s" % int(ceil(left)), 13, VisualTheme.TEXT, _bold)

var _rejoin_style: StyleBox = null

func _draw_bars() -> void:
	if not bars_source.is_valid() or not project.is_valid():
		return
	var tags := []
	for b in bars_source.call():
		if on_screen.is_valid() and not on_screen.call(b.pos):
			continue
		var p: Vector2 = project.call(b.pos)
		if p.y < 150.0:
			continue
		var r := Rect2(p - Vector2(17, 3), Vector2(34, 5))
		if bool(b.get("wide", false)):
			r = Rect2(p - Vector2(34, 4), Vector2(68, 8))         # (0.31.155: a 5v5 tower)
		draw_rect(r.grow(1.0), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(r.position, Vector2(r.size.x * float(b.fill), r.size.y)), b.color)
		if b.has("name"):                                 # 0.31.86: a live player's name over the bar
			tags.append([p, b])
	_draw_name_tags(tags)

# ---------------- names and titles over heads (0.31.86, 0.31.87) ----------------
# Each live player's name on a dark plate over their bar, in their side's colour; a title joins it with its
# punctuation (Net.title_parts), in its rarity's colour, and the plate shows the rarity: common plain, rare a blue rim,
# epic a purple rim and a slow glow, legendary a gold rim, a glow, a light band sweeping the letters and two sparkles.
const TAG_PX := 12
const TAG_COL := {"common": Color("#cfd8e0"), "rare": Color("#6cc4ff"), "epic": Color("#d6a2ff"), "legendary": Color("#ffc23d")}
const TAG_RIM := {"rare": [Color("#5fb6ff"), 1], "epic": [Color("#b86bff"), 2], "legendary": [Color("#ffc23d"), 2]}
const TAG_GLOW := {"epic": Color(0.62, 0.25, 1.0, 0.55), "legendary": Color(1.0, 0.55, 0.1, 0.6)}
var _tag_styles := {}

func _tag_style(key: String) -> StyleBoxFlat:
	if not _tag_styles.has(key):
		var sb := StyleBoxFlat.new()
		sb.anti_aliasing = true
		if key.begins_with("glow"):
			sb.set_corner_radius_all(9 + 2 * int(key.substr(4)))
		else:
			sb.bg_color = Color(0.03, 0.04, 0.09, 0.62)
			sb.set_corner_radius_all(8)
			if TAG_RIM.has(key):
				sb.border_color = TAG_RIM[key][0]
				sb.set_border_width_all(int(TAG_RIM[key][1]))
		_tag_styles[key] = sb
	return _tag_styles[key]

func _draw_name_tags(tags: Array) -> void:
	# The nearest (lowest on screen) keep their place; a plate that would cover one already placed steps up.
	tags.sort_custom(func(a, b): return (a[0] as Vector2).y > (b[0] as Vector2).y)
	var placed: Array = []
	var t := Time.get_ticks_msec() / 1000.0
	for tg in tags:
		var p: Vector2 = tg[0]
		var b: Dictionary = tg[1]
		var parts := NetT.title_parts(str(b.name), str(b.get("title", "")))
		var w := 0.0
		for part in parts:
			w += _bold.get_string_size(str(part[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, TAG_PX).x
		var plate := Rect2(p.x - w * 0.5 - 6.0, p.y - 7.0 - 13.0, w + 12.0, 17.0)
		for _i in 4:
			var hit := false
			for r in placed:
				if (r as Rect2).intersects(plate):
					hit = true
					break
			if not hit:
				break
			plate.position.y -= 18.0
		placed.append(plate)
		_draw_tag(plate, parts, NetT.title_rarity(str(b.get("title", ""))), b.get("name_color", Color.WHITE), t)

func _draw_tag(plate: Rect2, parts: Array, rarity: String, side_col: Color, t: float) -> void:
	if TAG_GLOW.has(rarity):
		var glow: Color = TAG_GLOW[rarity]
		var pulse := 0.6 + 0.4 * sin(t * 3.0)
		for g in 3:
			var gs := _tag_style("glow%d" % g)
			gs.bg_color = Color(glow, glow.a * pulse * (0.28 - 0.08 * g))
			draw_style_box(gs, plate.grow(2.0 + 2.0 * g))
	draw_style_box(_tag_style(rarity if TAG_RIM.has(rarity) else "plain"), plate)
	if rarity == "legendary":
		for sx in [plate.position.x, plate.end.x]:
			_sparkle(Vector2(sx, plate.position.y + 1.0), 5.0, Color(1.0, 0.95, 0.6, 0.65 + 0.35 * sin(t * 5.0 + sx)))
	var x := plate.position.x + 6.0
	var y := plate.position.y + 13.0
	var col: Color = TAG_COL.get(rarity, Color.WHITE)
	for part in parts:
		var s: String = part[0]
		var is_title: bool = part[1]
		var sw := _bold.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, TAG_PX).x
		if is_title and rarity == "legendary":
			# letter by letter, so a light band can sweep across the gold
			var cx := x
			for i in s.length():
				var ch := s.substr(i, 1)
				draw_char_outline(_bold, Vector2(cx, y), ch, TAG_PX, 4, Color(0, 0, 0, 0.75))
				cx += _bold.get_char_size(ch.unicode_at(0), TAG_PX).x
			cx = x
			for i in s.length():
				var ch := s.substr(i, 1)
				var band := fposmod((cx - x) / maxf(1.0, sw) - t * 0.6, 1.6)
				var k := clampf(1.0 - absf(band - 0.3) / 0.2, 0.0, 1.0)
				draw_char(_bold, Vector2(cx, y), ch, TAG_PX, col.lerp(Color("#fff8dc"), k))
				cx += _bold.get_char_size(ch.unicode_at(0), TAG_PX).x
		else:
			draw_string_outline(_bold, Vector2(x, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, TAG_PX, 4, Color(0, 0, 0, 0.75))
			draw_string(_bold, Vector2(x, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, TAG_PX, col if is_title else side_col)
		x += sw

func _sparkle(c: Vector2, s: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 0.3, -s * 0.3), c + Vector2(s, 0), c + Vector2(s * 0.3, s * 0.3),
		c + Vector2(0, s), c + Vector2(-s * 0.3, s * 0.3), c + Vector2(-s, 0), c + Vector2(-s * 0.3, -s * 0.3)]), col)

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
		if bool(n.get("gold", false)):
			c = Color("#ffd65a")                       # 0.31.157 5V5: gold you earned
		c.a = 1.0 - u * u
		_text(p + Vector2(0, -34.0 * u), str(n.text), 18, c, _bold)

func _draw_castle_status(me: Dictionary) -> void:
	var t: int = me.team
	if sim.moba != null:
		_draw_moba_status(me)
		return
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
			draw_rect(Rect2(r.position, Vector2(r.size.x * g.hp / g.max_hp, r.size.y)), TEAM_COLORS[vt(t)])
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
		var base: Color = Color(0.55, 0.58, 0.62) if owner < 0 else TEAM_COLORS[vt(owner)]
		draw_colored_polygon(inner, base)
		var pr: float = op.prog
		var capturing: bool = (owner < 0 and absf(pr) > 0.02) or (owner == 0 and pr < 0.999) or (owner == 1 and pr > -0.999)
		if capturing:
			var towards: Color = TEAM_COLORS[vt(0)] if pr > 0.0 else TEAM_COLORS[vt(1)]
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
	if sim.moba != null:
		# 0.31.156 5V5: the Kings are the hearts
		if not sim.moba.king_threat(int(me.team)).is_empty() and sim.moba.king_open(int(me.team)):
			return "OUR KING IS UNDER ATTACK!"
		if sim.moba.king_open(1 - int(me.team)):
			return "Their King is open -- defeat him!"
		return "Defeat their King -- he's guarded until a gate of his falls"
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
	if not project.is_valid() or not on_screen.is_valid() or sim.moba != null:
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
		var team_col: Color = TEAM_COLORS[vt(int(sp.team))]
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
	if sim.moba != null:
		goal = sim.moba.king_pos(1 - int(me.team))         # 0.31.156: the King to defeat, theirs
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
	var col: Color = VisualTheme.GOLD if not me.carrying else TEAM_COLORS[vt(int(me.team))]
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
	var badge := ""                                  # (a small mark drawn over the button: the ult's rank, ward charges)
	match str(b.id):
		"attack":
			label = "ATTACK"
			col = Color("#9a6414")
			rim = Color("#fff1bf")
			ready = not me.carrying
		"block":
			label = "BLOCK"
			col = Color("#2c4a6e")
			rim = Color("#bcd8ff")
			ready = not me.carrying
		"ability":
			var ab := str(sim.ability_of(me))
			label = ab.to_upper() if ab != "" else "—"
			col = Color("#35226a")
			rim = Color("#d6b8ff")
			cd = me.cd_ability
			cd_max = maxf(0.1, {"hammer":Sim.HAMMER_CD, "resurrect":Sim.RESURRECT_CD, "vanish":Sim.VANISH_CD, "pierce":Sim.PIERCE_CD,
				"meteor":Sim.METEOR_CD}.get(ab, float(Sim.CLASSES[me.cls].ab_cd)))
			ready = ab != "" and cd <= 0.0 and not me.carrying
		"ult":
			# 0.31.157 5V5: the ultimate -- locked until level 6 (LV 6), its name once it's yours, a glow when it's ready
			var info: Dictionary = sim.moba.ult_info(me)
			var unlocked: bool = sim.moba.ult_rank(me) > 0
			label = str(info.get("short", info.get("name", "ULT"))) if unlocked else "LV %d" % sim.moba.ULT_LEVEL
			col = Color("#7a3208")
			rim = Color("#ffd65a")
			cd = float(me.get("ult_cd", 0.0))
			cd_max = maxf(1.0, float(sim.moba.ult_max_cd(me)))
			ready = unlocked and cd <= 0.0
			if ready:
				var pulse := 0.5 + 0.5 * sin(_time * 5.0)
				draw_arc(c, r + 5.0 + 3.0 * pulse, 0, TAU, 48, Color(1.0, 0.84, 0.35, 0.35 + 0.4 * pulse), 4.0, true)
			if unlocked and sim.moba.ult_rank(me) >= 2:
				badge = "II"
		"ward":
			# 0.31.158 5V5: a ward at your feet -- its charges in the corner, the next one filling in round the rim
			var ch := float(me.get("ward_ch", 0.0))
			label = "WARD"
			col = Color("#16485a")
			rim = Color("#8fe3ff")
			ready = ch >= 1.0 and sim.alive(me)
			if ch < float(sim.moba.vision.WARD_CHARGES):
				cd = 1.0 - (ch - floorf(ch))
				cd_max = 1.0
			badge = str(int(ch))
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
	_text(c + Vector2(0, 6), label, 15 if r > 40 else (12 if r > 30 else 11), Color("#fffaf0") if ready else Color("#8a939a"), _bold)
	if badge != "":
		if str(b.id) == "ward":
			var bc := c + Vector2(r * 0.72, -r * 0.72)
			draw_circle(bc, 9.0, Color("#0d2a33"))
			draw_arc(bc, 9.0, 0, TAU, 24, rim, 1.5, true)
			_text(bc + Vector2(0, 4), badge, 11, Color("#dff7ff"), _bold)
		else:
			_text(c + Vector2(0, -r + 12), badge, 11, Color("#ffe9a6"), _bold)


# ---------- 5V5: gold, the shop, the jungle's timers (0.31.157) ----------
# Under the towers line: your gold and SHOP (tap: the shop; it glows while you can buy -- in your castle or while down),
# your six item slots, the buffs you carry. The shop: your items (tap one to sell it), the basic and the big items (tap
# one: what it gives, what it's built from, its price -- less what you own of it -- and BUY). Over a cleared camp in
# view: when it's back.
const STAT_NAMES := {"dmg":"damage", "hp":"health", "as":"attack speed", "spd":"speed", "cdr":"ability recharge", "ls":"lifesteal",
	"regen":"health/s", "armor":"less damage taken", "heal":"healing"}
var shop_panel: PanelContainer = null
var _shop_gold: Label
var _shop_where: Label
var _shop_slots: Array = []
var _shop_cells: Dictionary = {}               # item id -> {button, price}
var _shop_name: Label
var _shop_stats: Label
var _shop_from: Label
var _shop_act: Button
var _shop_sel := {}                            # {"item": id} or {"slot": i}
var _shop_key := ""
var _shop_style: StyleBox = null
var _coin_tex: Texture2D = null

func shop_open() -> bool:
	return shop_panel != null and shop_panel.visible

func shop_rect() -> Rect2:
	return Rect2(12, 174, 128, 30)

func open_shop() -> void:
	if sim == null or sim.moba == null:
		return
	if shop_panel == null:
		_build_shop()
	_shop_key = ""
	shop_panel.visible = true
	_center(shop_panel, true)
	var me: Dictionary = sim.by_id.get(player_id, {})
	if not me.is_empty():
		_refresh_shop(me)

func close_shop() -> void:
	if shop_panel != null:
		shop_panel.visible = false

static func item_text(id: String) -> String:
	var it: Dictionary = Moba.ITEMS.get(id, {})
	var parts := []
	for k in ["dmg", "hp", "as", "spd", "cdr", "ls", "armor", "heal"]:
		if it.has(k):
			parts.append("+%d%% %s" % [int(round(float(it[k]) * 100.0)), STAT_NAMES[k]])
	if it.has("regen"):
		parts.append("+%.1f%% health/s" % (float(it.regen) * 100.0))
	return ", ".join(parts)

func _item_cell(parent: Node, id: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(80, 66)
	b.set_meta("action_key", "shop_item_" + id)
	parent.add_child(b)
	var ic := ItemIcon.new()
	ic.item = id
	ic.position = Vector2(22, 4)
	ic.size = Vector2(36, 36)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(ic)
	var pl := Label.new()
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pl.position = Vector2(0, 42)
	pl.size = Vector2(80, 20)
	pl.add_theme_font_size_override("font_size", 13)
	pl.add_theme_font_override("font", _bold)
	pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(pl)
	b.pressed.connect(func():
		_shop_sel = {"item":id}
		_shop_key = "")
	_shop_cells[id] = {"button":b, "price":pl, "icon":ic}
	return b

func _build_shop() -> void:
	shop_panel = _panel(400)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	shop_panel.add_child(v)
	var hdr := HBoxContainer.new()
	v.add_child(hdr)
	var tl := UI2.text(hdr, "SHOP", 24, UI2.GOLD)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shop_gold = UI2.text(hdr, "", 20, Color("#ffd65a"))
	_shop_where = _label(v, "", 11, Color("#d4cbbb"))
	UI2.body(v, "YOUR ITEMS · tap one to sell it", 10, UI2.MUTED, false)
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 6)
	slots.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(slots)
	_shop_slots = []
	for i in Moba.ITEM_SLOTS:
		var sb := Button.new()
		sb.focus_mode = Control.FOCUS_NONE
		sb.custom_minimum_size = Vector2(50, 50)
		sb.set_meta("action_key", "shop_slot_%d" % i)
		var ic := ItemIcon.new()
		ic.position = Vector2(7, 7)
		ic.size = Vector2(36, 36)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sb.add_child(ic)
		var slot := i
		sb.pressed.connect(func():
			_shop_sel = {"slot":slot}
			_shop_key = "")
		slots.add_child(sb)
		_shop_slots.append({"button":sb, "icon":ic})
	for group in [["BASIC", Moba.ITEM_ORDER.filter(func(x): return not Moba.ITEMS[x].has("from"))],
			["BIG ITEMS · built from the small ones you own", Moba.ITEM_ORDER.filter(func(x): return Moba.ITEMS[x].has("from"))]]:
		UI2.body(v, str(group[0]), 10, UI2.MUTED, false)
		var g := GridContainer.new()
		g.columns = 4
		g.add_theme_constant_override("h_separation", 6)
		g.add_theme_constant_override("v_separation", 6)
		var cc := CenterContainer.new()
		cc.add_child(g)
		v.add_child(cc)
		for id in group[1]:
			_item_cell(g, str(id))
	_shop_name = _label(v, "", 16, UI2.GOLD, _bold)
	_shop_stats = _label(v, "", 12, Color.WHITE)
	_shop_from = _label(v, "", 11, Color("#d4cbbb"))
	_shop_act = _button(v, "BUY", "gold", func(): _shop_action())
	_shop_act.set_meta("action_key", "shop_act")
	var cb := _button(v, "CLOSE", "secondary", func(): close_shop())
	cb.set_meta("action_key", "shop_close")

func _shop_action() -> void:
	if _shop_sel.has("item"):
		action_pressed.emit("shop_buy:" + str(_shop_sel.item))
	elif _shop_sel.has("slot"):
		action_pressed.emit("shop_sell:%d" % int(_shop_sel.slot))
		_shop_sel = {}
	_shop_key = ""

func _cell_style(big: bool, sel: bool, can: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.06, 0.03, 0.95) if can else Color(0.05, 0.05, 0.07, 0.9)
	sb.border_color = Color("#ffe9a6") if sel else (Color("#c99a3a") if big else Color("#5a6470"))
	sb.set_border_width_all(3 if sel else 2)
	sb.set_corner_radius_all(9)
	return sb

func _refresh_shop(me: Dictionary) -> void:
	var inv: Array = me.get("items", [])
	var here: bool = sim.moba.can_shop(me)
	var key := "%d|%s|%s|%s" % [int(float(me.get("gold", 0.0))), str(inv), str(here), str(_shop_sel)]
	if key == _shop_key:
		return
	_shop_key = key
	var gold := int(float(me.get("gold", 0.0)))
	_shop_gold.text = "%d gold" % gold
	_shop_where.text = "In your castle -- tap an item, then BUY" if sim.alive(me) and here else ("You're down -- you can shop now" if here else "You can buy in your own castle, or while you're down")
	_shop_where.add_theme_color_override("font_color", Color("#9fe07a") if here else Color("#ffb07a"))
	for i in _shop_slots.size():
		var sl: Dictionary = _shop_slots[i]
		var ic: ItemIcon = sl.icon
		ic.item = str(inv[i]) if i < inv.size() else ""
		ic.queue_redraw()
		var sb := _cell_style(false, _shop_sel.get("slot", -1) == i, ic.item != "")
		for st in ["normal", "hover", "pressed", "focus", "hover_pressed", "disabled"]:
			(sl.button as Button).add_theme_stylebox_override(st, sb)
	for id in _shop_cells:
		var cell: Dictionary = _shop_cells[id]
		var pr: int = sim.moba.price(me, id)
		var why: String = sim.moba.buy_why(me, id)
		var can := why == "" or why == "where"
		(cell.price as Label).text = str(pr)
		(cell.price as Label).add_theme_color_override("font_color", Color("#ffd65a") if gold >= pr else Color("#a08c70"))
		(cell.icon as ItemIcon).dim = not can
		(cell.icon as ItemIcon).queue_redraw()
		var sb2 := _cell_style(Moba.ITEMS[id].has("from"), str(_shop_sel.get("item", "")) == id, can)
		for st in ["normal", "hover", "pressed", "focus", "hover_pressed", "disabled"]:
			(cell.button as Button).add_theme_stylebox_override(st, sb2)
	# the details of the one picked
	if _shop_sel.has("item"):
		var id2 := str(_shop_sel.item)
		var it: Dictionary = Moba.ITEMS[id2]
		_shop_name.text = str(it.name).to_upper()
		_shop_stats.text = item_text(id2)
		if it.has("from"):
			var names := []
			for c in it.from:
				names.append(str(Moba.ITEMS[c].name))
			var own: int = sim.moba._comps_owned(me, id2).size()
			_shop_from.text = "Built from %s%s · full price %d" % [" + ".join(names), (" (you have %d)" % own) if own > 0 else "", int(it.cost)]
		else:
			_shop_from.text = "Goes into: %s" % ", ".join(Moba.ITEM_ORDER.filter(func(x): return (Moba.ITEMS[x].get("from", []) as Array).has(id2)).map(func(x): return str(Moba.ITEMS[x].name)))
		var why2: String = sim.moba.buy_why(me, id2)
		_shop_act.visible = true
		_shop_act.disabled = why2 != ""
		_shop_act.text = {"": "BUY · %d" % sim.moba.price(me, id2), "gold": "NEED %d GOLD" % sim.moba.price(me, id2), "where": "BUY IN YOUR CASTLE",
			"full": "NO ROOM (6 ITEMS)", "boots": "ONE PAIR OF BOOTS"}.get(why2, "BUY")
	elif _shop_sel.has("slot") and int(_shop_sel.slot) < inv.size():
		var id3 := str(inv[int(_shop_sel.slot)])
		_shop_name.text = str(Moba.ITEMS[id3].name).to_upper()
		_shop_stats.text = item_text(id3)
		_shop_from.text = "Yours"
		_shop_act.visible = true
		_shop_act.disabled = not here
		_shop_act.text = ("SELL · +%d" % int(float(Moba.ITEMS[id3].cost) * Moba.SELL_BACK)) if here else "SELL IN YOUR CASTLE"
	else:
		_shop_name.text = "PICK AN ITEM"
		_shop_stats.text = "Gold comes in every second, and from last hits, knockouts, towers and the jungle's camps."
		_shop_from.text = ""
		_shop_act.visible = false

func _draw_gold_and_items(me: Dictionary) -> void:
	var r := shop_rect()
	var here: bool = sim.moba.can_shop(me)
	if _shop_style == null:
		_shop_style = VisualTheme.panel(Color(0.08, 0.05, 0.02, 0.9), VisualTheme.GOLD_DARK, 10, 6)
	draw_style_box(_shop_style, r)
	if here:
		var pulse := 0.5 + 0.5 * sin(_time * 4.0)
		draw_rect(r.grow(2.0), Color(1.0, 0.84, 0.35, 0.3 + 0.4 * pulse), false, 2.0)
	if _coin_tex == null and ResourceLoader.exists("res://assets/ui/currency/coin.png"):
		_coin_tex = load("res://assets/ui/currency/coin.png")
	if _coin_tex != null:
		draw_texture_rect(_coin_tex, Rect2(r.position + Vector2(5, 4), Vector2(22, 22)), false)
	else:
		draw_circle(r.position + Vector2(16, 15), 9, Color("#ffcf4a"))
	_text(r.position + Vector2(31, 21), str(int(float(me.get("gold", 0.0)))), 15, Color("#ffd65a"), _bold, HORIZONTAL_ALIGNMENT_LEFT, 60)
	_text(r.position + Vector2(r.size.x - 50, 21), "SHOP", 13, Color.WHITE if here else Color(1, 1, 1, 0.75), _bold, HORIZONTAL_ALIGNMENT_LEFT, 50)
	var inv: Array = me.get("items", [])
	for i in sim.moba.ITEM_SLOTS:
		var q := Rect2(12 + i * 22, r.end.y + 5, 20, 20)
		draw_rect(q, Color(0, 0, 0, 0.5))
		draw_rect(q, Color(VisualTheme.GOLD_DARK, 0.8), false, 1.0)
		if i < inv.size():
			ItemIcon.draw_item(self, str(inv[i]), q.get_center(), 18.0)
	# buffs
	var x := 12.0
	var y := r.end.y + 42.0
	var b: Dictionary = me.get("buffs", {})
	for k in ["arcane", "ember", "lord"]:
		var left := float(b.get(k, -1.0)) - float(sim.time)
		if left > 0.0:
			var txt := "%s %d:%02d" % [str(sim.moba.BUFF_NAMES[k]), int(left) / 60, int(left) % 60]
			var col := Color("#7fb8ff") if k == "arcane" else (Color("#ff9a5a") if k == "ember" else Color("#d8c2ff"))
			_text(Vector2(x, y), txt, 11, col, _bold, HORIZONTAL_ALIGNMENT_LEFT, 160)
			x += _bold.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 10.0

func _draw_camp_timers() -> void:
	if not project.is_valid() or not on_screen.is_valid():
		return
	for camp in sim.moba.camps:
		if bool(camp.alive):
			continue
		var p: Vector2 = camp.p
		var w := Vector3(p.x, Sim.height_at(p) + 1.0, p.y)
		if not on_screen.call(w):
			continue
		var sp: Vector2 = project.call(w)
		if sp.y < 230.0:
			continue
		sp.x = clampf(sp.x, 70.0, size.x - 70.0)
		var left := maxf(0.0, float(camp.next) - float(sim.time))
		var nm := str(sim.moba.CAMP_KINDS[camp.kind].name).to_upper() + " " if str(camp.kind) in ["lord", "arcane", "ember"] else ""
		_text(sp, "%s%d:%02d" % [nm, int(left) / 60, int(left) % 60], 13, Color("#e8dcc0"), _bold)
