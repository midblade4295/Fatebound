extends Control
# 0.31.155 5V5 (the test; scripts/siege/moba.gd): pick your hero, then BATTLE -- an offline 5v5 with bots on both sides
# (siege_app.start_moba). Twelve heroes: the six classes and their six upgrades. The last pick is kept on the phone
# (settings.moba_hero). 0.31.167: by role, each card's role on it, and the picked hero's role and kit (Q W E R) under
# the grid. 0.31.168 (Kevin: six new heroes, "Unlock with gold"): eighteen, as a table of League's six roles -- a column
# each, three heroes in it (the class, its upgrade, the new one); the new six cost gold (economy.gd HERO_PRICES, the
# profile's "heroes"): a locked card shows its price, and picking one turns BATTLE into UNLOCK.
# 0.31.185 (Kevin: "I want the same IAP system as league of legends"): this week's two free heroes play like your own
# (FREE on the card); UNLOCK opens a chooser over the window (League's "unlock with Blue Essence or RP"): the gold, the
# gems, a hero shard (at Eco.SHARD_UNLOCK of the gold) or a Hero Token; beside BATTLE, UNLOCK for a free one and MELT for
# a shard of a hero you own. Your Hero Tokens and shards beside PICK YOUR HERO (a ◆ on a card: a shard of him).
# 0.31.204 (Kevin: "put a hero tab in the market ... that's where they will purchase them"; asked about this window: "Send
# to Market"): heroes are bought in the Market's HEROES -- a locked hero's BATTLE is GET IN MARKET, and beside BATTLE a
# free one has MARKET; both open the Market's HEROES with his card lit (siege_app.open_market). The chooser is gone from
# here (screens.gd buy_hero has it); MELT stays (a shard of a hero you own, for gold).
const UI = preload("res://scripts/app/ui.gd")
const UI2 = preload("res://scripts/app/ui2.gd")
const SocialUI = preload("res://scripts/app/social_ui.gd")
const Moba = preload("res://scripts/siege/moba.gd")
const Kits = preload("res://scripts/siege/moba_kits.gd")      # 0.31.167: roles and kits
const Eco = preload("res://scripts/meta/economy.gd")
const Hud = preload("res://scripts/siege/siege_hud.gd")         # 0.31.171: the ability icons
const Showcase = preload("res://scripts/app/showcase.gd")      # 0.31.175: the picked hero in 3D
const ROLE_COL := {"tank":"#6fa8dc", "fighter":"#e06666", "assassin":"#a48ae0", "mage":"#f6a24b", "marksman":"#8fd16f",
	"support":"#ffd966"}
const COIN := "res://assets/ui/currency/coin.png"
const GEM := "res://assets/ui/currency/gem.png"
# 0.31.175 (Kevin: "Use eleven or meshy to make these menus better looking and more high quality"): ElevenLabs paintings
# (tools/build_menu_icons.py) -- the champions' hall the picked hero stands in, the six role badges over the columns,
# the padlock on a hero still to unlock
const HALL := "res://assets/ui/menu/hero_hall.webp"
const LOCK := "res://assets/ui/menu/lock.png"
const STAGE_H := 136.0

const CARD_W := 54.0
const CARD_H := 64.0          # (72 in portrait)
const LOOK := {"knight":"knight", "barbarian":"barbarian", "rogue":"rogue", "ranger":"ranger", "mage":"mage", "priest":"priest",
	"crusader":"crusader", "berserker":"berserker", "assassin":"assassin", "sniper":"sniper", "archmage":"archmage", "necromancer":"necromancer",
	"golem":"golem", "dragoon":"dragoon", "duelist":"duelist", "stormcaller":"stormcaller", "musketeer":"musketeer", "druid":"druid"}

var app
var hero := "knight"
var _grid: GridContainer
var _go: Button
var _side: Button               # 0.31.185: beside BATTLE -- UNLOCK (one free this week); 0.31.204: MARKET
var _melt: Button               # ... or MELT (a shard of one you own)
var _inv: Label                  # 0.31.185: the Hero Tokens and shards you hold
var _kit: VBoxContainer          # 0.31.171: the kit, a row per ability with its icon
var _show                        # 0.31.175: the stage -- the hero in 3D on the hall's dais, his name, role and price
var _stage_name: Label
var _stage_role: Label
var _stage_badge: TextureRect
var _stage_text: Label
var _stage_lock: HBoxContainer
var _stage_price: Label
var _stage_free: Label           # 0.31.185: FREE THIS WEEK (the rotation)
var _skin_btn: Button            # 0.31.186: the skin he wears -- tap for the next one you own (his own look among them)

