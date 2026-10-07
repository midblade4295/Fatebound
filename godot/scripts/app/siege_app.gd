extends Control
# Fatebound Siege app shell (replaces the dice-era full_client). Owns the profile, the chrome
# (top bar + tab bar), the five screens (scripts/app/screens.gd) and launching matches.
const UI = preload("res://scripts/app/ui.gd")
const Eco = preload("res://scripts/meta/economy.gd")
const Profile = preload("res://scripts/meta/profile.gd")
const Screens = preload("res://scripts/app/screens.gd")
const Showcase = preload("res://scripts/app/showcase.gd")
const Siege = preload("res://scripts/siege/siege_mode.gd")
const Audio = preload("res://scripts/native_audio.gd")
const Assets = preload("res://scripts/siege/asset_cache.gd")

const TABS := [["home", "HOME", "home"], ["pass", "PASS", "pass"], ["shop", "SHOP", "shop"], ["locker", "LOCKER", "locker"], ["settings", "SETTINGS", "gear"]]

# Tests may point these elsewhere before the node enters the tree.
var profile_path := "user://siege_profile.json"
var legacy_path := "user://fatebound-save.json"
var now_override := -1

var profile
var audio: Node
var tab := "home"
var play_online := false
var home_class := "knight"
var locker_class := "knight"
var siege = null

var chrome: Control
var content_scroll: ScrollContainer
var content: VBoxContainer
var tab_buttons := {}
var level_label: Label
var name_label: Label
var xp_bar: ProgressBar
var gold_label: Label
var gems_label: Label
var modal: Control = null
var hero_layer: Control
var hero_node: Control
const HERO_H := 470.0
const FADE_COLOR := Color("#0d1627")
var _toast: Label
var _toast_box: PanelContainer
var _toast_until := 0.0

# ---------------- start-up diagnostics and safe start (0.31.70; 0.31.72: moved into the BootGuard autoload) ----------------
# BootGuard (scripts/app/boot_guard.gd) runs before this scene loads: the start-up log, the "pending until the menu
# is up" record, the switch to OpenGL after a stuck Vulkan start, and SAFE START (no background model loading and no
# live 3D hero) after a stuck start. This scene only reads safe_boot and marks its steps in the log.
var safe_boot := false
var _guard: Node = null

func _boot_mark(phase: String) -> void:
	if _guard != null:
		_guard.mark(phase)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_guard = get_node_or_null("/root/BootGuard")
	if _guard != null and bool(_guard.restarting):
		set_process(false)                    # switching renderer: the app restarts before anything is built
		set_process_input(false)
		return
	get_tree().auto_accept_quit = false
	safe_boot = _guard != null and bool(_guard.safe_boot)
	if not safe_boot:
		_boot_mark("preload models")
		Assets.preload_async()                 # 0.31.8: load the match's models on a thread while the menus are up
	_boot_mark("profile")
	profile = Profile.new(profile_path, legacy_path)
	profile.now_override = now_override
	profile.load_or_create()
	_boot_mark("audio")
	audio = Audio.new()
	add_child(audio)
	_apply_audio()
	_boot_mark("background")
	_build_background()
	_boot_mark("hero")
	_build_hero()
	_boot_mark("menus")
	_build_chrome()
	# Toast: a dark pill just above the tab bar, readable over anything.
	_toast_box = PanelContainer.new()
	var tsb := UI.card_style(Color(0.02, 0.04, 0.08, 0.92), 18, UI.CARD_HI)
	_toast_box.add_theme_stylebox_override("panel", tsb)
	_toast_box.anchor_left = 0.0
	_toast_box.anchor_right = 1.0
	_toast_box.anchor_top = 1.0
	_toast_box.anchor_bottom = 1.0
	_toast_box.offset_left = 18
	_toast_box.offset_right = -18
	_toast_box.offset_top = -150
	_toast_box.offset_bottom = -92
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.visible = false
	add_child(_toast_box)
	_toast = UI.label(_toast_box, "", 14, UI.TEXT, null, true)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if str(profile.d.migration.get("from", "")) == "legacy" and not bool(profile.d.migration.get("shown", false)):
		profile.d.migration["shown"] = true
		profile.save()
		var m: Dictionary = profile.d.migration
		call_deferred("toast", "Welcome to Fatebound! Your progress carried over: +%d gold, +%d gems" % [int(m.gold), int(m.gems)], UI.GOLD)
	content_scroll.get_v_scroll_bar().value_changed.connect(_on_scroll)
	show_tab("home")
	_boot_mark("home shown, waiting for frames")

