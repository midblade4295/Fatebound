extends Control
const Sim_Eco = preload("res://scripts/meta/economy.gd")
# The match HUD. The stick and the combat buttons are drawn and hit-tested by hand from raw
# InputEventScreenTouch events, because Godot's Buttons only follow the first finger and on a
# phone you hold the stick while tapping ATTACK. Modal panels (pause, result, shop) use Buttons.
const VisualTheme = preload("res://scripts/ui/visual_theme.gd")
const UI = preload("res://scripts/app/ui.gd")
const UI2 = preload("res://scripts/app/ui2.gd")
# The old brass kinds map onto the app's tactile styles so battle panels match the menus.
const BUTTON_STYLE := {"primary":"orange", "secondary":"blue", "gold":"gold", "roll":"gold", "active":"green", "danger":"red"}   # 0.31.79: the menu skins
const Sim = preload("res://scripts/siege/siege_sim.gd")
const NetT = preload("res://scripts/siege/siege_net.gd")
const Moba = preload("res://scripts/siege/moba.gd")
const ItemIcon = preload("res://scripts/siege/item_icon.gd")   # 0.31.157 5V5: the shop's item glyphs

signal leave_requested
signal replay_requested
signal action_pressed(kind: String)
signal quick_chat(i: int)              # 0.31.111: a line from the quick chat wheel (NetT.QUICK_CHAT index)

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

var gate_bars_source: Callable   # -> Array of {pos, fill, color, broken}
var pause_panel: PanelContainer
var result_panel: PanelContainer
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
	# 0.31.160: the scoreboard and the status lines under it on a layer of their own (_draw_top), drawn again only when
	# what they show changes (_top_parts) -- they were a third of the HUD's 7 ms a frame on Kevin's phone. Behind the
	# HUD's own drawing, as they were drawn first.
	_top_layer = Control.new()
	_top_layer.name = "TopLayer"
	_top_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_layer.show_behind_parent = true
	_top_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_top_layer.draw.connect(_draw_top_layer)
	add_child(_top_layer)
	move_child(_top_layer, 0)
	# 0.31.8: the pause panel is built the first time it opens.
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

func paused() -> bool:
	return pause_panel != null and pause_panel.visible

func show_pause() -> void:
	if pause_panel == null:
		_build_pause_panel()
	pause_panel.visible = true
	_center(pause_panel, true)

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
	for st in [["castle", "1 · PUSH A LANE", "Bring down its towers, then a gate of their keep"], ["swords", "2 · THE KING'S TOWERS", "Inside, the two towers guarding their King"],
			["crown", "3 · DEFEAT THEIR KING", "wins the match"]]:
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
	var tricks := UI.label(v, "Walk in behind your minions: a tower shoots the nearest of them first. Last hits, jungle camps and towers pay gold -- shop in your keep or while you're down. The Bone Lord and the Grave Wyrm make your whole side stronger. Your fountain heals you.", 11, Color("#5d3a1c"), UI.HEAVY_FONT)
	tricks.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tricks.custom_minimum_size = Vector2(290, 0)
	var rb := _button(v, "RESUME", "active", func(): pause_panel.visible = false)
	rb.custom_minimum_size.y = 58
	rb.add_theme_font_size_override("font_size", 26)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	# (0.31.163: no RESOLUTION button -- the 3D is locked at 50 %, siege_mode.RENDER_SCALE)
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
			UI2.center(UI2.body(cell, "KINGS", 11, UI2.GOLD, false))
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
	var third := ["castle", "%d tower%s" % [int(me.get("towers", 0)), "" if int(me.get("towers", 0)) == 1 else "s"]]     # (0.31.164)
	for ch in [["skull", "%d KOs" % me.kills], ["helmet", "%d downs" % me.deaths], third]:
		var c := UI2.chip(you, "", Color(0.01, 0.02, 0.08, 0.8), Color.WHITE, Color(UI2.GOLD, 0.4))
		var cl: Label = c.get_child(0)
		c.remove_child(cl)
		cl.queue_free()
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 3)
		c.add_child(r)
		UI2.icon(r, str(ch[0]), 20.0)
		UI2.body(r, str(ch[1]), 11, Color.WHITE, false)
	UI2.center(UI2.body(v, "Last hits %d · camps %d · tower and gate damage %d" % [int(me.get("lh", 0)), int(me.get("camps", 0)),
		int(me.gate_dmg)], 12, Color("#cfe8b8"), false))
	# 0.31.155 5V5: the towers each side brought down, your level (0.31.164: paid like any match now)
	UI2.center(UI2.body(v, "Towers down: theirs %d · yours %d  ·  you reached level %d" % [sim.moba.towers_down(1 - int(me.team)),
		sim.moba.towers_down(int(me.team)), int(me.get("level", 1))], 12, Color("#ffcf7a"), false))
	UI2.center(UI2.body(v, "Gold earned %d · %d item%s" % [int(me.get("gold_total", 0.0)), (me.get("items", []) as Array).size(),
		"" if (me.get("items", []) as Array).size() == 1 else "s"], 12, Color("#ffe39a"), false))
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
	var br := HBoxContainer.new()
	br.add_theme_constant_override("separation", 10)
	v.add_child(br)
	_button(br, "HOME", "secondary", func(): leave_requested.emit())
	var sb := _button(br, "SCORES", "gold", func(): show_scoreboard())         # 0.31.119
	sb.set_meta("key", "scoreboard")
	var pa := _button(br, "PLAY AGAIN", "primary", func(): replay_requested.emit())
	pa.size_flags_stretch_ratio = 1.5
	UI2.sweep(pa)
	result_panel.visible = true
	_center(result_panel, true)
	if pause_panel != null:
		pause_panel.visible = false

