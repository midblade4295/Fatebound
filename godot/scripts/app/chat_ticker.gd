extends Control
# 0.31.111 (Kevin: "Build a global chat"): the chat line over the tab bar on Home -- the newest global line (or what
# the chat is doing), an unread count, and a tap opens the chat. It follows scripts/meta/social.gd as lines arrive.
const UI = preload("res://scripts/app/ui.gd")
const UI2 = preload("res://scripts/app/ui2.gd")

const H := 46.0
var app
var _name: Label
var _text: Label
var _badge: PanelContainer
var _badge_l: Label

func setup(a) -> void:
	app = a
	custom_minimum_size = Vector2(0, H)
	var bg := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.04, 0.12, 0.9)
	sb.border_color = Color("#b9761b")
	sb.border_width_top = 2
	sb.corner_radius_top_left = 14
	sb.corner_radius_top_right = 14
	bg.add_theme_stylebox_override("panel", sb)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.offset_left = 6
	bg.offset_right = -6
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 8)
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.offset_left = 14
	r.offset_right = -14
	r.offset_top = 3
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	UI2.icon(r, "chat", 34.0).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_name = UI.label(r, "", 14, UI2.GOLD, UI.HEAVY_FONT)
	_name.autowrap_mode = TextServer.AUTOWRAP_OFF
	_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_text = UI.label(r, "", 14, Color.WHITE, UI.BODY_FONT)
	_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	_text.clip_text = true
	_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_badge = PanelContainer.new()
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color("#e8443a")
	bs.border_color = Color("#3a0805")
	bs.set_border_width_all(2)
	bs.set_corner_radius_all(11)
	bs.content_margin_left = 6
	bs.content_margin_right = 6
	_badge.add_theme_stylebox_override("panel", bs)
	_badge.custom_minimum_size = Vector2(24, 22)
	_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(_badge)
	_badge_l = UI.label(_badge, "", 12, Color.WHITE, UI.HEAVY_FONT)
	_badge_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	_badge_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var go := UI2.text(r, "›", 26, UI2.GOLD)
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var hit := Button.new()
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	for st_name in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		hit.add_theme_stylebox_override(st_name, StyleBoxEmpty.new())
	hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hit.set_meta("action_key", "chat_ticker")
	hit.pressed.connect(func():
		app.sfx("menuOpen")
		app.open_chat("party" if app.social.unread.party > 0 or not app.social.show_global else "global"))
	add_child(hit)
	app.social.changed.connect(_refresh)
	_refresh()

func _refresh(_what := "") -> void:
	var s = app.social
	var n: int = s.unread_total()
	_badge.visible = n > 0
	_badge_l.text = str(n) if n < 100 else "99+"
	var lines: Array = s.lines.get("global", []) if s.show_global else s.lines.get("party", [])
	var last := {}
	for i in range(lines.size() - 1, -1, -1):
		if not bool(lines[i].get("sys", false)):
			last = lines[i]
			break
	if s.online() and not last.is_empty():
		_name.text = str(last.get("n", "")) + ":"
		_text.text = str(last.get("x", ""))
		_text.modulate = Color.WHITE
		return
	_name.text = "CHAT" if s.show_global else "PARTY CHAT"
	_text.modulate = Color(0.75, 0.8, 0.92)
	match str(s.state):
		"online": _text.text = "Say hi to everyone online!" if s.show_global else "Global chat is off"
		"connecting": _text.text = "Connecting..."
		"old": _text.text = "Arrives with the next server update"
		_: _text.text = "Connects when you're online" if not s.has_account() else "Reconnecting..."
