extends Control
## The deck builder: all eighteen cards, the eight in the deck across the top, and a panel
## that says what the chosen card does. Tap a card to read about it; the button under the
## description puts it in the deck or takes it out. A deck is eight different cards.

const Kit = preload("res://scripts/view/ui_kit.gd")
const Profile = preload("res://scripts/app/profile.gd")

const COLUMNS := 5
const CARD := Vector2(96.0, 126.0)
const GAP := Vector2(6.0, 8.0)

var app: Node
var deck: Array = []               # being edited; saved when it is closed with eight cards
var chosen: String = ""
var _hot: Dictionary = {}
var _pressed: String = ""
var _note: String = ""
var _note_time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	resized.connect(queue_redraw)
	get_viewport().size_changed.connect(_fill_screen)
	_fill_screen()


## Covers the whole screen, whatever shape it is.
func _fill_screen() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size


func open(current: Array) -> void:
	deck = current.duplicate()
	chosen = deck[0] if not deck.is_empty() else ""
	_note = ""
	visible = true
	queue_redraw()


## Back to the menu. A deck of eight is kept; anything else is thrown away and says so.
func close() -> void:
	if Profile.is_valid_deck(deck, app.cards):
		app.set_deck(deck)
	app.show_menu()


func _process(delta: float) -> void:
	_note_time = maxf(0.0, _note_time - delta)
	if visible:
		queue_redraw()             # the legendary card's glint, and the fading note


func rect_of(name: String) -> Rect2:
	return _hot.get(name, Rect2())


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressed = _at(event.position)
		else:
			var released := _at(event.position)
			if released != "" and released == _pressed:
				_press(released)
			_pressed = ""
		accept_event()
		queue_redraw()


func _at(p: Vector2) -> String:
	for name: String in _hot:
		if (_hot[name] as Rect2).has_point(p):
			return name
	return ""


func _say(text: String) -> void:
	_note = text
	_note_time = 2.2


func _press(name: String) -> void:
	if name == "done":
		if deck.size() == Profile.DECK_SIZE:
			close()
		else:
			_say("A deck is eight cards: choose %d more" % (Profile.DECK_SIZE - deck.size()))
	elif name == "toggle":
		toggle(chosen)
	elif name.begins_with("card:") or name.begins_with("slot:"):
		chosen = name.substr(5)


## Puts a card in the deck, or takes it out.
func toggle(card_id: String) -> void:
	if card_id == "" or not app.cards.has(card_id):
		return
	if deck.has(card_id):
		deck.erase(card_id)
	elif deck.size() >= Profile.DECK_SIZE:
		_say("The deck is full: take a card out first")
	else:
		deck.append(card_id)
	queue_redraw()


