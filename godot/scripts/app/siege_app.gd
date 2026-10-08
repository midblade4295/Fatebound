extends Control
# Fatebound Siege app shell (replaces the dice-era full_client). Owns the profile, the chrome
# (top bar + tab bar), the five screens (scripts/app/screens.gd) and launching matches.
const UI = preload("res://scripts/app/ui.gd")
const UI2 = preload("res://scripts/app/ui2.gd")
const Roster = preload("res://scripts/app/roster.gd")
const Eco = preload("res://scripts/meta/economy.gd")
const Profile = preload("res://scripts/meta/profile.gd")
const Screens = preload("res://scripts/app/screens.gd")
const Showcase = preload("res://scripts/app/showcase.gd")
const Siege = preload("res://scripts/siege/siege_mode.gd")
const Audio = preload("res://scripts/native_audio.gd")
const Assets = preload("res://scripts/siege/asset_cache.gd")

const TABS := [["home", "HOME", "castle"], ["pass", "PASS", "banner"], ["shop", "SHOP", "stall"], ["locker", "LOCKER", "helmet"], ["settings", "SETTINGS", "gear"]]

# Tests may point these elsewhere before the node enters the tree.
var profile_path := "user://siege_profile.json"
var legacy_path := "user://fatebound-save.json"
var now_override := -1

var profile
var audio: Node
var tab := "home"
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
var hero_node: Control                 # the Home line-up (roster.gd); null on a safe start
var safe_top := 0.0
var xp_holder: Control
var pass_badge: Control
var _tab_tweens := {}
const HERO_H := 650.0                  # the home backdrop layer (plus the safe area)
const TOP_H := 56.0                    # the top bar
const TAB_H := 72.0                    # the tab bar
const BG_ASPECT := 1280.0 / 720.0      # the painted home backdrop
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
	# 0.31.79: the royal damask under every screen, faint
	var dam := TextureRect.new()
	dam.texture = UI2.tex(UI2.V2 + "tex_damask.webp")
	dam.stretch_mode = TextureRect.STRETCH_TILE
	dam.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	dam.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	dam.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dam.modulate = Color(1.6, 1.7, 2.2, 0.32)
	dam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dam)
	# A soft warm glow behind the top of the screen.
	var glow_g := Gradient.new()
	glow_g.set_color(0, Color(1.0, 0.72, 0.3, 0.18))
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
	# 0.31.79: Home's painted backdrop (castle battlements at golden hour, the rival castle beyond, a gold-rimmed dais),
	# drifting cloud wisps, slow sun rays, the seven heroes in 3D on the dais (roster.gd), gold motes and the logo.
	# Scrolls away with a parallax as the menu is scrolled.
	safe_top = _safe_top()
	hero_layer = Control.new()
	hero_layer.anchor_right = 1.0
	hero_layer.offset_bottom = HERO_H + safe_top
	hero_layer.clip_contents = true
	hero_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hero_layer)
	var bgt := TextureRect.new()
	bgt.texture = UI2.tex(UI2.V2 + "bg_home.webp")
	bgt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bgt.stretch_mode = TextureRect.STRETCH_SCALE
	bgt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero_layer.add_child(bgt)
	var calm := bool(profile.d.settings.get("reduce_motion", false))
	var clouds: Array = []
	for cd in [[0.36, 260.0, 46.0, 0.42, 75.0], [0.47, 200.0, 34.0, 0.36, 60.0], [0.27, 170.0, 30.0, 0.3, 95.0]]:
		var c := TextureRect.new()
		c.texture = UI2.glow_tex()
		c.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		c.stretch_mode = TextureRect.STRETCH_SCALE
		c.size = Vector2(cd[1], cd[2])
		c.modulate = Color(1, 0.97, 0.92, cd[3])
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hero_layer.add_child(c)
		clouds.append([c, cd])
	var sun := UI2.rays(hero_layer, 620.0, Color(1.0, 0.9, 0.62), 90.0, 0.32)
	var sun_glow := UI2.glow(hero_layer, Rect2(0, 0, 170, 170), Color(1.0, 0.93, 0.7, 0.7))
	if safe_boot:
		hero_node = null                      # safe start: the painted backdrop only, no live 3D heroes
	else:
		hero_node = Roster.new()
		hero_layer.add_child(hero_node)
	var lay := func():
		var w := hero_layer.size.x
		var h := w * BG_ASPECT
		var top := -0.405 * w + safe_top
		bgt.position = Vector2(0, top)
		bgt.size = Vector2(w, h)
		var sp := Vector2(0.615 * w, top + 0.574 * h)
		sun.position = sp - sun.size * 0.5
		sun_glow.position = sp - sun_glow.size * 0.5
		for cl in clouds:
			(cl[0] as Control).position.y = top + float(cl[1][0]) * h
		if hero_node != null:
			var dais := top + 0.858 * h                     # the painted dais' centre
			hero_node.position = Vector2(0, dais - Roster.FEET_Y)
			hero_node.size = Vector2(w, 340.0)
	hero_layer.resized.connect(lay)
	lay.call()
	if not calm:
		for cl in clouds:
			var c: Control = cl[0]
			var secs: float = cl[1][4]
			c.position.x = randf_range(-80.0, 300.0)
			UI2.when_ready(c, func(): _drift(c, secs, true))
	_band(hero_layer, Color(0.02, 0.03, 0.09, 0.72), Color(0.02, 0.03, 0.09, 0.0), true, 110.0 + safe_top)
	_band(hero_layer, Color(FADE_COLOR, 0.0), Color(FADE_COLOR, 1.0), false, 150.0)
	if not calm:
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
		motes.position = Vector2(210, 470 + safe_top)
		motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		motes.emission_rect_extents = Vector2(200, 30)
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
	# The game is just "Fatebound" (Kevin): the logo in Luckiest Guy, like the trailer and store art.
	var logo := UI2.text(hero_layer, "FATEBOUND", 50, UI2.GOLD, UI2.INK, 13)
	logo.add_theme_color_override("font_shadow_color", Color(0.1, 0.05, 0.0, 0.85))
	logo.add_theme_constant_override("shadow_offset_y", 6)
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo.anchor_right = 1.0
	logo.offset_top = 66 + safe_top
	logo.offset_bottom = 122 + safe_top
	var tag := UI.label(hero_layer, "ANYONE  CAN  CHANGE  FATE", 11, UI2.CREAM, UI.HEAVY_FONT)
	tag.autowrap_mode = TextServer.AUTOWRAP_OFF
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	tag.add_theme_constant_override("outline_size", 4)
	tag.anchor_right = 1.0
	tag.offset_top = 122 + safe_top
	tag.offset_bottom = 138 + safe_top
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE

const LOGO_FONT = preload("res://assets/fonts/LuckiestGuy-Regular.ttf")

func _drift(c: Control, secs: float, first: bool) -> void:
	# a cloud wisp crosses the sky left to right, then starts again off the left edge
	var w := hero_layer.size.x
	if not first:
		c.position.x = -c.size.x - 20.0
	var dist := w + 40.0 - c.position.x
	var tw := c.create_tween()
	tw.tween_property(c, "position:x", w + 40.0, secs * dist / (w + c.size.x + 60.0))
	tw.tween_callback(func(): _drift(c, secs, false))

func hero_show(_cls := "", _look := {}) -> void:
	# Home's line-up wears what's equipped (rebuilt only for a class whose look changed).
	if hero_node != null:
		var looks := {}
		for c in Eco.CLASSES:
			looks[c] = profile.look_for(c)
		hero_node.set_looks(looks)

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
	UI.spacer(chrome, 6.0 + safe_top)
	# --- top bar: level shield, name + XP, gold and gems (0.31.79 look)
	var top := Control.new()
	top.custom_minimum_size = Vector2(0, TOP_H)
	chrome.add_child(top)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.offset_left = 10
	bar.offset_right = -10
	bar.offset_bottom = -6
	top.add_child(bar)
	var sh := Control.new()
	sh.custom_minimum_size = Vector2(44, 50)
	sh.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(sh)
	var st := TextureRect.new()
	st.texture = UI2.tex(UI2.V2 + "shield.svg")
	st.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	st.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	st.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	st.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sh.add_child(st)
	level_label = UI2.text(sh, "1", 20, Color.WHITE, Color("#0e1433"), 5)
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	level_label.offset_bottom = -6
	var who := VBoxContainer.new()
	who.add_theme_constant_override("separation", 4)
	who.alignment = BoxContainer.ALIGNMENT_CENTER
	UI.grow(who)
	bar.add_child(who)
	name_label = UI2.body(who, "", 14, Color.WHITE, false)
	name_label.clip_text = true
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	name_label.add_theme_constant_override("outline_size", 4)
	xp_holder = VBoxContainer.new()
	xp_holder.custom_minimum_size = Vector2(0, 10)
	who.add_child(xp_holder)
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
	margin.add_theme_constant_override("margin_bottom", 26)
	content_scroll.add_child(margin)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(content)
	# --- tab bar: dark wood with a gold edge; the open tab is a raised gold-framed tile (0.31.79)
	var tb := Control.new()
	tb.custom_minimum_size = Vector2(0, TAB_H)
	chrome.add_child(tb)
	var wood := TextureRect.new()
	wood.texture = UI2.tex(UI2.V2 + "tex_wood.webp")
	wood.stretch_mode = TextureRect.STRETCH_TILE
	wood.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wood.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	wood.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wood.modulate = Color(0.62, 0.5, 0.42)
	wood.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tb.add_child(wood)
	_band(tb, Color(0.08, 0.03, 0.0, 0.1), Color(0.05, 0.02, 0.0, 0.7), true, TAB_H)
	var edge := ColorRect.new()
	edge.color = Color("#2a1604")
	edge.anchor_right = 1.0
	edge.offset_top = -3
	edge.offset_bottom = 3
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tb.add_child(edge)
	var gold_edge := TextureRect.new()
	gold_edge.texture = _grad(Color("#fff0b0"), Color("#b9761b"), 4, 16)
	gold_edge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gold_edge.stretch_mode = TextureRect.STRETCH_SCALE
	gold_edge.anchor_right = 1.0
	gold_edge.offset_top = -2
	gold_edge.offset_bottom = 2
	gold_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tb.add_child(gold_edge)
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 0)
	trow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	trow.offset_left = 4
	trow.offset_right = -4
	tb.add_child(trow)
	for t in TABS:
		tab_buttons[t[0]] = _tab_button(trow, t[0], t[1], t[2])
	pass_badge = UI2.badge(tab_buttons["pass"].button, "0", Vector2(-10, 4))
	tab_buttons["pass"]["badge"] = pass_badge

