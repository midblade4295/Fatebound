extends Control
# 0.31.79 (Kevin: "chests in 3d and animated"): opening a chest. The Meshy chest teases in the middle of a sunburst;
# TAP TO OPEN (or OPEN) rolls the contents (Profile.open_chest), the chest shakes, the lid flies open with a flash and a
# spray of coins, the chest sinks and the rewards rise into view one by one: the weapon (or the gold), then the gold and
# gems, then COLLECT / EQUIP NOW.
const UI = preload("res://scripts/app/ui.gd")
const UI2 = preload("res://scripts/app/ui2.gd")
const Eco = preload("res://scripts/meta/economy.gd")
const Chest3D = preload("res://scripts/app/chest3d.gd")

var app
var index := 0
var kind := "wooden"
var result: Dictionary = {}

var _stage: Control
var _vp: SubViewport
var _chest: Node3D
var _t := 0.0
var _open_t := -1.0
var _rays: TextureRect
var _rays2: TextureRect
var _prompt: Control
var _reveal: Control
var _flash: ColorRect

const COLORS := {
	"wooden": [Color("#6a4220"), Color("#2a160a"), Color("#f0bf86"), Color(1.0, 0.77, 0.51)],
	"silver": [Color("#3d5878"), Color("#121e33"), Color("#eef4fa"), Color(0.84, 0.91, 1.0)],
	"gold": [Color("#6b4a12"), Color("#24150a"), Color("#ffd65a"), Color(1.0, 0.84, 0.43)],
	"royal": [Color("#4a1f86"), Color("#140829"), Color("#e0b5ff"), Color(0.8, 0.59, 1.0)],
}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var cs: Array = COLORS.get(kind, COLORS.wooden)
	var g := Gradient.new()
	g.set_color(0, cs[0])
	g.set_color(1, Color("#06040f"))
	g.add_point(0.45, cs[1])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.45)
	gt.fill_to = Vector2(1.15, 0.45)
	gt.width = 128
	gt.height = 256
	var bg := TextureRect.new()
	bg.texture = gt
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.2)
	_rays = UI2.rays(self, 900.0, cs[3], 46.0, 0.34)
	for i in 8:
		_twinkle(Vector2(randf_range(30, 390), randf_range(170, 640)), randf_range(8, 14), randf_range(0.0, 2.0))
	var def: Dictionary = Eco.CHESTS[kind]
	var title := UI2.text(self, str(def.name).to_upper(), 36, cs[2], UI2.INK, 9)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_right = 1.0
	title.offset_top = 64 + _safe()
	title.offset_bottom = 110 + _safe()
	var odds := UI2.body(self, Eco.chest_odds(kind), 11, Color("#e8dcff"))
	odds.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	odds.anchor_right = 1.0
	odds.offset_left = 24
	odds.offset_right = -24
	odds.offset_top = 112 + _safe()
	odds.offset_bottom = 150 + _safe()
	# the chest
	_stage = Control.new()
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.size = Vector2(340, 340)
	add_child(_stage)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_stage.add_child(_vp)
	var vt := TextureRect.new()
	vt.texture = _vp.get_texture()
	vt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vt.stretch_mode = TextureRect.STRETCH_SCALE
	vt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(vt)
	var world := Node3D.new()
	_vp.add_child(world)
	Chest3D.stage(world)
	var cam := Camera3D.new()
	cam.fov = 28.0
	world.add_child(cam)
	var yaw := deg_to_rad(28.0)
	cam.look_at_from_position(Vector3(sin(yaw) * 7.1, 2.75, cos(yaw) * 7.1), Vector3(0.0, 0.8, 0.0), Vector3.UP)
	_chest = Chest3D.make(kind)
	world.add_child(_chest)
	var tap := Button.new()
	tap.flat = true
	for st_name in ["normal", "hover", "pressed", "focus"]:
		tap.add_theme_stylebox_override(st_name, StyleBoxEmpty.new())
	tap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tap.set_meta("action_key", "chest_tap")
	tap.pressed.connect(open)
	_stage.add_child(tap)
	# before: TAP TO OPEN and a big OPEN
	_prompt = Control.new()
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_prompt)
	var tt := UI2.text(_prompt, "TAP TO OPEN", 26, Color.WHITE, UI2.INK, 7)
	tt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tt.anchor_top = 1.0
	tt.anchor_bottom = 1.0
	tt.anchor_right = 1.0
	tt.offset_top = -200
	tt.offset_bottom = -166
	UI2.pulse(tt, 0.06, 0.7)
	var ob := UI2.button(_prompt, "OPEN", "gold", open, "chest_modal_open", 32, 66.0, 20.0)
	ob.anchor_left = 0.5
	ob.anchor_right = 0.5
	ob.anchor_top = 1.0
	ob.anchor_bottom = 1.0
	ob.offset_left = -125
	ob.offset_right = 125
	ob.offset_top = -138
	ob.offset_bottom = -72
	UI2.sweep(ob)
	var close := UI2.button(_prompt, "✕", "ghost", func():
		app.sfx("menuClose")
		app.close_modal(), "chest_modal_close", 20, 40.0, 12.0)
	close.custom_minimum_size = Vector2(44, 44)
	close.position = Vector2(12, 14 + _safe())
	resized.connect(_layout)
	_layout()