# ---------- scoreboard and MVP (0.31.119, Kevin: "Do all" -- a proper end-of-match screen) ----------
# Every hero's knockouts, downs, towers and tower/gate damage come with the snapshots (and are the sim's own offline), so
# the board is the match as the server counted it. Points: a knockout 20, tower, gate and King damage 1 per 10. Bots are
# on the board too (as "Bot · <hero>"): most matches are mostly bots, and an honest board says when one outplayed
# everybody.
const MVP_KO := 20
const MVP_GATE := 0.1

static func points(u: Dictionary) -> int:
	return int(u.get("kills", 0)) * MVP_KO + int(float(u.get("gate_dmg", 0.0)) * MVP_GATE)

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
	var out: Array = sim.units.filter(func(u): return (team < 0 or int(u.team) == team) and bool(u.get("hero", false)))
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
	if int(m.get("towers", 0)) > 0:
		bits.append("%d tower%s" % [int(m.towers), "" if int(m.towers) == 1 else "s"])
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
		for hh in [["KO", 34], ["TW", 26], ["PTS", 46]]:
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
	UI2.center(UI2.body(v, "Points: KO %d · tower, gate and King damage ÷%d  ·  TW: towers" % [MVP_KO, int(1.0 / MVP_GATE)], 10, UI2.MUTED, true))
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
	for val in [[str(int(u.kills)), 34], [str(int(u.get("towers", 0))), 26], [str(points(u)), 46]]:
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
	match str(e.k):
		"level":
			if str(e.get("id", "")) == str(player_id):
				toast("LEVEL %d!  PICK AN UPGRADE" % int(e.level), VisualTheme.GOLD)
		"tower_immune":
			toast("That tower is protected -- take the one in front of it first", Color("#ffcf7a"))
		"king_immune":
			toast("Their King is protected until both his towers fall", Color("#ffcf7a"))
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
				toast("THE BONE LORD HAS RISEN IN THE WEST PIT", Color("#d8c2ff"))
			elif str(e.get("kind", "")) == "wyrm":
				toast("THE GRAVE WYRM STIRS IN THE EAST PIT", Color("#7fffd4"))
		"wyrm_down":                                     # 0.31.166
			var ours_w := int(e.get("team", -1)) == int(me.team)
			var pct := int(round(sim.moba.WYRM_HIDE * 100.0 * int(e.get("stacks", 0))))
			toast(("WE SLEW THE GRAVE WYRM! WYRM'S HIDE x%d: +%d%% HEALTH FOR ALL" if ours_w else "THEY SLEW THE GRAVE WYRM -- THEIR HIDE x%d (+%d%%)") % [int(e.get("stacks", 0)), pct],
				VisualTheme.GOLD if ours_w else VisualTheme.RED)
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
		"death":
			if e.id == player_id:
				toast("You fell!", VisualTheme.RED)
		"gate_broken":
			var side: String = str(sim.gates[int(e.gate)].side).to_upper()
			toast("OUR %s GATE HAS FALLEN!" % side if mine else "ENEMY %s GATE BROKEN — CHARGE!" % side, VisualTheme.RED if mine else VisualTheme.GOLD)

# ---------- input ----------
func _buttons() -> Array:
	var me: Dictionary = sim.by_id.get(player_id, {})
	if me.is_empty() or not bool(me.get("hero", false)):
		return []
	var br := Vector2(size.x, size.y)
	# 0.31.167 5V5 (Kevin: "class roles like League of Legends"): Q, W, E and R in an arc round ATTACK (Wild Rift's
	# layout), DODGE and WARD above them; on the narrowest screen (420 wide) Q and W reach as far left as the old
	# ABILITY did. The Crusader's W is his shield, held (it was its own BLOCK button).
	var crus: bool = me.cls == "knight" and bool(me.get("up", false))
	return [
		{"id":"attack", "c":br + Vector2(-78, -108), "r":46.0},
		{"id":"ability", "c":br + Vector2(-178, -58), "r":32.0},
		{"id":"block" if crus else "w", "c":br + Vector2(-188, -146), "r":32.0},
		{"id":"e", "c":br + Vector2(-148, -226), "r":32.0},
		{"id":"ult", "c":br + Vector2(-66, -218), "r":36.0},
		{"id":"dodge", "c":br + Vector2(-46, -300), "r":28.0},
		{"id":"ward", "c":br + Vector2(-122, -306), "r":24.0},
	]

