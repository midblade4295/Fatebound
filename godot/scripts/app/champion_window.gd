extends Control
# 0.31.187 (Kevin: "When clicking on a champion, make a customized window for them that pops up that is themed around them
# and player can also zoom in and rotate them. Use art and effects that match each characters lore. Also put every skin
# that character has into that page that allows players to purchase or preview what it looks like"): a champion's own
# window, from the Locker's CHAMPIONS (screens.gd locker) and the Armory's nameplate.
#   * his place painted behind him (Champions.art -- the Knight's castle bridge at dawn, the Necromancer's graveyard...),
#     slowly breathing, his colour over it, and his effects in it (champion_fx.gd: embers, leaves, rain and lightning...);
#   * he stands in it in 3D, in the skin he wears: drag to turn him, pinch (or + / -) to zoom;
#   * his name, title, class and role; whether he's yours, free this week or at his launch price -- UNLOCK (the same
#     choices as the 5v5 window: gold, gems, a shard, a Hero Token), or PLAY as him;
#   * SKINS: his own look and every skin of his -- tap one to see him in it; WEAR one you own, BUY one you don't (gems,
#     asked first; a skin of a hero still locked brings him, League's way);
#   * his story and his line, and his kit (Q W E R) with its icons.
const UI = preload("res://scripts/app/ui.gd")
const UI2 = preload("res://scripts/app/ui2.gd")
const Eco = preload("res://scripts/meta/economy.gd")
const Champions = preload("res://scripts/meta/champions.gd")
const Moba = preload("res://scripts/siege/moba.gd")
const Kits = preload("res://scripts/siege/moba_kits.gd")
const Hud = preload("res://scripts/siege/siege_hud.gd")
const Showcase = preload("res://scripts/app/showcase.gd")
const Fx = preload("res://scripts/app/champion_fx.gd")
const MobaPanel = preload("res://scripts/app/moba_panel.gd")
const COIN := "res://assets/ui/currency/coin.png"
const GEM := "res://assets/ui/currency/gem.png"
const STAGE_TOP := 0.13            # the 3D stage, as fractions of the window's height (his feet land on the painting's
const STAGE_BOTTOM := 0.6          # open ground, about half way down)

var app
var hero := "knight"
var preview := ""                  # the skin he's shown in ("" his own look) -- a skin you don't own is only a preview
var _show
var _bg: TextureRect
var _sheet: VBoxContainer          # the panel's content (rebuilt by _render)
var _scroll: ScrollContainer
var _status: HBoxContainer         # the chips over the stage
var _preview_chip: Control
var overlay: Control               # the unlock chooser or a purchase question, over the window
var fx: Array = []                 # the effect layers (champion_fx.gd)