static func role_badge(role: String) -> Texture2D:
	var p := "res://assets/ui/roles/%s.png" % role
	return load(p) if ResourceLoader.exists(p) else null

static func _tex(p: String) -> Texture2D:
	return load(p) if ResourceLoader.exists(p) else null

static func portrait(hid: String) -> String:
	return "res://assets/ui/skins/default_%s.png" % str(LOOK.get(hid, "knight"))

func _owns(hid: String) -> bool:
	return app.profile.owns_hero(hid)

func _plays(hid: String) -> bool:
	# yours, or free this week (0.31.185)
	return app.profile.can_play_hero(hid)

func open(a) -> void:
	app = a
	var saved := str(app.profile.d.settings.get("moba_hero", ""))
	hero = saved if Moba.HEROES.has(saved) and _plays(saved) else "knight"
	var w := SocialUI.window(self, "5V5", "swords", func():
		app.sfx("menuClose")
		app.close_modal(), 6.0 + float(app.safe_top), 8.0)       # (0.31.216: the whole screen, as Honor of Kings' hero select)
	var sheet: VBoxContainer = w.body
	# 0.31.216 (landscape, Honor of Kings' hero select): the picked hero on his stage and his kit on the left, the heroes to
	# pick from and BATTLE on the right (one column in portrait)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 12)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sheet.add_child(cols)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.85
	cols.add_child(left)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(body)
	# (0.31.155-0.31.163: "TEST MODE" -- 0.31.164, Kevin: "5v5 only": it's the game's match now, PLAY opens this)
	# (0.31.165: the Rift -- three towers a lane, a keep with a gate at each lane's end and two King towers inside;
	# 0.31.166: the Grave Wyrm)
	# (0.31.170: online -- the players in the match and bots in the seats nobody has taken)
	_build_stage(left)
	_kit = VBoxContainer.new()
	_kit.add_theme_constant_override("separation", 3)
	left.add_child(_kit)
	# (0.31.175: the match said shorter -- the stage took its room; 0.31.216 shorter still -- the kit's under the stage)
	UI2.body(left, "Five a side, bots in the empty seats. Break a lane, its gate and the two King towers, then defeat their King.",
		9, UI2.SOFT)
	var ph := UI.row(body, 8)
	UI2.text(ph, "PICK YOUR HERO", 16, UI2.GOLD)
	_inv = UI2.body(ph, "", 10, Color("#c9f7bd"))
	_inv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_inv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var holder := CenterContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(holder)
	_grid = GridContainer.new()
	_grid.columns = Kits.ROLE_ORDER.size()
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 5)
	holder.add_child(_grid)
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(gap)
	var foot := UI.row(body, 8)
	_go = UI2.button(foot, "BATTLE", "orange", _on_go, "moba_battle", 22, 52.0, 16.0)
	_go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI2.sweep(_go)
	_side = UI2.button(foot, "MARKET", "gold", _to_market, "moba_side_market", 16, 52.0, 16.0, "res://assets/ui/v2/icons/stall.png")
	_side.custom_minimum_size.x = 120
	_melt = UI2.button(foot, "MELT", "green", func(): _unlock_by("melt"), "moba_melt_shard", 15, 52.0, 16.0, COIN)
	_melt.custom_minimum_size.x = 132
	_render()