func _modal_open() -> bool:
	return paused() or (result_panel != null and result_panel.visible) \
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
			KEY_R: action_pressed.emit("ult")             # 0.31.157 5V5
			KEY_U: action_pressed.emit("w")               # 0.31.167 5V5: W and E
			KEY_I: action_pressed.emit("e")
			KEY_T: action_pressed.emit("ward")            # 0.31.158 5V5
			KEY_B: open_shop()

func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	if pressed:
		if _modal_open() or pause_btn.get_global_rect().has_point(pos + global_position) \
				or (qc_btn.visible and qc_btn.get_global_rect().has_point(pos + global_position)):
			return
		if qc_panel != null and qc_panel.visible:
			if qc_panel.get_global_rect().has_point(pos + global_position):
				return                             # (the wheel's own buttons take it)
			qc_panel.visible = false
		for i in 3:
			if pick_rect(i).has_point(pos) and _picks_open():
				action_pressed.emit("pick%d" % i)
				get_viewport().set_input_as_handled()
				return
		if shop_rect().grow(6.0).has_point(pos):
			open_shop()                            # 0.31.157 5V5: the shop
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
	if not me.is_empty() and shop_open():
		_refresh_shop(me)
	if _top_layer != null:
		var tk := _top_key(me)
		if tk != _top_parts:
			_top_parts = tk
			_top_layer.queue_redraw()
	queue_redraw()

func _text(pos: Vector2, text: String, size_px: int, color: Color, font: Font = null, align := HORIZONTAL_ALIGNMENT_CENTER, width := -1.0) -> void:
	var f := font if font != null else _bold
	if align == HORIZONTAL_ALIGNMENT_CENTER and width < 0:
		width = 400.0
		pos.x -= width * 0.5
	_ci.draw_string_outline(f, pos, text, align, width, size_px, 5, Color(0, 0, 0, 0.6))
	_ci.draw_string(f, pos, text, align, width, size_px, color)

# ---------- the top layer (0.31.160) ----------
var _top_layer: Control = null
var _ci: CanvasItem = self                    # what _text and the top's drawing draw on: the HUD, or the top layer
var _top_parts: Array = []

func _top_key(me: Dictionary) -> Array:
	# everything _draw_top shows, as it shows it (whole numbers, bar widths in pixels): when it changes, it's redrawn
	if me.is_empty():
		return []
	var t: int = me.team
	var w := size.x
	var hpw := minf(220.0, w * 0.52)
	var k := [w, size.y, t, int(maxf(0.0, float(sim.match_time) - sim.time)), int(ceil(me.hp)),
		int(hpw * clampf(me.hp / maxf(1.0, me.max_hp), 0.0, 1.0)), sim.class_label(me), _king_status(me)]
	var lv := int(me.get("level", 1))
	k.append_array([int(ceil(sim.moba.king_frac(t) * 100.0)), int(ceil(sim.moba.king_frac(1 - t) * 100.0)), lv,
		int(minf(160.0, w * 0.38) * clampf(float(me.get("xp", 0.0)) / sim.moba.need(lv), 0.0, 1.0)),
		sim.moba.towers_down(0), sim.moba.towers_down(1), int(float(me.get("gold", 0.0))), sim.moba.can_shop(me),
		(me.get("items", []) as Array).duplicate()])
	var b: Dictionary = me.get("buffs", {})
	for bk in ["arcane", "ember", "lord"]:
		k.append(int(maxf(0.0, float(b.get(bk, -1.0)) - float(sim.time))))
	k.append(int(sim.moba.wyrm_stacks[clampi(t, 0, 1)]))
	return k

func _draw_top_layer() -> void:
	if sim == null:
		return
	var me: Dictionary = sim.by_id.get(player_id, {})
	if me.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	_ci = _top_layer
	_draw_top(me)
	_ci = self
	if diag != null:
		diag.add_time("hud", Time.get_ticks_usec() - t0)

func _draw() -> void:
	var t0 := Time.get_ticks_usec()
	if diag != null:
		diag.mark("hud draw")
	_draw_hud()
	if diag != null:
		diag.add_time("hud", Time.get_ticks_usec() - t0)
		diag.mark("hud drawn, rendering")

var prof_on := false                      # (tests/moba_bench.gd: microseconds per part of the draw in prof)
var prof := {}

func _ph(key: String, t0: int) -> int:
	var now := Time.get_ticks_usec()
	prof[key] = int(prof.get(key, 0)) + (now - t0)
	return now

