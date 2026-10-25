extends Control
# 0.31.217 TRAINING (Kevin, with a recording of Honor of Kings' first launch: "Here is how I want the training to go in
# fatebound"): which training -- 1 THE BASICS or 2 5V5 BATTLE -- and a hero of three (Honor of Kings' pick of three), Kael
# the Dragoon beside them; BATTLE -> siege_app.start_training. The menu's TUTORIAL, the Herald's first-run intro and
# Settings' HOW TO PLAY open it (siege_app.start_tutorial). The match itself: scripts/siege/training.gd.
const UI = preload("res://scripts/app/ui.gd")
const UI2 = preload("res://scripts/app/ui2.gd")
const SocialUI = preload("res://scripts/app/social_ui.gd")
const MobaPanel = preload("res://scripts/app/moba_panel.gd")
const Kits = preload("res://scripts/siege/moba_kits.gd")
const Moba = preload("res://scripts/siege/moba.gd")
const Eco = preload("res://scripts/meta/economy.gd")
const KAEL := "res://assets/ui/skins/default_dragoon.png"
# the three to pick from: a tank for the top lane, a mage for the middle, a marksman for the bottom
const HEROES := [["knight", "TANK", "Top lane"], ["mage", "MAGE", "Middle lane"], ["ranger", "MARKSMAN", "Bottom lane"]]
const TRAININGS := [
	["1", "THE BASICS", "Move, fight, learn your skills, buy from the quick-buy, break the towers and the King."],
	["2", "5V5 BATTLE", "The Rift's lanes and who goes where, how towers fight -- then a real match, Kael beside you."]]

var app
var which := 1
var hero := "knight"
var _cards: Array = []           # the two trainings' buttons
var _heroes: Array = []          # the three heroes' buttons
var _say: Label