func _apply_audio() -> void:
	var st: Dictionary = profile.d.settings
	if audio.has_method("set_levels"):
		audio.set_levels({"master":float(st.get("master", 0.8)), "combat":float(st.get("sfx", 0.8)), "ui":float(st.get("sfx", 0.8)),
			"music":float(st.get("music", 0.6))})

func sfx(cue: String) -> void:
	if audio != null and audio.has_method("play"):
		audio.play(cue)

# ---------------- chrome ----------------
func _build_background() -> void:
	var grad := Gradient.new()
	grad.set_color(0, UI.BG_TOP)
	grad.set_color(1, UI.BG_BOTTOM)
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	gt.width = 8
	gt.height = 256
	var bg := TextureRect.new()
	bg.texture = gt
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	# A soft warm glow behind the top of the screen.
	var glow_g := Gradient.new()
	glow_g.set_color(0, Color(1.0, 0.72, 0.3, 0.22))
	glow_g.set_color(1, Color(1.0, 0.72, 0.3, 0.0))
	var glow := GradientTexture2D.new()
	glow.gradient = glow_g
	glow.fill = GradientTexture2D.FILL_RADIAL
	glow.fill_from = Vector2(0.5, 0.5)
	glow.fill_to = Vector2(1.0, 0.5)
	glow.width = 256
	glow.height = 256
	var gl := TextureRect.new()
	gl.texture = glow
	gl.stretch_mode = TextureRect.STRETCH_SCALE
	gl.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gl.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	gl.offset_top = -180
	gl.offset_bottom = 380
	gl.offset_left = -120
	gl.offset_right = 120
	gl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(gl)

func _grad(c0: Color, c1: Color, w := 8, h := 64) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, c0)
	g.set_color(1, c1)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0.5, 0.0)
	t.fill_to = Vector2(0.5, 1.0)
	t.width = w
	t.height = h
	return t

func _band(parent: Control, c0: Color, c1: Color, top: bool, px: float) -> void:
	var r := TextureRect.new()
	r.texture = _grad(c0, c1)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.anchor_right = 1.0
	if top:
		r.offset_bottom = px
	else:
		r.anchor_top = 1.0
		r.anchor_bottom = 1.0
		r.offset_top = -px
	parent.add_child(r)