func _pill(parent: Node, kind: String) -> Label:
	# A dark pill with the currency coming out of its left end and a green "+". Tapping it opens the shop.
	var p := PanelContainer.new()
	var sb := StyleBoxEmpty.new()
	sb.content_margin_left = 16
	sb.content_margin_right = 4
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(p)
	UI2.skin(p, {"radius": 15.0, "outline": 2.0, "outline_color": Color("#e9b648") if kind == "coin" else Color("#5fd2f0"),
		"rim": 0.0, "fill_top": Color(0.06, 0.09, 0.24, 0.94), "fill_bottom": Color(0.01, 0.02, 0.08, 0.94), "shadow_y": 3.0, "shadow_alpha": 0.5, "bevel": 0.1})
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 3)
	p.add_child(r)
	var l := UI2.body(r, "0", 14, Color.WHITE, false)
	l.custom_minimum_size = Vector2(40, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var plus := Panel.new()
	plus.custom_minimum_size = Vector2(22, 22)
	plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(plus)
	UI2.skin(plus, UI2.button_params("green", 7.0, 3.0))
	var pl := UI.label(plus, "+", 16, Color.WHITE, UI.HEAVY_FONT)
	pl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pl.offset_top = -3
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var coin := TextureRect.new()
	coin.texture = UI2.tex("res://assets/ui/currency/%s.png" % ("coin" if kind == "coin" else "gem"))
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin.size = Vector2(32, 32)
	coin.position = Vector2(-14, -4)
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(coin)                      # (a non-container child, so it's placed by hand)
	coin.top_level = false
	p.sort_children.connect(func():
		coin.size = Vector2(32, 32)
		coin.position = Vector2(-16, (p.size.y - 32.0) * 0.5))
	for c in r.get_children():
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hit := Button.new()
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	for st_name in ["normal", "hover", "pressed", "focus"]:
		hit.add_theme_stylebox_override(st_name, StyleBoxEmpty.new())
	hit.set_meta("action_key", "pill_" + kind)
	hit.pressed.connect(func():
		sfx("tap")
		show_tab("shop"))
	p.add_child(hit)
	return l

func _tab_button(parent: Node, id: String, text: String, icon_name: String) -> Dictionary:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	for st_name in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st_name, StyleBoxEmpty.new())
	b.custom_minimum_size = Vector2(0, TAB_H)
	b.set_meta("action_key", "tab_" + id)
	UI.grow(b)
	b.pressed.connect(func():
		sfx("tap")
		show_tab(id))
	parent.add_child(b)
	var plate := Control.new()                    # the raised tile of the open tab
	plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	plate.offset_top = -18
	plate.offset_left = 1
	plate.offset_right = -1
	plate.offset_bottom = -3
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.visible = false
	b.add_child(plate)
	UI2.plate(plate, "royal", 16.0, "gold")
	var halo := UI2.glow(plate, Rect2(0, 0, 10, 10), Color(1.0, 0.86, 0.45, 0.55))
	plate.resized.connect(func():
		halo.size = Vector2(plate.size.x * 1.1, 56)
		halo.position = Vector2(plate.size.x * -0.05, 2))
	var ic := TextureRect.new()
	ic.texture = UI2.tex(UI2.icon_path(icon_name))
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(ic)
	var l := UI2.text(b, text, 11, Color("#f1dfba"), Color(0.1, 0.04, 0.0, 0.9), 3, false)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	l.offset_top = -22
	l.offset_bottom = -6
	return {"button":b, "icon":ic, "label":l, "plate":plate}