func open(a) -> void:
	app = a
	var done := bool(app.profile.d.get("tutorial_done", false)) if app.profile != null else false
	which = 2 if done else 1
	var saved := str(app.profile.d.settings.get("moba_hero", "")) if app.profile != null else ""
	for h in HEROES:
		if str(h[0]) == saved:
			hero = saved
	var w := SocialUI.window(self, "TRAINING", "horn", func():
		app.sfx("menuClose")
		app.close_modal(), 6.0 + float(app.safe_top), 8.0)
	var sheet: VBoxContainer = w.body
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sheet.add_child(cols)
	# Kael, on the left
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 4)
	left.custom_minimum_size = Vector2(150, 0)
	cols.add_child(left)
	var face := Panel.new()
	face.custom_minimum_size = Vector2(120, 120)
	face.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var fs := StyleBoxFlat.new()
	fs.bg_color = Color(0.85, 0.72, 0.42)
	fs.set_corner_radius_all(60)
	fs.border_color = UI2.GOLD
	fs.set_border_width_all(3)
	fs.anti_aliasing = true
	face.add_theme_stylebox_override("panel", fs)
	face.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	left.add_child(face)
	var ft := TextureRect.new()
	ft.texture = load(KAEL) if ResourceLoader.exists(KAEL) else null
	ft.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ft.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	ft.position = Vector2(-14, -4)
	ft.size = Vector2(148, 148)
	face.add_child(ft)
	UI2.center(UI2.text(left, "KAEL", 18, UI2.GOLD))
	UI2.center(UI2.body(left, "The Dragoon · your trainer", 10, UI2.SOFT, false))
	_say = UI2.body(left, "", 11, Color("#fff4d6"))
	_say.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# the trainings and the heroes, on the right
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(body)
	UI2.text(body, "CHOOSE A TRAINING", 14, UI2.GOLD)
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 8)
	body.add_child(trow)
	_cards = []
	for i in TRAININGS.size():
		var td: Array = TRAININGS[i]
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 92)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.set_meta("action_key", "training_%d" % (i + 1))
		trow.add_child(b)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 1)
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.offset_left = 10
		v.offset_right = -10
		v.offset_top = 6
		v.offset_bottom = -6
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(v)
		var hrow := HBoxContainer.new()
		hrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(hrow)
		var n := UI2.text(hrow, "TRAINING %s" % str(td[0]), 11, UI2.SOFT)
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if i == 0 and not done:
			var sp := Control.new()
			sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hrow.add_child(sp)
			var g := UI2.text(hrow, "+%d GOLD" % Eco.TUTORIAL_GOLD, 11, Color("#ffd65a"))
			g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var t := UI2.text(v, str(td[1]), 17, Color.WHITE)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var d := UI2.body(v, str(td[2]), 10, UI2.SOFT)
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ti := i + 1
		b.pressed.connect(func():
			app.sfx("tab")
			which = ti
			_refresh())
		_cards.append(b)
	UI2.text(body, "PICK YOUR HERO", 14, UI2.GOLD)
	var hrow2 := HBoxContainer.new()
	hrow2.add_theme_constant_override("separation", 8)
	body.add_child(hrow2)
	_heroes = []
	for h in HEROES:
		var hid := str(h[0])
		var b2 := Button.new()
		b2.focus_mode = Control.FOCUS_NONE
		b2.custom_minimum_size = Vector2(0, 92)
		b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b2.set_meta("action_key", "training_hero_" + hid)
		b2.set_meta("hid", hid)
		hrow2.add_child(b2)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 6)
		hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hb.offset_left = 6
		hb.offset_right = -6
		hb.offset_top = 6
		hb.offset_bottom = -6
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b2.add_child(hb)
		var pt := TextureRect.new()
		pt.texture = load(MobaPanel.portrait(hid)) if ResourceLoader.exists(MobaPanel.portrait(hid)) else null
		pt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pt.custom_minimum_size = Vector2(70, 70)
		pt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(pt)
		var hv := VBoxContainer.new()
		hv.add_theme_constant_override("separation", 0)
		hv.alignment = BoxContainer.ALIGNMENT_CENTER
		hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(hv)
		var nm := UI2.text(hv, str(Moba.HEROES[hid].name).to_upper(), 15, Color.WHITE)
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rl := UI2.text(hv, str(h[1]), 11, Color(MobaPanel.ROLE_COL.get(Kits.role_of(hid), "#ffffff")))
		rl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ln := UI2.body(hv, str(h[2]), 10, UI2.SOFT, false)
		ln.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b2.pressed.connect(func():
			app.sfx("tab")
			hero = hid
			_refresh())
		_heroes.append(b2)
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(gap)
	var brow := HBoxContainer.new()
	brow.alignment = BoxContainer.ALIGNMENT_END
	body.add_child(brow)
	var go := UI2.button(brow, "BATTLE", "gold", func():
		app.sfx("confirm")
		app.close_modal()
		app.start_training(which, hero), "training_go", 20, 46.0)
	go.custom_minimum_size.x = 200
	_refresh()

func _refresh() -> void:
	for i in _cards.size():
		_style(_cards[i], i + 1 == which)
	for b in _heroes:
		_style(b, str(b.get_meta("hid")) == hero)
	var lane := ""
	for h in HEROES:
		if str(h[0]) == hero:
			lane = str(h[2]).to_lower()
	_say.text = ("\"Stay close, and I'll show you how we fight.\"" if which == 1 else
		"\"Five against five. %s %s's place is the %s -- I'll take you there.\"" % [("An" if str(Moba.HEROES[hero].name).left(1) in ["A", "E", "I", "O", "U"] else "A"), str(Moba.HEROES[hero].name), lane])

static func _style(b: Button, on: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.22, 0.15, 0.05, 0.96) if on else Color(0.05, 0.07, 0.14, 0.92)
	sb.border_color = Color("#ffd65a") if on else Color("#3e4a66")
	sb.set_border_width_all(3 if on else 2)
	sb.set_corner_radius_all(12)
	sb.anti_aliasing = true
	if on:
		sb.shadow_color = Color(1.0, 0.82, 0.35, 0.45)
		sb.shadow_size = 6
	for st in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		b.add_theme_stylebox_override(st, sb)