func _build_stage(body: VBoxContainer) -> void:
	# (0.31.216: on the left of the window, as tall as it can be)
	# 0.31.175: the picked hero, in 3D and idling, on the dais of the painted champions' hall; his name, role badge,
	# what the role does, and the price while he's locked, on the hall's dark right side
	var st := Panel.new()
	st.custom_minimum_size = Vector2(0, STAGE_H)
	st.size_flags_vertical = Control.SIZE_EXPAND_FILL
	st.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.03, 0.06)
	sb.set_corner_radius_all(12)
	st.add_theme_stylebox_override("panel", sb)
	st.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	body.add_child(st)
	var hall := TextureRect.new()
	hall.texture = _tex(HALL)
	hall.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hall.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	hall.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hall.mouse_filter = Control.MOUSE_FILTER_IGNORE
	st.add_child(hall)
	var rim := Panel.new()                 # (a thin gold rim over the painting's edge)
	var rs := StyleBoxFlat.new()
	rs.draw_center = false
	rs.border_color = Color("#c99a3a")
	rs.set_border_width_all(2)
	rs.set_corner_radius_all(12)
	rim.add_theme_stylebox_override("panel", rs)
	rim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_show = Showcase.new()
	_show.plinth = false
	_show.mouse_filter = Control.MOUSE_FILTER_IGNORE
	st.add_child(_show)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 3)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	st.add_child(info)
	_stage_name = UI2.text(info, "", 24, Color.WHITE, Color("#120a20"))
	var rr := HBoxContainer.new()
	rr.add_theme_constant_override("separation", 5)
	rr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(rr)
	_stage_badge = TextureRect.new()
	_stage_badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_stage_badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_stage_badge.custom_minimum_size = Vector2(26, 26)
	_stage_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rr.add_child(_stage_badge)
	_stage_role = UI2.text(rr, "", 15, Color.WHITE, Color("#120a20"))
	_stage_text = UI2.body(info, "", 10, Color("#e8dcc8"))
	_stage_text.custom_minimum_size = Vector2(150, 0)
	_stage_lock = HBoxContainer.new()
	_stage_lock.add_theme_constant_override("separation", 4)
	_stage_lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(_stage_lock)
	for t in [LOCK, COIN]:
		var ic := TextureRect.new()
		ic.texture = _tex(t)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.custom_minimum_size = Vector2(20, 20)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stage_lock.add_child(ic)
		if t == LOCK:
			_stage_lock.move_child(ic, 0)
	_stage_price = UI2.text(_stage_lock, "", 15, Color("#ffd65a"), Color("#201002"))
	_stage_lock.move_child(_stage_price, 2)
	_stage_free = UI2.text(info, "FREE THIS WEEK", 13, Color("#9dff8a"), Color("#0a2006"))
	st.add_child(rim)
	_skin_btn = UI2.button(st, "", "blue", _next_skin, "moba_skin", 10, 26.0, 9.0)
	st.resized.connect(func():
		# the hall's dais is at ~23 % across, its top ~76 % down the painting (cover-scaled to the stage's width): the
		# hero's feet (78 % down his frame) on it
		var w := st.size.x
		var hh := w * 0.5
		var dais := Vector2(w * 0.235, hh * 0.755 - (hh - st.size.y) * 0.5)
		var fh := 176.0
		_show.size = Vector2(150, fh)
		_show.position = Vector2(dais.x - 75.0, dais.y - fh * 0.78)
		info.position = Vector2(w * 0.47, 14)
		_stage_text.custom_minimum_size.x = w * 0.53 - 14
		info.size = Vector2(w * 0.53 - 10, 0)
		_skin_btn.size = Vector2(minf(150.0, w * 0.42), 26)
		_skin_btn.position = Vector2(8, st.size.y - 32))

func _render_stage() -> void:
	var role := Kits.role_of(hero)
	_stage_name.text = str(Moba.HEROES[hero].name).to_upper()
	_stage_role.text = str(Kits.ROLE_NAMES.get(role, ""))
	_stage_role.add_theme_color_override("font_color", Color(str(ROLE_COL.get(role, "#ffffff"))).lightened(0.25))
	_stage_badge.texture = role_badge(role)
	_stage_text.text = str(Kits.ROLE_TEXT.get(role, ""))
	var owned := _owns(hero)
	_stage_free.visible = not owned and _plays(hero)       # (in the price's place: UNLOCK beside BATTLE has the prices)
	_stage_lock.visible = not owned and not _stage_free.visible
	_stage_price.text = UI.grouped(int(app.profile.hero_price(hero).get("gold", 0)))
	if _show != null:
		_show.show_look(hero, app.profile.look_for(hero))     # 0.31.186: in the outfit he wears (0.31.188: its weapon too)
		_show.modulate = Color.WHITE if _plays(hero) else Color(0.62, 0.62, 0.7)
	# 0.31.186: SKIN -- shown when you own one of his
	var mine: Array = Eco.skins_of(hero).filter(func(id): return app.profile.owns_skin(str(id)))
	_skin_btn.visible = not mine.is_empty() and _owns(hero)
	var w2: String = app.profile.worn_skin(hero)
	_skin_btn.text = "OUTFIT: " + (str(Eco.SKINS[w2].set).to_upper() if w2 != "" else "DEFAULT") + "  ▸"