func _draw_hud() -> void:
	if sim == null:
		return
	var me: Dictionary = sim.by_id.get(player_id, {})
	if me.is_empty():
		return
	var tq := Time.get_ticks_usec() if prof_on else 0
	var w := size.x
	if _top_layer == null:
		_draw_top(me)                           # (no layer: drawn with the rest)
	_draw_shop_pulse(me)
	_draw_camp_timers()
	if prof_on: tq = _ph("top", tq)
	# Toast.
	var age := _time - _toast_at
	if age < 2.6 and _toast != "":
		var c := _toast_color
		c.a = clampf(2.6 - age, 0.0, 1.0)
		_text(Vector2(w * 0.5, 284), _toast, 18, c, _bold)     # (0.31.157 5V5: under the kill feed, clear of the gold)
	_draw_kill_feed()
	_draw_idle(me)
	_draw_rejoin()
	if prof_on: tq = _ph("feed", tq)
	_draw_bars()
	if prof_on: tq = _ph("bars", tq)
	_draw_pings()
	_draw_gate_bars()
	_draw_king_marker(me)
	_draw_numbers()
	if prof_on: tq = _ph("pings..numbers", tq)
	# (0.31.163, Kevin: "Remove both": the fps / memory readout isn't shown -- it's in the diag log's STAT lines)
	if not _modal_open():
		_draw_picks(me)                           # (before the respawn line: the hand plays while you're down too)
	if prof_on: tq = _ph("cards+picks", tq)
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
	if prof_on: tq = _ph("stick+buttons", tq)

func _draw_top(me: Dictionary) -> void:
	# the scoreboard, my health and status, the 5v5's status lines -- on the top layer (0.31.160)
	var w := size.x
	# Scoreboard.
	var bar := Rect2(8, 8, w - 16, 62)
	if _bar_style == null:
		_bar_style = VisualTheme.panel(Color(0.035, 0.09, 0.12, 0.92), VisualTheme.GOLD_DARK, 12, 8)
	_ci.draw_style_box(_bar_style, bar)
	var t: int = me.team
	_text(Vector2(24, 34), "YOUR SIDE", 12, TEAM_COLORS[vt(t)], _bold, HORIZONTAL_ALIGNMENT_LEFT, 120)
	# 0.31.156 5V5: each side's King (the heart), his health
	_text(Vector2(24, 60), "♛ %d%%" % int(ceil(sim.moba.king_frac(t) * 100.0)), 22, VisualTheme.GOLD, _title, HORIZONTAL_ALIGNMENT_LEFT, 120)
	_text(Vector2(w - 144, 34), "ENEMY", 12, TEAM_COLORS[vt(1 - t)], _bold, HORIZONTAL_ALIGNMENT_RIGHT, 120)
	_text(Vector2(w - 144, 60), "%d%% ♛" % int(ceil(sim.moba.king_frac(1 - t) * 100.0)), 22, VisualTheme.GOLD, _title, HORIZONTAL_ALIGNMENT_RIGHT, 120)
	var left := maxf(0.0, float(sim.match_time) - sim.time)
	_text(Vector2(w * 0.5, 52), "%d:%02d" % [int(left) / 60, int(left) % 60], 32, Color("#e8eef2") if left > 60 else VisualTheme.RED, _title)
	# Player status line.
	var hp_rect := Rect2(12, 78, minf(220.0, w * 0.52), 14)
	_ci.draw_rect(hp_rect, Color(0, 0, 0, 0.55))
	var frac := clampf(me.hp / maxf(1.0, me.max_hp), 0.0, 1.0)
	_ci.draw_rect(Rect2(hp_rect.position, Vector2(hp_rect.size.x * frac, hp_rect.size.y)), Color("#7dff8a") if frac > 0.35 else VisualTheme.RED)
	_ci.draw_rect(hp_rect, VisualTheme.GOLD_DARK, false, 1.5)
	_text(Vector2(14, 110), "%s · %d HP" % [sim.class_label(me).to_upper(), int(ceil(me.hp))], 13, VisualTheme.TEXT, _bold, HORIZONTAL_ALIGNMENT_LEFT, 260)
	_text(Vector2(14, 128), _king_status(me), 12, VisualTheme.GOLD, _font, HORIZONTAL_ALIGNMENT_LEFT, w - 80)
	_draw_moba_status(me)

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
# On the right under the toast line: who knocked out whom, towers and gates broken, epic monsters slain --
# newest on top, KF_MAX lines, each KF_LIFE seconds then fading. Players by name (you: "You", on a gold plate),
# bots by class, in their side's colour; a knockout with no one behind it (a fall, the moat) shows a skull.
const KF_MAX := 4
const KF_LIFE := 6.0
const KF_PX := 12
const KF_TOP := 202.0                 # (under the toast; the quick-chat lines are on the left at the same height)
const KF_STEP := 19.0
var kill_feed: Array = []                  # newest first: {"parts": [[text, colour], ...], "at": _time, "me": I'm in it}
var kill_feed_on := true                   # (a match can turn it off)

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
		"lord_down":
			var ours_l := int(e.get("team", -1)) == int(me.team)
			var lb := str(e.get("by", ""))
			if lb != "" and sim.by_id.has(lb):
				_kf_add([kf_name(lb), [" slew the Bone Lord", VisualTheme.GOLD if ours_l else VisualTheme.RED]], lb == player_id)
		"wyrm_down":
			var ours_k := int(e.get("team", -1)) == int(me.team)
			var wb := str(e.get("by", ""))
			if wb != "" and sim.by_id.has(wb):
				_kf_add([kf_name(wb), [" slew the Grave Wyrm", VisualTheme.GOLD if ours_k else VisualTheme.RED]], wb == player_id)
		"buff":
			if str(e.get("id", "")) != str(player_id) and sim.by_id.has(str(e.get("id", ""))):
				_kf_add([kf_name(str(e.id)), [" took %s" % str(sim.moba.BUFF_NAMES.get(str(e.buff), "")), Color("#7fb8ff") if str(e.buff) == "arcane" else Color("#ff9a5a")]], false)
		"tower_down":
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
		"gate_broken":
			var gi := int(e.get("gate", -1))
			if gi < 0 or gi >= sim.gates.size():
				return
			var g: Dictionary = sim.gates[gi]
			var ours3 := int(g.team) == int(me.team)
			var what := "the %s gate" % str(g.get("side", "")).to_lower()
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
	_ci.draw_rect(xr.grow(1), Color(0, 0, 0, 0.6))
	if lv < sim.moba.LEVEL_MAX:
		_ci.draw_rect(Rect2(xr.position, Vector2(xr.size.x * clampf(float(me.get("xp", 0.0)) / need, 0.0, 1.0), xr.size.y)), Color("#ffd65a"))
	else:
		_ci.draw_rect(xr, Color("#ffd65a"))
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
	_draw_gold_and_items(me)                      # 0.31.157 (0.31.160: the camp timers and the shop's pulse per frame, in _draw_hud)

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