func _style_tab(tb: Dictionary, on: bool) -> void:
	var b: Button = tb.button
	var ic: TextureRect = tb.icon
	var l: Label = tb.label
	(tb.plate as Control).visible = on
	var px := 52.0 if on else 38.0
	var place := func():
		ic.size = Vector2(px, px)
		ic.position = Vector2((b.size.x - px) * 0.5, -8.0 if on else 6.0)
	if b.resized.is_connected(tb.get("place", func(): pass)):
		b.resized.disconnect(tb.place)
	tb["place"] = place
	b.resized.connect(place)
	place.call()
	ic.modulate = Color.WHITE if on else Color(0.92, 0.88, 0.84)
	l.add_theme_color_override("font_color", UI2.GOLD if on else Color("#f1dfba"))
	l.add_theme_font_size_override("font_size", 13 if on else 10)
	l.add_theme_constant_override("outline_size", 4 if on else 3)
	var key := str(b.get_meta("action_key"))
	if _tab_tweens.has(key) and is_instance_valid(_tab_tweens[key]):
		(_tab_tweens[key] as Tween).kill()
	_tab_tweens.erase(key)
	if on and is_inside_tree():
		var tw := ic.create_tween().set_loops()
		tw.tween_property(ic, "position:y", -12.0, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(ic, "position:y", -8.0, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_tab_tweens[key] = tw

func refresh_top() -> void:
	var d: Dictionary = profile.d
	level_label.text = str(int(d.level))
	var title := ""
	if str(d.title) != "":
		title = "  ·  " + str(Eco.item(str(d.title)).get("name", ""))
	name_label.text = str(d.name) + title
	for c in xp_holder.get_children():
		c.queue_free()
	UI2.bar(xp_holder, int(d.xp), Eco.level_xp(int(d.level)), Color("#b6f3ff"), Color("#36b9ea"), 10.0)
	gold_label.text = UI.compact(int(d.gold))
	gems_label.text = UI.compact(int(d.gems))
	# Badge on the PASS tab when rewards are waiting.
	var claimable := 0
	for tier in range(1, profile.pass_tier() + 1):
		for prem in [false, true]:
			if profile.can_claim(tier, prem):
				claimable += 1
	pass_badge.visible = claimable > 0
	(pass_badge.get_child(0) as Label).text = str(claimable)

func show_tab(id: String) -> void:
	tab = id
	profile.refresh()
	for t in tab_buttons:
		_style_tab(tab_buttons[t], t == id)
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
