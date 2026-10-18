extends Control
# 0.31.155 5V5 (the test; scripts/siege/moba.gd): pick your hero, then BATTLE -- an offline 5v5 with bots on both sides
# (siege_app.start_moba). Twelve heroes: the six classes and their six upgrades. The last pick is kept on the phone
# (settings.moba_hero). 0.31.167: by role, each card's role on it, and the picked hero's role and kit (Q W E R) under
# the grid. 0.31.168 (Kevin: six new heroes, "Unlock with gold"): eighteen, as a table of League's six roles -- a column
# each, three heroes in it (the class, its upgrade, the new one); the new six cost gold (economy.gd HERO_PRICES, the
# profile's "heroes"): a locked card shows its price, and picking one turns BATTLE into UNLOCK.
const UI = preload("res://scripts/app/ui.gd")
const UI2 = preload("res://scripts/app/ui2.gd")
const SocialUI = preload("res://scripts/app/social_ui.gd")
const Moba = preload("res://scripts/siege/moba.gd")
const Kits = preload("res://scripts/siege/moba_kits.gd")      # 0.31.167: roles and kits
const Eco = preload("res://scripts/meta/economy.gd")
const ROLE_COL := {"tank":"#6fa8dc", "fighter":"#e06666", "assassin":"#a48ae0", "mage":"#f6a24b", "marksman":"#8fd16f",
	"support":"#ffd966"}
const COIN := "res://assets/ui/currency/coin.png"

const CARD_W := 54.0
const CARD_H := 78.0
const LOOK := {"knight":"knight", "barbarian":"barbarian", "rogue":"rogue", "ranger":"ranger", "mage":"mage", "priest":"priest",
	"crusader":"crusader", "berserker":"berserker", "assassin":"assassin", "sniper":"sniper", "archmage":"archmage", "necromancer":"necromancer",
	"golem":"golem", "dragoon":"dragoon", "duelist":"duelist", "stormcaller":"stormcaller", "musketeer":"musketeer", "druid":"druid"}

var app
var hero := "knight"
var _grid: GridContainer
var _info: Label
var _go: Button

static func portrait(hid: String) -> String:
	return "res://assets/ui/skins/default_%s.png" % str(LOOK.get(hid, "knight"))

func _owns(hid: String) -> bool:
	return app.profile.owns_hero(hid)

func open(a) -> void:
	app = a
	var saved := str(app.profile.d.settings.get("moba_hero", ""))
	hero = saved if Moba.HEROES.has(saved) and _owns(saved) else "knight"
	var w := SocialUI.window(self, "5V5", "swords", func():
		app.sfx("menuClose")
		app.close_modal(), 56.0 + float(app.safe_top), 24.0)
	var body: VBoxContainer = w.body
	# (0.31.155-0.31.163: "TEST MODE" -- 0.31.164, Kevin: "5v5 only": it's the game's match now, PLAY opens this)
	# (0.31.165: the Rift -- three towers a lane, a keep with a gate at each lane's end and two King towers inside;
	# 0.31.166: the Grave Wyrm)
	# (0.31.170: online -- the players in the match and bots in the seats nobody has taken)
	UI2.body(body, "Five heroes a side: you, other players and bots in the seats nobody has taken. Minions march down three lanes past three towers each to a "
		+ "gate of the keep. Level up to 10 near the fighting -- W at level 2, E at 3, your ULTIMATE at 6 -- earn gold and "
		+ "buy items in your keep. The jungle's camps give gold and buffs; the Bone Lord blesses your side, every Grave "
		+ "Wyrm slain toughens it. Break a lane, its gate and the two King towers, then defeat their King on his throne.", 11, UI2.SOFT)
	UI2.text(body, "PICK YOUR HERO", 16, UI2.GOLD)
	var holder := CenterContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(holder)
	_grid = GridContainer.new()
	_grid.columns = Kits.ROLE_ORDER.size()
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 5)
	holder.add_child(_grid)
	_info = UI2.body(body, "", 11, Color.WHITE)
	_info.custom_minimum_size = Vector2(0, 120)
	_info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_info.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_go = UI2.button(body, "BATTLE", "orange", _on_go, "moba_battle", 22, 56.0, 16.0)
	UI2.sweep(_go)
	_render()

func _on_go() -> void:
	if not _owns(hero):
		# 0.31.168: UNLOCK -- the gold, then the hero is yours (and picked)
		var r: Dictionary = app.profile.buy_hero(hero)
		if bool(r.get("ok", false)):
			app.sfx("purchase")
			app.toast("%s unlocked!" % str(Moba.HEROES[hero].name), UI2.GOLD)
		else:
			app.sfx("error")
			app.toast(str(r.get("error", "Can't unlock")), Color("#ff8a7a"))
		_render()
		return
	app.profile.d.settings["moba_hero"] = hero
	app.profile.save()
	app.sfx("confirm")
	app.close_modal()
	app.start_moba(hero)

static func role_table() -> Array:
	# the grid's cells in reading order: a header per role, then the heroes row by row (each role's in HERO_ORDER)
	var cols := []
	for role in Kits.ROLE_ORDER:
		cols.append(Moba.HERO_ORDER.filter(func(h): return Kits.role_of(str(h)) == role))
	var out := []
	for role in Kits.ROLE_ORDER:
		out.append("#" + role)
	var rows := 0
	for c in cols:
		rows = maxi(rows, (c as Array).size())
	for r in rows:
		for c in cols:
			out.append(str((c as Array)[r]) if r < (c as Array).size() else "")
	return out