func _on_go() -> void:
	if not _plays(hero):
		# 0.31.168: UNLOCK (0.31.185: the chooser -- gold, gems, a shard or a Hero Token). 0.31.204: the Market sells him
		_to_market()
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
	var lines := kit_lines(hero)
	_inv.text = inventory_text(app.profile)
	_inv.visible = _inv.text != ""
	_render_stage()
	for c in _kit.get_children():
		_kit.remove_child(c)
		c.queue_free()
	for i in 4:
		_kit.add_child(_kit_row(hero, ["q", "w", "e", "r"][i], str(lines[i + 1])))
	_go.disabled = false
	_go.text = "BATTLE" if _plays(hero) else "GET IN MARKET"
	# 0.31.185: beside it, UNLOCK for one free this week (0.31.204: MARKET), MELT for a shard of one you own
	var p = app.profile
	_side.visible = _plays(hero) and not _owns(hero)
	_melt.visible = _owns(hero) and p.shards_of(hero) > 0
	_melt.text = "MELT +%s" % UI.grouped(Eco.shard_melt_gold(hero, p.now()))

func _next_skin() -> void:
	# 0.31.186: his own look, then each skin of his you own, round and round
	var p = app.profile
	var cycle: Array = [""] + Eco.skins_of(hero).filter(func(id): return p.owns_skin(str(id)))
	var i := cycle.find(p.worn_skin(hero))
	p.wear_skin(hero, str(cycle[(i + 1) % cycle.size()]))
	app.sfx("equip")
	_render_stage()

static func inventory_text(p) -> String:
	# "HERO TOKEN x1  ·  ◆ SHARDS 2" (which heroes: the ◆ on their cards; this week's free ones: FREE on theirs)
	var bits := []
	if int(p.d.get("tokens", 0)) > 0:
		bits.append("HERO TOKEN x%d" % int(p.d.tokens))
	var n := (p.d.get("shards", []) as Array).size()
	if n > 0:
		bits.append("◆ SHARD%s %d" % ["S" if n > 1 else "", n])
	return "  ·  ".join(bits)

func _to_market() -> void:
	# 0.31.204: the Market's HEROES, his card lit -- heroes are bought there
	app.sfx("tab")
	app.open_market("heroes", hero)

func _unlock_by(how: String) -> void:
	# (0.31.204: only MELT is left here -- a shard of a hero you own, for gold)
	var p = app.profile
	var r: Dictionary = p.melt_shard(hero) if how == "melt" else {"ok": false}
	if bool(r.get("ok", false)):
		app.sfx("purchase")
		app.toast("Shard melted: +%s gold" % UI.grouped(int(r.get("gold", 0))), UI2.GOLD)
		app.refresh_top()
	else:
		app.sfx("error")
		app.toast(str(r.get("error", "Can't unlock")), Color("#ff8a7a"))
	_render()

static func kit_text(hid: String) -> String:
	return "\n".join(kit_lines(hid))

static func kit_lines(hid: String) -> Array:
	# the hero's role, then his kit: Q, W (level 2), E (level 3), R (level 6)
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
	return lines

func _kit_row(hid: String, slot: String, line: String) -> Control:
	# 0.31.171: the ability's icon (the HUD's button) beside its line
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := TextureRect.new()
	ic.texture = Hud.ability_icon(hid, slot)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.custom_minimum_size = Vector2(30, 30)
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(ic)
	var l := UI2.body(row, line, 10, Color.WHITE)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size = Vector2(10, 0)
	return row

func _role_head(role: String) -> Control:
	# 0.31.175: the role's painted badge and its name (was a coloured strip with the name in 5-8 px)
	var c := Control.new()
	c.custom_minimum_size = Vector2(CARD_W, 33)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var b := TextureRect.new()
	b.texture = role_badge(role)
	b.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	b.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	b.position = Vector2((CARD_W - 22.0) * 0.5, 0)
	b.size = Vector2(22, 22)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(b)
	var nm := str(Kits.ROLE_NAMES.get(role, ""))
	var fs := 9
	while fs > 6 and UI2.LG.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > CARD_W - 2.0:
		fs -= 1
	var rl := UI2.text(c, nm, fs, Color(str(ROLE_COL.get(role, "#ffffff"))).lightened(0.2), Color("#120a20"), 2, false)
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rl.position = Vector2(-2, 21)
	rl.size = Vector2(CARD_W + 4, 12)
	return c

static var _glows: Dictionary = {}