func _build_hero() -> void:
	# Full-bleed home hero behind the menu: Blender backdrop, live 3D character, scrims, logo and
	# drifting gold motes. Scrolls away with a parallax as the menu is scrolled.
	hero_layer = Control.new()
	hero_layer.anchor_right = 1.0
	hero_layer.offset_bottom = HERO_H
	hero_layer.clip_contents = true
	hero_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hero_layer)
	Showcase.backdrop(hero_layer)
	if safe_boot:
		hero_node = null                      # safe start: the painted backdrop only, no live 3D character
	else:
		hero_node = Showcase.new()
		# The home hero is taller than the Locker's box, so the camera sits further back to keep the
		# helmet clear of the logo: character ~45% of the frame, feet at ~78% down.
		hero_node.cam_z = 9.7
		hero_node.cam_y = 1.6
		hero_node.look_y = 1.24
		hero_node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hero_layer.add_child(hero_node)
	_band(hero_layer, Color(0.02, 0.03, 0.09, 0.78), Color(0.02, 0.03, 0.09, 0.0), true, 120.0)
	_band(hero_layer, Color(FADE_COLOR, 0.0), Color(FADE_COLOR, 1.0), false, 210.0)
	if not bool(profile.d.settings.get("reduce_motion", false)):
		var glow := Gradient.new()
		glow.set_color(0, Color(1, 0.85, 0.5, 1.0))
		glow.set_color(1, Color(1, 0.85, 0.5, 0.0))
		var gt := GradientTexture2D.new()
		gt.gradient = glow
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 24
		gt.height = 24
		var motes := CPUParticles2D.new()
		motes.texture = gt
		motes.amount = 22
		motes.lifetime = 7.0
		motes.preprocess = 7.0
		motes.position = Vector2(210, HERO_H - 40)
		motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		motes.emission_rect_extents = Vector2(230, 10)
		motes.direction = Vector2(0.2, -1.0)
		motes.spread = 18.0
		motes.gravity = Vector2.ZERO
		motes.initial_velocity_min = 14.0
		motes.initial_velocity_max = 34.0
		motes.scale_amount_min = 0.25
		motes.scale_amount_max = 0.6
		var ramp := Gradient.new()
		ramp.set_color(0, Color(1, 1, 1, 0.0))
		ramp.set_color(1, Color(1, 1, 1, 0.0))
		ramp.add_point(0.25, Color(1, 1, 1, 0.9))
		ramp.add_point(0.75, Color(1, 1, 1, 0.6))
		motes.color_ramp = ramp
		hero_layer.add_child(motes)
	# The game is just "Fatebound" (Kevin): no "Siege" subtitle; the logo in Luckiest Guy, like the
	# trailer and store art.
	var logo := UI.title(hero_layer, "FATEBOUND", 46, UI.GOLD)
	logo.add_theme_font_override("font", LOGO_FONT)
	logo.add_theme_color_override("font_outline_color", Color("#2e1908"))
	logo.add_theme_constant_override("outline_size", 12)
	logo.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	logo.add_theme_constant_override("shadow_offset_y", 4)
	logo.autowrap_mode = TextServer.AUTOWRAP_OFF
	logo.anchor_right = 1.0
	logo.offset_top = 78
	logo.offset_bottom = 132

const LOGO_FONT = preload("res://assets/fonts/LuckiestGuy-Regular.ttf")

func hero_show(cls: String, look: Dictionary) -> void:
	if hero_node != null:
		hero_node.show_look(cls, look)

func _on_scroll(v: float) -> void:
	hero_layer.position.y = -v * 0.55
	hero_layer.modulate.a = clampf(1.0 - v / 360.0, 0.0, 1.0)

func _safe_top() -> float:
	# Status bar / notch inset in logical pixels.
	var safe := DisplayServer.get_display_safe_area()
	var window := Vector2(DisplayServer.window_get_size())
	var logical := get_viewport().get_visible_rect().size
	if window.y <= 0 or safe.size.y <= 0:
		return 0.0
	return clampf(float(safe.position.y) * logical.y / window.y, 0.0, 60.0)

func _build_chrome() -> void:
	chrome = VBoxContainer.new()
	chrome.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	chrome.add_theme_constant_override("separation", 0)
	add_child(chrome)
	UI.spacer(chrome, 6.0 + _safe_top())
	# --- top bar ---
	var top := MarginContainer.new()
	for side in ["left", "right"]:
		top.add_theme_constant_override("margin_" + side, 12)
	top.add_theme_constant_override("margin_bottom", 6)
	chrome.add_child(top)
	var bar := UI.row(top, 10)
	var badge := PanelContainer.new()
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color("#1b2c4c")
	bs.set_corner_radius_all(24)
	bs.border_color = UI.GOLD
	bs.set_border_width_all(3)
	bs.shadow_color = Color(0, 0, 0, 0.4)
	bs.shadow_size = 6
	badge.add_theme_stylebox_override("panel", bs)
	badge.custom_minimum_size = Vector2(48, 48)
	bar.add_child(badge)
	level_label = UI.label(badge, "1", 18, UI.GOLD, UI.HEAVY_FONT, true)
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var who := VBoxContainer.new()
	who.add_theme_constant_override("separation", 3)
	UI.grow(who)
	bar.add_child(who)
	name_label = UI.label(who, "", 15, UI.TEXT, null, true)
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.clip_text = true
	xp_bar = UI.progress(who, 0, 1, UI.CYAN, 8)
	gold_label = _pill(bar, "coin")
	gems_label = _pill(bar, "gem")
	# --- screen area ---
	content_scroll = ScrollContainer.new()
	content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Drag-scrolling is done by _input below; the built-in one never saw drags that started on a
	# card or button (they stop the event) and would fight ours where it did.
	content_scroll.scroll_deadzone = 1000000
	chrome.add_child(content_scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 18)
	content_scroll.add_child(margin)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(content)
	# --- tab bar ---
	var tabbar := PanelContainer.new()
	var ts := UI.card_style(Color("#0c1528"), 0, Color("#2d4a78"), true)
	ts.content_margin_top = 6
	ts.content_margin_bottom = 8
	ts.content_margin_left = 6
	ts.content_margin_right = 6
	tabbar.add_theme_stylebox_override("panel", ts)
	chrome.add_child(tabbar)
	var trow := UI.row(tabbar, 4)
	for t in TABS:
		tab_buttons[t[0]] = _tab_button(trow, t[0], t[1], t[2])