func _render() -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	# 0.31.168: a column per role (TANK, FIGHTER, ASSASSIN, MAGE, MARKSMAN, SUPPORT) under its name
	for cell in role_table():
		var id := str(cell)
		if id.begins_with("#"):
			_grid.add_child(_role_head(id.substr(1)))
		elif id == "":
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(CARD_W, CARD_H)
			_grid.add_child(gap)
		else:
			_grid.add_child(_card(id))
	var txt := kit_text(hero)
	if not _owns(hero):
		txt = "LOCKED -- %d gold to unlock (you have %d).\n" % [int(Eco.HERO_PRICES.get(hero, 0)), int(app.profile.d.gold)] + txt
	_info.text = txt
	if _owns(hero):
		_go.text = "BATTLE"
		_go.disabled = false
	else:
		var price := int(Eco.HERO_PRICES.get(hero, 0))
		_go.text = "UNLOCK  %d GOLD" % price
		_go.disabled = int(app.profile.d.gold) < price

static func kit_text(hid: String) -> String:
	# the hero's role and his kit: Q, W (level 2), E (level 3), R (level 6)
	var role := Kits.role_of(hid)
	var lines := ["%s · %s -- %s" % [str(Moba.HEROES[hid].name).to_upper(), str(Kits.ROLE_NAMES.get(role, "")),
		str(Kits.ROLE_TEXT.get(role, ""))]]
	var q := Kits.kit(hid, "q")
	lines.append("Q %s: %s" % [str(q.get("name", "")), str(q.get("text", Moba.HERO_LINE.get(hid, "")))])
	for slot in ["w", "e"]:
		var k := Kits.kit(hid, slot)
		lines.append("%s %s (lv %d): %s" % [slot.to_upper(), str(k.get("name", "")), int(Kits.UNLOCK[slot]), str(k.get("text", ""))])
	var u: Dictionary = Moba.ULTS.get(hid, {})
	lines.append("R %s (lv %d): %s" % [str(u.get("name", "")), Moba.ULT_LEVEL, str(u.get("text", ""))])
	return "\n".join(lines)

func _role_head(role: String) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(CARD_W, 15)
	var strip := ColorRect.new()
	strip.color = Color(Color(str(ROLE_COL.get(role, "#ffffff"))), 0.9)
	strip.position = Vector2(0, 1)
	strip.size = Vector2(CARD_W, 13)
	c.add_child(strip)
	var rl := UI2.text(c, str(Kits.ROLE_NAMES.get(role, "")), {"marksman":5, "assassin":6, "support":6, "fighter":6}.get(role, 8), Color("#120a20"),
		Color(0, 0, 0, 0), 0, false)
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rl.position = Vector2(0, 2)
	rl.size = Vector2(CARD_W, 13)
	return c

func _card(hid: String) -> Control:
	var on := hid == hero
	var owned := _owns(hid)
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(CARD_W, CARD_H)
	b.set_meta("action_key", "moba_hero_" + hid)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.07, 0.03) if on else Color(0.05, 0.05, 0.08)
	var rim := Color(str(ROLE_COL.get(Kits.role_of(hid), "#5a6470")))
	sb.border_color = Color("#ffc23d") if on else (rim.darkened(0.15) if owned else Color("#3a3f48"))
	sb.set_border_width_all(3 if on else 2)
	sb.set_corner_radius_all(8)
	for st in ["normal", "hover", "pressed", "focus", "hover_pressed", "disabled"]:
		b.add_theme_stylebox_override(st, sb)
	var tex := TextureRect.new()
	var p := portrait(hid)
	tex.texture = load(p) if ResourceLoader.exists(p) else null
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tex.position = Vector2(3, 3)
	tex.size = Vector2(CARD_W - 6, CARD_H - 19)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not owned:
		tex.modulate = Color(0.45, 0.45, 0.5)
	b.add_child(tex)
	var nm := str(Moba.HEROES[hid].name).to_upper()
	var nl := UI2.text(b, nm, 8 if nm.length() <= 6 else (7 if nm.length() <= 8 else 6), Color.WHITE, Color("#120a20"), 3, false)
	nl.clip_text = true
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.position = Vector2(0, CARD_H - 16)
	nl.size = Vector2(CARD_W, 14)
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not owned:
		# the price over the portrait: a coin and the gold
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 1)
		chip.alignment = BoxContainer.ALIGNMENT_CENTER
		chip.position = Vector2(0, CARD_H * 0.36)
		chip.size = Vector2(CARD_W, 16)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(chip)
		var ci := TextureRect.new()
		ci.texture = load(COIN) if ResourceLoader.exists(COIN) else null
		ci.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ci.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ci.custom_minimum_size = Vector2(13, 13)
		ci.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(ci)
		var pl := UI2.text(chip, str(int(Eco.HERO_PRICES.get(hid, 0))), 10, Color("#ffd65a"), Color("#201002"), 3, false)
		pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	elif Eco.HERO_PRICES.has(hid):
		var nw := UI2.text(b, "★", 10, Color("#ffd65a"), Color("#201002"), 3, false)      # (one you bought)
		nw.position = Vector2(4, 1)
		nw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if on:
		var ck := UI2.text(b, "✔", 12, Color("#ffd65a"), Color("#201002"), 4, false)
		ck.position = Vector2(CARD_W - 15, 1)
		ck.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.pressed.connect(func():
		hero = hid
		app.sfx("equip")
		_render())
	return b