func open(a, hid: String, show_skin := "__worn") -> void:
	app = a
	hero = hid if Moba.HEROES.has(hid) else "knight"
	preview = app.profile.worn_skin(hero) if show_skin == "__worn" else show_skin
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var ch: Dictionary = Champions.of(hero)
	var acc: Color = Champions.accent(hero)
	app.sfx("menuOpen")
	# ---- his place: the painting (cover), breathing slowly
	var back := ColorRect.new()
	back.color = Color(0.02, 0.02, 0.04)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	_bg = TextureRect.new()
	var art := Champions.art(hero)
	_bg.texture = load(art) if ResourceLoader.exists(art) else null
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	resized.connect(func(): _bg.pivot_offset = _bg.size * Vector2(0.5, 0.45))
	UI2.when_ready(_bg, func():
		var tw := _bg.create_tween().set_loops()
		tw.tween_property(_bg, "scale", Vector2.ONE * 1.05, 9.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(_bg, "scale", Vector2.ONE, 9.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT))
	# his colour: a dark band at the top for the name, the bottom into the panel, his colour at the edges
	add_child(_shade([[0.0, Color(0, 0, 0, 0.72)], [0.16, Color(0, 0, 0, 0.0)], [0.5, Color(0, 0, 0, 0.0)],
		[0.62, Color(acc.darkened(0.85), 0.88)], [1.0, Color(0.01, 0.01, 0.03, 0.97)]], true))
	add_child(_shade([[0.0, Color(acc, 0.22)], [0.18, Color(acc, 0.0)], [0.82, Color(acc, 0.0)], [1.0, Color(acc, 0.22)]], false))
	# ---- his effects behind him
	fx = ch.get("fx", [])
	for add in [true, false]:
		_fx_layer(false, add)
	# ---- he stands there in 3D
	var stage := Control.new()
	stage.anchor_left = 0.0
	stage.anchor_right = 1.0
	stage.anchor_top = STAGE_TOP
	stage.anchor_bottom = STAGE_BOTTOM
	stage.clip_contents = true
	add_child(stage)
	_show = Showcase.new()
	_show.plinth = false
	_show.interactive = true
	_show.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(_show)
	_show_look()
	# ---- his effects in front of him (falling leaves, rain, blown embers)
	for add in [true, false]:
		_fx_layer(true, add)
	var zs: Control = Control.new()                  # (the zoom buttons and hint over the stage, above the front effects)
	zs.anchor_right = 1.0
	zs.anchor_top = STAGE_TOP
	zs.anchor_bottom = STAGE_BOTTOM
	zs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(zs)
	zoom_controls(zs, _show)
	_status = HBoxContainer.new()
	_status.add_theme_constant_override("separation", 6)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.position = Vector2(12, 8)
	zs.add_child(_status)
	# ---- the name
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 0)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.anchor_right = 1.0
	head.offset_left = 14
	head.offset_right = -64
	head.offset_top = 10.0 + float(app.safe_top)
	add_child(head)
	var rr := HBoxContainer.new()
	rr.add_theme_constant_override("separation", 6)
	rr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(rr)
	var role := Kits.role_of(hero)
	var badge := TextureRect.new()
	badge.texture = MobaPanel.role_badge(role)
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.custom_minimum_size = Vector2(22, 22)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rr.add_child(badge)
	var cl := UI2.text(rr, "%s  ·  %s" % [str(Moba.HEROES[hero].name).to_upper(), str(Kits.ROLE_NAMES.get(role, ""))], 13,
		Color(str(MobaPanel.ROLE_COL.get(role, "#ffffff"))).lightened(0.3), Color(0, 0, 0, 0.9), 4)
	cl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var nm := UI2.text(head, str(ch.get("name", hero)).to_upper(), 27, Color.WHITE, acc.darkened(0.7), 7)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.set_meta("champ_name", true)
	var ep := UI.label(head, str(ch.get("title", "")), 15, acc.lightened(0.55), UI.LORE_FONT, true)
	ep.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	ep.add_theme_constant_override("outline_size", 5)
	var x := UI2.button(self, "✕", "ghost", close, "champ_close", 20, 44.0, 14.0)
	x.anchor_left = 1.0
	x.anchor_right = 1.0
	x.offset_left = -56
	x.offset_right = -10
	x.offset_top = 10.0 + float(app.safe_top)
	x.offset_bottom = 54.0 + float(app.safe_top)
	# ---- the panel: status and UNLOCK / PLAY, SKINS, the story, the kit
	var panel := Control.new()
	panel.anchor_right = 1.0
	panel.anchor_top = STAGE_BOTTOM
	panel.anchor_bottom = 1.0
	panel.offset_left = 8
	panel.offset_right = -8
	panel.offset_top = -4
	panel.offset_bottom = -8
	add_child(panel)
	UI2.plate(panel, "glass", 20.0, "gold", {"fill_top": Color(acc.darkened(0.82), 0.82), "fill_bottom": Color(0.02, 0.02, 0.05, 0.92),
		"outline": 2.0, "outline_color": Color(acc, 0.75)})
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.offset_left = 12
	_scroll.offset_right = -12
	_scroll.offset_top = 10
	_scroll.offset_bottom = -8
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(_scroll)
	_sheet = VBoxContainer.new()
	_sheet.add_theme_constant_override("separation", 8)
	_sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_sheet)
	_render()

