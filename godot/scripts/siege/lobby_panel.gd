extends Control
# 0.31.82 (Kevin: "when starting match have it countdown from 20 seconds and show players joining"): the online lobby,
# up from PLAY until the server's welcome. First "connecting", then the server's "lobby" messages (every half second):
# the countdown to the wave's start (run here between messages), everyone waiting with you (new names pop in with a
# flip), how many players are on, and whether you'll go into a battle already running. The last five seconds tick.
# LEAVE (or Back) goes home. A server without the lobby (before 0.31.82) welcomes at once, so this just disappears.
const UI2 = preload("res://scripts/app/ui2.gd")

signal leave

const MAX_NAMES := 10                # two columns of five; the rest are "+N more"
const GOLD := Color("#ffd65a")
const HOT := Color("#ff8a3d")

var audio: Node = null
var state := "connecting"            # "connecting", "lobby", "failed"
var left := -1.0
var wait := 20.0
var _last_sec := -1
var _spin := 0.0
var _chips := {}                     # key ("name#n") -> chip
var _my_key := ""
var _first := true

var title: Label
var ring: Control
var number: Label
var mode_lbl: Label
var count_lbl: Label
var sub_lbl: Label
var grid: GridContainer
var more_lbl: Label
var join_head: Control
var leave_btn: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 50                                   # over the HUD (the FATEBOUND card, z 100, goes over this)
	var bg := TextureRect.new()
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.set_color(0, Color("#1a2766"))
	gr.set_color(1, Color("#060a1c"))
	gt.gradient = gr
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	gt.width = 8
	gt.height = 128
	bg.texture = gt
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 16
	v.offset_right = -16
	v.offset_top = 44
	v.offset_bottom = -30
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 10)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	UI2.center(UI2.text(v, "FATEBOUND", 42, GOLD, Color("#2e1908"), 11))
	UI2.center(UI2.body(v, "16 vs 16 SIEGE", 12, Color("#9fb0d6")))
	var top_gap := Control.new()
	top_gap.custom_minimum_size = Vector2(0, 26)
	top_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top_gap)
	title = UI2.center(UI2.text(v, "FINDING A BATTLE", 28, GOLD))
	# the countdown ring: the number inside an arc that empties as the time runs out
	ring = Control.new()
	ring.custom_minimum_size = Vector2(176, 176)
	ring.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(ring)
	var rays := UI2.rays(ring, 300.0, Color(1.0, 0.85, 0.45), 40.0, 0.22)
	rays.position = Vector2(88, 88) - Vector2(150, 150)
	ring.draw.connect(_draw_ring)
	number = UI2.text(ring, "", 84, Color.WHITE, Color("#2a1604"), 14)
	number.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number.offset_top = -4
	number.resized.connect(func(): number.pivot_offset = number.size * 0.5)
	mode_lbl = UI2.center(UI2.body(v, "Connecting to the Siege server...", 14, Color("#fff4d6")))
	var cr := HBoxContainer.new()
	cr.alignment = BoxContainer.ALIGNMENT_CENTER
	cr.add_theme_constant_override("separation", 8)
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(cr)
	var dot := Panel.new()
	var ds := StyleBoxFlat.new()
	ds.bg_color = Color("#5fdc86")
	ds.set_corner_radius_all(5)
	ds.shadow_color = Color(0.37, 0.86, 0.53, 0.7)
	ds.shadow_size = 5
	dot.add_theme_stylebox_override("panel", ds)
	dot.custom_minimum_size = Vector2(10, 10)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cr.add_child(dot)
	count_lbl = UI2.text(cr, "16 vs 16", 22, Color("#8cf0a8"), Color("#0b2a14"))
	sub_lbl = UI2.center(UI2.body(v, "bots fill the empty slots", 12, Color("#9fb0d6")))
	join_head = UI2.divider(v, "JOINING", 18)
	join_head.visible = false
	var gc := CenterContainer.new()
	gc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(gc)
	grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gc.add_child(grid)
	more_lbl = UI2.center(UI2.body(v, "", 12, Color("#9fb0d6")))
	more_lbl.visible = false
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(gap)
	var lc := CenterContainer.new()
	lc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(lc)
	leave_btn = UI2.button(lc, "LEAVE", "grey", func():
		_sfx("menuClose")
		leave.emit(), "lobby_leave", 18, 48.0)
	leave_btn.custom_minimum_size.x = 190

func _sfx(cue: String) -> void:
	if audio != null and audio.has_method("play"):
		audio.play(cue)

# ---------------- server messages ----------------
func update(msg: Dictionary) -> void:
	# A "lobby" message: {left, wait, names, me, online, in_match, slots, running}
	state = "lobby"
	wait = maxf(1.0, float(msg.get("wait", wait)))
	var l := float(msg.get("left", 0.0))
	if left < 0.0 or absf(l - left) > 0.35:        # (between messages the clock runs here; resync on drift)
		left = l
	title.text = "BATTLE STARTS IN"
	title.add_theme_color_override("font_color", GOLD)
	var slots := int(msg.get("slots", 32))
	var online := int(msg.get("online", 1))
	count_lbl.text = "%d / %d PLAYERS" % [mini(online, slots), slots]
	if bool(msg.get("running", false)):
		var n := int(msg.get("in_match", 0))
		mode_lbl.text = "A battle is on -- %d player%s fighting. You join it at zero." % [n, "" if n == 1 else "s"]
	else:
		mode_lbl.text = "A new 16 vs 16 battle starts at zero"
	sub_lbl.text = "bots fill the empty slots"
	_set_names(msg.get("names", []) as Array, int(msg.get("me", -1)))
	_first = false