static func _glow(role: String) -> Texture2D:
	# a soft light behind a card's portrait in its role's colour
	if not _glows.has(role):
		var g := Gradient.new()
		var c := Color(str(ROLE_COL.get(role, "#ffffff")))
		g.set_color(0, Color(c, 0.75))
		g.set_color(1, Color(c.darkened(0.6), 0.0))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.42)
		gt.fill_to = Vector2(0.5, 1.05)
		gt.width = 64
		gt.height = 96
		_glows[role] = gt
	return _glows[role]

func _card(hid: String) -> Control:
	# 0.31.175: on a dark ground in its role's colour with a glow behind the portrait; a hero to unlock dimmed, with
	# the padlock and his price in gold; the picked one in a gold frame with a tick
	var on := hid == hero
	var owned := _plays(hid)             # (0.31.185: a free one this week shows as playable, FREE on it)
	var free := owned and not _owns(hid)
	var role := Kits.role_of(hid)
	var rim := Color(str(ROLE_COL.get(role, "#5a6470")))
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(CARD_W, CARD_H)
	b.set_meta("action_key", "moba_hero_" + hid)
	var sb := StyleBoxFlat.new()
	sb.bg_color = rim.darkened(0.82) if owned else Color(0.06, 0.06, 0.08)
	sb.border_color = Color("#ffc23d") if on else (rim.darkened(0.1) if owned else Color("#3a3f48"))
	sb.set_border_width_all(3 if on else 2)
	sb.set_corner_radius_all(8)
	if on:
		sb.shadow_color = Color(1.0, 0.78, 0.25, 0.55)
		sb.shadow_size = 5
	for st in ["normal", "hover", "pressed", "focus", "hover_pressed", "disabled"]:
		b.add_theme_stylebox_override(st, sb)
	var glow := TextureRect.new()
	glow.texture = _glow(role)
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.position = Vector2(3, 3)
	glow.size = Vector2(CARD_W - 6, CARD_H - 6)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.modulate = Color(1, 1, 1, 0.9 if owned else 0.25)
	b.add_child(glow)
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
	# the name on a dark band across the card's foot
	var band := ColorRect.new()
	band.color = Color(0.03, 0.02, 0.05, 0.82)
	band.position = Vector2(2, CARD_H - 17)
	band.size = Vector2(CARD_W - 4, 15)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(band)
	var nm := str(Moba.HEROES[hid].name).to_upper()
	var nl := UI2.text(b, nm, 8 if nm.length() <= 6 else (7 if nm.length() <= 8 else 6), Color.WHITE, Color("#120a20"), 3, false)
	nl.clip_text = true
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.position = Vector2(0, CARD_H - 16)
	nl.size = Vector2(CARD_W, 14)
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not owned:
		var lk := TextureRect.new()
		lk.texture = _tex(LOCK)
		lk.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lk.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		lk.position = Vector2(CARD_W * 0.5 - 11, CARD_H * 0.2)
		lk.size = Vector2(22, 22)
		lk.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(lk)
		# the price under the padlock: a coin and the gold
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 1)
		chip.alignment = BoxContainer.ALIGNMENT_CENTER
		chip.position = Vector2(0, CARD_H * 0.52)
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
		var pl := UI2.text(chip, str(int(app.profile.hero_price(hid).get("gold", 0))), 10, Color("#ffd65a"), Color("#201002"), 3, false)
		pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	elif free:
		var fr := UI2.text(b, "FREE", 8, Color("#9dff8a"), Color("#0a2006"), 3, false)     # 0.31.185: this week's rotation
		fr.position = Vector2(3, 1)
		fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	elif Eco.HERO_PRICES.has(hid):
		var nw := UI2.text(b, "★", 10, Color("#ffd65a"), Color("#201002"), 3, false)      # (one you bought)
		nw.position = Vector2(4, 1)
		nw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if app.profile.shards_of(hid) > 0:                   # 0.31.185: a shard of him held
		var sd := UI2.text(b, "◆", 10, Color("#9dff8a"), Color("#0a2006"), 3, false)
		sd.position = Vector2(CARD_W - 13, CARD_H - 31)
		sd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if on:
		var ck := UI2.text(b, "✔", 12, Color("#ffd65a"), Color("#201002"), 4, false)
		ck.position = Vector2(CARD_W - 15, 1)
		ck.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.pressed.connect(func():
		hero = hid
		app.sfx("equip")
		_render())
	return b
