# Main-menu drag scrolling (0.18.3, Kevin: "the main menu can't scroll up and down").
# Simulates a phone: every touch is followed by the mouse event Godot emulates from it (device -1),
# pushed in viewport coordinates.
extends SceneTree
var app
var frames := 0
var fired := 0
var play_btn: Button
var pp := Vector2(210, 640)        # PLAY's centre, found by its action key (0.31.79: the mode row above it is gone)
func _init() -> void:
	app = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(app)
var _last := Vector2.ZERO
func _touch(p: Vector2, down: bool) -> void:
	# What a phone delivers: the touch, then the mouse event Godot emulates from it (device -1).
	var ev := InputEventScreenTouch.new()
	ev.index = 0; ev.position = p; ev.pressed = down
	root.push_input(ev, true)
	var mb := InputEventMouseButton.new()
	mb.device = InputEvent.DEVICE_ID_EMULATION
	mb.button_index = MOUSE_BUTTON_LEFT; mb.pressed = down; mb.position = p; mb.global_position = p
	mb.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	root.push_input(mb, true)
	_last = p
func _move(p: Vector2, rel: Vector2) -> void:
	var m := InputEventScreenDrag.new()
	m.index = 0; m.position = p; m.relative = rel; m.velocity = rel * 60.0
	root.push_input(m, true)
	var mm := InputEventMouseMotion.new()
	mm.device = InputEvent.DEVICE_ID_EMULATION
	mm.position = p; mm.global_position = p; mm.relative = rel; mm.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(mm, true)
	_last = p
func _btn_key(key: String) -> Button:
	for c in root.find_children("*", "Button", true, false):
		if str(c.get_meta("action_key", "")) == key and (c as Control).is_visible_in_tree():
			return c
	return null
func _btn_at(p: Vector2) -> Button:
	var best: Button = null
	for c in root.find_children("*", "Button", true, false):
		if (c as Control).is_visible_in_tree() and (c as Control).get_global_rect().has_point(p):
			best = c
	return best
var results := []
var after_drag := 0
func _process(d: float) -> bool:
	frames += 1
	var sc: ScrollContainer = app.content_scroll
	if frames == 20:
		play_btn = _btn_key("play")
		pp = play_btn.get_global_rect().get_center()
		# Don't really start a match if PLAY fires: count it instead.
		for con in play_btn.pressed.get_connections(): play_btn.pressed.disconnect(con.callable)
		play_btn.pressed.connect(func(): fired += 1)
		_touch(pp, true)

	if frames >= 21 and frames <= 30:
		_move(pp - Vector2(0, 32 * (frames - 20)), Vector2(0, -32))
	if frames == 31:
		_touch(pp - Vector2(0, 320), false)
	if frames == 33:
		results.append(["drag starting on PLAY scrolls the menu (%d px) and doesn't press PLAY (%d)" % [sc.scroll_vertical, fired], sc.scroll_vertical > 150 and fired == 0])
		after_drag = sc.scroll_vertical
	if frames == 60:
		results.append(["a flick keeps gliding after release (%d -> %d)" % [after_drag, sc.scroll_vertical], sc.scroll_vertical > after_drag + 30])
		sc.scroll_vertical = 0
		fired = 0
	if frames == 64:
		_touch(pp, true)
	if frames == 66:
		_touch(pp, false)
	if frames == 70:
		results.append(["a plain tap still presses PLAY (%d)" % fired, fired == 1])
		sc.scroll_vertical = 0
	if frames == 72:
		_touch(Vector2(210, 300), true)
	if frames >= 73 and frames <= 80:
		_move(Vector2(210, 300 - 25 * (frames - 72)), Vector2(0, -25))
	if frames == 81:
		_touch(Vector2(210, 100), false)
	if frames == 83:
		results.append(["drag starting on the hero area scrolls (%d px)" % sc.scroll_vertical, sc.scroll_vertical > 100])
		var ok := true
		for r in results:
			print(("ok   " if r[1] else "FAIL ") + str(r[0]))
			ok = ok and bool(r[1])
		print("APP_SCROLL_PASS" if ok else "APP_SCROLL_FAIL")
		quit(0 if ok else 1)
	return false
