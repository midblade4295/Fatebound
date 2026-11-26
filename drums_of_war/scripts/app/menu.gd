extends Control
## The main menu: a few panels floating over the idle battlefield. Drawn with the HUD's kit;
## each thing that can be pressed is a rect in _hot, looked up when the finger comes down.

const Kit = preload("res://scripts/view/ui_kit.gd")
const Bot = preload("res://scripts/sim/bot.gd")

var app: Node
var _hot: Dictionary = {}          # what can be pressed -> where it is
var _pressed: String = ""


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


## Where a named control is, for tests.
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


func _press(name: String) -> void:
	match name:
		"battle":
			app.start_battle()
		"deck":
			app.show_deck()
		"fps":
			app.set_show_fps(not app.profile.show_fps)
		"sound":
			app.set_sound(not app.profile.sound)
		_:
			if name.begins_with("level"):
				app.set_level(int(name.substr(5)))


func _draw() -> void:
	if app == null or app.kit == null:
		return
	var kit: Kit = app.kit
	var screen := size
	_hot.clear()
	draw_rect(Rect2(Vector2.ZERO, screen), Color(0.07, 0.04, 0.02, 0.38))        # the field steps back
	var ox := (screen.x - 540.0) * 0.5
	var block_h := 660.0
	var y := maxf(40.0, (screen.y - block_h) * 0.5)

	# Title.
	var title := Rect2(ox + 40.0, y, 460.0, 112.0)
	kit.tray(self, title)
	kit.outlined(self, Vector2(screen.x * 0.5, y + 62.0), "DRUMS OF WAR", 44, Color("ffd24a"), 440.0, 9)
	kit.text(self, Vector2(screen.x * 0.5, y + 92.0), "Victories %d     Defeats %d     Draws %d" % [app.profile.wins, app.profile.losses, app.profile.draws],
			13, Kit.CREAM, HORIZONTAL_ALIGNMENT_CENTER, 440.0, true)
	y += 136.0

	# The deck: eight small cards, and the way into the deck builder.
	var panel := Rect2(ox + 28.0, y, 484.0, 138.0)
	kit.tray(self, panel)
	kit.text(self, Vector2(panel.position.x + 18.0, y + 27.0), "YOUR DECK", 14, Kit.CREAM, HORIZONTAL_ALIGNMENT_LEFT, 200.0, true)
	var total := 0.0
	for id: String in app.profile.deck:
		total += float(app.cards[id]["cost"])
	kit.text(self, Vector2(panel.end.x - 18.0, y + 27.0), "average cost %.1f" % (total / maxf(1.0, app.profile.deck.size())), 12, Kit.BRASS_LIGHT,
			HORIZONTAL_ALIGNMENT_RIGHT, 200.0, true)
	for i in app.profile.deck.size():
		var id: String = app.profile.deck[i]
		var slot := Rect2(panel.position.x + 17.0 + i * 57.0, y + 40.0, 49.0, 52.0)
		kit.mini_card(self, slot, _art(id), String(app.cards[id]["name"]))
		kit.coin(self, slot.position + Vector2(3, 3), int(app.cards[id]["cost"]), true)
	_hot["deck"] = Rect2(panel.position.x + 142.0, y + 99.0, 200.0, 30.0)
	kit.button(self, _hot["deck"], "CHANGE DECK", "wood", 14)
	y += 160.0

	# The opponent.
	var foe := Rect2(ox + 28.0, y, 484.0, 116.0)
	kit.tray(self, foe)
	kit.text(self, Vector2(foe.position.x + 18.0, y + 27.0), "OPPONENT", 14, Kit.CREAM, HORIZONTAL_ALIGNMENT_LEFT, 200.0, true)
	for i in Bot.LEVELS.size():
		var r := Rect2(foe.position.x + 18.0 + i * 152.0, y + 40.0, 144.0, 40.0)
		_hot["level%d" % i] = r
		kit.button(self, r, String(Bot.LEVELS[i]["name"]).to_upper(), "on" if app.profile.level == i else "wood", 16)
	kit.text(self, Vector2(screen.x * 0.5, y + 101.0), String(Bot.LEVELS[app.profile.level]["about"]), 13, Kit.BRASS_LIGHT,
			HORIZONTAL_ALIGNMENT_CENTER, 460.0, true)
	y += 138.0

	# Into battle.
	_hot["battle"] = Rect2(ox + 90.0, y, 360.0, 72.0)
	kit.button(self, _hot["battle"], "TO BATTLE", "gold", 30)
	y += 100.0

	# Settings.
	_hot["sound"] = Rect2(ox + 60.0, y, 200.0, 38.0)
	kit.button(self, _hot["sound"], "SOUND: " + ("ON" if app.profile.sound else "OFF"), "wood", 14)
	_hot["fps"] = Rect2(ox + 280.0, y, 200.0, 38.0)
	kit.button(self, _hot["fps"], "FPS READOUT: " + ("ON" if app.profile.show_fps else "OFF"), "wood", 14)


func _art(card_id: String) -> Texture2D:
	return app.battle._art(card_id)
