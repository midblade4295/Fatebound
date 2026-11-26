extends Control
## The deck builder: the eight cards in the deck across the top, every card there is in a grid
## that scrolls (drag it) and can be narrowed to one kind (the tabs), and a panel that says what
## the chosen card does. Tap a card to read about it; the button beside the description puts it
## in the deck or takes it out. A deck is eight different cards, with at most one commander.

const Kit = preload("res://scripts/view/ui_kit.gd")
const Profile = preload("res://scripts/app/profile.gd")

const COLUMNS := 5
const CARD := Vector2(96.0, 126.0)
const GAP := Vector2(6.0, 8.0)

const TABS := [["all", "ALL"], ["infantry", "FOOT"], ["cavalry", "HORSE"], ["artillery", "GUNS"], ["order", "ORDERS"], ["support", "SUPPORT"]]

var app: Node
var deck: Array = []               # being edited; saved when it is closed with eight cards
var chosen: String = ""
var tab: String = "all"
var scroll: float = 0.0            # how far the grid has been scrolled up, in pixels
var _hot: Dictionary = {}
var _pressed: String = ""
var _grid: Control                 # the scrolling grid's window: it clips what is drawn in it
var _grid_rect: Rect2 = Rect2()
var _content_h: float = 0.0
var _press_at: Vector2 = Vector2.ZERO
var _scroll_at_press: float = 0.0
var _down: bool = false
var _scrolling: bool = false
var _note: String = ""
var _note_time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	resized.connect(queue_redraw)
	_grid = Control.new()
	_grid.clip_contents = true
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE      # this screen reads all the input
	_grid.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_grid.draw.connect(_draw_grid)
	add_child(_grid)
	get_viewport().size_changed.connect(_fill_screen)
	_fill_screen()


## Covers the whole screen, whatever shape it is.
func _fill_screen() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size


func open(current: Array) -> void:
	deck = current.duplicate()
	chosen = deck[0] if not deck.is_empty() else ""
	tab = "all"
	scroll = 0.0
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
		_grid.queue_redraw()


func rect_of(name: String) -> Rect2:
	return _hot.get(name, Rect2())


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_down = true
			_scrolling = false
			_press_at = event.position
			_scroll_at_press = scroll
			_pressed = _at(event.position)
		else:
			_down = false
			var released := _at(event.position)
			if not _scrolling and released != "" and released == _pressed:
				_press(released)
			_pressed = ""
			_scrolling = false
		accept_event()
		queue_redraw()
	elif event is InputEventMouseMotion and _down and _grid_rect.has_point(_press_at):
		# A finger that moves in the grid scrolls it, and is then not a tap.
		if absf(event.position.y - _press_at.y) > 10.0:
			_scrolling = true
		if _scrolling:
			scroll = clampf(_scroll_at_press - (event.position.y - _press_at.y), 0.0, maxf(0.0, _content_h - _grid_rect.size.y))
			queue_redraw()
		accept_event()
	elif event is InputEventMouseButton and event.pressed and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		scroll = clampf(scroll + (60.0 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -60.0), 0.0, maxf(0.0, _content_h - _grid_rect.size.y))
		accept_event()


func _at(p: Vector2) -> String:
	for name: String in _hot:
		if name.begins_with("card:") and not _grid_rect.has_point(p):
			continue                   # a card scrolled out of the window cannot be tapped
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
	elif name.begins_with("tab:"):
		tab = name.substr(4)
		scroll = 0.0


## Puts a card in the deck, or takes it out.
func toggle(card_id: String) -> void:
	if card_id == "" or not app.cards.has(card_id):
		return
	if deck.has(card_id):
		deck.erase(card_id)
	elif deck.size() >= Profile.DECK_SIZE:
		_say("The deck is full: take a card out first")
	elif bool(app.cards[card_id].get("unique", false)) and deck.any(func(id): return bool(app.cards[id].get("unique", false))):
		_say("One commander to a deck: take the other out first")
	else:
		deck.append(card_id)
	queue_redraw()


## Which tab a card belongs under.
func _kind(def: Dictionary) -> String:
	if def["type"] == "order":
		return "order"
	if def["type"] == "work" or def.get("arm", "") == "command":
		return "support"
	return String(def.get("arm", "infantry"))