func _pill(parent: Node, kind: String) -> Label:
	# A panel sized by its contents with a transparent button over it (a Button doesn't size
	# itself to child controls). Tapping a currency opens the shop.
	var p := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0, 0, 0, 0.45)
	st.set_corner_radius_all(16)
	st.border_color = Color(1, 1, 1, 0.12)
	st.set_border_width_all(1)
	st.content_margin_left = 6
	st.content_margin_right = 8
	st.content_margin_top = 5
	st.content_margin_bottom = 5
	p.add_theme_stylebox_override("panel", st)
	parent.add_child(p)
	var r := UI.row(p, 4)
	UI.tex_icon(r, "res://assets/ui/currency/%s.png" % ("coin" if kind == "coin" else "gem"), 26)
	var l := UI.label(r, "0", 15, UI.TEXT, UI.HEAVY_FONT, true)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.custom_minimum_size = Vector2(38, 0)
	UI.icon(r, "plus", 12, UI.GREEN)
	for c in r.get_children():
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hit := Button.new()
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	hit.set_meta("action_key", "pill_" + kind)
	hit.pressed.connect(func():
		sfx("tap")
		show_tab("shop"))
	p.add_child(hit)
	return l

func _tab_button(parent: Node, id: String, text: String, icon_kind: String) -> Dictionary:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	for st_name in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st_name, StyleBoxEmpty.new())
	b.custom_minimum_size = Vector2(0, 58)
	b.set_meta("action_key", "tab_" + id)
	UI.grow(b)
	b.pressed.connect(func():
		sfx("tap")
		show_tab(id))
	parent.add_child(b)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var ic := UI.icon(v, icon_kind, 26, UI.MUTED)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var l := UI.label(v, text, 10, UI.MUTED)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot := ColorRect.new()
	dot.color = UI.GOLD
	dot.custom_minimum_size = Vector2(22, 3)
	dot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(dot)
	return {"button":b, "icon":ic, "label":l, "dot":dot}

func refresh_top() -> void:
	var d: Dictionary = profile.d
	level_label.text = str(int(d.level))
	var title := ""
	if str(d.title) != "":
		title = "  ·  " + str(Eco.item(str(d.title)).get("name", ""))
	name_label.text = str(d.name) + title
	xp_bar.max_value = Eco.level_xp(int(d.level))
	xp_bar.value = int(d.xp)
	gold_label.text = UI.compact(int(d.gold))
	gems_label.text = UI.compact(int(d.gems))
	# Badge on the PASS tab when rewards are waiting.
	var claimable := 0
	for tier in range(1, profile.pass_tier() + 1):
		for prem in [false, true]:
			if profile.can_claim(tier, prem):
				claimable += 1
	var pt: Dictionary = tab_buttons["pass"]
	(pt.label as Label).text = "PASS" if claimable == 0 else "PASS (%d)" % claimable