func fail(why: String) -> void:
	state = "failed"
	title.text = "CAN'T JOIN"
	title.add_theme_color_override("font_color", Color("#ff6b5e"))
	number.text = ""
	mode_lbl.text = why
	sub_lbl.text = "Back to the menu..."
	ring.queue_redraw()

func _set_names(names: Array, me: int) -> void:
	var keys := []
	var seen := {}
	for i in names.size():
		var nm := str(names[i])
		seen[nm] = int(seen.get(nm, 0)) + 1
		keys.append("%s#%d" % [nm, seen[nm]])
	_my_key = keys[me] if me >= 0 and me < keys.size() else ""
	var shown := keys.slice(0, MAX_NAMES)
	for k in _chips.keys():
		if not k in shown or bool(_chips[k].get_meta("me")) != (k == _my_key):
			grid.remove_child(_chips[k])               # (out of the grid now: the order below counts children)
			_chips[k].queue_free()
			_chips.erase(k)
	var joined := false
	for i in shown.size():
		var k: String = shown[i]
		if not _chips.has(k):
			_chips[k] = _chip(str(names[i]), k == _my_key, not _first)
			if not _first and k != _my_key:
				joined = true
		grid.move_child(_chips[k], i)
	if joined:
		_sfx("flip")
	join_head.visible = not keys.is_empty()
	more_lbl.visible = keys.size() > MAX_NAMES
	more_lbl.text = "+%d more" % (keys.size() - MAX_NAMES)

func _chip(nm: String, is_me: bool, pop: bool) -> Control:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 0.84, 0.35, 0.16) if is_me else Color(1, 1, 1, 0.07)
	sb.border_color = Color(GOLD, 0.8) if is_me else Color(1, 1, 1, 0.16)
	sb.set_border_width_all(2 if is_me else 1)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	pc.add_theme_stylebox_override("panel", sb)
	pc.custom_minimum_size = Vector2(176, 36)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.set_meta("me", is_me)
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 8)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(r)
	# a little shield in a colour from the name, so the list reads at a glance
	var badge := Panel.new()
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color.from_hsv(float(absi(hash(nm)) % 360) / 360.0, 0.55, 0.95)
	bs.set_corner_radius_all(4)
	bs.corner_radius_bottom_left = 9
	bs.corner_radius_bottom_right = 9
	bs.border_color = Color(0, 0, 0, 0.5)
	bs.set_border_width_all(1)
	badge.add_theme_stylebox_override("panel", bs)
	badge.custom_minimum_size = Vector2(14, 17)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(badge)
	var l := UI2.body(r, nm, 14, Color("#fff4d6") if is_me else Color("#dfe6fb"), false)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if is_me:
		UI2.chip(r, "YOU", GOLD, Color("#3a1c02")).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_child(pc)
	if pop:
		pc.modulate.a = 0.0
		pc.scale = Vector2(0.5, 0.5)
		pc.resized.connect(func(): pc.pivot_offset = pc.size * 0.5)
		var tw := pc.create_tween().set_parallel()
		tw.tween_property(pc, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(pc, "modulate:a", 1.0, 0.2)
	return pc

# ---------------- clock ----------------
func _process(delta: float) -> void:
	_spin += delta
	if state == "lobby":
		left = maxf(0.0, left - delta)
		var sec := int(ceil(left))
		if sec != _last_sec:
			number.text = str(sec)
			if _last_sec >= 0 and sec < _last_sec:
				# each second lands with a little punch; the last five tick (and go orange)
				number.scale = Vector2(1.22, 1.22) if sec <= 5 else Vector2(1.1, 1.1)
				number.create_tween().tween_property(number, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				if sec <= 5 and sec >= 1:
					_sfx("countdown")
			number.add_theme_color_override("font_color", Color("#ffd2a8") if sec <= 5 else Color.WHITE)
			_last_sec = sec
		if left <= 0.0:
			title.text = "STARTING"
	ring.queue_redraw()

func _draw_ring() -> void:
	var c := ring.size * 0.5
	var r := minf(c.x, c.y) - 8.0
	ring.draw_circle(c, r + 6.0, Color(0.02, 0.03, 0.1, 0.55))
	ring.draw_arc(c, r, 0.0, TAU, 72, Color(1, 1, 1, 0.12), 10.0, true)
	if state == "connecting":
		var a := _spin * 4.0
		ring.draw_arc(c, r, a, a + 1.6, 24, GOLD, 10.0, true)
	elif state == "lobby":
		var f := clampf(left / wait, 0.0, 1.0)
		var col := HOT if left <= 5.0 else GOLD
		if f > 0.0:
			ring.draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * f, maxi(8, int(72 * f)), col, 10.0, true)
	else:
		ring.draw_arc(c, r, 0.0, TAU, 72, Color("#ff6b5e"), 10.0, true)