func close() -> void:
	app.sfx("menuClose")
	app.close_modal()

func refresh() -> void:
	# (app.rebuild calls this: the profile changed under the window)
	if _sheet != null:
		_render()

func _shade(stops: Array, vertical: bool) -> TextureRect:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(stops.map(func(s): return float(s[0])))
	g.colors = PackedColorArray(stops.map(func(s): return s[1]))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 4 if vertical else 64
	gt.height = 64 if vertical else 4
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1) if vertical else Vector2(1, 0)
	var t := TextureRect.new()
	t.texture = gt
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

func _fx_layer(in_front: bool, add: bool) -> void:
	if not fx.any(func(l): return Fx.wants(l, in_front, add)):
		return
	var f := Fx.new()
	f.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	f.name = "ChampionFx_%s_%s" % ["front" if in_front else "back", "light" if add else "laid"]
	add_child(f)
	# (round him: the stage's middle, about his chest -- his feet are 78 % down the stage)
	f.setup(fx, in_front, add, Vector2(0.5, STAGE_TOP + (STAGE_BOTTOM - STAGE_TOP) * 0.6))

func _look() -> Dictionary:
	# the outfit shown -- its body and its own weapon (0.31.188); {} his own look
	return {"skin": preview} if preview != "" else {}

func _show_look() -> void:
	if _show != null:
		_show.show_look(hero, _look())

static func zoom_controls(stage: Control, sh) -> void:
	# + / - on the right of the stage, and the hint under him (the Locker's own, Screens.zoom_controls, keys champ_*)
	var zc := VBoxContainer.new()
	zc.add_theme_constant_override("separation", 10)
	zc.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	zc.offset_left = -56
	zc.offset_right = -10
	zc.offset_top = -50
	zc.offset_bottom = 50
	stage.add_child(zc)
	for zb in [["+", 1.3, "champ_zoom_in"], ["−", 1.0 / 1.3, "champ_zoom_out"]]:
		var zf: float = zb[1]
		var b := UI2.button(zc, str(zb[0]), "blue", func(): sh.zoom_by(zf), str(zb[2]), 24, 44.0, 22.0)
		b.custom_minimum_size = Vector2(44, 44)
		b.add_theme_font_override("font", UI.HEAVY_FONT)
	var hint := UI2.chip(stage, "DRAG TO TURN  ·  PINCH TO ZOOM", Color(0.02, 0.03, 0.1, 0.7), Color(1, 1, 1, 0.85), Color(UI2.GOLD, 0.45))
	hint.anchor_left = 0.5
	hint.anchor_right = 0.5
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = -100
	hint.offset_right = 100
	hint.offset_top = -26
	hint.offset_bottom = -8
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE

