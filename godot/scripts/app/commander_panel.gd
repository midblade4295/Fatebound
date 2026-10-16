extends Control
# 0.31.153 COMMANDER (the prototype; scripts/meta/cards.gd): the window before the match -- what the mode is, your deck
# of 8 out of the 14 troops (tap a card to take it in or out; the last one tapped is described under the grid), the
# deck's average cost, and BATTLE (an offline match against the AI commander: siege_app.start_commander). The deck is
# kept on this phone (settings.cmd_deck). Everything is unlocked: the collection, levels and the shop come later, if
# the test plays well.
const UI = preload("res://scripts/app/ui.gd")
const UI2 = preload("res://scripts/app/ui2.gd")
const SocialUI = preload("res://scripts/app/social_ui.gd")
const Cards = preload("res://scripts/meta/cards.gd")

const CARD_W := 74.0
const CARD_H := 96.0

var app
var deck: Array = []
var focus := ""                       # the card last tapped (its line under the grid)
var _grid: GridContainer
var _info: Label
var _count: Label
var _go: Button

func open(a) -> void:
	app = a
	var saved: Array = app.profile.d.settings.get("cmd_deck", []) if app.profile.d.settings.get("cmd_deck", []) is Array else []
	deck = saved.duplicate() if Cards.valid_deck(saved) else Cards.DEFAULT_DECK.duplicate()
	var w := SocialUI.window(self, "COMMANDER", "helmet", func():
		app.sfx("menuClose")
		app.close_modal(), 56.0 + float(app.safe_top), 24.0)
	var body: VBoxContainer = w.body
	var tag := UI2.body(body, "TEST MODE", 11, Color("#d6a2ff"))
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI2.body(body, "You and 15 soldiers against the enemy commander's army. Command points fill up over the match: tap a "
		+ "card to send its squad out of your castle in its hats. Fallen soldiers drop their hats and come back to the "
		+ "barracks for your next card. Rescue your King 3 times, or be ahead when the 8 minutes run out.", 12, UI2.SOFT)
	var row := UI.row(body, 6)
	var dl := UI2.text(row, "YOUR DECK", 16, UI2.GOLD)
	dl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count = UI2.body(row, "", 12, UI2.SOFT, false)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = 1000000                  # (drag-scrolled by the app, like the menus)
	body.add_child(scroll)
	set_meta("drag_scroll", scroll)
	var holder := CenterContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(holder)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	holder.add_child(_grid)
	_info = UI2.body(body, "", 12, Color.WHITE)
	_info.custom_minimum_size = Vector2(0, 36)
	_go = UI2.button(body, "BATTLE", "orange", func():
		if deck.size() != Cards.DECK_SIZE:
			app.sfx("error")
			return
		app.profile.d.settings["cmd_deck"] = deck.duplicate()
		app.profile.save()
		app.sfx("confirm")
		app.close_modal()
		app.start_commander(deck.duplicate()), "cmd_battle", 22, 56.0, 16.0)
	UI2.sweep(_go)
	_render()

func _render() -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	for id in Cards.ORDER:
		_grid.add_child(_card(str(id)))
	_count.text = "%d / %d  ·  average cost %.1f" % [deck.size(), Cards.DECK_SIZE, Cards.deck_cost(deck)]
	_go.disabled = deck.size() != Cards.DECK_SIZE
	_go.text = "BATTLE" if deck.size() == Cards.DECK_SIZE else "PICK %d MORE" % (Cards.DECK_SIZE - deck.size())
	if focus != "":
		var cd := Cards.card(focus)
		_info.text = "%s (%s, %d to play, %s): %s" % [str(cd.name), str(cd.rarity).capitalize(), int(cd.cost),
			"one" if int(cd.squad) == 1 else "%d soldiers" % int(cd.squad), str(cd.text)]
	else:
		_info.text = "Tap a card to take it out of your deck or put it in."

func _card(id: String) -> Control:
	var cd := Cards.card(id)
	var on := deck.has(id)
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(CARD_W, CARD_H)
	b.set_meta("action_key", "cmd_card_" + id)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.07, 0.14) if on else Color(0.05, 0.05, 0.08)
	var rc := Color(str(Cards.RARITY_COLOR.get(str(cd.rarity), "#b8c4c9")))
	sb.border_color = rc if on else rc.darkened(0.55)
	sb.set_border_width_all(3 if on else 2)
	sb.set_corner_radius_all(9)
	for st in ["normal", "hover", "pressed", "focus", "hover_pressed", "disabled"]:
		b.add_theme_stylebox_override(st, sb)
	var tex := TextureRect.new()
	var p := Cards.portrait(id)
	tex.texture = load(p) if ResourceLoader.exists(p) else null
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tex.position = Vector2(4, 4)
	tex.size = Vector2(CARD_W - 8, CARD_H - 24)
	tex.modulate = Color.WHITE if on else Color(0.42, 0.42, 0.48)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(tex)
	var nl := UI2.text(b, str(cd.name).to_upper(), 10 if str(cd.name).length() <= 9 else 9, Color.WHITE if on else Color(0.7, 0.7, 0.75), Color("#120a20"), 4, false)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.position = Vector2(0, CARD_H - 21)
	nl.size = Vector2(CARD_W, 18)
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cost := PanelContainer.new()
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color("#b25cff") if on else Color("#5a2e80")
	cs.border_color = Color("#1a0628")
	cs.set_border_width_all(2)
	cs.set_corner_radius_all(11)
	cs.content_margin_left = 6
	cs.content_margin_right = 6
	cost.add_theme_stylebox_override("panel", cs)
	cost.position = Vector2(-4, -4)
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(cost)
	var cl := UI2.text(cost, str(int(cd.cost)), 14, Color.WHITE, Color("#1a0628"), 4, false)
	cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if int(cd.squad) > 1:
		var sq := UI2.text(b, "×%d" % int(cd.squad), 11, Color.WHITE, Color("#120a20"), 4, false)
		sq.position = Vector2(CARD_W - 26, 2)
		sq.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if on:
		var ck := UI2.text(b, "✔", 14, Color("#7dff8a"), Color("#08200c"), 4, false)
		ck.position = Vector2(CARD_W - 18, CARD_H - 40)
		ck.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.pressed.connect(func(): _tap(id))
	return b

func _tap(id: String) -> void:
	focus = id
	if deck.has(id):
		deck.erase(id)
		app.sfx("tab")
	elif deck.size() < Cards.DECK_SIZE:
		deck.append(id)
		app.sfx("equip")
	else:
		app.sfx("error")
		app.toast("Your deck is full -- tap a card in it to take it out first", UI.MUTED)
	_render()