func show_tab(id: String) -> void:
	tab = id
	profile.refresh()
	for t in tab_buttons:
		var tb: Dictionary = tab_buttons[t]
		var on: bool = t == id
		(tb.icon as Control).set("tint", UI.GOLD if on else UI.MUTED)
		(tb.icon as Control).queue_redraw()
		(tb.label as Label).add_theme_color_override("font_color", UI.GOLD if on else UI.MUTED)
		(tb.dot as ColorRect).modulate.a = 1.0 if on else 0.0
		var pill: StyleBox = StyleBoxEmpty.new()
		if on:
			var pf := StyleBoxFlat.new()
			pf.bg_color = Color(1.0, 0.79, 0.3, 0.14)
			pf.set_corner_radius_all(16)
			pf.border_color = Color(1.0, 0.79, 0.3, 0.35)
			pf.set_border_width_all(1)
			pill = pf
		for st_name in ["normal", "hover", "pressed"]:
			(tb.button as Button).add_theme_stylebox_override(st_name, pill)
	hero_layer.visible = id == "home"
	hero_layer.position.y = 0.0
	hero_layer.modulate.a = 1.0
	content_scroll.scroll_vertical = 0
	rebuild()
	content.modulate.a = 0.0
	create_tween().tween_property(content, "modulate:a", 1.0, 0.18)

func rebuild() -> void:
	# Screens are rebuilt from the profile after every change; they're small and static.
	for c in content.get_children():
		content.remove_child(c)
		c.queue_free()
	match tab:
		"home": Screens.home(self, content)
		"pass": Screens.pass_screen(self, content)
		"shop": Screens.shop(self, content)
		"locker": Screens.locker(self, content)
		"settings": Screens.settings(self, content)
	refresh_top()

# ---------------- feedback ----------------
func toast(text: String, color := UI.TEXT) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", color)
	_toast_box.visible = true
	_toast_box.modulate.a = 1.0
	_toast_until = Time.get_ticks_msec() / 1000.0 + 2.8
	move_child(_toast_box, get_child_count() - 1)

func confirm(title_text: String, body: String, yes_text: String, style: String, on_yes: Callable) -> void:
	close_modal()
	modal = Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(modal)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(center)
	var v := UI.card(center)
	(v.get_parent() as Control).custom_minimum_size = Vector2(minf(360, size.x - 32), 0)
	UI.title(v, title_text, 20)
	var b := UI.label(v, body, 14, UI.MUTED)
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var r := UI.row(v, 10)
	UI.grow(UI.button(r, "CANCEL", "secondary", func():
		sfx("menuClose")
		close_modal(), "modal_no"))
	UI.grow(UI.button(r, yes_text, style, func():
		close_modal()
		on_yes.call(), "modal_yes"))

func close_modal() -> void:
	if is_instance_valid(modal):
		modal.queue_free()
	modal = null

# ---------------- menu drag-scroll (0.18.3, Kevin: "the main menu can't scroll up and down") ----------------
# Every screen is cards and buttons, and those stop input, so the ScrollContainer's own touch drag
# never started. Here the app sees events before the controls: a press inside the menu that moves
# more than DRAG_START px vertically becomes a scroll; the control under the finger gets a
# cancelled press (released off-screen) so it doesn't fire; short taps pass through untouched.
const DRAG_START := 14.0
var _drag_down := false
var _dragging := false
var _drag_from := Vector2.ZERO
var _drag_scroll0 := 0.0
var _fling := 0.0
var _cancelling := false
var _swallow_up := false

func _menu_scroll_live() -> bool:
	return siege == null and modal == null and is_instance_valid(content_scroll) and content_scroll.is_visible_in_tree()