# ---------------- the panel ----------------
func _render() -> void:
	var p = app.profile
	var acc: Color = Champions.accent(hero)
	var ch: Dictionary = Champions.of(hero)
	var keep := _scroll.scroll_vertical
	for c in _sheet.get_children():
		_sheet.remove_child(c)
		c.queue_free()
	for c in _status.get_children():
		_status.remove_child(c)
		c.queue_free()
	var owned: bool = p.owns_hero(hero)
	var plays: bool = p.can_play_hero(hero)
	var pr: Dictionary = p.hero_price(hero)
	# ---- the chips over the stage
	if not owned and plays:
		UI2.chip(_status, "FREE THIS WEEK", Color("#2f8a3e"), Color.WHITE, Color("#0a2006"))
	if Eco.launching(hero, p.now()):
		var left := int(ceil(float(int(Eco.HERO_LAUNCH[hero]) + Eco.LAUNCH_DAYS * 86400 - p.now()) / 86400.0))
		UI2.chip(_status, "NEW  ·  %d DAY%s AT LAUNCH PRICE" % [left, "" if left == 1 else "S"], Color("#d9682a"), Color.WHITE, Color("#3a1402"))
	if preview != "" and not p.owns_skin(preview):
		UI2.chip(_status, "PREVIEW", Color(acc.darkened(0.45), 0.9), Color.WHITE, Color(0, 0, 0, 0.8))
	# ---- yours? UNLOCK or PLAY
	var top := UI.row(_sheet, 8)
	if owned:
		var yl := UI2.text(top, "YOURS", 18, Color("#9dff8a"), Color("#0a2006"), 5)
		yl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	elif not pr.is_empty():
		var pv := VBoxContainer.new()
		pv.add_theme_constant_override("separation", 0)
		pv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(pv)
		var pl := UI.row(pv, 4)
		UI2.img(pl, COIN, 20.0)
		UI2.text(pl, UI.grouped(int(pr.gold)), 17, UI2.GOLD, Color("#201002"), 4)
		UI2.body(pl, "or", 11, UI2.SOFT, false)
		UI2.img(pl, GEM, 20.0)
		UI2.text(pl, UI.grouped(int(pr.gems)), 17, Color("#cfe9ff"), Color("#0a1238"), 4)
		if p.shards_of(hero) > 0:
			UI2.body(pv, "◆ With the shard you hold: %s gold" % UI.grouped(Eco.shard_unlock_gold(hero, p.now())), 10, Color("#c9f7bd"), false)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	if not owned and not pr.is_empty():
		var ub := UI2.button(top, "UNLOCK", "gold", open_chooser, "champ_unlock", 17, 46.0, 14.0)
		ub.custom_minimum_size.x = 120
		UI2.sweep(ub)
	if plays:
		var pb := UI2.button(top, "PLAY", "orange", _play, "champ_play", 17, 46.0, 14.0)
		pb.custom_minimum_size.x = 100
	# ---- SKINS
	var ids: Array = [""] + Eco.skins_of(hero)
	var mine := 1 + Eco.skins_of(hero).filter(func(id): return p.owns_skin(str(id))).size()
	_head(_sheet, "OUTFITS", "%d of %d yours  ·  tap one to try it on" % [mine, ids.size()], acc)      # (0.31.188: whole outfits, weapon and all)
	var hs := ScrollContainer.new()
	hs.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hs.custom_minimum_size = Vector2(0, 124)
	_sheet.add_child(hs)
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 8)
	hs.add_child(strip)
	for id0 in ids:
		_skin_tile(strip, str(id0), acc)
	_skin_action(acc)
	# ---- the story
	_head(_sheet, "THE STORY", "", acc)
	var lore := UI2.body(_sheet, str(ch.get("lore", "")), 12, Color("#efe6d6"))
	lore.custom_minimum_size.x = 10
	var q := UI.label(_sheet, "“%s”" % str(ch.get("quote", "")), 14, acc.lightened(0.45), UI.LORE_FONT, true)
	q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	q.add_theme_constant_override("outline_size", 4)
	# ---- the kit
	_head(_sheet, "ABILITIES", str(Kits.ROLE_TEXT.get(Kits.role_of(hero), "")), acc)
	var lines := MobaPanel.kit_lines(hero)
	for i in 4:
		_kit_row(["q", "w", "e", "r"][i], str(lines[i + 1]), acc)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 8)
	_sheet.add_child(pad)
	_scroll.set_deferred("scroll_vertical", keep)

func _head(parent: Node, title: String, sub: String, acc: Color) -> void:
	var r := UI.row(parent, 8)
	var bar := ColorRect.new()
	bar.color = acc
	bar.custom_minimum_size = Vector2(4, 18)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(bar)
	var t := UI2.text(r, title, 16, UI2.GOLD, UI2.INK, 4)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if sub != "":
		var s := UI2.body(r, sub, 10, UI2.SOFT, true)
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		s.custom_minimum_size.x = 10