func _king_status(me: Dictionary) -> String:
	# 0.31.156 5V5: the Kings are the hearts
	if not sim.moba.king_threat(int(me.team)).is_empty() and sim.moba.king_open(int(me.team)):
		return "OUR KING IS UNDER ATTACK!"
	if sim.moba.king_open(1 - int(me.team)):
		return "Their King is open -- defeat him!"
	return "Defeat their King -- he's guarded until both his towers fall"

func _draw_king_marker(me: Dictionary) -> void:
	# 0.31.156: point to the King to defeat, theirs, when he is off-screen
	if not project.is_valid() or not on_screen.is_valid():
		return
	var goal: Vector2 = sim.moba.king_pos(1 - int(me.team))
	var world := Vector3(goal.x, 1.0, goal.y)
	if on_screen.call(world):
		return
	var p: Vector2 = project.call(world)
	var center := size * 0.5
	var dir := (p - center).normalized()
	var edge := center + dir * minf(size.x * 0.42, size.y * 0.36)
	var col: Color = VisualTheme.GOLD
	var tip := edge + dir * 16
	var side := Vector2(-dir.y, dir.x) * 11
	draw_colored_polygon(PackedVector2Array([tip, edge - dir * 6 + side, edge - dir * 6 - side]), col)
	_text(edge - dir * 22 + Vector2(0, 5), "KING", 11, col, _bold)

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
	var icon: Texture2D = null                       # 0.31.171: Q, W, E and R show their painted icon (assets/ui/abilities)
	var locked := false
	match str(b.id):
		"attack":
			label = "ATTACK"
			col = Color("#9a6414")
			rim = Color("#fff1bf")
		"block":
			label = "BLOCK"
			col = Color("#2c4a6e")
			rim = Color("#bcd8ff")
			icon = ability_icon(str(me.get("hid", "")), "w")    # (the Crusader's W: his shield)
		"w", "e":
			# 0.31.167 5V5: W and E -- locked until their level (LV 2 / LV 3), then their name and recharge
			var k: Dictionary = sim.moba.kits.kit(str(me.get("hid", "")), str(b.id))
			var unl: bool = sim.moba.kits.unlocked(me, str(b.id))
			label = str(k.get("short", k.get("name", "—"))) if unl else "LV %d" % int(sim.moba.kits.UNLOCK[str(b.id)])
			col = Color("#1f4a33") if str(b.id) == "w" else Color("#4a2a1a")
			rim = Color("#9ff0b8") if str(b.id) == "w" else Color("#ffc08a")
			cd = float(me.get("cd_" + str(b.id), 0.0))
			cd_max = maxf(0.1, float(k.get("cd", 1.0)))
			ready = unl and cd <= 0.0 and sim.alive(me)
			badge = str(b.id).to_upper()
			icon = ability_icon(str(me.get("hid", "")), str(b.id))
			locked = not unl
		"ability":
			var ab := str(sim.ability_of(me))
			label = ab.to_upper() if ab != "" else "—"
			badge = "Q"
			col = Color("#35226a")
			rim = Color("#d6b8ff")
			cd = me.cd_ability
			cd_max = maxf(0.1, {"hammer":Sim.HAMMER_CD, "resurrect":Sim.RESURRECT_CD, "vanish":Sim.VANISH_CD, "pierce":Sim.PIERCE_CD,
				"meteor":Sim.METEOR_CD}.get(ab, float(Sim.CLASSES[me.cls].ab_cd)))
			if me.has("kq"):
				# 0.31.168: a new hero's Q is a kit spell -- its own name and recharge
				var kq: Dictionary = sim.moba.kits.kit(str(me.get("hid", "")), "q")
				label = str(kq.get("short", kq.get("name", label)))
				cd_max = maxf(0.1, float(kq.get("cd", cd_max)))
			ready = ab != "" and cd <= 0.0
			icon = ability_icon(str(me.get("hid", "")), "q")
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
			badge = "R II" if unlocked and sim.moba.ult_rank(me) >= 2 else "R"
			icon = ability_icon(str(me.get("hid", "")), "r")
			locked = not unlocked
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
			ready = cd <= 0.0
	var pressed: bool = _time - float(_pressed_at.get(b.id, -10.0)) < 0.12 or (b.id == "attack" and _attack_held)
	var body := col.lightened(0.15) if pressed else col
	if not ready:
		body = body.darkened(0.45)
	draw_circle(c + Vector2(0, 4), r, Color(0, 0, 0, 0.45))
	draw_circle(c, r, body)
	if icon != null:
		# 0.31.171: the icon in the circle -- dimmed while it recharges or is locked, the time left over it
		var lit := Color(1, 1, 1) if ready else (Color(0.3, 0.3, 0.34) if locked else Color(0.5, 0.5, 0.54))
		_icon_circle(c, r - 1.5, icon, lit)
		if pressed:
			draw_circle(c, r - 1.5, Color(1, 1, 1, 0.18))
		if cd > 0.0 and not locked and cd / cd_max > 0.01:
			_pie(c, r - 1.5, cd / cd_max, Color(0, 0, 0, 0.45))
	draw_arc(c, r, 0, TAU, 48, rim if ready else rim.darkened(0.5), 3.0, true)
	if cd > 0.0:
		draw_arc(c, r - 6, -PI * 0.5, -PI * 0.5 + TAU * (cd / cd_max), 40, Color(1, 1, 1, 0.55), 5.0, true)
	if icon == null:
		_text(c + Vector2(0, 6), label, 15 if r > 40 else (12 if r > 30 else 11), Color("#fffaf0") if ready else Color("#8a939a"), _bold)
	elif locked:
		_text(c + Vector2(0, 6), label, 12 if r > 30 else 11, Color("#c9d0d6"), _bold)          # LV 2 / LV 3 / LV 6
	elif cd > 0.0 and str(b.id) != "ward":
		_text(c + Vector2(0, 7), str(ceili(cd)) if cd >= 1.0 else "%.1f" % cd, 18 if r > 33 else 16, Color("#fffaf0"), _bold)
	if badge != "":
		if str(b.id) == "ward":
			var bc := c + Vector2(r * 0.72, -r * 0.72)
			draw_circle(bc, 9.0, Color("#0d2a33"))
			draw_arc(bc, 9.0, 0, TAU, 24, rim, 1.5, true)
			_text(bc + Vector2(0, 4), badge, 11, Color("#dff7ff"), _bold)
		elif str(b.id) in ["ability", "w", "e"]:
			_text(c + Vector2(0, -r + 13), badge, 10, Color(1, 1, 1, 0.75) if ready else Color(1, 1, 1, 0.35), _bold)
		else:
			_text(c + Vector2(0, -r + 12), badge, 11, Color("#ffe9a6"), _bold)