func _safe() -> float:
	return float(app.safe_top) if app != null else 0.0

func _layout() -> void:
	var r := Chest3D.viewport_ratio(self)
	_vp.size = Vector2i(int(340 * r), int(340 * r))
	var c := Vector2(size.x * 0.5, size.y * 0.5 + 20)
	if _open_t < 0.0:
		_stage.position = c - Vector2(170, 170)
	_rays.position = c - _rays.size * 0.5

func _twinkle(at: Vector2, px: float, delay: float) -> void:
	var t := TextureRect.new()
	t.texture = UI2.glow_tex()
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.size = Vector2(px, px)
	t.position = at
	t.pivot_offset = Vector2(px, px) * 0.5
	t.modulate = Color(1, 0.95, 0.8, 0.0)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(t)
	UI2.when_ready(t, func():
		var tw := t.create_tween().set_loops()
		tw.tween_interval(delay)
		tw.tween_property(t, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE)
		tw.tween_property(t, "modulate:a", 0.1, 0.8).set_trans(Tween.TRANS_SINE))

func open() -> void:
	if _open_t >= 0.0:
		return
	result = app.profile.open_chest(index)
	if not bool(result.get("ok", false)):
		app.close_modal()
		return
	app.sfx("purchase")
	_open_t = 0.0
	var tw := create_tween()
	tw.tween_property(_prompt, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func(): _prompt.visible = false)