## The cards shown in the grid: those under the current tab, by kind, then cost, then name.
func _listed() -> Array:
	var rank := {"infantry": 0, "cavalry": 1, "artillery": 2, "order": 3, "support": 4}
	var ids: Array = []
	for id: String in app.cards:
		if tab == "all" or _kind(app.cards[id]) == tab:
			ids.append(id)
	ids.sort_custom(func(a: String, b: String) -> bool:
		var da: Dictionary = app.cards[a]
		var db: Dictionary = app.cards[b]
		var ka := int(rank[_kind(da)])
		var kb := int(rank[_kind(db)])
		if ka != kb:
			return ka < kb
		if int(da["cost"]) != int(db["cost"]):
			return int(da["cost"]) < int(db["cost"])
		return String(da["name"]) < String(db["name"]))
	return ids


func _draw() -> void:
	if app == null or app.kit == null:
		return
	var kit: Kit = app.kit
	var screen := size
	_hot.clear()
	kit.wood_panel(self, Rect2(Vector2.ZERO, screen), Color(0.62, 0.6, 0.58))
	var ox := (screen.x - 540.0) * 0.5
	var y := 14.0 + clampf((screen.y - 1100.0) * 0.25, 0.0, 60.0)

	kit.outlined(self, Vector2(screen.x * 0.5, y + 30.0), "YOUR DECK", 30, Color("ffd24a"), 500.0, 7)
	var total := 0.0
	for id: String in deck:
		total += float(app.cards[id]["cost"])
	var count_colour := Kit.CREAM if deck.size() == Profile.DECK_SIZE else Color("ff9a3c")
	kit.text(self, Vector2(screen.x * 0.5, y + 54.0), "%d of %d cards     average cost %.1f     %d cards to choose from" % [deck.size(),
			Profile.DECK_SIZE, total / maxf(1.0, deck.size()), app.cards.size()], 13, count_colour, HORIZONTAL_ALIGNMENT_CENTER, 520.0, true)
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
	y += 94.0

	# Tabs.
	var tab_w := 512.0 / TABS.size()
	for i in TABS.size():
		var r := Rect2(ox + 14.0 + i * tab_w + 2.0, y, tab_w - 4.0, 32.0)
		_hot["tab:" + String(TABS[i][0])] = r
		kit.button(self, r, String(TABS[i][1]), "on" if tab == TABS[i][0] else "wood", 13)
	y += 42.0

	# From the bottom up: DONE, then the description, then the grid fills what is left.
	var done_y := screen.y - 58.0 - clampf((screen.y - 1100.0) * 0.25, 0.0, 60.0)
	var info := Rect2(ox + 14.0, done_y - 12.0 - 132.0, 512.0, 132.0)
	_grid_rect = Rect2(ox + 2.0, y, 536.0, info.position.y - 10.0 - y)
	_grid.position = _grid_rect.position
	_grid.size = _grid_rect.size
	var listed := _listed()
	var rows := int(ceil(listed.size() / float(COLUMNS)))
	_content_h = rows * (CARD.y + GAP.y) + 10.0
	scroll = clampf(scroll, 0.0, maxf(0.0, _content_h - _grid_rect.size.y))
	for i in listed.size():
		_hot["card:" + String(listed[i])] = _cell(i).grow(-1.0)
	# A thin scroll bar when there is more than fits.
	if _content_h > _grid_rect.size.y:
		var bar_h := _grid_rect.size.y * _grid_rect.size.y / _content_h
		var bar_y := _grid_rect.position.y + (_grid_rect.size.y - bar_h) * scroll / maxf(1.0, _content_h - _grid_rect.size.y)
		draw_rect(Rect2(_grid_rect.end.x - 1.0, _grid_rect.position.y, 3.0, _grid_rect.size.y), Color(0, 0, 0, 0.3))
		draw_rect(Rect2(_grid_rect.end.x - 1.0, bar_y, 3.0, bar_h), Kit.BRASS_MID)
	draw_rect(Rect2(_grid_rect.position.x, _grid_rect.position.y - 1.0, _grid_rect.size.x, 1.0), Color(0, 0, 0, 0.4))
	draw_rect(Rect2(_grid_rect.position.x, _grid_rect.end.y, _grid_rect.size.x, 1.0), Color(0, 0, 0, 0.4))

	# What the chosen card does.
	kit.tray(self, info)
	if chosen != "" and app.cards.has(chosen):
		var def: Dictionary = app.cards[chosen]
		kit.coin(self, info.position + Vector2(30, 30), int(def["cost"]), true)
		kit.text(self, info.position + Vector2(54, 36), String(def["name"]), 20, Color("ffd24a"), HORIZONTAL_ALIGNMENT_LEFT, 300.0, true)
		var rarity := String(def.get("rarity", "rare"))
		var tier: Dictionary = Kit.RARITY.get(rarity, Kit.RARITY["rare"])
		kit.text(self, info.position + Vector2(info.size.x - 18.0, 28), kit.kind_label(def), 12, Kit.BRASS_LIGHT, HORIZONTAL_ALIGNMENT_RIGHT, 150.0, true)
		var tier_ink: Color = tier["ink"]
		if rarity == "legendary":
			tier_ink = Color.from_hsv(fposmod(Time.get_ticks_msec() / 1000.0 * 0.22, 1.0), 0.5, 1.0)
		kit.text(self, info.position + Vector2(info.size.x - (34.0 if rarity == "rare" or rarity == "epic" else 18.0), 46), String(tier["name"]).to_upper(), 12, tier_ink,
				HORIZONTAL_ALIGNMENT_RIGHT, 150.0, true)
		kit.gem(self, info.position + Vector2(info.size.x - 24.0, 41), rarity, 6.0)
		draw_string(kit.font_bold, info.position + Vector2(18, 60), String(def.get("field", "")), HORIZONTAL_ALIGNMENT_LEFT, info.size.x - 36.0, 13, Kit.CREAM)
		draw_multiline_string(kit.font, info.position + Vector2(18, 80), String(def.get("job", "")), HORIZONTAL_ALIGNMENT_LEFT, info.size.x - 190.0, 13, 3,
				Color(Kit.CREAM, 0.9))
		var has := deck.has(chosen)
		_hot["toggle"] = Rect2(info.end.x - 164.0, info.position.y + 64.0, 146.0, 40.0)
		kit.button(self, _hot["toggle"], "TAKE OUT" if has else "ADD TO DECK", "wood" if has else ("gold" if deck.size() < Profile.DECK_SIZE else "off"), 15)

	_hot["done"] = Rect2(ox + 150.0, done_y, 240.0, 46.0)
	var ready := deck.size() == Profile.DECK_SIZE
	kit.button(self, _hot["done"], "DONE" if ready else "CHOOSE %d MORE" % (Profile.DECK_SIZE - deck.size()), "gold" if ready else "off", 20)
	if _note_time > 0.0:
		var plate := Rect2(screen.x * 0.5 - 230.0, info.position.y - 48.0, 460.0, 38.0)
		draw_style_box(kit.box("deck_note", Color(0.1, 0.06, 0.03, 0.94), 8.0, 2.0, Kit.BRASS_MID), plate)
		kit.text(self, plate.get_center() + Vector2(0, 5), _note, 14, Kit.CREAM, HORIZONTAL_ALIGNMENT_CENTER, 440.0, true)