func _input(event: InputEvent) -> void:
	if _cancelling or not _menu_scroll_live():
		return
	# Touch (the phone) or a real mouse (desktop). Mouse events emulated from touch are ignored
	# here (the touch events drive it) and swallowed while a scroll is in progress.
	var is_touch: bool = event is InputEventScreenTouch or event is InputEventScreenDrag
	var emulated: bool = (event is InputEventMouse) and event.device == InputEvent.DEVICE_ID_EMULATION
	if is_touch and int(event.get("index")) != 0:
		return
	if emulated:
		# Swallow the pointer while scrolling, and the finger-lift release that follows a scroll
		# (whichever order the platform delivers the touch and its emulated mouse event in).
		if _dragging or (_swallow_up and event is InputEventMouseButton and not event.pressed):
			if event is InputEventMouseButton and not event.pressed:
				_swallow_up = false
			get_viewport().set_input_as_handled()
		return
	var press: bool = (event is InputEventScreenTouch) or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT)
	var motion: bool = (event is InputEventScreenDrag) or (event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0)
	if press:
		if event.pressed:
			_swallow_up = false
			if content_scroll.get_global_rect().has_point(event.position):
				_drag_down = true
				_dragging = false
				_drag_from = event.position
				_drag_scroll0 = content_scroll.scroll_vertical
				_fling = 0.0
		else:
			if _dragging:
				get_viewport().set_input_as_handled()
				_swallow_up = true
			_drag_down = false
			_dragging = false
	elif motion and _drag_down:
		var dy: float = event.position.y - _drag_from.y
		if not _dragging and absf(dy) > DRAG_START:
			_dragging = true
			_cancel_press()
		if _dragging:
			content_scroll.scroll_vertical = int(_drag_scroll0 - dy)
			var vy: float = event.velocity.y if "velocity" in event else event.relative.y * 60.0
			_fling = clampf(-vy, -4000.0, 4000.0)
			get_viewport().set_input_as_handled()

func _cancel_press() -> void:
	# Cancel the pressed control: move the pointer off-screen first (buttons update "pressing
	# inside" only from motion, and the drag's motion is swallowed -- without this PLAY still fired
	# after a scroll), then release there. Godot buttons only fire when released over them.
	_cancelling = true
	var away := InputEventMouseMotion.new()
	away.position = Vector2(-10000, -10000)
	away.global_position = away.position
	away.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(away, true)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = Vector2(-10000, -10000)
	up.global_position = up.position
	get_viewport().push_input(up, true)
	_cancelling = false

func _process(_delta: float) -> void:
	Assets.poll()
	# Keep gliding after a flick, easing out.
	if not _drag_down and absf(_fling) > 30.0 and _menu_scroll_live():
		content_scroll.scroll_vertical = int(content_scroll.scroll_vertical + _fling * _delta)
		_fling *= pow(0.04, _delta)
	elif not _drag_down:
		_fling = 0.0
	if _toast_box.visible:
		var left := _toast_until - Time.get_ticks_msec() / 1000.0
		_toast_box.modulate.a = clampf(left / 0.5, 0.0, 1.0)
		if left <= 0.0:
			_toast_box.visible = false

# ---------------- matches ----------------
const TUTORIAL_GOLD := 250

func start_tutorial() -> void:
	# The Herald's walkthrough: a small offline match (siege_mode.gd tutorial = true).
	start_match(false, true)

func start_match(online: bool, tutorial := false) -> void:
	if siege != null:
		return
	sfx("matchStart")
	siege = Siege.new()
	siege.online = online
	siege.tutorial = tutorial
	siege.profile = profile
	siege.audio = audio
	siege.low_fx = bool(profile.d.settings.get("reduce_motion", false))
	siege.hq_gfx = bool(profile.d.settings.get("hq_graphics", true))
	siege.player_name = str(profile.d.name)
	siege.exited.connect(_end_match)
	_set_menu_active(false)
	add_child(siege)

func _set_menu_active(on: bool) -> void:
	# While a match runs nothing of the menu may render or animate: the home hero owns a
	# physical-resolution 4x-MSAA 3D viewport plus particles, and the PLAY button loops tweens.
	# A hidden layer alone is not enough for the tweens/particles, so processing is disabled too.
	chrome.visible = on
	chrome.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	hero_layer.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	if not on:
		hero_layer.visible = false          # coming back, show_tab decides (home only)

func _end_match() -> void:
	if is_instance_valid(siege):
		siege.queue_free()
	siege = null
	_set_menu_active(true)
	show_tab("home")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if is_instance_valid(modal):
			close_modal()
		elif is_instance_valid(siege):
			siege.request_leave()
		elif tab != "home":
			show_tab("home")
		else:
			get_tree().quit()
	elif what == NOTIFICATION_APPLICATION_PAUSED and audio != null and audio.has_method("stop"):
		audio.stop()