# 0.31.171: the ability icons (tools/build_ability_icons.py): <hero>_<q|w|e|r>.png, loaded once (a missing one: the
# button's name, as before)
const ICON_DIR := "res://assets/ui/abilities/"
static var _icons := {}

static func ability_icon(hid: String, slot: String) -> Texture2D:
	var key := "%s_%s" % [hid, slot]
	if not _icons.has(key):
		var p := ICON_DIR + key + ".png"
		_icons[key] = load(p) if hid != "" and ResourceLoader.exists(p) else null
	return _icons[key]

func _icon_circle(c: Vector2, r: float, tex: Texture2D, tint: Color) -> void:
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i in 40:
		var d := Vector2.from_angle(TAU * float(i) / 40.0)
		pts.append(c + d * r)
		uvs.append(Vector2(0.5, 0.5) + d * 0.5)
	draw_polygon(pts, PackedColorArray([tint]), uvs, tex)

func _pie(c: Vector2, r: float, frac: float, color: Color) -> void:
	# the part still recharging, clockwise from the top
	var n := maxi(3, int(40.0 * clampf(frac, 0.0, 1.0)) + 1)
	var pts := PackedVector2Array([c])
	for i in n + 1:
		pts.append(c + Vector2.from_angle(-PI * 0.5 + TAU * clampf(frac, 0.0, 1.0) * float(i) / float(n)) * r)
	draw_colored_polygon(pts, color)

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
var _shop_pick_icon                            # 0.31.175: the picked item's icon beside its name
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

const SHOP_BANNER := "res://assets/ui/menu/shop_banner.webp"
const CELL_W := 84.0
const CELL_H := 82.0