func _skin_tile(parent: Node, id: String, acc: Color) -> void:
	var p = app.profile
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	for st_name in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st_name, StyleBoxEmpty.new())
	b.custom_minimum_size = Vector2(92, 118)
	b.set_meta("action_key", "champ_skin_" + (id if id != "" else "default"))
	b.pressed.connect(func():
		preview = id
		app.sfx("tap")
		_show_look()
		_render())
	parent.add_child(b)
	var on := preview == id
	if on:
		UI2.skin(b, UI2.button_params("gold", 14.0, 3.0).merged({"glow": 7.0, "glow_color": Color(acc.lightened(0.3), 0.8)}, true))
	else:
		var rar := "common" if id == "" else str(Eco.SKINS[id].rarity)
		UI2.plate(b, "night" if id == "" else ("purple" if rar == "epic" else ("ember" if rar == "legendary" else "royal")), 14.0,
			"silver" if id == "" else "purple", {"rim": 2.0, "dim": 0.1})
	var path := ("res://assets/ui/skins/%s.png" % id) if id != "" else MobaPanel.portrait(hero)
	var ti := TextureRect.new()
	ti.texture = load(path) if ResourceLoader.exists(path) else null
	ti.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ti.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ti.position = Vector2(8, 6)
	ti.size = Vector2(76, 76)
	ti.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(ti)
	var label := "DEFAULT" if id == "" else str(Eco.SKINS[id].set).to_upper()
	var l := UI2.text(b, label, 11, Color.WHITE, UI2.INK, 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector2(0, 80)
	l.size = Vector2(92, 16)
	var worn: bool = p.worn_skin(hero) == id
	var state := ""
	if worn:
		state = "WORN"
	elif id == "" or p.owns_skin(id):
		state = "OWNED"
	var sl: Label
	if state != "":
		sl = UI2.text(b, state, 10, Color("#9dff8a") if worn else Color("#cfe9ff"), Color(0, 0, 0, 0.8), 3)
	else:
		var o := Eco.skin_offer(id, p.now())                 # 0.31.203: the weekly sale's price, and its cut
		sl = UI2.text(b, ("◆ %d  -%d%%" % [int(o.gems), int(o.off)]) if int(o.off) > 0 else "◆ %d" % int(o.gems), 11,
			Color("#ffd2c4") if int(o.off) > 0 else Color("#e8ccff"), Color("#4a0306") if int(o.off) > 0 else Color("#1e0a45"), 3)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sl.position = Vector2(0, 97)
	sl.size = Vector2(92, 14)

func _skin_action(acc: Color) -> void:
	# under the strip: the shown skin's name and what you can do with it
	var p = app.profile
	var r := UI.row(_sheet, 8)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(v)
	var nm := Champions.short_of(hero) + ("  ·  original" if preview == "" else "")
	if preview != "":
		nm = str(Eco.SKINS[preview].name)
	UI2.text(v, nm.to_upper(), 14, Color.WHITE, UI2.INK, 4)
	if preview != "":
		var rar := str(Eco.SKINS[preview].rarity)
		var what := "a new look and its own weapon" if Eco.SKINS[preview].has("weapon") else "a new look, the weapon repainted to match"
		UI2.body(v, rar.to_upper() + " OUTFIT  ·  " + ("yours" if p.owns_skin(preview) else (("%s comes with it" % Champions.short_of(hero)) if not p.owns_hero(hero) else what)),
			10, Color(str(Eco.RARITY_COLOR.get(rar, "#b8c4c9"))).lightened(0.3), false)
	else:
		UI2.body(v, "DEFAULT  ·  the original look", 10, UI2.SOFT, false)
	var b: Button
	var worn: bool = p.worn_skin(hero) == preview
	if preview == "" or p.owns_skin(preview):
		b = UI2.button(r, "WORN" if worn else "WEAR", "grey" if worn else "blue", func():
			p.wear_skin(hero, preview)
			app.sfx("equip")
			app.toast("%s wears %s" % [Champions.short_of(hero), "the original look" if preview == "" else str(Eco.SKINS[preview].name)], UI.CYAN)
			_render(), "champ_wear", 15, 42.0, 12.0)
		b.disabled = worn
	else:
		var o := Eco.skin_offer(preview, p.now())             # 0.31.203: the weekly sale's price when it's on it
		var gems := int(o.gems)
		var gold := int(o.gold)
		b = UI2.button(r, UI.grouped(gems), "purple", _ask_buy, "champ_buy", 16, 42.0, 12.0, GEM)
		b.disabled = int(p.d.gems) < gems and (gold <= 0 or int(p.d.gold) < gold)      # (0.31.189: or the gold)
		if int(o.off) > 0:
			UI2.body(v, "WEEKLY SALE  -%d%%  ·  was %s gems" % [int(o.off), UI.grouped(int(o.was_gems))], 10, Color("#ff9c8a"), false)
		if gold > 0:
			UI2.body(v, "or %s gold" % UI.grouped(gold), 10, Color("#ffd86b"), false)
	b.custom_minimum_size.x = 112
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER

func _kit_row(slot: String, line: String, acc: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet.add_child(row)
	var ic := TextureRect.new()
	ic.texture = Hud.ability_icon(hero, slot)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.custom_minimum_size = Vector2(38, 38)
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(ic)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	# "Q BOULDER: ..." / "W STONESKIN (lv 2): ..." -> the name, then what it does
	var cut := line.find(": ")
	var name := line.substr(0, cut) if cut > 0 else line
	var what := line.substr(cut + 2) if cut > 0 else ""
	UI2.text(v, name, 13, acc.lightened(0.5), UI2.INK, 4)
	var w := UI2.body(v, what, 11, Color("#e8e2d6"))
	w.custom_minimum_size.x = 10

# ---------------- PLAY, UNLOCK and BUY ----------------
func _play() -> void:
	# (the 5v5 window with him picked)
	app.profile.d.settings["moba_hero"] = hero
	app.profile.save()
	app.sfx("confirm")
	app.open_moba()

func _overlay(title: String, sub: String) -> VBoxContainer:
	close_overlay()
	app.sfx("menuOpen")
	overlay = ColorRect.new()
	(overlay as ColorRect).color = Color(0, 0, 0, 0.62)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(cc)
	var box := UI2.frame(cc, "night", 14, 18.0, "gold")
	(box.get_parent() as Control).custom_minimum_size = Vector2(300, 0)
	box.add_theme_constant_override("separation", 8)
	var t := UI2.center(UI2.text(box, title, 21, UI2.GOLD))
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = 260
	var s := UI2.center(UI2.body(box, sub, 11, UI2.SOFT))
	s.custom_minimum_size.x = 260
	return box

func close_overlay() -> void:
	if is_instance_valid(overlay):
		overlay.queue_free()
	overlay = null

func open_chooser() -> void:
	# UNLOCK <NAME>: each way to unlock him (the 5v5 window's chooser), those you can't pay dimmed; CANCEL
	var p = app.profile
	var pr: Dictionary = p.hero_price(hero)
	if pr.is_empty() or p.owns_hero(hero):
		return
	var box := _overlay("UNLOCK " + Champions.name_of(hero).to_upper(), "The %s, yours for good.%s" % [str(Moba.HEROES[hero].name),
		"  Launch price for now." if Eco.launching(hero, p.now()) else ""])
	var opts := [["%s GOLD" % UI.grouped(int(pr.gold)), "gold", COIN, "champ_unlock_gold", int(p.d.gold) >= int(pr.gold), "gold"],
		["%s GEMS" % UI.grouped(int(pr.gems)), "blue", GEM, "champ_unlock_gems", int(p.d.gems) >= int(pr.gems), "gems"]]
	if p.shards_of(hero) > 0:
		var sg := Eco.shard_unlock_gold(hero, p.now())
		opts.append(["SHARD + %s GOLD" % UI.grouped(sg), "green", COIN, "champ_unlock_shard", int(p.d.gold) >= sg, "shard"])
	if int(p.d.get("tokens", 0)) > 0:
		opts.append(["HERO TOKEN", "purple", "", "champ_unlock_token", true, "token"])
	for o in opts:
		var how: String = o[5]
		var b := UI2.button(box, str(o[0]), str(o[1]), func(): _unlock_by(how), str(o[3]), 17, 46.0, 14.0, str(o[2]))
		b.disabled = not bool(o[4])
	UI2.button(box, "CANCEL", "grey", func():
		app.sfx("menuClose")
		close_overlay(), "champ_cancel", 15, 40.0, 12.0)

func _unlock_by(how: String) -> void:
	var p = app.profile
	var r: Dictionary
	match how:
		"gold":
			r = p.buy_hero(hero)
		"gems":
			r = p.buy_hero_gems(hero)
		"shard":
			r = p.use_shard(hero)
		_:
			r = p.use_token(hero)
	if bool(r.get("ok", false)):
		app.sfx("purchase")
		app.toast("%s joins you!" % Champions.name_of(hero), UI2.GOLD)
		close_overlay()
		app.refresh_top()
		app.rebuild()                           # (the Locker under the window -- and refresh() here)
	else:
		app.sfx("error")
		app.toast(str(r.get("error", "Can't unlock")), Color("#ff8a7a"))

func _ask_buy() -> void:
	var p = app.profile
	var id := preview
	if id == "" or p.owns_skin(id):
		return
	var sk: Dictionary = Eco.SKINS[id]
	var o := Eco.skin_offer(id, p.now())                     # 0.31.203: at the weekly sale's price when it's on it
	var gems := int(o.gems)
	var gold := int(o.gold)
	var with_hero: bool = not p.owns_hero(hero)
	var box := _overlay("BUY %s?" % str(sk.name).to_upper(), "%s%s gems%s. Worn at once.%s" % [
		("Weekly sale: %d%% off. " % int(o.off)) if int(o.off) > 0 else "", UI.grouped(gems),
		(" or %s gold" % UI.grouped(gold)) if gold > 0 else "",
		(" %s comes with it -- the %s is yours too." % [Champions.short_of(hero), str(Moba.HEROES[hero].name)]) if with_hero else ""])
	var done := func(r: Dictionary) -> void:
		if bool(r.get("ok", false)):
			app.sfx("purchase")
			app.toast("%s is yours%s" % [str(sk.name), (" -- and %s" % Champions.short_of(hero)) if bool(r.get("hero", false)) else ""], UI.GOLD)
			close_overlay()
			app.refresh_top()
			app.rebuild()
		else:
			app.sfx("error")
			app.toast(str(r.get("error", "Can't buy")), UI.RED)
	var bg := UI2.button(box, "BUY  %s" % UI.grouped(gems), "purple", func(): done.call(p.buy_outfit(id, false)), "champ_buy_yes", 17, 46.0, 14.0, GEM)
	bg.disabled = int(p.d.gems) < gems
	if gold > 0:                                       # 0.31.189 (Kevin: "Frostbound for gold")
		var bo := UI2.button(box, "BUY  %s" % UI.grouped(gold), "gold", func(): done.call(p.buy_outfit(id, true)), "champ_buy_gold", 17, 46.0, 14.0, COIN)
		bo.disabled = int(p.d.gold) < gold
	UI2.button(box, "CANCEL", "grey", func():
		app.sfx("menuClose")
		close_overlay(), "champ_cancel", 15, 40.0, 12.0)