func _draw() -> void:
	if app == null or app.kit == null:
		return
	var kit: Kit = app.kit
	var screen := size
	_hot.clear()
	kit.wood_panel(self, Rect2(Vector2.ZERO, screen), Color(0.62, 0.6, 0.58))
	var ox := (screen.x - 540.0) * 0.5
	var spare := maxf(0.0, screen.y - 960.0)
	var y := 18.0 + spare * 0.3

	kit.outlined(self, Vector2(screen.x * 0.5, y + 30.0), "YOUR DECK", 30, Color("ffd24a"), 500.0, 7)
	var total := 0.0
	for id: String in deck:
		total += float(app.cards[id]["cost"])
	var count_colour := Kit.CREAM if deck.size() == Profile.DECK_SIZE else Color("ff9a3c")
	kit.text(self, Vector2(screen.x * 0.5, y + 54.0), "%d of %d cards     average cost %.1f" % [deck.size(), Profile.DECK_SIZE,
			total / maxf(1.0, deck.size())], 13, count_colour, HORIZONTAL_ALIGNMENT_CENTER, 400.0, true)
	y += 66.0

	# The deck: eight slots.
	var strip := Rect2(ox + 14.0, y, 512.0, 84.0)
	kit.tray(self, strip)
	for i in Profile.DECK_SIZE:
		var slot := Rect2(strip.position.x + 14.0 + i * 61.5, y + 13.0, 54.0, 58.0)
		if i < deck.size():
			var id: String = deck[i]
			kit.mini_card(self, slot, _art(id), String(app.cards[id]["name"]), String(app.cards[id].get("rarity", "rare")))
			kit.coin(self, slot.position + Vector2(3, 3), int(app.cards[id]["cost"]), true)
			if id == chosen:
				draw_rect(slot.grow(4.0), Color(1, 1, 1, 0.9), false, 2.0)
			_hot["slot:" + id] = slot
		else:
			draw_style_box(kit.box("deck_empty", Color(0, 0, 0, 0.35), 5.0, 1.0, Kit.BRASS_DARK), slot)
	y += 98.0

	# Every card there is.
	var ids: Array = app.cards.keys()
	var grid_w := COLUMNS * CARD.x + (COLUMNS - 1) * GAP.x
	var gx := ox + (540.0 - grid_w) * 0.5
	for i in ids.size():
		var id: String = ids[i]
		var cell := Rect2(gx + (i % COLUMNS) * (CARD.x + GAP.x), y + (i / COLUMNS) * (CARD.y + GAP.y), CARD.x, CARD.y)
		var inside := deck.has(id)
		kit.card_face(self, cell, app.cards[id], _art(id), true, 1.0 if id == chosen else 0.0)
		if id == chosen:
			draw_rect(cell.grow(3.5), Color(1, 1, 1, 0.95), false, 2.0)
		if inside:
			# A brass tick in the corner says it is in the deck.
			var badge := Vector2(cell.end.x - 15.0, cell.end.y - Kit.CARD_NAME - 12.0)
			draw_circle(badge, 10.5, Kit.BRASS_DARK)
			draw_circle(badge, 9.0, Color("3f9a3c"))
			draw_polyline(PackedVector2Array([badge + Vector2(-4.5, 0.0), badge + Vector2(-1.2, 3.6), badge + Vector2(4.8, -3.6)]), Color.WHITE, 2.4)
		_hot["card:" + id] = cell
	var rows := int(ceil(ids.size() / float(COLUMNS)))
	y += rows * (CARD.y + GAP.y) + 4.0

	# What the chosen card does.
	var info := Rect2(ox + 14.0, y, 512.0, maxf(122.0, screen.y - y - 68.0 - spare * 0.1))
	info.size.y = minf(info.size.y, 170.0)
	kit.tray(self, info)
	if chosen != "" and app.cards.has(chosen):
		var def: Dictionary = app.cards[chosen]
		kit.coin(self, info.position + Vector2(30, 30), int(def["cost"]), true)
		kit.text(self, info.position + Vector2(54, 36), String(def["name"]), 20, Color("ffd24a"), HORIZONTAL_ALIGNMENT_LEFT, 300.0, true)
		var rarity := String(def.get("rarity", "rare"))
		var tier: Dictionary = Kit.RARITY.get(rarity, Kit.RARITY["rare"])
		kit.text(self, info.position + Vector2(info.size.x - 18.0, 28), kit.kind_label(def), 12, Kit.BRASS_LIGHT, HORIZONTAL_ALIGNMENT_RIGHT, 150.0, true)
		kit.text(self, info.position + Vector2(info.size.x - (34.0 if rarity != "common" else 18.0), 46), String(tier["name"]).to_upper(), 12, tier["ink"],
				HORIZONTAL_ALIGNMENT_RIGHT, 150.0, true)
		kit.gem(self, info.position + Vector2(info.size.x - 24.0, 41), rarity, 6.0)
		draw_string(kit.font_bold, info.position + Vector2(18, 60), String(def.get("field", "")), HORIZONTAL_ALIGNMENT_LEFT, info.size.x - 36.0, 13, Kit.CREAM)
		draw_multiline_string(kit.font, info.position + Vector2(18, 80), String(def.get("job", "")), HORIZONTAL_ALIGNMENT_LEFT, info.size.x - 190.0, 13, 3,
				Color(Kit.CREAM, 0.9))
		var has := deck.has(chosen)
		_hot["toggle"] = Rect2(info.end.x - 164.0, info.position.y + 64.0, 146.0, 40.0)
		kit.button(self, _hot["toggle"], "TAKE OUT" if has else "ADD TO DECK", "wood" if has else ("gold" if deck.size() < Profile.DECK_SIZE else "off"), 15)
	y = info.end.y + 12.0

	_hot["done"] = Rect2(ox + 150.0, y, 240.0, 46.0)
	var ready := deck.size() == Profile.DECK_SIZE
	kit.button(self, _hot["done"], "DONE" if ready else "CHOOSE %d MORE" % (Profile.DECK_SIZE - deck.size()), "gold" if ready else "off", 20)
	if _note_time > 0.0:
		var plate := Rect2(screen.x * 0.5 - 220.0, y - 52.0, 440.0, 38.0)
		draw_style_box(kit.box("deck_note", Color(0.1, 0.06, 0.03, 0.94), 8.0, 2.0, Kit.BRASS_MID), plate)
		kit.text(self, plate.get_center() + Vector2(0, 5), _note, 14, Kit.CREAM, HORIZONTAL_ALIGNMENT_CENTER, 420.0, true)


func _art(card_id: String) -> Texture2D:
	return app.battle._art(card_id)