func _item_cell(parent: Node, id: String) -> Button:
	# 0.31.175: the item's painted icon, its name, and its price beside a coin
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(CELL_W, CELL_H)
	b.set_meta("action_key", "shop_item_" + id)
	parent.add_child(b)
	var ic := ItemIcon.new()
	ic.item = id
	ic.position = Vector2((CELL_W - 44.0) * 0.5, 3)
	ic.size = Vector2(44, 44)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(ic)
	var nl := Label.new()
	nl.text = str(Moba.ITEMS[id].name)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.clip_text = true
	nl.position = Vector2(2, 46)
	nl.size = Vector2(CELL_W - 4, 15)
	nl.add_theme_font_size_override("font_size", 10)
	nl.add_theme_font_override("font", _bold)
	nl.add_theme_color_override("font_color", Color("#f2e6cf"))
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(nl)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 2)
	row.position = Vector2(0, 61)
	row.size = Vector2(CELL_W, 18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	var coin := TextureRect.new()
	coin.texture = _coin()
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin.custom_minimum_size = Vector2(14, 14)
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(coin)
	var pl := Label.new()
	pl.add_theme_font_size_override("font_size", 13)
	pl.add_theme_font_override("font", _bold)
	pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(pl)
	b.pressed.connect(func():
		_shop_sel = {"item":id}
		_shop_key = "")
	_shop_cells[id] = {"button":b, "price":pl, "icon":ic, "name":nl}
	return b

func _coin() -> Texture2D:
	if _coin_tex == null and ResourceLoader.exists("res://assets/ui/currency/coin.png"):
		_coin_tex = load("res://assets/ui/currency/coin.png")
	return _coin_tex

func _build_shop() -> void:
	shop_panel = _panel(400)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	shop_panel.add_child(v)
	# 0.31.175 (Kevin: "make these menus better looking and more high quality"): the keep's armory painted across the
	# top (ElevenLabs; tools/build_menu_icons.py), SHOP and your gold over it
	var hdr := Panel.new()
	hdr.custom_minimum_size = Vector2(0, 84)
	hdr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hs := StyleBoxFlat.new()
	hs.bg_color = Color(0.06, 0.04, 0.03)
	hs.set_corner_radius_all(12)
	hdr.add_theme_stylebox_override("panel", hs)
	hdr.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	v.add_child(hdr)
	var art := TextureRect.new()
	art.texture = load(SHOP_BANNER) if ResourceLoader.exists(SHOP_BANNER) else null
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hdr.add_child(art)
	var shade := TextureRect.new()                       # (darker toward the foot, under the words)
	var gg := Gradient.new()
	gg.set_color(0, Color(0, 0, 0, 0.0))
	gg.set_color(1, Color(0.02, 0.01, 0.03, 0.78))
	var gt := GradientTexture2D.new()
	gt.gradient = gg
	gt.fill_from = Vector2(0, 0.25)
	gt.fill_to = Vector2(0, 1)
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hdr.add_child(shade)
	var rim := Panel.new()
	var rs := StyleBoxFlat.new()
	rs.draw_center = false
	rs.border_color = Color("#c99a3a")
	rs.set_border_width_all(2)
	rs.set_corner_radius_all(12)
	rim.add_theme_stylebox_override("panel", rs)
	rim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hdr.add_child(rim)
	var hrow := HBoxContainer.new()
	hrow.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hrow.offset_top = -40
	hrow.offset_bottom = -6
	hrow.offset_left = 12
	hrow.offset_right = -12
	hrow.add_theme_constant_override("separation", 6)
	hrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hdr.add_child(hrow)
	var tl := UI2.text(hrow, "SHOP", 28, UI2.GOLD)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var gc := TextureRect.new()
	gc.texture = _coin()
	gc.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gc.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	gc.custom_minimum_size = Vector2(24, 24)
	gc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hrow.add_child(gc)
	_shop_gold = UI2.text(hrow, "", 22, Color("#ffd65a"))
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
		sb.custom_minimum_size = Vector2(52, 52)
		sb.set_meta("action_key", "shop_slot_%d" % i)
		var ic := ItemIcon.new()
		ic.position = Vector2(5, 5)
		ic.size = Vector2(42, 42)
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
		g.add_theme_constant_override("h_separation", 5)
		g.add_theme_constant_override("v_separation", 5)
		var cc := CenterContainer.new()
		cc.add_child(g)
		v.add_child(cc)
		for id in group[1]:
			_item_cell(g, str(id))
	var nrow := HBoxContainer.new()
	nrow.alignment = BoxContainer.ALIGNMENT_CENTER
	nrow.add_theme_constant_override("separation", 8)
	v.add_child(nrow)
	_shop_pick_icon = ItemIcon.new()
	_shop_pick_icon.custom_minimum_size = Vector2(40, 40)
	_shop_pick_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nrow.add_child(_shop_pick_icon)
	_shop_name = _label(nrow, "", 17, UI2.GOLD, _bold)
	_shop_name.custom_minimum_size = Vector2(0, 0)
	_shop_name.autowrap_mode = TextServer.AUTOWRAP_OFF
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
	# 0.31.175: a warm ground for what you can buy now, cooler for the rest; the big items in gold on a deep purple;
	# the picked one lit
	var sb := StyleBoxFlat.new()
	if big:
		sb.bg_color = Color(0.2, 0.1, 0.24, 0.96) if can else Color(0.09, 0.06, 0.12, 0.92)
	else:
		sb.bg_color = Color(0.16, 0.11, 0.06, 0.96) if can else Color(0.06, 0.06, 0.09, 0.92)
	sb.border_color = Color("#ffe9a6") if sel else (Color("#c99a3a") if big else Color("#6a7486"))
	sb.set_border_width_all(3 if sel else 2)
	sb.set_corner_radius_all(10)
	if sel:
		sb.shadow_color = Color(1.0, 0.85, 0.4, 0.55)
		sb.shadow_size = 5
	return sb

func _refresh_shop(me: Dictionary) -> void:
	var inv: Array = me.get("items", [])
	var here: bool = sim.moba.can_shop(me)
	var key := "%d|%s|%s|%s" % [int(float(me.get("gold", 0.0))), str(inv), str(here), str(_shop_sel)]
	if key == _shop_key:
		return
	_shop_key = key
	var gold := int(float(me.get("gold", 0.0)))
	_shop_gold.text = "%d" % gold
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
		(cell.name as Label).add_theme_color_override("font_color", Color("#f2e6cf") if can else Color("#9a927f"))
		(cell.icon as ItemIcon).dim = not can
		(cell.icon as ItemIcon).queue_redraw()
		var sb2 := _cell_style(Moba.ITEMS[id].has("from"), str(_shop_sel.get("item", "")) == id, can)
		for st in ["normal", "hover", "pressed", "focus", "hover_pressed", "disabled"]:
			(cell.button as Button).add_theme_stylebox_override(st, sb2)
	# the details of the one picked
	var picked := str(_shop_sel.get("item", "")) if _shop_sel.has("item") else (str(inv[int(_shop_sel.slot)]) if _shop_sel.has("slot") and int(_shop_sel.slot) < inv.size() else "")
	_shop_pick_icon.item = picked
	_shop_pick_icon.visible = picked != ""
	_shop_pick_icon.queue_redraw()
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
	_ci.draw_style_box(_shop_style, r)
	if _coin_tex == null and ResourceLoader.exists("res://assets/ui/currency/coin.png"):
		_coin_tex = load("res://assets/ui/currency/coin.png")
	if _coin_tex != null:
		_ci.draw_texture_rect(_coin_tex, Rect2(r.position + Vector2(5, 4), Vector2(22, 22)), false)
	else:
		_ci.draw_circle(r.position + Vector2(16, 15), 9, Color("#ffcf4a"))
	_text(r.position + Vector2(31, 21), str(int(float(me.get("gold", 0.0)))), 15, Color("#ffd65a"), _bold, HORIZONTAL_ALIGNMENT_LEFT, 60)
	_text(r.position + Vector2(r.size.x - 50, 21), "SHOP", 13, Color.WHITE if here else Color(1, 1, 1, 0.75), _bold, HORIZONTAL_ALIGNMENT_LEFT, 50)
	var inv: Array = me.get("items", [])
	for i in sim.moba.ITEM_SLOTS:
		var q := Rect2(12 + i * 22, r.end.y + 5, 20, 20)
		_ci.draw_rect(q, Color(0, 0, 0, 0.5))
		_ci.draw_rect(q, Color(VisualTheme.GOLD_DARK, 0.8), false, 1.0)
		if i < inv.size():
			ItemIcon.draw_item(_ci, str(inv[i]), q.get_center(), 18.0)
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
	var hide := int(sim.moba.wyrm_stacks[clampi(int(me.team), 0, 1)])
	if hide > 0:                                          # 0.31.166: the side's WYRM'S HIDE (for the rest of the match)
		var ht := "WYRM'S HIDE x%d +%d%%" % [hide, int(round(sim.moba.WYRM_HIDE * 100.0 * hide))]
		_text(Vector2(x, y), ht, 11, Color("#7fffd4"), _bold, HORIZONTAL_ALIGNMENT_LEFT, 180)

func _draw_shop_pulse(me: Dictionary) -> void:
	if sim.moba.can_shop(me):
		var pulse := 0.5 + 0.5 * sin(_time * 4.0)
		draw_rect(shop_rect().grow(2.0), Color(1.0, 0.84, 0.35, 0.3 + 0.4 * pulse), false, 2.0)

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
		var nm := str(sim.moba.CAMP_KINDS[camp.kind].name).to_upper() + " " if str(camp.kind) in ["lord", "wyrm", "arcane", "ember"] else ""
		_text(sp, "%s%d:%02d" % [nm, int(left) / 60, int(left) % 60], 13, Color("#e8dcc0"), _bold)