func _process(delta: float) -> void:
	_t += delta
	if _open_t < 0.0:
		Chest3D.pose(_chest, "tease", _t)
		return
	var was := _open_t
	_open_t += delta
	Chest3D.pose(_chest, "open" if _open_t < 1.6 else "opened", _open_t)
	if was < 0.45 and _open_t >= 0.45:
		_burst()
	if was < 1.3 and _open_t >= 1.3:
		var c := Vector2(size.x * 0.5, size.y * 0.5 + 20)
		var tw := create_tween().set_parallel()
		tw.tween_property(_stage, "position", c - Vector2(170, 170) + Vector2(0, 150), 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		_stage.pivot_offset = Vector2(170, 170)
		tw.tween_property(_stage, "scale", Vector2.ONE * 0.62, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(_rays, "position", c - _rays.size * 0.5 + Vector2(0, -60), 0.55)
	if was < 1.45 and _open_t >= 1.45:
		_show_rewards()

func _burst() -> void:
	app.sfx("coin")
	var cs: Array = COLORS.get(kind, COLORS.wooden)
	_flash = ColorRect.new()
	_flash.color = Color(1, 0.98, 0.9, 0.0)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)
	var ft := create_tween()
	ft.tween_property(_flash, "color:a", 0.9, 0.08)
	ft.tween_property(_flash, "color:a", 0.0, 0.7)
	ft.tween_callback(_flash.queue_free)
	_rays2 = UI2.rays(self, 760.0, cs[3], 18.0, 0.0)
	var c := Vector2(size.x * 0.5, size.y * 0.5 + 20)
	_rays2.position = c - _rays2.size * 0.5 + Vector2(0, -60)
	move_child(_rays2, 2)
	create_tween().tween_property(_rays2, "modulate:a", 0.7, 0.4)
	# coins and gems spray out of the chest
	var origin := c + Vector2(0, -10)
	for i in 16:
		var gem := i % 4 == 1
		var px := 34.0 if i % 3 else 42.0
		var t := TextureRect.new()
		t.texture = UI2.tex("res://assets/ui/currency/%s.png" % ("gem" if gem else "coin"))
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.size = Vector2(px, px)
		t.pivot_offset = t.size * 0.5
		t.position = origin - t.size * 0.5
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(t)
		var ang := deg_to_rad(-165.0 + i * (150.0 / 15.0) + randf_range(-6, 6))
		var dist := randf_range(150, 230)
		var dest := origin + Vector2(cos(ang), sin(ang)) * dist + Vector2(0, 70)
		var peak := origin + Vector2(cos(ang), sin(ang)) * dist * 0.6 + Vector2(0, -60)
		var dur := randf_range(0.9, 1.3)
		var spin := randf_range(-6.0, 6.0)
		var tw := t.create_tween()
		tw.tween_method(func(v: float):
			var a := origin.lerp(peak, v)
			var b := peak.lerp(dest, v)
			t.position = a.lerp(b, v) - t.size * 0.5
			t.rotation = v * spin
			t.modulate.a = 1.0 - maxf(0.0, (v - 0.7) / 0.3), 0.0, 1.0, dur)
		tw.tween_callback(t.queue_free)

func _show_rewards() -> void:
	_reveal = Control.new()
	_reveal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_reveal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_reveal)
	var item := str(result.get("item", ""))
	var top := 168.0 + _safe()
	var card := Control.new()
	card.size = Vector2(210, 238)
	card.position = Vector2((size.x - 210) * 0.5, top)
	card.pivot_offset = card.size * 0.5
	_reveal.add_child(card)
	var rar := "common"
	var title := ""
	var tag := ""
	var icon := ""
	if item != "":
		var it := Eco.item(item)
		rar = str(it.get("rarity", "rare"))
		title = str(it.get("name", "")).to_upper()
		tag = "%s  ·  %s %s" % [rar.to_upper(), str(Eco.CLASS_NAMES.get(str(it.get("class", "")), "")).to_upper(), str(it.get("kind", "")).to_upper()]
		icon = "res://assets/ui/icons/%s.png" % item
	elif int(result.get("dupe_gold", 0)) > 0:
		title = "+%d GOLD" % int(result.dupe_gold)
		tag = "A WEAPON YOU OWN  ·  TURNED INTO GOLD"
		icon = "res://assets/ui/currency/coins_l.png"
	else:
		title = "+%d GOLD" % int(result.get("gold", 0))
		tag = "NO WEAPON THIS TIME"
		icon = "res://assets/ui/currency/coins_l.png"
	var panel: String = {"common": "night", "rare": "royal", "epic": "purple", "legendary": "ember"}.get(rar, "night")
	var rim: String = {"common": "silver", "rare": "blue", "epic": "purple", "legendary": "orange"}.get(rar, "gold")
	var tint: Color = {"common": Color(1, 0.9, 0.6), "rare": Color(0.5, 0.75, 1.0), "epic": Color(0.8, 0.55, 1.0), "legendary": Color(1.0, 0.75, 0.3)}.get(rar, Color(1, 0.9, 0.6))
	var plate := Control.new()
	plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	plate.clip_contents = true
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(plate)
	UI2.plate(plate, panel, 22.0, rim, {"rim": 4.0})
	var halo := UI2.rays(plate, 300.0, tint, 16.0, 0.5)
	halo.position = Vector2(-45, -60)
	var ic := UI2.img(card, icon, 140.0)
	ic.position = Vector2(35, 14)
	UI2.bob(ic, 6.0, 1.3)
	var nl := UI2.text(card, title, 17, Color.WHITE, UI2.INK, 5)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.position = Vector2(10, 158)
	nl.size = Vector2(190, 44)
	var tl := UI2.body(card, tag, 10, tint.lightened(0.2), false)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.position = Vector2(6, 206)
	tl.size = Vector2(198, 20)
	if item != "":
		var nb := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#e8443a")
		sb.border_color = Color("#3a0805")
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(10)
		sb.content_margin_left = 9
		sb.content_margin_right = 9
		sb.content_margin_top = 3
		sb.content_margin_bottom = 1
		nb.add_theme_stylebox_override("panel", sb)
		nb.position = Vector2(150, -14)
		nb.rotation = deg_to_rad(12)
		card.add_child(nb)
		UI2.text(nb, "NEW!", 16, Color.WHITE, Color("#3a0805"), 4)
	card.scale = Vector2.ONE * 0.6
	card.modulate.a = 0.0
	var tw := create_tween().set_parallel()
	tw.tween_property(card, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "modulate:a", 1.0, 0.25)
	# gold and gems
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 12)
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	chips.position = Vector2(20, top + 256)
	chips.size = Vector2(size.x - 40, 60)
	_reveal.add_child(chips)
	var amounts := []
	if item != "" or int(result.get("dupe_gold", 0)) > 0:
		amounts.append(["coins_m", "+%s" % UI.compact(int(result.get("gold", 0))), UI2.GOLD, UI2.INK])
	if int(result.get("gems", 0)) > 0:
		amounts.append(["gems", "+%d" % int(result.gems), UI2.CYAN, Color("#06283a")])
	var k := 0
	for a in amounts:
		var f := UI2.frame(chips, "night", 6, 16.0, "gold")
		var pc := f.get_parent() as Control
		pc.custom_minimum_size = Vector2(150, 58)
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 6)
		r.alignment = BoxContainer.ALIGNMENT_CENTER
		f.add_child(r)
		UI2.img(r, "res://assets/ui/currency/%s.png" % a[0], 46.0)
		UI2.text(r, a[1], 24, a[2], a[3], 6)
		pc.modulate.a = 0.0
		var ct := create_tween()
		ct.tween_interval(0.35 + k * 0.2)
		ct.tween_property(pc, "modulate:a", 1.0, 0.25)
		k += 1
	# actions
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.anchor_top = 1.0
	row.anchor_bottom = 1.0
	row.anchor_right = 1.0
	row.offset_left = 16
	row.offset_right = -16
	row.offset_top = -100
	row.offset_bottom = -36
	_reveal.add_child(row)
	if item != "":
		var eb := UI2.button(row, "EQUIP NOW", "blue", func():
			app.profile.equip(item)
			app.sfx("equip")
			_close(), "chest_equip", 20, 62.0, 18.0)
		eb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cb := UI2.button(row, "COLLECT", "green", _close, "chest_collect", 26, 62.0, 18.0)
	cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cb.size_flags_stretch_ratio = 1.3
	UI2.sweep(cb)
	row.modulate.a = 0.0
	var rt := create_tween()
	rt.tween_interval(0.8)
	rt.tween_property(row, "modulate:a", 1.0, 0.3)

func _close() -> void:
	app.sfx("coin")
	app.close_modal()
	app.rebuild()
