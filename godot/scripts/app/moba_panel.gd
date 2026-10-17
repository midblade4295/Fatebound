extends Control
# 0.31.155 5V5 (the test; scripts/siege/moba.gd): pick your hero, then BATTLE -- an offline 5v5 with bots on both sides
# (siege_app.start_moba). Twelve heroes: the six classes and their six upgrades. The last pick is kept on the phone
# (settings.moba_hero). Everything is unlocked for the test.
const UI = preload("res://scripts/app/ui.gd")
const UI2 = preload("res://scripts/app/ui2.gd")
const SocialUI = preload("res://scripts/app/social_ui.gd")
const Moba = preload("res://scripts/siege/moba.gd")

const CARD_W := 74.0
const CARD_H := 96.0
const LOOK := {"knight":"knight", "barbarian":"barbarian", "rogue":"rogue", "ranger":"ranger", "mage":"mage", "priest":"priest",
	"crusader":"crusader", "berserker":"berserker", "assassin":"assassin", "sniper":"sniper", "archmage":"archmage", "necromancer":"necromancer"}

var app
var hero := "knight"
var _grid: GridContainer
var _info: Label
var _go: Button

static func portrait(hid: String) -> String:
	return "res://assets/ui/skins/default_%s.png" % str(LOOK.get(hid, "knight"))

func open(a) -> void:
	app = a
	var saved := str(app.profile.d.settings.get("moba_hero", ""))
	hero = saved if Moba.HEROES.has(saved) else "knight"
	var w := SocialUI.window(self, "5V5", "swords", func():
		app.sfx("menuClose")
		app.close_modal(), 56.0 + float(app.safe_top), 24.0)
	var body: VBoxContainer = w.body
	# (0.31.155-0.31.163: "TEST MODE" -- 0.31.164, Kevin: "5v5 only": it's the game's match now, PLAY opens this)
	UI2.body(body, "You and four bot heroes against five. Every 30 seconds each castle sends minions down the three lanes. "
		+ "Two towers guard each lane, and your gates are behind them. Level up to 10 by fighting near minions; pick an "
		+ "upgrade each level, and at level 6 your ULTIMATE. Earn gold and buy items in your castle. Skeleton camps in the "
		+ "jungle give gold and buffs; the Bone Lord on the island blesses your whole side. Break their towers and a gate, "
		+ "then defeat their King on his throne -- he's their heart, and he hits back.", 12, UI2.SOFT)
	UI2.text(body, "PICK YOUR HERO", 16, UI2.GOLD)
	var holder := CenterContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(holder)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	holder.add_child(_grid)
	_info = UI2.body(body, "", 12, Color.WHITE)
	_info.custom_minimum_size = Vector2(0, 54)
	_go = UI2.button(body, "BATTLE", "orange", func():
		app.profile.d.settings["moba_hero"] = hero
		app.profile.save()
		app.sfx("confirm")
		app.close_modal()
		app.start_moba(hero), "moba_battle", 22, 56.0, 16.0)
	UI2.sweep(_go)
	_render()

func _render() -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	for hid in Moba.HERO_ORDER:
		_grid.add_child(_card(str(hid)))
	var u: Dictionary = Moba.ULTS.get(hero, {})
	_info.text = "%s: %s\nULTIMATE (level %d) %s: %s" % [str(Moba.HEROES[hero].name), str(Moba.HERO_LINE.get(hero, "")), Moba.ULT_LEVEL,
		str(u.get("name", "")), str(u.get("text", ""))]

func _card(hid: String) -> Control:
	var on := hid == hero
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(CARD_W, CARD_H)
	b.set_meta("action_key", "moba_hero_" + hid)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.07, 0.03) if on else Color(0.05, 0.05, 0.08)
	sb.border_color = Color("#ffc23d") if on else (Color("#c47bff") if bool(Moba.HEROES[hid].up) else Color("#5a6470"))
	sb.set_border_width_all(3 if on else 2)
	sb.set_corner_radius_all(9)
	for st in ["normal", "hover", "pressed", "focus", "hover_pressed", "disabled"]:
		b.add_theme_stylebox_override(st, sb)
	var tex := TextureRect.new()
	var p := portrait(hid)
	tex.texture = load(p) if ResourceLoader.exists(p) else null
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tex.position = Vector2(4, 4)
	tex.size = Vector2(CARD_W - 8, CARD_H - 24)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(tex)
	var nm := str(Moba.HEROES[hid].name).to_upper()
	var nl := UI2.text(b, nm, 10 if nm.length() <= 9 else 9, Color.WHITE, Color("#120a20"), 4, false)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.position = Vector2(0, CARD_H - 21)
	nl.size = Vector2(CARD_W, 18)
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if on:
		var ck := UI2.text(b, "✔", 14, Color("#ffd65a"), Color("#201002"), 4, false)
		ck.position = Vector2(CARD_W - 18, 2)
		ck.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.pressed.connect(func():
		hero = hid
		app.sfx("equip")
		_render())
	return b