## Where the i-th listed card sits, on screen.
func _cell(i: int) -> Rect2:
	var grid_w := COLUMNS * CARD.x + (COLUMNS - 1) * GAP.x
	var gx := _grid_rect.position.x + (_grid_rect.size.x - grid_w) * 0.5
	return Rect2(gx + (i % COLUMNS) * (CARD.x + GAP.x), _grid_rect.position.y + 12.0 + (i / COLUMNS) * (CARD.y + GAP.y) - scroll, CARD.x, CARD.y)


## The grid, drawn on its own clipping node so that cards scrolled half out of view are cut off
## at its edges rather than drawn over the deck and the description.
func _draw_grid() -> void:
	if app == null or app.kit == null:
		return
	var kit: Kit = app.kit
	var c: Control = _grid
	var listed := _listed()
	for i in listed.size():
		var id: String = listed[i]
		var cell := _cell(i)
		if cell.end.y < _grid_rect.position.y - 12.0 or cell.position.y > _grid_rect.end.y + 12.0:
			continue
		cell.position -= _grid_rect.position
		kit.card_face(c, cell, app.cards[id], _art(id), true, 1.0 if id == chosen else 0.0)
		if id == chosen:
			c.draw_rect(cell.grow(3.5), Color(1, 1, 1, 0.95), false, 2.0)
		if deck.has(id):
			# A tick in the corner says it is in the deck.
			var badge := Vector2(cell.end.x - 15.0, cell.end.y - Kit.CARD_NAME - 12.0)
			c.draw_circle(badge, 10.5, Kit.BRASS_DARK)
			c.draw_circle(badge, 9.0, Color("3f9a3c"))
			c.draw_polyline(PackedVector2Array([badge + Vector2(-4.5, 0.0), badge + Vector2(-1.2, 3.6), badge + Vector2(4.8, -3.6)]), Color.WHITE, 2.4)


func _art(card_id: String) -> Texture2D:
	return app.battle._art(card_id)
